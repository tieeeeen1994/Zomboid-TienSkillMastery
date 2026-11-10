--[[
Tien's Skill Mastery: movement speed as a position nudge (owner's client, single player and multiplayer).

- Swordsmanship.StrafeSpeed: strafing while aiming with a long blade. Why a nudge (42.21): the strafe nodes scale by
  the anim variable `StrafeSpeed`, which `calculateWalkSpeed` rewrites in single player right before the animator
  runs, with no Lua event in between, and an MP client only gets the server's value every 2 s; Nimble's own input
  caps at level 6. Overriding vanilla's strafe XML was declined (gun mods touch it, remote players would see vanilla).
- Crouched movement (Freerunning.CrouchSpeed below; Stealth.SneakSpeed until 2026-11-11). The sneak clips scale by `sneakLimpSpeedScale`, which
  `IsoPlayer.updateMovementRates` (~2404) resets every update after `OnPlayerUpdate`, and the animator runs right
  after the cell update with no Lua event between.
- Freerunning.SprintSpeed (user, 2026-11-11): sprinting. The sprint clips are root motion too, and the Sprinting
  skill only feeds the run / sprint blend. Speed anti-cheat (42.21 `AntiCheatSpeed`): the server measures each
  player's distance over about a second (`NetworkCharacterAI.SpeedChecker`, tiles per second) and refuses a player on
  foot above 20 tiles a second; a sprint is a fraction of that, so 15% more is far under it. Only while
  `isSprinting()` (Java keeps a player among trees at a run, so no sprint bonus there).
- Freerunning.RunSpeed (user, 2026-11-11): running (not sprinting), the same nudge, 10% at mastery 10.
- Freerunning.CrouchSpeed (user, 2026-11-11): crouched (sneaking), walking or running, 5% at mastery 10; a crouched
  run takes it instead of RunSpeed. It replaced Stealth.SneakSpeed (Stealth is to be about noise instead, user).

Each update the share of last update's displacement is added with `setX` / `setY` (movement is root motion), only
when the step stays on the same square or goes to an orthogonal neighbour that `isBlockedTo` does not refuse and that
`isFree(false)` (diagonal pairs always read unblocked, so diagonal crossings are skipped). The feet slide by the
share; the animation is not sped up. MP: the client owns its position; these speeds are far under the Speed
anti-cheat, and NoClip only refuses moves up a level. Steps over half a tile (teleports) are ignored.

Street Fighting's signature, battering ram (phase 3b; named "bowl them over" until 2026-11-08, still `SigBowlOver` and
relay kind "bowl" in code): sprinting with at most the first endurance moodle (the
warning; user, 2026-11-08, was: none), running into a zombie
knocks it down instead of tripping the master, at an endurance cost per zombie. Vanilla (42.21
`IsoMovingObject.separate` ~1221): a player moving fast enough bumps a character only when `getBumpedChr()` is not
that character, and a sprint bump always trips (`setBumpFall(true)`, then the "wasBumped" event). There is no Lua
event between that roll and the trip, but `setBumpedChr` is public: each update (`OnPlayerUpdate` runs before
`separate`) the nearest standing zombie within a tile is set as already bumped, so no trip is rolled against it, and it is knocked down on its owner through the relay (`knockDown`, from behind when the master comes
from behind it; shared/TienSkillMastery_Relay.lua, kind "bowl", 0.02 endurance, taken by the server). Each zombie
at most once every 2 s. The two still push apart for that update (`isPushedByForSeparate`), then the zombie is on the
floor.
Any direction (user, 2026-11-08: zombies standing still still tripped the master): vanilla bumps on contact from any
angle (`len < twidth`, both widths, positions after this update's move), and a zombie standing still is usually
brushed at an angle while running past it, so the first version's cone (within ~70 degrees of the facing) missed it.
`setBumpedChr` holds one character, so it shields only the nearest zombie, and two zombies tripped the master (user,
2026-11-08: the first one, still staggering, stayed the nearest). So every standing zombie within NONSOLID_REACH is
also made not solid for that update: vanilla bumps (and trips) only on objects that `isSolidForSeparate`, which is
false while `solid` is false (`IsoMovingObject` ~1174), and `IsoZombie` sets `solid = true` again in its own update
(~3407), so the flag cannot stick; it is set here, inside the player's update right before its `separate`, every
update, and put back at once for a zombie no longer in reach.
]]

if isServer() then return end

require "TienSkillMastery"
require "TienSkillMastery_Relay"
local M = TienSkillMastery

local bowled = {}   -- [zombie] = getTimestampMs() of its knockdown
local BOWL_REACH = 1.0       -- tiles: the nearest zombie this close is shielded from the trip roll
local NONSOLID_REACH = 0.8   -- tiles: every standing zombie this close is not solid for this update (no bump at all)
local BOWL_CONTACT = 0.65    -- tiles: and knocked down once this close (vanilla's contact: the two widths, ~0.5,
                             -- against next positions), so one merely passed is not
local unsolid = {}           -- [zombie] = true while made not solid here

local function restoreSolid(keep)
    for z in pairs(unsolid) do
        if not keep or not keep[z] then
            pcall(function() z:setSolid(true) end)
            unsolid[z] = nil
        end
    end
end

local function bowlOver(player)
    -- Still on at the first endurance moodle, a warning; off from the second (user, 2026-11-08).
    if not player:isSprinting() or player:getMoodles():getMoodleLevel(MoodleType.ENDURANCE) > 1
        or not M.sig(player, "StreetFighting.SigBowlOver") then
        restoreSolid(nil)
        return
    end
    local list = getCell() and getCell():getZombieList()
    if not list then return end
    local px, py = player:getX(), player:getY()
    local best, bestD = nil, BOWL_REACH
    local near, knock = {}, {}
    for i = 0, list:size() - 1 do
        local z = list:get(i)
        if z and not z:isDead() and not z:isOnFloor() and not z:isReanimatedForGrappleOnly()
            and math.abs(z:getZ() - player:getZ()) < 0.5 then
            local dx, dy = z:getX() - px, z:getY() - py
            local d = math.sqrt(dx * dx + dy * dy)
            if d < bestD and d > 0.001 then best, bestD = z, d end
            if d <= NONSOLID_REACH then
                near[z] = true
                if d <= BOWL_CONTACT then knock[#knock + 1] = z end
            end
        end
    end
    restoreSolid(near)
    for z in pairs(near) do
        z:setSolid(false)
        unsolid[z] = true
    end
    if best then player:setBumpedChr(best) end
    local now = getTimestampMs()
    local due = {}
    for _, z in ipairs(knock) do
        if not bowled[z] or now - bowled[z] > 2000 then
            bowled[z] = now
            due[#due + 1] = z
        end
    end
    if #due > 0 then M.Relay.act(player, "bowl", due) end
end

Events.EveryOneMinute.Add(function()
    local now = getTimestampMs()
    for z, t in pairs(bowled) do
        if now - t > 10000 then bowled[z] = nil end
    end
end)

local last = {}   -- [player num] = { x, y, z }

local function shareFor(player)
    if player:getVehicle() or player:isClimbing() then return 0 end
    if player:isSneaking() then return M.val(player, "Freerunning.CrouchSpeed") / 100 end
    if player:isSprinting() then return M.val(player, "Freerunning.SprintSpeed") / 100 end
    if player:isRunning() then return M.val(player, "Freerunning.RunSpeed") / 100 end
    local share = 0
    if player:isAiming() and M.weaponMastery(player:getPrimaryHandItem()) == "Swordsmanship" then
        share = M.val(player, "Swordsmanship.StrafeSpeed")
    end
    return share / 100
end

local function canStep(from, to)
    if not from or not to then return false end
    if from == to then return true end
    local dx, dy = to:getX() - from:getX(), to:getY() - from:getY()
    if math.abs(dx) + math.abs(dy) ~= 1 or to:getZ() ~= from:getZ() then return false end
    return not from:isBlockedTo(to) and to:isFree(false)
end

local function onPlayerUpdate(player)
    if not player or not player:isLocalPlayer() then return end
    bowlOver(player)
    local num = player:getPlayerNum()
    local x, y, z = player:getX(), player:getY(), player:getZ()
    local prev = last[num]
    last[num] = { x, y, z }
    if not prev or prev[3] ~= z or not player:isPlayerMoving() then return end
    local dx, dy = x - prev[1], y - prev[2]
    local step = dx * dx + dy * dy
    if step <= 0.0000001 or step > 0.25 then return end
    local share = shareFor(player)
    if share <= 0 then return end
    local nx, ny = x + dx * share, y + dy * share
    local from = player:getCurrentSquare()
    local to = getCell():getGridSquare(math.floor(nx), math.floor(ny), math.floor(z))
    if not canStep(from, to) then return end
    player:setX(nx)
    player:setY(ny)
    last[num] = { nx, ny, z }
end
Events.OnPlayerUpdate.Add(onPlayerUpdate)
