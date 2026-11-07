--[[
Tien's Skill Mastery: menus for Salvaging's signature (shared/TienSkillMastery_Scrap.lua).
- "Scrap vehicle" on any car that is neither burnt nor smashed, added after vanilla's `FillMenuOutsideVehicle`, with
  vanilla's own requirements (welding mask carried, blowtorch with 10 uses) and the guards, then vanilla's handler
  `ISVehicleMenu.onRemoveBurntVehicle` (walk adjacent, equip the torch, wear the mask, queue ISRemoveBurntVehicle).
  The tooltip warns that installed parts are destroyed with the car.
- "Scrap" on vehicle part items in the inventory: the torch is equipped and the mask worn the same way, the part
  moved out of a bag, then the scrap action.
]]

require "TienSkillMastery"
require "TienSkillMastery_Scrap"
require "Vehicles/ISUI/ISVehicleMenu"
local M = TienSkillMastery

local function torchFor(playerObj, uses)
    return playerObj:getInventory():getFirstEvalRecurse(function(item) return M.isBlowTorch(item, uses) end)
end

local function line(ok, text)
    return " <LINE> " .. (ok and "<RGB:1,1,1> " or "<RGB:1,0,0> ") .. text
end

local vanillaFill = ISVehicleMenu.FillMenuOutsideVehicle
function ISVehicleMenu.FillMenuOutsideVehicle(player, context, vehicle, test, ...)
    local r = { vanillaFill(player, context, vehicle, test, ...) }
    local ok, err = pcall(function()
        local playerObj = getSpecificPlayer(player)
        if test or not vehicle or not playerObj or M.isBurntOrSmashed(vehicle) then return end
        if not M.sig(playerObj, "Salvaging.SigScrapAnyCar") then return end
        local option = context:addOption(getText("IGUI_TienSkillMastery_ScrapCar"), playerObj,
            ISVehicleMenu.onRemoveBurntVehicle, vehicle)
        local tip = ISWorldObjectContextMenu.addToolTip()
        tip:setName(getText("IGUI_TienSkillMastery_ScrapCar"))
        local text = getText("IGUI_TienSkillMastery_ScrapCarTip") .. " <LINE> "
        local mask = playerObj:getInventory():containsEvalRecurse(M.isWeldingMask)
        text = text .. line(mask, getItemNameFromFullType("Base.WeldingMask"))
        local torch = torchFor(playerObj, 10)
        text = text .. line(torch ~= nil, getItemNameFromFullType("Base.BlowTorch") .. " 10")
        local why = M.scrapRefusal(playerObj, vehicle)
        if why then text = text .. line(false, getText(why)) end
        tip.description = text
        option.toolTip = tip
        if not mask or not torch or why then option.notAvailable = true end
    end)
    if not ok then print("[TienSkillMastery] scrap car menu failed: " .. tostring(err)) end
    return unpack(r)
end

local function queueScrapPart(playerObj, item)
    local def = M.scrapPartDef(item)
    local torch = def and torchFor(playerObj, def[3])
    if not torch then return end
    ISInventoryPaneContextMenu.transferIfNeeded(playerObj, item)
    ISWorldObjectContextMenu.equip(playerObj, playerObj:getPrimaryHandItem(), function(i)
        return M.isBlowTorch(i, def[3])
    end, true)
    local mask = playerObj:getInventory():getFirstEvalRecurse(M.isWeldingMask)
    if mask then ISInventoryPaneContextMenu.wearItem(mask, playerObj:getPlayerNum()) end
    ISTimedActionQueue.add(TienSkillMasteryScrapPart:new(playerObj, item))
end

Events.OnFillInventoryObjectContextMenu.Add(function(playerNum, context, items)
    local playerObj = getSpecificPlayer(playerNum)
    if not playerObj or not M.sig(playerObj, "Salvaging.SigScrapAnyCar") then return end
    local list = ISInventoryPane.getActualItems(items)
    if #list ~= 1 then return end
    local item = list[1]
    local def = M.scrapPartDef(item)
    if not def then return end
    local option = context:addOption(getText("IGUI_TienSkillMastery_ScrapPart"), playerObj, queueScrapPart, item)
    local tip = ISWorldObjectContextMenu.addToolTip()
    local mask = playerObj:getInventory():containsEvalRecurse(M.isWeldingMask)
    local torch = torchFor(playerObj, def[3])
    local parts = {}
    for _, y in ipairs(def[2]) do
        local n = y[2] == y[3] and string.format("%d", y[2]) or string.format("%d-%d", y[2], y[3])
        parts[#parts + 1] = n .. " " .. getItemNameFromFullType(y[1])
    end
    tip.description = getText("IGUI_TienSkillMastery_ScrapPartTip", table.concat(parts, ", "))
        .. " <LINE> " .. line(mask, getItemNameFromFullType("Base.WeldingMask"))
        .. line(torch ~= nil, getItemNameFromFullType("Base.BlowTorch") .. " " .. string.format("%d", def[3]))
    option.toolTip = tip
    if not mask or not torch then option.notAvailable = true end
end)
