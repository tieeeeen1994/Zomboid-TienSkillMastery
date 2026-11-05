--[[
Tien's Skill Mastery: crafting-skill timed actions outside the handcraft window (42.21 vanilla Lua).

Times (both sides). Each action below works its time out in `getDuration` and its `new` sets
`o.maxTime = o:getDuration()`; an MP server rebuilds the action with `Type.new(...)` and reads `getDuration()` for
the real end time (Java `NetTimedAction`), so wrapping `getDuration` scales the client's bar, single player and the
server once each. The wrapped function computes from scratch every call, so nothing compounds. Values <= 1
(`isTimedActionInstant` returns 1, ISRepairClothing returns 0 when an item is missing) are left alone.
- `Woodwork.Unbarricade`: shared/TimedActions/ISUnbarricadeAction.lua `getDuration` (~154) = 200 - 5 x Woodwork,
  - 20 Handy (wood and metal barricades alike; vanilla reads Woodwork for both); `new` ~165.
- `Electricity.HotwireTime`: shared/Vehicles/TimedActions/ISHotwireVehicle.lua `getDuration` (~43) =
  200 - 3 x Electricity; `new` ~50.
- `Tailoring.PatchTime`: shared/TimedActions/ISRepairClothing.lua `getDuration` (~84) and ISRemovePatch.lua
  `getDuration` (~82), both 150 - 6 x Tailoring; `new` ~93 / ~90.

Outcomes (server / single player: `complete` runs on the MP server and in single player, never on an MP client).
- `Electricity.Hotwire`: `ISHotwireVehicle:complete` (~32) calls Java `BaseVehicle.tryHotwire(level)` (~8545):
  success when Rand(100) <= clamp(100 - engine quality, 5, 50) + 4 x level (`setHotwired(true)`), else broken when
  Rand(100) <= 10 - level; the server flags the vehicle (updateFlags 4096) to sync. After a failed try, a `M.roll`
  turns it into a success with `vehicle:cheatHotwire(true, brokenBefore)` (same flag, so it syncs the same way; a
  hotwire broken by this very failure is undone) and plays vanilla's success sound the way `tryHotwire` does
  (`playServerSound` on a server, the driver's emitter otherwise).
- `Electricity.GeneratorRepair`: `ISFixGenerator:complete` (~62) uses one ElectronicsScrap and sets condition +
  4 + Electricity / 2 (~70). After it, + `M.int` condition (`IsoGenerator.setCondition` ~566 clamps 0..100 and
  syncs on a server), only when vanilla's repair went through.
- `Tailoring.FabricRecovery`: `ISRemovePatch.chanceToGetPatchBack(character)` (~76) = 10 + 5 x Tailoring, rolled in
  `complete` (~44, server / single player) and shown in the garment window and inventory menu tooltips
  (client/ISUI/ISGarmentUI.lua ~205, ISInventoryPaneContextMenu.lua ~1537). Adding the points there covers the roll
  and the tooltips (a client knows its own mastery).
]]

require "TienSkillMastery"
require "TimedActions/ISUnbarricadeAction"
require "Vehicles/TimedActions/ISHotwireVehicle"
require "TimedActions/ISFixGenerator"
require "TimedActions/ISRepairClothing"
require "TimedActions/ISRemovePatch"
local M = TienSkillMastery

-- ---------------------------------------------------------------------------------------------------------------
-- Times
-- ---------------------------------------------------------------------------------------------------------------

local function scaled(self, bonusId, d, ...)
    if type(d) == "number" and d > 1 then
        local chr = self.character
        if chr and not chr:isTimedActionInstant() then
            local f = M.less(chr, bonusId)
            if f < 1 then d = math.max(2, math.floor(d * f + 0.5)) end
        end
    end
    return d, ...
end

local function wrapDuration(class, className, bonusId)
    local vanilla = class and class.getDuration
    if not vanilla then
        print("[TienSkillMastery] " .. className .. ":getDuration not found, " .. bonusId .. " not applied")
        return
    end
    class.getDuration = function(self, ...)
        return scaled(self, bonusId, vanilla(self, ...))
    end
end

wrapDuration(ISUnbarricadeAction, "ISUnbarricadeAction", "Woodwork.Unbarricade")
wrapDuration(ISHotwireVehicle, "ISHotwireVehicle", "Electricity.HotwireTime")
wrapDuration(ISRepairClothing, "ISRepairClothing", "Tailoring.PatchTime")
wrapDuration(ISRemovePatch, "ISRemovePatch", "Tailoring.PatchTime")

-- ---------------------------------------------------------------------------------------------------------------
-- Hotwiring
-- ---------------------------------------------------------------------------------------------------------------

if ISHotwireVehicle and ISHotwireVehicle.complete then
    local vanillaComplete = ISHotwireVehicle.complete

    local function afterHotwire(chr, vehicle, wasHotwired, wasBroken)
        if wasHotwired or vehicle:isHotwired() then return end
        if not M.roll(chr, "Electricity.Hotwire") then return end
        vehicle:cheatHotwire(true, wasBroken)
        if isServer() then
            local square = vehicle:getSquare()
            if square then playServerSound("VehicleHotwireSuccess", square) end
        elseif vehicle:getDriver() then
            vehicle:getDriver():getEmitter():playSound("VehicleHotwireSuccess")
        end
    end

    local function finish(chr, vehicle, wasHotwired, wasBroken, ...)
        if vehicle then
            local ok, err = pcall(afterHotwire, chr, vehicle, wasHotwired, wasBroken)
            if not ok then print("[TienSkillMastery] hotwire bonus failed: " .. tostring(err)) end
        end
        return ...
    end

    function ISHotwireVehicle:complete(...)
        local chr = self.character
        local vehicle = chr and chr:getVehicle()
        local wasHotwired = vehicle and vehicle:isHotwired()
        local wasBroken = vehicle and vehicle:isHotwiredBroken()
        return finish(chr, vehicle, wasHotwired, wasBroken, vanillaComplete(self, ...))
    end
else
    print("[TienSkillMastery] ISHotwireVehicle:complete not found, Electricity.Hotwire not applied")
end

-- ---------------------------------------------------------------------------------------------------------------
-- Generator repair
-- ---------------------------------------------------------------------------------------------------------------

if ISFixGenerator and ISFixGenerator.complete then
    local vanillaComplete = ISFixGenerator.complete

    local function afterRepair(chr, generator, before, result)
        if result == false or not before then return end
        local now = generator:getCondition()
        if now <= before or now >= 100 then return end
        local n = M.int(chr, "Electricity.GeneratorRepair")
        if n > 0 then generator:setCondition(math.min(100, now + n)) end
    end

    local function finish(chr, generator, before, ...)
        if generator then
            local ok, err = pcall(afterRepair, chr, generator, before, (...))
            if not ok then print("[TienSkillMastery] generator repair bonus failed: " .. tostring(err)) end
        end
        return ...
    end

    function ISFixGenerator:complete(...)
        local generator = self.generator
        local before = generator and generator:getCondition()
        return finish(self.character, generator, before, vanillaComplete(self, ...))
    end
else
    print("[TienSkillMastery] ISFixGenerator:complete not found, Electricity.GeneratorRepair not applied")
end

-- ---------------------------------------------------------------------------------------------------------------
-- Patch removal: fabric back
-- ---------------------------------------------------------------------------------------------------------------

if ISRemovePatch and ISRemovePatch.chanceToGetPatchBack then
    local vanillaChance = ISRemovePatch.chanceToGetPatchBack
    ISRemovePatch.chanceToGetPatchBack = function(character, ...)
        local chance = vanillaChance(character, ...)
        if type(chance) == "number" and character then
            chance = chance + M.val(character, "Tailoring.FabricRecovery")
        end
        return chance
    end
else
    print("[TienSkillMastery] ISRemovePatch.chanceToGetPatchBack not found, Tailoring.FabricRecovery not applied")
end
