--[[
Tien's Skill Mastery: Deft Hands for item transfers, client part (user, 2026-11-08; see the shared file for why).

Multiplayer. `ISInventoryTransferAction` opens each batch with the global `createItemTransaction` (vanilla `start` for
the first, `perform` for each next one, 42.21). While a master's transfer opens a batch whose two containers can be
addressed, that call sends the batch to the server instead (`deftTransfer`) and returns 0, vanilla's "no
transaction" id; the action's time becomes vanilla's length cut by the signature (the progress bar), and it then
waits for the items to really arrive, as vanilla waits for its Done: a queued follow-up action (eating out of a bag)
expects the item there. `update` runs vanilla's with the transaction polls answering "not yet" (id 0 reads done and
would end it at once), then completes the action once every item is in the destination (dropping to the floor: once
the server has answered, since a dropped item has no destination to watch), or 10 s past the expected end (a lost
packet). Items the server declined that are still at the source are moved the vanilla way (a real transaction for
those; the next batch is sent to the server again). Cancelling the action tells the server to drop the batch.

Single player has no transactions: the first batch's time goes through `adjustMaxTime` (Deft Hands' cut,
TienSkillMastery_Signatures.lua), each next batch takes its time straight from the queue in `perform`, so it is cut
there.

Zomboid Fixes B42 (its client ZomboidFixesB42_Transfer.lua) intercepts the same calls for the Fast Timed Actions
cheat (`zfixFast`) and for multiplayer fast forward; a batch either of those takes is left to it, in whichever order
the two mods load.

Grabbing from the ground (`ISGrabItemAction`: the world menu's Grab, build cursors picking up materials, search
mode icons; covered since 2026-11-08, user). Vanilla's grab queues world items in batches (same type, up to 20;
later grabs join the last queued grab), opens a transaction with no items and an "object" container whose parent is
the batch's first world item, never waits for it (no `setWaitForFinished`), and its `isValid` stops it, and the queue
behind it, as soon as the world item leaves the square, which the server's move does. So for a master in MP the
whole grab runs its own way (ported from Zomboid Fixes B42's quick grab): `start` runs vanilla's without its
transaction, sends the batch's items (src = the floor, with floor hints), waits for them to arrive in the inventory,
`isValid` is skipped once started, and `perform` sends the next batch. Declined items still on the ground go the
vanilla way. Single player cuts each later batch's time in `perform`, as for transfers.
]]

if isServer() then return end

require "TimedActions/ISInventoryTransferAction"
require "TienSkillMastery"
require "TienSkillMastery_DeftTransferShared"

local M = TienSkillMastery
local DT = M.DeftTransfer

local LOST_MS = 10000
local waiting = {}        -- [token] = action
local nextToken = 0
local batchFor = nil      -- the action opening a batch right now
local quietPolls = false  -- the transaction polls answer "not yet" while true

local inner = {
    start = ISInventoryTransferAction.start,
    update = ISInventoryTransferAction.update,
    perform = ISInventoryTransferAction.perform,
    stop = ISInventoryTransferAction.stop,
}

--- Zomboid Fixes B42's fast forward is running: its timed transfers take every batch.
local function zfFastForward()
    local ZF = ZomboidFixesB42
    local vars = SandboxVars and SandboxVars.ZomboidFixesB42
    return ZF ~= nil and vars ~= nil and vars.MultiplayerFastForward == true and (ZF.fastForwardSpeed or 1) > 1
end

local function forgetBatch(self)
    if self.tsmToken then waiting[self.tsmToken] = nil end
    self.tsmToken = nil
    self.tsmTimed = false
    self.tsmPending = nil
    self.tsmAcked = false
    self.tsmDone = false
    self.tsmDeadline = nil
end

-- Transaction polls -------------------------------------------------------------------------------------------------

local vanillaDone, vanillaRejected = isItemTransactionDone, isItemTransactionRejected
function isItemTransactionDone(id, ...)
    if quietPolls then return false end
    return vanillaDone(id, ...)
end
function isItemTransactionRejected(id, ...)
    if quietPolls then return false end
    return vanillaRejected(id, ...)
end

-- Opening a batch ---------------------------------------------------------------------------------------------------

local suppressCreate = false  -- vanilla's grab start runs without opening its transaction

local vanillaCreate = createItemTransaction
function createItemTransaction(character, items, src, dst)
    if suppressCreate then return 0 end
    local action = batchFor
    if action and isClient() and not action.zfixFast and not zfFastForward() and DT.cut(character) > 0 then
        local srcCode = DT.encodeContainer(src, character)
        local dstCode = DT.encodeContainer(dst, character)
        if srcCode and dstCode and not (srcCode == DT.FLOOR and dstCode == DT.FLOOR) then
            local list, ids, units = {}, {}, 0
            for _, item in ipairs(items or {}) do
                list[#list + 1] = item
                ids[#ids + 1] = tostring(item:getID())
                units = math.max(units, DT.transferUnits(character, item, src, dst))
            end
            units = units * (1 - DT.cut(character) / 100)
            forgetBatch(action)
            nextToken = nextToken + 1
            action.tsmToken = tostring(nextToken)
            action.tsmTimed = true
            action.tsmPending = list
            action.tsmSrc, action.tsmDst = srcCode, dstCode
            action.tsmUnits = math.max(1, units)
            action.tsmDeadline = getTimestampMs() + units * DT.MS_PER_UNIT + LOST_MS
            waiting[action.tsmToken] = action
            if #ids == 0 then
                action.tsmPending = {}
                action.tsmAcked = true
            else
                sendClientCommand(character, M.MODULE, DT.COMMAND, {
                    token = action.tsmToken, src = srcCode, dst = dstCode,
                    items = table.concat(ids, ","), floor = DT.encodeFloorHints(list),
                })
            end
            return 0
        end
    end
    return vanillaCreate(character, items, src, dst)
end

--- Runs a vanilla step that may open a batch; a batch sent to the server gets the cut length as its time.
local function openingBatch(self, fn)
    self.tsmTimed = false
    batchFor = self
    local ok, err = pcall(fn, self)
    batchFor = nil
    if not ok then error(err) end
    if self.tsmTimed then
        self.maxTime = self.tsmUnits
        self.action:setTime(self.maxTime)
    end
end

-- The server's answer -----------------------------------------------------------------------------------------------

local function stillAtSource(self, item)
    if self.tsmSrc == DT.FLOOR then return item:getWorldItem() ~= nil end
    return self.srcContainer ~= nil and self.srcContainer:containsID(item:getID())
end

Events.OnServerCommand.Add(function(module, command, args)
    if module ~= M.MODULE or command ~= DT.REPLY or type(args) ~= "table" then return end
    local self = waiting[tostring(args.token)]
    if not self or not self.tsmPending then return end
    local declined = {}
    if type(args.failed) == "string" then
        for id in string.gmatch(args.failed, "([^,]+)") do declined[tonumber(id) or -1] = true end
    end
    local keep, fallback = {}, {}
    for _, item in ipairs(self.tsmPending) do
        if declined[item:getID()] then
            if stillAtSource(self, item) then fallback[#fallback + 1] = item end
        else
            keep[#keep + 1] = item
        end
    end
    self.tsmPending = keep
    if #fallback > 0 then self.tsmFallback = fallback end
    self.tsmAcked = true
end)

--- Every item of the batch has landed (by ID: the client's copy after the server's packets is a new object).
local function arrived(self)
    if not self.tsmPending then return false end
    if self.tsmDst == DT.FLOOR then return self.tsmAcked end
    local dest, fresh = self.destContainer, nil
    for _, item in ipairs(self.tsmPending) do
        if not (dest and dest:containsID(item:getID())) then
            -- A bag the server could only update by re-sending it whole is a new object here: look it up again.
            if fresh == nil then fresh = DT.decodeContainer(self.tsmDst, self.character) or false end
            if not fresh or not fresh:containsID(item:getID()) then return false end
        end
    end
    return true
end

--- What the server declined and the client still shows at the source goes the vanilla way.
local function fallBack(self)
    local items = self.tsmFallback
    self.tsmFallback = nil
    forgetBatch(self)
    for _, queued in ipairs(self.queueList or {}) do queued.time = -1 end
    self.maxTime = -1
    self.action:setTime(-1)
    self.transactionId = vanillaCreate(self.character, items, self.srcContainer, self.destContainer)
    print(string.format("[TienSkillMastery] The server declined %d item(s) of a deft transfer; moving them the normal way", #items))
end

-- The action --------------------------------------------------------------------------------------------------------

function ISInventoryTransferAction:start()
    return openingBatch(self, inner.start)
end

function ISInventoryTransferAction:update()
    if not self.tsmTimed then return inner.update(self) end
    quietPolls = true
    local ok, err = pcall(inner.update, self)
    quietPolls = false
    if not ok then error(err) end
    if self.tsmFallback then return fallBack(self) end
    if not self.tsmDone and (arrived(self) or getTimestampMs() > (self.tsmDeadline or 0)) then
        self.tsmDone = true
        self:forceComplete()
    end
end

function ISInventoryTransferAction:perform()
    if self.tsmTimed then forgetBatch(self) end
    openingBatch(self, inner.perform)
    -- Single player: the next batch's time came straight from the queue, past adjustMaxTime.
    if not isClient() and self.queueList and #self.queueList > 0 and self.maxTime and self.maxTime > 1 then
        local cut = DT.cut(self.character)
        if cut > 0 then
            self.maxTime = math.max(1, self.maxTime * (1 - cut / 100))
            self.action:setTime(self.maxTime)
        end
    end
end

function ISInventoryTransferAction:stop()
    if self.tsmTimed and self.tsmToken and not self.tsmDone then
        sendClientCommand(self.character, M.MODULE, DT.CANCEL, { token = self.tsmToken })
    end
    if self.tsmTimed then forgetBatch(self) end
    return inner.stop(self)
end

-- Grabbing from the ground -------------------------------------------------------------------------------------------

require "TimedActions/ISGrabItemAction"

local grab = {
    new = ISGrabItemAction.new,
    isValid = ISGrabItemAction.isValid,
    start = ISGrabItemAction.start,
    update = ISGrabItemAction.update,
    perform = ISGrabItemAction.perform,
    stop = ISGrabItemAction.stop,
}

--- Sends the world items of one grab batch that are still on the ground, timed like a transfer from the floor.
local function sendGrabBatch(self, queuedItem)
    local chr = self.character
    local items, ids, units = {}, {}, 0
    local floor = ItemContainer.new("floor", nil, nil)
    forgetBatch(self)
    self.tsmSentIds = {}
    for _, worldItem in ipairs((queuedItem and queuedItem.items) or {}) do
        local item = worldItem:getItem()
        if item and worldItem:getSquare() then
            items[#items + 1] = item
            ids[#ids + 1] = tostring(item:getID())
            self.tsmSentIds[item:getID()] = true
            units = math.max(units, DT.transferUnits(chr, item, floor, self.destContainer))
        end
    end
    units = math.max(1, units * (1 - DT.cut(chr) / 100))
    nextToken = nextToken + 1
    self.tsmToken = tostring(nextToken)
    self.tsmPending = items
    self.tsmSrc = DT.FLOOR
    self.tsmDeadline = getTimestampMs() + units * DT.MS_PER_UNIT + LOST_MS
    waiting[self.tsmToken] = self
    self.maxTime = units
    self.action:setTime(units)
    if #ids == 0 then
        self.tsmAcked = true
        return
    end
    sendClientCommand(chr, M.MODULE, DT.COMMAND, {
        token = self.tsmToken, src = DT.FLOOR, dst = self.tsmDst,
        items = table.concat(ids, ","), floor = DT.encodeFloorHints(items),
    })
end

--- Declined items still on the ground: a vanilla transaction for them, the rest of the grab vanilla's.
local function fallBackGrab(self)
    local worldItems = {}
    for _, item in ipairs(self.tsmFallback) do
        local worldItem = item:getWorldItem()
        if worldItem and worldItem:getSquare() then worldItems[#worldItems + 1] = worldItem end
    end
    self.tsmFallback = nil
    local queuedItem = self.queueList and self.queueList[1]
    if #worldItems == 0 or not queuedItem then return end
    forgetBatch(self)
    self.tsmGrab = false
    self.action:setWaitForFinished(false)
    queuedItem.items = worldItems
    for _, queued in ipairs(self.queueList) do queued.time = -1 end
    self.item = worldItems[1]
    self.sourceContainer = ItemContainer.new("object", self.item:getSquare(), self.item)
    self.maxTime = -1
    self.action:setTime(-1)
    self.transactionId = vanillaCreate(self.character, nil, self.sourceContainer, self.destContainer)
    print(string.format("[TienSkillMastery] The server declined %d item(s) of a deft grab; picking them up the normal way", #worldItems))
end

function ISGrabItemAction:new(character, item, time)
    local o = grab.new(self, character, item, time)
    -- A grab that joined an earlier grab action (ignoreAction) is never run itself.
    if not o.ignoreAction and isClient() and DT.cut(character) > 0 then
        local dst = DT.encodeContainer(o.destContainer, character)
        if dst then
            o.tsmGrab = true
            o.tsmDst = dst
        end
    end
    return o
end

function ISGrabItemAction:isValid()
    if self.tsmGrab and self.started then return true end
    return grab.isValid(self)
end

function ISGrabItemAction:start()
    -- Zomboid Fixes B42's cheat or fast forward takes it, whichever mod wrapped first.
    if self.tsmGrab and (self.zfixFast or zfFastForward() or DT.cut(self.character) <= 0) then self.tsmGrab = false end
    if not self.tsmGrab then return grab.start(self) end
    suppressCreate = true
    local ok, err = pcall(grab.start, self)
    suppressCreate = false
    if not ok then error(err) end
    self.transactionId = 0
    self.action:setWaitForFinished(true)
    sendGrabBatch(self, self.queueList and self.queueList[1])
end

function ISGrabItemAction:update()
    if not self.tsmGrab then return grab.update(self) end
    local item = self.item and self.item:getItem()
    if item then item:setJobDelta(self.action:getJobDelta()) end
    if self.tsmFallback then return fallBackGrab(self) end
    if not self.tsmDone and (arrived(self) or getTimestampMs() > (self.tsmDeadline or 0)) then
        self.tsmDone = true
        self:forceComplete()
    end
end

function ISGrabItemAction:perform()
    if not self.tsmGrab then
        grab.perform(self)
        -- Single player: the next batch's time came straight from the queue, past adjustMaxTime.
        if not isClient() and self.queueList and #self.queueList > 0 and self.maxTime and self.maxTime > 1 then
            local cut = DT.cut(self.character)
            if cut > 0 then
                self.maxTime = math.max(1, self.maxTime * (1 - cut / 100))
                self.action:setTime(self.maxTime)
            end
        end
        return
    end
    local queuedItem = table.remove(self.queueList, 1)
    -- Grabs that joined the batch after it was sent go next.
    if queuedItem then
        local left = {}
        for _, worldItem in ipairs(queuedItem.items) do
            local item = worldItem:getItem()
            if item and not (self.tsmSentIds and self.tsmSentIds[item:getID()]) then left[#left + 1] = worldItem end
        end
        if #left > 0 then table.insert(self.queueList, 1, { items = left, time = self.maxTime, type = queuedItem.type }) end
    end
    forgetBatch(self)
    self.tsmSentIds = nil
    if #self.queueList > 0 then
        local nextItem = self.queueList[1]
        self.item = nextItem.items[1]
        self.action:reset() -- clears forceComplete
        self:resetJobDelta()
        sendGrabBatch(self, nextItem)
    else
        self.action:stopTimedActionAnim()
        self.action:setLoopedAction(false)
        self.action:setWaitForFinished(false)
        ISBaseTimedAction.perform(self)
        self.started = false
    end
    ISInventoryPage.renderDirty = true
end

function ISGrabItemAction:stop()
    if self.tsmGrab and self.tsmToken and not self.tsmDone then
        sendClientCommand(self.character, M.MODULE, DT.CANCEL, { token = self.tsmToken })
    end
    if self.tsmGrab then forgetBatch(self) end
    return grab.stop(self)
end
