--[[
Tien's Skill Mastery: Stealth's Lose Them and Unseen signatures (user, 2026-11-11). Traced in the 42.22.2 Java
(decompiled, and the user's pzopt copy of `IsoZombie.spottedNew`, which keeps the same early outs).

- Lose Them: a zombie chasing a crouched master that has had no sight of the master for 3 s gives up: it forgets the
  master and stands where it is (then wanders the vanilla way, and can spot the master again like anyone else).
- Unseen: while a master is crouched and still (0.5 s without moving), a zombie that was not already after the master
  does not notice them: one that spots the master forgets it at once and walks on (to where it was walking, else a
  few tiles away from the master). Zombies that were already after the master when they stopped keep chasing.

How a zombie spots a player (42.22 `IsoZombie.spottedNew`, from `IsoPlayer.updateLOS` → `TestZombieSpotPlayer`):
every update, each **local** player tests every object on a square it could see (`isCouldSee(playerIndex)`, or the
zombie's head square). The roll only counts on the zombie's owner (`spottedNew` returns at once for a remote zombie),
so in multiplayer a zombie owned by another client spots this player through the server: the server runs the same
`updateLOS` for each remote player (`ServerLOS`) and either rolls on its copy or, when the player leads the zombie's
aggro list, sends `ZombieControl` to the owner, which sets the target. In multiplayer a success only counts while the
zombie is idle, eating, sitting or turning (`NetworkZombieManager.canSpotted`), so walking zombies never pick up a new
target there. A success sets `bonusSpotTime = 720`: for that long (about 15 s) every update calls
`spotted(spottedLast, true)`, a forced spot that tracks the target through walls, and later rolls are x5.
`timeSinceSeenFlesh` passes the sandbox Memory (500 to 1250 units) before vanilla drops the target by itself.
None of those fields has a getter or setter; `setTarget(nil)` alone comes back on the next forced spot.
The way to clear both target and `spottedLast` from Lua: `setUseless(true)`, `spotted(master, true)`, put the useless
flag back. `spottedNew` and `spottedOld` both start with `if (isUseless()) { setTarget(null); spottedLast = null; }`
(after the remote-zombie and missing-square checks), and nothing else reads the flag in between.
After that the zombie may still be walking a path to the master (`PathFindBehavior2` goal = the character), so it is
put in `ZombieIdleState` (exposed; `PathFindState.exit` cancels the path request and resets `allowRepathDelay`), and
only from states where that is safe (`getCurrentStateName()`: idle, path finding, walking, lunging, thumping, turning,
eating, sitting; never mid-attack, climbing, staggering or on the ground: tried again on the next pass).
`pathToLocation(int)` (`IsoGameCharacter`, not gated by `allowRepathDelay` like the zombie's `pathToLocationF`)
starts the walk on.

Who decides and who applies:
- Lose Them needs the master's own sight: only the master's game knows `isCouldSee` for that player (another
  client's `isTargetVisible()` reads its own local player). So the master's game times each zombie whose
  `getTarget()` is the master (targets travel in ZombiePacket, so remote zombies show them too). A zombie this game
  runs is dropped here; others go to the server (`loseThem { list = online IDs }`), which checks the sender holds the
  signature and is the zombie's target, then drops one no client owns or sends `loseThemApply` to the owner, which
  checks the target again.
- Unseen needs only crouched and still, which every game sees (sneaking travels in the player's network variables,
  position in its packets). So the game that runs a zombie (client: `not isRemoteZombie()`; server: no
  `getOwnerPlayer()`; single player: all) drops it itself in OnTick after the update the target appeared in. The
  server sends everyone the online IDs of the signature's holders (`stealthMasters`), as Evasion does.
- An idle zombie in view keeps rolling (x5 for 15 s after each spot), so it would be dropped every update; sending it
  a few tiles away from the master ends that: in multiplayer a walking zombie cannot spot, and one that arrives faces
  away (`spottedNew` gives 0 when the look vector is more than ~115 degrees off). In single player a walking zombie
  that keeps the master in view can still stall, spotted and dropped every update. Known limit.
]]

require "TienSkillMastery"
require "TienSkillMastery_Relay"
local M = TienSkillMastery

local L = {}
M.LoseThem = L

local LOSE = "Stealth.SigLoseThem"
local UNSEEN = "Stealth.SigUnseen"

L.CHECK_MS = 100            -- Lose Them: how often the master's game looks at its chasers
L.RESEND_MS = 2000          -- a drop asked again if the zombie still chases after this long
L.STILL_MS = 500            -- Unseen: crouched without moving this long
L.STILL_SLACK = 0.15        -- tiles of drift still counted as standing still
L.REFRESH_MS = 1000         -- masters list
L.MAX_LIST = 20             -- zombies per command
L.MAX_DIST = 60             -- tiles: farthest zombie a master can make lose them (server check)
L.NEAR = 25                 -- tiles: own zombies whose walk is remembered while a master is hidden
L.AWAY_MIN, L.AWAY_MAX = 4, 7

--- States a drop may interrupt (the zombie is then put idle or sent walking).
L.INTERRUPT = {
    ZombieIdleState = true, PathFindState = true, WalkTowardState = true, LungeState = true, ThumpState = true,
    ZombieTurnAlerted = true, ZombieEatBodyState = true, ZombieSittingState = true,
}

L.remote = {}       -- client: [online ID] = true, from the server's list
L.masters = {}      -- players with Unseen this game knows of, rebuilt every REFRESH_MS
L.still = {}        -- [player] = { x, y, at = ms the player last moved, hidden, chasers = { [zombie] = true } }
L.resume = {}       -- [zombie] = { x, y, z } where an own zombie near a hidden master was walking
L.lose = {}         -- [player] = { [zombie] = { since = ms, sent = ms } }, Lose Them timers on the master's game

--- Zombies whose AI this game runs.
function L.owns(zombie)
    if isServer() then return zombie:getOwnerPlayer() == nil end
    if isClient() then return not zombie:isRemoteZombie() end
    return true
end

--- Clears the zombie's target and the "last spotted" that would bring it back (see the header).
function L.forget(zombie, master)
    if master:getCurrentSquare() and zombie:getCurrentSquare() then
        local was = zombie:isUseless()
        zombie:setUseless(true)
        pcall(function() zombie:spotted(master, true) end)
        zombie:setUseless(was)
    end
    if zombie:getTarget() ~= nil then zombie:setTarget(nil) end
end

local function interruptible(zombie)
    return not zombie:isDead() and L.INTERRUPT[zombie:getCurrentStateName() or ""] == true
end

local function idle(zombie)
    if ZombieIdleState then zombie:changeState(ZombieIdleState.instance()) end
end

local atan2 = math.atan2 or math.atan   -- Kahlua has atan2; Lua 5.3+ only the two-argument atan

--- A free square a few tiles from the zombie, away from the master; nil when none is found.
function L.awaySquare(zombie, master)
    local cell = getCell()
    if not cell then return nil end
    local zx, zy, zz = zombie:getX(), zombie:getY(), math.floor(zombie:getZ())
    local dx, dy = zx - master:getX(), zy - master:getY()
    local len = math.sqrt(dx * dx + dy * dy)
    local base = len > 0.01 and atan2(dy, dx) or ZombRandFloat(0, 6.283)
    for _ = 1, 6 do
        local a = base + ZombRandFloat(-0.6, 0.6)
        local d = ZombRandFloat(L.AWAY_MIN, L.AWAY_MAX)
        local x, y = math.floor(zx + math.cos(a) * d), math.floor(zy + math.sin(a) * d)
        local sq = cell:getGridSquare(x, y, zz)
        if sq and sq:isFree(true) then return x, y, zz end
    end
    return nil
end

--- Lose Them on the zombie's owner: forget the master, stand still. False when the zombie cannot be stopped now.
function L.loseApply(zombie, master)
    if not interruptible(zombie) then return false end
    L.forget(zombie, master)
    idle(zombie)
    return true
end

--- Unseen on the zombie's owner: forget the master, walk on where it was going or away from the master.
--- Returns where it was sent ({ x, y, z }), false when it was left alone, true when it was only stopped.
function L.unseenApply(zombie, master)
    if not interruptible(zombie) then return false end
    L.forget(zombie, master)
    idle(zombie)
    local r = L.resume[zombie]
    local x, y, z
    if r then x, y, z = r.x, r.y, r.z else x, y, z = L.awaySquare(zombie, master) end
    if not x then return true end
    zombie:pathToLocation(x, y, z)
    return { x = x, y = y, z = z }
end

-- ---------------------------------------------------------------------------------------------------------------
-- Masters (Unseen holders) and the server's list for the clients
-- ---------------------------------------------------------------------------------------------------------------

local lastList = ""

local function isMasterHere(p)
    return p and not p:isDead() and M.sig(p, UNSEEN)
end

function L.refresh()
    local list = {}
    local seen = {}
    local function add(p)
        if p and not seen[p] and not p:isDead() then
            seen[p] = true
            table.insert(list, p)
        end
    end
    if isServer() then
        local ids = {}
        local players = getOnlinePlayers()
        for i = 0, players:size() - 1 do
            local p = players:get(i)
            if isMasterHere(p) then
                add(p)
                table.insert(ids, tostring(p:getOnlineID()))
            end
        end
        table.sort(ids)
        local s = table.concat(ids, ",")
        if s ~= lastList then
            lastList = s
            sendServerCommand(M.MODULE, "stealthMasters", { list = s })
        end
    else
        for i = 0, getNumActivePlayers() - 1 do
            local p = getSpecificPlayer(i)
            if isMasterHere(p) then add(p) end
        end
        if isClient() then
            for id in pairs(L.remote) do add(getPlayerByOnlineID(id)) end
        end
    end
    L.masters = list
end

if isServer() then
    Events.OnClientCommand.Add(function(module, command, player, args)
        if module ~= M.MODULE or not player then return end
        if command == "stealthMastersRequest" then
            sendServerCommand(player, M.MODULE, "stealthMasters", { list = lastList })
        elseif command == "loseThem" and type(args) == "table" then
            L.serverLose(player, args)
        end
    end)
end

local answered = false
local nextAsk = 0

if isClient() then
    Events.OnServerCommand.Add(function(module, command, args)
        if module ~= M.MODULE or type(args) ~= "table" then return end
        if command == "stealthMasters" then
            local remote = {}
            for id in string.gmatch(tostring(args.list or ""), "%d+") do remote[tonumber(id)] = true end
            L.remote = remote
            answered = true
        elseif command == "loseThemApply" then
            L.clientLoseApply(args)
        end
    end)
end

-- ---------------------------------------------------------------------------------------------------------------
-- Unseen: on the zombie's owner, every update while a master is crouched and still
-- ---------------------------------------------------------------------------------------------------------------

local function zombies()
    local cell = getCell()
    return cell and cell:getZombieList()
end

local function targeting(master)
    local set = {}
    local list = zombies()
    if not list then return set end
    for i = 0, list:size() - 1 do
        local z = list:get(i)
        if z and z:getTarget() == master then set[z] = true end
    end
    return set
end

--- Crouched and still for STILL_MS; keeps the zombies already chasing from the moment it began.
function L.updateStill(now)
    local live = {}
    local any = false
    for _, p in ipairs(L.masters) do
        live[p] = true
        local st = L.still[p]
        if not st then
            st = {}
            L.still[p] = st
        end
        local x, y = p:getX(), p:getY()
        local crouched = not p:isDead() and p:isSneaking() and not p:getVehicle()
        if not crouched or not st.x or math.abs(x - st.x) > L.STILL_SLACK or math.abs(y - st.y) > L.STILL_SLACK then
            st.x, st.y, st.at = x, y, now
        end
        local hidden = crouched and now - st.at >= L.STILL_MS
        if hidden and not st.hidden then st.chasers = targeting(p) end
        if not hidden then st.chasers = nil end
        st.hidden = hidden
        any = any or hidden
    end
    for p in pairs(L.still) do
        if not live[p] then L.still[p] = nil end
    end
    return any
end

local function walkGoal(zombie)
    local state = zombie:getCurrentStateName()
    if state ~= "PathFindState" and state ~= "WalkTowardState" then return nil end
    local pfb = zombie:getPathFindBehavior2()
    if not pfb or not (pfb:isGoalLocation() or pfb:isGoalSound()) then return nil end
    return { x = math.floor(pfb:getTargetX()), y = math.floor(pfb:getTargetY()), z = math.floor(pfb:getTargetZ()) }
end

function L.updateUnseen()
    local hidden = {}
    local count = 0
    for p, st in pairs(L.still) do
        if st.hidden then
            hidden[p] = st
            count = count + 1
        end
    end
    if count == 0 then
        L.resume = {}
        L.hasResume = false
        return
    end
    local list = zombies()
    if not list then return end
    local resume = {}
    for i = 0, list:size() - 1 do
        local z = list:get(i)
        if z and not z:isDead() then
            local target = z:getTarget()
            local st = target and hidden[target]
            if st then
                if not st.chasers[z] and L.owns(z) then
                    local sent = L.unseenApply(z, target)
                    if type(sent) == "table" then resume[z] = sent end
                end
            elseif L.owns(z) then
                -- Not after a hidden master: remember where it walks, for a walk on after a later drop.
                for p in pairs(hidden) do
                    local dx, dy = z:getX() - p:getX(), z:getY() - p:getY()
                    if dx * dx + dy * dy <= L.NEAR * L.NEAR then
                        resume[z] = walkGoal(z)
                        break
                    end
                end
            end
            -- A chaser that let go of the master is no longer one.
            for p, s in pairs(hidden) do
                if s.chasers[z] and target ~= p then s.chasers[z] = nil end
            end
        end
    end
    L.resume = resume
    L.hasResume = true
end

-- ---------------------------------------------------------------------------------------------------------------
-- Lose Them: decided on the master's game, applied on the zombie's owner
-- ---------------------------------------------------------------------------------------------------------------

local function canLose(p)
    return p and not p:isDead() and p:isSneaking() and not p:getVehicle() and M.sig(p, LOSE)
end

local function seenBy(zombie, p)
    local sq = zombie:getCurrentSquare()
    if not sq then return true end
    return sq:isCouldSee(p:getPlayerNum()) or zombie:couldSeeHeadSquare(p)
end

--- One pass for one local master: times every chaser out of sight; returns the remote zombies to ask about.
function L.checkLose(p, now)
    local timers = L.lose[p]
    if not canLose(p) then
        L.lose[p] = nil
        return {}
    end
    if not timers then
        timers = {}
        L.lose[p] = timers
    end
    local loseMs = M.val(p, LOSE) * 1000
    local ask = {}
    local live = {}
    local list = zombies()
    if list then
        for i = 0, list:size() - 1 do
            local z = list:get(i)
            if z and z:getTarget() == p and not z:isDead() then
                live[z] = true
                if seenBy(z, p) then
                    timers[z] = nil
                else
                    local t = timers[z]
                    if not t then
                        t = { since = now }
                        timers[z] = t
                    end
                    if now - t.since >= loseMs and (not t.sent or now - t.sent >= L.RESEND_MS) then
                        if isClient() and z:isRemoteZombie() then
                            t.sent = now
                            if #ask < L.MAX_LIST then table.insert(ask, z:getOnlineID()) end
                        elseif L.loseApply(z, p) then
                            t.sent = now
                        end
                    end
                end
            end
        end
    end
    for z in pairs(timers) do
        if not live[z] then timers[z] = nil end
    end
    return ask
end

function L.updateLose(now)
    for i = 0, getNumActivePlayers() - 1 do
        local p = getSpecificPlayer(i)
        if p then
            local ask = L.checkLose(p, now)
            if #ask > 0 then
                local ids = {}
                for _, id in ipairs(ask) do table.insert(ids, tostring(id)) end
                sendClientCommand(p, M.MODULE, "loseThem", { list = table.concat(ids, ",") })
            end
        end
    end
    for p in pairs(L.lose) do
        if p:isDead() or not p:isLocalPlayer() then L.lose[p] = nil end
    end
end

local function idsOf(s, max)
    local ids = {}
    for id in string.gmatch(tostring(s or ""), "%d+") do
        if #ids >= max then break end
        table.insert(ids, tonumber(id))
    end
    return ids
end

--- Server: a master's game asks for zombies chasing it to give up.
function L.serverLose(player, args)
    if not canLose(player) then return end
    local byOwner = {}
    for _, id in ipairs(idsOf(args.list, L.MAX_LIST)) do
        local z = M.Relay.findZombie(id)
        if z and not z:isDead() and z:getTarget() == player then
            local dx, dy = z:getX() - player:getX(), z:getY() - player:getY()
            if dx * dx + dy * dy <= L.MAX_DIST * L.MAX_DIST then
                local owner = z:getOwnerPlayer()
                if owner == nil then
                    L.loseApply(z, player)
                else
                    byOwner[owner] = byOwner[owner] or {}
                    table.insert(byOwner[owner], tostring(id))
                end
            end
        end
    end
    for owner, ids in pairs(byOwner) do
        sendServerCommand(owner, M.MODULE, "loseThemApply",
            { master = player:getOnlineID(), list = table.concat(ids, ",") })
    end
end

--- Client: the server passes on a master's Lose Them for zombies this game runs.
function L.clientLoseApply(args)
    local master = getPlayerByOnlineID(tonumber(args.master) or -1)
    if not master then return end
    for _, id in ipairs(idsOf(args.list, L.MAX_LIST)) do
        local z = M.Relay.findZombie(id)
        if z and not z:isRemoteZombie() and z:getTarget() == master then L.loseApply(z, master) end
    end
end

-- ---------------------------------------------------------------------------------------------------------------

local lastRefresh = -L.REFRESH_MS
local lastLose = 0

Events.OnTick.Add(function()
    local now = getTimestampMs()
    if now - lastRefresh >= L.REFRESH_MS then
        lastRefresh = now
        L.refresh()
    end
    if isClient() and not answered and now >= nextAsk then
        local p = getPlayer()
        if p and p:getOnlineID() >= 0 then
            nextAsk = now + 3000
            sendClientCommand(p, M.MODULE, "stealthMastersRequest", {})
        end
    end
    if L.updateStill(now) then
        L.updateUnseen()
    elseif L.hasResume then
        L.resume = {}
        L.hasResume = false
    end
    if not isServer() and now - lastLose >= L.CHECK_MS then
        lastLose = now
        L.updateLose(now)
    end
end)
