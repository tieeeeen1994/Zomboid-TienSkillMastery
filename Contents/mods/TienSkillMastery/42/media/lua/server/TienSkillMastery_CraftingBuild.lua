--[[
Tien's Skill Mastery: `Woodwork.StructureHP`, health of built structures (42.21, media/lua/server/BuildingObjects).

Deviation from the design note: in 42.21 the build menu builds everything through ISBuildIsoEntity, and
`ISBuildIsoEntity:setInfo` (~595) does not call `buildUtil.getWoodHealth` (`ISBuildIsoEntity:getHealth` ~38 does, but
nothing calls it). setInfo (~655-668) computes the health itself:
  totalHealth = max(script health, 0) + bonusHealth (x 0.5 / 0.7 / 1 / 1.3 / 1.5 by sandbox ConstructionBonusPoints)
              + craftRecipe:getHighestRelevantSkillLevel(player) x script SkillBaseHealth
  thumpable:setMaxHealth(totalHealth); thumpable:setHealth(thumpable:getMaxHealth())
and only later adds the thumpable to the square and sends it (`AddSpecialObject`, `transmitCompleteItemToClients`), so a
health set inside setInfo travels with the object. `ISBuildIsoEntity:create` (~501), which calls setInfo per tile,
runs on the MP server (Java BuildAction) or in single player.
Hook: while a setInfo of a recipe that involves Woodwork runs, the first `setMaxHealth` called on an IsoThumpable
from Lua (line ~667, the new thumpable; the Java constructor and other Java code never go through Lua) is multiplied by
`M.more(player, "Woodwork.StructureHP")`, so the setHealth right after fills the raised maximum. The method is
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
        if not chr or not recipe or not recipe:involvesSkill(Perks.Woodwork) then return nil end
        local f = M.more(chr, "Woodwork.StructureHP")
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
    print("[TienSkillMastery] ISBuildIsoEntity:setInfo or IsoThumpable:setMaxHealth not reachable, Woodwork.StructureHP not applied to build entities")
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
                health = math.floor(health * M.more(chr, "Woodwork.StructureHP") + 0.5)
            end
        end
        return health
    end
else
    print("[TienSkillMastery] buildUtil.getWoodHealth not found, Woodwork.StructureHP not applied to older building objects")
end
