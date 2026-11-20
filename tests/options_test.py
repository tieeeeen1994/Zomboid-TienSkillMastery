"""Sandbox options for every mastery value (user, 2026-11-20): runs the real shared core, checks that
media/sandbox-options.txt has exactly one option per effect (name, type, default) and that the effect values follow
`SandboxVars.TienSkillMastery`: passives scaled by level, signature amounts, on / off signatures, step levels and
values, 0 = off, the defaults while the options are unknown.

Also the mastery costs (MasteryCostBase / MasteryCostGrowth) and each skill's contribution to each mastery
(`<Mastery>_Skill_<perk>`), both added the same day.

Deliberate breaks (each must print FAILED): nosandbox (amounts ignore the options), noflag (on / off signatures
ignore theirs), nocost (the cost ignores its base option), nocontribution (contributions ignore theirs), stale (an
option the script no longer writes left in the file), norefresh (the single player sandbox window no longer rebuilds
SandboxVars).
"""
import re
import sys
from pathlib import Path

here = Path(__file__).resolve().parent
repo = here.parent
sys.path.insert(0, str(here / '.lupa'))
import lupa

media = repo / 'Contents/mods/TienSkillMastery/42/media'
core = (media / 'lua/shared/TienSkillMastery.lua').read_bytes().decode('utf-8').replace('\r\n', '\n')
options = (media / 'sandbox-options.txt').read_bytes().decode('utf-8').replace('\r\n', '\n')
original = core

brk = sys.argv[1] if len(sys.argv) > 1 else None
if brk == 'nosandbox':
    core = core.replace('    local v = tonumber(sandboxValue(d.opt))\n', '    local v = nil\n')
elif brk == 'noflag':
    core = core.replace('        if sandboxValue(d.opt) == false then return false end\n', '')
elif brk == 'nocost':
    core = core.replace('    local base = vars and tonumber(vars.MasteryCostBase) or M.COST_BASE\n',
                        '    local base = M.COST_BASE\n')
elif brk == 'nocontribution':
    core = core.replace('    local v = vars and tonumber(vars[M.contributionKey(masteryId, perk)])\n', '    local v = nil\n')
elif brk == 'stale':
    options += '\noption TienSkillMastery.Firearms_Gone\n{\n    type = double,\n    default = 1,\n}\n'
if brk in ('nosandbox', 'noflag', 'nocost', 'nocontribution') and core == original:
    raise SystemExit('break not applied: ' + brk)

# name -> (type, default) from the options file
parsed = {}
for name, body in re.findall(r'option TienSkillMastery\.(\w+)\s*\{(.*?)\}', options, re.S):
    typ = re.search(r'type = (\w+)', body).group(1)
    default = re.search(r'default = ([\w.]+)', body).group(1)
    parsed[name] = (typ, default)

lua = lupa.LuaRuntime()
g = lua.globals()
g.core_source = core
g.py_options = lua.table_from({k: lua.table_from({'type': t, 'default': d}) for k, (t, d) in parsed.items()})

result = lua.execute(r'''
unpack = table.unpack
local dummy
dummy = setmetatable({}, { __index = function() return dummy end, __call = function() return dummy end })
setmetatable(_G, { __index = function(_, k) return dummy end })
isClient = function() return false end
isServer = function() return false end
SandboxVars = nil
assert(load(core_source, "TienSkillMastery.lua"))()
local M = TienSkillMastery

local out = {}
local function check(name, ok, detail)
    out[#out + 1] = name .. " " .. (ok and "ok" or ("BAD: " .. tostring(detail)))
end
local function near(a, b) return math.abs(a - b) < 1e-6 end

-- One option per effect, with the effect's default and the right type; nothing else but the general page.
local expected = { MaxMasteries = { type = "integer", default = "3" },
    MasteryCostBase = { type = "double", default = "100" }, MasteryCostGrowth = { type = "double", default = "5" } }
local function fmt(v)
    if v == math.floor(v) then return string.format("%d", v) end
    return tostring(v)
end
for _, m in ipairs(M.masteries) do
    for _, p in ipairs(m.members) do
        expected[M.contributionKey(m.id, p)] = { type = "double", default = fmt(M.PACE[p] or 1) }
    end
end
for id, d in pairs(M.defs) do
    if M.isFlag(d) then
        expected[d.opt] = { type = "boolean", default = "true" }
    elseif d.kind == "step" then
        for i, s in ipairs(d.steps) do
            expected[d.stepKeys[i][1]] = { type = "integer", default = fmt(s[1]) }
            expected[d.stepKeys[i][2]] = { type = "double", default = fmt(s[2]) }
        end
    else
        expected[d.opt] = { type = "double", default = fmt(d.at10) }
    end
end
local missing, wrong, extra = {}, {}, {}
for name, e in pairs(expected) do
    local o = py_options[name]
    if not o then missing[#missing + 1] = name
    elseif o.type ~= e.type or o.default ~= e.default then
        wrong[#wrong + 1] = name .. " " .. o.type .. "/" .. o.default .. " want " .. e.type .. "/" .. e.default
    end
end
for name in pairs(py_options) do
    if not expected[name] then extra[#extra + 1] = name end
end
check("every effect has its option", #missing == 0, table.concat(missing, ", "))
check("types and defaults match the defs", #wrong == 0, table.concat(wrong, "; "))
check("no option without an effect", #extra == 0, table.concat(extra, ", "))

-- Values: a master at a given mastery level (the picks themselves are covered by parking_test).
local LEVEL = 10
M.level = function() return LEVEL end
M.hasSignature = function() return true end
local P = {}

-- Defaults while the options are unknown (main menu, before the world loads).
check("passive default", near(M.val(P, "Firearms.Damage"), 10), M.val(P, "Firearms.Damage"))
check("signature amount default", near(M.val(P, "Firearms.SigQuickdraw"), 4), M.val(P, "Firearms.SigQuickdraw"))
check("flag signature default on", M.sig(P, "Firearms.SigRunReload"), "off")
check("step default", near(M.val(P, "Freerunning.SafeFall"), 3), M.val(P, "Freerunning.SafeFall"))

SandboxVars = { TienSkillMastery = {
    Firearms_Damage = 20, Firearms_SigQuickdraw = 6, Firearms_SigRunReload = false, Hunting_SigDoubleCatch = 0,
    Freerunning_SafeFall_Step1Level = 2, Freerunning_SafeFall_Step2Level = 4, Freerunning_SafeFall_Step3 = 5,
    Freerunning_SafeFall_Step3Level = 3,   -- out of order: from level 3 step 3 (5 floors), from 4 step 2 (2 floors)
    Conditioning_Endurance = -5,           -- clamped to 0
} }
check("passive at 10 follows the option", near(M.val(P, "Firearms.Damage"), 20), M.val(P, "Firearms.Damage"))
LEVEL = 5
check("passive at 5 is half of it", near(M.val(P, "Firearms.Damage"), 10), M.val(P, "Firearms.Damage"))
check("passive unset keeps its default", near(M.val(P, "Firearms.HitChance"), 2.5), M.val(P, "Firearms.HitChance"))
check("negative clamped to 0", M.val(P, "Conditioning.Endurance") == 0, M.val(P, "Conditioning.Endurance"))
check("signature amount follows the option", near(M.val(P, "Firearms.SigQuickdraw"), 6), M.val(P, "Firearms.SigQuickdraw"))
check("signature at 0 is off", not M.sig(P, "Hunting.SigDoubleCatch") and M.amount("Hunting.SigDoubleCatch") == 0,
    M.val(P, "Hunting.SigDoubleCatch"))
check("flag signature off", not M.sig(P, "Firearms.SigRunReload") and not M.enabled(M.defs["Firearms.SigRunReload"]),
    "still on")
check("passive at 0 is off and unlisted", not M.enabled(M.defs["Conditioning.Endurance"]), "listed")
check("other flag signatures stay on", M.sig(P, "Mending.SigRestore"), "off")
check("amount without a player", near(M.amount("Hunting.SigLiveCatch"), 4), M.amount("Hunting.SigLiveCatch"))
local d = M.defs["Freerunning.SafeFall"]
local function fall(level) return M.valueAt(d, level) end
check("step levels follow the options", fall(1) == 0 and fall(2) == 1 and fall(3) == 5 and fall(4) == 2 and fall(10) == 2,
    table.concat({ fall(1), fall(2), fall(3), fall(4), fall(10) }, " "))
LEVEL = 3
check("step value through M.val", near(M.val(P, "Freerunning.SafeFall"), 5), M.val(P, "Freerunning.SafeFall"))
check("panel's mastery 10 value", near(M.valueAt(M.defs["Firearms.Damage"], M.BONUS_LEVELS), 20),
    M.valueAt(M.defs["Firearms.Damage"], M.BONUS_LEVELS))

-- Mastery costs (MasteryCostBase / MasteryCostGrowth): 105 .. 150 by default, read live (the cache follows them).
SandboxVars = nil
check("cost default", M.costFor(1) == 105 and M.costFor(10) == 150 and near(M.pointsForLevel(10), 1275),
    M.costFor(1) .. " " .. M.costFor(10) .. " " .. M.pointsForLevel(10))
SandboxVars = { TienSkillMastery = { MasteryCostBase = 50, MasteryCostGrowth = 10 } }
check("cost follows the options", near(M.costFor(1), 55) and near(M.costFor(10), 100), M.costFor(1) .. " " .. M.costFor(10))
check("levels follow the cost", M.levelInfo(1275) > 10, M.levelInfo(1275))
SandboxVars.TienSkillMastery.MasteryCostGrowth = 0
check("growth 0 = flat", near(M.costFor(1), 50) and near(M.costFor(30), 50), M.costFor(30))
SandboxVars.TienSkillMastery.MasteryCostBase = -5
check("base clamped to 1%", near(M.costFor(1), 1), M.costFor(1))

-- Contribution of a skill to a mastery: the pace by default, the option otherwise, 0 = nothing.
local Str = { getId = function() return "Strength" end, getXpForLevel = function() return 150000 end }
local Aim = { getId = function() return "Aiming" end, getXpForLevel = function() return 9000 end }
SandboxVars = nil
check("contribution default = pace", M.contribution("Conditioning", Str) == 5 and M.contribution("Firearms", Aim) == 1,
    M.contribution("Conditioning", Str))
check("points at the default", near(M.pointsFor(Str, 150, "Conditioning"), 0.5), M.pointsFor(Str, 150, "Conditioning"))
SandboxVars = { TienSkillMastery = { Conditioning_Skill_Strength = 10, Axemanship_Skill_Strength = 0,
    Firearms_Skill_Aiming = 2 } }
check("contribution per mastery", near(M.pointsFor(Str, 150, "Conditioning"), 1)
    and M.pointsFor(Str, 150, "Axemanship") == 0 and near(M.pointsFor(Str, 150, "Bludgeoning"), 0.5),
    M.pointsFor(Str, 150, "Conditioning") .. " " .. M.pointsFor(Str, 150, "Axemanship"))
check("contribution inverse", near(M.xpForPoints(Aim, M.pointsFor(Aim, 777, "Firearms"), "Firearms"), 777)
    and M.xpForPoints(Str, 5, "Axemanship") == 0, M.xpForPoints(Aim, M.pointsFor(Aim, 777, "Firearms"), "Firearms"))
return table.concat(out, "\n")
''')

# client/TienSkillMastery_SandboxRefresh.lua: the in-game sandbox window rebuilds SandboxVars in single player
# (vanilla only does it through the server's relay), never on a client, and keeps vanilla's own work.
refresh = (media / 'lua/client/TienSkillMastery_SandboxRefresh.lua').read_bytes().decode('utf-8').replace('\r\n', '\n')
if brk == 'norefresh':
    refresh = refresh.replace('pcall(function() getSandboxOptions():toLua() end)', 'true')
lua2 = lupa.LuaRuntime()
lua2.globals().refresh_source = refresh
result2 = lua2.execute(r'''
unpack = table.unpack
local calls, vanilla, client = 0, 0, false
ISServerSandboxOptionsUI = { settingsFromUI = function(self, options) vanilla = vanilla + 1; return "done" end }
getSandboxOptions = function() return { toLua = function() calls = calls + 1 end } end
isClient = function() return client end
assert(load(refresh_source, "TienSkillMastery_SandboxRefresh.lua"))()
local out = {}
local r = ISServerSandboxOptionsUI:settingsFromUI({})
out[#out + 1] = "single player refreshes SandboxVars " .. ((calls == 1 and vanilla == 1 and r == "done") and "ok"
    or ("BAD: " .. calls .. " " .. vanilla .. " " .. tostring(r)))
client = true
ISServerSandboxOptionsUI:settingsFromUI({})
out[#out + 1] = "a client leaves it to the server " .. ((calls == 1 and vanilla == 2) and "ok" or ("BAD: " .. calls))
return table.concat(out, "\n")
''')
result = str(result) + '\n' + str(result2)

print(result)
bad = [l for l in str(result).splitlines() if 'BAD' in l]
n = len(str(result).splitlines())
print(f'{n - len(bad)}/{n} checks ok' if not bad else f'FAILED: {len(bad)} of {n}')
sys.exit(1 if bad else 0)
