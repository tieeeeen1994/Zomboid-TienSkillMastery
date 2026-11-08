--[[
Tien's Skill Mastery: bonuses the server owns (single player too): endurance, carry weight, weapon wear.

Endurance (Conditioning.Endurance, Freerunning.RunEndurance, <weapon mastery>.SwingEndurance): endurance is a server
stat (`NetworkPlayerManager` sends it to the owner every second), drained in Java with no Lua event: running /
sprinting in `IsoPlayer.updateEndurance`, swings in `CombatManager.processWeaponEndurance` (on the server, from
`AttackCollisionCheckPacket.processServer` / `PlayerHitCharacter`). Each tick the drop since the last tick is
measured per player and a share of it given back: Conditioning's share for every drop, plus Freerunning's while
running or sprinting, plus the weapon mastery's while standing or walking with a melee weapon of its category in hand
(how a swing is told apart: nothing else drains endurance there). Regeneration is left alone.

Carry weight (Conditioning.CarryWeight, flat): `BodyDamage.Update` (~2066, server / single player) sets `maxWeight` =
int(int(maxWeightBase x getWeightMod() - reducers) x maxWeightDelta) every update, and `maxWeightDelta` (trait
Strong 1.5 / Weak 0.75 / Feeble 0.9 / Stout 1.25, else 1) is only set when the player object is built, never saved,
never touched by vanilla Lua. The bonus is added to the delta as kg / (maxWeightBase x weightMod), whole kg only
(floor), and the original delta is remembered per player object, so each new amount goes on top of it, not on a rounded float.
The owner gets `maxWeight` with PlayerDamage (every 2 s). Conditioning's signature goes on the same delta: the max
weight is raised just enough that Heavy Load reads one level lower (shared/TienSkillMastery_HeavyLoad.lua).

Weapon wear (<weapon mastery>.WearUndo, chance per point, each weapon mastery for its own category, Firearms for
guns): condition, sharpness and head condition loss from use is rolled in `InventoryItem.damageCheck`, from
`CombatManager.processMaintenanceCheck` only when not a client, and from tree chopping on the server. A firearm
loses condition on the shooter's client (`attackCollisionCheck` ~1221, `damageCheck` with maintenance off) and
syncs it with `checkSyncItemFields`, so the server sees the drop the same way. Each tick the primary hand weapon of every player is compared with the last tick; each
lost point is given back on a roll and the owner is sent the fields (`syncItemFields`, which carries condition, head
condition and sharpness). A weapon that broke (condition 0) is left broken.

Phase 2 (2026-11-07):
- Knifework.SneakRunEndurance: sneaking costs nothing while walking; it makes running cost x1.5
  (`IsoPlayer.updateEndurance`). Its share joins the running give-back while sneaking.
- Conditioning.Recovery: the same per-tick compare adds the bonus share to every endurance rise (vanilla recovers
  standing, sitting and, at a quarter of that, walking: `IsoPlayer.updateEndurance` ~3340).
- Conditioning.MuscleStrain: every kind of muscle strain is stiffness on a body part (`BodyPart.addStiffness` /
  `setStiffness`): combat (`addCombatMuscleStrain`: arms, hands, the right leg for stomps), climbing walls and ropes
  (both arms), back strain (Heavy Load 3+, farming work), neck, and exercise soreness (`Fitness.increasePain`, +2.5
  on arms / legs some hours after a workout). Each tick a share of every rise on every body part is given back here
  (hands and arms only until 2026-11-08). Multiplayer (traced 2026-11-08): the server's copy is the only one that
  lasts. Stiffness travels server -> owner in PlayerDamage (`BodyDamage.save`, every 2 s), which overwrites the
  client's body; nothing sends a client's stiffness to the server. A swing's strain is added on the server
  (`CombatManager.attackCollisionCheck` ~713: a client sends AttackCollisionCheck, whose `processServer` runs
  `addCombatMuscleStrain`), as are tree chopping and bush clearing (`animEvent` behind `not isClient()` /
  `isServer()`, emulated events), farming `complete`s, Heavy Load back strain and exercise soreness (BodyDamage /
  Fitness updates). Strain vanilla adds only in a client-side `update` or client-only anim event (handcraft
  `ISHandcraftAction:update`, `ISShovelAction` / `ISFillGrave` `update`, sledgehammer and pickaxe hits) shows on
  that client for up to 2 s and is then overwritten in vanilla MP too, so there is nothing for this to soften.
- Wear undo now covers the items in both hands and every worn item: a weapon mastery's chance on its own weapon
  category (primary hand), plus the craftsman's mark of any marked item (modData `TSM_Mark`, percent, set when a
  Handicraft master made it; it belongs to the item, whoever uses it). The two chances combine:
  1 - (1 - a)(1 - b).
- Homesteading.AnimalStress: every second, animals within 10 tiles of a master give back the share of each stress
  rise (`getStress` / `setDebugStress`; stress reaches clients in AnimalPacket). All rises near the master count,
  whatever caused them (the cause is Java with no event).
- FieldMedicine.CrashSafety: `BaseVehicle.damagePlayers` (~9390, server / single player, skipped without sandbox
  PlayerDamageFromCrash) hurts each occupant, then fires `OnPlayerGetDamage(chr, "CARCRASHDAMAGE", damage)` before
  the server sends PlayerDamage. Each tick the body of every occupant of a car with a Field Medicine master on board
  is noted (part health, deep wound, fracture, glass); in the event each part gets the share of its health loss back
  and each new deep wound, fracture or glass is taken back on its own roll of the share.
]]

if isClient() then return end

require "TienSkillMastery"
require "TienSkillMastery_HeavyLoad"
local M = TienSkillMastery

-- ---------------------------------------------------------------------------------------------------------------
-- Endurance give-back
-- ---------------------------------------------------------------------------------------------------------------

local lastEndurance = {}   -- [player object] = value after our last change

local function enduranceShare(player)
    local share = M.val(player, "Conditioning.Endurance")
    if player:isRunning() or player:isSprinting() then
        share = share + M.val(player, "Freerunning.RunEndurance")
        if player:isSneaking() then share = share + M.val(player, "Knifework.SneakRunEndurance") end
    else
        local mastery = M.weaponMastery(player:getPrimaryHandItem())
        if mastery and mastery ~= "Firearms" then share = share + M.val(player, mastery .. ".SwingEndurance") end
    end
    return math.min(share, 60) / 100
end

-- Conditioning's signature (Heavy Load one level lower) is no longer given back here: the max weight is shifted so
-- the moodle itself is one level lower (shared/TienSkillMastery_HeavyLoad.lua, applied in updateMaxWeight below).

local function updateEndurance(player)
    local stats = player:getStats()
    local now = stats:get(CharacterStat.ENDURANCE)
    local prev = lastEndurance[player]
    if prev and now < prev then
        local share = enduranceShare(player)
        if share > 0 then
            now = math.min(prev, prev - (prev - now) * (1 - share))
            stats:set(CharacterStat.ENDURANCE, now)
            now = stats:get(CharacterStat.ENDURANCE)
        end
    elseif prev and now > prev then
        local bonus = M.val(player, "Conditioning.Recovery") / 100
        if bonus > 0 then
            stats:set(CharacterStat.ENDURANCE, now + (now - prev) * bonus)
            now = stats:get(CharacterStat.ENDURANCE)
        end
    end
    lastEndurance[player] = now
end

-- ---------------------------------------------------------------------------------------------------------------
-- Carry weight
-- ---------------------------------------------------------------------------------------------------------------

local addedDelta = {}     -- [player object] = delta this file added
local originalDelta = {}  -- [player object] = delta before anything was added
local writtenDelta = {}   -- [player object] = delta as Java stored our last write

--- Conditioning.CarryWeight, plus Conditioning's signature: the max weight raised just enough that Heavy Load is one
--- level lower (shared/TienSkillMastery_HeavyLoad.lua). Both go on `maxWeightDelta`; the shifted max is reached as
--- int(base x delta) with delta = (max + 0.5) / base.
--- The delta is a Java float, so "current - added" is not the original: float(1.275) - 0.275 = 0.99999998, and
--- int(20 x that) = 19 (found 2026-11-09). The original is kept instead, and worked out again only when something
--- else changed the delta.
local function updateMaxWeight(player)
    local HL = M.HeavyLoad
    local had = addedDelta[player] or 0
    local current = player:getMaxWeightDelta()
    if originalDelta[player] == nil or current ~= writtenDelta[player] then
        originalDelta[player] = current - had
    end
    local vanillaDelta = originalDelta[player]
    local carry, real, target, base = HL.compute(player, vanillaDelta)
    HL.realMax[player] = real
    local want = carry
    if target and base and base > 0 and target ~= real then
        want = (target + 0.5) / base - vanillaDelta
    end
    if math.abs(want - had) < 0.00001 then return end
    player:setMaxWeightDelta(vanillaDelta + want)
    addedDelta[player] = want
    writtenDelta[player] = player:getMaxWeightDelta()
end

-- ---------------------------------------------------------------------------------------------------------------
-- Weapon wear undo
-- ---------------------------------------------------------------------------------------------------------------

local lastItems = {}   -- [player object] = { [item ID] = { condition, sharpness, head } }

local function readItem(item)
    local s = { condition = item:getCondition() }
    if item:hasSharpness() then s.sharpness = item:getSharpness() end
    if item:hasHeadCondition() then s.head = item:getHeadCondition() end
    return s
end

local function rollPoints(chance, lost)
    local back = 0
    for _ = 1, lost do
        if ZombRandFloat(0, 100) < chance then back = back + 1 end
    end
    return back
end

--- Undo chances in percent for this item now: the weapon mastery's (primary hand only) combined with the item's mark,
--- for the overall condition and for the head (head condition and sharpness); see `M.markChance`.
local function undoChances(player, item, primary)
    local a = 0
    if primary then
        local mastery = M.weaponMastery(item)
        if mastery then a = M.val(player, mastery .. ".WearUndo") end
    end
    local function combine(b) return 100 * (1 - (1 - a / 100) * (1 - b / 100)) end
    return combine(M.markChance(item, "condition")), combine(M.markChance(item, "head"))
end

local function undoWear(item, prev, now, chance, headChance)
    local changed = false
    if chance > 0 and now.condition < prev.condition then
        local back = rollPoints(chance, prev.condition - now.condition)
        if back > 0 then
            item:setCondition(math.min(prev.condition, now.condition + back), false)
            changed = true
        end
    end
    if headChance > 0 and prev.head and now.head and now.head < prev.head and now.head > 0 then
        local back = rollPoints(headChance, prev.head - now.head)
        if back > 0 then
            item:setHeadCondition(math.min(prev.head, now.head + back))
            changed = true
        end
    end
    if headChance > 0 and prev.sharpness and now.sharpness and now.sharpness < prev.sharpness then
        -- Sharpness drops in steps of 1 / conditionMax; each step is one point.
        local step = 1 / math.max(1, item:getConditionMax())
        local lost = math.floor((prev.sharpness - now.sharpness) / step + 0.5)
        local back = rollPoints(headChance, lost)
        if back > 0 then
            item:setSharpness(math.min(prev.sharpness, now.sharpness + back * step))
            changed = true
        end
    end
    return changed
end

--- The items whose wear is watched: both hands (any item), and worn items carrying a mark.
local function watchedItems(player)
    local list = {}
    local primary = player:getPrimaryHandItem()
    if primary then list[#list + 1] = { item = primary, primary = instanceof(primary, "HandWeapon") } end
    local secondary = player:getSecondaryHandItem()
    if secondary and secondary ~= primary and M.hasMark(secondary) then
        list[#list + 1] = { item = secondary }
    end
    local worn = player:getWornItems()
    if worn then
        for i = 0, worn:size() - 1 do
            local w = worn:get(i)
            local item = w and w:getItem()
            if item and M.hasMark(item) and item ~= primary and item ~= secondary then
                list[#list + 1] = { item = item }
            end
        end
    end
    return list
end

local function updateWear(player)
    local prevAll = lastItems[player] or {}
    local nowAll = {}
    for _, w in ipairs(watchedItems(player)) do
        local item = w.item
        local id = item:getID()
        local now = readItem(item)
        local prev = prevAll[id]
        if prev and now.condition > 0 then
            local chance, headChance = undoChances(player, item, w.primary)
            if (chance > 0 or headChance > 0) and undoWear(item, prev, now, chance, headChance) then
                item:syncItemFields()
                now = readItem(item)
            end
        end
        nowAll[id] = now
    end
    lastItems[player] = nowAll
end

-- ---------------------------------------------------------------------------------------------------------------
-- Muscle strain (every body part; hands and arms only until 2026-11-08)
-- ---------------------------------------------------------------------------------------------------------------

local lastStiffness = {}   -- [player object] = { [body part index] = stiffness }

local function updateStrain(player)
    local share = M.val(player, "Conditioning.MuscleStrain") / 100
    if share <= 0 then
        lastStiffness[player] = nil
        return
    end
    local parts = player:getBodyDamage():getBodyParts()
    local prev = lastStiffness[player] or {}
    local now = {}
    for i = 0, parts:size() - 1 do
        local part = parts:get(i)
        local v = part:getStiffness()
        local before = prev[i]
        if before and v > before then
            v = v - (v - before) * share
            part:setStiffness(v)
        end
        now[i] = v
    end
    lastStiffness[player] = now
end

-- ---------------------------------------------------------------------------------------------------------------
-- Animal stress near a Homesteading master (every second)
-- ---------------------------------------------------------------------------------------------------------------

local lastStress = {}   -- [animal] = stress after our last look
local lastAnimalPass = 0
local ANIMAL_RANGE = 10

local function updateAnimals()
    local nowMs = getTimestampMs()
    if nowMs - lastAnimalPass < 1000 then return end
    lastAnimalPass = nowMs
    local masters = {}
    M.eachPlayer(function(p)
        local share = M.val(p, "Homesteading.AnimalStress") / 100
        if share > 0 then masters[#masters + 1] = { p = p, share = share } end
    end)
    if #masters == 0 then
        lastStress = {}
        return
    end
    local animals = getCell() and getCell():getAnimals()
    if not animals then return end
    local seen = {}
    for i = 0, animals:size() - 1 do
        local a = animals:get(i)
        if a and not a:isDead() then
            local share = 0
            for _, m in ipairs(masters) do
                if math.abs(a:getZ() - m.p:getZ()) < 1 and a:DistToProper(m.p) <= ANIMAL_RANGE then
                    share = math.max(share, m.share)
                end
            end
            if share > 0 then
                local stress = a:getStress()
                local before = lastStress[a]
                if before and stress > before then
                    stress = stress - (stress - before) * share
                    a:setDebugStress(stress)
                end
                seen[a] = a:getStress()
            end
        end
    end
    lastStress = seen
end

-- ---------------------------------------------------------------------------------------------------------------
-- Crash safety
-- ---------------------------------------------------------------------------------------------------------------

local crashNotes = {}   -- [occupant] = { tick, share, parts = { [index] = { health, deep, fracture, glass } } }
local tickNo = 0

local function noteBody(chr)
    local parts = {}
    local list = chr:getBodyDamage():getBodyParts()
    for i = 0, list:size() - 1 do
        local part = list:get(i)
        parts[i] = { health = part:getHealth(), deep = part:isDeepWounded(), fracture = part:getFractureTime(),
            glass = part:haveGlass() }
    end
    return parts
end

local function noteCrash(player)
    local vehicle = player:getVehicle()
    if not vehicle then return end
    local share = M.val(player, "FieldMedicine.CrashSafety") / 100
    if share <= 0 then return end
    for seat = 0, vehicle:getMaxPassengers() - 1 do
        local chr = vehicle:getCharacter(seat)
        if chr and instanceof(chr, "IsoPlayer") then
            local note = crashNotes[chr]
            if not note or note.tick ~= tickNo then
                crashNotes[chr] = { tick = tickNo, share = share, parts = noteBody(chr) }
            else
                note.share = math.max(note.share, share)
            end
        end
    end
end

local function onPlayerGetDamage(chr, damageType, damage)
    if damageType ~= "CARCRASHDAMAGE" or not chr then return end
    local note = crashNotes[chr]
    if not note or tickNo - note.tick > 1 then return end
    local share = note.share
    local list = chr:getBodyDamage():getBodyParts()
    for i = 0, list:size() - 1 do
        local part, before = list:get(i), note.parts[i]
        if before then
            local health = part:getHealth()
            if health < before.health then
                part:SetHealth(math.min(before.health, health + (before.health - health) * share))
            end
            if part:isDeepWounded() and not before.deep and ZombRandFloat(0, 1) < share then
                part:setDeepWounded(false)
                part:setDeepWoundTime(0)
            end
            if part:getFractureTime() > 0 and before.fracture <= 0 and ZombRandFloat(0, 1) < share then
                part:setFractureTime(0)
            end
            if part:haveGlass() and not before.glass and ZombRandFloat(0, 1) < share then
                part:setHaveGlass(false)
            end
        end
    end
    -- The next crash in the same tick counts from here.
    note.parts = noteBody(chr)
end
Events.OnPlayerGetDamage.Add(onPlayerGetDamage)
Events.OnTick.Add(function() tickNo = tickNo + 1 end)

-- ---------------------------------------------------------------------------------------------------------------

local function onTick()
    M.eachPlayer(function(player)
        updateEndurance(player)
        updateWear(player)
        updateMaxWeight(player)
        updateStrain(player)
        noteCrash(player)
    end)
    updateAnimals()
end
Events.OnTick.Add(onTick)

-- Player objects are rebuilt on relog and respawn; drop the old keys now and then.
local function cleanUp()
    local alive = {}
    M.eachPlayer(function(p) alive[p] = true end)
    for _, t in ipairs({ lastEndurance, addedDelta, originalDelta, writtenDelta, lastItems, lastStiffness, crashNotes }) do
        for k in pairs(t) do
            if not alive[k] then t[k] = nil end
        end
    end
end
Events.EveryHours.Add(cleanUp)
