--[[
Tien's Skill Mastery: Foraging search radius and spotting time (Fieldcraft.Radius, Fieldcraft.Spotting).
Vanilla 42.21 Lua, client/Foraging. Found item size is in shared/TienSkillMastery_SurvivalForageSize.lua.

Search mode is client only: the search manager (`ISSearchManager`, one per local player) and the forage icons
(`ISBaseIcon` and its subclasses ISForageIcon, ISWorldItemIcon, ISWorldItemIconTrack, ISStashIcon, none of which
override the methods below) live in the client folder and decide locally which icon the player sees and when it is
spotted. The server only checks the pick-up (`forageServer.onPickup`: icon record, 30 tiles), so these hooks run on
the owner's client (MP) or locally (single player), with the local player's mastery.

- Fieldcraft.Radius (pct):
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
- Fieldcraft.Spotting (less): `ISBaseIcon:updateSpotTimerMax` (~497) spotTimerMax = 300 + (11 - level) x 200 ms
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
    return 1 + cachedVal(player, "Fieldcraft.Radius") / 100
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
            local v = cachedVal(self.character, "Fieldcraft.Spotting")
            if v > 0 then
                self.spotTimerMax = self.spotTimerMax * math.max(0.05, 1 - v / 100)
            end
        end
        return unpack(r, 1, r.n)
    end
end

-- Fieldcraft.KeenEyes (phase 2): in search mode the darkness, weather and moving penalties fade with mastery (gone at
-- 10). `forageSystem.getLightLevelPenalty(chr, square, doReduction)`, `getWeatherPenalty(chr, square)` and
-- `getMovementVisionPenalty(chr)` (shared/Foraging/forageSystem.lua ~1751-1905, global, read by the client's search
-- manager and icons) return multipliers where 1 = no penalty; the result moves toward 1 by the bonus share. The
-- light penalty is only eased for the gameplay calls (`doReduction` true); the search mode's dark overlay
-- (`ISSearchManager` ~1071, doReduction false) is left as vanilla draws it.
if forageSystem and not forageSystem.__tsmKeenEyes then
    forageSystem.__tsmKeenEyes = true
    local function eased(chr, v)
        if type(v) ~= "number" or not chr or v >= 1 then return v end
        local share = math.min(1, cachedVal(chr, "Fieldcraft.KeenEyes") / 100)
        if share <= 0 then return v end
        return v + (1 - v) * share
    end
    local light, weather, moving = forageSystem.getLightLevelPenalty, forageSystem.getWeatherPenalty,
        forageSystem.getMovementVisionPenalty
    if light then
        forageSystem.getLightLevelPenalty = function(chr, square, doReduction, ...)
            local v = light(chr, square, doReduction, ...)
            if doReduction then return eased(chr, v) end
            return v
        end
    end
    if weather then
        forageSystem.getWeatherPenalty = function(chr, ...) return eased(chr, weather(chr, ...)) end
    end
    if moving then
        forageSystem.getMovementVisionPenalty = function(chr, ...) return eased(chr, moving(chr, ...)) end
    end
end

-- ---------------------------------------------------------------------------------------------------------------
-- Fieldcraft's signature (phase 3a), two parts, client only.
-- Forage while fighting (Fieldcraft.SigForageFighting): `ISSearchManager:checkShouldDisable` (~1092) turns search mode
-- off (after 15 checks in `doDisableCheck`) with any zombie very close, with 3+ visible and 3+ chasing zombies, and
-- while running or sprinting. For a master those three tests are dropped; the debug override, the Java search mode
-- override (`isOverrideSearchManager`, debug tools and scenarios) and the MP safehouse loot rule stay vanilla.
-- Sixth sense (Fieldcraft.SigZombieSense; dots over heads until 2026-11-08, then, user: "not icons, you actually see
-- them"): while a master is in search mode, what is inside the search circle (the manager's `radius`) is shown as if
-- seen. Characters (42.21): `IsoPlayer.updateLOS` (~5721, the local player's update) sets every moving object's
-- per-player target alpha to 0 when its square is not seen (1 when it is), each character's update moves its alpha
-- towards that (`IsoObject.updateAlpha`), and `FBORenderCell.renderMovingObject` draws every moving object on screen
-- with that alpha, LOS or not (the admin "See everyone" power, `isSeeEveryone`, skips the hiding the same way). So in
-- OnTick (after the updates, before the render) zombies, animals and other players in the circle on the player's
-- level get alpha and target alpha 1 for that player; they fade out the normal way once outside it. Corpses and floor
-- items are drawn whenever their square is (`calculateObjectRenderInfo`: renderAlpha 1, no cutaway); a square never
-- seen is drawn black (`CalcVisibility`, dark multiplier 0), so the circle's squares are marked seen
-- (`setIsSeen` + `checkLightingLater_OnePlayer_AllLevels`, which hands the bit to the native lighting; every 500 ms).
-- Not reachable: "can see now" is recomputed by the native lighting every frame, so out-of-sight squares keep their
-- dimming, and another building's inside stays under its roof (`FBORenderCutaways`). Client only; an MP client knows
-- the zombies, animals (AnimalPacket) and players near it. Skipped: corpses being dragged (`isReanimatedForGrappleOnly`),
-- hutched animals (not in the world), invisible players.
-- ---------------------------------------------------------------------------------------------------------------

if ISSearchManager and ISSearchManager.checkShouldDisable and not ISSearchManager.__tsmFighting then
    ISSearchManager.__tsmFighting = true
    local vanillaCheck = ISSearchManager.checkShouldDisable
    function ISSearchManager:checkShouldDisable(...)
        local chr = self.character
        if not chr or not M.sig(chr, "Fieldcraft.SigForageFighting") then return vanillaCheck(self, ...) end
        if ISSearchManager.showDebug then return false end
        if self.searchMode and self.searchMode:isOverrideSearchManager(self.player) then return true end
        if isClient() and self.square and not SafeHouse.isSafehouseAllowLoot(self.square, chr) then return true end
        return false
    end
end

local animalsCache, animalsAt = nil, 0

local function cachedAnimals()
    local now = getTimestampMs()
    if not animalsCache or now - animalsAt >= 250 then
        animalsAt = now
        -- A LinkedList built from the whole object list per call: copied once into an array.
        animalsCache = {}
        local ok, list = pcall(function() return getCell():getAnimals() end)
        if ok and list then
            local it = list:iterator()
            while it:hasNext() do animalsCache[#animalsCache + 1] = it:next() end
        end
    end
    return animalsCache
end

--- Calls fn(character) for every zombie, animal and other player the sense can show.
local function eachSensed(player, fn)
    local zombies = getCell() and getCell():getZombieList()
    if zombies then
        for j = 0, zombies:size() - 1 do
            local z = zombies:get(j)
            if z and not z:isDead() and not z:isReanimatedForGrappleOnly() then fn(z) end
        end
    end
    for _, a in ipairs(cachedAnimals()) do
        if not a:isDead() and a:getCurrentSquare() then fn(a) end
    end
    local others = isClient() and getOnlinePlayers() or nil
    if others then
        for j = 0, others:size() - 1 do
            local p = others:get(j)
            if p and p ~= player and not p:isDead() and not p:isInvisible() then fn(p) end
        end
    else
        for j = 0, getNumActivePlayers() - 1 do
            local p = getSpecificPlayer(j)
            if p and p ~= player and not p:isDead() then fn(p) end
        end
    end
end

local seenScanAt = {}   -- [player num] = getTimestampMs() of the last seen-square pass

--- Marks the circle's squares on the player's level as seen, so never-seen squares stop being drawn black.
local function markSeen(player, num, radius)
    local now = getTimestampMs()
    if seenScanAt[num] and now - seenScanAt[num] < 500 then return end
    seenScanAt[num] = now
    local cell = getCell()
    local px, py = player:getX(), player:getY()
    local z = math.floor(player:getZ())
    local r = math.ceil(radius)
    local r2 = radius * radius
    local relight = {}
    for x = math.floor(px) - r, math.floor(px) + r do
        for y = math.floor(py) - r, math.floor(py) + r do
            local dx, dy = x + 0.5 - px, y + 0.5 - py
            if dx * dx + dy * dy <= r2 then
                local sq = cell:getGridSquare(x, y, z)
                if sq and not sq:isSeen(num) then
                    sq:setIsSeen(num, true)
                    local chunk = sq:getChunk()
                    if chunk then relight[chunk] = true end
                end
            end
        end
    end
    for chunk in pairs(relight) do chunk:checkLightingLater_OnePlayer_AllLevels(num) end
end

local function sixthSense()
    if not ISSearchManager or not ISSearchManager.players then return end
    for i = 0, getNumActivePlayers() - 1 do
        local player = getSpecificPlayer(i)
        local manager = player and ISSearchManager.players[player]
        if manager and manager.isSearchMode and M.sig(player, "Fieldcraft.SigZombieSense") then
            local radius = tonumber(manager.radius) or 0
            if radius > 0 then
                local num = player:getPlayerNum()
                local px, py, pz = player:getX(), player:getY(), player:getZ()
                local r2 = radius * radius
                eachSensed(player, function(c)
                    if math.abs(c:getZ() - pz) < 1 then
                        local dx, dy = c:getX() - px, c:getY() - py
                        if dx * dx + dy * dy <= r2 then
                            c:setTargetAlpha(num, 1)
                            c:setAlpha(num, 1)
                        end
                    end
                end)
                markSeen(player, num, radius)
            end
        end
    end
end
local senseFailed = false
Events.OnTick.Add(function()
    local ok, err = pcall(sixthSense)
    if not ok and not senseFailed then
        senseFailed = true
        print("[TienSkillMastery] sixth sense failed: " .. tostring(err))
    end
end)

-- Angling.BaitDigger (phase 3c): foraging finds worms and insects more often. Vanilla's own lever is the category
-- "specialisation" professions and traits get (`forageSystem.getCategoryBonus(chr, catDef)` = 1 + points / 100,
-- forageSkills.lua: +5 .. +50 for "Insects" and "FishBait"), which scales how far and how readily that category's
-- icons are spotted (`ISBaseIcon` modifiers.categoryBonus, the zone display). The master's points are added there for
-- those two categories (worms are in "FishBait").
if forageSystem and forageSystem.getCategoryBonus and not forageSystem.__tsmBaitDigger then
    forageSystem.__tsmBaitDigger = true
    local vanillaBonus = forageSystem.getCategoryBonus
    local BAIT = { FishBait = true, Insects = true }
    forageSystem.getCategoryBonus = function(chr, catDef, ...)
        local v = vanillaBonus(chr, catDef, ...)
        if type(v) == "number" and chr and catDef and BAIT[catDef.name] then
            v = v + cachedVal(chr, "Angling.BaitDigger") / 100
        end
        return v
    end
end
