--[[
Tien's Skill Mastery: movement speed as a position nudge (owner's client, single player and multiplayer).

- Swordsmanship.StrafeSpeed: strafing while aiming with a long blade. Why a nudge (42.21): the strafe nodes scale by
  the anim variable `StrafeSpeed`, which `calculateWalkSpeed` rewrites in single player right before the animator
  runs, with no Lua event in between, and an MP client only gets the server's value every 2 s; Nimble's own input
  caps at level 6. Overriding vanilla's strafe XML was declined (gun mods touch it, remote players would see vanilla).
- Stealth.SneakSpeed: sneak-walking. The sneak clips scale by `sneakLimpSpeedScale`, which
  `IsoPlayer.updateMovementRates` (~2404) resets every update after `OnPlayerUpdate`, and the animator runs right
  after the cell update with no Lua event between.

Each update the share of last update's displacement is added with `setX` / `setY` (movement is root motion), only
when the step stays on the same square or goes to an orthogonal neighbour that `isBlockedTo` does not refuse and that
`isFree(false)` (diagonal pairs always read unblocked, so diagonal crossings are skipped). The feet slide by the
share; the animation is not sped up. MP: the client owns its position; these speeds are far under the Speed
anti-cheat, and NoClip only refuses moves up a level. Steps over half a tile (teleports) are ignored.

Street Fighting's signature, bowl them over (phase 3b): sprinting with no endurance moodle, running into a zombie
knocks it down instead of tripping the master, at an endurance cost per zombie. Vanilla (42.21
`IsoMovingObject.separate` ~1221): a player moving fast enough bumps a character only when `getBumpedChr()` is not
that character, and a sprint bump always trips (`setBumpFall(true)`, then the "wasBumped" event). There is no Lua
event between that roll and the trip, but `setBumpedChr` is public: each update (`OnPlayerUpdate` runs before
`separate`) the nearest standing zombie within a tile in front is set as already bumped, so no trip is rolled
against it, and it is knocked down on its owner through the relay (`knockDown`, from behind when the master comes
from behind it; shared/TienSkillMastery_Relay.lua, kind "bowl", 0.02 endurance, taken by the server). Each zombie
at most once every 2 s. The two still push apart for that update (`isPushedByForSeparate`), then the zombie is on the
floor.
]]

if isServer() then return end

require "TienSkillMastery"
require "TienSkillMastery_Relay"
local M = TienSkillMastery

local bowled = {}   -- [zombie] = getTimestampMs() of its knockdown
local BOWL_REACH, BOWL_DOT = 1.0, 0.3

local function bowlOver(player)
    if not player:isSprinting() or player:getMoodles():getMoodleLevel(MoodleType.ENDURANCE) > 0 then return end
    if not M.sig(player, "StreetFighting.SigBowlOver") then return end
    local list = getCell() and getCell():getZombieList()
    if not list then return end
    local px, py = player:getX(), player:getY()
    local fx, fy = player:getForwardDirectionX(), player:getForwardDirectionY()
    local best, bestD = nil, BOWL_REACH
    for i = 0, list:size() - 1 do
        local z = list:get(i)
        if z and not z:isDead() and not z:isOnFloor() and not z:isReanimatedForGrappleOnly()
            and math.abs(z:getZ() - player:getZ()) < 0.5 then
            local dx, dy = z:getX() - px, z:getY() - py
            local d = math.sqrt(dx * dx + dy * dy)
            if d < bestD and d > 0.001 and (dx * fx + dy * fy) / d > BOWL_DOT then best, bestD = z, d end
        end
    end
    if not best then return end
    player:setBumpedChr(best)
    local now = getTimestampMs()
    if not bowled[best] or now - bowled[best] > 2000 then
        bowled[best] = now
        M.Relay.act(player, "bowl", { best })
    end
end

Events.EveryOneMinute.Add(function()
    local now = getTimestampMs()
    for z, t in pairs(bowled) do
        if now - t > 10000 then bowled[z] = nil end
    end
end)

local last = {}   -- [player num] = { x, y, z }

local function shareFor(player)
    if player:getVehicle() or player:isClimbing() or player:isRunning() or player:isSprinting() then return 0 end
    local share = 0
    if player:isAiming() and M.weaponMastery(player:getPrimaryHandItem()) == "Swordsmanship" then
        share = M.val(player, "Swordsmanship.StrafeSpeed")
    end
    if player:isSneaking() then
        share = math.max(share, M.val(player, "Stealth.SneakSpeed"))
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
