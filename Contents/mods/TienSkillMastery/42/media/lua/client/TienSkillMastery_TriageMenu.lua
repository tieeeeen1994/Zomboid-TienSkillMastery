--[[
Tien's Skill Mastery: Field Medicine's triage, started by its key (plan and supplies in
shared/TienSkillMastery_Triage.lua). No world menu (user, 2026-11-09: the key only).

The key binding `T.KEY_NAME` (`OnKeyStartPressed`, player 0, as the throw key) tends you and every other player in reach
(`T.RANGE` tiles on your level, not invisible; an MP client's `getOnlinePlayers()` holds the players it has loaded; single
player: the other local players); alone, it tends you. Everyone shares one plan, you included, in `T.plan`'s order.

When anyone else is tended in MP the plan comes from the server (`triage` -> `triagePlan`); the queue is built once the
items the server moved from the patients are in this client's inventory (or after 3 s). Each step picks its item the way
`T.borrow` counted them (the doctor's own while they last, the best bandage first, then what that step's patient lent;
each item used once), moves it out of bags and queues vanilla's action for that body part. Whenever the patient changes
the doctor walks next to the new one (`walkToPatient`, `luautils.walkAdj`'s test from where the queue will have left the
doctor); a patient who cannot be reached is skipped.
Patients may move (user, 2026-11-08): vanilla's treatments stop as soon as the patient has moved at all since they
were queued (`isValid` -> `ISHealthPanel.DidPatientMove`, from `bandagedPlayerX/Y` set in `new`), and `stop` resets the
whole queue. Java reads `isValid` off the table (`LuaTimedActionNew.valid`, `rawget`), only while the action runs and
only on the client (`NetTimedAction` never calls it), so an instance field reaches these actions and nothing else
(vanilla's health panel is untouched): while the patient is `T.closeEnough` it renews those fields and asks vanilla's
`isValid`, which still does the item checks. A doctor driving a car keeps vanilla's rule.
A patient who is gone is skipped and the rest carry on (user, 2026-11-08). Gone = farther than that, dead, or (MP) no
longer the client's player of that online ID. Two ways out, because vanilla's `ISBaseTimedAction.stop` resets the whole
queue and Java treats an action by whether it has started (`IsoGameCharacter` ~9013):
- Not begun yet: the action's `begin` (the queue calls it, nothing has reached Java) goes straight to
  `queue:onCompleted(self)`, which starts the next one. The queued walk to a patient does the same if the patient is
  no longer near where it would lead.
- Running: `isValid` notes it and returns false, Java calls `stop`, and for that one call the queue's `resetQueue` is an
  instance field doing `onCompleted` instead, so vanilla's clean-up runs (sounds, the health panel, the item's job bar)
  and the next action starts, in the same shape as `perform` (`StartAction` replaces the list, Java then removes the old
  action; in MP `LuaTimedActionNew.stop` then cancels the old transaction, and the next request only goes out from its
  `start`, later). A stop for any other reason (the player cancels) still ends the whole queue.
- Begun but not started (turning to face the patient): an invalid action is dropped by Java without `stop`, and the
  queue's `tick` then calls it bugged and resets, so `isValid` stays true until it has started and takes the way above.
While a
treatment is asked for or running, further requests are ignored, so a second press does not restart the bar. When the
queue is done or cancelled, the patients' unused supplies are given back. With nothing that can be treated (no wounds, or
no supplies for them), whatever the doctor was doing carries on.
]]

require "TienSkillMastery"
require "TienSkillMastery_Triage"
local M = TienSkillMastery
local T = M.Triage

local pending = nil    -- { doctor, asked, steps, moved, untilMs }: waiting for the server's plan and borrowed items
local running = nil    -- { doctor, moved, started, idleSince }: the queue is working

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

local function giveBack(doctor, moved)
    for _, entry in ipairs(moved) do
        if isClient() then
            sendClientCommand(doctor, M.MODULE, "triageReturn",
                { target = entry.who or entry.patient:getOnlineID(), ids = entry.ids })
        elseif entry.patient then
            T.giveBack(doctor, entry.patient, entry.ids)
        end
    end
end

--- Dead or no longer this client's player of that online ID.
local function patientLeft(patient)
    return patient:isDead() or (isClient() and getPlayerByOnlineID(patient:getOnlineID()) ~= patient)
end

--- Makes `action` give way to the next one in the queue, without starting, if `isGone()` when its turn comes.
local function skipIfGone(action, isGone)
    local vanillaBegin = action.begin
    action.begin = function(self)
        if isGone() then
            ISTimedActionQueue.getTimedActionQueue(self.character):onCompleted(self)
            return
        end
        return vanillaBegin(self)
    end
end

--- Queues a treatment that goes on while its patient stays close and is skipped once they are gone (see the header).
local function addTreatment(action, doctor, patient)
    if patient ~= doctor then
        local function isGone()
            return patientLeft(patient) or (not doctor:isDriving() and not T.closeEnough(doctor, patient))
        end
        skipIfGone(action, isGone)
        local vanillaIsValid, vanillaStop = action.isValid, action.stop
        action.isValid = function(self)
            if isGone() then
                if not self:isStarted() then return true end
                self.patientGone = true
                return false
            end
            if not doctor:isDriving() then
                self.bandagedPlayerX, self.bandagedPlayerY = patient:getX(), patient:getY()
            end
            return vanillaIsValid(self)
        end
        action.stop = function(self)
            if not self.patientGone then return vanillaStop(self) end
            local queue = ISTimedActionQueue.getTimedActionQueue(self.character)
            queue.resetQueue = function(q)
                q.resetQueue = nil
                q:onCompleted(self)
            end
            vanillaStop(self)
            queue.resetQueue = nil
        end
    end
    ISTimedActionQueue.add(action)
end

--- Queues the walk to `patient` if the doctor will not be next to them; `at` = where the queue has left the doctor.
--- False: they cannot be reached.
local function walkToPatient(doctor, patient, at)
    if patient == doctor or doctor:getVehicle() then return true end
    local square = patient:getCurrentSquare()
    if not square then return false end
    square = luautils.getCorrectSquareForWall(doctor, square)
    if math.abs(square:getX() + 0.5 - at.x) <= 1.6 and math.abs(square:getY() + 0.5 - at.y) <= 1.6
        and at.square and at.square:canReachTo(square) then
        return true
    end
    local adjacent = AdjacentFreeTileFinder.Find(square, doctor)
    if not adjacent then return false end
    local walk = ISWalkToTimedAction:new(doctor, adjacent)
    skipIfGone(walk, function() return patientLeft(patient) or not T.closeEnough(adjacent, patient) end)
    ISTimedActionQueue.add(walk)
    at.square, at.x, at.y = adjacent, adjacent:getX() + 0.5, adjacent:getY() + 0.5
    return true
end

local function queueSteps(doctor, steps, moved)
    if #steps == 0 then
        giveBack(doctor, moved)
        return
    end
    local items = T.items(doctor:getInventory())
    local used = {}
    local lentFor = {}   -- [item ID] = the patient who lent it
    for _, entry in ipairs(moved) do
        for _, id in ipairs(entry.ids) do lentFor[id] = entry.patient or false end
    end
    local function pickOwn(pred, rank)
        return pick(items, used, function(it) return pred(it) and lentFor[it:getID()] == nil end, rank)
    end
    local function pickLent(patient, pred, rank)
        return pick(items, used, function(it) return pred(it) and lentFor[it:getID()] == patient end, rank)
    end
    -- The same choice T.borrow counted: a splint, else a plank and a sheet, the doctor's before the patient's.
    local function splintFor(patient)
        local splint = pickOwn(T.isSplint)
        if splint then return splint end
        local plank, sheet = pickOwn(T.isPlank), pickOwn(T.isSheet)
        if plank and sheet then return nil, plank, sheet end
        splint = pickLent(patient, T.isSplint)
        if not splint then
            plank = plank or pickLent(patient, T.isPlank)
            sheet = sheet or pickLent(patient, T.isSheet)
            if plank and sheet then return nil, plank, sheet end
        end
        if plank then used[plank] = nil end
        if sheet then used[sheet] = nil end
        return splint
    end
    local glassTool = pick(items, {}, T.isGlassTool)
    local tweezers = pick(items, {}, T.isTweezers)
    local at = { square = doctor:getCurrentSquare(), x = doctor:getX(), y = doctor:getY() }
    local current, reachable = nil, true
    local queued = 0
    -- Called once a step has what it needs: only then is what the doctor was doing dropped and a walk queued, so missing
    -- supplies neither interrupt anything nor send the doctor over for nothing.
    local function ready(patient)
        if queued == 0 and not current then ISTimedActionQueue.clear(doctor) end
        if patient ~= current then
            current = patient
            reachable = walkToPatient(doctor, patient, at)
        end
        if reachable then queued = queued + 1 end
        return reachable
    end
    -- Is one of these still free for this patient, the doctor's own or what they lent?
    local function available(patient, pred)
        for _, it in ipairs(items) do
            if not used[it] and pred(it) then
                local lender = lentFor[it:getID()]
                if lender == nil or lender == patient then return true end
            end
        end
        return false
    end
    for _, s in ipairs(steps) do
        local patient = s.patient
        local part = partOf(patient, s.part)
        local has = { tweezers = tweezers ~= nil, suture = available(patient, T.isSuture),
            bandage = available(patient, T.isBandage) }
        for _, act in ipairs(T.actions(s.w, has)) do
            if act == "unbandage" then
                if ready(patient) then
                    addTreatment(ISApplyBandage:new(doctor, patient, nil, part, false), doctor, patient)
                end
            elseif act == "glass" then
                if ready(patient) then
                    if glassTool then ISInventoryPaneContextMenu.transferIfNeeded(doctor, glassTool) end
                    addTreatment(ISRemoveGlass:new(doctor, patient, part, glassTool == nil), doctor, patient)
                end
            elseif act == "bullet" then
                if tweezers and ready(patient) then
                    ISInventoryPaneContextMenu.transferIfNeeded(doctor, tweezers)
                    addTreatment(ISRemoveBullet:new(doctor, patient, part), doctor, patient)
                end
            elseif act == "stitch" then
                local needle = pickOwn(T.isSuture) or pickLent(patient, T.isSuture)
                if needle and ready(patient) then
                    ISInventoryPaneContextMenu.transferIfNeeded(doctor, needle)
                    addTreatment(ISStitch:new(doctor, patient, needle, part, true), doctor, patient)
                end
            elseif act == "splint" then
                local splint, plank, sheet = splintFor(patient)
                if splint then
                    if ready(patient) then
                        ISInventoryPaneContextMenu.transferIfNeeded(doctor, splint)
                        addTreatment(ISSplint:new(doctor, patient, nil, splint, part, true), doctor, patient)
                    end
                elseif plank and sheet and ready(patient) then
                    ISInventoryPaneContextMenu.transferIfNeeded(doctor, sheet)
                    ISInventoryPaneContextMenu.transferIfNeeded(doctor, plank)
                    addTreatment(ISSplint:new(doctor, patient, sheet, plank, part, true), doctor, patient)
                end
            elseif act == "bandage" then
                local bandage = pickOwn(T.isBandage, bandageRank) or pickLent(patient, T.isBandage, bandageRank)
                if bandage and ready(patient) then
                    ISInventoryPaneContextMenu.transferIfNeeded(doctor, bandage)
                    addTreatment(ISApplyBandage:new(doctor, patient, bandage, part, true), doctor, patient)
                end
            end
        end
    end
    -- Nothing queued: anything borrowed goes back at once (the watcher sees an idle queue).
    running = { doctor = doctor, moved = moved, started = queued > 0 and getTimestampMs() or 0 }
end

--- Starts tending `people` (a list of characters, the doctor among them or not).
local function startTriage(doctor, people)
    if pending or running then return end
    local targets, includeSelf = {}, false
    for _, person in ipairs(people) do
        if person == doctor then
            includeSelf = true
        else
            targets[#targets + 1] = person:getOnlineID()
        end
    end
    if isClient() and #targets > 0 then
        sendClientCommand(doctor, M.MODULE, "triage", { targets = targets, self = includeSelf })
        pending = { doctor = doctor, asked = getTimestampMs() }
        return
    end
    local steps = T.plan(people)
    queueSteps(doctor, steps, T.borrow(doctor, steps))
end

Events.OnServerCommand.Add(function(module, command, args)
    if module ~= M.MODULE or command ~= "triagePlan" or type(args) ~= "table" then return end
    local steps, moved = {}, {}
    local i = 1
    while type(args.moved) == "table" and args.moved[i] ~= nil do
        local entry = { who = tonumber(args.moved[i].who), ids = {} }
        entry.patient = getPlayerByOnlineID(entry.who)
        local j = 1
        while type(args.moved[i].ids) == "table" and args.moved[i].ids[j] ~= nil do
            entry.ids[j] = tonumber(args.moved[i].ids[j])
            j = j + 1
        end
        moved[i] = entry
        i = i + 1
    end
    if not pending or pending.steps then
        -- Too late (the wait below gave up): nothing will use what the server just moved.
        local player = getPlayer()
        if player then giveBack(player, moved) end
        return
    end
    i = 1
    while type(args.steps) == "table" and args.steps[i] ~= nil do
        local s = args.steps[i]
        local patient = getPlayerByOnlineID(tonumber(s.who))
        if patient then steps[#steps + 1] = { patient = patient, part = tonumber(s.part), w = s.w } end
        i = i + 1
    end
    pending.steps, pending.moved, pending.untilMs = steps, moved, getTimestampMs() + 3000
end)

Events.OnTick.Add(function()
    local now = getTimestampMs()
    if pending and pending.steps then
        local inv = pending.doctor:getInventory()
        local arrived = true
        for _, entry in ipairs(pending.moved) do
            for _, id in ipairs(entry.ids) do
                if not inv:getItemWithIDRecursiv(id) then arrived = false break end
            end
        end
        if arrived or now > pending.untilMs then
            local p = pending
            pending = nil
            queueSteps(p.doctor, p.steps, p.moved)
        end
    elseif pending and now - pending.asked > 10000 then
        pending = nil   -- no answer
    end
    if running and now - running.started > 1000 then
        if ISTimedActionQueue.isPlayerDoingAction(running.doctor) then
            running.idleSince = nil
        else
            running.idleSince = running.idleSince or now
            if now - running.idleSince > 1000 then
                local r = running
                running = nil
                giveBack(r.doctor, r.moved)
            end
        end
    end
end)

local function nearbyPatients(doctor)
    local list = {}
    local vehicle = doctor:getVehicle()
    local function consider(p)
        if p and p ~= doctor and not p:isDead() and not p:isInvisible() and p:DistToProper(doctor) <= T.RANGE
            and math.floor(p:getZ()) == math.floor(doctor:getZ()) and (not vehicle or p:getVehicle() == vehicle) then
            list[#list + 1] = p
        end
    end
    if isClient() then
        local players = getOnlinePlayers()
        for i = 0, players:size() - 1 do consider(players:get(i)) end
    else
        for i = 0, getNumActivePlayers() - 1 do consider(getSpecificPlayer(i)) end
    end
    return list
end

local function everyoneInReach(doctor)
    local people = nearbyPatients(doctor)
    table.insert(people, 1, doctor)
    return people
end

Events.OnKeyStartPressed.Add(function(key)
    if not getCore():isKey(T.KEY_NAME, key) then return end
    local doctor = getSpecificPlayer(0)
    if not doctor or doctor:isDead() or doctor:isAsleep() or not M.sig(doctor, "FieldMedicine.SigTriage") then return end
    startTriage(doctor, everyoneInReach(doctor))
end)
