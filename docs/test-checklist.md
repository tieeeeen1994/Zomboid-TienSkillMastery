# In-game test checklist (version 0.4.3)

What still has to be seen on a real server before sharing the link. Written 2026-11-09. Everything here is coded and
passes the mock tests in `tests/`; none of it has been confirmed in game unless a note says so.

Work top to bottom: picks are permanent for players, so the things they could waste a pick on come first. Tick items as
they pass. When one fails, write what you saw under it, then give this file to Claude. Delete this file when it is done
(lasting findings go in `CLAUDE.md`).

## Setup

- [ ] **Upload first.** The server runs the Workshop copy, not your working folder, and only fetches updates when it
      starts. Upload, then restart the server. If a feature "does nothing", check this before anything else: compare the
      Workshop mirror's timestamp (`steamapps/workshop/content/108600/3836051294`) with the server's start time.
- [ ] **Two players** on the dedicated server: A and B, both with a role that may add XP (admin works), so both can use
      the cheats below.
- **Getting a mastery fast:** right-click a skill's name in the Skills tab > **Max All**. Then press **Pick** in the Mastery
  tab. Right-click a picked mastery for **Set mastery level** (use 10 unless a step says otherwise) or **Remove pick**, which
  frees the slot for the next section.
- **Logs:** after each section, search `Zomboid/console.txt` (and the server's console) for `[TienSkillMastery]` and for
  errors or stack traces mentioning `TienSkillMastery`. Lines saying a hit or bonus "failed" count as a failure.
- **Reading exact numbers:** launch with `-debug` (admin may connect with it) and use the Lua console, as in the steps below.
- **Who controls a zombie:** usually the nearest player's client. "B's zombie" = one standing much closer to B than to A.

## 1. Basics

- [ ] Mastery tab shows 22 masteries. **Salvaging** has a grey Coming Soon button, and everything else
      a Pick button once its skills are at 10.
- [ ] Pick one: the choice survives leaving and rejoining. The level-up halo and sound play when a level is gained.
- [ ] Mastery progress is earned from real XP (use the skill for a while) and is not earned by reading a skill book.
- [ ] (2026-11-10) Foraging at level 10 **without** a mastery that lists it: no "Foraging XP" text over the head. With
      Angling or Fieldcraft picked, the text shows and the mastery grows. Remove the pick: the text stops within a second.
- [ ] (2026-11-10) Mastery costs read 105, 110, 115... in the Mastery tab tooltip; mastery 10 costs 150.
- [ ] No XP anti-cheat kick on the first login after the update (every level-10 skill goes back up 240 XP once).

## 2. Today's sync fixes

**Battering Ram** (Street Fighting; most likely to look wrong)
- [ ] A sprints into **B's zombie**. Both players see it fall, lie there and get back up, with no snapping or sliding.
- [ ] A sprints into their **own** zombie. Same result, and B sees it too.
- [ ] The zombie's owner and A do not disagree afterwards about where it is.

**Throw flinches** (Axemanship *Tomahawk* or Spearcraft *Javelin*; throw key is Space in combat stance)
- [ ] A throws at a **loose animal**: both players see it flinch and bleed; it takes damage and can die.
- [ ] With PvP on, A throws at **B**: B and any other onlooker see the reaction and blood, and B takes a wound. B can move
      and act normally right after (not stuck in the reaction).
- [ ] From behind and from the front, the reaction looks right.
- [ ] B in a car, or asleep, is not thrown into a reaction.

**Lying zombies**
- [ ] A throws at a **knocked-down** zombie and a **crawler**: body hit only, no stagger, and the weapon can pass over them
      when aimed past.
- [ ] A throws at a **standing** zombie: head hits to about 4 tiles and a stagger, as before.
- [ ] A throws at a zombie **sitting** against a wall: can take a head hit, no stagger.

## 3. Hunting (now pickable, signatures never played)

Fastest way to get a catch: with `-debug`, right-click a placed trap > **Add Animal**.

- [ ] **Double Catch** (the riskiest): set several traps as a Hunting master and add animals until one holds two (a quarter
      of catches). Taking it out gives two animals. For a live one, the first is set down rather than lost or duplicated.
- [ ] **Sturdy Traps**: a master's baited trap keeps its bait for many in-game hours and survives while you are far away.
- [ ] **Live Catch**: a rabbit left in a master's trap many in-game hours still comes out alive, where it would die in a normal trap.
- [ ] Traps keep working after the master logs off, and after a server restart.
- [ ] Butcher a **cow**: more meat, sinew and bones than without the mastery. Butcher a **chicken** several times: never a
      third foot or a second whole chicken.
- [ ] Tracks are found more often in search mode, and inspecting one is quicker.

## 4. Angling (now pickable, signature never played)

- [ ] **Fish Finder**: aiming a rod at water shows the fish and trash line, and it changes between spots.
- [ ] A and B aim at the **same spot**: note whether the numbers match. They may not, since each client keeps its own counts;
      report the difference, as it decides whether the readout needs to come from the server.
- [ ] Catches arrive normally: bait is sometimes kept, the line lasts longer, junk is rarer.
- [ ] A master checking a fishing net gets more, with no extra break or bait loss.
- [ ] Foraging turns up worms and insects more often.

## 4b. Freerunning (opened in 0.4.2, nothing played)

- [ ] *Evasion* (a passive since 2026-11-11: 25% at mastery 10, 2.5% a level), zombies: let A's own zombies swing at A for a while. About 1 in 4 swings does nothing at all: no wound,
      no flinch, no torn clothing. The rest land as usual. Repeat with a zombie B controls (standing near B) attacking A.
- [ ] *Evasion*, PvP (PvP on): B hits A with a weapon many times. About 1 in 4 hits does nothing on any screen (no damage
      on A's health panel, no flinch); the others land. A non-master hit by B takes every hit.
- [ ] *Unfazed Runner*, trees: A sprints into a forest. A drops to a run without tripping, gets scratched / torn now and
      then, and sprints again once out (sprint key held). Bushes behave as vanilla. A non-master still trips.
- [ ] *Unfazed Runner*, bumps (changed 2026-11-12): A, with Toggle to Sprint on, sprints into a zombie, B and an
      animal: A and the one bumped play vanilla's stagger, A never falls, and A sprints on afterwards without pressing
      the key again (also with Toggle to Sprint off, holding the key). Letting go of the movement keys during the
      stagger stops A as vanilla. Also on B's screen.
- [ ] *Unfazed Runner* with *Battering Ram* (Street Fighting picked too): zombies are still knocked down when sprinting.
- [ ] Sprinting and running speed (added 2026-11-11): at mastery 10, A sprints about 15%, runs about 10% and moves crouched (walking or running) about 5% faster than a non-master, with
      no anti-cheat bounce or kick on the server, no sliding through walls, doors or fences; B sees A move smoothly.
- [ ] Safe falls: a 1-floor drop at mastery 3, a 2-floor drop at 6 and a 3-floor drop at 9 do no damage, also during
      fast forward. A 3-floor drop at mastery 6 hurts like a 2-floor drop (a hard landing, not the severe one); a 4-floor
      drop at mastery 9 like a 3-floor one (severe, not lethal).

## 4c. Stealth (built 2026-11-11, opened in 0.4.3, nothing played)

- [ ] *Quiet work*: with Stealth at 10, barricade or sledgehammer near zombies a little way off: fewer of them come than for a non-master at the same spot. Also on a
      dedicated server (the noise of most actions is made there).
- [ ] *Quiet swings*: swing a bat at the air near distant zombies: fewer react than for a non-master. Drop the bat or
      hand it to B: B's swings with it are as loud as vanilla. Guns are as loud as vanilla.
- [ ] *Distraction Throw*: hold an empty bottle in combat stance and press K at a spot 10-15 tiles away: it arcs there
      (B sees the flight), breaks with a glass sound into broken glass, and idle zombies near the spot walk to it. A
      can and a stone land as items with their sounds. "Throwable" shows in the tooltip of those items only, and only
      for the master. Bound to Space too (same key as the axe throw): a bottle in hand is lobbed, no axe thrown with it.
      Sounds: a whoosh as it leaves the hand (B hears it too), the bottle smash (`SmashedBottleBreak`), the mod's own
      can clatter (an empty tin can), `BreakMetalItem` (scrap metal), the stone's drop. Each audible at the spot from a
      few tiles away, and not too loud or too quiet next to vanilla sounds (volumes in
      `media/scripts/TienSkillMastery_sounds.txt`).
- [ ] *Lose Them*: get a few zombies chasing you, crouch and break line of sight (round a building corner, through a
      door you close). About 3 s after the last one could see you, the chasers stop and stand; standing up resets the
      clock. On a dedicated server with B nearby, so some chasers are run by B's game: those stop too (the request goes
      through the server). Watch for a zombie that stops and then starts after you again with no sight of you (would
      mean its forced tracking came back).
- [ ] *Unseen*: crouch still in plain view of idle zombies (daylight, facing you): they do not come. One that turns
      towards you walks off a few tiles instead. Stand up or move: they notice you as usual. Zombies chasing you
      before you stopped keep coming. Also with B owning the zombies, and B (not a master) standing next to you
      still gets noticed. Single player: a zombie walking past that keeps you in view may stall in place (known limit).

## 5. Homesteading (already pickable, mostly unplayed)

- [ ] Right-click a crop or furrow > **Homesteading** submenu. **Tend the field** and **Sow the field** each ask for two corners;
      the first corner tints yellow.
- [ ] A tended patch gets watered, cured and fertilized per plant; supplies are used per plant, and one action covers 3 x 3
      squares in about the time of a single plant.
- [ ] **Remove plots** clears dead, rotten or destroyed plots in the patch (needs a digging tool; hidden without one).
- [ ] **Dig furrows**: the 3 x 3 cursor stays until cancelled; each click digs **all 9** squares (a first test dug 4 of 9, since
      fixed); a far click walks there first, Build Cheat included.
- [ ] **Walking onto crops:** does a field job's walk ever end on a crop, and does that reset the queue? Unknown from the code.
- [ ] B sees the plants change without relogging.
- [ ] **Animal Whisperer**: standing in a pen, its animals' stress drops by 1 every 10 in-game minutes, including hutched
      ones and joined pens, and no faster with two masters.
- [ ] Milking and shearing are about 15% quicker, and the animal ends with the right milk and wool.

## 6. Other changes from 2026-11-09

**Carved spears** (Spearcraft at mastery 10; needs a forged spear to compare)
- [ ] Carve a spear, relog, and hold it. In the Lua console:
      `w = getPlayer():getPrimaryHandItem(); print(w:getMinDamage(), w:getMaxDamage(), w:getMaxRange())`.
      Expect about 1.08, 1.51, 1.44 (vanilla 1.0, 1.4, 1.4). Fire-hardened: about 1.08, 1.62, 1.44.
- [ ] The numbers are right **before** relogging too, on the crafter's client. This is the part most likely to fail.
- [ ] Give the spear to B: B's copy has the same numbers. A spear made at mastery 5 stays halfway after the maker levels up.
- [ ] A bound or stone spear gets nothing.

**Smithing**
- [ ] Weld a scrap sword and a piece of scrap armor: "Masterwork by (name)" in the tooltip. A metal sheet or sawn bar gets no mark.
- [ ] Tools wear less on sawing and scrapping metal (20%, so it takes a while to notice).
- [ ] **Torch Fuel on builds:** build something metal from the build menu (not with Build Cheat) several times. The torch sometimes
      keeps uses, and what the client shows matches after a relog.

**Crafting time and butchering**
- [ ] The crafting window shows the shortened time and the action really takes about that long.
- [ ] Kiln firing is quicker for a Handicraft master, and fired items carry the Craftsmanship mark.
- [ ] Butchering a whole chicken or small game gives food with the Choice Cuts bonus (Provisioning).

## 7. Older multiplayer checks

These come from reading the code and were never confirmed on a server.

**Combat**
- [ ] A's thrown weapon is seen flying by B, and lands where both agree. A kill counts for the thrower.
- [ ] *Wild Swing*: zombies in front that the swing missed stagger for both players, on both players' zombies.
- [ ] *Hamstring*: B's zombie falls and gets up crawling, seen the same way by both.
- [ ] Knifework's bonus against zombies not targeting you works on B's zombies.
- [ ] Street Fighting's stomp and shove damage work with something in hand.
- [ ] *Battering Ram* really stops the sprint trip, including with two zombies at once.
- [ ] Firearms with Gunworks: bursts and fire rate behave, and there are no anti-cheat kicks. *Running Reload* and *Quickdraw* look right.
- [ ] Firearms crit: a master's shots crit a little more often (+5 at mastery 10); with Guns of Tien's Gun Critical Hits on Old or Enhanced, shotgun pellets after the first get it too.
- [ ] *Lunge*: distance and feel at 1.5 tiles, on your own and on B's zombies.

**Field Medicine**
- [ ] *Field Triage* on A and B together: one shared list, the right order, items borrowed from the patient used only on
      them, the rest returned. Bandages land on B, and B moving within 2 tiles does not stop it.

**Engineering**
- [ ] *Tuned Engine*: driving at full speed causes no anti-cheat kick, and the car's values return to normal after leaving the seat.
- [ ] *Engine Overhaul*: B sees the new engine quality and the car drives accordingly.

**Construction and Conditioning**
- [ ] *Spare Materials*: building gives some back, and dismantling that build refunds only what was really paid.
- [ ] *Pack Mule*: the Heavy Load moodle reads one level lower, and the weight shown matches the server after a relog.
