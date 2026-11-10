--[[
Tien's Skill Mastery: Stealth's signature Distraction Throw (user, 2026-11-11). In combat stance, its own key (default
K, Options > Key bindings; it may be bound to the same key as Tomahawk / Javelin) lobs the junk item held in hand
toward the pointer, up to 15 tiles (Guns of Marz's grenade `maxThrowDist`), on a grenade-like arc. Where it lands it
makes a noise by material that draws zombies (those already chasing someone keep their target: a zombie with a
target follows it), and a glass item breaks into broken glass.

What can be thrown (`D.groupOf`, from the item script, so modded items with the same tags join; user: only what makes
sense, shown as "Throwable" in a master's tooltips): up to 1.0 weight, never a weapon, clothing, bag or book,
- glass: tag `base:glass` (bottles full or empty, jars, drinking glasses, glass panes),
- metal: tag `base:emptycan` / `base:tincan` (cans), or `base:hasmetal` / `base:smeltableironsmall` in the
  "Material" display category (scrap, chunks, pieces, nails, nuts and bolts; the tags alone also cover ~200 tools,
  electronics and keepsakes),
- stone: tag `base:stone` or `base:flintpiece`, bricks and stone blocks.
Always the item in hand (primary, else the off hand; user), never from the inventory.

Flight: lobbed at D.SPEED tiles a second along the ground; height = hand height falling to 0 at the aimed point plus
a parabola peaking at distance x D.ARC (Gunworks' default `arcFactor` 0.12), capped under a roof. Resolved on the
server (single player: locally) in 0.2-tile steps through the axe throw's `Th.blocked` (walls, closed doors and
windows stop it; a low fence is cleared while the arc is above it); it flies over characters. It lands where the
aim was or where it was stopped, after the flight time (distance / speed).

Landing (42.21): glass: `square:addBrokenGlass()` (only on a free square; the server transmits it itself) and the
item is gone; others: `square:AddWorldInventoryItem` (the server sends it). The noise: the Lua global
`addSound(nil, x, y, z, radius, volume)` = `WorldSoundManager.addSound(...)`, no source, made on the server and sent
by it to the clients, which run most zombies. Players hear the group's sound at the spot (`getFreeEmitter` +
`playSoundImpl`, as the axe throw's hits; the server broadcasts it): vanilla's `BreakGlassItem`, `BreakMetalItem`
(a placeholder until the user picks a metal sound), and for stones the item's own `DropSound` (`StoneDrop` for
stones) or `StoneDrop`. Sounds and radii are the table D.GROUPS.

The throw is the axe throw's action animation (`TsmThrowAxe`, vanilla's Molotov throw clip with a release event),
a short client-only action; at the release the client sends `distractThrow { id, tx, ty }`, and the server checks the
item is still in that player's hand with that ID and throwable, and that the player has the signature.
]]

require "TimedActions/ISBaseTimedAction"
require "TienSkillMastery"
require "TienSkillMastery_Throw"
local M = TienSkillMastery
local Th = M.Throw

local D = {}
M.Distraction = D

D.SIG = "Stealth.SigDistraction"
D.KEY_NAME = "TsmDistractionThrow"
D.RANGE = 15          -- tiles (Guns of Marz grenades)
D.SPEED = 9           -- tiles a second along the ground
D.ARC = 0.12          -- peak above the straight line, x the distance (Gunworks' default arcFactor)
D.ARC_ROOFED = 0.6    -- highest peak (levels) when the thrower or the aimed square is under a roof
D.MAX_WEIGHT = 1.0
D.STEP = 0.2
D.GROUPS = {
    glass = { sound = "BreakGlassItem", noise = 20, breaks = true },
    metal = { sound = "BreakMetalItem", noise = 15 },
    stone = { sound = "StoneDrop", noise = 10, ownDrop = true },
}
D.EXTRA_STONES = { ["Base.ClayBrick"] = true, ["Base.ClayBrickUnfired"] = true, ["Base.StoneBlock"] = true }

-- ---------------------------------------------------------------------------------------------------------------
-- What can be thrown
-- ---------------------------------------------------------------------------------------------------------------

local groups = {}   -- [full type] = group name or false

local function tagSet(script)
    local set = {}
    pcall(function()
        local it = script:getTags():iterator()
        while it:hasNext() do set[tostring(it:next())] = true end
    end)
    return set
end

local function scriptGroup(fullType, script)
    local okW, w = pcall(function() return script:getActualWeight() end)
    if not okW or type(w) ~= "number" or w > D.MAX_WEIGHT then return false end
    local tags = tagSet(script)
    if tags["base:glass"] then return "glass" end
    if tags["base:emptycan"] or tags["base:tincan"] then return "metal" end
    if tags["base:hasmetal"] or tags["base:smeltableironsmall"] then
        local ok, cat = pcall(function() return script:getDisplayCategory() end)
        if ok and cat == "Material" then return "metal" end
    end
    if tags["base:stone"] or tags["base:flintpiece"] or D.EXTRA_STONES[fullType] then return "stone" end
    return false
end

--- "glass", "metal", "stone", or nil when the item cannot be thrown.
function D.groupOf(item)
    if not item or not instanceof(item, "InventoryItem") then return nil end
    if instanceof(item, "HandWeapon") or instanceof(item, "Clothing") or instanceof(item, "InventoryContainer")
        or instanceof(item, "Literature") then
        return nil
    end
    local fullType = item:getFullType()
    local g = groups[fullType]
    if g == nil then
        local script = item:getScriptItem()
        g = script and scriptGroup(fullType, script) or false
        groups[fullType] = g
    end
    return g or nil
end

function D.canThrow(player, item)
    return player ~= nil and item ~= nil and D.groupOf(item) ~= nil and M.sig(player, D.SIG)
end

--- The throwable item in hand: the primary hand's, else the off hand's.
function D.held(player)
    local p = player:getPrimaryHandItem()
    if p and D.canThrow(player, p) then return p end
    local s = player:getSecondaryHandItem()
    if s and D.canThrow(player, s) then return s end
    return nil
end

-- ---------------------------------------------------------------------------------------------------------------
-- The arc
-- ---------------------------------------------------------------------------------------------------------------

local function roofed(square)
    if not square then return false end
    local ok, outside = pcall(function() return square:isOutside() end)
    return ok and outside == false
end

--- Peak height (levels) above the straight line for a throw of `d` tiles.
function D.peakFor(d, roof)
    local peak = d * D.ARC
    if roof then peak = math.min(peak, D.ARC_ROOFED) end
    return peak
end

--- Height above the floor after `s` tiles of a throw aimed `d` tiles away with that peak.
function D.heightAt(s, d, peak)
    local u = math.max(0, math.min(1, s / math.max(d, 0.5)))
    return Th.HAND_HEIGHT * (1 - u) + 4 * peak * u * (1 - u)
end

--- Flies toward (tx, ty): returns endX, endY, distance flown, aimed distance, peak.
function D.fly(player, tx, ty)
    local x, y, z = player:getX(), player:getY(), player:getZ()
    local dx, dy = tx - x, ty - y
    local d = math.sqrt(dx * dx + dy * dy)
    if d < 0.001 then return x, y, 0, 0, 0 end
    dx, dy = dx / d, dy / d
    local cell = getCell()
    local square = player:getCurrentSquare()
    local target = cell:getGridSquare(math.floor(tx), math.floor(ty), math.floor(z))
    local peak = D.peakFor(d, roofed(square) or roofed(target))
    local travelled = 0
    while travelled < d do
        local step = math.min(D.STEP, d - travelled)
        local nx, ny = x + dx * step, y + dy * step
        local nextSq = cell:getGridSquare(math.floor(nx), math.floor(ny), math.floor(z))
        local h = D.heightAt(travelled + step, d, peak)
        if not nextSq or Th.blocked(square, nextSq, h) then return x, y, travelled, d, peak end
        x, y, square = nx, ny, nextSq
        travelled = travelled + step
    end
    return x, y, travelled, d, peak
end

-- ---------------------------------------------------------------------------------------------------------------
-- Server / single player: the throw and the landing
-- ---------------------------------------------------------------------------------------------------------------

D.inFlight = D.inFlight or {}

function D.resolve(player, itemId, tx, ty)
    if not player or player:isDead() or not itemId then return false end
    local item
    local p, s = player:getPrimaryHandItem(), player:getSecondaryHandItem()
    if p and p:getID() == itemId then item = p elseif s and s:getID() == itemId then item = s end
    if not item or not D.canThrow(player, item) then return false end
    tx, ty = tonumber(tx), tonumber(ty)
    if not tx or not ty then return false end
    local fromX, fromY, z = player:getX(), player:getY(), player:getZ()
    local dx, dy = tx - fromX, ty - fromY
    local d = math.sqrt(dx * dx + dy * dy)
    if d < 0.5 then return false end
    if d > D.RANGE then tx, ty = fromX + dx / d * D.RANGE, fromY + dy / d * D.RANGE end
    local group = D.groupOf(item)

    local endX, endY, travelled, aimed, peak = D.fly(player, tx, ty)

    if player:getSecondaryHandItem() == item then player:setSecondaryHandItem(nil) end
    if player:getPrimaryHandItem() == item then player:setPrimaryHandItem(nil) end
    if item:getAttachedSlot() > -1 then
        player:removeAttachedItem(item)
        item:setAttachedSlot(-1)
        item:setAttachedSlotType(nil)
        item:setAttachedToModel(nil)
    end
    local container = item:getContainer()
    if container then
        container:DoRemoveItem(item)
        if isServer() then sendRemoveItemFromContainer(container, item) end
    end

    table.insert(D.inFlight, { item = item, group = group, x = endX, y = endY, z = z, player = player,
        at = getTimestampMs() + math.max(80, travelled / D.SPEED * 1000) })

    local fly = { type = item:getFullType(), fx = fromX, fy = fromY, z = z, tx = endX, ty = endY,
        travelled = travelled, aimed = aimed, peak = peak }
    if isServer() then
        sendServerCommand(M.MODULE, "distractFly", fly)
    elseif D.showFlight then
        D.showFlight(fly)
    end
    return true
end

--- The sound players hear where it lands.
function D.landSound(item, group)
    local g = D.GROUPS[group]
    if not g then return nil end
    if g.ownDrop then
        local ok, own = pcall(function() return item:getDropSound() end)
        if ok and type(own) == "string" and own ~= "" then return own end
    end
    return g.sound
end

function D.land(f)
    local g = D.GROUPS[f.group] or D.GROUPS.stone
    local square = getCell():getGridSquare(math.floor(f.x), math.floor(f.y), math.floor(f.z))
        or (f.player and f.player:getCurrentSquare())
    if not square then return end
    local sound = D.landSound(f.item, f.group)
    if g.breaks then
        square:addBrokenGlass()
    else
        square:AddWorldInventoryItem(f.item, f.x - square:getX(), f.y - square:getY(), 0)
    end
    addSound(nil, square:getX(), square:getY(), square:getZ(), g.noise, g.noise)
    local data = { x = f.x, y = f.y, z = f.z, sound = sound }
    if isServer() then
        sendServerCommand(M.MODULE, "distractLand", data)
    elseif D.playLand then
        D.playLand(data)
    end
end

if not isClient() then
    Events.OnTick.Add(function()
        if #D.inFlight == 0 then return end
        local now = getTimestampMs()
        for i = #D.inFlight, 1, -1 do
            local f = D.inFlight[i]
            if now >= f.at then
                table.remove(D.inFlight, i)
                local ok, err = pcall(D.land, f)
                if not ok then print("[TienSkillMastery] distraction landing failed: " .. tostring(err)) end
            end
        end
    end)
end

if isServer() then
    Events.OnClientCommand.Add(function(module, command, player, args)
        if module ~= M.MODULE or command ~= "distractThrow" or type(args) ~= "table" or not player then return end
        D.resolve(player, tonumber(args.id), args.tx, args.ty)
    end)
end

-- ---------------------------------------------------------------------------------------------------------------
-- Client: key, action, flight and sound
-- ---------------------------------------------------------------------------------------------------------------

if isServer() then return end

local flights = {}

function D.showFlight(args)
    local item = instanceItem(args.type)
    if not item then return end
    local fx, fy, tx, ty = tonumber(args.fx), tonumber(args.fy), tonumber(args.tx), tonumber(args.ty)
    if not fx or not fy or not tx or not ty then return end
    local travelled = tonumber(args.travelled) or 0
    table.insert(flights, { item = item, fx = fx, fy = fy, z = tonumber(args.z) or 0, tx = tx, ty = ty,
        travelled = travelled, aimed = tonumber(args.aimed) or travelled, peak = tonumber(args.peak) or 0,
        start = getTimestampMs(), duration = math.max(80, travelled / D.SPEED * 1000),
        angle = math.deg(math.atan2(ty - fy, tx - fx)) })
end

function D.playLand(args)
    local sound = args.sound
    local x, y, z = tonumber(args.x), tonumber(args.y), tonumber(args.z)
    if type(sound) ~= "string" or sound == "" or not x or not y or not z then return end
    local emitter = getWorld():getFreeEmitter(x, y, z)
    if emitter then emitter:playSoundImpl(sound, false, nil) end
end

Events.OnServerCommand.Add(function(module, command, args)
    if module ~= M.MODULE or type(args) ~= "table" then return end
    if command == "distractFly" then
        D.showFlight(args)
    elseif command == "distractLand" then
        local ok, err = pcall(D.playLand, args)
        if not ok then print("[TienSkillMastery] distraction sound failed: " .. tostring(err)) end
    end
end)

Events.RenderOpaqueObjectsInWorld.Add(function()
    if #flights == 0 then return end
    local now = getTimestampMs()
    for i = #flights, 1, -1 do
        local f = flights[i]
        local t = (now - f.start) / f.duration
        if t >= 1 then
            table.remove(flights, i)
        else
            local s = f.travelled * t
            local u = f.travelled > 0 and s / f.travelled or 0
            local x, y = f.fx + (f.tx - f.fx) * u, f.fy + (f.ty - f.fy) * u
            local square = getCell():getGridSquare(math.floor(x), math.floor(y), math.floor(f.z))
            if square then
                local h = math.max(0.02, D.heightAt(s, f.aimed, f.peak))
                local rot = f.angle + (now - f.start) * 0.6
                rot = rot - math.floor(rot / 360) * 360
                pcall(Render3DItem, f.item, square, x, y, f.z + h, rot)
            end
        end
    end
end)

TienSkillMasteryDistractionAction = ISBaseTimedAction:derive("TienSkillMasteryDistractionAction")
local DA = TienSkillMasteryDistractionAction
D.THROW_TIME = 45
D.RELEASE_AT = 0.6

function DA:isValid()
    return self.item == self.character:getPrimaryHandItem() or self.item == self.character:getSecondaryHandItem()
end

function DA:waitToStart()
    self.character:faceLocationF(self.tx, self.ty)
    return self.character:shouldBeTurning()
end

function DA:start()
    -- Shown in the throwing hand (the right one), also when it was held in the off hand.
    self:setOverrideHandModels(self.item, nil)
    self:setActionAnim("TsmThrowAxe")
end

function DA:release()
    if self.released then return end
    self.released = true
    if isClient() then
        sendClientCommand(self.character, M.MODULE, "distractThrow", { id = self.item:getID(), tx = self.tx, ty = self.ty })
    else
        D.resolve(self.character, self.item:getID(), self.tx, self.ty)
    end
end

function DA:update()
    if not self.released and self:getJobDelta() >= D.RELEASE_AT then self:release() end
end

function DA:animEvent(event)
    if event == "TsmThrowRelease" then self:release() end
end

function DA:perform()
    self:release()
    ISBaseTimedAction.perform(self)
end

function DA:new(character, item, tx, ty)
    local o = ISBaseTimedAction.new(self, character)
    o.item = item
    o.tx, o.ty = tx, ty
    o.stopOnWalk = false
    o.stopOnRun = true
    o.stopOnAim = false
    o.maxTime = D.THROW_TIME
    o.useProgressBar = false
    return o
end

-- Attacks are banned while the key is down or a throw is queued, so a key shared with vanilla's Melee (Space) does
-- not also shove (the axe throw does the same, see `holdAttacks` in Throw.lua).
local banned = {}

local function ban(player, key)
    if not banned[player] then banned[player] = { was = player:isBannedAttacking() } end
    banned[player].key = key
    player:setBannedAttacking(true)
end

--- True when this key press is a Distraction Throw (the axe throw then leaves it alone).
function D.claims(player, key)
    return getCore():isKey(D.KEY_NAME, key) and player:isAiming() and not player:getVehicle()
        and D.held(player) ~= nil
end

function D.throwKey(player, key)
    if not player or player:isDead() or player:getVehicle() or player:getJoypadBind() ~= -1 then return end
    if ISTimedActionQueue.hasActionType(player, "TienSkillMasteryDistractionAction") then
        ban(player, key)
        return
    end
    if not player:isAiming() then return end
    local item = D.held(player)
    if not item then return end
    local tx, ty = Th.aimPoint(player)
    if not tx then return end
    local dx, dy = tx - player:getX(), ty - player:getY()
    local d = math.sqrt(dx * dx + dy * dy)
    if d < 0.5 then return end
    if d > D.RANGE then tx, ty = player:getX() + dx / d * D.RANGE, player:getY() + dy / d * D.RANGE end
    ban(player, key)
    ISTimedActionQueue.add(TienSkillMasteryDistractionAction:new(player, item, tx, ty))
end

Events.OnTick.Add(function()
    for player, b in pairs(banned) do
        if player:isDead() or (not isKeyDown(b.key)
            and not ISTimedActionQueue.hasActionType(player, "TienSkillMasteryDistractionAction")) then
            banned[player] = nil
            player:setBannedAttacking(b.was)
        end
    end
end)

if keyBinding then
    table.insert(keyBinding, { value = D.KEY_NAME, key = Keyboard.KEY_K })
end

Events.OnKeyStartPressed.Add(function(key)
    if not getCore():isKey(D.KEY_NAME, key) then return end
    local player = getSpecificPlayer(0)
    if player then D.throwKey(player, key) end
end)
