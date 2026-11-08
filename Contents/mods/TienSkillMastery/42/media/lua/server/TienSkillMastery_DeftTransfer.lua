--[[
Tien's Skill Mastery: Deft Hands for item transfers, server part (user, 2026-11-08; see the shared file for why).

A master's client sends each transfer batch here instead of opening an item transaction: { token, src, dst, items
(IDs), floor (hints) }. The batch waits vanilla's length (`DT.transferUnits`, the formula of Java
`Transaction.getDuration`, its slowest item) cut by the signature, in real time as vanilla's does, then is moved with
vanilla's own server-side mover (`ISTransferAction:transferItem`: worn and equipped items, vehicle part weights,
replacement, the remove half of the replication) plus `sendAddItemToContainer`. Checked again at that moment, item
by item, as `TransactionManager.isConsistent` would: still in the source (or on the ground near the player), allowed
in and room in the destination (not for the player's main inventory, which vanilla's server never checks either),
both containers within reach (stricter than vanilla, which has no distance check for ordinary containers). The
client hears back once per batch which items were not moved, and moves those the vanilla way.

Refused outright, all items declined (the client then uses vanilla's transaction): no Deft Hands signature on this
side, a dead player, too many batches waiting. Ported from Zomboid Fixes B42's server / FastForwardTransfer files.
]]

if isClient() then return end

require "TienSkillMastery"
require "TienSkillMastery_DeftTransferShared"
require "TimedActions/ISTransferAction"

local M = TienSkillMastery
local DT = M.DeftTransfer

local MAX_PENDING_PER_PLAYER = 8
local pending = {}   -- { player, token, args, dueMs }

local function reply(player, token, failed, why)
    if why and #failed > 0 then
        print(string.format("[TienSkillMastery] Deft transfer declined for %s: %s", tostring(player:getUsername()), why))
    end
    if not token then return end
    sendServerCommand(player, M.MODULE, DT.REPLY, { token = token, failed = table.concat(failed, ",") })
end

local function hasRoom(player, dest, item)
    if dest == player:getInventory() then return true end
    return dest:hasRoomFor(player, item)
end

--- Java's `Transaction` (~166) names the mover as a moved food's chef, and `ISTransferAction:transferItem` does not.
--- Without it a master's food on a stove earns no cooking XP and no Savory Meals (Food.update ~485).
local function noteChef(player, item)
    if instanceof(item, "Food") then item:setChef(player:getUsername()) end
end

local function moveFromGround(player, itemId, dest, hint)
    local item, square = DT.findItemOnGroundNear(player, itemId, hint)
    if not item then return false, "not on the ground near the player" end
    if not dest:isItemAllowed(item) then return false, "not allowed in the destination" end
    if not hasRoom(player, dest, item) then return false, "no room in the destination" end
    noteChef(player, item)
    local floor = ItemContainer.new("floor", square, nil)
    local moved = ISTransferAction:transferItem(player, item, floor, dest, nil)
    sendAddItemToContainer(dest, moved or item)
    return true
end

local function moveToGround(player, itemId, src)
    local item = src:getItemWithID(itemId)
    if not item then return false, "not in the source container" end
    local floor = ItemContainer.new("floor", player:getCurrentSquare(), nil)
    local dropSquare = ISTransferAction:getNotFullFloorSquare(player, item, floor)
    if not dropSquare then return false, "no room on the floor" end
    noteChef(player, item)
    -- The floor branch ends in AddWorldInventoryItem, which replicates itself.
    ISTransferAction:transferItem(player, item, src, floor, dropSquare)
    return true
end

local function moveBetween(player, itemId, src, dest)
    local item = src:getItemWithID(itemId)
    if not item then return false, "not in the source container" end
    if not dest:isItemAllowed(item) then return false, "not allowed in the destination" end
    if not hasRoom(player, dest, item) then return false, "no room in the destination" end
    noteChef(player, item)
    local moved = ISTransferAction:transferItem(player, item, src, dest, nil)
    sendAddItemToContainer(dest, moved or item)
    return true
end

local function moveBatch(player, args)
    local fromGround, toGround = args.src == DT.FLOOR, args.dst == DT.FLOOR
    local ids = DT.parseIds(args.items)
    if fromGround and toGround then return reply(player, args.token, {}) end
    local src = (not fromGround) and DT.decodeContainer(args.src, player) or nil
    local dest = (not toGround) and DT.decodeContainer(args.dst, player) or nil
    if (not fromGround and not src) or (not toGround and not dest) then
        return reply(player, args.token, ids, string.format("container not found (src %s, dst %s)", tostring(args.src), tostring(args.dst)))
    end
    if src and dest and src == dest then return reply(player, args.token, ids, "source and destination are the same") end
    if src and not DT.isContainerInReach(player, src) then return reply(player, args.token, ids, "source out of reach") end
    if dest and not DT.isContainerInReach(player, dest) then return reply(player, args.token, ids, "destination out of reach") end
    local hints = DT.parseFloorHints(args.floor)
    local failed, reasons = {}, {}
    for _, id in ipairs(ids) do
        local ok, moved, why = pcall(function()
            if fromGround then return moveFromGround(player, id, dest, hints[id]) end
            if toGround then return moveToGround(player, id, src) end
            return moveBetween(player, id, src, dest)
        end)
        if not ok then moved, why = false, tostring(moved) end
        if not moved then
            failed[#failed + 1] = tostring(id)
            reasons[#reasons + 1] = tostring(id) .. " " .. tostring(why)
        end
    end
    reply(player, args.token, failed, table.concat(reasons, ", "))
end

--- Vanilla's length for this batch in ms, cut by the signature.
local function batchMs(player, args)
    local square = player:getCurrentSquare()
    local src = args.src == DT.FLOOR and ItemContainer.new("floor", square, nil) or DT.decodeContainer(args.src, player)
    local dst = args.dst == DT.FLOOR and ItemContainer.new("floor", square, nil) or DT.decodeContainer(args.dst, player)
    if not src or not dst then return 0 end
    local units = 0
    local hints = DT.parseFloorHints(args.floor)
    for _, id in ipairs(DT.parseIds(args.items)) do
        local item
        if args.src == DT.FLOOR then
            item = DT.findItemOnGroundNear(player, id, hints[id])
        else
            item = src:getItemWithID(id)
        end
        if item then units = math.max(units, DT.transferUnits(player, item, src, dst)) end
    end
    return units * DT.MS_PER_UNIT * (1 - DT.cut(player) / 100)
end

local function onRequest(player, args)
    local token = type(args.token) == "string" and args.token or nil
    if not token then return end
    if player:isDead() or DT.cut(player) <= 0 then
        return reply(player, token, DT.parseIds(args.items), "no Deft Hands on the server")
    end
    local count = 0
    for _, entry in ipairs(pending) do
        if entry.player == player then count = count + 1 end
    end
    if count >= MAX_PENDING_PER_PLAYER then return reply(player, token, DT.parseIds(args.items), "too many waiting") end
    local ok, ms = pcall(batchMs, player, args)
    pending[#pending + 1] = { player = player, token = token, args = args, dueMs = getTimestampMs() + (ok and ms or 0) }
end

local function onCancel(player, args)
    for i = #pending, 1, -1 do
        if pending[i].player == player and pending[i].token == args.token then table.remove(pending, i) end
    end
end

Events.OnTick.Add(function()
    if #pending == 0 then return end
    local now = getTimestampMs()
    local due = {}
    for i = #pending, 1, -1 do
        local entry = pending[i]
        if entry.player:isDead() or not entry.player:isExistInTheWorld() then
            table.remove(pending, i)
        elseif now >= entry.dueMs then
            table.remove(pending, i)
            table.insert(due, 1, entry)
        end
    end
    for _, entry in ipairs(due) do
        local ok, err = pcall(moveBatch, entry.player, entry.args)
        if not ok then
            print("[TienSkillMastery] deft transfer failed: " .. tostring(err))
            reply(entry.player, entry.token, DT.parseIds(entry.args.items))
        end
    end
end)

Events.OnClientCommand.Add(function(module, command, player, args)
    if module ~= M.MODULE or not player then return end
    if command == DT.COMMAND then
        onRequest(player, type(args) == "table" and args or {})
    elseif command == DT.CANCEL then
        onCancel(player, type(args) == "table" and args or {})
    end
end)
