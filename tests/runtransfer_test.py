"""Runs the real Signatures file against mocks: Running Reload and the transfer a reload waits for (the magazine or
the rounds out of a bag).

- A master's transfer inside their own inventory is created with stopOnRun off; a non-master's, one to or from
  outside the inventory and another class (Tien's Ammo Bags' own transfer) keep vanilla's stop on running.
- Running with a reload action behind it in the queue: the transfer goes on. With none behind it: stopped, once.
  Walking or standing: left alone.

Breaks: nostop (a transfer no reload waits for is never stopped), anybag (transfers from outside kept too)."""
import sys
from pathlib import Path

here = Path(__file__).resolve().parent
repo = here.parent
sys.path.insert(0, str(here / '.lupa'))
import lupa

src = (repo / 'Contents/mods/TienSkillMastery/42/media/lua/shared/TienSkillMastery_Signatures.lua') \
    .read_bytes().decode('utf-8').replace('\r\n', '\n')

m = sys.argv[1] if len(sys.argv) > 1 else ''
if m == 'nostop':
    src = src.replace('    action:forceStop()\n', '')
if m == 'anybag':
    src = src.replace('self.srcContainer:isInCharacterInventory(self.character)', 'true')

lua = lupa.LuaRuntime()
lua.globals().source = src
result = lua.execute(r'''
local out = {}
function require() end
function isServer() return false end
function isClient() return true end
local update
Events = setmetatable({}, { __index = function(_, name)
    return { Add = function(f) if name == "OnPlayerUpdate" then update = f end end }
end })
TienSkillMastery = { sig = function(p, id) return p.master and id == "Firearms.SigRunReload" end,
    val = function() return 0 end }
local M = TienSkillMastery
ISBaseTimedAction = { create = function(self) self.action = {} end, adjustMaxTime = function(_, t) return t end }
for _, name in ipairs({ "ISReloadWeaponAction", "ISInsertMagazine", "ISEjectMagazine", "ISLoadBulletsInMagazine",
    "ISRackFirearm", "ISUnloadBulletsFromFirearm", "ISUnloadBulletsFromMagazine", "ISEquipWeaponAction",
    "ISUnequipAction" }) do
    _G[name] = { start = function() end, animEvent = function() end }
end
ISTimedActionQueue = { queues = {} }
assert(load(source))()

local function player(master)
    local p = { master = master, running = false, moving = false }
    function p.isRunning() return p.running end
    function p.isSprinting() return false end
    function p.isPlayerMoving() return p.moving end
    return p
end
local function container(own) return { isInCharacterInventory = function() return own end } end
local function action(p, type, src, dest)
    local a = { Type = type, character = p, srcContainer = src, destContainer = dest, stopOnRun = true, stops = 0 }
    function a.forceStop() a.stops = a.stops + 1 end
    ISBaseTimedAction.create(a)
    return a
end
local bag, main, crate = container(true), container(true), container(false)

local master, plain = player(true), player(false)
out[#out + 1] = "masterKept=" .. tostring(action(master, "ISInventoryTransferAction", bag, main).stopOnRun == false)
out[#out + 1] = "plainStops=" .. tostring(action(plain, "ISInventoryTransferAction", bag, main).stopOnRun == true)
out[#out + 1] = "fromCrateStops=" .. tostring(action(master, "ISInventoryTransferAction", crate, main).stopOnRun == true)
out[#out + 1] = "toCrateStops=" .. tostring(action(master, "ISInventoryTransferAction", main, crate).stopOnRun == true)
out[#out + 1] = "otherClassLeft=" .. tostring(action(master, "MagazineBag_TransferAction", bag, main).stopOnRun == true)
out[#out + 1] = "reloadKept=" .. tostring(action(master, "ISInsertMagazine").stopOnRun == false)

local function run(behind, running, moving)
    local p = player(true)
    local transfer = action(p, "ISInventoryTransferAction", bag, main)
    local list = { transfer }
    for _, type in ipairs(behind) do list[#list + 1] = action(p, type) end
    ISTimedActionQueue.queues[p] = { queue = list }
    p.running, p.moving = running, moving
    update(p)
    update(p)
    return transfer.stops
end
out[#out + 1] = "runWithInsertBehind=" .. tostring(run({ "ISInsertMagazine" }, true, true) == 0)
out[#out + 1] = "runWithLoadFurtherBehind=" .. tostring(run({ "ISInventoryTransferAction", "ISLoadBulletsInMagazine" }, true, true) == 0)
out[#out + 1] = "runAloneStoppedOnce=" .. tostring(run({}, true, true) == 1)
out[#out + 1] = "runBeforeOtherWorkStopped=" .. tostring(run({ "ISEatFoodAction" }, true, true) == 1)
out[#out + 1] = "walkAloneLeft=" .. tostring(run({}, false, true) == 0)
out[#out + 1] = "runKeyStandingLeft=" .. tostring(run({}, true, false) == 0)
update(player(true))   -- no queue at all
return table.concat(out, "\n")
''')

failed = False
for line in result.splitlines():
    ok = line.endswith('=true')
    failed = failed or not ok
    print(('ok      ' if ok else 'FAILED  ') + line.split('=')[0])
print('FAILED' if failed else 'all pass')
sys.exit(1 if failed else 0)
