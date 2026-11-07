--[[
Tien's Skill Mastery: Freerunning.SafeFall, no damage from drops of up to 1 floor (mastery 5) or 2 floors (mastery 10).

42.21 `IsoGameCharacter.updateFalling` (~9165): while falling, `lastFallSpeed` (public get / set) grows by
5.0010414 x dt per update (dt x 0.16 on a server) and the character drops `lastFallSpeed x dt + 2.5 x dt^2`; on
reaching the floor it calls `DoLand(impact speed)`. `handleLandingImpact` (IsoPlayer: only when not a client, so the
server or single player) takes health, knees and dropped items by the impact speed alone (`FallingConstants`, from a
height h in levels: speed = sqrt(2 x 5.001 x h); no damage below h 0.5 = 2.236, hard fall from 1.5). A 1-floor drop
lands at ~3.16, a 2-floor one at ~4.47.

So while a master falls and the floor below is within the allowed drop (measured from where the fall started), the
fall speed is held at 90% of the no-damage speed every update: the landing counts as a light, harmless one and the
drop takes about a quarter longer. Both sides do it: the owner's client (its own copy, which plays the landing) and,
in multiplayer, the server for every online player (the server's copy decides the damage). Not yet checked in MP
whether the server runs `updateFalling` for players; if it does not, its part does nothing.
]]

require "TienSkillMastery"
local M = TienSkillMastery

local NO_DAMAGE = math.sqrt(2 * 5.0010414 * 0.5)
local CAP = NO_DAMAGE * 0.9

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
    if allowed <= 0 or speed <= CAP then return end
    local floorZ = player:getZ() - player:getHeightAboveFloor()
    if startZ - floorZ <= allowed + 0.25 then
        player:setLastFallSpeed(CAP)
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
