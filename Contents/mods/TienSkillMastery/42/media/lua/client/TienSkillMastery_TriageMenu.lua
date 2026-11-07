--[[
Tien's Skill Mastery: the "Tend wounds" options of Field Medicine's triage (plan and supplies in
shared/TienSkillMastery_Triage.lua).

World context menu (`OnFillWorldObjectContextMenu`): "Tend wounds" for yourself, and "Tend wounds: <name>" for each
other player within 3 tiles (an MP client's `getOnlinePlayers()` holds the players it has loaded; single player: the
other local players). For another player in MP the plan comes from the server (`triage` -> `triagePlan`); the queue
is built once the items the server moved from the patient are in this client's inventory (or after 3 s). Each step
picks its item (the best bandage first; each item used once), moves it out of bags and queues vanilla's action for
that body part; the doctor first walks next to the patient (`luautils.walkAdj`). When the queue is done or cancelled,
the patient's unused supplies are given back.
]]

require "TienSkillMastery"
require "TienSkillMastery_Triage"
local M = TienSkillMastery
local T = M.Triage

local pending = nil    -- { doctor, patient, steps, moved, untilMs } waiting for borrowed items to arrive
local watching = nil   -- { doctor, patient, moved, started, idleSince }

local function partOf(patient, index)
    return patient:getBodyDamage():getBodyPart(BodyPartType.FromIndex(index))
end

--- Picks the first unused item of the doctor's tree matching `pred`, best by `rank` (higher first).
local function pick(items, used, pred, rank)
    local best, bestRank = nil, nil
    for _, it in ipairs(items) do
        if not used[it] and pred(it) then
            local r = rank and rank(it) or 0
            if not best or r > bestRank then best, bestRank = it, r end
        end
    end
    if best then used[best] = true end
    return best
end

local function bandageRank(item)
    return item:getBandagePower() * 10 + (item:isAlcoholic() and 1 or 0)
end

local function queueSteps(doctor, patient, steps, moved)
    if patient ~= doctor and not luautils.walkAdj(doctor, patient:getCurrentSquare()) then return end
    local items = T.items(doctor:getInventory())
    local used = {}
    local glassTool = pick(items, {}, T.isGlassTool)
    local tweezers = pick(items, {}, T.isTweezers)
    local queued = 0
    for _, s in ipairs(steps) do
        local part = partOf(patient, s.part)
        if s.act == "glass" then
            if glassTool then ISInventoryPaneContextMenu.transferIfNeeded(doctor, glassTool) end
            ISTimedActionQueue.add(ISRemoveGlass:new(doctor, patient, part, glassTool == nil))
            queued = queued + 1
        elseif s.act == "bullet" and tweezers then
            ISInventoryPaneContextMenu.transferIfNeeded(doctor, tweezers)
            ISTimedActionQueue.add(ISRemoveBullet:new(doctor, patient, part))
            queued = queued + 1
        elseif s.act == "splint" then
            local splint = pick(items, used, T.isSplint)
            if splint then
                ISInventoryPaneContextMenu.transferIfNeeded(doctor, splint)
                ISTimedActionQueue.add(ISSplint:new(doctor, patient, nil, splint, part, true))
                queued = queued + 1
            else
                local plank, sheet = pick(items, used, T.isPlank), pick(items, used, T.isSheet)
                if plank and sheet then
                    ISInventoryPaneContextMenu.transferIfNeeded(doctor, sheet)
                    ISInventoryPaneContextMenu.transferIfNeeded(doctor, plank)
                    ISTimedActionQueue.add(ISSplint:new(doctor, patient, sheet, plank, part, true))
                    queued = queued + 1
                end
            end
        elseif s.act == "bandage" then
            local bandage = pick(items, used, T.isBandage, bandageRank)
            if bandage then
                ISInventoryPaneContextMenu.transferIfNeeded(doctor, bandage)
                ISTimedActionQueue.add(ISApplyBandage:new(doctor, patient, bandage, part, true))
                queued = queued + 1
            end
        end
    end
    if moved and #moved > 0 then
        -- Nothing queued: give back at once (the watcher sees an idle queue).
        watching = { doctor = doctor, patient = patient, moved = moved, started = queued > 0 and getTimestampMs() or 0 }
    end
end

local function giveBack(w)
    if isClient() and w.patient ~= w.doctor then
        sendClientCommand(w.doctor, M.MODULE, "triageReturn", { target = w.patient:getOnlineID(), ids = w.moved })
    else
        T.giveBack(w.doctor, w.patient, w.moved)
    end
end

local function startTriage(doctor, patient)
    if isClient() and patient ~= doctor then
        sendClientCommand(doctor, M.MODULE, "triage", { target = patient:getOnlineID() })
        pending = { doctor = doctor, patient = patient, asked = getTimestampMs() }
        return
    end
    local steps = T.plan(patient:getBodyDamage())
    local moved = T.borrow(doctor, patient, steps)
    queueSteps(doctor, patient, steps, moved)
end

Events.OnServerCommand.Add(function(module, command, args)
    if module ~= M.MODULE or command ~= "triagePlan" or type(args) ~= "table" or not pending then return end
    if pending.patient:getOnlineID() ~= tonumber(args.target) then return end
    local steps, moved = {}, {}
    local i = 1
    while type(args.steps) == "table" and args.steps[i] ~= nil do
        local s = args.steps[i]
        steps[#steps + 1] = { part = tonumber(s.part), act = s.act }
        i = i + 1
    end
    i = 1
    while type(args.moved) == "table" and args.moved[i] ~= nil do
        moved[#moved + 1] = tonumber(args.moved[i])
        i = i + 1
    end
    pending.steps, pending.moved, pending.untilMs = steps, moved, getTimestampMs() + 3000
end)

Events.OnTick.Add(function()
    local now = getTimestampMs()
    if pending and pending.steps then
        local inv = pending.doctor:getInventory()
        local arrived = true
        for _, id in ipairs(pending.moved) do
            if not inv:getItemWithIDRecursiv(id) then arrived = false break end
        end
        if arrived or now > pending.untilMs then
            local p = pending
            pending = nil
            queueSteps(p.doctor, p.patient, p.steps, p.moved)
        end
    elseif pending and now - pending.asked > 10000 then
        pending = nil   -- no answer (patient gone, refused)
    end
    if watching and now - watching.started > 1000 then
        if ISTimedActionQueue.isPlayerDoingAction(watching.doctor) then
            watching.idleSince = nil
        else
            watching.idleSince = watching.idleSince or now
            if now - watching.idleSince > 1000 then
                local w = watching
                watching = nil
                giveBack(w)
            end
        end
    end
end)

local function nearbyPatients(doctor)
    local list = {}
    local function consider(p)
        if p and p ~= doctor and not p:isDead() and p:DistToProper(doctor) <= T.RANGE then list[#list + 1] = p end
    end
    if isClient() then
        local players = getOnlinePlayers()
        for i = 0, players:size() - 1 do consider(players:get(i)) end
    else
        for i = 0, getNumActivePlayers() - 1 do consider(getSpecificPlayer(i)) end
    end
    return list
end

Events.OnFillWorldObjectContextMenu.Add(function(playerNum, context, worldobjects, test)
    if test then return end
    local doctor = getSpecificPlayer(playerNum)
    if not doctor or not M.sig(doctor, "FieldMedicine.SigTriage") then return end
    context:addOption(getText("IGUI_TienSkillMastery_Triage"), doctor, startTriage, doctor)
    for _, patient in ipairs(nearbyPatients(doctor)) do
        local name = patient:getDisplayName() or patient:getUsername()
        context:addOption(getText("IGUI_TienSkillMastery_TriageOther", name), doctor, startTriage, patient)
    end
end)
