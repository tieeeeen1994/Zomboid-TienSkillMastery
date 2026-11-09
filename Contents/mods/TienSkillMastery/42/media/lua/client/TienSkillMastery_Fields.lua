--[[
Tien's Skill Mastery: Homesteading's signature, tend the field and sow the field (client side; the action and what
runs on the server are in shared/TienSkillMastery_FieldAction.lua), 42.21.

World context menu (`OnFillWorldObjectContextMenu`) for a master, in a "Homesteading" submenu (user, 2026-11-09). With a
digging tool (`ISFarmingMenu.getShovel`), "Dig furrows" (server/TienSkillMastery_FurrowCursor.lua), also on bare ground
vanilla would dig. On a clicked crop or furrow, also "Remove plots" (with the tool: dead, rotten or destroyed, each over a
picked area as below, one action per block, time 40), "Tend the field" and "Sow the field" (a submenu of the seed types carried, as vanilla's `ISFarmingMenu:doSeedMenu` lists them: `farming_vegetableconf.props[type]
.seedTypes` or `.seedName`, good seeds only). Either asks for two corners (vanilla's `ISSelectCursor` from the build
cursors, `skipWalk2` so picking does not walk; at most 15 x 15 squares; the first corner stays tinted yellow during the
second pick, user, 2026-11-09, with the cursor's own `RenderGhostTileColor`). The area on that level is cut into 3 x 3
blocks from its corner, walked in a snake, and each block gets a walk, then one action per kind of work (user,
2026-11-09: one timed action works the whole block), for the plants there that need it
(`CFarmingSystem.instance:getLuaObjectOnSquare`), as long as the slowest single plant takes with vanilla's action:
- Tend: water seeded plants below 100 water (20 + 6 x uses as vanilla's `onWater`: the missing tenths, at most 10 and
  what the source holds; water sources are the items `ISFarmingMenu.getWaterUsesInteger` counts, equipped in turn, one
  action per source used), cure mildew / flies / aphids / slugs with the spray for each when carried (enough to clear
  it at Farming 10: 20 per use, time 100 per use as vanilla), fertilize plants that have had none yet (vanilla only
  benefits from the first dose; time 100) while fertilizer is carried, and remove harvested plots with a shovel (user,
  2026-11-09; vanilla's Remove, `ISFarmingMenu.getShovel`, time 40; without one they stay).
- Sow: one seed per free plowed square (time 40; one seed item each, moved out of bags first).
Walks: the character goes to the middle of each block, crop or not (user, 2026-11-09), unless the last stop is already
within a square of the block, so every plant it works is next to it. Stepping on crops is harmless in 42.21: the only
Java callers of `IsoGridSquare.destroyFarmingPlant` are `IsoZombie` (a roll per update on the square) and
`checkForIntersectingCrops` (vehicles), and the Lua `destroyThis` callers are decay and commands. Vanilla's finder
leaves plant squares out, a choice of its own. But `PathFindRequest` sets `avoidFarmingPlants` for players, read only by
PZPathFind64.dll, and how it treats that has not been traced: a path it refuses makes `ISWalkToTimedAction` `forceStop`,
which resets the queue.
]]

if isServer() then return end

require "TienSkillMastery"
require "TienSkillMastery_FieldAction"
local M = TienSkillMastery

local MAX_SIDE = 15

--- The plants of an area, in M.FIELD_BLOCK-sided blocks walked in a snake:
--- { { x1, y1, x2, y2, z, entries = { { plant, x, y }, ... } }, ... }, leaving out blocks with no plant.
local function blocksIn(x1, y1, x2, y2, z)
    local minX, maxX = math.min(x1, x2), math.max(x1, x2)
    local minY, maxY = math.min(y1, y2), math.max(y1, y2)
    local size = M.FIELD_BLOCK
    local blocks, column = {}, {}
    local forward = true
    for bx = minX, maxX, size do
        column = {}
        for by = minY, maxY, size do
            local block = { x1 = bx, y1 = by, x2 = math.min(bx + size - 1, maxX), y2 = math.min(by + size - 1, maxY),
                z = z, entries = {} }
            for x = block.x1, block.x2 do
                for y = block.y1, block.y2 do
                    local sq = getCell():getGridSquare(x, y, z)
                    local plant = sq and CFarmingSystem.instance:getLuaObjectOnSquare(sq)
                    if plant then table.insert(block.entries, { plant = plant, x = x, y = y }) end
                end
            end
            if #block.entries > 0 then table.insert(column, block) end
        end
        for i = 1, #column do
            table.insert(blocks, forward and column[i] or column[#column + 1 - i])
        end
        forward = not forward
    end
    return blocks
end

--- Queue the walk to a block unless the last stop reaches it. False when there is nowhere to stand at all.
--- Timed Action Instant walks too: the server only works squares within FIELD_REACH of the character.
local function walkToBlock(playerObj, block, at)
    if at.x >= block.x1 - 1 and at.x <= block.x2 + 1 and at.y >= block.y1 - 1 and at.y <= block.y2 + 1 then
        return true
    end
    local square = M.fieldStandSquare(block.x1, block.y1, block.x2, block.y2, block.z)
    if not square then return false end
    ISTimedActionQueue.add(ISWalkToTimedAction:new(playerObj, square))
    at.x, at.y = square:getX(), square:getY()
    return true
end

local function startPoint(playerObj)
    local square = playerObj:getCurrentSquare()
    return { x = square:getX(), y = square:getY() }
end

local function queueField(playerObj, item, kind, what, block, targets, maxTime)
    ISTimedActionQueue.add(TienSkillMasteryFieldAction:new(playerObj, item, kind, what, block.z,
        M.fieldEncode(targets), maxTime))
end

--- A function that queues putting an item in the primary hand, when the queue would not have it there yet.
local function newEquipper(playerObj)
    local equipped = playerObj:getPrimaryHandItem()
    return function(item)
        if equipped ~= item then
            ISInventoryPaneContextMenu.transferIfNeeded(playerObj, item)
            ISTimedActionQueue.add(ISEquipWeaponAction:new(playerObj, item, 50, true))
            equipped = item
        end
    end
end

-- ---------------------------------------------------------------------------------------------------------------
-- Tend
-- ---------------------------------------------------------------------------------------------------------------

local CURES = {
    { item = "GardeningSprayMilk", cure = "Mildew" },
    { item = "GardeningSprayCigarettes", cure = "Flies" },
    { item = "GardeningSprayAphids", cure = "Aphids" },
    { item = "SlugRepellent", cure = "Slugs" },
}

local function waterSources(inv)
    local list = {}
    local items = inv:getAllEvalRecurse(function(item) return ISFarmingMenu.getWaterUsesInteger(item) > 0 end)
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        list[#list + 1] = { item = item, uses = ISFarmingMenu.getWaterUsesInteger(item) }
    end
    return list
end

local function tend(playerObj, blocks)
    local inv = playerObj:getInventory()
    local sources = waterSources(inv)
    local fertilizer = inv:getFirstTypeRecurse("Fertilizer")
    local fertUses = M.fieldItemUses(fertilizer)
    local shovel = ISFarmingMenu.getShovel(playerObj)
    local cureItems = {}
    for _, c in ipairs(CURES) do
        local item = inv:getFirstTypeRecurse(c.item)
        if item and item:getCurrentUses() > 0 then cureItems[c.cure] = { item = item, uses = item:getCurrentUses() } end
    end
    local equip = newEquipper(playerObj)
    local at = startPoint(playerObj)
    for _, block in ipairs(blocks) do
        local jobs = {}
        -- One group per item used: { item, kind, what, targets, maxUses }, in the order of the work.
        local function add(item, kind, what, entry, uses)
            local group
            for _, job in ipairs(jobs) do
                if job.item == item and job.what == what then group = job end
            end
            if not group then
                group = { item = item, kind = kind, what = what, targets = {}, maxUses = 0 }
                table.insert(jobs, group)
            end
            table.insert(group.targets, entry)
            group.maxUses = math.max(group.maxUses, uses)
        end
        for _, entry in ipairs(block.entries) do
            local need = M.fieldWaterNeed(entry.plant)
            if need > 0 then
                for _, s in ipairs(sources) do
                    if s.uses > 0 then
                        local use = math.min(need, s.uses)
                        s.uses = s.uses - use
                        add(s.item, "water", "", entry, use)
                        break
                    end
                end
            end
        end
        for _, c in ipairs(CURES) do
            local ci = cureItems[c.cure]
            if ci then
                for _, entry in ipairs(block.entries) do
                    local need = M.fieldCureNeed(entry.plant, c.cure)
                    if need > 0 and ci.uses > 0 then
                        local use = math.min(need, ci.uses)
                        ci.uses = ci.uses - use
                        add(ci.item, "cure", c.cure, entry, use)
                    end
                end
            end
        end
        if fertilizer then
            for _, entry in ipairs(block.entries) do
                if fertUses > 0 and M.fieldWantsFertilizer(entry.plant) then
                    fertUses = fertUses - 1
                    add(fertilizer, "fertilize", "", entry, 1)
                end
            end
        end
        if shovel then
            for _, entry in ipairs(block.entries) do
                if entry.plant.state == "harvested" then add(shovel, "clear", "harvested", entry, 1) end
            end
        end
        if #jobs > 0 and walkToBlock(playerObj, block, at) then
            for _, job in ipairs(jobs) do
                equip(job.item)
                local time = 100
                if job.kind == "water" then time = 20 + 6 * job.maxUses end
                if job.kind == "cure" then time = 100 * job.maxUses end
                if job.kind == "clear" then time = 40 end
                queueField(playerObj, job.item, job.kind, job.what, block, job.targets, time)
            end
        end
    end
end

-- ---------------------------------------------------------------------------------------------------------------
-- Remove plots
-- ---------------------------------------------------------------------------------------------------------------

local function removePlots(playerObj, blocks, state)
    local shovel = ISFarmingMenu.getShovel(playerObj)
    if not shovel then return end
    local equip = newEquipper(playerObj)
    local at = startPoint(playerObj)
    for _, block in ipairs(blocks) do
        local targets = {}
        for _, entry in ipairs(block.entries) do
            if entry.plant.state == state then table.insert(targets, entry) end
        end
        if #targets > 0 and walkToBlock(playerObj, block, at) then
            equip(shovel)
            queueField(playerObj, shovel, "clear", state, block, targets, 40)
        end
    end
end

-- ---------------------------------------------------------------------------------------------------------------
-- Sow
-- ---------------------------------------------------------------------------------------------------------------

local function sow(playerObj, blocks, typeOfSeed, seedName)
    local seeds = playerObj:getInventory():getAllTypeRecurse(seedName)
    local list = {}
    for i = 0, seeds:size() - 1 do
        if M.fieldGoodSeed(seeds:get(i)) then list[#list + 1] = seeds:get(i) end
    end
    local n = 1
    local at = startPoint(playerObj)
    for _, block in ipairs(blocks) do
        local targets = {}
        for _, entry in ipairs(block.entries) do
            if entry.plant.state == "plow" and n + #targets <= #list then table.insert(targets, entry) end
        end
        if #targets > 0 and walkToBlock(playerObj, block, at) then
            local first = list[n]
            for i = n, n + #targets - 1 do
                ISInventoryPaneContextMenu.transferIfNeeded(playerObj, list[i])
            end
            n = n + #targets
            queueField(playerObj, first, "sow", typeOfSeed, block, targets, 40)
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
        if ui.corner then
            -- Drawn per frame by the cursor itself, so it goes with the cursor (second pick, Esc, a context menu).
            local cx, cy, cz = ui.corner:getX(), ui.corner:getY(), ui.corner:getZ()
            function cursor:render(x, y, z, square)
                ISSelectCursor.render(self, x, y, z, square)
                self:getFloorCursorSprite():RenderGhostTileColor(cx, cy, cz, 1, 1, 0, 0.8)
            end
        end
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
        onArea(blocksIn(a:getX(), a:getY(), x2, y2, a:getZ()))
    end
    newCursor()
end

local function seedChoices(playerObj)
    local out = {}
    for typeOfSeed, props in pairs(farming_vegetableconf.props) do
        for _, seedName in ipairs(props.seedTypes or { props.seedName }) do
            if seedName and playerObj:getInventory():getCountTypeEvalRecurse(seedName, M.fieldGoodSeed) > 0 then
                local script = getScriptManager():getItem(seedName)
                out[#out + 1] = { typeOfSeed = typeOfSeed, seedName = seedName,
                    text = script and script:getDisplayName() or seedName }
            end
        end
    end
    table.sort(out, function(a, b) return a.text < b.text end)
    return out
end

--- True when the click landed on a farming plot: a crop of any state or a plowed furrow, which is what sowing is for.
local function clickedFarmland(worldobjects)
    for _, object in ipairs(worldobjects) do
        local square = object:getSquare()
        if square and CFarmingSystem.instance:getLuaObjectOnSquare(square) then return true end
    end
    return false
end

Events.OnFillWorldObjectContextMenu.Add(function(playerNum, context, worldobjects, test)
    if test then return end
    local playerObj = getSpecificPlayer(playerNum)
    if not playerObj or playerObj:getVehicle() or not M.sig(playerObj, "Homesteading.SigFields") then return end
    local farmland = clickedFarmland(worldobjects)
    local tool = ISFarmingMenu.getShovel(playerObj)
    -- Bare ground only matters for digging, and a field has to start somewhere.
    if not farmland and not (tool and ISFarmingMenu.canDigHere(worldobjects)) then return end
    local parent = context:addOption(getText("IGUI_TienSkillMastery_Mastery_Homesteading"), nil, nil)
    local menu = ISContextMenu:getNew(context)
    context:addSubMenu(parent, menu)
    if farmland then
        menu:addOption(getText("IGUI_TienSkillMastery_TendField"), playerObj, function(p)
            pickArea(p, function(blocks) tend(p, blocks) end)
        end)
        local seeds = seedChoices(playerObj)
        if #seeds > 0 then
            local option = menu:addOption(getText("IGUI_TienSkillMastery_SowField"), nil, nil)
            local sub = ISContextMenu:getNew(menu)
            menu:addSubMenu(option, sub)
            for _, s in ipairs(seeds) do
                sub:addOption(s.text, playerObj, function(p)
                    pickArea(p, function(blocks) sow(p, blocks, s.typeOfSeed, s.seedName) end)
                end)
            end
        end
        if tool then
            local option = menu:addOption(getText("IGUI_TienSkillMastery_RemovePlots"), nil, nil)
            local sub = ISContextMenu:getNew(menu)
            menu:addSubMenu(option, sub)
            for _, state in ipairs({ "dead", "rotten", "destroyed" }) do
                sub:addOption(getText("IGUI_TienSkillMastery_RemovePlots_" .. state), playerObj, function(p)
                    pickArea(p, function(blocks) removePlots(p, blocks, state) end)
                end)
            end
        end
    end
    if tool then
        menu:addOption(getText("IGUI_TienSkillMastery_DigFurrows"), playerObj, function(p)
            getCell():setDrag(TienSkillMasteryFurrowCursor:new(p), p:getPlayerNum())
        end)
    end
end)
