--[[
Tien's Skill Mastery: Deft Hands for item transfers (user, 2026-11-08), shared part. Addressing containers over the
wire, vanilla's transfer length and the reach check, ported from Zomboid Fixes B42 (its shared ZomboidFixesB42.lua,
"Encoding" and "Floor hints"; both mods can be loaded together, each keeps its own copy).

Why a transfer needs its own path (42.21): in multiplayer an item transfer is not a Lua timed action on the server.
The client opens an item transaction (`createItemTransaction`); the server's Java `Transaction` fixes its end at
`getDuration()` real ms (20 per unit, the formula below) and moves the items then; the client's bar waits for its
Done. Nothing in it reads Lua, so Deft Hands' `adjustMaxTime` cut (TienSkillMastery_Signatures.lua) cannot reach it,
and in single player only the first batch of a transfer goes through `adjustMaxTime` (later batches take their time
straight from the queue). So for a master the client sends each batch to the server as a request instead
(client/TienSkillMastery_DeftTransfer.lua), and the server waits vanilla's length cut by the signature and moves
the items itself (server/TienSkillMastery_DeftTransfer.lua). Containers that cannot be addressed (corpses) keep
vanilla's transaction.
]]

require "TienSkillMastery"
local M = TienSkillMastery

local DT = {}
M.DeftTransfer = DT

DT.COMMAND = "deftTransfer"
DT.CANCEL = "deftTransferCancel"
DT.REPLY = "deftTransferDone"
DT.MS_PER_UNIT = 20            -- a timed action unit is 20 ms of real time on a server
DT.MAX_REACH = 8               -- generous: only stops a tampered client reaching across the map
DT.FLOOR_HINT_REACH = 2
DT.MAX_ITEMS = 250
DT.FLOOR = "f"
local SEP = "|"

--- Share of a transfer's length a master saves (the signature's percent), 0 without it.
function DT.cut(chr)
    return chr and math.min(95, M.val(chr, "Handicraft.SigDeftHands")) or 0
end

--- Vanilla's length for moving one item, in units (Java `Transaction.getDuration`, the same formula as
--- `ISInventoryTransferAction:new`); a batch takes as long as its slowest item.
function DT.transferUnits(player, item, src, dst)
    if not src or not dst or dst:getType() == "TradeUI" or src:getType() == "TradeUI" then return 0 end
    local units = 120
    local capacityDelta = 1
    local inventory = player:getInventory()
    if src == inventory then
        if dst:isInCharacterInventory(player) then
            local max = dst:getMaxWeight()
            if max > 0 then capacityDelta = dst:getCapacityWeight() / max end
        else
            units = 50
        end
    elseif not src:isInCharacterInventory(player) and dst:isInCharacterInventory(player) then
        units = 50
    end
    if capacityDelta < 0.4 then capacityDelta = 0.4 end
    if item then units = units * math.min(item:getActualWeight(), 3) * capacityDelta end
    if getCore():getGameMode() == "LastStand" then units = units * 0.3 end
    if dst:getType() == "floor" then
        if src == inventory then
            units = units * 0.1
        elseif not src:isInCharacterInventory(player) then
            units = units * 0.2
        end
    end
    if player:hasTrait(CharacterTrait.DEXTROUS) then units = units * 0.5 end
    if player:hasTrait(CharacterTrait.ALL_THUMBS) or player:isWearingAwkwardGloves() then units = units * 2 end
    return units
end

--[[ Encoding (as Zomboid Fixes B42's):
    p                                 the player's own main inventory
    i|<itemID>                        a bag the player is carrying, at any depth
    g|<itemID>                        a bag lying on the ground next to the player
    n|<itemID>|<encoded container>    a bag inside another container (crate, trunk, a bag in either)
    v|<vehicleID>|<partID>            a vehicle part container
    w|<x>|<y>|<z>|<obj>|<con>|<type>  a world object's container (object index, container index, type)
    f                                 the floor (resolved per item: where it lies, or a square with room)
  Anything else (corpses) is nil, and the transfer stays vanilla's. ]]

function DT.encodeContainer(container, character)
    if not container or not character then return nil end
    if container == character:getInventory() then return "p" end
    if container:getType() == "floor" then return DT.FLOOR end
    local holder = container:getContainingItem()
    if holder then
        local id = tostring(holder:getID())
        if container:isInCharacterInventory(character) then return "i" .. SEP .. id end
        if holder:getWorldItem() then return "g" .. SEP .. id end
        local outer = holder:getContainer()
        local outerEncoded = outer and outer ~= container and DT.encodeContainer(outer, character)
        if not outerEncoded or outerEncoded == DT.FLOOR then return nil end
        return "n" .. SEP .. id .. SEP .. outerEncoded
    end
    local parent = container:getParent()
    if parent and instanceof(parent, "BaseVehicle") then
        return "v" .. SEP .. tostring(parent:getId()) .. SEP .. container:getType()
    end
    local square = container:getSourceGrid() or (parent and parent:getSquare())
    if not parent or not square then return nil end
    local containerIndex = parent:getContainerIndex(container)
    if containerIndex < 0 then return nil end
    local objects = square:getObjects()
    for i = 0, objects:size() - 1 do
        if objects:get(i) == parent then
            return table.concat({ "w", square:getX(), square:getY(), square:getZ(), i, containerIndex, container:getType() }, SEP)
        end
    end
    return nil
end

local function findItemById(container, id, depth)
    if not container or depth > 10 then return nil end
    local items = container:getItems()
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if item:getID() == id then return item end
        if instanceof(item, "InventoryContainer") then
            local found = findItemById(item:getInventory(), id, depth + 1)
            if found then return found end
        end
    end
    return nil
end

--- An item on the ground within arm's reach (the 3x3 around the player), and its square.
function DT.findItemOnGround(player, itemId)
    local cell = getCell()
    local px, py, pz = math.floor(player:getX()), math.floor(player:getY()), math.floor(player:getZ())
    for dx = -1, 1 do
        for dy = -1, 1 do
            local square = cell:getGridSquare(px + dx, py + dy, pz)
            local worldObjects = square and square:getWorldObjects()
            if worldObjects then
                for i = 0, worldObjects:size() - 1 do
                    local item = worldObjects:get(i):getItem()
                    if item and item:getID() == itemId then return item, square end
                end
            end
        end
    end
    return nil
end

--- "id|x|y|z;..." for the items lying on the floor (the client names the square; the server's copy of the player's
--- position trails the client's while walking, so the 3x3 around it can miss the far edge the client shows).
function DT.encodeFloorHints(items)
    local parts = {}
    for _, item in ipairs(items or {}) do
        local worldItem = item and item:getWorldItem()
        local square = worldItem and worldItem:getSquare()
        if square then
            parts[#parts + 1] = table.concat({ item:getID(), square:getX(), square:getY(), square:getZ() }, SEP)
        end
    end
    return table.concat(parts, ";")
end

function DT.parseFloorHints(encoded)
    local hints = {}
    if type(encoded) ~= "string" then return hints end
    local count = 0
    for entry in string.gmatch(encoded, "([^;]+)") do
        local id, x, y, z = string.match(entry, "^(-?%d+)|(-?%d+)|(-?%d+)|(-?%d+)$")
        if id then
            hints[tonumber(id)] = { x = tonumber(x), y = tonumber(y), z = tonumber(z) }
            count = count + 1
            if count >= DT.MAX_ITEMS then break end
        end
    end
    return hints
end

function DT.findItemOnGroundNear(player, itemId, hint)
    if hint then
        local px, py, pz = math.floor(player:getX()), math.floor(player:getY()), math.floor(player:getZ())
        if hint.z == pz and math.abs(hint.x - px) <= DT.FLOOR_HINT_REACH and math.abs(hint.y - py) <= DT.FLOOR_HINT_REACH then
            local square = getCell():getGridSquare(hint.x, hint.y, hint.z)
            local worldObjects = square and square:getWorldObjects()
            if worldObjects then
                for i = 0, worldObjects:size() - 1 do
                    local item = worldObjects:get(i):getItem()
                    if item and item:getID() == itemId then return item, square end
                end
            end
        end
    end
    return DT.findItemOnGround(player, itemId)
end

function DT.parseIds(encoded)
    local ids = {}
    if type(encoded) ~= "string" then return ids end
    for field in string.gmatch(encoded, "([^,]+)") do
        local id = tonumber(field)
        if id then
            ids[#ids + 1] = id
            if #ids >= DT.MAX_ITEMS then break end
        end
    end
    return ids
end

--- An encoded container back to a real one (nil for the floor marker: the caller resolves the floor per item).
function DT.decodeContainer(encoded, player)
    if type(encoded) ~= "string" or not player or encoded == DT.FLOOR then return nil end
    local parts = {}
    for field in string.gmatch(encoded, "([^" .. SEP .. "]+)") do parts[#parts + 1] = field end
    local kind = parts[1]
    if kind == "p" then return player:getInventory() end
    if kind == "i" or kind == "g" or kind == "n" then
        local id = tonumber(parts[2]) or -1
        local holder
        if kind == "i" then
            holder = findItemById(player:getInventory(), id, 0)
        elseif kind == "g" then
            holder = DT.findItemOnGround(player, id)
        else
            local outer = DT.decodeContainer(string.match(encoded, "^n|[^|]*|(.+)$"), player)
            holder = outer and outer:getItemWithID(id)
        end
        if not holder or not instanceof(holder, "InventoryContainer") then return nil end
        return holder:getInventory()
    end
    if kind == "v" then
        local vehicle = getVehicleById(tonumber(parts[2]) or -1)
        local part = vehicle and vehicle:getPartById(parts[3])
        return part and part:getItemContainer() or nil
    end
    if kind == "w" then
        local square = getCell():getGridSquare(tonumber(parts[2]), tonumber(parts[3]), tonumber(parts[4]))
        if not square then return nil end
        local objects = square:getObjects()
        local index = tonumber(parts[5]) or -1
        local containerIndex = tonumber(parts[6]) or -1
        local containerType = parts[7]
        local function containerOn(object)
            if not object or containerIndex < 0 or containerIndex >= object:getContainerCount() then return nil end
            local found = object:getContainerByIndex(containerIndex)
            if found and containerType and found:getType() ~= containerType then return nil end
            return found
        end
        if index >= 0 and index < objects:size() then
            local found = containerOn(objects:get(index))
            if found then return found end
        end
        -- The square's object order may differ between client and server: look for the container by type.
        if containerType then
            for i = 0, objects:size() - 1 do
                local found = containerOn(objects:get(i))
                if found then return found end
            end
        end
    end
    return nil
end

local function containerPosition(container, depth)
    local parent = container:getParent()
    if parent then return parent:getX(), parent:getY(), parent:getZ() end
    local square = container:getSourceGrid()
    if square then return square:getX(), square:getY(), square:getZ() end
    local holder = container:getContainingItem()
    if holder then
        local worldItem = holder:getWorldItem()
        if worldItem then return worldItem:getX(), worldItem:getY(), worldItem:getZ() end
        local outer = holder:getContainer()
        depth = depth or 0
        if outer and outer ~= container and depth < 10 then return containerPosition(outer, depth + 1) end
    end
    return nil
end

--- Within MAX_REACH flat and under one level up or down; carried containers have no position and are fine.
function DT.isContainerInReach(player, container)
    local x, y, z = containerPosition(container)
    if not x then return true end
    if z and math.abs(z - player:getZ()) >= 1 then return false end
    local dx, dy = player:getX() - x, player:getY() - y
    return (dx * dx + dy * dy) <= DT.MAX_REACH * DT.MAX_REACH
end
