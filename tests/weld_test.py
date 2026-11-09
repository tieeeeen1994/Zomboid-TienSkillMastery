"""Loads the real TienSkillMastery_Crafting.lua against mocks and runs ISHandcraftAction:performRecipe."""
import sys
from pathlib import Path

here = Path(__file__).resolve().parent
repo = here.parent
sys.path.insert(0, str(here / '.lupa'))
import lupa

path = (repo / 'Contents/mods/TienSkillMastery/42/media/lua/shared/TienSkillMastery_Crafting.lua')
src = path.read_bytes().decode('utf-8')
# Optional mutation from the command line: drop a piece of the fix to prove the checks notice.
if len(sys.argv) > 1 and sys.argv[1] == 'nogear':
    src = src.replace('"masterwork", "head", true)', '"masterwork", "head")')
if len(sys.argv) > 1 and sys.argv[1] == 'nocategory':
    src = src.replace(' or recipe:getCategory() == "Metalworking"', '')
if len(sys.argv) > 1 and sys.argv[1] == 'nowelding':
    src = src.replace(' or listsWelding(recipe)) then', ') then').replace('elseif listsWelding(recipe) then', 'elseif false then')

lua = lupa.LuaRuntime()
lua.globals().crafting_source = src

result = lua.execute(r'''
unpack = table.unpack
pack = table.pack or function(...) return { n = select("#", ...), ... } end

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
function ZombRandFloat() return 0 end   -- every roll that can succeed does

local master = true
TienSkillMastery = {
    CRAFT_MASTERY = { Blacksmith = "Smithing", MetalWelding = "Smithing" },
    anyPerkId = function(p) return p end,
    val = function(_, id)
        if not master then return 0 end
        if id == "Smithing.ToolWear" then return 20 end
        if id == "Smithing.SigMasterwork" then return 15 end
        return 0
    end,
    valFor = function() return 0 end,
    more = function() return 1 end,
    roll = function() return false end,
    scaleInt = function(_, _, n) return n end,
    sig = function() return false end,
    markChance = function() return 0 end,
    hasMark = function() return false end,
    stretchFood = function() return false end,
    butcherBonus = function() return false end,
    resendItem = function() end,
}

local kept, created        -- the craft in progress
ISHandcraftAction = {
    getDuration = function() return 100 end,
    performRecipe = function()
        kept:setCondition(kept:getCondition() - 1)    -- vanilla wears the tool during the craft
    end,
}

assert(load(crafting_source))()

local function item(fullType, class)
    local it = { class = class, md = {}, condition = 10 }
    function it.getFullType() return fullType end
    function it.getID() return fullType end
    function it.getModData() return it.md end
    function it.getCondition() return it.condition end
    function it.setCondition(_, c) it.condition = c end
    function it.setConditionNoSound(_, c) it.condition = c end
    function it.hasHeadCondition() return false end
    function it.hasSharpness() return false end
    function it.hasTag() return false end
    function it.syncItemFields() end
    function it.getContainer() return true end
    return it
end

local function run(def)
    kept = item("Base.Saw", "Item")
    created = {}
    for _, o in ipairs(def.outputs) do created[#created + 1] = item(o[1], o[2]) end
    local perks = def.perks or {}
    local entries = {}
    for _, p in ipairs(perks) do entries[#entries + 1] = { getPerk = function() return p end } end
    local input = {
        getResourceType = function() return "item" end,
        isKeep = function() return true end,
        mayDegrade = function() return true end,
        mayDegradeHeavy = function() return false end,
        mayDegradeLight = function() return false end,
        mayDegradeVeryLight = function() return false end,
        sharpnessCheck = function() return false end,
        isAcceptsAnyItem = function() return true end,
    }
    local recipe = {
        getName = function() return "Base." .. def.name end,
        getTags = function() return list({}) end,
        getCategory = function() return def.cat end,
        isSmithing = function() return def.smith == true end,
        getInputs = function() return list({ input }) end,
        getRequiredSkillCount = function() return 0 end,
        getXPAwardCount = function() return #entries end,
        getXPAward = function(_, i) return entries[i + 1] end,
        getAutoLearnAnySkillCount = function() return 0 end,
        getAutoLearnAllSkillCount = function() return 0 end,
        involvesSkill = function() return false end,
    }
    local data = {
        getAllCreatedItems = function() return list(created) end,
        getAllKeepInputItems = function() return list({ kept }) end,
        getAllConsumedItems = function() return list({}) end,
    }
    local chr = {
        isTimedActionInstant = function() return false end,
        isEquipped = function() return false end,
        getDisplayName = function() return "Tester" end,
        getInventory = function() return { getItems = function() return list({ kept }) end } end,
    }
    local self = { character = chr, craftRecipe = recipe,
        logic = { getRecipeData = function() return data end, getContainers = function() return nil end } }
    ISHandcraftAction.performRecipe(self)
    local marks = {}
    for _, it in ipairs(created) do
        marks[#marks + 1] = it.getFullType() .. "=" .. tostring(it.md.TSM_Mark or 0)
    end
    return def.name .. "|" .. tostring(kept:getCondition()) .. "|" .. table.concat(marks, ",")
end

local out = {}
local cases = {
    { name = "Forge", cat = "Blacksmithing", smith = true, outputs = { { "Base.Blade", "Item" } } },
    { name = "SawBar", cat = "Metalworking", outputs = { { "Base.BarHalf", "Item" } } },
    { name = "MakeMetalSheet", cat = "Metalworking", perks = { "MetalWelding" }, outputs = { { "Base.SheetMetal", "Item" } } },
    { name = "Make_Scrap_Sword", cat = "Weaponry", perks = { "MetalWelding" }, outputs = { { "Base.Sword_Scrap", "HandWeapon" } } },
    { name = "Make_Scrap_Shortsword", cat = "Weaponry", perks = { "MetalWelding" },
      outputs = { { "Base.ShortSword_Scrap", "HandWeapon" }, { "Base.IronBarQuarter", "Item" } } },
    { name = "MakeScrapMetalHelmet", cat = "Metalworking", perks = { "MetalWelding" }, outputs = { { "Base.Helmet", "Clothing" } } },
    { name = "CarveSpoon", cat = "Carving", perks = { "Carving" }, outputs = { { "Base.Spoon", "Item" } } },
}
for _, c in ipairs(cases) do out[#out + 1] = run(c) end
master = false
out[#out + 1] = "NoMaster_" .. run({ name = "Make_Scrap_Sword", cat = "Weaponry", perks = { "MetalWelding" },
    outputs = { { "Base.Sword_Scrap", "HandWeapon" } } })
return table.concat(out, "\n")
''')
print(result)

# condition 10 = the wear was undone (the roll always succeeds), 9 = no undo was tried.
want = [
    'Forge|10|Base.Blade=15.0',
    'SawBar|10|Base.BarHalf=0',
    'MakeMetalSheet|10|Base.SheetMetal=0',
    'Make_Scrap_Sword|10|Base.Sword_Scrap=15.0',
    'Make_Scrap_Shortsword|10|Base.ShortSword_Scrap=15.0,Base.IronBarQuarter=0',
    'MakeScrapMetalHelmet|10|Base.Helmet=15.0',
    'CarveSpoon|9|Base.Spoon=0',
    'NoMaster_Make_Scrap_Sword|9|Base.Sword_Scrap=0',
]
got = [l.replace('=15|', '=15.0|') for l in result.splitlines()]
got = [l if not l.endswith('=15') else l + '.0' for l in got]
got = [l.replace('=15,', '=15.0,') for l in got]
bad = [(w, g) for w, g in zip(want, got) if w != g]
print('FAILED' if bad or len(want) != len(got) else 'all %d checks passed' % len(want))
for w, g in bad:
    print('  want', w, '\n  got ', g)
sys.exit(1 if bad else 0)
