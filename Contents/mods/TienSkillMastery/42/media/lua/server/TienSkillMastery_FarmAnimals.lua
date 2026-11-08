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

local originalPart = ButcheringUtil.addAnimalPart
ButcheringUtil.addAnimalPart = function(part, player, carcass, ...)
    if extraDepth > 0 or type(part) ~= "table" or not part.item or not player
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

-- Provisioning.LastingFood (phase 2) and the choice cuts signature (phase 3a): meat a master butchers stays fresh
-- longer and is more filling and nutritious (hunger, base hunger, calories, lipids, proteins, carbs x 1.4; vanilla's
-- own `modifyMeat` scales the same fields by animal size and cut). `giveMeatModified(meatDef, nb,
-- player, ...)` (~363) makes each meat item, runs `modifyMeat(item, size, meatRatio, hungerBoost, rotten, deathAge)`
-- (~426: nutrition, age), then `AddItem` + `sendAddItemToContainer`. `modifyMeat` has no player, so the butcher is
-- noted for the giveMeatModified call and modifyMeat's item gets its spoil times stretched before the send.
-- Organs and other parts (`addAnimalPart` without a meat definition) are left as they are.
local butcher = nil
local meatCall = ButcheringUtil.giveMeatModified
ButcheringUtil.giveMeatModified = function(meatDef, nb, player, ...)
    local was = butcher
    butcher = player
    local results = { pcall(meatCall, meatDef, nb, player, ...) }
    butcher = was
    if not results[1] then error(results[2], 0) end
    return unpack(results, 2)
end
local vanillaModifyMeat = ButcheringUtil.modifyMeat
if vanillaModifyMeat then
    ButcheringUtil.modifyMeat = function(item, ...)
        local text = vanillaModifyMeat(item, ...)
        if butcher and item then
            M.stretchFood(item, M.more(butcher, "Provisioning.LastingFood"))
            -- Provisioning's signature, choice cuts: the meat is 40% more filling and nutritious (flat, from the pick).
            local cuts = M.val(butcher, "Provisioning.SigChoiceCuts")
            if cuts > 0 and instanceof(item, "Food") then
                local f = 1 + cuts / 100
                item:setHungChange(item:getHungChange() * f)
                item:setBaseHunger(item:getBaseHunger() * f)
                item:setCalories(item:getCalories() * f)
                item:setLipids(item:getLipids() * f)
                item:setProteins(item:getProteins() * f)
                item:setCarbohydrates(item:getCarbohydrates() * f)
            end
        end
        return text
    end
end
