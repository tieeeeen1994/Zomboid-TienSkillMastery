--[[
Tien's Skill Mastery: Engineering's signature, engine overhaul (42.21). Repair raises the engine part's condition;
overhaul raises the car's engine quality, which vanilla sets once at spawn (`Vehicles.Create.Engine`,
server/Vehicles/Vehicles.lua ~262: script quality x vehicle type, randomised, 0-100) and never changes.

What quality does: start attempts retry 1 in quality (`VehicleEngine.updateStarting`); cold starts fail below 100;
fuel burn x (1 + (100 - quality) / 200) (`Vehicles.Update.GasTank` ~464); hotwiring is harder; engine power, but only
as computed at spawn (script force x max(0.6, min(1, quality x 1.6 / 100)), full power from quality 63).

The action (decided 2026-11-06): one Engine Parts = +1 quality, flat, up to 100 (vanilla repair gives up to 5
condition a part, so this is the dearer of the two on purpose); one action uses every Engine Parts carried, up to the
points left, in 300 like Repair Engine. Power is recomputed with vanilla's formula and never lowered.
`setEngineFeature(quality, loudness, power)` stores the loudness x 0.37, so the loudness passed is vanilla's spawn
value (script loudness x sandbox ZombieAttractionMultiplier) and `updatePartStats()` follows (it recomputes loudness
from the muffler). The server sends the engine state with `transmitEngine` (VehicleUpdatePacket flag 4). Shown by
vanilla's "Engine quality" line in the mechanics window.

Shared timed action with a server `complete` that re-checks the signature, the engine part, the wrench and the parts.
The menu option is in client/TienSkillMastery_EngineOverhaulMenu.lua. `new` keeps vanilla ISRepairEngine's parameter
names (the MP server rebuilds the action from them).
]]

require "TimedActions/ISBaseTimedAction"
require "TienSkillMastery"
local M = TienSkillMastery

TienSkillMasteryEngineOverhaul = ISBaseTimedAction:derive("TienSkillMasteryEngineOverhaul")
local A = TienSkillMasteryEngineOverhaul

--- Engine Parts the overhaul would use now (0 when nothing to do).
function M.overhaulParts(character, vehicle)
    if not character or not vehicle then return 0 end
    local room = 100 - vehicle:getEngineQuality()
    if room <= 0 then return 0 end
    return math.min(room, character:getInventory():getNumberOfItem("EngineParts", false, true))
end

function A:isValid()
    return self.vehicle ~= nil and self.part ~= nil and M.overhaulParts(self.character, self.vehicle) > 0
end

function A:waitToStart()
    self.character:faceThisObject(self.vehicle)
    return self.character:shouldBeTurning()
end

function A:update()
    self.character:faceThisObject(self.vehicle)
    self.character:setMetabolicTarget(Metabolics.MediumWork)
end

function A:start()
    self:setActionAnim("VehicleWorkOnMid")
end

function A:complete()
    local chr, vehicle, part = self.character, self.vehicle, self.part
    if not chr or not vehicle or not part or part:getId() ~= "Engine" then return false end
    if not M.sig(chr, "Engineering.SigEngineOverhaul") or not chr:getInventory():containsTag(ItemTag.WRENCH) then
        return false
    end
    local n = M.overhaulParts(chr, vehicle)
    if n <= 0 then return false end
    local items = chr:getInventory():getSomeTypeRecurse("EngineParts", n)
    local used = 0
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        local container = item and item:getContainer()
        if container then
            container:DoRemoveItem(item)
            sendRemoveItemFromContainer(container, item)
            used = used + 1
        end
    end
    if used <= 0 then return false end
    local script = vehicle:getScript()
    local quality = math.min(100, vehicle:getEngineQuality() + used)
    local boosted = math.min(100, quality * 1.6)
    local power = math.max(vehicle:getEnginePower(), script:getEngineForce() * math.max(0.6, boosted / 100))
    local loudness = (script:getEngineLoudness() or 100) * ((SandboxVars and SandboxVars.ZombieAttractionMultiplier) or 1)
    vehicle:setEngineFeature(quality, loudness, power)
    vehicle:updatePartStats()
    if isServer() then pcall(function() vehicle:transmitEngine() end) end
    print(string.format("[TienSkillMastery] %s overhauled vehicle %s: engine quality %d (+%d)",
        tostring(chr:getUsername()), tostring(vehicle:getId()), quality, used))
    return true
end

function A:getDuration()
    if self.character:isTimedActionInstant() then return 1 end
    return self.maxTime
end

function A:new(character, part, item, maxTimeInit)
    local o = ISBaseTimedAction.new(self, character)
    o.part = part
    if part ~= nil then o.vehicle = part:getVehicle() end
    o.item = item
    o.maxTimeInit = maxTimeInit
    o.maxTime = maxTimeInit
    o.jobType = getText("IGUI_TienSkillMastery_Overhaul")
    return o
end
