--[[
Tien's Skill Mastery: Fishing bonuses (Tension, Bait, BigFish, Junk, Trophy). Vanilla 42.21 Lua, shared/Fishing.

Where fishing runs in multiplayer:
- The owner's client builds its own rod (`client/Fishing/FishingStates.lua` ~52 `Fishing.FishingRod:new(player,
  joypad)`) and draws the line. The server builds a second rod for the same cast in Java `zombie/core/FishingAction.start`
  (~66: `rawget("new")` on `Fishing.FishingRod`, then `cast`) and runs `FishingRod:update` from `FishingAction.update`
  (~118). `FishingRod:updateLine` (FishingRod.lua ~113) returns at once on a server, so tension is the client's.
- Fish are rolled where the bobber is simulated: `Bobber:update` (Bobber.lua ~127) creates `Fishing.Fish:new` only
  when `not isClient()`, i.e. on the server in MP and locally in single player; `Fish:update` → `Fish:getFish` (~238) →
  `getFishByLure` (~68, junk) and `createFish` (~138, size and trophy). `FishingAction.update` sends the finished fish
  item to the owner (`FishingActionPacket` flagUpdateFish, full item bytes: weight, nutrition, name, modData) and the
  client copies it into its bobber (`Bobber.onFishingActionMPUpdate` ~262, with `fishItem` set, so `getFish` never runs
  there). So every catch roll is a server / single player hook.
- Bait: `FishingRod:consumeLure(isTrash)` (~359) returns on a client; the server calls it from `Bobber:destroy` (~257),
  single player from `FishingStates.PickupFish:start` (~301) and `FishingManager:disable` (~87). `removeLure` (~350)
  clears modData `fishing_Lure`, renames the rod and (server) sends the `fishing.consumeLure` server command to the
  owner (client ServerCommands.lua ~46). A skipped `removeLure` sends nothing, so the owner's rod keeps its lure too.

Bonuses:
- Fishing.Tension (pct): `updateLine` ~118 tensionLimit = (120 + 10 x level) x rodCoeff (x3 on a first fishing trip)
  is how long the line may stay at high / low tension before it breaks or the fish escapes. `rodCoeff` (~26) is read
  nowhere else, so the rod table's `rodCoeff` is multiplied once in `FishingRod.new` (client: the owner's local player).
- Fishing.Bait (pts on the keep chance): natural bait is consumed when ZombRand(20) > level (45% at 10, kept 55%),
  artificial lures 1 in 30 x (level + 1) (not touched: already 1 in 330). While `consumeLure` runs, the rod gets an
  instance `removeLure` that skips a natural bait's removal with chance points / consumed%, so the keep chance rises
  by exactly the bonus points.
- Fishing.Junk (less): `getFishByLure` returns (item, isTrash). On a trash result, with chance = the bonus percent, it
  is called again (up to 12 times) until it gives a fish, so junk catches drop by the bonus percent and the fish is
  drawn from vanilla's own fish branch (lure, river / lake, size limit, predators). A lure no fish takes stays junk.
- Fishing.BigFish (pts): `createFish` ~140 takes small / medium / big chances from
  `Fishing.Utils.getFishSizeChancesBySkillLevel(lvl, nearShore, fishNum)` (FishingUtils.lua ~185; 10 / 40 / 50 at
  level 10, halved to the small share near the shore, 100 / 0 / 0 when the school is empty). While our `createFish`
  wrapper runs, the bonus points move from the small share to the big one (empty schools left alone).
- Fishing.Trophy (pts): `createFish` ~153 rolls `ZombRand(20) == 0` (5%) for a Big fish at level 8+. It is the first
  `ZombRand` call of `createFish` (the size roll before it is `ZombRandFloat`), so during the call the global
  `ZombRand` is swapped for one that, on that first call with 20, turns a miss into 0 with chance points / 95: the
  trophy chance becomes 5% + points.
]]

require "TienSkillMastery"
require "Fishing/FishingUtils"
require "Fishing/FishingRod"
require "Fishing/Fish"

local M = TienSkillMastery

local function pack(...)
    return { n = select("#", ...), ... }
end

local function finish(r)
    if not r[1] then error(r[2], 0) end
    return unpack(r, 2, r.n)
end

if not (Fishing and Fishing.FishingRod and Fishing.Fish and Fishing.Utils) then return end

local FishingRod = Fishing.FishingRod
local Fish = Fishing.Fish

-- ---------------------------------------------------------------------------------------------------------------
-- Tension (client / single player; the server's rod never runs updateLine)
-- ---------------------------------------------------------------------------------------------------------------

local origRodNew = FishingRod.new
FishingRod.new = function(self, player, ...)
    local r = pack(origRodNew(self, player, ...))
    local o = r[1]
    if type(o) == "table" and player and type(o.rodCoeff) == "number" then
        o.rodCoeff = o.rodCoeff * M.more(player, "Fishing.Tension")
    end
    return unpack(r, 1, r.n)
end

-- ---------------------------------------------------------------------------------------------------------------
-- Bait kept (server / single player)
-- ---------------------------------------------------------------------------------------------------------------

local origConsumeLure = FishingRod.consumeLure
FishingRod.consumeLure = function(self, isTrash, ...)
    if isClient() or isTrash or not (self.rodItem and self.player) then
        return origConsumeLure(self, isTrash, ...)
    end
    local lure = self.rodItem:getModData().fishing_Lure
    local artificial = Fishing.lure and Fishing.lure.ArtificalLure and Fishing.lure.ArtificalLure[lure]
    local v = (lure ~= nil and not artificial) and M.val(self.player, "Fishing.Bait") or 0
    -- ZombRand(20) > level: 19 - level of the 20 outcomes consume the bait.
    local consumedPct = math.max(0, 19 - (self.skillLevel or 0)) * 5
    if v <= 0 or consumedPct <= 0 then
        return origConsumeLure(self, isTrash, ...)
    end
    local saveChance = math.min(1, v / consumedPct)
    self.removeLure = function(rod, ...)
        if ZombRandFloat(0, 1) < saveChance then return end
        return FishingRod.removeLure(rod, ...)
    end
    local r = pack(pcall(origConsumeLure, self, isTrash, ...))
    self.removeLure = nil
    return finish(r)
end

-- ---------------------------------------------------------------------------------------------------------------
-- Junk (server / single player)
-- ---------------------------------------------------------------------------------------------------------------

local JUNK_RETRIES = 12

local origGetFishByLure = Fish.getFishByLure
Fish.getFishByLure = function(self, ...)
    local r = pack(origGetFishByLure(self, ...))
    if r[2] and self.character and M.roll(self.character, "Fishing.Junk") then
        for _ = 1, JUNK_RETRIES do
            local again = pack(origGetFishByLure(self, ...))
            if again[1] ~= nil and not again[2] then return unpack(again, 1, again.n) end
        end
    end
    return unpack(r, 1, r.n)
end

-- ---------------------------------------------------------------------------------------------------------------
-- Big fish and trophies (server / single player)
-- ---------------------------------------------------------------------------------------------------------------

local bigFishPoints = nil   -- set while our createFish wrapper runs

local origSizeChances = Fishing.Utils.getFishSizeChancesBySkillLevel
Fishing.Utils.getFishSizeChancesBySkillLevel = function(lvl, isNearShore, fishNum, ...)
    local r = pack(origSizeChances(lvl, isNearShore, fishNum, ...))
    local pts = bigFishPoints
    if pts and pts > 0 and fishNum ~= 0 and type(r[1]) == "number" and type(r[3]) == "number" then
        local move = math.min(r[1], pts)
        r[1] = r[1] - move
        r[3] = r[3] + move
    end
    return unpack(r, 1, r.n)
end

local origCreateFish = Fish.createFish
Fish.createFish = function(self, fishConfig, ...)
    local chr = self.character
    if not chr then return origCreateFish(self, fishConfig, ...) end
    local big = M.val(chr, "Fishing.BigFish")
    local trophy = (self.fishingLvl or 0) >= 8 and M.val(chr, "Fishing.Trophy") or 0
    if big <= 0 and trophy <= 0 then return origCreateFish(self, fishConfig, ...) end

    bigFishPoints = big > 0 and big or nil
    local realRand = ZombRand
    local ours = nil
    if trophy > 0 then
        local armed = true
        local turnChance = (trophy / 100) / 0.95
        ours = function(n, ...)
            local v = realRand(n, ...)
            if armed then
                armed = false
                if n == 20 and select("#", ...) == 0 and v ~= 0 and ZombRandFloat(0, 1) < turnChance then
                    v = 0
                end
            end
            return v
        end
        ZombRand = ours
    end
    local r = pack(pcall(origCreateFish, self, fishConfig, ...))
    if ours and ZombRand == ours then ZombRand = realRand end
    bigFishPoints = nil
    return finish(r)
end
