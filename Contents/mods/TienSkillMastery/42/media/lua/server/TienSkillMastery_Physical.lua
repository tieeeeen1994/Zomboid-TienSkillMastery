--[[
Tien's Skill Mastery: bonuses the server owns (single player too): endurance, carry weight, weapon wear.

Endurance (Fitness.Endurance, Sprinting.RunEndurance, Axe / Blunt / Spear .SwingEndurance): endurance is a server
stat (`NetworkPlayerManager` sends it to the owner every second), drained in Java with no Lua event: running /
sprinting in `IsoPlayer.updateEndurance`, swings in `CombatManager.processWeaponEndurance` (on the server, from
`AttackCollisionCheckPacket.processServer` / `PlayerHitCharacter`). Each tick the drop since the last tick is
measured per player and a share of it given back: Fitness's share for every drop, plus Sprinting's while running or
sprinting, plus the weapon skill's while standing or walking with an axe, long blunt or spear in hand (how a swing is
told apart: nothing else drains endurance there). Regeneration is left alone.

Carry weight (Strength.CarryWeight, flat): `BodyDamage.Update` (~2066, server / single player) sets `maxWeight` =
int(int(maxWeightBase x getWeightMod() - reducers) x maxWeightDelta) every update, and `maxWeightDelta` (trait
Strong 1.5 / Weak 0.75 / Feeble 0.9 / Stout 1.25, else 1) is only set when the player object is built, never saved,
never touched by vanilla Lua. The bonus is added to the delta as kg / (maxWeightBase x weightMod), whole kg only
(floor), and what this file added is remembered per player object so it is taken back before a new amount goes on.
The owner gets `maxWeight` with PlayerDamage (every 2 s).

Weapon wear (Maintenance.WearUndo, chance per point): condition, sharpness and head condition loss from use is
rolled in `InventoryItem.damageCheck`, from `CombatManager.processMaintenanceCheck` only when not a client, and from
tree chopping on the server. Each tick the primary hand weapon of every player is compared with the last tick; each
lost point is given back on a roll and the owner is sent the fields (`syncItemFields`, which carries condition, head
condition and sharpness). A weapon that broke (condition 0) is left broken.
]]

if isClient() then return end

require "TienSkillMastery"
local M = TienSkillMastery

local HEAVY = { Axe = true, Blunt = true, Spear = true }

local weaponSkill
local function getWeaponSkill(weapon)
    if not weaponSkill then
        local cats = {
            { "AXE", "Axe" }, { "BLUNT", "Blunt" }, { "SMALL_BLUNT", "SmallBlunt" },
            { "LONG_BLADE", "LongBlade" }, { "SMALL_BLADE", "SmallBlade" }, { "SPEAR", "Spear" },
        }
        weaponSkill = function(w)
            local script = w and w:getScriptItem()
            if not script then return nil end
            for _, c in ipairs(cats) do
                local cat = WeaponCategory[c[1]]
                if cat and script:containsWeaponCategory(cat) then return c[2] end
            end
            return nil
        end
    end
    return weaponSkill(weapon)
end

-- ---------------------------------------------------------------------------------------------------------------
-- Endurance give-back
-- ---------------------------------------------------------------------------------------------------------------

local lastEndurance = {}   -- [player object] = value after our last change

local function enduranceShare(player)
    local share = M.val(player, "Fitness.Endurance")
    if player:isRunning() or player:isSprinting() then
        share = share + M.val(player, "Sprinting.RunEndurance")
    else
        local weapon = player:getPrimaryHandItem()
        if weapon and instanceof(weapon, "HandWeapon") and not weapon:isAimedFirearm() then
            local skill = getWeaponSkill(weapon)
            if skill and HEAVY[skill] then share = share + M.val(player, skill .. ".SwingEndurance") end
        end
    end
    return math.min(share, 60) / 100
end

local function updateEndurance(player)
    local stats = player:getStats()
    local now = stats:get(CharacterStat.ENDURANCE)
    local prev = lastEndurance[player]
    if prev and now < prev then
        local share = enduranceShare(player)
        if share > 0 then
            now = math.min(prev, now + (prev - now) * share)
            stats:set(CharacterStat.ENDURANCE, now)
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
    local kg = math.floor(M.val(player, "Strength.CarryWeight") + 0.0001)
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

local lastWeapon = {}   -- [player object] = { id, condition, sharpness, head }

local function readWeapon(weapon)
    local s = { id = weapon:getID(), condition = weapon:getCondition() }
    if weapon:hasSharpness() then s.sharpness = weapon:getSharpness() end
    if weapon:hasHeadCondition() then s.head = weapon:getHeadCondition() end
    return s
end

local function rollPoints(player, lost)
    local back = 0
    for _ = 1, lost do
        if M.roll(player, "Maintenance.WearUndo") then back = back + 1 end
    end
    return back
end

local function updateWear(player)
    local weapon = player:getPrimaryHandItem()
    if not weapon or not instanceof(weapon, "HandWeapon") then
        lastWeapon[player] = nil
        return
    end
    local prev = lastWeapon[player]
    local now = readWeapon(weapon)
    if prev and prev.id == now.id and M.val(player, "Maintenance.WearUndo") > 0 and now.condition > 0 then
        local changed = false
        if now.condition < prev.condition then
            local back = rollPoints(player, prev.condition - now.condition)
            if back > 0 then
                weapon:setCondition(math.min(prev.condition, now.condition + back), false)
                changed = true
            end
        end
        if prev.head and now.head and now.head < prev.head and now.head > 0 then
            local back = rollPoints(player, prev.head - now.head)
            if back > 0 then
                weapon:setHeadCondition(math.min(prev.head, now.head + back))
                changed = true
            end
        end
        if prev.sharpness and now.sharpness and now.sharpness < prev.sharpness then
            -- Sharpness drops in steps of 1 / conditionMax; each step is one point.
            local step = 1 / math.max(1, weapon:getConditionMax())
            local lost = math.floor((prev.sharpness - now.sharpness) / step + 0.5)
            local back = rollPoints(player, lost)
            if back > 0 then
                weapon:setSharpness(math.min(prev.sharpness, now.sharpness + back * step))
                changed = true
            end
        end
        if changed then
            weapon:syncItemFields()
            now = readWeapon(weapon)
        end
    end
    lastWeapon[player] = now
end

-- ---------------------------------------------------------------------------------------------------------------

local function onTick()
    M.eachPlayer(function(player)
        updateEndurance(player)
        updateWear(player)
        updateCarryWeight(player)
    end)
end
Events.OnTick.Add(onTick)

-- Player objects are rebuilt on relog and respawn; drop the old keys now and then.
local function cleanUp()
    local alive = {}
    M.eachPlayer(function(p) alive[p] = true end)
    for _, t in ipairs({ lastEndurance, addedDelta, lastWeapon }) do
        for k in pairs(t) do
            if not alive[k] then t[k] = nil end
        end
    end
end
Events.EveryHours.Add(cleanUp)
