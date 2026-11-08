--[[
Tien's Skill Mastery: Mending's signature, restore (42.21). An item's "Repaired x times" (`getHaveBeenRepaired`,
saved, sent by `syncItemFields`) makes every later repair weaker and likelier to fail. Restore sets it back to 0 and
the item's condition to full (user, 2026-11-08), for `M.RESTORE_COST` (3) times the price of a repair. Head condition
and sharpness are left alone (`setConditionNoSound`, the same value a repair raises). Only an item with a repair count
is offered it.

Two vanilla systems raise that count, and restore takes the materials of either (user, 2026-11-08: an axe repaired
with zip ties had no option, since only the first was read):
- The Fixing list (`FixingManager.fixItem` ~57; firearms and vehicle parts in vanilla: fail chance 3 + 2 x (repairs +
  1), gain divided by repairs + 1). The price is the item's first Fixing's first fixer
  (`FixingManager.getFixes(item):get(0):getFixers():get(0)`, usually a spare of the same gun), consumed the way a repair
  consumes it (`FixingManager.useFixer`, `getNumberOfUse` uses or items, main inventory only, so the client moves them
  out of a bag first). `useFixer` skips the item being repaired, so the item itself must not count as its own fixer
  (a pistol with no spare passed the old `contains` check and was restored for nothing). It takes what is there
  without complaint, so the amount is checked first.
- Craft recipes (`recipes_fixing.txt`, FixWith...: tools and melee weapons; `RecipeCodeOnCreate.genericFixer` ~1155
  counts failures too: fail chance 25 - factor x 5 - Maintenance x 5 + repairs x 2). `M.repairRecipes` takes every
  recipe with an IsDamaged input and at least one consumed input, so other mods' count too and FixSaw (a kept file,
  raises no count) does not. An option is offered per recipe the character could really use (required skills, learned);
  the price is that recipe's consumed inputs x 3, its kept tools must be carried and are not worn. Amounts follow
  `CraftRecipeData` ~553-615: uses of a drainable (duct tape: 2 of 4), else whole items, whole items too for
  ItemCount / destroy inputs. Materials come from anywhere in the character's inventory, bags included: the send
  goes to the owner whichever bag it is. Not checked: flags on inputs such as IsNotDull on the scissors.

Shared timed action with a server `complete` (re-checks the signature, the count and the materials); the client's menu
is client/TienSkillMastery_Restore.lua. `new`'s parameter names are what the MP server rebuilds the action from, so
the recipe travels by name, "" for the Fixing list.
]]

require "TimedActions/ISBaseTimedAction"
require "TienSkillMastery"
local M = TienSkillMastery

TienSkillMasteryRestoreAction = ISBaseTimedAction:derive("TienSkillMasteryRestoreAction")
local A = TienSkillMasteryRestoreAction

--- Restoring costs this many repairs' worth of materials.
M.RESTORE_COST = 3

--- The first fixer of an item's first Fixing, or nil.
function M.restoreFixer(item)
    if not item or item:getHaveBeenRepaired() <= 0 then return nil end
    local fixes = FixingManager.getFixes(item)
    if not fixes or fixes:size() == 0 then return nil end
    local fixers = fixes:get(0):getFixers()
    if not fixers or fixers:size() == 0 then return nil end
    return fixers:get(0)
end

--- Uses (drainables) or items a restore needs of this fixer.
function M.restoreFixerNeed(fixer)
    return fixer:getNumberOfUse() * M.RESTORE_COST
end

--- Items of this fixer's type other than the item being restored: anywhere on the character, or the main inventory.
local function fixerItems(player, item, fixer, mainOnly)
    local id, name = item:getID(), fixer:getFixerName()
    local function matches(other) return other:getID() ~= id and other:getFullType() == name end
    local inventory = player:getInventory()
    return mainOnly and inventory:getAllEval(matches) or inventory:getAllEvalRecurse(matches)
end

local function fixerAmount(list)
    local total = 0
    for i = 0, list:size() - 1 do
        local other = list:get(i)
        total = total + (instanceof(other, "DrainableComboItem") and other:getCurrentUses() or 1)
    end
    return total
end

--- The carried items that would pay for a fixer restore, for the client to move out of bags first.
function M.restoreFixerItems(player, item, fixer)
    local out, need = {}, M.restoreFixerNeed(fixer)
    local list = fixerItems(player, item, fixer, false)
    for i = 0, list:size() - 1 do
        if need <= 0 then break end
        local other = list:get(i)
        out[#out + 1] = other
        need = need - (instanceof(other, "DrainableComboItem") and other:getCurrentUses() or 1)
    end
    return out
end

-- ---------------------------------------------------------------------------------------------------------------
-- Repair recipes
-- ---------------------------------------------------------------------------------------------------------------

local repairCache = nil
-- Scripts are rebuilt on leaving a game, without always reloading Lua.
Events.OnLoadMapZones.Add(function() repairCache = nil end)

local function isItemInput(input)
    return input:getResourceType() == ResourceType.Item
end

local function isRepairRecipe(recipe)
    local damaged, consumes = false, false
    local inputs = recipe:getInputs()
    for i = 0, inputs:size() - 1 do
        local input = inputs:get(i)
        if isItemInput(input) then
            if input:isDamaged() then
                damaged = true
            elseif not input:isKeep() then
                consumes = true
            end
        end
    end
    return damaged and consumes
end

--- Every craft recipe that repairs an item with materials.
function M.repairRecipes()
    if repairCache then return repairCache end
    repairCache = {}
    local all = getScriptManager():getAllCraftRecipes()
    for i = 0, all:size() - 1 do
        local recipe = all:get(i)
        if isRepairRecipe(recipe) then table.insert(repairCache, recipe) end
    end
    return repairCache
end

--- True when the recipe repairs this item.
local function repairsItem(recipe, script)
    local inputs = recipe:getInputs()
    for i = 0, inputs:size() - 1 do
        local input = inputs:get(i)
        if isItemInput(input) and input:isDamaged() and input:containsItem(script) then return true end
    end
    return false
end

--- The character could use this recipe at all (what the crafting window asks; materials aside).
local function canUseRecipe(player, recipe)
    if recipe:needToBeLearn() and not player:isRecipeActuallyKnown(recipe) then return false end
    for i = 0, recipe:getRequiredSkillCount() - 1 do
        local skill = recipe:getRequiredSkill(i)
        if player:getPerkLevel(skill:getPerk()) < skill:getLevel() then return false end
    end
    return true
end

--- Carried items an input could take, never the item being restored.
local function carriedFor(player, item, input)
    local id = item:getID()
    return player:getInventory():getAllEvalRecurse(function(other)
        return other:getID() ~= id and not other:isBroken() and input:containsItem(other:getScriptItem())
    end)
end

--- This input counts in whole items for this carried item, not uses.
local function countsWhole(input, other)
    return input:isItemCount() or input:isDestroy() or not instanceof(other, "DrainableComboItem")
end

local function amountCarried(input, list)
    local total = 0
    for i = 0, list:size() - 1 do
        local other = list:get(i)
        total = total + (countsWhole(input, other) and 1 or other:getCurrentUses())
    end
    return total
end

--- What restoring with this recipe takes: { recipe, name, ok, materials = { { input, need, have } }, tools = { { input,
--- have } } }. `ok` = everything is carried.
local function planFor(player, item, recipe)
    local plan = { recipe = recipe, name = recipe:getName(), ok = true, materials = {}, tools = {} }
    local inputs = recipe:getInputs()
    for i = 0, inputs:size() - 1 do
        local input = inputs:get(i)
        if isItemInput(input) and not input:isDamaged() then
            local list = carriedFor(player, item, input)
            if input:isKeep() then
                local have = list:size() > 0
                table.insert(plan.tools, { input = input, have = have })
                if not have then plan.ok = false end
            else
                local need = input:getIntAmount() * M.RESTORE_COST
                local have = amountCarried(input, list) >= need
                table.insert(plan.materials, { input = input, need = need, have = have })
                if not have then plan.ok = false end
            end
        end
    end
    return plan
end

--- Every way this player could restore this item: a recipe's plan, or { fixer = Fixing.Fixer, need, ok } for the
--- Fixing list.
function M.restoreOptions(player, item)
    local options = {}
    if not item or item:getHaveBeenRepaired() <= 0 then return options end
    local fixer = M.restoreFixer(item)
    if fixer then
        local need = M.restoreFixerNeed(fixer)
        table.insert(options, { fixer = fixer, need = need,
            ok = fixerAmount(fixerItems(player, item, fixer, false)) >= need })
    end
    local script = item:getScriptItem()
    for _, recipe in ipairs(M.repairRecipes()) do
        if repairsItem(recipe, script) and canUseRecipe(player, recipe) then
            table.insert(options, planFor(player, item, recipe))
        end
    end
    return options
end

--- The plan for a recipe by name, checked as restoreOptions does, or nil.
local function planByName(player, item, name)
    local script = item:getScriptItem()
    for _, recipe in ipairs(M.repairRecipes()) do
        if recipe:getName() == name then
            if repairsItem(recipe, script) and canUseRecipe(player, recipe) then
                return planFor(player, item, recipe)
            end
            return nil
        end
    end
    return nil
end

local function consumeMaterials(player, item, plan)
    for _, material in ipairs(plan.materials) do
        local input, need = material.input, material.need
        local list = carriedFor(player, item, input)
        for i = 0, list:size() - 1 do
            if need <= 0 then break end
            local other = list:get(i)
            if countsWhole(input, other) then
                local container = other:getContainer()
                player:removeFromHands(other)
                container:DoRemoveItem(other)
                if isServer() then sendRemoveItemFromContainer(container, other) end
                need = need - 1
            else
                -- Counted first: the last use can turn the item into its empty version.
                local uses = math.min(need, other:getCurrentUses())
                for _ = 1, uses do other:Use(false, false, true) end
                need = need - uses
            end
        end
    end
end

-- ---------------------------------------------------------------------------------------------------------------
-- The action
-- ---------------------------------------------------------------------------------------------------------------

function A:isValid()
    if not self.character:getInventory():containsRecursive(self.item) then return false end
    if self.recipeName ~= "" then
        local plan = planByName(self.character, self.item, self.recipeName)
        return plan ~= nil and plan.ok and self.item:getHaveBeenRepaired() > 0
    end
    local fixer = M.restoreFixer(self.item)
    return fixer ~= nil
        and fixerAmount(fixerItems(self.character, self.item, fixer, true)) >= M.restoreFixerNeed(fixer)
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
    if not item or not chr or not M.sig(chr, "Mending.SigRestore") or item:getHaveBeenRepaired() <= 0 then
        return false
    end
    if self.recipeName ~= "" then
        local plan = planByName(chr, item, self.recipeName)
        if not plan or not plan.ok then return false end
        consumeMaterials(chr, item, plan)
    else
        local fixer = M.restoreFixer(item)
        if not fixer or fixerAmount(fixerItems(chr, item, fixer, true)) < M.restoreFixerNeed(fixer) then
            return false
        end
        for _ = 1, M.RESTORE_COST do FixingManager.useFixer(chr, fixer, item) end
    end
    item:setHaveBeenRepaired(0)
    item:setConditionNoSound(item:getConditionMax())
    item:syncItemFields()
    return true
end

function A:getDuration()
    if self.character:isTimedActionInstant() then return 1 end
    return 60
end

function A:new(character, item, recipeName)
    local o = ISBaseTimedAction.new(self, character)
    o.item = item
    o.recipeName = recipeName or ""
    o.maxTime = o:getDuration()
    o.caloriesModifier = 4
    return o
end
