--[[
Tien's Skill Mastery: shared core (masteries, picks, progress, effect table, XP parking helpers).

v2 (docs/v2-draft.md): skills stay vanilla (0-10). A mastery is a named group of vanilla skills with effects of its
own; it can be picked once every member is at 10, a character holds at most three, and XP earned past 10 on a member
skill goes to every picked mastery that lists it. The parking below is v1's and unchanged.

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

Storage: global mod data `TienSkillMastery` (server / single player), keyed by username:
`{ picks = { mastery ids }, points = { [mastery id] = n }, hours }`. Not player modData: a
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
-- Masteries (v2, docs/v2-draft.md): a mastery is a named group of at least two vanilla skills. It becomes pickable
-- once every member is at 10; a character holds at most MAX_PICKS, picks are permanent (an admin can remove one),
-- and once all are taken every other mastery is closed. A picked mastery whose member drops below 10 is inactive:
-- no effects, no progress, progress and slot kept.
-- ---------------------------------------------------------------------------------------------------------------

M.MAX_PICKS = 3
M.GROUPS = { "Combat", "Body", "Crafting", "Field" }

-- Parked masteries (user, 2026-11-07: Stealth and Freerunning, until their missing effects can be built): defined
-- with their effects and hooks, but not listed, not pickable, earning nothing, effects off. Remove an id here to
-- bring it back. A pick of one made before it was parked is dropped from the character's picks (its points stay).
-- Salvaging (user, 2026-11-08): hidden for now, too narrow as it stands. All three unhidden the same day (user), now
-- Coming Soon below; none is parked at the moment.
M.PARKED = {}
M.parked = {}         -- [id] = mastery, for parked ones

-- Coming soon (user, 2026-11-08): listed with their effects, but not pickable, the Pick button a grey Coming Soon.
-- Unlike a parked mastery, a pick made before it was listed here stays and keeps working. Remove an id once it is
-- ready: Angling, Homesteading and Hunting have signatures not played in game yet; Freerunning and Stealth lack most
-- of their effects; Salvaging is too narrow as it stands.
M.COMING_SOON = {
    Angling = true, Freerunning = true, Homesteading = true, Hunting = true, Salvaging = true, Stealth = true,
}

M.masteries = {}      -- display order
M.masteryById = {}
M.masteriesOf = {}    -- [perkId] = { mastery ids that list the skill }

function M.mastery(id, group, members)
    local m = { id = id, group = group, members = members, defs = {} }
    if M.PARKED[id] then
        m.parked = true
        M.parked[id] = m
        return m
    end
    table.insert(M.masteries, m)
    M.masteryById[id] = m
    for _, perkId in ipairs(members) do
        M.masteriesOf[perkId] = M.masteriesOf[perkId] or {}
        table.insert(M.masteriesOf[perkId], id)
    end
    return m
end

-- Every vanilla 42.21 skill, 35 skills in 22 masteries (approved 2026-11-06). Perk ids, not display names.
M.mastery("Firearms", "Combat", { "Aiming", "Reloading" })
M.mastery("Axemanship", "Combat", { "Axe", "Strength" })
M.mastery("Bludgeoning", "Combat", { "Blunt", "Strength" })
M.mastery("Swordsmanship", "Combat", { "LongBlade", "Nimble" })
M.mastery("Spearcraft", "Combat", { "Spear", "Carving" })
M.mastery("StreetFighting", "Combat", { "SmallBlunt", "Fitness" })
M.mastery("Knifework", "Combat", { "SmallBlade", "Sneak" })
M.mastery("Conditioning", "Body", { "Strength", "Fitness" })
M.mastery("Freerunning", "Body", { "Sprinting", "Lightfoot" })
M.mastery("Stealth", "Body", { "Sneak", "Lightfoot" })
M.mastery("Smithing", "Crafting", { "Blacksmith", "MetalWelding", "Maintenance" })
M.mastery("Construction", "Crafting", { "Woodwork", "Masonry" })
M.mastery("Engineering", "Crafting", { "Mechanics", "Electricity" })
M.mastery("Salvaging", "Crafting", { "MetalWelding", "Mechanics" })
M.mastery("Handicraft", "Crafting", { "Carving", "FlintKnapping", "Glassmaking", "Pottery" })
M.mastery("Mending", "Crafting", { "Tailoring", "Maintenance" })
M.mastery("FieldMedicine", "Crafting", { "Doctor", "Tailoring" })
M.mastery("Provisioning", "Crafting", { "Cooking", "Butchering" })
M.mastery("Hunting", "Field", { "Tracking", "Trapping", "Butchering" })
M.mastery("Angling", "Field", { "Fishing", "PlantScavenging" })
M.mastery("Fieldcraft", "Field", { "PlantScavenging", "Tracking" })
M.mastery("Homesteading", "Field", { "Farming", "Husbandry" })

-- A weapon mastery's effects apply with a weapon of its category (melee skill perk id -> mastery).
M.WEAPON_MASTERY = { Axe = "Axemanship", Blunt = "Bludgeoning", LongBlade = "Swordsmanship", Spear = "Spearcraft",
    SmallBlunt = "StreetFighting", SmallBlade = "Knifework" }
-- Crafting time on recipes whose relevant skills include one of these (perk id -> mastery).
M.CRAFT_MASTERY = { Woodwork = "Construction", Masonry = "Construction", Blacksmith = "Smithing",
    MetalWelding = "Smithing", Electricity = "Engineering", Carving = "Handicraft", FlintKnapping = "Handicraft",
    Glassmaking = "Handicraft", Pottery = "Handicraft", Tailoring = "Mending", Cooking = "Provisioning" }
-- Dismantling return chance by the scrap definition's skill (only these have scrap definitions).
M.DISMANTLE_MASTERY = { Woodwork = "Construction", Masonry = "Construction", MetalWelding = "Smithing",
    Blacksmith = "Smithing", Electricity = "Engineering" }

--- Perk id from a perk, a Perks entry or a string.
local function anyPerkId(perk)
    if type(perk) == "string" then return perk end
    if not perk then return nil end
    if perk.getId then return perk:getId() end
    return tostring(perk)
end
M.anyPerkId = anyPerkId

-- ---------------------------------------------------------------------------------------------------------------
-- Progress: points per picked mastery. A gain on a parked level-10 skill adds amount / xp10(skill) x 100 points to
-- every picked, active mastery listing the skill, so one mastery level is about one level-10 step of any member
-- (9000 XP for most skills, 150000 for Strength / Fitness), the v1 pace. Mastery level n costs
-- 100 x MasteryCostBase% x (1 + MasteryCostGrowth%)^n points (100 / 5 by default): mastery 1 = 105, mastery 10 =
-- 162.9, 1-10 together = 1320.7. Past 10 the curve continues as prestige.
-- ---------------------------------------------------------------------------------------------------------------

function M.pointsFor(perk, amount)
    local step = perk:getXpForLevel(10)
    if not step or step <= 0 then return 0 end
    return amount / step * 100
end

function M.xpForPoints(perk, points)
    return points * perk:getXpForLevel(10) / 100
end

local costCache = {}
function M.costFor(n)
    local c = costCache[n]
    if c then return c end
    local base = math.max(1, tonumber(M.option("MasteryCostBase", 100)) or 100) / 100
    local growth = math.max(0, tonumber(M.option("MasteryCostGrowth", 5)) or 5) / 100
    c = math.max(1, math.floor(100 * base * (1 + growth) ^ n * 10 + 0.5) / 10)
    costCache[n] = c
    return c
end

--- Mastery level (unbounded: past 10 is prestige), points into the next level and that level's cost.
function M.levelInfo(points)
    local level, left = 0, points or 0
    while level < 1000 do
        local cost = M.costFor(level + 1)
        if left < cost - 0.00001 then return level, math.max(0, left), cost end
        left = left - cost
        level = level + 1
    end
    return level, 0, M.costFor(level + 1)
end

--- Points needed to reach `level` from 0.
function M.pointsForLevel(level)
    local total = 0
    for n = 1, level do total = total + M.costFor(n) end
    return total
end

-- ---------------------------------------------------------------------------------------------------------------
-- Data. Server / single player: global mod data. Client (MP): what the server last sent, per local player.
-- Both have the same shape: { picks = { mastery ids in pick order }, points = { [mastery id] = n }, hours }.
-- ---------------------------------------------------------------------------------------------------------------

M.clientCache = M.clientCache or {}   -- [username] = { picks = {}, points = {} }

function M.store()
    return ModData.getOrCreate("TienSkillMastery")
end

function M.entry(player, create)
    local name = player and player:getUsername()
    if not name or name == "" then return nil end
    local store = M.store()
    local e = store[name]
    if not e and create then
        e = { picks = {}, points = {}, hours = player:getHoursSurvived() }
        store[name] = e
    end
    if e then
        -- v1 entries ({ xp = ... }) were never played; they start empty.
        e.picks = e.picks or {}
        e.points = e.points or {}
        e.xp = nil
        for i = #e.picks, 1, -1 do
            if M.PARKED[e.picks[i]] then table.remove(e.picks, i) end
        end
    end
    return e
end

local EMPTY = { picks = {}, points = {} }

--- This player's data (server entry or the client's copy); never nil.
function M.data(player)
    if not player then return EMPTY end
    if isClient() then return M.clientCache[player:getUsername()] or EMPTY end
    return M.entry(player, false) or EMPTY
end

function M.picks(player)
    return M.data(player).picks
end

function M.isPicked(player, masteryId)
    for _, id in ipairs(M.picks(player)) do
        if id == masteryId then return true end
    end
    return false
end

function M.getPoints(player, masteryId)
    return M.data(player).points[masteryId] or 0
end

function M.memberAt10(player, perkId)
    local perk = M.perk(perkId)
    return perk ~= nil and player:getPerkLevel(perk) >= 10
end

--- Every member skill at 10.
function M.membersAt10(player, masteryId)
    local m = M.masteryById[masteryId]
    if not m or not player then return false end
    for _, perkId in ipairs(m.members) do
        if not M.memberAt10(player, perkId) then return false end
    end
    return true
end

--- "picked" (earning, effects on), "inactive" (picked, a member below 10), "available" (all members at 10, a slot
--- free), "closed" (every slot taken), "soon" (M.COMING_SOON, a slot free, whatever its members' levels) or "locked"
--- (a member below 10, a slot free).
function M.state(player, masteryId)
    if M.isPicked(player, masteryId) then
        return M.membersAt10(player, masteryId) and "picked" or "inactive"
    end
    if #M.picks(player) >= M.MAX_PICKS then return "closed" end
    if M.COMING_SOON[masteryId] then return "soon" end
    return M.membersAt10(player, masteryId) and "available" or "locked"
end

--- Mastery level for effects, 0..10: zero unless picked and every member is at 10.
function M.level(player, masteryId)
    if not player or not M.isPicked(player, masteryId) or not M.membersAt10(player, masteryId) then return 0 end
    local points = M.getPoints(player, masteryId)
    if points <= 0 then return 0 end
    return math.min(M.levelInfo(points), M.BONUS_LEVELS)
end

--- Full level including prestige (display).
function M.fullLevel(player, masteryId)
    return (M.levelInfo(M.getPoints(player, masteryId)))
end

-- ---------------------------------------------------------------------------------------------------------------
-- Effects. Every value is the amount at mastery 10; each level gives a tenth (kind "step": fixed values from a
-- mastery level on). kind: "pct" = percent of the vanilla value, "less" = percent off (times, losses), "pts" =
-- percentage points on a chance, "ptsoff" = percentage points off a chance, "int" = whole extra items / condition
-- (fraction rolled), "flat" = flat amount, "step" = { { level, value }, ... } with `unit` for display.
-- Each effect belongs to one mastery only, so skills overlap but effects never stack.
-- ---------------------------------------------------------------------------------------------------------------

M.defs = {}

local function def(masteryId, name, at10, kind, extra)
    local id = masteryId .. "." .. name
    local d = { id = id, mastery = masteryId, name = name, at10 = at10, kind = kind, parked = M.PARKED[masteryId] }
    if extra then
        for k, v in pairs(extra) do d[k] = v end
    end
    M.defs[id] = d
    table.insert((M.masteryById[masteryId] or M.parked[masteryId]).defs, d)
    return d
end
M.def = def

local function multiHit()
    return SandboxVars ~= nil and SandboxVars.MultiHitZombies == true
end

-- Combat
def("Firearms", "Damage", 10, "pct")
def("Firearms", "HitChance", 5, "pts")
def("Firearms", "Range", 10, "pct")
def("Firearms", "AimSpeed", 15, "pct")
def("Firearms", "ReloadSpeed", 15, "pct")
def("Firearms", "WearUndo", 20, "pts")

local MELEE = {
    -- mastery, attack speed, crit reroll (nil = none), reach, knockback, wear undo
    { "Axemanship", 5, 10, 10, 20, 20 },
    { "Bludgeoning", 5, 5, nil, 15, 20 },
    { "Swordsmanship", 5, 5, 10, nil, 20 },
    { "Spearcraft", 5, 5, 10, nil, 30 },
    { "StreetFighting", 5, 10, nil, nil, 20 },
    -- Knives: speed is their identity (user, 2026-11-06); stabbing knives only crit on close kills.
    { "Knifework", 30, nil, nil, nil, 20 },
}
for _, row in ipairs(MELEE) do
    local id = row[1]
    def(id, "Damage", 10, "pct")
    def(id, "AttackSpeed", row[2], "pct")
    if row[3] then def(id, "CritReroll", row[3], "pts") end
    if row[4] then def(id, "Reach", row[4], "pct") end
    if row[5] then def(id, "Knockback", row[5], "pct") end
    def(id, "SwingEndurance", 15, "less")
    def(id, "WearUndo", row[6], "pts")
end
-- Bludgeoning: +1 target per swing at mastery 5, +2 at 10 with sandbox MultiHitZombies on; reach instead while it
-- is off, so the effect is never empty (user, 2026-11-07).
def("Bludgeoning", "ExtraTarget", 2, "step", { steps = { { 5, 1 }, { 10, 2 } }, unit = "flat", when = multiHit })
def("Bludgeoning", "Reach", 10, "step", { steps = { { 5, 5 }, { 10, 10 } }, unit = "pct",
    when = function() return not multiHit() end })
def("Spearcraft", "SpearCondition", 2, "int")

-- Body
def("Conditioning", "Endurance", 10, "less")
def("Conditioning", "CarryWeight", 5, "flat")
def("Conditioning", "Decay", 25, "less")
def("Freerunning", "RunEndurance", 15, "less")

-- Crafting
def("Smithing", "CraftTime", 25, "less")
def("Smithing", "Dismantle", 10, "pts")
def("Smithing", "ToolWear", 20, "pts")
def("Construction", "CraftTime", 25, "less")
def("Construction", "Dismantle", 10, "pts")
def("Construction", "StructureHP", 20, "pct")
def("Construction", "Unbarricade", 15, "less")
def("Construction", "WindowBreak", 5, "ptsoff")
def("Engineering", "CraftTime", 25, "less")
def("Engineering", "Dismantle", 10, "pts")
def("Engineering", "InstallTime", 15, "less")
def("Engineering", "EngineRepair", 1, "int")
def("Engineering", "Hotwire", 10, "pts")
def("Engineering", "HotwireTime", 15, "less")
def("Engineering", "Scrap", 25, "pts")
def("Salvaging", "BurntCarTime", 15, "less")
def("Salvaging", "SalvageRoll", 1, "int")
def("Salvaging", "Salvage", 20, "pct")
def("Handicraft", "CraftTime", 25, "less")
def("Handicraft", "ToolWear", 20, "pts")
def("Mending", "CraftTime", 25, "less")
def("Mending", "PatchTime", 15, "less")
def("Mending", "FabricRecovery", 10, "pts")
def("Mending", "Ripping", 1, "int")
def("Mending", "Aramid", 1, "int")
def("FieldMedicine", "TreatTime", 15, "less")
def("FieldMedicine", "TreatStrength", 15, "pct")
def("Provisioning", "CraftTime", 25, "less")
def("Provisioning", "Nutrition", 15, "pct")
def("Provisioning", "AddTime", 15, "less")
def("Provisioning", "ButcherTime", 15, "less")

-- Field
def("Hunting", "Find", 20, "pct")
def("Hunting", "InspectTime", 15, "less")
def("Hunting", "Catch", 5, "pts")
def("Hunting", "PartCount", 10, "pct")
def("Hunting", "PartChance", 15, "pct")
def("Angling", "Tension", 15, "pct")
def("Angling", "Bait", 10, "pts")
def("Angling", "BigFish", 10, "pts")
def("Angling", "Junk", 20, "less")
def("Angling", "Trophy", 2, "pts")
def("Fieldcraft", "Radius", 15, "pct")
def("Fieldcraft", "Spotting", 20, "less")
def("Fieldcraft", "Size", 10, "pct")
def("Homesteading", "Yield", 15, "pct")
def("Homesteading", "Cure", 15, "pct")
def("Homesteading", "PlantHealth", 3, "flat")
def("Homesteading", "BonusYield", 10, "pts")
def("Homesteading", "Curse", 10, "ptsoff")
def("Homesteading", "Fertilize", 10, "pts")
def("Homesteading", "BackStrain", 15, "less")
def("Homesteading", "Acceptance", 15, "pct")
def("Homesteading", "Calming", 15, "pct")
def("Homesteading", "ShearTime", 15, "less")

-- Phase 2 (2026-11-07): new effects from the draft that reuse or extend v1's hooks.
def("Firearms", "FireRate", 10, "pct")
def("Firearms", "JamChance", 25, "less")
def("Axemanship", "TreeDamage", 20, "pct")
def("StreetFighting", "StompDamage", 20, "pct")
def("StreetFighting", "ShoveDamage", 0.25, "flat")
def("Knifework", "SneakRunEndurance", 15, "less")
-- Executioner: chance (10% a level) that a close one-on-one knife stab is a critical, i.e. the jaw stab (instant kill).
-- Vanilla plays the jaw stab (`KnifeCrit*` nodes, CriticalHit) only when its own crit roll succeeds; a close stab
-- without it is an ordinary stab. It forces the crit only from behind on a zombie with no target (~3306).
def("Knifework", "Executioner", 100, "pts")
def("Knifework", "Ambush", 25, "pct")
def("Swordsmanship", "StrafeSpeed", 15, "pct")
def("Conditioning", "Recovery", 10, "pct")
def("Conditioning", "MuscleStrain", 25, "less")
-- Safe falls: drops of up to 1 floor from mastery 5, 2 floors at 10 (user, 2026-11-07).
def("Freerunning", "SafeFall", 2, "step", { steps = { { 5, 1 }, { 10, 2 } }, unit = "flat" })
def("Stealth", "SneakSpeed", 15, "pct")
def("Smithing", "CharcoalBack", 20, "pts")
def("Smithing", "OreYield", 15, "pct")
def("Smithing", "TorchFuel", 20, "pts")
def("Construction", "QuietWork", 50, "less")
def("Salvaging", "TorchFuel", 20, "pts")
-- Craftsman's mark: what a master makes ignores 1.5% of its wear per maker's mastery level, fixed at creation.
def("Mending", "CarefulRepairs", 15, "pct")
def("Mending", "StrongerPatches", 50, "pct")
def("FieldMedicine", "CrashSafety", 15, "less")
def("FieldMedicine", "Disinfectant", 50, "pct")
def("FieldMedicine", "StitchPain", 75, "less")
def("Provisioning", "LastingFood", 25, "pct")
-- Keen eyes: share of the darkness, weather and moving penalties ignored in search mode.
def("Fieldcraft", "KeenEyes", 100, "pct")
def("Homesteading", "AnimalStress", 15, "less")

-- Signature abilities (kind "sig": an unlock, on in full from the pick, value = the fixed amount the hook uses).
-- Phase 3a (2026-11-07).
def("Conditioning", "SigHeavyLoad", 1, "sig")       -- Heavy Load penalties one moodle level lower
def("Smithing", "SigMasterwork", 15, "sig")         -- wear ignored (%) by what the master forges
def("Construction", "SigPlanks", 100, "sig")        -- chance (%) of a 4th plank per sawn log (always since 2026-11-08; 50 before)
def("Construction", "SigStones", 2, "sig")          -- extra stones per broken large stone
def("Handicraft", "SigDeftHands", 10, "sig")        -- every timed action (%) faster
def("Handicraft", "SigCraftsmanship", 15, "sig")    -- wear ignored (%) by what the master makes (a "pts" bonus until 2026-11-08)
def("Provisioning", "SigChoiceCuts", 1, "sig")      -- butchered meat 10% more filling, 30% more nutritious (FarmAnimals.lua)
def("Provisioning", "SigSavoryMeals", 80, "sig")    -- food the master finishes with heat causes (%) less unhappiness
def("Hunting", "SigSturdyTraps", 1, "sig")          -- traps keep their bait and are never destroyed
def("Hunting", "SigLiveCatch", 4, "sig")            -- live catches last x times longer in the trap
def("Hunting", "SigDoubleCatch", 25, "sig")         -- chance (%) a trap holds two
def("Fieldcraft", "SigForageFighting", 1, "sig")    -- search mode not switched off by zombies or running
def("Fieldcraft", "SigZombieSense", 1, "sig")       -- zombies in the forage circle shown in search mode
def("Firearms", "SigQuickdraw", 4, "sig")           -- one-handed gun drawn / holstered x times faster
def("Firearms", "SigRunReload", 1, "sig")           -- reloading does not stop when running
def("Mending", "SigRestore", 1, "sig")              -- reset an item's repair count with its first fixer
def("Knifework", "SigLunge", 1.5, "sig")            -- jaw-stab reach (tiles; vanilla 0.61), closed with a lunge
def("Angling", "SigFishFinder", 1, "sig")           -- the aimed water's fish and trash shown
-- Phase 3b.
def("Bludgeoning", "SigPushBack", 1, "sig")         -- every swing staggers back the zombies in front it did not hit
def("Swordsmanship", "SigHamstring", 1, "sig")      -- sneaking and aiming, a long blade hit cripples into a crawler
def("Engineering", "SigEngineOverhaul", 1, "sig")   -- Engine Parts raise a car's engine quality, +1 each
def("Salvaging", "SigScrapAnyCar", 1, "sig")        -- scrap any car, and vehicle parts into metal
def("FieldMedicine", "SigTriage", 1, "sig")         -- "Tend wounds": vanilla treatments queued for every part
def("FieldMedicine", "SigNeedlework", 1, "sig")     -- recipes: bandages from ripped sheets, suture needles from needle and thread
def("Homesteading", "SigFields", 1, "sig")          -- tend / sow a picked area of the field
def("StreetFighting", "SigBowlOver", 1, "sig")      -- sprinting into zombies knocks them down
def("Axemanship", "SigThrowAxe", 1, "sig")          -- the throw key throws a one-handed axe (spares first)
def("Spearcraft", "SigThrowSpear", 1, "sig")        -- the throw key throws a spear (spares first)
-- Phase 3c passives.
def("Construction", "SpareMaterials", 15, "pts")    -- each build material comes back on a roll
def("Engineering", "TunedEngine", 15, "pct")        -- top speed and engine power while a master drives
def("Handicraft", "ExtraOutput", 15, "pts")         -- one more output on vetted recipes
def("Angling", "BaitDigger", 25, "flat")            -- foraging specialisation points for worms and insects
def("Angling", "BigHaul", 25, "pct")                -- fishing net catch hours

--- Bonus strength (setting, percent) for a mastery, times the global one.
function M.scale(masteryId)
    local global = tonumber(M.option("BonusStrength", 100)) or 100
    local own = tonumber(M.option(masteryId, 100)) or 100
    return math.max(0, global) / 100 * math.max(0, own) / 100
end

--- False when the effect hangs on a setting that is off, or does not apply under the current sandbox.
function M.enabled(d)
    if d.parked then return false end
    if d.option and M.option(d.option, true) ~= true then return false end
    if d.when and not d.when() then return false end
    return true
end

--- The effect's value at a mastery level (before scaling).
function M.valueAt(d, level)
    if d.kind == "sig" then return d.at10 end
    if d.kind == "step" then
        local v = 0
        for _, s in ipairs(d.steps) do
            if level >= s[1] then v = s[2] end
        end
        return v
    end
    return d.at10 * level / M.BONUS_LEVELS
end

--- The effect amount for this player now. 0 when unknown, off, or the mastery is not active.
function M.val(player, id)
    local d = M.defs[id]
    if not d or not player or not M.enabled(d) then return 0 end
    if d.kind == "sig" then
        -- Signatures: in full from the pick (mastery 0), never scaled by level (user, 2026-11-06).
        return M.hasSignature(player, d.mastery) and d.at10 or 0
    end
    local level = M.level(player, d.mastery)
    if level <= 0 then return 0 end
    return M.valueAt(d, level) * M.scale(d.mastery)
end

--- Picked and every member at 10: what a signature ability needs.
function M.hasSignature(player, masteryId)
    return player ~= nil and M.isPicked(player, masteryId) and M.membersAt10(player, masteryId)
end

--- True when this player has the signature effect `id` ("Mastery.Name" of kind "sig").
function M.sig(player, id)
    return M.val(player, id) > 0
end

--- Wear-undo chance (percent) an item's marks give, for `what` = "condition" (overall condition) or "head" (head
--- condition and sharpness). The main mark (`TSM_Mark`) covers the whole item, or only the head when `TSM_MarkPart`
--- is "head" (a hafted tool: axes, hammers, picks, scythes, spears); a hafted tool's handle mark (`TSM_HandleMark`)
--- covers the overall condition. See "Maker's marks" in TienSkillMastery_Crafting.lua (user, 2026-11-08).
function M.markChance(item, what)
    local md = item:getModData()
    local main = math.min(100, tonumber(md.TSM_Mark) or 0)
    if what == "head" then return main end
    if md.TSM_MarkPart == "head" then main = 0 end
    return math.max(main, math.min(100, tonumber(md.TSM_HandleMark) or 0))
end

--- True when the item carries any maker's mark.
function M.hasMark(item)
    local md = item:getModData()
    return (tonumber(md.TSM_Mark) or 0) > 0 or (tonumber(md.TSM_HandleMark) or 0) > 0
end

--- Default outline colour of the throw's target (a per-player mod option, client/TienSkillMastery_Options.lua):
--- purple, apart from vanilla's red melee outline (user, 2026-11-08; amber before).
M.OUTLINE_COLOR = { r = 0.72, g = 0.38, b = 1.0, a = 1.0 }

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

--- Best bonus among the masteries a perk maps to in `map` (e.g. CRAFT_MASTERY), for effect `name`.
function M.valFor(player, map, perk, name)
    local masteryId = map[anyPerkId(perk)]
    if not masteryId then return 0 end
    return M.val(player, masteryId .. "." .. name)
end

--- The weapon mastery for a melee weapon (by its category), or "Firearms" for an aimed firearm.
local CATEGORY = {
    { "AXE", "Axe" }, { "BLUNT", "Blunt" }, { "SMALL_BLUNT", "SmallBlunt" },
    { "LONG_BLADE", "LongBlade" }, { "SMALL_BLADE", "SmallBlade" }, { "SPEAR", "Spear" },
}
function M.weaponSkill(weapon)
    local script = weapon and weapon.getScriptItem and weapon:getScriptItem()
    if not script then return nil end
    for _, c in ipairs(CATEGORY) do
        local cat = WeaponCategory[c[1]]
        if cat and script:containsWeaponCategory(cat) then return c[2] end
    end
    return nil
end

function M.weaponMastery(weapon)
    if not weapon or not instanceof(weapon, "HandWeapon") then return nil end
    if weapon:isAimedFirearm() then return "Firearms" end
    local skill = M.weaponSkill(weapon)
    return skill and M.WEAPON_MASTERY[skill] or nil
end

-- Item helpers shared by the hooks.

--- Spoil times x f. Returns true when changed.
function M.stretchFood(item, f)
    if not item or not instanceof(item, "Food") or f <= 1 then return false end
    local off, offMax = item:getOffAge(), item:getOffAgeMax()
    if offMax <= 0 or offMax >= 1e8 then return false end
    item:setOffAge(off * f)
    item:setOffAgeMax(offMax * f)
    return true
end

--- Savory Meals: takes the signature's share off the unhappiness a food causes, once per item (modData `TSM_Savory`).
--- Only a penalty is touched: a food that cheers you up stays as it is. True when the item changed (server / SP).
--- Called when a food turns cooked (TienSkillMastery_WorkshopCooking.lua).
function M.savorFood(item, player)
    if not item or not instanceof(item, "Food") or item:getModData().TSM_Savory then return false end
    local share = M.val(player, "Provisioning.SigSavoryMeals")
    local unhappy = item:getUnhappyChangeUnmodified()
    if share <= 0 or unhappy <= 0 then return false end
    item:setUnhappyChange(unhappy * (1 - share / 100))
    item:getModData().TSM_Savory = true
    return true
end

--- Re-sends a whole item to whoever sees its container (server only; single player has nothing to send).
function M.resendItem(item)
    local container = isServer() and item and item:getContainer()
    if container then sendReplaceItemInContainer(container, item, item) end
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
