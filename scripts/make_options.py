"""Writes media/sandbox-options.txt and Translate/EN/Sandbox.json for Tien's Skill Mastery.

NOT IN USE since 2026-11-06 (no sandbox options for now). Run it only when bringing the options back, and make
shared/TienSkillMastery.lua M.option read SandboxVars.TienSkillMastery again.

Run from anywhere: py scripts/make_options.py
A literal percent sign in a translation is written %% (the Translator formats every string at load).
"""
import json
import os

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "Contents", "mods", "TienSkillMastery", "42", "media")
PAGE = "TienSkillMastery"

# Perk id -> display name. Lightfooted and Sneaking give no bonuses (prestige only), so they get no option.
SKILLS = [
    ("Fitness", "Fitness"), ("Strength", "Strength"), ("Sprinting", "Sprinting"), ("Nimble", "Nimble"),
    ("Axe", "Axe"), ("Blunt", "Long Blunt"), ("SmallBlunt", "Short Blunt"), ("LongBlade", "Long Blade"),
    ("SmallBlade", "Short Blade"), ("Spear", "Spear"), ("Maintenance", "Maintenance"),
    ("Aiming", "Aiming"), ("Reloading", "Reloading"),
    ("Woodwork", "Carpentry"), ("Carving", "Carving"), ("Cooking", "Cooking"), ("Electricity", "Electrical"),
    ("Glassmaking", "Glassmaking"), ("FlintKnapping", "Knapping"), ("Masonry", "Masonry"),
    ("Blacksmith", "Metalworking"), ("Mechanics", "Mechanics"), ("Pottery", "Pottery"), ("Tailoring", "Tailoring"),
    ("MetalWelding", "Welding"),
    ("Doctor", "First Aid"), ("Fishing", "Fishing"), ("PlantScavenging", "Foraging"), ("Tracking", "Tracking"),
    ("Trapping", "Trapping"),
    ("Farming", "Farming"), ("Husbandry", "Animal Care"), ("Butchering", "Butchering"),
]

options = [
    ("MasteryCostBase", 1, 1000, 100, "Mastery cost base (%% of level 10)",
     "The step the mastery costs grow from, as a percentage of what the skill's own level 9 to 10 cost "
     "(9000 XP for most skills, 150000 for Fitness and Strength). Default 100."),
    ("MasteryCostGrowth", 0, 100, 5, "Mastery cost growth (%%)",
     "How much each mastery level adds to the cost, as a percentage of the base, the same amount every level. "
     "Default 5: for most skills mastery 1 costs 9450, mastery 10 costs 13500, and mastery 1 to 10 together 114750 XP. "
     "Prestige levels past mastery 10 keep growing the same way."),
    ("BonusStrength", 0, 500, 100, "Bonus strength (%%)",
     "Scales every mastery bonus. 100 gives the designed values (about a fifth better than skill level 10 at "
     "mastery 10), 0 turns every bonus off while mastery still counts up."),
]

lines = ["VERSION = 1,", ""]
texts = {"Sandbox_" + PAGE: "Tien's Skill Mastery"}

def add_int(name, lo, hi, default, label, tooltip):
    lines.extend([
        f"option {PAGE}.{name}",
        "{",
        "    type = integer,",
        f"    min = {lo},",
        f"    max = {hi},",
        f"    default = {default},",
        f"    page = {PAGE},",
        f"    translation = {PAGE}_{name},",
        "}",
        "",
    ])
    texts[f"Sandbox_{PAGE}_{name}"] = label
    texts[f"Sandbox_{PAGE}_{name}_tooltip"] = tooltip

for o in options:
    add_int(*o)

def add_bool(name, default, label, tooltip):
    lines.extend([
        f"option {PAGE}.{name}",
        "{",
        "    type = boolean,",
        f"    default = {'true' if default else 'false'},",
        f"    page = {PAGE},",
        f"    translation = {PAGE}_{name},",
        "}",
        "",
    ])
    texts[f"Sandbox_{PAGE}_{name}"] = label
    texts[f"Sandbox_{PAGE}_{name}_tooltip"] = tooltip

add_bool("NimbleStrafe", True, "Nimble strafe speed (multiplayer)",
         "On: in multiplayer each player's own client sets their strafe speed while aiming every frame, which gives "
         "Nimble mastery its strafe speed bonus and fixes vanilla's strafe speed lagging up to 2 seconds behind the "
         "server (or starting at the default on the first aim after joining). Off: strafe speed is left to vanilla, "
         "as in single player, where the bonus cannot work: no Nimble mastery bonus, and the lag stays.")

for perk_id, display in SKILLS:
    add_int(perk_id, 0, 500, 100, f"{display} bonuses (%%)",
            f"Scales {display} mastery bonuses (on top of Bonus strength). 100 gives the designed values, "
            "0 turns them off while mastery still counts up.")

with open(os.path.join(ROOT, "sandbox-options.txt"), "w", encoding="utf-8", newline="\n") as f:
    f.write("\n".join(lines))

out = os.path.join(ROOT, "lua", "shared", "Translate", "EN")
os.makedirs(out, exist_ok=True)
with open(os.path.join(out, "Sandbox.json"), "w", encoding="utf-8", newline="\n") as f:
    json.dump(texts, f, indent=4, ensure_ascii=False)
    f.write("\n")
print("wrote", len(options) + len(SKILLS) + 1, "options")
