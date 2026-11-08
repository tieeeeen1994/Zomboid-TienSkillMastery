--[[
Tien's Skill Mastery: the inventory menu option for Mending's restore (shared/TienSkillMastery_RestoreAction.lua).
Shown on a single item with a repair count for a player with the signature. One way to pay: one option. Several (each
repair recipe the player could use, plus the Fixing list's fixer): a submenu, one line per way, naming its materials.
A way whose materials or tools are not carried is greyed out. The item is moved out of a bag first; Fixing fixers too,
since they are consumed from the main inventory only (recipe materials are consumed wherever they are carried).
]]

require "TienSkillMastery"
require "TienSkillMastery_RestoreAction"
local M = TienSkillMastery

local MAX_NAMES = 3

--- "Zip Ties", or "Ripped Sheets / Denim Strips" (at most MAX_NAMES, then "...").
local function inputNames(input)
    local names = {}
    local possible = input:getPossibleInputItems()
    for i = 0, possible:size() - 1 do
        if #names == MAX_NAMES then
            names[#names + 1] = "..."
            break
        end
        names[#names + 1] = possible:get(i):getDisplayName()
    end
    return table.concat(names, " / ")
end

--- "1 x Zip Ties" for a recipe's materials and tools, or the fixer's name.
local function costText(option)
    if option.fixer then
        local name = option.fixer:getFixerName()
        local script = getScriptManager():getItem(name)
        return string.format("%d x %s", option.need, script and script:getDisplayName() or name)
    end
    local parts = {}
    for _, material in ipairs(option.materials) do
        parts[#parts + 1] = string.format("%d x %s", material.need, inputNames(material.input))
    end
    for _, tool in ipairs(option.tools) do
        parts[#parts + 1] = inputNames(tool.input)
    end
    return table.concat(parts, ", ")
end

local function queueRestore(player, item, recipeName)
    ISInventoryPaneContextMenu.transferIfNeeded(player, item)
    if recipeName == "" then
        local fixer = M.restoreFixer(item)
        for _, fixerItem in ipairs(fixer and M.restoreFixerItems(player, item, fixer) or {}) do
            ISInventoryPaneContextMenu.transferIfNeeded(player, fixerItem)
        end
    end
    ISTimedActionQueue.add(TienSkillMasteryRestoreAction:new(player, item, recipeName))
end

local function addWay(menu, text, player, item, option)
    local entry = menu:addOption(text, player, queueRestore, item, option.name or "")
    local tip = ISWorldObjectContextMenu.addToolTip()
    tip.description = getText("IGUI_TienSkillMastery_RestoreTip", string.format("%d", item:getHaveBeenRepaired()),
        costText(option))
    entry.toolTip = tip
    if not option.ok then entry.notAvailable = true end
end

local function onFill(playerNum, context, items)
    local player = getSpecificPlayer(playerNum)
    if not player or not M.sig(player, "Mending.SigRestore") then return end
    local list = ISInventoryPane.getActualItems(items)
    if #list ~= 1 then return end
    local item = list[1]
    local options = M.restoreOptions(player, item)
    if #options == 0 then return end
    local title = getText("IGUI_TienSkillMastery_Restore")
    if #options == 1 then
        addWay(context, title, player, item, options[1])
        return
    end
    local parent = context:addOption(title)
    local sub = context:getNew(context)
    context:addSubMenu(parent, sub)
    for _, option in ipairs(options) do
        addWay(sub, costText(option), player, item, option)
    end
end
Events.OnFillInventoryObjectContextMenu.Add(onFill)
