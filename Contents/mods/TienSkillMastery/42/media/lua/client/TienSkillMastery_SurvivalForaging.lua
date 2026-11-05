--[[
Tien's Skill Mastery: Foraging search radius and spotting time (PlantScavenging.Radius, PlantScavenging.Spotting).
Vanilla 42.21 Lua, client/Foraging. Found item size is in shared/TienSkillMastery_SurvivalForageSize.lua.

Search mode is client only: the search manager (`ISSearchManager`, one per local player) and the forage icons
(`ISBaseIcon` and its subclasses ISForageIcon, ISWorldItemIcon, ISWorldItemIconTrack, ISStashIcon, none of which
override the methods below) live in the client folder and decide locally which icon the player sees and when it is
spotted. The server only checks the pick-up (`forageServer.onPickup`: icon record, 30 tiles), so these hooks run on
the owner's client (MP) or locally (single player), with the local player's mastery.

- PlantScavenging.Radius (pct):
  - `ISSearchManager:getOverlayRadius` (~1016): radius = min + (max - min) x level / 10 (min 3, max 10 from
    forageSystem, plus trait / profession bonuses), x penalties, x aim / sneak bonus, x light, clamped to
    [min, min(max x bonus, cap 15)]. It sets the overlay circle and `manager.radius` (`updateOverlay` ~1075), which
    `ISBaseIcon:isInRangeForUpdate` reads. Wrapped: result x bonus.
  - `ISBaseIcon:doVisionCheck` (~313): each icon's own view distance (min 3 + 0.5 x level + bonuses, same penalties
    and clamp, 1.5 in the dark), compared with the player distance in `updateSpotTimer` (~520). Wrapped: result x
    bonus. Icons are only updated while `isNearby()` (~655: distance <= `self.maxRadius`, 10 from forageSystem), and
    `updateAlpha` fades by the same field, so the wrapper also keeps the icon's `maxRadius` at its base x bonus
    (`doVisionCheck` reads `self.maxRadius` at its start, so it is put back to the base for that call) and `isNearby`
    is wrapped to use base x bonus too. The search manager's active icon radius is 20, so the extra reach (cap 15 x
    1.15) stays inside it.
- PlantScavenging.Spotting (less): `ISBaseIcon:updateSpotTimerMax` (~497) spotTimerMax = 300 + (11 - level) x 200 ms
  (500 at level 10), the stare time before an icon is spotted, recomputed in every `updateSpotTimer` call. Wrapped:
  result x (1 - bonus).

`isNearby` runs for every icon every frame, so the mastery value is cached per player for one second.
]]

require "TienSkillMastery"
require "Foraging/ISBaseIcon"
require "Foraging/ISSearchManager"

local M = TienSkillMastery

local cache = {}   -- [player] = { [id] = { t = ms, v = value } }

local function cachedVal(player, id)
    if not player then return 0 end
    local now = getTimestampMs()
    local byPlayer = cache[player]
    if not byPlayer then
        byPlayer = {}
        cache[player] = byPlayer
    end
    local e = byPlayer[id]
    if e and now - e.t < 1000 and now >= e.t then return e.v end
    local v = M.val(player, id)
    byPlayer[id] = { t = now, v = v }
    return v
end

local function radiusMult(player)
    return 1 + cachedVal(player, "PlantScavenging.Radius") / 100
end

local function pack(...)
    return { n = select("#", ...), ... }
end

-- ---------------------------------------------------------------------------------------------------------------
-- Overlay radius (search manager)
-- ---------------------------------------------------------------------------------------------------------------

if ISSearchManager and ISSearchManager.getOverlayRadius then
    local origOverlay = ISSearchManager.getOverlayRadius
    ISSearchManager.getOverlayRadius = function(self, ...)
        local r = pack(origOverlay(self, ...))
        if type(r[1]) == "number" then
            r[1] = r[1] * radiusMult(self.character)
        end
        return unpack(r, 1, r.n)
    end
end

-- ---------------------------------------------------------------------------------------------------------------
-- Icon view distance, nearby range, spotting time
-- ---------------------------------------------------------------------------------------------------------------

if ISBaseIcon then
    local function baseMaxRadius(icon)
        local base = icon.tsmBaseMaxRadius
        if not base then
            base = icon.maxRadius
            icon.tsmBaseMaxRadius = base
        end
        return base
    end

    local origVision = ISBaseIcon.doVisionCheck
    ISBaseIcon.doVisionCheck = function(self, ...)
        local base = baseMaxRadius(self)
        if type(base) ~= "number" then return origVision(self, ...) end
        self.maxRadius = base
        local r = pack(origVision(self, ...))
        local m = radiusMult(self.character)
        self.maxRadius = base * m
        if type(r[1]) == "number" then r[1] = r[1] * m end
        return unpack(r, 1, r.n)
    end

    local origNearby = ISBaseIcon.isNearby
    ISBaseIcon.isNearby = function(self, ...)
        local base = baseMaxRadius(self)
        if type(base) == "number" and self.distanceToPlayer then
            self.maxRadius = base * radiusMult(self.character)
        end
        return origNearby(self, ...)
    end

    local origSpotMax = ISBaseIcon.updateSpotTimerMax
    ISBaseIcon.updateSpotTimerMax = function(self, ...)
        local r = pack(origSpotMax(self, ...))
        if type(self.spotTimerMax) == "number" then
            local v = cachedVal(self.character, "PlantScavenging.Spotting")
            if v > 0 then
                self.spotTimerMax = self.spotTimerMax * math.max(0.05, 1 - v / 100)
            end
        end
        return unpack(r, 1, r.n)
    end
end
