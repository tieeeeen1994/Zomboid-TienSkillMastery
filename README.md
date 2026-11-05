# Tien's Skill Mastery

Skills keep growing past level 10. A skill at level 10 earns **mastery** from experience: mastery levels 1 to 10,
each giving a tenth of small bonuses made for that skill. Mastery 10 is about a fifth better than skill level 10,
without breaking anything. Past mastery 10, experience keeps counting as **prestige**.

- **Experience only.** Mastery grows from the experience you earn by using the skill. Reading never counts: a skill
  book's multiplier is taken back out, and Skill Journal restores are not counted.
- **Growing cost.** Each mastery level costs 5% more than the step before it, starting from what the skill's level
  10 cost (9000 XP for most skills, 150000 for Strength and Fitness). For most skills mastery 1 costs 9500,
  mastery 10 costs 14700, and all ten together 119000 XP. Costs are rounded to whole hundreds.
- **Level-ups like vanilla's.** Every mastery level shows the "+1 Axe Mastery" halo with the green arrow (+1 Prestige
  past 10) and plays vanilla's level-up sound.
- **Strength and Fitness** lose mastery before they lose a level when you stop training.
- **Mastery belongs to the character.** It is gone when the character dies.
- **Mastery tab** next to Skills in the character window, laid out like the Skills tab: ten boxes per skill (the next
  one fills as you progress, hover for the XP), categories you can collapse, and prestige shown as +n. Click a skill
  to see its bonuses now and at mastery 10.
- **What your skills do.** Click a skill's name in the vanilla Skills tab to see what its current level gives in
  vanilla: every effect with its number, and the features later levels unlock. Click again to close.
- **Admin cheats.** Right-click a skill in the Mastery tab to add or remove mastery XP, set the mastery level or clear
  it. Right-click a skill's name in the Skills tab to add or remove its real XP or set its level. Both work on your own
  character: in multiplayer for roles allowed to add XP (as for /addxp, checked on the server), in single player with
  -debug only. XP from /addxp still counts toward mastery, but only 240 of each award gets through.
- **Multiplayer.** Mastery is kept on the server and works on dedicated servers. Your skill panel, Skill Journal and
  other mods still see level 10 skills as full.

## Bonuses at mastery 10

Each mastery level gives a tenth. Plain numbers without % are percentage points on a chance.

- **Fitness:** attack speed +5%, endurance used -10%.
- **Strength:** melee damage +10%, knockback +15%, carry weight +3.
- **Sprinting:** endurance used while running or sprinting -10%.
- **Nimble:** strafe speed while aiming +15% (multiplayer only: single player rewrites it every frame). In
  multiplayer it also fixes strafe speed lagging up to 2 s behind the server, for everyone.
- **Axe, Long Blunt, Short Blunt, Long Blade, Short Blade, Spear** (with a weapon of that skill): damage +10%,
  attack speed +5%, 5% chance to reroll a hit that did not crit (the reroll uses vanilla's own crit chance;
  knife stabs keep vanilla's rule: they only crit on close kills).
- **Axe, Long Blunt, Spear** also: reach +10%, endurance used swinging -15%. **Axe** also: knockback +20%, and a 10% crit reroll chance instead of 5%.
- **Maintenance:** 20% chance to undo each point of wear on the weapon in your hand.
- **Aiming:** hit chance +5, critical hit chance +5, range +10% (kept inside what the server's anti-cheat allows),
  aim-in speed +15%.
- **Reloading:** reload and rack speed +15%.
- **Every crafting skill** (Carpentry, Carving, Cooking, Electrical, Glassmaking, Knapping, Masonry, Metalworking,
  Mechanics, Pottery, Tailoring, Welding): crafting time -15% on its recipes, dismantling return chance +10.
- **Carpentry:** built structure health +20%, unbarricading time -15%, window break chance when picking up -5.
- **Carving:** carved spear condition +2.
- **Cooking:** nutrition from added ingredients +15%, time to add ingredients -15%.
- **Electrical:** hotwire success chance +10, hotwiring time -15%, generator repair +1 condition, 25% chance of an
  extra electronics scrap when dismantling electronics.
- **First Aid:** treatment time -15%, treatment strength +15% (bandages, poultices, splints, stitches, bullet
  removal).
- **Metalworking:** 20% chance to undo each point of tool wear on its recipes.
- **Mechanics:** part install and uninstall time -15%, engine repair +1 condition per part, engine parts salvaged
  +20%.
- **Tailoring:** patching time -15%, fabric recovery chance +10, +1 material from ripping clothes, +1 aramid thread
  use.
- **Welding:** burnt car salvage time -15%, one more salvage roll per burnt car, break chance when picking up metal
  furniture -5.
- **Fishing:** line tension limit +15%, natural bait kept +10, big fish +10, junk catches -20%, trophy fish +2.
- **Foraging:** search radius +15%, spotting time -20%, found item size +10%.
- **Tracking:** track finding +20%, track inspection time -15%.
- **Trapping:** catch chance +5 on traps you place.
- **Farming:** harvest +15%, cure strength +15%, planting health +3, best month bonus yield chance +10, risk month
  curse chance -10, fertilizing effect chance +10, back strain -15%.
- **Animal Care:** acceptance gained by petting and hand feeding +15%, calming +15%, shearing time -15%.
- **Butchering:** parts +10%, part chance +15%, butchering time -15%.
- **Lightfooted, Sneaking:** no bonuses; their mastery is prestige only.

Whole-number bonuses (carry weight, condition, extra items) build up as a chance: +1 condition at mastery 10 is a
10% chance per mastery level until then.

## Notes

- Mastery is kept in the save's global mod data (by username), not in the player's own data, so a client cannot
  overwrite it.
- A level 10 skill keeps its real XP 240 below the cap so new experience can be caught; the skill panel and other
  Lua code still read the full amount. 240 stays under what the server's XP anti-cheat tolerates.
