"""Loads the real TienSkillMastery_Crafting.lua against mocks: the flat bonus on spears from Carving recipes."""
import re
import sys
from pathlib import Path

here = Path(__file__).resolve().parent
repo = here.parent
sys.path.insert(0, str(here / '.lupa'))
import lupa

base = (repo / 'Contents/mods/TienSkillMastery/42/media/lua/shared')
src = (base / 'TienSkillMastery_Crafting.lua').read_bytes().decode('utf-8')
core = (base / 'TienSkillMastery.lua').read_bytes().decode('utf-8')
# The bonus values come from the real definitions, so the check below really is about the shipped numbers.
at10 = {n: float(v) for n, v in re.findall(r'def\("Spearcraft", "(Carved\w+)", ([\d.]+), "pct"\)', core)}
print('definitions:', at10)

mutation = sys.argv[1] if len(sys.argv) > 1 else ''
if mutation == 'anyrecipe':
    src = src.replace('if relevantPerks(recipe).Carving then afterCarvedSpears', 'if true then afterCarvedSpears')
if mutation == 'anyitem':
    src = src.replace('if item and M.weaponMastery(item) == "Spearcraft" then', 'if item then')
if mutation == 'nosend':
    src = src.replace('M.resendItem(item)     -- the item bytes', '-- the item bytes')
if mutation == 'noreach':
    src = src.replace('item:setMaxRange(item:getMaxRange() * reach)', '')
if mutation == 'nomin':
    src = src.replace('item:setMinDamage(item:getMinDamage() * damage)', '')

lua = lupa.LuaRuntime()
lua.globals().crafting_source = src
lua.globals().at_damage = at10['CarvedDamage']
lua.globals().at_reach = at10['CarvedReach']
result = lua.execute(r'''
unpack = table.unpack
local function list(t)
    return { size = function() return #t end, get = function(_, i) return t[i + 1] end }
end
ResourceType = { Item = "item" }
ItemTag = { BREAK_ON_SMITHING = "break" }
Perks = { Electricity = "Electricity" }
Actions = { addOrDropItem = function() end }
function instanceItem() return nil end
function require() end
function sendAddItemToContainer() end
function instanceof(o, class) return o.class == class end
function ZombRandFloat() return 100 end

local STATS = {
    ["Base.SpearCrafted"] = { 1.0, 1.4, 1.4, "Spearcraft" },
    ["Base.SpearCraftedFireHardened"] = { 1.0, 1.5, 1.4, "Spearcraft" },
    ["Mod.GreatSpear"] = { 2.0, 3.0, 2.0, "Spearcraft" },
    ["Base.WoodenSpoon"] = { 0.1, 0.2, 0.5, nil },
}
local function item(fullType)
    local s = STATS[fullType]
    local it = { min = s[1], max = s[2], range = s[3], md = {}, mastery = s[4] }
    function it.getFullType() return fullType end
    function it.getModData() return it.md end
    function it.getMinDamage() return it.min end
    function it.getMaxDamage() return it.max end
    function it.getMaxRange() return it.range end
    function it.setMinDamage(_, v) it.min = v end
    function it.setMaxDamage(_, v) it.max = v end
    function it.setMaxRange(_, v) it.range = v end
    function it.syncItemFields() end
    return it
end

local level, sent = 10, 0
local function value(id)
    if id == "Spearcraft.CarvedDamage" then return at_damage * level / 10 end
    if id == "Spearcraft.CarvedReach" then return at_reach * level / 10 end
    return 0
end
TienSkillMastery = {
    CRAFT_MASTERY = {},
    anyPerkId = function(p) return p end,
    val = function(_, id) return value(id) end,
    valFor = function() return 0 end,
    more = function(_, id) return 1 + value(id) / 100 end,   -- as the real M.more
    roll = function() return false end,
    int = function() return 0 end,
    scaleInt = function(_, _, n) return n end,
    sig = function() return false end,
    markChance = function() return 0 end,
    hasMark = function() return false end,
    stretchFood = function() return false end,
    butcherBonus = function() return false end,
    resendItem = function() sent = sent + 1 end,
    weaponMastery = function(w) return w.mastery end,
}
ISHandcraftAction = { getDuration = function() return 100 end, performRecipe = function() end }
assert(load(crafting_source))()

local function craft(name, perks, created)
    local entries = {}
    for _, p in ipairs(perks) do entries[#entries + 1] = { getPerk = function() return p end } end
    local recipe = {
        getName = function() return "Base." .. name end, getTags = function() return list({}) end,
        getCategory = function() return "Weaponry" end, isSmithing = function() return false end,
        getInputs = function() return list({}) end, getRequiredSkillCount = function() return 0 end,
        getXPAwardCount = function() return #entries end, getXPAward = function(_, i) return entries[i + 1] end,
        getAutoLearnAnySkillCount = function() return 0 end, getAutoLearnAllSkillCount = function() return 0 end,
        involvesSkill = function() return false end,
    }
    local data = {
        getAllCreatedItems = function() return list(created) end,
        getAllKeepInputItems = function() return list({}) end,
        getAllConsumedItems = function() return list({}) end,
    }
    local chr = {
        isTimedActionInstant = function() return false end,
        getDisplayName = function() return "Tester" end,
        getInventory = function() return { getItems = function() return list({}) end } end,
    }
    ISHandcraftAction.performRecipe({ character = chr, craftRecipe = recipe,
        logic = { getRecipeData = function() return data end, getContainers = function() return nil end } })
end

local out = {}
local function case(label, recipe, perks, fullType, lvl)
    level, sent = lvl, 0
    local it = item(fullType)
    craft(recipe, perks, { it })
    out[#out + 1] = string.format("%s=%.4f/%.4f/%.4f/%d", label, it.min, it.max, it.range, sent)
end
local C = { "Carving" }
case("carved0", "CarveSpear", C, "Base.SpearCrafted", 0)
case("carved5", "CarveSpear", C, "Base.SpearCrafted", 5)
case("carved10", "CarveSpear", C, "Base.SpearCrafted", 10)
case("fire5", "FireHardenSpear", C, "Base.SpearCraftedFireHardened", 5)
case("fire10", "FireHardenSpear", C, "Base.SpearCraftedFireHardened", 10)
case("bound", "BindSpear", { "Maintenance" }, "Base.SpearCrafted", 10)
case("spoon", "CarveWoodenSpoon", C, "Base.WoodenSpoon", 10)
case("modSpear", "CarveGreatSpear", C, "Mod.GreatSpear", 10)
return table.concat(out, " ")
''')
print(result.replace(' ', '\n'))
want = {
    # min / max / reach / item re-sent
    'carved0': '1.0000/1.4000/1.4000/0',
    'carved5': '1.0400/1.4560/1.4210/1',
    'carved10': '1.0800/1.5120/1.4420/1',
    'fire5': '1.0400/1.5600/1.4210/1',
    'fire10': '1.0800/1.6200/1.4420/1',
    'bound': '1.0000/1.4000/1.4000/0',
    'spoon': '0.1000/0.2000/0.5000/0',
    'modSpear': '2.1600/3.2400/2.0600/1',
}
got = dict(p.split('=') for p in result.split())
bad = {k: (got.get(k), v) for k, v in want.items() if got.get(k) != v}

# The user's rule: near forged at mastery 10, never past it, on average damage and on reach.
def nums(k):
    return [float(x) for x in got[k].split('/')[:3]]
forged = {'carved10': (1.0, 1.6, 1.45), 'fire10': (1.2, 1.7, 1.48)}
for k, (fmin, fmax, freach) in forged.items():
    mn, mx, r = nums(k)
    avg, favg = (mn + mx) / 2, (fmin + fmax) / 2
    print(f'{k}: average {avg:.3f} vs forged {favg:.3f} ({avg / favg:.1%}), reach {r:.3f} vs {freach} ({r / freach:.1%})')
    if avg > favg or r > freach:
        bad[k + ' past forged'] = (f'{avg:.3f}/{r:.3f}', f'{favg:.3f}/{freach}')

print('FAILED' if bad else 'all %d checks passed' % (len(want) + len(forged)))
for k, v in bad.items():
    print('  ', k, 'got', v[0], 'want', v[1])
sys.exit(1 if bad else 0)
