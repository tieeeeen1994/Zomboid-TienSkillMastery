--[[
Tien's Skill Mastery: Animal Care (acceptance, calming) and Butchering (part count, part chance). Server / single
player.

Animal Care. Java `IsoAnimal` (42.21):
- `petAnimal(chr)` (~2495) does nothing on a client; elsewhere, when `petTimer == 0`: stress
  `changeStress(Rand.Next(-11, -7) - Husbandry)`, acceptance `min(100, acceptance + Rand.Next(2, 7))`, petTimer
  15000-25000 - 200 x Husbandry. Lua callers: `ISPetAnimal:complete` (~69) and `ISPetAnimal:animEvent`
  "pettingFinished" (~86; emulated once at 3 s on the server by `serverStart`, a real anim event in single player).
  The second call finds the timer running and changes nothing.
- `feedFromHand(chr, food)` (~2477): stress `changeStress(Rand.Next(-4, -1) - Husbandry / 5)`, acceptance
  `min(100, acceptance + Rand.Next(1, 4))`. Lua caller: `ISFeedAnimalFromHand:complete` (~45).
Both run in the action's server-side `complete` / `animEvent` (MP) or locally (single player). The wrappers read
`getStress()` and `getAcceptanceLevel(chr)` before and after the vanilla call and add the bonus share of what it
removed / gained with `setDebugStress` (clamped at 0) / `setDebugAcceptance` (capped at 100). The client copy gets
both by the server's AnimalPacket (stress byte, and the receiving player's acceptance, `NetworkPlayerAI` ~210), every
0.8-1 s. Not reachable: acceptance from luring (`IsoPlayer` ~8541-8572 `tryLure` / `eatFromLured` ->
`addAcceptance(chr, 5)`) and from holding an animal (`updateStress` ~689, every update), both Java only with no Lua
call in between. Measuring the actions also covers stress genes and the "highstress" disorder (the share is of the
real change).

Butchering. `ButcheringUtil` (shared/Definitions/animal/ButcheringUtil.lua), whose item-giving functions only run on
the server / single player: `butcherAnimalFromGround` returns at once on a client, and the hook actions call
`addAnimalPart` from their server-side `complete` (`ISRemoveMeatFromAnimal` ~97). Every call goes through the table
(`ButcheringUtil.addAnimalPart(...)`), so replacing the fields works.
- Part count: `addAnimalPart(part, player, carcass, fromGround)` (~226) rolls `nb = ZombRand(minNb, maxNb)` (~313;
  maxNb x (1 + floor(level / 2) / 10) ~275), or the part's fixed `nb`, at least 1. Meat parts
  (`AnimalPartsDefinitions.meat[part.item]`) go to `giveMeatModified(meatDef, nb, ...)` (~322 / ~363), which splits
  nb over the cuts; the wrapper scales that nb with `M.scaleInt` there, so the cuts are split as vanilla would. Other
  parts are made in a loop inside addAnimalPart (~327); for them the wrapper counts what vanilla put into the
  player's main inventory and calls vanilla once more with a copy of the part whose fixed `nb` is the extra count
  (same size, meat ratio, rot and roadkill handling; the dead-baby branch has already cleared its flag). Extra items
  give the same per-item Butchering XP as vanilla's. Items are sent by vanilla's `sendAddItemToContainer`.
- Part chance: `getPartChance(baseChance, size, meatRatio, player)` (~416) = base x size x meatRatio x level / 7
  (100 for the last cut, which has no baseChance and takes the rest). The wrapper multiplies the result when there
  is a baseChance, which moves meat from the last (plain) cut to the better ones.
]]

if isClient() then return end

require "TienSkillMastery"
local M = TienSkillMastery

-- ---------------------------------------------------------------------------------------------------------------
-- Animal Care: acceptance gained and stress removed by petting / feeding from the hand
-- ---------------------------------------------------------------------------------------------------------------

--- Run fn(...) and add the bonus share of the stress removed from / acceptance gained by animal for chr.
local function withCareBonus(animal, chr, fn, ...)
    if not animal or not chr or not instanceof(animal, "IsoAnimal") or not instanceof(chr, "IsoPlayer") then
        return fn(...)
    end
    local calming = M.more(chr, "Homesteading.Calming")
    local acceptance = M.more(chr, "Homesteading.Acceptance")
    if calming <= 1 and acceptance <= 1 then return fn(...) end

    local stress0 = animal:getStress()
    local acc0 = animal:getAcceptanceLevel(chr)
    local results = { fn(...) }

    local stress1 = animal:getStress()
    local removed = stress0 - stress1
    if calming > 1 and removed > 0 then
        animal:setDebugStress(math.max(0, stress1 - removed * (calming - 1)))
    end
    local acc1 = animal:getAcceptanceLevel(chr)
    local gained = acc1 - acc0
    if acceptance > 1 and gained > 0 and acc1 < 100 then
        animal:setDebugAcceptance(chr, math.min(100, acc1 + gained * (acceptance - 1)))
    end
    return unpack(results)
end

if ISPetAnimal and not ISPetAnimal.__tsmCare then
    ISPetAnimal.__tsmCare = true
    local originalComplete = ISPetAnimal.complete
    if originalComplete then
        ISPetAnimal.complete = function(self, ...)
            return withCareBonus(self.animal, self.character, originalComplete, self, ...)
        end
    end
    local originalAnimEvent = ISPetAnimal.animEvent
    if originalAnimEvent then
        ISPetAnimal.animEvent = function(self, event, parameter, ...)
            if event ~= "pettingFinished" then return originalAnimEvent(self, event, parameter, ...) end
            return withCareBonus(self.animal, self.character, originalAnimEvent, self, event, parameter, ...)
        end
    end
end

if ISFeedAnimalFromHand and ISFeedAnimalFromHand.complete and not ISFeedAnimalFromHand.__tsmCare then
    ISFeedAnimalFromHand.__tsmCare = true
    local originalComplete = ISFeedAnimalFromHand.complete
    ISFeedAnimalFromHand.complete = function(self, ...)
        return withCareBonus(self.animal, self.character, originalComplete, self, ...)
    end
end

-- ---------------------------------------------------------------------------------------------------------------
-- Homesteading's signature, Animal Whisperer (user, 2026-11-09): every 10 in-game minutes, each animal in the pen a
-- master stands in loses a flat 1 stress (0-100; `setDebugStress` has no clamp and skips the stress gene, so it is
-- flat). `EveryTenMinutes` follows the game clock (`GameTime`), so fast forward speeds it up, as it does the stress
-- the animal gains. The pen is what vanilla treats as one: `DesignationZoneAnimal.getZone` at the master's square, with
-- its connected zones and the hutches in them (loose animals in loaded chunks only, `VirtualAnimal`s are out of Lua's
-- reach). Two masters in one pen count once. Stress reaches clients in AnimalPacket, hutched animals too.
-- ---------------------------------------------------------------------------------------------------------------

local WHISPER_STRESS = 1

local function whisper(animal, seen)
    if not animal or seen[animal] then return end
    seen[animal] = true
    if animal:isDead() or animal:isOnHook() then return end
    animal:setDebugStress(math.max(0, animal:getStress() - WHISPER_STRESS))
end

Events.EveryTenMinutes.Add(function()
    local seen = {}
    M.eachPlayer(function(player)
        if not M.sig(player, "Homesteading.SigWhisperer") then return end
        local zone = DesignationZoneAnimal.getZone(math.floor(player:getX()), math.floor(player:getY()),
            math.floor(player:getZ()))
        if not zone then return end
        local animals = zone:getAnimalsConnected()
        for i = 0, animals:size() - 1 do
            whisper(animals:get(i), seen)
        end
        local hutches = zone:getHutchsConnected()
        for i = 0, hutches:size() - 1 do
            local hutch = hutches:get(i):getHutch()
            if hutch and not seen[hutch] then
                seen[hutch] = true
                for n = 0, hutch:getMaxAnimals() - 1 do
                    whisper(hutch:getAnimal(n), seen)
                end
                for n = 0, hutch:getMaxNestBox() do
                    whisper(hutch:getAnimalInNestBox(n), seen)
                end
            end
        end
    end)
end)

-- ---------------------------------------------------------------------------------------------------------------
-- Butchering: part count and part chance
-- ---------------------------------------------------------------------------------------------------------------

if not ButcheringUtil or not ButcheringUtil.addAnimalPart or ButcheringUtil.__tsmButchering then return end
ButcheringUtil.__tsmButchering = true

local meatPlayer = nil     -- set while vanilla's addAnimalPart hands a meat part to giveMeatModified
local extraDepth = 0       -- inside our own extra call: no further bonus

local originalChance = ButcheringUtil.getPartChance
if originalChance then
    ButcheringUtil.getPartChance = function(baseChance, size, meatRatio, player, ...)
        local results = { originalChance(baseChance, size, meatRatio, player, ...) }
        if baseChance and player and type(results[1]) == "number" then
            results[1] = results[1] * M.more(player, "Hunting.PartChance")
        end
        return unpack(results)
    end
end

local originalMeat = ButcheringUtil.giveMeatModified
if originalMeat then
    ButcheringUtil.giveMeatModified = function(meatDef, nb, player, ...)
        if meatPlayer and player == meatPlayer and type(nb) == "number" and nb > 0 then
            meatPlayer = nil   -- one scaling per part
            nb = M.scaleInt(player, "Hunting.PartCount", nb)
        end
        return originalMeat(meatDef, nb, player, ...)
    end
end

-- A part with a fixed count (`nb` > 0) gets no extras (user, 2026-11-09): all 26 in vanilla's AnimalPartsDefinitions are
-- anatomy or a whole carcass (2 chicken feet, 1 whole chicken or turkey, 1 skinned rat or mouse, 1 small bird), so the
-- copy below made a third foot or a second chicken. Parts with a minNb / maxNb range (meat, sinew, bones) still scale.
-- Test `> 0`, not `nb ~= nil`: vanilla's addAnimalPart writes `part.nb = -1` into the shared definition on first use.
local originalPart = ButcheringUtil.addAnimalPart
ButcheringUtil.addAnimalPart = function(part, player, carcass, ...)
    if extraDepth > 0 or type(part) ~= "table" or not part.item or not player
            or (tonumber(part.nb) or -1) > 0
            or M.val(player, "Hunting.PartCount") <= 0 then
        return originalPart(part, player, carcass, ...)
    end

    if AnimalPartsDefinitions and AnimalPartsDefinitions.meat and AnimalPartsDefinitions.meat[part.item] then
        local prev = meatPlayer
        meatPlayer = player
        local results = { pcall(originalPart, part, player, carcass, ...) }
        meatPlayer = prev
        if not results[1] then error(results[2]) end
        return unpack(results, 2)
    end

    local items = player:getInventory():getItems()
    local before = items:size()
    local text = originalPart(part, player, carcass, ...)
    local got = items:size() - before
    if got <= 0 then return text end
    local extra = M.scaleInt(player, "Hunting.PartCount", got) - got
    if extra <= 0 then return text end

    local copy = {}
    for k, v in pairs(part) do copy[k] = v end
    copy.nb = extra
    extraDepth = extraDepth + 1
    local ok, more = pcall(originalPart, copy, player, carcass, ...)
    extraDepth = extraDepth - 1
    if not ok then
        print("[TienSkillMastery] Butchering: extra part " .. tostring(part.item) .. " failed: " .. tostring(more))
        return text
    end
    return (text or "") .. (more or "")
end

-- Provisioning.LastingFood (phase 2) and the choice cuts signature (phase 3a), `M.butcherBonus`: all the food a master
-- butchers from an animal (user, 2026-11-09; only parts with a meat definition before, so not whole chickens and turkeys,
-- chicken feet, small bird and animal meat, skinned rats and mice). Both of `addAnimalPart`'s routes run `modifyMeat(item,
-- size, meatRatio, hungerBoost, rotten, deathAge)` (~426: nutrition, age) on each food item, then `AddItem` +
-- `sendAddItemToContainer`: `giveMeatModified(meatDef, nb, player, ...)` (~363) for a part with a meat definition, its
-- own loop (~327) for any other. `modifyMeat` has no player, so the butcher is noted around both calls and the bonus goes
-- on before the send. Animal heads are not given by that path and stay as they are. Small animals and fish butchered
-- by a recipe: TienSkillMastery_Crafting.lua.
local butcher = nil
local function withButcher(player, call, ...)
    local was = butcher
    butcher = player
    local results = { pcall(call, ...) }
    butcher = was
    if not results[1] then error(results[2], 0) end
    return unpack(results, 2)
end
local meatCall = ButcheringUtil.giveMeatModified
ButcheringUtil.giveMeatModified = function(meatDef, nb, player, ...)
    return withButcher(player, meatCall, meatDef, nb, player, ...)
end
local partCall = ButcheringUtil.addAnimalPart
ButcheringUtil.addAnimalPart = function(part, player, ...)
    return withButcher(player, partCall, part, player, ...)
end
local vanillaModifyMeat = ButcheringUtil.modifyMeat
if vanillaModifyMeat then
    ButcheringUtil.modifyMeat = function(item, ...)
        local text = vanillaModifyMeat(item, ...)
        if butcher and item then M.butcherBonus(item, butcher) end
        return text
    end
end
