"""Runs the real butchering section of TienSkillMastery_FarmAnimals.lua against a port of vanilla's addAnimalPart."""
import sys
from pathlib import Path

here = Path(__file__).resolve().parent
repo = here.parent
sys.path.insert(0, str(here / '.lupa'))
import lupa

path = (repo / 'Contents/mods/TienSkillMastery/42/media/lua/server/TienSkillMastery_FarmAnimals.lua')
text = path.read_bytes().decode('utf-8')
start = text.index('if not ButcheringUtil or not ButcheringUtil.addAnimalPart')
end = text.index('-- Provisioning.LastingFood (phase 2) and the choice cuts')
section = text[start:end]

lua = lupa.LuaRuntime()
g = lua.globals()
g.section_source = section

result = lua.execute(r'''
unpack = table.unpack
local given = {}
local inv = { n = 0 }
local items = { size = function() return inv.n end }
local player = { getInventory = function() return { getItems = function() return items end } end }

AnimalPartsDefinitions = { meat = { ["Base.Beef"] = {} } }

-- Port of the parts of vanilla's addAnimalPart this wrapper depends on: it writes nb = -1 into the shared definition,
-- and rolls a range when nb is -1 (a fixed 5 here, so counts are exact).
local function vanillaPart(part, p, carcass)
    if not part.nb then part.nb = -1 end
    local nb = part.nb
    if nb == -1 then nb = 5 end
    if AnimalPartsDefinitions.meat[part.item] then
        return ButcheringUtil.giveMeatModified({}, nb, p)
    end
    for _ = 1, nb do
        inv.n = inv.n + 1
        given[part.item] = (given[part.item] or 0) + 1
    end
    return ""
end

ButcheringUtil = {
    addAnimalPart = vanillaPart,
    getPartChance = function() return 50 end,
    giveMeatModified = function(def, nb, p)
        given.meatCalls = (given.meatCalls or 0) + 1
        given.meat = (given.meat or 0) + nb
        inv.n = inv.n + nb
        return ""
    end,
}

-- The bonus is forced to its largest effect: always one more than asked, so a leak can never hide behind a roll.
local partCount = 10
M = {
    val = function(_, id) if id == "Hunting.PartCount" then return partCount end return 0 end,
    more = function() return 1 end,
    scaleInt = function(_, _, n) return n + 1 end,
}

assert(load(section_source))()

local out = {}
local function run(label, part)
    given = {}
    inv.n = 0
    ButcheringUtil.addAnimalPart(part, player, {})
    local total = (given[part.item] or 0) + (given.meat or 0)
    out[#out + 1] = label .. "=" .. total
end

-- Shared definitions, as vanilla keeps them, each butchered twice: the second run sees vanilla's nb = -1.
local foot = { item = "Base.ChickenFoot", nb = 2 }
local whole = { item = "Base.ChickenWhole", nb = 1 }
local bone = { item = "Base.SmallAnimalBone", minNb = 4, maxNb = 6 }
local sinew = { item = "Base.AnimalSinew", minNb = 3, maxNb = 5 }
local beef = { item = "Base.Beef", minNb = 10, maxNb = 18 }

run("foot1", foot)    run("foot2", foot)
run("whole1", whole)  run("whole2", whole)
run("bone1", bone)    run("bone2", bone)
run("sinew1", sinew)  run("sinew2", sinew)
run("beef1", beef)    run("beef2", beef)

-- Without the mastery a range stays vanilla's.
partCount = 0
run("boneNoMastery", { item = "Base.SmallAnimalBone", minNb = 4, maxNb = 6 })

return table.concat(out, " ")
''')
print(result)

want = {
    'foot1': 2, 'foot2': 2, 'whole1': 1, 'whole2': 1,   # fixed: never an extra
    'bone1': 6, 'bone2': 6, 'sinew1': 6, 'sinew2': 6,   # ranges: 5 + the forced extra, first and later runs alike
    'beef1': 6, 'beef2': 6,                             # meat definition: scaled once
    'boneNoMastery': 5,
}
got = dict(p.split('=') for p in result.split())
bad = {k: (got.get(k), v) for k, v in want.items() if int(got.get(k, -1)) != v}
print('FAILED' if bad else 'all %d checks passed' % len(want), bad or '')
sys.exit(1 if bad else 0)
