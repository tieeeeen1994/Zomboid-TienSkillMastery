--[[
Tien's Skill Mastery: server core (also runs in single player). See shared/TienSkillMastery.lua for the mechanism.

- `Events.AddXP` turns every gain on a parked skill into points for every picked, active mastery that lists the skill
  (a share of the skill's level-10 step, see the shared core) and parks the skill again; a gain no picked mastery
  takes is lost, as in vanilla. Negative XP (Strength / Fitness decay) comes out of every such mastery that still
  has points; the skill drops below 10 only once none could pay. The event fires on the server / single player only (`XP.AddXP`, `!GameClient.client`).
- A pass every second notes every online player's XP object (for the getXP wrapper), parks level-10 skills that a
  picked, active mastery lists and that sit at total(10) (just reached, a new pick, Skill Journal, admin /addxp),
  unparks the others (back to total(10), where Java ignores gains and shows no XP halo), and sends changed mastery to
  the owner.
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
        e.picks, e.points = {}, {}
        markDirty(player)
    end
    e.hours = hours
end

--- A mastery level gained from experience: vanilla's level-up feedback on the owner's screen. Vanilla's own
--- (`IsoGameCharacter.LevelPerk` ~4809 halo "+1 <skill>" with the up arrow in the good colour; `XP.AddXP` ~17549
--- `sendObjectChange(PLAY_GAIN_EXPERIENCE_LEVEL_SOUND)` on a server, `playGainExperienceLevelSound()` locally) runs
--- where the player is local, so the server sends "levelUp" and the client plays both
--- (client/TienSkillMastery_Client.lua M.showLevelUp); single player calls it directly.
function M.notifyLevelUp(player, masteryId, level)
    local args = { mastery = masteryId, level = level }
    if isServer() then
        sendServerCommand(player, M.MODULE, "levelUp", args)
    elseif M.showLevelUp then
        M.showLevelUp(player, args)
    end
end

--- Picked masteries listing the skill whose members are all at 10 (those earn and pay).
local function activeMasteriesOf(player, perk)
    local list = {}
    for _, id in ipairs(M.masteriesOf[perk:getId()] or {}) do
        if M.isPicked(player, id) and M.membersAt10(player, id) then table.insert(list, id) end
    end
    return list
end

--- A level-10 skill is parked only while a picked, active mastery lists it (user, 2026-11-10). A parked skill lets
--- gains land, and Java's AddXP then shows its "<skill> XP: n" halo (`XP.AddXP` ~281, for awards made with haloText
--- on the local player: foraging, for one); for a skill no mastery takes, that showed XP going nowhere. Any other
--- level-10 skill sits at vanilla's total(10), where AddXP returns before the halo, as in vanilla.
local function wantsPark(player, perk)
    return #activeMasteriesOf(player, perk) > 0
end

--- Back to vanilla's cap from the park line: at most PARK_MARGIN up, under the XP anti-cheat's 250 floor.
local function unpark(player, perk)
    return setRawXp(player, perk, M.total10(perk))
end

local function addPoints(player, masteryId, points)
    local e = M.entry(player, true)
    local before = e.points[masteryId] or 0
    local after = math.max(0, before + points)
    e.points[masteryId] = after
    markDirty(player)
    if points > 0 then
        local l1, l2 = M.levelInfo(before), M.levelInfo(after)
        if l2 > l1 then M.notifyLevelUp(player, masteryId, l2) end
    end
end

-- ---------------------------------------------------------------------------------------------------------------
-- The AddXP event
-- ---------------------------------------------------------------------------------------------------------------

local function onAddXP(player, perk, amount)
    if adjusting or not amount or amount == 0 then return end
    if adminVanilla then
        -- Admin skill cheat: the XP stays vanilla XP. Park a skill it brought to 10, bank nothing, eat no mastery.
        if instanceof(player, "IsoPlayer") and player:getPerkLevel(perk) >= 10
            and M.rawXp(player, perk) > M.parkValue(perk) + M.EPS and wantsPark(player, perk) then
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
        -- park if above the line and a mastery takes the skill, nothing to bank.
        if raw > parkAt + M.EPS and wantsPark(player, perk) then park(player, perk) end
        return
    end

    local earners = activeMasteriesOf(player, perk)
    if amount > 0 then
        if suppress <= 0 and #earners > 0 then
            -- Mastery is experience, never reading: take a skill book multiplier back out.
            local mult = player:getXp():getMultiplier(perk)
            local earned = mult > 1 and amount / mult or amount
            local points = M.pointsFor(perk, earned)
            for _, id in ipairs(earners) do addPoints(player, id, points) end
        end
        -- No earner left (a pick removed, a member dropped below 10 before the pass saw it): back to vanilla's cap.
        if #earners > 0 then park(player, perk) else unpark(player, perk) end
        return
    end

    -- Negative XP (decay): Conditioning slows it, then every earning mastery listing the skill pays what it can.
    -- The skill stays at 10 while at least one paid in full.
    local need = -amount * M.less(player, "Conditioning.Decay")
    local needPts = M.pointsFor(perk, need)
    local e = M.entry(player, true)
    local paid = 0
    for _, id in ipairs(earners) do
        local pay = math.min(e.points[id] or 0, needPts)
        if pay > 0 then addPoints(player, id, -pay) end
        paid = math.max(paid, pay)
    end
    if paid >= needPts - 0.000001 then
        park(player, perk)
        return
    end
    local rest = M.xpForPoints(perk, needPts - paid)
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
    local picks, points = {}, {}
    if e then
        for i, id in ipairs(e.picks) do picks[i] = id end
        for k, v in pairs(e.points) do points[k] = v end
    end
    return { username = player:getUsername(), picks = picks, points = points }
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
            if wantsPark(player, perk) then
                if raw >= M.total10(perk) - M.EPS then park(player, perk) end
            elseif M.isParked(player, perk, raw) then
                -- Picked away, inactive, or parked by an older version: vanilla's cap. Only from the park line
                -- (isParked), so a level-10 skill an admin left far below the cap is never raised past the anti-cheat.
                unpark(player, perk)
            end
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

local MAX_POINTS = 1e7

--- Picking a mastery (the Mastery tab's Pick button). Checked here, whoever asks: the mastery exists, is not picked,
--- is not coming soon, a slot is free and every member skill is at 10. Returns true when picked.
function M.pick(player, masteryId)
    if not player or type(masteryId) ~= "string" or not M.masteryById[masteryId] then return false end
    local e = M.entry(player, true)
    if M.COMING_SOON[masteryId] or M.isPicked(player, masteryId) or #e.picks >= M.MAX_PICKS
        or not M.membersAt10(player, masteryId) then
        print("[TienSkillMastery] refused pick of " .. masteryId .. " by " .. tostring(player:getUsername()))
        return false
    end
    table.insert(e.picks, masteryId)
    e.points[masteryId] = 0
    markDirty(player)
    print(string.format("[TienSkillMastery] %s picked %s (%d of %d)", tostring(player:getUsername()), masteryId,
        #e.picks, M.MAX_PICKS))
    return true
end

--- args: { mastery = id, op = "add" | "remove" | "level" | "clear" | "unpick", amount = points, level = n }, on a
--- picked mastery of the admin's own character. Removing a pick takes its progress too (user, 2026-11-07).
--- Returns true when applied.
function M.adminChange(player, args)
    if type(args) ~= "table" or not player then return false end
    local id = args.mastery
    if type(id) ~= "string" or not M.masteryById[id] or not M.isPicked(player, id) then return false end
    local e = M.entry(player, true)
    local before = e.points[id] or 0
    local points = before
    local amount = math.max(0, math.min(MAX_POINTS, tonumber(args.amount) or 0))
    if args.op == "add" then
        points = math.min(MAX_POINTS, points + amount)
    elseif args.op == "remove" then
        points = math.max(0, points - amount)
    elseif args.op == "level" then
        local level = math.max(0, math.min(100, math.floor(tonumber(args.level) or 0)))
        points = M.pointsForLevel(level)
    elseif args.op == "clear" then
        points = 0
    elseif args.op == "unpick" then
        for i = #e.picks, 1, -1 do
            if e.picks[i] == id then table.remove(e.picks, i) end
        end
        e.points[id] = nil
        markDirty(player)
        print(string.format("[TienSkillMastery] %s removed own pick %s (%.1f points)", tostring(player:getUsername()),
            id, before))
        return true
    else
        return false
    end
    e.points[id] = points
    markDirty(player)
    -- Same level-up feedback as earned mastery (user, 2026-11-06), once for the new level, only when it went up.
    local levelBefore, levelAfter = M.levelInfo(before), M.levelInfo(points)
    if levelAfter > levelBefore and M.membersAt10(player, id) then M.notifyLevelUp(player, id, levelAfter) end
    print(string.format("[TienSkillMastery] %s set own %s mastery points %.1f -> %.1f (%s)",
        tostring(player:getUsername()), id, before, points, tostring(args.op)))
    return true
end

--- Admin "Max All": every skill below 10 goes to 10, mastery untouched. `XP.AddXP` runs `LevelPerk` once per level
--- crossed, each with its halo line and level-up sound (350 of each from a fresh character), so a skill is set to 9
--- first and crosses only the last level. `xpUpdate.levelPerk` tests only level ranges and thresholds, so level 10
--- gives the same traits and recipes as climbing there. One over the gap is awarded because Java clamps at total(10)
--- and float rounding must not stop short of it. AddXP does nothing while asleep, or for Fitness with weight trouble
--- (`canAddFitnessXp`): such a skill gets its old level back and is logged.
local function maxAllSkills(player)
    local raised, failed = 0, {}
    for _, perk in ipairs(M.perks()) do
        local before = player:getPerkLevel(perk)
        if before < 10 then
            local gap = M.total10(perk) - M.rawXp(player, perk) + 1
            player:setPerkLevelDebug(perk, 9)
            adminVanilla = true
            pcall(addXpNoMultiplier, player, perk, gap / proteinFactor(player, perk))
            adminVanilla = false
            if player:getPerkLevel(perk) >= 10 then
                if M.rawXp(player, perk) > M.parkValue(perk) + M.EPS and wantsPark(player, perk) then
                    park(player, perk)
                end
                raised = raised + 1
            else
                player:setPerkLevelDebug(perk, before)
                table.insert(failed, perk:getId())
            end
        end
    end
    print(string.format("[TienSkillMastery] %s maxed own skills: %d raised, not raised: %s",
        tostring(player:getUsername()), raised, #failed > 0 and table.concat(failed, ", ") or "none"))
    return true
end

--- Admin cheat on the vanilla skill (the Skills tab's right-click menu): args { perk = id, op = "add" | "remove" |
--- "level", amount = n, level = n }, or { op = "maxAll" } for every skill. Goes through the `addXpNoMultiplier` global: on a server that is
--- GameServer.addXp (no boosts, then `updateXpChecker`, so the XP anti-cheat's snapshot follows, as for /addxp), in
--- single player a plain AddXP without boosts. Java's level loops do the levelling (several levels in one award), and
--- the Strength protein factor is divided out so the amount lands as asked. A parked skill is first put back at
--- vanilla's total(10) so a removal counts from the real cap. Mastery is left as it is (it only counts at 10).
function M.adminSkill(player, args)
    if type(args) ~= "table" or not player then return false end
    if args.op == "maxAll" then return maxAllSkills(player) end
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
    -- Back to the park line when the skill is (still) 10 and a mastery takes it.
    if player:getPerkLevel(perk) >= 10 and M.rawXp(player, perk) > M.parkValue(perk) + M.EPS
        and wantsPark(player, perk) then
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
    elseif command == "pick" then
        if M.pick(player, type(args) == "table" and args.mastery) then send(player) end
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
