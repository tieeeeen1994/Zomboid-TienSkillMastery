"""Runs the real Distraction file on a mocked server: what counts as throwable (tags, weight, display category,
weapons / clothing / bags / books refused), only from the hand and only for a master, the server's checks (item ID,
15-tile cap), the arc (lands at the aim, stopped by a wall, clears a low fence only while high), and the landing:
glass breaks into broken glass with no item left, cans, metal and stone land as items, each makes its noise (no
source) and its sound.

Breaks: nomaterial (scrap tag without the Material category accepted), nocap (range not capped), noglass (glass lands
as an item)."""
import sys
from pathlib import Path

here = Path(__file__).resolve().parent
repo = here.parent
sys.path.insert(0, str(here / '.lupa'))
import lupa

src = (repo / 'Contents/mods/TienSkillMastery/42/media/lua/shared/TienSkillMastery_Distraction.lua') \
    .read_bytes().decode('utf-8').replace('\r\n', '\n')

m = sys.argv[1] if len(sys.argv) > 1 else ''
if m == 'nomaterial':
    src = src.replace('if ok and cat == "Material" then return "metal" end', 'return "metal"')
if m == 'nocap':
    src = src.replace('if d > D.RANGE then tx, ty = fromX + dx / d * D.RANGE, fromY + dy / d * D.RANGE end', '')
if m == 'noglass':
    src = src.replace('    if g.breaks then\n        square:addBrokenGlass()\n    else', '    if false then\n    else')

lua = lupa.LuaRuntime()
lua.globals().source = src
result = lua.execute(r'''
local out = {}
local now = 1000
function require() end
function isServer() return true end
function isClient() return false end
function getTimestampMs() return now end
function instanceof(o, c)
    if c == "InventoryItem" then return o.isItem == true end
    return o.class == c
end
ISBaseTimedAction = { derive = function() return {} end }

-- Squares on one row (y = 0): walls[x] = wall on the east edge of x, fences[x] = low fence there.
local walls, fences, glassAt, worldItems, noises, sent = {}, {}, {}, {}, {}, {}
local squares = {}
local function square(x)
    if squares[x] then return squares[x] end
    local s = { x = x }
    function s.getX() return x end
    function s.getY() return 0 end
    function s.getZ() return 0 end
    function s.isOutside() return true end
    function s.addBrokenGlass() glassAt[#glassAt + 1] = x end
    function s.AddWorldInventoryItem(_, item, ox, oy, h) worldItems[#worldItems + 1] = { item = item, x = x + ox } end
    squares[x] = s
    return s
end
function getCell() return { getGridSquare = function(_, x, y, z) if y == 0 and x >= 0 and x < 40 then return square(x) end end } end
TienSkillMastery = { MODULE = "TSM", Throw = { HAND_HEIGHT = 0.55,
    blocked = function(a, b, h)
        local lo, hi = math.min(a.x, b.x), math.max(a.x, b.x)
        for x = lo, hi - 1 do
            if walls[x] then return true end
            if fences[x] and h <= 0.4 then return true end
        end
        return false
    end } }
TienSkillMastery.sig = function(p, id) assert(id == "Stealth.SigDistraction"); return p.master == true end
function addSound(source, x, y, z, r, v) noises[#noises + 1] = { source = source, x = x, r = r } end
function sendServerCommand(a, b, c) sent[#sent + 1] = { command = b, args = c } end
function sendRemoveItemFromContainer() end
local clientCommand
Events = { OnTick = { Add = function(f) if not tickFn then tickFn = f end end },
    OnClientCommand = { Add = function(f) clientCommand = f end } }

local function script(opts)
    local tags = opts.tags or {}
    return {
        getActualWeight = function() return opts.weight or 0.2 end,
        getDisplayCategory = function() return opts.cat end,
        getTags = function()
            local i = 0
            return { iterator = function() return {
                hasNext = function() return i < #tags end,
                next = function() i = i + 1; return tags[i] end } end }
        end,
    }
end
local nextId = 1
local function item(fullType, opts)
    opts = opts or {}
    local it = { isItem = true, class = opts.class or "InventoryItem", id = nextId, ft = fullType, sc = script(opts),
        drop = opts.drop, attached = -1 }
    nextId = nextId + 1
    function it.getID() return it.id end
    function it.getFullType() return it.ft end
    function it.getScriptItem() return it.sc end
    function it.getDropSound() return it.drop end
    function it.getAttachedSlot() return it.attached end
    function it.getContainer() return it.container end
    return it
end
local function player(master)
    local p = { master = master, x = 0.5, y = 0.5, z = 0 }
    local inv = { removed = {} }
    function inv.DoRemoveItem(_, it) inv.removed[#inv.removed + 1] = it; it.container = nil end
    p.inv = inv
    function p.isDead() return false end
    function p.getX() return p.x end
    function p.getY() return p.y end
    function p.getZ() return p.z end
    function p.getCurrentSquare() return square(math.floor(p.x)) end
    function p.getPrimaryHandItem() return p.primary end
    function p.getSecondaryHandItem() return p.secondary end
    function p.setPrimaryHandItem(_, v) p.primary = v end
    function p.setSecondaryHandItem(_, v) p.secondary = v end
    return p
end
local function hold(p, it, hand)
    it.container = p.inv
    if hand == "off" then p.secondary = it else p.primary = it end
end

assert(load(source))()
local D = TienSkillMastery.Distraction

-- What can be thrown.
local bottle = item("Base.BeerEmpty", { tags = { "base:glass" }, weight = 0.1 })
local window = item("Base.FrontWindow1", { tags = { "base:glass" }, weight = 3.0 })
local can = item("Base.TinCanEmpty", { tags = { "base:hasmetal", "base:tincan", "base:emptycan" }, weight = 0.2 })
local scrap = item("Base.IronScrap", { tags = { "base:hasmetal" }, cat = "Material", weight = 0.5 })
local tool = item("Base.Calipers", { tags = { "base:hasmetal" }, cat = "Tool", weight = 0.3 })
local stone = item("Base.Stone2", { tags = { "base:stone" }, weight = 1.0, drop = "StoneDrop" })
local brick = item("Base.ClayBrick", { weight = 0.3 })
local knife = item("Base.SmashedBottle", { tags = { "base:glass" }, weight = 1.0, class = "HandWeapon" })
local shirt = item("Base.Tshirt", { tags = { "base:glass" }, class = "Clothing" })
local apple = item("Base.Apple", { weight = 0.2 })
out[#out + 1] = "groups=" .. table.concat({ tostring(D.groupOf(bottle)), tostring(D.groupOf(window)),
    tostring(D.groupOf(can)), tostring(D.groupOf(scrap)), tostring(D.groupOf(tool)), tostring(D.groupOf(stone)),
    tostring(D.groupOf(brick)), tostring(D.groupOf(knife)), tostring(D.groupOf(shirt)), tostring(D.groupOf(apple)) }, ",")

-- Only from the hand, only for a master.
local pl, plain = player(true), player(false)
out[#out + 1] = "notHeld=" .. tostring(D.held(pl) == nil)
hold(pl, bottle, "off")
out[#out + 1] = "offHand=" .. tostring(D.held(pl) == bottle)
hold(plain, can)
out[#out + 1] = "nonMaster=" .. tostring(D.held(plain) == nil)

-- Server checks: wrong ID, non-master.
clientCommand("TSM", "distractThrow", pl, { id = 999, tx = 8.5, ty = 0.5 })
clientCommand("TSM", "distractThrow", plain, { id = can.id, tx = 8.5, ty = 0.5 })
out[#out + 1] = "refused=" .. tostring(#D.inFlight == 0)

-- Glass, open ground, aimed 8 tiles: lands there, breaks, noise 20, its sound.
clientCommand("TSM", "distractThrow", pl, { id = bottle.id, tx = 8.5, ty = 0.5 })
local f = D.inFlight[1]
out[#out + 1] = "glassFlew=" .. tostring(f ~= nil and math.abs(f.x - 8.5) < 0.01 and pl.secondary == nil
    and pl.inv.removed[1] == bottle)
now = now + 5000; tickFn()
out[#out + 1] = "glassBroke=" .. tostring(glassAt[1] == 8 and #worldItems == 0)
out[#out + 1] = "glassNoise=" .. tostring(noises[1] and noises[1].source == nil and noises[1].r == 20 and noises[1].x == 8)
out[#out + 1] = "glassSound=" .. tostring(sent[#sent].command == "distractLand" and sent[#sent].args.sound == "SmashedBottleBreak")

-- A can, a wall after x = 4: stopped there, lands as an item, noise 15, the mod's own can sound.
walls[4] = true
hold(pl, can)
clientCommand("TSM", "distractThrow", pl, { id = can.id, tx = 9.5, ty = 0.5 })
now = now + 5000; tickFn()
local w = worldItems[1]
out[#out + 1] = "wallStops=" .. tostring(w ~= nil and w.item == can and w.x < 5 and w.x > 4)
out[#out + 1] = "can=" .. tostring(noises[2].r == 15 and sent[#sent].args.sound == "TsmDistractionCanLand")
walls[4] = nil

-- A low fence at x = 6: a far throw clears it (high there); a short throw landing beyond it does not.
fences[6] = true
hold(pl, stone)
clientCommand("TSM", "distractThrow", pl, { id = stone.id, tx = 12.5, ty = 0.5 })
now = now + 5000; tickFn()
out[#out + 1] = "fenceCleared=" .. tostring(worldItems[2] and worldItems[2].x > 12)
out[#out + 1] = "stone=" .. tostring(noises[3].r == 10 and sent[#sent].args.sound == "StoneDrop")
hold(pl, brick)
pl.x = 5.5
clientCommand("TSM", "distractThrow", pl, { id = brick.id, tx = 7.5, ty = 0.5 })
now = now + 5000; tickFn()
out[#out + 1] = "lowFenceStops=" .. tostring(worldItems[3] and worldItems[3].x < 7)
fences[6] = nil
pl.x = 0.5

-- Scrap metal: noise 15, the vanilla metal sound.
hold(pl, scrap)
clientCommand("TSM", "distractThrow", pl, { id = scrap.id, tx = 3.5, ty = 0.5 })
now = now + 5000; tickFn()
out[#out + 1] = "metal=" .. tostring(noises[#noises].r == 15 and sent[#sent].args.sound == "BreakMetalItem")

-- 15-tile cap.
local jar = item("Base.EmptyJar", { tags = { "base:glass" }, weight = 0.2 })
hold(pl, jar)
clientCommand("TSM", "distractThrow", pl, { id = jar.id, tx = 35.5, ty = 0.5 })
out[#out + 1] = "capped=" .. tostring(D.inFlight[1] and math.abs(D.inFlight[1].x - 15.5) < 0.05)

return table.concat(out, "\n")
''')

print(result)
lines = result.split('\n')
bad = [l for l in lines if l.endswith('=false')]
if 'groups=glass,nil,can,metal,nil,stone,stone,nil,nil,nil' not in lines:
    bad.append('groups')
if bad:
    print('FAILED:', bad)
    sys.exit(1)
print('OK')
