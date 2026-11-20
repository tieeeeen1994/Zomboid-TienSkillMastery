"""Runs the real Skills tab registry against a mock player: the "1 in N" lines (wall climbing, bumping into someone,
weapon wear) printed as what the shown level changes in percent and the chance now, the chance lines in percent.

Breaks: nobase (the change is measured against the current level instead of level 0), noweapon (wear shown without a
melee weapon in hand)."""
import sys
from pathlib import Path

here = Path(__file__).resolve().parent
repo = here.parent
sys.path.insert(0, str(here / '.lupa'))
import lupa

shared = repo / 'Contents/mods/TienSkillMastery/42/media/lua/shared'
core = (shared / 'TienSkillMastery_SkillEffects.lua').read_bytes().decode('utf-8').replace('\r\n', '\n')
body = (shared / 'TienSkillMastery_SkillEffectsBody.lua').read_bytes().decode('utf-8').replace('\r\n', '\n')

m = sys.argv[1] if len(sys.argv) > 1 else ''
if m == 'nobase':
    body = body.replace('return now - at(0), now', 'return now - at(L), now')
if m == 'noweapon':
    body = body.replace('if w and instanceof(w, "HandWeapon") and not w:isRanged() then return w end',
                        'if true then return { getConditionLowerChance = function() return 10 end } end')

lua = lupa.LuaRuntime()
lua.globals().core = core
lua.globals().body = body
result = lua.execute(r'''
function require() end
TienSkillMastery = {}
function getText(k, a) if k == "IGUI_TienSkillMastery_EffectNow" then return "now " .. a end return k end
function instanceof(o, c) return type(o) == "table" and o.cls == c end
Perks = { Fitness = "Fitness", Strength = "Strength", Nimble = "Nimble", Maintenance = "Maintenance" }
MoodleType = { HEAVY_LOAD = "HEAVY_LOAD", DRUNK = "DRUNK" }
BodyPartType = { Torso_Lower = "TL" }
CharacterTrait = { CLUMSY = "CLUMSY", GRACEFUL = "GRACEFUL", VERY_UNDERWEIGHT = "VU", OBESE = "OB",
    UNDERWEIGHT = "U", OVERWEIGHT = "OW" }
assert(load(core))()
assert(load(body))()
local M = TienSkillMastery

local lv = { Fitness = 5, Strength = 5, Nimble = 5, Maintenance = 4 }
local traits, moodles, pain = {}, {}, 0
local weapon = { cls = "HandWeapon", isRanged = function() return false end,
    getConditionLowerChance = function() return 10 end }
local p = {
    getPerkLevel = function(_, k) return lv[k] or 0 end,
    getClimbingFailChanceFloat = function() return 2 * (lv.Fitness + lv.Strength + lv.Nimble) end,
    getMoodles = function() return { getMoodleLevel = function(_, x) return moodles[x] or 0 end } end,
    hasTrait = function(_, t) return traits[t] == true end,
    getBodyDamage = function() return { getBodyPart = function() return { getAdditionalPain = function() return pain end } end } end,
    getPrimaryHandItem = function() return weapon end,
    getWeaponLevel = function() return 6 end,
}
local function find(perk, name)
    for _, e in ipairs(M.SkillEffects[perk]) do if e.name == name then return e end end
end
local function shown(perk, name) return M.formatEffect(find(perk, name), lv[perk] or 6, p) end
local out = {}
local function check(k, got, want) out[#out + 1] = k .. "=" .. tostring(got == want) .. (got == want and "" or " (" .. tostring(got) .. ")") end

-- Climbing: N = 30 now (3.33%), 20 at Fitness 0 (5%): -1.67%.
check("climbFitness", shown("Fitness", "Climbing"), "-1.67% (now 3.33%)")
check("climbNimble", shown("Nimble", "Climbing"), "-1.67% (now 3.33%)")
-- Bump, second in a row: N = 7 + 5 + 5 = 17 (5.88%), at Strength 0: 12 (8.33%).
check("bumpStrength", shown("Strength", "Bump"), "-2.45% (now 5.88%)")
traits.CLUMSY = true
check("bumpClumsy", shown("Fitness", "Bump"), "-5.95% (now 8.33%)")   -- 12 vs 7
traits.CLUMSY = nil
pain = 60                                                              -- -2 to N
check("bumpPain", shown("Fitness", "Bump"), "-3.33% (now 6.67%)")      -- 15 vs 10
pain = 0
-- Wear: Axe 6 in hand: N = 10 + 4 + 3 = 17 (5.88%); Axe 0: 14 (7.14%). Maintenance 4 vs 0: 17 vs 13 (7.69%).
lv.Axe = 6
check("wearAxe", shown("Axe", "Wear"), "-1.26% (now 5.88%)")
check("wearMaintenance", shown("Maintenance", "Wear"), "-1.81% (now 5.88%)")
-- Heavy load with N <= 0: always fails, at every level.
lv.Fitness, lv.Strength, lv.Nimble = 0, 0, 0
moodles.HEAVY_LOAD = 1
check("climbHeavyZero", shown("Fitness", "Climbing"), "0% (now 100%)")
moodles.HEAVY_LOAD = nil
SandboxVars = { EasyClimbing = true }
check("easyClimbing", shown("Fitness", "Climbing"), "0% (now 0%)")
SandboxVars = nil
weapon = nil
check("wearHiddenEmptyHand", shown("Maintenance", "Wear"), nil)
-- Chance lines carry their %.
lv.Fitness = 5
check("fendOffPercent", shown("Fitness", "FendOff"), "+10%")
return table.concat(out, "\n")
''')
print(result)
bad = [l for l in result.split('\n') if '=false' in l]
if bad:
    print('FAILED:', bad)
    sys.exit(1)
print('OK')
