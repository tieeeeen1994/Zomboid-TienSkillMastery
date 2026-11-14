# Balance audit (2026-11-14)

The user asked for every mastery to be checked against what a player actually feels, and against whether a master
contributes something better than a non-master. Nothing below has been played; numbers come from the code (the
mod's hooks and vanilla 42.22 Lua and Java).

## Questions asked of every mastery

1. **Is it felt?** At mastery 10, would a player notice the effect without opening the panel? A 5% speed-up or a
   +2-point chance is not noticed. A 25% cut to the time of the master's main job, a doubled rare drop, or a
   certainty (window never breaks) is.
2. **Does the master bring something?** On a server, the master should be the person others go to: the smith's
   gear lasts longer, the builder's walls hold, the medic patches people up faster, the farmer works a whole field.
3. **Does it level?** A mastery whose skills earn little XP at level 10 sits at mastery 0-1 for good, so only its
   signature is ever felt.
4. **Is any pick a must-have?** With three picks out of 21, no single pick should be the obvious choice for every
   build.

## Applied

| What | Was | Now | Why |
|---|---|---|---|
| Pace: Strength, Fitness | x1 | x5 | Their level-10 step is 150000 XP against 9000, while they earn per action like other skills (1 per melee hit, 4-8 per exercise rep, `Fitness.java`). Conditioning took about 80000 hits for mastery 1. |
| Pace: Sprinting, Nimble | x1 | x5 | 1 XP per ~20 s of running or aiming on the move (`xpUpdate.onPlayerMove`, `isRandXp(1000, 0.05)`): about 50 hours of running per mastery level. |
| Pace: Sneaking, Lightfooted | x1 | x3 | 1 XP on a 1 in 1100 roll per unaware zombie per update (`IsoZombie` ~2696), 1-3 from animals. Better than running, still slow. |
| Melee attack speed (5 weapon masteries, not knives) | +5% | +10% | The bonus speeds up the swing animation but not the delay after it, so +5% was about +3% more attacks. +10% is about +7%, and with damage +10% it lands on the "about 20% better at mastery 10" rule. |
| Construction structure health | +20% | +30% | The builder's walls are what they give the group, and zombies test them all night. |
| Engineering install / uninstall time | -15% | -25% | A master's main job at the same 25% as the crafting masteries' crafting time. |
| Mending patching time | -15% | -25% | Same rule. |
| Field Medicine treatment time | -15% | -25% | Same rule; it also matters most when someone is bleeding. |
| Field Medicine treatment strength | +15% | +25% | The patient should feel the medic's work: bandages last longer, splints and stitches heal sooner. |
| Angling trophy fish | +2 points | +5 points | 5% -> 7% went unnoticed; 10% doubles trophies. |

The pace is `M.PACE` in the shared core. It multiplies points in `M.pointsFor` and divides in `M.xpForPoints`, so
decay costs the same share of a level as before. Points already earned are unchanged.
`tests/parking_test.py` checks it ("8b").

Rough pace now, per mastery level, for someone playing that part: weapon masteries about 3500-4500 hits; crafting
and field masteries a level-10 step of recipes or finds; Conditioning about 30000 Strength / Fitness XP (a few
thousand exercise reps, or ~15000 hits); Freerunning about 10 hours of running.

## Mastery by mastery

- **Firearms**: the fullest kit (nine numbers, two signatures you feel at once). Its limit is ammunition: Aiming
  earns 1 XP per hit. No change.
- **Axemanship**: clear identity (reach, knockback, Tomahawk) and it brings wood (tree damage +20%). Attack speed raised.
- **Bludgeoning**: crowd control (Wild Swing, extra targets). Attack speed raised.
- **Swordsmanship**: the passives match the others, but Hamstring needs crouch + aim, the stance players least use in
  a real fight (proposal 3).
- **Spearcraft**: Javelin, plus carved spears that anyone can use. No change beyond attack speed.
- **Street Fighting**: Battering Ram is felt at once. Stomp +20% adds little, since a Strength 10 stomp already
  kills most downed zombies, but it costs nothing. Attack speed raised.
- **Knifework**: the strongest one-on-one kit. Executioner reaches 100% at mastery 10, so with Lunge every close
  stab with at most one chaser is a kill. This is the knife's identity by your choice, and crowds are unaffected.
  Watch it in play, but no change.
- **Conditioning**: the hauler (Pack Mule, carry +5). Its numbers were out of reach before the pace fix.
- **Freerunning**: the pace fix makes Evasion's 25% reachable for the first time (proposal 2).
- **Stealth**: the signatures carry it; the passives are noise only. The pace fix lets it level.
- **Smithing**: Masterwork is its contribution, but at 15% it is hard to notice (proposal 1).
- **Construction**: walls raised to +30%; Clean Cuts / Clean Breaks and spare materials are good.
- **Engineering**: the car person (Engine Overhaul, tuned engine, faster installs now).
- **Handicraft**: Deft Hands helps every action; Craftsmanship has the same issue as Masterwork (proposal 1).
- **Mending**: Restoration makes the tailor the repair person for the group; patching now 25% faster.
- **Field Medicine**: Triage is a real group job; treatments faster and stronger now.
- **Provisioning**: it feeds the group (Choice Cuts, Savory Meals, lasting food). No change.
- **Hunting**: Sturdy Traps and Double Catch are felt. No change.
- **Angling**: trophies raised; Fish Finder is felt. No change otherwise.
- **Fieldcraft**: Sixth Sense and Steady Eyes are felt. No change.
- **Homesteading**: the biggest group contributor (Harvest Moon works a whole field). Planting health +3 was too
  small to notice (vanilla already starts a Farming 10 plant at 67-74) and was dropped. The ±10-point season rolls
  are not small: at Farming 10 vanilla gives 95% best-month bonus, 5% risk-month curse and 95% early fertilizer
  effect (`SPlantGlobalObject` ~614, ~727-728), so from mastery 5 a master's crops always get the bonus and the
  fertilizer and are never cursed. Kept; they top out at mastery 5.

## Proposals (each reversed an earlier choice or changed a mechanic, so the user decided)

1. **Masterwork and Craftsmanship 15% -> 25%.** Ignoring 15% of wear makes an item last 1.18x as long, which nobody
   notices; 25% is 1.33x. These marks are the smith's and the crafter's whole contribution to others. Lowered from
   25% on 2026-11-06. **Applied** (user, 2026-11-14).
2. **Evasion 25% -> 20%.** Until now almost nobody would have reached Freerunning 10. With the pace fix they will,
   and a quarter of all zombie attacks missing stacks with any combat pick, which makes Freerunning the default
   third pick. Set at 25% on 2026-11-11. **Applied** (user, 2026-11-14).
3. **Hamstring outside crouch.** For example, also a 20% chance on any long-blade hit. As it is, the signature
   seldom fires in a real fight. **Not taken** (user, 2026-11-14).
4. **Homesteading trim.** First proposed as folding plant health and the three season rolls into yield; the rolls
   turned out to be certainties from mastery 5 (above), so only planting health was dropped (user, 2026-11-14).
