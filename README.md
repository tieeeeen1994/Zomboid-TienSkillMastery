# Tien's Skill Mastery

Skills stay vanilla, levels 0 to 10. On top of them come **masteries**: named groups of skills, such as **Firearms**
(Aiming and Reloading) or **Construction** (Carpentry and Masonry), each with effects of its own. Once every skill in a
mastery is at level 10 you can pick it. A character holds at most **three** masteries, so choose what your survivor
is known for.

- **Picks are permanent.** Once three are taken, every other mastery is closed for that character. An admin can
  remove a pick (its progress goes with it).
- **Experience only.** A picked mastery grows from the experience you earn in its skills after you pick it: mastery
  levels 1 to 10, each giving a tenth of its effects, then endless **prestige**. Reading never counts: a skill book's
  multiplier is taken back out, and Skill Journal restores are not counted.
- **Growing cost.** One mastery level is about one level-10 step of any of its skills (9000 XP for most skills,
  150000 for Strength and Fitness). Mastery 1 costs 5% more than that step, and each level after it adds another 5%
  of the step: 105%, 110%, 115% and so on.
- **Shared skills.** A skill can be in several masteries (Strength is in three). Experience in it counts for every
  picked mastery that lists it.
- **Paused, not lost.** If a skill in a picked mastery drops below 10 (Strength or Fitness decay), the mastery pauses
  until the skill is back, keeping its progress and its slot. Strength and Fitness lose mastery points before they
  lose a level.
- **Level-ups like vanilla's.** Every mastery level shows the "+1 Firearms Mastery" halo with the green arrow (+1
  Prestige past 10) and plays vanilla's level-up sound.
- **Mastery belongs to the character.** It is gone when the character dies.
- **Mastery tab** next to Skills in the character window, laid out like the Skills tab: the masteries by group, each
  with its skills (green once at 10), a Pick button when it is ready (a grey Coming Soon on those not open yet), ten boxes once picked (hover for the points).
  Click a mastery to see its effects now and at mastery 10. Long lines here and in the Skills tab's effect lists wrap;
  set the length in Options > Mods.
- **What your skills do.** Click a skill's name in the vanilla Skills tab to see what its current level gives in
  vanilla: every effect with its number, and the features later levels unlock. Click again to close.
- **Admin cheats.** Right-click a picked mastery in the Mastery tab to change its points or level, or remove the
  pick; right-click a skill's name in the Skills tab to change its XP or level, or max every skill. Own character only: in multiplayer
  for roles allowed to add XP, in single player with -debug.
- **Multiplayer.** Masteries are kept on the server and work on dedicated servers. Your skill panel, Skill Journal
  and other mods still see level 10 skills as full.

## Masteries and their effects at mastery 10

Each mastery level gives a tenth. Plain numbers without % are percentage points on a chance. A weapon mastery's
effects apply with a weapon of its kind.

- **Firearms** (Aiming, Reloading): damage +10%, fire rate +10% (Gunworks guns too), jams -25%, hit chance +5,
  range +10%, aim-in speed +15%, reload and rack speed +15%, 20% chance to undo firearm wear.
- **Axemanship** (Axe, Strength): damage +10%, attack speed +5%, 10% chance to reroll a hit that did not crit, reach
  +10%, knockback +20%, endurance used swinging -15%, 20% chance to undo axe wear, damage to trees +20%.
- **Bludgeoning** (Long Blunt, Strength): damage +10%, attack speed +5%, 5% crit reroll, knockback +15%, endurance
  used swinging -15%, 20% chance to undo wear; with the sandbox option to hit several zombies on: +1 target per swing
  from mastery 5, +2 at 10; with it off: reach +5% from mastery 5, +10% at 10.
- **Swordsmanship** (Long Blade, Nimble): damage +10%, attack speed +5%, 5% crit reroll, reach +10%, endurance used
  swinging -15%, 20% chance to undo wear, strafe speed while aiming +15%.
- **Spearcraft** (Spear, Carving): damage +10%, attack speed +5%, 5% crit reroll, reach +10%, endurance used swinging
  -15%, 30% chance to undo spear wear. Spears you carve or fire-harden have +8% damage and +3% reach, for whoever uses them,
  set by your mastery level when you make them: near a forged spear's numbers at mastery 10, but they stay wooden and wear out as fast as ever.
- **Street Fighting** (Short Blunt, Fitness): damage +10%, attack speed +5%, 10% crit reroll, endurance used
  swinging -15%, 20% chance to undo wear; with anything in hand: stomp damage +20%, shoves deal 0.25 damage.
- **Knifework** (Short Blade, Sneaking): damage +10%, attack speed +30%, endurance used swinging -15%, 20% chance
  to undo wear, endurance used running while sneaking -15%, +25% damage to zombies not targeting you, and 10% a
  level that a close one-on-one knife stab is a jaw stab (vanilla only jaw-stabs on a critical hit).
- **Conditioning** (Strength, Fitness): endurance used -10%, endurance recovery +10%, carry weight +5, Strength and
  Fitness decay -25%, muscle strain from everything (fighting, climbing, carrying, farming, exercise) -25%.
- **Freerunning** (Sprinting, Lightfooted): sprinting speed +15%, running speed +10%, crouched walking and running speed +5%, endurance used running -15%, 25% of attacks by zombies and players miss you (no damage, no wound, no flinch; animals still hit), drop one floor without harm from mastery 3, two from 6 and three from 9, and from those levels any higher fall lands as if it were one floor lower.
- **Stealth (coming soon)** (Sneaking, Lightfooted): noise of your work -50% (building, barricading, digging, clearing glass, bushes and grass, moving furniture, fishing), noise of your melee swings -50%.
- **Smithing** (Metalworking, Welding, Maintenance): crafting time -25% and dismantling return +10 on metalworking
  and welding, 20% chance to undo tool wear on forging, metalworking and welding recipes, 20% chance to get back each burnt charcoal and
  each blowtorch use, iron from ore and blooms +15%.
- **Construction** (Carpentry, Masonry): crafting time -25% and dismantling return +10 on carpentry and masonry,
  built structure health +20%, unbarricading time -15%, window break chance when picking up -5, building noise
  -50%, 15% chance to get each build material back.
- **Engineering** (Mechanics, Electrical): crafting time -25% and dismantling return +10 on electrical, part install
  and uninstall time -15%, engine repair +1 condition per part, hotwire success +10, hotwiring time -15%, 25% chance
  of an extra electronics scrap when dismantling electronics, top speed and engine power +15% while you drive.
- **Salvaging (coming soon)** (Welding, Mechanics): burnt car salvage time -15%, +1 burnt car salvage roll, engine parts salvaged +20%, 20% chance to get each blowtorch use back when scrapping cars.
- **Handicraft** (Carving, Knapping, Glassmaking, Pottery): crafting time -25% on their recipes, 20% chance to undo
  tool wear on them; 15% chance of one more item from simple knapping, carving and clay press recipes.
- **Mending** (Tailoring, Maintenance): tailoring crafting time -25%, patching time -15%, fabric recovery chance
  +10, +1 material from ripping clothes, +1 aramid thread use, patches protect 50% more, repairs restore 15% more
  and a failed one costs no condition.
- **Field Medicine** (First Aid, Tailoring): treatment time -15%, treatment strength +15% (bandages, poultices,
  splints, stitches, bullet removal), disinfecting uses 50% less, stitching hurts 75% less, crash injuries -15% for
  everyone in your car.
- **Provisioning** (Cooking, Butchering): cooking crafting time -25%, nutrition from added ingredients +15%, time to
  add ingredients -15%, butchering time -15%, food you cook or butcher stays fresh 25% longer.
- **Hunting** (Tracking, Trapping, Butchering): track finding +20%, track inspection time -15%, trap catch chance +5
  on traps you place, meat, sinew and bones from butchering +10%, chance of better cuts +15%.
- **Angling** (Fishing, Foraging): line tension limit +15%, natural bait kept +10, big fish +10, junk catches -20%,
  trophy fish +2, worms and insects found more often when foraging, fishing nets catch 25% more.
- **Fieldcraft** (Foraging, Tracking): search radius +15%, spotting time -20%, found item size +10%, search mode's
  darkness, weather and moving penalties fade (gone at mastery 10).
- **Homesteading** (Farming, Animal Care): harvest +15%, cure strength +15%, planting health +3, best month bonus
  yield chance +10, risk month curse chance -10, fertilizing effect chance +10, back strain -15%, acceptance gained
  by petting and hand feeding +15%, calming +15%, shearing time -15%, milking time -15%, animals near you gain 15% less stress.

Whole-number bonuses (carry weight, condition, extra items) build up as a chance: +1 condition at mastery 10 is a
10% chance per mastery level until then.

## Signature abilities

Each mastery also unlocks a signature ability (a few have two or three), each with its own name, in full from the
moment it is picked (it does not grow with mastery levels).

- **Firearms:** *Quickdraw*: one-handed guns drawn and holstered 4 times faster. *Running Reload*: reloading does
  not stop when you run.
- **Bludgeoning:** *Wild Swing*: every swing with a long blunt weapon also staggers back the zombies in front of you
  that it did not hit, for a little endurance each.
- **Swordsmanship:** *Hamstring*: sneaking and aiming with a long blade, every hit leaves the zombie crawling.
- **Street Fighting:** *Battering Ram*: sprinting into a zombie knocks it down instead of tripping you, for a little
  endurance each. The first endurance moodle is a warning; from the second you stumble again.
- **Axemanship:** *Tomahawk*: in combat stance, the throw key (Space, rebindable) throws a one-handed axe at the
  zombie, animal or (with PvP) player under the cursor, for half again its damage, aimed at the head (head hits out to
  about 4 tiles). Spares go first: one loose in your main inventory, then one on your hotbar, then the one in hand.
  Skill, strength and condition count as for a swing. What the throw can reach is outlined (colour in Options > Mods).
- **Spearcraft:** *Javelin*: the same throw with a spear, just as far and as hard: spares first (main inventory, then hotbar,
  then the one in your hand), and it flies point first.
- **Knifework:** *Lunge*: with at most one zombie after you, a stab at a zombie up to 1.5 tiles away (vanilla: 0.6) is a jaw stab, and you lunge in to close the gap.
- **Conditioning:** *Pack Mule*: the Heavy Load moodle counts one level lower, for everything it does (speed, endurance, health, combat, climbing); just over your max weight there is no moodle at all.
- **Stealth (coming soon):** *Distraction Throw*: in combat stance, the distraction key (K, rebindable; it can share a key with the axe throw) lobs the junk
  in your hand up to 15 tiles on a grenade-like arc: bottles, jars and glasses, cans, scrap metal, stones and bricks (a master sees "Throwable" in their
  tooltips). Where it lands it makes a noise that draws zombies that are not already after someone (glass the loudest, then metal, then stone), and
  glass breaks into broken glass. Walls, closed doors and windows stop it; it sails over low fences.
- **Freerunning:** *Unfazed Runner*: you never trip. Sprinting into trees or hedges you run through them
  (the branches still scratch and tear) and sprint again once clear; running or sprinting, you pass straight through
  zombies, animals and players without breaking stride.
- **Smithing:** *Masterwork*: what you forge, and weapons and armor you weld, ignore 15% of their wear, whoever uses them. A forged blade or head keeps the mark when a smithing master assembles it into a weapon (a non-master's weapon is plain); on axes, hammers, picks, scythes and spears it covers the head and its edge, not the wooden handle.
- **Construction:** *Clean Cuts*: one more plank from every carpentry recipe that makes planks
  (4 from a log, 2 from a large branch). *Clean Breaks*: 12 stones per large stone, not 10;
  flat stones break into 3.
- **Handicraft:** *Deft Hands*: every timed action 10% faster, moving items included. *Craftsmanship*: what you carve, knap, blow or fire
  ignores 15% of its wear, whoever uses it; your handles and heads keep it when a Handicraft master assembles them.
- **Engineering:** *Engine Overhaul*: Engine Parts raise a car's engine quality, one point each up to 100 (easier
  starts, less fuel, full power).
- **Salvaging (coming soon):** *Scrapper*: scrap any car, and scrap vehicle parts into metal.
- **Mending:** *Restoration*: right-click a repaired item to bring it back to full condition and clear its repair count,
  for three times the price of a repair (zip ties, tape, glue, epoxy: whatever repairs it and you are carrying).
- **Field Medicine:** *Field Triage*: the wound key (comma, rebindable) tends you and everyone next to you. It queues the fewest treatments that stop health loss: glass and bullets out,
  deep wounds stitched if a suture needle is at hand, fractures splinted, every other wound (burns included) bandaged with the best bandage you carry (theirs too, used only on them). Everyone shares one
  list, you included: anyone under 25% overall health goes first, then the body part costing the most health, whoever's
  it is. Patients can move around within 2 tiles of you; anyone who goes farther, dies or leaves is skipped and you carry on
  with the rest. Infected wounds get bandaged like any other, but nothing here disinfects them. What you lack the tool for
  is bandaged for now, and every later triage looks again: a bullet once you carry tweezers or a suture needle holder, a
  deep wound once you carry a suture needle, a fracture once you have a splint. *Needlework*: sew a bandage
  from 2 ripped sheets with a needle (kept) and thread, and make a suture needle from any sewing needle (used up) and thread.
  Anything that counts as thread will do: thread, sinew, dental floss, fishing line.
- **Provisioning:** *Choice Cuts*: meat you butcher is 10% more filling and 30% more nutritious. *Savory Meals*: food you cook
  in an oven, on a stove or over a fire causes 80% less unhappiness when eaten (a rat you roast costs 6, not 30). Stale,
  rotten and burnt food adds its usual penalty on top of that lower number.
- **Hunting:** *Sturdy Traps*: your traps keep their bait and are never destroyed. *Live Catch*: animals caught alive
  last 4 times longer. *Double Catch*: a quarter of catches come in twos.
- **Homesteading:** *Harvest Moon*: right-click a crop or furrow to tend the field (water, cure and fertilize every plant in a patch you pick and, with a shovel, remove its harvested plots) and sow the field
  (plant every plowed square in it with the seed you choose). One action covers 3 x 3 squares in the time a single plant takes;
  water, sprays, fertilizer and seeds are still used per plant. With a shovel or trowel you can also remove dead, rotten or destroyed
  plots over a patch, and dig furrows: a 3 x 3 square follows the mouse, like the rake, and each click digs it in one action until you cancel. *Animal Whisperer*: while you are in an animal zone, its
  animals (hutched ones and joined zones included) lose 1 stress every 10 in-game minutes.
- **Angling:** *Fish Finder*: aiming a rod at water shows how many fish are there and how much trash.
- **Fieldcraft:** *Steady Eyes*: search mode is not switched off by zombies or running. *Sixth Sense*: what is inside the search circle
  shows as if in plain sight, even behind walls: zombies, animals, survivors, items and corpses.
