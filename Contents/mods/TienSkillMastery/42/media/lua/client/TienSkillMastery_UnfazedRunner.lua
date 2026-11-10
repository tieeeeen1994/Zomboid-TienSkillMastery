--[[
Tien's Skill Mastery: Freerunning's signature Unfazed Runner (user, 2026-11-10; "Tree Runner" until the same day):
the master never trips. Sprinting into trees or a hedge only turns the sprint into a run (the branches still scratch
and tear, user), and running or sprinting into a zombie, an animal or another player plays the bump (the stagger)
but never the fall. Owner's game only: in multiplayer the player's own client moves it and decides both.

Trees (42.21 `IsoPlayer.updateInternal2`): the input is read (~2380: `setSprinting(inputState.sprinting)`, which
needs `isAllowSprint()`), then (~2712) a player `isInTrees()` (or on a collapsed fence, or slow / injured) who
`isSprinting()` drops to a run, and on an `isInTreesNoBush()` square (a tree bigger than a bush, or a HedgeLow /
HedgeHigh square) or a collapsed fence also gets `BumpFall` with `TripObstacleType` "tree" and the `wasBumped` event:
the trip. Bushes only drop the sprint. `isSprinting()` reads `canSprint()` live, false while `isAllowSprint()` is
false; nothing in Java sets `allowSprint` (vanilla Lua only in the tutorial). `OnPlayerUpdate` fires at ~2296, before
both, so sprinting is not allowed for an update that starts on, or half a tile from, such a square. Collapsed fences
still trip.

Characters (`IsoMovingObject.separate` ~1221, called at ~2698 of the same `updateInternal2`, after the event; the
action state is only entered in `postupdate`, after every object's update, with no Lua event in between, so a
`BumpFall` cannot be cleared once set). A moving player touching a solid character it has not just bumped
(`getBumpedChr() != obj`) gets the bump: bump type left / right, `setBumpedChr`, `setLastBump(now)`, and the bumped
state plays the stagger (left.xml / right.xml; it is entered on the `bumped` variable, a non-empty bump type). The
fall is decided by `wasBumped` = not on the floor and (`getBumpedChr()` already set, or the last bump under 1.5 s
ago, or `isSprinting()`): then `BumpFall` on a 1 in 1..80 roll (Fitness, Strength, traits, drunk, back pain), and
always when sprinting. `BumpedState.enter` stores `BumpFall` in the state's network params (other games show the
fall from them) and its exit costs the knees (`fallenOnKnees`). So `wasBumped` is kept false for every bump:
`setLastBump(0)` each update (nothing else reads it), sprint held off while a solid character is within touching
reach, a leftover `bumpedChr` (Street Fighting's Battering Ram sets one to shield a zombie) cleared then, and while
a stagger plays (`isBumped()` with a `bumpedChr`) every other character in reach is made not solid for that update
(`isSolidForSeparate`), so walking into a second one cannot turn it into a fall. Zombies set `solid` again in their
own update; players and animals do not, so this file puts back every one it changed once it is out of reach or
the stagger is over. Battering Ram runs first (Movement.lua loads before this file), and zombies it made not solid
are not bumped at all.
]]

require "TienSkillMastery"
local M = TienSkillMastery

local ID = "Freerunning.SigUnfazedRunner"
local AHEAD = 0.5      -- tiles along the facing looked at for a tree square
local CONTACT = 0.75   -- tiles: a solid character this close can be bumped this update (vanilla contact ~0.5)

local held = setmetatable({}, { __mode = "k" })   -- [player] = true while this file holds sprint off
local unsolid = {}                                 -- [player or animal] = true while made not solid here

-- ---------------------------------------------------------------------------------------------------------------
-- Trees
-- ---------------------------------------------------------------------------------------------------------------

--- `IsoGameCharacter.isInTrees2(true)` for a square: a tree bigger than a bush, or a hedge.
local function treeSquare(square)
    if not square then return false end
    if square:has(IsoObjectType.tree) then
        local tree = square:getTree()
        if not tree or tree:getSize() > 2 then return true end
    end
    local movement = square:getProperties():get("Movement")
    if movement then
        movement = string.lower(movement)
        return movement == "hedgelow" or movement == "hedgehigh"
    end
    return false
end

local function amongTrees(player)
    if treeSquare(player:getCurrentSquare()) then return true end
    local dir = player:getForwardDirection()
    local cell = getCell()
    if not dir or not cell then return false end
    local ahead = cell:getGridSquare(math.floor(player:getX() + dir:getX() * AHEAD),
        math.floor(player:getY() + dir:getY() * AHEAD), math.floor(player:getZ()))
    return treeSquare(ahead)
end

-- ---------------------------------------------------------------------------------------------------------------
-- Characters
-- ---------------------------------------------------------------------------------------------------------------

--- Standing characters on the player's square and the 8 round it (what `separate` looks at) within `reach`.
local function nearby(player, reach)
    local found = {}
    local square = player:getCurrentSquare()
    local cell = getCell()
    if not square or not cell then return found end
    local px, py, pz = player:getX(), player:getY(), player:getZ()
    for dx = -1, 1 do
        for dy = -1, 1 do
            local sq = cell:getGridSquare(square:getX() + dx, square:getY() + dy, square:getZ())
            if sq then
                local objects = sq:getMovingObjects()
                for i = 0, objects:size() - 1 do
                    local o = objects:get(i)
                    if o ~= player and instanceof(o, "IsoGameCharacter") and not o:isDead() and not o:isOnFloor()
                        and math.abs(o:getZ() - pz) <= 0.3
                        and not (instanceof(o, "IsoZombie") and o:isReanimatedForGrappleOnly()) then
                        local ox, oy = o:getX() - px, o:getY() - py
                        if ox * ox + oy * oy <= reach * reach then table.insert(found, o) end
                    end
                end
            end
        end
    end
    return found
end

local function restoreSolid(keep)
    local back = {}
    for c in pairs(unsolid) do
        if not keep or not keep[c] then table.insert(back, c) end
    end
    for _, c in ipairs(back) do
        pcall(function() c:setSolid(true) end)
        unsolid[c] = nil
    end
end

local function holdSprint(player, hold)
    if hold then
        if not held[player] and player:isAllowSprint() then
            player:setAllowSprint(false)
            held[player] = true
        end
    elseif held[player] then
        player:setAllowSprint(true)
        held[player] = nil
    end
end

Events.OnPlayerUpdate.Add(function(player)
    if not player or not player:isLocalPlayer() then return end
    if player:isDead() or not M.sig(player, ID) then
        holdSprint(player, false)
        restoreSolid(nil)
        return
    end
    -- A bump more than 1.5 s after the last one is not a repeat.
    player:setLastBump(0)

    local near = nearby(player, CONTACT)
    local stumbling = player:isBumped() and player:getBumpedChr() or nil
    local keep = {}
    if stumbling then
        -- While the stagger plays, nobody else can be bumped into.
        for _, o in ipairs(near) do
            if o ~= stumbling and (o:isSolid() or unsolid[o]) then
                o:setSolid(false)
                if not instanceof(o, "IsoZombie") then
                    unsolid[o] = true
                    keep[o] = true
                end
            end
        end
    end
    restoreSolid(keep)

    local bumping = false
    if not stumbling then
        for _, o in ipairs(near) do
            if o:isSolid() then
                bumping = true
                break
            end
        end
        if bumping and player:getBumpedChr() then player:setBumpedChr(nil) end
    end
    holdSprint(player, bumping or amongTrees(player))
end)
