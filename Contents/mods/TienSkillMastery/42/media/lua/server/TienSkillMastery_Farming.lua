--[[
Tien's Skill Mastery: Farming mastery (yield, cure, planting, fertilizing, back strain). Server / single player.

Where vanilla 42.21 computes each value. Farming is a server global object system: `media/lua/server/Farming`
(SFarmingSystem, SPlantGlobalObject, farmingCommands) only runs on a server or in single player (each file starts
with `if isClient() then return end`). The shared farming actions do the work in `complete`, which in multiplayer
runs only on the server (`NetTimedAction`) and in single player locally. So every hook here sits on the server side;
a client never computes any of it. Changes to a plant reach clients the way vanilla sends them: each vanilla method
ends with `self:saveData()` (modData into the IsoObject + `transmitModData`), and items with
`sendAddItemsToContainer`.

The plant methods only receive a skill number, never the player (`plant:seed(type, skill)`, `cureX(src, uses,
skill)`, `fertilize(args)` with `args.skill`, global `getVegetablesNumber(..., skill)`). So the callers that know the
player set `current` for the duration of the call (pcall, put back afterwards):
- the shared actions' `complete`: ISCurePlantAction (~56), ISSeedActionNew (~56), ISFertilizeAction (~59),
  ISHarvestPlantAction (~51), ISPlowAction (~76), plus ISRemoveGrass (~41) / ISRemoveBush (~118) for back strain;
- `SFarmingSystem:harvest(luaObject, player)` (~333), whatever calls it;
- the legacy commands `SFarmingSystemCommands.cure*/seed/fertilize` (farmingCommands.lua; vanilla 42.21 no longer
  sends them, but the dispatcher `SFarmingSystem:OnClientCommand` (~83) looks the table up at every call). Their
  `args.skill` comes from the client; the bonus is taken from the sender as the server knows him.
Plant objects find methods through the class table (`SPlantGlobalObject` / `SFarmingSystem` metatables), so
replacing the class fields at load reaches every plant. `getVegetablesNumber` is a global looked up at call time by
`SFarmingSystem:harvest`, so replacing the global works.

Farming.Yield: `getVegetablesNumber` (farming_vegetableconf.lua ~17): ZombRand(min, max + 1) by plant health, minus
pests, + level when ZombRand(10) < level (~67), at least 1. The result is scaled with `M.scaleInt` (fraction rolled).
Vanilla bug seen (~72-73): the sandbox yield `FarmingAmountNew` is written to a stray global `numberOfVeg` and never
applied, so that sandbox option does nothing in 42.21.

Farming.Cure: `SPlantGlobalObject:cureMildew/cureFlies/cureAphids/cureSlugs(src, uses, skill)` (~436-498) remove
`10 + skill` per use (clamped at 0 each use). The wrapper passes a skill that makes that (10 + skill) x (1 + bonus).

Farming.PlantHealth: `SPlantGlobalObject:initHealth(skill)` (~736, only called by `seed`) sets health to
ZombRand(57, 64) + skill (best month), 37..43 + skill (cursed) or `SFarmingSystem:getHealth()` + skill. The wrapper
adds `M.int` (3 at mastery 10, fraction rolled).

Farming.BonusYield / Farming.Curse: `SPlantGlobalObject:seed(type, skill)` (~715), with PlantGrowingSeasons on:
not a sow month = cursed; elseif risk month and ZombRand(20) < 11 - skill = cursed (~727); elseif best month and
ZombRand(20) < 9 + skill = bonusYield (~728). After vanilla's roll the wrapper moves the odds by the bonus points: a
plant the risk roll cursed is uncursed with chance c / p0 (p0 = vanilla's curse chance, so P = p0 - c); then, as in
vanilla's elseif, a best month rolls the bonus, and the health is rolled again for an uncursed plant (initHealth
assigns, so this replaces the cursed range); a plant that missed the bonus roll gets it with chance
(b1 - b0) / (1 - b0), b1 = b0 + points. Then `saveData` again.

Farming.Fertilize: `SPlantGlobalObject:fertilize2(skill)` (~596, from `fertilize` on the first dose and from
`compostPlant`): outside winter (or with seasons off), nbOfGrow <= 3, not cursed, no weeds: bonusYield when
ZombRand(20) < 9 + skill (~614). Same top-up roll as above; both callers `saveData` after it.

Farming.BackStrain: every Lua `addBackMuscleStrain` call in vanilla 42.21 is farming work, each in `complete` with
1 - 0.05 x Farming: ISHarvestPlantAction (~57, low plants), ISPlowAction (~106, trowel or hands, x0.7 / x1),
ISSeedActionNew (~58), ISRemoveGrass (~43), ISRemoveBush (~121, without a weapon; on a server `self.weapon` is unset).
`IsoGameCharacter.addBackMuscleStrain` (Java ~16389) adds the stiffness to Torso_Upper / Torso_Lower, which reaches the
owner with the 2 s PlayerDamage sync. The wrapper on IsoPlayer's class `__index` (it shadows IsoGameCharacter's
method for players only; Java callers such as heavy-load strain in BodyDamage ~2306 never pass through Lua) scales the
argument only while one of those `complete`s runs for that character. ISShovelAction has no back strain: its
farming-scaled strain is `addCombatMuscleStrain` (arms) in the client-side `update`, so it is not touched.
]]

if isClient() then return end

require "TienSkillMastery"
require "Farming/SFarmingSystem"
require "Farming/SPlantGlobalObject"
require "Farming/farming_vegetableconf"
require "Farming/farmingCommands"
local M = TienSkillMastery

if not SFarmingSystem or not SPlantGlobalObject then
    print("[TienSkillMastery] Farming: farming system not found, farming bonuses off")
    return
end
if SPlantGlobalObject.__tsmFarming then return end
SPlantGlobalObject.__tsmFarming = true

-- ---------------------------------------------------------------------------------------------------------------
-- Context: the player whose farming work is being applied, and the back strain factor per character.
-- ---------------------------------------------------------------------------------------------------------------

local current = nil
local strainScale = {}

--- Call fn(...) with `current` set to player, restoring it afterwards even when fn throws.
local function withPlayer(player, fn, ...)
    local prev = current
    current = player
    local results = { pcall(fn, ...) }
    current = prev
    if not results[1] then error(results[2]) end
    return unpack(results, 2)
end

local function clamp01(x)
    if x < 0 then return 0 end
    if x > 1 then return 1 end
    return x
end

--- Chance for a second roll after a failed one so that the total chance goes from base to base + pts.
local function topUp(base, pts)
    base = clamp01(base)
    if base >= 1 or pts <= 0 then return 0 end
    return (clamp01(base + pts) - base) / (1 - base)
end

local function seasonsOn()
    return getSandboxOptions():getOptionByName("PlantGrowingSeasons"):getValue() == true
end

-- ---------------------------------------------------------------------------------------------------------------
-- Back strain: scale IsoPlayer:addBackMuscleStrain while a farming action's complete runs for that character.
-- ---------------------------------------------------------------------------------------------------------------

do
    local meta = __classmetatables and IsoPlayer and __classmetatables[IsoPlayer.class]
    local index = meta and meta.__index
    local original = index and index.addBackMuscleStrain
    if original then
        index.addBackMuscleStrain = function(chr, painfactor, ...)
            local f = strainScale[chr]
            if f and type(painfactor) == "number" then painfactor = painfactor * f end
            return original(chr, painfactor, ...)
        end
    else
        print("[TienSkillMastery] Farming: IsoPlayer:addBackMuscleStrain is not reachable, back strain bonus off")
    end
end

--- Wrap an action's complete: farming context + back strain factor for self.character.
local function wrapComplete(class)
    if not class or type(class.complete) ~= "function" then return end
    local original = class.complete
    class.complete = function(self, ...)
        local chr = self.character
        if not chr then return original(self, ...) end
        local prevStrain = strainScale[chr]
        local f = M.less(chr, "Farming.BackStrain")
        if f < 1 then strainScale[chr] = f end
        local prev = current
        current = chr
        local results = { pcall(original, self, ...) }
        current = prev
        strainScale[chr] = prevStrain
        if not results[1] then error(results[2]) end
        return unpack(results, 2)
    end
end

wrapComplete(ISHarvestPlantAction)
wrapComplete(ISPlowAction)
wrapComplete(ISSeedActionNew)
wrapComplete(ISCurePlantAction)
wrapComplete(ISFertilizeAction)
wrapComplete(ISRemoveGrass)
wrapComplete(ISRemoveBush)

-- Legacy commands: the sender is the player.
if SFarmingSystemCommands then
    for _, name in ipairs({ "cureFlies", "cureMildew", "cureAphids", "cureSlugs", "seed", "fertilize" }) do
        local original = SFarmingSystemCommands[name]
        if type(original) == "function" then
            SFarmingSystemCommands[name] = function(player, args, ...)
                if not player then return original(player, args, ...) end
                return withPlayer(player, original, player, args, ...)
            end
        end
    end
end

-- ---------------------------------------------------------------------------------------------------------------
-- Harvest yield
-- ---------------------------------------------------------------------------------------------------------------

local originalHarvest = SFarmingSystem.harvest
function SFarmingSystem:harvest(luaObject, player, ...)
    if not player then return originalHarvest(self, luaObject, player, ...) end
    return withPlayer(player, originalHarvest, self, luaObject, player, ...)
end

local originalVegetables = getVegetablesNumber
if type(originalVegetables) == "function" then
    function getVegetablesNumber(...)
        local results = { originalVegetables(...) }
        local n = results[1]
        if current and type(n) == "number" and n > 0 then
            results[1] = M.scaleInt(current, "Farming.Yield", n)
        end
        return unpack(results)
    end
end

-- ---------------------------------------------------------------------------------------------------------------
-- Cures
-- ---------------------------------------------------------------------------------------------------------------

for _, name in ipairs({ "cureMildew", "cureFlies", "cureAphids", "cureSlugs" }) do
    local original = SPlantGlobalObject[name]
    if type(original) == "function" then
        SPlantGlobalObject[name] = function(self, source, uses, skill, ...)
            if current then
                local f = M.more(current, "Farming.Cure")
                if f > 1 then
                    -- vanilla removes 10 + skill per use
                    skill = (10 + (tonumber(skill) or 0)) * f - 10
                end
            end
            return original(self, source, uses, skill, ...)
        end
    end
end

-- ---------------------------------------------------------------------------------------------------------------
-- Planting: health, curse and bonus yield
-- ---------------------------------------------------------------------------------------------------------------

local originalInitHealth = SPlantGlobalObject.initHealth
function SPlantGlobalObject:initHealth(skill, ...)
    local results = { originalInitHealth(self, skill, ...) }
    if current and type(self.health) == "number" then
        local extra = M.int(current, "Farming.PlantHealth")
        if extra > 0 then self.health = self.health + extra end
    end
    return unpack(results)
end

local originalSeed = SPlantGlobalObject.seed
function SPlantGlobalObject:seed(typeOfSeed, skill, ...)
    local player = current
    if not player then return originalSeed(self, typeOfSeed, skill, ...) end
    local cursedBefore, bonusBefore = self.cursed, self.bonusYield
    local results = { originalSeed(self, typeOfSeed, skill, ...) }
    if not seasonsOn() or not self:isSowMonth() then return unpack(results) end

    local s = tonumber(skill) or 0
    local bonusBase = clamp01((9 + s) / 20)
    local bonusPts = M.val(player, "Farming.BonusYield") / 100
    local changed = false

    if self:isRiskMonth() and self.cursed and not cursedBefore then
        -- the risk roll cursed it; take off the bonus points
        local curseBase = clamp01((11 - s) / 20)
        local cursePts = M.val(player, "Farming.Curse") / 100
        if curseBase > 0 and cursePts > 0 and ZombRandFloat(0, 1) < math.min(1, cursePts / curseBase) then
            self.cursed = false
            changed = true
            -- vanilla's elseif: a failed curse roll in a best month rolls the bonus next
            if self:isBestMonth() and ZombRandFloat(0, 1) < clamp01(bonusBase + bonusPts) then
                self.bonusYield = true
            end
            self:initHealth(skill)
        end
    elseif self:isBestMonth() and not self.cursed and not self.bonusYield and not bonusBefore then
        if ZombRandFloat(0, 1) < topUp(bonusBase, bonusPts) then
            self.bonusYield = true
            changed = true
        end
    end

    if changed then
        local sprite = farming_vegetableconf.getSpriteName(self)
        if sprite then self:setSpriteName(sprite) end
        self:saveData()
    end
    return unpack(results)
end

-- ---------------------------------------------------------------------------------------------------------------
-- Fertilizing: early bonus yield chance
-- ---------------------------------------------------------------------------------------------------------------

local originalFertilize2 = SPlantGlobalObject.fertilize2
function SPlantGlobalObject:fertilize2(skill, ...)
    local player = current
    if not player then return originalFertilize2(self, skill, ...) end
    local eligible = (getClimateManager():getSeasonName() ~= "Winter" or not seasonsOn())
        and (tonumber(self.nbOfGrow) or 99) <= 3 and not self.cursed and not self.hasWeeds
    local bonusBefore = self.bonusYield
    local results = { originalFertilize2(self, skill, ...) }
    if eligible and not bonusBefore and not self.bonusYield then
        local base = (9 + (tonumber(skill) or 0)) / 20
        if ZombRandFloat(0, 1) < topUp(base, M.val(player, "Farming.Fertilize") / 100) then
            -- both callers (fertilize, compostPlant) saveData after this
            self.bonusYield = true
        end
    end
    return unpack(results)
end
