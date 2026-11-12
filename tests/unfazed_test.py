"""Runs the real UnfazedRunner file against mocks, then a Lua port of 42.22's `separate` bump roll on the result: a
sprinting master who bumps into a zombie staggers (and so does the zombie) but never falls, nobody else can be bumped
into while that stagger plays, Toggle to Sprint / Run is put back after it (vanilla's movement block switched it off)
while a movement key is held, trees and hedges hold the sprint, vanilla's fall for a non-master, nothing changed for
remote players, the tutorial's sprint setting left alone.

Breaks: nounsolid (nobody made not solid), norestore (players / animals never put back), nolastbump (repeat timer
kept), notoggle (the sprint toggle never put back)."""
import sys
from pathlib import Path

here = Path(__file__).resolve().parent
repo = here.parent
sys.path.insert(0, str(here / '.lupa'))
import lupa

src = (repo / 'Contents/mods/TienSkillMastery/42/media/lua/client/TienSkillMastery_UnfazedRunner.lua') \
    .read_bytes().decode('utf-8').replace('\r\n', '\n')

m = sys.argv[1] if len(sys.argv) > 1 else ''
if m == 'norestore':
    src = src.replace('        pcall(function() c:setSolid(true) end)\n', '')
if m == 'nolastbump':
    src = src.replace('player:setLastBump(0)', '')
if m == 'notoggle':
    src = src.replace('if r.sprint then player:setForceSprint(true) end', '')
if m == 'nounsolid':
    src = src.replace('                o:setSolid(false)\n', '')

lua = lupa.LuaRuntime()
lua.globals().source = src
result = lua.execute(r'''
local out = {}
local now = 100000
function require() end
function getTimestampMs() return now end
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
    p.lastBump, p.bumpedChr, p.bumpType, p.sprintKey, p.running = 0, nil, "", true, true
    p.forceSprint, p.forceRun, p.moveKeys = false, false, true
    local function sprintInput() return p.sprintKey or p.forceSprint end
    function p.isRunning() return p.running and not (sprintInput() and p.allow) end
    function p.isSprinting() return p.running and sprintInput() and p.allow end
    function p.isForceSprint() return p.forceSprint end
    function p.setForceSprint(_, b) p.forceSprint = b end
    function p.isForceRun() return p.forceRun end
    function p.setForceRun(_, b) p.forceRun = b end
    function p.pressedMovement(_, ignoreBlock) assert(ignoreBlock == true); return p.moveKeys end
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
    local sprinting = (p.sprintKey or p.forceSprint) and p.allow
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

-- 2. Sprinting into a zombie with an animal and a player close by: sprint held off for the touch, so the bump is a
--    stagger, never a fall (every vanilla fall roll fails here), and no one else can be bumped into while it plays.
local z = character("IsoZombie", 9.0)
local a = character("IsoAnimal", 9.1)
local other = character("IsoPlayer", 9.2)
movers = { pl, z, a, other }
pl.lastBump = now - 500
pl.roll = 0
onUpdate(pl)
out[#out + 1] = "sprintHeldAtTouch=" .. tostring(not pl.allow)
out[#out + 1] = "zombieStaggersNoFall=" .. tostring(separate(pl, z) == "stagger")
pl.lastBump = now - 100
onUpdate(pl)
out[#out + 1] = "lastBumpReset=" .. tostring(pl.lastBump == 0)
out[#out + 1] = "othersPassedInStagger=" .. tostring(not a.solid and not other.solid)
out[#out + 1] = "animalNotBumpedInStagger=" .. tostring(separate(pl, a) == "none")

-- 3. Stagger over, nobody in reach: players and animals solid again, sprint allowed again.
pl.bumpType, pl.bumpedChr = "", nil
movers = { pl }
pl.x = 12.5
onUpdate(pl)
out[#out + 1] = "putBackAfterStagger=" .. tostring(a.solid and other.solid and pl.allow)

-- 3b. Toggle to Sprint: the stagger's movement block switches the toggle off; after it the toggle is put back while
--     a movement key is held, then left to the game once the master sprints again.
local tg = player({ master = true, x = 20.5 })
tg.sprintKey, tg.forceSprint = false, true
movers = { tg }
onUpdate(tg)                                  -- sprinting on the toggle, seen outside a stagger
tg.bumpType, tg.bumpedChr = "left", z
onUpdate(tg)                                  -- stagger starts
tg.forceSprint = false                        -- the game: zero move direction while blocked (IsoPlayer ~2425)
onUpdate(tg)
tg.forceSprint = false
tg.bumpType, tg.bumpedChr = "", nil           -- stagger over
onUpdate(tg)
out[#out + 1] = "toggleBackAfterStagger=" .. tostring(tg.forceSprint)
tg.forceSprint = false                        -- the stagger's last zero direction clears it once more
onUpdate(tg)
out[#out + 1] = "toggleBackAgain=" .. tostring(tg.forceSprint)
for _ = 1, 3 do onUpdate(tg) end              -- sprinting at pace: settled
tg.forceSprint = false                        -- the player stops later: vanilla ends the toggle, not put back now
tg.running = false
onUpdate(tg)
out[#out + 1] = "settledThenLeftAlone=" .. tostring(not tg.forceSprint)

-- 3c. Movement keys let go during the stagger: the toggle stays off (vanilla stop).
local st = player({ master = true, x = 24.5 })
st.sprintKey, st.forceSprint = false, true
movers = { st }
onUpdate(st)
st.bumpType, st.bumpedChr = "left", z
onUpdate(st)
st.forceSprint, st.moveKeys = false, false
onUpdate(st)
st.bumpType, st.bumpedChr = "", nil
st.moveKeys = true
onUpdate(st)
out[#out + 1] = "stoppedInStaggerStaysOff=" .. tostring(not st.forceSprint)

-- 3d. Hold to sprint (no toggle): nothing switched on.
local hs = player({ master = true, x = 28.5 })
movers = { hs }
onUpdate(hs)
hs.bumpType, hs.bumpedChr = "left", z
onUpdate(hs)
hs.bumpType, hs.bumpedChr = "", nil
onUpdate(hs)
out[#out + 1] = "holdToSprintUntouched=" .. tostring(not hs.forceSprint and not hs.forceRun)

-- 3e. Never past RESTORE_MS.
local to = player({ master = true, x = 32.5 })
to.sprintKey, to.forceSprint = false, true
movers = { to }
onUpdate(to)
to.bumpType, to.bumpedChr = "left", z
onUpdate(to)
to.bumpType, to.bumpedChr, to.forceSprint, to.allow = "", nil, false, true
to.running = false                            -- never at pace, so never settled
onUpdate(to)
now = now + 2000
to.forceSprint = false
onUpdate(to)
out[#out + 1] = "restoreTimesOut=" .. tostring(not to.forceSprint)

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

-- 8. Mastery lost mid-stagger: everyone put back, sprint allowed.
local lost = player({ master = true, x = 9.5 })
local an = character("IsoAnimal", 9.7)
movers = { lost, an }
lost.bumpType, lost.bumpedChr = "left", z
onUpdate(lost)
local was = not an.solid
lost.master = false
onUpdate(lost)
out[#out + 1] = "lostMasteryGivenBack=" .. tostring(was and an.solid and lost.allow)

return table.concat(out, "\n")
''')

print(result)
bad = [line for line in result.split('\n') if line.endswith('=false')]
if bad:
    print('FAILED:', bad)
    sys.exit(1)
print('OK')
