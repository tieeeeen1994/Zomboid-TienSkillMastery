--[[
Tien's Skill Mastery: Salvaging's signature, scrap any car and scrap car parts (42.21).

Scrap any car: vanilla offers "Remove burnt vehicle" only when the script name contains "Burnt" or "Smashed"
(client/Vehicles/ISUI/ISVehicleMenu.lua ~617, `FillMenuOutsideVehicle`, a plain `string.match`); the shared
`ISRemoveBurntVehicle` checks only the blowtorch in hand (>= 10 uses) and that the car still exists, and its server
`complete` rolls the salvage, burns 10 torch uses and `permanentlyRemove`s the car. So a master gets the same option on
any car (client/TienSkillMastery_ScrapMenu.lua, vanilla's own handler), and the server re-checks in a wrapped
`complete`: a car that is neither burnt nor smashed is scrapped only for a master and only when the approved guards
pass (user, 2026-11-06): no one inside, every container empty (trunk, glove box, seats), not towing or towed, and not
inside a safehouse the scrapper may not loot (`SafeHouse.isSafehouseAllowLoot`, MP only). Installed parts are destroyed
with the car (the tooltip warns). Same yield as a burnt car.

Scrap car parts: an inventory option on vehicle part items (doors, hoods, trunk lids, mufflers, gas tanks, suspension,
brakes, seats; recognised by item type, since the script's VehicleType has no Lua getter) for a master with a
blowtorch and a welding mask, as for a car. Not tires (armor, fire fuel), windows (glass), batteries, trunks or glove
boxes. Yield is a fixed list per part (user, 2026-11-06; first draft), the same for every quality grade and condition;
1 torch use and 100 time a part, 2 uses / 150 for the big panels. Shared timed action with a server `complete` that
re-checks the signature, the item still being carried and the torch, then removes the part (`DoRemoveItem` +
`sendRemoveItemFromContainer`) and adds the yield (`AddItem` + `sendAddItemToContainer`).
]]

require "TimedActions/ISBaseTimedAction"
require "Vehicles/TimedActions/ISRemoveBurntVehicle"
require "TienSkillMastery"
local M = TienSkillMastery

-- ---------------------------------------------------------------------------------------------------------------
-- Scrap any car
-- ---------------------------------------------------------------------------------------------------------------

function M.isBurntOrSmashed(vehicle)
    local name = vehicle and vehicle:getScript() and vehicle:getScript():getName() or ""
    return string.match(name, "Burnt") ~= nil or string.match(name, "Smashed") ~= nil
end

--- Why a car may not be scrapped by this player now (a translation key), or nil.
function M.scrapRefusal(player, vehicle)
    if not vehicle then return "IGUI_TienSkillMastery_ScrapGone" end
    for seat = 0, vehicle:getMaxPassengers() - 1 do
        if vehicle:getCharacter(seat) then return "IGUI_TienSkillMastery_ScrapOccupied" end
    end
    for i = 0, vehicle:getPartCount() - 1 do
        local container = vehicle:getPartByIndex(i):getItemContainer()
        if container and not container:isEmpty() then return "IGUI_TienSkillMastery_ScrapNotEmpty" end
    end
    if vehicle:getVehicleTowing() or vehicle:getVehicleTowedBy() then return "IGUI_TienSkillMastery_ScrapTowing" end
    if (isClient() or isServer()) and vehicle:getSquare()
        and not SafeHouse.isSafehouseAllowLoot(vehicle:getSquare(), player) then
        return "IGUI_TienSkillMastery_ScrapSafehouse"
    end
    return nil
end

if ISRemoveBurntVehicle and ISRemoveBurntVehicle.complete then
    local vanilla = ISRemoveBurntVehicle.complete
    function ISRemoveBurntVehicle:complete(...)
        local vehicle, chr = self.vehicle, self.character
        if vehicle and chr and not M.isBurntOrSmashed(vehicle) then
            if not M.sig(chr, "Salvaging.SigScrapAnyCar") then return false end
            local why = M.scrapRefusal(chr, vehicle)
            if why then
                print("[TienSkillMastery] refused scrapping vehicle " .. tostring(vehicle:getId()) .. " by "
                    .. tostring(chr:getUsername()) .. ": " .. why)
                return false
            end
            print("[TienSkillMastery] " .. tostring(chr:getUsername()) .. " scrapped intact vehicle "
                .. tostring(vehicle:getScript():getName()) .. " id " .. tostring(vehicle:getId()))
        end
        return vanilla(self, ...)
    end
end

-- ---------------------------------------------------------------------------------------------------------------
-- Scrap car parts
-- ---------------------------------------------------------------------------------------------------------------

-- { pattern on the item type, yield = { { full type, min, max } }, uses, time }
local DOOR = { { "Base.SheetMetal", 1, 1 }, { "Base.SmallSheetMetal", 1, 2 }, { "Base.Screws", 1, 1 } }
local PANEL = { { "Base.SheetMetal", 2, 2 }, { "Base.SmallSheetMetal", 1, 2 }, { "Base.Screws", 1, 1 } }
M.SCRAP_PARTS = {
    { "^RearCarDoorDouble%d*$", PANEL, 2, 150 },
    { "^EngineDoor%d*$", PANEL, 2, 150 },
    { "^TrunkDoor%d*$", PANEL, 2, 150 },
    { "^FrontCarDoor%d*$", DOOR, 1, 100 },
    { "^RearCarDoor%d*$", DOOR, 1, 100 },
    { "CarMuffler%d*$", { { "Base.MetalPipe", 1, 2 }, { "Base.ScrapMetal", 1, 1 } }, 1, 100 },
    { "GasTank%d*$", { { "Base.SheetMetal", 1, 1 }, { "Base.SmallSheetMetal", 1, 2 } }, 1, 100 },
    { "Suspension%d*$", { { "Base.MetalBar", 1, 1 }, { "Base.ScrapMetal", 1, 1 } }, 1, 100 },
    { "Brake%d*$", { { "Base.ScrapMetal", 1, 2 } }, 1, 100 },
    { "CarSeat%d*$", { { "Base.MetalBar", 1, 1 }, { "Base.ScrapMetal", 1, 2 } }, 1, 100 },
    { "^VanSeat%d*$", { { "Base.MetalBar", 1, 1 }, { "Base.ScrapMetal", 1, 2 } }, 1, 100 },
}

function M.scrapPartDef(item)
    if not item or item:getModule() ~= "Base" then return nil end
    local t = item:getType()
    for _, d in ipairs(M.SCRAP_PARTS) do
        if string.match(t, d[1]) then return d end
    end
    return nil
end

function M.isWeldingMask(item)
    return item:hasTag(ItemTag.WELDING_MASK) or item:getType() == "WeldingMask"
end

function M.isBlowTorch(item, uses)
    return item ~= nil and (item:hasTag(ItemTag.BLOW_TORCH) or item:getType() == "BlowTorch")
        and item:getCurrentUses() >= (uses or 1)
end

TienSkillMasteryScrapPart = ISBaseTimedAction:derive("TienSkillMasteryScrapPart")
local A = TienSkillMasteryScrapPart

function A:isValid()
    local def = M.scrapPartDef(self.item)
    return def ~= nil and self.character:getInventory():containsRecursive(self.item)
        and M.isBlowTorch(self.character:getPrimaryHandItem(), def[3])
end

function A:update()
    self.character:setMetabolicTarget(Metabolics.MediumWork)
end

function A:start()
    self:setActionAnim("BlowTorch")
    local torch = self.character:getPrimaryHandItem()
    self:setOverrideHandModels(torch, nil)
    self.sound = self.character:playSound("BlowTorch")
end

function A:stop()
    if self.sound and self.sound ~= 0 then self.character:stopOrTriggerSound(self.sound) end
    ISBaseTimedAction.stop(self)
end

function A:perform()
    if self.sound and self.sound ~= 0 then self.character:stopOrTriggerSound(self.sound) end
    ISBaseTimedAction.perform(self)
end

function A:complete()
    local chr, item = self.character, self.item
    local def = M.scrapPartDef(item)
    if not chr or not def or not M.sig(chr, "Salvaging.SigScrapAnyCar") then return false end
    local container = item:getContainer()
    if not container or not chr:getInventory():containsRecursive(item) then return false end
    local torch = chr:getPrimaryHandItem()
    if not M.isBlowTorch(torch, def[3]) then return false end
    container:DoRemoveItem(item)
    sendRemoveItemFromContainer(container, item)
    local inv = chr:getInventory()
    for _, y in ipairs(def[2]) do
        for _ = 1, ZombRand(y[2], y[3] + 1) do
            local made = inv:AddItem(y[1])
            if made then sendAddItemToContainer(inv, made) end
        end
    end
    for _ = 1, def[3] do torch:Use(false, false, true) end
    addXp(chr, Perks.MetalWelding, 2)
    return true
end

function A:getDuration()
    if self.character:isTimedActionInstant() then return 1 end
    local def = M.scrapPartDef(self.item)
    return def and def[4] or 100
end

function A:new(character, item)
    local o = ISBaseTimedAction.new(self, character)
    o.item = item
    o.maxTime = o:getDuration()
    return o
end
