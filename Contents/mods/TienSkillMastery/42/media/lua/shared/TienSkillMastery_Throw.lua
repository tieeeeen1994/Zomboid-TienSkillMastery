--[[
Tien's Skill Mastery: Axemanship's and Spearcraft's signature, throwing the weapon (42.21).

Trigger (user, 2026-11-07): the throw key only (see the key section below); throwing by swinging at a zombie out of
reach was dropped the same day (the user kept throwing the axe with the attack button). The key throws a one-handed
axe or a spear (with that signature) carried in the main inventory (loose first, then on the hotbar, never from
bags), and only with none of those the primary hand item.

Resolution, on the server (single player: locally), never trusted from the client: the weapon must still be the
thrower's primary hand item with the same ID (a carried one: directly in the main inventory, not in hand), of the
mastery's category, with the signature.

The flight aims for the head (user, 2026-11-07): released at hand height and thrown in a straight line at the
target's head, while gravity (the game's own fall acceleration, `FallingConstants.IsoFallAcceleration` 5.0010414
levels a second squared) pulls it down over the flight: height(x) = hand + (head - hand) x / d - g / 2 x (x / v)^2,
x the distance flown, d the distance to the target, v the throw speed (22 tiles a second, axe and spear). So a close
throw lands on the head and a long one drops into the body, the legs or the floor. Resolved at once in 0.2-tile
steps: it stops at the first wall, closed door or window between squares (`isBlockedTo`, both orthogonal ways for a
diagonal step), at the floor (height 0: it lands there), or at the first target within 0.45 tiles of the path while
the height is within its body (below its top; above that it flies over). Targets (user, 2026-11-08): standing
zombies, loose animals, and other players where vanilla's PvP rules allow a hit (see `Th.pvpAllowed`). The height at
a zombie or player picks the body part and vanilla's damage factor for it (`CombatConfigKey`: head x3
HEAD_HIT_DAMAGE_SPLIT_MODIFIER, legs x0.05 LEG_HIT_DAMAGE_SPLIT_MODIFIER, body x1). Heights are in levels (a
level is 2.45 m at the game's scale, so head 0.65 is about 1.6 m). Every number is a constant below. The weapon leaves the hands and the inventory
(`DoRemoveItem` + `sendRemoveItemFromContainer`; the server's hand change syncs itself) at the throw; the hit and the
landing where the flight ended (`AddWorldInventoryItem`, which the server sends) wait for the flight time (distance
flown / speed; see `Th.inFlight`). Every throw, hit or miss, gets vanilla's melee wear roll
(at most one point; the mastery's wear undo and the item's mark can cancel it; see `wearRoll`). A hit deals the weapon's damage roll (min..max, plus the mastery's damage
bonus) and staggers the zombie: on its owner through the relay (shared/TienSkillMastery_Relay.lua), or locally /
on the server for a zombie nobody owns, where a zombie brought to 0 is killed with `Kill(thrower)`. An animal takes
it through vanilla's `IsoAnimal.hitConsequences` (server / SP), a player through vanilla's PvP wound,
`BodyDamage.DamageFromWeapon` on the server (see `applyHit`). Clients get
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
-- the floor at ~11. Spears made the same as axes 2026-11-08 (user: same distance, harder; only the look and the
-- sounds differ). Kept per mastery so they can be told apart again.
Th.SPEED = { Axemanship = 22, Spearcraft = 22 }   -- tiles a second
Th.GRAVITY = 5.0010414    -- levels a second squared (FallingConstants.IsoFallAcceleration)
Th.HAND_HEIGHT = 0.55     -- release height, levels above the floor
Th.HEAD_HEIGHT = 0.65     -- where it is aimed on the target
Th.HEAD_MIN = 0.55        -- at or above: a head hit
Th.LEGS_MAX = 0.2         -- below: a leg hit
Th.ZOMBIE_TOP = 0.8       -- above: flies over a zombie
Th.DAMAGE = { head = 3.0, body = 1.0, legs = 0.05 }   -- vanilla's CombatConfig factors
Th.STEP = 0.2
Th.HIT_RADIUS = 0.45
Th.RANGE = { Axemanship = 12, Spearcraft = 12 }
-- Thrown weapon damage over the weapon's own roll (before the head / body / legs factor and the mastery's bonus).
Th.THROW_DAMAGE = { Axemanship = 1.5, Spearcraft = 1.5 }
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

-- ---------------------------------------------------------------------------------------------------------------
-- Targets (user, 2026-11-08: animals and PvP players too, not only zombies). Kinds: "zombie" (standing, not a corpse
-- being dragged), "player" (another player a melee hit could reach under vanilla's PvP rules, not invisible),
-- "animal" (any loose animal: `square:getAnimals()`; hutched ones are out of the world). Heights are tops in levels
-- (a level is 2.45 m): a zombie or player 0.8; animal definitions have no height (`collisionSize` is a width), so
-- each type gets a rough one here (a hen 0.15 = ~0.37 m, a cow 0.6 = ~1.5 m). A throw flies over a target while
-- above its top; it is aimed at a person's head and at 0.6 of an animal's height.
-- ---------------------------------------------------------------------------------------------------------------

Th.ANIMAL_TOP = {
    chick = 0.06, hen = 0.15, cockerel = 0.17, turkeypoult = 0.1, turkeyhen = 0.25, gobblers = 0.3,
    rabkitten = 0.05, rabdoe = 0.12, rabbuck = 0.12, mousepups = 0.03, mouse = 0.04, mousefemale = 0.04,
    ratbaby = 0.03, rat = 0.06, ratfemale = 0.06, raccoonkit = 0.1, raccoonsow = 0.16, raccoonboar = 0.17,
    piglet = 0.15, sow = 0.32, boar = 0.34, lamb = 0.2, ewe = 0.33, ram = 0.36,
    fawn = 0.3, doe = 0.45, buck = 0.5, cowcalf = 0.35, cow = 0.6, bull = 0.63,
}
Th.ANIMAL_TOP_DEFAULT = 0.3
Th.ANIMAL_AIM = 0.6   -- share of an animal's height the throw is aimed at

-- Posture of a zombie or player (user, 2026-11-08: sitting and lying zombies could not be targeted): "down" =
-- `isOnFloor()` (knocked down, crawling, fake dead, lying), "sit" = `isSitOnGround()` / `isSittingOnFurniture()` /
-- a zombie's `isSitAgainstWall()`, else "stand". Tops: 0.15 / 0.4 / 0.8 levels. A low target is aimed at its own
-- height (sitting: the head, SIT_AIM; lying: LOW_AIM) with the full drop correction, like an animal; a sitting one
-- can take a head hit (at or above SIT_HEAD of its top), a lying one takes body hits.
-- The server resolves the flight, but its copy of a zombie is not told `isOnFloor` (42.21 `NetworkZombieVariables`:
-- reanimated players only). Every ZombiePacket does carry the state the owner's zombie is in (`getRealState()`, the action
-- state's name; `NetworkZombiePacker.applyZombie`) and the crawling and sitting flags, so those answer for a zombie.
local ZOMBIE_DOWN_STATES = { falldown = true, onground = true, getup = true, fakedead = true }
Th.DOWN_TOP = 0.15
Th.SIT_TOP = 0.4
Th.SIT_AIM = 0.85   -- share of a sitting target's top aimed at (its head)
Th.SIT_HEAD = 0.75  -- at or above this share of a sitting target's top: a head hit
Th.LOW_AIM = 0.6    -- share of a lying target's top aimed at

local function bool(chr, method)
    local ok, v = pcall(function() return chr[method](chr) end)
    return ok and v == true
end

function Th.postureOf(chr, kind)
    if kind == "animal" then return "animal" end
    if bool(chr, "isOnFloor") then return "down" end
    local realState = nil
    if kind == "zombie" then
        if bool(chr, "isCrawling") then return "down" end
        local ok, state = pcall(function() return chr:getRealState() end)
        realState = ok and state or nil
        if ZOMBIE_DOWN_STATES[realState] then return "down" end
    end
    if bool(chr, "isSitOnGround") or bool(chr, "isSittingOnFurniture") or realState == "sitting"
        or (kind == "zombie" and bool(chr, "isSitAgainstWall")) then
        return "sit"
    end
    return "stand"
end

function Th.topOf(chr, kind)
    if kind == "animal" then
        local ok, t = pcall(function() return chr:getAnimalType() end)
        return (ok and Th.ANIMAL_TOP[t]) or Th.ANIMAL_TOP_DEFAULT
    end
    local posture = Th.postureOf(chr, kind)
    if posture == "down" then return Th.DOWN_TOP end
    if posture == "sit" then return Th.SIT_TOP end
    return Th.ZOMBIE_TOP
end

function Th.aimHeightOf(chr, kind)
    if kind == "animal" then return Th.topOf(chr, kind) * Th.ANIMAL_AIM end
    local posture = Th.postureOf(chr, kind)
    if posture == "down" then return Th.DOWN_TOP * Th.LOW_AIM end
    if posture == "sit" then return Th.SIT_TOP * Th.SIT_AIM end
    return Th.HEAD_HEIGHT
end

--- The part a throw at height h hits on this target.
function Th.partFor(chr, kind, h)
    if kind == "animal" then return "body" end
    local posture = Th.postureOf(chr, kind)
    if posture == "down" then return "body" end
    if posture == "sit" then return h >= Th.SIT_TOP * Th.SIT_HEAD and "head" or "body" end
    return Th.partAt(h)
end

--- Vanilla's PvP rules for a melee hit (`CombatManager.checkPVP`, 42.21), written out because on a server that Java
--- only returns the co-op flag (its checks run on the attacker's client): no PvP in single player; the target not in
--- god mode; server option PVP on; not both with the safety on (SafetySystem); neither in a non-PvP zone; not the
--- same faction unless either has faction PvP on.
function Th.pvpAllowed(a, b)
    if not (isClient() or isServer()) then return false end
    local ok, allowed = pcall(function()
        if not instanceof(a, "IsoPlayer") or not instanceof(b, "IsoPlayer") or b:isGodMod() then return false end
        local opts = getServerOptions()
        if not opts:getBoolean("PVP") then return false end
        if opts:getBoolean("SafetySystem") and a:getSafety():isEnabled() and b:getSafety():isEnabled() then
            return false
        end
        if NonPvpZone.getNonPvpZone(math.floor(b:getX()), math.floor(b:getY()))
            or NonPvpZone.getNonPvpZone(math.floor(a:getX()), math.floor(a:getY())) then
            return false
        end
        if not a:isFactionPvp() and not b:isFactionPvp() then
            local fa, fb = Faction.getPlayerFaction(a), Faction.getPlayerFaction(b)
            if fa ~= nil and fa == fb then return false end
        end
        return true
    end)
    return ok and allowed == true
end

local function isTarget(thrower, chr, kind, z)
    if not chr or chr == thrower or chr:isDead() or math.abs(chr:getZ() - z) >= 0.5 then return false end
    if kind == "zombie" then return not chr:isReanimatedForGrappleOnly() end   -- standing, sitting or lying
    if kind == "player" then return not chr:isInvisible() and Th.pvpAllowed(thrower, chr) end
    return true
end

--- Calls fn(chr, kind) for every target: all zombies and players of the cell, and the animals on the squares within
--- `radius` of (x, y) (animals have no cell-wide list that does not build a new one each call).
function Th.eachTarget(thrower, x, y, z, radius, fn)
    local cell = getCell()
    if not cell then return end
    local zombies = cell:getZombieList()
    if zombies then
        for i = 0, zombies:size() - 1 do
            local zed = zombies:get(i)
            if isTarget(thrower, zed, "zombie", z) then fn(zed, "zombie") end
        end
    end
    if isClient() or isServer() then
        local players = getOnlinePlayers()
        for i = 0, players:size() - 1 do
            local pl = players:get(i)
            if isTarget(thrower, pl, "player", z) then fn(pl, "player") end
        end
    end
    local fz = math.floor(z)
    for sx = math.floor(x - radius), math.floor(x + radius) do
        for sy = math.floor(y - radius), math.floor(y + radius) do
            local sq = cell:getGridSquare(sx, sy, fz)
            local animals = sq and sq:getAnimals()
            if animals then
                for i = 0, animals:size() - 1 do
                    local an = animals:get(i)
                    if isTarget(thrower, an, "animal", z) then fn(an, "animal") end
                end
            end
        end
    end
end

--- The nearest target within `radius` of (x, y); with `h`, only one whose body reaches that height. Returns chr, kind.
function Th.targetNear(thrower, x, y, z, radius, h)
    local best, bestKind, bestD = nil, nil, radius
    Th.eachTarget(thrower, x, y, z, radius, function(chr, kind)
        if h and h > Th.topOf(chr, kind) then return end
        local dx, dy = chr:getX() - x, chr:getY() - y
        local d = math.sqrt(dx * dx + dy * dy)
        if d < bestD then best, bestKind, bestD = chr, kind, d end
    end)
    return best, bestKind
end

-- Low fences (user, 2026-11-08: a throw could not cross a fence to a zombie behind it). `isBlockedTo` (42.21
-- `IsoGridSquare` ~932) = `isWallTo` or a blocked window, a blocked door or a stair side, and a low fence's edge is
-- a wall there. A low fence is a hoppable edge (`isHoppableTo`: sprite flag HoppableN / HoppableW, or an empty
-- window frame; tall fences carry TallHoppableN / W and do not count), so a throw crosses it while above FENCE_TOP and
-- hits it below; walls, tall fences, closed doors and closed windows always stop it.
Th.FENCE_TOP = 0.4   -- levels (about 1 m)

local function edgeBlocked(a, b, h)
    if not a:isBlockedTo(b) then return false end
    if h and h > Th.FENCE_TOP and a:isHoppableTo(b) and not a:isWindowBlockedTo(b) and not a:isDoorBlockedTo(b) then
        return false
    end
    return true
end

--- Whether a throw at height `h` (nil: no fence is crossed) is stopped between two neighbouring squares.
local function blocked(a, b, h)
    if not a or not b then return true end
    if a == b then return false end
    local dx, dy = b:getX() - a:getX(), b:getY() - a:getY()
    if math.abs(dx) + math.abs(dy) == 1 then return edgeBlocked(a, b, h) end
    -- diagonal: open only if both orthogonal ways are
    local cell = getCell()
    local s1 = cell:getGridSquare(a:getX() + dx, a:getY(), a:getZ())
    local s2 = cell:getGridSquare(a:getX(), a:getY() + dy, a:getZ())
    if not s1 or not s2 then return true end
    return (edgeBlocked(a, s1, h) or edgeBlocked(s1, b, h)) and (edgeBlocked(a, s2, h) or edgeBlocked(s2, b, h))
end

--- Height above the floor after flying `x` tiles toward a point `d` tiles away at `speed`, aimed at height `aimH`
--- there (a person's head by default).
function Th.heightAt(x, d, speed, aimH)
    local t = x / speed
    local aim = aimH or Th.HEAD_HEIGHT
    return Th.HAND_HEIGHT + (aim - Th.HAND_HEIGHT) * x / math.max(d, 0.5) - Th.GRAVITY / 2 * t * t
end

function Th.partAt(h)
    if h >= Th.HEAD_MIN then return "head" end
    if h < Th.LEGS_MAX then return "legs" end
    return "body"
end

-- Reaching what is outlined (user, 2026-11-08: outlined targets the spear fell short of). Thrown straight at the
-- aim point, gravity drops a throw by g / 2 (d / v)^2 at the target (0.33 levels at 8 tiles, 0.75 at 12), so past
-- ~11 tiles it hit the floor first, and a small animal (aimed at 0.6 of its height) almost at once. With a target,
-- the thrower now aims above it by part of that drop: it arrives no lower than `Th.ARRIVE_MIN[kind]` (a person: the
-- body, 0.35, so head hits up close and body hits farther out still come from the arc; an animal: its aim height,
-- the full drop). `launchAim` returns the point to aim at so it arrives there.
Th.ARRIVE_MIN = { zombie = 0.35, player = 0.35 }   -- levels; animals: their aim height (full correction)

function Th.launchAim(d, speed, aimH, kind, posture)
    local t = d / speed
    local drop = Th.GRAVITY / 2 * t * t
    local arrive = aimH - drop
    -- Partial correction only for a standing person; animals and sitting / lying people get the full drop.
    local floor = (posture == nil or posture == "stand") and Th.ARRIVE_MIN[kind] or aimH
    if arrive < floor then arrive = floor end
    return arrive + drop
end

--- True when nothing blocks a throw from the player to (tx, ty): the same square steps and `blocked` test the flight
--- uses (walls, closed doors and windows), so an outline is never shown through a wall.
--- With `speed` and `aimH` it follows the throw's arc, so a low fence counts as the flight counts it.
function Th.pathClear(player, tx, ty, speed, aimH)
    local x, y, z = player:getX(), player:getY(), player:getZ()
    local dx, dy = tx - x, ty - y
    local d = math.sqrt(dx * dx + dy * dy)
    if d < 0.001 then return true end
    dx, dy = dx / d, dy / d
    local cell = getCell()
    local square = player:getCurrentSquare()
    local travelled = 0
    while travelled < d do
        x, y = x + dx * Th.STEP, y + dy * Th.STEP
        travelled = travelled + Th.STEP
        local h = speed and Th.heightAt(travelled, d, speed, aimH) or nil
        local nextSq = cell:getGridSquare(math.floor(x), math.floor(y), math.floor(z))
        if not nextSq or blocked(square, nextSq, h) then return false end
        square = nextSq
    end
    return true
end

--- Flies from the thrower toward (tx, ty), aimed at height `aimH` there: returns endX, endY, target hit (or nil),
--- body part hit (animals: "body"), distance flown, kind of target.
function Th.fly(player, tx, ty, range, speed, aimH)
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
        local h = Th.heightAt(travelled + Th.STEP, d, speed, aimH)
        if not nextSq or blocked(square, nextSq, h) then return x, y, nil, nil, travelled end
        x, y, square = nx, ny, nextSq
        travelled = travelled + Th.STEP
        if h <= 0 then return x, y, nil, nil, travelled end   -- reached the floor first: lands here
        if travelled > 0.6 and h <= Th.ZOMBIE_TOP then
            local hit, kind = Th.targetNear(player, x, y, z, Th.HIT_RADIUS, h)
            if hit then
                local part = Th.partFor(hit, kind, h)
                return hit:getX(), hit:getY(), hit, part, travelled, kind
            end
        end
    end
    return x, y, nil, nil, travelled
end

-- The thrower's condition (user, 2026-11-08), vanilla's melee factors (`CombatManager` ~957-1090, 42.21) on the
-- weapon's roll: weapon skill (`HandWeapon.getDamageMod`: Axe / Spear 3-6 x1.1, 7+ x1.2) and Strength
-- (`getHittingMod`: 0.8 at 1 .. 1.0 at 5 .. 1.25 at 10), arm pain (Hand_L .. UpperArm_R summed, above 10 the damage
-- is divided by pain / 10, at most 30), Underweight traits (`getTraitDamageDealtReductionModifier`), Panic and
-- Stress above level 1 (minus 0.1 a level from vanilla's damageSplit, which is the roll x2 for a first hit, so 0.05
-- a level here; at least 0.05), then Endurance and Tired (each x0.5 / 0.2 / 0.1 / 0.05 at levels 1-4). Left out:
-- the reach factor and the multi-hit split, which belong to a swing. The server's body and moodles are the real ones.
local MOODLE_MULT = { [0] = 1, 0.5, 0.2, 0.1, 0.05 }
local function moodle(player, kind)
    local ok, level = pcall(function() return player:getMoodles():getMoodleLevel(MoodleType[kind]) end)
    return ok and tonumber(level) or 0
end

function Th.conditionDamage(player, weapon, base)
    local dmg = base * weapon:getDamageMod(player) * player:getHittingMod()
    local pain = 0
    local parts = player:getBodyDamage() and player:getBodyDamage():getBodyParts()
    if parts then
        for i = BodyPartType.ToIndex(BodyPartType.Hand_L), BodyPartType.ToIndex(BodyPartType.UpperArm_R) do
            pain = pain + parts:get(i):getPain()
        end
    end
    if pain > 10 then dmg = dmg / math.min(30, pain / 10) end
    local ok, traitMod = pcall(function()
        return player:getCharacterTraits():getTraitDamageDealtReductionModifier()
    end)
    if ok and tonumber(traitMod) then dmg = dmg * traitMod end
    for _, kind in ipairs({ "PANIC", "STRESS" }) do
        local level = moodle(player, kind)
        if level > 1 then dmg = dmg - 0.05 * level end
    end
    dmg = math.max(0.05, dmg)
    dmg = dmg * (MOODLE_MULT[moodle(player, "ENDURANCE")] or 0.05) * (MOODLE_MULT[moodle(player, "TIRED")] or 0.05)
    return dmg
end

local function damageFor(player, weapon, mastery, part)
    local base = ZombRandFloat(weapon:getMinDamage(), math.max(weapon:getMinDamage(), weapon:getMaxDamage()))
    return Th.conditionDamage(player, weapon, base) * (Th.THROW_DAMAGE[mastery] or 1)
        * M.more(player, mastery .. ".Damage") * (Th.DAMAGE[part] or 1)
end

-- A player's wound: vanilla's PvP path, `BodyDamage.DamageFromWeapon(weapon, part)` on the server (clothing defense
-- roll, hole, deep wound / laceration / scratch, pain, the weapon's damage x15, head and neck x4, upper torso x2,
-- server option PVPMeleeDamageModifier, syncVisuals; the body reaches its owner with the 2 s PlayerDamage sync). It
-- rolls its own damage from the weapon, as a vanilla PvP hit does, so the thrower's condition does not apply there.
local function bodyPartIndex(part)
    local pick
    if part == "head" then
        pick = { "Head" }
    elseif part == "legs" then
        pick = { "UpperLeg_L", "UpperLeg_R", "LowerLeg_L", "LowerLeg_R" }
    else
        pick = { "Torso_Upper", "Torso_Lower" }
    end
    return BodyPartType.ToIndex(BodyPartType[pick[ZombRand(#pick) + 1]])
end

-- The kill counter (reported 2026-11-08: thrown kills never counted): vanilla adds a zombie kill only in a hit's own
-- code (`IsoGameCharacter.hitConsequences` ~6219, on the attacker's client and again on the server), each side keeping
-- its own copy (the server's is saved, the client's is what the windows show). A throw skips that code, so both are
-- added here. In MP the owner's client takes the health and the server only learns of the death from a later
-- ZombiePacket, so the server judges a kill from its own copy of the health: two throws landing on one zombie before
-- that packet can both count.
local function creditKill(player)
    player:setZombieKills(player:getZombieKills() + 1)
    if isServer() then
        sendServerCommand(player, M.MODULE, "throwKill", { id = player:getOnlineID() })
    end
end

local function applyHit(player, target, kind, amount, part, weapon)
    if kind == "animal" then
        -- Vanilla's animal hit (`IsoAnimal.hitConsequences`, server / SP): health loss (damage x the animal's
        -- `getHealthLoss`), a wild one's flee and drop-dead timer, blood, the hit reaction, the kill credit, stress and
        -- an attack back for animals that do; health and death reach clients by AnimalPacket.
        target:hitConsequences(weapon, player, false, amount, false)
        return
    end
    if kind == "player" then
        target:getBodyDamage():DamageFromWeapon(weapon, bodyPartIndex(part))
        print(string.format("[TienSkillMastery] %s threw %s at %s (%s)", player:getUsername(), weapon:getFullType(),
            target:getUsername(), tostring(part)))
        return
    end
    -- A sitting or lying zombie takes the damage without the stagger (nothing to push back).
    local standing = Th.postureOf(target, "zombie") == "stand"
    local owner = isServer() and target:getOwnerPlayer() or nil
    if owner then
        -- The killer on the corpse: the server's `die()` kills with `getAttackedBy()`, as after a vanilla hit.
        target:setAttackedBy(player)
        local lethal = target:getHealth() <= math.min(amount, M.Relay.MAX_DAMAGE)
        if lethal then creditKill(player) end
        sendServerCommand(owner, M.MODULE, "zombieDamage", { id = target:getOnlineID(), amount = amount })
        if standing then
            sendServerCommand(owner, M.MODULE, "zombieActApply", { id = target:getOnlineID(), kind = "pushback",
                x = player:getX(), y = player:getY() })
            -- Everyone else sees the stagger too (see the relay), unless it is about to fall dead instead.
            if not lethal then M.Relay.show("pushback", { target:getOnlineID() }, player:getX(), player:getY()) end
        end
        return
    end
    target:setHealth(math.max(0, target:getHealth() - amount))
    if target:getHealth() <= 0 then
        creditKill(player)
        pcall(function() target:Kill(player) end)
    elseif standing then
        M.Relay.queueAct(target, "pushback", { x = player:getX(), y = player:getY() })
        if isServer() then M.Relay.show("pushback", { target:getOnlineID() }, player:getX(), player:getY()) end
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
    local b = M.markChance(weapon, "condition")
    local undo = 100 * (1 - (1 - a / 100) * (1 - b / 100))
    if undo > 0 and ZombRandFloat(0, 100) < undo then return end
    weapon:setCondition(math.max(0, weapon:getCondition() - 1), false)
end

--- Server / single player. Returns true when thrown.
--- `carried`: an axe or spear thrown with the throw key from the main inventory, not in hand; else the primary hand item.
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
    if not ok then return false end
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
    -- Aimed at the target at the aimed point (a person's head, part-way up an animal), else head height.
    local aimTarget, aimKind = Th.targetNear(player, tx, ty, z, 1.0)
    local aimH = Th.HEAD_HEIGHT
    if aimTarget then
        -- Aimed above the target by the drop it needs to reach it (see `Th.launchAim`).
        local ax, ay = aimTarget:getX() - fromX, aimTarget:getY() - fromY
        aimH = Th.launchAim(math.sqrt(ax * ax + ay * ay), speed, Th.aimHeightOf(aimTarget, aimKind), aimKind,
            Th.postureOf(aimTarget, aimKind))
    end
    local endX, endY, hit, part, travelled, kind = Th.fly(player, tx, ty, range, speed, aimH)

    -- Out of the hands (only a hand holding it: a carried throw leaves the held weapon where it is; user, 2026-11-08:
    -- the main weapon was unequipped by every carried throw) and the inventory.
    if player:getSecondaryHandItem() == weapon then player:setSecondaryHandItem(nil) end
    if player:getPrimaryHandItem() == weapon then player:setPrimaryHandItem(nil) end
    local container = weapon:getContainer()
    if container then
        container:DoRemoveItem(weapon)
        if isServer() then sendRemoveItemFromContainer(container, weapon) end
    end

    wearRoll(player, weapon, mastery)

    -- The hit and the landing wait for the flight (user, 2026-11-07: damage came before the axe got there): the
    -- flight time is the distance flown / speed, the same the clients draw it over (`Th.showFlight`).
    table.insert(Th.inFlight, { player = player, weapon = weapon, target = hit, kind = kind, part = part,
        damage = hit and damageFor(player, weapon, mastery, part) or 0, x = endX, y = endY, z = z,
        at = getTimestampMs() + math.max(60, (travelled or 0) / speed * 1000) })

    local fly = { type = weapon:getFullType(), fx = fromX, fy = fromY, z = z, tx = endX, ty = endY, aim = aim,
        speed = speed, spin = mastery ~= "Spearcraft", aimH = aimH }
    if isServer() then
        sendServerCommand(M.MODULE, "throwFly", fly)
    elseif Th.showFlight then
        Th.showFlight(fly)
    end
    return true
end

-- Server / single player: weapons in the air. The path (and so the target and body part) is worked out at the throw;
-- at arrival the target must still be alive (a player: still open to PvP) and within TRACK_RADIUS of where the
-- weapon was headed (it kept moving: a runner can leave the spot, a shambler rarely does), else the throw misses and
-- the weapon lands there anyway.
-- Server ticks are 100 ms apart, so an arrival can be up to that late.
Th.inFlight = Th.inFlight or {}
Th.TRACK_RADIUS = 1.0

local function arrive(f)
    local t = f.target
    if t and not t:isDead() and (f.kind ~= "player" or Th.pvpAllowed(f.player, t)) then
        local dx, dy = t:getX() - f.x, t:getY() - f.y
        if dx * dx + dy * dy <= Th.TRACK_RADIUS * Th.TRACK_RADIUS then
            -- The weapon's zombie hit sound, at the target, for everyone (see `Th.playHit`), before the hit (a kill
            -- turns the target into a corpse). The same message carries the flinch (`Th.showHit`), so it goes out
            -- for a weapon with no hit sound too.
            local data = { x = t:getX(), y = t:getY(), z = t:getZ(), sound = f.weapon:getZombieHitSound() }
            data.kind, data.id = f.kind, t:getOnlineID()
            data.tx, data.ty = f.player and f.player:getX(), f.player and f.player:getY()
            if isServer() then
                sendServerCommand(M.MODULE, "throwHit", data)
            elseif Th.playHit then
                -- Guarded: an error here must never stop the landing below (a sound error lost the thrown
                -- weapon twice on 2026-11-08).
                local ok, err = pcall(Th.playHit, data)
                if not ok then print("[TienSkillMastery] throw hit sound failed: " .. tostring(err)) end
            end
            local ok, err = pcall(applyHit, f.player, t, f.kind, f.damage, f.part, f.weapon)
            if not ok then print("[TienSkillMastery] thrown hit failed: " .. tostring(err)) end
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

local flights = {}   -- { item, fx, fy, z, tx, ty, start, duration, spin }
Th.SPEAR_YAW = 0     -- degrees added to the flight angle for a spear (see the render below)
-- How a thrown axe looks in flight (user, 2026-11-08): "tumble" = end over end, through the world item atlas (see the
-- render below); "still" = head first without turning (the live model, like a spear); "flat" = turning about the
-- vertical axis (the first version).
Th.AXE_FLIGHT = "tumble"
Th.TUMBLE_RATE = 900   -- degrees a second, head forward over the top
Th.TUMBLE_STEP = 22.5  -- tumble angle rounded to this (16 baked pictures a turn)
Th.YAW_STEP = 22.5     -- and the flight direction to this, for the baked pictures only

-- Blade first (user, 2026-11-08: the tumble was right but the head should lead with the blade). The edge has to lead
-- the tumble: down while the axe is level, facing the target when the head is up. Every vanilla one-handed axe mesh
-- (survey 2026-11-08: HandAxe, forged, old, bone, scrap, cleavers, ice axe, scythes) has the handle along mesh +Y and
-- the blade edge toward mesh -Z (the 0-thickness end of the head), but their `world` attachments differ (HandAxe 180 0
-- 180, the forged one 0 0 0), and `ItemModelRenderer.init` applies that attachment inverted before the weapon fix, so
-- the same edge lands on opposite sides. So per model: the handle and edge are carried through the attachment's
-- inverse (rotateXYZ, degrees) and the weapon fix (mesh (x, y, z) -> laid (y, x, -z)), a body rotation B takes them
-- to handle +X, edge -Y, and the drawn rotation Ry(yaw) Rz(tumble) B is turned back into the X / Y / Z angles the
-- renderer applies (Rx Ry Rz).
local function rotate(v, axis, deg)
    local r = math.rad(deg)
    local c, s = math.cos(r), math.sin(r)
    local x, y, z = v[1], v[2], v[3]
    if axis == "x" then return { x, y * c - z * s, y * s + z * c } end
    if axis == "y" then return { x * c + z * s, y, -x * s + z * c } end
    return { x * c - y * s, x * s + y * c, z }
end

local function cross(a, b)
    return { a[2] * b[3] - a[3] * b[2], a[3] * b[1] - a[1] * b[3], a[1] * b[2] - a[2] * b[1] }
end

local function norm(v)
    local l = math.sqrt(v[1] * v[1] + v[2] * v[2] + v[3] * v[3])
    if l < 1e-9 then return v end
    return { v[1] / l, v[2] / l, v[3] / l }
end

--- The model's `world` attachment rotation (degrees), 0 0 0 without one.
local function worldAttachRotate(modelName)
    local ok, rx, ry, rz = pcall(function()
        local script = getScriptManager():getModelScript(modelName)
        local att = script and script:getAttachmentById("world")
        local r = att and att:getRotate()
        if not r then return 0, 0, 0 end
        return r:x(), r:y(), r:z()
    end)
    if not ok then return 0, 0, 0 end
    return rx or 0, ry or 0, rz or 0
end

--- Mesh vector -> the laid-down frame the drawn rotations act on.
local function toLaid(v, ax, ay, az)
    -- inverse of rotateXYZ(ax, ay, az) = Rz(-az) Ry(-ay) Rx(-ax): Rx first
    v = rotate(v, "x", -ax)
    v = rotate(v, "y", -ay)
    v = rotate(v, "z", -az)
    return { v[2], v[1], -v[3] }
end

-- Extra roll about the handle (degrees), for setting the blade in game from the debug console:
-- `TienSkillMastery.Throw.BLADE_ROLL = 90` (then 180, 270) and throw across the screen. 0 = as worked out above.
Th.BLADE_ROLL = 0

local bladeBody = {}   -- [model name] = 3x3 rows, laid frame -> handle +X, edge -Y
function Th.bladeBody(modelName)
    local key = modelName or ""
    if bladeBody[key] then return bladeBody[key] end
    local ax, ay, az = worldAttachRotate(modelName)
    local h = norm(toLaid({ 0, 1, 0 }, ax, ay, az))
    local e = toLaid({ 0, 0, -1 }, ax, ay, az)
    local d = e[1] * h[1] + e[2] * h[2] + e[3] * h[3]
    e = norm({ e[1] - d * h[1], e[2] - d * h[2], e[3] - d * h[3] })
    local w = cross(h, e)
    -- B = targets x sources^T, sources h, e, w -> targets (1,0,0), (0,-1,0), (1,0,0) x (0,-1,0) = (0,0,-1)
    local tH, tE, tW = { 1, 0, 0 }, { 0, -1, 0 }, { 0, 0, -1 }
    local B = {}
    for r = 1, 3 do
        B[r] = {}
        for c = 1, 3 do B[r][c] = tH[r] * h[c] + tE[r] * e[c] + tW[r] * w[c] end
    end
    bladeBody[key] = B
    print(string.format("[TienSkillMastery] thrown axe model %s, world attachment rotate %.1f %.1f %.1f",
        tostring(modelName), ax, ay, az))
    return B
end

local function matMul(A, B)
    local C = {}
    for r = 1, 3 do
        C[r] = {}
        for c = 1, 3 do C[r][c] = A[r][1] * B[1][c] + A[r][2] * B[2][c] + A[r][3] * B[3][c] end
    end
    return C
end

local function matRot(axis, deg)
    local cols = { rotate({ 1, 0, 0 }, axis, deg), rotate({ 0, 1, 0 }, axis, deg), rotate({ 0, 0, 1 }, axis, deg) }
    return { { cols[1][1], cols[2][1], cols[3][1] }, { cols[1][2], cols[2][2], cols[3][2] },
        { cols[1][3], cols[2][3], cols[3][3] } }
end

--- Rotations (degrees, 0..360) for the renderer's Rx(a) Ry(b) Rz(c): returns a, b, c for Ry(yaw) Rz(tumble) B.
function Th.tumbleAngles(modelName, yaw, tumble)
    local R = matMul(matMul(matMul(matRot("y", yaw), matRot("z", tumble)), matRot("x", Th.BLADE_ROLL)),
        Th.bladeBody(modelName))
    local sb = math.max(-1, math.min(1, R[1][3]))
    local b = math.deg(math.asin(sb))
    local a, c
    if math.abs(sb) < 0.9999 then
        a = math.deg(math.atan2(-R[2][3], R[3][3]))
        c = math.deg(math.atan2(-R[1][2], R[1][1]))
    else
        a = 0
        c = math.deg(math.atan2(R[2][1], R[2][2]))
    end
    local function wrap(v) v = math.floor(v * 1000 + 0.5) / 1000; return v - math.floor(v / 360) * 360 end
    return wrap(a), wrap(b), wrap(c)
end

function Th.showFlight(args)
    local item = instanceItem(args.type)
    if not item then return end
    local dx, dy = args.tx - args.fx, args.ty - args.fy
    local d = math.sqrt(dx * dx + dy * dy)
    local speed = tonumber(args.speed) or 15
    table.insert(flights, { item = item, fx = args.fx, fy = args.fy, z = args.z, tx = args.tx, ty = args.ty,
        start = getTimestampMs(), duration = math.max(60, d / speed * 1000), dist = d,
        aim = tonumber(args.aim) or d, speed = speed, angle = math.deg(math.atan2(dy, dx)),
        spin = args.spin ~= false, aimH = tonumber(args.aimH) })
end

--- A thrown weapon's hit sound (user, 2026-11-07): the weapon script's `HitSound` (`getZombieHitSound`, HandAxeHit),
--- played as vanilla plays a melee hit, `playSoundImpl` on an emitter (local only, hence the server's broadcast),
--- here a free world emitter at the target's spot (see inside). A world emitter (`BaseSoundEmitter`) has both
--- `(String, IsoGridSquare)` and `(String, IsoObject)`; Kahlua picked the square one for a two-argument nil and it
--- reads `square.x` at once (NullPointerException, 2026-11-08), so it is called `(name, false, nil)`. (A character's
--- emitter, `BaseCharacterSoundEmitter`, has only `(String, IsoObject)` and refuses three arguments.)
-- Vanilla's melee hit sets the attacker's `MeleeHitSurface` FMOD parameter first (`CombatManager` ~815:
-- `ownerPlayer.setMeleeHitSurface(Material.Body)`, label 1; the player carries a `ParameterMeleeHitSurface`) and plays
-- the weapon's `HitSound` from the attacker. The throw plays it at the target, on an emitter with no such parameter,
-- so it stayed at Default (0): the spears' hit events (`Weapon/Melee/Spear/.../Hit`) are thought to pick their clip
-- by surface and played nothing there (user, 2026-11-08: no spear hit sound; axes were heard). So the parameter is set
-- on the played sound itself (`setParameterValueByName(handle, ...)`, as vanilla Lua sets CharacterVoicePitch).
Th.HIT_SURFACE = 1   -- ParameterMeleeHitSurface.Material.Body

local function setHitSurface(emitter, handle)
    if not handle or handle == 0 then return end
    -- Straight to the sound (a character emitter has no `isUsingParameter`): the just played sound waits in the
    -- emitter's to-start list, where `FMODSoundEmitter.setParameterValue` queues the value for its start; a sound
    -- without the parameter is not affected.
    pcall(function() emitter:setParameterValueByName(handle, "MeleeHitSurface", Th.HIT_SURFACE) end)
end

function Th.playHit(args)
    local sound = args.sound
    if type(sound) ~= "string" or sound == "" then return end
    -- At the spot, on a world emitter, for every kind of target (user, 2026-11-08: animals and players sound like
    -- zombies). Not on the target's own emitter: a character's sound only starts at that character's next update
    -- (`toStart`), and a target the hit kills becomes a corpse before that, so a killing hit was silent (user,
    -- 2026-11-08: only the death sound was heard). `IsoWorld` ticks every emitter in `currentEmitters` and returns
    -- it to the pool once its sounds end, whatever became of the target.
    local x, y, z = tonumber(args.x), tonumber(args.y), tonumber(args.z)
    if x and y and z then
        local emitter = getWorld():getFreeEmitter(x, y, z)
        if emitter then setHitSurface(emitter, emitter:playSoundImpl(sound, false, nil)) end
    end
end

--- What a thrown hit looks like on an MP client, on every client, the target's owner included, as vanilla's hit packet
--- does it (42.21 `fields/hit/Character.process` sets the reaction on every client). The damage is the server's.
--- Animal: `setHitReaction("hitreact")` (`IsoAnimal.hitConsequences` sets it only when not a client; the animal's
--- `hashitreaction` transition and `AnimalHitReactionState`, whose exit clears it) and the blood. Player: what
--- `IsoPlayer.hitConsequences` does for a PvP hit: hit force at most 0.5, "HitReaction", from behind or not, then the
--- `washitpvp` event and `hitpvp` variable (the `hitreactionpvp` node of every player state).
function Th.showHit(args)
    local id = tonumber(args.id)
    if not id then return end
    if args.kind == "animal" then
        local animal = getAnimal(id)
        if not animal or animal:isDead() then return end
        animal:setHitReaction("hitreact")
        animal:splatBloodFloorBig()
    elseif args.kind == "player" then
        local target = getPlayerByOnlineID(id)
        if not target or target:isDead() or target:getVehicle() or target:isAsleep() then return end
        target:setHitForce(math.min(0.5, target:getHitForce()))
        local tx, ty = tonumber(args.tx), tonumber(args.ty)
        if tx and ty then
            target:setHitFromBehind(target:getForwardDirectionX() * (tx - target:getX())
                + target:getForwardDirectionY() * (ty - target:getY()) < 0)
        end
        target:setHitReaction("HitReaction")
        target:reportEvent("washitpvp")
        target:setVariable("hitpvp", true)
        target:splatBloodFloorBig()
    end
end

Events.OnServerCommand.Add(function(module, command, args)
    if module == M.MODULE and command == "throwHit" and type(args) == "table" then
        Th.playHit(args)
        local ok, err = pcall(Th.showHit, args)
        if not ok then print("[TienSkillMastery] throw hit reaction failed: " .. tostring(err)) end
        return
    end
    if module == M.MODULE and command == "throwKill" and type(args) == "table" then
        local thrower = getPlayerByOnlineID(tonumber(args.id))
        if thrower and thrower:isLocalPlayer() then thrower:setZombieKills(thrower:getZombieKills() + 1) end
        return
    end
    if module == M.MODULE and command == "throwFly" and type(args) == "table" then
        Th.showFlight({ type = args.type, fx = tonumber(args.fx), fy = tonumber(args.fy), z = tonumber(args.z),
            tx = tonumber(args.tx), ty = tonumber(args.ty), aim = args.aim, speed = args.speed, spin = args.spin,
            aimH = args.aimH })
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
                -- Axes turn as they fly; spears fly point first (user, 2026-11-08: spears spun, then flew side
                -- on), at a fixed yaw along the flight. `Render3DItem`'s rotation is the world item's yaw in
                -- degrees, and `ItemModelRenderer` uses it only when >= 0 (a negative one falls back to the item's
                -- resting rotation, which is what threw spears side on for every throw with a negative atan2
                -- angle), so it is brought into 0..360. Traced (42.21): a weapon mesh (tip along model +Y, e.g.
                -- SpearCrafted.X 0.68 up) is laid down by `init`'s weapon fix rotateXYZ(0, pi, pi/2) (tip to +X),
                -- turned by Ry(yaw), and the world frame (`WorldModelCamera` Ry(-pi), `DoPushIsoStuff` scale(-1.5)
                -- + Ry(pi), frame X = world -x, Z = world -y) puts the tip at world (cos yaw, sin yaw): yaw =
                -- atan2(dy, dx) points it along the flight. SPEAR_YAW is left for a mod spear modelled otherwise.
                local h = math.max(0.02, Th.heightAt(f.dist * t, f.aim, f.speed, f.aimH))
                if f.spin and Th.AXE_FLIGHT == "tumble" then
                    -- End over end (user, 2026-11-08: tumble like a real axe, not a flat spin). The live model
                    -- path of `Render3DItem` takes only a yaw (with a rotation >= 0 `ItemModelRenderer` sets angle.x
                    -- and angle.z to 0), and no 3D model renderer is exposed to Lua. With a negative rotation it
                    -- uses the item's own rotations (angle.x = worldXRotation, angle.y = worldZRotation, angle.z =
                    -- worldYRotation), drawn from the world item atlas (on by default, `DebugOptions` WorldItemAtlas
                    -- Enable): a picture baked once per model + angles (`WorldItemAtlas.getItemKey`), the way vanilla
                    -- shows items tilted with Extended Placement. So the angles are rounded (TUMBLE_STEP, YAW_STEP)
                    -- and the pictures are shared by every throw of that model; a new one is baked a frame after it
                    -- is first asked for. The mesh is laid down tip along model +X, Rz(angle.z) turns the tip toward
                    -- model +Y (up), then Ry(yaw); in the world frame that is tip = (cos z forward, sin z up), so a
                    -- forward tumble (head going over the top) is a falling angle.
                    local yaw = math.floor(f.angle / Th.YAW_STEP + 0.5) * Th.YAW_STEP
                    yaw = yaw - math.floor(yaw / 360) * 360
                    local tumble = -(now - f.start) / 1000 * Th.TUMBLE_RATE
                    tumble = math.floor(tumble / Th.TUMBLE_STEP + 0.5) * Th.TUMBLE_STEP
                    tumble = tumble - math.floor(tumble / 360) * 360
                    -- Blade leading (see `Th.bladeBody`): renderer angle.x / y / z = world X / Z / Y rotation.
                    local model = f.model
                    if model == nil then
                        local ok, m = pcall(function() return f.item:getWeaponSprite() end)
                        model = ok and m or false
                        f.model = model
                    end
                    local a, bb, c = Th.tumbleAngles(model or nil, yaw, tumble)
                    f.item:setWorldXRotation(a)
                    f.item:setWorldZRotation(bb)
                    f.item:setWorldYRotation(c)
                    pcall(Render3DItem, f.item, square, x, y, f.z + h, -1)
                else
                    local rot
                    if f.spin and Th.AXE_FLIGHT == "flat" then
                        rot = f.angle + (now - f.start) * 0.9
                    else
                        rot = f.angle + (f.spin and 0 or Th.SPEAR_YAW)   -- "still" axes and spears: head first
                    end
                    rot = rot - math.floor(rot / 360) * 360
                    pcall(Render3DItem, f.item, square, x, y, f.z + h, rot)
                end
            end
        end
    end
end)

--- The target the aim points at, picked the way vanilla's melee picks (user, 2026-11-08: the on-screen body test
--- followed the pointer's tip, which sits at the top of the iso cursor). While aiming, `IsoPlayer.setAngleFromAim`
--- turns the player every update toward the pointer projected at chest height (`calculateAimVector`:
--- `AimingReticle` x / y = the mouse x zoom, `XToIso` / `YToIso` at `getAimOriginPosZ` = z + `getChestHeight()` 0.495),
--- so pointing at a body lines the facing up with it; melee then takes what lies in a cone around that facing
--- (`CombatManager.getNearestMeleeTargetPosAndDot`). Here: the first target along the facing (nearest along the
--- line, 0.5 .. range tiles out) within AIM_RADIUS of it, which is also what the flight would reach first.
--- Returns chr, kind.
Th.AIM_RADIUS = 0.6   -- tiles from the facing line
local function aimTarget(player, range, speed)
    local fwd = player:getForwardDirection()
    local dx, dy = fwd:getX(), fwd:getY()
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 0.001 then return nil end
    dx, dy = dx / len, dy / len
    local px, py, pz = player:getX(), player:getY(), player:getZ()
    local half = range / 2
    local best, bestKind, bestAlong = nil, nil, nil
    Th.eachTarget(player, px + dx * half, py + dy * half, pz, half + 1, function(chr, kind)
        local vx, vy = chr:getX() - px, chr:getY() - py
        local along = vx * dx + vy * dy
        if along < 0.5 or along > range then return end
        if math.abs(vx * dy - vy * dx) > Th.AIM_RADIUS then return end
        if not bestAlong or along < bestAlong then best, bestKind, bestAlong = chr, kind, along end
    end)
    -- Only what the throw can reach: nothing outlined behind a wall or closed door, or behind a low fence the arc
    -- would drop into (the same arc the server flies: `Th.launchAim`).
    if best then
        local bx, by = best:getX() - px, best:getY() - py
        local d = math.sqrt(bx * bx + by * by)
        local sp = speed or Th.SPEED.Axemanship
        local aimH = Th.launchAim(d, sp, Th.aimHeightOf(best, bestKind), bestKind, Th.postureOf(best, bestKind))
        if not Th.pathClear(player, best:getX(), best:getY(), sp, aimH) then return nil end
    end
    return best, bestKind
end
Th.aimTarget = aimTarget

--- The pointer projected at chest height, as vanilla's aim projects it (see `aimTarget`): where a throw at empty
--- ground goes.
function Th.aimPoint(player)
    local num = player:getPlayerNum()
    local h = player:getZ() + player:getChestHeight()
    local mx, my = getMouseX(), getMouseY()
    return screenToIsoX(num, mx, my, h), screenToIsoY(num, mx, my, h)
end

-- ---------------------------------------------------------------------------------------------------------------
-- The throw key (user, 2026-11-07), the only way to throw: a one-handed axe or a spear (2026-11-08) you carry
-- without it being in hand, from the main inventory first, then one attached to the hotbar, never from bags; only
-- with none of those the primary hand item (2026-11-08: spares before the held weapon; `Th.throwable`). Only in combat stance (aiming). Pressed with
-- a target along the aim (the facing, as vanilla's melee picks; see `aimTarget`) it is aimed at that target (a
-- person's head); otherwise at the pointer projected at chest height (`Th.aimPoint`, as vanilla's aim projects it). Within the weapon's throw range; player 0 on
-- the mouse only. A vanilla key binding ("[TienSkillMastery]" section, default Space, Options > Key bindings;
-- `keyBinding` entries are loaded by `MainOptions.loadKeys` into `getCore():addKeyBinding`, tested with
-- `getCore():isKey`). Space is vanilla's Melee key too (a shove in combat stance), so attacking is banned while the
-- key is down or a throw is queued (see `holdAttacks`); with nothing to throw, Space shoves as usual.
-- The throw is a short client-only action (no `complete`): it plays `AnimSets/player/actions/TsmThrowAxe.xml`
-- (vanilla's `Bob_AttackThrowMolotov`, the clip of the `ranged/Throw` attack node, here as an action node with a
-- release event; a carried weapon is put in the hand model) and at the release sends `throwWeapon { carried }`; for
-- a carried one the server checks it is directly in the main inventory and takes it off the hotbar.
-- ---------------------------------------------------------------------------------------------------------------

Th.KEY_NAME = "TsmThrowAxe"

-- A carried throwable (user, 2026-11-08: spears like axes): a one-handed axe or a spear of a mastery whose
-- signature the player has, not in hand, usable.
local function carriedMastery(player, item)
    if not instanceof(item, "HandWeapon") or item:getCondition() <= 0 then return nil end
    if item == player:getPrimaryHandItem() or item == player:getSecondaryHandItem() then return nil end
    local ok, mastery = Th.canThrow(player, item)
    return ok and mastery or nil
end

--- A throwable axe or spear in the main inventory: loose ones first, then hotbar-attached ones; never inside bags.
--- Returns item, mastery.
function Th.findCarried(player)
    local items = player:getInventory():getItems()
    local attached, attachedMastery = nil, nil
    for i = 0, items:size() - 1 do
        local it = items:get(i)
        local mastery = carriedMastery(player, it)
        if mastery then
            if it:getAttachedSlot() < 0 then return it, mastery end
            if not attached then attached, attachedMastery = it, mastery end
        end
    end
    return attached, attachedMastery
end

--- What the throw key would throw: item, mastery, carried. Spares first (user, 2026-11-08: consume the main inventory
--- first): a loose one in the main inventory, then one on the hotbar, and only then the primary hand item.
function Th.throwable(player)
    local item, mastery = Th.findCarried(player)
    if item then return item, mastery, true end
    local held = player:getPrimaryHandItem()
    if held and instanceof(held, "HandWeapon") and held:getCondition() > 0 then
        local ok, heldMastery = Th.canThrow(player, held)
        if ok then return held, heldMastery, false end
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
    -- The hand model first: `setActionAnim` enters PlayerActionsState on an MP client, and its `enter` captures the
    -- action's override and model name right there for the other clients (`PlayerActionsState.setParams`), so set after
    -- it they would see the thrower's real hand items instead of the carried weapon.
    if self.carried then self:setOverrideHandModels(self.item, nil) end
    self:setActionAnim("TsmThrowAxe")
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

--- The throw key pressed: aim, pick the weapon, queue the throw (see the header).
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
    local target = aimTarget(player, range, Th.SPEED[mastery])
    local tx, ty
    if target then
        tx, ty = target:getX(), target:getY()
    else
        tx, ty = Th.aimPoint(player)
        if not tx then return end
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
-- Target outline when a throw is possible (user, 2026-11-08; replaced a drawn copy of vanilla's aim reticle, which
-- the user found ugly). While aiming with something the throw key would throw (`Th.throwable`), the target the aim
-- points at within its throw range (`aimTarget`: zombie, animal, PvP player) gets an outline (colour below), the way vanilla's
-- melee outline marks what a swing would hit (`CombatManager.highlightMeleeTargets`: `setOutlineHighlight(index,
-- true)` + `setOutlineHighlightCol`). `IsoMovingObject.renderlast` clears an outline every frame unless it was set
-- during that frame's UI update or render (`FBORenderObjectOutline` keeps the UI time), so it is set again from
-- `OnPreUIDraw` every frame and goes away by itself once it is not. The colour is a per-player mod option
-- (client/TienSkillMastery_Options.lua, `M.throwOutlineColor`, user 2026-11-08), default `M.OUTLINE_COLOR`.
-- ---------------------------------------------------------------------------------------------------------------

local function outlineColor()
    return M.throwOutlineColor and M.throwOutlineColor() or M.OUTLINE_COLOR
end

local function throwTarget(player)
    if not player:isAiming() or player:getVehicle() then return nil end
    local item, mastery = Th.throwable(player)
    if not item then return nil end
    return aimTarget(player, Th.RANGE[mastery], Th.SPEED[mastery])
end

local outlined, outlinedAt = nil, 0
Events.OnPreUIDraw.Add(function()
    local player = getSpecificPlayer(0)
    if not player or player:isDead() or player:getJoypadBind() ~= -1 then return end
    -- The pick reads the squares along the aim for animals (~225), so it runs at most every 50 ms; the outline itself
    -- has to be set every frame.
    local now = getTimestampMs()
    if now - outlinedAt >= 50 then
        outlinedAt = now
        local ok, t = pcall(throwTarget, player)
        outlined = ok and t or nil
    end
    local target = outlined
    if not target or target:isDead() or not player:isAiming() then return end
    local c = outlineColor()
    local index = player:getPlayerNum()
    target:setOutlineHighlight(index, true)
    target:setOutlineHighlightCol(index, c.r, c.g, c.b, c.a)
end)
