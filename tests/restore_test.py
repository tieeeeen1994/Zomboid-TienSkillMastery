"""Mastery surviving a restored backup or a crash, and the admin window's server side (2026-11-23), against the real
shared core and server core.

Global mod data reaches the disk only in a full world save, players.db as the server goes, so a backup or a crash
can pair the players with an older global_mod_data.bin (server/TienSkillMastery_Server.lua header). The server keeps
a stamped copy of each entry in the player's modData and, the first time it sees the player after starting, keeps
the newer one. Admins change any player's mastery, online or offline (M.adminChange with `target`, M.adminState).

Deliberate breaks (each must print FAILED): nomirror (the mirror is never read back), nogate (it is read back on
every pass, so a client's stale or forged copy would win), hoursreset (a character with a mirror is still reset for
having fewer hours).
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
if brk == 'nomirror':
    server = server.replace('if m and (tonumber(m.stamp) or 0) > (e.stamp or 0) then', 'if false then')
elif brk == 'nogate':
    server = server.replace('    if not checked[name] then\n', '    if true then\n')
elif brk == 'hoursreset':
    server = server.replace('if not m and e.hours and hours + 0.5 < e.hours then', 'if e.hours and hours + 0.5 < e.hours then')
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

local handlers = {}
Events = setmetatable({}, { __index = function(t, k)
    return { Add = function(fn) handlers[k] = handlers[k] or {}; table.insert(handlers[k], fn) end }
end })
local store = {}
ModData = { getOrCreate = function() return store end }
function isClient() return false end
function isServer() return true end
local clock = 1000000
function getTimestampMs() return clock end
function instanceof(o, c) return c == "IsoPlayer" and o.isPlayer == true end
local sent = {}
function sendServerCommand(p, module, command, args)
    sent[#sent + 1] = { player = p, command = command, args = args }
end
function print() end
function require() end
CharacterStat = { FITNESS = "FITNESS" }
Capability = { AddXP = "AddXP" }
local players = {}
function getOnlinePlayers()
    return { size = function() return #players end, get = function(_, i) return players[i + 1] end }
end

local XP = {}
local XPMT = { __index = XP }
function XP:getXP(perk) return self.map[perk] or 0 end
function XP:getMultiplier() return 1 end
function XP:AddXP(perk, amount)
    local chr = self.chr
    local old = self.map[perk] or 0
    local max = perk:getTotalXpForLevel(10)
    if amount >= 0 and old >= max then return end
    local new = math.max(0, math.min(max, old + amount))
    self.map[perk] = new
    for _, fn in ipairs(handlers.AddXP or {}) do fn(chr, perk, new - old) end
end
function addXpNoMultiplier(p, perk, amount) p.xp:AddXP(perk, amount) end

local function newPlayer(name, hours, level, admin)
    local p = { isPlayer = true, name = name, levels = {}, modData = {}, hours = hours or 100 }
    p.xp = setmetatable({ chr = p, map = {} }, XPMT)
    for _, id in ipairs(IDS) do
        local perk = Perks[id]
        p.levels[perk] = level or 0
        p.xp.map[perk] = perk:getTotalXpForLevel(level or 0)
    end
    function p:getUsername() return self.name end
    function p:getHoursSurvived() return self.hours end
    function p:getPerkLevel(perk) return self.levels[perk] or 0 end
    function p:setPerkLevelDebug(perk, l) self.levels[perk] = l end
    function p:getXp() return self.xp end
    function p:getModData() return self.modData end
    function p:getStats() return { set = function() end } end
    function p:getNutrition() return { getProteins = function() return 0 end } end
    function p:isAsleep() return false end
    function p:isDead() return false end
    function p:getRole() return { hasCapability = function() return admin == true end } end
    return p
end

local function deepcopy(t)
    if type(t) ~= "table" then return t end
    local c = {}
    for k, v in pairs(t) do c[k] = deepcopy(v) end
    return c
end

local M
--- A server (re)start: the files load again with empty file-level state, as after a restart.
local function start()
    for k in pairs(handlers) do handlers[k] = nil end
    TienSkillMastery = nil
    assert(load(shared_source, "shared"))()
    assert(load(server_source, "server"))()
    M = TienSkillMastery
end
local function pass()
    clock = clock + 1000
    for _, fn in ipairs(handlers.OnTick or {}) do fn() end
end
local function command(p, name, args)
    for _, fn in ipairs(handlers.OnClientCommand or {}) do fn("TienSkillMastery", name, p, args) end
end

start()

-- 1. A picks Angling and earns points; the pass writes the mirror into A's modData with the entry's stamp.
local a = newPlayer("A", 100, 10)
players = { a }
pass()
check("pickA", M.pick(a, "Angling"), "pick refused")
pass()
a.xp:AddXP(Perks.Fishing, 900)
pass()
local points = M.getPoints(a, "Angling")
check("earned", points > 0, points)
local mirror = a.modData.TienSkillMastery
check("mirrorWritten", type(mirror) == "table" and mirror.picks[1] == "Angling" and mirror.points.Angling == points,
    mirror and mirror.points and mirror.points.Angling)
check("mirrorStamped", mirror and mirror.stamp == store.A.stamp and store.A.stamp > 0, mirror and mirror.stamp)

-- 2. The backup: players.db as of now (A with the mirror), global mod data from the server's start (empty).
local savedA = deepcopy(a.modData)
for k in pairs(store) do store[k] = nil end
start()
local a2 = newPlayer("A", 120, 10)
a2.modData = savedA
players = { a2 }
pass()
check("restoredPick", M.isPicked(a2, "Angling"), "pick lost")
check("restoredPoints", math.abs(M.getPoints(a2, "Angling") - points) < 0.001, M.getPoints(a2, "Angling"))
check("restoredSent", store.A ~= nil and #sent > 0, #sent)

-- 2b. A crash with a global mod data older than the player's save but not empty (an earlier pick, fewer points).
local older = deepcopy(savedA.TienSkillMastery)
older.points.Angling = 1
older.stamp = older.stamp - 5000
a2.xp:AddXP(Perks.Fishing, 900)
pass()
local later = M.getPoints(a2, "Angling")
local savedA2 = deepcopy(a2.modData)
for k in pairs(store) do store[k] = nil end
store.A = older
start()
local a3 = newPlayer("A", 130, 10)
a3.modData = savedA2
players = { a3 }
pass()
check("crashNewerMirrorWins", math.abs(M.getPoints(a3, "Angling") - later) < 0.001, M.getPoints(a3, "Angling"))

-- 3. A client's transmitModData from its login copy (older stamp): the store stays, the mirror is written again.
a3.xp:AddXP(Perks.Fishing, 900)
pass()
local now = M.getPoints(a3, "Angling")
a3.modData = deepcopy(savedA2)
pass()
check("staleTransmitIgnored", math.abs(M.getPoints(a3, "Angling") - now) < 0.001, M.getPoints(a3, "Angling"))
check("staleTransmitRewritten", a3.modData.TienSkillMastery.stamp == store.A.stamp, a3.modData.TienSkillMastery.stamp)

-- 3b. A forged copy with a newer stamp after the first sighting is never read back.
local forged = deepcopy(a3.modData.TienSkillMastery)
forged.points.Angling = 99999
forged.stamp = clock + 1e9
a3.modData.TienSkillMastery = forged
pass()
check("forgedIgnored", math.abs(M.getPoints(a3, "Angling") - now) < 0.001, M.getPoints(a3, "Angling"))

-- 3c. A character with a mirror and fewer hours than recorded (players.db alone rolled back) keeps its mastery.
local savedA3 = deepcopy(a3.modData)
start()
local a4 = newPlayer("A", 50, 10)
a4.modData = savedA3
players = { a4 }
pass()
check("mirrorNoHoursReset", M.isPicked(a4, "Angling"), "reset for fewer hours")

-- 4. Death: cleared; the new character (fresh modData, fewer hours) starts empty, nothing comes back.
for _, fn in ipairs(handlers.OnCharacterDeath or {}) do fn(a4) end
local fresh = newPlayer("A", 0, 10)
players = { fresh }
pass()
check("newCharacterEmpty", #M.picks(fresh) == 0, #M.picks(fresh))
store.A.hours = 500
pass()
check("noMirrorHoursReset", #M.picks(fresh) == 0, #M.picks(fresh))

-- 5. Admin on another player (online): pick without the member check, set the level, add points, unpick.
start()
local admin = newPlayer("Admin", 10, 0, true)
local b = newPlayer("B", 10, 0)
players = { admin, b }
pass()
check("adminPick", M.adminChange(admin, { target = "B", mastery = "Firearms", op = "pick" }), "refused")
check("adminPickStored", M.isPicked(b, "Firearms") and not M.isPicked(admin, "Firearms"), "wrong player")
check("adminLevel", M.adminChange(admin, { target = "B", mastery = "Firearms", op = "level", level = 3 }), "refused")
check("adminLevelPoints", math.abs(M.getPoints(b, "Firearms") - M.pointsForLevel(3)) < 0.001, M.getPoints(b, "Firearms"))
check("adminAdd", M.adminChange(admin, { target = "B", mastery = "Firearms", op = "add", amount = 50 }), "refused")
check("adminAddPoints", math.abs(M.getPoints(b, "Firearms") - M.pointsForLevel(3) - 50) < 0.001,
    M.getPoints(b, "Firearms"))
check("adminNotPickedRefused", not M.adminChange(admin, { target = "B", mastery = "Angling", op = "add", amount = 5 }),
    "changed an unpicked mastery")
check("adminUnknownRefused", not M.adminChange(admin, { target = "B", mastery = "Nope", op = "pick" }), "picked")
pass()
check("adminMirrorFollows", b.modData.TienSkillMastery and b.modData.TienSkillMastery.points.Firearms
    == M.getPoints(b, "Firearms"), "mirror not written")
M.adminChange(admin, { target = "B", mastery = "Angling", op = "pick" })
M.adminChange(admin, { target = "B", mastery = "Axemanship", op = "pick" })
check("adminPickSlotLimit", not M.adminChange(admin, { target = "B", mastery = "Cooking", op = "pick" }),
    "picked past the limit")
check("adminUnpick", M.adminChange(admin, { target = "B", mastery = "Axemanship", op = "unpick" }) and
    not M.isPicked(b, "Axemanship"), "still picked")

-- 6. Offline target: changed in the store; when they log in, the store's newer stamp beats their mirror.
local c = newPlayer("C", 10, 10)
players = { admin, c }
M.pick(c, "Angling")
pass()
local cSave = deepcopy(c.modData)
players = { admin }
pass()
check("offlineAdd", M.adminChange(admin, { target = "C", mastery = "Angling", op = "add", amount = 40 }), "refused")
check("offlineStored", math.abs((store.C.points.Angling or 0) - 40) < 0.001, store.C.points.Angling)
start()
local c2 = newPlayer("C", 20, 10)
c2.modData = cSave
players = { admin, c2 }
pass()
check("offlineKeptAtLogin", math.abs(M.getPoints(c2, "Angling") - 40) < 0.001, M.getPoints(c2, "Angling"))

-- 7. The window's state: every known player, sorted, and the target's entry.
local st = M.adminState(admin, "C")
check("stateNames", table.concat(st.names, ",") == "A,Admin,B,C", table.concat(st.names, ","))
check("stateTarget", st.target == "C" and st.online and st.picks[1] == "Angling" and st.active.Angling == true,
    st.target)
local offline = M.adminState(admin, "B")
check("stateOffline", offline.online == false and offline.picks[1] == "Firearms", tostring(offline.online))

-- 8. The command path: refused without AddXP; with it, the change and an adminState reply.
local plain = newPlayer("Plain", 10, 0)
players = { admin, c2, plain }
command(plain, "adminChange", { target = "C", mastery = "Angling", op = "add", amount = 1000 })
check("commandRefused", math.abs(M.getPoints(c2, "Angling") - 40) < 0.001, M.getPoints(c2, "Angling"))
sent = {}
command(admin, "adminChange", { target = "C", mastery = "Angling", op = "add", amount = 10 })
local replied, toTarget = false, false
for _, s in ipairs(sent) do
    if s.player == admin and s.command == "adminState" then replied = true end
    if s.player == c2 and s.command == "state" then toTarget = true end
end
check("commandApplied", math.abs(M.getPoints(c2, "Angling") - 50) < 0.001, M.getPoints(c2, "Angling"))
check("commandReplies", replied and toTarget, tostring(replied) .. " " .. tostring(toTarget))

return table.concat(out, "\n")
''')

parts = result.split('\n')
bad = [p for p in parts if not p.endswith(' ok')]
for p in bad:
    print('  ' + p)
print('FAILED' if bad else 'all %d checks passed' % len(parts))
sys.exit(1 if bad else 0)
