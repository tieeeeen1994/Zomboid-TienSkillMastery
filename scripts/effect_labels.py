"""Adds the Skills-tab effect labels (IGUI_TienSkillMastery_Effect_*) to Translate/EN/IG_UI.json.

    py scripts/effect_labels.py

Keys are <perk>_<name> as registered in shared/TienSkillMastery_SkillEffects*.lua ("Melee" and "Craft" are shared
labels). No percent sign in labels: the game's Translator formats every string at load.
"""
import json
import os

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PATH = os.path.join(REPO, "Contents", "mods", "TienSkillMastery", "42", "media", "lua", "shared", "Translate", "EN",
                    "IG_UI.json")

E = {
    "Fitness": {"AttackSpeed": "Attack speed", "EnduranceRegen": "Endurance regeneration",
                "RunEndurance": "Endurance used running and sprinting", "SwingEndurance": "Endurance used per swing",
                "FallDamage": "Fall damage", "FallInjury": "Injury roll after a fall",
                "FendOff": "Chance to fend off a zombie in front", "LungeFall": "Chance to fall when a crawler lunges",
                "Climbing": "Climbing check", "FenceFall": "Chance to fall vaulting a fence",
                "WindowEscape": "Escaping a grabbing zombie through a window",
                "Bump": "Staying up when bumping into someone", "WindowEffort": "Effort opening windows",
                "Rope": "Rope climbing uses the higher of Fitness and Strength"},
    "Strength": {"Capacity": "Carrying capacity before traits", "Damage": "Melee damage",
                 "Shove": "Shove and knockback strength", "ShoveKnockdown": "Shove knockdown chance",
                 "Stomp": "Stomp damage", "Strain": "Muscle strain from fighting",
                 "FendOff": "Chance to fend off a zombie in front", "Climbing": "Climbing check",
                 "Bump": "Staying up when bumping into someone", "ForceWindow": "Forcing a locked window open",
                 "DoorDamage": "Weapon damage to doors", "Recoil": "Firearm recoil delay",
                 "PickUpAnimal": "Heaviest animal you can pick up", "Dismantle": "Dismantling time",
                 "Sledgehammer": "Sledgehammer and pickaxe time", "Reeling": "Reeling strength when fishing",
                 "Rope": "Rope climbing uses the higher of Fitness and Strength"},
    "Sprinting": {"RunSpeed": "Running speed"},
    "Lightfoot": {"Footsteps": "Footstep noise", "SneakSound": "Steps zombies can hear while sneaking",
                  "Animals": "Chance animals notice you"},
    "Nimble": {"StrafeSpeed": "Strafe speed while aiming", "Footsteps": "Footstep noise", "FallDamage": "Fall damage",
               "FallInjury": "Injury roll after a fall", "KneeFall": "Tearing clothes when falling on your knees",
               "LungeFall": "Chance to fall when a crawler lunges", "Climbing": "Climbing check",
               "MovePenalty": "Firearm penalty for moving", "Animals": "Chance animals notice you"},
    "Sneak": {"Spotted": "Chance zombies spot you while sneaking", "Footsteps": "Footstep noise while sneaking",
              "Animals": "Chance animals notice you"},
    "Melee": {"WithWeapon": "With a weapon of this skill:", "Damage": "Damage", "AttackSpeed": "Attack speed", "Crit": "Critical hit chance",
              "FendOff": "Chance to fend off a zombie in front", "Thump": "Chance a zombie attack does no harm",
              "Wear": "Added to the weapon wear roll", "HeavyDamage": "Extra damage", "Reach": "Longer reach",
              "SwingEndurance": "Less endurance per swing", "AxeKnockback": "Double knockback",
              "JawStuck": "Knife stuck in a zombie's jaw", "KnifeKillSafe": "Safe from the zombie during a knife kill"},
    "Maintenance": {"Wear": "Added to the weapon wear roll"},
    "Aiming": {"HitChance": "Hit chance", "Crit": "Critical hit chance", "Range": "Range in tiles",
               "AimIn": "Aim-in speed", "SightBand": "Wider sight range band", "Recoil": "Recoil delay",
               "Wind": "Wind penalty", "MovePenalty": "Penalty for moving", "Unjam": "Jam clearing",
               "PvpCrit": "Critical hits on players", "WildAnimals": "Time for a shot wild animal to drop"},
    "Reloading": {"ReloadSpeed": "Reload speed", "RackSpeed": "Rack speed", "RackAim": "Aim lost when racking"},
    "Craft": {"CraftTime": "Crafting: 5 percent faster per level above a recipe's requirement",
              "AutoLearn": "Some recipes are learned automatically at set levels",
              "Dismantle": "Dismantling: chance to get each material back",
              "BreakFurniture": "Chance to break furniture when picking it up",
              "BreakWindow": "Chance to break a window when picking it up"},
    "Woodwork": {"BuildTime": "Build time", "BuildHealth": "Built structure health",
                 "Barricade": "Barricading time", "Unbarricade": "Unbarricading time",
                 "PlankStrength": "Plank barricade strength", "Noise": "Hammering noise",
                 "Designs": "Better build menu designs (more at higher levels)"},
    "Carving": {"Spear": "Carved spear condition"},
    "Cooking": {"Nutrition": "Nutrition from added ingredients", "IngredientUse": "Ingredient used up",
                "AddTime": "Time to add an ingredient", "Poison": "Spots poisons of detection level",
                "LidKept": "Canning keeps the jar lid's condition", "Tooltip": "Food tooltips show cooking details",
                "Rotten": "Can cook with rotten ingredients"},
    "Electricity": {"Hotwire": "Can hotwire cars", "HotwireChance": "Hotwire success chance",
                    "HotwireTime": "Hotwiring time", "GeneratorRepair": "Generator repair condition",
                    "GeneratorTime": "Generator repair time", "RadioParts": "Radio and TV parts when dismantling",
                    "RadioQuality": "Better radios when crafting them", "Generator": "Can connect generators",
                    "Lamps": "Can modify lamps"},
    "FlintKnapping": {"ExtraStone": "Extra sharpened stone when knapping"},
    "Masonry": {"Designs": "Brick designs in the build menu by level"},
    "Blacksmith": {"ToolWear": "Smithing tool wear follows the craft's skill"},
    "Mechanics": {"Hotwire": "Can hotwire cars", "InstallTime": "Part install and uninstall time",
                  "OpenHood": "Time to open the mechanics window", "EngineRepair": "Engine repair condition per part",
                  "Installer": "Installed parts work better (brakes, tires)",
                  "CarLevel": "Engine work needs the car's mechanics level"},
    "Tailoring": {"PatchTime": "Patching time", "PatchDefense": "Patch defense (share of the fabric's best)",
                  "FabricBack": "Chance to get fabric back from a patch", "Ripping": "Extra materials from ripping clothes",
                  "Aramid": "Extra aramid thread uses", "PatchCondition": "Patches no longer cost condition",
                  "HideJacket": "Better look on crafted hide jackets", "FullRestore": "Same fabric fully restores a hole"},
    "MetalWelding": {"BurntCarTime": "Burnt car salvage time", "BurntCarRounds": "Burnt car salvage rounds",
                     "MetalBarricade": "Metal barricading time", "Noise": "Quieter welding"},
    "Doctor": {"TreatTime": "Bandaging, disinfecting, poultice and stitch time",
               "BulletTime": "Bullet and burn treatment time", "CheckTime": "Medical check time",
               "BandageLife": "Bandage life (average)", "SplintFactor": "Splint strength",
               "StitchTime": "Stitch healing (average)",
               "PanelInfo": "The health panel shows more about wounds with level"},
    "Fishing": {"Tension": "Line tension limit", "BaitKept": "Natural bait kept",
                "LureLost": "Lure lost once in this many catches", "SizeSmall": "Small fish",
                "SizeMedium": "Medium fish", "SizeBig": "Big fish", "SizeLimit": "Largest fish size",
                "Junk": "Junk catches", "Scatter": "Cast scatter",
                "InfoTime": "Fishing window shows the time of day effect",
                "InfoTemperature": "Fishing window shows the temperature effect",
                "InfoWeather": "Fishing window shows weather and fish records",
                "Trophy": "Trophy fish possible", "InfoWind": "Fishing window shows the wind effect"},
    "PlantScavenging": {"Radius": "Search radius (share of the extra range)", "Vision": "Vision bonus",
                        "Identify": "Identifies finds within this share of view distance",
                        "Spotting": "Spotting time in seconds", "Cone": "Spotting cone ahead, in degrees",
                        "Poison": "Chance a find is poisonous", "Fresh": "Chance of fresher finds",
                        "Size": "Larger finds (average)", "Adjacent": "Spots items on squares next to visible ones"},
    "Tracking": {"Find": "Track finding odds", "Radius": "Track search radius",
                 "InspectTime": "Track inspection time", "Animals": "Chance animals notice you",
                 "MinSkill": "Only finds tracks your level allows", "Details": "Track details"},
    "Trapping": {"Catch": "Trap catch chance"},
    "Farming": {"Harvest": "Chance of a bigger harvest", "Cure": "Disease removed per use",
                "PlantHealth": "Starting plant health", "BestMonth": "Best month bonus yield chance",
                "Curse": "Risk month curse chance", "Fertilize": "Fertilizer early effect chance",
                "BackStrain": "Back strain from farm work", "Info": "Plant info shows water and health",
                "InfoMore": "Plant info shows more details", "Seasons": "Knows every growing season"},
    "Husbandry": {"Acceptance": "Acceptance gained", "Petting": "Extra calming from petting",
                  "PetCooldown": "Seconds between pets (average)", "HandFeed": "Extra calming from hand feeding",
                  "Fights": "Chance a stressed animal fights back", "ShearTime": "Shearing time per litre",
                  "CalmMilking": "Milking and shearing no longer stress the animal",
                  "InfoPregnancy": "Animal info shows acceptance and pregnancy", "InfoEggs": "Animal info shows eggs",
                  "InfoMore": "Animal info shows more details", "NoFightBack": "Stressed animals no longer fight back"},
    "Butchering": {"PartCount": "Parts per animal", "PartChance": "Chance of better cuts", "Time": "Butchering time",
                   "HookTime": "Hooking, unhooking and beheading time", "MeatTime": "Meat and leather time",
                   "Blood": "Most blood spilled"},
}
NOTES = {"Gun": "with the gun in hand",
         "PlusBase": "plus the material's own chance", "TimesBase": "x the structure's own bonus",
         "TimesRod": "x the rod", "Mechanics2": "needs Mechanics 2", "Electrical1": "needs Electrical 1",
         "CarLevel": "above the car's level", "Placed": "on traps you place", "PlusLevel": "of your level in extra crops"}

t = json.load(open(PATH, encoding="utf-8"))
for perk, d in E.items():
    for k, v in d.items():
        assert "%" not in v, v
        t[f"IGUI_TienSkillMastery_Effect_{perk}_{k}"] = v
for k, v in NOTES.items():
    t[f"IGUI_TienSkillMastery_EffectNote_{k}"] = v
with open(PATH, "w", encoding="utf-8", newline="\n") as f:
    json.dump(t, f, indent=4, ensure_ascii=False)
print(len(t), "keys")
