--[[
Tien's Skill Mastery: Freerunning's Evasion (user, 2026-11-06 / 2026-11-10): a share of zombie and player attacks on
the master miss, 2.5% per mastery level (25% at 10; 15% until the user raised it, 2026-11-11). A signature (15% flat) until 2026-11-11, now a passive that grows
with the level (user). Animals are left out (user, 2026-11-10). Traced in the 42.21 Java (decompiled).

Zombies (`AttackState`, run only by the zombie's owner: a client for the zombies it owns, the server for zombies no
client owns, single player for all). `enter` sets the attack outcome field to "start" (`getAttackOutcome()` reads
the field, which nothing else sets to "start"), the start anim's `SetAttackOutcome` event turns it "success" or
"fail", and the whole hit runs in the success anim's `AttackCollisionCheck` event, gated by `!zombie.isNoTeeth()`:
`triggerPlayerReaction` → `BodyDamage.AddRandomDamageFromZombie` does the player's hit reaction (the animation), the
damage, the holes, the drag-down and, on a client, `sendZombieHit` (the packet the server rolls again). `noTeeth`
(public `setNoTeeth`) is read only there and by `cantBite()` (itself read only inside `AddRandomDamageFromZombie`),
reset when the zombie is reused, never saved or sent. So when a swing at a master starts ("start" seen), the owner
rolls once and on a dodge sets `setNoTeeth(true)` until the swing ends (outcome no longer "start" / "success",
`ZombieBiteDone`, the zombie targets someone else or is out of sight, or 3 s): no damage, no hit animation, no packet,
nothing to undo. A zombie already toothless (vanilla's tutorial) is left alone. Still seen: the zombie's own swing,
vanilla's front defense (`testDefense` in `execute`, can play "Defended"), a sprinter's slow-down, and other
players' copies of the zombie (`AttackNetworkState`) play the bite / scratch sound and a blood splat.
Who owns a zombie: on a client `isRemoteZombie()` = not this connection's; on a server it means the opposite
(`NetworkZombieComponent.isRemote` = no `authOwner`), so the server only takes zombies with no `getOwnerPlayer()`.
The owner is often not the master's game, so every client must know every master's chance: the server sends the
list (`evasion { list = "onlineID:chance,..." }`) to everyone when it changes and to a client that asks.
ZomboidFixesB42's ClothingWear skips toothless zombies, so a dodge by a zombie the victim's own game runs wears no
clothing; one another game runs can still wear it there (that game's roll is not known to the victim's).

Players (`IsoGameCharacter.Hit` ~5867): `OnWeaponHitCharacter(wielder, target, weapon, damage)` fires, then the
`WeaponHitCharacter` hook, then `if (avoidDamage) { avoidDamage = false; return 0 }` before any damage or hit
reaction. Not the hook: `Event.trigger` ignores what Lua returns and answers true whenever any callback is
registered, so a registered hook makes every weapon hit on every character do nothing. `setAvoidDamage` (public,
read only there, not sent) set from the event is a one-hit skip. `Hit` runs on every machine: the attacker's client
first (`CombatManager.attackCollisionCheck` ~1159, local wielder; its return value is the damage put in the
`PlayerHitPlayerPacket`), then the server and the other clients (`WeaponHit.process` → `Hit(..., bRemote)` with the
packet's damage). So the attacker's game rolls (single player: the only game), and every game cancels a hit on a
master whose damage is exactly 0 (a real 0-damage hit on a master is cancelled too: fine, user 2026-11-10). Still
runs: the attacker's swing, endurance and weapon wear, `helmetFall` (rolled before `Hit` on the attacker's client),
a small push in the hit direction on other players' screens (`calculateHitReactionFromWeapon`, the packet's Fall),
the server's spiked-armor check. Not checked in game.
]]

require "TienSkillMastery"
local M = TienSkillMastery

local E = {}
M.Evasion = E

local ID = "Freerunning.Evasion"
local SCAN = 2                  -- tiles round a master searched for zombies (reach 1.0, crawlers 1.3)
local SWING_TIMEOUT_MS = 3000
local REFRESH_MS = 1000

E.remote = {}                   -- client: [online ID] = chance (%), from the server's list
E.masters = {}                  -- { { player = p, chance = c }, ... }, rebuilt every REFRESH_MS

--- Chance (%) this player dodges an attack: the own mastery where it is known (server, single player, the client's
--- own players), else the server's list.
function E.chance(player)
    if not player or not instanceof(player, "IsoPlayer") or instanceof(player, "IsoAnimal") then return 0 end
    local own = M.val(player, ID)
    if own > 0 or not isClient() then return own end
    return E.remote[player:getOnlineID()] or 0
end

local function addMaster(list, player)
    if not player or player:isDead() then return end
    local chance = E.chance(player)
    if chance > 0 then table.insert(list, { player = player, chance = chance }) end
end

-- ---------------------------------------------------------------------------------------------------------------
-- Masters, and the server's list for the clients
-- ---------------------------------------------------------------------------------------------------------------

local lastList = ""

local function listOf(masters)
    local parts = {}
    for _, m in ipairs(masters) do
        table.insert(parts, string.format("%d:%.2f", m.player:getOnlineID(), m.chance))
    end
    table.sort(parts)
    return table.concat(parts, ",")
end

local function refresh()
    local list = {}
    if isServer() then
        local players = getOnlinePlayers()
        for i = 0, players:size() - 1 do addMaster(list, players:get(i)) end
        local s = listOf(list)
        if s ~= lastList then
            lastList = s
            sendServerCommand(M.MODULE, "evasion", { list = s })
        end
    else
        local seen = {}
        for i = 0, getNumActivePlayers() - 1 do
            local p = getSpecificPlayer(i)
            if p then
                seen[p] = true
                addMaster(list, p)
            end
        end
        if isClient() then
            for id, _ in pairs(E.remote) do
                local p = getPlayerByOnlineID(id)
                if p and not seen[p] then addMaster(list, p) end
            end
        end
    end
    E.masters = list
end

if isServer() then
    Events.OnClientCommand.Add(function(module, command, player, args)
        if module ~= M.MODULE or command ~= "evasionRequest" or not player then return end
        sendServerCommand(player, M.MODULE, "evasion", { list = lastList })
    end)
end

local answered = false
local nextAsk = 0

if isClient() then
    Events.OnServerCommand.Add(function(module, command, args)
        if module ~= M.MODULE or command ~= "evasion" or type(args) ~= "table" then return end
        local remote = {}
        for id, chance in string.gmatch(tostring(args.list or ""), "(%d+):([%d%.]+)") do
            remote[tonumber(id)] = math.max(0, math.min(100, tonumber(chance) or 0))
        end
        E.remote = remote
        answered = true
    end)
end

-- ---------------------------------------------------------------------------------------------------------------
-- Zombies: a toothless swing on a dodge
-- ---------------------------------------------------------------------------------------------------------------

local swings = {}   -- [zombie] = { last = outcome last seen, dodged = bool, at = ms, target = player }

local function restore(zombie, s)
    if s.dodged then
        zombie:setNoTeeth(false)
        s.dodged = false
    end
end

--- Zombies this game runs the attacks of.
local function ownsAttack(zombie)
    if isServer() then return zombie:getOwnerPlayer() == nil end
    if isClient() then return not zombie:isRemoteZombie() end
    return true
end

local function watch(zombie, player, chance, now)
    local s = swings[zombie]
    if s and s.target ~= player then
        restore(zombie, s)
        s = nil
    end
    if not s then
        s = { target = player, at = now }
        swings[zombie] = s
    end
    local outcome = zombie:getAttackOutcome()
    if outcome == "start" and s.last ~= "start" then
        -- A new swing.
        restore(zombie, s)
        s.at = now
        if not zombie:isNoTeeth() and ZombRandFloat(0, 100) < chance then
            zombie:setNoTeeth(true)
            s.dodged = true
        end
    elseif s.dodged then
        local over = (outcome ~= "start" and outcome ~= "success")
            or zombie:getVariableString("ZombieBiteDone") == "true"
            or now - s.at > SWING_TIMEOUT_MS
        if over then restore(zombie, s) end
    end
    s.last = outcome
end

local function scanZombies(now)
    local seen = {}
    local cell = getCell()
    if cell then
        for _, m in ipairs(E.masters) do
            local player = m.player
            local square = not player:isDead() and player:getCurrentSquare()
            if square then
                local x, y, z = square:getX(), square:getY(), square:getZ()
                for dx = -SCAN, SCAN do
                    for dy = -SCAN, SCAN do
                        local sq = cell:getGridSquare(x + dx, y + dy, z)
                        if sq then
                            local objects = sq:getMovingObjects()
                            for i = 0, objects:size() - 1 do
                                local zombie = objects:get(i)
                                if instanceof(zombie, "IsoZombie") and not seen[zombie]
                                    and zombie:getTarget() == player and ownsAttack(zombie) then
                                    seen[zombie] = true
                                    watch(zombie, player, m.chance, now)
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    -- Zombies no longer at a master: give their teeth back.
    local gone = {}
    for zombie, s in pairs(swings) do
        if not seen[zombie] then table.insert(gone, zombie) end
    end
    for _, zombie in ipairs(gone) do
        restore(zombie, swings[zombie])
        swings[zombie] = nil
    end
end

local lastRefresh = 0

Events.OnTick.Add(function()
    local now = getTimestampMs()
    if now - lastRefresh >= REFRESH_MS then
        lastRefresh = now
        refresh()
    end
    if isClient() and not answered and now >= nextAsk then
        local p = getPlayer()
        if p and p:getOnlineID() >= 0 then
            nextAsk = now + 3000
            sendClientCommand(p, M.MODULE, "evasionRequest", {})
        end
    end
    scanZombies(now)
end)

-- ---------------------------------------------------------------------------------------------------------------
-- Players: the attacker's game rolls, every game cancels a 0-damage hit on a master
-- ---------------------------------------------------------------------------------------------------------------

Events.OnWeaponHitCharacter.Add(function(wielder, target, weapon, damage)
    if not target or not instanceof(target, "IsoPlayer") or instanceof(target, "IsoAnimal") then return end
    local chance = E.chance(target)
    if chance <= 0 then return end
    local attackerHere = not isServer() and wielder ~= nil and instanceof(wielder, "IsoPlayer")
        and wielder:isLocalPlayer()
    if attackerHere then
        if ZombRandFloat(0, 100) < chance then target:setAvoidDamage(true) end
    elseif tonumber(damage) == 0 then
        target:setAvoidDamage(true)
    end
end)
