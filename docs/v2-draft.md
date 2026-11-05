# Skill Mastery v2: group masteries (draft, 2026-11-06)

Not approved, nothing built. v1 (one mastery per skill, bonuses that copy the skill's vanilla effects) is described
in CLAUDE.md. v2 keeps v1's XP capture and changes what the XP is spent on.

## The idea

- **Skills stay vanilla**: levels 0-10, XP, books and effects exactly as the game has them. Mastery is a layer on top.
- A **mastery** is a named group of skills with its own effects, e.g. **Firearms** = Aiming + Reloading.
- It is **locked** while any member skill is below 10 (user, 2026-11-06). Locked = no effects **and no progress**:
  XP a member earns past 10 while another member is still below 10 is lost, as in vanilla. It unlocks at mastery 0
  once every member is at 10, and from then on members' XP past 10 is mastery XP.
- Its effects are chosen for the mastery as a whole. They no longer copy what a single skill does in vanilla (a
  Firearms effect applies whether the gain came from Aiming or Reloading).
- Levels 1-10 give the effects (each level a tenth of the mastery-10 value, as in v1), then endless prestige.
- Every skill belongs to **exactly one** mastery, so each XP gain goes to one place. A mastery can have a single
  member (Medic). A skill added by another mod that no mastery lists gets its own one-skill mastery with prestige
  only, so nothing is lost and no list needs to know other mods.

## The groups (every vanilla 42.21 skill, 35 skills, 13 masteries)

| Mastery | Member skills (perk ids) |
|---|---|
| Firearms | Aiming, Reloading |
| Two-Handed Weapons | Axe, Long Blunt (Blunt), Long Blade (LongBlade), Spear |
| One-Handed Weapons | Short Blunt (SmallBlunt), Short Blade (SmallBlade) |
| Athlete | Fitness, Strength, Sprinting |
| Agility | Nimble, Lightfooted, Sneaking |
| Smithing | Metalworking (Blacksmith), Welding (MetalWelding), Maintenance |
| Construction | Carpentry (Woodwork), Masonry |
| Engineering | Mechanics, Electrical (Electricity) |
| Artisan | Carving, Knapping (FlintKnapping), Glassmaking, Pottery, Tailoring |
| Provisioner | Cooking, Butchering |
| Medic | First Aid (Doctor) |
| Outdoorsman | Foraging (PlantScavenging), Tracking, Trapping, Fishing |
| Homesteader | Farming, Animal Care (Husbandry) |

The two least obvious picks: Maintenance goes in Smithing (wear and repair of weapons and tools), and Lightfooted /
Sneaking get real effects for the first time through Agility (v1 could not reach their vanilla effects; v2 does not
have to).

## Progress: how member XP becomes mastery levels

v1 machinery stays as it is: a level-10 skill is parked, every gain is caught in `AddXP` and stored as that skill's
mastery XP (`xp[perkId]`), Strength / Fitness decay comes out of it first. One change: a gain is banked only while
the skill's mastery is unlocked (every member at 10); while it is locked the gain is dropped and the skill stays at
the level-10 total, exactly as vanilla.

New: a mastery's progress is worked out from its members' stored XP, never stored itself:

    points = sum over members of  xp[perk] / xp10(perk) x 100
    level n costs 100 x (1 + MasteryCostGrowth%)^n points (5% default, the v1 curve)

Each gain counts as a share of **its own** skill's level-10 step, so 900 Strength XP is worth much less than 900
Aiming XP (Strength's step is 150000, Aiming's 9000). Without that, pooling raw XP would make Athlete fill almost only
from Strength and Fitness. One mastery level is about one level-10 step of any member, the same pace as v1. A bigger
group is not slower to level: it is harder to *unlock*, which is the price of breadth.

Why keep per-skill storage: v1 data carries over with nothing lost (the points are computed from it), Skill Journal
can still record per skill, and changing a group's members later recomputes everything correctly.

## Data shape (code sketch)

```lua
M.mastery("Firearms", { "Aiming", "Reloading" })
M.effect("Firearms", "HitChance", 5, "pts")
M.effect("Firearms", "ReloadSpeed", 15, "pct")
-- hooks: M.val(player, "Firearms.HitChance"), M.more / less / roll / int / scaleInt as in v1
```

`M.level(player, masteryId)` = 0 unless every member is at 10. `M.masteryOf[perkId]` gives the mastery of a skill.
At load, every perk from `M.perks()` that no mastery lists gets a one-skill mastery without effects. Weapon hooks
map a weapon category to a mastery instead of a skill (Axe / Blunt / LongBlade / Spear -> Two-Handed Weapons,
SmallBlunt / SmallBlade -> One-Handed Weapons). The hooks mostly only need their ids renamed.

## Effects at mastery 10

v1's balance rule stays: about a 20% improvement over level 10, combat power 5-10%, defence / endurance / speeds
10-15%, yields 10-20%. Marked **new** = not built in v1, needs a hook (and tracing where noted). Everything else
reuses a built v1 hook with the id renamed.

- **Firearms**: hit chance +5 pts, crit +5 pts, range +10%, aim-in speed +15%, reload and rack speed +15%.
  Candidate (new, trace first): fewer jams.
- **Two-Handed Weapons** (with any weapon of those four categories): damage +10%, attack speed +5%, crit reroll 5%,
  reach +10%, swing endurance -15%, knockback +15%. Change from v1: Long Blade now gets reach and endurance too, and
  every two-handed weapon gets knockback (v1: Axe only, +20%).
- **One-Handed Weapons** (Short Blunt / Short Blade weapons): damage +10%, attack speed +5%, crit reroll 10%, swing
  endurance -15% (new for these two categories, same give-back hook as the long weapons).
- **Athlete**: endurance loss -10%, running endurance -10% (stacks), carry weight +3, knockback +10% with any melee
  weapon. v1's Strength melee damage and Fitness attack speed are dropped so they do not double the weapon
  masteries' bonuses.
- **Agility**: strafe speed +15% (multiplayer only, as in v1), endurance while sneaking -15% (new, the Sprinting
  give-back with `isSneaking()`), nearby animals gain 15% less stress from you (new, server give-back; offered in v1).
- **Smithing**: held weapon wear undone 20%, tool wear undone 20% on smithing recipes, crafting time -15% and
  dismantle return +10 pts on Metalworking / Welding recipes and materials, burnt-car scrapping time -15%, +1
  salvage roll per burnt car.
- **Construction**: built structure HP +20% (Carpentry and now Masonry builds: the hook checks
  `involvesSkill(Perks.Woodwork)`, add Masonry), unbarricade time -15%, window pick-up break -5 pts, crafting time
  -15%, dismantle return +10 pts.
- **Engineering**: part install / uninstall time -15%, engine and lightbar repair +1 condition per part, engine
  salvage +20% parts, hotwire success +10 pts, hotwire time -15%, generator repair +1 condition, extra Electronics
  Scrap 25%, crafting time -15%.
- **Artisan**: crafting time -15% and dismantle return +10 pts on any member's recipes, carved spear condition +2,
  patch / remove patch time -15%, fabric recovery +10 pts, ripping +1 material, aramid thread +1 use.
- **Provisioner**: added ingredient nutrition +15%, add-ingredient time -15%, cooking craft time -15%, butchering
  part count +10%, part chance +15%, butchering time -15%.
- **Medic**: treatment time -15%, treatment strength +15%.
- **Outdoorsman**: fishing line tension +15%, natural bait kept +10 pts, big fish +10 pts, junk -20%, trophy +2 pts;
  forage radius +15%, spotting time -20%, found item size +10%; track find chance +20%, inspect time -15%; trap catch
  +5 pts.
- **Homesteader**: harvest yield +15%, cure strength +15%, planting health +3, bonus yield +10 pts, curse -10 pts,
  fertilizing +10 pts, back strain -15%; animal acceptance +15%, calming +15%, shearing time -15%.

Engineering, Outdoorsman and Homesteader end up with many effects because they join v1 masteries that were each
balanced alone. That seems fair (more skills to get to 10 first), but they could be trimmed.

## UI

The Mastery tab lists masteries instead of skills: name, the member skills with a tick for each one at 10, "Locked"
until all are, then v1's gold level boxes and prestige +n. The tooltip lists the effects at the current level and at
mastery 10. The cheat menu moves to masteries (add / remove points, set level, clear); internally it spreads the XP
over the members by their xp10.

## Open decisions

1. Settled (user, 2026-11-06): nothing is earned while locked.
2. Settled (user, 2026-11-06): a member dropping below 10 (Strength / Fitness decay, admin) locks the mastery again
   (no effects, no progress), but its earned progress is kept and works again once the skill is back at 10.
   Decay that happens while the mastery is unlocked still comes out of that skill's mastery XP first, as in v1
   (user, 2026-11-06): it protects the skill level at the cost of some progress, and the skill only drops below 10
   (locking the mastery) once that share is used up.
3. **Exclusive groups** (recommended) or overlapping ones (a skill in several masteries, each gain counted in each;
   more combinations, but stacked effects get hard to balance).
4. **Bigger groups level at the same pace** (recommended, the cost is the unlock) or slower (cost x member count).
5. The groups and effects above, especially Maintenance in Smithing, Tailoring in Artisan, and the Athlete trim.
6. v1 or v2: v2 replaces v1 (v1 data carries over through the per-skill storage), not a second mode next to it.
