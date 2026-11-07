--[[
Tien's Skill Mastery: Field Medicine's signature, field triage (user's design, 2026-11-06), 42.21.

"Tend wounds" on yourself or a player next to you walks there and queues vanilla's own treatments for every body part
that needs them, in this order: remove glass (`ISRemoveGlass`, by hand with pain when there are no tweezers / suture
needle holder, as vanilla allows), remove bullets (`ISRemoveBullet`, needs tweezers or a suture needle holder:
skipped without), splint fractures (`ISSplint`: a splint, or a plank / stick with ripped sheets; not head or torso),
then bandage every bleeding or open wound (`ISApplyBandage`: scratches, cuts, deep wounds, bites and the holes the
glass and bullets leave). Nothing else: no stitching, disinfecting, burns, poultices or pills. A part with an infected
wound (`isInfectedWound`, the kind that needs disinfectant) is skipped whole, and so is a part already bandaged
(vanilla treats a part only while it is not bandaged, `BaseHandler:isInjured`). The best bandage carried goes first
(highest `getBandagePower`, alcoholic before plain). Those actions already treat another player and get Field
Medicine's treatment time and strength like any other treatment.

Where the plan comes from: another player's body on an MP client is a full-health fake (`BodyDamage.Update` restores
remote players every update, ZomboidFixesB42 "Player stats are server-authoritative"), so for another player the
client sends `triage { target }` and the server builds the plan from the real body. Supplies come from the doctor
**and** the patient: the server counts what the plan needs, and what the doctor lacks it moves from the patient's
inventory tree into the doctor's main inventory (`DoRemoveItem` + `sendRemoveItemFromContainer`, `AddItem` +
`sendAddItemToContainer`, as TienGiveItemMP moves items between players), then answers `triagePlan { steps, moved }`.
The client waits until the moved items are in its inventory (an item packet and a server command are not ordered),
then queues. Whatever of the patient's is still unused when the queue ends or is cancelled goes back
(`triageReturn`). Yourself and single player read the body directly and do the same moves locally.

`ISApplyBandage` / `ISSplint` `complete` remove the item from the doctor's main inventory only, so every item is moved
out of bags first (`ISInventoryPaneContextMenu.transferIfNeeded`).
]]

require "TienSkillMastery"
local M = TienSkillMastery

M.Triage = M.Triage or {}
local T = M.Triage

local NO_SPLINT = { Head = true, Torso_Upper = true, Torso_Lower = true }
local PLANKS = { Plank = true, TreeBranch2 = true, WoodenStick2 = true, TreeBranch = true, WoodenStick = true }
T.RANGE = 3

--- Steps for a body: { { part = index, act = "glass" | "bullet" | "splint" | "bandage" } }, in treatment order.
function T.plan(body)
    local glass, bullet, splint, bandage = {}, {}, {}, {}
    local parts = body:getBodyParts()
    for i = 0, parts:size() - 1 do
        local part = parts:get(i)
        if not part:isInfectedWound() and not part:bandaged() then
            local idx = part:getIndex()
            if part:haveGlass() then glass[#glass + 1] = { part = idx, act = "glass" } end
            if part:haveBullet() then bullet[#bullet + 1] = { part = idx, act = "bullet" } end
            if part:getFractureTime() > 0 and part:getSplintFactor() <= 0
                and not NO_SPLINT[tostring(part:getType())] then
                splint[#splint + 1] = { part = idx, act = "splint" }
            end
            if part:scratched() or part:isCut() or part:isDeepWounded() or part:bitten() or part:haveGlass()
                or part:haveBullet() then
                bandage[#bandage + 1] = { part = idx, act = "bandage" }
            end
        end
    end
    local steps = {}
    for _, list in ipairs({ glass, bullet, splint, bandage }) do
        for _, s in ipairs(list) do steps[#steps + 1] = s end
    end
    return steps
end

function T.isTweezers(item)
    return item:hasTag(ItemTag.REMOVE_BULLET) or item:getType() == "Tweezers" or item:getType() == "SutureNeedleHolder"
end
function T.isGlassTool(item)
    return item:hasTag(ItemTag.REMOVE_GLASS) or item:getType() == "Tweezers" or item:getType() == "SutureNeedleHolder"
end
function T.isBandage(item) return item:getBandagePower() > 0 end
function T.isSplint(item) return item:getType() == "Splint" end
function T.isPlank(item) return PLANKS[item:getType()] == true end
function T.isSheet(item) return item:getType() == "RippedSheets" end

--- Every non-container item in a container tree.
function T.items(container, out)
    out = out or {}
    local list = container:getItems()
    for i = 0, list:size() - 1 do
        local item = list:get(i)
        if item:IsInventoryContainer() then
            T.items(item:getInventory(), out)
        else
            out[#out + 1] = item
        end
    end
    return out
end

local function count(items, pred)
    local n = 0
    for _, it in ipairs(items) do if pred(it) then n = n + 1 end end
    return n
end

--- What the plan needs, by kind: { bandage = n, tweezers = 0|1, splint = n } (splints count as splint, or plank +
--- sheet).
local function needs(steps)
    local n = { bandage = 0, tweezers = 0, splint = 0 }
    for _, s in ipairs(steps) do
        if s.act == "bandage" then n.bandage = n.bandage + 1
        elseif s.act == "bullet" then n.tweezers = 1
        elseif s.act == "splint" then n.splint = n.splint + 1 end
    end
    return n
end

--- Moves what the doctor lacks from the patient to the doctor's main inventory. Returns the moved item IDs.
function T.borrow(doctor, patient, steps)
    if doctor == patient then return {} end
    local n = needs(steps)
    local mine, theirs = T.items(doctor:getInventory()), T.items(patient:getInventory())
    local take = {}
    local function want(pred, missing)
        for _, it in ipairs(theirs) do
            if missing <= 0 then return end
            if pred(it) and not take[it] then
                take[it] = true
                missing = missing - 1
            end
        end
    end
    want(T.isBandage, n.bandage - count(mine, T.isBandage))
    if n.tweezers > 0 and count(mine, T.isTweezers) == 0 then want(T.isTweezers, 1) end
    local splintsMissing = n.splint - count(mine, T.isSplint) - math.min(count(mine, T.isPlank), count(mine, T.isSheet))
    if splintsMissing > 0 then
        local before = splintsMissing
        want(T.isSplint, splintsMissing)
        local got = 0
        for it in pairs(take) do if T.isSplint(it) then got = got + 1 end end
        local still = before - got
        if still > 0 then
            want(T.isPlank, still - count(mine, T.isPlank))
            want(T.isSheet, still - count(mine, T.isSheet))
        end
    end
    local moved = {}
    local dest = doctor:getInventory()
    for item in pairs(take) do
        local from = item:getContainer()
        if from then
            from:DoRemoveItem(item)
            if isServer() then sendRemoveItemFromContainer(from, item) end
            dest:AddItem(item)
            if isServer() then sendAddItemToContainer(dest, item) end
            moved[#moved + 1] = item:getID()
        end
    end
    return moved
end

--- Gives the borrowed items still carried by the doctor back to the patient's main inventory.
function T.giveBack(doctor, patient, ids)
    if not doctor or not patient or type(ids) ~= "table" then return end
    local dest = patient:getInventory()
    local i = 1
    while ids[i] ~= nil do
        local item = doctor:getInventory():getItemWithIDRecursiv(tonumber(ids[i]))
        local from = item and item:getContainer()
        if from then
            from:DoRemoveItem(item)
            if isServer() then sendRemoveItemFromContainer(from, item) end
            dest:AddItem(item)
            if isServer() then sendAddItemToContainer(dest, item) end
        end
        i = i + 1
    end
end

-- Server: plan from the real body, borrow, answer; give back on request.
if isServer() then
    Events.OnClientCommand.Add(function(module, command, player, args)
        if module ~= M.MODULE or type(args) ~= "table" or not player then return end
        if command ~= "triage" and command ~= "triageReturn" then return end
        local patient = getPlayerByOnlineID(tonumber(args.target) or -1)
        if not patient then return end
        if command == "triageReturn" then
            T.giveBack(player, patient, args.ids)
            return
        end
        if not M.sig(player, "FieldMedicine.SigTriage") or patient:DistToProper(player) > T.RANGE then return end
        local steps = T.plan(patient:getBodyDamage())
        local moved = T.borrow(player, patient, steps)
        sendServerCommand(player, M.MODULE, "triagePlan", { target = args.target, steps = steps, moved = moved })
    end)
end
