--[[
Tien's Skill Mastery: Axemanship's and Spearcraft's signature, throwing the weapon (42.21).

Trigger (user, 2026-11-07): the throw key only (see the key section below); throwing by swinging at a zombie out of
reach was dropped the same day (the user kept throwing the axe with the attack button). The key throws the primary
hand item when it is throwable (a one-handed axe or any spear, with that signature), else a one-handed axe carried
in the main inventory (loose first, then on the hotbar, never from bags).

Resolution, on the server (single player: locally), never trusted from the client: the weapon must still be the
thrower's primary hand item with the same ID (a carried axe: directly in the main inventory, not in hand), of the
mastery's category, with the signature.

The flight aims for the head (user, 2026-11-07): released at hand height and thrown in a straight line at the
target's head, while gravity (the game's own fall acceleration, `FallingConstants.IsoFallAcceleration` 5.0010414
levels a second squared) pulls it down over the flight: height(x) = hand + (head - hand) x / d - g / 2 x (x / v)^2,
x the distance flown, d the distance to the target, v the throw speed (axe 22, spear 20 tiles a second). So a close
throw lands on the head and a long one drops into the body, the legs or the floor. Resolved at once in 0.2-tile
steps: it stops at the first wall, closed door or window between squares (`isBlockedTo`, both orthogonal ways for a
diagonal step), at the floor (height 0: it lands there), or at the first standing zombie within 0.45 tiles of the
path while the height is within a zombie (below `ZOMBIE_TOP`; above that it flies over). The height at the zombie
picks the body part and vanilla's damage factor for it (`CombatConfigKey`: head x3
HEAD_HIT_DAMAGE_SPLIT_MODIFIER, legs x0.05 LEG_HIT_DAMAGE_SPLIT_MODIFIER, body x1). Heights are in levels (a
level is 2.45 m at the game's scale, so head 0.65 is about 1.6 m). Every number is a constant below. The weapon leaves the hands and the inventory
(`DoRemoveItem` + `sendRemoveItemFromContainer`; the server's hand change syncs itself) at the throw; the hit and the
landing where the flight ended (`AddWorldInventoryItem`, which the server sends) wait for the flight time (distance
flown / speed; see `Th.inFlight`). Every throw, hit or miss, gets vanilla's melee wear roll
(at most one point; the mastery's wear undo and the item's mark can cancel it; see `wearRoll`). A hit deals the weapon's damage roll (min..max, plus the mastery's damage
bonus) and staggers the zombie: on its owner through the relay (shared/TienSkillMastery_Relay.lua), or locally /
on the server for a zombie nobody owns, where a zombie brought to 0 is killed with `Kill(thrower)`. Clients get
`throwFly` and draw the weapon flying (`Render3DItem` from `RenderOpaqueObjectsInWorld`, as ZomboidFixesB42's
throwables and `ISPlace3DItemCursor` do; only drawn while the mouse is over the world).
]]

require "TimedActions/ISBaseTimedAction"
require "TienSkillMastery"
require "TienSkillMastery_Relay"
local M = TienSkillMastery

M.Throw = M.Throw or {}
local Th = M.Throw

-- Axe raised 2026-11-07 (user: farther, more damage): 22 tiles a second gives head hits to ~4.4 tiles, body to ~9,
-- the floor at ~11.
Th.SPEED = { Axemanship = 22, Spearcraft = 20 }   -- tiles a second
Th.GRAVITY = 5.0010414    -- levels a second squared (FallingConstants.IsoFallAcceleration)
Th.HAND_HEIGHT = 0.55     -- release height, levels above the floor
Th.HEAD_HEIGHT = 0.65     -- where it is aimed on the target
Th.HEAD_MIN = 0.55        -- at or above: a head hit
Th.LEGS_MAX = 0.2         -- below: a leg hit
Th.ZOMBIE_TOP = 0.8       -- above: flies over a zombie
Th.DAMAGE = { head = 3.0, body = 1.0, legs = 0.05 }   -- vanilla's CombatConfig factors
Th.STEP = 0.2
Th.HIT_RADIUS = 0.45
Th.RANGE = { Axemanship = 12, Spearcraft = 10 }
-- Thrown weapon damage over the weapon's own roll (before the head / body / legs factor and the mastery's bonus).
Th.THROW_DAMAGE = { Axemanship = 1.5, Spearcraft = 1.0 }
Th.SIG = { Axemanship = "Axemanship.SigThrowAxe", Spearcraft = "Spearcraft.SigThrowSpear" }

--- The throwing mastery of a weapon, or nil: one-handed axes and any spear.
function Th.masteryOf(weapon)
    local mastery = M.weaponMastery(weapon)
    if mastery == "Axemanship" then
        if weapon:isTwoHandWeapon() or weapon:isRequiresEquippedBothHands() then return nil end
        return mastery
    elseif mastery == "Spearcraft" then
        return mastery
    end
    return nil
end

function Th.canThrow(player, weapon)
    local mastery = weapon and Th.masteryOf(weapon)
    return mastery ~= nil and M.sig(player, Th.SIG[mastery]), mastery
end

local function standingZombieNear(x, y, z, radius, skip)
    local list = getCell() and getCell():getZombieList()
    if not list then return nil end
    local best, bestD = nil, radius
    for i = 0, list:size() - 1 do
        local zed = list:get(i)
        if zed and zed ~= skip and not zed:isDead() and not zed:isOnFloor() and not zed:isReanimatedForGrappleOnly()
            and math.abs(zed:getZ() - z) < 0.5 then
            local dx, dy = zed:getX() - x, zed:getY() - y
            local d = math.sqrt(dx * dx + dy * dy)
            if d < bestD then best, bestD = zed, d end
        end
    end
    return best
end
Th.standingZombieNear = standingZombieNear

local function blocked(a, b)
    if not a or not b then return true end
    if a == b then return false end
    local dx, dy = b:getX() - a:getX(), b:getY() - a:getY()
    if math.abs(dx) + math.abs(dy) == 1 then return a:isBlockedTo(b) end
    -- diagonal: open only if both orthogonal ways are
    local cell = getCell()
    local s1 = cell:getGridSquare(a:getX() + dx, a:getY(), a:getZ())
    local s2 = cell:getGridSquare(a:getX(), a:getY() + dy, a:getZ())
    if not s1 or not s2 then return true end
    return (a:isBlockedTo(s1) or s1:isBlockedTo(b)) and (a:isBlockedTo(s2) or s2:isBlockedTo(b))
end

--- Height above the floor after flying `x` tiles toward a target `d` tiles away at `speed`.
function Th.heightAt(x, d, speed)
    local t = x / speed
    return Th.HAND_HEIGHT + (Th.HEAD_HEIGHT - Th.HAND_HEIGHT) * x / math.max(d, 0.5) - Th.GRAVITY / 2 * t * t
end

function Th.partAt(h)
    if h >= Th.HEAD_MIN then return "head" end
    if h < Th.LEGS_MAX then return "legs" end
    return "body"
end

--- Flies from the thrower toward (tx, ty): returns endX, endY, zombie hit (or nil), body part hit, distance flown.
function Th.fly(player, tx, ty, range, speed)
    local x, y, z = player:getX(), player:getY(), player:getZ()
    local dx, dy = tx - x, ty - y
    local d = math.sqrt(dx * dx + dy * dy)
    if d < 0.001 then return x, y, nil, nil, 0 end
    dx, dy = dx / d, dy / d
    local cell = getCell()
    local square = player:getCurrentSquare()
    local travelled = 0
    local limit = math.min(range, d + 1.5)
    while travelled < limit do
        local nx, ny = x + dx * Th.STEP, y + dy * Th.STEP
        local nextSq = cell:getGridSquare(math.floor(nx), math.floor(ny), math.floor(z))
        if not nextSq or blocked(square, nextSq) then return x, y, nil, nil, travelled end
        x, y, square = nx, ny, nextSq
        travelled = travelled + Th.STEP
        local h = Th.heightAt(travelled, d, speed)
        if h <= 0 then return x, y, nil, nil, travelled end   -- reached the floor first: lands here
        if travelled > 0.6 and h <= Th.ZOMBIE_TOP then
            local hit = standingZombieNear(x, y, z, Th.HIT_RADIUS)
            if hit then return hit:getX(), hit:getY(), hit, Th.partAt(h), travelled end
        end
    end
    return x, y, nil, nil, travelled
end

local function damageFor(player, weapon, mastery, part)
    local base = ZombRandFloat(weapon:getMinDamage(), math.max(weapon:getMinDamage(), weapon:getMaxDamage()))
    return base * (Th.THROW_DAMAGE[mastery] or 1) * M.more(player, mastery .. ".Damage") * (Th.DAMAGE[part] or 1)
end

local function applyHit(player, zombie, amount)
    local owner = isServer() and zombie:getOwnerPlayer() or nil
    if owner then
        sendServerCommand(owner, M.MODULE, "zombieDamage", { id = zombie:getOnlineID(), amount = amount })
        sendServerCommand(owner, M.MODULE, "zombieActApply", { id = zombie:getOnlineID(), kind = "pushback",
            x = player:getX(), y = player:getY() })
        return
    end
    zombie:setHealth(math.max(0, zombie:getHealth() - amount))
    if zombie:getHealth() <= 0 then
        pcall(function() zombie:Kill(player) end)
    else
        M.Relay.queueAct(zombie, "pushback", { x = player:getX(), y = player:getY() })
    end
end

--- Vanilla's melee wear odds for every throw, hit or miss (user, 2026-11-07): `InventoryItem.damageCheck` loses a
--- point 1 in (ConditionLowerChance + Maintenance + weapon skill / 2). The thrown weapon has left the hands, so the
--- per-tick wear undo in server/TienSkillMastery_Physical.lua never sees it; the same chances are applied here: the
--- mastery's WearUndo and the item's mark (combined as there) can give the point back. One point at most per throw.
local SKILL = { Axemanship = Perks.Axe, Spearcraft = Perks.Spear }
local function wearRoll(player, weapon, mastery)
    local base = weapon:getConditionLowerChance()
    if base <= 0 or weapon:getCondition() <= 0 then return end
    local odds = base + player:getPerkLevel(Perks.Maintenance) + math.floor(player:getPerkLevel(SKILL[mastery]) / 2)
    if ZombRand(math.max(1, odds)) ~= 0 then return end
    local a = M.val(player, mastery .. ".WearUndo")
    local b = math.min(100, tonumber(weapon:getModData().TSM_Mark) or 0)
    local undo = 100 * (1 - (1 - a / 100) * (1 - b / 100))
    if undo > 0 and ZombRandFloat(0, 100) < undo then return end
    weapon:setCondition(math.max(0, weapon:getCondition() - 1), false)
end

--- Server / single player. Returns true when thrown.
--- `carried`: an axe thrown with the throw key from the main inventory, not in hand; else the primary hand item.
function Th.resolve(player, weaponId, tx, ty, carried)
    if not player or not weaponId then return false end
    local weapon
    if carried then
        -- The main inventory itself (loose or on the hotbar), never a bag (user, 2026-11-07).
        weapon = player:getInventory():getItemById(weaponId)
        if weapon and (weapon:getContainer() ~= player:getInventory() or weapon == player:getPrimaryHandItem()
            or weapon == player:getSecondaryHandItem()) then
            weapon = nil
        end
    else
        weapon = player:getPrimaryHandItem()
        if weapon and weapon:getID() ~= weaponId then weapon = nil end
    end
    if not weapon or not instanceof(weapon, "HandWeapon") then return false end
    local ok, mastery = Th.canThrow(player, weapon)
    if not ok or (carried and mastery ~= "Axemanship") then return false end
    -- Off the hotbar first (vanilla's detach, ISHotbar:removeItem); the owner's hotbar drops the model itself once
    -- the item is gone from the inventory, and its removeAttachedItem reaches the other clients.
    if weapon:getAttachedSlot() > -1 then
        player:removeAttachedItem(weapon)
        weapon:setAttachedSlot(-1)
        weapon:setAttachedSlotType(nil)
        weapon:setAttachedToModel(nil)
    end
    tx, ty = tonumber(tx), tonumber(ty)
    if not tx or not ty then return false end
    local range, speed = Th.RANGE[mastery], Th.SPEED[mastery]
    local fromX, fromY, z = player:getX(), player:getY(), player:getZ()
    local aim = math.sqrt((tx - fromX) * (tx - fromX) + (ty - fromY) * (ty - fromY))
    local endX, endY, hit, part, travelled = Th.fly(player, tx, ty, range, speed)

    -- Out of the hands and the inventory.
    if player:getSecondaryHandItem() == weapon then player:setSecondaryHandItem(nil) end
    player:setPrimaryHandItem(nil)
    local container = weapon:getContainer()
    if container then
        container:DoRemoveItem(weapon)
        if isServer() then sendRemoveItemFromContainer(container, weapon) end
    end

    wearRoll(player, weapon, mastery)

    -- The hit and the landing wait for the flight (user, 2026-11-07: damage came before the axe got there): the
    -- flight time is the distance flown / speed, the same the clients draw it over (`Th.showFlight`).
    table.insert(Th.inFlight, { player = player, weapon = weapon, zombie = hit,
        damage = hit and damageFor(player, weapon, mastery, part) or 0, x = endX, y = endY, z = z,
        at = getTimestampMs() + math.max(60, (travelled or 0) / speed * 1000) })

    local fly = { type = weapon:getFullType(), fx = fromX, fy = fromY, z = z, tx = endX, ty = endY, aim = aim,
        speed = speed }
    if isServer() then
        sendServerCommand(M.MODULE, "throwFly", fly)
    elseif Th.showFlight then
        Th.showFlight(fly)
    end
    return true
end

-- Server / single player: weapons in the air. The path (and so the zombie and body part) is worked out at the throw;
-- at arrival the zombie must still be alive and within TRACK_RADIUS of where the weapon was headed (it kept walking:
-- a runner can leave the spot, a shambler rarely does), else the throw misses and the weapon lands there anyway.
-- Server ticks are 100 ms apart, so an arrival can be up to that late.
Th.inFlight = Th.inFlight or {}
Th.TRACK_RADIUS = 1.0

local function arrive(f)
    local z = f.zombie
    if z and not z:isDead() then
        local dx, dy = z:getX() - f.x, z:getY() - f.y
        if dx * dx + dy * dy <= Th.TRACK_RADIUS * Th.TRACK_RADIUS then
            pcall(applyHit, f.player, z, f.damage)
            -- The weapon's zombie hit sound, at the zombie, for everyone (see `Th.playHit`).
            local sound = f.weapon:getZombieHitSound()
            if sound and sound ~= "" then
                local data = { id = z:getOnlineID(), x = z:getX(), y = z:getY(), z = z:getZ(), sound = sound }
                if isServer() then
                    sendServerCommand(M.MODULE, "throwHit", data)
                elseif Th.playHit then
                    Th.playHit(data)
                end
            end
        end
    end
    local square = getCell():getGridSquare(math.floor(f.x), math.floor(f.y), math.floor(f.z))
        or (f.player and f.player:getCurrentSquare())
    if square then square:AddWorldInventoryItem(f.weapon, f.x - square:getX(), f.y - square:getY(), 0) end
end

if not isClient() then
    Events.OnTick.Add(function()
        if #Th.inFlight == 0 then return end
        local now = getTimestampMs()
        for i = #Th.inFlight, 1, -1 do
            local f = Th.inFlight[i]
            if now >= f.at then
                table.remove(Th.inFlight, i)
                arrive(f)
            end
        end
    end)
end

if isServer() then
    Events.OnClientCommand.Add(function(module, command, player, args)
        if module ~= M.MODULE or command ~= "throwWeapon" or type(args) ~= "table" or not player then return end
        Th.resolve(player, tonumber(args.id), args.tx, args.ty, args.carried == true)
    end)
end

-- ---------------------------------------------------------------------------------------------------------------
-- Client: trigger and flight visual
-- ---------------------------------------------------------------------------------------------------------------

if isServer() then return end

local flights = {}   -- { item, fx, fy, z, tx, ty, start, duration }

function Th.showFlight(args)
    local item = instanceItem(args.type)
    if not item then return end
    local dx, dy = args.tx - args.fx, args.ty - args.fy
    local d = math.sqrt(dx * dx + dy * dy)
    local speed = tonumber(args.speed) or 15
    table.insert(flights, { item = item, fx = args.fx, fy = args.fy, z = args.z, tx = args.tx, ty = args.ty,
        start = getTimestampMs(), duration = math.max(60, d / speed * 1000), dist = d,
        aim = tonumber(args.aim) or d, speed = speed, angle = math.deg(math.atan2(dy, dx)) })
end

--- A thrown weapon's hit sound (user, 2026-11-07): the weapon script's `HitSound` (`getZombieHitSound`, HandAxeHit),
--- played as vanilla plays a melee hit, `playSoundImpl` on an emitter (local only, hence the server's broadcast),
--- here the zombie's own (a free world emitter at the spot when this client does not have the zombie).
function Th.playHit(args)
    local sound = args.sound
    if type(sound) ~= "string" or sound == "" then return end
    local zed = M.Relay and M.Relay.findZombie(tonumber(args.id))
    if zed then
        zed:getEmitter():playSoundImpl(sound, nil)
        return
    end
    local x, y, z = tonumber(args.x), tonumber(args.y), tonumber(args.z)
    if x and y and z then
        local emitter = getWorld():getFreeEmitter(x, y, z)
        if emitter then emitter:playSoundImpl(sound, nil) end
    end
end

Events.OnServerCommand.Add(function(module, command, args)
    if module == M.MODULE and command == "throwHit" and type(args) == "table" then
        Th.playHit(args)
        return
    end
    if module == M.MODULE and command == "throwFly" and type(args) == "table" then
        Th.showFlight({ type = args.type, fx = tonumber(args.fx), fy = tonumber(args.fy), z = tonumber(args.z),
            tx = tonumber(args.tx), ty = tonumber(args.ty), aim = args.aim, speed = args.speed })
    end
end)

Events.RenderOpaqueObjectsInWorld.Add(function()
    if #flights == 0 then return end
    local now = getTimestampMs()
    for i = #flights, 1, -1 do
        local f = flights[i]
        local t = (now - f.start) / f.duration
        if t >= 1 then
            table.remove(flights, i)
        else
            local x, y = f.fx + (f.tx - f.fx) * t, f.fy + (f.ty - f.fy) * t
            local square = getCell():getGridSquare(math.floor(x), math.floor(y), math.floor(f.z))
            if square then
                local spin = (now - f.start) * 0.9
                local h = math.max(0.02, Th.heightAt(f.dist * t, f.aim, f.speed))
                pcall(Render3DItem, f.item, square, x, y, f.z + h, f.angle + spin)
            end
        end
    end
end)

--- The standing zombie whose body is under the mouse on screen (feet to head), nearest the mouse; within `range`.
--- The floor square under the mouse lies a tile or two behind a zombie when the mouse is on its chest or head (the
--- iso view), so the picked square alone made the trigger hit or miss with where on the body the player aimed.
Th.BODY_HEIGHT = 0.75   -- levels, feet to head (about 1.8 m)
local function zombieUnderMouse(player, range)
    local list = getCell() and getCell():getZombieList()
    if not list then return nil end
    local num = player:getPlayerNum()
    local mx, my = getMouseX(), getMouseY()
    local px, py, pz = player:getX(), player:getY(), player:getZ()
    local best, bestScore = nil, nil
    for i = 0, list:size() - 1 do
        local z = list:get(i)
        if z and not z:isDead() and not z:isOnFloor() and not z:isReanimatedForGrappleOnly()
            and math.abs(z:getZ() - pz) < 0.5 then
            local zx, zy, zz = z:getX(), z:getY(), z:getZ()
            if (zx - px) * (zx - px) + (zy - py) * (zy - py) <= range * range then
                local fx, fy = isoToScreenX(num, zx, zy, zz), isoToScreenY(num, zx, zy, zz)
                local hy = isoToScreenY(num, zx, zy, zz + Th.BODY_HEIGHT)
                local height = math.max(1, fy - hy)
                local half = math.max(10, height * 0.3)
                if mx >= fx - half and mx <= fx + half and my >= hy - half * 0.5 and my <= fy + half * 0.3 then
                    local cy = (fy + hy) / 2
                    local score = math.abs(mx - fx) + math.abs(my - cy) * 0.5
                    if not bestScore or score < bestScore then best, bestScore = z, score end
                end
            end
        end
    end
    return best
end
Th.zombieUnderMouse = zombieUnderMouse

-- ---------------------------------------------------------------------------------------------------------------
-- The throw key (user, 2026-11-07), the only way to throw: the primary hand item when throwable, else a one-handed
-- axe you carry without it being in hand: from the main inventory first, then one attached to the hotbar, never from
-- bags (`Th.throwable`). Only in combat stance (aiming). Pressed with
-- the cursor on a zombie (its on-screen body, as for a swing) it is aimed at that zombie's head; otherwise at the
-- floor under the cursor (`ISCoordConversion.ToWorld`, as fishing aims). Within the axe's throw range; player 0 on
-- the mouse only. A vanilla key binding ("[TienSkillMastery]" section, default Space, Options > Key bindings;
-- `keyBinding` entries are loaded by `MainOptions.loadKeys` into `getCore():addKeyBinding`, tested with
-- `getCore():isKey`). Space is vanilla's Melee key too (a shove in combat stance), so attacking is banned while the
-- key is down or a throw is queued (see `holdAttacks`); with nothing to throw, Space shoves as usual.
-- The throw is a short client-only action (no `complete`): it plays `AnimSets/player/actions/TsmThrowAxe.xml`
-- (vanilla's `Bob_AttackThrowMolotov`, the clip of the `ranged/Throw` attack node, here as an action node with a
-- release event; a carried axe is put in the hand model) and at the release sends `throwWeapon { carried }`; for a
-- carried axe the server checks it is directly in the main inventory and takes it off the hotbar.
-- ---------------------------------------------------------------------------------------------------------------

Th.KEY_NAME = "TsmThrowAxe"

local function isCarriedAxe(player, item)
    return instanceof(item, "HandWeapon") and Th.masteryOf(item) == "Axemanship" and item:getCondition() > 0
        and item ~= player:getPrimaryHandItem() and item ~= player:getSecondaryHandItem()
end

--- A one-handed axe in the main inventory: loose ones first, then hotbar-attached ones; never inside bags.
function Th.findCarriedAxe(player)
    local items = player:getInventory():getItems()
    local attached = nil
    for i = 0, items:size() - 1 do
        local it = items:get(i)
        if isCarriedAxe(player, it) then
            if it:getAttachedSlot() < 0 then return it end
            attached = attached or it
        end
    end
    return attached
end

--- What the throw key would throw: item, mastery, carried. The primary hand item when throwable, else a carried axe.
function Th.throwable(player)
    local held = player:getPrimaryHandItem()
    if held and instanceof(held, "HandWeapon") and held:getCondition() > 0 then
        local ok, mastery = Th.canThrow(player, held)
        if ok then return held, mastery, false end
    end
    if M.sig(player, Th.SIG.Axemanship) then
        local axe = Th.findCarriedAxe(player)
        if axe then return axe, "Axemanship", true end
    end
    return nil
end

TienSkillMasteryThrowAction = ISBaseTimedAction:derive("TienSkillMasteryThrowAction")
local TA = TienSkillMasteryThrowAction
-- Timing (user, 2026-11-07: the axe left before the arm got there; make it faster). `Bob_AttackThrowMolotov` is
-- 7040 ticks at 4800 a second = 1.47 s; the node plays it at 1.6 (0.92 s), and its `TsmThrowRelease` event sits at
-- 0.3, vanilla's own release point (`ranged/Throw.xml` AttackCollisionCheck), so the axe leaves ~0.28 s in. The
-- action runs 45 units (`BaseAction` adds `getMultiplier()`, ~48 a second at 1x: ~0.94 s, the whole clip); the job
-- delta release is only a fallback for a missed event, well after it.
Th.RELEASE_AT = 0.6
Th.THROW_TIME = 45

function TA:isValid()
    return self.item:getContainer() == self.character:getInventory()
end

function TA:waitToStart()
    if self.target and not self.target:isDead() then
        self.character:faceThisObject(self.target)
    else
        self.character:faceLocationF(self.tx, self.ty)
    end
    return self.character:shouldBeTurning()
end

function TA:start()
    self:setActionAnim("TsmThrowAxe")
    if self.carried then self:setOverrideHandModels(self.item, nil) end
end

function TA:release()
    if self.released then return end
    self.released = true
    -- The axe's swing sound as it leaves the hand (user, 2026-11-07), as vanilla's swing plays it: `playSound` on the
    -- character, which an MP client also sends to the players near it (PlaySoundPacket).
    local swing = self.item:getSwingSound()
    if swing and swing ~= "" then self.character:playSound(swing) end
    local tx, ty = self.tx, self.ty
    if self.target and not self.target:isDead() then tx, ty = self.target:getX(), self.target:getY() end
    if isClient() then
        sendClientCommand(self.character, M.MODULE, "throwWeapon",
            { id = self.item:getID(), tx = tx, ty = ty, carried = self.carried })
    else
        Th.resolve(self.character, self.item:getID(), tx, ty, self.carried)
    end
end

function TA:update()
    if not self.released and self:getJobDelta() >= Th.RELEASE_AT then self:release() end
end

function TA:animEvent(event)
    if event == "TsmThrowRelease" then self:release() end
end

function TA:perform()
    self:release()
    ISBaseTimedAction.perform(self)
end

function TA:new(character, item, target, tx, ty, carried)
    local o = ISBaseTimedAction.new(self, character)
    o.item = item
    o.carried = carried == true
    o.target = target
    o.tx, o.ty = tx, ty
    o.stopOnWalk = false
    o.stopOnRun = true
    o.stopOnAim = false   -- thrown from combat stance: aiming must not stop it (`StopAllActionQueueAiming`)
    o.maxTime = Th.THROW_TIME
    o.useProgressBar = false
    return o
end

local held = {}   -- [player] = { key, was }: attacks banned while the throw key is down or a throw is queued

-- Space is vanilla's Melee key: `IsoPlayer` starts a shove on every update the key is down (so holding it shoved
-- twice) unless `bannedAttacking` is set (~2508, on foot). Keys are read (`GameKeyboard.update`, `OnKeyStartPressed`)
-- before the players update in the same frame, so banning at the press stops that shove before it starts. A
-- `WeaponSwing` hook cannot: reverting `SwipeStatePlayer` leaves the shove animation playing (reported 2026-11-07).
local function holdAttacks(player, key)
    if not held[player] then held[player] = { was = player:isBannedAttacking() } end
    held[player].key = key
    player:setBannedAttacking(true)
end

--- The throw key pressed: aim, pick the axe, queue the throw (see the header).
function Th.throwKey(player, key)
    if not player or player:isDead() or player:getVehicle() or player:getJoypadBind() ~= -1 then return end
    if ISTimedActionQueue.hasActionType(player, "TienSkillMasteryThrowAction") then
        holdAttacks(player, key)   -- pressed again mid-throw: no shove (it would also stop the throw)
        return
    end
    if not player:isAiming() then return end
    local item, mastery, carried = Th.throwable(player)
    if not item then return end
    local range = Th.RANGE[mastery]
    local target = zombieUnderMouse(player, range)
    local tx, ty
    if target then
        tx, ty = target:getX(), target:getY()
    else
        tx, ty = ISCoordConversion.ToWorld(getMouseXScaled(), getMouseYScaled(), player:getZ())
        if not tx then return end
        target = standingZombieNear(tx, ty, player:getZ(), 1.0)
        if target then tx, ty = target:getX(), target:getY() end
    end
    local dx, dy = tx - player:getX(), ty - player:getY()
    local d = math.sqrt(dx * dx + dy * dy)
    if d < 0.5 then return end
    if d > range then tx, ty = player:getX() + dx / d * range, player:getY() + dy / d * range end
    holdAttacks(player, key)
    ISTimedActionQueue.add(TienSkillMasteryThrowAction:new(player, item, target, tx, ty, carried))
end

Events.OnTick.Add(function()
    for player, h in pairs(held) do
        if player:isDead() or (not isKeyDown(h.key)
            and not ISTimedActionQueue.hasActionType(player, "TienSkillMasteryThrowAction")) then
            held[player] = nil
            player:setBannedAttacking(h.was)
        end
    end
end)

-- The key binding.
if keyBinding then
    table.insert(keyBinding, { value = "[TienSkillMastery]" })
    table.insert(keyBinding, { value = Th.KEY_NAME, key = Keyboard.KEY_SPACE })
end

Events.OnKeyStartPressed.Add(function(key)
    if not getCore():isKey(Th.KEY_NAME, key) then return end
    local player = getSpecificPlayer(0)
    if player then Th.throwKey(player, key) end
end)

-- ---------------------------------------------------------------------------------------------------------------
-- Aim reticle when a throw is possible (user, 2026-11-07). Vanilla's reticle (Java `IsoReticle`) is not exposed to
-- Lua and `IsoPlayer` sets its mode every update (the reticle only with the precision-aim key and a firearm), so the
-- same textures are drawn at the cursor from `OnPreUIDraw`: the player's chosen aim circle
-- (`media/ui/Reticle/aimCircleNN.png`, `getOptionAimTextureIndex`) and crosshair (`crosshairXY.png`, four parts,
-- `getOptionCrosshairTextureIndex`), sized as vanilla sizes them (texture / 16, x 1 / zoom with the camera-zoom
-- option). Shown while aiming with something the throw key would throw (`Th.throwable`) and a zombie under the
-- cursor within its throw range.
-- ---------------------------------------------------------------------------------------------------------------

local reticleTex = {}
local function tex(path)
    if reticleTex[path] == nil then reticleTex[path] = getTexture(path) or false end
    return reticleTex[path] or nil
end

local function throwReady(player)
    if not player:isAiming() or player:getVehicle() then return false end
    local item, mastery = Th.throwable(player)
    return item ~= nil and zombieUnderMouse(player, Th.RANGE[mastery]) ~= nil
end

local function drawTex(t, x, y, w, h, a)
    getRenderer():renderPoly(t, x, y, x + w, y, x + w, y + h, x, y + h, 1, 1, 1, a)
end

Events.OnPreUIDraw.Add(function()
    local player = getSpecificPlayer(0)
    if not player or player:isDead() or player:getJoypadBind() ~= -1 then return end
    local ok, ready = pcall(throwReady, player)
    if not ok or not ready then return end
    local core = getCore()
    local zoom = core:getOptionReticleCameraZoom() and 1 / core:getZoom(0) or 1
    local mx, my = getMouseX(), getMouseY()
    local circle = tex(string.format("media/ui/Reticle/aimCircle%02d.png", core:getOptionAimTextureIndex()))
    if circle then
        local w, h = circle:getWidth() / 16 * zoom, circle:getHeight() / 16 * zoom
        drawTex(circle, mx - w / 2, my - h / 2, w, h, 0.9)
    end
    local ci = core:getOptionCrosshairTextureIndex()
    local offset = 6
    for part = 0, 3 do
        local t = tex(string.format("media/ui/Reticle/crosshair%d%d.png", ci, part))
        if t then
            local w, h = t:getWidth() / 16 * zoom, t:getHeight() / 16 * zoom
            local x, y = mx - w / 2, my - h / 2
            if part == 0 then x = x - offset elseif part == 1 then y = y - offset
            elseif part == 2 then x = x + offset else y = y + offset end
            drawTex(t, x, y, w, h, 0.9)
        end
    end
end)
