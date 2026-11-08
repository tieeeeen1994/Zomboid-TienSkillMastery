--[[
Tien's Skill Mastery: Field Medicine's signature, field triage (user's design, 2026-11-06), 42.21.

"Tend wounds" on yourself or a player next to you walks there and queues vanilla's own treatments. The goal (user,
2026-11-09): the **fewest actions that stop health loss**, with what is carried right now. What a part gets depends on
its wounds (`T.woundsOf`, plain flags, sent over the network) and the supplies (`T.actions`, which `T.borrow` and the
client's queue both call, so they agree). What each treatment does in `BodyPart.DamageUpdate` (42.21 ~144):
- Scratch, cut, bite, burn, bleeding: a bandage stops the damage (`ISApplyBandage`), infected or not (user, 2026-11-08:
  those were skipped whole before). Infection itself asks for nothing (user, 2026-11-09: it can wait, the point is
  to stop health loss now): `DamageUpdate` takes no health for it and clears it once every wound timer is 0 (~482), so
  an infected part always has a wound, and one with no open wound is a stitch or a fracture, which a bandage does not help.
- Deep wound: a bandage only halves it until it closes; `ISStitch` with a `SutureNeedle` (user, 2026-11-09, not plain
  needle and thread) ends it, bleeding included (`setStitched`), so a stitched part needs no bandage for that wound.
- Glass: no damage of its own, but a deep wound with glass in never closes (held at 3, ~405) and vanilla will not stitch
  it, so it comes out of a deep wound first (`ISRemoveGlass`, by hand with pain without tweezers / suture needle
  holder). Glass with no deep wound only gets the bandage.
- Bullet: halved under a bandage and never ends. `ISRemoveBullet` (tweezers or suture needle holder) leaves a bleeding
  deep wound that an open part never closes (held at 3), so it comes out only with a stitch or a bandage to follow.
- Fracture: only `ISSplint` stops it (a splint, or a plank / stick with ripped sheets; not head or torso); a bandage only
  eases the pain (`/ 1.5`), so a fracture alone gets no bandage.
Missing a tool: bandage for now where that helps, and every later triage looks again (user, 2026-11-09), so a part
already bandaged still gets what it could not have then. Stitch, splint and glass need nothing done to the bandage:
their actions do not ask, though vanilla's menu does for the stitch (`BaseHandler:isInjured`), and `setStitched` leaves
it on. A bullet needs it off first: `setHaveBullet(false)` -> `setDeepWounded(true)` clears `bandaged`, losing the old
one, and `ISRemoveBullet`'s sync does not carry that flag. If other wounds were under it, a spare bandage must be there
to cover them again: the old one only exists once it is off, too late for the queue to pick it.
No disinfecting, burn cleaning, poultices or pills. The best bandage carried goes first
(highest `getBandagePower`, alcoholic before plain). Those actions already treat another player and get Field
Medicine's treatment time and strength like any other treatment.

Order (user, 2026-11-08): `T.plan` takes everyone being tended, the doctor included, and merges them into one list of
body parts, each part's treatments together in the order above. Anyone under `T.CRITICAL_HEALTH` overall health comes
first, whatever their wounds; inside each of those two groups the part costing the most overall health goes first
(`T.drain`). So a stranger's bleeding neck comes before the doctor's scratch, and the doctor's scratch before the
stranger's bleeding neck if only the doctor is dying. The plan is made once, when the treatment starts.
`T.drain` follows `BodyPart.DamageUpdate` (42.21 ~142): per update, each wound takes its own amount (burn 3.75, deep
wound / bullet / unsplinted fracture 3.125, bite 2.1875, cut 1.875, scratch 0.9375) from that part, times
`getDamageScaler()` (neck x 5). A bandage stops all of those but deep wounds and bullets (half) and fractures (full).
Unbandaged, bleeding takes 0.2857 x bleeding time / 10 x the scaler through
`ReduceGeneralHealth`. `BodyDamage.calculateOverallHealth` (~2437) adds up each part's missing health times
`BodyPartType.getDamageModifyer` (hand 0.1 ... neck 0.7) while `ReduceGeneralHealth` divides by that modifier and by the
17 parts, so bleeding counts in full and a part's own damage counts times its modifier. All wounds of the part count,
burns too, even though triage only stops them when it bandages. A part already at 0 health has nothing left to lose but
can still bleed.

Where the plan comes from: another player's body on an MP client is a full-health fake (`BodyDamage.Update` restores
remote players every update, ZomboidFixesB42 "Player stats are server-authoritative"), so when anyone else is tended
the client sends `triage { targets, self }` and the server plans from the real bodies (the doctor's too, for the merged
order). Supplies come from the doctor **and** the patient: walking the plan in order, each step uses what the doctor
has while it lasts, then that step's patient's, which the server moves to the doctor's main inventory
(`DoRemoveItem` + `sendRemoveItemFromContainer`, `AddItem` + `sendAddItemToContainer`, as TienGiveItemMP moves items
between players), then answers `triagePlan { steps, moved }`. So when supplies run short the worst wounds get them, and
what one patient lends is used on that patient only (a borrowed tweezers excepted: it is not used up). The client waits
until the moved items are in its inventory (an item packet and a server command are not ordered), then queues.
Whatever is still unused when the queue ends or is cancelled goes back to its owner (`triageReturn`, one per patient).
Yourself alone and single player read the bodies directly and do the same moves locally.

`ISApplyBandage` / `ISSplint` `complete` remove the item from the doctor's main inventory only, so every item is moved
out of bags first (`ISInventoryPaneContextMenu.transferIfNeeded`).
]]

require "TienSkillMastery"
require "TienSkillMastery_Throw"   -- its key binding opens this mod's section in the key bindings
local M = TienSkillMastery

M.Triage = M.Triage or {}
local T = M.Triage

local NO_SPLINT = { Head = true, Torso_Upper = true, Torso_Lower = true }
local PLANKS = { Plank = true, TreeBranch2 = true, WoodenStick2 = true, TreeBranch = true, WoodenStick = true }
T.RANGE = 3
T.TEND_TILES = 2         -- a patient may move about while being tended, this close (see the menu file's header)
T.CRITICAL_HEALTH = 25   -- overall health (0-100) under which a person's parts go before everyone else's
T.MAX_TARGETS = 8        -- how many other players one request may name
T.KEY_NAME = "TsmTendWounds"

-- The key binding (default comma, free in vanilla; Options > Key bindings > Tien's Skill Mastery).
if keyBinding then
    table.insert(keyBinding, { value = T.KEY_NAME, key = Keyboard.KEY_COMMA })
end

--- What this part costs its owner's overall health per update, on one scale for every part and person (see the header).
function T.drain(part)
    local bandaged = part:bandaged()
    local wounds = 0
    if part:getHealth() > 0 then
        local deep = bandaged and 1.5625 or 3.125
        if part:getDeepWoundTime() > 0 and not part:stitched() then wounds = wounds + deep end
        if part:haveBullet() then wounds = wounds + deep end
        if part:getFractureTime() > 0 and not part:isSplint() then wounds = wounds + 3.125 end
        if not bandaged then
            if part:getScratchTime() > 0 then wounds = wounds + 0.9375 end
            if part:getCutTime() > 0 then wounds = wounds + 1.875 end
            if part:getBiteTime() > 0 then wounds = wounds + 2.1875 end
            if part:getBurnTime() > 0 then wounds = wounds + 3.75 end
        end
    end
    local scaler = part:getDamageScaler()
    local drain = wounds * scaler * BodyPartType.getDamageModifyer(part:getIndex())
    if part:getBleedingTime() > 0 and not bandaged then drain = drain + 0.2857143 * part:getBleedingTime() / 10 * scaler end
    return drain
end

--- A part's wounds as plain flags: they travel in the `triagePlan` command.
function T.woundsOf(part)
    local w = {}
    local function flag(name, on) if on then w[name] = true end end
    flag("bandaged", part:bandaged())
    flag("glass", part:haveGlass())
    flag("bullet", part:haveBullet())
    flag("deep", (part:isDeepWounded() or part:getDeepWoundTime() > 0) and not part:stitched())
    flag("splint", part:getFractureTime() > 0 and part:getSplintFactor() <= 0
        and not NO_SPLINT[tostring(part:getType())])
    -- What only a bandage helps. Bleeding of a deep wound or bullet goes with them.
    flag("other", part:scratched() or part:getScratchTime() > 0 or part:isCut() or part:getCutTime() > 0
        or part:bitten() or part:getBiteTime() > 0 or part:getBurnTime() > 0
        or (part:getBleedingTime() > 0 and not w.deep and not w.bullet) or (w.glass and not w.deep))
    return w
end

--- The fewest treatments for these wounds with these supplies (`has.tweezers`, `has.suture`, `has.bandage`), in order:
--- "unbandage", "glass", "bullet", "stitch", "bandage", "splint". See the header.
function T.actions(w, has)
    local acts = {}
    local function add(act) acts[#acts + 1] = act end
    local bulletOut = w.bullet and has.tweezers and (has.suture or has.bandage)
    -- Taking the bullet out uncovers what the old bandage covered.
    if bulletOut and w.bandaged and w.other and not has.bandage then bulletOut = false end
    local stitch = has.suture and (bulletOut or (w.deep and not w.bullet))
    if bulletOut and w.bandaged then add("unbandage") end
    if w.glass and w.deep then add("glass") end
    if bulletOut then add("bullet") end
    if stitch then add("stitch") end
    if not w.bandaged or bulletOut then
        if w.other or ((w.deep or w.bullet) and not stitch) then add("bandage") end
    end
    if w.splint then add("splint") end
    return acts
end

local EVERYTHING = { tweezers = true, suture = true, bandage = true }

--- Steps for a list of people: { { patient = character, part = index, w = T.woundsOf(part) } }, one per part that has
--- anything left to do, most urgent first (see the header).
function T.plan(people)
    local groups = {}
    for _, person in ipairs(people) do
        local body = person:getBodyDamage()
        local critical = body:getOverallBodyHealth() < T.CRITICAL_HEALTH
        local parts = body:getBodyParts()
        for i = 0, parts:size() - 1 do
            local part = parts:get(i)
            local w = T.woundsOf(part)
            if #T.actions(w, EVERYTHING) > 0 then
                local step = { patient = person, part = part:getIndex(), w = w }
                groups[#groups + 1] = { step = step, critical = critical, drain = T.drain(part), seq = #groups }
            end
        end
    end
    table.sort(groups, function(a, b)
        if a.critical ~= b.critical then return a.critical end
        if a.drain ~= b.drain then return a.drain > b.drain end
        return a.seq < b.seq
    end)
    local steps = {}
    for _, group in ipairs(groups) do steps[#steps + 1] = group.step end
    return steps
end

--- Close enough to go on treating: at most `T.TEND_TILES` tiles along each axis, same floor (the rule of vanilla's Trade).
function T.closeEnough(doctor, patient)
    return math.abs(math.floor(patient:getX()) - math.floor(doctor:getX())) <= T.TEND_TILES
        and math.abs(math.floor(patient:getY()) - math.floor(doctor:getY())) <= T.TEND_TILES
        and math.floor(patient:getZ()) == math.floor(doctor:getZ())
end

function T.isTweezers(item)
    return item:hasTag(ItemTag.REMOVE_BULLET) or item:getType() == "Tweezers" or item:getType() == "SutureNeedleHolder"
end
function T.isGlassTool(item)
    return item:hasTag(ItemTag.REMOVE_GLASS) or item:getType() == "Tweezers" or item:getType() == "SutureNeedleHolder"
end
function T.isBandage(item) return item:getBandagePower() > 0 end
function T.isSuture(item) return item:getType() == "SutureNeedle" end
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

--- Walks the plan in order and moves to the doctor's main inventory what each step needs and the doctor is out of,
--- from that step's patient (splints: a splint, or a plank and a sheet). The client's queue picks in the same order.
--- Returns { { patient = character, ids = { item ID, ... } }, ... }.
function T.borrow(doctor, steps)
    local mine = T.items(doctor:getInventory())
    local own = { bandage = count(mine, T.isBandage), suture = count(mine, T.isSuture),
        tweezers = count(mine, T.isTweezers) > 0, splint = count(mine, T.isSplint), plank = count(mine, T.isPlank), sheet = count(mine, T.isSheet) }
    local theirs, take = {}, {}
    local function spare(patient, pred)
        if patient == doctor then return nil end
        theirs[patient] = theirs[patient] or T.items(patient:getInventory())
        for _, it in ipairs(theirs[patient]) do
            if pred(it) and not take[it] then return it end
        end
        return nil
    end
    local function takeFrom(patient, pred)
        local it = spare(patient, pred)
        if it then take[it] = patient end
        return it ~= nil
    end
    local function useOne(kind, patient, pred)
        if own[kind] > 0 then own[kind] = own[kind] - 1 else takeFrom(patient, pred) end
    end
    for _, s in ipairs(steps) do
        local has = { tweezers = own.tweezers or spare(s.patient, T.isTweezers) ~= nil,
            suture = own.suture > 0 or spare(s.patient, T.isSuture) ~= nil,
            bandage = own.bandage > 0 or spare(s.patient, T.isBandage) ~= nil }
        for _, act in ipairs(T.actions(s.w, has)) do
            if act == "bandage" then
                useOne("bandage", s.patient, T.isBandage)
            elseif act == "stitch" then
                useOne("suture", s.patient, T.isSuture)
            elseif act == "bullet" then
                if not own.tweezers then own.tweezers = takeFrom(s.patient, T.isTweezers) end
            elseif act == "splint" then
                if own.splint > 0 then
                    own.splint = own.splint - 1
                elseif own.plank > 0 and own.sheet > 0 then
                    own.plank, own.sheet = own.plank - 1, own.sheet - 1
                elseif not takeFrom(s.patient, T.isSplint) then
                    local plank = own.plank > 0 or spare(s.patient, T.isPlank)
                    local sheet = own.sheet > 0 or spare(s.patient, T.isSheet)
                    if plank and sheet then
                        if own.plank > 0 then own.plank = own.plank - 1 else take[plank] = s.patient end
                        if own.sheet > 0 then own.sheet = own.sheet - 1 else take[sheet] = s.patient end
                    end
                end
            end
        end
    end
    local moved, byPatient = {}, {}
    local dest = doctor:getInventory()
    for item, patient in pairs(take) do
        local from = item:getContainer()
        if from then
            from:DoRemoveItem(item)
            if isServer() then sendRemoveItemFromContainer(from, item) end
            dest:AddItem(item)
            if isServer() then sendAddItemToContainer(dest, item) end
            if not byPatient[patient] then
                byPatient[patient] = { patient = patient, ids = {} }
                moved[#moved + 1] = byPatient[patient]
            end
            table.insert(byPatient[patient].ids, item:getID())
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

-- Server: plan from the real bodies, borrow, answer (always, so the client is not left waiting); give back on request.
if isServer() then
    Events.OnClientCommand.Add(function(module, command, player, args)
        if module ~= M.MODULE or type(args) ~= "table" or not player then return end
        if command == "triageReturn" then
            local patient = getPlayerByOnlineID(tonumber(args.target) or -1)
            if patient then T.giveBack(player, patient, args.ids) end
            return
        end
        if command ~= "triage" then return end
        local wire = { steps = {}, moved = {} }
        if M.sig(player, "FieldMedicine.SigTriage") then
            local people, seen = {}, { [player] = true }
            if args.self == true then people[1] = player end
            local i = 1
            while type(args.targets) == "table" and args.targets[i] ~= nil and i <= T.MAX_TARGETS do
                local patient = getPlayerByOnlineID(tonumber(args.targets[i]) or -1)
                if patient and not seen[patient] and patient:DistToProper(player) <= T.RANGE then
                    seen[patient] = true
                    people[#people + 1] = patient
                end
                i = i + 1
            end
            local steps = T.plan(people)
            for _, entry in ipairs(T.borrow(player, steps)) do
                table.insert(wire.moved, { who = entry.patient:getOnlineID(), ids = entry.ids })
            end
            for _, s in ipairs(steps) do
                table.insert(wire.steps, { who = s.patient:getOnlineID(), part = s.part, w = s.w })
            end
        end
        sendServerCommand(player, M.MODULE, "triagePlan", wire)
    end)
end
