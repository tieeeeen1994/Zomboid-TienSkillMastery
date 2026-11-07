--[[
Tien's Skill Mastery: client core.

- Multiplayer: the server keeps mastery (global mod data) and sends the owner its entry ("state") on request and
  whenever it changes (at most once a second). The client asks after login and repeats until the first answer
  comes: a command sent while the server has no player on this connection yet is dropped (42.21 login order:
  `OnGameStart` fires before `sendPlayerConnect`), see ZomboidFixesB42's notes "Login order".
- Single player has no commands: the client reads the same global mod data the server code writes.
- The getXP wrapper (shared core) needs to know which character owns an XP object; local players are noted here
  (the server notes everyone it handles).
]]

require "TienSkillMastery"
local M = TienSkillMastery

M.version = M.version or 0   -- bumped on every change, for the Mastery tab
local answered = false
local nextAsk = 0

--- Display name of a mastery.
function M.masteryName(masteryId)
    return getTextOrNull("IGUI_TienSkillMastery_Mastery_" .. tostring(masteryId)) or tostring(masteryId)
end

--- Vanilla's level-up feedback for a mastery level (see server M.notifyLevelUp): the halo "+1 Firearms Mastery" (or
--- "+1 Firearms Prestige" past 10) with the up arrow in the good colour, and vanilla's level-up sound.
function M.showLevelUp(player, args)
    local id = player and type(args) == "table" and args.mastery
    if not id or not M.masteryById[id] then return end
    local level = tonumber(args.level) or 0
    local key = level > M.BONUS_LEVELS and "IGUI_TienSkillMastery_LevelUpPrestige" or "IGUI_TienSkillMastery_LevelUp"
    HaloTextHelper.addTextWithArrow(player, getText(key, M.masteryName(id)), "[br/]", true, HaloTextHelper.getGoodColor())
    player:playGainExperienceLevelSound()
    M.version = (M.version or 0) + 1
end

local function onServerCommand(module, command, args)
    if module == M.MODULE and command == "levelUp" then
        M.showLevelUp(getPlayer(), args)
        return
    end
    if module ~= M.MODULE or command ~= "state" or type(args) ~= "table" then return end
    if not args.username then return end
    local picks, points = {}, {}
    if type(args.picks) == "table" then
        -- A table sent by the server arrives with number keys as doubles; rebuild the list in order.
        local i = 1
        while args.picks[i] ~= nil do
            if M.masteryById[args.picks[i]] then table.insert(picks, args.picks[i]) end
            i = i + 1
        end
    end
    if type(args.points) == "table" then
        for k, v in pairs(args.points) do points[k] = tonumber(v) or 0 end
    end
    M.clientCache[args.username] = { picks = picks, points = points }
    answered = true
    M.version = M.version + 1
end
Events.OnServerCommand.Add(onServerCommand)

local lastNote = 0
local function onTick()
    local now = getTimestampMs()
    if now - lastNote >= 1000 then
        lastNote = now
        for i = 0, getNumActivePlayers() - 1 do
            local p = getSpecificPlayer(i)
            if p then
                M.installXpWrapper(p)
                M.noteOwner(p)
            end
        end
        if not isClient() then M.version = M.version + 1 end   -- single player: the store may have changed
    end
    if isClient() and not answered and now >= nextAsk then
        local p = getPlayer()
        if p and p:getOnlineID() >= 0 then
            nextAsk = now + 3000
            sendClientCommand(p, M.MODULE, "request", {})
        end
    end
end
Events.OnTick.Add(onTick)

local function onPlayerDeath(player)
    if player and isClient() then
        M.clientCache[player:getUsername()] = nil
        M.version = M.version + 1
    end
end
Events.OnPlayerDeath.Add(onPlayerDeath)

local function onCreatePlayer(playerNum, player)
    if isClient() then
        answered = false
        nextAsk = 0
    end
    if player then
        M.installXpWrapper(player)
        M.noteOwner(player)
    end
end
Events.OnCreatePlayer.Add(onCreatePlayer)
