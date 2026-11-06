# Tien's Skill Mastery — working notes

Skills keep going past level 10 as **mastery**: levels 1-10 with small per-skill bonuses (each level a tenth of
the bonus), then endless prestige with no more bonuses. Mastery is earned only by experience (real XP gains), never
by reading. Skill Journal (lait, workshop 3776641628) should one day record and restore it (low priority).
Standalone mod, started 2026-11-05; **built 2026-11-05, not yet played in game or on a server**.
A v2 (picked masteries over groups of skills, with effects of their own) is drafted in `docs/v2-draft.md`: rules and
the 23 masteries approved 2026-11-06, effects still to be reviewed, nothing built.

Engine facts are from the 42.21 jar (Vineflower, recipe in ZomboidFixesB42's CLAUDE.md) and vanilla 42.21 Lua.

## Why mastery and not real levels 11+

- Each perk has only `xp1..xp10`; `getXpForLevel(11)` = -1. `XP.AddXP` caps XP at `getTotalXpForLevel(10)` and returns
  early (no `AddXP` Lua event) once a skill is there. `IsoGameCharacter.LevelPerk` clamps the level to 10.
- `setPerkLevelDebug(perk, 11)` does stick (int, saved, synced), but 14 Java tables end `level == 10 ? best : default`,
  so 11+ falls back to roughly level 0 (Strength weight mod 2.5 -> 0.8, Aiming hit chances 5 -> 1, ...).

## Core mechanism (built; the long version is the header of shared/TienSkillMastery.lua)

- XP only lands on the server in MP; the Lua `AddXP(chr, perk, amount)` event fires at the end of `XP.AddXP` (not on
  clients) for every award, after boosts, sandbox multipliers and the clamp; `PlayerXpPacket` sends XP to the owner
  every second.
- **Parking**: a level-10 skill keeps its real XP at total(10) - 240 (`M.PARK_MARGIN`). A gain lands there without a
  level-up (that needs total(11) = total(10)), the event amount becomes mastery XP, and the skill is moved back.
  Lua can only write XP through `AddXP` (6 arguments, no boosts; Strength's protein factor divided out) and
  `setXPToLevel` (boundaries only); a move that would cross a boundary runs with the level set to 0 for that one call
  (`setPerkLevelDebug`, no event or packet on a server).
- **Why 240**: `AntiCheatXPUpdate` (AntiCheatXP, default 2 = kick) flags a perk whose server XP rose more than
  1000 x multiplier x boost factor (>= 250) between 60 s snapshots. Parking only lowers XP; the one rise (mastery
  used up by decay, back to vanilla's total(10) - rest) nets at most 240.
- Java stores XP as a float: at Strength / Fitness totals (~325000) it lands only within 1/32, so park checks use
  `M.EPS` = 0.1.
- `XP:getXP` is wrapped on both sides (class metatable `__index`, owner looked up in `M.xpOwner` by XP object) to
  report total(10) for a parked skill. Needed on the server too: vanilla's `xpUpdate.checkForLosingLevel` demotes
  Strength / Fitness whose `getXP` is below total(level).
- Negative XP (Strength / Fitness idleness) comes out of mastery first; with none left the skill drops below 10 the
  vanilla way (total(10), then `AddXP(-rest)` so Java's lose-level loop fires `LoseLevel`).
- Our own positive moves would count as training in vanilla's `xpUpdate.addXp` (it lowers `strengthUpTimer` /
  `fitnessUpTimer` by 3000 per positive award), so those timers are put back after each move.
- A skill book multiplier active at level 10 is divided out of the gain. Skill Journal's `SkillJournal.restore` is
  wrapped to bank nothing while it runs. Admin `/addxp` cannot be told apart. A single award of 240 or more is
  clamped by Java and shows vanilla's "+1 skill" halo once.
- **Storage**: global mod data `TienSkillMastery[username] = { xp = { [perkId] = n }, hours }`, never player modData:
  a client's `transmitModData()` of its player (`ObjectModDataPacket`) replaces the server's whole player modData.
  Cleared on death (`OnCharacterDeath`); reset when the same name shows up with fewer hours survived. The server
  sends the owner `state` on request (client repeats until answered) and at most once a second after a change.
- **Cost** (user, 2026-11-06: compounding 5% from the level-10 step, never the bare step; no XP boosters reach
  mastery, so it stays tough): mastery level n costs xp10 x MasteryCostBase% x (1 + MasteryCostGrowth%)^n, defaults 100 / 5. xp10 = `getXpForLevel(10)`, already x1.5 from
  `PerkFactory.AddPerk` (every vanilla table is multiplied on build): 9000 for most skills (total to 10: 32775),
  150000 for Fitness / Strength. Each level rounded to whole hundreds: mastery 1 = 9500, mastery 10 = 14700, 1-10 together = 119000
  (~3.6x the 0-10 climb).
  Prestige levels continue the curve.
- **No sandbox options** (user, 2026-11-06: "I want to control the values for now"). `M.option(name, default)` reads
  `M.SETTINGS` (empty) and returns the caller's default, so every value lives in the code: `MasteryCostBase` 100,
  `MasteryCostGrowth` 5, `BonusStrength` 100, one % per skill (perk id) 100, `NimbleStrafe` true.
  sandbox-options.txt and Translate/EN/Sandbox.json were deleted; `scripts/make_options.py` regenerates both if the
  options come back (then make `M.option` read `SandboxVars.TienSkillMastery` again). History: the cost options were
  renamed from CostBase / CostGrowth once because a test world kept the old 50 / 25 defaults (a renamed option takes
  its default in existing saves).
- **Level-up feedback** (user, 2026-11-06): a mastery level gained (experience or the mastery cheat) shows vanilla's
  "+1 <skill> Mastery" / "Prestige" halo with the up arrow and plays vanilla's level-up sound on the owner's client
  (server `M.notifyLevelUp` -> "levelUp" command -> client `M.showLevelUp`; SP direct). The Skills-tab cheat gets
  vanilla's own feedback from Java (`LevelPerk`).
- **UI**: a Mastery tab after Skills in the character window (`client/TienSkillMastery_Panel.lua`), styled like the
  vanilla Skills tab (user, 2026-11-06): collapsible categories, SkillBarSeparator, SkillUnit boxes in vanilla gold, the
  level in progress filled by progress, XP in a tooltip over the boxes; prestige in a deeper gold with +n.
- Tests: a lupa harness ports `XP.AddXP` (float storage included) and runs 30 parking scenarios
  (session scratchpad `tsm_test`; not kept in the repo).

## Per-skill decisions

**Values below are superseded by the "Balanced values" table** (2026-11-05: per-bonus values at mastery 10, each
mastery level gives a tenth). The per-skill notes stay for the hooks and vanilla formulas; what was built, and where
it differs, is in "Built hooks" below.

- **Fitness**: attack speed +0.1%/level, cap +2% (client: `OnWeaponSwing` fires in `SwipeStatePlayer.enter` after
  `pressedAttack` set `setCombatSpeed(calculateCombatSpeed())`; multiply `setCombatSpeed`; the hit packet carries the
  `CombatSpeed` variable). Endurance loss -0.2%/level, cap -3% (server: give back a share of each endurance drop;
  endurance is server-owned and synced every second).
- **Strength**: melee damage +0.1%/level cap +2%, knockback +0.1%/level cap +2% (client, `OnWeaponSwingHitPoint`
  fires before the damage roll: raise that weapon instance's min/max damage and push-back mod for the swing, put back
  next tick; min/max damage are saved in item bytes, so never leave them raised). Carry weight: +1 at mastery 15 and
  +1 at 30 (server `setMaxWeightDelta`; `BodyDamage` recomputes `maxWeight` as int each update; delta is re-derived
  from traits at load, so re-apply at login). Stagger duration is recomputed by the client running the zombie.

- **Sprinting**: endurance lost while `isRunning()` / `isSprinting()` -0.2%/level, cap -3% (server, same give-back
  as Fitness, stacks with it). Sprint speed rejected (would need animset overrides). Why speed is out of Lua's reach:
  `getSprintMod` (x0.9..x1.6) and Athletic's x1.2 only feed a local `delta` in `IsoPlayer.updateInternal2` whose sole
  use is `isWalking = delta > 0`; movement is root motion. Sprinting adds 0.05/level to run speed (`calculateWalkSpeed`,
  server/SP only, capped 1.0, sent to clients via `NetworkPlayerAI.runSpeed`), which the sprint node blends on
  (`m_Scalar2 WalkSpeed`: 0.5 = `Bob_Run`, 1.0 = `Bob_Sprint`); the node's `m_SpeedScale` is a fixed 0.96.

- **Lightfooted**: undecided. Every vanilla effect is out of reach: footstep loudness / zombie radius
  (`DoFootstepSound`: volume x `getLightfootMod` 0.99..0.2; sneaking world sound 1 in min(12, 4 + level)); the
  `OnWorldSound` event passes numbers only, `WorldSoundManager.soundList` is a field and `WorldSound` has no setters;
  animals noticing you (`BaseAnimalBehavior` ~1585). Offered: nearby animals' stress gain given back on the server.
  User's idea (2026-11-05): maybe Lightfooted mastery amplifies other skills' mastery bonuses. Revisit at the end.

- **Nimble**: strafe speed +0.1%/level, cap +2%. Vanilla: `calculateWalkSpeed` (server/SP only) sets the anim variable
  `StrafeSpeed` = max(min(0.9 + level/10, 1.5) x min(walk-or-run speed x 2.5, 1), 0.48) x 0.8 only while `isAiming()`;
  strafe nodes use it as `m_SpeedScale`. An MP client gets it only from `PlayerInjuriesPacket` (`NetworkPlayerAI.
  syncDamage`, every 2 s, after `updateMovementRates`), so it lags up to 2 s and can read the default 1.0 on the first
  aim after login. Plan: owner's client recomputes the vanilla formula from its `WalkSpeed` variable every frame while
  aiming, times the bonus, `setVariable("StrafeSpeed", v)` (fixes the lag too; user wants the fix in this mod).
  Remote copies get it via `PlayerStrafeState` params. Other Nimble effects (fall damage, fence trips, wall/rope
  climbing, firearm move penalty (Aiming + Nimble) / 40, footsteps x (2 - `getNimbleMod`), animals) are Java only;
  `getNimbleMod` in movement is dead code like `getSprintMod`.

- **Sneaking**: parked with Lightfooted. Vanilla: zombie spot chance x `getSneakSpotMod` (0.95..0.4, x1.2) while
  sneaking (`IsoZombie` ~2168, ~2618, rolled on the zombie's owner; that is why `SyncPerks` sends Sneak, Strength and
  Fitness), sneaking footstep volume x the same, animals noticing. Dropping a zombie's target does not work: no setter
  for `spottedLast` / `timeSinceSeenFlesh`, and a recent spot makes the next roll certain (chance = 1000).

- **Melee weapon skills** (Axe, Long Blunt, Short Blunt, Long Blade, Short Blade, Spear), only with a weapon of that
  skill's category (`isOfWeaponCategory`): damage, attack speed and crit chance (relative), each +0.1%/level cap +2%.
  Axe, Long Blunt, Spear also: reach +0.1%/level cap +2%, swing endurance -0.2%/level cap -3% (only if a server-side
  swing signal is found). Axe also: knockback +0.1%/level cap +2% (stacks with Strength) and a second crit chance
  bonus +0.1%/level cap +2%. Short Blade: shared three only (jaw stab, KnifeDeath, butchering cuts are Java).
  Vanilla (`getWeaponLevel` = the held weapon's skill): damage x (0.3 + 0.1 x level) (`applyWeaponLevelDamageModifier`,
  CombatConfig), combat speed +0.03/level, crit +3/level (`IsoPlayer.calculateCritChance`), Maintenance + level/2 for
  wear, thump chance 15 + `getMeleeCombatMod`, fend off +3/level; Axe/Blunt/Spear `getDamageMod` 1.1 (3-6) / 1.2 (7+),
  `getRangeMod` 1.2 (7+), `getFatigueMod` 0.8 (8+); Axe `getKnockbackMod` 2.0 (6+). `HandWeapon.getSpeedMod` and
  `getToHitMod` have no callers. Timing (client, `CombatManager.attackCollisionCheck`): `OnWeaponSwingHitPoint` fires
  first, then `calculateHitInfoList` (range), `processHit` (crit roll), the damage roll; so per-swing weapon instance
  boosts (min/max damage, max range, crit chance, push-back) work. Swing endurance is charged on the server
  (`AttackCollisionCheckPacket.processServer` -> `processWeaponEndurance`; `PlayerHitCharacter` ->
  `applyMeleeEnduranceLoss`) with no Lua event in between.

- **Maintenance**: chance to undo each condition / sharpness / head-condition loss on a held weapon, +0.1%/level cap
  2% (server: watch each online player's primary hand weapon per tick, restore and `syncItemFields`). Vanilla wear is
  `InventoryItem.damageCheck` (1 in ConditionLowerChance x mult + Maintenance + weapon level / 2), called from
  `CombatManager.processMaintenanceCheck` only when `!GameClient.client`; trees double the chance. Crafting tool wear
  (`CraftRecipeData` MayDegrade), sharpening and `RecipeCodeOnCreate.genericFixer` repair odds are Java only.

- **Aiming**: hit chance, crit chance, max range and aim-in speed, each +0.1%/level cap +2%. Per shot: raise the gun's
  `setAimingPerkHitChanceModifier` / `setAimingPerkCritModifier` / `setAimingPerkRangeModifier` in
  `OnWeaponSwingHitPoint`, restore next tick (`calculateHitInfoList` -> `calculateHitChanceData` and `processHit` run
  after the event; `setHitChance` is an int, so use the float perk modifiers). Aim-in: owner client,
  `updateAimingDelay` drains `0.625 x multiplier x (1 + 0.05 x level + Marksman 0.1)` per update; drain the extra
  share with `setAimingDelay`. Check that Gunworks does not overwrite those weapon fields mid-shot. Vanilla also:
  sight band x (1 -/+ level/30), recoil delay x (1 - level/40) (int), move penalty, wind, jams / unjam
  8 - 0.5 x level, wild animals drop sooner, recoil anim var, XP x2.7 below 5. `getHitChancesMod` has no callers.

- **Reloading**: reload and rack speed +0.1%/level cap +2%: wrap `ISReloadWeaponAction.setReloadSpeed(character,
  rack)` and multiply the `ReloadSpeed` variable it set (0.8 + 0.1/level, racking 0.04/level, panic, straps x1.15,
  driver x0.8). Runs client (anim speed) and server (`getReloadTime` = base / speed for emulated events). Gunworks
  calls the same function and reads the variable (`ReloadAnim.getReloadSpeed`). Java `getReloadingMod` has no callers.

- **All crafting skills** (shared rules): crafting time on recipes where the skill is the relevant one -0.1%/level
  cap -2% (wrap `ISHandcraftAction:getDuration` = `craftRecipe:getTime(chr) * 5`, client and server; vanilla
  `CraftRecipe.getTime(chr)` = time - (best relevant level - highest requirement) x time/20), and dismantle return
  chance on materials of the skill +0.1%/level cap +2% (wrap `ISMoveableSpriteProps:getChanceByDef(scrapDef, chr)`
  = 10 + 10 x level + baseChance, by `scrapDef.perk`).
- **Carpentry** on top: built structure HP +0.1%/level cap +2% (wrap `buildUtil.getWoodHealth`, server; used by
  `ISBuildIsoEntity` = script `getSkillBaseHealth()` + 50 x Woodwork + Handy 100, for every build entity), furniture
  pick-up break chance -0.1%/level cap -2% (`ISMoveableSpriteProps` ~328: (10 - level) x 7.5, windows
  5 + (10 - level) x 5), unbarricade time -0.1%/level cap -2% (`ISUnbarricadeAction` 200 - 5 x level). Not reachable:
  build time (Java `BuildAction.getDuration` (200 - 5 x Woodwork) x 20 ms for every build), barricade plank strength
  (`IsoBarricade.addPlank` x `getBarricadeStrengthMod`, no setter); `getBarricadeTimeMod` has no callers.

- **Carving**: shared crafting bonuses, plus a chance (+0.1%/level cap 2%) that a carved / fire-hardened spear gets
  +1 condition (within max): wrap `ISHandcraftAction:performRecipe` (server/SP), after it read
  `craftRecipeData:getAllCreatedItems()`; vanilla `RecipeCodeOnCreate.setRandomSpearCondition` = default + Carving +
  Rand(0..1), clamp 2..max. Sync the item to the owner. Nothing else reads Carving.
- **Glassmaking, Pottery**: shared crafting bonuses only; nothing reads them outside the general crafting rules
  (checked 42.21 Java + Lua).
- **Metalworking** (Blacksmith): shared crafting bonuses, plus tool wear undo on its own recipes (+0.1%/level cap 2%):
  in the `ISHandcraftAction:performRecipe` wrapper, record the kept tools' condition / sharpness / head condition
  before, put a lost point back on a roll after, sync. Vanilla: tool wear is `CraftRecipeData` MayDegrade(Heavy)
  `damageCheck(highest relevant skill + Maintenance mod)` during the craft; `isSmithing` only decides whether
  `BreakOnSmithing` inputs break. Material refund was offered and not taken. Tool wear undo is not shared.

- **Cooking**: shared crafting bonuses, plus (each +0.1%/level cap 2%) added-ingredient nutrition and add-ingredient
  time (`ISAddItemInRecipe:getDuration` = 100 - 2.5 x level). Ingredient saving was dropped by the user. Nutrition:
  wrap `ISAddItemInRecipe:complete` (server/SP), record the dish's calories/proteins/carbs/lipids/thirst before,
  scale what `EvolvedRecipe.addItem` added (vanilla x (1 + level/15); the ingredient loses usedHunger x
  (1 - 0.03 x level)), then re-send the dish with `sendReplaceItemInContainer` (food nutrition is saved per instance
  but not in `SyncItemFieldsPacket`). Not reachable: rotten-ingredient gate (7+), poison detection
  (Cooking >= 10 - poison level), tooltip cooking time (5+).

- **Electrical**: shared crafting bonuses, plus (each +0.1%/level cap 2%) hotwire success (after a failed
  `BaseVehicle.tryHotwire` roll, extra chance to `setHotwired(true)` on the server; vanilla chance = clamp(100 -
  engine quality, 5, 50) + 4 x level, alarm 11 - level, broken 10 - level), hotwire time (`ISHotwireVehicle`
  200 - 3 x level), generator repair chance of +1 condition (`ISFixGenerator` +4 + level/2, time 150 - 3 x level),
  and one extra `Base.ElectronicsScrap` when dismantling electronics: radio/TV/walkie recipes (Java OnCreate
  `getRadioBaseItems` = 0-2 of scrap/wire/aluminum; hook the `performRecipe` wrapper) and electrical furniture
  (`ISMoveableSpriteProps:scrapObjectInternal`, "Electric" material). Radio build quality (`radioCraft`) not taken.

- **First Aid**: treatment time -0.1%/level and treatment strength +0.1%/level, cap 2% each (pain not taken).
  All vanilla Lua; each shared medical action sets `o.doctorLevel` in `new` (server copy too). Times: bandage /
  disinfect / cataplasms 120 - 4L, splint 140 - 4L, stitch base - 4L, clean burn / remove bullet 250 - 6L, remove
  glass 150 (300) - 4L, `ISMedicalCheckAction` 150 - 2.5L. Strength: bandage life rand((L+1)x0.5, (L+1)x1) + power,
  cataplasm power rand(same) + 10, splint factor (L+1)/2, stitch time (1+L)/2 x rand(2,5); scale them in `complete`.
  Not reachable: `setHaveBullet(false, L)` (Java), health panel thresholds.

- **Knapping**: shared crafting bonuses only (the extra sharpened stone was dropped by the user). Vanilla's only own
  effect: Java OnCreate `RecipeCodeOnCreate.knappFlake` gives a `SharpedStone` when Rand.Next(11) < level.

- **Masonry**: shared crafting bonuses only (Brick dismantling uses Masonry; the extra ore / boulder piece was
  dropped by the user). Vanilla: build menu tier gates; `ISPickAxeGroundCoverItem` only gives Masonry XP.

- **Mechanics**: (each +0.1%/level cap 2%) install / uninstall time (`ISVehiclePartMenu` passes time - L x time/15 to
  `ISInstallVehiclePart:new`; `ISUninstallVehiclePart:getDuration` workTime - L x workTime/15), engine and lightbar
  repair chance of +1 condition per engine part (`ISRepairEngine` / `ISRepairLightbar` 1 + (L - engine repair
  level)/2, max 5), salvaging an engine chance of +1 engine part (`ISTakeEngineParts`: cond / rand(x/3, x),
  x = max(20 - (L - engine level), 5)). Not taken / not reachable: install success (100% at or above the part's
  level), installer skill (`VehiclePart.mechanicSkillInstaller`, int, brakes + force/50 x L, tire friction + 0.1 x L).

- **Tailoring**: shared crafting bonuses, plus (each +0.1%/level cap 2%) patching and patch-removal time
  (`ISRepairClothing` / `ISRemovePatch` 150 - 6L), fabric recovery chance when removing a patch (`ISRemovePatch` base
  + 5L), ripping clothes chance of +1 material within the garment's max (Java OnCreate `ripClothing`: rand + L/2,
  clamp 1..max; hook `performRecipe`), picking aramid thread chance of +1 use (Java OnCreate `pickAramidThread`:
  rand(n, 2n + L/2), clamp 1..10; `setCurrentUses`). Not reachable: patch bite/scratch defense (fabric max x L/10,
  stored in `Clothing.ClothingPatch`, no setters), patch condition gain (full from 6), full restore gate (8+).

- **Welding** (MetalWelding): shared crafting bonuses (blowtorch dismantling of Metal* / Plumbing / Fridge / Sink
  materials), plus (each +0.1%/level cap 2%) burnt-car scrapping time (`ISRemoveBurntVehicle:getDuration`
  800 - 20L), a chance of one extra salvage roll per burnt car (`complete`: max(5, L) rolls of `checkAddItem`, each
  1 in (base - L) with a lesser fallback), metal furniture pick-up break chance (tool def "Metal" = screwdriver,
  (10 - L) x 7.5, mirrors Carpentry). Not reachable: metal barricade strength (`IsoBarricade` x
  `getMetalBarricadeStrengthMod`), welding noise (`getWeldingSoundMod` floors at 0.4 from level 5).

- **Fishing** (all vanilla Lua, `shared/Fishing`): each +0.1%/level cap 2%: line tension limit (`FishingRod`
  (120 + 10L) x rodCoeff, client), bait / lure kept (`FishingRod` ~365, server: natural consumed when rand(20) > L,
  artificial 1 in 30(L+1)), big fish chance (`Fishing.Utils.getFishSizeChancesBySkillLevel`, table 10/40/50 at 10;
  move share from small), junk odds (`Fish.lua` ~77-93: trashFactor x 0.8 / 0.6 / 0.2 at 5 / 7 / 9, roll with L/30,
  L/20), trophy chance (`Fish.lua` ~153: big fish at 8+, 1 in 20). Check where `Fish.lua` runs (client or server)
  before hooking. Not taken: size limit table, cast scatter / (L+1), fish window info gates.

- **Foraging** (PlantScavenging; all vanilla Lua): each +0.1%/level cap 2%: search radius (`ISSearchManager` ~1028
  min + (max - min) x L/10, client), spotting time (`ISBaseIcon` ~498 `spotTimerMax` 300 + (11 - L) x 200, client),
  found item size (`forageSystem` ~2273 + (rand(L) + 1) x 0.05, shared). Not taken (user): poison chance
  (+ (10 - L) x 3), freshness roll. Also vanilla: vision bonus L x levelBonus, identify distance, item skill gates.

- **Tracking**: each +0.1%/level cap 2%: track find chance as extra find attempts (wrap client
  `ISAnimalTracksFinder:update`; on a roll call `getAndFindNearestTracks(chr)` once more: MP client sends
  `sendGetAnimalTracks`, the server rolls Java `AnimalTracks.canFindTrack` = 1 in (def + track chance) /
  ((L + 1) / 0.7), closer is easier; SP returns the list, add them like vanilla. Misses can give vanilla's 2-4 XP
  1 in 10), track inspection time (`ISInspectAnimalTrackAction` 100 - 1.5L). Not reachable: search radius
  20 + 2L (Java), animals noticing you. Display: freshness wording, details at 5+.

- **Trapping**: catch chance +0.1%/level of the trap's total chance, cap 2%. Vanilla: `shared/Traps/TrapSystem.lua`
  ~46 saves `modData.trappingSkill` = Trapping at placement; server `STrapGlobalObject` ~375 rolls
  ZombRand(100) < trap + bait (or zone) + 1.5 x trappingSkill on each check. Raise the stored value at placement.

- **Farming** (all vanilla Lua, server global object system), each +0.1%/level cap 2%: harvest yield (global
  `getVegetablesNumber(min, max, minA, maxA, plant, skill)` in `server/Farming/farming_vegetableconf.lua`: level in 10
  chance of +level; scale the result, remainder by a roll), cure strength (`SPlantGlobalObject:cureX(src, uses,
  skill)` kill 10 + L per use), planting (`SPlantGlobalObject:seed(type, skill)`: health rand(57, 64) + L via
  `initHealth`, best month bonus yield (9 + L)/20, risk month curse (11 - L)/20), fertilizing (`fertilize2(skill)`
  (9 + L)/20 early effect), back strain (`addBackMuscleStrain(1 - 0.05L)` in harvest / plow / seed / shovel /
  remove grass / remove bush actions). Info gates (3+ / 6+) and season recipes (6 / 10) left alone.

- **Animal Care** (Husbandry), each +0.1%/level cap 2%: acceptance gain (Java `IsoAnimal.addAcceptance` x (1 + L/10),
  via `tryLure` etc.; wrap the causing Lua actions on the server, compare `getAcceptanceLevel(chr)` before / after,
  add the share with `setDebugAcceptance`), calming by petting / hand-feeding (`petAnimal` stress -(7..11) - L,
  cooldown 15000-25000 - 200L; `feedFromHand` -(1..4) - L/5; give the share with `setDebugStress`), shearing speed
  (`ISShearAnimal` timePerLiter 100 / 60 electric - 2L). Nothing past 10 in milking / shearing stress rules (<= 5,
  <= 7); display gates (pregnancy info at 3+, `NetworkPlayerAI` ~209).

- **Butchering** (all vanilla Lua), each +0.1%/level cap 2%: part yield (count: `ButcheringUtil.addAnimalPart` maxNb x
  (1 + floor(L/2)/10); chance: `ButcheringUtil.getPartChance` base x size x meatRatio x L/7) and butchering time
  (`ISButcherAnimal` 900 - 20L, hook / unhook / head 250 - 10L, cut on hook 150 - 10L, leather 400 - 15L, meat
  450 - 15L). Vanilla bug seen: `ISGatherBloodFromAnimal` ~35 `if ZombRand(20 + L x 3) then` is always true in Lua.

## Balanced values (at mastery 10; each mastery level gives a tenth)

Rule (user, 2026-11-05): mastery 10 should feel like about a 20% improvement over skill 10 without being broken.
Combat power (damage, crit, attack speed, hit) sits at 5-10%, defense / endurance / speeds of non-combat actions at
10-15%, yields 10-20%, "+1 extra" chances reach a sure +1 or 20-25% at mastery 10.

- Fitness: attack speed +5%, endurance loss -10%. Strength: melee damage +10%, knockback +15%, carry weight +3.
  Sprinting: running endurance -10% (stacks with Fitness). Nimble: strafe speed +15%.
- Melee skills: damage +10%, attack speed +5%, 5% chance to reroll a hit that did not crit (user, 2026-11-05:
  replaced crit +5 points and Axe's extra +3). Axe / Long Blunt / Spear: reach +10%, swing
  endurance -15% (their damage table extra is folded into the damage bonus). Axe: knockback +20%, crit reroll 10% instead of 5%. Maintenance:
  weapon wear undo 20%.
- Aiming: hit chance +5 points, crit +5 points, range +10%, aim-in speed +15%. Reloading: reload and rack speed +15%.
- Crafting shared: crafting time -15%, dismantle return chance +10 points. Carpentry: structure HP +20%, unbarricade
  time -15%, window pick-up break -5 points (vanilla 5% at 10, so 0 at mastery 10; windows only, user). Carving:
  spear condition +2. Cooking: added nutrition +15%, add time -15%. Electrical: hotwire success +10 points, hotwire
  time -15%, generator repair +1 condition at mastery 10 (10% chance per level before), extra Electronics Scrap 25%.
  First Aid: treatment time -15%, treatment strength +15%. Metalworking: tool wear undo 20%. Mechanics: install /
  uninstall time -15%, engine / lightbar repair +1 condition per part, engine salvage +20% parts. Tailoring: patch /
  remove time -15%, fabric recovery +10 points, ripping +1 material, aramid +1 use. Welding: burnt-car time -15%,
  +1 salvage roll, metal window pick-up break -5 points. Glassmaking, Pottery, Knapping, Masonry: shared only.
- Fishing: line tension +15%, natural bait kept +10 points, big fish +10 points, junk -20%, trophy +2 points.
  Foraging: search radius +15%, spotting time -20%, found item size +10%. Tracking: find chance +20%, inspect time
  -15%. Trapping: catch chance +5 points. Farming: harvest yield +15%, cure strength +15%, planting health +3, bonus
  yield +10 points, curse -10 points, fertilizing +10 points, back strain -15%. Animal Care: acceptance gain +15%,
  calming +15%, shearing time -15%. Butchering: part count +10%, part chance +15%, butchering time -15%.
- Integer results (carry weight, condition, extra items) are rounded by a roll per mastery level (e.g. +1 condition
  at mastery 10 = a 10% chance per mastery level below it).
- Approved by the user as listed (2026-11-05).
- Lightfooted and Sneaking: no bonuses (user, 2026-11-05; amplifiers of other skills were offered and declined).
  Their mastery is earned and shown like any other skill's, prestige only.

## Built hooks (2026-11-05, not yet played)

Every file opens with a header naming the vanilla code, the side it runs on and why the hook works; this is the map.
Bonus amounts all come from `M.val / more / less / roll / int / scaleInt(player, "Perk.Name")` (`M.defs`, shared core).

- Skills tab overview (user, 2026-11-05: vanilla effects only, not mastery): `shared/*_SkillEffects.lua`
  registry (`M.addSkillEffects`, value / unlock entries, labels `IGUI_TienSkillMastery_Effect_<perk>_<name>`),
  data in `*_SkillEffectsBody / Craft / Field.lua`; `client/*_SkillsTab.lua` is vanilla's `ISCharacterInfo:render`
  copied with three insertions by `scripts/make_skills_tab.py` (re-run it after a game update).
- Skills tab cheat (user, 2026-11-06): right-click a skill name in the vanilla Skills tab (`M.showSkillCheatMenu`):
  add / remove real XP, set level 0-10, via `adminSkill` -> `M.adminSkill` -> the `addXpNoMultiplier` global (server:
  GameServer.addXp, which refreshes the XP anti-cheat snapshot like /addxp; SP: plain AddXP); a parked skill is put
  back at total(10) first, mastery is never touched, the protein factor is divided out.
- Mastery cheat (user, 2026-11-06): right-click a skill in the Mastery tab (`M.showCheatMenu`): add / remove mastery XP, set level,
  clear (own character). MP: `adminChange` command, `Capability.AddXP` checked on the server; SP: `-debug`, the
  client calls `M.adminChange` directly. Exists because `/addxp` reaches mastery only 240 per award (Java clamps at
  the level-10 total, the skill is parked 240 below it).
- `shared/TienSkillMastery.lua` core; `server/TienSkillMastery_Server.lua` XP capture, parking, death, sending;
  `client/TienSkillMastery_Client.lua` state from the server; `client/TienSkillMastery_Panel.lua` Mastery tab.
- `client/TienSkillMastery_Combat.lua`: attack speed and melee crit in `OnWeaponSwing`; damage, knockback, reach,
  firearm hit / crit / range as per-swing weapon fields in `OnWeaponSwingHitPoint`, put back next tick only if still
  ours; aim-in and Nimble strafe in `OnPlayerUpdate`.
  - Melee crit is rolled in `pressedAttack` before any event, so the reroll happens in `OnWeaponSwing`: a swing
    with a target (`getHitInfoList()` not empty) and no crit rolls vanilla's chance again
    (`calculateCritChance(nil)`: `HitInfo` is not exposed, the melee branch only instanceof-tests the target; zombie
    toughness added back). Shove, `NoCriticals` and knife swings excluded.
  - Firearm range is capped 4.5 tiles inside the server copy's `getMaxRange()` (`AntiCheatHitWeapon`: +5 slack).
  - **Nimble does nothing in single player**: `calculateWalkSpeed` rewrites `StrafeSpeed` later in the same update,
    right before `postupdate` runs the animator, with no Lua event in between. MP: owner client sets it every update
    (also fixes the 2 s `PlayerInjuriesPacket` lag). Sandbox `NimbleStrafe` (boolean, default on; user 2026-11-05)
    turns both off to match single player; the def carries `option = "NimbleStrafe"`, which `M.enabled` checks.
- `shared/TienSkillMastery_Reload.lua`: `ISReloadWeaponAction.setReloadSpeed` times the bonus (both sides).
- `server/TienSkillMastery_Physical.lua`: endurance give-back per tick (Fitness always, Sprinting while running,
  heavy-weapon skill while not running with that weapon in hand), carry weight through `maxWeightDelta` (whole kg),
  Maintenance wear undo on the primary weapon per tick (+ `syncItemFields`).
- Crafting (`*_Crafting.lua`, `*_CraftingActions.lua`, `*_CraftingMoveables.lua`, `server/*_CraftingBuild.lua`):
  - CraftTime: `ISHandcraftAction:getDuration`, best bonus among the recipe's relevant skills
    (`getHighestRelevantSkillLevel`'s list). The crafting window still shows vanilla's time.
  - Dismantle: `getChanceByDef` is already 100 from level 9, so the points go on the per-roll chance in
    `addScrapItemToList` (80 / 70% at level 10) while `getScrapItemsList` runs.
  - StructureHP: 42.21 builds go through `ISBuildIsoEntity:setInfo` (~655-668), which never calls
    `buildUtil.getWoodHealth`; the first `IsoThumpable:setMaxHealth` inside `setInfo` for a Woodwork recipe is scaled.
  - Hotwire: after a failed `tryHotwire`, a roll calls `vehicle:cheatHotwire(true, brokenBefore)`.
  - Spear / rip / aramid recipes are found by name (`CraftRecipe.LuaCall` is not exposed); their OnCreate changes
    were never synced by vanilla, and are synced when a bonus applies.
  - ToolWear: notes condition / head / sharpness of every candidate kept tool before the craft, restores per point
    after (`isSmithing` recipes).
  - MetalWelding.WindowBreak may never apply (no window found picked up with the "Metal" tool).
- Workshop (`*_Workshop*.lua`): "computed" actions wrap `getDuration`; "stored" ones (`ISSplint`,
  `ISInstallVehiclePart`, `ISMedicalCheckAction`) wrap `getDuration` on the server and `create` on the client.
  - Nutrition: scaled inside `ISAddItemInRecipe.checkTemperature` (called after `EvolvedRecipe.addItem`, before
    vanilla's `sendItemStats`), calories / proteins / carbs / lipids and a thirst gain; dish hunger left alone (vanilla
    does not boost it, and Food weight follows hunger).
  - TreatStrength also covers bullet removal (the deep wound time `setHaveBullet` set is corrected afterwards).
  - Engine repair: one `M.int` per part used; salvage: `M.scaleInt` on the parts added; burnt cars: one extra round
    of `checkAddItem` replayed with the car's saved square.
- Survival (`*_Survival*.lua`): fishing tension in `FishingRod.new` (`rodCoeff`, client); bait, junk, big fish and
  trophy on the server (`FishingAction` runs its own rod and bobber there; trophy swaps the global `ZombRand` for the
  first call of `createFish`); forage radius / spotting on the client, item size by swapping
  `forageSystem` definitions' `spawnFuncs` entries at `OnLoadedMapZones` (they hold function references); tracks: an
  extra `getAndFindNearestTracks` per attempt on a roll; trapping raises the trap's stored `trappingSkill` by
  points / 1.5 at placement.
- Farm (`server/*_Farming.lua`, `server/*_FarmAnimals.lua`, `shared/*_FarmTimes.lua`): plant methods get only a skill
  number, so the player is set around the callers' `complete`s; yield through the global `getVegetablesNumber`;
  curse / bonus yield / fertilize as top-up rolls after vanilla's; back strain scales `addBackMuscleStrain` inside
  the five farming `complete`s.
  - Acceptance covers petting and hand feeding only: luring and holding add it in Java (`IsoAnimal.addAcceptance`,
    which multiplies the whole new value by 1 + L/10).
  - `ISShearAnimal:new` wrapped with vanilla's parameter names (`timePerLiter` drives everything).

Engine findings from the build (42.21), worth keeping:
- `FarmingAmountNew` (sandbox yield) does nothing: `farming_vegetableconf.lua` ~72 writes it to a stray global.
- Kahlua `error(msg, level)`: the second argument is a stack-trace string, not a level. `unpack(t, i, j)` works.
- `ISAnimalTracksFinder.getAnimalTracks` (~16) checks `tracks[isoTrack]` against an array: never matches.
- `ItemStatsPacket` carries full Food nutrition, reliable ordered. Java `LuaTimedActionNew` reads `maxTime` as an
  Integer; a client takes the server's duration only when `maxTime == -1`.
- `RecipeCodeOnCreate.ripClothing` / `pickAramidThread` / spear condition change items after they were sent and
  never sync.

Design settled and built 2026-11-05; nothing has been played yet.
