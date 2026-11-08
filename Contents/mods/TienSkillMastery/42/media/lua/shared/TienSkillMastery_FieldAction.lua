--[[
Tien's Skill Mastery: Homesteading's signature, the one timed action that works a 3 x 3 block of a field (user,
2026-11-09), 42.21. client/TienSkillMastery_Fields.lua plans and queues it.

One action = one kind of work (water, one cure, fertilizer, clearing finished plots, digging furrows, sowing) on a block, as long as the slowest
single plant would take with vanilla's own action. Water, spray, fertilizer and seeds are still paid per plant, and
the back strain of sowing is still per seed: only the time and the walking are saved.

Dedicated server: a shared class with a `complete`, so `ISTimedActionQueue.add` makes it a server action
(`LuaTimedActionNew`), the table rebuilt from `new`'s parameter names. The client only says which squares; the server
decides from its own plants what each one needs and refuses without the signature (`complete` false = Reject). Squares
travel as a string ("x,y;x,y"), a plain value whatever the network code does with nested tables. `item` is never nil
on the client: for sowing it is the first seed, and the server takes its seeds of that type from the main inventory,
where the client moved them first (vanilla's `ISSeedActionNew:complete` removes from there only). Nothing happens until
`complete`, so a cancelled action costs nothing and does nothing (vanilla's water pours as the bar fills; that also is
what doubled watering in MP, see ZomboidFixesB42's *_WaterPlant.lua).

Each plant goes through vanilla's `complete` of that work, called on a small table with vanilla's class as metatable,
so what wraps those stays in force: Homesteading's cure, health, seasons, fertilizer and back strain passives
(server/TienSkillMastery_Farming.lua's `wrapComplete`), and Zomboid Fixes' water cut. Single player runs `complete` too
(Java's `LuaTimedActionNew.complete` when not a client).

Reach: the client stands in the middle of the block, or within a square of it when it is already there, so a plant is at
most 3 squares away. The server allows FIELD_REACH along each axis for the lag of its copy of the player, and
FIELD_MAX_TARGETS squares.
]]

require "TimedActions/ISBaseTimedAction"
require "Farming/TimedActions/ISWaterPlantAction"
require "Farming/TimedActions/ISCurePlantAction"
require "Farming/TimedActions/ISFertilizeAction"
require "Farming/TimedActions/ISSeedActionNew"
require "Farming/TimedActions/ISShovelAction"
require "Farming/TimedActions/ISPlowAction"
require "TienSkillMastery"
local M = TienSkillMastery

TienSkillMasteryFieldAction = ISBaseTimedAction:derive("TienSkillMasteryFieldAction")
local A = TienSkillMasteryFieldAction

M.FIELD_BLOCK = 3
M.FIELD_REACH = 5
M.FIELD_MAX_TARGETS = M.FIELD_BLOCK * M.FIELD_BLOCK
M.FIELD_CURE_PER_USE = 20    -- vanilla removes 10 + Farming per use; a master has Farming 10
M.FIELD_CURE_FIELD = { Mildew = "mildewLvl", Flies = "fliesLvl", Aphids = "aphidLvl", Slugs = "slugsLvl" }
M.FIELD_CLEARABLE = { harvested = true, dead = true, rotten = true, destroyed = true }   -- never a living plant or a furrow

--- The square nearest the middle of an area that can be stood on, crop or not.
function M.fieldStandSquare(x1, y1, x2, y2, z)
    local mx, my = (x1 + x2) / 2, (y1 + y2) / 2
    local best, bestDist = nil, nil
    for x = x1, x2 do
        for y = y1, y2 do
            local sq = getCell():getGridSquare(x, y, z)
            if sq and sq:canStand() then
                local dist = math.abs(x - mx) + math.abs(y - my)
                if not best or dist < bestDist then best, bestDist = sq, dist end
            end
        end
    end
    return best
end

--- Water uses an item holds. `ISFarmingMenu.getWaterUsesInteger` is client only, and `complete` runs on the server.
function M.fieldWaterUses(item)
    if not item then return 0 end
    if item:hasComponent(ComponentType.FluidContainer) then
        local container = item:getFluidContainer()
        local fluid = container and container:getPrimaryFluid()
        if not fluid then return 0 end
        local name = fluid:getFluidTypeString()
        if name ~= "Water" and name ~= "TaintedWater" then return 0 end
        return math.floor(container:getAmount() * 1000 / ZomboidGlobals.farmingFluidContainerMillilitresPerUse)
    end
    if item:IsDrainable() and item:isWaterSource() then return item:getCurrentUses() end
    return 0
end

--- Whole uses of a cure or fertilizer item.
function M.fieldItemUses(item)
    if not item then return 0 end
    if item.getCurrentUses then return item:getCurrentUses() end
    return 1
end

--- A seed vanilla's seed menu would offer.
function M.fieldGoodSeed(item)
    if not instanceof(item, "Food") then return true end
    return not (item:isRotten() or item:isCooked() or item:isBurnt())
end

--- Uses of water this plant takes, 0 if it needs none.
function M.fieldWaterNeed(plant)
    if plant.state ~= "seeded" then return 0 end
    local missing = 100 - (tonumber(plant.waterLvl) or 100)
    if missing <= 0 then return 0 end
    return math.min(10, math.ceil(missing / 10))
end

--- Uses of this cure the plant takes, 0 if it needs none.
function M.fieldCureNeed(plant, cure)
    local state = plant.state
    if state == "plow" or state == "dead" or state == "rotten" or state == "harvested" or state == "destroyed" then
        return 0
    end
    local lvl = tonumber(plant[M.FIELD_CURE_FIELD[cure]]) or 0
    if lvl <= 0 then return 0 end
    return math.max(1, math.ceil(lvl / M.FIELD_CURE_PER_USE))
end

--- True when a first dose of fertilizer would help this plant (vanilla only benefits from the first).
function M.fieldWantsFertilizer(plant)
    local state = plant.state
    if state == "plow" or state == "dead" or state == "rotten" or state == "harvested" or state == "destroyed" then
        return false
    end
    return (tonumber(plant.fertilizer) or 0) == 0
end

--- { { x = x, y = y }, ... } -> "x,y;x,y". `%d`: a coordinate must not reach the string as "1234.0".
function M.fieldEncode(list)
    local parts = {}
    for i = 1, #list do parts[i] = string.format("%d,%d", list[i].x, list[i].y) end
    return table.concat(parts, ";")
end

function M.fieldDecode(text)
    local list = {}
    for x, y in string.gmatch(tostring(text or ""), "(%-?%d+),(%-?%d+)") do
        list[#list + 1] = { x = tonumber(x), y = tonumber(y) }
    end
    return list
end

-- ---------------------------------------------------------------------------------------------------------------
-- The work, per kind: server / single player
-- ---------------------------------------------------------------------------------------------------------------

local function vanilla(class, fields)
    return setmetatable(fields, { __index = class })
end

local Work = {}

function Work.water(self, plant, square)
    local need = M.fieldWaterNeed(plant)
    if need <= 0 then return true end
    local left = M.fieldWaterUses(self.item)
    if left <= 0 then return false end
    ISWaterPlantAction.complete(vanilla(ISWaterPlantAction, {
        character = self.character, item = self.item, uses = math.min(need, left), usesUsed = 0, sq = square,
    }))
    return true
end

--- What vanilla's `complete`s read from their client plant: only its coordinates.
local function at(square)
    return { x = square:getX(), y = square:getY(), z = square:getZ() }
end

function Work.cure(self, plant, square)
    local need = M.fieldCureNeed(plant, self.what)
    if need <= 0 then return true end
    local left = M.fieldItemUses(self.item)
    if left <= 0 then return false end
    ISCurePlantAction.complete(vanilla(ISCurePlantAction, {
        character = self.character, item = self.item, uses = math.min(need, left), cure = self.what,
        plant = at(square),
    }))
    return true
end

function Work.fertilize(self, plant, square)
    if not M.fieldWantsFertilizer(plant) then return true end
    if M.fieldItemUses(self.item) <= 0 then return false end
    ISFertilizeAction.complete(vanilla(ISFertilizeAction, {
        character = self.character, item = self.item, plant = at(square),
    }))
    return true
end

local function isDigTool(item)
    return not item:isBroken() and item:hasTag(ItemTag.DIG_PLOW)
end

--- A finished plot of the state asked for, removed the way vanilla's Remove does (`ISShovelAction:complete`: tall grass
--- and the plot).
function Work.clear(self, plant, square)
    if not M.FIELD_CLEARABLE[self.what] or plant.state ~= self.what then return true end
    if not isDigTool(self.item) then return false end
    ISShovelAction.complete(vanilla(ISShovelAction, {
        character = self.character, item = self.item, plant = at(square),
    }))
    return true
end

--- `ISFarmingMenu.canDigHereSquare` (client only), against the server's plant. `ISPlowAction:complete` removes any plant
--- it finds on the square and asks nothing, so this is what keeps a living crop or a furrow safe.
local function canFurrow(square, plant)
    if square:hasGrave() then return false end
    if plant and (plant.state == "plow" or plant:isAlive()) then return false end
    local groundFloor = getSandboxOptions():getOptionByName("PlaceDirtAboveground"):getValue() == true or square:getZ() == 0
    if not groundFloor then return false end
    return square:isFree(false) and ISShovelGroundCursor.GetDirtGravelSand(square) == "dirt"
end

--- A new furrow through vanilla's `complete`, so arm strain and worms are per square, and Homesteading's back strain wrap
--- applies. `plant` may be nil here, unlike every other kind of work.
function Work.furrow(self, plant, square)
    if not canFurrow(square, plant) then return true end
    if not isDigTool(self.item) then return false end
    ISPlowAction.complete(vanilla(ISPlowAction, {
        character = self.character, item = self.item, gridSquare = square,
    }))
    return true
end

function Work.sow(self, plant, square)
    if plant.state ~= "plow" then return true end
    local seed = table.remove(self.seeds, 1)
    if not seed then return false end
    ISSeedActionNew.complete(vanilla(ISSeedActionNew, {
        character = self.character, seed = seed, typeOfSeed = self.what, plant = at(square),
    }))
    return true
end

--- The good seeds of the action's type in the main inventory.
local function seedsOf(chr, item)
    local out = {}
    local list = chr:getInventory():getAllType(item:getFullType())
    for i = 0, list:size() - 1 do
        if M.fieldGoodSeed(list:get(i)) then out[#out + 1] = list:get(i) end
    end
    return out
end

function A:complete()
    local chr, item = self.character, self.item
    if not chr or not item or not Work[self.kind] or not M.sig(chr, "Homesteading.SigFields") then return false end
    local inv = chr:getInventory()
    if not inv:containsID(item:getID()) then return false end
    if self.kind == "sow" then self.seeds = seedsOf(chr, item) end

    local px, py, z = chr:getX(), chr:getY(), self.z
    if z ~= math.floor(chr:getZ()) then return false end
    local targets = M.fieldDecode(self.targets)
    for i = 1, math.min(#targets, M.FIELD_MAX_TARGETS) do
        local x, y = targets[i].x, targets[i].y
        if math.abs(x - px) <= M.FIELD_REACH and math.abs(y - py) <= M.FIELD_REACH then
            local square = getCell():getGridSquare(x, y, z)
            local plant = square and SFarmingSystem.instance:getLuaObjectOnSquare(square)
            if square and (plant or self.kind == "furrow") and not Work[self.kind](self, plant, square) then break end
            -- The last use can turn the item into its empty version or remove it.
            if self.kind ~= "sow" and not inv:containsID(item:getID()) then break end
        end
    end
    return true
end

-- ---------------------------------------------------------------------------------------------------------------
-- The action around it
-- ---------------------------------------------------------------------------------------------------------------

local JOB_TEXT = { water = "ContextMenu_Water", cure = "ContextMenu_Treat_Problem", fertilize = "ContextMenu_Fertilize",
    clear = "ContextMenu_Remove", furrow = "ContextMenu_Dig" }
local SOUND = { water = "WaterCrops", cure = "WaterCrops", fertilize = "DropSoilFromSandBag", sow = "SowSeeds" }

function A:isValid()
    return self.item ~= nil and self.character:getInventory():containsID(self.item:getID())
end

function A:waitToStart()
    self.character:faceLocation(self.faceX, self.faceY)
    return self.character:isTurning() or self.character:shouldBeTurning()
end

function A:update()
    if self.kind ~= "sow" then self.item:setJobDelta(self:getJobDelta()) end
    self.character:faceLocation(self.faceX, self.faceY)
    if self.kind == "clear" then
        -- As vanilla's `ISShovelAction:update`, for the one action's length.
        self.character:setMetabolicTarget(Metabolics.DiggingSpade)
        local strain = (1 - self.character:getPerkLevel(Perks.Farming) * 0.05) / 10 * getGameTime():getMultiplier()
        self.character:addCombatMuscleStrain(self.item, 1, strain)
        return
    end
    if self.kind == "furrow" then
        self.character:setMetabolicTarget(Metabolics.DiggingSpade)
        return
    end
    self.character:setMetabolicTarget(self.kind == "sow" and Metabolics.HeavyDomestic or Metabolics.LightWork)
end

function A:start()
    if isClient() and self.item then
        self.item = self.character:getInventory():getItemById(self.item:getID()) or self.item
    end
    if self.kind == "sow" then
        self:setActionAnim("Loot")
        self.character:SetVariable("LootPosition", "Low")
        self.character:reportEvent("EventLootItem")
    elseif self.kind == "clear" then
        self.item:setJobType(getText(JOB_TEXT.clear))
        self.item:setJobDelta(0.0)
        self:setActionAnim(BuildingHelper.getShovelAnim(self.character:getPrimaryHandItem()))
        -- A looping world sound, stopped by hand, as vanilla's `ISShovelAction:start`.
        local square = getCell():getGridSquare(self.faceX, self.faceY, self.z)
        if square then self.worldSound = getSoundManager():PlayWorldSound("Shoveling", square, 0, 10, 1, true) end
        return
    elseif self.kind == "furrow" then
        -- As vanilla's `ISPlowAction:start`, the noise that draws zombies included.
        self.item:setJobType(getText(JOB_TEXT.furrow))
        self.item:setJobDelta(0.0)
        local trowel = DigType.TROWEL:toString() == self.item:getDigType()
        self.sound = self.character:playSound(trowel and "DigFurrowWithTrowel" or "DigFurrowWithShovel")
        addSound(self.character, self.character:getX(), self.character:getY(), self.character:getZ(), 10, 1)
        self:setActionAnim(BuildingHelper.getShovelAnim(self.item))
        self:setOverrideHandModels(self.item:getStaticModel(), nil)
        return
    else
        self.item:setJobType(getText(JOB_TEXT[self.kind]))
        self.item:setJobDelta(0.0)
        self:setActionAnim(CharacterActionAnims.Pour)
        self:setAnimVariable("PourType", self.item:getPourType() or "Bucket")
        self:setOverrideHandModels(self.item, nil)
    end
    self.sound = self.character:playSound(SOUND[self.kind])
end

local function finish(self)
    if self.sound and self.sound ~= 0 then self.character:getEmitter():stopOrTriggerSound(self.sound) end
    if self.worldSound and self.worldSound:isPlaying() then self.worldSound:stop() end
    if self.item and self.kind ~= "sow" then self.item:setJobDelta(0.0) end
end

function A:stop()
    finish(self)
    ISBaseTimedAction.stop(self)
end

function A:perform()
    finish(self)
    ISBaseTimedAction.perform(self)
end

function A:getDuration()
    if self.character:isTimedActionInstant() then return 1 end
    return self.maxTimeInit
end

--- kind: "water", "cure", "fertilize", "clear", "furrow" or "sow". what: the cure's name, the sown plant's type, the state
--- of the plots to clear, else "". z: the level.
--- targets: M.fieldEncode's string. maxTimeInit: the length of the slowest single plant.
function A:new(character, item, kind, what, z, targets, maxTimeInit)
    local o = ISBaseTimedAction.new(self, character)
    o.item = item
    o.kind = kind
    o.what = what or ""
    o.z = z
    o.targets = targets
    o.maxTimeInit = maxTimeInit
    o.maxTime = o:getDuration()
    if kind == "furrow" then o.caloriesModifier = 5 elseif kind == "clear" then o.caloriesModifier = 4 end
    local sx, sy, list = 0, 0, M.fieldDecode(targets)
    for i = 1, #list do
        sx, sy = sx + list[i].x, sy + list[i].y
    end
    o.faceX = #list > 0 and math.floor(sx / #list) or character:getX()
    o.faceY = #list > 0 and math.floor(sy / #list) or character:getY()
    return o
end
