"""Runs the real Lose Them / Unseen file against mocks: the server's list of masters, Lose Them timed on the master's
game (out of sight, crouched, 3 s) and applied on the zombie's owner (here, through the server, or by the server),
Unseen dropping only new targets of a crouched and still master on the zombie's owner, walking them on or away, and
the useless trick clearing the "last spotted" that would bring the target back.

Breaks: nolast (only setTarget(nil): the forced re-spot brings the target back), nochasers (zombies already chasing
are dropped too), nosight (Lose Them ignores sight), noowner (every zombie taken)."""
import sys
from pathlib import Path

here = Path(__file__).resolve().parent
repo = here.parent
sys.path.insert(0, str(here / '.lupa'))
import lupa

src = (repo / 'Contents/mods/TienSkillMastery/42/media/lua/shared/TienSkillMastery_LoseThem.lua') \
    .read_bytes().decode('utf-8').replace('\r\n', '\n')

m = sys.argv[1] if len(sys.argv) > 1 else ''
if m == 'nolast':
    src = src.replace('pcall(function() zombie:spotted(master, true) end)', '')
if m == 'nochasers':
    src = src.replace('if not st.chasers[z] and L.owns(z) then', 'if L.owns(z) then')
if m == 'nosight':
    src = src.replace('if seenBy(z, p) then', 'if false then')
if m == 'noowner':
    src = src.replace('function L.owns(zombie)', 'function L.owns(zombie)\n    do return true end')

lua = lupa.LuaRuntime()
lua.globals().lose_source = src
result = lua.execute(r'''
local out = {}
local function check(name, v) out[#out + 1] = name .. "=" .. tostring(v) end
local now = 0
function require() end
function getTimestampMs() return now end
function ZombRandFloat(a, b) return (a + b) / 2 end
function instanceof(o, c) return o.class == c end

local function list(t)
    return { size = function() return #t end, get = function(_, i) return t[i + 1] end }
end

-- Squares: every square exists and is free; could-see is a set of "x,y" keys for player 0.
local visible = {}
local function square(x, y, z)
    local s = { x = x, y = y, z = z }
    function s.getX() return s.x end
    function s.getY() return s.y end
    function s.getZ() return s.z end
    function s.isFree() return true end
    function s.isCouldSee(_, n) return visible[x .. "," .. y] == true end
    return s
end

local zombieList = {}
function getCell()
    return {
        getZombieList = function() return list(zombieList) end,
        getGridSquare = function(_, x, y, z) return square(x, y, z) end,
    }
end
ZombieIdleState = { instance = function() return "ZombieIdleState" end }

local function player(id, x, y, opts)
    opts = opts or {}
    local p = { class = "IsoPlayer", id = id, x = x, y = y, sneaking = opts.sneaking ~= false, master = opts.master,
        localPlayer = opts.localPlayer, dead = false, num = opts.num or 0 }
    function p.getOnlineID() return p.id end
    function p.isDead() return p.dead end
    function p.getX() return p.x end
    function p.getY() return p.y end
    function p.getZ() return 0 end
    function p.isSneaking() return p.sneaking end
    function p.getVehicle() return nil end
    function p.getCurrentSquare() return square(math.floor(p.x), math.floor(p.y), 0) end
    function p.isLocalPlayer() return p.localPlayer == true end
    function p.getPlayerNum() return p.num end
    return p
end

local nextId = 100
local function zombie(target, x, y, opts)
    opts = opts or {}
    nextId = nextId + 1
    local z = { class = "IsoZombie", id = nextId, target = target, spottedLast = target, x = x, y = y,
        state = opts.state or "PathFindState", useless = opts.useless or false, remote = opts.remote or false,
        owner = opts.owner, dead = false, goal = opts.goal, path = nil }
    function z.getOnlineID() return z.id end
    function z.getTarget() return z.target end
    function z.setTarget(_, t) z.target = t end
    function z.isDead() return z.dead end
    function z.getX() return z.x end
    function z.getY() return z.y end
    function z.getZ() return 0 end
    function z.getCurrentSquare() return square(math.floor(z.x), math.floor(z.y), 0) end
    function z.isUseless() return z.useless end
    function z.setUseless(_, b) z.useless = b end
    -- Java: a useless zombie's spotted() clears target and spottedLast (the early out the file relies on).
    function z.spotted(_, other, forced)
        if z.useless then z.target = nil; z.spottedLast = nil end
    end
    function z.getCurrentStateName() return z.state end
    function z.changeState(_, s) z.state = s; z.path = nil end
    function z.pathToLocation(_, x, y, zz) z.state = "PathFindState"; z.path = { x = x, y = y, z = zz } end
    function z.isRemoteZombie() return z.remote end
    function z.getOwnerPlayer() return z.owner end
    function z.couldSeeHeadSquare() return false end
    function z.getPathFindBehavior2()
        local g = z.goal
        return {
            isGoalLocation = function() return g ~= nil end,
            isGoalSound = function() return false end,
            getTargetX = function() return g.x end, getTargetY = function() return g.y end,
            getTargetZ = function() return 0 end,
        }
    end
    return z
end

-- The engine between two OnTicks: a forced re-spot while "last spotted" is set (bonus time).
local function engine()
    for _, z in ipairs(zombieList) do
        if z.spottedLast and not z.useless and z.target == nil then z.target = z.spottedLast end
    end
end

local sent = {}
function sendServerCommand(a, b, c, d)
    if type(a) == "string" then sent[#sent + 1] = { to = "all", command = b, args = c }
    else sent[#sent + 1] = { to = a, command = c, args = d } end
end
function sendClientCommand(_, _, command, args) sent[#sent + 1] = { to = "server", command = command, args = args } end

local online, locals = {}, {}
function getOnlinePlayers() return list(online) end
function getNumActivePlayers() return #locals end
function getSpecificPlayer(i) return locals[i + 1] end
function getPlayer() return locals[1] end
function getPlayerByOnlineID(id) for _, p in ipairs(online) do if p.id == id then return p end end end

local L
local function load_side(which)
    local h = {}
    function isServer() return which == "server" end
    function isClient() return which == "client" end
    Events = {
        OnClientCommand = { Add = function(f) h.command = f end },
        OnServerCommand = { Add = function(f) h.serverCommand = f end },
        OnTick = { Add = function(f) h.tick = f end },
    }
    TienSkillMastery = { MODULE = "TSM" }
    local M = TienSkillMastery
    -- A client knows only its own players' masteries; the server knows everyone's.
    function M.sig(p, id)
        if which == "client" and not p.localPlayer then return false end
        return p.master == true
    end
    function M.val(p, id)
        if not M.sig(p, id) then return 0 end
        return id == "Stealth.SigLoseThem" and 3 or 1
    end
    M.Relay = { findZombie = function(id) for _, z in ipairs(zombieList) do if z.id == id then return z end end end }
    assert(load(lose_source))()
    L = M.LoseThem
    return h
end

local function tick(h, ms) now = now + (ms or 100); engine(); h.tick() end
local function run(h, ms) local t = 0; while t < ms do tick(h, 100); t = t + 100 end end
-- Creeping: crouched but moving, so Unseen stays off and only Lose Them acts.
local function creep(h, ms, p)
    local t = 0
    while t < ms do p.x = p.x + 0.2; tick(h, 100); t = t + 100 end
end

-- ================= Server =================
local master = player(3, 10, 10, { master = true })
local plain = player(4, 30, 30)
local otherClient = player(5, 50, 50)
online = { master, plain, otherClient }
locals = {}
local sv = load_side("server")
tick(sv, 1000)
tick(sv, 1000)
local broadcasts = 0
for _, s in ipairs(sent) do
    if s.to == "all" and s.command == "stealthMasters" and s.args.list == "3" then broadcasts = broadcasts + 1 end
end
check("serverBroadcastOnce", broadcasts == 1)
sent = {}
sv.command("TSM", "stealthMastersRequest", plain, {})
check("serverAnswers", sent[1] ~= nil and sent[1].to == plain and sent[1].args.list == "3")

-- Lose Them relayed: owned zombie to its owner, a free one dropped here, others refused.
local owned = zombie(master, 14, 10, { owner = otherClient })
local free = zombie(master, 15, 10, { owner = nil })
local notMine = zombie(plain, 16, 10)
local far = zombie(master, 90, 10)
zombieList = { owned, free, notMine, far }
sent = {}
sv.command("TSM", "loseThem", master, { list = owned.id .. "," .. free.id .. "," .. notMine.id .. "," .. far.id })
check("serverRelaysToOwner", #sent == 1 and sent[1].to == otherClient and sent[1].command == "loseThemApply"
    and sent[1].args.list == tostring(owned.id) and sent[1].args.master == 3)
check("serverDropsFree", free.target == nil and free.spottedLast == nil and free.state == "ZombieIdleState")
check("serverLeavesOtherTarget", notMine.target == plain)
check("serverLeavesFar", far.target == master)
check("ownedLeftForOwner", owned.target == master)
sent = {}
free.target, free.spottedLast = master, master
sv.command("TSM", "loseThem", plain, { list = tostring(free.id) })
check("serverRefusesNonMaster", free.target == master and #sent == 0)
master.sneaking = false
sv.command("TSM", "loseThem", master, { list = tostring(free.id) })
check("serverRefusesStanding", free.target == master)
master.sneaking = true

-- Unseen on the server: only zombies no client owns.
zombieList = {}
free.target, free.spottedLast = nil, nil
owned.target, owned.spottedLast = nil, nil
zombieList = { free, owned }
run(sv, 600)      -- crouched and still for 0.5 s
free.target, free.spottedLast, free.state = master, master, "PathFindState"
owned.target, owned.spottedLast = master, master
tick(sv)
check("serverUnseenDropsFree", free.target == nil and free.path ~= nil)
check("serverUnseenLeavesOwned", owned.target == master)
check("uselessRestored", free.useless == false)

-- ================= Client =================
now = 0
sent = {}
zombieList = {}
local me = player(7, 10, 10, { master = true, localPlayer = true })
local remoteMaster = player(3, 40, 40, { master = true })
online = { me, remoteMaster }
locals = { me }
local cl = load_side("client")
tick(cl, 1000)
check("clientAsks", sent[1] ~= nil and sent[1].command == "stealthMastersRequest")
cl.serverCommand("TSM", "stealthMasters", { list = "3,9" })
check("clientKeepsList", L.remote[3] == true and L.remote[9] == true)
tick(cl, 1000)

-- ---- Lose Them on the master's game (creeping, so Unseen stays out of it).
local mine = zombie(me, 14, 10)
local theirs = zombie(me, 15, 10, { remote = true })
local watching = zombie(me, 16, 10)
visible["16,10"] = true
zombieList = { mine, theirs, watching }
sent = {}
creep(cl, 2500, me)
check("notBefore3s", mine.target == me)
creep(cl, 700, me)
check("loseDropsOwn", mine.target == nil and mine.spottedLast == nil and mine.state == "ZombieIdleState")
check("loseLeavesInSight", watching.target == me)
local asks = 0
for _, s in ipairs(sent) do
    if s.command == "loseThem" and s.args.list == tostring(theirs.id) then asks = asks + 1 end
end
check("loseAsksServerOnce", asks == 1)
creep(cl, 2100, me)
asks = 0
for _, s in ipairs(sent) do
    if s.command == "loseThem" then asks = asks + 1 end
end
check("loseAsksAgainAfter2s", asks == 2)
-- Seen in between restarts the clock.
local peek = zombie(me, 17, 10)
zombieList = { peek }
creep(cl, 2000, me)
visible["17,10"] = true
creep(cl, 100, me)
visible["17,10"] = nil
creep(cl, 2000, me)
check("sightRestartsClock", peek.target == me)
creep(cl, 1100, me)
check("loseAfterRestart", peek.target == nil)
-- Standing up stops it.
local upright = zombie(me, 18, 10)
zombieList = { upright }
me.sneaking = false
creep(cl, 4000, me)
check("loseNeedsCrouch", upright.target == me)
me.sneaking = true
-- Mid-attack: tried again once it can be stopped.
local biting = zombie(me, 11, 10, { state = "AttackState" })
zombieList = { biting }
creep(cl, 3500, me)
check("loseWaitsForAttack", biting.target == me)
biting.state = "WalkTowardState"
creep(cl, 100, me)
check("loseAfterAttack", biting.target == nil)

-- ---- Lose Them passed on by the server to this game.
local ownZ = zombie(remoteMaster, 41, 40)
local notOwn = zombie(remoteMaster, 42, 40, { remote = true })
local otherTarget = zombie(me, 43, 40)
zombieList = { ownZ, notOwn, otherTarget }
cl.serverCommand("TSM", "loseThemApply", { master = 3, list = ownZ.id .. "," .. notOwn.id .. "," .. otherTarget.id })
check("applyOwn", ownZ.target == nil and ownZ.state == "ZombieIdleState")
check("applySkipsRemote", notOwn.target == remoteMaster)
check("applyChecksTarget", otherTarget.target == me)

-- ---- Unseen for a remote master on this game's zombies.
zombieList = {}
remoteMaster.x = 40.5   -- moved: not hidden while the chaser takes it as target
local chaser = zombie(remoteMaster, 44, 40, { state = "WalkTowardState" })
zombieList = { chaser }
run(cl, 600)    -- then crouched and still
local idleZ = zombie(nil, 46, 40, { state = "ZombieIdleState" })
idleZ.spottedLast = nil
local walker = zombie(nil, 35, 40, { state = "WalkTowardState", goal = { x = 30, y = 45 } })
walker.spottedLast = nil
local remoteZ = zombie(nil, 47, 40, { remote = true, state = "ZombieIdleState" })
remoteZ.spottedLast = nil
local wasUseless = zombie(nil, 48, 40, { state = "ZombieIdleState", useless = true })
wasUseless.spottedLast = nil
zombieList = { chaser, idleZ, walker, remoteZ, wasUseless }
tick(cl)            -- the walker's goal is noted while it is not after the master
for _, z in ipairs({ idleZ, walker, remoteZ, wasUseless }) do z.target, z.spottedLast = remoteMaster, remoteMaster end
tick(cl)
check("unseenKeepsChaser", chaser.target == remoteMaster)
check("unseenDropsIdle", idleZ.target == nil and idleZ.spottedLast == nil)
check("unseenSendsAway", idleZ.path ~= nil and idleZ.path.x > 46)
check("unseenWalksOn", walker.target == nil and walker.path ~= nil and walker.path.x == 30 and walker.path.y == 45)
check("unseenLeavesRemote", remoteZ.target == remoteMaster)
check("uselessKept", wasUseless.useless == true)
-- Spotted again on the next pass: dropped again, same walk.
walker.target, walker.spottedLast = remoteMaster, remoteMaster
tick(cl)
check("unseenAgainSameWalk", walker.target == nil and walker.path.x == 30)
-- Moving ends it.
remoteMaster.x = 41
local late = zombie(nil, 49, 40, { state = "ZombieIdleState" })
late.spottedLast = nil
zombieList = { late }
tick(cl)
late.target, late.spottedLast = remoteMaster, remoteMaster
tick(cl)
check("unseenNeedsStill", late.target == remoteMaster)
-- Not crouched: nothing.
remoteMaster.sneaking = false
run(cl, 1000)
late.target = nil; late.spottedLast = nil
tick(cl)
late.target, late.spottedLast = remoteMaster, remoteMaster
tick(cl)
check("unseenNeedsCrouch", late.target == remoteMaster)

-- ================= Single player =================
now = 0
zombieList = {}
local solo = player(0, 10, 10, { master = true, localPlayer = true })
online = {}
locals = { solo }
local sp = load_side("sp")
run(sp, 1200)
local spZ = zombie(nil, 12, 10, { state = "ZombieIdleState" })
spZ.spottedLast = nil
zombieList = { spZ }
tick(sp)
spZ.target, spZ.spottedLast = solo, solo
tick(sp)
check("spUnseen", spZ.target == nil)
local spChase = zombie(solo, 13, 10)
zombieList = { spChase }
solo.x = 10.5     -- moving: Unseen off, Lose Them on
run(sp, 3200)
check("spLoseThem", spChase.target == nil)

return table.concat(out, "\n")
''')

print(result)
bad = [line for line in result.split('\n') if line.endswith('=false')]
if bad:
    print('FAILED:', bad)
    sys.exit(1)
print('OK')
