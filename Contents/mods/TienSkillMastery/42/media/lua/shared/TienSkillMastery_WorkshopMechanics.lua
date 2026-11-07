--[[
Tien's Skill Mastery: Mechanics bonuses (shared/Vehicles/TimedActions, 42.21). Crafting time of handcraft recipes is
not here (ISHandcraftAction belongs to the shared crafting hooks).

Engineering.InstallTime ("less"):
- Install: client/Vehicles/ISUI/ISVehiclePartMenu.lua ~194 / ~197 passes `time - L x time / 15` as `maxTimeInit` to
  ISInstallVehiclePart:new ~133, which stores it as `maxTime` (~141); getDuration ~123 returns `self.maxTime` (1 for
  the mechanics cheat or Timed Action Instant, 0 without part / item). A "stored" action: the server's rebuild gets
  `maxTimeInit` back as a `new` parameter and its getDuration is scaled there; the client / single player scale
  `maxTime` in `create` (shared/TienSkillMastery_Workshop.lua).
- Uninstall: ISUninstallVehiclePart:getDuration ~99 = workTime - L x workTime / 15 (same exceptions), `new` ~119
  `maxTime = o:getDuration()`: "computed", one getDuration wrapper.
The mechanics cheat is left alone on both.

Engineering.EngineRepair ("int", +1 condition per engine part used at mastery 10, rolled per part below it):
- ISRepairEngine:complete ~37 (server / single player): condPerPart = min(5, 1 + (L - engine repair level) / 2),
  added once per EngineParts item (counted recursively, ~45) until the engine reaches 100; the parts used are removed
  with `getSomeTypeRecurse` + `DoRemoveItem` + `sendRemoveItemFromContainer`, then `transmitPartCondition`. The parts
  used = the recursive EngineParts count before minus after; each rolls `M.int`, the sum is added (max 100) and sent
  with `transmitPartCondition` like vanilla. Vanilla's loop already stopped at 100, so no part is used for the bonus.
- ISRepairLightbar:complete ~37: one item, condition + 15 + (L - engine repair level); one roll.
`VehiclePart.setCondition` sends nothing itself; `transmitPartCondition` sets the update flag on the server and does
nothing harmful in single player (vanilla calls it on every side).

Salvaging.Salvage ("pct"): ISTakeEngineParts:complete ~31: x = max(20 - (L - engine repair level), 5),
condForPart = ZombRand(x / 3, x), parts = floor(condition / condForPart), added with
`getInventory():AddItems('Base.EngineParts', n)` + `sendAddItemsToContainer` (~47). The parts it added (main
inventory count before / after) are scaled by `M.scaleInt` and the extra added and sent the same way.
]]

require "TienSkillMastery"
require "TienSkillMastery_Workshop"
local M = TienSkillMastery
local W = M.Workshop

local function mechanicsCheat(action)
    return action.character:isMechanicsCheat()
end

W.wrapStoredDuration(ISInstallVehiclePart, "Engineering.InstallTime", mechanicsCheat)
W.wrapComputedDuration(ISUninstallVehiclePart, "Engineering.InstallTime", mechanicsCheat)

local function addCondition(action, extra)
    local part, vehicle = action.part, action.vehicle
    if extra <= 0 or not part or not vehicle then return end
    local cond = part:getCondition()
    local target = math.min(100, cond + extra)
    if target <= cond then return end
    part:setCondition(target)
    vehicle:transmitPartCondition(part)
end

-- ---------------------------------------------------------------------------------------------------------------
-- Engine repair
-- ---------------------------------------------------------------------------------------------------------------

if ISRepairEngine and ISRepairEngine.complete then
    local orig = ISRepairEngine.complete
    function ISRepairEngine:complete(...)
        if isClient() or not self.character or M.val(self.character, "Engineering.EngineRepair") <= 0 then
            return orig(self, ...)
        end
        local inv = self.character:getInventory()
        local partsBefore = inv:getNumberOfItem("EngineParts", false, true)
        local results = W.pack(orig(self, ...))
        if results[1] ~= false then
            local used = partsBefore - inv:getNumberOfItem("EngineParts", false, true)
            local extra = 0
            for _ = 1, used do
                extra = extra + M.int(self.character, "Engineering.EngineRepair")
            end
            addCondition(self, extra)
        end
        return W.unpack(results)
    end
end

if ISRepairLightbar and ISRepairLightbar.complete then
    local orig = ISRepairLightbar.complete
    function ISRepairLightbar:complete(...)
        if isClient() or not self.character or M.val(self.character, "Engineering.EngineRepair") <= 0 then
            return orig(self, ...)
        end
        local results = W.pack(orig(self, ...))
        if results[1] ~= false then
            addCondition(self, M.int(self.character, "Engineering.EngineRepair"))
        end
        return W.unpack(results)
    end
end

-- ---------------------------------------------------------------------------------------------------------------
-- Engine salvage
-- ---------------------------------------------------------------------------------------------------------------

if ISTakeEngineParts and ISTakeEngineParts.complete then
    local orig = ISTakeEngineParts.complete
    function ISTakeEngineParts:complete(...)
        if isClient() or not self.character or M.val(self.character, "Salvaging.Salvage") <= 0 then
            return orig(self, ...)
        end
        local inv = self.character:getInventory()
        local before = inv:getNumberOfItem("EngineParts", false, false)
        local results = W.pack(orig(self, ...))
        if results[1] ~= false then
            local got = inv:getNumberOfItem("EngineParts", false, false) - before
            if got > 0 then
                local extra = M.scaleInt(self.character, "Salvaging.Salvage", got) - got
                if extra > 0 then
                    local items = inv:AddItems("Base.EngineParts", extra)
                    sendAddItemsToContainer(inv, items)
                end
            end
        end
        return W.unpack(results)
    end
end
