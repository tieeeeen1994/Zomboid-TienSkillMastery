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
- Kiln firing (user, 2026-11-09): a 42.21 kiln is a `CraftBench` (entity_kiln_small / large, bench tags KilnSmall /
  KilnLarge), so its Fire* recipes are ordinary handcrafts through this action, but they list no skill at all (no xpAward,
  no requirement). `relevantPerks` counts them as Pottery here, so Handicraft's crafting time and the craftsman's mark
  apply. Vanilla's own `getTime(chr)` still sees no skill. The dome kiln (charcoal, coke) has other tags and is left out.
- The crafting window's time labels: client/TienSkillMastery_CraftTimeLabels.lua, through `M.craftTimeFactor`.

Everything below runs inside `performRecipe` (~221), which vanilla calls only where items are really made:
`perform` when `not isClient()` (single player, ~191) and `complete` when `isServer()` (MP server, ~210). It runs
`logic:performCurrentRecipe()` (consumes inputs, wears kept tools, creates outputs), `Actions.addOrDropItem` per
output, then the Java OnCreate (`luaCallOnCreate`). OnCreate changes made after `addOrDropItem` are not sent to the
owner by vanilla, so every item this file changes is sent again with `syncItemFields` (carries condition, head
condition, sharpness, uses) and every item it adds goes out with `sendAddItemToContainer`.

- `Spearcraft.CarvedDamage`, `CarvedReach` (user, 2026-11-09, replaced a +2 condition that did nothing: Spearcraft needs
  Carving 10, and `RecipeCodeOnCreate.setRandomSpearCondition` = clamp(default + Carving + Rand(0..1), 2, max) already fills a
  carved or fire-hardened spear): any spear from a recipe listing Carving (vanilla: CarveSpear, FireHardenSpear) gets more
  damage and reach, fixed when made, for whoever uses it; the model stays wooden. See "Carved spears" below.
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
- `Smithing.ToolWear` (recipes where `craftRecipe:isSmithing()`: involves Blacksmith or category Blacksmithing; since
  2026-11-09, user, also category Metalworking and any recipe listing Welding, 46 vanilla recipes that wear a tool:
  sawing bars, scrapping metal, welding scrap armor and weapons) and
  `Handicraft.ToolWear` (recipes whose relevant skills include Carving, Knapping, Glassmaking or Pottery):
  kept tools wear inside `performCurrentRecipe` (Java `CraftRecipeData.processKeepInputItem` ~1260: MayDegradeHeavy /
  MayDegrade / Light / VeryLight = `damageCheck(highest relevant level + maintenance mod, 1 / 2 / 3 / 6)`,
  SharpnessCheck = `sharpnessCheck`; `InventoryItem.damageCheck` ~4520 can take a sharpness step (1 / conditionMax),
  a head condition point and a condition point). The kept tools are not known before the call, so every item in the
  craft's containers that a kept, wearing input accepts is noted first; after it, each lost point of the tools
  `getAllKeepInputItems()` reports is put back on its own roll. Tools tagged BreakOnSmithing (broken on purpose
  by smithing) and a condition forced to 0 by a head at 0 are left alone.
- A kept tool's maker's mark (user, 2026-11-09), whoever crafts with it: same notes and rolls, at `M.markChance`,
  combined with the tool wear undo above as server/TienSkillMastery_Physical.lua combines a weapon's. A tool in a hand or
  worn is left to that file's per-tick watcher, which already rolls its mark on whatever the craft took, so the mark
  never rolls twice for it.

Phase 2 (2026-11-07), also inside `performRecipe`:
- `Smithing.TorchFuel` (any recipe, Smithing master): blowtorch uses are recipe inputs (`item 2 / 4 / 6 / 8
  [Base.BlowTorch]`, 43 recipes). Every blowtorch in the inventory tree and the craft's containers is noted before;
  each use gone after comes back on its own roll (`setCurrentUses` + `syncItemFields`). Welded builds are not
  handcrafts: server/TienSkillMastery_CraftingBuild.lua does the same around `ISBuildIsoEntity:create`.
- `Smithing.CharcoalBack` (`isSmithing()` recipes): smithing recipes burn `item N tags[base:charcoal]` (Charcoal,
  CharcoalCrafted, Coke). Each consumed piece (`getAllConsumedItems()`, the list vanilla's own performRecipe reads)
  comes back on its own roll, dropped on the smith's square (`AddWorldInventoryItem`, which the server sends).
- `Smithing.OreYield` (primary sources only; smelting scrap is loopable: an IronBarQuarter smelts back into the
  crucible use it was cast from): ExtractIronFromIronOre (`RecipeCodeOnCreate.smeltIronOrSteelIngot`, +12 crucible
  uses for the ore or bloom) gets `M.scaleInt` of those 12 as extra uses within the crucible's max;
  ExtractIronFromIronBloom (12 Base.IronChunk) gets the extra as chunks.
- `Handicraft.SigCraftsmanship` (the craftsman's mark; a 1.5%-a-level bonus `CraftsmansMark` until 2026-11-08, now a
  signature, 15% from the pick): everything (weapons and clothing only until 2026-11-08; now parts too, passed on like
  masterwork, see "Maker's marks") a Handicraft master makes in a recipe of its skills is marked
  (modData `TSM_Mark` = the bonus now, percent, fixed for good; `TSM_MarkBy` = the maker's name as plain text, since a
  dedicated server has no mod translations), sent with `syncItemFields` (carries modData). The mark's wear undo is in
  server/TienSkillMastery_Physical.lua and works for whoever holds or wears the item.
- Phase 3a signatures: `Smithing.SigMasterwork` marks everything a Smithing master makes in an `isSmithing()` recipe
  (= uses the Blacksmith skill or is in the Blacksmithing category; most forging makes a blade or head, a plain item,
  turned into the weapon by a Maintenance assembly recipe), at 15% (`TSM_MarkKind` "masterwork"; a mark is never
  lowered), and it passes on through later recipes ("Maker's marks" below, user 2026-11-08). A recipe listing Welding
  that is not `isSmithing()` (user, 2026-11-09: scrap swords, knives, cleavers, sawblade weapons, scrap metal armor)
  marks only the weapons and clothing it makes, so a sheet, a drilled chunk or a leftover IronBarQuarter stays plain;
  `Construction.SigPlanks` /
  `SigStones`: every recipe that makes planks gives one more (SawLogs only, on a 50% roll, until 2026-11-08, user;
  Carpentry recipes only, not when it also uses up a plank), Make_Stones_from_Large_Stone (-> 10 Stone2) 2 more, added with vanilla's own `Actions.addOrDropItem` (sends; drops on the floor when full). Nothing
  turns planks back into logs or stones into a large stone, so neither loops.
- `Provisioning.LastingFood` (recipes involving Cooking): created Food stays fresh longer, `setOffAge` /
  `setOffAgeMax` x the bonus (saved per item; not in SyncItemFieldsPacket, so the item is re-sent whole with
  `sendReplaceItemInContainer` on a server). Items that never spoil (1e9) are left alone.
- Recipes that give Butchering XP (vanilla: ButcherSmallAnimal, SliceFillet; user, 2026-11-09): what they make gets
  `M.butcherBonus` (Lasting Food and Choice Cuts) like an animal's meat. Their Java OnCreate (`cutSmallAnimal`, `cutFish`)
  has set the values by then; the re-send carries them too. CutChicken / CutTurkey give Cooking XP and keep Lasting Food
  only: a master's whole chicken has its Choice Cuts already. Fish guts and roe are not created items, so they stay plain.
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

--- True for a kiln's firing recipe (the bench tags; see "Kiln firing" above).
local function isKilnRecipe(recipe)
    local tags = recipe:getTags()
    for i = 0, tags:size() - 1 do
        local tag = string.lower(tags:get(i))
        if tag == "kilnsmall" or tag == "kilnlarge" then return true end
    end
    return false
end

--- Perk ids of the recipe's relevant skills (vanilla's `getHighestRelevantSkillLevel` set, plus Pottery for a kiln's
--- firing), as a set.
local function relevantPerks(recipe)
    local set = {}
    if isKilnRecipe(recipe) then set.Pottery = true end
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

--- The crafting window's categories that name a crafting skill (`CraftRecipe:getCategory`). Many vanilla recipes list no
--- skill at all (37 Blacksmithing, 33 Metalworking, 44 Cooking, 21 Tailoring...), so for crafting time a recipe also
--- counts as its category's skill (user, 2026-11-09). Time only: marks, tool wear and the rest still follow
--- `relevantPerks`. Categories without an entry (Farming, Packing, Weaponry, Tools...) add nothing.
local CATEGORY_PERK = {
    Blacksmithing = "Blacksmith", Metalworking = "MetalWelding", Carpentry = "Woodwork", Masonry = "Masonry",
    Electrical = "Electricity", Carving = "Carving", Knapping = "FlintKnapping", Glassmaking = "Glassmaking",
    Pottery = "Pottery", Tailoring = "Tailoring", Cooking = "Cooking",
}

--- Best CraftTime bonus (percent) among the masteries of the recipe's relevant skills and its category's skill.
local function craftTimeBonus(chr, recipe)
    local best = 0
    local categoryPerk = CATEGORY_PERK[recipe:getCategory()]
    if categoryPerk then best = M.valFor(chr, M.CRAFT_MASTERY, categoryPerk, "CraftTime") end
    for perkId in pairs(relevantPerks(recipe)) do
        local v = M.valFor(chr, M.CRAFT_MASTERY, perkId, "CraftTime")
        if v > best then best = v end
    end
    return best
end

--- The share of a recipe's time this crafter takes: 1 without a bonus, never below 0.05.
function M.craftTimeFactor(chr, recipe)
    return math.max(0.05, 1 - craftTimeBonus(chr, recipe) / 100)
end

--- True for a recipe of Smithing's Welding side: it lists the skill, whichever category it sits in (vanilla: Metalworking
--- and Weaponry). `isSmithing()` tests only Blacksmith and the Blacksmithing category, so it says false for these.
local function listsWelding(recipe)
    return relevantPerks(recipe).MetalWelding == true
end

--- Which tool wear undo applies to the recipe for this crafter, if any.
local function toolWearId(chr, recipe)
    if M.val(chr, "Smithing.ToolWear") > 0
        and (recipe:isSmithing() or recipe:getCategory() == "Metalworking" or listsWelding(recipe)) then
        return "Smithing.ToolWear"
    end
    if M.val(chr, "Handicraft.ToolWear") > 0 then
        -- The category counts too (user, 2026-11-09): vanilla's MeltSand, MeltGlass and the three wooden molds list no
        -- skill. Tool wear only: the craftsman's mark and extra output still follow `relevantPerks`.
        local categoryPerk = CATEGORY_PERK[recipe:getCategory()]
        if categoryPerk and M.CRAFT_MASTERY[categoryPerk] == "Handicraft" then return "Handicraft.ToolWear" end
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
            local ok, factor = pcall(M.craftTimeFactor, chr, self.craftRecipe)
            if ok and factor < 1 then
                d = math.max(2, math.floor(d * factor + 0.5))
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

--- Notes condition / head condition / sharpness of every item a kept, wearing input of the recipe could take: all of
--- them, or with `markedOnly` the ones with a maker's mark.
local function snapshotTools(self, recipe, markedOnly)
    local accepts, any, wears = {}, false, false
    local inputs = recipe:getInputs()
    for i = 0, inputs:size() - 1 do
        local input = inputs:get(i)
        if wearsTool(input) then
            wears = true
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
    if not wears then return nil end
    local tools, found = {}, false
    local function scan(container)
        if not container then return end
        local items = container:getItems()
        for i = 0, items:size() - 1 do
            local item = items:get(i)
            if (any or accepts[item:getFullType()]) and tools[item:getID()] == nil
                and (not markedOnly or M.hasMark(item)) then
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
function M.noteTorches(chr, containers)
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
    scan(chr:getInventory())
    if containers then
        for i = 0, containers:size() - 1 do scan(containers:get(i)) end
    end
    return found
end

--- Every item a repair recipe's damaged input could take: { { item, cond, repaired } }, or nil when it has no such
--- input. The one the recipe repaired is the one whose repair count rose (`RecipeCodeOnCreate.genericFixer` ~1158).
local function snapshotRepairs(self, recipe)
    local accepts, any = {}, false
    local inputs = recipe:getInputs()
    for i = 0, inputs:size() - 1 do
        local input = inputs:get(i)
        if input:getResourceType() == ResourceType.Item and input:isDamaged() then
            local possible = input:getPossibleInputItems()
            for j = 0, possible:size() - 1 do
                accepts[possible:get(j):getFullName()] = true
                any = true
            end
        end
    end
    if not any then return nil end
    local list, seen = {}, {}
    local function scan(container)
        if not container then return end
        local items = container:getItems()
        for i = 0, items:size() - 1 do
            local item = items:get(i)
            if accepts[item:getFullType()] and not seen[item:getID()] then
                seen[item:getID()] = true
                list[#list + 1] = { item = item, cond = item:getCondition(), repaired = item:getHaveBeenRepaired() }
            end
        end
    end
    scan(self.character:getInventory())
    local containers = (self.logic and self.logic:getContainers()) or self.containers
    if containers then
        for i = 0, containers:size() - 1 do scan(containers:get(i)) end
    end
    return list
end

--- Careful repairs on what a repair recipe repaired (M.afterRepair, TienSkillMastery_Repairs.lua).
local function afterRepairs(chr, list)
    for _, s in ipairs(list) do
        if s.item:getHaveBeenRepaired() > s.repaired and M.afterRepair(chr, s.item, s.cond, s.repaired) then
            s.item:syncItemFields()
        end
    end
end

local function before(self)
    local chr, recipe = self.character, self.craftRecipe
    if not chr or not recipe then return nil end
    local ctx = { name = shortName(recipe) }
    if M.val(chr, "Mending.CarefulRepairs") > 0 then ctx.repairs = snapshotRepairs(self, recipe) end
    ctx.toolWear = toolWearId(chr, recipe)
    ctx.tools = snapshotTools(self, recipe, not ctx.toolWear)
    if RIP_RECIPES[ctx.name] and M.val(chr, "Mending.Ripping") > 0 then
        ctx.fabric = countFabric(chr:getInventory())
    end
    if M.val(chr, "Smithing.TorchFuel") > 0 then
        ctx.torches = M.noteTorches(chr, (self.logic and self.logic:getContainers()) or self.containers)
    end
    return ctx
end

local function addToInventory(chr, item)
    local inv = chr:getInventory()
    inv:AddItem(item)
    sendAddItemToContainer(inv, item)
end

--- Percent chance a lost point comes back, for the overall condition and for the head: the tool wear undo `id` (may be
--- nil) combined with the tool's own mark. A tool in a hand or worn keeps its mark for Physical's watcher.
local function wearChances(chr, item, id)
    local a = id and M.val(chr, id) or 0
    local watched = chr:isEquipped(item)
    local function combine(what)
        local b = watched and 0 or M.markChance(item, what)
        return 100 * (1 - (1 - a / 100) * (1 - b / 100))
    end
    return combine("condition"), combine("head")
end

local function undoToolWear(chr, item, s, id)
    local chance, headChance = wearChances(chr, item, id)
    local function lucky(percent) return percent > 0 and ZombRandFloat(0, 100) < percent end
    local changed = false
    local headBackFromZero = false
    if s.h and item:hasHeadCondition() then
        local now = item:getHeadCondition()
        local back = 0
        for _ = 1, s.h - now do
            if lucky(headChance) then back = back + 1 end
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
                if lucky(chance) then back = back + 1 end
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
                if lucky(headChance) then back = back + 1 end
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

--- Each use burnt since `M.noteTorches` comes back on its own `Smithing.TorchFuel` roll (crafts here, builds in
--- server/TienSkillMastery_CraftingBuild.lua).
function M.returnTorchFuel(chr, torches)
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

-- ---------------------------------------------------------------------------------------------------------------
-- Maker's marks: masterwork (Smithing's signature) and the craftsman's mark (Handicraft), user 2026-11-08.
-- Every item a master makes in a recipe of their craft is marked in modData (both kinds work the same way):
--   TSM_Mark / TSM_MarkBy / TSM_MarkKind (+ TSM_MarkPart "head")  the main mark: the whole item, or its head
--   TSM_HandleMark / TSM_HandleMarkBy / TSM_HandleMarkKind        a hafted tool's handle
--   TSM_MarkRole "head" | "handle"                                 what a marked part becomes in a hafted tool
-- A recipe that uses up a marked item as a single piece (a blade, a head, a handle, a knife; not a batch such as nails,
-- not a drainable) passes its marks to what it makes, keeping the maker's name, but only a mark whose kind the crafter
-- is a master of (masterwork: Smithing's signature; craftsman: Handicraft's signature Craftsmanship): a non-master's result is
-- plain. Marks go on every weapon and piece of clothing made, or on the only item made. A weapon with a separate head
-- condition (axes, hammers, picks, scythes, spears) is hafted: a "head" mark covers its head and edge, a "handle" mark
-- its overall condition (the handle); anything else takes the best mark whole. Roles: masterwork is metal, a head;
-- craftsman parts from Carving alone are wood, a handle; from Flint Knapping, Glassmaking or Pottery a head. Marks are
-- never lowered. Works for modded items: it reads marks, not item names or tags. Wear: `M.markChance`.
-- ---------------------------------------------------------------------------------------------------------------

local MARK_SKILL = { masterwork = "Smithing.SigMasterwork", craftsman = "Handicraft.SigCraftsmanship" }

--- Writes a mark into a slot ("whole", "head", "handle") if it beats what is there. True when written.
local function setMark(item, slot, value, by, kind, role)
    local md = item:getModData()
    if slot == "handle" then
        if (tonumber(md.TSM_HandleMark) or 0) >= value then return false end
        md.TSM_HandleMark, md.TSM_HandleMarkBy, md.TSM_HandleMarkKind = value, by, kind
    else
        if (tonumber(md.TSM_Mark) or 0) >= value then return false end
        md.TSM_Mark, md.TSM_MarkBy, md.TSM_MarkKind = value, by, kind
        md.TSM_MarkPart = slot == "head" and "head" or nil
    end
    if role then md.TSM_MarkRole = role end
    return true
end

--- Marks every item just made (whole item) with this master's mark; with `gearOnly`, only the weapons and clothing.
local function markCreated(chr, created, mark, kind, role, gearOnly)
    if mark <= 0 then return end
    local value = math.floor(mark * 10 + 0.5) / 10
    local by = chr:getDisplayName() or chr:getUsername()
    for i = 0, created:size() - 1 do
        local item = created:get(i)
        if item and (not gearOnly or instanceof(item, "HandWeapon") or instanceof(item, "Clothing"))
            and setMark(item, "whole", value, by, kind, role) then
            item:syncItemFields()
        end
    end
end

--- What a craftsman's part becomes in a hafted tool: carved wood is a handle, stone / glass / clay a head.
local function craftsmanRole(recipe)
    local perks = relevantPerks(recipe)
    if perks.Carving and not (perks.FlintKnapping or perks.Glassmaking or perks.Pottery) then return "handle" end
    return "head"
end

--- The marks a used-up item passes on, for the kinds this crafter is a master of.
local function marksOf(chr, item, out)
    local md = item:getModData()
    local main = tonumber(md.TSM_Mark) or 0
    if main > 0 and MARK_SKILL[md.TSM_MarkKind] and M.val(chr, MARK_SKILL[md.TSM_MarkKind]) > 0 then
        local role = md.TSM_MarkPart == "head" and "head" or md.TSM_MarkRole
            or (md.TSM_MarkKind == "craftsman" and "handle" or "head")
        out[#out + 1] = { value = main, by = md.TSM_MarkBy, kind = md.TSM_MarkKind, role = role }
    end
    local handle = tonumber(md.TSM_HandleMark) or 0
    if handle > 0 and MARK_SKILL[md.TSM_HandleMarkKind] and M.val(chr, MARK_SKILL[md.TSM_HandleMarkKind]) > 0 then
        out[#out + 1] = { value = handle, by = md.TSM_HandleMarkBy, kind = md.TSM_HandleMarkKind, role = "handle" }
    end
end

--- Passes the marks of single-piece used-up items on to what the recipe made (rules above).
local function carryMarks(chr, data, created)
    local consumed = data:getAllConsumedItems()
    local count, marks = {}, {}
    for i = 0, consumed:size() - 1 do
        local item = consumed:get(i)
        if item then count[item:getFullType()] = (count[item:getFullType()] or 0) + 1 end
    end
    for i = 0, consumed:size() - 1 do
        local item = consumed:get(i)
        if item and count[item:getFullType()] == 1 and not instanceof(item, "DrainableComboItem") then
            marksOf(chr, item, marks)
        end
    end
    if #marks == 0 then return end
    local only = created:size() == 1
    for i = 0, created:size() - 1 do
        local item = created:get(i)
        local weapon = item and instanceof(item, "HandWeapon")
        if item and (only or weapon or instanceof(item, "Clothing")) then
            local hafted = weapon and item:hasHeadCondition()
            local changed = false
            for _, m in ipairs(marks) do
                local slot = hafted and (m.role == "handle" and "handle" or "head") or "whole"
                if setMark(item, slot, m.value, m.by, m.kind, not hafted and m.role or nil) then changed = true end
            end
            if changed then item:syncItemFields() end
        end
    end
end

-- Handicraft.ExtraOutput (phase 3c, "pts"): one more of the recipe's first output on a roll, only for recipes vetted
-- so that nothing turns the output back into its inputs (42.21 scripts): knapping (flakes, blades, drills, axe and maul
-- heads), carving end products (spoons, forks, pipes, goblets, cutting boards, dice, stakes, knapping tools) and the
-- hand press (unfired bricks, shingles, tiles: nothing turns them back into clay). Kiln firing is not on the list: the
-- user asked for its time and mark only. Added with vanilla's `Actions.addOrDropItem`.
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

local function afterMark(chr, recipe, created)
    markCreated(chr, created, M.val(chr, "Handicraft.SigCraftsmanship"), "craftsman", craftsmanRole(recipe))
end

-- Carved spears (`Spearcraft.CarvedDamage`, `CarvedReach`, user 2026-11-09): a plain stats bonus, set so that a spear carved
-- at mastery 10 ends up near a forged one without passing it. Carved 1.0-1.4 + 8% = 1.08-1.51, average 1.296 (forged short
-- 1.0-1.6, 1.30); fire-hardened 1.0-1.5 = 1.08-1.62, average 1.35 (forged long 1.2-1.7, 1.45); reach 1.4 + 3% = 1.442 (forged
-- 1.45, 1.48). Min / max damage and max range are saved per weapon and sent with it (42.21 `HandWeapon.save`,
-- `SyncHandWeaponFieldsPacket`), so they are set directly. Left as they are, by the user's choice: lifespan (max condition
-- and the wear chance are not saved: `InventoryItem.save` writes only the condition, `HandWeapon.load` takes the rest from
-- the script) and a fire-hardened spear's crit (30%, x10 against forged's 20%, x5, in vanilla). A spear fire-hardened from
-- a carved one is a new item with the script's stats, so the bonus never stacks.
local function afterCarvedSpears(chr, created)
    local damage, reach = M.more(chr, "Spearcraft.CarvedDamage"), M.more(chr, "Spearcraft.CarvedReach")
    if damage <= 1 and reach <= 1 then return end
    for i = 0, created:size() - 1 do
        local item = created:get(i)
        if item and M.weaponMastery(item) == "Spearcraft" then
            item:setMaxDamage(item:getMaxDamage() * damage)
            item:setMinDamage(item:getMinDamage() * damage)
            item:setMaxRange(item:getMaxRange() * reach)
            M.resendItem(item)     -- the item bytes carry the stats
        end
    end
end

--- Construction's signatures. Clean Cuts (user, 2026-11-08; SawLogs only before): one more plank from every Carpentry
--- recipe that makes planks (one involving Woodwork: vanilla SawLogs 3 -> 4, SawLargeBranch 1 -> 2; modded ones too;
--- not vanilla's CarvePlank, a Carving recipe), except one that also uses up a plank, so a plank-in, planks-out
--- recipe cannot be repeated for endless planks. The
--- chance is `Construction.SigPlanks` (100). Clean Breaks: 12 stones instead of 10 from a large stone.
local function afterConstruction(chr, name, recipe, data, created)
    local chance = M.val(chr, "Construction.SigPlanks")
    if chance > 0 and relevantPerks(recipe).Woodwork then
        local made = false
        for i = 0, created:size() - 1 do
            local item = created:get(i)
            if item and item:getFullType() == "Base.Plank" then made = true break end
        end
        if made then
            local consumed = data:getAllConsumedItems()
            for i = 0, consumed:size() - 1 do
                local item = consumed:get(i)
                if item and item:getFullType() == "Base.Plank" then made = false break end
            end
        end
        if made and ZombRandFloat(0, 100) < chance then
            Actions.addOrDropItem(chr, instanceItem("Base.Plank"))
        end
    end
    if name == "Make_Stones_from_Large_Stone" then
        for _ = 1, math.floor(M.val(chr, "Construction.SigStones")) do
            Actions.addOrDropItem(chr, instanceItem("Base.Stone2"))
        end
    end
end

--- Clean Breaks' flat stone recipe (TSM_BreakFlatStone, media/scripts/TienSkillMastery_recipes.txt), masters only.
--- OnAddToMenu (the crafting window's lists, `callLuaBool(name, { player, recipe, shouldShowAll })`) hides it from
--- everyone else. It must be a plain global name: 42.21 `callLuaBool` looks it up with `env.rawget(name)`, so a
--- dotted name is never found and the recipe is hidden from everyone (the right-click menu does not ask it); OnTest
--- goes through `LuaManager.getFunctionObject`, which follows dots. OnTest (`CraftRecipe.OnTestItem(item, character)`, every candidate input item, on the client for
--- the window and on the server for the craft) refuses it, so a non-master cannot craft it in MP either.
function TienSkillMastery_FlatStoneMenu(params)
    local player = params and params.player
    return player ~= nil and M.sig(player, "Construction.SigStones")
end

function TienSkillMastery.FlatStoneTest(item, character)
    return character ~= nil and M.sig(character, "Construction.SigStones")
end

--- Needlework's recipes (TSM_MakeBandage, TSM_MakeSutureNeedle), gated the same way.
function TienSkillMastery_NeedleworkMenu(params)
    local player = params and params.player
    return player ~= nil and M.sig(player, "FieldMedicine.SigNeedlework")
end

function TienSkillMastery.NeedleworkTest(item, character)
    return character ~= nil and M.sig(character, "FieldMedicine.SigNeedlework")
end

local function afterLastingFood(chr, created)
    local f = M.more(chr, "Provisioning.LastingFood")
    if f <= 1 then return end
    for i = 0, created:size() - 1 do
        local item = created:get(i)
        if M.stretchFood(item, f) then M.resendItem(item) end
    end
end

local function afterButchering(chr, created)
    for i = 0, created:size() - 1 do
        local item = created:get(i)
        if M.butcherBonus(item, chr) then M.resendItem(item) end
    end
end

local function after(self, ctx)
    local chr, recipe = self.character, self.craftRecipe
    local data = self.logic and self.logic:getRecipeData()
    if not chr or not recipe or not data then return end
    if ctx.repairs then afterRepairs(chr, ctx.repairs) end
    if ctx.tools then afterToolWear(chr, data, ctx.tools, ctx.toolWear) end
    if ctx.fabric then afterRipping(chr, data, ctx.fabric) end
    if ctx.torches then M.returnTorchFuel(chr, ctx.torches) end
    if recipe:isSmithing() and M.val(chr, "Smithing.CharcoalBack") > 0 then afterCharcoal(chr, data) end
    local created = data:getAllCreatedItems()
    if created:size() == 0 then return end
    afterOre(chr, ctx.name, created)
    if involves(recipe, "Handicraft") then
        afterMark(chr, recipe, created)
        afterExtraOutput(chr, ctx.name, created)
    end
    if recipe:isSmithing() then
        markCreated(chr, created, M.val(chr, "Smithing.SigMasterwork"), "masterwork", "head")
    elseif listsWelding(recipe) then
        markCreated(chr, created, M.val(chr, "Smithing.SigMasterwork"), "masterwork", "head", true)
    end
    carryMarks(chr, data, created)
    afterConstruction(chr, ctx.name, recipe, data, created)
    if relevantPerks(recipe).Butchering then
        afterButchering(chr, created)
    elseif involves(recipe, "Provisioning") then
        afterLastingFood(chr, created)
    end
    if relevantPerks(recipe).Carving then afterCarvedSpears(chr, created) end
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
