--[[
Tien's Skill Mastery: Mending's signature, restore (42.21). An item's "Repaired x times" (`getHaveBeenRepaired`,
saved, sent by `syncItemFields`) makes every later repair weaker and likelier to fail (`FixingManager.fixItem`:
fail chance 3 + 2 x (repairs + 1), gain divided by repairs + 1). Restore sets it back to 0 for the price of a repair:
the item's first Fixing's first fixer (`FixingManager.getFixes(item):get(0):getFixers():get(0)`, the material its
Fix recipe names first), consumed the way a repair consumes it (`FixingManager.useFixer`, main inventory only, so
the client moves it out of a bag first). Condition is unchanged: it repairs like new again.

Shared timed action with a server `complete` (re-checks the signature, the count and the fixer); the client's menu is
client/TienSkillMastery_Restore.lua. `new`'s parameter names are what the MP server rebuilds the action from.
]]

require "TimedActions/ISBaseTimedAction"
require "TienSkillMastery"
local M = TienSkillMastery

TienSkillMasteryRestoreAction = ISBaseTimedAction:derive("TienSkillMasteryRestoreAction")
local A = TienSkillMasteryRestoreAction

--- The first fixer of an item's first Fixing, or nil.
function M.restoreFixer(item)
    if not item or item:getHaveBeenRepaired() <= 0 then return nil end
    local fixes = FixingManager.getFixes(item)
    if not fixes or fixes:size() == 0 then return nil end
    local fixers = fixes:get(0):getFixers()
    if not fixers or fixers:size() == 0 then return nil end
    return fixers:get(0)
end

function A:isValid()
    local fixer = M.restoreFixer(self.item)
    return fixer ~= nil and self.character:getInventory():contains(fixer:getFixerName())
        and self.character:getInventory():containsRecursive(self.item)
end

function A:update()
    self.item:setJobDelta(self:getJobDelta())
    self.character:setMetabolicTarget(Metabolics.UsingTools)
end

function A:start()
    if isClient() and self.item then
        self.item = self.character:getInventory():getItemById(self.item:getID()) or self.item
    end
    self.item:setJobType(getText("IGUI_TienSkillMastery_Restore"))
    self.item:setJobDelta(0.0)
end

function A:stop()
    ISBaseTimedAction.stop(self)
    if self.item then self.item:setJobDelta(0.0) end
end

function A:perform()
    if self.item then self.item:setJobDelta(0.0) end
    ISBaseTimedAction.perform(self)
end

function A:complete()
    local item, chr = self.item, self.character
    if not item or not chr or not M.sig(chr, "Mending.SigRestore") then return false end
    local fixer = M.restoreFixer(item)
    if not fixer or not chr:getInventory():contains(fixer:getFixerName()) then return false end
    FixingManager.useFixer(chr, fixer, item)
    item:setHaveBeenRepaired(0)
    item:syncItemFields()
    return true
end

function A:getDuration()
    if self.character:isTimedActionInstant() then return 1 end
    return 60
end

function A:new(character, item)
    local o = ISBaseTimedAction.new(self, character)
    o.item = item
    o.maxTime = o:getDuration()
    o.caloriesModifier = 4
    return o
end
