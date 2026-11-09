--[[
Tien's Skill Mastery: extra damage to a zombie, applied where the zombie's health counts (42.21).

Why a relay: in multiplayer a zombie's health belongs to the client that owns (simulates) it. That client's health goes
to the server in ZombiePacket (`NetworkZombiePacker.applyZombie`), and at 0 the server's `parseZombie` calls `die()`
and tells everyone; other clients ignore ZombiePacket health for a zombie they already have. The attacker is often
not the owner. So:
- The attacker's client sees the hit in `OnWeaponHitCharacter(wielder, target, weapon, damage)`, which
  `IsoGameCharacter.Hit` (~5875) fires before `hitConsequences`. A zombie this client owns (`not isRemoteZombie()`,
  always in single player) loses the extra health right there, so `hitConsequences` sees a zombie at 0 as dead and
  kills it the vanilla way (ZomboidFixesB42's spiked armor does the same).
- A remote zombie: the client sends `zombieHit { id = online ID, kind, damage }`. The server finds the zombie
  (`getCell():getZombieList()` by `getOnlineID()`; Lua has no lookup by ID), checks the sender is within 4 tiles,
  works the amount out from its own copy of the sender's mastery (never the client's number), and sends
  `zombieDamage { id, amount }` to `zombie:getOwnerPlayer()`, or lowers its own copy when no player owns it. The owner
  lowers its copy's health; at 0 its next ZombiePacket makes the server kill it.

Kinds (amount from the server's copy of the attacker's mastery):
- "shove": Street Fighting, `StreetFighting.ShoveDamage` flat (a standing shove deals no damage in vanilla:
  `Hit` sets `bIgnoreDamage` for `isDoShove()` and not aiming at the floor, ~5870).
- "ambush": Knifework, `Knifework.Ambush` percent of the hit's damage, for a zombie not targeting the attacker.
]]

require "TienSkillMastery"
local M = TienSkillMastery

M.Relay = M.Relay or {}
local R = M.Relay

local MAX_DIST = 4
R.MAX_DAMAGE = 5   -- the most one `zombieDamage` takes off, on the owner's client

--- Extra damage of a kind for this attacker, from the local copy of its mastery (server: the real one).
function R.amount(attacker, kind, damage)
    if kind == "shove" then
        return M.val(attacker, "StreetFighting.ShoveDamage")
    elseif kind == "ambush" then
        local d = math.max(0, math.min(10, tonumber(damage) or 0))
        return d * M.val(attacker, "Knifework.Ambush") / 100
    end
    return 0
end

local function lower(zombie, amount)
    if not zombie or zombie:isDead() or amount <= 0 then return end
    zombie:setHealth(math.max(0, zombie:getHealth() - amount))
end

function R.findZombie(id)
    local list = getCell() and getCell():getZombieList()
    if not list or not id then return nil end
    for i = 0, list:size() - 1 do
        local z = list:get(i)
        if z and z:getOnlineID() == id then return z end
    end
    return nil
end

--- Called on the attacker's side (client, or single player) for a hit by a local player.
function R.hit(attacker, zombie, kind, damage)
    if not attacker or not zombie or not instanceof(zombie, "IsoZombie") or zombie:isDead() then return end
    if zombie:isReanimatedForGrappleOnly() then return end
    if not isClient() or not zombie:isRemoteZombie() then
        lower(zombie, R.amount(attacker, kind, damage))
        return
    end
    if R.amount(attacker, kind, damage) <= 0 then return end
    sendClientCommand(attacker, M.MODULE, "zombieHit", { id = zombie:getOnlineID(), kind = kind, damage = damage })
end

-- Server: check and forward.
if isServer() then
    Events.OnClientCommand.Add(function(module, command, player, args)
        if module ~= M.MODULE or command ~= "zombieHit" or type(args) ~= "table" or not player then return end
        local zombie = R.findZombie(tonumber(args.id))
        if not zombie or zombie:isDead() then return end
        if zombie:DistToProper(player) > MAX_DIST then return end
        local amount = R.amount(player, args.kind, args.damage)
        if amount <= 0 then return end
        local owner = zombie:getOwnerPlayer()
        if owner and owner ~= player then
            sendServerCommand(owner, M.MODULE, "zombieDamage", { id = zombie:getOnlineID(), amount = amount })
        elseif not owner then
            lower(zombie, amount)
        end
    end)
end

-- Owner client: apply.
if isClient() then
    Events.OnServerCommand.Add(function(module, command, args)
        if module ~= M.MODULE or command ~= "zombieDamage" or type(args) ~= "table" then return end
        local zombie = R.findZombie(tonumber(args.id))
        if zombie and not zombie:isRemoteZombie() then
            lower(zombie, math.max(0, math.min(R.MAX_DAMAGE, tonumber(args.amount) or 0)))
        end
    end)
end

-- ---------------------------------------------------------------------------------------------------------------
-- Phase 3b: actions on a zombie's owner (not damage). Applied on the next tick, never inside the hit that caused
-- them (vanilla's `hitConsequences` and hit reaction would overwrite the flags).
-- - "hamstring" (Swordsmanship's signature): `knockDown(false)` (knocked down + stagger back + hit force 1, reports
--   "wasHit"), with `setBecomeCrawler(true)` and `setCanWalk(false)` so it gets up crawling, vanilla's own path for
--   a zombie knocked down hard (`IsoZombie` ~4077). Invulnerable zombies refuse `setBecomeCrawler`.
-- - "pushback" (Bludgeoning's signature): a stagger back, not a knockdown: `setPlayerAttackPosition` ("FRONT" when the
--   attacker is in front of the zombie, else "BEHIND"), `setHitForce`, `getHitDir()` pointed away from the attacker,
--   `setStaggerBack(true)`, `reportEvent("wasHit")` (the zombie actiongroup's staggerback node; ZomboidFixesB42
--   "Zombie stagger transitions"). ZombiePacket carries no stagger, and vanilla's only own message, ZombieStagger (sent
--   by the owner from `StaggerBackState.enter`), carries just where the zombie ends up, so alone it slides other
--   clients' copies there (`HitReactionNetworkAI.process`). Vanilla's flag comes with the hit packet, which sets it on
--   every client (`fields/hit/Zombie.process`); here the server sends `zombieActShow` to everyone and each client sets
--   it on its remote copy (`R.show`; the owner has `zombieActApply`). A remote copy's `StaggerBackState` plays the
--   animation with its own root motion off while ZombieStagger moves it, and clears the flag on exit.
-- - "bowl" (Street Fighting's signature) is shown the same way: `knockDown` sets on a remote copy what vanilla's hit
--   packet sets there (`fields/hit/Character.process` + `Zombie.process`: knocked down, stagger back, attack position,
--   no hit reaction), and `StaggerBackState`, `ZombieFallDownState` and `ZombieOnGroundState` then run on that copy as
--   after a vanilla knockdown. The attacker sees it too when another client owns the zombie.
-- Server checks: the signature, the 4-tile distance (5 for push back's cone), and for push back the endurance cost
-- (0.01 a zombie, server-owned stat) before anything is forwarded.
-- ---------------------------------------------------------------------------------------------------------------

local pendingActs = {}

local function applyAct(zombie, kind, args)
    if not zombie or zombie:isDead() or zombie:isReanimatedForGrappleOnly() then return end
    if kind == "hamstring" then
        if zombie:isCrawling() then return end
        zombie:setBecomeCrawler(true)
        zombie:setCanWalk(false)
        -- Already falling from the hit itself (the attacker's client makes it `alwaysKnockedDown` for that hit, see
        -- client/TienSkillMastery_Combat.lua): only the crawler flags are needed here; a knockDown now would wait
        -- for the hit reaction and look like a freeze.
        if not zombie:isKnockedDown() and not zombie:isOnFloor() then zombie:knockDown(false) end
    elseif kind == "bowl" then
        -- Street Fighting's signature: knocked down by a sprinting master (`knockDown(hitFromBehind)`).
        if zombie:isOnFloor() or zombie:isCrawling() then return end
        local ax, ay = tonumber(args.x), tonumber(args.y)
        local behind = ax and ay and (zombie:getForwardDirectionX() * (ax - zombie:getX())
            + zombie:getForwardDirectionY() * (ay - zombie:getY())) < 0 or false
        zombie:knockDown(behind)
    elseif kind == "pushback" then
        if zombie:isOnFloor() or zombie:isCrawling() then return end
        local ax, ay = tonumber(args.x), tonumber(args.y)
        if not ax or not ay then return end
        local dx, dy = zombie:getX() - ax, zombie:getY() - ay
        local d = math.sqrt(dx * dx + dy * dy)
        if d < 0.001 then return end
        dx, dy = dx / d, dy / d
        local front = (zombie:getForwardDirectionX() * -dx + zombie:getForwardDirectionY() * -dy) > 0
        zombie:setPlayerAttackPosition(front and "FRONT" or "BEHIND")
        zombie:setHitForce(0.6)
        local hd = zombie:getHitDir()
        if hd then hd:set(dx, dy) end
        zombie:setStaggerBack(true)
        zombie:reportEvent("wasHit")
    end
end

local function queueAct(zombie, kind, args)
    table.insert(pendingActs, { zombie = zombie, kind = kind, args = args or {} })
end
--- Queues an action on a zombie this side owns (no checks, no cost): the throw's stagger uses it.
R.queueAct = queueAct

R.SHOWN = { pushback = true, bowl = true }     -- acts other clients play on their copies of the zombie

--- Server: every client plays this act on its remote copies of these zombies (online IDs), attacker at (x, y).
function R.show(kind, ids, x, y)
    sendServerCommand(M.MODULE, "zombieActShow", { kind = kind, ids = ids, x = x, y = y })
end

Events.OnTick.Add(function()
    if #pendingActs == 0 then return end
    local list = pendingActs
    pendingActs = {}
    for _, a in ipairs(list) do
        local ok, err = pcall(applyAct, a.zombie, a.kind, a.args)
        if not ok then print("[TienSkillMastery] zombie action failed: " .. tostring(err)) end
    end
end)

R.PUSH_COST = 0.01
-- Endurance per zombie (server-owned stat): push back 0.01 (user, 2026-11-07), battering ram (bowl) 0.02 (to tune in game).
R.COST = { pushback = R.PUSH_COST, bowl = 0.02 }

--- Attacker side. kind "hamstring": `zombies` is one zombie; "pushback": a list of zombies.
function R.act(attacker, kind, zombies)
    if not attacker then return end
    if type(zombies) ~= "table" then zombies = { zombies } end
    if isClient() then
        local ids = {}
        for _, z in ipairs(zombies) do ids[#ids + 1] = z:getOnlineID() end
        if #ids > 0 then sendClientCommand(attacker, M.MODULE, "zombieAct", { kind = kind, ids = ids }) end
        return
    end
    -- Single player: the same checks the server makes, then apply.
    local cost = R.COST[kind]
    if cost then
        local stats = attacker:getStats()
        local allowed = math.floor(stats:get(CharacterStat.ENDURANCE) / cost + 0.000001)
        local n = math.min(#zombies, allowed)
        if n <= 0 then return end
        stats:set(CharacterStat.ENDURANCE, stats:get(CharacterStat.ENDURANCE) - n * cost)
        for i = 1, n do queueAct(zombies[i], kind, { x = attacker:getX(), y = attacker:getY() }) end
    else
        for _, z in ipairs(zombies) do queueAct(z, kind, {}) end
    end
end

local ACT_SIG = { hamstring = "Swordsmanship.SigHamstring", pushback = "Bludgeoning.SigPushBack",
    bowl = "StreetFighting.SigBowlOver" }

if isServer() then
    Events.OnClientCommand.Add(function(module, command, player, args)
        if module ~= M.MODULE or command ~= "zombieAct" or type(args) ~= "table" or not player then return end
        local kind = args.kind
        if not ACT_SIG[kind] or not M.sig(player, ACT_SIG[kind]) or type(args.ids) ~= "table" then return end
        local zombies = {}
        local i = 1
        while args.ids[i] ~= nil and #zombies < 12 do
            local z = R.findZombie(tonumber(args.ids[i]))
            if z and not z:isDead() and z:DistToProper(player) <= (kind == "hamstring" and MAX_DIST or 5) then
                zombies[#zombies + 1] = z
            end
            i = i + 1
        end
        local cost = R.COST[kind]
        if cost then
            local stats = player:getStats()
            local n = math.min(#zombies, math.floor(stats:get(CharacterStat.ENDURANCE) / cost + 0.000001))
            for j = #zombies, n + 1, -1 do table.remove(zombies, j) end
            if n > 0 then stats:set(CharacterStat.ENDURANCE, stats:get(CharacterStat.ENDURANCE) - n * cost) end
        end
        local shown = {}
        for _, z in ipairs(zombies) do
            local data = { id = z:getOnlineID(), kind = kind, x = player:getX(), y = player:getY() }
            local owner = z:getOwnerPlayer()
            if owner then
                sendServerCommand(owner, M.MODULE, "zombieActApply", data)
            else
                queueAct(z, kind, data)
            end
            shown[#shown + 1] = data.id
        end
        if R.SHOWN[kind] and #shown > 0 then R.show(kind, shown, player:getX(), player:getY()) end
    end)
end

if isClient() then
    Events.OnServerCommand.Add(function(module, command, args)
        if module ~= M.MODULE or command ~= "zombieActApply" or type(args) ~= "table" then return end
        local zombie = R.findZombie(tonumber(args.id))
        if zombie and not zombie:isRemoteZombie() then queueAct(zombie, args.kind, args) end
    end)

    -- What everyone else sees of it (see the header); checked anyway, it comes off the wire.
    Events.OnServerCommand.Add(function(module, command, args)
        if module ~= M.MODULE or command ~= "zombieActShow" or type(args) ~= "table" then return end
        if not R.SHOWN[args.kind] or type(args.ids) ~= "table" then return end
        local i = 1
        while args.ids[i] ~= nil do
            local zombie = R.findZombie(tonumber(args.ids[i]))
            if zombie and zombie:isRemoteZombie() then queueAct(zombie, args.kind, args) end
            i = i + 1
        end
    end)
end
