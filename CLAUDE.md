# Tien's Skill Mastery — working notes

## Start here (status 2026-11-11)

The notes below grew as a log, and v1 sections are marked superseded. This section is the current state.

- **Version 0.4.3**, on `master` (the only branch; `v2-draft` deleted 2026-11-11), Workshop item 3836051294, **unlisted by choice**.
- **Open masteries:** 21 of 22 (Freerunning opened in 0.4.2, 2026-11-10; Stealth in 0.4.3, 2026-11-11). Coming Soon:
  Salvaging.
- **Next:** play `docs/test-checklist.md` on a dedicated server with two players, then fix what it finds.
- **Tests:** `tests/README.md` (`py tests/run_all.py`; `--release` adds the release report). They need `tests/.lupa`, installed
  once per computer. Older notes below mention harness files in a session scratchpad; those are gone.

- **Released in 0.4.3, not played (2026-11-10 / 11):** Freerunning: sprint +15%, run +10%,
  crouch +5% (client `*_Movement.lua` nudge), Evasion a 25% passive (`shared/*_Evasion.lua`), safe falls in three tiers
  (1 / 2 / 3 floors at mastery 3 / 6 / 9) that land higher drops as one floor lower (`shared/*_Falls.lua`), Unfazed
  Runner (`client/*_UnfazedRunner.lua`; since 2026-11-12 a stagger without the fall and the sprint toggle put back). Stealth, opened: quiet work and quiet swings, -50%
  at mastery 10 (`shared/*_Stealth.lua`; its sneak speed became Freerunning's crouch speed; Construction's own building
  noise cut was removed so the two no longer stack), signature Distraction Throw (`shared/*_Distraction.lua`, key K),
  and the signatures Lose Them (crouched and out of a chaser's sight 3 s: it gives up) and Unseen (crouched and still:
  zombies not already after the master do not notice), both in `shared/*_LoseThem.lua`, whose header has the 42.22
  trace. Every one has a test in `tests/` and a step in `docs/test-checklist.md`.

Still to do, in order:
1. Stealth in game: Distraction Throw's sound volumes (chosen 2026-11-11 from offline renders, see "Sounds" below:
   glass `SmashedBottleBreak`, metal `BreakMetalItem`, stone `StoneDrop`, and the mod's own synthesised can landing
   and release whoosh, both approved from previews), and Lose Them / Unseen on a server. Engine findings for anyone
   touching zombie targets: `setTarget(nil)` alone does not stick (for ~15 s after a sighting the zombie re-spots its
   "last spotted" by force every update); `setUseless(true)` + `spotted(player, true)` + useless back clears both. In
   multiplayer a zombie only picks up a new target while idle, eating, sitting or turning
   (`NetworkZombieManager.canSpotted`). pzopt staggers `OnZombieUpdate` handlers (`pzopt/LuaZombie`), so these run
   from OnTick.
2. Tomahawk and Javelin signatures should produce a sound.
3. Freerunning: the vault-trip / tall-wall exhaustion effects (`docs/v2-draft.md`; out of Lua's reach as far as traced).
4. Salvaging needs the user's decision. Suggested: Strip Down (one click uninstalls every part) plus the time and torch
   passives on part scrapping. Other ideas are under "Salvaging's problem" below.
5. Skill Journal recording and restoring mastery (low priority).
6. `scripts/make_workshop.py` writes `forum.txt` and `workshop.txt` with LF; put CRLF back after running it, or fix the script.

Releasing: bump `modversion` in `mod.info`, drop "(coming soon)" from `README.md` for anything opened, remove the id from
`M.COMING_SOON`, run `py scripts/make_workshop.py`, `py tests/run_all.py --release`. Commit on master, upload in
game. The summary goes in `workshop.txt` (Steam caps it at 8000 characters) and the full text in `forum.txt`, the pinned
Discussions thread, which the user pastes in; keep `README.md` the full source and never trim features to fit.

### The user's standing rules

These apply to all of the user's mods and were kept outside this repo until now. Their reasons, the reference notes
(what syncs in MP, what Lua can reach, Kahlua's library, decompiling on this PC, pzopt) and this mod's history in short
are in `docs/working-rules.md` (2026-11-11, user: keep every memory in the repository).

- **Dedicated server first.** The user's mods run on their dedicated server; single-player-only or host-only behaviour is useless.
  Every plan says how each piece works there: which side changes the world, which call syncs it, and which events fire there.
- **The server runs the Workshop copy.** A client runs the local working folder, and the server only fetches updates when it
  starts. When something "does nothing" or "waits for the server" in multiplayer, first compare the Workshop mirror's timestamp
  with the server's start time, then debug.
- **Verify against the implementation.** Docs, headers and these notes can be wrong: read the Lua or decompiled Java before relying
  on a claim, correct the note when it is wrong, and look for a simple cause before building sync workarounds.
- **Trace what the code can answer.** Never leave engine behaviour as "unknown" or "to check in MP" when a decompile
  settles it (user, 2026-11-10, about safe falls); keep in-game checks for feel, timing and visuals.
- **Findings go next to the code:** in the header or a comment of the file that relies on them, plus a short line here.
- **No over-the-head text as feature feedback** (`HaloTextHelper`), except the vanilla-style level-up halo, which is wanted.
- **No timers just to notice sandbox option changes.** This mod has no sandbox options for now (user: "I want to control the values").
- **TODO files hold open work only.** No "check in game" lists for built features there; `docs/test-checklist.md` was asked for
  separately and is deleted once done.
- **Workshop preview text** states only what plays, no real-world trivia.
- Lua sees a Java class's methods and static fields only: instance fields read as nil, so look for getters.

Windows tools: Python is `py`. The game is at `C:/Program Files (x86)/Steam/steamapps/common/ProjectZomboid`; its `jre64/bin/java.exe`
runs Vineflower on the jar's Java 25 classes (recipe in ZomboidFixesB42's `CLAUDE.md`, a separate repo).

### Sounds (2026-11-11)

- **Hearing vanilla sounds without the game:** the game's own `fmodstudio.dll` / `fmod.dll` (game folder, version
  0x00020399) through Python `ctypes` render any event of `media/sound/banks/ZomboidSound*.bank` to a WAV: output type 5
  (`WAVWRITER_NRT`, the WAV path as `extradriverdata`), Studio initialised with the synchronous-update flag 0x2, and
  `EventDescription_LoadSampleData` + `System_FlushSampleLoading` before playing (else the first plays come out silent).
  Script names map to events in `media/scripts/generated/sounds/**` (`event = Path` = `event:/Path`). Found that way:
  `BreakGlassItem` is near silent (no vanilla code plays it), `LongHandleCanDrop` and `WoodenStickCanDrop` are the same
  samples, and no vanilla event is a tin can landing.
- **Own sounds:** `scripts/make_sounds.py` synthesises them (numpy + soundfile, Ogg Vorbis, fixed seeds, nothing to
  license) into `42/media/sounds/`; `media/scripts/TienSkillMastery_sounds.txt` (module Base, several `clip`s = one
  picked at random, `GameSound.getRandomClip`) names them. The game's `fmod.dll` `System_CreateSound` loads the files
  (checked; type 10 = Ogg Vorbis). Used: `TsmDistractionWhoosh` (release), `TsmDistractionCanLand` (cans).
  The user approved both from the preview WAVs (2026-11-11); keep the current seeds and parameters unless asked.

## Overview and history

Skills keep going past level 10 as **mastery**: levels 1-10 with small per-skill bonuses (each level a tenth of
the bonus), then endless prestige with no more bonuses. Mastery is earned only by experience (real XP gains), never
by reading. Skill Journal (lait, workshop 3776641628) should one day record and restore it (low priority).
Standalone mod, started 2026-11-05.
**v2 replaces v1** (picked masteries over groups of skills, with effects of their own; design and every decision in
`docs/v2-draft.md`). **All of v2 built 2026-11-07** (v0.3.0) except most of Stealth's and Freerunning's effects: see "v2 build" below. Now v0.4.1 (0.4.0 merged to master 2026-11-09; 0.4.1 on 2026-11-10: flat mastery costs, only picked skills parked; Workshop item unlisted). What has been played is listed next; no full pass on a dedicated server is recorded.
**Played in game (2026-11-07, user):** Firearms' signatures (Quickdraw, reloading while running) and Axemanship's
(the throw key: held and carried axes, swing / hit sounds, damage on arrival; the reticle since replaced by an
outline, animal and PvP targets added after that test, those played 2026-11-08); 2026-11-08: Smithing's Masterwork and Handicraft's
Craftsmanship (marks, passing on, tooltip), Construction's Clean Cuts and Clean Breaks (with the flat stone recipe), Conditioning's Pack Mule (moodle one level lower
via max weight), Knifework's Lunge (1.5-tile reach, vanilla's TargetDist target), Engineering's Engine Overhaul, Street Fighting's
Battering Ram, Handicraft's Deft Hands (transfers and grabs included), Fieldcraft's Steady Eyes and Sixth Sense, Field
Medicine's Field Triage (sort, low-health priority, key, shared list; no menu since 2026-11-09; 2026-11-09: the fewest-actions rework, user reports it works), Needlework and the stitching pain passive,
Provisioning's Choice Cuts and Savory Meals, Mending's Restoration, Bludgeoning's Wild Swing, Swordsmanship's Hamstring,
Spearcraft's Javelin.

Deft Hands and item transfers (2026-11-08): MP transfers are Java item transactions Lua cannot time, so a master's
client sends each batch to the server instead (`*_DeftTransfer*.lua`, ported from Zomboid Fixes B42's fast-forward
timed transfers: container addressing, vanilla's duration formula, `ISTransferAction:transferItem`), which waits
vanilla's length cut by the signature and moves the items; SP cuts each later batch in `perform`. Steps aside for
Zomboid Fixes B42's cheat / fast forward transfers. Right-click Grab (`ISGrabItemAction`) has its own path there too
(ported from Zomboid Fixes B42's quick grab: no transaction, waits for arrival, `isValid` skipped once started).
Played and working (2026-11-08, at a temporary 90%: transfers and grabs). Everything else is still
unplayed: Hunting's and Angling's signatures, Homesteading's (one report on Dig furrows, 2026-11-09, below) and every other passive. The v1 sections that
follow still describe the hooks and the parking, which v2 keeps; their per-skill ids and values are superseded.

Engine facts are from the 42.21 jar (Vineflower, recipe in ZomboidFixesB42's CLAUDE.md) and vanilla 42.21 Lua.

## v2 build (from 2026-11-07)

- Core (`shared/TienSkillMastery.lua`): `M.mastery(id, group, members)` for the 22 masteries (ids without spaces:
  `StreetFighting`, `FieldMedicine`; names in `IGUI_TienSkillMastery_Mastery_<id>`), `M.def(mastery, name, at10,
  kind, extra)` effects with ids `<Mastery>.<Name>` (kind "step" = `steps = { { level, value } }` + `unit`; `when`
  = a sandbox condition, e.g. Bludgeoning's ExtraTarget with MultiHitZombies on, its Reach with it off). Maps:
  `M.WEAPON_MASTERY` (melee perk -> mastery), `M.CRAFT_MASTERY` (crafting time), `M.DISMANTLE_MASTERY`;
  `M.weaponMastery(weapon)` (Firearms for aimed firearms), `M.valFor(player, map, perk, name)`.
- Storage `TienSkillMastery[username] = { picks = { ids }, points = { [id] = n }, hours }` (v1 `xp` entries are
  dropped on read; v1 was never played). Client cache has the same shape. `M.state` = picked / inactive / available /
  locked / closed; `M.level` is 0 unless picked and every member at 10; `M.MAX_PICKS` = 3 (code constant).
- Points: a gain on a parked skill adds `amount / xp10 x 100` to every picked, active mastery listing it (none =
  lost). Level n costs `100 x base% x (1 + growth% x n)` points (rounded to 0.1; 105, 110 .. 150, 1-10 = 1275). Decay
  (x `Conditioning.Decay`) is paid by every earning mastery listing the skill; the skill stays at 10 while one paid
  in full, else the rest goes the vanilla way.
- Server: `M.pick` (client command `pick`, checked: exists, not picked, slot free, members at 10), `M.adminChange`
  on picked masteries only (`add` / `remove` points, `level`, `clear`, `unpick` = pick and progress gone).
- Panel: groups, name coloured by state, boxes / Pick button (ISModalDialog confirm) / Locked / Closed, members green
  at 10, click for effects, right-click cheats. `M.masteryName` lives in the client core.
- Hooks moved to mastery ids; v1 effects dropped in v2: Fitness attack speed, Strength damage / knockback (each weapon
  mastery has its own), Aiming crit, Nimble strafe variable (Swordsmanship gets a position nudge later), Electrical
  generator repair, Welding metal window break. Swing endurance and wear undo now cover every weapon mastery's
  category (wear: Firearms for guns); structure HP covers Masonry recipes too; tool wear undo also on Handicraft
  recipes; firearm damage is new (same min / max scaling as melee).
- Tests: lupa harness (session scratchpad `tsm/harness.lua` + `tests.lua`, not kept) loads the real core and server
  files: 92 checks (costs, picks, slots, gains before a pick lost, shared skills, inactive, decay, admin, steps).
  The mock's lose-level loop must only fire on a downward crossing, as Java's does, or every park looks like a drop.
- **Parking (none parked now)**: `M.PARKED` in the core: a parked mastery keeps its definition, effects and hooks, but
  is left out of `M.masteries` / `M.masteryById` / `M.masteriesOf` (not listed, not pickable, earns nothing), its
  effects read 0 (`M.enabled`), and a pick of it in saved data is dropped on read (points kept). Stealth and Freerunning
  (user, 2026-11-07, until their missing effects are built) and Salvaging were parked this way until 2026-11-08, when
  the user unhid them as Coming Soon (below). Picks dropped while parked do not come back.
- **Salvaging's problem** (user, 2026-11-08: too narrow; every bonus sits on scrapping a car or taking
  engine parts, and a burnt car already drops ~135 items at Welding 10). Its effects, Scrapper and
  hooks are all there. Splitting them across Smithing and Engineering was tried and reverted the same day.
  Ideas offered, none chosen: Strip Down (one click uninstalls every part through vanilla's actions), Reclaimed Parts
  (installed parts sometimes survive scrapping), part scrapping getting the time and torch passives, Scrap Eye (forage
  Junk), Cut Through (torch opens locked doors, not traced).
- **Coming soon: Stealth, Salvaging** (user, 2026-11-08: unhidden, see Parking; Stealth shows no effect
  since 2026-11-11, when its Sneak Speed became Freerunning's crouch speed, and has no signature). Homesteading, Hunting and Angling were on this list too (their signatures not played) until the user
  opened them on 2026-11-09, still unplayed as far as these notes know; Freerunning (running endurance, safe falls,
  signatures Evasion and Unfazed Runner, built 2026-11-10 and not played; Evasion a passive since 2026-11-11) was opened in 0.4.2 the same day.
  `M.COMING_SOON` in the core: listed with their effects, but `M.state` gives "soon" (after picked / inactive and
  closed, whatever the members' levels, so nobody levels up to a Locked that never opens), the panel draws a grey
  Coming Soon button that does nothing, and `M.pick` refuses them on the server. Unlike parking, an existing pick
  stays and works. Remove an id once the user opens it, and drop its "(coming soon)" from the README (`py
  scripts/make_workshop.py` writes forum.txt and workshop.txt from it).
- Phase 2 (same day): the passives that fit existing hooks. Files: `shared/*_Relay.lua` (extra damage on a zombie's
  owner: own zombie inside `OnWeaponHitCharacter`, before `hitConsequences`; remote one via `zombieHit` -> server
  amount from its own copy of the mastery, 4-tile check -> `zombieDamage` to `getOwnerPlayer()`), `shared/*_Falls.lua`
  (safe falls: `lastFallSpeed` held one update's step under the no-damage impact speed, at most 90% of it, both
  sides; a higher drop held at the landing speed of a drop one floor shorter, 2026-11-11), `shared/*_Evasion.lua` (Freerunning's Evasion, 2026-11-10: a dodged zombie swing is made toothless,
  `setNoTeeth`, on the zombie's owner from "start" to the swing's end; a dodged PvP hit is `setAvoidDamage` from
  `OnWeaponHitCharacter`, rolled on the attacker's game, and every game cancels 0-damage hits on masters; the server
  sends every client the masters' online IDs and chances. Never register a `Hook.WeaponHitCharacter`: Java ignores
  the Lua return and skips every weapon hit while any callback exists), `client/*_UnfazedRunner.lua` (Freerunning's
  Unfazed Runner, 2026-11-10, "Tree Runner" before: from `OnPlayerUpdate`, which fires before the sprint input, the
  tree trip check and `separate` in `updateInternal2`: `setAllowSprint(false)` near tree / hedge squares and for the update a solid character is within touching reach,
  so `separate`'s bump is a stagger, not a fall; others in reach made not solid while it plays. 0.4.3 passed through
  characters instead; the user wants the stagger, with the sprint kept (2026-11-12). The sprint used to stop after
  the stagger because Toggle to Sprint is cleared by `IsoPlayer` (~2425) when the stagger's movement block zeroes the
  move direction; `setForceSprint` / `setForceRun` put it back after the stagger while a movement key is held. `BumpFall`
  cannot be cleared after `separate`: the bumped state is entered in `postupdate` with no Lua event between. A tree-scratch
  undo was built and dropped the same day: the user wants the scratches and tears kept),
  `shared/*_WeaponsShared.lua`
  (jams via HandWeapon's class-table `checkJam`; tree damage taken off `IsoTree:setHealth` before vanilla's hit,
  since `getTreeDamage()` includes sharpness and the script has no getter), `shared/*_Repairs.lua` (careful
  repairs; lasting repairs removed 2026-11-08, user; around `FixingManager.fixItem`'s callers; stronger patches via `addPatchForSync` at Tailoring
  10 x 1.5, vanilla's condition gain kept in modData `TSM_PatchGain` because the rebuilt patch has none),
  `client/*_Movement.lua` (strafe / sneak / run / sprint position nudge; it must add to `setNextX/Y`, since root motion is
  already in the next position when `OnPlayerUpdate` fires and `setX` overwrote it: a stop-start stutter until
  2026-11-12). (`client/*_BuildNoise.lua`, Construction's building noise,
  removed 2026-11-11, user: it stacked with Stealth's Quiet Work, which covers building.) Extended: Combat (fire rate: shoot speed variables + recoil-delay drain floored at
  150 ms per shot for `AntiCheatHitWeapon`; Gunworks via its `getWeaponRPM` during `canFire`; Knifework's melee-delay
  drain; stomp via the shoes' `setStompPower`; Executioner finds the close-kill target itself because
  `AttackVars.closeKill` has no getter), Physical (sneak-run endurance, recovery, muscle strain, wear undo over both
  hands and marked worn items, animal stress, crash safety from `OnPlayerGetDamage` "CARCRASHDAMAGE"), Crafting
  (torch fuel, charcoal back, ore yield, craftsman's mark modData `TSM_Mark` / `TSM_MarkBy`, lasting food), FirstAid
  (sparing disinfectant), Welding (scrapping torch fuel), Cooking / FarmAnimals (lasting food: evolved dishes once
  per dish, `TSM_Lasting`; meat through a `modifyMeat` wrap during `giveMeatModified`), Foraging (keen eyes:
  light, weather and moving penalty multipliers eased toward 1). `M.stretchFood` / `M.resendItem` in the core.
  Second harness file `tests2.lua`: 13 checks (safe-fall caps per level and drop, relay amounts, Executioner per
  level, food stretching).
- Phase 3a (same day): signature abilities that hook vanilla systems. Kind "sig" in the core (`M.sig`,
  `M.hasSignature`: picked and members at 10, on at mastery 0, fixed value); the panel lists them by name (no
  "Signature:" prefix since 2026-11-08), unlocked / unlocks when picked. Built: Heavy Load one level lower (since 2026-11-08 for every effect: the
  max weight is raised so the moodle itself reads one level lower, `shared/*_HeavyLoad.lua`, server through
  `maxWeightDelta` with CarryWeight, client `setMaxWeight` per update, Lua `IsoPlayer:getMaxWeight` and the main inventory's
  `ItemContainer:getMaxWeight` wrapped on every side to return the real max (weight label, pickup timers); the server keeps each player's original delta, since subtracting from the stored float drifted its max 1 kg below the client's (2026-11-09); replaced the per-effect give-backs: +0.07 combat speed, drop factors, regen at 2); masterwork (smithing recipes mark every output at
  15%, `TSM_MarkKind`; since 2026-11-08 `carryMasterwork` passes it through later recipes for a master crafter only,
  from a single-piece input, head-only `TSM_MarkPart` on weapons with head condition, `M.markChance`; the same day Handicraft's
  `CraftsmansMark` bonus became the signature `SigCraftsmanship` and passes on the same way, a handle mark in its own
  slot `TSM_HandleMark`, see "Maker's marks" in Crafting.lua; marks show in item tooltips,
  `client/*_MarkTooltip.lua`, TienBagUpgrades' after-the-chain pattern); every signature has a 1-2 word name
  (`IGUI_TienSkillMastery_SigName_<def name>`, shown as "Name: description" in the panel and the README, user's picks); planks / stones (`Actions.addOrDropItem`; planks always since 2026-11-08; Clean Breaks also gets the mod's
  first script recipe, `media/scripts/TienSkillMastery_recipes.txt` TSM_BreakFlatStone, FlatStone -> 3 Stone2, gated by
  `TienSkillMastery_FlatStoneMenu` (OnAddToMenu, a plain global: `callLuaBool` cannot follow dots) and `.FlatStoneTest` (OnTest, also on the server)); choice cuts (`modifyMeat` wrap, `M.butcherBonus` with Lasting Food; since 2026-11-09 all food from butchering, every `addAnimalPart` route plus recipes giving Butchering XP, heads and fish guts excepted, not played; since 2026-11-08 hunger x1.1, so meat is
  also 10% heavier: Food weight follows hunger, and nutrients x1.3; x1.15 for all before); `server/*_HuntingTraps.lua` (trap modData `tsmTrap` / `tsmDouble`
  through `fromModData` / `toModData`; no `checkDestroy`; `animalAliveHour` / 4; second hand-over in
  `removeAnimal`); Fieldcraft (`checkShouldDisable` without the zombie / running tests; red dots in `OnPreUIDraw`);
  `shared/*_Signatures.lua` (run-and-gun `stopOnRun = false` and quickdraw maxTime / 4 + animSpeed x4 in
  `ISBaseTimedAction:create` by `self.Type`; quickdraw also lowers `maxTimeInit`, a `new` parameter name, so the
  MP server rebuilds the action with the short time; the put-away of whatever is in hand before a pistol draw is
  quick too (user, 2026-11-07: `ISHotbar:equipItem` is marked while it queues it, since the put-away begins before
  the draw is queued; plus a 3-action look-ahead in the queue); deft hands via
  `ISBaseTimedAction:adjustMaxTime` x0.9). **Never wrap a timed action's `new` here**: Gunworks (and Hot Brass)
  replace the reload actions' `new` with extra parameters (`gunworksRackPhase`, `gunworksReloadStep`, `ammoLimit`,
  `ammoTypeOverride`, `gunworksReloadAiming`), and the MP server rebuilds an action from the outermost `new`'s
  parameter names; the first version wrapped them with vanilla's names and Gunworks reloads looped (rack, rack,
  reload again; reported 2026-11-07). Running still restarted the reload: the `run` / `sprint` action states have no
  `to_actions.xml` and no `actions` child tag (idle and walk do), so the reload clip's substate is dropped and
  re-entered from frame 0, and single player advances the reload on the clip's events. **Action groups cannot be
  modded** (`ActionGroup.load` reads only `ZomboidFileSystem.getMediaFile`, the game folder; mod files there are
  never read). So in single player a master's reload is driven by time like an MP server: after `start`, the
  action's own `serverStart` runs with `emulateAnimEvent(Once)` swapped for Lua timers (real ms), `netAction` is a
  stand-in, the timers fire `animEvent`, and the animation's copies of those events are ignored. The clip still
  cannot play while running; restore
  (`shared/*_RestoreAction.lua` + `client/*_Restore.lua`, `FixingManager.useFixer` of the first fixer, then
  `setHaveBeenRepaired(0)`); the lunge (Combat: knife min **and** max range raised to the reach, 1.5 tiles, while 0-1
  chasers; vanilla values kept per hand item and put back, and on `OnSave` because `HandWeapon.save` writes a max
  range other than 1.0; until 2026-11-08 only min range x1.5, which `calcValidTargets` capped at the knife's max range
  ~0.9, so the lunge only moved the player for targets 0.61-0.9 away; moved toward the target at up to 5 tiles a second
  for at most 0.4 s, diagonal steps allowed, a blocked step slides along one axis; the target is vanilla's own, the standing zombie at
  the `TargetDist` variable `pressedAttack` sets just before `OnWeaponSwing` (an own search missed far jaw stabs);
  Executioner's close-kill test uses it too; a purple outline on it was tried and dropped 2026-11-08); `client/*_FishFinder.lua`. Third harness file `tests3.lua` (14
  checks: signatures at mastery 0, inactive, the trap wrappers against a mock `STrapGlobalObject`). The harness needs
  `unpack = table.unpack` for Lua 5.5.
- Phase 3b, first part (same day): the relay grew zombie actions (`zombieAct` -> server: signature, distance, and
  push back's 0.01 endurance per zombie taken there -> `zombieActApply` to the owner; applied next tick, never inside
  the hit): Bludgeoning's push back (cone noted at `OnWeaponSwingHitPoint`, the ones `OnWeaponHitCharacter` did not
  report are staggered: attack position, hit force 0.6, hit dir, `setStaggerBack`, "wasHit") and Swordsmanship's
  hamstring (`knockDown(false)` + `setBecomeCrawler(true)` + `setCanWalk(false)`). Hamstring falls inside the
  hit since 2026-11-08 (user: the zombie froze in its hit reaction, then fell; the actiongroup takes the knockdown only
  with no hit reaction playing): in `OnWeaponHitCharacter` the attacker's client makes the zombie `alwaysKnockedDown`
  (plus become crawler, cannot walk) and puts the flag back next tick, so vanilla's own line right after the event
  (`IsoZombie` ~4238 `setKnockedDown(isCriticalHit || isOnFloor || isAlwaysKnockedDown)`, for an owned zombie or SP;
  the hit packet carries it) knocks it down in that hit; the relay's later act only knocks down one not yet falling. `shared/*_EngineOverhaul.lua` +
  `client/*_EngineOverhaulMenu.lua` (quality +1 per Engine Parts, power by vanilla's spawn formula, never lowered,
  vanilla spawn loudness then `updatePartStats`, `transmitEngine`). `shared/*_Scrap.lua` + `client/*_ScrapMenu.lua`
  (any car through vanilla's ISRemoveBurntVehicle with a server re-check of the signature and guards; part items by
  type pattern, `M.SCRAP_PARTS` yield table). Fourth harness file `tests4.lua` (17 checks: part table, guards, the
  wrapped complete, push back's endurance).
- Phase 3b, second part: `shared/*_Triage.lua` + `client/*_TriageMenu.lua` (plan rules in `M.Triage.plan`: since 2026-11-09 the goal is the fewest actions that stop health loss, chosen by `T.actions` from the wounds and supplies: stitch with a suture needle, else bandage for now, and every later triage looks again, on bandaged parts too; a fracture alone only a splint; a stitch gets no bandage (user: infection can wait, the point is to stop health loss now and avoid death); another
  player's plan from the server, which also borrows the doctor's missing supplies from the patient and gives the
  unused ones back after the queue: `triage` / `triagePlan` / `triageReturn`; the client queues once the borrowed
  item IDs are in its inventory or after 3 s). Since 2026-11-08 (user; played): key binding `TsmTendWounds` (default
  comma) and "Tend wounds: everyone nearby" tend you and everyone in reach as one list: anyone under
  `T.CRITICAL_HEALTH` (25) overall health first, then by `T.drain`, each part's treatments together, walking between
  patients; a patient's lent supplies go only on that patient; infected parts are bandaged too (skipped before); a
  patient moving does not stop a treatment while within `T.TEND_TILES` (2) tiles along each axis, same floor; a patient
  farther off, dead or gone from the server is skipped and the rest carry on (per action `begin` / `isValid` / `stop`,
  header of the menu file). Scratchpad `triage_harness.lua` / `triage_tests.lua` (real files against mocks, not kept).
  Passive `StitchPain` (user, 2026-11-08, played): -75% at mastery 10, in `shared/*_WorkshopFirstAid.lua`.
  Second signature `SigNeedlework` (user, 2026-11-08, played; Field Medicine's Tailoring side): recipes TSM_MakeBandage
  (2 ripped sheets, one use of `base:thread`, a `base:sewingneedle` kept with MayDegradeLight) and TSM_MakeSutureNeedle (tags `base:sewingneedle` + `base:thread`, the needle is used up), gated
  like the flat stone (`TienSkillMastery_NeedleworkMenu`, `.NeedleworkTest`). `client/*_Fields.lua` + `shared/*_FieldAction.lua` (two `ISSelectCursor` picks, at most 15 x 15,
  the first corner tinted yellow; tend = water / the four cures / first fertilizer / harvested plots removed with a shovel, sow = one seed item per plowed square. User, 2026-11-09: one
  timed action per kind of work per 3 x 3 block, as long as the slowest single plant, materials and back strain still
  per plant; a shared action whose server `complete` re-checks each plant and runs vanilla's `complete` for it, so the passive wrappers and
  Zomboid Fixes' water cut still apply. Walks to the middle of each block, crop or not (user, 2026-11-09). Players do not damage crops in 42.21 (only zombies and vehicles reach `destroyFarmingPlant`), so no
  trampling passive is needed; `avoidFarmingPlants` on player paths is read only by the native pathfinder, untraced: **in-game check owed**, can a walk end on a crop (a refused path resets the queue).
  Checked against mocks with vanilla's real action files, not played). Passive `MilkTime`
  (user, 2026-11-09, -15%, `shared/*_FarmTimes.lua`, not played). Second signature `SigWhisperer`, Animal Whisperer (user, 2026-11-09, not played;
  `server/*_FarmAnimals.lua`): flat -1 stress every 10 game minutes (`EveryTenMinutes`) to the master's pen, connected zones and hutches included, once however many masters.
  Also in the block action (user, 2026-11-09; Dig furrows played once, as reported below, its fixes and Remove plots not; digging tool required, the options hidden without one): "Remove plots" (dead / rotten / destroyed, picked area) and "Dig furrows" (`server/*_FurrowCursor.lua`, rake-style 3 x 3 cursor that stays until cancelled, one action of 110 per click; `ISPlowAction:complete` removes any plant it finds, so the server's `canFurrow` re-checks). Strain and worms stay per square. Sight only validates the click, never picks squares (`tryBuild` runs `walkTo` + `create` in one call, so a per-square sight test sees from the click spot: 4 dug of 9, reported 2026-11-09). Field work always walks, cheats too: `tryBuild` skips `walkTo` under Build Cheat, so the cursor queues its walk in `create`, and `FIELD_REACH` on the server silently drops anything farther.
  World menus (user, 2026-11-09, not played): the field options sit in a "Homesteading" submenu, on a clicked crop or furrow, plus diggable ground with a tool (Dig furrows only there). Triage has no world menu any more, the key only (same day; a menu only for the wounded was built and dropped, needing the server to send each master who is wounded, since a client cannot read another player's body). Battering ram ("bowl them over" until 2026-11-08; `SigBowlOver`, relay kind "bowl") in
  `client/*_Movement.lua`: the
  nearest standing zombie within a tile, from any direction, is set as `setBumpedChr` (vanilla bumps, and so
  trips, only a character that is not the last bumped one, `IsoMovingObject.separate` ~1221, on contact from any
  angle; the first version's ~70 degree cone in front let zombies standing still, brushed at an angle, trip the master:
  2026-11-08) and, once within 0.65 tiles (contact), knocked down through the relay (kind "bowl", 0.02 endurance;
  relay costs are `R.COST`). `setBumpedChr` holds one character, and two zombies still tripped the master (the
  first, still staggering, stayed the nearest), so every standing zombie within 0.8 tiles is also made not solid for
  that update: `isSolidForSeparate` is false while `solid` is false (`IsoMovingObject` ~1174), so vanilla bumps none of
  them; `IsoZombie` sets `solid = true` in its own update (~3407), it is set from `OnPlayerUpdate` (inside the
  player's update, before its `separate`) every update and given back at once out of reach. Each zombie in contact is
  knocked down (2 s each). On up to the first endurance moodle (a warning; user, 2026-11-08, was none at all).
  `tests14.lua`.
  Zombies getting up are no risk (`IsoZombie.isSolidForSeparate` is false in `ZombieGetUpState`). Fifth harness file `tests5.lua` (triage plan order and
  rules, borrowing, giving back).
- Phase 3b, throws: `shared/*_Throw.lua`. Only the throw key throws (below). The first trigger, a swing at a zombie
  beyond reach (`OnWeaponSwing` + `getAttackTargetSquare()`, `OnWeaponSwingHitPoint` sending `throwWeapon`), was
  dropped 2026-11-07: the user kept throwing the axe with the attack button. Targeting (2026-11-08) is vanilla's melee way: while
  aiming, `IsoPlayer.setAngleFromAim` turns the player every update toward the pointer's tip projected at chest
  height (`calculateAimVector`: `AimingReticle` = mouse x zoom, `XToIso` / `YToIso` at `getAimOriginPosZ` = z +
  `getChestHeight()` 0.495), so the facing runs through a body the pointer is on, and melee takes targets in a cone
  around that facing (`CombatManager.getNearestMeleeTargetPosAndDot`, dot vs `MinAngle`). `aimTarget` takes the first
  target along `getForwardDirection()` within `Th.AIM_RADIUS` (0.6 tiles) of the line, 0.5 .. range tiles out; a
  throw at empty ground goes to `Th.aimPoint` (`screenToIsoX/Y(num, mouse, z + chest height)`, the same projection).
  Earlier tries: the floor square under the mouse (lies a tile or two behind a zombie aimed at chest-high) and an
  on-screen body box (`isoToScreenX/Y`), which followed the pointer's tip, at the top of the iso cursor. Range 12 tiles (axes one-handed only;
  spears 10 until 2026-11-08, now the same as axes in every number: user, same distance and harder). The server re-checks hand
  item ID, category and signature, resolves the flight at once: aimed in a straight line from hand height (0.55
  levels) at the target's head (0.65) with gravity (the game's 5.0010414 levels/s^2) pulling it down, 22 tiles a
  second (spears 20 until 2026-11-08) (user, 2026-11-07: aim for the head, gravity arcs it down); 0.2-tile steps, `isBlockedTo` walls,
  the floor (lands short), first standing zombie within 0.45 while below 0.8; the height there picks head (>= 0.55,
  x3) / body / legs (< 0.2, x0.05), vanilla's `CombatConfigKey` head / leg factors. With these numbers a straight throw hits the
  head to ~4.4 tiles and the floor at ~11; since 2026-11-08 (user: outlined targets were not reached) a throw at a
  target aims above it by part of the drop (`Th.launchAim`: it arrives no lower than `Th.ARRIVE_MIN`, the body at
  0.35 for people, the full correction for animals), so anything outlined within 12 tiles is reached (head to ~4.4,
  body beyond), and `aimTarget` drops a target with a wall or closed door in between (`Th.pathClear`, the flight's
  own steps). The raised arc can pass over a zombie in between (above `ZOMBIE_TOP`). `tests11.lua`.
  Postures (user, 2026-11-08: sitting and lying zombies could not be targeted; the first version skipped any
  `isOnFloor()` zombie): `Th.postureOf` = "down" (`isOnFloor`: knocked down, crawling, fake dead), "sit"
  (`isSitOnGround` / `isSittingOnFurniture` / a zombie's `isSitAgainstWall`) or "stand", tops 0.15 / 0.4 / 0.8; low
  targets are aimed at their own height (sitting 0.85 of the top, lying 0.6) with the full drop correction, a sitting
  one can take a head hit (from 0.75 of its top), a lying one body hits only, and neither is staggered. Players
  (PvP) the same.
  Low fences (user, 2026-11-08: no throwing over a fence): `isBlockedTo` (`IsoGridSquare` ~932) = `isWallTo` or a
  blocked window / door / stair side, and a low fence's edge is a wall to it. `isHoppableTo` marks low fences
  (`IsoObject.getHoppableDirection`: sprite flags HoppableN / HoppableW) and empty window frames; tall fences have
  TallHoppableN / W instead. So the flight's `blocked(a, b, h)` lets a hoppable edge through while the throw is above
  `Th.FENCE_TOP` (0.4 levels, ~1 m), and the outline's `Th.pathClear` follows the same arc (`launchAim` at the
  target) so it never shows a target the fence would stop. A low target right behind a fence stays out of reach: at
  22 tiles a second the arc cannot clear 0.4 and come down to a lying zombie within half a tile. Thrown axes and spears deal x1.5 (`Th.THROW_DAMAGE`; user, 2026-11-07:
  farther and harder; spears x1 until 2026-11-08). All are `Th.*` constants. Then it takes the weapon
  out, deals its damage roll x the mastery's damage x the part factor through the relay (owner;
  else local with `Kill(thrower)` at 0) plus a stagger (`R.queueAct`, no endurance); every throw, hit or miss (user, 2026-11-07), rolls vanilla's melee
  wear (1 in ConditionLowerChance + Maintenance + skill / 2, one point; WearUndo and the mark can cancel it, since
  Physical's per-tick undo only sees held items); drops it at
  the end, broadcasts `throwFly` (clients draw it with `Render3DItem`, whose last argument is the world item's yaw in
  degrees and is **ignored when negative**: `ItemModelRenderer` then uses the item's resting rotation, so an
  `atan2` angle must be brought into 0..360 (it drew spears side on for half the directions, 2026-11-08). Axes turn as
  they fly; spears keep yaw = atan2(dy, dx), which points a vanilla weapon mesh's tip along the flight: the mesh tip
  is model +Y, `init`'s weapon fix rotateXYZ(0, pi, pi/2) lays it to +X, and the world frame (`WorldModelCamera`
  Ry(-pi), `DoPushIsoStuff` scale(-1.5) + Ry(pi), frame X = world -x, Z = world -y) puts it at (cos, sin) of the yaw;
  `Th.SPEAR_YAW` stays for a mod spear modelled otherwise).
  Axe tumble (user, 2026-11-08: end over end, not flat): `Render3DItem` is the only Lua call that draws an item model
  in the world, and its live model path takes only the yaw (with a rotation >= 0 `ItemModelRenderer` zeroes angle.x
  and angle.z); no 3D renderer is exposed (only `SpriteRenderer`). With rotation -1 it uses the item's own
  `worldXRotation` / `worldZRotation` (yaw) / `worldYRotation` (angle.x / y / z) through the world item atlas
  (`DebugOptions` WorldItemAtlas Enable, debug-only and true by default; vanilla's Extended Placement tilts use it):
  one baked picture per model + angles (`WorldItemAtlas.getItemKey`, shared across items, baked a frame after first
  asked). `isDoingExtendedPlacement` skips the atlas but queues an `ExtendedPlacementDrawer` that dereferences the
  item's world object (none on a flying copy). So `Th.AXE_FLIGHT` "tumble" rounds yaw and tumble to 22.5 degrees
  (16 x 16 pictures per axe model) and sets worldYRotation = -(t x TUMBLE_RATE): the laid-down tip (+X) turned by
  Rz(z) is (cos z forward, sin z up) in the world, so a falling angle carries the head over the top. "still" and
  "flat" are the live model. `tests12.lua`.
  Blade first (user, 2026-11-08): the edge must lead the tumble. Survey of every vanilla one-handed axe mesh (the
  `.X` files): handle along mesh +Y, blade edge toward mesh -Z (the 0-thickness end of the head), but the model
  scripts' `world` attachments differ (HandAxe, HandAxe_Old, IceAxe, cleaver, scythes 180 0 180; the forged ones 0 0
  0; bone / scrap ones small Y tilts), and `ItemModelRenderer.init` multiplies that attachment in inverted after the
  weapon fix, so the same edge lands on opposite sides. `Th.bladeBody(model)` reads the attachment
  (`getModelScript(item:getWeaponSprite()):getAttachmentById("world"):getRotate()`, `v:x()`), carries handle and edge
  into the laid frame (inverse rotateXYZ, then (x, y, z) -> (y, x, -z)) and builds B (handle +X, edge -Y);
  `Th.tumbleAngles` decomposes Ry(yaw) Rz(tumble) B into the renderer's Rx Ry Rz (world X / Z / Y rotations).
  Mod axes modelled with the edge elsewhere would fly edge-sideways (not checked). Sixth harness file `tests6.lua` (4 flight
  checks against a mock grid).
  Throw key (user, 2026-11-07): a vanilla key binding `TsmThrowAxe` (section `[TienSkillMastery]`, default Space,
  appended to `keyBinding`, tested with `getCore():isKey` in `OnKeyStartPressed`), only in combat stance
  (`isAiming()`), throws `Th.throwable`: a carried one-handed axe or spear (spears added 2026-11-08) of a signature
  the player has, without equipping it: loose in the main inventory first, then one on the hotbar, never from bags
  (`Th.findCarried`, sent `carried`); only with none of those the primary hand item (sent as held; user, 2026-11-08:
  spares before the held weapon). Aim: the zombie whose on-screen body holds the mouse, else the floor
  under the cursor (`ISCoordConversion.ToWorld`), clamped to 12 tiles. Space is vanilla's Melee key: `IsoPlayer`
  (~2508, on foot) starts a shove on **every update the key is down** unless `bannedAttacking`; a `WeaponSwing` hook
  returning true only reverts `SwipeStatePlayer`, the shove animation still plays (seen in game 2026-11-07, twice
  while held). Keys are read (`GameWindow.logic`: `GameKeyboard.update` → `OnKeyStartPressed`) before the players
  update in that frame, so the press sets `setBannedAttacking(true)` (old value restored once the key is up and no
  throw is queued) and queues the client-only `TienSkillMasteryThrowAction` at once (`stopOnAim = false`; plays `AnimSets/player/actions/TsmThrowAxe.xml`
  = `Bob_AttackThrowMolotov`, 1.47 s, at speed 1.6, with a `TsmThrowRelease` event at 0.3 = vanilla's release point,
  ~0.28 s in; action 45 units ≈ the whole clip; a job-delta release at 0.6 only as a fallback: the first version
  released at 0.35 of 30 units, before the arm got there, reported 2026-11-07) with the axe as the
  hand model; the release sends `throwWeapon { carried = true }`, and the server takes the axe only from the main
  inventory itself (`getItemById`, container check), detaches it from the hotbar (`removeAttachedItem` + slot fields)
  and resolves it like a held throw. Marker: first a drawn copy of vanilla's aim reticle (`IsoReticle` is not
  exposed; `media/ui/Reticle/aimCircleNN.png` + `crosshairXY.png`, texture / 16), dropped 2026-11-08 as ugly; now the
  target under the cursor gets an outline in a per-player mod option colour (`client/*_Options.lua`, `M.throwOutlineColor`, default
  `M.OUTLINE_COLOR` purple; amber until 2026-11-08) set from `OnPreUIDraw` every frame:
  `IsoMovingObject.renderlast` clears outlines each frame unless set during that frame's UI update / render
  (`FBORenderObjectOutline` UI times), which is how vanilla's melee outline (`CombatManager.highlightMeleeTargets`)
  stays on. `tests9.lua` (order, combat stance only, attack ban held and restored).
  Targets (user, 2026-11-08): zombies, loose animals (`square:getAnimals()` near the point; `IsoCell.getAnimals()`
  builds a new list per call) and players under vanilla's PvP rules, written out in `Th.pvpAllowed` because the
  Java `CombatManager.checkPVP` does its checks only on a client (on a server it returns the co-op flag): PVP
  option, god mode, both safeties on (SafetySystem), non-PvP zones, same faction unless either has faction PvP;
  invisible players are skipped. Animals have no height in their definitions (`collisionSize` is a width), so
  `Th.ANIMAL_TOP` guesses one per type; throws aim at 0.6 of it and fly over an animal while above its top.
  Hits: animals through `IsoAnimal.hitConsequences(weapon, thrower, false, damage, false)` (server / SP: health x
  `getHealthLoss(0.025)`, wild flee, hit reaction, `killed(player)`, stress, attack back; AnimalPacket syncs);
  players through `BodyDamage.DamageFromWeapon(weapon, part)` on the server (vanilla's PvP wound: clothing defense,
  wound type, weapon damage x15, head / neck x4, upper torso x2, PVPMeleeDamageModifier; no thrower condition, as
  vanilla's PvP; a null "using player" is safe), logged with `print`. `tests10.lua` has a hen.
  Arrival (user, 2026-11-07: damage came before the axe got there): `Th.resolve` still works out the path at the
  throw, takes the weapon out and rolls wear, but the hit and the landing go into `Th.inFlight` and an OnTick (server
  / SP; 100 ms server ticks) applies them at throw + distance flown / speed, the time clients draw the flight over.
  The zombie must still be alive and within `Th.TRACK_RADIUS` (1 tile) of where it was headed, else a miss.
  `tests10.lua`. Condition (user, 2026-11-08): `Th.conditionDamage` puts vanilla's melee factors on the roll
  (`CombatManager` ~957-1090: `getDamageMod` skill, `getHittingMod` Strength, arm pain Hand_L..UpperArm_R > 10 divides
  by pain / 10, `getTraitDamageDealtReductionModifier`, Panic / Stress > 1 minus 0.05 a level = vanilla's 0.1 on its
  damageSplit, which is the roll x2 for a first hit, Endurance and Tired x0.5 / 0.2 / 0.1 / 0.05); the reach factor
  and multi-hit split are a swing's and left out. Hands: `resolve` clears only a hand holding the thrown weapon (it
  cleared the primary on every throw, so a carried axe unequipped the held weapon; reported 2026-11-08). Sounds (user, 2026-11-07): the key throw's release plays the weapon's `getSwingSound()` with
  `character:playSound` (an MP client relays it itself; the held throw is a real swing and has vanilla's); a hit on
  arrival sends `throwHit` to every client (`Th.playHit`: `getZombieHitSound()`, the script's `HitSound`, through
  `playSoundImpl` on `getWorld():getFreeEmitter(x, y, z)` at the target, played before the damage). Not on the
  target's own emitter (tried 2026-11-08, by `findZombie` / `getAnimal(onlineID)` / `getPlayerByOnlineID`): a
  character's sound waits in `toStart` until that character's next update, and a target the hit kills is a corpse
  by then, so a killing hit was silent (only the death sound was heard); `IsoWorld` ticks its `currentEmitters` and
  returns them to the pool once their sounds end.
  Emitter calls differ by kind (both failed in game 2026-11-08): a world emitter (`BaseSoundEmitter`, e.g.
  `getFreeEmitter`) has `(String, IsoGridSquare)` and `(String, IsoObject)`, and Kahlua sent a two-argument nil to the
  square one (NPE on `square.x`), so call `playSoundImpl(name, false, nil)`; a character's emitter
  (`BaseCharacterSoundEmitter`) has only `playSoundImpl(String, IsoObject)` and refuses three arguments ("expected 2
  arguments, got 3"), so call `playSoundImpl(name, nil)`.
  Hit surface (2026-11-08, spear hits unheard while axe hits were): vanilla sets the attacker's `MeleeHitSurface`
  (`ParameterMeleeHitSurface`, Body = 1, Default = 0) before playing `HitSound` from the attacker; a target's emitter
  has no such parameter, so the throw sets it on the played sound (`setParameterValueByName(handle, "MeleeHitSurface",
  1)`; a just-played sound waits in `toStart`, where the value is queued). Whether the spear events really go silent
  at Default is a guess from that difference, not traced in the FMOD banks.
- Throw sync fixes (2026-11-08, from reading the code; not yet played on a server). Carried throw: the hand model is set
  before `setActionAnim`, because `PlayerActionsState.enter` captures the override and model for other clients at that
  moment (`HandWeapon.getStaticModel` falls back to the weapon sprite, so the name is good). Kills: `creditKill` adds to
  the server's copy and tells the thrower (`throwKill`), since vanilla only counts inside a hit's own code
  (`hitConsequences` ~6219); in MP a kill is judged from the server's copy of the health against
  `min(amount, R.MAX_DAMAGE)`, and `setAttackedBy` gives the corpse its killer. Stagger: `R.show` broadcasts
  `zombieActShow` (kind "pushback": thrown hits and Wild Swing), and each client sets the flag on its remote copy, as
  vanilla's hit packet does (`fields/hit/Zombie.process`); the owner's ZombieStagger still moves it. Since 2026-11-09 (user, not played): "bowl" too (`R.SHOWN`; `knockDown` sets what the hit
  packet sets, and the fall states run on the remote copy; simulator's own `isKnockedDown` jump to on-ground is at zombie creation only). The
  server's `isOnFloor` is not fed by ZombiePacket (`NetworkZombieVariables`: reanimated players only), so `Th.postureOf`
  also reads `zombie:getRealState()` (falldown, onground, getup, fakedead; sitting) and `isCrawling()`, both in every ZombiePacket.
  Animal and player targets flinch on every client from `throwHit` (`Th.showHit`, sent now for a weapon with no hit sound too):
  animal `setHitReaction("hitreact")` + blood; player `IsoPlayer.hitConsequences`' PvP lines ("HitReaction", `washitpvp`, `hitpvp`, hit force, from behind) + blood. Checks: `throwsync.lua` (server + client mocks, 21 checks, session scratchpad, not kept).
  Old harness files `tests.lua`, `tests3-5.lua` already fail on checks these fixes do not touch (same failures with
  the committed Throw and Relay).
- Two repair systems raise an item's repair count (traced 2026-11-08, reported on an axe repaired with zip ties):
  `Fixing` scripts (`fixing.txt` / `vehiclesfixing.txt`: firearms and vehicle parts only) and craft recipes
  (`recipes_fixing.txt`, `genericFixer`: tools and melee weapons, the count rising on failures too). Restoration and
  careful repairs read only the first until then. Now restoration offers each usable repair recipe, charging its
  consumed inputs (`M.repairRecipes`, `M.restoreOptions`), and careful repairs also run after repair recipes
  (`M.afterRepair`). Restoration clears the count and fills the condition for 3 repairs' worth (`M.RESTORE_COST`, user,
  2026-11-08; head condition and sharpness left alone). Restoration played; careful repairs after repair recipes not yet.
- Savory Meals (user, 2026-11-08, Provisioning's second signature, played): food a master finishes with heat
  causes 80% less unhappiness, flat, boredom untouched; not butchering, not putting dishes together, not recipes (user
  dropped those the same day). Through `OnCooked`, set on every food script by `DoParam` at `OnLoadMapZones` with the old
  value chained; the cook is vanilla's `chef`, which `*_DeftTransfer` now sets too (before, a Deft Hands master's food
  earned no cooking XP). The saved field is what is cut, so stale / rotten / burnt penalties build on the lower value (a
  rat: 6, 16, 26), as the user asked. Header of `shared/*_WorkshopCooking.lua`.
- Phase 3c: spare materials (`ISBuildingObject:updateModData` wrap in `server/*_CraftingBuild.lua`: rolls per new
  `need:` unit, drops the spared items and lowers the count, so dismantling never pays back the saving); tuned engine
  (`client/*_TunedEngine.lua`, driver's client, power / max speed x f, vanilla values per vehicle, re-boosted when the
  server or an overhaul changes them, restored on leaving the seat and before `OnSave`); extra output (Crafting,
  vetted `EXTRA_OUTPUT` recipe names); bait digger (`forageSystem.getCategoryBonus` + points for "FishBait" /
  "Insects", vanilla's specialisation lever); big haul (`server/*_FishingNets.lua`: a second run of
  `fishingNet.checkTrap` for the bonus share of the hours, at most 5, so no break roll and no extra bait).
- **Open questions for the user** (2026-11-09):
  - Settled 2026-11-10: the server runs `updateFalling` for every player (header of `shared/*_Falls.lua`, which now
    also keeps the cap one update's step under the threshold, for fast forward). Salvaging still needs a design decision.
- **Carved spears** (user, 2026-11-09, not played): `Spearcraft.CarvedDamage` +8% and `CarvedReach` +3% replaced
  `SpearCondition`, a +2 that did nothing (Carving 10, a member skill, already fills carved and fire-hardened spears). Any
  spear from a recipe listing Carving (vanilla: CarveSpear, FireHardenSpear; stone, bone, knife and other bound, wired or taped
  spears and assembled ones list Maintenance) gets them, fixed when made, for whoever uses it (saved and synced); same wooden
  model. A plain bonus, no forged spear in the formula, with values set to land near forged (user): at mastery 10 carved
  averages 1.296 damage (forged short 1.30), fire-hardened 1.35 (forged long 1.45), reach 1.442 (1.45, 1.48). A lifespan mark and
  lowering fire-hardened's crit were offered and declined, so lifespan stays vanilla (60 / 98 wear rolls against forged's
  200 at Spear 10, Maintenance 5) and fire-hardened keeps its vanilla crit (30%, x10 against 20%, x5), which already
  out-damages forged on average. Header "Carved spears" in `shared/*_Crafting.lua`.
- **Decided** (user, 2026-11-09): Hunting's `PartCount` (`server/*_FarmAnimals.lua`, `addAnimalPart` wrap) skips parts
  with a fixed `nb` in `AnimalPartsDefinitions` (all 26 are anatomy or a whole carcass; it used to give a third foot at 20%,
  a second whole chicken at 10%); ranges and meat definitions still scale. So poultry, rats, mice and small birds get only
  extra bones from it. The test is `nb > 0`: vanilla writes `nb = -1` into the shared definition on first use. Checked
  against a port of vanilla's `addAnimalPart` (lupa, not kept), not played. Labels now say what they do: "meat, sinew and
  bones", and "better cuts" for `PartChance` (`getPartChance` splits meat among prime / medium / poor cuts).
- **Torch Fuel on builds** (user, 2026-11-09, not played; `server/*_CraftingBuild.lua`): the 40 build-menu entities that burn
  a blowtorch get it too. Corrects an earlier note here: Java `BuildAction.perform` only fires `OnProcessAction("build")`;
  Lua's `ISBuildIsoEntity:create` consumes through `buildPanelLogic:performCurrentRecipe()`, so it can be wrapped. In-game
  check owed on a server: vanilla sends the torch during `create` (`sendItemStats`, `syncItemFields`, reliable, and our
  `SyncItemFields` is unordered), so confirm the client ends on the returned uses.
- **Not built**: Freerunning's vault / wall rolls. Stealth's distraction throw, lose them and unseen were built
  2026-11-11; its older quiet hands plan gave way to the noise rework the same day.
- MP checks owed (from reading only): whether stomp's
  `ItemBodyLocation.SHOES` lookup works from Lua, `OnWeaponHitCharacter` on the attacker for a remote zombie, the
  strafe / sneak nudge feel, Gunworks bursts with the RPM wrap (where combat muscle strain lands in MP: traced 2026-11-08, on the
  server, see Physical.lua's header); for 3a:
  reload animation while running, quickdraw look, the lunge distance and feel, fish
  counts between clients, a second live animal from a double catch, triage's merged queue with two patients; for 3b: whether a Lua-set stagger / knockdown
  on a zombie is picked up outside a hit, the crawler getting up, the engine state reaching clients after
  `transmitEngine`, triage's item arrival order and bandages on another player, the area picker's cursor, whether
  `setBumpedChr` set before `separate` really stops the sprint trip; for the throws and 3c: the swing reaching
  `OnWeaponSwingHitPoint` with no target in reach, the flight visual, tuned engine against the vehicle anti-cheat,
  whether the build's `need:` counts really become the thumpable's build materials.
- forum.txt / workshop.txt (user, 2026-11-08): `py scripts/make_workshop.py` writes both from README.md. forum.txt is
  the whole README in BBCode, the pinned thread in the Workshop page's Discussions tab (full details live there);
  workshop.txt is the summary (intro, rules, each mastery's name and skills, each mastery's signature names, a
  pointer to the thread), well under Steam's 8000-character cap (4575). Keep README the full source: signature
  lines start with the names in italics (`*Name*:`), which the script lists for the summary.

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
  Only skills a picked, active mastery lists are parked (user, 2026-11-10): a gain landing on a parked skill shows
  Java's "<skill> XP: n" halo (`XP.AddXP` ~281, awards made with haloText on the local player, e.g. foraging), which
  for an unpicked skill showed XP going nowhere. The others sit at total(10), where AddXP returns before the halo.
  The pass parks a new pick's skills and unparks the rest (a rise of at most 240, under the anti-cheat's floor).
  Lua can only write XP through `AddXP` (6 arguments, no boosts; Strength's protein factor divided out) and
  `setXPToLevel` (boundaries only); a move that would cross a boundary runs with the level set to 0 for that one call
  (`setPerkLevelDebug`, no event or packet on a server).
- **Why 240**: `AntiCheatXPUpdate` (AntiCheatXP, default 2 = kick) flags a perk whose server XP rose more than
  1000 x multiplier x boost factor (>= 250) between 60 s snapshots. Parking lowers XP; the rises (mastery used up by
  decay, back to vanilla's total(10) - rest; unparking a skill no mastery takes) net at most 240.
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
- **Cost** (user, 2026-11-06: never the bare step; no XP boosters reach mastery, so it stays tough. Changed
  2026-11-10 from compounding 5% to a flat +5% of the step a level, "105, 110, 115, 120 and so forth"; vanilla's
  doubling was considered and turned down, as there are no skill books for mastery): mastery level n costs
  xp10 x MasteryCostBase% x (1 + MasteryCostGrowth% x n), defaults 100 / 5. xp10 = `getXpForLevel(10)`, already x1.5
  from `PerkFactory.AddPerk` (every vanilla table is multiplied on build): 9000 for most skills (total to 10: 32775),
  150000 for Fitness / Strength. For most skills mastery 1 = 9450 XP, mastery 10 = 13500, 1-10 together = 114750
  (~3.5x the 0-10 climb). Prestige levels continue the line (+40, mastery 50 = 350 points, 31500 XP).
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
  Text in the Mastery tab and the Skills tab's effect lists wraps at a mod option's length in characters (user,
  2026-11-08, `M.wrapText` in `client/*_Options.lua`, default 80, 300 = none), the rest indented. The Skills tab is
  generated: change `scripts/make_skills_tab.py`, then run it.
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
  first, then `calculateHitInfoList` (range), `processHit` (crit roll, 42.21 only), the damage roll; so per-swing
  weapon instance boosts (min/max damage, max range, push-back) work. 42.22 rolls a firearm crit once per trigger
  pull in `pressedAttack`, before this event, so a firearm crit field raised here no longer reaches that roll;
  Guns of Tien's Gun Critical Hits option (Old / Enhanced) re-rolls per target after it and does pick it up for
  every target after the first. Firearms.Crit (+5 pts at 10, user 2026-11-11, back after being dropped on
  2026-11-06: guns only felt too strong because of 42.21's damage-chance bug) does both: the trigger pull is topped
  up in `OnWeaponSwing` (bonus / (100 - vanilla's chance for the `TargetDist` zombie), so P = base + bonus) and the
  gun's crit chance is raised for the shot at `OnWeaponSwingHitPoint`; `tests/crit_test.py`. Swing endurance is charged on the server
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

## Built hooks (v1, 2026-11-05; what has been played is at the top of this file)

Every file opens with a header naming the vanilla code, the side it runs on and why the hook works; this is the map.
Bonus amounts all come from `M.val / more / less / roll / int / scaleInt(player, "Perk.Name")` (`M.defs`, shared core).

- Skills tab overview (user, 2026-11-05: vanilla effects only, not mastery): `shared/*_SkillEffects.lua`
  registry (`M.addSkillEffects`, value / unlock entries, labels `IGUI_TienSkillMastery_Effect_<perk>_<name>`),
  data in `*_SkillEffectsBody / Craft / Field.lua`; `client/*_SkillsTab.lua` is vanilla's `ISCharacterInfo:render`
  copied with three insertions by `scripts/make_skills_tab.py` (re-run it after a game update).
- Skills tab cheat (user, 2026-11-06): right-click a skill name in the vanilla Skills tab (`M.showSkillCheatMenu`):
  add / remove real XP, set level 0-10, via `adminSkill` -> `M.adminSkill` -> the `addXpNoMultiplier` global (server:
  GameServer.addXp, which refreshes the XP anti-cheat snapshot like /addxp; SP: plain AddXP); a parked skill is put
  back at total(10) first, mastery is never touched, the protein factor is divided out. Max All (user, 2026-11-09,
  op `maxAll`): every skill below 10 is set to 9 first, because `XP.AddXP` runs `LevelPerk` (halo line, sound,
  `checkAutoLearn`) per level crossed; `xpUpdate.levelPerk` only tests ranges and thresholds, so one level-up to 10 gives
  the same traits and recipes. Asleep, or Fitness with weight trouble (`canAddFitnessXp`), AddXP does nothing: that
  skill gets its old level back and is logged.
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
    (`getHighestRelevantSkillLevel`'s list, plus Pottery for kiln firing). The crafting window shows the scaled time
    (`client/*_CraftTimeLabels.lua`, user 2026-11-09, not played): `CraftRecipe:getTime` answers with the bonus during
    the three label methods only, never for buildable recipes or CraftLogic machines, whose time has no bonus.
  - Kiln firing (user, 2026-11-09, not played): a 42.21 kiln is a `CraftBench`, not `CraftLogic` as an earlier note
    here said, so firing is an ordinary `ISHandcraftAction`; its recipes list no skill, so `relevantPerks` adds
    Pottery by bench tag (KilnSmall / KilnLarge). Crafting time and the craftsman's mark apply; extra output does not.
    Many other vanilla recipes list no skill either (37 Blacksmithing, 33 Metalworking, 21 Tailoring, 44 Cooking...), so
    for crafting time only a recipe also counts as its crafting window category's skill (`CATEGORY_PERK`, user
    2026-11-09, not played); opening a can is a Cooking recipe and gets it too, and small recipes keep it (user, 2026-11-09). Deft Hands is strictly timed actions and
    item transfers by design (user, 2026-11-09): builds, looped actions and reloads staying out is not a gap.
  - Dismantle: `getChanceByDef` is already 100 from level 9, so the points go on the per-roll chance in
    `addScrapItemToList` (80 / 70% at level 10) while `getScrapItemsList` runs.
  - StructureHP: 42.21 builds go through `ISBuildIsoEntity:setInfo` (~655-668), which never calls
    `buildUtil.getWoodHealth`; the first `IsoThumpable:setMaxHealth` inside `setInfo` for a Woodwork recipe is scaled.
  - Hotwire: after a failed `tryHotwire`, a roll calls `vehicle:cheatHotwire(true, brokenBefore)`.
  - Spear / rip / aramid recipes are found by name (`CraftRecipe.LuaCall` is not exposed); their OnCreate changes
    were never synced by vanilla, and are synced when a bonus applies.
  - ToolWear: notes condition / head / sharpness of every candidate kept tool before the craft, restores per point
    after (`isSmithing` recipes; since 2026-11-09, user, not played: category Metalworking and any recipe listing Welding
    too, because `isSmithing()` (Java: involves Blacksmith or category Blacksmithing) misses all 58 Metalworking recipes
    and 10 Weaponry ones; those Welding recipes also get Masterwork on the weapons and clothing they make). The 37
    Blacksmithing recipes listing no skill were never a gap for these: `isSmithing()` takes them by category. Handicraft's
    Tool Wear also goes by category (user, 2026-11-09, not played), for the five recipes listing no skill (MeltSand,
    MeltGlass, three wooden molds); its mark and extra output do not. A kept tool's maker's mark does the same for anyone crafting with it (user,
    2026-11-09, not played), combined with ToolWear; a tool in a hand or worn keeps its mark for Physical's watcher,
    so it never rolls twice.
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

v1's design was settled and built 2026-11-05; v2 replaced it before v1 was played.