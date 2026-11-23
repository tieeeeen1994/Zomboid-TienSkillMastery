"""Runs the real Combat file against mocks: Firearms.FireRate speeds up single fire only (vanilla Single, Gunworks'
RealSingle, a gun with no fire mode, GoM's "Bore"), never auto or burst in either naming: the single-shot animation
speed at OnWeaponSwing (the auto one never), the recoil-delay drain at OnPlayerUpdate (with the 150 ms floor after a
shot), and Gunworks' RPM gate, reached through `require` of its RateOfFire module (no global) and wrapped at game
start: `canFire` called through the module table gives a shorter interval for a master's single fire only, never
pushes 150 ms or more under 150 ms, and leaves non-masters and other players alone. Without Gunworks nothing breaks.

Breaks: allmodes (the bonus for every fire mode), global (the old global `RateOfFire` lookup)."""
import sys
from pathlib import Path

here = Path(__file__).resolve().parent
repo = here.parent
sys.path.insert(0, str(here / '.lupa'))
import lupa

src = (repo / 'Contents/mods/TienSkillMastery/42/media/lua/client/TienSkillMastery_Combat.lua') \
    .read_bytes().decode('utf-8').replace('\r\n', '\n')

m = sys.argv[1] if len(sys.argv) > 1 else ''
if m == 'allmodes':
    src = src.replace('return mode == nil or not MULTI_SHOT[string.lower(tostring(mode))]', 'return true')
if m == 'global':
    src = src.replace('local ok, mod = pcall(require, "WeaponSystems/Utils/RateOfFire")',
                      'local ok, mod = true, RateOfFire')


def run(with_gunworks):
    lua = lupa.LuaRuntime()
    lua.globals().source = src
    lua.globals().with_gunworks = with_gunworks
    return lua.execute(r'''
local out = {}
local now = 1000
unpack = unpack or table.unpack
function isServer() return false end
function getTimestampMs() return now end
function ZombRandFloat(a, b) return a end
function ZombRand(n) return 0 end
function instanceof(o, c) return o and o.class == c end
ItemTag = { NO_CRITICALS = "nocrit" }
WeaponType = { KNIFE = "knife", getWeaponType = function() return "firearm" end }
local handlers = {}
Events = setmetatable({}, { __index = function(t, name)
    local e = { Add = function(f) handlers[name] = handlers[name] or {}; table.insert(handlers[name], f) end }
    rawset(t, name, e)
    return e
end })
local function fire(name, ...) for _, f in ipairs(handlers[name] or {}) do f(...) end end

-- Gunworks' RateOfFire: a module reached only through require, as in WeaponSystems/Utils/RateOfFire.lua.
local RoF = nil
if with_gunworks then
    RoF = { lastFireTime = {}, rpm = 600 }
    function RoF.IsWeaponRegistered(w) return w.registered == true end
    function RoF.getWeaponRPM(w) return w.rpm or RoF.rpm end
    function RoF.canFire(player, weapon)
        local id = player:getPlayerNum()
        local interval = 60000 / RoF.getWeaponRPM(weapon)
        local nextAllowed = RoF.lastFireTime[id] or 0
        if now >= nextAllowed then
            RoF.lastFireTime[id] = now + interval
            return true, interval
        end
        return false
    end
end
function require(name)
    if name == "WeaponSystems/Utils/RateOfFire" then
        if RoF then return RoF end
        error("module not found: " .. name)
    end
end

TienSkillMastery = {
    val = function(p, id) return p.vals[id] or 0 end,
    weaponMastery = function(w) return w.firearm and "Firearms" or nil end,
    sig = function() return false end,
    Relay = {},
}

local function gun(mode, registered, rpm)
    local w = { class = "HandWeapon", firearm = true, mode = mode, registered = registered, rpm = rpm }
    function w.isAimedFirearm() return true end
    function w.hasTag() return false end
    function w.getFireMode() return w.mode end
    return w
end

local function player(bonus, isLocal)
    local p = { class = "IsoPlayer", vars = {}, recoil = 0, num = 0, localPlayer = isLocal ~= false,
        vals = { ["Firearms.FireRate"] = bonus } }
    function p.getPlayerNum() return p.num end
    function p.isLocalPlayer() return p.localPlayer end
    function p.isCriticalHit() return false end
    function p.isDoShove() return false end
    function p.getHitInfoList() return { isEmpty = function() return true end } end
    function p.getVariableFloat(_, name, def) return p.vars[name] or def end
    function p.setVariable(_, name, v) p.vars[name] = v end
    function p.isAiming() return false end
    function p.getPrimaryHandItem() return p.hand end
    function p.getRecoilDelay() return p.recoil end
    function p.setRecoilDelay(_, v) p.recoil = v end
    return p
end

assert(load(source))()

-- ---- The shot animation: singleShootSpeed x 1.1 for single fire, autoShootSpeed never.
local function swing(mode, bonus)
    local p, w = player(bonus), gun(mode)
    p.hand = w
    p.vars.singleShootSpeed, p.vars.autoShootSpeed = 1, 1
    fire("OnWeaponSwing", p, w)
    return p.vars.singleShootSpeed, p.vars.autoShootSpeed
end
local function near(a, b) return math.abs(a - b) < 1e-9 end
for _, mode in ipairs({ "Single", "RealSingle", "Bore", "" }) do
    local s, a = swing(mode, 10)
    out[#out + 1] = "animFaster_" .. (mode == "" and "none" or mode) .. "=" .. tostring(near(s, 1.1) and a == 1)
end
local s, a = swing(nil, 10)
out[#out + 1] = "animFaster_nil=" .. tostring(near(s, 1.1) and a == 1)
for _, mode in ipairs({ "Auto", "RealAuto", "Burst", "RealBurst", "auto" }) do
    s, a = swing(mode, 10)
    out[#out + 1] = "animKept_" .. mode .. "=" .. tostring(s == 1 and a == 1)
end
s, a = swing("Single", 0)
out[#out + 1] = "animKeptNonMaster=" .. tostring(s == 1)

-- ---- The recoil delay: vanilla drains 0.625 an update; a master's single fire drains 10% more.
local function drainRun(mode, bonus)
    local p, w = player(bonus), gun(mode)
    p.hand = w
    p.recoil = 10
    fire("OnPlayerUpdate", p)          -- remembers 10
    p.recoil = 9                       -- vanilla drained 1
    now = now + 1000                   -- long after the last shot
    fire("OnPlayerUpdate", p)
    return p.recoil
end
out[#out + 1] = "drainSingle=" .. tostring(near(drainRun("Single", 10), 8.9))
out[#out + 1] = "drainRealSingle=" .. tostring(near(drainRun("RealSingle", 10), 8.9))
out[#out + 1] = "drainNoMode=" .. tostring(near(drainRun(nil, 10), 8.9))
out[#out + 1] = "noDrainAuto=" .. tostring(drainRun("Auto", 10) == 9)
out[#out + 1] = "noDrainRealBurst=" .. tostring(drainRun("RealBurst", 10) == 9)
out[#out + 1] = "noDrainNonMaster=" .. tostring(drainRun("Single", 0) == 9)
-- The floor: within 150 ms of the last shot the delay never reaches 0.
do
    local p, w = player(1000), gun("Single")
    p.hand = w
    p.vars.singleShootSpeed = 1
    fire("OnWeaponSwing", p, w)        -- the shot, now
    p.recoil = 1
    fire("OnPlayerUpdate", p)
    p.recoil = 0.5
    now = now + 50
    fire("OnPlayerUpdate", p)
    out[#out + 1] = "floorHeld=" .. tostring(p.recoil > 0)
end

-- ---- Gunworks' RPM gate, wrapped at game start, through the module table as CustomSystemHooks calls it.
fire("OnGameStart")
if not with_gunworks then
    local p = player(10)
    p.hand = gun("Single")
    fire("OnWeaponSwing", p, p.hand)
    fire("OnPlayerUpdate", p)
    out[#out + 1] = "noGunworksFine=true"
    return table.concat(out, "\n")
end
out[#out + 1] = "wrapped=" .. tostring(RoF.__tsmWrapped == true)
local function interval(mode, bonus, rpm, isLocal)
    local p, w = player(bonus, isLocal), gun(mode, true, rpm)
    p.hand = w
    RoF.lastFireTime = {}
    local ok, ms = RoF.canFire(p, w)
    return ok and ms
end
out[#out + 1] = "rpm150Kept=" .. tostring(near(interval("RealSingle", 10, 400), 150))
out[#out + 1] = "rpmSlowGunFaster=" .. tostring(near(interval("RealSingle", 10, 100), 600 / 1.1))
out[#out + 1] = "rpmNoModeFaster=" .. tostring(near(interval(nil, 10, 100), 600 / 1.1))
out[#out + 1] = "rpmRealAutoKept=" .. tostring(near(interval("RealAuto", 10, 100), 600))
out[#out + 1] = "rpmRealBurstKept=" .. tostring(near(interval("RealBurst", 10, 100), 600))
out[#out + 1] = "rpmFloor150=" .. tostring(near(interval("RealSingle", 50, 300), 150))
out[#out + 1] = "rpmUnder150Kept=" .. tostring(near(interval("RealSingle", 10, 600), 100))
out[#out + 1] = "rpmNonMasterKept=" .. tostring(near(interval("RealSingle", 0, 100), 600))
out[#out + 1] = "rpmRemoteKept=" .. tostring(near(interval("RealSingle", 10, 100, false), 600))
-- getWeaponRPM outside canFire (Gunworks' UI labels) is the gun's own.
local w = gun("RealSingle", true, 100)
out[#out + 1] = "rpmOutsideCanFireKept=" .. tostring(RoF.getWeaponRPM(w) == 100)
fire("OnGameStart")
out[#out + 1] = "wrappedOnce=" .. tostring(near(interval("RealSingle", 10, 100), 600 / 1.1))
return table.concat(out, "\n")
''')


lines = run(True).split('\n') + run(False).split('\n')
print('\n'.join(lines))
bad = [line for line in lines if line.endswith('=false')]
if bad:
    print('FAILED:', bad)
    sys.exit(1)
print('OK')
