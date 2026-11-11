"""Runs the real Combat file against mocks: Firearms.Crit makes a trigger pull with a target a crit at vanilla's chance
for that target plus the bonus (bonus / 100 on top when the target is not found), never for a non-master or a
NoCriticals gun, with vanilla's x1.1 combat speed; and raises the gun's crit chance for the shot at
OnWeaponSwingHitPoint (for Guns of Tien's per-target rolls), put back on the next tick.

Breaks: noformula (the plain bonus / 100 even with the target known), nofield (no crit chance raise for the shot)."""
import sys
from pathlib import Path

here = Path(__file__).resolve().parent
repo = here.parent
sys.path.insert(0, str(here / '.lupa'))
import lupa

src = (repo / 'Contents/mods/TienSkillMastery/42/media/lua/client/TienSkillMastery_Combat.lua') \
    .read_bytes().decode('utf-8').replace('\r\n', '\n')

m = sys.argv[1] if len(sys.argv) > 1 else ''
if m == 'noformula':
    src = src.replace('chance = 100 * bonus / (100 - base)', 'chance = bonus')
if m == 'nofield':
    src = src.replace('change(entry, "crit", weapon:getCriticalChance() + crit)', '')

lua = lupa.LuaRuntime()
lua.globals().source = src
result = lua.execute(r'''
local out = {}
math.randomseed(7)
function require() end
function isServer() return false end
function getTimestampMs() return 0 end
function ZombRandFloat(a, b) return a + math.random() * (b - a) end
function ZombRand(n) return math.random(0, n - 1) end
function instanceof(o, c) return o and o.class == c end
ItemTag = { NO_CRITICALS = "nocrit" }
Perks = { Aiming = "Aiming" }
CombatConfigKey = { ADDITIONAL_CRITICAL_HIT_CHANCE_DEFAULT = "behind" }
function getCombatConfig() return { get = function(_, k) return 10 end } end
local handlers = {}
Events = setmetatable({}, { __index = function(t, name)
    local e = { Add = function(f) handlers[name] = handlers[name] or {}; table.insert(handlers[name], f) end }
    rawset(t, name, e)
    return e
end })
local function fire(name, ...) for _, f in ipairs(handlers[name] or {}) do f(...) end end

local zombie = { x = 15, y = 20 }
function zombie.isDead() return false end
function zombie.isReanimatedForGrappleOnly() return false end
function zombie.getX() return zombie.x end
function zombie.getY() return zombie.y end
function zombie.getZ() return 0 end
local zlist = { zombie }
function getCell()
    return { getZombieList = function() return {
        size = function() return #zlist end, get = function(_, i) return zlist[i + 1] end } end }
end

TienSkillMastery = {
    val = function(p, id) return p.vals[id] or 0 end,
    weaponMastery = function(w) return w.firearm and "Firearms" or nil end,
    sig = function() return false end,
    Relay = {},
}

local function gun(nocrit)
    local w = { class = "HandWeapon", firearm = true, crit = 5, nocrit = nocrit }
    function w.isAimedFirearm() return true end
    function w.hasTag(_, t) return t == "nocrit" and w.nocrit end
    function w.getCriticalChance() return w.crit end
    function w.setCriticalChance(_, v) w.crit = v end
    function w.getAimingPerkHitChanceModifier() return 4 end
    return w
end

local function player(bonus)
    local p = { class = "IsoPlayer", crit = false, speed = 1, targetDist = 5, vals = { ["Firearms.Crit"] = bonus } }
    function p.getPlayerNum() return 0 end
    function p.isLocalPlayer() return true end
    function p.isCriticalHit() return p.crit end
    function p.setCriticalHit(_, b) p.crit = b end
    function p.isDoShove() return false end
    function p.isAimAtFloor() return false end
    function p.isAttackFromBehind() return false end
    function p.getHitInfoList() return { isEmpty = function() return false end } end
    function p.getVariableFloat(_, name, def) if name == "TargetDist" then return p.targetDist end return 0 end
    function p.setVariable() end
    function p.getX() return 10 end
    function p.getY() return 20 end
    function p.getZ() return 0 end
    function p.getForwardDirectionX() return 1 end
    function p.getForwardDirectionY() return 0 end
    function p.getPerkLevel() return 10 end
    function p.getCombatSpeed() return p.speed end
    function p.setCombatSpeed(_, v) p.speed = v end
    -- vanilla's chance for the zombie: 15 + the gun's crit chance
    function p.calculateCritChance(_, t) assert(t == zombie); return 15 + p.gunInHand.crit end
    return p
end

assert(load(source))()

local function rate(p, w, n)
    p.gunInHand = w
    local crits = 0
    for i = 1, n do
        p.crit = math.random() * 100 < 15 + w.crit
        if w.nocrit then p.crit = false end
        fire("OnWeaponSwing", p, w)
        if p.crit then crits = crits + 1 end
    end
    return 100 * crits / n
end

local N = 60000
local r = rate(player(5), gun(false), N)
out[#out + 1] = string.format("masterBasePlusBonus=%s", tostring(math.abs(r - 25) < 0.6))
local lost = player(5); lost.targetDist = 9
r = rate(lost, gun(false), N)
out[#out + 1] = string.format("unknownTargetBonusOnTop=%s", tostring(math.abs(r - 24) < 0.6))
r = rate(player(0), gun(false), N)
out[#out + 1] = string.format("nonMasterVanilla=%s", tostring(math.abs(r - 20) < 0.6))
r = rate(player(5), gun(true), 2000)
out[#out + 1] = "noCriticalsNever=" .. tostring(r == 0)

local p, w = player(5), gun(false)
p.gunInHand = w
local ups = 0
for i = 1, 2000 do
    p.crit, p.speed = false, 1
    fire("OnWeaponSwing", p, w)
    if p.crit then
        ups = ups + 1
        if math.abs(p.speed - 1.1) > 1e-9 then ups = -1e9 end
    elseif p.speed ~= 1 then ups = -1e9 end
end
out[#out + 1] = "speedOnlyWithCrit=" .. tostring(ups > 0)

fire("OnWeaponSwingHitPoint", p, w)
out[#out + 1] = "fieldRaisedForShot=" .. tostring(w.crit == 10)
fire("OnTick")
out[#out + 1] = "fieldBackNextTick=" .. tostring(w.crit == 5)
local nw = gun(true)
p.gunInHand = nw
fire("OnWeaponSwingHitPoint", p, nw)
out[#out + 1] = "noCriticalsFieldKept=" .. tostring(nw.crit == 5)
fire("OnTick")
local np, pw = player(0), gun(false)
np.gunInHand = pw
fire("OnWeaponSwingHitPoint", np, pw)
out[#out + 1] = "nonMasterFieldKept=" .. tostring(pw.crit == 5)
fire("OnTick")

return table.concat(out, "\n")
''')

print(result)
bad = [line for line in result.split('\n') if line.endswith('=false')]
if bad:
    print('FAILED:', bad)
    sys.exit(1)
print('OK')
