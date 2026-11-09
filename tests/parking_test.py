"""Runs the real shared core and server core against a port of Java's XP.AddXP (42.21): which level-10 skills are
parked, and whether a gain shows vanilla's "<skill> XP: n" halo. Only skills a picked, active mastery lists should be
parked; any other level-10 skill sits at the cap, where Java ignores gains and shows nothing (user, 2026-11-10).

Deliberate breaks (each must print FAILED): parkall (the pass parks every level-10 skill, the old behaviour),
nounpark (the pass never unparks).
"""
import sys
from pathlib import Path

here = Path(__file__).resolve().parent
repo = here.parent
sys.path.insert(0, str(here / '.lupa'))
import lupa

lua_dir = repo / 'Contents/mods/TienSkillMastery/42/media/lua'
shared = (lua_dir / 'shared/TienSkillMastery.lua').read_bytes().decode('utf-8').replace('\r\n', '\n')
server = (lua_dir / 'server/TienSkillMastery_Server.lua').read_bytes().decode('utf-8').replace('\r\n', '\n')
original = server

brk = sys.argv[1] if len(sys.argv) > 1 else None
if brk == 'parkall':
    server = server.replace('            if wantsPark(player, perk) then\n                if raw >=',
                            '            if true then\n                if raw >=')
elif brk == 'nounpark':
    server = server.replace('            elseif M.isParked(player, perk, raw) then', '            elseif false then')
if brk and server == original:
    raise SystemExit('break not applied: ' + brk)

lua = lupa.LuaRuntime()
g = lua.globals()
g.shared_source = shared
g.server_source = server

result = lua.execute(r'''
unpack = table.unpack
local out = {}
local function check(name, ok, detail)
    out[#out + 1] = name .. " " .. (ok and "ok" or ("BAD: " .. tostring(detail)))
end

-- Perks: vanilla steps (x1.5 built in) for most skills, the Strength / Fitness table for those two.
local STEPS = { 75, 150, 300, 750, 1500, 3000, 4500, 6000, 7500, 9000 }
local BODY = { 1500, 3000, 6000, 9000, 18000, 30000, 60000, 90000, 120000, 150000 }
local IDS = { "Aiming", "Reloading", "Axe", "Strength", "Blunt", "LongBlade", "Nimble", "Spear", "Carving",
    "SmallBlunt", "Fitness", "SmallBlade", "Sneak", "Sprinting", "Lightfoot", "Blacksmith", "MetalWelding",
    "Maintenance", "Woodwork", "Masonry", "Mechanics", "Electricity", "FlintKnapping", "Glassmaking", "Pottery",
    "Tailoring", "Doctor", "Cooking", "Butchering", "Tracking", "Trapping", "Fishing", "PlantScavenging",
    "Farming", "Husbandry" }
local Perk = {}
Perk.__index = Perk
function Perk:getId() return self.id end
function Perk:getParent() return self.parent end
function Perk:getXpForLevel(n) return self.steps[n] or 0 end
function Perk:getTotalXpForLevel(n)
    local t = 0
    for i = 1, math.min(n, 10) do t = t + self.steps[i] end
    return t
end
Perks = { None = { id = "None" } }
local list = {}
for i, id in ipairs(IDS) do
    local p = setmetatable({ id = id, parent = { id = "Cat" },
        steps = (id == "Strength" or id == "Fitness") and BODY or STEPS }, Perk)
    Perks[id] = p
    list[i - 1] = p
end
function Perks.getMaxIndex() return #IDS end
function Perks.fromIndex(i) return list[i] end
PerkFactory = { getPerk = function(p) return p end }

-- Events, mod data, environment (a dedicated server).
local handlers = {}
Events = setmetatable({}, { __index = function(t, k)
    local e = { Add = function(fn) handlers[k] = handlers[k] or {}; table.insert(handlers[k], fn) end }
    rawset(t, k, e)
    return e
end })
local store = {}
ModData = { getOrCreate = function() return store end }
function isClient() return false end
function isServer() return true end
local clock = 0
function getTimestampMs() return clock end
function instanceof(o, c) return c == "IsoPlayer" and o.isPlayer == true end
function sendServerCommand() end
function print() end
function require() end
CharacterStat = { FITNESS = "FITNESS" }
Capability = { AddXP = "AddXP" }
local players = {}
function getOnlinePlayers()
    return { size = function() return #players end, get = function(_, i) return players[i + 1] end }
end

-- XP: a port of Java's XP.AddXP (42.21 IsoGameCharacter$XP ~132): no boosts in this test, early return at the cap
-- for a gain, clamp to total(10), level loops, the halo only when the stored XP rose, the Lua event last.
local XP = {}
local XPMT = { __index = XP }
local halos = {}
function XP:getXP(perk) return self.map[perk] or 0 end
function XP:getMultiplier() return 1 end
function XP:AddXP(perk, amount, callLua, doBoost, remote, haloText)
    local chr = self.chr
    local old = self.map[perk] or 0
    local max = perk:getTotalXpForLevel(10)
    if amount >= 0 and old >= max then return end
    local new = old + amount
    if new < 0 then new = 0; amount = -old end
    if new > max then new = max; amount = max - old end
    self.map[perk] = new
    while chr.levels[perk] < 10 and old < perk:getTotalXpForLevel(chr.levels[perk] + 1)
        and new >= perk:getTotalXpForLevel(chr.levels[perk] + 1) do
        chr.levels[perk] = chr.levels[perk] + 1
    end
    while chr.levels[perk] > 0 and old >= perk:getTotalXpForLevel(chr.levels[perk])
        and new < perk:getTotalXpForLevel(chr.levels[perk]) do
        chr.levels[perk] = chr.levels[perk] - 1
    end
    if haloText and new > old then table.insert(halos, perk:getId()) end
    for _, fn in ipairs(handlers.AddXP or {}) do fn(chr, perk, amount) end
end

-- The admin path's global (server: GameServer.addXp; here an AddXP without boosts, as in single player).
function addXpNoMultiplier(p, perk, amount) p.xp:AddXP(perk, amount, true, false, false, false) end

local function newPlayer(name)
    local p = { isPlayer = true, name = name, levels = {}, modData = {} }
    p.xp = setmetatable({ chr = p, map = {} }, XPMT)
    for _, id in ipairs(IDS) do p.levels[Perks[id]] = 0 end
    function p:getUsername() return self.name end
    function p:getHoursSurvived() return 100 end
    function p:getPerkLevel(perk) return self.levels[perk] or 0 end
    function p:setPerkLevelDebug(perk, l) self.levels[perk] = l end
    function p:getXp() return self.xp end
    function p:getModData() return self.modData end
    function p:getStats() return { set = function() end } end
    function p:getNutrition() return { getProteins = function() return 0 end } end
    function p:isAsleep() return false end
    function p:isDead() return false end
    return p
end

local function setLevel(p, id, level, raw)
    local perk = Perks[id]
    p.levels[perk] = level
    p.xp.map[perk] = raw or perk:getTotalXpForLevel(level)
end

assert(load(shared_source, "shared"))()
assert(load(server_source, "server"))()
local M = TienSkillMastery

local function pass()
    clock = clock + 1000
    for _, fn in ipairs(handlers.OnTick or {}) do fn() end
end
local function raw(p, id) return M.rawXp(p, Perks[id]) end
local function total(id) return Perks[id]:getTotalXpForLevel(10) end
local function near(a, b) return math.abs(a - b) < 0.01 end
-- A haloText award, as vanilla's local-player awards are made (foraging), on the server copy here.
local function award(p, id, amount)
    halos = {}
    p.xp:AddXP(Perks[id], amount, true, true, false, true)
    return #halos > 0
end

-- The XP anti-cheat: each perk's rise against a snapshot. Our moves alone must never net more than 240 up.
local function maxRiseCheck(p, snapshot)
    local worst = 0
    for _, id in ipairs(IDS) do
        local d = (p.xp.map[Perks[id]] or 0) - (snapshot[id] or 0)
        if d > worst then worst = d end
    end
    return worst
end
local function snap(p)
    local s = {}
    for _, id in ipairs(IDS) do s[id] = p.xp.map[Perks[id]] or 0 end
    return s
end

local a = newPlayer("A")
players = { a }

-- 1. An older save: every level-10 skill parked. No picks: the pass puts them back at the cap.
setLevel(a, "PlantScavenging", 10, total("PlantScavenging") - 240)
setLevel(a, "Fishing", 10, total("Fishing") - 240)
setLevel(a, "Axe", 10, total("Axe") - 240)
setLevel(a, "Strength", 10, total("Strength") - 240)
local s0 = snap(a)
pass()
check("oldSaveUnparked", near(raw(a, "PlantScavenging"), total("PlantScavenging")), raw(a, "PlantScavenging"))
check("unparkRiseUnder250", maxRiseCheck(a, s0) <= 240.01, maxRiseCheck(a, s0))
check("levelKept", a:getPerkLevel(Perks.PlantScavenging) == 10, a:getPerkLevel(Perks.PlantScavenging))

-- 2. Foraging with no mastery taking it: no halo, no XP change, nothing banked.
local shown = award(a, "PlantScavenging", 5)
check("noHaloUnpicked", not shown, "halo shown")
check("noChangeUnpicked", near(raw(a, "PlantScavenging"), total("PlantScavenging")), raw(a, "PlantScavenging"))
check("getXPvanilla", near(a:getXp():getXP(Perks.PlantScavenging), total("PlantScavenging")),
    a:getXp():getXP(Perks.PlantScavenging))

-- 3. Pick Angling (Fishing + Foraging): the pass parks both; a gain counts, with the halo (it is real progress).
check("picked", M.pick(a, "Angling"), "pick refused")
pass()
check("pickParks", near(raw(a, "PlantScavenging"), total("PlantScavenging") - 240), raw(a, "PlantScavenging"))
check("pickParksFishing", near(raw(a, "Fishing"), total("Fishing") - 240), raw(a, "Fishing"))
check("otherStaysAtCap", near(raw(a, "Axe"), total("Axe")), raw(a, "Axe"))
check("getXPreportsCap", near(a:getXp():getXP(Perks.PlantScavenging), total("PlantScavenging")),
    a:getXp():getXP(Perks.PlantScavenging))
shown = award(a, "PlantScavenging", 90)
check("haloPicked", shown, "no halo")
check("pointsEarned", near(M.getPoints(a, "Angling"), 1), M.getPoints(a, "Angling"))
check("reparked", near(raw(a, "PlantScavenging"), total("PlantScavenging") - 240), raw(a, "PlantScavenging"))
shown = award(a, "Axe", 5)
check("noHaloOther", not shown, "halo on Axe")

-- 4. The pick removed: a gain before the pass runs is not banked and the skill goes back to the cap; the pass
-- unparks the other member.
check("unpicked", M.adminChange(a, { mastery = "Angling", op = "unpick" }), "unpick refused")
award(a, "PlantScavenging", 90)
check("noPointsAfterUnpick", M.getPoints(a, "Angling") == 0, M.getPoints(a, "Angling"))
check("gainUnparks", near(raw(a, "PlantScavenging"), total("PlantScavenging")), raw(a, "PlantScavenging"))
pass()
check("passUnparksMember", near(raw(a, "Fishing"), total("Fishing")), raw(a, "Fishing"))

-- 5. Inactive: Axemanship picked, then Strength drops to 9. Axe goes back to the cap; Strength back at 10 parks both.
check("pickedAxe", M.pick(a, "Axemanship"), "pick refused")
pass()
check("axeParked", near(raw(a, "Axe"), total("Axe") - 240), raw(a, "Axe"))
setLevel(a, "Strength", 9, total("Strength") - 1000)
pass()
check("inactiveUnparks", near(raw(a, "Axe"), total("Axe")), raw(a, "Axe"))
award(a, "Strength", 2000)
check("strengthBackTo10", a:getPerkLevel(Perks.Strength) == 10, a:getPerkLevel(Perks.Strength))
check("reachParks", near(raw(a, "Strength"), total("Strength") - 240), raw(a, "Strength"))
pass()
check("activeAgainParksAxe", near(raw(a, "Axe"), total("Axe") - 240), raw(a, "Axe"))

-- 6. Reaching 10 with no mastery: stays at the cap, as in vanilla.
setLevel(a, "Cooking", 9, total("Cooking") - 100)
award(a, "Cooking", 500)
check("reach10NoMastery", near(raw(a, "Cooking"), total("Cooking")) and a:getPerkLevel(Perks.Cooking) == 10,
    raw(a, "Cooking"))
pass()
check("reach10StaysAtCap", near(raw(a, "Cooking"), total("Cooking")), raw(a, "Cooking"))

-- 7. A level-10 skill an admin left far below the cap, no mastery: never raised (anti-cheat).
setLevel(a, "Tailoring", 10, total("Tailoring") - 5000)
pass()
check("adminLowLeftAlone", near(raw(a, "Tailoring"), total("Tailoring") - 5000), raw(a, "Tailoring"))

-- 8. Max All with no pick leaves every skill at the cap; picking Conditioning parks Strength and Fitness only.
local b = newPlayer("B")
players = { a, b }
M.adminSkill(b, { op = "maxAll" })
local allCap = true
for _, id in ipairs(IDS) do
    if not near(raw(b, id), total(id)) then allCap = false end
end
check("maxAllAtCap", allCap, "a skill below the cap")
M.pick(b, "Conditioning")
pass()
check("conditioningParks", near(raw(b, "Fitness"), total("Fitness") - 240) and near(raw(b, "Strength"), total("Strength") - 240),
    raw(b, "Fitness"))
check("othersAtCap", near(raw(b, "Cooking"), total("Cooking")), raw(b, "Cooking"))

-- 9. Admin skill cheat on a skill no mastery takes: back at the cap afterwards.
M.adminSkill(b, { perk = "Cooking", op = "remove", amount = 100 })
M.adminSkill(b, { perk = "Cooking", op = "add", amount = 100 })
check("adminSkillAtCap", near(raw(b, "Cooking"), total("Cooking")), raw(b, "Cooking"))
M.adminSkill(b, { perk = "Strength", op = "add", amount = 10 })
check("adminSkillParkedMember", near(raw(b, "Strength"), total("Strength") - 240), raw(b, "Strength"))

return table.concat(out, "\n")
''')

parts = result.split('\n')
bad = [p for p in parts if not p.endswith(' ok')]
for p in bad:
    print('  ' + p)
print('FAILED' if bad else 'all %d checks passed' % len(parts))
sys.exit(1 if bad else 0)
