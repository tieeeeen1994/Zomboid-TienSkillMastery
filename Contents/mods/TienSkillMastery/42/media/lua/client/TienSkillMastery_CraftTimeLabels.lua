--[[
Tien's Skill Mastery: the crafting window shows the crafting time a master really takes (user, 2026-11-09), 42.21.

The action's time is scaled in `ISHandcraftAction:getDuration` (shared/TienSkillMastery_Crafting.lua), but the window asks
`CraftRecipe:getTime(player)` itself, in three places: the recipe panel's title (`ISWidgetTitleHeader:createChildren`
~111), the list tooltip's info box (`ISCraftRecipeInfoBox:createDynamicChildren` ~49) and the control's "Time required"
(`ISWidgetHandCraftControl:prerender` ~228). Each works out its own text from that number, so `getTime` answers with the
bonus during those three calls only (`__classmetatables[CraftRecipe.class].__index`, which Java's own calls never go
through). Everywhere else, `ISHandcraftAction:getDuration` included, it answers as vanilla does, so nothing is scaled twice.

Left out on purpose, because their time has no bonus: buildable recipes (`isBuildableRecipe`, the same title widget in the
build window; a build's time is Java's `BuildAction`), and `ISWidgetCraftLogicInputControl` (drying racks and other
CraftLogic machines, timed by Java from the plain recipe time).

The depth lives on the global table and the wrapper reads it through the global: if the class table outlives a Lua reload
(joining a server reloads Lua), the first wrapper stays in place and must see the reloaded file's state.
]]

require "TienSkillMastery"
require "TienSkillMastery_Crafting"
local M = TienSkillMastery

if not M.craftTimeFactor then return end

M.craftLabelDepth = 0

local function wrapGetTime()
    local meta = __classmetatables and CraftRecipe and __classmetatables[CraftRecipe.class]
    local index = meta and meta.__index
    if type(index) ~= "table" or type(index.getTime) ~= "function" then
        print("[TienSkillMastery] CraftRecipe:getTime is not reachable, the crafting window shows vanilla's time")
        return false
    end
    if index.__tsmGetTime then return true end
    index.__tsmGetTime = true
    local vanilla = index.getTime
    -- Two overloads, getTime() and getTime(character): pass exactly what came, a nil argument would pick the second.
    index.getTime = function(self, ...)
        local time = vanilla(self, ...)
        local chr = ...
        local tsm = TienSkillMastery
        if not chr or not tsm or (tsm.craftLabelDepth or 0) <= 0 or self:isBuildableRecipe() then return time end
        local ok, factor = pcall(tsm.craftTimeFactor, chr, self)
        if ok and factor < 1 then return math.max(1, math.floor(time * factor + 0.5)) end
        return time
    end
    return true
end

local function leave(ok, ...)
    M.craftLabelDepth = M.craftLabelDepth - 1
    if not ok then error((...), 0) end
    return ...
end

--- Makes `getTime` answer with the bonus during this method of a vanilla UI class.
local function withLabels(class, name)
    local original = class and class[name]
    if type(original) ~= "function" then
        print("[TienSkillMastery] crafting window: " .. name .. " not found, its time stays vanilla's")
        return
    end
    class[name] = function(...)
        M.craftLabelDepth = M.craftLabelDepth + 1
        return leave(pcall(original, ...))
    end
end

if wrapGetTime() then
    withLabels(ISWidgetTitleHeader, "createChildren")
    withLabels(ISCraftRecipeInfoBox, "createDynamicChildren")
    withLabels(ISWidgetHandCraftControl, "prerender")
end
