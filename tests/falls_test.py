"""Runs the real Falls file against a Lua port of 42.21's `updateFalling` (speed + 5.001 x dt per update, drop speed x dt
+ 2.5 x dt^2) on a server at 1x and at 5x fast forward, and sorts each landing into `FallingConstants` tiers by impact
speed: safe drops land harmless, higher ones one floor lower, a non-master falls as vanilla.

Breaks: nolower (higher drops not lowered), nosafe (safe drops not held)."""
import sys
from pathlib import Path

here = Path(__file__).resolve().parent
repo = here.parent
sys.path.insert(0, str(here / '.lupa'))
import lupa

src = (repo / 'Contents/mods/TienSkillMastery/42/media/lua/shared/TienSkillMastery_Falls.lua') \
    .read_bytes().decode('utf-8').replace('\r\n', '\n')

m = sys.argv[1] if len(sys.argv) > 1 else ''
if m == 'nolower':
    src = src.replace('cap = math.sqrt(2 * G * math.max(0, drop - 1))', 'cap = math.huge')
if m == 'nosafe':
    src = src.replace('        cap = capNow()\n', '        cap = math.huge\n')

lua = lupa.LuaRuntime()
lua.globals().source = src
result = lua.execute(r'''
local out = {}
local G = 5.0010414
local dt = 0.016
function require() end
function isServer() return true end
function getGameTime() return { getTimeDelta = function() return dt / 0.16 end } end
local tick
Events = {
    OnTick = { Add = function(f) tick = f end },
    OnPlayerUpdate = { Add = function() end },
    EveryHours = { Add = function() end },
}
local players = {}
function getOnlinePlayers()
    return { size = function() return #players end, get = function(_, i) return players[i + 1] end }
end
TienSkillMastery = { val = function(p, id) assert(id == "Freerunning.SafeFall"); return p.allowed end }
assert(load(source))()

-- FallingConstants by height in levels: damage 0.5, hard 1.5, severe 2.5, lethal 3.5.
local function tier(speed)
    local h = speed * speed / (2 * G)
    if h < 0.5 then return "none" elseif h < 1.5 then return "light" elseif h < 2.5 then return "hard"
    elseif h < 3.5 then return "severe" end
    return "lethal"
end

local function fall(floors, allowed, step)
    dt = step
    local p = { z = floors, speed = 0, allowed = allowed }
    function p.isDead() return false end
    function p.getZ() return p.z end
    function p.getHeightAboveFloor() return p.z end
    function p.getLastFallSpeed() return p.speed end
    function p.setLastFallSpeed(_, v) p.speed = v end
    players = { p }
    for _ = 1, 100000 do
        -- IsoGameCharacter.updateFalling (server: dt = timeDelta x 0.16)
        p.speed = p.speed + G * dt
        local nz = p.z - (p.speed * dt + 2.5 * dt * dt)
        if nz <= 0 then return tier(p.speed) end
        p.z = nz
        tick()   -- OnTick: after the cell update
    end
    return "never landed"
end

for _, step in ipairs({ 0.016, 0.08 }) do
    local tag = step == 0.016 and "1x" or "5x"
    out[#out + 1] = tag .. " plain 1=" .. fall(1, 0, step) .. " 2=" .. fall(2, 0, step) .. " 3=" .. fall(3, 0, step)
    out[#out + 1] = tag .. " m3 1=" .. fall(1, 1, step) .. " 2=" .. fall(2, 1, step) .. " 3=" .. fall(3, 1, step)
    out[#out + 1] = tag .. " m6 2=" .. fall(2, 2, step) .. " 3=" .. fall(3, 2, step) .. " 4=" .. fall(4, 2, step)
    out[#out + 1] = tag .. " m9 3=" .. fall(3, 3, step) .. " 4=" .. fall(4, 3, step) .. " 5=" .. fall(5, 3, step)
        .. " 6=" .. fall(6, 3, step)
end
return table.concat(out, "\n")
''')

print(result)
want = {
    'plain 1=light 2=hard 3=severe',
    'm3 1=none 2=light 3=hard',
    'm6 2=none 3=hard 4=severe',
    'm9 3=none 4=severe 5=lethal 6=lethal',
}
lines = result.split('\n')
bad = [w for w in want for speed in ('1x', '5x') if f'{speed} {w}' not in lines]
if bad:
    print('FAILED:', bad)
    sys.exit(1)
print('OK')
