--[[
Tien's Skill Mastery: what each level of First Aid and the outdoor skills gives in vanilla 42.21 (shown in the Skills
tab). Sources (vanilla Lua and decompiled 42.21):

First Aid (Doctor): treatment times (each action's getDuration: bandage / disinfect / poultices 120 - 4 L, splint
140 - 4 L, stitch base - 4 L, clean burn / remove bullet 250 - 6 L, remove glass 150 - 4 L; medical check 150 - 2.5 L,
client ISMedicalCheckAction ~85); bandage life rand((L + 1) x 0.5, L + 1) + bandage power; poultice power rand(same)
+ 10; splint factor (L + 1) / 2; stitch time (1 + L) / 2 x rand(2, 5) (each action's complete); the health panel
shows more about wounds with level (ISHealthPanel doctorLevel).
Fishing: line tension limit 120 + 10 L (FishingRod.updateLine ~118); cast scatter / (L + 1) (~69); natural bait used
when rand(20) > L, artificial lures 1 in 30 (L + 1) (FishingRod.consumeLure ~365); fish size chances (FishingUtils
~172: 95/5/0 .. 10/40/50), size limit (~158: 1.4 .. 45); junk x0.8 from 5, x0.6 from 7, x0.2 from 9 (Fish.lua ~77);
trophy fish 1 in 20 of big fish from 8 (~153); reeling uses Strength (FishingRod ~186); fishing window shows time from
2, temperature from 4, weather and caught-fish records from 6, wind from 8 (FishWindow ~41, ~161..226).
Foraging (PlantScavenging): search radius min + (max - min) x L / 10 (ISSearchManager ~1028); vision bonus + 0.5 x L
(forageSystem.levelBonus ~107); icons identified at (0.25 + 0.05 L) x view distance (ISBaseIcon ~370); spotting time
300 + (11 - L) x 200 ms (~498); spots items in a cone of L x 6 degrees ahead (~524); adjacent squares checked from 5
(~283); poisonous finds + (10 - L) x 3 (forageSystem ~2230); fresher finds L in 10 (~2246); found item size
+ (rand(L) + 1) x 0.05 (~2273).
Tracking: finds tracks / ((L + 1) / 0.7) (AnimalTracks.canFindTrack ~94), only tracks whose minimum skill you meet
(~92), within 20 + 2 L (~143); inspection time 100 - 1.5 L (ISInspectAnimalTrackAction ~54); track details from 5
(ISAnimalTracksUI ~53); animals notice you / ((L + 2) x 0.5) (BaseAnimalBehavior ~1583).
Trapping: catch chance + 1.5 x the level saved on the trap when placed (TrapSystem ~46, STrapGlobalObject ~375).
Farming: harvest: L in 10 chance of + L more (getVegetablesNumber); cures remove 10 + L per use (SPlantGlobalObject
cure*); new plants start at rand(57, 64) + L health; best-month bonus yield (9 + L) / 20, risk-month curse
(11 - L) / 20 (seed); fertilizer early effect (9 + L) / 20 (fertilize2); back strain x (1 - 0.05 L) (harvest, plow,
seed, remove grass / bush); plant info shows water and health from 3, more from 6 (CFarmingSystem ~101 / ~115);
season recipes learned at 10 (XpUpdate.onLoad). The sandbox yield option does nothing in 42.21.
Animal Care (Husbandry): acceptance gains x (1 + L / 10) (IsoAnimal ~2469 / ~2571); petting calms by rand(7, 11) + L,
cooldown 15000-25000 - 200 L (~2497); hand feeding rand(2, 4) + L / 5 (~2487); milking / shearing stress the animal
1 in (L + 3) up to level 5 (~1825 / ~1871), stressed animals fight back less (chance - 5 L, none above 7; ISMilkAnimal
~17, ISShearAnimal ~16); shearing time per litre - 2 L (ISShearAnimal ~159); animal info: acceptance and pregnancy from
3, eggs from 4, more from 5 (ISAnimalUI ~102..202, NetworkPlayerAI ~209).
Butchering: part counts x (1 + floor(L / 2) / 10) (ButcheringUtil.addAnimalPart ~227); part chance x L / 7
(getPartChance ~417); blood rand(22 - 2 L) (~170); times (ISButcherAnimal 900 - 20 L, hook / unhook / head 250 - 10 L,
cut on hook 150 - 10 L, leather 400 - 15 L, meat 450 - 15 L).
]]

require "TienSkillMastery_SkillEffects"
local M = TienSkillMastery

local SIZE = { { 95, 5, 0 }, { 85, 15, 0 }, { 75, 24, 1 }, { 70, 25, 5 }, { 60, 30, 10 }, { 48, 40, 12 },
    { 35, 45, 20 }, { 25, 45, 30 }, { 20, 40, 40 }, { 15, 40, 45 }, { 10, 40, 50 } }
local SIZE_LIMIT = { 1.4, 1.5, 1.9, 2.2, 2.3, 2.8, 4.5, 9, 27, 32, 45 }
local function lv(L) return math.max(0, math.min(10, L)) + 1 end

M.addSkillEffects("Doctor", {
    { name = "TreatTime", format = "pct", value = function(L) return -100 * 4 * L / 120 end },
    { name = "BulletTime", format = "pct", value = function(L) return -100 * 6 * L / 250 end },
    { name = "CheckTime", format = "pct", value = function(L) return -100 * 2.5 * L / 150 end },
    { name = "BandageLife", format = "plain", value = function(L) return (L + 1) * 0.75 end },
    { name = "SplintFactor", format = "plain", value = function(L) return (L + 1) / 2 end },
    { name = "StitchTime", format = "plain", value = function(L) return (1 + L) / 2 * 3.5 end },
    { name = "PanelInfo", unlock = 0 },
})

M.addSkillEffects("Fishing", {
    { name = "Tension", format = "plain", value = function(L) return 120 + 10 * L end, note = "IGUI_TienSkillMastery_EffectNote_TimesRod" },
    { name = "BaitKept", format = "chance", value = function(L) return 100 * math.min(20, L + 1) / 20 end },
    { name = "LureLost", format = "plain", value = function(L) return 30 * (L + 1) end },
    { name = "SizeSmall", format = "chance", value = function(L) return SIZE[lv(L)][1] end },
    { name = "SizeMedium", format = "chance", value = function(L) return SIZE[lv(L)][2] end },
    { name = "SizeBig", format = "chance", value = function(L) return SIZE[lv(L)][3] end },
    { name = "SizeLimit", format = "plain", value = function(L) return SIZE_LIMIT[lv(L)] end },
    { name = "Junk", format = "mult", value = function(L)
        if L >= 9 then return 0.2 elseif L >= 7 then return 0.6 elseif L >= 5 then return 0.8 end
        return 1.0
    end },
    { name = "Scatter", format = "mult", value = function(L) return 1 / (L + 1) end },
    { name = "InfoTime", unlock = 2 },
    { name = "InfoTemperature", unlock = 4 },
    { name = "InfoWeather", unlock = 6 },
    { name = "Trophy", unlock = 8 },
    { name = "InfoWind", unlock = 8 },
})

M.addSkillEffects("PlantScavenging", {
    { name = "Radius", format = "pct", value = function(L) return 10 * L end },
    { name = "Vision", format = "num", value = function(L) return 0.5 * L end },
    { name = "Identify", format = "chance", value = function(L) return 25 + 5 * L end },
    { name = "Spotting", format = "plain", value = function(L) return (300 + (11 - L) * 200) / 1000 end },
    { name = "Cone", format = "plain", value = function(L) return 6 * L end },
    { name = "Poison", format = "pts", value = function(L) return 3 * (10 - L) end },
    { name = "Fresh", format = "chance", value = function(L) return 10 * L end },
    { name = "Size", format = "pct", value = function(L) return 2.5 * (L + 1) end },
    { name = "Adjacent", unlock = 5 },
})

M.addSkillEffects("Tracking", {
    { name = "Find", format = "mult", value = function(L) return L + 1 end },
    { name = "Radius", format = "plain", value = function(L) return 20 + 2 * L end },
    { name = "InspectTime", format = "pct", value = function(L) return -1.5 * L end },
    { name = "Animals", format = "mult", value = function(L) return 1 / ((L + 2) * 0.5) end },
    { name = "MinSkill", unlock = 0 },
    { name = "Details", unlock = 5 },
})

M.addSkillEffects("Trapping", {
    { name = "Catch", format = "pts", value = function(L) return 1.5 * L end, note = "IGUI_TienSkillMastery_EffectNote_Placed" },
})

M.addSkillEffects("Farming", {
    { name = "Harvest", format = "chance", value = function(L) return 10 * L end, note = "IGUI_TienSkillMastery_EffectNote_PlusLevel" },
    { name = "Cure", format = "plain", value = function(L) return 10 + L end },
    { name = "PlantHealth", format = "num", value = function(L) return L end },
    { name = "BestMonth", format = "chance", value = function(L) return 100 * (9 + L) / 20 end },
    { name = "Curse", format = "chance", value = function(L) return math.max(0, 100 * (11 - L) / 20) end },
    { name = "Fertilize", format = "chance", value = function(L) return math.min(100, 100 * (9 + L) / 20) end },
    { name = "BackStrain", format = "pct", value = function(L) return -5 * L end },
    { name = "Info", unlock = 3 },
    { name = "InfoMore", unlock = 6 },
    { name = "Seasons", unlock = 10 },
})

M.addSkillEffects("Husbandry", {
    { name = "Acceptance", format = "pct", value = function(L) return 10 * L end },
    { name = "Petting", format = "num", value = function(L) return L end },
    { name = "PetCooldown", format = "plain", value = function(L) return (20000 - 200 * L) / 1000 end },
    { name = "HandFeed", format = "num", value = function(L) return L / 5 end },
    { name = "Fights", format = "pts", value = function(L) return -5 * L end },
    { name = "ShearTime", format = "num", value = function(L) return -2 * L end },
    { name = "CalmMilking", unlock = 6 },
    { name = "InfoPregnancy", unlock = 3 },
    { name = "InfoEggs", unlock = 4 },
    { name = "InfoMore", unlock = 5 },
    { name = "NoFightBack", unlock = 8 },
})

M.addSkillEffects("Butchering", {
    { name = "PartCount", format = "mult", value = function(L) return 1 + math.floor(L / 2) / 10 end },
    { name = "PartChance", format = "mult", value = function(L) return L / 7 end },
    { name = "Time", format = "pct", value = function(L) return -100 * 20 * L / 900 end },
    { name = "HookTime", format = "pct", value = function(L) return -4 * L end },
    { name = "MeatTime", format = "pct", value = function(L) return -100 * 15 * L / 450 end },
    { name = "Blood", format = "plain", value = function(L) return math.max(0, 22 - 2 * L) end },
})
