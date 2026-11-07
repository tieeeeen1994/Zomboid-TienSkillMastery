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
  150000 for Strength and Fitness), and each level costs 5% more than the one before.
- **Shared skills.** A skill can be in several masteries (Strength is in three). Experience in it counts for every
  picked mastery that lists it.
- **Paused, not lost.** If a skill in a picked mastery drops below 10 (Strength or Fitness decay), the mastery pauses
  until the skill is back, keeping its progress and its slot. Strength and Fitness lose mastery points before they
  lose a level.
- **Level-ups like vanilla's.** Every mastery level shows the "+1 Firearms Mastery" halo with the green arrow (+1
  Prestige past 10) and plays vanilla's level-up sound.
- **Mastery belongs to the character.** It is gone when the character dies.
- **Mastery tab** next to Skills in the character window, laid out like the Skills tab: the masteries by group, each
  with its skills (green once at 10), a Pick button when it is ready, ten boxes once picked (hover for the points).
  Click a mastery to see its effects now and at mastery 10.
- **What your skills do.** Click a skill's name in the vanilla Skills tab to see what its current level gives in
  vanilla: every effect with its number, and the features later levels unlock. Click again to close.
- **Admin cheats.** Right-click a picked mastery in the Mastery tab to change its points or level, or remove the
  pick; right-click a skill's name in the Skills tab to change its XP or level. Own character only: in multiplayer
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
  -15%, 30% chance to undo spear wear, carved spears +2 condition.
- **Street Fighting** (Short Blunt, Fitness): damage +10%, attack speed +5%, 10% crit reroll, endurance used
  swinging -15%, 20% chance to undo wear; with anything in hand: stomp damage +20%, shoves deal 0.25 damage.
- **Knifework** (Short Blade, Sneaking): damage +10%, attack speed +30%, endurance used swinging -15%, 20% chance
  to undo wear, endurance used running while sneaking -15%, +25% damage to zombies not targeting you, and 10% a
  level that a one-on-one jaw stab kills outright.
- **Conditioning** (Strength, Fitness): endurance used -10%, endurance recovery +10%, carry weight +5, Strength and
  Fitness decay -25%, muscle strain from fighting -25%.
- **Smithing** (Metalworking, Welding, Maintenance): crafting time -25% and dismantling return +10 on metalworking
  and welding, 20% chance to undo tool wear on smithing recipes, 20% chance to get back each burnt charcoal and
  each blowtorch use, iron from ore and blooms +15%.
- **Construction** (Carpentry, Masonry): crafting time -25% and dismantling return +10 on carpentry and masonry,
  built structure health +20%, unbarricading time -15%, window break chance when picking up -5, building noise
  -50%, 15% chance to get each build material back.
- **Engineering** (Mechanics, Electrical): crafting time -25% and dismantling return +10 on electrical, part install
  and uninstall time -15%, engine repair +1 condition per part, hotwire success +10, hotwiring time -15%, 25% chance
  of an extra electronics scrap when dismantling electronics, top speed and engine power +15% while you drive.
- **Salvaging** (Welding, Mechanics): burnt car salvage time -15%, one more salvage roll per burnt car, 20% chance
  to get back each blowtorch use, engine parts salvaged +20%.
- **Handicraft** (Carving, Knapping, Glassmaking, Pottery): crafting time -25% on their recipes, 20% chance to undo
  tool wear on them; weapons and clothing you make ignore 1.5% of their wear per mastery level you had when you
  made them, whoever uses them; 15% chance of one more item from simple knapping, carving and clay press recipes.
- **Mending** (Tailoring, Maintenance): tailoring crafting time -25%, patching time -15%, fabric recovery chance
  +10, +1 material from ripping clothes, +1 aramid thread use, patches protect 50% more, repairs restore 15% more
  and a failed one costs no condition, 20% chance a repair does not add to the repair count.
- **Field Medicine** (First Aid, Tailoring): treatment time -15%, treatment strength +15% (bandages, poultices,
  splints, stitches, bullet removal), disinfecting uses 50% less, crash injuries -15% for everyone in your car.
- **Provisioning** (Cooking, Butchering): cooking crafting time -25%, nutrition from added ingredients +15%, time to
  add ingredients -15%, butchering time -15%, food you cook or butcher stays fresh 25% longer.
- **Hunting** (Tracking, Trapping, Butchering): track finding +20%, track inspection time -15%, trap catch chance +5
  on traps you place, butchering parts +10%, part chance +15%.
- **Angling** (Fishing, Foraging): line tension limit +15%, natural bait kept +10, big fish +10, junk catches -20%,
  trophy fish +2, worms and insects found more often when foraging, fishing nets catch 25% more.
- **Fieldcraft** (Foraging, Tracking): search radius +15%, spotting time -20%, found item size +10%, search mode's
  darkness, weather and moving penalties fade (gone at mastery 10).
- **Homesteading** (Farming, Animal Care): harvest +15%, cure strength +15%, planting health +3, best month bonus
  yield chance +10, risk month curse chance -10, fertilizing effect chance +10, back strain -15%, acceptance gained
  by petting and hand feeding +15%, calming +15%, shearing time -15%, animals near you gain 15% less stress.

Whole-number bonuses (carry weight, condition, extra items) build up as a chance: +1 condition at mastery 10 is a
10% chance per mastery level until then.

## Signature abilities

Each mastery also unlocks a signature ability, in full from the moment it is picked (it does not grow with mastery
levels).

- **Firearms:** quickdraw (one-handed guns drawn and holstered 4 times faster) and run-and-gun reloading (reloading
  does not stop when you run).
- **Bludgeoning:** push back: every swing with a long blunt weapon also staggers back the zombies in front of you
  that it did not hit, for a little endurance each.
- **Swordsmanship:** hamstring: sneaking and aiming with a long blade, every hit leaves the zombie crawling.
- **Street Fighting:** bowl them over: sprinting into a zombie knocks it down instead of tripping you, for a little
  endurance each (no endurance moodle).
- **Axemanship:** in combat stance, the throw key (Space, rebindable) throws a one-handed axe at the target under
  the cursor (a zombie, an animal, or a player where PvP allows it), aimed at the head, for half again its damage:
  spares first (one loose in your main inventory, then one on your hotbar, never from bags), and only then the one
  in your hand. Your skill, strength and condition count as for a swing (tired, out of breath, panicked, stressed or
  with sore arms, it hits softer). It is thrown in an arc that
  reaches the target: head hits (triple damage, as vanilla's) out to about 4 tiles, body hits beyond that. A target
  the throw can reach (in range, no wall in between) is outlined in amber. It lands where it stops.
- **Spearcraft:** the same throw with a spear, just as far and as hard: spares first (main inventory, then hotbar,
  then the one in your hand), and it flies point first.
- **Knifework:** the lunge: jaw stabs reach half again as far, and you close the gap as you stab.
- **Conditioning:** Heavy Load penalties count one level lower (combat speed, endurance used, recovery).
- **Smithing:** masterwork: weapons and clothing you forge ignore 15% of their wear, whoever uses them.
- **Construction:** half the time a 4th plank from each sawn log, 12 stones instead of 10 from a large stone.
- **Handicraft:** deft hands: every timed action 10% faster.
- **Engineering:** engine overhaul: Engine Parts raise a car's engine quality, one point each up to 100 (easier
  starts, less fuel, full power).
- **Salvaging:** scrap any car, not only burnt wrecks (nobody inside, everything taken out, not towing, not in
  someone else's safehouse), and cut vehicle parts such as doors, hoods and seats into metal.
- **Mending:** restore: clear an item's repair count for the price of a repair, so it repairs like new again.
- **Field Medicine:** field triage: "Tend wounds" on yourself or someone next to you queues every needed treatment at
  once: glass and bullets out, fractures splinted, wounds bandaged with the best bandage you carry (theirs too).
  Infected wounds are left for proper treatment.
- **Provisioning:** choice cuts: meat you butcher is 15% more filling and nutritious.
- **Hunting:** your traps keep their bait and are never destroyed, animals caught alive last 4 times longer, and a
  quarter of catches come in twos.
- **Homesteading:** tend the field (water, cure and fertilize every plant in a patch you pick) and sow the field
  (plant every plowed square in it with the seed you choose).
- **Angling:** fish finder: aiming a rod at water shows how many fish are there and how much trash.
- **Fieldcraft:** search mode is not switched off by zombies or running, and zombies inside the search circle are
  marked wherever they are.
