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
- Which mastery: the weapon's (M.weaponMastery: the melee category's mastery, or Firearms for an aimed firearm).
  Effects that a mastery does not define read 0 (Knifework has no crit reroll, Street Fighting no reach).
- Bludgeoning's extra targets (sandbox MultiHitZombies on): `calculateHitInfoList` caps a melee hit list at the
  weapon's `getMaxHitCount()` and builds the list that deals damage after `OnWeaponSwingHitPoint`, so the count is
  raised for the swing like the other fields. Each further target takes less damage (vanilla's split). With the
  option off the count is forced to 1, so the mastery gives reach instead (both steps at mastery 5 and 10).
- v1's Nimble strafe variable (MP only) is gone: Swordsmanship's strafe speed is a position nudge
  (client/TienSkillMastery_Movement.lua).

Phase 2 (2026-11-07):
- Fire rate (Firearms.FireRate). Vanilla: semi-auto waits for the character's recoil delay
  (`HandWeapon.getRecoilDelay(owner)`, set in `pressedAttack` ~3209) and plays at the `singleShootSpeed` variable;
  full auto at `autoShootSpeed`; both variables are set in `SwipeStatePlayer.enter` right before `OnWeaponSwing`,
  which scales them. The recoil delay drains 0.625 x multiplier per update (`IsoGameCharacter` ~8644, after
  `OnPlayerUpdate`), so the extra share is drained there like aim-in. Anti-cheat (`AntiCheatHitWeapon.isRateExceeded`):
  single-fire hits must average 150 ms or more, so the extra drain never lets a shot come sooner than 150 ms after
  the last one. Gunworks guns (`RateOfFire.IsWeaponRegistered`) are gated by Gunworks' own RPM interval instead
  (`RateOfFire.canFire`, which also hands its interval to bursts): while `canFire` runs for a local master, its
  `getWeaponRPM` lookup returns the RPM x (1 + bonus), never pushing an interval of 150 ms or more under 150 ms.
- Knifework's attack speed also drains the melee delay faster (`setMeleeDelay`, the stab's `SetMeleeDelay` 8 at
  its end, drained at the same rate as the recoil delay): CombatSpeed alone gives only about two thirds of it.
- Stomp (StreetFighting.StompDamage, any weapon): `CombatManager` ~1043 computes stomp damage after this event as
  rand(0.7, 1) + Strength x 0.2, x the worn shoes' `getStompPower()`; the shoes' stomp power is raised for the swing
  like the weapon fields.
- Executioner (Knifework): vanilla's close kill (a jaw stab) needs the target nearer than the knife's
  `getMinRange()`, at most one chasing zombie and a crit, which vanilla rolls in `pressedAttack` (certain from behind
  on an unaware zombie) before `OnWeaponSwing`. `AttackVars.closeKill` has no getter, so the close kill is found
  the same way: a standing zombie in front within the min range and `getNumChasingZombies() <= 1`; then a roll makes
  the swing a crit. Setting it in `OnWeaponSwing` is before the swing anim is chosen (v1's crit reroll relies on it).
- Shove damage (StreetFighting.ShoveDamage) and Ambush (Knifework.Ambush, a zombie whose target is not the attacker)
  go through `OnWeaponHitCharacter` to the zombie's owner (shared/TienSkillMastery_Relay.lua).
]]

if isServer() then return end

require "TienSkillMastery"
require "TienSkillMastery_Relay"
local M = TienSkillMastery

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

local lastShot = {}   -- [player num] = getTimestampMs() of the last firearm swing
local startLunge      -- defined with the lunge below

local function isGunworksGun(weapon)
    return RateOfFire ~= nil and type(RateOfFire.IsWeaponRegistered) == "function"
        and RateOfFire.IsWeaponRegistered(weapon) == true
end

--- A standing zombie in front, nearer than the knife's min range (vanilla's close-kill distance).
local function closeKillTarget(player, weapon)
    local list = getCell() and getCell():getZombieList()
    if not list then return nil end
    local range = weapon:getMinRange()
    local px, py = player:getX(), player:getY()
    local fx, fy = player:getForwardDirectionX(), player:getForwardDirectionY()
    for i = 0, list:size() - 1 do
        local z = list:get(i)
        if z and not z:isDead() and not z:isOnFloor() and math.abs(z:getZ() - player:getZ()) < 0.5 then
            local dx, dy = z:getX() - px, z:getY() - py
            local d2 = dx * dx + dy * dy
            if d2 < range * range and d2 > 0.0001 then
                local d = math.sqrt(d2)
                if (dx * fx + dy * fy) / d > 0.5 then return z end
            end
        end
    end
    return nil
end

-- ---------------------------------------------------------------------------------------------------------------
-- Knifework's signature, the lunge (phase 3a). A jaw stab (close kill, `calculateAttackVars` ~1400) needs the target
-- nearer than the knife's `getMinRange()` (stabbing knives 0.61) with at most one chasing zombie; with more chasers
-- the same distance gives a shove, so the window only widens while `getNumChasingZombies() <= 1` (last frame's
-- count). `HandWeapon.setMinRange` works per instance and is not saved (`HandWeapon.save` does not write it); the
-- vanilla value is remembered per item ID and put back as soon as the conditions end or the knife leaves the hand.
-- No new animation: when a stab starts at a target beyond vanilla's distance, the player is eased toward it during
-- the next ~0.25 s until ~0.55 tiles away (at most ~0.35 tiles), only over squares `isBlockedTo` does not refuse.
-- MP: the client owns its position; this is walking pace for the Speed anti-cheat.
-- ---------------------------------------------------------------------------------------------------------------

local knifeBase = {}    -- [player num] = { weapon, id, base }
local lunges = {}       -- [player num] = { target, untilMs }
local LUNGE_STOP = 0.55

local function isStabbingKnife(player, weapon)
    return weapon and M.weaponMastery(weapon) == "Knifework" and WeaponType.getWeaponType(player) == WeaponType.KNIFE
end

local function restoreKnife(num)
    local k = knifeBase[num]
    if k and k.weapon and math.abs(k.weapon:getMinRange() - k.widened) < 0.0001 then
        k.weapon:setMinRange(k.base)
    end
    knifeBase[num] = nil
end

local function updateKnifeWindow(player)
    local num = player:getPlayerNum()
    local weapon = player:getPrimaryHandItem()
    local k = knifeBase[num]
    local want = weapon and instanceof(weapon, "HandWeapon") and isStabbingKnife(player, weapon)
        and player:getStats():getNumChasingZombies() <= 1 and M.val(player, "Knifework.SigLunge") or 0
    if k and (want <= 0 or k.weapon ~= weapon) then
        restoreKnife(num)
        k = nil
    end
    if want > 0 and not k then
        local base = weapon:getMinRange()
        local widened = base * (1 + want / 100)
        weapon:setMinRange(widened)
        knifeBase[num] = { weapon = weapon, base = base, widened = weapon:getMinRange() }
    end
end

local function canStep(from, to)
    if not from or not to then return false end
    if from == to then return true end
    local dx, dy = to:getX() - from:getX(), to:getY() - from:getY()
    if math.abs(dx) + math.abs(dy) ~= 1 or to:getZ() ~= from:getZ() then return false end
    return not from:isBlockedTo(to) and to:isFree(false)
end

startLunge = function(player, weapon)
    local k = knifeBase[player:getPlayerNum()]
    if not k or player:isDoShove() then return end
    local target = closeKillTarget(player, weapon)
    if not target then return end
    local dx, dy = target:getX() - player:getX(), target:getY() - player:getY()
    if math.sqrt(dx * dx + dy * dy) <= k.base then return end
    lunges[player:getPlayerNum()] = { target = target, untilMs = getTimestampMs() + 250 }
end

local function updateLunge(player)
    local num = player:getPlayerNum()
    local l = lunges[num]
    if not l then return end
    local target = l.target
    if getTimestampMs() > l.untilMs or not target or target:isDead() then
        lunges[num] = nil
        return
    end
    local dx, dy = target:getX() - player:getX(), target:getY() - player:getY()
    local d = math.sqrt(dx * dx + dy * dy)
    if d <= LUNGE_STOP then
        lunges[num] = nil
        return
    end
    local step = math.min((d - LUNGE_STOP) * 0.4, 0.06)
    local nx, ny = player:getX() + dx / d * step, player:getY() + dy / d * step
    local to = getCell():getGridSquare(math.floor(nx), math.floor(ny), math.floor(player:getZ()))
    if not canStep(player:getCurrentSquare(), to) then
        lunges[num] = nil
        return
    end
    player:setX(nx)
    player:setY(ny)
end

local function onFirearmSwing(player, weapon)
    lastShot[player:getPlayerNum()] = getTimestampMs()
    local rate = M.val(player, "Firearms.FireRate")
    if rate <= 0 then return end
    local f = 1 + rate / 100
    for _, var in ipairs({ "singleShootSpeed", "autoShootSpeed" }) do
        local v = player:getVariableFloat(var, 0)
        if v > 0 then player:setVariable(var, v * f) end
    end
end

local function onWeaponSwing(player, weapon)
    if not player or not player:isLocalPlayer() or not weapon then return end
    if isFirearm(weapon) then
        onFirearmSwing(player, weapon)
        return
    end
    -- Conditioning's signature: Heavy Load one moodle level lower. Vanilla takes 0.07 combat speed per level
    -- (`calculateCombatSpeed` ~9399); one level of it is given back, any weapon or bare hands.
    if M.sig(player, "Conditioning.SigHeavyLoad") and player:getMoodles():getMoodleLevel(MoodleType.HEAVY_LOAD) >= 1 then
        player:setCombatSpeed(player:getCombatSpeed() + 0.07)
    end
    local mastery = M.weaponMastery(weapon)
    if not mastery then return end
    local speed = M.val(player, mastery .. ".AttackSpeed")

    if mastery == "Knifework" then startLunge(player, weapon) end
    if mastery == "Knifework" and not player:isDoShove() and not player:isCriticalHit()
        and WeaponType.getWeaponType(player) == WeaponType.KNIFE
        and not weapon:hasTag(ItemTag.NO_CRITICALS) and M.roll(player, "Knifework.Executioner")
        and player:getStats():getNumChasingZombies() <= 1 and closeKillTarget(player, weapon) then
        player:setCriticalHit(true)
    end

    if not player:isDoShove() and not player:isCriticalHit() then
        local reroll = M.val(player, mastery .. ".CritReroll")
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
    stomp = { get = function(c) return c:getStompPower() end, set = function(c, v) c:setStompPower(v) end },
    maxHit = { get = function(w) return w:getMaxHitCount() end, set = function(w, v) w:setMaxHitCount(v) end },
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

local notePush   -- push back (defined below)

local function onHitPoint(owner, weapon)
    if not owner or not instanceof(owner, "IsoPlayer") or not owner:isLocalPlayer() or not weapon then return end
    restoreAll()
    notePush(owner, weapon)
    local entry = { weapon = weapon, changes = {} }

    -- Stomp: the worn shoes' stomp power, whatever the weapon.
    if owner:isAimAtFloor() and owner:isDoShove() then
        local stomp = M.val(owner, "StreetFighting.StompDamage")
        local ok, shoes = pcall(function() return owner:getWornItem(ItemBodyLocation.SHOES) end)
        if stomp > 0 and ok and shoes and instanceof(shoes, "Clothing") then
            local shoeEntry = { weapon = shoes, changes = {} }
            change(shoeEntry, "stomp", shoes:getStompPower() * (1 + stomp / 100))
            if #shoeEntry.changes > 0 then table.insert(pending, shoeEntry) end
        end
    end

    if isFirearm(weapon) then
        local aiming = owner:getPerkLevel(Perks.Aiming)
        local hit = M.val(owner, "Firearms.HitChance")
        if hit > 0 and aiming > 0 then
            change(entry, "aimHit", weapon:getAimingPerkHitChanceModifier() + hit / aiming)
        end
        local dmg = M.val(owner, "Firearms.Damage")
        if dmg > 0 then
            -- The firearm damage roll (~783) comes after this event too; the hit packet carries the damage and
            -- AntiCheatHitDamage only refuses > 100.
            local f = 1 + dmg / 100
            change(entry, "maxDamage", getRawMaxDamage(weapon) * f)
            change(entry, "minDamage", weapon:getMinDamage() * f)
        end
        local range = M.val(owner, "Firearms.Range")
        if range > 0 then
            local full = weapon:getMaxRange(owner)
            local room = weapon:getMaxRange() + 4.5 - full
            local add = math.min(full * range / 100, math.max(0, room))
            if add > 0 then change(entry, "maxRange", weapon:getMaxRange() + add) end
        end
    else
        local mastery = M.weaponMastery(weapon)
        local dmg, knock = 0, 0
        if mastery then
            dmg = M.val(owner, mastery .. ".Damage")
            knock = M.val(owner, mastery .. ".Knockback")
            local reach = M.val(owner, mastery .. ".Reach")
            if reach > 0 then change(entry, "maxRange", weapon:getMaxRange() * (1 + reach / 100)) end
            local extra = math.floor(M.val(owner, mastery .. ".ExtraTarget") + 0.0001)
            if extra > 0 then change(entry, "maxHit", weapon:getMaxHitCount() + extra) end
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

-- Bludgeoning's signature, push back (phase 3b): every swing with a long blunt weapon also staggers back the zombies
-- in a cone in front (1.5 tiles deep, 120 degrees, `getForwardDirection`) that the swing did not hit, at 0.01
-- endurance each (taken by the server; no push without the endurance). Noted at `OnWeaponSwingHitPoint`; the hits
-- come right after in the same frame (`OnWeaponHitCharacter` per zombie hit), so the rest are pushed next tick
-- through the relay (shared/TienSkillMastery_Relay.lua). Zombies on the floor and dragged corpses are skipped.
local pushes = {}   -- [player num] = { player, zombies = { [zombie] = true }, hit = { [zombie] = true } }
local PUSH_DEPTH, PUSH_DOT = 1.5, 0.5

notePush = function(owner, weapon)
    if M.weaponMastery(weapon) ~= "Bludgeoning" or owner:isDoShove() or not M.sig(owner, "Bludgeoning.SigPushBack") then
        return
    end
    local list = getCell() and getCell():getZombieList()
    if not list then return end
    local px, py = owner:getX(), owner:getY()
    local fx, fy = owner:getForwardDirectionX(), owner:getForwardDirectionY()
    local found = {}
    for i = 0, list:size() - 1 do
        local z = list:get(i)
        if z and not z:isDead() and not z:isOnFloor() and not z:isReanimatedForGrappleOnly()
            and math.abs(z:getZ() - owner:getZ()) < 0.5 then
            local dx, dy = z:getX() - px, z:getY() - py
            local d = math.sqrt(dx * dx + dy * dy)
            if d > 0.001 and d <= PUSH_DEPTH and (dx * fx + dy * fy) / d > PUSH_DOT then found[z] = true end
        end
    end
    pushes[owner:getPlayerNum()] = { player = owner, zombies = found, hit = {} }
end

Events.OnTick.Add(function()
    for num, p in pairs(pushes) do
        pushes[num] = nil
        local list = {}
        for z in pairs(p.zombies) do
            if not p.hit[z] and not z:isDead() then list[#list + 1] = z end
        end
        if #list > 0 then M.Relay.act(p.player, "pushback", list) end
    end
end)

local function onWeaponHitCharacter(wielder, target, weapon, damage)
    if not wielder or not instanceof(wielder, "IsoPlayer") or not wielder:isLocalPlayer() then return end
    if not target or not instanceof(target, "IsoZombie") then return end
    local push = pushes[wielder:getPlayerNum()]
    if push then push.hit[target] = true end
    -- Swordsmanship's signature, hamstring (phase 3b): sneaking and aiming with a long blade, every hit goes for the
    -- legs and the zombie gets up crawling (applied on its owner through the relay).
    if not wielder:isDoShove() and weapon and M.weaponMastery(weapon) == "Swordsmanship" and wielder:isSneaking()
        and wielder:isAiming() and not target:isCrawling() and M.sig(wielder, "Swordsmanship.SigHamstring") then
        M.Relay.act(wielder, "hamstring", target)
    end
    if wielder:isDoShove() then
        if not wielder:isAimAtFloor() then M.Relay.hit(wielder, target, "shove") end
        return
    end
    if weapon and M.weaponMastery(weapon) == "Knifework" and target:getTarget() ~= wielder then
        M.Relay.hit(wielder, target, "ambush", damage)
    end
end
Events.OnWeaponHitCharacter.Add(onWeaponHitCharacter)
Events.OnTick.Add(function()
    if #pending > 0 then restoreAll() end
end)

-- ---------------------------------------------------------------------------------------------------------------
-- OnPlayerUpdate: aim-in speed (owner only)
-- ---------------------------------------------------------------------------------------------------------------

local lastDelay = {}
local lastRecoil = {}
local lastMelee = {}
local MIN_SHOT_MS = 150

--- Extends whatever vanilla drained from a delay since the last update by `bonus` percent. `floorFn(now)` may
--- return a minimum the result must keep. Returns the value to remember.
local function drain(prev, now, bonus, setter, minimum)
    if prev and now < prev and now > 0 and bonus > 0 then
        local v = math.max(0, now - (prev - now) * bonus / 100)
        if minimum and v < minimum then v = math.min(now, minimum) end
        if v < now then
            setter(v)
            return v
        end
    end
    return now
end

local function onPlayerUpdate(player)
    if not player or not player:isLocalPlayer() then return end
    local num = player:getPlayerNum()
    local aiming = player:isAiming()

    -- Aim-in speed: extend whatever vanilla drained since our last look.
    local weapon = player:getPrimaryHandItem()
    if aiming and weapon and instanceof(weapon, "HandWeapon") and weapon:isAimedFirearm() then
        local now = player:getAimingDelay()
        local prev = lastDelay[num]
        local bonus = M.val(player, "Firearms.AimSpeed")
        if prev and now < prev and now > 0 and bonus > 0 then
            now = math.max(0, now - (prev - now) * bonus / 100)
            player:setAimingDelay(now)
        end
        lastDelay[num] = now
    else
        lastDelay[num] = nil
    end

    -- Fire rate: the recoil delay, never letting a shot come sooner than MIN_SHOT_MS after the last.
    if weapon and instanceof(weapon, "HandWeapon") and weapon:isAimedFirearm() and not isGunworksGun(weapon) then
        local bonus = M.val(player, "Firearms.FireRate")
        local now = player:getRecoilDelay()
        local shot = lastShot[num]
        local minimum = nil
        if shot and getTimestampMs() - shot < MIN_SHOT_MS then minimum = 0.001 end
        lastRecoil[num] = drain(lastRecoil[num], now, bonus, function(v) player:setRecoilDelay(v) end, minimum)
    else
        lastRecoil[num] = nil
    end

    -- Knifework's lunge: the jaw-stab window and the lunge itself.
    updateKnifeWindow(player)
    updateLunge(player)

    -- Knifework: the melee delay after a stab.
    if weapon and M.weaponMastery(weapon) == "Knifework" then
        local now = player:getMeleeDelay()
        lastMelee[num] = drain(lastMelee[num], now, M.val(player, "Knifework.AttackSpeed"),
            function(v) player:setMeleeDelay(v) end)
    else
        lastMelee[num] = nil
    end
end
Events.OnPlayerUpdate.Add(onPlayerUpdate)

-- ---------------------------------------------------------------------------------------------------------------
-- Gunworks: its RPM gate (see the header). Wrapped once its tables exist.
-- ---------------------------------------------------------------------------------------------------------------

local rpmPlayer = nil   -- the local player whose canFire is running

local function wrapGunworks()
    local rof = RateOfFire
    if type(rof) ~= "table" or rof.__tsmWrapped then return end
    if type(rof.canFire) ~= "function" or type(rof.getWeaponRPM) ~= "function" then return end
    rof.__tsmWrapped = true
    local canFire, getRPM = rof.canFire, rof.getWeaponRPM
    rof.getWeaponRPM = function(weapon, ...)
        local rpm = getRPM(weapon, ...)
        local player = rpmPlayer
        if player and type(rpm) == "number" and rpm > 0 and weapon == player:getPrimaryHandItem() then
            local bonus = M.val(player, "Firearms.FireRate")
            if bonus > 0 then
                local interval = 60000 / rpm
                local faster = math.max(interval / (1 + bonus / 100), math.min(interval, MIN_SHOT_MS))
                rpm = 60000 / faster
            end
        end
        return rpm
    end
    rof.canFire = function(player, weapon, ...)
        local was = rpmPlayer
        rpmPlayer = (player and player.isLocalPlayer and player:isLocalPlayer()) and player or nil
        local results = { pcall(canFire, player, weapon, ...) }
        rpmPlayer = was
        if not results[1] then error(results[2], 0) end
        return unpack(results, 2)
    end
end
Events.OnGameStart.Add(wrapGunworks)
