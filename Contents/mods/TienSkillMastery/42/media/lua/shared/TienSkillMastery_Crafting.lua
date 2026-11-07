--[[
Tien's Skill Mastery: handcraft hooks (every recipe crafted through ISHandcraftAction). This file owns the
ISHandcraftAction wrappers; no other file touches that class.

Crafting time, `<mastery>.CraftTime` (Construction: Carpentry, Masonry; Smithing: Metalworking, Welding;
Engineering: Electrical; Handicraft: Carving, Knapping, Glassmaking, Pottery; Mending: Tailoring; Provisioning:
Cooking; `M.CRAFT_MASTERY`), both sides
- Vanilla (shared/Entity/TimedActions/ISHandcraftAction.lua, 42.21): `getDuration` (~253) = 1 with
  `isTimedActionInstant`, -1 without a recipe, else `craftRecipe:getTime(character) * 5`; `new` (~391) sets
  `o.maxTime = o:getDuration()` (~411). Java `CraftRecipe.getTime(chr)` (~198) = time - (highest relevant level -
  highest requirement) x time / 20, where "relevant" (`getHighestRelevantSkillLevel` ~1063) = the recipe's required
  skills, xp awards, AutoLearnAny and AutoLearnAll skills.
- Where it runs: the client's / single player's `new`, and on an MP server `NetTimedAction` rebuilds the action with
  `ISHandcraftAction.new(...)` and reads `getDuration()` for the real end time. Wrapping `getDuration` therefore
  scales every side once; it computes from scratch each call, so nothing compounds.
- Which skill: the same set vanilla calls relevant. Mastery only exists at level 10, the highest level, so the
  "highest relevant skill" vanilla uses is any relevant skill at 10; the bonus is the best CraftTime of the masteries
  the recipe's relevant skills map to (skills without one count 0). Values <= 1 (instant, no recipe) are left alone.

Everything below runs inside `performRecipe` (~221), which vanilla calls only where items are really made:
`perform` when `not isClient()` (single player, ~191) and `complete` when `isServer()` (MP server, ~210). It runs
`logic:performCurrentRecipe()` (consumes inputs, wears kept tools, creates outputs), `Actions.addOrDropItem` per
output, then the Java OnCreate (`luaCallOnCreate`). OnCreate changes made after `addOrDropItem` are not sent to the
owner by vanilla, so every item this file changes is sent again with `syncItemFields` (carries condition, head
condition, sharpness, uses) and every item it adds goes out with `sendAddItemToContainer`.

- `Spearcraft.SpearCondition` (CarveSpear, FireHardenSpear): Java `RecipeCodeOnCreate.carveSpear` (~639) /
  `fireHardenSpear` (~644) -> `setRandomSpearCondition` = clamp(default + Carving + Rand(0..1), 2, max). After it,
  + `M.int` condition within `getConditionMax()`.
- `Mending.Ripping` (RipClothing, RipDenimClothing; tag RemoveResultItems, so the materials come only from the
  OnCreate): `RecipeCodeOnCreate.ripClothing` (~594) adds clamp(Rand(min..max) + Tailoring / 2, 1, max) of the fabric's
  material (dirty when Rand(99) + 1 <= dirt + blood; clean RippedSheets get modData filterLife) straight to the main
  inventory, max = max(covered parts - (holes + patches), 1). Counted here as the gain of those types in the main
  inventory; + `M.int` more within max, made the same way.
- `Mending.Aramid` (PickAramidThread): `RecipeCodeOnCreate.pickAramidThread` (~1333) sets the created thread's uses to
  clamp(Rand(n, 2n + Tailoring / 2), 1, 10). After it, + `M.int` uses within min(10, max uses).
- `Engineering.Scrap`: one more Base.ElectronicsScrap on a `M.roll`, for any recipe that involves Electricity and
  whose created outputs include Base.ElectronicsScrap (vanilla: DismantleElectronicsDevice with
  `RecipeCodeOnCreate.dismantleElectronics` ~459 / `getRadioBaseItems` ~518 for radios, TVs, walkies; also
  DismantleElectronics and DismantleMiscElectronics). Electrical furniture is in TienSkillMastery_CraftingMoveables.
- `Smithing.ToolWear` (recipes where `craftRecipe:isSmithing()`: involves Blacksmith or category Blacksmithing) and
  `Handicraft.ToolWear` (recipes whose relevant skills include Carving, Knapping, Glassmaking or Pottery):
  kept tools wear inside `performCurrentRecipe` (Java `CraftRecipeData.processKeepInputItem` ~1260: MayDegradeHeavy /
  MayDegrade / Light / VeryLight = `damageCheck(highest relevant level + maintenance mod, 1 / 2 / 3 / 6)`,
  SharpnessCheck = `sharpnessCheck`; `InventoryItem.damageCheck` ~4520 can take a sharpness step (1 / conditionMax),
  a head condition point and a condition point). The kept tools are not known before the call, so every item in the
  craft's containers that a kept, wearing input accepts is noted first; after it, each lost point of the tools
  `getAllKeepInputItems()` reports is put back on its own `M.roll`. Tools tagged BreakOnSmithing (broken on purpose
  by smithing) and a condition forced to 0 by a head at 0 are left alone.

Phase 2 (2026-11-07), also inside `performRecipe`:
- `Smithing.TorchFuel` (any recipe, Smithing master): blowtorch uses are recipe inputs (`item 2 / 4 / 6 / 8
  [Base.BlowTorch]`, 43 recipes). Every blowtorch in the inventory tree and the craft's containers is noted before;
  each use gone after comes back on its own roll (`setCurrentUses` + `syncItemFields`). Welded builds (Java
  `BuildAction`) are not handcrafts and not covered.
- `Smithing.CharcoalBack` (`isSmithing()` recipes): smithing recipes burn `item N tags[base:charcoal]` (Charcoal,
  CharcoalCrafted, Coke). Each consumed piece (`getAllConsumedItems()`, the list vanilla's own performRecipe reads)
  comes back on its own roll, dropped on the smith's square (`AddWorldInventoryItem`, which the server sends).
- `Smithing.OreYield` (primary sources only; smelting scrap is loopable: an IronBarQuarter smelts back into the
  crucible use it was cast from): ExtractIronFromIronOre (`RecipeCodeOnCreate.smeltIronOrSteelIngot`, +12 crucible
  uses for the ore or bloom) gets `M.scaleInt` of those 12 as extra uses within the crucible's max;
  ExtractIronFromIronBloom (12 Base.IronChunk) gets the extra as chunks.
- `Handicraft.CraftsmansMark`: weapons and clothing a Handicraft master makes in a recipe of its skills are marked
  (modData `TSM_Mark` = the bonus now, percent, fixed for good; `TSM_MarkBy` = the maker's name as plain text, since a
  dedicated server has no mod translations), sent with `syncItemFields` (carries modData). The mark's wear undo is in
  server/TienSkillMastery_Physical.lua and works for whoever holds or wears the item.
- Phase 3a signatures: `Smithing.SigMasterwork` marks what a Smithing master makes in an `isSmithing()` recipe like
  the craftsman's mark, at 15% (`TSM_MarkKind` "masterwork"; a mark is never lowered); `Construction.SigPlanks` /
  `SigStones`: SawLogs (1 log -> 3 planks) gives a 4th plank on a 50% roll, Make_Stones_from_Large_Stone (-> 10
  Stone2) 2 more, added with vanilla's own `Actions.addOrDropItem` (sends; drops on the floor when full). Nothing
  turns planks back into logs or stones into a large stone, so neither loops. Recipe tools with a mark are not yet
  given their wear back inside a craft (only held and worn items are watched).
- `Provisioning.LastingFood` (recipes involving Cooking): created Food stays fresh longer, `setOffAge` /
  `setOffAgeMax` x the bonus (saved per item; not in SyncItemFieldsPacket, so the item is re-sent whole with
  `sendReplaceItemInContainer` on a server). Items that never spoil (1e9) are left alone.
]]

require "TienSkillMastery"
require "Entity/TimedActions/ISHandcraftAction"
local M = TienSkillMastery

if not ISHandcraftAction or not ISHandcraftAction.getDuration or not ISHandcraftAction.performRecipe then
    print("[TienSkillMastery] ISHandcraftAction not found, crafting bonuses not applied")
    return
end

local function shortName(recipe)
    local name = recipe and recipe:getName()
    if not name then return nil end
    return name:match("([^%.]+)$")
end

-- ---------------------------------------------------------------------------------------------------------------
-- Crafting time
-- ---------------------------------------------------------------------------------------------------------------

--- Perk ids of the recipe's relevant skills (vanilla's `getHighestRelevantSkillLevel` set), as a set.
local function relevantPerks(recipe)
    local set = {}
    local function each(count, get)
        for i = 0, count - 1 do
            local entry = get(i)
            local perk = entry and entry:getPerk()
            if perk then set[M.anyPerkId(perk)] = true end
        end
    end
    each(recipe:getRequiredSkillCount(), function(i) return recipe:getRequiredSkill(i) end)
    each(recipe:getXPAwardCount(), function(i) return recipe:getXPAward(i) end)
    each(recipe:getAutoLearnAnySkillCount(), function(i) return recipe:getAutoLearnAnySkill(i) end)
    each(recipe:getAutoLearnAllSkillCount(), function(i) return recipe:getAutoLearnAllSkill(i) end)
    return set
end

--- Best CraftTime bonus (percent) among the masteries of the recipe's relevant skills.
local function craftTimeBonus(chr, recipe)
    local best = 0
    for perkId in pairs(relevantPerks(recipe)) do
        local v = M.valFor(chr, M.CRAFT_MASTERY, perkId, "CraftTime")
        if v > best then best = v end
    end
    return best
end

--- Which tool wear undo applies to the recipe for this crafter, if any.
local function toolWearId(chr, recipe)
    if recipe:isSmithing() and M.val(chr, "Smithing.ToolWear") > 0 then return "Smithing.ToolWear" end
    if M.val(chr, "Handicraft.ToolWear") > 0 then
        for perkId in pairs(relevantPerks(recipe)) do
            if M.CRAFT_MASTERY[perkId] == "Handicraft" then return "Handicraft.ToolWear" end
        end
    end
    return nil
end

local function scaleCraftDuration(self, d, ...)
    if type(d) == "number" and d > 1 and self.craftRecipe then
        local chr = self.character
        if chr and not chr:isTimedActionInstant() then
            local ok, bonus = pcall(craftTimeBonus, chr, self.craftRecipe)
            if ok and bonus > 0 then
                d = math.max(2, math.floor(d * math.max(0.05, 1 - bonus / 100) + 0.5))
            end
        end
    end
    return d, ...
end

local vanillaGetDuration = ISHandcraftAction.getDuration
function ISHandcraftAction:getDuration(...)
    return scaleCraftDuration(self, vanillaGetDuration(self, ...))
end

-- ---------------------------------------------------------------------------------------------------------------
-- performRecipe: before / after
-- ---------------------------------------------------------------------------------------------------------------

local RIP_RECIPES = { RipClothing = true, RipDenimClothing = true }
local SPEAR_RECIPES = { CarveSpear = true, FireHardenSpear = true }
local ARAMID_RECIPES = { PickAramidThread = true }

local function fabricTypes()
    local defs = ClothingRecipesDefinitions and ClothingRecipesDefinitions["FabricType"]
    return defs or {}
end

local function countFabric(inv)
    local counts = {}
    for _, def in pairs(fabricTypes()) do
        for _, t in ipairs({ def.material, def.materialDirty }) do
            if t and counts[t] == nil then counts[t] = inv:getNumberOfItem(t) end
        end
    end
    return counts
end

local function wearsTool(input)
    return input:getResourceType() == ResourceType.Item and input:isKeep()
        and (input:mayDegradeHeavy() or input:mayDegrade() or input:mayDegradeLight()
            or input:mayDegradeVeryLight() or input:sharpnessCheck())
end

--- Notes condition / head condition / sharpness of every item a kept, wearing input of the recipe could take.
local function snapshotTools(self, recipe)
    local accepts, any = {}, false
    local inputs = recipe:getInputs()
    for i = 0, inputs:size() - 1 do
        local input = inputs:get(i)
        if wearsTool(input) then
            if input:isAcceptsAnyItem() then
                any = true
            else
                local possible = input:getPossibleInputItems()
                for j = 0, possible:size() - 1 do
                    accepts[possible:get(j):getFullName()] = true
                end
            end
        end
    end
    local tools, found = {}, false
    local function scan(container)
        if not container then return end
        local items = container:getItems()
        for i = 0, items:size() - 1 do
            local item = items:get(i)
            if (any or accepts[item:getFullType()]) and tools[item:getID()] == nil then
                tools[item:getID()] = {
                    c = item:getCondition(),
                    h = item:hasHeadCondition() and item:getHeadCondition() or nil,
                    s = item:hasSharpness() and item:getSharpness() or nil,
                }
                found = true
            end
        end
    end
    scan(self.character:getInventory())
    local containers = (self.logic and self.logic:getContainers()) or self.containers
    if containers then
        for i = 0, containers:size() - 1 do scan(containers:get(i)) end
    end
    return found and tools or nil
end

--- Every blowtorch the craft could draw on: { [item ID] = { item, uses } }, or nil when there is none.
local function snapshotTorches(self)
    local found = nil
    local function scan(container)
        if not container then return end
        local list = container:getAllTypeRecurse("Base.BlowTorch")
        for i = 0, list:size() - 1 do
            local t = list:get(i)
            if instanceof(t, "DrainableComboItem") then
                found = found or {}
                found[t:getID()] = { item = t, uses = t:getCurrentUses() }
            end
        end
    end
    scan(self.character:getInventory())
    local containers = (self.logic and self.logic:getContainers()) or self.containers
    if containers then
        for i = 0, containers:size() - 1 do scan(containers:get(i)) end
    end
    return found
end

local function before(self)
    local chr, recipe = self.character, self.craftRecipe
    if not chr or not recipe then return nil end
    local ctx = { name = shortName(recipe) }
    ctx.toolWear = toolWearId(chr, recipe)
    if ctx.toolWear then
        ctx.tools = snapshotTools(self, recipe)
    end
    if RIP_RECIPES[ctx.name] and M.val(chr, "Mending.Ripping") > 0 then
        ctx.fabric = countFabric(chr:getInventory())
    end
    if M.val(chr, "Smithing.TorchFuel") > 0 then ctx.torches = snapshotTorches(self) end
    return ctx
end

local function addToInventory(chr, item)
    local inv = chr:getInventory()
    inv:AddItem(item)
    sendAddItemToContainer(inv, item)
end

local function undoToolWear(chr, item, s, id)
    local function lucky() return M.roll(chr, id) end
    local changed = false
    local headBackFromZero = false
    if s.h and item:hasHeadCondition() then
        local now = item:getHeadCondition()
        local back = 0
        for _ = 1, s.h - now do
            if lucky() then back = back + 1 end
        end
        if back > 0 then
            item:setHeadCondition(now + back)
            changed = true
            headBackFromZero = now <= 0
        end
    end
    local cond = item:getCondition()
    if headBackFromZero then
        -- the head reaching 0 forced the condition to 0 (setHeadCondition); that goes with the head point
        if cond < s.c then
            item:setConditionNoSound(s.c)
            changed = true
        end
    elseif not (item:hasHeadCondition() and item:getHeadCondition() <= 0) then
        local lost = s.c - cond
        if lost > 0 and lost <= 2 then
            local back = 0
            for _ = 1, lost do
                if lucky() then back = back + 1 end
            end
            if back > 0 then
                item:setConditionNoSound(cond + back)
                changed = true
            end
        end
    end
    if s.s and item:hasSharpness() then
        local inc = item:getSharpnessIncrement()
        local now = item:getSharpness()
        if inc > 0 and now < s.s then
            local lost = math.floor((s.s - now) / inc + 0.5)
            local back = 0
            for _ = 1, lost do
                if lucky() then back = back + 1 end
            end
            if back > 0 then
                item:setSharpness(math.min(s.s, now + back * inc))
                changed = true
            end
        end
    end
    if changed then item:syncItemFields() end
end

local function afterToolWear(chr, data, tools, id)
    local keep = data:getAllKeepInputItems()
    for i = 0, keep:size() - 1 do
        local item = keep:get(i)
        local s = item and tools[item:getID()]
        if s and not item:hasTag(ItemTag.BREAK_ON_SMITHING) then
            undoToolWear(chr, item, s, id)
        end
    end
end

local function afterRipping(chr, data, counts)
    local consumed = data:getAllConsumedItems()
    local clothing
    for i = 0, consumed:size() - 1 do
        local item = consumed:get(i)
        if instanceof(item, "Clothing") and item:getFabricType() and item:getFabricType() ~= "" then
            clothing = item
            break
        end
    end
    if not clothing then return end
    local def = fabricTypes()[clothing:getFabricType()]
    if not def or not def.material then return end
    local inv = chr:getInventory()
    local gained = inv:getNumberOfItem(def.material) - (counts[def.material] or 0)
    if def.materialDirty then
        gained = gained + inv:getNumberOfItem(def.materialDirty) - (counts[def.materialDirty] or 0)
    end
    if gained < 1 then return end
    local maxMaterial = math.max(clothing:getNbrOfCoveredParts() - (clothing:getHolesNumber() + clothing:getPatchesNumber()), 1)
    local extra = math.min(M.int(chr, "Mending.Ripping"), maxMaterial - gained)
    if extra <= 0 then return end
    local grime = math.min(clothing:getDirtiness() + clothing:getBloodLevel(), 100)
    for _ = 1, extra do
        local dirty = ZombRand(99) + 1 <= clothing:getDirtiness() + clothing:getBloodLevel()
        local item = instanceItem(dirty and (def.materialDirty or def.material) or def.material)
        if item then
            if not dirty and item:getFullType() == "Base.RippedSheets" then
                item:getModData().filterLife = 1 - grime / 100
            end
            addToInventory(chr, item)
        end
    end
end

local function afterSpear(chr, created)
    local item = created:size() > 0 and created:get(0)
    if not item then return end
    local n = M.int(chr, "Spearcraft.SpearCondition")
    if n <= 0 then return end
    local target = math.min(item:getCondition() + n, item:getConditionMax())
    if target > item:getCondition() then
        item:setConditionNoSound(target)
        item:syncItemFields()
    end
end

local function afterAramid(chr, created)
    local item = created:size() > 0 and created:get(0)
    if not item then return end
    local n = M.int(chr, "Mending.Aramid")
    if n <= 0 then return end
    local maxUses = math.min(10, item:getMaxUses())
    local target = math.min(item:getCurrentUses() + n, maxUses)
    if target > item:getCurrentUses() then
        item:setCurrentUses(target)
        item:syncItemFields()
    end
end

local function afterScrap(chr, recipe, data, created)
    if not recipe:involvesSkill(Perks.Electricity) then return end
    if data:getAllConsumedItems():size() == 0 then return end
    local hasScrap = false
    for i = 0, created:size() - 1 do
        if created:get(i):getFullType() == "Base.ElectronicsScrap" then
            hasScrap = true
            break
        end
    end
    if hasScrap and M.roll(chr, "Engineering.Scrap") then
        local item = instanceItem("Base.ElectronicsScrap")
        if item then addToInventory(chr, item) end
    end
end

local CHARCOAL = nil
local function charcoalTag()
    if CHARCOAL == nil then
        local ok, tag = pcall(function() return ItemTag.get(ResourceLocation.of("base:charcoal")) end)
        CHARCOAL = ok and tag or false
    end
    return CHARCOAL or nil
end

local function afterTorches(chr, torches)
    for _, t in pairs(torches) do
        local item = t.item
        local now = item:getCurrentUses()
        if now < t.uses and item:getContainer() then
            local back = 0
            for _ = 1, t.uses - now do
                if M.roll(chr, "Smithing.TorchFuel") then back = back + 1 end
            end
            if back > 0 then
                item:setCurrentUses(math.min(t.uses, now + back))
                item:syncItemFields()
            end
        end
    end
end

local function afterCharcoal(chr, data)
    local tag = charcoalTag()
    local square = chr:getCurrentSquare()
    if not tag or not square then return end
    local used = data:getAllConsumedItems()
    for i = 0, used:size() - 1 do
        local item = used:get(i)
        if item and item:hasTag(tag) and M.roll(chr, "Smithing.CharcoalBack") then
            square:AddWorldInventoryItem(item:getFullType(), ZombRandFloat(0.2, 0.8), ZombRandFloat(0.2, 0.8), 0)
        end
    end
end

local ORE_USES = 12
local function afterOre(chr, name, created)
    if M.val(chr, "Smithing.OreYield") <= 0 then return end
    local extra = M.scaleInt(chr, "Smithing.OreYield", ORE_USES) - ORE_USES
    if extra <= 0 then return end
    if name == "ExtractIronFromIronOre" then
        for i = 0, created:size() - 1 do
            local item = created:get(i)
            if item and item.getCurrentUses and item.getMaxUses then
                local now = item:getCurrentUses()
                local target = math.min(item:getMaxUses(), now + extra)
                if target > now then
                    item:setCurrentUses(target)
                    item:syncItemFields()
                end
                return
            end
        end
    elseif name == "ExtractIronFromIronBloom" then
        for _ = 1, extra do addToInventory(chr, instanceItem("Base.IronChunk")) end
    end
end

local function involves(recipe, mastery)
    for perkId in pairs(relevantPerks(recipe)) do
        if M.CRAFT_MASTERY[perkId] == mastery then return true end
    end
    return false
end

--- Marks weapons and clothing just made: `TSM_Mark` (percent of wear ignored, never lowered), maker, kind.
local function markCreated(chr, created, mark, kind)
    if mark <= 0 then return end
    for i = 0, created:size() - 1 do
        local item = created:get(i)
        if item and (instanceof(item, "HandWeapon") or instanceof(item, "Clothing")) then
            local md = item:getModData()
            local value = math.floor(mark * 10 + 0.5) / 10
            if (tonumber(md.TSM_Mark) or 0) < value then
                md.TSM_Mark = value
                md.TSM_MarkBy = chr:getDisplayName() or chr:getUsername()
                md.TSM_MarkKind = kind
                item:syncItemFields()
            end
        end
    end
end

-- Handicraft.ExtraOutput (phase 3c, "pts"): one more of the recipe's first output on a roll, only for recipes vetted
-- so that nothing turns the output back into its inputs (42.21 scripts): knapping (flakes, blades, drills, axe and maul
-- heads), carving end products (spoons, forks, pipes, goblets, cutting boards, dice, stakes, knapping tools) and the
-- hand press (unfired bricks, shingles, tiles: nothing turns them back into clay). Kiln firing runs in the kiln's
-- Java CraftLogic (no performRecipe), not covered. Added with vanilla's `Actions.addOrDropItem`.
local EXTRA_OUTPUT = {
    MakeSharpFlintFlake = true, MakeStoneBlade = true, MakeStoneDrill = true, MakeLargeStoneAxeHead = true,
    MakeStoneMaulHead = true, CarveWoodenSpoon = true, CarveWoodenFork = true, CarvePipe = true, CarveGoblets = true,
    CarveCuttingBoards = true, CarveDice = true, MakeStake = true, CarveKnappingTools = true,
    PressClayBrick = true, PressClayShingle = true, PressClayTile = true, PressClayTileManually = true,
}

local function afterExtraOutput(chr, name, created)
    if not EXTRA_OUTPUT[name] or not M.roll(chr, "Handicraft.ExtraOutput") then return end
    local first = created:get(0)
    local extra = first and instanceItem(first:getFullType())
    if extra then Actions.addOrDropItem(chr, extra) end
end

local function afterMark(chr, created)
    markCreated(chr, created, M.val(chr, "Handicraft.CraftsmansMark"), "craftsman")
end

--- Construction's signature: a 4th plank per sawn log on a roll, 12 stones instead of 10 from a large stone.
local function afterConstruction(chr, name)
    if name == "SawLogs" then
        local chance = M.val(chr, "Construction.SigPlanks")
        if chance > 0 and ZombRandFloat(0, 100) < chance then
            Actions.addOrDropItem(chr, instanceItem("Base.Plank"))
        end
    elseif name == "Make_Stones_from_Large_Stone" then
        for _ = 1, math.floor(M.val(chr, "Construction.SigStones")) do
            Actions.addOrDropItem(chr, instanceItem("Base.Stone2"))
        end
    end
end

local function afterLastingFood(chr, created)
    local f = M.more(chr, "Provisioning.LastingFood")
    if f <= 1 then return end
    for i = 0, created:size() - 1 do
        local item = created:get(i)
        if M.stretchFood(item, f) then M.resendItem(item) end
    end
end

local function after(self, ctx)
    local chr, recipe = self.character, self.craftRecipe
    local data = self.logic and self.logic:getRecipeData()
    if not chr or not recipe or not data then return end
    if ctx.tools then afterToolWear(chr, data, ctx.tools, ctx.toolWear) end
    if ctx.fabric then afterRipping(chr, data, ctx.fabric) end
    if ctx.torches then afterTorches(chr, ctx.torches) end
    if recipe:isSmithing() and M.val(chr, "Smithing.CharcoalBack") > 0 then afterCharcoal(chr, data) end
    local created = data:getAllCreatedItems()
    if created:size() == 0 then return end
    afterOre(chr, ctx.name, created)
    if involves(recipe, "Handicraft") then
        afterMark(chr, created)
        afterExtraOutput(chr, ctx.name, created)
    end
    if recipe:isSmithing() then markCreated(chr, created, M.val(chr, "Smithing.SigMasterwork"), "masterwork") end
    afterConstruction(chr, ctx.name)
    if involves(recipe, "Provisioning") then afterLastingFood(chr, created) end
    if SPEAR_RECIPES[ctx.name] then afterSpear(chr, created) end
    if ARAMID_RECIPES[ctx.name] then afterAramid(chr, created) end
    afterScrap(chr, recipe, data, created)
end

local function finish(self, ctx, ...)
    if ctx then
        local ok, err = pcall(after, self, ctx)
        if not ok then print("[TienSkillMastery] crafting bonus failed: " .. tostring(err)) end
    end
    return ...
end

local vanillaPerformRecipe = ISHandcraftAction.performRecipe
function ISHandcraftAction:performRecipe(...)
    local ok, ctx = pcall(before, self)
    if not ok then
        print("[TienSkillMastery] crafting bonus failed: " .. tostring(ctx))
        ctx = nil
    end
    return finish(self, ctx, vanillaPerformRecipe(self, ...))
end
