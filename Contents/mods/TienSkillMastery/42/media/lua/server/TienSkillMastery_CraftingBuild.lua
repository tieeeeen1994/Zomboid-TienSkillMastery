--[[
Tien's Skill Mastery: `Construction.StructureHP`, health of built structures (42.21, media/lua/server/BuildingObjects).

Deviation from the design note: in 42.21 the build menu builds everything through ISBuildIsoEntity, and
`ISBuildIsoEntity:setInfo` (~595) does not call `buildUtil.getWoodHealth` (`ISBuildIsoEntity:getHealth` ~38 does, but
nothing calls it). setInfo (~655-668) computes the health itself:
  totalHealth = max(script health, 0) + bonusHealth (x 0.5 / 0.7 / 1 / 1.3 / 1.5 by sandbox ConstructionBonusPoints)
              + craftRecipe:getHighestRelevantSkillLevel(player) x script SkillBaseHealth
  thumpable:setMaxHealth(totalHealth); thumpable:setHealth(thumpable:getMaxHealth())
and only later adds the thumpable to the square and sends it (`AddSpecialObject`, `transmitCompleteItemToClients`), so a
health set inside setInfo travels with the object. `ISBuildIsoEntity:create` (~501), which calls setInfo per tile,
runs on the MP server (Java BuildAction) or in single player.
Hook: while a setInfo of a recipe that involves Woodwork or Masonry (v2: Construction covers both) runs, the first `setMaxHealth` called on an IsoThumpable
from Lua (line ~667, the new thumpable; the Java constructor and other Java code never go through Lua) is multiplied by
`M.more(player, "Construction.StructureHP")`, so the setHealth right after fills the raised maximum. The method is
replaced in IsoThumpable's class table (`__classmetatables[IsoThumpable.class].__index`, which shadows the inherited
IsoObject method for thumpables only) and does nothing outside that window. The player is found as setInfo does:
`self.character` on a server, `getSpecificPlayer(self.player)` otherwise.

The older building objects (ISWoodenWall, ISSimpleFurniture, ISWoodenDoor, ISEmptyGraves...; graves are the only
ones a 42.21 menu still builds, client/ISUI/ISWorldObjectContextMenu.lua ~2761) take
`buildUtil.getWoodHealth` (ISBuildUtil.lua ~39: 50 x Woodwork + 100 Handy) on top of a fixed base; that skill part is
multiplied by the same factor.

Server folder: loaded on the MP server and in single player after vanilla's server files (so ISBuildIsoEntity and
buildUtil exist at file load); MP clients load it too and leave here (builds are made on the server).
]]

if isClient() then return end

require "TienSkillMastery"
require "BuildingObjects/ISBuildUtil"
require "BuildingObjects/ISBuildIsoEntity"
local M = TienSkillMastery

local function builderOf(obj)
    if not obj then return nil end
    if isServer() then return obj.character end
    if type(obj.player) == "number" then return getSpecificPlayer(obj.player) end
    return obj.character or obj.player
end

-- ---------------------------------------------------------------------------------------------------------------
-- Build entities
-- ---------------------------------------------------------------------------------------------------------------

local pending = nil   -- health factor for the next Lua setMaxHealth on a thumpable, during ISBuildIsoEntity:setInfo

local classTable = __classmetatables and IsoThumpable and __classmetatables[IsoThumpable.class]
local index = classTable and classTable.__index
local vanillaSetMaxHealth = index and index.setMaxHealth

if ISBuildIsoEntity and ISBuildIsoEntity.setInfo and vanillaSetMaxHealth then
    index.setMaxHealth = function(thumpable, health, ...)
        if pending and type(health) == "number" then
            local factor = pending
            pending = nil
            health = math.floor(health * factor + 0.5)
        end
        return vanillaSetMaxHealth(thumpable, health, ...)
    end

    local function factorFor(self)
        local chr = builderOf(self)
        local recipe = self.objectInfo and self.objectInfo:getRecipe() and self.objectInfo:getRecipe():getCraftRecipe()
        if not chr or not recipe then return nil end
        if not recipe:involvesSkill(Perks.Woodwork) and not recipe:involvesSkill(Perks.Masonry) then return nil end
        local f = M.more(chr, "Construction.StructureHP")
        if f > 1 then return f end
        return nil
    end

    local function finish(ok, ...)
        pending = nil
        if not ok then error((...), 0) end
        return ...
    end

    local vanillaSetInfo = ISBuildIsoEntity.setInfo
    function ISBuildIsoEntity:setInfo(...)
        local ok, f = pcall(factorFor, self)
        pending = ok and f or nil
        return finish(pcall(vanillaSetInfo, self, ...))
    end
else
    print("[TienSkillMastery] ISBuildIsoEntity:setInfo or IsoThumpable:setMaxHealth not reachable, Construction.StructureHP not applied to build entities")
end

-- ---------------------------------------------------------------------------------------------------------------
-- Older building objects
-- ---------------------------------------------------------------------------------------------------------------

if buildUtil and buildUtil.getWoodHealth then
    local vanillaGetWoodHealth = buildUtil.getWoodHealth
    buildUtil.getWoodHealth = function(item, ...)
        local health = vanillaGetWoodHealth(item, ...)
        if type(health) == "number" and item and item.player then
            local chr = isServer() and item.player or getSpecificPlayer(item.player)
            if chr and type(chr) ~= "number" then
                health = math.floor(health * M.more(chr, "Construction.StructureHP") + 0.5)
            end
        end
        return health
    end
else
    print("[TienSkillMastery] buildUtil.getWoodHealth not found, Construction.StructureHP not applied to older building objects")
end

-- ---------------------------------------------------------------------------------------------------------------
-- Construction.SpareMaterials (phase 3c, "pts", approved at 15%): each material a build consumes comes back on its
-- own roll, dropped on the builder's square (`AddWorldInventoryItem`, which the server sends).
-- Where (42.21): `ISBuildIsoEntity:create` (~501, server / single player) consumes through
-- `buildPanelLogic:performCurrentRecipe()` and then calls `self:updateModData()` (ISBuildingObject ~354), which
-- records one `need:<full type>` per consumed item in the build's modData; those counts become the built object's
-- build materials, which dismantling pays back from (`ISDismantleAction:complete` ~55: 1..n of each). So the spared
-- items are taken off those counts as they drop: the structure only remembers what was really paid, and a build /
-- dismantle loop cannot gain from the saving. Moveable scrapping pays by the tile's material, whatever the build
-- cost, so the saving does not feed it either.
-- ---------------------------------------------------------------------------------------------------------------

if ISBuildingObject and ISBuildingObject.updateModData then
    local vanillaUpdate = ISBuildingObject.updateModData
    function ISBuildingObject:updateModData(...)
        local before = {}
        if self.modData then
            for k, v in pairs(self.modData) do
                if type(k) == "string" and k:sub(1, 5) == "need:" then before[k] = tonumber(v) or 0 end
            end
        end
        local r = { vanillaUpdate(self, ...) }
        local ok, err = pcall(function()
            local chr = builderOf(self)
            if not chr or type(chr) == "number" or M.val(chr, "Construction.SpareMaterials") <= 0 or not self.modData then
                return
            end
            local square = chr:getCurrentSquare()
            if not square then return end
            for k, v in pairs(self.modData) do
                if type(k) == "string" and k:sub(1, 5) == "need:" then
                    local added = (tonumber(v) or 0) - (before[k] or 0)
                    local spared = 0
                    for _ = 1, added do
                        if M.roll(chr, "Construction.SpareMaterials") then spared = spared + 1 end
                    end
                    if spared > 0 then
                        local fullType = k:sub(6)
                        for _ = 1, spared do
                            square:AddWorldInventoryItem(fullType, ZombRandFloat(0.2, 0.8), ZombRandFloat(0.2, 0.8), 0)
                        end
                        self.modData[k] = (tonumber(v) or 0) - spared
                    end
                end
            end
        end)
        if not ok then print("[TienSkillMastery] spare materials failed: " .. tostring(err)) end
        return unpack(r)
    end
end

-- ---------------------------------------------------------------------------------------------------------------
-- Smithing.TorchFuel on builds (user, 2026-11-09; handcrafts: TienSkillMastery_Crafting.lua): 40 vanilla build entities
-- burn blowtorch uses (`item 1 .. 4 [Base.BlowTorch] flags[DontRecordInput]`: metal counters, crates, lockers, shelves,
-- metal barricades, the barrel oven). Java `BuildAction.perform` only fires `OnProcessAction("build")`, and Lua's
-- `ISBuildIsoEntity:create` (~501, server / single player) does the consuming through
-- `buildPanelLogic:performCurrentRecipe()`, so the torches are noted before it and each use gone after comes back on its
-- own roll. A Build Cheat consumes nothing. DontRecordInput keeps the torch out of `getAllRecordedConsumedItems`, so
-- it never reaches the `need:` counts Spare Materials rolls on: one use is never rolled twice.
-- ---------------------------------------------------------------------------------------------------------------

if ISBuildIsoEntity and ISBuildIsoEntity.create then
    local function noteBuild(self)
        local chr = self.character
        if not chr or type(chr) == "number" or not M.noteTorches or M.val(chr, "Smithing.TorchFuel") <= 0 then
            return nil, nil
        end
        local logic = self.buildPanelLogic
        return chr, M.noteTorches(chr, (logic and logic:getContainers()) or self.containers)
    end

    local function afterBuild(chr, torches, ok, ...)
        if torches then
            local fine, err = pcall(M.returnTorchFuel, chr, torches)
            if not fine then print("[TienSkillMastery] build torch fuel failed: " .. tostring(err)) end
        end
        if not ok then error((...), 0) end
        return ...
    end

    local vanillaCreate = ISBuildIsoEntity.create
    function ISBuildIsoEntity:create(...)
        local fine, chr, torches = pcall(noteBuild, self)
        if not fine then
            print("[TienSkillMastery] build torch fuel failed: " .. tostring(chr))
            chr, torches = nil, nil
        end
        return afterBuild(chr, torches, pcall(vanillaCreate, self, ...))
    end
else
    print("[TienSkillMastery] ISBuildIsoEntity:create not found, Smithing.TorchFuel not applied to builds")
end
