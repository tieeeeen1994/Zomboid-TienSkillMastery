--[[
Tien's Skill Mastery: Mending's repairs and patches (42.21, server / single player: every hook is a `complete`).

Repairs (Mending.CarefulRepairs "pct", Mending.LastingRepairs "pts"): items are repaired by `ISFixAction:complete`
and installed vehicle parts by `ISFixVehiclePartAction:complete`, both calling Java `FixingManager.fixItem` (~37).
A success adds round(missing condition x repair %) (at least 1) and raises `haveBeenRepaired` by 1, the "Repaired x
times" that makes every later repair weaker and likelier to fail; a failure takes 1 condition; both
`syncItemFields`. The wrapper notes condition and repair count before: after a success the item gets 15% more of
what it gained (at least 1, within its max) and, on a roll, the repair count back; after a failure the lost point
back. The vehicle part then takes the item's condition again (`setCondition`, `doInventoryItemStats`,
`transmitPartItem`, as vanilla's own complete does). Engineering touches no repair, so vehicle parts are Mending's.

Stronger patches (Mending.StrongerPatches "pct"): `Clothing.addPatch` (~1059, from `ISRepairClothing:complete`)
builds a `ClothingPatch(tailorLvl, fabric, hasHole)` whose scratch / bite defense = the fabric's max x level / 10
(Cotton 5 / 0, Denim 10 / 5, Leather 20 / 10), saved per patch (bytes) and summed into the garment's defense. Nothing
clamps the level, and `addPatchForSync(partIdx, level, fabricType, hasHole)` rebuilds a patch at any level. After
vanilla's patch, the master's patch is rebuilt at Tailoring 10 x (1 + bonus) (15 at mastery 10: Leather 30 / 15,
Denim 15 / 7, Cotton 7 / 0). The rebuilt patch has `conditionGain` 0 (a field with no setter), so removing it would
not take back the condition vanilla's patch gave; that gain is kept in the item's modData per part
(`TSM_PatchGain`) and `ISRemovePatch:complete` takes it off before vanilla removes the patch. A patch that fully
restores the garment (`canFullyRestore`, Tailoring 8+) leaves no patch: nothing to do. Vanilla syncs an unworn
garment with `syncItemFields` (carries patches); a worn one's patch reaches its owner's client when the item is
next sent (the server's copy, which rolls zombie hits, is right at once).
]]

require "TienSkillMastery"
require "TimedActions/ISFixAction"
require "TimedActions/ISFixVehiclePartAction"
require "TimedActions/ISRepairClothing"
require "TimedActions/ISRemovePatch"
local M = TienSkillMastery

local function pack(...) return { n = select("#", ...), ... } end

-- ---------------------------------------------------------------------------------------------------------------
-- Repairs
-- ---------------------------------------------------------------------------------------------------------------

--- Returns true when the item changed.
local function afterFix(chr, item, cond, repaired)
    if not item then return false end
    local nowCond, nowRepaired = item:getCondition(), item:getHaveBeenRepaired()
    if nowRepaired > repaired then
        local changed = false
        local gain = nowCond - cond
        local bonus = M.val(chr, "Mending.CarefulRepairs")
        if gain > 0 and bonus > 0 then
            local extra = math.max(1, math.floor(gain * bonus / 100 + 0.5))
            local target = math.min(item:getConditionMax(), nowCond + extra)
            if target > nowCond then
                item:setConditionNoSound(target)
                changed = true
            end
        end
        if M.roll(chr, "Mending.LastingRepairs") then
            item:setHaveBeenRepaired(repaired)
            changed = true
        end
        return changed
    elseif nowCond < cond and M.val(chr, "Mending.CarefulRepairs") > 0 then
        item:setConditionNoSound(cond)
        return true
    end
    return false
end

local function wrapFix(class, name, isVehicle)
    if not class or not class.complete then
        print("[TienSkillMastery] " .. name .. ":complete not found, Mending repairs not applied there")
        return
    end
    local vanilla = class.complete
    class.complete = function(self, ...)
        local chr, item = self.character, self.item
        if not chr or not item or (M.val(chr, "Mending.CarefulRepairs") <= 0 and M.val(chr, "Mending.LastingRepairs") <= 0) then
            return vanilla(self, ...)
        end
        local cond, repaired = item:getCondition(), item:getHaveBeenRepaired()
        local results = pack(vanilla(self, ...))
        local ok, changed = pcall(afterFix, chr, item, cond, repaired)
        if not ok then
            print("[TienSkillMastery] repair bonus failed: " .. tostring(changed))
        elseif changed then
            item:syncItemFields()
            local part = isVehicle and self.vehiclePart
            if part then
                part:setCondition(item:getCondition())
                part:doInventoryItemStats(item, part:getMechanicSkillInstaller())
                part:getVehicle():updatePartStats()
                part:getVehicle():transmitPartItem(part)
            end
        end
        return unpack(results, 1, results.n)
    end
end

wrapFix(ISFixAction, "ISFixAction", false)
wrapFix(ISFixVehiclePartAction, "ISFixVehiclePartAction", true)

-- ---------------------------------------------------------------------------------------------------------------
-- Patches
-- ---------------------------------------------------------------------------------------------------------------

local function partIndex(part)
    return part and part.index and part:index()
end

if ISRepairClothing and ISRepairClothing.complete then
    local vanilla = ISRepairClothing.complete
    function ISRepairClothing:complete(...)
        local chr, clothing, part = self.character, self.clothing, self.part
        local bonus = chr and M.val(chr, "Mending.StrongerPatches") or 0
        if bonus <= 0 or not clothing or not part or not instanceof(clothing, "Clothing") then
            return vanilla(self, ...)
        end
        local hole = clothing:getVisual():getHole(part) > 0
        local cond = clothing:getCondition()
        local results = pack(vanilla(self, ...))
        if results[1] ~= false then
            local ok, err = pcall(function()
                local patch = clothing:getPatchType(part)
                if not patch then return end   -- fully restored: no patch
                local level = math.floor(10 * (1 + bonus / 100))
                local idx = partIndex(part)
                clothing:addPatchForSync(idx, level, patch:getFabricType(), hole)
                local gain = clothing:getCondition() - cond
                if hole and gain > 0 then
                    local md = clothing:getModData()
                    md.TSM_PatchGain = md.TSM_PatchGain or {}
                    md.TSM_PatchGain[tostring(idx)] = gain
                end
                if not chr:isEquippedClothing(clothing) then syncItemFields(chr, clothing) end
            end)
            if not ok then print("[TienSkillMastery] stronger patch failed: " .. tostring(err)) end
        end
        return unpack(results, 1, results.n)
    end
else
    print("[TienSkillMastery] ISRepairClothing:complete not found, Mending.StrongerPatches not applied")
end

if ISRemovePatch and ISRemovePatch.complete then
    local vanilla = ISRemovePatch.complete
    function ISRemovePatch:complete(...)
        local clothing, part = self.clothing, self.part
        local md = clothing and clothing:getModData()
        local gains = md and md.TSM_PatchGain
        local key = part and tostring(partIndex(part))
        if gains and key and gains[key] then
            -- Vanilla's removePatch takes back the patch's conditionGain, which is 0 for a rebuilt patch.
            clothing:setCondition(math.max(0, clothing:getCondition() - gains[key]), false)
            gains[key] = nil
        end
        return vanilla(self, ...)
    end
end
