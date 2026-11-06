# Skill Mastery v2: picked masteries (draft, 2026-11-06)

Nothing built. v1 (one mastery per skill, bonuses that copy the skill's vanilla effects) is described in CLAUDE.md.
v2 keeps v1's XP capture and changes what the XP is spent on. **Approved** (user, 2026-11-06): the rules under "The
idea" and the 23 masteries with their members and names. **Not yet approved**: the effects, and everything marked
"proposed" below.

## The idea

- **Skills stay vanilla**: levels 0-10, XP, books and effects exactly as the game has them. Mastery is a layer on top.
- A **mastery** is a named group of at least **2 vanilla skills** with effects of its own, e.g. **Firearms** =
  Aiming + Reloading. Its effects are chosen for the mastery as a whole and no longer copy what a single skill does
  in vanilla.
- Masteries are **picked**. One becomes pickable once every member skill is at **10** (always 10, no mixed
  requirements), and it starts earning from the moment it is picked. A character holds at most **3** picks. Picks
  are permanent; once 3 are taken, every other mastery is locked for good. Admins can remove a pick.
- A skill may belong to several masteries (Strength is in three).
- Levels 1-10 give the effects (each level a tenth of the mastery-10 value, as in v1), then endless prestige.
- A picked mastery whose member drops below 10 (Strength / Fitness decay, admin) is inactive (no effects, no
  progress) but keeps its progress and its slot; it works again once the skill is back at 10.
- Names are disciplines, never people: no mastery repeats a vanilla trait, profession or skill name (42.21 has
  Marksman, Brawler, Runner, Hunter, Angler, Artisan as traits; Lumberjack, Chef, Farmer, Rancher, Tailor as
  professions; Mechanic, Blacksmith as both).

## The masteries (every vanilla 42.21 skill, 35 skills, 23 masteries)

| Group | Mastery | Member skills (perk ids) |
|---|---|---|
| Combat | Firearms | Aiming, Reloading |
| | Axemanship | Axe, Strength |
| | Bludgeoning | Long Blunt (Blunt), Strength |
| | Swordsmanship | Long Blade (LongBlade), Nimble |
| | Spearcraft | Spear, Carving |
| | Street Fighting | Short Blunt (SmallBlunt), Fitness |
| | Knifework | Short Blade (SmallBlade), Sneaking |
| Body | Conditioning | Strength, Fitness |
| | Freerunning | Sprinting, Lightfooted |
| | Stealth | Sneaking, Lightfooted |
| Crafting | Smithing | Metalworking (Blacksmith), Welding (MetalWelding), Maintenance |
| | Construction | Carpentry (Woodwork), Masonry |
| | Auto Repair | Mechanics, Electrical (Electricity) |
| | Salvaging | Welding (MetalWelding), Mechanics |
| | Handicraft | Carving, Knapping (FlintKnapping), Glassmaking, Pottery |
| | Mending | Tailoring, Maintenance |
| | Field Medicine | First Aid (Doctor), Tailoring |
| | Provisioning | Cooking, Butchering |
| Field | Hunting | Tracking, Trapping, Butchering |
| | Angling | Fishing, Foraging (PlantScavenging) |
| | Fieldcraft | Foraging (PlantScavenging), Tracking |
| | Homesteading | Farming, Animal Care (Husbandry) |
| | Livestock | Animal Care (Husbandry), Butchering |

Skills in more than one mastery: Strength and Butchering (3 each); Fitness, Sneaking, Lightfooted, Welding,
Mechanics, Maintenance, Tailoring, Foraging, Tracking, Animal Care, Carving (2 each).

## Effects at mastery 10 (proposed)

v1's balance rule stays: about a 20% improvement over level 10, combat power 5-10%, defence / endurance / speeds
10-15%, yields 10-20%. Proposed rule: **each effect belongs to one mastery only**, so skills overlap but effects
never stack. A weapon mastery's effects apply with a weapon of its category. Marked **new** = not built in v1, needs
a hook (and tracing where noted); everything else reuses a built v1 hook with the id renamed.

- **Firearms** (in review): damage +10%, fire rate +10% (new), hit chance +5 pts, range +10%, aim-in speed +15%,
  reload and rack speed +15%, jam chance -25% (new), firearm wear undone 20%. Crit +5 pts dropped, a third damage
  multiplier. **Approved** (user, 2026-11-06), fire rate covering vanilla and Gunworks guns, bursts included.
  - Damage: same per-shot min / max scaling as melee in `OnWeaponSwingHitPoint` (the firearm damage roll comes after
    it, ~783; the hit packet carries the damage, `AntiCheatHitDamage` only refuses > 100).
  - Fire rate (42.21): semi-auto waits for the character's recoil delay (`HandWeapon.getRecoilDelay(owner)`, set in
    `pressedAttack` ~3209, drained 0.625 x multiplier per update, `IsoPlayer` ~2567 fires only at 0) and plays at
    `singleShootSpeed`; full auto plays at `autoShootSpeed` = `getCyclicRateMultiplier()`. Both variables are set in
    `SwipeStatePlayer.enter` right before `OnWeaponSwing`. Hook: drain the extra share in `OnPlayerUpdate` (as aim-in)
    and scale both variables in `OnWeaponSwing`. Gunworks guns are gated by its own RPM interval instead
    (`RateOfFire.canFire`, per-player `RateOfFire.lastFireTime[playerNum]`, "Real" modes pin RecoilDelay to 1), which
    only moving `lastFireTime` or wrapping its RPM lookup reaches.
    Anti-cheat (42.21 `AntiCheatHitWeapon.isRateExceeded`, corrected 2026-11-06: an earlier note said there was
    none): per player, hits within 3 x T must not exceed 3 x maxHits, T = 400 ms melee, 150 ms single-fire
    firearm, 15 ms auto; maxHits = the **server copy's** `getProjectileCount() x getMaxHitCount()`, at least 3
    with sandbox MultiHitZombies on (`AttackRateChecker.check`). So single-fire must average 150 ms or more per
    hit-shot (MultiHitZombies off): vanilla's fastest gun (RecoilDelay 11, Aiming / Strength 10: 6 delay units
    = ~200 ms) stays above it at +10%, but a fast Gunworks gun near 150 ms can be pushed under; floor the
    shortened single-fire interval at 150 ms.
    Gunworks part (chosen, client only): in `OnWeaponSwing` for a `RateOfFire.IsWeaponRegistered` gun, pull
    `lastFireTime[playerNum]` back by interval x bonus / (1 + bonus) (interval = 60000 / `getWeaponRPM`); when a new
    `burstState[playerNum]` appears, shorten its `intervalMs` and `nextShotTime` the same way. Both tables are
    internal (Gunworks' API_DOCS only cover the Register* calls): type-check them, so a Gunworks rename silently
    drops the bonus for its guns. Check in game that `OnWeaponSwing` fires once per Gunworks auto shot.
  - Jams: rolled by `HandWeapon.checkJam(player, racking)` from vanilla Lua only (`ISReloadWeaponAction.onShoot`
    feeding a round, `ISRackFirearm.rackBullet` closing the bolt; Gunworks calls vanilla's onShoot). Hook: wrap
    `checkJam` (class metatable) and clear a fresh jam on a roll of the bonus.
  - Wear: a firearm loses condition in `attackCollisionCheck` (~1221: on a hit, or firing empty) through
    `damageCheck(0, 1, false, true, owner)`, maintenance off, so Maintenance never helped guns; it runs on the
    shooter's client and syncs with `checkSyncItemFields`. Hook: v1's server-side held weapon wear undo, limited to
    firearms here (Smithing's then covers melee weapons only).
- **Axemanship** (**approved**, user 2026-11-06): damage +10%, attack speed +5%, crit reroll 10%, reach +10%, swing
  endurance -15% (also covers tree chopping: `ISChopTreeAction:useEndurance` drains in the same held-axe,
  not-running window the give-back watches), knockback +20%, tree damage per chop +20% (new), axe wear undone 20%
  (added by the user, 2026-11-06; covers chopping wear too).
  - Tree damage (42.21): the server's `ISChopTreeAction:serverStart` emulates `ChopTree` every 1500 ms; its
    `animEvent` calls `IsoTree.WeaponHit`, which takes `weapon:getTreeDamage()` (x1.5 Ax-pert) off the tree's
    health ((log yield - 1) x 80, min 40) and topples it at 0. Hook: wrap that `animEvent` on the server and raise
    the axe's `setTreeDamage` (int, rounded) for the call. Attacking a tree outside the action is Java only
    (`CombatManager.processTreeHit`), so not covered. A shorter emulator period would desync the client's chop anim.
- **Bludgeoning** (**approved**, user 2026-11-06): damage +10%, attack speed +5%, crit reroll 5%, +1 target per
  swing with sandbox MultiHitZombies on, reach +10% instead while it is off (so the effect is never empty), swing
  endurance -15%, knockback +15% (new for this category, same per-swing push-back hook), long blunt wear undone 20%.
  - Extra target (42.21): `CombatManager.calculateHitInfoList` caps a melee hit list at the weapon's
    `getMaxHitCount()` (script `MaxHitcount`, long blunts 2-3), forced to 1 when sandbox MultiHitZombies is off;
    the list that deals damage is built in `attackCollisionCheck` (~701) after `OnWeaponSwingHitPoint`, so a
    per-swing `setMaxHitCount(n + 1)` with the other per-swing fields works. Each further target takes less damage
    (`damage / (split x 0.5)`, split counting from 1). Anti-cheat: melee allows 3 x maxHits hits per 1.2 s, maxHits =
    max(3, the server copy's count) with MultiHitZombies on; a long blunt (2-3 targets + 1) stays inside it as long as
    no more than two swings land in 1.2 s (swing length not measured; check in game).
- **Swordsmanship** (**approved** with the sandbox option, user 2026-11-06): damage +10%, attack speed +5%, crit reroll 5%, reach +10% and swing endurance -15%
  (both new for Long Blade, same hooks), long blade wear undone 20%, and a Nimble effect that works in single player
  too (user, 2026-11-06: v1's strafe speed +15% is multiplayer only). Candidate: **Deflect**, 10% chance that a
  zombie's attack on you is broken off with a stagger while you hold a long blade.
  The user wants a sandbox option to choose between the two (2026-11-06), proposed: enum `SwordsmanshipFootwork`,
  1 = Deflect 10% (default, works everywhere), 2 = strafe speed +15% (multiplayer only; nothing in single player).
  This brings sandbox options back (v1 has none, CLAUDE.md: `M.option` reads `M.SETTINGS`;
  `scripts/make_options.py` regenerates sandbox-options.txt and Sandbox.json). Only effect in the reviewed set
  that is multiplayer only; Firearms, Axemanship and Bludgeoning have none.
  - Why not strafe: `calculateWalkSpeed` rewrites `StrafeSpeed` in SP right before the animator, no Lua event in
    between; Nimble's input there caps at level 6 (min(0.9 + N / 10, 1.5)). Nimble's other uses (42.21
    `IsoGameCharacter`): fall damage ~2331-2409, fence trip ~13451, crawler lunge fall ~13689, climbing fail
    ~16081, footstep volume ~5442, firearm moving penalty (`CombatManager` ~2529): all Java.
  - Deflect, to trace: the zombie's `getAttackOutcome()` turns "success" at the end of its start anim, before the
    `AttackCollisionCheck` event that rolls the wound (ZomboidFixesB42 `*_ClothingWear.lua` watches the same
    moment); the zombie attack actiongroup has `to_staggerback` / `to_staggerback-knockeddown` transitions, so
    setting the stagger there should end the attack before it lands. Runs on the zombie's owner (SP: always the
    player), where the attack resolves; in MP other clients do not see the stagger (ZombiePacket carries no
    stagger or knockdown, see ZomboidFixesB42's notes), they only see the attack not land.
- **Spearcraft** (**approved**, user 2026-11-06): damage +10%, attack speed +5%, crit reroll 5%, reach +10%, swing
  endurance -15%, spear wear undone 30% (condition, head condition and sharpness: v1's hook already restores all
  three; above the other weapons' 20% because spears are the ones that break), every crafted spear +2 condition
  (up to its max).
  - Spear crafting (42.21 `recipes_spears.txt`): CarveSpear (`RecipeCodeOnCreate.carveSpear`, random default +
    Carving), FireHardenSpear (`fireHardenSpear`), BindSpear / DuctTapeSpear / WireSpear (knife, glass, bone, stone
    heads by `SpearMapper`; stick `InheritCondition`, Bind and Wire then `slightlyMoreDurable`), AssembleSpear
    (`SpearHead` / `SpearLongHead` -> `SpearShort` / `SpearLong`: ConditionMax 10, head condition 10, head wears
    x2). `InheritCondition` scales the stick's condition to the spear's max, so a full stick gives a full spear;
    `setConditionMax` exists but the max is not saved (from the script at `InstanceItem`), so +2 only helps a spear
    that comes out below max (carved ones, or any built from a worn stick). The hook finds the recipes by name, as
    v1's carved spear bonus does.
- **Street Fighting** (**approved**, user 2026-11-06): damage +10%, attack speed +5%, crit reroll 10%, swing
  endurance -15% (new for this category, same hook), short blunt wear undone 20%; with anything in hand: stomp
  damage +20% (new) and shoves deal 0.25 damage to each zombie shoved (new, user's idea; a normal zombie has
  1.8-2.1 health).
  - Stomp (42.21 `CombatManager` ~1043): damage = rand(0.7, 1.0) + Strength x 0.2, x the worn shoes'
    `getStompPower()` (x0.5 barefoot), after `OnWeaponSwingHitPoint`. Hook: raise the shoes' stomp power for the
    swing (`Clothing.setStompPower` exists) and put it back next tick, as v1 does with weapon fields.
  - Shove: `IsoGameCharacter.Hit` (~5877) sets `bIgnoreDamage` for a standing shove (no damage, hit reaction x1.5)
    but still fires `OnWeaponHitCharacter(wielder, target, weapon, damage)` right after. Hook: on that event, take
    the damage off the zombie on the client that owns it (as ZomboidFixesB42's `*_SpikedArmor.lua`): directly when
    the shover owns it (`not zombie:isRemoteZombie()`), else through the server to `getOwnerPlayer()` (the same relay
    the axe throw needs). Health and a kill reach everyone through ZombiePacket / the server's `die()`.
- **Knifework** (**approved**, user 2026-11-06): damage +10%, attack speed +30% (changed from +50% without damage),
  swing endurance -15% (new for this category, same hook), short blade wear undone 20%, endurance while
  sneak-running -15% (new; sneaking costs nothing while walking, it only makes running cost x1.5,
  `IsoPlayer.updateEndurance`), jaw-stab window +50% MinRange with a lunge, Executioner (10% a level), Ambush
  (+25% damage to a zombie not targeting you). Far over the 5-10% combat band by the user's choice: knives are
  weak per hit, speed is their identity.
  - Attack speed: the stab `Bob_AttackKnife01_Hit` is 1.0 s at `CombatSpeed` (~1.5 at Short Blade and Fitness
    10: 0.67 s), then the node's `SetMeleeDelay` 8 at End (~0.27 s; `IsoPlayer` attacks only at melee delay 0,
    drained 0.625 x multiplier per update). A bonus on `CombatSpeed` alone falls short (+50% gave ~+30%
    attacks), so the melee delay is drained faster too (`setMeleeDelay`, the same extra-share drain as aim-in and
    fire rate) for the full +30% (0.94 s -> ~0.72 s). Anti-cheat: knives hit one target, so 3 hits per 1.2 s
    with MultiHitZombies off; 0.72 s is inside it. Check the look of the stab at ~1.95x in game. Crit reroll dropped: stabbing knives (weapon type
  KNIFE) only crit on a close kill, so it would be empty for most of them. Candidates under discussion:
  Ambush (+25% damage to a zombie not targeting you, through `OnWeaponHitCharacter` and the shove-damage relay),
  Assassinate (instead: 5% a level to kill such a zombie outright), Silent Ambush (calm zombies that start
  responding to a player sound within 16 tiles for ~1 s after an Ambush kill: `isRespondingToPlayerSound()`,
  `setLastHeardSound(-1, -1, -1)`; the hit noise itself cannot be stopped), a wider jaw-stab window, the knife never
  stuck after a jaw stab.
  - Hit noise (42.21 `CombatManager` ~1098-1113, `IsoGameCharacter.Hit` ~5900): `addWorldSoundUnlessInvisible`
    on the attacker, jaw-stab kill 4 / 4, any other hit 8 / 8 and often 10 or 16, plus 5 / 1 per hit; Java to
    Java, skipped only for an invisible player. `WorldSoundManager.soundList` and `WorldSound` fields are not
    reachable from Lua.
  - Jaw stab (close kill, `calculateAttackVars` ~1400): the target nearer than the weapon's `getMinRange()`
    (stabbing knives 0.61), no window between, `numChasingZombies <= 1`, weapon type KNIFE; with more chasers the
    same distance gives a **shove** instead. `numChasingZombies` is a public field the zombies count up each frame
    (`IsoZombie` ~3037), no setter, so the chaser limit cannot change. `HandWeapon.setMinRange` works per instance
    and the value is not saved (`minRange` is not written by `HandWeapon.save`), so the distance can widen while a
    knife is held, but only while `getStats():getNumChasingZombies() <= 1` (last frame's count), or crowds would
    turn more stabs into shoves. The crit that makes it a kill is still vanilla's roll (certain from behind on an
    unaware zombie). Animation fit at a longer distance: the user's answer (2026-11-06) is a **lunge**: no new
    animation, the player is eased toward the zombie during the stab so it lands at vanilla's distance. Plan
    (owner's client, `OnPlayerUpdate`): when a swing starts with a stabbing knife, 0-1 chasers and the nearest
    zombie in front between vanilla's MinRange and ours (the target is not readable: `HitInfo` is not exposed and
    `AttackVars.targetStanding` is a field, so it is found the same way), move the player by `setX` / `setY` a
    share of the remaining gap each frame until it is ~0.55 tiles, within ~0.2 s, before the hit lands. At most
    ~0.35 tiles; only when the squares between are not blocked (`isBlockedTo`). MP: the client owns its player's
    position; ~1.5 tiles/s is walking pace for the Speed anti-cheat and NoClip only refuses moves up a level.
  - Jaw-stab kill: a knife crit plays `KnifeCritStart` / `KnifeCrit` (conditions `CriticalHit = true` and a
    `prout` variable, not traced), whose anim event sets `ZombieHitReaction=KnifeDeath`, the instant kill. Vanilla
    rolls the crit in `pressedAttack` (certain from behind on an unaware zombie) and cancels a knife crit that is
    not a close kill. v1's melee crit reroll already sets `setCriticalHit(true)` in `OnWeaponSwing` before the
    swing anim is chosen, so a close kill (detected as for the lunge) can be made a crit on a roll: candidate
    **Executioner**, 10% a level, every one-on-one jaw stab kills at mastery 10.
  - Stuck knife (`applyKnifeDeathEffect` ~4021): a jaw-stab kill leaves the knife in the zombie 1 in
    (8 + 2 x (Short Blade + 1)), 1 in (3 + ...) if it was attacking; `setAttachedItem("JawStab", item)`.
- **Conditioning** (**approved**, user 2026-11-06): endurance loss -10%, carry weight +5 (was +3), Strength /
  Fitness decay -25% (new, cheap: the decay is already caught in our `AddXP` handler), endurance recovery +10% in
  every state (new: the server give-back also adds to gains; +25% was too strong because vanilla also recovers
  while walking, at a quarter of the standing rate, `IsoPlayer.updateEndurance` ~3340), Heavy Load penalties
  taken **one moodle level lower** where Lua can reach them (new; user 2026-11-06, replacing "halved"), muscle
  strain -25% (new, user 2026-11-06).
  - One level lower, per reachable penalty: combat speed gets 0.07 back; running drain uses the next lower factor
    (none / 1.5 / 1.9 / 2.3 / 2.8: give back 1 - lower / current); the walking drain from L 3 likewise (L 3 then
    has none); recovery, blocked from L 2, is added back at L 2 only; vault trip -13 and wall climbing +8 points
    through the Freerunning reroll. Movement speed (base -0.15 L and the weight-ratio slowdown) stays vanilla.
  - Muscle strain (42.21): `IsoGameCharacter.addCombatMuscleStrain` (~15930: melee and firearm recoil, ~15948;
    tree chopping from `ISChopTreeAction`) -> `addStiffness` on hands / forearms; `BodyPart:getStiffness /
    setStiffness` are public. Hook: the server gives back 25% of each part's stiffness rise per tick (the endurance
    give-back pattern). To trace: which side adds the strain in MP (combat runs on the attacker's client, chopping
    on the server) and how stiffness reaches the server / owner (PlayerDamage carries `BodyDamage.save`).
  - Heavy Load penalties (42.21, moodle level L): base movement speed -0.15 L (`calculateBaseSpeed` ~9301) and
    path speed (`IsoPlayer.getPathSpeed` ~1074): Java, root motion, out of reach (as sprint speed). Combat speed
    -0.07 L (`calculateCombatSpeed` ~9399): reachable, `CombatSpeed` in `OnWeaponSwing`. Running / sprinting
    endurance x1.5 / 1.9 / 2.3 / 2.8, walking drain from L 3 (`IsoPlayer.updateEndurance` ~3260-3310): reachable,
    server give-back. No endurance recovery at all from L 2 (~3326, ~3340): reachable, the server adds vanilla's
    regen (`imobileEnduranceReduce` x regen sandbox x recovery mod) itself. Vault
    trip +13 L and tall-wall climbing -8 L: reachable with the Freerunning outcome reroll (same MP caveat).
    Melee crit -5 L (`calculateCritChance` ~3862): reachable only as part of a reroll, left out. Not reachable:
    zombie grab defense -2 L (`testDefense` ~13155), crawler lunge fall +5 L (~13687), rope climbing speed
    (~16173), vehicle discomfort.
- **Freerunning** (**approved**, user 2026-11-06): running endurance -15%; no damage from falls of up to 2 levels,
  exhaustion no longer adds to the vault trip chance, nor to tall-wall climbing failure (all three new, user
  2026-11-06; traced below under "Freerunning movement effects"); **sure-footed**: 5% a level (50% at mastery 10)
  that a trip from running into a zombie, animal or player becomes a stagger, sprinting included (new, user
  2026-11-06; **needs trace**: dropped if Lua has no window before `BumpedState.enter`, see below). Sprint speed
  dropped: movement is root motion and Sprinting's speed only feeds the run / sprint blend (v1 notes), out of
  Lua's reach.
- Freerunning movement effects (asked for under Knifework, moved to Freerunning by the user 2026-11-06), traced
  42.21:
  - **No damage from falls of up to 2 levels.** `IsoGameCharacter.updateFalling` (~9171) accumulates the fall
    speed in `lastFallSpeed` (public `getLastFallSpeed` / `setLastFallSpeed`) and on landing calls `DoLand(impact)`
    -> `handleLandingImpact` (`IsoPlayer` override: only when not a client, so server / SP). `FallingConstants`
    (in levels of height): fall 0.35, damage 0.5, hard 1.5 (knees + `dropHandItems`), severe 2.5, lethal 3.5. A
    2-level drop is a hard fall. Health is taken with `ReduceGeneralHealth`, then `OnPlayerGetDamage(player,
    "FALLDOWN", amount)` fires, then fractures / wounds are rolled. Plan: when a fall starts with the floor at most
    2 levels below (`getHeightAboveFloor`), hold `lastFallSpeed` just under the damage threshold every update, so
    the landing counts as a light fall (no damage, no knees, nothing dropped); the drop takes ~25% longer (2 levels:
    ~1.1 s instead of ~0.9 s). Both sides (the server's simulation decides the damage); check in MP that the server
    runs `updateFalling` for players and that `OnPlayerUpdate` (or an `OnTick` sweep) reaches it.
  - **Exhaustion does not make you trip when vaulting.** `ClimbOverFenceState.enter` (owner only) rolls
    `shouldFallAfterVaultOver` for running / sprinting vaults: sprint 10 + 10 per endurance moodle level + drunk,
    heavy load, pain, traits - Fitness, and on a hit sets the anim variable `ClimbFenceOutcome = "fall"` and the
    state param OUTCOME (sent to other clients; `Param` is not reachable from Lua). Plan: right after, on a "fall",
    redo vanilla's formula without the endurance term and keep the fall only with probability
    chance-without / chance-with (so the trip rate becomes exactly vanilla's minus exhaustion), else set the
    variable to "success". The knees consequences (`fallenOnKnees`: holes, dirt, dropped items) only run when not a
    client, i.e. from the anim event on the server / SP: check whether the server animates the trip from OUTCOME
    in MP (if so the server copy must be flipped too, and other players may still see the trip).
  - **Running into zombies / animals / players** (user asked 2026-11-06), 42.21 `IsoMovingObject.separate`
    (~1225, owner's update): a bump needs `WalkSpeed > 0.2` and `runningTime > 0.5` (jogging or sprinting). It
    "counts" (`wasBumped`) when sprinting, or within 1.5 s of the last bump, or while still bumped. Then
    `baseChance = 10 - 3 x bumps in a row + Fitness + Strength - 2 x drunk +- traits - pain`, clamped 1..80, and
    the player trips (`setBumpFall(true)`, `TripObstacleType` zombie) on 1 in baseChance **or always when
    sprinting**. So a sprint into a zombie or animal (IsoAnimal is a player subclass) is a certain trip; a jog
    trips only on a second bump within 1.5 s, ~1 in 24-27 at Fitness / Strength 10, rising with each bump. The roll
    is Java with no event between it and the `wasBumped` report. `OnPlayerUpdate` (`IsoPlayer` ~2296) fires
    before `separate` (~2698) in the same update, so the only Lua window is clearing `BumpFall` before
    `BumpedState.enter` reads it (~43; the state sends BUMP_FALL to other clients) — when the "wasBumped" event
    is turned into the state change is not traced yet. Candidate: on a roll, the trip becomes a stagger.
  - **Tall walls**: the success / struggle roll (`getClimbingFailChanceInt`, endurance moodle -5 per level) runs
    before `ClimbOverWallState.enter` and is stored with public `setClimbOverWallSuccess / Struggle`; the state then
    sets `ClimbFenceOutcome` "success" / "fail". Same flip approach and the same MP caveat.
- **Stealth** (**approved**, user 2026-11-06): **lose them** (sneaking and still, unseen for 3 s: chasing zombies give up),
  **silent kills** (a kill made while sneaking does not draw zombies: those within 16 tiles that start responding
  to a player sound in the next ~1 s are calmed; the Silent Ambush idea from Knifework), **sneak speed +15%**
  (position nudge, needs an in-game feel test). Vanilla Sneaking / Lightfooted effects stay vanilla: out of reach
  (below).
  - Being spotted (42.21 `IsoZombie` ~2040-2290, the zombie owner's update): chance from light, distance, facing,
    movement, `getSneakSpotMod()` (Sneaking 10: 0.48), traits, cover; a hit sets `bonusSpotTime = 720` (x5 for the
    next rolls, no setter). Footsteps (`IsoGameCharacter.DoFootstepSound` ~5411, from anim events): volume x
    `getLightfootMod()` (Lightfooted 10: 0.2) x Nimble x sneak mod, world sound 1 in min(12, 4 + Lightfooted) while
    sneaking. Both are Java to Java (a class-metatable wrapper is never called) and the tables stop at level 10,
    so neither can be pushed further; undoing a spot would be re-rolled at x5 at once.
  - Sneak speed: `sneakWalk*.xml` scale the sneak clips by the anim variable `sneakLimpSpeedScale` (1.0 unless
    limping), but `IsoPlayer.updateMovementRates` (~2404, local player, after `OnPlayerUpdate` ~2296) resets it
    every update, and `IsoWorld.updateWorld` animates (`MovingObjectUpdateScheduler.postupdate`) right after the
    cell update with no Lua event between (only `OnZombieUpdate` of a zombie updated later in the same list,
    unreliable). So the bonus is a nudge: each update, 15% of last update's sneak displacement added with `setX` /
    `setY`, only while the step stays on the same or an unblocked neighbouring square (`isBlockedTo`). Feet slide
    15%; MP: the client owns its position, sneak pace is far under the Speed anti-cheat.
  - Silent kills: the hit noise (see the Knifework notes above) cannot be stopped. A zombie that hears it runs
    `RespondToSound` (owner only: `pathToSound` + `setLastHeardSound`, `timeSinceRespondToSound = 0`;
    `isRespondingToPlayerSound()` is public). Calming = `setLastHeardSound(-1, -1, -1)` and ending its path to the
    sound (how, from Lua, still to trace) on the owner, relayed like the shove damage. Zombies already chasing
    someone are left alone.
  - Candidate (user's idea for Knifework, 2026-11-06; fits here or there): **lose them** — sneaking, standing still
    and not attacking, out of a chasing zombie's sight for 3 s, the zombie gives up the chase.
    Traced (42.21 `IsoZombie`): a zombie drops its target itself once `timeSinceSeenFlesh > memory` (sandbox Memory,
    hundreds to 1250 multiplier units, ~0.8 a frame at 60 fps: many seconds), `~3417` `setTarget(null)`.
    `timeSinceSeenFlesh` / `spottedLast` are public fields with no getter or setter (Lua cannot touch them), but
    `isTargetLocationKnown()` = `bonusSpotTime > 0 or timeSinceSeenFlesh < 1` and `isTargetVisible()` (the
    target player's could-see on the zombie's square) are public, and so is `setTarget`. The spot roll is certain
    only while `spottedLast == player and timeSinceSeenFlesh < 120` (~2.5 s), so after 3 s unseen a dropped target
    is not re-spotted at once. Plan: track each zombie whose `getTarget()` is the player; once
    `isTargetLocationKnown()` has been false for 3 s while the player stays still, sneaking and quiet,
    `setTarget(nil)` on the zombie's owner (zombie AI runs there; the player's client sends the IDs through the
    server when it does not own them, as the shove-damage relay). The zombie then walks on to where it was going and
    may still respond to sounds (`RespondToSound` after 240 units unseen).
- **Smithing** (**approved**, user 2026-11-06): crafting time **-25%** (user 2026-11-06, up from v1's 15%) and dismantle
  return +10 pts on Metalworking / Welding recipes, tool wear undone 20% on smithing recipes (v1), **charcoal
  back** (new, user 2026-11-06: each piece of charcoal a recipe burns comes back on a 20% roll, dropped on the
  smith's square), plus **masterwork** (new, user 2026-11-06, replacing
  "forged edges", which the user did not want), **ore yield +15%** (new: iron from ore and blooms only), **torch
  fuel** (new: 20% of the blowtorch uses a recipe burns are given back). No weapon wear on the smith's own use
  (user, 2026-11-06): each weapon mastery undoes wear on its own category (v1's server-side held weapon wear undo,
  20%, limited to the category; Firearms for guns).
  - Masterwork: every item with a condition that a Smithing master makes in a smithing recipe
    (`craftRecipe:isSmithing()`: weapons, armor, tools, anything in the Blacksmithing category) is marked in its
    modData (saved and sent with the item; set after `performRecipe` and sent with `syncItemFields`, the v1
    crafting hook). A marked item ignores 15% of its wear (user 2026-11-06, down from 25%), **whoever** holds or
    wears it: each condition, head condition or sharpness point lost is given back on a 15% roll (about 18% longer
    life). It belongs to the
    item, so it survives trading and a removed pick. Stacks with a weapon mastery's own undo (an Axemanship master
    with a masterwork axe: 1 - 0.85 x 0.8 = 32%). Where the wear is caught (server / single player): held items by
    v1's per-tick compare of the hands; worn armor by the same compare over worn marked items (zombie hits wear
    clothing on the server); recipe tools in the crafting hook. A tooltip line names it ("Masterwork, forged by
    X": the forger's name stored as plain text, since a dedicated server has no mod translations).
    Real max condition is out: `conditionMax` comes from the script at `InstanceItem` and is not saved
    (`InventoryItem.save` writes only the condition, as a byte), so a raised max would have to be put back on
    every copy of the item, and any vanilla `setCondition` clamps to the script's max first.
  - Ore yield: `RecipeCodeOnCreate.smeltIronOrSteel(data, chr, add)` (42.21 ~1319) sets the crucible to
    uses + add (1 / 2 / 3 / 4 by item size, 12 from ore, `ExtractIronFromIronOre`); `ExtractIronFromIronBloom`
    gives 12 Base.IronChunk. Only these primary sources: smelting scrap is loopable (an IronBarQuarter is tagged
    `smeltableironsmall`, +1 use, and casts back from one), so a bonus there would make iron from nothing. +15% of
    `add` with the fraction rolled, within `getMaxUses()`; chunks: +15% as extra chunks, fraction rolled.
  - Charcoal back: smithing recipes burn `item N tags[base:charcoal]` (2 to 18 a craft; the tag covers
    Base.Charcoal, Base.CharcoalCrafted and Base.Coke). The crafting hook notes the charcoal in the craft's
    containers before `performRecipe` and counts what is gone after it, per type; each piece comes back on its own
    20% roll as the same type, `square:AddWorldInventoryItem(type, rx, ry, 0)` on the smith's current square
    (server / single player; the server's call sends it to nearby clients). Only recipes where `isSmithing()`.
  - Torch fuel: handcraft recipes take blowtorch uses as inputs (`item 2 / 4 / 6 / 8 [Base.BlowTorch]`, 43
    recipes); note the torches' uses before `performRecipe` and give back each burnt use on a 20% roll. Welded
    builds (Java `BuildAction`) and burnt-car scrapping are not covered (to trace).
- **Construction** (**approved**, user 2026-11-06, with spare materials at 15%): built structure HP +20% (Carpentry and Masonry builds: the hook checks
  `involvesSkill(Perks.Woodwork)`, add Masonry), unbarricade time -15%, window pick-up break -5 pts, crafting time
  -25% (matching Smithing; v1 had 15%), dismantle return +10 pts, **quiet work** (new: building noise -50%),
  **more planks** (new, user 2026-11-06: sawing a log gives a 4th plank on a 50% roll, +17%), **more stones** (new,
  user 2026-11-06: breaking a large stone gives 12 stones instead of 10, +20%).
  - Planks and stones (42.21 recipes): `SawLogs` (recipes_carpentry.txt: 1 Base.Log -> 3 Base.Plank, saw kept) and
    `Make_Stones_from_Large_Stone` (recipes_stonemasonry_i.txt: 1 Base.LargeStone -> 10 Base.Stone2, hammer /
    sledge / maul / pickaxe kept). The v1 crafting hook (`performRecipe`, server / single player) adds the extra
    items where vanilla put the outputs (`Actions.addOrDropItem`, which sends them). No loop: nothing turns planks
    back into logs or stones into a large stone.
  - Quiet work (42.21 `client/BuildingObjects/TimedActions/ISBuildAction.lua` ~73-104, every build-menu build and
    barricade): the client's `update` calls the global `addSound` with radius 20 x `getHammerSoundMod()` (8 from
    Carpentry 4) for hammering, 15 for sawing and for a recipe's `craftingBank`. Swap `addSound` during that
    `update` and halve the radius (8 -> 4, 15 -> 8). A client's world sound reaches the server through
    `WorldSoundManager`, so the halved one is what zombies hear. The sound you hear is unchanged.
  - Out of reach (42.21): build time in MP is Java `BuildAction.getDuration` (~81: (200 - 5 x Carpentry, - 50
    Handy) x 20 ms, i.e. 3 s at Carpentry 10, no Lua between). Plank barricade strength is Java `IsoBarricade.addPlank`
    (~81: 1000 x condition x `getBarricadeStrengthMod()`, 1.5 at Carpentry 10), and `IsoBarricade.setHealth` clamps
    every plank to 1000, below vanilla's own 1500, so Lua cannot raise it.
  - **Spare materials** (approved at 15%, user 2026-11-06): each material a build consumes comes back on a 15% roll.
    Where: `ISBuildIsoEntity:create` (~501, server / single player) consumes through
    `self.buildPanelLogic:performCurrentRecipe()`; `getAllConsumedItems()` lists them afterwards (vanilla reads it
    at ~702), so a wrapper rolls per consumed item and drops the same type on the builder's square. The catch is
    dismantling, which pays materials back by two paths, both of which a saving could turn into a build / dismantle
    loop: `ISDismantleAction:complete` (~55) gives 1..n of each entry of the thumpable's `getBuildMaterials()`
    (n = the need count; a count of 1 always comes back whole), and moveable scrapping
    (`ISMoveableSpriteProps`, ~3707 / ~4323 read the same table, and the tile's Material scrap definitions, Wood =
    up to 6 planks at 40% and 4 nails at 50% a roll) gives back by the object's material whatever it cost.
    Guard: `getBuildMaterials()` is a live, saved Lua table (Java `IsoThumpable` ~175; vanilla's `ISLightSource`
    writes into it), so the saved count is taken off it, and the object gets a modData note of what was saved,
    which a wrapper of `getScrapItemsList` (v1 already wraps it) takes out of the scrap list. A standing structure
    keeps the saving; tearing it down gives back no more than vanilla would for what was really paid. To trace:
    whether picking a built object up as a moveable and placing it again keeps its modData and build materials (if
    not, carry the note on the moveable item).
- **Auto Repair** (proposed 2026-11-06, **review paused here**: the user stopped mid-review, pick up from this
  proposal; still to review after it: Salvaging, Mending, Field Medicine, Provisioning, Hunting, Angling,
  Fieldcraft, Homesteading, Livestock): part install / uninstall time -15%, engine and lightbar repair +1
  condition per part, hotwire success +10 pts, hotwire time -15%, generator repair +1 condition, dismantle +10 pts
  on Electrical scrap (all v1), crafting time -25% on Electrical recipes (matching the other crafting masteries; v1
  had 15%), **tuned parts** (new: parts a master installs or repairs lose 15% less condition from driving),
  **fuel saver** (new: 15% less fuel burnt while a master drives).
  - Driving wear (42.21 `server/Vehicles/Vehicles.lua`, server / single player, once a game minute through the
    cached `Vehicles.Update.*`, so wrap at file load): `Update.Brakes` (~709) and `Vehicles.LowerCondition` (~722;
    suspension, muffler, tires) take 1 condition on a roll with `part:setCondition` + `transmitPartCondition`. Tuned
    parts: installing (`ISInstallVehiclePart` complete) and repairing (`ISFixVehiclePartAction`, engine repair)
    by a master writes a mark in the part item's modData (saved with the part; travels with the item when it is
    taken out and put in another car). The wrapper gives the point back on a 15% roll for a marked part. Crashes,
    weapon hits and zombie damage (Java, see ZomboidFixesB42 "Where a vehicle wears down") are not driving wear and
    stay vanilla.
  - Fuel (`Update.GasTank` ~450): the burn per minute is computed in Lua from engine quality, mass, gear and engine
    speed, then `amount = amount - elapsedMinutes x newAmount` and a leak under 70 condition. Wrapper: when
    `vehicle:getDriver()` is a master, give back 15% of the drop the call made (the wrapper only sees the total, so the
    0.01 leak of a worn tank is included).
- **Salvaging**: burnt-car scrapping time -15%, +1 salvage roll per burnt car, engine salvage +20% parts, extra
  Electronics Scrap 25%, metal window pick-up break -5 pts (v1 found no window this applies to).
- **Handicraft** (**approved**, user 2026-11-06): crafting time -25% on Carving / Knapping / Glassmaking / Pottery recipes
  (66 / 11 / 8 / 21 recipes award their XP), tool wear undone 20% on them (new here, Smithing's hook),
  **craftsman's mark** (new: what a master makes there with a condition ignores 15% of its wear, whoever uses it;
  Smithing's masterwork for wood, stone and clay), **extra output** (new: 15% chance of one more of the recipe's
  output, on a vetted list of recipes that nothing turns back into their inputs), **deft hands** (new: every timed
  action in the game -10%, below). v1's dismantle bonus dropped:
  only Carpentry, Electrical, Masonry and Welding have scrap definitions, so it did nothing for these skills.
  - **Deft hands** (user 2026-11-06: kept on Handicraft at 10%, chosen over a per-pick bonus or a mastery of its
    own; item transfers left out for now, parked in TODO): every
    Lua timed action -10%, whatever it is for (not only Handicraft's skills: eating, reading, first aid, repairs,
    farming, butchering, everything that goes through `ISBaseTimedAction`).
    Item transfers (user asked 2026-11-06, 42.21 `client/TimedActions/ISInventoryTransferAction.lua`): single
    player times them in Lua (`new` ~764: 120 / 50 x weight x capacity factor x 0.1 / 0.2 / 0.5 Dextrous / 2 All
    Thumbs), and the first batch already goes through `create` -> `adjustMaxTime`; later batches set `maxTime` from
    the queue (~528) without it, so SP would need that line covered too. In MP the client only waits for the
    server: `createItemTransaction` (~313 / ~526), the server ends it at Java `Transaction.getDuration` (Dextrous
    x 0.5 read in Java), and the client reads the length back (`getItemTransactionDuration`, ~169). No Lua hook
    changes it. The only MP route is the one ZomboidFixesB42 took for fast forward and the Fast Timed Actions cheat:
    send each batch as a server-run move of our own (`*_Transfer.lua` + its server side, with floor reach, bags in
    vehicles, ghost items and Reject handling). Possible by porting that code, but a large, fragile piece for 10%. One hook: `ISBaseTimedAction:adjustMaxTime` (42.21 shared ~99: unhappy, drunk, hand
    pain, temperature; no vanilla subclass overrides it) is what the client's `create` (~79) and the MP server's
    `NetTimedAction` both run on the duration, so wrapping it scales every action on both sides at once (an action
    that calls it itself, `ISWashClothing:getDuration`, gets it twice, like vanilla's own factors). Not covered:
    item transfers (Java `Transaction.getDuration`), build-menu builds (Java `BuildAction.getDuration`), looped
    actions (-1) and actions that end on anim events (reloading). Stacks multiplicatively with a mastery's own
    time bonus (Smithing crafting: 0.75 x 0.9 = -32.5%).
  - Condition at creation is already full: `RecipeCodeOnCreate.minorCondition` (~1079; 21 carving and 10 knapping
    recipes) sets max condition from skill 10, so a "better made" bonus has to come as wear (the mark).
  - Extra output list, to vet per recipe: knapping (`knappFlake` already gives an extra sharpened stone at
    Knapping in 11), hand-pressed clay bricks / shingles / tiles (`craftrecipe_handpress.txt`, 1 clay -> 1 item),
    carving recipes with several outputs. Kiln firing runs in the kiln's Java CraftLogic (no `performRecipe`),
    not covered.
- **Mending**: patch / remove patch time -15%, fabric recovery +10 pts, ripping +1 material, aramid thread +1 use,
  crafting time -15% on Tailoring recipes.
- **Field Medicine**: treatment time -15%, treatment strength +15%; one more effect wanted (new, e.g. wounds infect
  less or stitching speed).
- **Provisioning**: added ingredient nutrition +15%, add-ingredient time -15%, cooking crafting time -15%; slower
  spoilage (new, trace).
- **Hunting**: track find chance +20%, track inspect time -15%, trap catch +5 pts, butchering part count +10%, part
  chance +15%, butchering time -15%.
- **Angling**: fishing line tension +15%, natural bait kept +10 pts, big fish +10 pts, junk -20%, trophy +2 pts.
- **Fieldcraft**: forage radius +15%, spotting time -20%, found item size +10%.
- **Homesteading**: harvest yield +15%, cure strength +15%, planting health +3, bonus yield +10 pts, curse -10 pts,
  fertilizing +10 pts, back strain -15%.
- **Livestock**: animal acceptance +15%, calming +15%, shearing time -15%; nearby animals gain 15% less stress from
  you (new, server give-back).

## Progress (proposed)

v1 machinery stays: a level-10 skill is parked, every gain is caught in `AddXP`, Strength / Fitness decay is caught
too. What changes is where a gain goes:

- Progress is stored **per picked mastery**, as points. A gain on a parked skill adds
  `amount / xp10(perk) x 100` points to **every picked, active mastery that lists the skill**. Each gain counts as
  a share of its own skill's level-10 step, so 900 Strength XP is worth much less than 900 Aiming XP (150000 vs 9000
  per step); one mastery level is about one level-10 step of any member, the v1 pace.
- Level n costs `100 x (1 + MasteryCostGrowth%)^n` points (5% default, the v1 curve).
- A gain on a skill that no picked, active mastery lists is lost, as in vanilla. Nothing earned before a pick counts.
  Every level-10 skill stays parked anyway (harmless, and ready for a later pick).
- Decay (negative Strength / Fitness XP) comes out of every picked mastery listing the skill that still has points;
  the skill drops below 10 only once none has any left.
- Why not v1's per-skill storage: two masteries sharing a skill can be picked at different times, so a shared pool
  cannot tell what each has earned. v1 was never played, so there is no saved data to carry over.

## Data shape (code sketch)

```lua
M.mastery("Firearms", { "Aiming", "Reloading" })
M.effect("Firearms", "HitChance", 5, "pts")
M.effect("Firearms", "ReloadSpeed", 15, "pct")
-- hooks: M.val(player, "Firearms.HitChance"), M.more / less / roll / int / scaleInt as in v1
```

Storage (global mod data, as v1): `TienSkillMastery[username] = { picks = { "Firearms", ... }, points =
{ Firearms = n }, hours }`. `M.MAX_PICKS = 3` (code constant). `M.level(player, masteryId)` = 0 unless picked and
every member is at 10. `M.masteriesOf[perkId]` lists the masteries of a skill. Weapon hooks map a weapon category to
its mastery (Axe -> Axemanship, Blunt -> Bludgeoning, LongBlade -> Swordsmanship, Spear -> Spearcraft, SmallBlunt ->
Street Fighting, SmallBlade -> Knifework). Proposed: skills added by other mods get no mastery and stay vanilla (a
prestige-only mastery would be a trap that wastes a slot); a mod can register its own with `M.mastery`.

## UI

The Mastery tab lists the 23 masteries by group: name, the member skills with a tick for each one at 10, and the
state:

- **Locked** (some member below 10), **Available** (all at 10, a slot free: a Start button with a confirmation
  saying the pick is permanent and which slot it takes), **Picked** (v1's gold level boxes and prestige +n;
  "Inactive" while a member is below 10), **Closed** (3 picks taken, never pickable by this character).
- A slot counter ("2 of 3 masteries picked"). The tooltip lists the effects at the current level and at mastery 10.
- MP: picking is a client command; the server checks every member at 10, the slot count and that it is not already
  picked.
- The cheat menu moves to masteries: add / remove points, set level, clear, and **remove pick** (admin:
  `Capability.AddXP` in MP, `-debug` in SP, as v1's mastery cheat).

## TODO: signature abilities (parked, user 2026-11-06)

The user wants masteries to give the player something new to do, not only numbers. Parked until the numbers are
reviewed. Proposed rule: every mastery gets one signature ability, with fewer passives to make room. Open: whether
the passives are trimmed, and when the ability unlocks (at the pick, at mastery 5 (proposed), or at 10).

- **Axemanship: throw one-handed axes** (user's idea; axe category, not two-handed). Feasible. Reuse
  ZomboidFixesB42's `*_Throwables.lua` flight (fixed 60 Hz steps, same path on client and server, item taken out by
  ID, 3D model in flight; each mod keeps its own copy). New: a "Throw axe" timed action with a custom
  `AnimSets/player/actions` node playing `Bob_AttackThrowMolotov` (vanilla's `Throw` node only runs for weapon type
  "throwing"; write the node out in full, `x_extends` breaks on Linux); zombie collision along the path; damage on
  the zombie's owner client (as `*_SpikedArmor.lua`; the server relays it to `getOwnerPlayer` when the thrower does
  not own it), kills sync, a stagger shows only on the owner; the server drops the axe where it hits or lands
  (`AddWorldInventoryItem`) with a condition roll. About 300-500 new lines plus the copied flight code. Trigger
  undecided (key bind, radial / context option while aiming, attack modifier).
- **Spearcraft: throw spears** (user, 2026-11-06): same machinery as the axe throw. Not discussed further yet.
- **Street Fighting: bowl zombies over while sprinting** (user, 2026-11-06): while sprinting with no endurance
  moodle, running into zombies knocks them down instead of the player falling, at an endurance cost per zombie.
  To trace: vanilla's sprint collision with zombies (the player's bump / fall).
- **Bludgeoning: push nearby zombies** (user, 2026-11-06): an active effect that pushes back the zombies close
  around the player. Specifics not discussed yet.
- **Firearms candidates**: Steady Aim (hold a key while aiming: instant aim-in and faster recoil settling for a few
  seconds, endurance cost, cooldown; recommended), Quickdraw (near-instant handgun draw from a holster / hotbar
  slot, `ISEquipWeaponAction` time), Field strip (mastery-only recipe restoring gun condition; inputs to check).
- **Deft hands for item transfers** (user wants faster actions, 2026-11-06; parked): single player is a small
  change (cover the queued batches' `maxTime`); MP needs ZomboidFixesB42's server-run transfer path ported (see
  the Handicraft notes).

## Open decisions

1. Effects: the list above, especially whether one weapon category per mastery is too narrow, the thin ones
   (Stealth, Field Medicine, Provisioning, Handicraft, Fieldcraft) and Salvaging as its own mastery.
2. Proposed, not confirmed: one effect per mastery; per-mastery point storage; nothing counts before a pick; no
   masteries for other mods' skills.
3. Removing a pick: does the mastery's progress go too (proposed: yes, a removed pick starts from 0 if picked again)?
4. v2 replaces v1, not a second mode next to it.
