# Skill Mastery v2: picked masteries (draft, 2026-11-06)

All of it built 2026-11-07 (v0.3.0), except what is parked with Stealth and Freerunning (core, picks, points, tab, v1 hooks moved to masteries; then the passives that fit
existing hooks). CLAUDE.md "v2 build" lists what is not built yet.
Stealth and Freerunning were parked (hidden; user, 2026-11-07) until their remaining effects are built, Salvaging too (2026-11-08).
Those three are now listed but marked Coming Soon, not pickable (user, 2026-11-08; Homesteading, Hunting and Angling were too, until the user opened them on 2026-11-09). v1 (one mastery per skill, bonuses that copy the skill's vanilla effects) is described in CLAUDE.md.
v2 keeps v1's XP capture and changes what the XP is spent on. **Approved** (user, 2026-11-06): the rules under "The
idea" and the masteries with their members and names (23 approved, Livestock later dropped: 22). **Not yet approved**: the effects, and everything marked
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
- **Sandbox choices only for mode gaps** (user, 2026-11-06): an effect that works in only one mode (single player
  or multiplayer) is paired with an alternative that works everywhere, and a sandbox option picks between them
  (none left: Swordsmanship's footwork choice went once strafe worked in single player). Effects that work in both modes are simply part of the mastery, with no option.
- Names are disciplines, never people: no mastery repeats a vanilla trait, profession or skill name (42.21 has
  Marksman, Brawler, Runner, Hunter, Angler, Artisan as traits; Lumberjack, Chef, Farmer, Rancher, Tailor as
  professions; Mechanic, Blacksmith as both).

## The masteries (every vanilla 42.21 skill, 35 skills, 22 masteries)

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
| | Engineering | Mechanics, Electrical (Electricity) |
| | Salvaging | Welding (MetalWelding), Mechanics |
| | Handicraft | Carving, Knapping (FlintKnapping), Glassmaking, Pottery |
| | Mending | Tailoring, Maintenance |
| | Field Medicine | First Aid (Doctor), Tailoring |
| | Provisioning | Cooking, Butchering |
| Field | Hunting | Tracking, Trapping, Butchering |
| | Angling | Fishing, Foraging (PlantScavenging) |
| | Fieldcraft | Foraging (PlantScavenging), Tracking |
| | Homesteading | Farming, Animal Care (Husbandry) |

Livestock (Animal Care + Butchering) was **dropped** (user, 2026-11-06): both skills are covered elsewhere
(Butchering by Provisioning and Hunting, Animal Care by Homesteading, whose animal side was empty), so its effects
moved to Homesteading. 22 masteries.

Skills in more than one mastery: Strength (3); Butchering, Fitness, Sneaking, Lightfooted, Welding, Mechanics,
Maintenance, Tailoring, Foraging, Tracking, Carving (2 each).

## Effects at mastery 10 (proposed)

v1's balance rule stays: about a 20% improvement over level 10, combat power 5-10%, defence / endurance / speeds
10-15%, yields 10-20%. Proposed rule: **each effect belongs to one mastery only**, so skills overlap but effects
never stack. A weapon mastery's effects apply with a weapon of its category. Marked **new** = not built in v1, needs
a hook (and tracing where noted); everything else reuses a built v1 hook with the id renamed.

- **Firearms** (in review): damage +10%, fire rate +10% (new), hit chance +5 pts, range +10%, aim-in speed +15%,
  reload and rack speed +15%, jam chance -25% (new), firearm wear undone 20%. Crit +5 pts dropped, a third damage
  multiplier. **Approved** (user, 2026-11-06), fire rate covering vanilla and Gunworks guns, bursts included.
  Signature, two parts (user 2026-11-06; Steady Aim declined): **quickdraw** (drawing and holstering a one-handed
  gun is always fast, whatever the hands held; vanilla's hand rules are unchanged) and **run-and-gun reload**
  (reloading does not stop when the master runs or sprints).
  - Run-and-gun reload (42.21): every reload action sets `stopOnRun = true` in `new` (`ISReloadWeaponAction` ~292,
    `ISInsertMagazine` ~146, `ISEjectMagazine` ~107, `ISLoadBulletsInMagazine` ~166, `ISRackFirearm` ~210,
    `ISUnloadBulletsFromFirearm` ~129, `ISUnloadBulletsFromMagazine` ~146), read by Java `BaseAction` on the
    client; `stopOnWalk` and `stopOnAim` are already false. Hook: wrap those `new`s and set `stopOnRun = false` for
    a master. Vanilla keeps some animated actions going while running (`ISOpenCloseDoor`, `ISToggleLightAction`,
    `ISDumpWaterAction` set it false), so the upper-body action anim should layer over the run; check in game that
    the reload anim plays and that its anim events still arrive while running (the server's emulated events time
    the reload either way, see ZomboidFixesB42 "Reload timing"), with Gunworks guns too.
  - Quickdraw (42.21 `shared/TimedActions/ISEquipWeaponAction.lua`, `ISUnequipAction.lua`): the caller passes the
    time (`maxTimeInit`); from a hotbar / holster slot `animSpeed` = maxTime / `adjustMaxTime(maxTime)`, and with
    maxTime -1 the action ends on the anim event (`detachConnect` when drawing, `attachConnect` when holstering).
    `complete` (server / SP) applies vanilla's hand rules: a handgun clears a HandWeapon from the off hand (~194),
    a primary clears a both-hands item, `forceDropHeavyItems`. Hook: wrap both `new`s (the server rebuilds the
    action with `new` from its parameters, so it gets the same time) for a HandWeapon that `isRanged()` and is not
    `isTwoHandWeapon()` / `isRequiresEquippedBothHands()`, held by a master: maxTime x0.25 (at least 1) and
    animSpeed x4, so an anim-timed draw reaches its event 4x sooner. Proposed x4; check the look in game. same per-shot min / max scaling as melee in `OnWeaponSwingHitPoint` (the firearm damage roll comes after
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
  (added by the user, 2026-11-06; covers chopping wear too). Signature **throw axes** (one-handed axes; user
  2026-11-06, design under "TODO: signature abilities"). Trigger (user 2026-11-07): swinging a one-handed axe while
  the reticle is on a zombie beyond the axe's reach throws it.
  - Tree damage (42.21): the server's `ISChopTreeAction:serverStart` emulates `ChopTree` every 1500 ms; its
    `animEvent` calls `IsoTree.WeaponHit`, which takes `weapon:getTreeDamage()` (x1.5 Ax-pert) off the tree's
    health ((log yield - 1) x 80, min 40) and topples it at 0. Hook: wrap that `animEvent` on the server and raise
    the axe's `setTreeDamage` (int, rounded) for the call. Attacking a tree outside the action is Java only
    (`CombatManager.processTreeHit`), so not covered. A shorter emulator period would desync the client's chop anim.
- **Bludgeoning** (**approved**, user 2026-11-06): damage +10%, attack speed +5%, crit reroll 5%, +1 target per
  swing at mastery 5 and +2 at mastery 10 (user 2026-11-07) with sandbox MultiHitZombies on, reach instead while it is off (so the effect is never empty), stepping the same way: +5% at mastery 5, +10% at
  mastery 10 (user 2026-11-07), swing
  endurance -15%, knockback +15% (new for this category, same per-swing push-back hook), long blunt wear undone 20%.
  Signature **push back** (user 2026-11-06: every swing also pushes back the nearby zombies it did not hit, at an
  endurance cost; design under "TODO: signature abilities").
  - Extra target (42.21): `CombatManager.calculateHitInfoList` caps a melee hit list at the weapon's
    `getMaxHitCount()` (script `MaxHitcount`, long blunts 2-3), forced to 1 when sandbox MultiHitZombies is off;
    the list that deals damage is built in `attackCollisionCheck` (~701) after `OnWeaponSwingHitPoint`, so a
    per-swing `setMaxHitCount(n + 1)` with the other per-swing fields works. Each further target takes less damage
    (`damage / (split x 0.5)`, split counting from 1). Anti-cheat: melee allows 3 x maxHits hits per 1.2 s, maxHits =
    max(3, the server copy's count) with MultiHitZombies on; a long blunt (2-3 targets + 1) stays inside it as long as
    no more than two swings land in 1.2 s (swing length not measured; check in game).
- **Swordsmanship** (**approved**, user 2026-11-06; the sandbox option was later dropped, below): damage +10%, attack speed +5%, crit reroll 5%, reach +10% and swing endurance -15%
  (both new for Long Blade, same hooks), long blade wear undone 20%, and a Nimble effect that works in single player
  too (user, 2026-11-06: v1's strafe speed +15% is multiplayer only). Candidate: **Deflect**, 10% chance that a
  zombie's attack on you is broken off with a stagger while you hold a long blade.
  The user first wanted a sandbox option to choose between the two (2026-11-06: enum `SwordsmanshipFootwork`,
  Deflect or strafe speed +15%) because strafe was multiplayer only. **Superseded** (user, 2026-11-06): strafe now
  works in single player too, as a position nudge (below), so by the "sandbox choices only for mode gaps" rule
  there is no option. Then **Deflect dropped** (user, 2026-11-06: it only matters once a zombie is already
  attacking you, which good play avoids), and riposte with it: the Nimble passive is **strafe speed +15%**. No
  sandbox option in the reviewed set. Signature **hamstring** (user 2026-11-06): while the master is sneaking
  and in attack stance (aiming) with a long blade, attacks go for the legs, and a zombie hit there loses the use
  of its legs and becomes a crawler.
  - Hamstring (42.21 `IsoZombie`: `setCanWalk`, `setBecomeCrawler`, `toggleCrawling`, `isCrawling`, `isCanWalk`;
    the debug menu's crawler toggles use `toggleCrawling` / `setCanWalk`, DebugContextMenu ~648): on
    `OnWeaponHitCharacter` from a master who `isSneaking()` and `isAiming()` with a long blade, on the zombie's
    owner (directly or relayed through the server, as the shove damage): `setCanWalk(false)` +
    `setBecomeCrawler(true)` so it drops and gets back up crawling (exact sequence to trace: vanilla's own path is
    a knocked-down zombie with the crawler flag). **Every** leg hit cripples (user, 2026-11-06), damage unchanged. To trace:
    whether the crawler state reaches other clients (ZombiePacket / `NetworkZombieVariables`) or each client must
    be told.
  - Strafe speed, position nudge (SP and MP, owner's client): while the master aims and moves, each update adds
    15% of last update's displacement with `setX` / `setY`, only when the step stays on the same or an unblocked
    neighbouring square (`isBlockedTo`), the same approach as Stealth's sneak speed. Feet slide 15%; the animation
    is not sped up. Chosen over overriding vanilla's strafe anim nodes with a variable of our own (looks better,
    but replaces vanilla's strafe XML, which gun mods such as Gunworks may also touch, and remote players would see
    the vanilla speed). v1's MP-only `setVariable("StrafeSpeed")` route is dropped.
  - Why the variable route fails in SP: `calculateWalkSpeed` rewrites `StrafeSpeed` in SP right before the animator, no Lua event in
    between; Nimble's input there caps at level 6 (min(0.9 + N / 10, 1.5)). Nimble's other uses (42.21
    `IsoGameCharacter`): fall damage ~2331-2409, fence trip ~13451, crawler lunge fall ~13689, climbing fail
    ~16081, footstep volume ~5442, firearm moving penalty (`CombatManager` ~2529): all Java.
  - Deflect (**dropped**, reference only), to trace: the zombie's `getAttackOutcome()` turns "success" at the end of its start anim, before the
    `AttackCollisionCheck` event that rolls the wound (ZomboidFixesB42 `*_ClothingWear.lua` watches the same
    moment); the zombie attack actiongroup has `to_staggerback` / `to_staggerback-knockeddown` transitions, so
    setting the stagger there should end the attack before it lands. Runs on the zombie's owner (SP: always the
    player), where the attack resolves; in MP other clients do not see the stagger (ZombiePacket carries no
    stagger or knockdown, see ZomboidFixesB42's notes), they only see the attack not land.
- **Spearcraft** (**approved**, user 2026-11-06): damage +10%, attack speed +5%, crit reroll 5%, reach +10%, swing
  endurance -15%, spear wear undone 30% (condition, head condition and sharpness: v1's hook already restores all
  three; above the other weapons' 20% because spears are the ones that break), spears from Carving recipes get +8% damage and +3% reach, fixed when made,
  landing near forged at mastery 10 (user 2026-11-09, replaced a +2 condition that did nothing; see CLAUDE.md "Forged spears"). Signature **throw spears** (user 2026-11-06; the axe throw's machinery, under "TODO: signature
  abilities").
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
  1.8-2.1 health). Signature **bowl them over** (user 2026-11-06, under "TODO: signature abilities"; shares the
  bump hook with Freerunning's phase through).
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
  weak per hit, speed is their identity. Signature (user 2026-11-07: "the current we have now is fine"): the
  **lunge**, i.e. the jaw-stab window +50% with the lunge, in full from the pick; Executioner and Ambush stay
  passives.
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
  strain -25% (new, user 2026-11-06). Signature (user 2026-11-07): **Heavy Load one level lower**, promoted from
  the passives, in full from the pick (so it leaves the per-level question in "Open decisions").
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
- **Freerunning** (**approved**, user 2026-11-06): running endurance -15%; no damage from falls of up to 2 levels (stepped, user 2026-11-07: a 1-level drop,
  from the 2nd floor, at mastery 5; a 2-level drop, from the 3rd floor, at mastery 10; none below 5),
  exhaustion no longer adds to the vault trip chance, nor to tall-wall climbing failure (per level, user
  2026-11-07: each mastery level removes 10% of what exhaustion adds, all of it at mastery 10) (all three new,
  user 2026-11-06; traced below under "Freerunning movement effects"); ~~sure-footed~~ (**dropped**, user 2026-11-06:
  evasion's phase through prevents every bump trip; it was 5% a level that a trip from running into a zombie,
  animal or player becomes a stagger). Sprint speed
  dropped: movement is root motion and Sprinting's speed only feeds the run / sprint blend (v1 notes), out of
  Lua's reach. Signature **evasion** (user 2026-11-06): a chance to dodge attacks (they do not land), and the master
  phases through anything they run into without the trip animation.
  - Dodge (**15%** an attack, flat as a signature, user 2026-11-06; to trace): the zombie's `getAttackOutcome()` turns
    "success" at the end of its start anim, before the `AttackCollisionCheck` event that resolves the hit, on the
    zombie's owner (the Deflect trace below; ZomboidFixesB42 `*_ClothingWear.lua` watches the same moment).
    `IsoZombie:setAttackOutcome` is public, so on a roll the owner sets it to a miss there; also public:
    `IsoGameCharacter:setAvoidDamage` (what it skips not traced). In MP the roll is made where the attack
    resolves (the zombie's owner, usually the victim's client; a zombie another client owns needs the server
    relay to that owner), and the server re-rolls a hit that gets through (`Bite.process`, ZomboidFixesB42 "Zombie
    attacks on players"), so a dodge must also stop the `ZombieHitPlayerPacket`, i.e. happen before the client's
    roll. **Animals included** (user, 2026-11-06).
    Traced 2026-11-10 (42.21 `AttackState.animEvent`): the whole hit runs in the `AttackCollisionCheck` branch, gated
    by `!zombie.isNoTeeth()`; inside it `triggerPlayerReaction` → `BodyDamage.AddRandomDamageFromZombie` does the
    player's `setHitReaction` (the hit animation), the damage, holes and `sendZombieHit` (the packet the server
    re-rolls). `IsoZombie:setNoTeeth(b)` is public; `noTeeth` is read only there and by `cantBite()` (itself read
    only inside `AddRandomDamageFromZombie`), reset in the zombie's reset, not saved and not in any packet. So a dodge
    = the zombie's owner sets `setNoTeeth(true)` for that swing (rolled when it enters AttackState, outcome "start",
    at a master) and clears it when the swing ends: no damage, no player animation, no packet, nothing to undo.
    Still runs: the zombie's own swing, `testDefense` in `execute` (vanilla's front defense, can play "Defended"),
    the sprinter slow factor, and observers' `AttackNetworkState` bite sound / blood splat. MP: only the owner's
    `AttackState` counts, so a client owning a zombie that targets another player must know that player's chance
    (clients get only their own mastery entry today: the server would broadcast masters' evasion). Animals are
    separate (`AnimalAttackState`, server, no gate found): undo plan below; leaving animals out is fine (user,
    2026-11-10).
  - Dodging other players (user, 2026-11-10: masters dodge PvP hits too). Traced 42.21: `IsoGameCharacter.Hit`
    (~5856) fires `OnWeaponHitCharacter` and `OnPlayerGetDamage "WEAPONHIT"`, then `LuaHookManager.TriggerHook(
    "WeaponHitCharacter", wielder, target, weapon, damageSplit)`; a Lua hook returning true (`Hook.WeaponHitCharacter
    .Add(fn)`, same API as vanilla's `Hook.Attack`) makes `Hit` return 0 before `processHitDamage` and
    `hitConsequences` (damage, hit reaction). (`setAvoidDamage(true)` is the same skip, one hit, not synced.) `Hit`
    runs on every machine: the attacker's client (`CombatManager` ~1159, local wielder; its return value is the
    damage put in the packet via `processClientHit`), then `PlayerHitPlayerPacket` (handlingType 3): the server
    relays it and runs `processClient` itself, and every client runs it too, each calling `WeaponHit.process` →
    `target.Hit(..., bRemote = true)` with the packet's damage. So every machine must agree: roll on the attacker's
    client (needs the masters' chances, same broadcast as for zombies), whose hook returns true, so the packet
    carries damage 0; the server's and clients' hooks then cancel any hit on a master whose damage is exactly 0
    (a real 0-damage hit, e.g. a shove, being cancelled too is fine: user, 2026-11-10). To check: whether the
    attacker's `HitReactionNetworkAI.calculateHitReactionFromWeapon` (still runs) / the packet's `Fall` field still
    make the victim stagger or fall on other clients.
  - Dodging animals (42.21 `zombie/ai/states/animals/AnimalAttackState`, Java): on the animal's `AttackConnect`
    anim event, when the target is a player (not in a vehicle, within `adef.attackDist + 0.5`, not invisible or in
    ghost mode, line of sight clear), the server / SP computes `animal.calcDamage()` and calls
    `chr:hitConsequences(nil, animal, false, damage, false)`, then sends `AnimalHitPlayer` to nearby clients.
    No Lua event before it, and `atkTarget` is a field. So the dodge is an undo (server / SP, the crash safety
    pattern): each tick, while an animal near a master `isAnimalAttacking()`, note the master's body part health
    and wound flags; when they drop and that animal is the attacker (`getAttackedBy` / a hit inside its attack),
    on a 15% roll put everything back (health, new scratches / cuts / bites / fractures). The hit reaction may
    still play; only the damage is dodged.
  - Phase through (to trace): bumping into a zombie, animal or player while running sets `BumpFall` in
    `IsoMovingObject.separate` (see "Freerunning movement effects"); public `setBumpFall` / `setBumpType` /
    `setCollidable` exist on the player. Plan: while the master runs or sprints, clear the bump (no trip, no
    stagger) and let them pass through (`setCollidable(false)` while running past characters, if it does not also
    drop wall collision; to check). Supersedes **sure-footed** (a trip becoming a stagger), dropped (user,
    2026-11-06). With Street Fighting's bowl them over too: the zombie is knocked down and the
    master passes through.
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
    ~1.1 s instead of ~0.9 s). Both sides (the server's simulation decides the damage). Traced 2026-11-10: the server
    runs `updateFalling` for every player (remote branch of `updateInternal2`, then `IsoGameCharacter.updateInternal`);
    an `OnTick` sweep reaches it (built).
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
  **quiet hands** (user 2026-11-07, replaces silent kills and widens it: any noise the master makes while
  sneaking, a kill, a door, a window, climbing over a fence or through a window, breaking glass, does not draw
  zombies: those within 16 tiles that start responding to a player sound in the next ~1 s are calmed; the Silent
  Ambush idea from Knifework; per level by seconds, user 2026-11-07: they are calmed after 10 s - 1 s a level of
  heading for the sound, at once at mastery 10; lose them likewise needs 13 s - 1 s a level unseen, 3 s at 10), **sneak speed +15%**
  (position nudge, needs an in-game feel test). Vanilla Sneaking / Lightfooted effects stay vanilla: out of reach
  (below).
  Signature (user 2026-11-07): **distraction throw**: while sneaking, throw a small item (a can, a bottle) and
  where it lands it makes a sound that draws zombies there. The flight is the axe throw's (`*_Throwables.lua`
  copy, item taken out by ID and dropped where it lands); the server adds the world sound at the landing square
  (`addSound`, radius and volume to tune). Items (user 2026-11-07): anything light, by its encumbrance
  (`getActualWeight`, contents included); proposed limit 1.0 (empty cans 0.2, empty bottles 0.1, a stone 1.0; a
  Molotov is 1.5). How to throw (2026-11-07, the axe's gesture): sneaking, the light item in the primary hand,
  aim at the spot and attack (aiming works with a non-weapon in hand, user). A non-weapon attacks as the bare-hands
  shove, which goes through the same `SwipeStatePlayer.enter`, so `getAttackTargetSquare()` is the spot under the
  mouse in `OnWeaponSwing`; farther than ~2 tiles, `Hook.WeaponSwing` cancels the shove and the throw plays
  instead. Glass shatters (user 2026-11-07): an item tagged `base:glass` (45 vanilla items: bottles, jars,
  glasses) is destroyed where it lands instead of dropping, with a louder world sound and a glass smash sound,
  and leaves broken glass on the square (`IsoGridSquare` has `addBrokenGlass` / `transmitBrokenGlass`, server;
  which one sends it to clients is to trace).
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
  - Quiet hands (was silent kills; the other noises use the same calming): the hit noise (see the Knifework notes above) cannot be stopped. A zombie that hears it runs
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
  20%, limited to the category; Firearms for guns). Signature (user 2026-11-07): **masterwork**, promoted from the
  passives, in full from the pick (so it leaves the per-level question in "Open decisions").
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
  -25% (matching Smithing; v1 had 15%), dismantle return +10 pts, **quiet work** (new: building noise -50%).
  Signature, two parts (user 2026-11-07, promoted from the passives, in full from the pick, no scaling):
  **more planks** (new, user 2026-11-06: sawing a log gives a 4th plank on a 50% roll, +17%) and **more stones**
  (new, user 2026-11-06: breaking a large stone gives 12 stones instead of 10, +20%).
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
- **Engineering** (renamed from Auto Repair by the user, 2026-11-06; vanilla's Engineer profession is a person, the
  same split as Hunting / Hunter) (reviewed 2026-11-06, the user moved on; the per-level question for on / off
  passives is open, see "Open decisions"): part install / uninstall time -15%, engine and lightbar repair +1
  condition per part, hotwire success +10 pts (vanilla at Electrical 10 is 45-90% by engine quality, so it is not
  empty), hotwire time -15%, dismantle +10 pts on Electrical scrap, extra Electronics Scrap 25% when dismantling
  radios, TVs and walkies (moved from Salvaging, 2026-11-06) (all v1), crafting time -25% on Electrical
  recipes (matching the other crafting masteries; v1 had 15%), **tuned engine** (new, user 2026-11-06: while a master drives, top speed +15% and
  engine power +15%), and the signature ability **engine overhaul** (new, user 2026-11-06: engine parts raise the
  car's engine quality, below). All work in single player and multiplayer, so no sandbox option.
  Trimmed (user, 2026-11-06): tuned parts (driving wear too slow to notice, the most code), generator repair +1
  condition (too small), careful driver (15% less car damage while a master drives; removed by the user, trace kept
  below), fuel saver (15% less fuel while a master drives; removed by the user, trace kept below; engine overhaul
  already lowers fuel burn through quality). Crash safety moved to Field Medicine.
  - Engine overhaul (signature ability, unlocked at the pick): a new option in the
    mechanics window's engine menu, beside vanilla's Repair Engine, for a master with a wrench and Engine Parts.
    Repair raises the engine part's **condition**; overhaul raises the car's **engine quality**, which vanilla sets
    once at spawn (`Vehicles.Create.Engine`: script quality x vehicle type, randomised, 0-100) and never changes.
    What quality does (42.21): start attempts retry 1 in quality (`VehicleEngine.updateStarting`); a cold-start
    failure 31 in (quality + 50 - cold) below 100, none at 100 (`shouldFailToStartDueToCold`; cold adds up to 30
    below 65 quality at or under 2 C); fuel burn x (1 + (100 - quality) / 200) (`Update.GasTank` ~464); engine
    power, but only as computed at spawn (script force x max(0.6, min(1, quality x 1.6 / 100)), so full power from
    quality 63); hotwiring gets harder (chance 100 - quality, clamped 5..50, + 4 x Electrical). **Decided** (user,
    2026-11-06): +1 quality per Engine Parts used, flat (no mastery scaling; vanilla repair gives up to 5 condition
    a part, so this is the dearer of the two on purpose), up to 100 (`VehicleEngine.setFeatures` clamps 0..100); power recomputed with vanilla's
    formula and never lowered (a car whose power is already higher keeps it). Shown by vanilla's "Engine quality"
    line in the mechanics window. Shared timed action with a server `complete` (re-checks the mastery, the wrench,
    the parts; removes the parts; `setEngineFeature(quality, getEngineLoudness, power)` + `updatePartStats()`, since
    loudness is stored x0.37; the server's engine update sends it). Tuned engine must take any engine power that is
    not its own boosted value as the new vanilla value. Proposed: one action uses every Engine Parts carried (up to
    the points left to 100) in 300, as vanilla's Repair Engine does.
  - Tuned engine (42.21 `CarController.update` / `control_ForwardNew`, `BaseVehicle`): the car's physics run on
    the driver's game (`Bullet.controlVehicle` only when not the server), from that copy's `getEnginePower()` and
    `getMaxSpeed()`. Engine force = power x (0.5 + rpm / 24000) x (1 - km/h / 200), faded to 0 from `maxSpeed` to
    `maxSpeed + 20` (Speed Demon from x1.15, so +15% top speed is a second Speed Demon; they stack); gears are spread
    over `maxSpeed`, so raising it alone lengthens the gears and weakens acceleration, hence the power bonus with
    it. Out of reach: the hard cap (`updateVelocityMultiplier`: 34 m/s, ~122 km/h, Java) and in MP the server
    option `SpeedLimit` (default 70 km/h; the client cuts the engine at it), so on a default server only the
    acceleration shows above 70. `CarController.engineForce` is a field (not readable from Lua).
    Hook (driver's client, SP and MP): while a master sits in the driver's seat, `setMaxSpeed(script maxSpeed x
    1.15)` (not saved, reset from the script at `createPhysics`) and raise the engine power with
    `setEngineFeature(quality, loudness, power x 1.15)` + `updatePartStats()` (loudness is stored x0.37, as the
    ZomboidFixesB42 notes say); put both back when the master leaves the seat. Engine power is saved and the
    server re-sends it with the engine state (`transmitEngine`), so the client re-applies it whenever it finds
    the vanilla value again, keeps the vanilla value in the vehicle's modData to put back, and puts it back
    before a single player save (in MP the client's copy is never saved). Check in game: vehicle anti-cheat with
    the higher acceleration.
  - Careful driver (**removed**, user 2026-11-06; the trace stays for reference) (42.21 `BaseVehicle`): a crash is `crash(delta, front)` (~4634), which on the server / SP
    lowers the front end durability and damages parts through `addDamageFront/Rear` and injures the occupants
    with `damagePlayers(delta)`. Single player calls it from Java (physics contact ~3432, `HitByVehicle` ~4630 for
    car against car), so wrapping `crash` would only work in MP (an MP client sends `vehicle.crash` and the
    server's VehicleCommands calls it from Lua). Hitting zombies is `damageFromHitChr` -> `addDamage*HitAChr`,
    also Java in SP. So the hook is a give-back instead, which works in both: each tick, for every vehicle whose
    driver (`getDriverRegardlessOfTow`, as vanilla's god mode check) is a master, note every part's condition and
    give back each lost point on a 15% roll (`setCondition` + `transmitPartCondition`), server / SP. That covers
    crashes, running zombies down, zombie thumps, weapon hits and driving wear alike (`Update.Brakes` ~709,
    `Vehicles.LowerCondition` ~722: suspension, muffler, tires, 1 condition on a roll, server / SP). A part
    whose item is gone at 0 (a window dropping its glass, a headlight) cannot be given back; skipped.
    `currentFrontEndDurability` / `currentRearEndDurability` are not given back: public fields with no setter,
    only lowered and saved, read by nothing (checked 2026-11-06). `VehiclePart.damage` is `setCondition` +
    `transmitPartCondition`, or `VehicleWindow.damage` for windows (glass dropped at 0). Cost: about 30-40 parts per vehicle
    with a master at the wheel, so a handful of vehicles at most.
  - Fuel saver (**removed**, user 2026-11-06; the trace stays for reference) (`Update.GasTank` ~450): the burn per minute is computed in Lua from engine quality, mass, gear and engine
    speed, then `amount = amount - elapsedMinutes x newAmount` and a leak under 70 condition. Wrapper: when
    `vehicle:getDriver()` is a master, give back 15% of the drop the call made (the wrapper only sees the total, so the
    0.01 leak of a worn tank is included).
- **Salvaging** (**Coming Soon**, user 2026-11-08; too narrow as it stands, see CLAUDE.md) (**approved**, user 2026-11-06; still to review after it: Mending, Field Medicine, Provisioning,
  Hunting, Angling, Fieldcraft, Homesteading): burnt-car scrapping time -15%, +1 salvage roll per
  burnt car, engine salvage +20% parts, **torch fuel for scrapping** (new: 20% of the blowtorch uses a burnt car
  takes come back), and the signature ability **scrap any car** (new, user 2026-11-06, below). Dropped: metal window
  pick-up break (v1 found no window it applies to). Extra Electronics Scrap 25% moved to Engineering (it is
  Electrical's).
  - Scrap any car (signature, unlocked at the pick): vanilla offers "Remove burnt vehicle" only when the script name
    contains "Burnt" or "Smashed" (42.21 `client/Vehicles/ISUI/ISVehicleMenu.lua` ~617, a plain `string.match`);
    the shared `ISRemoveBurntVehicle` itself checks only the blowtorch in hand (>= 10 uses) and that the vehicle
    still exists, and its server `complete` rolls the salvage, burns 10 torch uses and `permanentlyRemove`s the car.
    So the ability is the same menu option (and welding mask / torch tooltip) for any vehicle when a Salvaging
    master opens the menu, plus a server re-check in a wrapped `complete` (burnt / smashed, or the scrapper is a
    master). Same yield table as a burnt car. To decide (proposed): refuse while anyone sits in the car or any of
    its containers (trunk, glove box, seats) holds items, and while it tows or is towed; installed parts are
    destroyed with it (the tooltip warns: take them off first). MP griefing: a master could scrap anyone's car in
    ~13 s; proposed guard: refuse inside a safehouse the scrapper does not belong to (`SafeHouse.getSafeHouse`).
    **Guards approved** (user, 2026-11-06): no one inside, every container empty, not towing or towed, installed
    parts destroyed with the car (tooltip warns), refused in a safehouse the scrapper is not a member of.
  - Scrap car parts (part of the same signature, user 2026-11-06, proposed): an inventory menu option "Scrap" on
    vehicle part items (script `VehicleType` set) for a Salvaging master, with a blowtorch and a welding mask as
    for a car. 42.21 vanilla has no recipe that takes them except brakes (tagged `base:smeltablesteellarge`, and
    one welded weapon recipe) and whole tires (tag `base:wholetire`, tire armor). Scope: doors, hoods, trunk lids,
    mufflers, gas tanks, suspension, brakes, seats; not tires (armor, fire fuel), windows (glass), batteries,
    trunks or glove boxes (the car's storage as an item, not real metal). **Yield: a fixed list per part** (user,
    2026-11-06; the numbers are a first draft):
    | Part (items) | Yield |
    |---|---|
    | Front / rear door | 1 Sheet Metal, 1-2 Small Sheet Metal, 1 Screws |
    | Double rear door, hood (EngineDoor), trunk lid (TrunkDoor) | 2 Sheet Metal, 1-2 Small Sheet Metal, 1 Screws |
    | Muffler | 1-2 Metal Pipe, 1 Scrap Metal |
    | Gas tank | 1 Sheet Metal, 1-2 Small Sheet Metal |
    | Suspension | 1 Metal Bar, 1 Scrap Metal |
    | Brakes | 1-2 Scrap Metal |
    | Seat | 1 Metal Bar, 1-2 Scrap Metal |
    Ranges are rolled evenly. The same for every quality grade (1 / 2 / 3); a broken part (condition 0) gives the
    same, since scrap is scrap. Time and torch: proposed 1 torch use and 100 time a part (a door: ~2 s), 2 uses /
    150 for the 2-Sheet-Metal parts. Why not the burnt-car table: at Welding 10 it averages ~13.5 items a round
    over 21 entries (common 1 in 2, uncommon 1 in 5, rare 1 in 15, two tries each, plus lesser fallbacks), so a
    door would give ~13 random items (Engine Parts and wire from a door). Vanilla bug seen there:
    `IronBand`'s fallback is `"IronScrap "` with a trailing space (probably gives nothing). Own shared timed
    action with a server `complete` (re-checks the mastery, tools, the item still in the inventory), items sent
    with `sendAddItemToContainer`.
  - Burnt cars (42.21 `shared/Vehicles/TimedActions/ISRemoveBurntVehicle.lua`, server `complete`): needs a
    blowtorch with at least 10 uses in hand; max(5, Welding) rounds of `checkAddItem` over 16 items, two tries each
    at 1 in (base - Welding) (Engine Parts use min(Mechanics, Welding)); then 10 x `item:Use()` and
    `permanentlyRemove`. Torch fuel: wrap `complete`, count the torch's uses before and after, give each burnt use
    back on a 20% roll (2 a car on average; `setCurrentUses` + `syncItemFields`).
- **Handicraft** (**approved**, user 2026-11-06): crafting time -25% on Carving / Knapping / Glassmaking / Pottery recipes
  (66 / 11 / 8 / 21 recipes award their XP), tool wear undone 20% on them (new here, Smithing's hook),
  **craftsman's mark** (new: what a master makes there with a condition ignores 15% of its wear, whoever uses it;
  Smithing's masterwork for wood, stone and clay; per level, user 2026-11-07: 1.5% per maker's mastery level,
  stored on the item when it is made and never changed), **extra output** (new: 15% chance of one more of the recipe's
  output, on a vetted list of recipes that nothing turns back into their inputs). Signature (user 2026-11-07):
  **deft hands** (new: every timed action in the game -10%, below), in full from the pick, no scaling. v1's
  dismantle bonus dropped:
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
- **Mending**: patch / remove patch time -15%, fabric recovery +10 pts, ripping
  +1 material, aramid thread +1 use (all v1, Tailoring), crafting time -25% on Tailoring recipes (v1 had 15%; the
  other crafting masteries' value), and for the Maintenance side (its vanilla job, weapon wear, now belongs to each
  weapon mastery): **careful repairs** (new: repairs restore 15% more condition, and a failed repair costs no
  condition) and **lasting repairs** (new: a repair counts toward the item's repair count only 80% of the time;
  **removed**, user 2026-11-08).
  **Stronger patches** (new, user 2026-11-06: a master's patches protect **50%** more against scratches and bites),
  and the signature **restore** (below). **Approved** (user, 2026-11-06).
  - Patch protection (42.21 `Clothing`): `addPatch(chr, part, fabric)` (from `ISRepairClothing`'s server
    `complete`) builds a `ClothingPatch(tailorLvl, fabric, hasHole)` whose scratch / bite defense is fabric max x
    Tailoring / 10 (Cotton 5 / 0, Denim 10 / 5, Leather 20 / 10), stored on the patch as bytes and saved;
    `getDefForPart` adds it to the garment's defense (or uses it alone where there was a hole). Nothing clamps the
    level: the public `addPatchForSync(partIdx, tailorLvl, fabricType, hasHole)` rebuilds a patch at any level, and
    the sync path sends the level, so every copy computes the same numbers. Hook: wrap that `complete`, note the
    hole before; after it, if the part has a patch, rebuild it at Tailoring 10 + 5 (+50%, 0.5 a mastery level,
    rounded down: Leather 30 / 15, Denim 15 / 7, Cotton 7 / 0), then `syncItemFields` (carries patches). Shown by
    vanilla wherever a patch's defense is shown. Catch: Lua cannot read the patch's `hasHole` or `conditionGain`
    (fields, no getters), and the rebuilt patch has `conditionGain` 0, so removing it would not take back the
    condition the patch gave (a patch / remove loop would gain condition). So the condition gain vanilla gave (the
    condition change across the `complete`) goes into the item's modData per part, and a wrapped `ISRemovePatch`
    `complete` takes it off. `hasHole` = the hole noted before. A patch that fully restores the garment
    (`canFullyRestore`) leaves no patch: nothing to do.
  - Repairs (42.21 `FixingManager`, Java, called from Lua: `ISFixAction:complete` ~38 for items,
    `ISFixVehiclePartAction:complete` ~35 for vehicle parts, both server / SP): success unless
    rand(100) < fail chance (3 + 2 x (repairs + 1), +30 per missing fixer skill level, -5 per level above); a success
    adds `missing condition x pct / 100` (pct = 50 / 20 / 10 for the first / second / other fixers, divided by
    (repairs + 1), +5 per skill level above the fixer's need up to +25, x the Fixing's condition modifier) and raises
    `haveBeenRepaired` by 1 (the "Repaired x times" that makes every later repair weaker and likelier to fail); a
    failure takes 1 condition. Hook: wrap both `complete`s, note condition and `haveBeenRepaired` before, then after
    a success add 15% of the gain (at least 1, within max) and on a 20% roll put `haveBeenRepaired` back; after a
    failure give the point back; `syncItemFields`. Vehicle part repairs included: Engineering touches no Fixing.
  - Signature **restore**: a menu option on an item with a repair count: one use of the item's own
    first fixer (the material its Fix recipe names first) and the same time as a repair set `haveBeenRepaired`
    back to 0, so the item repairs like new again (condition unchanged). Simple (`setHaveBeenRepaired` exists,
    sent by `syncItemFields`).
- **Field Medicine** (**approved**, user 2026-11-06, with the patient's unused supplies handed back): treatment time -15%, treatment strength +15% (both v1), **crash safety** (moved from Engineering by the
  user, 2026-11-06; proposed trigger: a Field Medicine master **anywhere** in the car, so everyone in it takes 15%
  less crash injury; works in single player and multiplayer), **sparing disinfectant** (new, user 2026-11-06:
  disinfecting uses 50% less alcohol), and the signature **field triage** (user 2026-11-06, below).
  - Sparing disinfectant (42.21 `shared/TimedActions/ISDisinfect.lua` `complete` ~68, server / SP): the part's
    alcohol level rises by the alcohol's strength (a fluid: 4 x its alcohol share; a drainable: its alcohol
    power), not by the amount used, so using less does not weaken it. Then a fluid container loses 0.15 L
    (`adjustAmount(amount - 0.15)` + `sendItemStats`; nothing at all when 0.15 L or less is left, a vanilla quirk)
    and a drainable one use (`UseAndSync`). Hook: wrap `complete`, note the amount / uses before, then give back
    50% of the fluid used (`adjustAmount` + `sendItemStats`) or the used use on a 50% roll (`setCurrentUses` +
    `syncItemFields`). Any disinfecting by a master, from the health panel or anywhere else that queues
    `ISDisinfect`.
  - Field triage (signature, unlocked at the pick; the user's design): a right-click option "Tend wounds" on another
    player and on yourself. It walks to the patient and queues vanilla's own treatment actions for every body part
    that needs them, in this order: remove glass (`ISRemoveGlass`, by hand with pain when no tweezers / suture
    needle holder, as vanilla allows), remove bullets (`ISRemoveBullet`, needs tweezers or a suture needle holder:
    skipped without), splint fractures (`ISSplint`: a splint, or a plank / stick with a rag), then bandage every
    bleeding or open wound (`ISApplyBandage`: scratches, cuts, deep wounds, bites, the extracted glass and bullet
    holes). Only these: no stitching, **disinfecting** (never, user 2026-11-06), burns, poultices or pain killers. **Infected parts are
    skipped** (user). Meant to keep someone alive until proper treatment; parts already bandaged / splinted are left
    alone. The actions are vanilla's (they already treat another player, server `complete`s), so they get the
    mastery's treatment time and strength like any other treatment.
    MP: another player's real body is not on the doctor's client (a remote player's `BodyDamage` is a full-health
    fake, see ZomboidFixesB42 "Player stats are server-authoritative"), so the plan comes from the server: the
    option sends `triage {target}`, the server lists the parts and what each needs, the client queues the actions.
    Self and single player read the body directly. **Decided** (user, 2026-11-06): "infected" = a wound infection,
    the kind that needs disinfectant (`bodyPart:isInfectedWound()`): such parts are skipped whole; the best
    bandage carried is used (sterilized bandage > bandage > sterilized rag > rag); supplies come from the doctor
    **and** the patient (inventories and bags).
    Supplies (42.21): `ISApplyBandage` / `ISSplint` `complete` remove the item with
    `self.character:getInventory():Remove` + `sendRemoveItemFromContainer`, i.e. from the doctor's **main**
    inventory only (an item in a bag would be used and kept; vanilla's health panel moves it out first). So the
    doctor's own bag items go through `transferIfNeeded` before each action, and the patient's are moved by the
    server: when the triage plan needs more than the doctor has, the server takes the missing items from the
    patient's inventory tree into the doctor's main inventory (`DoRemoveItem` + `sendRemoveItemFromContainer`,
    `AddItem` + `sendAddItemToContainer`, as TienGiveItemMP moves items between players) and lists them in its
    reply; the doctor's own supplies are used first. Proposed: whatever of the patient's is still unused when the
    queue ends or is cancelled goes back to the patient (`triageReturn`). Glass and bullets come before bandages so
    the bandage goes on last (whether vanilla allows removal through a bandage is not traced).
  - Crash safety (42.21 `BaseVehicle.damagePlayers` ~9390, server / SP, skipped without sandbox
    PlayerDamageFromCrash): per occupant, `addRandomDamageFromCrash` takes health off 1-3 random body parts and may
    add a deep wound, a fracture, or window glass (a scratch from the window, sometimes a deep wound with glass),
    then `OnPlayerGetDamage(chr, "CARCRASHDAMAGE", damage)` fires, then the server sends PlayerDamage to that
    player. So the event is a window before the send. Hook: each tick, note body part health and wound flags of
    every occupant of a car with a master on board; in the event give back 15% of each part's health loss,
    and take back each new deep wound, fracture or glass on its own 15% roll. The changes ride the PlayerDamage
    packet that follows. Other damage in the same tick gets the same give-back (one tick, negligible).
- **Provisioning** (**approved**, user 2026-11-06, choice cuts as the signature, butchering time moved here from
  Hunting): added ingredient nutrition +15%, add-ingredient time -15% (both v1, Cooking), cooking crafting time -25%
  (v1 had 15%; the other crafting masteries' value), **lasting food** (new: food a master cooks or butchers stays
  fresh 25% longer), butchering time -15% (v1's, moved here from Hunting, which keeps the part count and part
  chance: Hunting = how much a carcass gives, Provisioning = how good the meat is and how fast it is cut), and the
  signature **choice cuts** (user 2026-11-06: meat a master butchers is 15% more filling and nutritious; since 2026-11-08 10% more filling and 30% more nutritious, in full
  from the pick). Comfort food, briefly the signature, was replaced by choice cuts (note kept below).
  - Choice cuts (signature, flat x1.15 from the pick) (42.21 `shared/Definitions/animal/ButcheringUtil.lua`, server / SP): `giveMeatModified` (~363)
    makes each meat item, runs `modifyMeat(item, size, meatRatio, hungerBoost, rotten, deathAge)` (~426: hunger,
    calories, lipids, proteins, carbs x animal size x meat ratio x the cut's boost, x0.9-1.1 each; sets its age),
    then `AddItem` + `sendAddItemToContainer`. `modifyMeat` has no player argument, so wrap `giveMeatModified` to
    note the butcher for the call and wrap `modifyMeat` to scale the item's hunger, base hunger and the four
    nutrients x1.15 and stretch its spoil times (lasting food) when that butcher is a master;
    the send that follows carries it. Organs and other parts (`addAnimalPart`) are left as they are.
  - Lasting food (42.21 `Food`): fresh until `offAge`, rotten at `offAgeMax` (days), both per item, saved and sent
    with the item (`Food.save`), setters public (`setOffAge` / `setOffAgeMax`, the admin item editor uses them). At
    creation, x1.25 both (2.5% a level): cooking recipe outputs (the v1 `performRecipe` hook, server / SP; the
    outputs were already sent by `addOrDropItem`, so re-send with `sendReplaceItemInContainer`, as v1's nutrition
    does), evolved dishes when a master starts them (`ISAddItemInRecipe:complete`, once per dish: a modData mark,
    so adding more ingredients never stacks it), and the meat a master butchers (the choice cuts `modifyMeat`
    wrap, before the send; other parts from `addAnimalPart` still to trace). Items with no spoiling (1e9) untouched.
  - Comfort food (**replaced** by choice cuts as the signature, user 2026-11-06; kept for reference): dishes a master cooks also lower unhappiness and boredom when eaten
    (`setUnhappyChange` / `setBoredomChange`, per item and saved like the spoil times), e.g. -10 each for a full
    serving, so a cooked meal lifts morale like good food does in vanilla.
- **Hunting**: track find chance +20%, track inspect time -15%, trap catch +5 pts, butchering part count +10%, part
  chance +15% (butchering time moved to Provisioning, 2026-11-06). Signature (user 2026-11-06, two parts like
  Salvaging's): **sturdy traps** (traps a master sets never lose their bait to animals and are never destroyed)
  plus **live catch** (animals caught alive in a master's trap survive about 4x longer in it) and **double catch**
  (25% that a master's trap holds two of the animal it caught) (user 2026-11-06; field dressing dropped: vanilla has
  it, below). **Approved** (user, 2026-11-06).
  - Live catch (42.21 `STrapGlobalObject`): only rabbit, mouse, rat and raccoon can be caught alive
    (`TrapDefinition.lua`, `canBeAlive`). `calculTrap` (every hour) adds 1 to `animalAliveHour` while something is
    in the trap; taking it out (`addAliveAnimal` ~204) runs the animal's hunger, thirst and health for
    rand(hours, hours + 15) updates, and if that kills it the player gets a corpse instead. Hook: for a master's
    trap, wrap `addAliveAnimal` and count only a quarter of the stored hours for the call (the +0..15 stays).
  - Double catch: on `setAnimal` (~427, the catch) for a master's trap, roll 25% and keep a flag on the trap
    (saved with its state). Wrap `removeAnimal` (~269): note `self.animal` and `animalAliveHour` before, let vanilla
    hand over the first (it clears the trap), then put them back for one more call of the same give path and clear
    again. A second live animal goes in the hands like the first (`addAliveAnimal` calls `forceDropHeavyItems`,
    which should set the first one down; check in game).
  - Sturdy traps (42.21 `server/Traps/STrapGlobalObject.lua`, server / SP global object system):
    `checkDestroy(square)` (~160, every hour) takes the bait 1 in (trap strength + 10) and, while the trap's square is
    not loaded, destroys the trap 1 in 40 x 1 in trap strength. Placement saves the placer's Trapping in
    `trappingSkill` (`shared/Traps/TrapSystem.lua` ~46); mark the trap as a master's there too (a field on the
    global object, saved with its state) and skip `checkDestroy` for marked traps.
  - Field dressing as first proposed (gut a small catch from the inventory) is vanilla's `ButcherSmallAnimal`
    (`recipes_cooking.txt` ~702: dead bird / mouse / squirrel / rat / frog / rabbit -> meat, sharp knife or cleaver
    kept, any surface, time 50).
- **Angling** (**approved**, user 2026-11-06): fishing line tension +15%, natural bait kept +10 pts, big fish +10 pts, junk
  -20%, trophy +2 pts (all v1), **bait digger** (new passive, user 2026-11-06: foraging finds worms and insects
  more often; number and hook to trace) and **big haul** (new passive, user 2026-11-06: a master's fishing nets and
  fish traps catch more; to trace), and the signature **fish finder** (user 2026-11-06).
  - Fish finder (signature, client only): while a master aims a rod at water (vanilla's fishing states, `Fishing
    .Utils.isPlayerAimOnWater` / `getAimCoords`), a small readout beside the cursor (`OnPreUIDraw`, as forage
    icons draw) shows the aim square's fish (`Fishing.Utils.getFishNumParams(x, y)`: the count and its bite factor,
    in words: fished out / few / good / rich for x0.1 / 0.5 / 1.0 / 1.5) and trash share
    (`FishSchoolManager.getInstance():getTrashAbundance(x, y)`, %), the same numbers vanilla's
    `FishingDebugWindow` reads. Bite chance is rolled on the angler's own game from its own `FishSchoolManager`
    (`Bobber:attractFish` is client side; the server relays chum with an `addChum` command), so the readout shows
    what the master's bites will use. Not traced: whether two clients' fish counts agree in MP.
  - Bite chance (42.21 `shared/Fishing/Bobber.lua` `attractFish` ~222): 0.8 x temperature (1; 0.75 at 0-15 C or
    30-40 C; 0.5 below 0 or 40+; 0.25 at -10 or less) x weather (fog or wind 0.8, rain 1.2) x time (1.2 at 4-6 and
    18-20 h) x hook x fish abundance (0 fish 0.1, under 10 0.5, up to 25 1.0, more 1.5), all from
    `Fishing.Utils.get*Params` (global, wrappable). A caught fish (not trash) calls
    `FishSchoolManager.getInstance():catchFish(x, y)` (`Fish:getFish` ~247), which depletes the spot; chum
    (`addChum`) raises it; `getFishAbundance` / `getTrashAbundance` are readable (the debug window shows them).
- **Fieldcraft** (**approved**, user 2026-11-06): forage radius +15%, spotting time -20%, found item size +10% (all v1),
  **keen eyes** (new passive, user 2026-11-06: in search mode the darkness, weather and walking penalties are
  ignored; `forageSystem.getLightLevelPenalty` / `getWeatherPenalty` / `getMovementVisionPenalty`, global Lua,
  client), and a two-part signature: **forage while fighting** (user 2026-11-06: search mode is not switched off
  by zombies) and **zombie sense** (user 2026-11-06: in search mode, zombies inside the forage circle are shown
  wherever they are). Trailblazer (full track details for a master) dropped: empty, see below.
  - Forage while fighting (42.21 `client/Foraging/ISSearchManager.lua`): `doDisableCheck` counts up while
    `checkShouldDisable` (~1092) is true and turns search mode off after 15 checks; it is true with any zombie very
    close (`getNumVeryCloseZombies() > 0`), with 3+ visible and 3+ chasing zombies, while running or sprinting, under
    the Java override (set only by debug tools and scenarios: `SearchMode.setOverride`, fires
    `OnOverrideSearchManager`), and in MP inside a safehouse the player may not loot. Hook (client): wrap
    `checkShouldDisable` for a master and drop the two zombie tests and the running / sprinting test (user
    2026-11-06: never cancelled by fighting or running); vehicles and the safehouse rule stay vanilla.
  - Zombie sense (second part of the signature, user 2026-11-06): while a master is in search mode, every zombie
    inside the forage circle is shown wherever it is (behind the player, behind walls, out of sight). Vanilla
    decides a zombie's visibility in Java every frame (per-player alpha from line of sight), so forcing the model
    visible from Lua would be overwritten before it is drawn (to try: `setAlphaAndTarget(playerNum, 1)` each
    frame). Sure route (client): draw a marker over each such zombie in `OnPreUIDraw` with `isoToScreenX/Y`, as
    forage icons are drawn, from `getCell():getZombieList()` (on an MP client, the zombies this client knows,
    i.e. the ones near it); radius = the search manager's current circle. Skips `isReanimatedForGrappleOnly()`
    corpses being dragged.
  - Trailblazer, dropped: `ISAnimalTracksUI` (42.21) gates details at Tracking > 4 and words freshness by the
    level (`getFreshnessString(level)`); a master has Tracking 10, so vanilla already shows everything.
- **Homesteading** (in review, 2026-11-06): Farming side (all v1): harvest yield +15%, cure strength +15%, planting
  health +3, bonus yield +10 pts, curse -10 pts, fertilizing +10 pts, back strain -15%. Animal Care side (moved from
  the dropped Livestock, 2026-11-06): animal acceptance +15%, calming +15%, shearing time -15% (v1), nearby animals
  gain 15% less stress from you (new, server give-back). All 11 kept (user, 2026-11-06). Signature, two parts
  (user 2026-11-06, area actions that queue vanilla's own actions, client side): **tend the field** (water the
  thirsty, cure the sick with the cures carried, fertilize where fertilizer is carried, for every plant in a
  picked area) and **sow the field** (plant every free plowed square in a picked area with the seeds carried).
  User, 2026-11-09: milking time -15% added, and one timed action now works a 3 x 3 block (own shared action, no longer
  vanilla's per plant; see CLAUDE.md). Second signature the same day: Animal Whisperer, flat -1 stress every 10 in-game
  minutes to the animals of the zone the master is in.
  Tend the herd (milk / shear a whole pen) was added, then **removed** by the user (2026-11-06: nothing special
  about it); its trace is kept below. **Approved** (user, 2026-11-06).
  - Areas: a two-click square picker (first corner, second corner; `ISSelectCursor` style with `skipWalk2`, see
    ZomboidFixesB42 "The whole admin surface"), plants and plowed squares found on the client, each plant's
    action queued with vanilla's walk-to first. Exact vanilla calls to trace at build time (farming menu in
    `client/Farming/ISFarmingMenu.lua`).
  - Tend the herd (**removed**, reference only) (42.21 `client/ISUI/Animal/ISAnimalContextMenu.lua` ~775 / ~840): vanilla's handlers block the
    animal's movement (`getBehavior():setBlockMovement(true)`), pick the nearer `leftmilk` / `rightmilk` (or
    `leftshear` / `rightshear`) attachment point, queue `ISWalkToTimedActionF` there, then `ISMilkAnimal(chr,
    animal, bucket, right, all)` / `ISShearAnimal(chr, animal, shear)` (shears moved to the hands first). Both
    stop when the player is 3+ squares from the animal; milking also when the inventory is full. Options "Milk the
    herd" / "Shear the herd" on an animal's menu: every animal in its pen (`DesignationZoneAnimal.getZone` +
    `getAnimalsConnected()`, loose animals only) that has milk / wool. Blocking all at once would freeze the herd
    (and `wanderIdle` lifts a block after ~2.8 min), so each animal's turn starts with a one-tick client step that
    blocks it and inserts the walk and the action right after itself. Milk goes into the carried containers in
    turn, moving to the next when one is full; the queue ends when none is left.

## Progress (proposed)

v1 machinery stays: a level-10 skill is parked, every gain is caught in `AddXP`, Strength / Fitness decay is caught
too. What changes is where a gain goes:

- Progress is stored **per picked mastery**, as points. A gain on a parked skill adds
  `amount / xp10(perk) x 100` points to **every picked, active mastery that lists the skill**. Each gain counts as
  a share of its own skill's level-10 step, so 900 Strength XP is worth much less than 900 Aiming XP (150000 vs 9000
  per step); one mastery level is about one level-10 step of any member, the v1 pace.
- Level n costs `100 x (1 + MasteryCostGrowth% x n)` points (5% default: 105, 110, 115...; the v1 compounding curve
  was replaced by this flat step, user 2026-11-10).
- A gain on a skill that no picked, active mastery lists is lost, as in vanilla. Nothing earned before a pick counts.
  Only skills a picked, active mastery lists are parked; the others sit at vanilla's cap (user, 2026-11-10: a parked
  skill showed vanilla's "<skill> XP: n" halo for gains no mastery took). A new pick parks its skills within a second.
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

The Mastery tab lists the 22 masteries by group: name, the member skills with a tick for each one at 10, and the
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
the passives are trimmed. **Decided** (user, 2026-11-06): a signature ability is an unlock, in full at the pick
(mastery 0), and does not grow with mastery level; only the passives follow the tenth-per-level rule.

- **Axemanship: throw one-handed axes** (user's idea; axe category, not two-handed; **chosen** as the signature,
  2026-11-06). Feasible. Reuse
  ZomboidFixesB42's `*_Throwables.lua` flight (fixed 60 Hz steps, same path on client and server, item taken out by
  ID, 3D model in flight; each mod keeps its own copy). New: a "Throw axe" timed action with a custom
  `AnimSets/player/actions` node playing `Bob_AttackThrowMolotov` (vanilla's `Throw` node only runs for weapon type
  "throwing"; write the node out in full, `x_extends` breaks on Linux); zombie collision along the path; damage on
  the zombie's owner client (as `*_SpikedArmor.lua`; the server relays it to `getOwnerPlayer` when the thrower does
  not own it), kills sync, a stagger shows only on the owner; the server drops the axe where it hits or lands
  (`AddWorldInventoryItem`) with a condition roll. About 300-500 new lines plus the copied flight code.
  **Trigger** (user 2026-11-07): an ordinary swing while the reticle is on a far zombie. Traced (42.21
  `SwipeStatePlayer.enter` ~159-201): `doAttack` first sets `attackTargetSquare` from `UIManager.getPicked()`
  (the picked zombie's square, or the picked square; player 0 on mouse only, a joypad gets its own square), then
  fires `OnWeaponSwing(player, weapon)`, then `Hook.WeaponSwing` (`LuaHookManager.TriggerHook`; returning true
  reverts the attack state, i.e. cancels the swing). So in `OnWeaponSwing` (attacker's client): a one-handed axe
  in the primary hand, a zombie on `getAttackTargetSquare()` farther than the weapon's max range and within the
  throw range (to tune) = a throw: either let the swing play and launch at `OnWeaponSwingHitPoint` (the swing is
  the throw motion, nothing in reach to hit) or cancel it with the hook and play the throw node (the plan
  above). A zombie within reach is a normal swing. Joypad players cannot aim at a far zombie this way (no picked
  object), so no throw for them.
- **Spearcraft: throw spears** (user, 2026-11-06; **chosen** as the signature): same machinery as the axe throw,
  same trigger (a swing with a spear while the reticle is on a zombie beyond its reach). Not discussed further yet.
- **Street Fighting: bowl zombies over while sprinting** (user, 2026-11-06; **chosen** as the signature): while
  sprinting with no endurance moodle, running into zombies knocks them down instead of the player falling, at an
  endurance cost per zombie. To trace: vanilla's sprint collision with zombies (the player's bump / fall,
  `IsoMovingObject.separate`, "Freerunning movement effects"); the knockdown on the zombie's owner (relayed as the
  shove damage), the endurance taken by the server.
- **Bludgeoning: push back** (user, 2026-11-06; **chosen** as the signature): every swing a master makes with a
  long blunt weapon also pushes back the zombies close around them that the swing did not hit (user: "goes with
  the attack for as long as they're not targeted"); no key, no cooldown, **an endurance cost** (user 2026-11-06).
  Area: **a cone in front of the player** (user 2026-11-06), proposed 1.5 tiles deep and 120 degrees wide
  (the player's facing, `getForwardDirection`, against the direction to each zombie). Proposed: on every swing
  (hit or miss), as a stagger back (not a knockdown);
  endurance 0.01 **per zombie** pushed (per zombie decided, user 2026-11-07; stat 0..1, tune the amount in game), taken by the server (stats are server
  authoritative: the attacker's client reports the count with the push; SP takes it directly), and no push while
  endurance is below the cost. Hook (attacker's client): in
  `OnWeaponSwingHitPoint` note the zombies in range; `OnWeaponHitCharacter` fires for each zombie the swing hits
  (after the hit point, same frame), so next tick push the noted ones that were not hit: on the zombie's owner
  (directly, or relayed through the server to `getOwnerPlayer`, as the shove damage), `setPlayerAttackPosition`
  from the player's side + `setHitForce` + `setStaggerBack(true)` (the zombie actiongroup's staggerback node, see
  ZomboidFixesB42 "Zombie stagger transitions"; to trace that a Lua-set flag is picked up outside a hit). MP:
  the stagger is not in ZombiePacket, so only the owner sees it animate (other clients see the zombie move back).
  Skips `isReanimatedForGrappleOnly()` and zombies on the floor.
- **Engineering: engine overhaul** (user, 2026-11-06): Engine Parts raise a car's engine quality; traced and
  written up under Engineering.
- **Swordsmanship: hamstring** chosen (2026-11-06, written up under Swordsmanship; Deflect / riposte, momentum,
  clean cut, cleave, iaido, whirlwind, hit and run, fighting on the move, finisher were the other ideas).
- **Firearms: quickdraw** chosen (2026-11-06, written up under Firearms). Earlier candidates: Steady Aim (hold a key while aiming: instant aim-in and faster recoil settling for a few
  seconds, endurance cost, cooldown; recommended), Quickdraw (near-instant handgun draw from a holster / hotbar
  slot, `ISEquipWeaponAction` time), Field strip (mastery-only recipe restoring gun condition; inputs to check).
- **Deft hands for item transfers** (user wants faster actions, 2026-11-06; parked): single player is a small
  change (cover the queued batches' `maxTime`); MP needs ZomboidFixesB42's server-run transfer path ported (see
  the Handicraft notes).

## Open decisions

1. Effects: **decided** (user 2026-11-07): one weapon category per mastery is not too narrow, and Salvaging stays
   its own mastery; the thin ones got signatures. (Salvaging parked 2026-11-08.)
2. **Vanilla skills only** (user 2026-11-07): no masteries for other mods' skills. Also **confirmed** (user 2026-11-07):
   each effect belongs to one mastery only; each mastery stores its own points; nothing counts before a pick.
3. Passives that are on / off: how they behave below mastery 10. All decided 2026-11-07: Handicraft's
   craftsman's mark ignores 1.5% of wear per maker's mastery level, fixed when the item is made; Stealth by seconds,
   no chances (user): lose them needs 13 s - 1 s a level unseen (3 s at mastery 10), quiet hands calms the
   zombies drawn by the noise after 10 s - 1 s a level (at once at mastery 10); Bludgeoning's extra target +1 at mastery 5,
   +2 at 10 (reach +5% / +10% with MultiHitZombies off); Freerunning's safe falls 1 level at mastery 5, 2 at 10,
   and its vault / wall rolls lose 10% of exhaustion's addition a level.
4. Removing a pick: **decided** (user 2026-11-07): the mastery's progress goes too, so a removed pick starts from 0
   if picked again. Only admins can remove a pick.
5. **Decided** (user 2026-11-07): v2 replaces v1, not a second mode next to it.
