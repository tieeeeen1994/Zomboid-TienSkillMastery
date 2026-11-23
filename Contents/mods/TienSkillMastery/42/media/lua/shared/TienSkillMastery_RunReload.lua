--[[
Tien's Skill Mastery: Firearms.SigRunReload, the reload animation while running (user, 2026-11-20; traced in the
42.22.2 Java and AnimSets, not played). TienSkillMastery_Signatures.lua keeps the reload going through running; this
file makes the arms play it.

Why the arms stop: reload clips are nodes of the `actions` substate, which `idle`, `movement` (walking) and `strafe`
enter through `to_actions.xml` (IsPerformingAnAction) and `run` / `sprint` never do (their `childTags.xml` lack
`actions`; action groups cannot be modded, see Signatures.lua). Both do enter `maskingright` as a substate whenever the
variable `RightHandMask` is not empty (`actiongroups/player/run|sprint/to_maskingright.xml`, `transitionOut.xml` when
empty), vanilla's layer for a bag, torch or umbrella held while moving. AnimSet nodes can be added from a mod there.

The route:
- `scripts/make_run_reload.py` copies every reload node (PerformingAction Reload, InsertBullets, RemoveBullets) of
  vanilla, Hot Brass VCEF, Gunworks and Guns of Marz (their load order) into
  `AnimSets/player/maskingright/TsmRunReload/`, resolved in full, renamed
  `TsmRun_*`, with one more condition: RightHandMask = TsmRunReload. Same clip, speed (ReloadSpeed), events (sounds,
  Gunworks' magazine and casing events, model swaps) and bone weights; a node without its own weights gets the game's
  default upper-body ones (`AnimNode.Parse`: Spine1 0.5, Neck, BackPack, Prop1, Prop2 1.0), the same that layer the
  reload over walking. Re-run the script when the game, Hot Brass, Gunworks or Guns of Marz change their reload
  nodes (`tests/runreload_test.py` fails until then).
- This file sets RightHandMask = TsmRunReload on a master who is in the `run` or `sprint` action state
  (`getCurrentActionContextStateName`) while performing a reload (`IsPerformingAnAction` and `PerformingAction`), and
  clears it otherwise. The variable's setter (`IsoGameCharacter.setPrimaryHandMask`) wins over the held item's mask
  in `getPrimaryHandMask`; `ModelManager.DoCharacterModelEquipped` clears it whenever hand models are rebuilt, which
  reload events do. That runs in `ModelManager.update`, after the world update (where the animator runs) and before
  `OnTick` (IngameState.updateInternal), so setting it every OnTick has it back before the next animator update.
- Anim events reach the action from any layer (`IsoPlayer.OnAnimEvent` → the first character action), so the
  copies drive sounds the way the walking clip does. In single player the timers in Signatures.lua own the reload's
  progress events and ignore the clip's copies, so a clip restarted by a change of gait cannot restart the reload.
- Other players' games: `RightHandMask` is in no packet (only IsoGameCharacter, ModelManager and Item read it), but a
  remote player's `PerformingAction` and friends are set on their copy by `PlayerActionsState.setParams` (from the
  action's anim variables when it entered) and the action state is synced, so every client sets the mask on remote
  masters as well. Masters are not known to other clients (mastery is the owner's data), so the server sends the
  online IDs of everyone with the signature (`runReloadMasters { list = "id,id" }`) when it changes and to a client
  that asks, as Evasion does.

Left as is: changing gait still restarts the clip (walking uses the `actions` copy, running ours; each starts from
its first frame), and the clip runs on its own clock while the reload is timed by the server (single player: by
Signatures.lua's timers), so the round going in and the clip need not line up.
]]

require "TienSkillMastery"
local M = TienSkillMastery

local R = {}
M.RunReload = R

local ID = "Firearms.SigRunReload"
local MASK = "TsmRunReload"
local ACTIONS = { Reload = true, InsertBullets = true, RemoveBullets = true }
local STATES = { run = true, sprint = true }
local REFRESH_MS = 1000

R.remote = {}      -- client: [online ID] = true, from the server's list
local masked = {}  -- [player] = true while this file has the mask set on them

-- ---------------------------------------------------------------------------------------------------------------
-- Masters, and the server's list for the clients
-- ---------------------------------------------------------------------------------------------------------------

local lastList = ""

local function serverRefresh()
    local ids = {}
    local players = getOnlinePlayers()
    for i = 0, players:size() - 1 do
        local p = players:get(i)
        if p and not p:isDead() and M.sig(p, ID) then table.insert(ids, tostring(p:getOnlineID())) end
    end
    table.sort(ids)
    local s = table.concat(ids, ",")
    if s ~= lastList then
        lastList = s
        sendServerCommand(M.MODULE, "runReloadMasters", { list = s })
    end
end

if isServer() then
    Events.OnClientCommand.Add(function(module, command, player, args)
        if module ~= M.MODULE or command ~= "runReloadMastersRequest" or not player then return end
        sendServerCommand(player, M.MODULE, "runReloadMasters", { list = lastList })
    end)
end

local answered = false
local nextAsk = 0

if isClient() then
    Events.OnServerCommand.Add(function(module, command, args)
        if module ~= M.MODULE or command ~= "runReloadMasters" or type(args) ~= "table" then return end
        local remote = {}
        for id in string.gmatch(tostring(args.list or ""), "%d+") do remote[tonumber(id)] = true end
        R.remote = remote
        answered = true
    end)
end

-- ---------------------------------------------------------------------------------------------------------------
-- The mask
-- ---------------------------------------------------------------------------------------------------------------

--- True while this character should show the running reload.
function R.wants(p)
    if not p or p:isDead() then return false end
    if not STATES[p:getCurrentActionContextStateName()] then return false end
    if not p:getVariableBoolean("IsPerformingAnAction") then return false end
    return ACTIONS[p:getVariableString("PerformingAction")] == true
end

local function isMaster(p, own)
    if own then return M.sig(p, ID) end
    return R.remote[p:getOnlineID()] == true
end

local function update()
    local keep = {}
    local function consider(p, own)
        if p and not keep[p] and isMaster(p, own) and R.wants(p) then
            keep[p] = true
            -- Every tick: hand model rebuilds clear it (see the header).
            if p:getVariableString("RightHandMask") ~= MASK then p:setVariable("RightHandMask", MASK) end
        end
    end
    for i = 0, getNumActivePlayers() - 1 do consider(getSpecificPlayer(i), true) end
    if isClient() then
        for id, _ in pairs(R.remote) do
            local p = getPlayerByOnlineID(id)
            if p and not p:isLocalPlayer() then consider(p, false) end
        end
    end
    for p, _ in pairs(masked) do
        if not keep[p] then
            -- Only ours: anything else would have replaced the value, and the held item's mask comes back by itself.
            if p:getVariableString("RightHandMask") == MASK then p:clearVariable("RightHandMask") end
            masked[p] = nil
        end
    end
    for p, _ in pairs(keep) do masked[p] = true end
end

local lastRefresh = 0

Events.OnTick.Add(function()
    if isServer() then
        local now = getTimestampMs()
        if now - lastRefresh >= REFRESH_MS then
            lastRefresh = now
            serverRefresh()
        end
        return
    end
    if isClient() and not answered then
        local now = getTimestampMs()
        if now >= nextAsk then
            local p = getPlayer()
            if p and p:getOnlineID() >= 0 then
                nextAsk = now + 3000
                sendClientCommand(p, M.MODULE, "runReloadMastersRequest", {})
            end
        end
    end
    update()
end)
