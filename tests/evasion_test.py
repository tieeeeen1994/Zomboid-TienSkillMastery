"""Runs the real Evasion file against mocks: zombie swings made toothless on a dodge and given back, who owns the
attack on each side, the server's list of masters, and the 0-damage rule for player hits.

Breaks: norestore (teeth never given back), nozero (0-damage hits not cancelled), noowner (every zombie taken)."""
import sys
from pathlib import Path

here = Path(__file__).resolve().parent
repo = here.parent
sys.path.insert(0, str(here / '.lupa'))
import lupa

src = (repo / 'Contents/mods/TienSkillMastery/42/media/lua/shared/TienSkillMastery_Evasion.lua') \
    .read_bytes().decode('utf-8').replace('\r\n', '\n')

m = sys.argv[1] if len(sys.argv) > 1 else ''
if m == 'norestore':
    src = src.replace('zombie:setNoTeeth(false)', '')
if m == 'nozero':
    src = src.replace('elseif tonumber(damage) == 0 then', 'elseif false then')
if m == 'noowner':
    src = src.replace('local function ownsAttack(zombie)', 'local function ownsAttack(zombie)\n    do return true end')

lua = lupa.LuaRuntime()
lua.globals().evasion_source = src
result = lua.execute(r'''
local out = {}
local now = 0
local roll = 0
function require() end
function getTimestampMs() return now end
function ZombRand(n) return roll end
function instanceof(o, c)
    if c == "IsoAnimal" then return false end
    return o.class == c
end

local function list(t)
    return { size = function() return #t end, get = function(_, i) return t[i + 1] end }
end

-- One square holding every zombie; players stand on it.
local objects = {}
local square = { getX = function() return 10 end, getY = function() return 10 end, getZ = function() return 0 end,
    getMovingObjects = function() return list(objects) end }
function getCell()
    return { getGridSquare = function(_, x, y, z) if x == 10 and y == 10 then return square end end }
end

local function player(id, opts)
    opts = opts or {}
    local p = { class = "IsoPlayer", id = id, master = opts.master, localPlayer = opts.localPlayer, avoid = false }
    function p.getOnlineID() return p.id end
    function p.isDead() return false end
    function p.getCurrentSquare() return square end
    function p.isLocalPlayer() return p.localPlayer == true end
    function p.setAvoidDamage(_, b) p.avoid = b end
    return p
end

local function zombie(target, opts)
    opts = opts or {}
    local z = { class = "IsoZombie", target = target, outcome = nil, teeth = opts.noTeeth or false,
        remote = opts.remote or false, owner = opts.owner, biteDone = nil }
    function z.getTarget() return z.target end
    function z.getAttackOutcome() return z.outcome end
    function z.isNoTeeth() return z.teeth end
    function z.setNoTeeth(_, b) z.teeth = b end
    function z.isRemoteZombie() return z.remote end
    function z.getOwnerPlayer() return z.owner end
    function z.getVariableString(_, name) if name == "ZombieBiteDone" then return z.biteDone end end
    return z
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

local function load_side(which)
    local h = {}
    function isServer() return which == "server" end
    function isClient() return which == "client" end
    Events = {
        OnClientCommand = { Add = function(f) h.command = f end },
        OnServerCommand = { Add = function(f) h.serverCommand = f end },
        OnTick = { Add = function(f) h.tick = f end },
        OnWeaponHitCharacter = { Add = function(f) h.hit = f end },
    }
    TienSkillMastery = { MODULE = "TSM" }
    -- The client knows only its own mastery (M.val); others come from the server's list.
    TienSkillMastery.val = function(p, id)
        assert(id == "Freerunning.SigEvasion")
        if which == "client" and not p.localPlayer then return 0 end
        return p.master and 15 or 0
    end
    assert(load(evasion_source))()
    return h
end

local function tick(h, ms) now = now + (ms or 100); h.tick() end

-- ---- Server: list of masters to everyone, and to a client that asks.
local master = player(3, { master = true })
local plain = player(4)
online = { master, plain }
locals = {}
local sv = load_side("server")
tick(sv, 1000)
local broadcast = 0
for _, s in ipairs(sent) do
    if s.to == "all" and s.command == "evasion" and s.args.list == "3:15" then broadcast = broadcast + 1 end
end
tick(sv, 1000)
out[#out + 1] = "serverBroadcastOnce=" .. broadcast
sent = {}
sv.command("TSM", "evasionRequest", plain, {})
out[#out + 1] = "serverAnswers=" .. tostring(sent[1] and sent[1].to == plain and sent[1].args.list == "3:15")

-- ---- Server: only zombies no client owns.
local owned = zombie(master, { owner = plain })
local free = zombie(master)
objects = { owned, free }
roll = 0
owned.outcome, free.outcome = "start", "start"
tick(sv)
out[#out + 1] = "serverSkipsOwned=" .. tostring(not owned.teeth)
out[#out + 1] = "serverTakesFree=" .. tostring(free.teeth)

-- ---- Client: the list from the server, then this game's zombies at a remote master.
now = 0
sent = {}
local me = player(5, { localPlayer = true })
local remoteMaster = player(3, { master = true })
online = { me, remoteMaster }
locals = { me }
local cl = load_side("client")
tick(cl, 1000)
out[#out + 1] = "clientAsks=" .. tostring(sent[1] and sent[1].command == "evasionRequest")
cl.serverCommand("TSM", "evasion", { list = "3:15" })
tick(cl, 1000)

local mine = zombie(remoteMaster)
local theirs = zombie(remoteMaster, { remote = true })
local atMe = zombie(me)
local toothless = zombie(remoteMaster, { noTeeth = true })
objects = { mine, theirs, atMe, toothless }

-- Swing 1: dodged (roll 0 < 15), toothless through "success", teeth back once the bite is done.
roll = 0
for _, z in ipairs(objects) do z.outcome = "start" end
tick(cl)
out[#out + 1] = "dodgeMakesToothless=" .. tostring(mine.teeth)
out[#out + 1] = "remoteZombieLeft=" .. tostring(not theirs.teeth)
out[#out + 1] = "nonMasterLeft=" .. tostring(not atMe.teeth)
mine.outcome = "success"
tick(cl)
out[#out + 1] = "stillToothlessInSuccess=" .. tostring(mine.teeth)
mine.biteDone = "true"
tick(cl)
out[#out + 1] = "teethBackAfterBite=" .. tostring(not mine.teeth)
out[#out + 1] = "vanillaToothlessKept=" .. tostring(toothless.teeth)

-- Swing 2: not dodged (roll 50).
mine.biteDone = nil
roll = 50
mine.outcome = "start"
tick(cl)
out[#out + 1] = "missedRollBites=" .. tostring(not mine.teeth)

-- Swing 3: dodged, then the zombie walks off mid-swing.
mine.outcome = "success"
tick(cl)
roll = 0
mine.outcome = "start"
tick(cl)
local wasToothless = mine.teeth
objects = {}
tick(cl)
out[#out + 1] = "teethBackWhenGone=" .. tostring(wasToothless and not mine.teeth)

-- Swing 4: dodged, never seen to end: 3 s timeout.
objects = { mine }
mine.outcome = "fail"
tick(cl)
mine.outcome = "start"
tick(cl)
mine.outcome = "success"
for _ = 1, 31 do tick(cl) end
out[#out + 1] = "teethBackAfterTimeout=" .. tostring(not mine.teeth)

-- ---- Player hits.
-- The attacker's game (local wielder) rolls.
local attacker = player(5, { localPlayer = true })
roll = 0
remoteMaster.avoid = false
cl.hit(attacker, remoteMaster, {}, 0.8)
out[#out + 1] = "attackerRollsDodge=" .. tostring(remoteMaster.avoid)
roll = 50
remoteMaster.avoid = false
cl.hit(attacker, remoteMaster, {}, 0.8)
out[#out + 1] = "attackerRollMisses=" .. tostring(not remoteMaster.avoid)
-- Another game: the packet's damage decides.
local otherWielder = player(9)
remoteMaster.avoid = false
cl.hit(otherWielder, remoteMaster, {}, 0)
out[#out + 1] = "zeroDamageCancelled=" .. tostring(remoteMaster.avoid)
remoteMaster.avoid = false
cl.hit(otherWielder, remoteMaster, {}, 0.8)
out[#out + 1] = "realDamageKept=" .. tostring(not remoteMaster.avoid)
-- Not a master: nothing.
local plainTarget = player(6)
roll = 0
cl.hit(attacker, plainTarget, {}, 0.8)
out[#out + 1] = "nonMasterHitKept=" .. tostring(not plainTarget.avoid)
-- The server never rolls, it only cancels 0 damage.
roll = 0
master.avoid = false
sv.hit(plain, master, {}, 0.8)
out[#out + 1] = "serverDoesNotRoll=" .. tostring(not master.avoid)
sv.hit(plain, master, {}, 0)
out[#out + 1] = "serverCancelsZero=" .. tostring(master.avoid)

return table.concat(out, "\n")
''')

print(result)
bad = [line for line in result.split('\n') if line.endswith('=false') or line.endswith('=0')
       or line == 'serverBroadcastOnce=2']
expected = {'serverBroadcastOnce=1'}
missing = [e for e in expected if e not in result.split('\n')]
if bad or missing:
    print('FAILED:', bad + missing)
    sys.exit(1)
print('OK')
