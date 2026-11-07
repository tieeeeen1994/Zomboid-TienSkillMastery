--[[
Tien's Skill Mastery: Tracking bonuses (Hunting.Find, Hunting.InspectTime). Vanilla 42.21 Lua + Java.

Finding tracks:
- `ISAnimalTracksFinder:update(chr)` (client/Foraging/ISAnimalTracksFinder.lua ~25) runs from the search manager's
  update (ISSearchManager ~1225, client, search mode on) and every 20 ticks calls the global
  `getAndFindNearestTracks(chr)` (~33). Java `LuaManager` ~8799: on an MP client it only sends `AnimalTracksPacket`
  (`GameClient.sendGetAnimalTracks`), whose `processServer` runs `AnimalTracks.getAndFindNearestTracks(player)` on the
  server; in single player it runs that directly and returns the list, which vanilla Lua turns into icons / glowing
  tiles (`ISAnimalTracksFinder.getAnimalTracks`, ~5). `AnimalTracks.getAndFindNearestTracks` (AnimalTracks.java ~141)
  takes every track within 20 + 2 x level tiles and rolls `canFindTrack` (~81): 1 in (definition + track chance) /
  ((level + 1) / 0.7), divided further by 2..3 with distance (by 20 within 4 tiles); a found track is added to the
  world and, on a server, sent to nearby clients (`OnAnimalTracks`). A miss gives 2-4 XP 1 in 10, a find 7-15 XP.
- Hunting.Find (pct): the find roll and its odds are Java with no Lua hook, so the bonus is extra find attempts: after
  each vanilla attempt (the 20-tick timer just ran out), with chance = the bonus percent, the client calls
  `getAndFindNearestTracks` once more (MP: one more request, rolled by the server with vanilla's odds; single player:
  the returned tracks are added exactly as vanilla adds them). With a per-attempt find chance p this gives
  p (1 + bonus x (1 - p)) per cycle, i.e. about bonus percent more finds for the small p of real tracking. Extra
  attempts can also give vanilla's miss / find XP, like a vanilla attempt.
- Not reachable: the search radius 20 + 2 x level (Java), animals noticing the player.

Inspecting a track:
- `ISInspectAnimalTrackAction` (client/TimedActions/Animal/ISInspectAnimalTrackAction.lua) is client only: it has no
  `complete`, so it never becomes a server action in MP. `getDuration` (~50) = 100 - 1.5 x level (1 with
  `isTimedActionInstant`); `new` (~57) sets `maxTime = o:getDuration()`. Hunting.InspectTime (less): the wrapper
  scales `getDuration` (not the instant 1).
]]

require "TienSkillMastery"
require "Foraging/ISAnimalTracksFinder"
require "TimedActions/Animal/ISInspectAnimalTrackAction"

local M = TienSkillMastery

local function pack(...)
    return { n = select("#", ...), ... }
end

-- ---------------------------------------------------------------------------------------------------------------
-- Extra find attempts
-- ---------------------------------------------------------------------------------------------------------------

if ISAnimalTracksFinder and ISAnimalTracksFinder.update then
    local origUpdate = ISAnimalTracksFinder.update
    ISAnimalTracksFinder.update = function(self, chr, ...)
        local due = (tonumber(ISAnimalTracksFinder.tick) or 0) <= 0
        local r = pack(origUpdate(self, chr, ...))
        if due and chr and M.roll(chr, "Hunting.Find") then
            local tracks = getAndFindNearestTracks(chr)
            if not isClient() and tracks then
                for i = 0, tracks:size() - 1 do
                    ISAnimalTracksFinder.getAnimalTracks(chr, tracks:get(i))
                end
            end
        end
        return unpack(r, 1, r.n)
    end
end

-- ---------------------------------------------------------------------------------------------------------------
-- Inspection time
-- ---------------------------------------------------------------------------------------------------------------

if ISInspectAnimalTrackAction and ISInspectAnimalTrackAction.getDuration then
    local origDuration = ISInspectAnimalTrackAction.getDuration
    ISInspectAnimalTrackAction.getDuration = function(self, ...)
        local r = pack(origDuration(self, ...))
        local chr = self.character
        if chr and type(r[1]) == "number" and r[1] > 1 and not chr:isTimedActionInstant() then
            r[1] = r[1] * M.less(chr, "Hunting.InspectTime")
        end
        return unpack(r, 1, r.n)
    end
end
