--[[
Tien's Skill Mastery: Freerunning.SafeFall, no damage from drops of up to 1 floor (mastery 5) or 2 floors (mastery 10).

42.21 `IsoGameCharacter.updateFalling` (~9165): while falling, `lastFallSpeed` (public get / set) grows by
5.0010414 x dt per update (dt x 0.16 on a server) and the character drops `lastFallSpeed x dt + 2.5 x dt^2`; on
reaching the floor it calls `DoLand(impact speed)`. `handleLandingImpact` (IsoPlayer: only when not a client, so the
server or single player) takes health, knees and dropped items by the impact speed alone (`FallingConstants`, from a
height h in levels: speed = sqrt(2 x 5.001 x h); no damage below h 0.5 = 2.236, hard fall from 1.5). A 1-floor drop
lands at ~3.16, a 2-floor one at ~4.47.

So while a master falls and the floor below is within the allowed drop (measured from where the fall started), the
fall speed is held under the no-damage speed every update: the landing counts as a light, harmless one and the
drop takes about a quarter longer. Both sides do it: the owner's client (its own copy, which plays the landing) and,
in multiplayer, the server for every online player (the server's copy decides the damage).

The server does simulate every player's fall (traced 2026-11-10): a server player is remote, so
`IsoPlayer.updateInternal2` takes the `updateRemotePlayer()` branch and returns true, `updateInternal1` then runs
`IsoGameCharacter.update` → `updateInternal`, which calls `updateFalling` with no server guard. Its height is its
own: `NetworkPlayerAI.parse` sends only the whole level (`realz = (byte)z`) outside climbing. `OnTick` runs after the
cell update, so the cap set here applies from the next update.

The cap leaves room for one update's step: the landing update adds up to `5.001 x dt` (dt = `getTimeDelta()`, x 0.16
on a server: 0.08 a server update at 1x, five times that at 5x fast forward), so a fixed 90% cap (0.22 under the
threshold) took damage from about 3x on. Capped at the threshold minus 1.1 steps instead, at most 90%.
]]

require "TienSkillMastery"
local M = TienSkillMastery

local NO_DAMAGE = math.sqrt(2 * 5.0010414 * 0.5)
local CAP = NO_DAMAGE * 0.9

--- The highest speed from which the next update's landing still stays under the no-damage speed.
local function capNow()
    local dt = getGameTime():getTimeDelta()
    if isServer() then dt = dt * 0.16 end
    return math.max(0.1, math.min(CAP, NO_DAMAGE - 5.0010414 * dt * 1.1))
end

local starts = {}   -- [player] = z where the current fall started

function M.updateSafeFall(player)
    if not player or player:isDead() then return end
    local speed = player:getLastFallSpeed()
    if speed <= 0 then
        starts[player] = nil
        return
    end
    local startZ = starts[player]
    if not startZ then
        startZ = player:getZ()
        starts[player] = startZ
    end
    local allowed = M.val(player, "Freerunning.SafeFall")
    if allowed <= 0 then return end
    local cap = capNow()
    if speed <= cap then return end
    local floorZ = player:getZ() - player:getHeightAboveFloor()
    if startZ - floorZ <= allowed + 0.25 then
        player:setLastFallSpeed(cap)
    end
end

if isServer() then
    Events.OnTick.Add(function()
        local list = getOnlinePlayers()
        for i = 0, list:size() - 1 do M.updateSafeFall(list:get(i)) end
    end)
else
    Events.OnPlayerUpdate.Add(function(player)
        if player and player:isLocalPlayer() then M.updateSafeFall(player) end
    end)
end

Events.EveryHours.Add(function()
    for p in pairs(starts) do
        if p:isDead() then starts[p] = nil end
    end
end)
