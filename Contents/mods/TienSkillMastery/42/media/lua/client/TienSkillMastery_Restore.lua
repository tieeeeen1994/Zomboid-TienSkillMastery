--[[
Tien's Skill Mastery: the inventory menu option for Mending's restore (shared/TienSkillMastery_RestoreAction.lua).
Shown on a single item with a repair count for a player with the signature; greyed out with a tooltip when the fixer
is missing. The item and the fixer are moved out of bags first (`ISInventoryPaneContextMenu.transferIfNeeded`), since
the fixer is consumed from the main inventory only.
]]

require "TienSkillMastery"
require "TienSkillMastery_RestoreAction"
local M = TienSkillMastery

local function queueRestore(player, item, fixerName)
    local fixerItem = player:getInventory():getFirstTypeRecurse(fixerName)
    ISInventoryPaneContextMenu.transferIfNeeded(player, item)
    if fixerItem then ISInventoryPaneContextMenu.transferIfNeeded(player, fixerItem) end
    ISTimedActionQueue.add(TienSkillMasteryRestoreAction:new(player, item))
end

local function onFill(playerNum, context, items)
    local player = getSpecificPlayer(playerNum)
    if not player or not M.sig(player, "Mending.SigRestore") then return end
    local list = ISInventoryPane.getActualItems(items)
    if #list ~= 1 then return end
    local item = list[1]
    local fixer = M.restoreFixer(item)
    if not fixer then return end
    local fixerName = fixer:getFixerName()
    local script = getScriptManager():getItem(fixerName)
    local fixerLabel = script and script:getDisplayName() or fixerName
    local option = context:addOption(getText("IGUI_TienSkillMastery_Restore"), player, queueRestore, item, fixerName)
    local tip = ISWorldObjectContextMenu.addToolTip()
    tip.description = getText("IGUI_TienSkillMastery_RestoreTip", string.format("%d", item:getHaveBeenRepaired()),
        fixerLabel)
    option.toolTip = tip
    if not player:getInventory():containsTypeRecurse(fixerName) then option.notAvailable = true end
end
Events.OnFillInventoryObjectContextMenu.Add(onFill)
