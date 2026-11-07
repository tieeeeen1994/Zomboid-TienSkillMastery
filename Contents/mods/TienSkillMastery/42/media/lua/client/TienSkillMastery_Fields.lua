--[[
Tien's Skill Mastery: Homesteading's signature, tend the field and sow the field (client side; the actions are
vanilla's shared farming actions with their own server `complete`s), 42.21.

World context menu (`OnFillWorldObjectContextMenu`) for a master: "Tend the field" and "Sow the field" (a submenu of
the seed types carried, as vanilla's `ISFarmingMenu:doSeedMenu` lists them: `farming_vegetableconf.props[type]
.seedTypes` or `.seedName`, good seeds only). Either asks for two corners (vanilla's `ISSelectCursor` from the build
cursors, `skipWalk2` so picking does not walk; at most 15 x 15 squares), then queues, for each plant in the area on
that level (`CFarmingSystem.instance:getLuaObjectOnSquare`), a walk next to it and vanilla's action:
- Tend: water a seeded plant below 100 water (`ISWaterPlantAction`, uses as vanilla's `onWater`: the missing tenths,
  at most 10 and what the source holds; water sources are the items `ISFarmingMenu.getWaterUsesInteger` counts,
  equipped in turn), cure mildew / flies / aphids / slugs with the spray for each when carried (`ISCurePlantAction`,
  uses enough to clear it at Farming 10: 20 per use, time 100 per use as vanilla), and fertilize a plant that has had
  none yet (`ISFertilizeAction`; vanilla only benefits from the first dose) while fertilizer is carried.
- Sow: one seed per free plowed square (`ISSeedActionNew`, one seed item each, moved out of bags first).
Walks: vanilla's `walkToPlant` only checks adjacency against where the player stands when queuing, so each plant
gets its own walk to a free adjacent square (plants excluded, as vanilla's finder does).
]]

if isServer() then return end

require "TienSkillMastery"
local M = TienSkillMastery

local MAX_SIDE = 15

local function walkTo(playerObj, square, skipIfAdjacent)
    if playerObj:isTimedActionInstant() then return true end
    if skipIfAdjacent and AdjacentFreeTileFinder.isTileOrAdjacent(playerObj:getCurrentSquare(), square) then
        return true
    end
    local exclude = {}
    for d = 1, 8 do
        local sq2 = square:getAdjacentSquare(IsoDirections.fromIndex(d - 1))
        if sq2 and sq2:hasFarmingPlant() then table.insert(exclude, sq2) end
    end
    local adjacent = AdjacentFreeTileFinder.Find(square, playerObj, exclude)
    if not adjacent then return false end
    ISTimedActionQueue.add(ISWalkToTimedAction:new(playerObj, adjacent))
    return true
end

local function plantsIn(x1, y1, x2, y2, z)
    local list = {}
    for x = math.min(x1, x2), math.max(x1, x2) do
        for y = math.min(y1, y2), math.max(y1, y2) do
            local sq = getCell():getGridSquare(x, y, z)
            local plant = sq and CFarmingSystem.instance:getLuaObjectOnSquare(sq)
            if plant then list[#list + 1] = { plant = plant, square = sq } end
        end
    end
    return list
end

local function isGoodSeed(item)
    if not instanceof(item, "Food") then return true end
    return not (item:isRotten() or item:isCooked() or item:isBurnt())
end

-- ---------------------------------------------------------------------------------------------------------------
-- Tend
-- ---------------------------------------------------------------------------------------------------------------

local CURES = {
    { field = "mildewLvl", item = "GardeningSprayMilk", cure = "Mildew" },
    { field = "fliesLvl", item = "GardeningSprayCigarettes", cure = "Flies" },
    { field = "aphidLvl", item = "GardeningSprayAphids", cure = "Aphids" },
    { field = "slugsLvl", item = "SlugRepellent", cure = "Slugs" },
}
local CURE_PER_USE = 20

local function waterSources(inv)
    local list = {}
    local items = inv:getAllEvalRecurse(function(item) return ISFarmingMenu.getWaterUsesInteger(item) > 0 end)
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        list[#list + 1] = { item = item, uses = ISFarmingMenu.getWaterUsesInteger(item) }
    end
    return list
end

local function tend(playerObj, entries)
    local inv = playerObj:getInventory()
    local sources = waterSources(inv)
    local fertilizer = inv:getFirstTypeRecurse("Fertilizer")
    local fertUses = fertilizer and (fertilizer.getCurrentUses and fertilizer:getCurrentUses() or 1) or 0
    local cureItems = {}
    for _, c in ipairs(CURES) do
        local item = inv:getFirstTypeRecurse(c.item)
        if item and item:getCurrentUses() > 0 then cureItems[c.cure] = { item = item, uses = item:getCurrentUses() } end
    end
    local equipped = playerObj:getPrimaryHandItem()
    local function equip(item)
        if equipped ~= item then
            ISInventoryPaneContextMenu.transferIfNeeded(playerObj, item)
            ISTimedActionQueue.add(ISEquipWeaponAction:new(playerObj, item, 50, true))
            equipped = item
        end
    end
    local first = true
    for _, e in ipairs(entries) do
        local plant, sq = e.plant, e.square
        local jobs = {}
        if plant.state == "seeded" and (tonumber(plant.waterLvl) or 100) < 100 then
            local missing = math.ceil((100 - plant.waterLvl) / 10)
            for _, s in ipairs(sources) do
                if s.uses > 0 then
                    local use = math.min(missing, 10, s.uses)
                    s.uses = s.uses - use
                    jobs[#jobs + 1] = function()
                        equip(s.item)
                        ISTimedActionQueue.add(ISWaterPlantAction:new(playerObj, s.item, use, sq, 20 + 6 * use))
                    end
                    break
                end
            end
        end
        if plant.state ~= "plow" and plant.state ~= "dead" and plant.state ~= "rotten" then
            for _, c in ipairs(CURES) do
                local lvl = tonumber(plant[c.field]) or 0
                local ci = cureItems[c.cure]
                if lvl > 0 and ci and ci.uses > 0 then
                    local uses = math.min(ci.uses, math.max(1, math.ceil(lvl / CURE_PER_USE)))
                    ci.uses = ci.uses - uses
                    jobs[#jobs + 1] = function()
                        equip(ci.item)
                        ISTimedActionQueue.add(ISCurePlantAction:new(playerObj, ci.item, uses, plant, 100 * uses, c.cure))
                    end
                end
            end
            if fertilizer and fertUses > 0 and (tonumber(plant.fertilizer) or 0) == 0 and plant.state ~= "harvested" then
                fertUses = fertUses - 1
                jobs[#jobs + 1] = function()
                    equip(fertilizer)
                    ISTimedActionQueue.add(ISFertilizeAction:new(playerObj, fertilizer, plant, 100))
                end
            end
        end
        if #jobs > 0 and walkTo(playerObj, sq, first) then
            first = false
            for _, job in ipairs(jobs) do job() end
        end
    end
end

-- ---------------------------------------------------------------------------------------------------------------
-- Sow
-- ---------------------------------------------------------------------------------------------------------------

local function sow(playerObj, entries, typeOfSeed, seedName)
    local seeds = playerObj:getInventory():getAllTypeRecurse(seedName)
    local list = {}
    for i = 0, seeds:size() - 1 do
        if isGoodSeed(seeds:get(i)) then list[#list + 1] = seeds:get(i) end
    end
    local n, first = 1, true
    for _, e in ipairs(entries) do
        if n > #list then break end
        if e.plant.state == "plow" and walkTo(playerObj, e.square, first) then
            first = false
            local seed = list[n]
            n = n + 1
            ISInventoryPaneContextMenu.transferIfNeeded(playerObj, seed)
            ISTimedActionQueue.add(ISSeedActionNew:new(playerObj, seed, typeOfSeed, e.plant))
        end
    end
end

-- ---------------------------------------------------------------------------------------------------------------
-- Area picker and menu
-- ---------------------------------------------------------------------------------------------------------------

local function pickArea(playerObj, onArea)
    local ui = { corner = nil }
    local function newCursor()
        local cursor = ISSelectCursor:new(playerObj, ui, nil)
        cursor.skipWalk2 = true
        ui.cursor = cursor
        getCell():setDrag(cursor, playerObj:getPlayerNum())
    end
    function ui:onSquareSelected(square)
        if not square then return end
        if not self.corner then
            self.corner = square
            newCursor()
            return
        end
        self.cursor = nil
        local a, b = self.corner, square
        local x2 = math.max(a:getX() - MAX_SIDE + 1, math.min(a:getX() + MAX_SIDE - 1, b:getX()))
        local y2 = math.max(a:getY() - MAX_SIDE + 1, math.min(a:getY() + MAX_SIDE - 1, b:getY()))
        onArea(plantsIn(a:getX(), a:getY(), x2, y2, a:getZ()))
    end
    newCursor()
end

local function seedChoices(playerObj)
    local out = {}
    for typeOfSeed, props in pairs(farming_vegetableconf.props) do
        for _, seedName in ipairs(props.seedTypes or { props.seedName }) do
            if seedName and playerObj:getInventory():getCountTypeEvalRecurse(seedName, isGoodSeed) > 0 then
                local script = getScriptManager():getItem(seedName)
                out[#out + 1] = { typeOfSeed = typeOfSeed, seedName = seedName,
                    text = script and script:getDisplayName() or seedName }
            end
        end
    end
    table.sort(out, function(a, b) return a.text < b.text end)
    return out
end

Events.OnFillWorldObjectContextMenu.Add(function(playerNum, context, worldobjects, test)
    if test then return end
    local playerObj = getSpecificPlayer(playerNum)
    if not playerObj or playerObj:getVehicle() or not M.sig(playerObj, "Homesteading.SigFields") then return end
    context:addOption(getText("IGUI_TienSkillMastery_TendField"), playerObj, function(p)
        pickArea(p, function(entries) tend(p, entries) end)
    end)
    local seeds = seedChoices(playerObj)
    if #seeds > 0 then
        local option = context:addOption(getText("IGUI_TienSkillMastery_SowField"), nil, nil)
        local sub = ISContextMenu:getNew(context)
        context:addSubMenu(option, sub)
        for _, s in ipairs(seeds) do
            sub:addOption(s.text, playerObj, function(p)
                pickArea(p, function(entries) sow(p, entries, s.typeOfSeed, s.seedName) end)
            end)
        end
    end
end)
