--[[
Tien's Skill Mastery: Welding (perk MetalWelding) bonuses for scrapping a burnt car (ISRemoveBurntVehicle,
shared/Vehicles/TimedActions/ISRemoveBurntVehicle.lua, 42.21). Blowtorch dismantling and metal furniture pick-up
are not here (ISMoveableSpriteProps belongs to the shared crafting hooks).

Salvaging.BurntCarTime ("less"): getDuration ~179 = 800 - 20 x Welding (10 with the mechanics cheat or Timed
Action Instant, left alone); `new` ~194 `maxTime = o:getDuration()`: a "computed" action, one getDuration wrapper
covers the client, single player and the server's rebuild (shared/TienSkillMastery_Workshop.lua).

Salvaging.SalvageRoll ("int", one extra roll at mastery 10, a tenth of a chance per level below): `complete` ~60
(server / single player) runs max(5, Welding) rounds (~63); each round calls `self:checkAddItem(type, baseChance)`
twice for each of 17 materials (~68-129): 1 in (baseChance - level) drops the item on the car's square, else
1 in (baseChance - Welding) a lesser item (~143-177), with `square:AddWorldInventoryItem(type, x, y, 0)`, which
transmits to clients on a server (`IsoGridSquare.AddWorldInventoryItem` ~6028). Then the car is removed
(`permanentlyRemove`). The wrapper records the round's calls while vanilla runs (an instance field shadows the
class method for this one action), and after `complete` replays the first round's calls once more through
vanilla's own `checkAddItem`, with `self.vehicle` swapped for a stand-in that returns the car's square (saved
before: the car is gone by then). No XP for the extra round (vanilla's XP stays as it was).
]]

require "TienSkillMastery"
require "TienSkillMastery_Workshop"
local M = TienSkillMastery
local W = M.Workshop

local function mechanicsCheat(action)
    return action.character:isMechanicsCheat()
end

W.wrapComputedDuration(ISRemoveBurntVehicle, "Salvaging.BurntCarTime", mechanicsCheat)

if not ISRemoveBurntVehicle or not ISRemoveBurntVehicle.complete then return end

local origComplete = ISRemoveBurntVehicle.complete
function ISRemoveBurntVehicle:complete(...)
    if isClient() or not self.character or not self.vehicle then return origComplete(self, ...) end
    local extra = M.int(self.character, "Salvaging.SalvageRoll")
    if extra <= 0 then return origComplete(self, ...) end

    local square = self.vehicle:getSquare()
    local rounds = math.max(5, self.character:getPerkLevel(Perks.MetalWelding))
    local check = self.checkAddItem
    local calls = {}
    self.checkAddItem = function(action, itemType, baseChance, ...)
        calls[#calls + 1] = { itemType, baseChance }
        return check(action, itemType, baseChance, ...)
    end
    local results = W.pack(origComplete(self, ...))
    self.checkAddItem = nil

    local perRound = math.floor(#calls / rounds)
    if results[1] ~= false and square and perRound > 0 then
        local vehicle = self.vehicle
        self.vehicle = { getSquare = function() return square end }
        for _ = 1, extra do
            for i = 1, perRound do
                check(self, calls[i][1], calls[i][2])
            end
        end
        self.vehicle = vehicle
    end
    return W.unpack(results)
end

-- Salvaging.TorchFuel (phase 2, "pts"): `complete` burns 10 blowtorch uses (`self.item:Use(false, false, true)` x10,
-- `self.item` = the primary hand item from `serverStart`). Each burnt use comes back on its own roll; sent with
-- `syncItemFields` (carries uses). Wraps the wrapper above.
local salvageComplete = ISRemoveBurntVehicle.complete
function ISRemoveBurntVehicle:complete(...)
    local chr = self.character
    local torch = self.item or (chr and chr:getPrimaryHandItem())
    if isClient() or not chr or not torch or M.val(chr, "Salvaging.TorchFuel") <= 0
        or not instanceof(torch, "DrainableComboItem") then
        return salvageComplete(self, ...)
    end
    local before = torch:getCurrentUses()
    local results = W.pack(salvageComplete(self, ...))
    local now = torch:getCurrentUses()
    if now < before and torch:getContainer() then
        local back = 0
        for _ = 1, before - now do
            if M.roll(chr, "Salvaging.TorchFuel") then back = back + 1 end
        end
        if back > 0 then
            torch:setCurrentUses(now + back)
            torch:syncItemFields()
        end
    end
    return W.unpack(results)
end
