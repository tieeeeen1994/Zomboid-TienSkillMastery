--[[
Tien's Skill Mastery: signature abilities that live in vanilla's timed actions (42.21, both sides).

No `new` is wrapped here (fixed 2026-11-07). An MP server rebuilds a client's timed action with `Type.new(...)`,
filling the arguments from the client table's values of the outermost `new`'s parameter names (`NetTimedAction.set`
reads the function's locvars), and other mods replace these `new`s with parameters of their own. Gunworks (42.13):
`ISReloadWeaponAction:new(character, gun, ammoLimit, ammoTypeOverride, gunworksReloadAiming, gunworksReloadStep)`,
`ISRackFirearm:new(character, gun, gunworksRackPhase)`, `gunworksReloadAiming` on ISInsertMagazine / ISEjectMagazine /
ISUnloadBulletsFromFirearm, `ammoLimit, ammoTypeOverride` on ISLoadBulletsInMagazine; Hot Brass also overrides
`ISRackFirearm:new`. The first version wrapped them with vanilla's names only, which dropped those arguments on both
sides: Gunworks lost its rack phase and reload step and looped (rack, rack, reload again). So:

- Firearms.SigRunReload (run-and-gun reload): every reload action sets `stopOnRun = true` in `new`
  (ISReloadWeaponAction ~292, ISInsertMagazine ~146, ISEjectMagazine ~107, ISLoadBulletsInMagazine ~166,
  ISRackFirearm ~210, ISUnloadBulletsFromFirearm ~129, ISUnloadBulletsFromMagazine ~146), read by Java `BaseAction`
  on the client only. It is set false in `ISBaseTimedAction:create` (~78, the client's / single player's step that
  builds the Java action, right after `new`; none of these classes override it), by the action's `Type`.
  `stopOnWalk` / `stopOnAim` are already false.
  That alone still restarted the reload when running (reported twice, 2026-11-07). Why: the reload clips are nodes
  of the `actions` substate (AnimSets/player/actions), which the `idle` and `movement` (walking) states enter through
  their `to_actions.xml` and keep through `childTags.xml`; `run` and `sprint` have neither. Starting to run drops the
  substate, slowing down enters it again from the clip's first frame, and in single player the reload advances on
  that clip's events (`loadFinished` at its end, `InsertBullet`...), so it started over. Action groups cannot be
  modded: `ActionGroup.load` (42.21) reads only `ZomboidFileSystem.getMediaFile("actiongroups/...")`, the game's own
  folder (an attempt to add run / sprint transitions from the mod was never loaded).
  So in single player a master's reload is driven by time instead, the way an MP server drives it: after `start`,
  the action's own `serverStart` runs with `emulateAnimEvent` / `emulateAnimEventOnce` (server globals that take the
  Java net action) swapped for Lua timers on the same real-time clock, and `self.netAction` is a stand-in whose
  `forceComplete` ends the action. The timers fire the action's `animEvent` (periodic ones repeat), and the real
  animation's copies of those event names are ignored; sounds and model swaps still come from the animation. So the
  reload keeps its pace through running, walking and standing; the clip itself still cannot play while running and
  starts over afterwards. An MP server already does this, so MP clients are left alone. `serverStart`'s side effects
  repeat `start`'s (`initVars` sets the reload speed again; ISRackFirearm ejects spent rounds again, by then none).
- Firearms.SigQuickdraw: `ISEquipWeaponAction` / `ISUnequipAction`: the caller passes the time (`maxTimeInit`); from a
  hotbar slot `animSpeed` = maxTime / `adjustMaxTime(maxTime)`, and with maxTime -1 the action ends on the anim
  event. For a one-handed firearm (`isRanged()`, not `isTwoHandWeapon()` / `isRequiresEquippedBothHands()`) held by
  a master: the time / 4 (at least 1) and animSpeed x 4, so an anim-timed draw reaches its event 4x sooner.
  Whatever was in hand goes away as fast (user, 2026-11-07): the hotbar puts a held hotbar item away with its own
  `ISUnequipAction(chr, primary, 20)` queued right before the draw (`ISHotbar:equipItem`), so an unequip of anything
  whose next few queued actions include a quickdraw draw by the same character is quickened the same way.
  All in `create` (client / single player), before the Java action is built from `maxTime` and before the request
  goes to an MP server: both `maxTime` and `maxTimeInit` are lowered, and `maxTimeInit` is one of `new`'s parameter
  names (both classes), so the server rebuilds the action with the short time (its `new` sets `maxTime` from it,
  and the base `getDuration` returns that). Vanilla's hand rules in `complete` are untouched.
- Handicraft.SigDeftHands: `ISBaseTimedAction:adjustMaxTime(maxTime)` (~99: unhappy, drunk, hand pain, temperature;
  no vanilla subclass overrides it) is what a client's `create` (~79) and the MP server's `NetTimedAction` both run
  on the duration, so scaling its result by 0.9 shortens every Lua timed action on both sides. Item transfers (Java
  `Transaction.getDuration` in MP; later batches skip `adjustMaxTime` in SP) have their own path since 2026-11-08:
  TienSkillMastery_DeftTransfer*.lua (client / server / shared), right-click Grab too. Not covered: build-menu builds (Java `BuildAction.getDuration`), looped actions
  (-1) and actions that end on anim events (reloading). It multiplies with a mastery's own time bonus.
]]

require "TienSkillMastery"
require "TimedActions/ISBaseTimedAction"
require "TimedActions/ISReloadWeaponAction"
require "TimedActions/ISInsertMagazine"
require "TimedActions/ISEjectMagazine"
require "TimedActions/ISLoadBulletsInMagazine"
require "TimedActions/ISRackFirearm"
require "TimedActions/ISUnloadBulletsFromFirearm"
require "TimedActions/ISUnloadBulletsFromMagazine"
require "TimedActions/ISEquipWeaponAction"
require "TimedActions/ISUnequipAction"
local M = TienSkillMastery

-- ---------------------------------------------------------------------------------------------------------------
-- Run-and-gun reload and quickdraw, without touching any `new` (see the header)
-- ---------------------------------------------------------------------------------------------------------------

local RELOAD = { ISReloadWeaponAction = true, ISInsertMagazine = true, ISEjectMagazine = true,
    ISLoadBulletsInMagazine = true, ISRackFirearm = true, ISUnloadBulletsFromFirearm = true,
    ISUnloadBulletsFromMagazine = true }
local EQUIP = { ISEquipWeaponAction = true, ISUnequipAction = true }
local QUICK = 4

local function quickdrawApplies(character, item)
    return character and item and instanceof(item, "HandWeapon") and item:isRanged() and not item:isTwoHandWeapon()
        and not item:isRequiresEquippedBothHands() and M.sig(character, "Firearms.SigQuickdraw")
end

local function quickTime(t)
    if type(t) == "number" and t > 1 then return math.max(1, math.floor(t / QUICK)) end
    return t
end

--- True when a quickdraw draw by the same character is among the next few queued actions (the hotbar queues the
--- put-away of what is in hand right before the draw, with a transfer from a bag perhaps between).
local drawing = {}   -- [character] = true while ISHotbar:equipItem queues a quickdraw draw

local function drawFollows(action)
    local chr = action.character
    if not chr or not ISTimedActionQueue or not M.sig(chr, "Firearms.SigQuickdraw") then return false end
    -- `ISTimedActionQueue.add` begins an action at once when the queue is empty, so the put-away the hotbar queues
    -- first runs `create` before the draw exists; `equipItem` is marked for that (wrapped below).
    if drawing[chr] then return true end
    local queue = ISTimedActionQueue.getTimedActionQueue(chr)
    local list = queue and queue.queue
    if not list then return false end
    local at = nil
    for i, a in ipairs(list) do
        if a == action then at = i break end
    end
    if not at then return false end
    for i = at + 1, math.min(#list, at + 3) do
        local a = list[i]
        if a.Type == "ISEquipWeaponAction" and quickdrawApplies(chr, a.item) then return true end
    end
    return false
end

if ISBaseTimedAction and ISBaseTimedAction.create and not ISBaseTimedAction.__tsmCreate then
    ISBaseTimedAction.__tsmCreate = true
    local vanillaCreate = ISBaseTimedAction.create
    function ISBaseTimedAction:create(...)
        local t = self.Type
        local runReload = false
        if RELOAD[t] and self.character and M.sig(self.character, "Firearms.SigRunReload") then
            self.stopOnRun = false
            runReload = true
        elseif EQUIP[t] and not self.tsmQuick and (quickdrawApplies(self.character, self.item)
            or (t == "ISUnequipAction" and drawFollows(self))) then
            self.tsmQuick = true
            self.maxTime = quickTime(self.maxTime)
            self.maxTimeInit = quickTime(self.maxTimeInit)
            self.animSpeed = (self.animSpeed or 1) * QUICK
        end
        -- Single player: progress by time (see the header; started after `start`).
        if runReload and not isClient() and not isServer() and type(self.serverStart) == "function" then
            self.tsmTimed = true
        end
        return vanillaCreate(self, ...)
    end
end

-- ---------------------------------------------------------------------------------------------------------------
-- Single player: a master's reload driven by time (the server's emulated events), so running cannot restart it
-- ---------------------------------------------------------------------------------------------------------------

local timed = {}   -- actions with timers: { action, timers = { { event, param, period, once, due } } }

local function startTimers(action)
    local timers = {}
    local now = getTimestampMs()
    local function capture(once)
        return function(_, period, event, param)
            period = math.max(20, tonumber(period) or 1000)
            timers[#timers + 1] = { event = event, param = param, period = period, once = once, due = now + period }
        end
    end
    local saveRepeat, saveOnce = emulateAnimEvent, emulateAnimEventOnce
    emulateAnimEvent, emulateAnimEventOnce = capture(false), capture(true)
    local hadNet = action.netAction
    action.netAction = action.netAction or {
        forceComplete = function() action:forceComplete() end,
        forceStop = function() action:forceStop() end,
        getProgress = function() return action:getJobDelta() end,
    }
    local ok, err = pcall(action.serverStart, action)
    emulateAnimEvent, emulateAnimEventOnce = saveRepeat, saveOnce
    if not hadNet then action.netAction.tsmStandIn = true end
    if not ok then
        print("[TienSkillMastery] timed reload failed, the animation drives it: " .. tostring(err))
        action.tsmTimed = nil
        return
    end
    action.tsmEvents = {}
    for _, t in ipairs(timers) do action.tsmEvents[t.event] = true end
    if #timers > 0 then table.insert(timed, { action = action, timers = timers }) end
end

local function isRunning(action)
    local queue = action.character and ISTimedActionQueue.getTimedActionQueue(action.character)
    return queue ~= nil and queue.queue ~= nil and queue.queue[1] == action
end

Events.OnTick.Add(function()
    if #timed == 0 then return end
    local now = getTimestampMs()
    for i = #timed, 1, -1 do
        local entry = timed[i]
        local action = entry.action
        if not isRunning(action) then
            table.remove(timed, i)
        else
            for j = #entry.timers, 1, -1 do
                local t = entry.timers[j]
                if now >= t.due then
                    action.tsmFiring = true
                    local ok, err = pcall(action.animEvent, action, t.event, t.param)
                    action.tsmFiring = nil
                    if not ok then print("[TienSkillMastery] timed reload event failed: " .. tostring(err)) end
                    if t.once then table.remove(entry.timers, j) else t.due = now + t.period end
                end
            end
        end
    end
end)

for name in pairs(RELOAD) do
    local class = _G[name]
    if class and class.start and class.animEvent and not rawget(class, "__tsmTimed") then
        rawset(class, "__tsmTimed", true)
        local vanillaStart, vanillaEvent = class.start, class.animEvent
        class.start = function(self, ...)
            local r = { vanillaStart(self, ...) }
            if self.tsmTimed then startTimers(self) end
            return unpack(r)
        end
        class.animEvent = function(self, event, parameter, ...)
            -- The timers own these events; the animation's copies would restart with the clip.
            if self.tsmTimed and self.tsmEvents and self.tsmEvents[event] and not self.tsmFiring then return end
            return vanillaEvent(self, event, parameter, ...)
        end
    end
end

-- ---------------------------------------------------------------------------------------------------------------
-- Deft hands
-- ---------------------------------------------------------------------------------------------------------------

if ISBaseTimedAction and ISBaseTimedAction.adjustMaxTime and not ISBaseTimedAction.__tsmDeft then
    ISBaseTimedAction.__tsmDeft = true
    local v = ISBaseTimedAction.adjustMaxTime
    function ISBaseTimedAction:adjustMaxTime(maxTime, ...)
        local t = v(self, maxTime, ...)
        if type(t) == "number" and t > 1 and self.character then
            local cut = M.val(self.character, "Handicraft.SigDeftHands")
            if cut > 0 then t = math.max(1, t * (1 - cut / 100)) end
        end
        return t
    end
end

-- ---------------------------------------------------------------------------------------------------------------
-- Quickdraw: mark a hotbar draw while it queues the put-away of what is in hand (client / single player). Wrapped
-- once the client's ISHotbar exists; mods that replace `activateSlot` still end in `equipItem`, or the look-ahead in
-- `drawFollows` covers a put-away that waits behind other actions.
-- ---------------------------------------------------------------------------------------------------------------

local function wrapHotbar()
    if isServer() or not ISHotbar or not ISHotbar.equipItem or ISHotbar.__tsmQuickdraw then return end
    ISHotbar.__tsmQuickdraw = true
    local vanilla = ISHotbar.equipItem
    function ISHotbar:equipItem(item, ...)
        local chr = self.chr
        local mark = chr and quickdrawApplies(chr, item) and chr:getPrimaryHandItem() ~= item
            and chr:getSecondaryHandItem() ~= item
        if mark then drawing[chr] = true end
        local r = { pcall(vanilla, self, item, ...) }
        if mark then drawing[chr] = nil end
        if not r[1] then error(r[2], 0) end
        return unpack(r, 2)
    end
end
Events.OnGameStart.Add(wrapHotbar)
