"""Loads the real Crafting and CraftingBuild files against mocks: torch fuel on builds, and category tool wear."""
import sys
from pathlib import Path

here = Path(__file__).resolve().parent
repo = here.parent
sys.path.insert(0, str(here / '.lupa'))
import lupa

base = (repo / 'Contents/mods/TienSkillMastery/42/media/lua')
crafting = (base / 'shared/TienSkillMastery_Crafting.lua').read_bytes().decode('utf-8')
build = (base / 'server/TienSkillMastery_CraftingBuild.lua').read_bytes().decode('utf-8')
mutation = sys.argv[1] if len(sys.argv) > 1 else ''
if mutation == 'nocategory':
    crafting = crafting.replace('if categoryPerk and M.CRAFT_MASTERY[categoryPerk] == "Handicraft" then return "Handicraft.ToolWear" end', '')
if mutation == 'noreturn':
    build = build.replace('pcall(M.returnTorchFuel, chr, torches)', 'true, nil')
if mutation == 'swallow':
    build = build.replace('if not ok then error((...), 0) end\n        return ...', 'return ...').replace('if not ok then error((...), 0) end\r\n        return ...', 'return ...')
if mutation == 'nowrap':
    build = build.replace('function ISBuildIsoEntity:create(...)', 'function ISBuildIsoEntity.unused(self, ...)')

lua = lupa.LuaRuntime()
lua.globals().crafting_source = crafting
lua.globals().build_source = build

result = lua.execute(r'''
unpack = table.unpack
local function list(t)
    return { size = function() return #t end, get = function(_, i) return t[i + 1] end }
end

ResourceType = { Item = "item" }
ItemTag = { BREAK_ON_SMITHING = "break" }
Perks = { Electricity = "Electricity", Woodwork = "Woodwork", Masonry = "Masonry" }
Actions = { addOrDropItem = function() end }
function instanceItem() return nil end
function require() end
function sendAddItemToContainer() end
function instanceof(o, class) return o.class == class end
function ZombRandFloat() return 0 end
function isClient() return false end
function isServer() return true end
function getSpecificPlayer() return nil end

local rolled = 0
local rollResult = true
local torchMaster, wearMaster = true, true
TienSkillMastery = {
    CRAFT_MASTERY = { Blacksmith = "Smithing", MetalWelding = "Smithing", Glassmaking = "Handicraft", Pottery = "Handicraft" },
    anyPerkId = function(p) return p end,
    val = function(_, id)
        if id == "Smithing.TorchFuel" then return torchMaster and 20 or 0 end
        if id == "Handicraft.ToolWear" then return wearMaster and 20 or 0 end
        if id == "Handicraft.SigCraftsmanship" then return wearMaster and 15 or 0 end
        return 0
    end,
    valFor = function() return 0 end,
    more = function() return 1 end,
    roll = function(_, id)
        if id == "Smithing.TorchFuel" then rolled = rolled + 1 return rollResult end
        return false
    end,
    scaleInt = function(_, _, n) return n end,
    sig = function() return false end,
    markChance = function() return 0 end,
    hasMark = function() return false end,
    stretchFood = function() return false end,
    butcherBonus = function() return false end,
    resendItem = function() end,
}

local kept
ISHandcraftAction = {
    getDuration = function() return 100 end,
    performRecipe = function() kept:setCondition(kept:getCondition() - 1) end,
}
assert(load(crafting_source))()

-- A stand-in for vanilla's create: burns `burn` uses unless the cheat is on, returns what it was told to.
local cheat, burn, returns, throws = false, 4, nil, false
local torch
ISBuildingObject = { updateModData = function() end }
buildUtil = {}
ISBuildIsoEntity = {
    create = function(self, x)
        if not cheat then torch.uses = torch.uses - burn end
        if throws then error("vanilla failed") end      -- after burning: the fuel must still come back
        return returns
    end,
}
assert(load(build_source))()

local function newTorch(uses)
    local t = { class = "DrainableComboItem", uses = uses, synced = 0 }
    function t.getID() return "torch" end
    function t.getCurrentUses() return t.uses end
    function t.setCurrentUses(_, n) t.uses = n end
    function t.getContainer() return true end
    function t.syncItemFields() t.synced = t.synced + 1 end
    return t
end

local function chrWith(t)
    local inv = {
        getAllTypeRecurse = function() return list({ t }) end,
        getItems = function() return list({}) end,
    }
    return {
        getInventory = function() return inv end,
        isBuildCheat = function() return cheat end,
    }
end

local out = {}
local function build(label, setup)
    torch = newTorch(100)
    rolled = 0
    rollResult, torchMaster, cheat, burn, returns, throws = true, true, false, 4, nil, false
    if setup then setup() end
    local self = setmetatable({ character = chrWith(torch),
        buildPanelLogic = { getContainers = function() return nil end } }, { __index = ISBuildIsoEntity })
    local ok, r = pcall(self.create, self, 1, 2, 3)
    out[#out + 1] = label .. "=" .. torch.uses .. "/" .. rolled .. "/" .. tostring(ok) .. "/"
        .. (ok and (r == nil or r == false) and tostring(r) or (ok and "swallowed" or "error"))
end

build("allBack")                                                          -- 100 - 4, every roll won
build("noneBack", function() rollResult = false end)
build("notMaster", function() torchMaster = false end)
build("cheat", function() cheat = true end)
build("noBurn", function() burn = 0 end)
build("failedBuild", function() burn = 0; returns = false end)
build("vanillaError", function() throws = true end)

-- Handicraft tool wear by category, with no mark.
local function craft(def)
    local it = { md = {}, condition = 10 }
    function it.getFullType() return "Base.Tool" end
    function it.getID() return "tool" end
    function it.getModData() return it.md end
    function it.getCondition() return it.condition end
    function it.setCondition(_, c) it.condition = c end
    function it.setConditionNoSound(_, c) it.condition = c end
    function it.hasHeadCondition() return false end
    function it.hasSharpness() return false end
    function it.hasTag() return false end
    function it.syncItemFields() end
    kept = it
    local made = { getFullType = function() return "Base.Made" end, md = {} }
    function made.getModData() return made.md end
    function made.syncItemFields() end
    local input = {
        getResourceType = function() return "item" end, isKeep = function() return true end,
        mayDegrade = function() return true end, mayDegradeHeavy = function() return false end,
        mayDegradeLight = function() return false end, mayDegradeVeryLight = function() return false end,
        sharpnessCheck = function() return false end, isAcceptsAnyItem = function() return true end,
    }
    local entries = {}
    for _, p in ipairs(def.perks or {}) do entries[#entries + 1] = { getPerk = function() return p end } end
    local recipe = {
        getName = function() return "Base." .. def.name end, getTags = function() return list({}) end,
        getCategory = function() return def.cat end, isSmithing = function() return false end,
        getInputs = function() return list({ input }) end, getRequiredSkillCount = function() return 0 end,
        getXPAwardCount = function() return #entries end, getXPAward = function(_, i) return entries[i + 1] end,
        getAutoLearnAnySkillCount = function() return 0 end, getAutoLearnAllSkillCount = function() return 0 end,
        involvesSkill = function() return false end,
    }
    local data = {
        getAllCreatedItems = function() return list({ made }) end,
        getAllKeepInputItems = function() return list({ it }) end,
        getAllConsumedItems = function() return list({}) end,
    }
    local chr = {
        isTimedActionInstant = function() return false end, isEquipped = function() return false end,
        getDisplayName = function() return "Tester" end,
        getInventory = function() return { getItems = function() return list({ it }) end,
            getAllTypeRecurse = function() return list({}) end } end,
    }
    ISHandcraftAction.performRecipe({ character = chr, craftRecipe = recipe,
        logic = { getRecipeData = function() return data end, getContainers = function() return nil end } })
    out[#out + 1] = def.name .. "=" .. it.condition .. "/" .. tostring(made.md.TSM_Mark or 0)
end

wearMaster = true
torchMaster = false
craft({ name = "MeltSand", cat = "Glassmaking" })
craft({ name = "MakeBrickMold", cat = "Pottery" })
craft({ name = "SomethingListed", cat = "Pottery", perks = { "Pottery" } })
craft({ name = "OpenCan", cat = "Cooking" })
wearMaster = false
craft({ name = "NoMaster", cat = "Glassmaking" })

return table.concat(out, " ")
''')
print(result.replace(' ', '\n'))

want = {
    # torch uses / rolls / create ok / what create returned
    'allBack': '100/4/true/nil',
    'noneBack': '96/4/true/nil',
    'notMaster': '96/0/true/nil',
    'cheat': '100/0/true/nil',
    'noBurn': '100/0/true/nil',
    'failedBuild': '100/0/true/false',      # vanilla's `return false` still reaches the caller
    # tool condition / mark on the output (10 = wear undone, 15 = marked)
    'MeltSand': '10/0',
    'MakeBrickMold': '10/0',
    'OpenCan': '9/0',
    'NoMaster': '9/0',
}
got = dict(p.split('=', 1) for p in result.split())
bad = {k: (got.get(k), v) for k, v in want.items() if got.get(k) != v}
if got['vanillaError'] != '100/4/false/error':
    bad['vanillaError'] = (got['vanillaError'], 'fuel returned and error passed on')
if not (got['SomethingListed'].startswith('10/15')):
    bad['SomethingListed'] = (got['SomethingListed'], 'wear undone and marked')
print('FAILED' if bad else 'all %d checks passed' % (len(want) + 2))
for k, v in bad.items():
    print('  ', k, 'got', v[0], 'want', v[1])
sys.exit(1 if bad else 0)
