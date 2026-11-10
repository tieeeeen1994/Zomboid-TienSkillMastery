"""Runs the real Stealth file against mocks: the wrapped `addSound` cuts a master's own-square work noise and leaves
admin noises at a clicked square, non-masters, animals and extra arguments alone; the melee weapon in a local master's
hand is made quieter and gets its radius back once switched, put away or the mastery is lost; guns are left alone.

Breaks: nosquare (any square is cut), norestore (weapons never put back), ranged (guns cut too)."""
import sys
from pathlib import Path

here = Path(__file__).resolve().parent
repo = here.parent
sys.path.insert(0, str(here / '.lupa'))
import lupa

src = (repo / 'Contents/mods/TienSkillMastery/42/media/lua/shared/TienSkillMastery_Stealth.lua') \
    .read_bytes().decode('utf-8').replace('\r\n', '\n')

m = sys.argv[1] if len(sys.argv) > 1 else ''
if m == 'nosquare':
    src = src.replace('math.floor(x) ~= math.floor(source:getX()) or math.floor(y) ~= math.floor(source:getY())', 'false')
    src = src.replace('        or math.floor(z) ~= math.floor(source:getZ()) then', '        or false then')
if m == 'norestore':
    src = src.replace('        pcall(function() w:setSoundRadius(S.cutWeapons[w]) end)\n', '')
if m == 'ranged':
    src = src.replace('and not w:isRanged() then', 'then')

lua = lupa.LuaRuntime()
lua.globals().source = src
result = lua.execute(r'''
local out = {}
function require() end
function isServer() return false end
function instanceof(o, c)
    if c == "IsoAnimal" then return o.animal == true end
    return o.class == c or (c == "IsoPlayer" and o.animal == true)
end
local heard = {}
function addSound(source, x, y, z, radius, volume, extra)
    heard[#heard + 1] = { radius = radius, volume = volume, extra = extra }
end
local tick
Events = { OnTick = { Add = function(f) tick = f end } }

local function player(master)
    local p = { class = "IsoPlayer", master = master, hand = nil }
    function p.isDead() return false end
    function p.getX() return 10.4 end
    function p.getY() return 20.7 end
    function p.getZ() return 0 end
    function p.getPrimaryHandItem() return p.hand end
    return p
end
local function weapon(radius, ranged)
    local w = { class = "HandWeapon", radius = radius, ranged = ranged }
    function w.isRanged() return w.ranged end
    function w.getSoundRadius() return w.radius end
    function w.setSoundRadius(_, r) w.radius = r end
    return w
end
TienSkillMastery = { val = function(p, id) return p.master and 50 or 0 end }
local locals = {}
function getNumActivePlayers() return #locals end
function getSpecificPlayer(i) return locals[i + 1] end
assert(load(source))()

local function last() return heard[#heard] end

-- Quiet work.
local master, plain = player(true), player(false)
addSound(master, master:getX(), master:getY(), master:getZ(), 20, 10)
out[#out + 1] = "ownSquareHalved=" .. tostring(last().radius == 10 and last().volume == 10)
addSound(master, 10, 20, 0, 20, 10)
out[#out + 1] = "sameSquareIntegers=" .. tostring(last().radius == 10)
addSound(master, 14, 25, 0, 30, 30)
out[#out + 1] = "adminClickedSquareKept=" .. tostring(last().radius == 30)
addSound(plain, plain:getX(), plain:getY(), plain:getZ(), 20, 10)
out[#out + 1] = "nonMasterKept=" .. tostring(last().radius == 20)
local animal = player(true); animal.animal = true
addSound(animal, animal:getX(), animal:getY(), animal:getZ(), 20, 10)
out[#out + 1] = "animalKept=" .. tostring(last().radius == 20)
addSound(master, 10, 20, 0, 1, 1)
out[#out + 1] = "neverUnderOne=" .. tostring(last().radius == 1)
addSound(nil, 10, 20, 0, 20, 10, "x")
out[#out + 1] = "noSourceAndExtraArgs=" .. tostring(last().radius == 20 and last().extra == "x")

-- Quiet swings.
local bat, gun, knife = weapon(15, false), weapon(40, true), weapon(5, false)
master.hand = bat
locals = { master }
tick()
out[#out + 1] = "meleeHalved=" .. tostring(bat.radius == 8)
tick()
out[#out + 1] = "notCutTwice=" .. tostring(bat.radius == 8)
master.hand = knife
tick()
out[#out + 1] = "switchedBack=" .. tostring(bat.radius == 15 and knife.radius == 3)
master.hand = gun
tick()
out[#out + 1] = "gunLeftAlone=" .. tostring(gun.radius == 40 and knife.radius == 5)
master.hand = bat
tick()
master.master = false
tick()
out[#out + 1] = "lostMasteryBack=" .. tostring(bat.radius == 15)
master.master = true
tick()
master.hand = nil
tick()
out[#out + 1] = "putAwayBack=" .. tostring(bat.radius == 15)
plain.hand = bat
locals = { plain }
tick()
out[#out + 1] = "nonMasterSwingKept=" .. tostring(bat.radius == 15)

return table.concat(out, "\n")
''')

print(result)
bad = [line for line in result.split('\n') if line.endswith('=false')]
if bad:
    print('FAILED:', bad)
    sys.exit(1)
print('OK')
