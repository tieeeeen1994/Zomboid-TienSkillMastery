--[[
Tien's Skill Mastery: combat bonuses computed on the attacker's own client (single player too).

Where 42.21 decides each thing (all on the attacking client; in MP the hit packet carries the results):
- Attack speed: `CombatManager.pressedAttack` (~3170) sets `setCombatSpeed(calculateCombatSpeed())` (vanilla: Fitness
  +0.02 and weapon level +0.03 per level, clamped 0.8..1.6, x1.1 on a crit), then `SwipeStatePlayer.enter` (~199)
  fires `OnWeaponSwing(player, weapon)`; the swing anim reads the `CombatSpeed` variable and the hit packet carries it
  (`fields/hit/Player` ~67). So `OnWeaponSwing` multiplies it. Melee only: firearm fire rate uses other variables.
- Melee crit reroll: vanilla rolls the crit in `pressedAttack` (~3254: `Rand.Next(100) < calculateCritChance(the
  closest target)` plus a from-behind extra), before any Lua event, and only when the swing has a target in
  `getHitInfoList()` (filled by `calculateHitInfoList` just before). In `OnWeaponSwing`, a swing that has a target but
  no crit gets, on a roll of the reroll chance, a second roll of vanilla's own crit chance. The target itself cannot be
  read (`HitInfo` is not exposed to Lua), so `calculateCritChance(nil)` is used: its melee branch only tests the target
  with instanceof (PVP strength / weight, zombie toughness); the zombie toughness +-6 is added back from the sandbox,
  clamped 10..90 like vanilla. The from-behind extra is not. Vanilla's exclusions are kept (shove, `NoCriticals` tag,
  knife swings, which only crit on close kills), and vanilla's x1.1 combat speed for a crit is applied with it.
  P(crit) = base + reroll x base.
- `OnWeaponSwingHitPoint(owner, weapon)` (`CombatManager.attackCollisionCheck` ~670) fires before the hit list
  (`calculateHitInfoList`: range = `getMaxRange(owner) x getRangeMod(owner)`), the firearm crit roll (`processHit`
  ~2923 / `hitConsequences`: `calculateCritChance` adds `getCriticalChance()` and `aimingPerkCritModifier x Aiming`),
  the firearm hit chance (`calculateHitChanceData` ~2641: `hitChance + aimingPerkHitChanceModifier x Aiming`) and
  the damage roll (~783: `getMinDamage()` .. `getMaxDamage()`). Knockback is `pushBackMod x knockbackMod x
  shovingMod` (HandWeapon ~2492). So those weapon fields are raised on that weapon instance for the swing and put back
  on the next tick, only where nothing else changed them meanwhile (Gunworks also handles this event). The event
  also fires on the server for firearm hits (`fields/hit/Player` ~168); this file is client only and acts for local
  players only.
- Anti-cheats on the server (42.21): `AntiCheatHitWeapon` refuses a hit farther than the server copy's
  `getMaxRange()` + 5 tiles, `AntiCheatHitDamage` one over 100 damage. Firearm range is raised by at most what stays
  4.5 tiles inside that; melee reach is tiny.
- Aim-in: `updateAimingDelay` (IsoGameCharacter ~11052) drains `0.625 x multiplier x (1 + 0.05 x Aiming + Marksman
  0.1)` per update while aiming with the recoil settled; it runs after `OnPlayerUpdate` in the same update. The drain
  seen since the last update is extended by the bonus with `setAimingDelay`.
- Nimble strafe: `calculateWalkSpeed` (IsoGameCharacter ~9832, server / single player only) sets the anim variable
  `StrafeSpeed` = max(min(0.9 + Nimble / 10, 1.5) x min(walk-or-run speed x 2.5, 1), 0.48) x 0.8 while aiming. An MP
  client gets it only through `PlayerInjuriesPacket` (every 2 s), so it lags and can read the default 1.0 on the first
  aim after login. The owner's client recomputes it every update from its `WalkSpeed` variable (set from the server's
  walk / run speed, `IsoPlayer.calculateWalkSpeed` ~3754), times the bonus; remote copies take it from the strafe
  state's parameters. All of this only while the setting NimbleStrafe is on (default; M.SETTINGS); off, multiplayer
  matches single player. Single player: vanilla rewrites the variable later in the same update, right before the
  animator reads it (`postupdate`), with no Lua event in between, so the strafe bonus does not reach single player.
]]

if isServer() then return end

require "TienSkillMastery"
local M = TienSkillMastery

local CATEGORY = {
    { cat = "AXE", perk = "Axe" },
    { cat = "BLUNT", perk = "Blunt" },
    { cat = "SMALL_BLUNT", perk = "SmallBlunt" },
    { cat = "LONG_BLADE", perk = "LongBlade" },
    { cat = "SMALL_BLADE", perk = "SmallBlade" },
    { cat = "SPEAR", perk = "Spear" },
}

--- The melee skill of a weapon, as vanilla's damage tables pick it.
local function weaponSkill(weapon)
    local script = weapon and weapon:getScriptItem()
    if not script then return nil end
    for _, c in ipairs(CATEGORY) do
        local cat = WeaponCategory[c.cat]
        if cat and script:containsWeaponCategory(cat) then return c.perk end
    end
    return nil
end
M.weaponSkill = weaponSkill

local function isFirearm(weapon)
    return weapon and weapon:isAimedFirearm()
end

-- ---------------------------------------------------------------------------------------------------------------
-- OnWeaponSwing: attack speed and the melee crit roll
-- ---------------------------------------------------------------------------------------------------------------

--- True when pressedAttack found something to hit (vanilla rolls a crit only then).
local function hasTarget(player)
    local list = player:getHitInfoList()
    return list ~= nil and not list:isEmpty()
end

--- Vanilla's melee crit chance without the target: calculateCritChance(nil), plus zombie toughness.
local function meleeCritChance(player)
    local chance = player:calculateCritChance(nil)
    local lore = SandboxVars and SandboxVars.ZombieLore
    local toughness = lore and lore.Toughness
    if toughness == 1 then chance = chance - 6 elseif toughness == 3 then chance = chance + 6 end
    return math.max(10, math.min(90, chance))
end

local function onWeaponSwing(player, weapon)
    if not player or not player:isLocalPlayer() or not weapon or isFirearm(weapon) then return end
    local skill = weaponSkill(weapon)
    local speed = M.val(player, "Fitness.AttackSpeed")
    if skill then speed = speed + M.val(player, skill .. ".AttackSpeed") end

    if skill and not player:isDoShove() and not player:isCriticalHit() then
        local reroll = M.val(player, skill .. ".CritReroll")
        if reroll > 0 and ZombRandFloat(0, 100) < reroll and hasTarget(player)
            and not weapon:hasTag(ItemTag.NO_CRITICALS) and WeaponType.getWeaponType(player) ~= WeaponType.KNIFE
            and ZombRand(100) < meleeCritChance(player) then
            player:setCriticalHit(true)
            player:setCombatSpeed(player:getCombatSpeed() * 1.1)
        end
    end

    if speed > 0 then
        player:setCombatSpeed(player:getCombatSpeed() * (1 + speed / 100))
    end
end
Events.OnWeaponSwing.Add(onWeaponSwing)

-- ---------------------------------------------------------------------------------------------------------------
-- OnWeaponSwingHitPoint: per-swing weapon boosts, put back next tick
-- ---------------------------------------------------------------------------------------------------------------

-- Max damage has no plain getter: getMaxDamage() = (raw - min) x sharpness multiplier + min for a sharp weapon
-- whose raw max is above its min (InventoryItem.getSharpnessMultiplier = (sharpness + 1) / 2), else raw.
local function getRawMaxDamage(weapon)
    local shown = weapon:getMaxDamage()
    local min = weapon:getMinDamage()
    if weapon:hasSharpness() and shown > min then
        local s = weapon:getSharpnessMultiplier()
        if s > 0 then return (shown - min) / s + min end
    end
    return shown
end

-- Each field: how to read and write the raw value.
local FIELDS = {
    minDamage = { get = function(w) return w:getMinDamage() end, set = function(w, v) w:setMinDamage(v) end },
    maxDamage = { get = getRawMaxDamage, set = function(w, v) w:setMaxDamage(v) end },
    pushBack = { get = function(w) return w:getPushBackMod() end, set = function(w, v) w:setPushBackMod(v) end },
    maxRange = { get = function(w) return w:getMaxRange() end, set = function(w, v) w:setMaxRange(v) end },
    crit = { get = function(w) return w:getCriticalChance() end, set = function(w, v) w:setCriticalChance(v) end },
    aimHit = {
        get = function(w) return w:getAimingPerkHitChanceModifier() end,
        set = function(w, v) w:setAimingPerkHitChanceModifier(v) end,
    },
}

local pending = {}   -- { weapon = w, changes = { { field, before, after } } }

local function change(entry, name, value)
    local f = FIELDS[name]
    local w = entry.weapon
    local before = f.get(w)
    if math.abs(value - before) < 0.00001 then return end
    f.set(w, value)
    table.insert(entry.changes, { field = f, before = before, after = f.get(w) })
end

local function restoreAll()
    for i = #pending, 1, -1 do
        local entry = pending[i]
        for j = #entry.changes, 1, -1 do
            local c = entry.changes[j]
            -- Only undo what is still ours: another mod may have set the field since.
            if math.abs(c.field.get(entry.weapon) - c.after) < 0.0001 then
                c.field.set(entry.weapon, c.before)
            end
        end
        pending[i] = nil
    end
end

local function onHitPoint(owner, weapon)
    if not owner or not instanceof(owner, "IsoPlayer") or not owner:isLocalPlayer() or not weapon then return end
    restoreAll()
    local entry = { weapon = weapon, changes = {} }

    if isFirearm(weapon) then
        local aiming = owner:getPerkLevel(Perks.Aiming)
        local hit = M.val(owner, "Aiming.HitChance")
        if hit > 0 and aiming > 0 then
            change(entry, "aimHit", weapon:getAimingPerkHitChanceModifier() + hit / aiming)
        end
        local crit = M.val(owner, "Aiming.Crit")
        if crit > 0 then
            change(entry, "crit", weapon:getCriticalChance() + crit)
        end
        local range = M.val(owner, "Aiming.Range")
        if range > 0 then
            local full = weapon:getMaxRange(owner)
            local room = weapon:getMaxRange() + 4.5 - full
            local add = math.min(full * range / 100, math.max(0, room))
            if add > 0 then change(entry, "maxRange", weapon:getMaxRange() + add) end
        end
    else
        local skill = weaponSkill(weapon)
        local dmg = M.val(owner, "Strength.Damage")
        local knock = M.val(owner, "Strength.Knockback")
        if skill then
            dmg = dmg + M.val(owner, skill .. ".Damage")
            if skill == "Axe" then knock = knock + M.val(owner, "Axe.Knockback") end
            if M.defs[skill .. ".Reach"] then
                local reach = M.val(owner, skill .. ".Reach")
                if reach > 0 then change(entry, "maxRange", weapon:getMaxRange() * (1 + reach / 100)) end
            end
        end
        if dmg > 0 then
            local f = 1 + dmg / 100
            -- Raw max first: it is derived from the current min.
            change(entry, "maxDamage", getRawMaxDamage(weapon) * f)
            change(entry, "minDamage", weapon:getMinDamage() * f)
        end
        if knock > 0 then
            change(entry, "pushBack", weapon:getPushBackMod() * (1 + knock / 100))
        end
    end

    if #entry.changes > 0 then table.insert(pending, entry) end
end
Events.OnWeaponSwingHitPoint.Add(onHitPoint)
Events.OnTick.Add(function()
    if #pending > 0 then restoreAll() end
end)

-- ---------------------------------------------------------------------------------------------------------------
-- OnPlayerUpdate: aim-in speed and Nimble strafe speed (owner only)
-- ---------------------------------------------------------------------------------------------------------------

local lastDelay = {}

local function onPlayerUpdate(player)
    if not player or not player:isLocalPlayer() then return end
    local num = player:getPlayerNum()
    local aiming = player:isAiming()

    -- Aim-in speed: extend whatever vanilla drained since our last look.
    local weapon = player:getPrimaryHandItem()
    if aiming and weapon and instanceof(weapon, "HandWeapon") and weapon:isAimedFirearm() then
        local now = player:getAimingDelay()
        local prev = lastDelay[num]
        local bonus = M.val(player, "Aiming.AimSpeed")
        if prev and now < prev and now > 0 and bonus > 0 then
            now = math.max(0, now - (prev - now) * bonus / 100)
            player:setAimingDelay(now)
        end
        lastDelay[num] = now
    else
        lastDelay[num] = nil
    end

    -- Strafe speed (MP client only, see the header). Setting NimbleStrafe (on by default); off, the
    -- variable is left to vanilla, as in single player (no bonus, and the 2 s lag stays).
    if aiming and isClient() and M.option("NimbleStrafe", true) == true then
        local nimble = player:getPerkLevel(Perks.Nimble)
        local walk = player:getVariableFloat("WalkSpeed", 0)
        local strafe = math.min(0.9 + nimble / 10, 1.5) * math.min(walk * 2.5, 1)
        strafe = math.max(strafe, 0.48) * 0.8
        strafe = strafe * M.more(player, "Nimble.StrafeSpeed")
        player:setVariable("StrafeSpeed", strafe)
    end
end
Events.OnPlayerUpdate.Add(onPlayerUpdate)
