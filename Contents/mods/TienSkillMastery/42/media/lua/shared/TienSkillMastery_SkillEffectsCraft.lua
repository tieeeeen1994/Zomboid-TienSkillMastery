--[[
Tien's Skill Mastery: what each level of the crafting skills gives in vanilla 42.21 (shown in the Skills tab).
Sources (decompiled 42.21 and vanilla Lua):

Every crafting skill: handcraft time - (best relevant level - highest requirement) x time / 20 (CraftRecipe.getTime);
some recipes are learned automatically at set levels (ScriptManager.checkAutoLearn on level-up). Skills with scrap
definitions (Carpentry, Electrical, Masonry, Welding): dismantling returns each material at 10 + 10 x level, plus the
definition's base (ISMoveableSpriteProps:getChanceByDef ~3834). Skills that are a pick-up tool's perk (Carpentry:
hammer / crowbar / cutter / screwdriver; Electrical; Welding: "Metal"): furniture breaks when picked up (10 - L) x 7.5
in 100, windows 5 + (10 - L) x 5 (getBreakChance ~334).
Carpentry: build time 200 - 5 L (Java BuildAction.getDuration ~85, every build-menu build), built structure health
+ skill base health x level (ISBuildIsoEntity:setInfo), barricade time 100 - 5 L (ISBarricadeAction ~179), unbarricade
200 - 5 L (ISUnbarricadeAction ~158), plank barricade strength x getBarricadeStrengthMod (IGC ~4374: 1.0 .. 1.5,
IsoBarricade ~89), hammering noise radius 20 x getHammerSoundMod (1 / 0.8 / 0.6 / 0.4 at 0-1 / 2 / 3 / 4+;
ISBuildAction ~88), build menu designs by level (CraftRecipe_BuildMenu tests, tiers at 3 to 8).
Carving: carved / fire-hardened spear condition = default + level (+0..1) (RecipeCodeOnCreate.setRandomSpearCondition
~651).
Cooking: nutrition from added ingredients x (1 + L / 15) (EvolvedRecipe.addItem ~229), ingredient used x
(1 - 0.03 L), time to add 100 - 2.5 L (ISAddItemInRecipe ~228); rotten ingredients usable from 7 (RecipeManager ~497,
~591; EvolvedRecipe.getItemsCanBeUse); spots a poison when level >= 10 - its detection level (IGC ~11817); food
tooltips show cooking details from 5 (Food ~1538); canning keeps the jar lid's condition L in 11 (RecipeCodeOnCreate
.modifyLidCondition ~288).
Electrical: hotwire offered from 1 (with Mechanics 2; ISVehicleMenu ~116); hotwire chance + 4 x level (Java
BaseVehicle.tryHotwire), time 200 - 3 L (ISHotwireVehicle ~47); generator repair + 4 + L / 2 condition, time 150 - 3 L
(ISFixGenerator ~70 / ~84); generators connectable from 3 (or the recipe; ISWorldObjectContextMenuLogic ~2099); lamp
modifying from 5 (ISLightActions.perkLevel); radio / TV / walkie parts 50 + 5 x level in 100 (RecipeCodeOnCreate
.dismantleRadio* ~485 / ~498 / ~537); crafted radios get better values with level (getRandomRadioValue ~567).
Knapping: an extra sharpened stone L in 11 (RecipeCodeOnCreate.knappFlake ~1269).
Masonry: build menu brick designs by level (CraftRecipe_BuildMenu ~339 / ~347); dismantling bricks.
Metalworking: smithing recipes break BreakOnSmithing inputs and wear tools by the craft's skill (CraftRecipe ~1189,
CraftRecipeData tool wear uses the highest relevant level + Maintenance).
Mechanics: hotwire offered from 2 (with Electrical 1); install / uninstall time - L x time / 15 (ISVehiclePartMenu ~194,
ISUninstallVehiclePart ~106); mechanics window opens in 200 - L x 200 / 15 (ISOpenMechanicsUIAction ~46); engine
repair + 1 + (L - car's level) / 2 condition per part, max 5 (ISRepairEngine ~44, ISRepairLightbar); engine parts
salvaged: condition / random(x / 3, x), x = max(20 - (L - car's level), 5) (ISTakeEngineParts ~42); installer skill
saved on the part (VehiclePart.setInventoryItem: brakes and tires work better); engine / lightbar repair and headlight
aiming need the car's level (ISVehicleMechanics ~325..364); burnt cars give engine parts at the lower of Mechanics and
Welding (ISRemoveBurntVehicle ~147).
Tailoring: patch / remove time 150 - 6 L (ISRepairClothing ~90, ISRemovePatch ~87); patch bite / scratch defense =
fabric max x max(1, L) / 10 (Clothing ~984 / ~990); patches lose 2 condition below 3 (Clothing ~1092); same fabric
fully restores a hole from 8 (canFullyRestore ~1038); fabric back when removing a patch + 5 x level (ISRemovePatch ~78);
ripping clothes + L / 2 materials (RecipeCodeOnCreate ~603); aramid thread + L / 2 uses (~1336); hide jackets L in 21
for the better look from 6 (~1323).
Welding: welding noise radius 20 x getWeldingSoundMod (IGC ~4292, ISBarricadeAction ~66); metal barricade time
170 - 5 L (ISBarricadeAction ~181) and strength (IGC ~4330); burnt car time 800 - 20 L (ISRemoveBurntVehicle ~186),
max(5, L) salvage rounds of 1 in (base - L) each (~63 / ~153).
Glassmaking, Pottery: only the general crafting rules (no other reader in 42.21).
Skipped: getBarricadeTimeMod (no callers), XP-only rules.
]]

require "TienSkillMastery_SkillEffects"
local M = TienSkillMastery

local function shared(list, scrap, tool)
    local out = {
        { name = "CraftTime", unlock = 0, labelPerk = "Craft" },
        { name = "AutoLearn", unlock = 0, labelPerk = "Craft" },
    }
    if scrap then
        table.insert(out, { name = "Dismantle", format = "chance", labelPerk = "Craft",
            value = function(L) return math.min(100, 10 + 10 * L) end, note = "IGUI_TienSkillMastery_EffectNote_PlusBase" })
    end
    if tool then
        table.insert(out, { name = "BreakFurniture", format = "chance", labelPerk = "Craft",
            value = function(L) return math.max(0, (10 - L) * 7.5) end })
        table.insert(out, { name = "BreakWindow", format = "chance", labelPerk = "Craft",
            value = function(L) return 5 + (10 - L) * 5 end })
    end
    for _, e in ipairs(list or {}) do table.insert(out, e) end
    return out
end

local BARRICADE = { 1.0, 1.0, 1.1, 1.14, 1.18, 1.22, 1.26, 1.3, 1.34, 1.4, 1.5 }
local function hammerSound(L)
    if L >= 4 then return 0.4 elseif L == 3 then return 0.6 elseif L == 2 then return 0.8 end
    return 1.0
end

M.addSkillEffects("Woodwork", shared({
    { name = "BuildTime", format = "pct", value = function(L) return -100 * 5 * L / 200 end },
    { name = "BuildHealth", format = "num", value = function(L) return L end, note = "IGUI_TienSkillMastery_EffectNote_TimesBase" },
    { name = "Barricade", format = "pct", value = function(L) return -5 * L end },
    { name = "Unbarricade", format = "pct", value = function(L) return -100 * 5 * L / 200 end },
    { name = "PlankStrength", format = "mult", value = function(L) return BARRICADE[math.min(10, L) + 1] end },
    { name = "Noise", format = "mult", value = hammerSound },
    { name = "Designs", unlock = 3 },
}, true, true))

M.addSkillEffects("Carving", shared({
    { name = "Spear", format = "num", value = function(L) return L end },
}))

M.addSkillEffects("Cooking", shared({
    { name = "Nutrition", format = "pct", value = function(L) return 100 * L / 15 end },
    { name = "IngredientUse", format = "pct", value = function(L) return -3 * L end },
    { name = "AddTime", format = "pct", value = function(L) return -2.5 * L end },
    { name = "Poison", format = "plain", value = function(L) return math.max(0, 10 - L) end },
    { name = "LidKept", format = "chance", value = function(L) return 100 * math.min(11, L) / 11 end },
    { name = "Tooltip", unlock = 5 },
    { name = "Rotten", unlock = 7 },
}))

M.addSkillEffects("Electricity", shared({
    { name = "Hotwire", unlock = 1, note = "IGUI_TienSkillMastery_EffectNote_Mechanics2" },
    { name = "HotwireChance", format = "pts", value = function(L) return 4 * L end },
    { name = "HotwireTime", format = "pct", value = function(L) return -100 * 3 * L / 200 end },
    { name = "GeneratorRepair", format = "num", value = function(L) return 4 + L / 2 end },
    { name = "GeneratorTime", format = "pct", value = function(L) return -100 * 3 * L / 150 end },
    { name = "RadioParts", format = "chance", value = function(L) return math.min(100, 50 + 5 * L) end },
    { name = "RadioQuality", unlock = 0 },
    { name = "Generator", unlock = 3 },
    { name = "Lamps", unlock = 5 },
}, true, true))

M.addSkillEffects("Glassmaking", shared())
M.addSkillEffects("Pottery", shared())

M.addSkillEffects("FlintKnapping", shared({
    { name = "ExtraStone", format = "chance", value = function(L) return 100 * math.min(11, L) / 11 end },
}))

M.addSkillEffects("Masonry", shared({
    { name = "Designs", unlock = 0 },
}, true))

M.addSkillEffects("Blacksmith", shared({
    { name = "ToolWear", unlock = 0 },
}))

M.addSkillEffects("Mechanics", shared({
    { name = "Hotwire", unlock = 2, note = "IGUI_TienSkillMastery_EffectNote_Electrical1" },
    { name = "InstallTime", format = "pct", value = function(L) return -100 * L / 15 end },
    { name = "OpenHood", format = "pct", value = function(L) return -100 * L / 15 end },
    { name = "EngineRepair", format = "num", value = function(L) return math.min(5, 1 + L / 2) end, note = "IGUI_TienSkillMastery_EffectNote_CarLevel" },
    { name = "Installer", unlock = 0 },
    { name = "CarLevel", unlock = 0 },
}))

M.addSkillEffects("Tailoring", shared({
    { name = "PatchTime", format = "pct", value = function(L) return -100 * 6 * L / 150 end },
    { name = "PatchDefense", format = "pct", value = function(L) return 10 * math.max(1, L) end },
    { name = "FabricBack", format = "pts", value = function(L) return 5 * L end },
    { name = "Ripping", format = "num", value = function(L) return math.floor(L / 2) end },
    { name = "Aramid", format = "num", value = function(L) return math.floor(L / 2) end },
    { name = "PatchCondition", unlock = 3 },
    { name = "HideJacket", unlock = 6 },
    { name = "FullRestore", unlock = 8 },
}))

M.addSkillEffects("MetalWelding", shared({
    { name = "BurntCarTime", format = "pct", value = function(L) return -100 * 20 * L / 800 end },
    { name = "BurntCarRounds", format = "plain", value = function(L) return math.max(5, L) end },
    { name = "MetalBarricade", format = "pct", value = function(L) return -100 * 5 * L / 170 end },
    { name = "Noise", unlock = 2 },
}, true, true))
