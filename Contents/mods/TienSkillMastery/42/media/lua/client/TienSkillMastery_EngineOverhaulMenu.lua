--[[
Tien's Skill Mastery: the "Overhaul engine" option in the mechanics window's engine menu, beside vanilla's Repair
Engine (client/Vehicles/ISUI/ISVehicleMechanics.lua `doPartContextMenu` ~208 / ~334). Same conditions and the same
queue as `ISVehicleMechanics.onRepairEngine` (~418: wrench and Engine Parts moved to the main inventory, walk to the
engine, open / close the hood, unlock it when needed), with the overhaul action
(shared/TienSkillMastery_EngineOverhaul.lua) in place of ISRepairEngine. Only for a player with the signature.
]]

require "TienSkillMastery"
require "TienSkillMastery_EngineOverhaul"
require "Vehicles/ISUI/ISVehicleMechanics"
local M = TienSkillMastery

local function onOverhaul(playerObj, part)
    if playerObj:getVehicle() then ISVehicleMenu.onExit(playerObj) end
    local _, tagToItem = VehicleUtils.getItems(playerObj:getPlayerNum())
    local wrench = tagToItem[ItemTag.WRENCH] and tagToItem[ItemTag.WRENCH][1]
    if not wrench then return end
    ISVehiclePartMenu.toPlayerInventory(playerObj, wrench)
    local inv = playerObj:getInventory()
    local parts = inv:getSomeTypeRecurse("EngineParts", M.overhaulParts(playerObj, part:getVehicle()))
    for i = 0, parts:size() - 1 do ISVehiclePartMenu.toPlayerInventory(playerObj, parts:get(i)) end
    ISTimedActionQueue.add(ISPathFindAction:pathToVehicleArea(playerObj, part:getVehicle(), part:getArea()))
    local vehicle = part:getVehicle()
    local cover = vehicle:getPartById("EngineDoor")
    if cover and cover:getDoor() and cover:getInventoryItem() and not cover:getDoor():isOpen() then
        if cover:getDoor():isLocked() and VehicleUtils.RequiredKeyNotFound(cover, playerObj) then
            ISTimedActionQueue.add(ISUnlockVehicleDoor:new(playerObj, cover))
        end
        ISTimedActionQueue.add(ISOpenVehicleDoor:new(playerObj, vehicle, cover))
        ISTimedActionQueue.add(TienSkillMasteryEngineOverhaul:new(playerObj, part, wrench, 300))
        ISTimedActionQueue.add(ISCloseVehicleDoor:new(playerObj, vehicle, cover))
    else
        ISTimedActionQueue.add(TienSkillMasteryEngineOverhaul:new(playerObj, part, wrench, 300))
    end
end

local vanilla = ISVehicleMechanics.doPartContextMenu
function ISVehicleMechanics:doPartContextMenu(part, x, y, ...)
    local r = { vanilla(self, part, x, y, ...) }
    local ok, err = pcall(function()
        local chr = self.chr
        if not part or part:getId() ~= "Engine" or not self.context or not chr then return end
        if not M.sig(chr, "Engineering.SigEngineOverhaul") then return end
        if VehicleUtils.RequiredKeyNotFound(part, chr) then return end
        local vehicle = part:getVehicle()
        local n = M.overhaulParts(chr, vehicle)
        local hasWrench = chr:getInventory():containsTagRecurse(ItemTag.WRENCH)
        local option = self.context:addOption(getText("IGUI_TienSkillMastery_Overhaul"), chr, onOverhaul, part)
        local tip = ISWorldObjectContextMenu.addToolTip()
        tip.description = getText("IGUI_TienSkillMastery_OverhaulTip", string.format("%d", vehicle:getEngineQuality()),
            string.format("%d", n))
        option.toolTip = tip
        if n <= 0 or not hasWrench then option.notAvailable = true end
    end)
    if not ok then print("[TienSkillMastery] overhaul menu failed: " .. tostring(err)) end
    return unpack(r)
end
