--[[
Tien's Skill Mastery: Angling.BigHaul ("pct", phase 3c): a master's fishing nets catch more (server / single player).

42.21 server/Fishing/BuildingObjects/FishingNet.lua `fishingNet.checkTrap(player, trap, hours)` (~78, not on a
client): a net left more than 15 hours breaks 1 in 5 when checked; otherwise the hours since the last check (at most
20) are rolled one by one (1 in 8 a junk-or-fish item from `Fishing.fishNet`, and with bait a fish from
`Fishing.fishNetWithBait`), the items go to the checking player, then the bait and the timestamp are updated. The catch
belongs to whoever checks, so a master's check is followed by a second run of the same rolls for the bonus share of
the hours (fraction rolled). That run has at most 5 hours, so it never reaches vanilla's break roll, and the bait and
timestamp were just updated, so it uses up no extra bait.
]]

if isClient() then return end

require "TienSkillMastery"
local M = TienSkillMastery

local function wrap()
    if not fishingNet or not fishingNet.checkTrap or fishingNet.__tsmBigHaul then return end
    fishingNet.__tsmBigHaul = true
    local vanilla = fishingNet.checkTrap
    fishingNet.checkTrap = function(player, trap, hours, ...)
        local r = { vanilla(player, trap, hours, ...) }
        if player and trap and type(hours) == "number" and trap:getSquare() and trap:getObjectIndex() >= 0 then
            local extra = math.min(5, M.scaleInt(player, "Angling.BigHaul", math.min(hours, 20)) - math.min(hours, 20))
            if extra > 0 then
                local ok, err = pcall(vanilla, player, trap, extra, ...)
                if not ok then print("[TienSkillMastery] big haul failed: " .. tostring(err)) end
            end
        end
        return unpack(r)
    end
end
wrap()
Events.OnGameStart.Add(wrap)
Events.OnServerStarted.Add(wrap)
