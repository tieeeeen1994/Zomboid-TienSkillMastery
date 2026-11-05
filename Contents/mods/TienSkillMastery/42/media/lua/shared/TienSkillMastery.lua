--[[
Tien's Skill Mastery: shared core (data, cost curve, bonus table, XP parking helpers).

Why mastery and not levels 11+ (42.21 jar): every perk has only xp1..xp10, `XP.AddXP` caps XP at
`getTotalXpForLevel(10)` and returns early (no Lua `AddXP` event) once a skill is there, `LevelPerk` clamps the level
to 10, and 14 Java tables end `level == 10 ? best : default`, so a real level 11 would fall back to about level 0.

How XP past 10 is caught ("parking", server / single player only):
- XP only lands on the server in MP. The Lua `AddXP(character, perk, amount)` event fires at the end of `XP.AddXP`
  for every award (whenever not a client), after traits, boosts, sandbox multipliers and the clamp.
- A level-10 skill keeps its real XP at total(10) - PARK_MARGIN. A gain then lands normally (no level-up: that needs
  total(11) = total(10), which only a gain >= PARK_MARGIN reaches), the event hands us the amount, it becomes mastery
  XP and the skill is parked again.
- Lua cannot write XP directly: `xpMap` is a field and the only writers are `AddXP` and `setXPToLevel` (level
  boundaries only). So XP is moved with the 6-argument `AddXP(perk, delta, false, false, false, false)` (no boosts;
  the Strength protein factor still applies and is divided out). A move that would cross a level boundary is done with
  the level set to 0 for that one synchronous call (`setPerkLevelDebug`, no event and no packet on a server), so
  neither the level-up nor the lose-level loop fires.
- Why the margin is only 240: the XP anti-cheat (`AntiCheatXPUpdate`, server option AntiCheatXP, default 2 = kick)
  compares each perk's server XP with a snapshot taken every 60 s and flags a rise above 1000 x multiplier x boost
  factor (at least 250). Parking only lowers XP; the one upward move (mastery used up by Strength / Fitness decay, back
  to vanilla's total(10) - rest) nets at most PARK_MARGIN against the snapshot.
- `XP:getXP` is wrapped (both sides) to report total(10) for a parked skill, so the skill panel, Skill Journal and
  vanilla's Strength / Fitness decay (`xpUpdate.checkForLosingLevel`, which demotes a skill whose XP is below
  total(level)) see vanilla values. Java readers of the XP map are only `AddXP` and the anti-cheat.
- Negative XP (Strength / Fitness idleness, -1 per step) comes out of mastery first; with none left the skill drops
  below 10 as in vanilla.
- A gain of PARK_MARGIN or more in one award is clamped by Java and shows vanilla's "+1 skill" halo once (the skill is
  already 10). No vanilla award comes near it.

Storage: global mod data `TienSkillMastery` (server / single player), keyed by username. Not player modData: a
client's `transmitModData()` of its player (vanilla hotbar, crafting favourites) sends an `ObjectModDataPacket` that
replaces the server's whole player modData with the client's copy. Clients get their own entry by server command.
]]

TienSkillMastery = TienSkillMastery or {}
local M = TienSkillMastery

M.MODULE = "TienSkillMastery"
M.BONUS_LEVELS = 10
M.PARK_MARGIN = 240
-- XP is a Java float: at Strength / Fitness totals (~325000) values land only within 1/32, so park checks allow 0.1.
M.EPS = 0.1

-- ---------------------------------------------------------------------------------------------------------------
-- Settings (no sandbox options for now)
-- ---------------------------------------------------------------------------------------------------------------

--- Every tunable value. No sandbox options for now (user, 2026-11-06: values stay in the author's hands); the
--- defaults passed by each caller are the values. scripts/make_options.py can bring the options back.
M.SETTINGS = {}

function M.option(name, default)
    local v = M.SETTINGS[name]
    if v == nil then return default end
    return v
end

-- ---------------------------------------------------------------------------------------------------------------
-- Perks
-- ---------------------------------------------------------------------------------------------------------------

local perkList, perkById
local function indexPerks()
    perkList, perkById = {}, {}
    for i = 0, Perks.getMaxIndex() - 1 do
        local perk = PerkFactory.getPerk(Perks.fromIndex(i))
        if perk and perk:getParent() ~= Perks.None then
            table.insert(perkList, perk)
            perkById[perk:getId()] = perk
        end
    end
end

--- Every real skill (categories left out), as PerkFactory.Perk objects.
function M.perks()
    if not perkList then indexPerks() end
    return perkList
end

function M.perk(id)
    if not perkById then indexPerks() end
    return perkById[id]
end

function M.perkId(perk)
    if type(perk) == "string" then return perk end
    return perk and perk:getId()
end

function M.total10(perk)
    return perk:getTotalXpForLevel(10)
end

function M.parkValue(perk)
    return M.total10(perk) - M.PARK_MARGIN
end

-- ---------------------------------------------------------------------------------------------------------------
-- Cost curve: mastery level n costs xp10 x base% x (1 + growth%)^n, compounding from the skill's own level-10 step
-- (user, 2026-11-06: 5% per level, never the bare 9000; no XP boosters reach mastery, so it stays tough).
-- xp10 = `getXpForLevel(10)`, already x1.5 from `PerkFactory.AddPerk`: 9000 for most skills, 150000 for Fitness and
-- Strength. Each level's cost is rounded to whole hundreds. Defaults: mastery 1 = 9500, mastery 10 = 14700,
-- mastery 1-10 together = 119000 for a 9000-step skill.
-- ---------------------------------------------------------------------------------------------------------------

function M.costFor(perk, n)
    local base = math.max(1, tonumber(M.option("MasteryCostBase", 100)) or 100) / 100
    local growth = math.max(0, tonumber(M.option("MasteryCostGrowth", 5)) or 5) / 100
    -- Rounded to whole hundreds (user, 2026-11-06), at least 100.
    local cost = perk:getXpForLevel(10) * base * (1 + growth) ^ n
    return math.max(100, math.floor(cost / 100 + 0.5) * 100)
end

--- Mastery level (unbounded: past 10 is prestige), XP into the next level and that level's cost.
function M.levelInfo(perk, xp)
    local level, left = 0, xp or 0
    while level < 1000 do
        local cost = M.costFor(perk, level + 1)
        if left < cost then return level, left, cost end
        left = left - cost
        level = level + 1
    end
    return level, 0, M.costFor(perk, level + 1)
end

-- ---------------------------------------------------------------------------------------------------------------
-- Data. Server / single player: global mod data. Client (MP): what the server last sent, per local player.
-- ---------------------------------------------------------------------------------------------------------------

M.clientCache = M.clientCache or {}   -- [username] = { [perkId] = xp }

function M.store()
    return ModData.getOrCreate("TienSkillMastery")
end

function M.entry(player, create)
    local name = player and player:getUsername()
    if not name or name == "" then return nil end
    local store = M.store()
    local e = store[name]
    if not e and create then
        e = { xp = {}, hours = player:getHoursSurvived() }
        store[name] = e
    end
    return e
end

function M.getXp(player, perk)
    local id = M.perkId(perk)
    if isClient() then
        local t = M.clientCache[player:getUsername()]
        return (t and t[id]) or 0
    end
    local e = M.entry(player, false)
    return (e and e.xp[id]) or 0
end

--- Bonus mastery level, 0..10. Zero whenever the skill itself is below 10.
function M.level(player, perk)
    if type(perk) == "string" then perk = M.perk(perk) end
    if not player or not perk or player:getPerkLevel(perk) < 10 then return 0 end
    local xp = M.getXp(player, perk)
    if xp <= 0 then return 0 end
    local level = M.levelInfo(perk, xp)
    return math.min(level, M.BONUS_LEVELS)
end

-- ---------------------------------------------------------------------------------------------------------------
-- Bonuses. Every value is the amount at mastery 10 (approved list, 2026-11-05); each level gives a tenth.
-- kind: "pct" = percent of the vanilla value, "less" = percent off (times, losses), "pts" = percentage points on a
-- chance, "ptsoff" = percentage points off a chance, "int" = whole extra items / condition (fraction rolled),
-- "flat" = flat amount.
-- ---------------------------------------------------------------------------------------------------------------

M.defs = {}
M.defsByPerk = {}

local function def(perkId, name, at10, kind)
    local id = perkId .. "." .. name
    local d = { id = id, perk = perkId, name = name, at10 = at10, kind = kind }
    M.defs[id] = d
    M.defsByPerk[perkId] = M.defsByPerk[perkId] or {}
    table.insert(M.defsByPerk[perkId], d)
end

def("Fitness", "AttackSpeed", 5, "pct")
def("Fitness", "Endurance", 10, "less")
def("Strength", "Damage", 10, "pct")
def("Strength", "Knockback", 15, "pct")
def("Strength", "CarryWeight", 3, "flat")
def("Sprinting", "RunEndurance", 10, "less")
-- Multiplayer only, and only while the setting NimbleStrafe is on (see client/TienSkillMastery_Combat.lua).
def("Nimble", "StrafeSpeed", 15, "pct")
M.defs["Nimble.StrafeSpeed"].option = "NimbleStrafe"

M.MELEE = { "Axe", "Blunt", "SmallBlunt", "LongBlade", "SmallBlade", "Spear" }
for _, id in ipairs(M.MELEE) do
    def(id, "Damage", 10, "pct")
    def(id, "AttackSpeed", 5, "pct")
    def(id, "CritReroll", 5, "pts")   -- chance to reroll a swing that did not crit
end
for _, id in ipairs({ "Axe", "Blunt", "Spear" }) do
    def(id, "Reach", 10, "pct")
    def(id, "SwingEndurance", 15, "less")
end
def("Axe", "Knockback", 20, "pct")
M.defs["Axe.CritReroll"].at10 = 10   -- Axe rerolls twice as often (user, 2026-11-05)
def("Maintenance", "WearUndo", 20, "pts")

def("Aiming", "HitChance", 5, "pts")
def("Aiming", "Crit", 5, "pts")
def("Aiming", "Range", 10, "pct")
def("Aiming", "AimSpeed", 15, "pct")
def("Reloading", "ReloadSpeed", 15, "pct")

-- Crafting skills (parent Crafting): shared crafting time and dismantling.
M.CRAFTING = { "Woodwork", "Carving", "Cooking", "Electricity", "Glassmaking", "FlintKnapping", "Masonry",
    "Blacksmith", "Mechanics", "Pottery", "Tailoring", "MetalWelding" }
for _, id in ipairs(M.CRAFTING) do
    def(id, "CraftTime", 15, "less")
    def(id, "Dismantle", 10, "pts")
end
def("Woodwork", "StructureHP", 20, "pct")
def("Woodwork", "Unbarricade", 15, "less")
def("Woodwork", "WindowBreak", 5, "ptsoff")
def("Carving", "SpearCondition", 2, "int")
def("Cooking", "Nutrition", 15, "pct")
def("Cooking", "AddTime", 15, "less")
def("Electricity", "Hotwire", 10, "pts")
def("Electricity", "HotwireTime", 15, "less")
def("Electricity", "GeneratorRepair", 1, "int")
def("Electricity", "Scrap", 25, "pts")
def("Doctor", "TreatTime", 15, "less")
def("Doctor", "TreatStrength", 15, "pct")
def("Blacksmith", "ToolWear", 20, "pts")
def("Mechanics", "InstallTime", 15, "less")
def("Mechanics", "EngineRepair", 1, "int")
def("Mechanics", "Salvage", 20, "pct")
def("Tailoring", "PatchTime", 15, "less")
def("Tailoring", "FabricRecovery", 10, "pts")
def("Tailoring", "Ripping", 1, "int")
def("Tailoring", "Aramid", 1, "int")
def("MetalWelding", "BurntCarTime", 15, "less")
def("MetalWelding", "SalvageRoll", 1, "int")
def("MetalWelding", "WindowBreak", 5, "ptsoff")

def("Fishing", "Tension", 15, "pct")
def("Fishing", "Bait", 10, "pts")
def("Fishing", "BigFish", 10, "pts")
def("Fishing", "Junk", 20, "less")
def("Fishing", "Trophy", 2, "pts")
def("PlantScavenging", "Radius", 15, "pct")
def("PlantScavenging", "Spotting", 20, "less")
def("PlantScavenging", "Size", 10, "pct")
def("Tracking", "Find", 20, "pct")
def("Tracking", "InspectTime", 15, "less")
def("Trapping", "Catch", 5, "pts")
def("Farming", "Yield", 15, "pct")
def("Farming", "Cure", 15, "pct")
def("Farming", "PlantHealth", 3, "flat")
def("Farming", "BonusYield", 10, "pts")
def("Farming", "Curse", 10, "ptsoff")
def("Farming", "Fertilize", 10, "pts")
def("Farming", "BackStrain", 15, "less")
def("Husbandry", "Acceptance", 15, "pct")
def("Husbandry", "Calming", 15, "pct")
def("Husbandry", "ShearTime", 15, "less")
def("Butchering", "PartCount", 10, "pct")
def("Butchering", "PartChance", 15, "pct")
def("Butchering", "Time", 15, "less")

--- Per-skill bonus strength (setting, percent) times the global one.
function M.scale(perkId)
    local global = tonumber(M.option("BonusStrength", 100)) or 100
    local own = tonumber(M.option(perkId, 100)) or 100
    return math.max(0, global) / 100 * math.max(0, own) / 100
end

--- The bonus amount for this player now: at10 x level / 10 x scale. 0 when the bonus is unknown.
--- False when the bonus hangs on a setting that is off.
function M.enabled(d)
    return not d.option or M.option(d.option, true) == true
end

function M.val(player, id)
    local d = M.defs[id]
    if not d or not player or not M.enabled(d) then return 0 end
    local level = M.level(player, d.perk)
    if level <= 0 then return 0 end
    return d.at10 * level / M.BONUS_LEVELS * M.scale(d.perk)
end

--- 1 + bonus%, for "pct" bonuses.
function M.more(player, id)
    return 1 + M.val(player, id) / 100
end

--- 1 - bonus%, for "less" bonuses (never below 0.05).
function M.less(player, id)
    return math.max(0.05, 1 - M.val(player, id) / 100)
end

--- Roll a "pts" bonus as a chance in percent.
function M.roll(player, id)
    local v = M.val(player, id)
    return v > 0 and ZombRandFloat(0, 100) < v
end

--- Whole number from a bonus: the integer part, plus one more with the fraction as chance.
function M.int(player, id)
    local v = M.val(player, id)
    if v <= 0 then return 0 end
    local n = math.floor(v)
    if ZombRandFloat(0, 1) < v - n then n = n + 1 end
    return n
end

--- Scale an integer result (yields, counts) by a "pct" bonus, rounding the extra by a roll.
function M.scaleInt(player, id, n)
    local v = (n or 0) * M.val(player, id) / 100
    if v <= 0 then return n end
    local extra = math.floor(v)
    if ZombRandFloat(0, 1) < v - extra then extra = extra + 1 end
    return n + extra
end

-- ---------------------------------------------------------------------------------------------------------------
-- XP owner map and the getXP wrapper (both sides). Kahlua uses the same Java object as the same table key.
-- ---------------------------------------------------------------------------------------------------------------

M.xpOwner = M.xpOwner or {}

function M.noteOwner(player)
    if player then M.xpOwner[player:getXp()] = player end
end

local rawGetXP
--- The real XP, past the wrapper.
function M.rawXp(player, perk)
    local xp = player:getXp()
    if rawGetXP then return rawGetXP(xp, perk) end
    return xp:getXP(perk)
end

function M.isParked(player, perk, raw)
    if player:getPerkLevel(perk) < 10 then return false end
    raw = raw or M.rawXp(player, perk)
    local total = M.total10(perk)
    return raw < total and raw >= M.parkValue(perk) - M.EPS
end

function M.installXpWrapper(player)
    if rawGetXP or not player then return end
    local mt = getmetatable(player:getXp())
    local index = mt and mt.__index
    if type(index) ~= "table" or not index.getXP then return end
    rawGetXP = index.getXP
    index.getXP = function(self, perk)
        local v = rawGetXP(self, perk)
        local owner = M.xpOwner[self]
        if owner and perk and M.isParked(owner, perk, v) then
            return M.total10(perk)
        end
        return v
    end
end
