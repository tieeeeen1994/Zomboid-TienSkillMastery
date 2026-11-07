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
(floor), and what this file added is remembered per player object so it is taken back before a new amount goes on.
The owner gets `maxWeight` with PlayerDamage (every 2 s).

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
- Conditioning.MuscleStrain: combat strain is `addCombatMuscleStrain` -> `addStiffness` on hands and arms (melee,
  recoil, tree chopping). Each tick a share of every rise in those parts' `getStiffness()` is given back here. In
  multiplayer the strain from a swing is added on the attacker's client (combat runs there) and from chopping on the
  server; how a client's strain reaches the server was not traced, so only what the server's copy shows is softened.
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

-- Conditioning's signature, Heavy Load one moodle level lower (42.21 `IsoPlayer.updateEndurance` ~3216): running /
-- sprinting drain x 1.5 / 1.9 / 2.3 / 2.8 at levels 1-4, so the drop is scaled by the next lower factor over this
-- one; walking drains from level 3 (x 1.9 at 3, 2.3 at 4, halved), so level 3 gives the walking drop back whole
-- (level 2 has none) and level 4 scales it by 1.9 / 2.3; recovery (standing still, and a quarter of it walking) stops
-- from level 2, so at level 2 vanilla's own regen is added here. Movement speed stays vanilla (root motion, Java).
local RUN_FACTOR = { [0] = 1, 1.5, 1.9, 2.3, 2.8 }

local function heavyLevel(player)
    if not M.sig(player, "Conditioning.SigHeavyLoad") then return 0 end
    return math.min(4, player:getMoodles():getMoodleLevel(MoodleType.HEAVY_LOAD))
end

--- Share of a drop that one level lower would not have cost.
local function heavyDropFactor(player, level)
    if level <= 0 then return 1 end
    if player:isRunning() or player:isSprinting() then
        return RUN_FACTOR[level - 1] / RUN_FACTOR[level]
    end
    if player:isPlayerMoving() then
        if level == 3 then return 0 end
        if level == 4 then return 1.9 / 2.3 end
    end
    return 1
end

--- Vanilla's regen for one update, which level 2 blocks (standing still; a quarter while walking).
local function heavyRegen(player)
    local ok, v = pcall(function()
        local stats = player:getStats()
        local base = ZomboidGlobals.imobileEnduranceReduce * getSandboxOptions():getEnduranceRegenMultiplier()
            * player:getRecoveryMod() * getGameTime():getMultiplier()
        if not player:isPlayerMoving() then
            return base * (1 - stats:get(CharacterStat.FATIGUE) * 0.85)
        elseif not player:isRunning() and not player:isSprinting()
            and player:getMoodles():getMoodleLevel(MoodleType.ENDURANCE) < 2 then
            return base / 4 * (1 - stats:get(CharacterStat.FATIGUE))
        end
        return 0
    end)
    return ok and v or 0
end

local function updateEndurance(player)
    local stats = player:getStats()
    local now = stats:get(CharacterStat.ENDURANCE)
    local prev = lastEndurance[player]
    local heavy = heavyLevel(player)
    if heavy == 2 and not player:isSitting() then
        stats:set(CharacterStat.ENDURANCE, now + heavyRegen(player))
        now = stats:get(CharacterStat.ENDURANCE)
    end
    if prev and now < prev then
        local share = enduranceShare(player)
        local factor = heavyDropFactor(player, heavy)
        if share > 0 or factor < 1 then
            now = math.min(prev, prev - (prev - now) * factor * (1 - share))
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

local addedDelta = {}   -- [player object] = delta this file added

local function updateCarryWeight(player)
    local kg = math.floor(M.val(player, "Conditioning.CarryWeight") + 0.0001)
    local base = player:getMaxWeightBase() * player:getWeightMod()
    local want = 0
    if kg > 0 and base > 0 then want = (kg + 0.05) / base end
    local had = addedDelta[player] or 0
    if math.abs(want - had) < 0.00001 then return end
    player:setMaxWeightDelta(player:getMaxWeightDelta() - had + want)
    addedDelta[player] = want
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

--- Undo chance in percent for this item now: the weapon mastery's (primary hand only) and the item's mark combined.
local function undoChance(player, item, primary)
    local a = 0
    if primary then
        local mastery = M.weaponMastery(item)
        if mastery then a = M.val(player, mastery .. ".WearUndo") end
    end
    local b = tonumber(item:getModData().TSM_Mark) or 0
    if a <= 0 and b <= 0 then return 0 end
    return 100 * (1 - (1 - a / 100) * (1 - math.min(100, b) / 100))
end

local function undoWear(item, prev, now, chance)
    local changed = false
    if now.condition < prev.condition then
        local back = rollPoints(chance, prev.condition - now.condition)
        if back > 0 then
            item:setCondition(math.min(prev.condition, now.condition + back), false)
            changed = true
        end
    end
    if prev.head and now.head and now.head < prev.head and now.head > 0 then
        local back = rollPoints(chance, prev.head - now.head)
        if back > 0 then
            item:setHeadCondition(math.min(prev.head, now.head + back))
            changed = true
        end
    end
    if prev.sharpness and now.sharpness and now.sharpness < prev.sharpness then
        -- Sharpness drops in steps of 1 / conditionMax; each step is one point.
        local step = 1 / math.max(1, item:getConditionMax())
        local lost = math.floor((prev.sharpness - now.sharpness) / step + 0.5)
        local back = rollPoints(chance, lost)
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
    if secondary and secondary ~= primary and secondary:getModData().TSM_Mark then
        list[#list + 1] = { item = secondary }
    end
    local worn = player:getWornItems()
    if worn then
        for i = 0, worn:size() - 1 do
            local w = worn:get(i)
            local item = w and w:getItem()
            if item and item:getModData().TSM_Mark and item ~= primary and item ~= secondary then
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
            local chance = undoChance(player, item, w.primary)
            if chance > 0 and undoWear(item, prev, now, chance) then
                item:syncItemFields()
                now = readItem(item)
            end
        end
        nowAll[id] = now
    end
    lastItems[player] = nowAll
end

-- ---------------------------------------------------------------------------------------------------------------
-- Muscle strain (hands and arms)
-- ---------------------------------------------------------------------------------------------------------------

local STRAIN_PARTS = { "Hand_L", "Hand_R", "ForeArm_L", "ForeArm_R", "UpperArm_L", "UpperArm_R" }
local lastStiffness = {}   -- [player object] = { [part name] = stiffness }

local function updateStrain(player)
    local share = M.val(player, "Conditioning.MuscleStrain") / 100
    if share <= 0 then
        lastStiffness[player] = nil
        return
    end
    local body = player:getBodyDamage()
    local prev = lastStiffness[player] or {}
    local now = {}
    for _, name in ipairs(STRAIN_PARTS) do
        local part = body:getBodyPart(BodyPartType[name])
        if part then
            local v = part:getStiffness()
            local before = prev[name]
            if before and v > before then
                v = v - (v - before) * share
                part:setStiffness(v)
            end
            now[name] = v
        end
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
        updateCarryWeight(player)
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
    for _, t in ipairs({ lastEndurance, addedDelta, lastItems, lastStiffness, crashNotes }) do
        for k in pairs(t) do
            if not alive[k] then t[k] = nil end
        end
    end
end
Events.EveryHours.Add(cleanUp)
