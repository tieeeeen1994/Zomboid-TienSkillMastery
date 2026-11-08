--[[
Tien's Skill Mastery: Conditioning's signature, Heavy Load one moodle level lower, for **every** effect of it
(user, 2026-11-08; until then only combat speed, running drain and recovery were given back by hand).

The moodle level is the only thing those effects read (42.21, `getMoodleLevel(MoodleType.HEAVY_LOAD)`): walk / run
speed (`calculateBaseSpeed` -0.15 a level), running / walking endurance drain and recovery (`IsoPlayer.updateEndurance`),
exercise endurance (`Fitness`), health damage and back strain at 3+ (`BodyDamage.Update`), combat speed, melee crit,
grab defence, crawler-lunge fall, fence trip, wall / rope climbing, rope speed, climbing arm strain, vehicle
discomfort. Lua cannot set a moodle's level (`Moodle` has no setter; `Update` recomputes it every update), but the
level is just carried weight / max weight against 1.0 / 1.25 / 1.5 / 1.75 (`Moodle.Update` ~375, `MoodleStat`), so a
max weight that puts the same load one band lower lowers every effect at once. Load at level 1 becomes no moodle,
level 4 becomes 3.

Max weight (`BodyDamage.UpdateStrength` ~2008, every update on the server / single player only; an MP client never
computes it and takes the server's from PlayerDamage every 2 s): int(maxWeightBase x weightMod) minus 1-3 points per
hunger / thirst / sickness / bleeding / injury moodle (floored at 0), then int(x maxWeightDelta). `HL.compute` does the
same in Lua and picks the shifted max: the load's ratio moved down 0.25 (one band), clamped inside the target band,
then stepped by whole kg until the level is right. The server reaches it through `maxWeightDelta` (Physical.lua,
together with Conditioning.CarryWeight); the client sets its local player's `maxWeight` itself every update so the
client-side effects (speed, combat, climbing) do not wait for the next PlayerDamage.

Other readers of max weight (checked 2026-11-08): Java's `Transaction` timing uses a carried bag's own capacity, not
the player's max (unaffected); `Thermoregulator` heat from load is clamped at load = max (a level 1 load reads just
under it: practically the same); `isOverEncumbered` has no caller. Lua reads it through `IsoPlayer:getMaxWeight()` and
the main inventory's `ItemContainer:getMaxWeight()`, both wrapped below to return the real max, so the weight label
and the pickup timers that scale with how full the inventory is stay vanilla.
]]

require "TienSkillMastery"
local M = TienSkillMastery

local HL = {}
M.HeavyLoad = HL

HL.realMax = setmetatable({}, { __mode = "k" })   -- [player] = real max weight while the signature is on

-- Strength reducers per moodle level 1..4 (`UpdateStrength`).
local REDUCERS = {
    { "HUNGRY", { 0, 1, 2, 2 } },
    { "THIRST", { 0, 1, 2, 2 } },
    { "SICK", { 0, 1, 2, 3 } },
    { "BLEEDING", { 0, 1, 1, 1 } },
    { "INJURED", { 0, 1, 2, 3 } },
}

-- Band of each level: level L when ratio is in [LOW[L], HIGH[L]) (level 1 is open at 1.0).
local LOW = { [0] = 0, 1.0, 1.25, 1.5, 1.75 }
local HIGH = { [0] = 1.0, 1.25, 1.5, 1.75, math.huge }

--- The Heavy Load level `Moodle.Update` gives this load against this max.
function HL.levelOf(weight, max)
    if max <= 0 then return weight > 0 and 4 or 0 end
    local r = weight / max
    if r >= 1.75 then return 4 end
    if r >= 1.5 then return 3 end
    if r >= 1.25 then return 2 end
    if r > 1.0 then return 1 end
    return 0
end

--- Conditioning.CarryWeight as a share of maxWeightDelta (whole kg).
function HL.carryDelta(player)
    local kg = math.floor(round(M.val(player, "Conditioning.CarryWeight"), 3))
    local base = player:getMaxWeightBase() * player:getWeightMod()
    if kg > 0 and base > 0 then return (kg + 0.05) / base end
    return 0
end

--- `UpdateStrength`'s max weight before the delta.
function HL.strengthBase(player)
    local moodles = player:getMoodles()
    local n = 0
    for _, r in ipairs(REDUCERS) do
        local level = moodles:getMoodleLevel(MoodleType[r[1]])
        if level and level >= 1 then n = n + r[2][math.min(level, 4)] end
    end
    return math.max(0, math.floor(player:getMaxWeightBase() * player:getWeightMod()) - n)
end

--- The max weight that puts `weight` one Heavy Load level below what `real` gives (`real` when it is level 0).
function HL.shiftedMax(weight, real)
    if real <= 0 then return real end
    local level = HL.levelOf(weight, real)
    if level == 0 then return real end
    local want = level - 1
    local target
    if want == 0 then
        target = math.ceil(weight)
    else
        local r = math.max(LOW[want] + 0.01, math.min(HIGH[want] - 0.01, weight / real - 0.25))
        target = math.floor(weight / r + 0.5)
        for _ = 1, 100 do
            local l = HL.levelOf(weight, target)
            if l > want then target = target + 1
            elseif l < want and target > 1 then target = target - 1
            else break end
        end
        -- A max under ~6 kg can leave the band with no whole number in it: then the smallest max that is at least
        -- one level lower (two lower at worst), never less than promised.
        if HL.levelOf(weight, target) ~= want then
            target = real
            while HL.levelOf(weight, target) > want do target = target + 1 end
        end
    end
    return math.max(real, target)
end

--- For a player and the delta vanilla gave it: carry delta, and (signature on) the real max, the shifted max and the
--- base `UpdateStrength` multiplies by the delta.
function HL.compute(player, vanillaDelta)
    local carry = HL.carryDelta(player)
    if not M.sig(player, "Conditioning.SigHeavyLoad") then return carry end
    local base = HL.strengthBase(player)
    if base <= 0 then return carry end
    -- Java multiplies in float (20 x 0.9f = 18.0), Lua in double (17.9999995), then Java's (int) cuts the decimals. So
    -- round the float noise away (vanilla's `round`, shared/env.lua), then floor: rounding to a whole number would
    -- be wrong (19 x 1.25 = 23.75 is 23 in Java).
    local real = math.floor(round(base * (vanillaDelta + carry), 3))
    local weight = player:getInventory():getCapacityWeight()
    return carry, real, HL.shiftedMax(weight, real), base
end

-- ---------------------------------------------------------------------------------------------------------------
-- Client: the local player's max weight at once (the server's arrives with PlayerDamage every 2 s).
-- ---------------------------------------------------------------------------------------------------------------

if isClient() then
    local shifted = setmetatable({}, { __mode = "k" })
    Events.OnPlayerUpdate.Add(function(player)
        if not player or not player:isLocalPlayer() then return end
        local ok, _, real, target = pcall(HL.compute, player, player:getMaxWeightDelta())
        if not ok then return end
        HL.realMax[player] = real
        -- Set while shifted, and once more when it stops (else the shifted max stays until PlayerDamage).
        if target and (target ~= real or shifted[player]) and player:getMaxWeight() ~= target then
            player:setMaxWeight(target)
        end
        shifted[player] = target ~= nil and target ~= real or nil
    end)
end

-- ---------------------------------------------------------------------------------------------------------------
-- Lua callers see the real max (every side; Java's own calls are not affected): `IsoPlayer:getMaxWeight()` (inventory
-- weight label, Strength XP from carrying, hotbar weight check) and the main inventory's `ItemContainer:getMaxWeight()`
-- (= the owner's max in Java, ~2268), which scales pickup times by how full the inventory is:
-- `ISWorldObjectContextMenu.grabItemTime` (Grab; single player, MP grabs are timed by the server's Transaction) and
-- `ISPickUpGroundCoverItem.grabItemTime2` (stones, branches; its duration is taken on the server in MP).
-- ---------------------------------------------------------------------------------------------------------------

local function wrapGetMaxWeight(class, name, realOf)
    local meta = __classmetatables and class and __classmetatables[class.class]
    local index = meta and meta.__index
    local original = index and index.getMaxWeight
    if not original then
        print("[TienSkillMastery] HeavyLoad: " .. name .. ":getMaxWeight is not reachable, the shifted max weight shows there")
        return
    end
    index.getMaxWeight = function(self, ...)
        local real = realOf(self)
        if real then return real end
        return original(self, ...)
    end
end

wrapGetMaxWeight(IsoPlayer, "IsoPlayer", function(player) return HL.realMax[player] end)
wrapGetMaxWeight(ItemContainer, "ItemContainer", function(container)
    local parent = container:getParent()
    return parent and HL.realMax[parent] or nil
end)
