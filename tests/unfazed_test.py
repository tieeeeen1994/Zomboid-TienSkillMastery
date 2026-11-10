"""Runs the real UnfazedRunner file against mocks, then a Lua port of 42.21's `separate` bump roll on the result: no
fall for a master (trees and hedges hold sprint, a character in touching reach holds sprint, the bump-repeat timer and
a leftover bumped character are cleared, others are not solid during a stagger and put back after), vanilla's fall
for a non-master, nothing changed for remote players, the tutorial's sprint setting left alone.

Breaks: nohold (sprint not held near characters), nolastbump (repeat timer kept), nounsolid (others stay solid)."""
import sys
from pathlib import Path

here = Path(__file__).resolve().parent
repo = here.parent
sys.path.insert(0, str(here / '.lupa'))
import lupa

src = (repo / 'Contents/mods/TienSkillMastery/42/media/lua/client/TienSkillMastery_UnfazedRunner.lua') \
    .read_bytes().decode('utf-8').replace('\r\n', '\n')

m = sys.argv[1] if len(sys.argv) > 1 else ''
if m == 'nohold':
    src = src.replace('holdSprint(player, bumping or amongTrees(player))', 'holdSprint(player, amongTrees(player))')
if m == 'nolastbump':
    src = src.replace('player:setLastBump(0)', '')
if m == 'nounsolid':
    src = src.replace('                o:setSolid(false)\n', '')

lua = lupa.LuaRuntime()
lua.globals().source = src
result = lua.execute(r'''
local out = {}
local now = 100000
function require() end
IsoObjectType = { tree = "tree" }

-- Squares by x only; kinds[x] = "tree", "bush", "hedge" or nil; moving objects per x.
local kinds, movers = {}, {}
local function square(x)
    local s = { x = x }
    function s.getX() return x end
    function s.getY() return 0 end
    function s.getZ() return 0 end
    function s.has(_, t) return t == "tree" and (kinds[x] == "tree" or kinds[x] == "bush") end
    function s.getTree()
        if kinds[x] == "tree" then return { getSize = function() return 4 end } end
        if kinds[x] == "bush" then return { getSize = function() return 1 end } end
    end
    function s.getProperties()
        return { get = function(_, k) if k == "Movement" and kinds[x] == "hedge" then return "HedgeLow" end end }
    end
    function s.getMovingObjects()
        local l = {}
        for _, o in ipairs(movers) do if math.floor(o.x) == x then l[#l + 1] = o end end
        return { size = function() return #l end, get = function(_, i) return l[i + 1] end }
    end
    return s
end
function getCell() return { getGridSquare = function(_, x, y, z) if y == 0 then return square(x) end end } end
function instanceof(o, c)
    if c == "IsoGameCharacter" then return o.chr == true end
    return o.class == c
end

local function character(class, x)
    local c = { class = class, chr = true, x = x, solid = true }
    function c.isDead() return false end
    function c.isOnFloor() return false end
    function c.getX() return c.x end
    function c.getY() return 0.5 end
    function c.getZ() return 0 end
    function c.isSolid() return c.solid end
    function c.setSolid(_, b) c.solid = b end
    function c.isReanimatedForGrappleOnly() return false end
    return c
end

local function player(opts)
    local p = character("IsoPlayer", opts.x or 0.5)
    p.master, p.localPlayer, p.allow = opts.master, opts.localPlayer ~= false, true
    p.lastBump, p.bumpedChr, p.bumpType, p.sprintKey = 0, nil, "", true
    function p.isLocalPlayer() return p.localPlayer end
    function p.getCurrentSquare() return square(math.floor(p.x)) end
    function p.getForwardDirection() return { getX = function() return 1 end, getY = function() return 0 end } end
    function p.isAllowSprint() return p.allow end
    function p.setAllowSprint(_, b) p.allow = b end
    function p.setLastBump(_, v) p.lastBump = v end
    function p.getBumpedChr() return p.bumpedChr end
    function p.setBumpedChr(_, c) p.bumpedChr = c end
    function p.isBumped() return p.bumpType ~= "" end
    return p
end

-- 42.21 separate()'s bump roll for `p` touching `obj` (contact assumed), with the sprint input applied first.
local function separate(p, obj)
    if not obj.solid or p.bumpedChr == obj then return "none" end
    local sprinting = p.sprintKey and p.allow
    local wasBumped = p.bumpedChr ~= nil or (now - p.lastBump) / 100 < 15 or sprinting
    local fall = wasBumped and (sprinting or p.roll == 0)
    p.lastBump = now
    p.bumpedChr = obj
    p.bumpType = "left"
    return fall and "fall" or "stagger"
end

local onUpdate
Events = { OnPlayerUpdate = { Add = function(f) onUpdate = f end } }
TienSkillMastery = { sig = function(p, id) assert(id == "Freerunning.SigUnfazedRunner"); return p.master == true end }
assert(load(source))()

-- 1. Trees: held on and half a tile before a tree square, not for a bush, held for a hedge, given back once clear.
local pl = player({ master = true, x = 0.2 })
kinds = { [1] = "tree", [4] = "bush", [6] = "hedge" }
onUpdate(pl); out[#out + 1] = "openGroundSprints=" .. tostring(pl.allow)
pl.x = 0.7; onUpdate(pl); out[#out + 1] = "treeAheadHeld=" .. tostring(not pl.allow)
pl.x = 1.5; onUpdate(pl); out[#out + 1] = "onTreeHeld=" .. tostring(not pl.allow)
pl.x = 3.2; onUpdate(pl); out[#out + 1] = "clearGivenBack=" .. tostring(pl.allow)
pl.x = 4.2; onUpdate(pl); out[#out + 1] = "bushLeft=" .. tostring(pl.allow)
pl.x = 5.7; onUpdate(pl); out[#out + 1] = "hedgeHeld=" .. tostring(not pl.allow)
kinds = {}
pl.x = 8.5; onUpdate(pl)

-- 2. Sprinting into a zombie, a second bump within 1.5 s, an animal during the stagger: always a stagger.
local z = character("IsoZombie", 9.0)
movers = { pl, z }
pl.lastBump = now - 500
pl.roll = 0   -- every vanilla fall roll fails: only wasBumped staying false keeps them up
onUpdate(pl)
out[#out + 1] = "sprintHeldAtContact=" .. tostring(not pl.allow)
out[#out + 1] = "zombieStagger=" .. tostring(separate(pl, z) == "stagger")
local a = character("IsoAnimal", 9.1)
movers = { pl, z, a }
onUpdate(pl)
out[#out + 1] = "othersUnsolidInStagger=" .. tostring(not a.solid)
out[#out + 1] = "animalDuringStagger=" .. tostring(separate(pl, a) ~= "fall")
-- The stagger ends: the animal is solid again and a fresh bump on it is a stagger too.
pl.bumpType, pl.bumpedChr = "", nil
onUpdate(pl)
out[#out + 1] = "animalPutBack=" .. tostring(a.solid)
out[#out + 1] = "animalAfter=" .. tostring(separate(pl, a) == "stagger")
pl.bumpType, pl.bumpedChr = "", nil

-- 3. A leftover bumped character (Battering Ram's shield) is cleared before a bump.
local other = character("IsoPlayer", 9.2)
pl.bumpedChr = z
movers = { pl, other }
onUpdate(pl)
out[#out + 1] = "leftoverCleared=" .. tostring(pl.bumpedChr == nil)
out[#out + 1] = "playerStagger=" .. tostring(separate(pl, other) == "stagger")
pl.bumpType, pl.bumpedChr = "", nil

-- 4. Out of reach: sprint given back.
movers = { pl }
onUpdate(pl)
out[#out + 1] = "sprintBackWhenClear=" .. tostring(pl.allow)

-- 5. Not a master: vanilla's sprint trip happens; nothing changed.
local plain = player({ master = false, x = 8.8 })
plain.lastBump = now - 50000
local z2 = character("IsoZombie", 9.0)
movers = { plain, z2 }
onUpdate(plain)
out[#out + 1] = "nonMasterTrips=" .. tostring(separate(plain, z2) == "fall")

-- 6. Remote player: untouched.
local remote = player({ master = true, localPlayer = false, x = 8.8 })
onUpdate(remote)
out[#out + 1] = "remoteLeft=" .. tostring(remote.allow and remote.lastBump == 0)

-- 7. The tutorial turned sprint off: never turned back on here.
local tut = player({ master = true, x = 1.5 })
tut.allow = false
kinds = { [1] = "tree" }
movers = { tut }
onUpdate(tut)
kinds = {}
tut.x = 3.5
onUpdate(tut)
out[#out + 1] = "othersOffKept=" .. tostring(not tut.allow)

-- 8. Mastery lost while something is held: given back.
local lost = player({ master = true, x = 9.5 })
local z3 = character("IsoZombie", 9.6)
local an = character("IsoAnimal", 9.7)
movers = { lost, z3, an }
onUpdate(lost)
lost.bumpType, lost.bumpedChr = "left", z3
onUpdate(lost)
lost.master = false
onUpdate(lost)
out[#out + 1] = "lostMasteryGivenBack=" .. tostring(lost.allow and an.solid)

return table.concat(out, "\n")
''')

print(result)
bad = [line for line in result.split('\n') if line.endswith('=false')]
if bad:
    print('FAILED:', bad)
    sys.exit(1)
print('OK')
