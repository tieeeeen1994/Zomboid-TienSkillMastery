"""Runs the real Relay file and the real postureOf / showHit from Throw against mocks of server and client."""
import re
import sys
from pathlib import Path

here = Path(__file__).resolve().parent
repo = here.parent
sys.path.insert(0, str(here / '.lupa'))
import lupa

base = (repo / 'Contents/mods/TienSkillMastery/42/media/lua/shared')
relay = (base / 'TienSkillMastery_Relay.lua').read_bytes().decode('utf-8').replace('\r\n', '\n')
throw = (base / 'TienSkillMastery_Throw.lua').read_bytes().decode('utf-8').replace('\r\n', '\n')

m = sys.argv[1] if len(sys.argv) > 1 else ''
if m == 'noshowbowl':
    relay = relay.replace('R.SHOWN = { pushback = true, bowl = true }', 'R.SHOWN = { pushback = true }')
if m == 'nostate':
    throw = throw.replace('if ZOMBIE_DOWN_STATES[realState] then return "down" end', '')
if m == 'nocrawl':
    throw = throw.replace('if bool(chr, "isCrawling") then return "down" end', '')
if m == 'nosit':
    throw = throw.replace(' or realState == "sitting"', '')
if m == 'noanimal':
    throw = throw.replace('animal:setHitReaction("hitreact")', '')
if m == 'noevent':
    throw = throw.replace('target:reportEvent("washitpvp")', '')

# Pieces of the real Throw file: its 2000 lines need the whole game, these two functions do not.
posture = re.search(r'local ZOMBIE_DOWN_STATES.*?\nlocal function bool.*?\nend\n\nfunction Th\.postureOf.*?\nend\n', throw, re.S)
if not posture:
    a = throw.index('local ZOMBIE_DOWN_STATES')
    b = throw.index('function Th.topOf')
    posture_src = throw[a:b]
else:
    posture_src = posture.group(0)
a = throw.index('function Th.showHit(args)')
b = throw.index('Events.OnServerCommand.Add', a)
show_src = throw[a:b]

lua = lupa.LuaRuntime()
g = lua.globals()
g.relay_source, g.posture_source, g.show_source = relay, posture_src, show_src
result = lua.execute(r'''
unpack = table.unpack
local handlers = { client = {}, server = {}, tick = {} }
local side = "server"
local out = {}

function require() end
function instanceof(o, c) return o.class == c end
function ZombRandFloat() return 0 end
function getTimestampMs() return 0 end

local function zombie(id, opts)
    opts = opts or {}
    local z = { class = "IsoZombie", id = id, log = {}, floor = opts.floor or false, crawl = opts.crawl or false,
        remote = opts.remote or false, owner = opts.owner, state = opts.state or "idle", wall = opts.wall or false }
    function z.getOnlineID() return z.id end
    function z.isDead() return false end
    function z.isReanimatedForGrappleOnly() return false end
    function z.isRemoteZombie() return z.remote end
    function z.isOnFloor() return z.floor end
    function z.isCrawling() return z.crawl end
    function z.isKnockedDown() return false end
    function z.getRealState() return z.state end
    function z.isSitOnGround() return false end
    function z.isSittingOnFurniture() return false end
    function z.isSitAgainstWall() return z.wall end
    function z.getOwnerPlayer() return z.owner end
    function z.DistToProper() return 1 end
    function z.getX() return 5 end
    function z.getY() return 5 end
    function z.getForwardDirectionX() return 1 end
    function z.getForwardDirectionY() return 0 end
    function z.knockDown(_, behind) z.log[#z.log + 1] = "knockDown:" .. tostring(behind) end
    function z.setPlayerAttackPosition() end
    function z.setHitForce() end
    function z.getHitDir() return nil end
    function z.setStaggerBack() z.log[#z.log + 1] = "stagger" end
    function z.reportEvent() end
    return z
end

local zombies = {}
local sent = {}

getCell = function()
    return { getZombieList = function()
        return { size = function() return #zombies end, get = function(_, i) return zombies[i + 1] end }
    end }
end
function sendServerCommand(a, b, c, d)
    if type(a) == "string" then sent[#sent + 1] = { to = "all", module = a, command = b, args = c }
    else sent[#sent + 1] = { to = a, module = b, command = c, args = d } end
end
function sendClientCommand(_, _, command, args) sent[#sent + 1] = { to = "server", command = command, args = args } end

CharacterStat = { ENDURANCE = "endurance" }
TienSkillMastery = { MODULE = "TSM", sig = function() return true end, val = function() return 0 end }

local function load_side(which)
    side = which
    local h = {}
    function isServer() return which == "server" end
    function isClient() return which == "client" end
    Events = {
        OnClientCommand = { Add = function(f) h.command = h.command or {}; table.insert(h.command, f) end },
        OnServerCommand = { Add = function(f) h.serverCommand = h.serverCommand or {}; table.insert(h.serverCommand, f) end },
        OnTick = { Add = function(f) h.tick = f end },
    }
    TienSkillMastery.Relay = nil
    assert(load(relay_source))()
    return h, TienSkillMastery.Relay
end

-- ---- Battering Ram: the server tells everyone.
local attacker = { getX = function() return 4 end, getY = function() return 5 end,
    getStats = function() return { get = function() return 1 end, set = function() end } end }
local owner = { name = "owner" }
local sv = load_side("server")
zombies = { zombie(7, { owner = owner }) }
for _, f in ipairs(sv.command) do f("TSM", "zombieAct", attacker, { kind = "bowl", ids = { 7 } }) end
local showTo, applyTo = 0, 0
for _, s in ipairs(sent) do
    if s.command == "zombieActShow" and s.to == "all" and s.args.kind == "bowl" then showTo = showTo + 1 end
    if s.command == "zombieActApply" and s.to == owner then applyTo = applyTo + 1 end
end
out[#out + 1] = "serverShowsBowl=" .. showTo
out[#out + 1] = "serverAppliesToOwner=" .. applyTo

-- ---- Battering Ram: a client with a remote copy falls it, the owner's own copy is left to zombieActApply.
local cl = load_side("client")
local remoteCopy, ownCopy = zombie(7, { remote = true }), zombie(8, { remote = false })
zombies = { remoteCopy, ownCopy }
local show = { kind = "bowl", ids = { 7, 8 }, x = 4, y = 5 }
for _, f in ipairs(cl.serverCommand) do f("TSM", "zombieActShow", show) end
cl.tick()
out[#out + 1] = "remoteCopyFalls=" .. table.concat(remoteCopy.log, ",")
out[#out + 1] = "ownCopyLeftAlone=" .. #ownCopy.log
local frontCopy = zombie(10, { remote = true })
zombies = { frontCopy }
for _, f in ipairs(cl.serverCommand) do f("TSM", "zombieActShow", { kind = "bowl", ids = { 10 }, x = 9, y = 5 }) end
cl.tick()
out[#out + 1] = "remoteCopyFront=" .. table.concat(frontCopy.log, ",")

-- ---- Unknown kinds off the wire do nothing.
local other = zombie(9, { remote = true })
zombies = { other }
for _, f in ipairs(cl.serverCommand) do f("TSM", "zombieActShow", { kind = "hamstring", ids = { 9 }, x = 1, y = 1 }) end
cl.tick()
out[#out + 1] = "unknownKindIgnored=" .. #other.log

-- ---- Lying zombies on a server: isOnFloor is false there, the state and flags tell.
Th = {}
assert(load(posture_source))()
local function pose(label, opts) out[#out + 1] = label .. "=" .. Th.postureOf(zombie(1, opts), "zombie") end
pose("poseStanding", { state = "walktoward-network" })
pose("poseFallDown", { state = "falldown" })
pose("poseOnGround", { state = "onground" })
pose("poseGetUp", { state = "getup" })
pose("poseFakeDead", { state = "fakedead" })
pose("poseCrawling", { state = "walktoward", crawl = true })
pose("poseSitting", { state = "sitting" })
pose("poseAgainstWall", { state = "idle", wall = true })
pose("poseOnClient", { floor = true, state = "idle" })
pose("poseAttacking", { state = "attack-network" })
-- A player has no getRealState: must not break.
local pl = { isOnFloor = function() return false end, isSitOnGround = function() return false end,
    isSittingOnFurniture = function() return false end }
out[#out + 1] = "posePlayer=" .. Th.postureOf(pl, "player")
out[#out + 1] = "poseAnimal=" .. Th.postureOf(pl, "animal")

-- ---- Flinches.
assert(load(show_source))()
local function actor(dead)
    local a = { log = {}, force = 1.0, behind = "unset" }
    function a.isDead() return dead or false end
    function a.getVehicle() return a.vehicle end
    function a.isAsleep() return a.asleep or false end
    function a.setHitReaction(_, r) a.log[#a.log + 1] = "reaction:" .. r end
    function a.splatBloodFloorBig() a.log[#a.log + 1] = "blood" end
    function a.getHitForce() return a.force end
    function a.setHitForce(_, f) a.force = f end
    function a.getX() return 10 end
    function a.getY() return 10 end
    function a.getForwardDirectionX() return 1 end
    function a.getForwardDirectionY() return 0 end
    function a.setHitFromBehind(_, b) a.behind = b end
    function a.reportEvent(_, e) a.log[#a.log + 1] = "event:" .. e end
    function a.setVariable(_, k, v) a.log[#a.log + 1] = k .. ":" .. tostring(v) end
    return a
end
local beast, person
function getAnimal(id) return id == 3 and beast or nil end
function getPlayerByOnlineID(id) return id == 4 and person or nil end

beast = actor()
Th.showHit({ kind = "animal", id = 3 })
out[#out + 1] = "animalFlinch=" .. table.concat(beast.log, ",")
beast = actor(true)
Th.showHit({ kind = "animal", id = 3 })
out[#out + 1] = "deadAnimalLeft=" .. #beast.log
beast = nil
Th.showHit({ kind = "animal", id = 3 })
out[#out + 1] = "unknownAnimalSafe=ok"

person = actor()
Th.showHit({ kind = "player", id = 4, tx = 5, ty = 10 })   -- thrower at x 5, target at x 10 facing +x: from behind
out[#out + 1] = "playerFlinch=" .. table.concat(person.log, ",")
out[#out + 1] = "playerForce=" .. person.force
out[#out + 1] = "playerBehind=" .. tostring(person.behind)
person = actor()
Th.showHit({ kind = "player", id = 4, tx = 15, ty = 10 })  -- from in front
out[#out + 1] = "playerFront=" .. tostring(person.behind)
person = actor(); person.vehicle = true
Th.showHit({ kind = "player", id = 4 })
out[#out + 1] = "inVehicleLeft=" .. #person.log
person = actor(); person.asleep = true
Th.showHit({ kind = "player", id = 4 })
out[#out + 1] = "asleepLeft=" .. #person.log
beast = actor()
Th.showHit({ kind = "zombie", id = 3 })
out[#out + 1] = "zombieNoFlinchHere=" .. #beast.log
return table.concat(out, " ")
''')
print(result.replace(' ', '\n'))
want = {
    'serverShowsBowl': '1', 'serverAppliesToOwner': '1',
    'remoteCopyFalls': 'knockDown:true',    # attacker at x 4, zombie at x 5 facing +x: the attacker is behind it
    'remoteCopyFront': 'knockDown:false',   # attacker at x 9, in front of it
    'ownCopyLeftAlone': '0', 'unknownKindIgnored': '0',
    'poseStanding': 'stand', 'poseFallDown': 'down', 'poseOnGround': 'down', 'poseGetUp': 'down', 'poseFakeDead': 'down',
    'poseCrawling': 'down', 'poseSitting': 'sit', 'poseAgainstWall': 'sit', 'poseOnClient': 'down', 'poseAttacking': 'stand',
    'posePlayer': 'stand', 'poseAnimal': 'animal',
    'animalFlinch': 'reaction:hitreact,blood', 'deadAnimalLeft': '0', 'unknownAnimalSafe': 'ok',
    'playerFlinch': 'reaction:HitReaction,event:washitpvp,hitpvp:true,blood',
    'playerForce': '0.5', 'playerBehind': 'true', 'playerFront': 'false', 'inVehicleLeft': '0', 'asleepLeft': '0',
    'zombieNoFlinchHere': '0',
}
got = dict(p.split('=', 1) for p in result.split())
bad = {k: (got.get(k), v) for k, v in want.items() if got.get(k) != v}
print('FAILED' if bad else 'all %d checks passed' % len(want))
for k, v in bad.items():
    print('  ', k, 'got', v[0], 'want', v[1])
sys.exit(1 if bad else 0)
