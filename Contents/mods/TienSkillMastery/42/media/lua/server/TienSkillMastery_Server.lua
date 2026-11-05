--[[
Tien's Skill Mastery: server core (also runs in single player). See shared/TienSkillMastery.lua for the mechanism.

- `Events.AddXP` turns every gain on a parked skill into mastery XP and parks the skill again; negative XP comes out of
  mastery first. The event fires on the server / single player only (`XP.AddXP`, `!GameClient.client`).
- A pass every second notes every online player's XP object (for the getXP wrapper), parks level-10 skills that sit
  at total(10) (just reached, an older save, Skill Journal, admin /addxp), and sends changed mastery to the owner.
- Not experience: Skill Journal's restore (lait, 3776641628) calls the 6-argument `AddXP`, which fires the event too;
  `SkillJournal.restore` is wrapped to ignore gains while it runs. Admin `/addxp` cannot be told apart.
- Mastery belongs to the character: cleared on death (`OnCharacterDeath`, fires on the server for players), and
  reset when a character with fewer hours survived than recorded shows up under the same name.
]]

if isClient() then return end

require "TienSkillMastery"
local M = TienSkillMastery

local adjusting = false   -- our own AddXP calls
local adminVanilla = false -- an admin's vanilla skill cheat: real XP, never mastery
local suppress = 0        -- Skill Journal restores in progress
local dirty = {}          -- [username] = true: send to the owner

-- ---------------------------------------------------------------------------------------------------------------
-- Moving real XP (see the shared header: AddXP only, level juggled to 0 when a boundary would be crossed)
-- ---------------------------------------------------------------------------------------------------------------

local function proteinFactor(player, perk)
    if perk ~= Perks.Strength then return 1 end
    local proteins = player:getNutrition():getProteins()
    if proteins > 50 and proteins < 300 then return 1.5 end
    if proteins < -300 then return 0.7 end
    return 1
end

--- Moves the skill's real XP to `target` without any level change. Returns true when it landed.
local function setRawXp(player, perk, target)
    local raw = M.rawXp(player, perk)
    local delta = target - raw
    if math.abs(delta) < 0.001 then return true end
    local level = player:getPerkLevel(perk)
    local here = perk:getTotalXpForLevel(level)
    local nextAt = perk:getTotalXpForLevel(level + 1)
    local juggle = (target < here and raw >= here) or (target >= nextAt and raw < nextAt)
    if juggle then player:setPerkLevelDebug(perk, 0) end
    -- Vanilla's own AddXP handler (xpUpdate.addXp) counts any positive Strength / Fitness award as training and
    -- holds decay back; our moves are not training, so its timers are put back.
    local modData = player:getModData()
    local strengthTimer, fitnessTimer = modData.strengthUpTimer, modData.fitnessUpTimer
    adjusting = true
    local ok = pcall(function()
        player:getXp():AddXP(perk, delta / proteinFactor(player, perk), false, false, false, false)
    end)
    adjusting = false
    modData.strengthUpTimer, modData.fitnessUpTimer = strengthTimer, fitnessTimer
    if juggle then player:setPerkLevelDebug(perk, level) end
    if perk == Perks.Fitness then
        player:getStats():set(CharacterStat.FITNESS, player:getPerkLevel(perk) / 5 - 1)
    end
    return ok and math.abs(M.rawXp(player, perk) - target) < M.EPS
end

local function park(player, perk)
    return setRawXp(player, perk, M.parkValue(perk))
end

-- ---------------------------------------------------------------------------------------------------------------
-- Entries
-- ---------------------------------------------------------------------------------------------------------------

local function markDirty(player)
    dirty[player:getUsername()] = true
end

local function checkCharacter(player, e)
    local hours = player:getHoursSurvived()
    if e.hours and hours + 0.5 < e.hours then
        print("[TienSkillMastery] " .. tostring(player:getUsername()) .. " is a new character, mastery reset")
        e.xp = {}
        markDirty(player)
    end
    e.hours = hours
end

--- A mastery level gained from experience: vanilla's level-up feedback on the owner's screen. Vanilla's own
--- (`IsoGameCharacter.LevelPerk` ~4809 halo "+1 <skill>" with the up arrow in the good colour; `XP.AddXP` ~17549
--- `sendObjectChange(PLAY_GAIN_EXPERIENCE_LEVEL_SOUND)` on a server, `playGainExperienceLevelSound()` locally) runs
--- where the player is local, so the server sends "levelUp" and the client plays both
--- (client/TienSkillMastery_Client.lua M.showLevelUp); single player calls it directly.
function M.notifyLevelUp(player, perk, level)
    local args = { perk = perk:getId(), level = level }
    if isServer() then
        sendServerCommand(player, M.MODULE, "levelUp", args)
    elseif M.showLevelUp then
        M.showLevelUp(player, args)
    end
end

local function addMastery(player, perk, amount)
    local e = M.entry(player, true)
    local id = perk:getId()
    e.xp[id] = math.max(0, (e.xp[id] or 0) + amount)
    markDirty(player)
end

-- ---------------------------------------------------------------------------------------------------------------
-- The AddXP event
-- ---------------------------------------------------------------------------------------------------------------

local function onAddXP(player, perk, amount)
    if adjusting or not amount or amount == 0 then return end
    if adminVanilla then
        -- Admin skill cheat: the XP stays vanilla XP. Park a skill it brought to 10, bank nothing, eat no mastery.
        if instanceof(player, "IsoPlayer") and player:getPerkLevel(perk) >= 10
            and M.rawXp(player, perk) > M.parkValue(perk) + M.EPS then
            setRawXp(player, perk, M.parkValue(perk))
        end
        return
    end
    if not instanceof(player, "IsoPlayer") or player:getPerkLevel(perk) < 10 then return end
    if perk:getParent() == Perks.None then return end
    M.noteOwner(player)
    local raw = M.rawXp(player, perk)
    local old = raw - amount
    local parkAt = M.parkValue(perk)
    -- Parked means exactly at the park line before this award (our moves land on it to within float error).
    local wasParked = math.abs(old - parkAt) < M.EPS

    if not wasParked then
        -- Just reached 10 (Java clamped at total(10)), or somewhere else at level 10 (an admin set the level):
        -- park if above the line, nothing to bank.
        if raw > parkAt + M.EPS then park(player, perk) end
        return
    end

    if amount > 0 then
        if suppress <= 0 then
            -- Mastery is experience, never reading: take a skill book multiplier back out.
            local mult = player:getXp():getMultiplier(perk)
            local earned = mult > 1 and amount / mult or amount
            local before = M.levelInfo(perk, M.getXp(player, perk))
            addMastery(player, perk, earned)
            local after = M.levelInfo(perk, M.getXp(player, perk))
            if after > before then M.notifyLevelUp(player, perk, after) end
        end
        park(player, perk)
        return
    end

    -- Negative XP (decay): mastery pays first.
    local need = -amount
    local e = M.entry(player, true)
    local id = perk:getId()
    local have = e.xp[id] or 0
    if have >= need then
        addMastery(player, perk, -need)
        park(player, perk)
        return
    end
    if have > 0 then addMastery(player, perk, -have) end
    local rest = need - have
    -- Back to vanilla's state: total(10), then the rest through AddXP so its lose-level loop drops the skill.
    if setRawXp(player, perk, M.total10(perk)) and rest > 0 then
        adjusting = true
        pcall(function()
            player:getXp():AddXP(perk, -rest / proteinFactor(player, perk), false, false, false, false)
        end)
        adjusting = false
    end
end
Events.AddXP.Add(onAddXP)

-- ---------------------------------------------------------------------------------------------------------------
-- Skill Journal: its restore is reading, not experience.
-- ---------------------------------------------------------------------------------------------------------------

local function wrapSkillJournal()
    if not SkillJournal or not SkillJournal.restore or SkillJournal.__tsmWrapped then return end
    SkillJournal.__tsmWrapped = true
    local original = SkillJournal.restore
    SkillJournal.restore = function(...)
        suppress = suppress + 1
        local results = { pcall(original, ...) }
        suppress = suppress - 1
        if not results[1] then error(results[2]) end
        return unpack(results, 2)
    end
end
wrapSkillJournal()
Events.OnGameBoot.Add(wrapSkillJournal)
Events.OnServerStarted.Add(wrapSkillJournal)
Events.OnGameStart.Add(wrapSkillJournal)

-- ---------------------------------------------------------------------------------------------------------------
-- Players, the pass, sending
-- ---------------------------------------------------------------------------------------------------------------

function M.eachPlayer(fn)
    if isServer() then
        local list = getOnlinePlayers()
        for i = 0, list:size() - 1 do
            local p = list:get(i)
            if p and not p:isDead() then fn(p) end
        end
    else
        for i = 0, getNumActivePlayers() - 1 do
            local p = getSpecificPlayer(i)
            if p and not p:isDead() then fn(p) end
        end
    end
end

local function stateFor(player)
    local e = M.entry(player, false)
    local xp = {}
    if e then
        for k, v in pairs(e.xp) do xp[k] = v end
    end
    return { username = player:getUsername(), xp = xp }
end

local function send(player)
    if isServer() then
        sendServerCommand(player, M.MODULE, "state", stateFor(player))
    end
end

local function passPlayer(player)
    M.installXpWrapper(player)
    M.noteOwner(player)
    local e = M.entry(player, true)
    checkCharacter(player, e)
    if player:isAsleep() then return end
    for _, perk in ipairs(M.perks()) do
        if player:getPerkLevel(perk) >= 10 then
            local raw = M.rawXp(player, perk)
            if raw >= M.total10(perk) - M.EPS then park(player, perk) end
        end
    end
end

local lastPass = 0
local function onTick()
    local now = getTimestampMs()
    if now - lastPass < 1000 then return end
    lastPass = now
    local owners = {}
    M.eachPlayer(function(player)
        owners[player:getXp()] = player
        passPlayer(player)
        local name = player:getUsername()
        if dirty[name] then
            dirty[name] = nil
            send(player)
        end
    end)
    M.xpOwner = owners
end
Events.OnTick.Add(onTick)

local function onCharacterDeath(character)
    if not instanceof(character, "IsoPlayer") then return end
    local name = character:getUsername()
    if not name then return end
    local store = M.store()
    if store[name] then
        store[name] = nil
        print("[TienSkillMastery] " .. name .. " died, mastery cleared")
    end
    dirty[name] = nil
end
Events.OnCharacterDeath.Add(onCharacterDeath)

-- ---------------------------------------------------------------------------------------------------------------
-- Admin cheat: change mastery XP directly (the Mastery tab's right-click menu). Java's AddXP caps every award at the
-- level-10 total, so admin XP through /addxp reaches mastery only 240 at a time; this writes mastery itself.
-- MP: roles with Capability.AddXP (like /addxp), checked here. Single player: the client calls M.adminChange
-- directly, and only offers it with -debug (vanilla gates its single player admin tools the same way).
-- ---------------------------------------------------------------------------------------------------------------

local MAX_XP = 1e9

--- Total mastery XP needed to reach `level`.
local function xpForLevel(perk, level)
    local total = 0
    for n = 1, level do total = total + M.costFor(perk, n) end
    return total
end

--- args: { perk = id, op = "add" | "remove" | "level" | "clear", amount = n, level = n }. Returns true when applied.
function M.adminChange(player, args)
    if type(args) ~= "table" then return false end
    local perk = M.perk(args.perk)
    if not perk or not player then return false end
    local e = M.entry(player, true)
    local id = perk:getId()
    local before = e.xp[id] or 0
    local xp = before
    local amount = math.max(0, math.min(MAX_XP, math.floor(tonumber(args.amount) or 0)))
    if args.op == "add" then
        xp = math.min(MAX_XP, xp + amount)
    elseif args.op == "remove" then
        xp = math.max(0, xp - amount)
    elseif args.op == "level" then
        local level = math.max(0, math.min(100, math.floor(tonumber(args.level) or 0)))
        xp = xpForLevel(perk, level)
    elseif args.op == "clear" then
        xp = 0
    else
        return false
    end
    e.xp[id] = xp
    markDirty(player)
    -- Same level-up feedback as earned mastery (user, 2026-11-06), once for the new level, only when it went up.
    local levelBefore, levelAfter = M.levelInfo(perk, before), M.levelInfo(perk, xp)
    if levelAfter > levelBefore and player:getPerkLevel(perk) >= 10 then M.notifyLevelUp(player, perk, levelAfter) end
    print(string.format("[TienSkillMastery] %s set own %s mastery XP %d -> %d (%s)",
        tostring(player:getUsername()), id, math.floor(before), math.floor(xp), tostring(args.op)))
    return true
end

--- Admin cheat on the vanilla skill (the Skills tab's right-click menu): args { perk = id, op = "add" | "remove" |
--- "level", amount = n, level = n }. Goes through the `addXpNoMultiplier` global: on a server that is
--- GameServer.addXp (no boosts, then `updateXpChecker`, so the XP anti-cheat's snapshot follows, as for /addxp), in
--- single player a plain AddXP without boosts. Java's level loops do the levelling (several levels in one award), and
--- the Strength protein factor is divided out so the amount lands as asked. A parked skill is first put back at
--- vanilla's total(10) so a removal counts from the real cap. Mastery is left as it is (it only counts at 10).
function M.adminSkill(player, args)
    if type(args) ~= "table" or not player then return false end
    local perk = M.perk(args.perk)
    if not perk then return false end
    local amount = math.max(0, math.min(1e7, tonumber(args.amount) or 0))
    if M.isParked(player, perk) then setRawXp(player, perk, M.total10(perk)) end
    local raw = M.rawXp(player, perk)
    local delta
    if args.op == "add" then
        delta = amount
    elseif args.op == "remove" then
        delta = -math.min(amount, raw)
    elseif args.op == "level" then
        local level = math.max(0, math.min(10, math.floor(tonumber(args.level) or 0)))
        delta = perk:getTotalXpForLevel(level) - raw
    else
        return false
    end
    local before = player:getPerkLevel(perk)
    if math.abs(delta) > 0.001 then
        adminVanilla = true
        pcall(addXpNoMultiplier, player, perk, delta / proteinFactor(player, perk))
        adminVanilla = false
    end
    -- Back to the park line when the skill is (still) 10.
    if player:getPerkLevel(perk) >= 10 and M.rawXp(player, perk) > M.parkValue(perk) + M.EPS then
        park(player, perk)
    end
    print(string.format("[TienSkillMastery] %s %s own %s XP by %d (level %d -> %d)", tostring(player:getUsername()),
        tostring(args.op), perk:getId(), math.floor(delta), before, player:getPerkLevel(perk)))
    return true
end

local function onClientCommand(module, command, player, args)
    if module ~= M.MODULE then return end
    if command == "request" then
        M.installXpWrapper(player)
        M.noteOwner(player)
        checkCharacter(player, M.entry(player, true))
        send(player)
    elseif command == "adminChange" or command == "adminSkill" then
        local role = player and player:getRole()
        if not (role and role:hasCapability(Capability.AddXP)) then
            print("[TienSkillMastery] refused " .. command .. " from " .. tostring(player and player:getUsername()))
            return
        end
        if command == "adminChange" then
            if M.adminChange(player, args) then send(player) end
        else
            M.adminSkill(player, args)
        end
    end
end
Events.OnClientCommand.Add(onClientCommand)
