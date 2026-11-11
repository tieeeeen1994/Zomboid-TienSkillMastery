# Working rules and reference notes

The user's standing rules and the reference notes that apply to this mod, kept in the repository (2026-11-11, user:
"make sure all memories and other stuff are committed"). They were in Claude's private memory before; that memory
still exists, but this file is the copy that travels with the code. `CLAUDE.md` has the short list under "The user's
standing rules"; this file has the reasons and the details. Rules marked "all mods" apply to every one of the user's
mods, not only this one.

## Rules

### Dedicated server first (all mods)

The user's mods run on their dedicated server (NuecaB42); single-player-only or host-only behaviour is useless to
them. When planning Tien's Generator Manager the user rejected a plan until it was explicit about dedicated servers
("this needs to be able to be workable in dedicated servers").

How to apply: every plan says how each piece works on a dedicated server: which side changes the world, which call
syncs it, which events fire there (`OnObjectAdded` is client-only, for example). Verification starts on a local
dedicated server (`ProjectZomboidServer.bat` in the game folder), single player second.

### The server runs the Workshop copy (all mods)

When the user joins their dedicated server, the client loads a mod from the local working folder
(`C:\Users\Chen\Zomboid\Workshop\<mod>`), but the server downloads the published Workshop copy (local mirror under
`steamapps/workshop/content/108600/<id>`; this mod is 3836051294). The user's pzopt setup has
`luaChecksumExempt=true`, so the mismatch does not stop them joining. A new feature's server file is simply missing on
the server until it is uploaded and the server restarted: the server fetches Workshop updates only when it starts
("Workshop: ... CheckItemState -> Ready ID=<id>" = no download), so an upload made after the restart is not on it.

Seen: 2026-09-24, Zomboid Fixes' body stats editor sat on "Waiting for the server..." forever; the Workshop copy had no
`*_BodyStats.lua`. 2026-09-27, "reload is not sped up by fast forward": the published copy predated the file.
2026-10-11, Tien's Attachment Positions 0.1.3 reached Steam at 14:52:55 while the server had started at 14:50 with the
old copy.

How to apply: when a client/server feature "does nothing" or "waits for the server" in MP, first check the file exists
in the Workshop mirror and compare the mirror's timestamp with the server's start time; only then debug the code.
Quickest check: `steamapps/workshop/appworkshop_108600.acf`, the mod's entry, `latest_timeupdated` (unix seconds),
then `diff -rq` the mirror's `media/lua` against the working copy. There is no server log on this machine
(`coop-console.txt` is only for hosted games).

### Verify against the implementation (all mods)

Documentation in any mod (file headers, CLAUDE.md notes, other mods' comments) can be wrong. Before stating or relying
on a claim about how a mod or the game behaves, check the implementation (the Lua or the decompiled Java), and correct
our docs when they disagree with it.

Why: on 2026-09-27 a whole day of "sync" fixes chased magazines losing rounds that were really a deterministic
counting bug (TienMagazineBag passed Gunworks' `ammoLimit`, and Gunworks' server-side `isLoadFinished` used an
`ammoCountStart` only `start()` sets); it happened at normal speed too. A GoM tooltip header also stated a wrong claim
taken on assumption.

How to apply: when a report says "only at fast forward" or "only in MP", first look for a normal-speed or single-cause
reproduction and read the code paths end to end before building timing or sync workarounds. Quote the code, not a
doc, as evidence.

### Trace what the code can answer (all mods)

A question the code can answer is never left as "unknown" or "to check in MP": decompile or read it and settle it.

Why: 2026-11-10, safe falls carried "whether the server runs fall damage" as an open question; the user: "why on
earth is it unknown for you if server runs fall damage. you can check that in code". The trace took minutes, settled
it (the server simulates every player's fall) and found a real bug (the cap could be overshot at 3x speed and
more). The same day the user also corrected a claim that evasion could not avoid the hit animation; the trace
proved the user right (`setNoTeeth` skips the whole hit).

How to apply: before writing "unknown", "untraced" or "to check in game" about engine behaviour, trace it (recipe
below). Keep "to check in game" for what only play shows: feel, timing, visuals, multiplayer races.

### Findings go next to the code (all mods)

Each engine finding goes in the header or an inline comment of the file that relies on it, plus a short line in the
repo's `CLAUDE.md` (and a "features built" entry for a new feature). The user once moved a CLAUDE.md's findings into
the Lua files, then brought a central CLAUDE.md back; both are kept.

### No over-the-head text as feedback (all mods)

Don't add halo texts (`HaloTextHelper.addText` / `addBadText`) as feedback for new features: the user removed a "Craft
queued" halo (2026-10-05) and does not want that chatter. When a feature needs to acknowledge something, the
behaviour itself is the feedback, or ask first.

Exception (2026-11-06): a mastery level-up mirrors vanilla's own ("+1 ..." halo with the arrow and the level-up
sound), which the user asked for.

### No timers just to notice sandbox option changes (all mods)

No periodic handler may exist only to re-check sandbox options (or re-apply load-time changes when they change).
Load-time work reads the option once at world load; its name gets " (Requires Restart)" and its tooltip says a change
takes effect after a restart. Code that runs anyway may read an option live; a branch that only reacts to an option
being switched counts as polling. Why: a needless performance cost for something admins rarely do (2026-10-25, after
an `Events.EveryTenMinutes.Add(apply)` in a race car patch). When per-player work is needed after a restart and the
server has no join event, the client asks once after joining (repeating until answered).

This mod has no sandbox options for now (user: "I want to control the values").

### TODO lists hold open work only (all mods)

A to-do list holds only work still to do: bugs, decisions, unbuilt or unpolished pieces. Finished items are removed,
and so are "to check in game" lists for features already coded. Why: the user said built features "most likely work
by now through real gameplay"; long done / untested lists buried the real open work (GoMExtensionGunsOfTien's
TODO.md had grown to ~940 lines). Here the to-do list is "Still to do" in `CLAUDE.md`; `docs/test-checklist.md` was
asked for separately and is deleted once played through. Data worth keeping from a shelved plan goes to a `docs/`
file.

### Workshop text: summary there, full text in the forum post (all mods)

`workshop.txt` holds only a summary (intro, short lists, a pointer to the Discussions thread); every detail goes in
`forum.txt`, posted as the pinned thread. Feature descriptions are never trimmed to fit Steam's 8000-character cap
(the user said so for this mod, 2026-11-08). Here `scripts/make_workshop.py` writes both from `README.md`.

### Preview text: gameplay only (all mods)

Workshop preview images carry short text about what plays only (no real-world trivia such as barrel lengths or model
names; user, 2026-11-03, about Guns of Tien's previews).

### Line endings (all repos)

Files are CRLF in the working tree (git autocrlf). Git Bash's `sed -i` and Python text-mode writes with `newline=''`
silently turn a whole file to LF, and git hides it. Edit with the Edit tool or Python in binary mode, check with
`b.count(b'\r\n')`, and never run a line-ending fix over files you did not edit (2026-11-11: a sweep touched five
untouched files, restored with `git checkout`).

## Reference

### What reaches the server in multiplayer

- Player stats are server side. `Stats.add/remove/set` never send anything; a client can only push stats through
  `sendPlayerStat`, which needs `CanModifyBodyStats` (admins). Apply on the server, then `syncPlayerStats(player,
  mask)` (mask from `SyncPlayerStatsPacket.getBitMaskForStat(CharacterStat.X)`; the bits OR together). Anything the
  server sets reaches the owner within a second (see Zomboid Fixes B42's CLAUDE.md for the packet table).
- Item mod data changed on a client stays on that client; on the server, `syncItemModData(player, item)` pushes it.
- Inventory, server side: `sendRemoveItemFromContainer(inv, item)` then `inv:Remove(item)`, and
  `sendAddItemToContainer(inv, item)` after `AddItem` (set mod data and name first: the packet serialises the item).
- `sendClientCommand(player, ...)` in single player fires `OnClientCommand` locally, so a server file guarded with
  `if isClient() then return end` handles the same command in single player too.
- `CoopServer:isRunning()` is true only on the machine hosting a co-op game; that host is still `isClient()`.

### Lua sees Java methods, not instance fields

`LuaJavaClassExposer` exposes a class's methods and its static public fields; instance public fields read as nil from
Lua (and cannot be written). Check for getters and setters, not public fields, before planning a fix around a Java
class. Writing through a method still works (`layout:addItem():setLabel(...)`). Which classes Lua can reach at all is
`LuaManager$Exposer.exposeAll()` (`setExposed(Foo.class)`); `HutchManager`, `GameClient`, `GameServer` and
`IngameState` are not exposed. Examples met in this mod: `IsoZombie.lastTargetSeenX/Y/Z` and `WorldSound`'s fields
are out of reach.

### Kahlua's base library

Smaller than real Lua 5.1: pcall, print, select, type, tostring, tonumber, getmetatable, setmetatable, error,
unpack, setfenv, getfenv, rawequal, rawset, rawget, collectgarbage, debugstacktrace. **`next` does not exist.**
`pairs` / `ipairs` come from `table.pairs` / `table.ipairs`; TableLib adds concat, insert, remove, newarray, isempty,
wipe. A syntax check does not catch a missing global. The tests here run the real files in lupa (Lua 5.5), which is
stricter in places and has things Kahlua lacks.

### No real pause in multiplayer

A real MP pause cannot be done from Lua (the server pauses only while empty with `PauseEmpty`; the client pause is
`GameClient`, not exposed). The user rejected a fake pause through a near-zero time multiplier ("No. We need to pause
the game"): don't offer slowed time as a pause again.

### Decompiling the game on this PC (Windows)

`projectzomboid.jar` is Java 25 (class version 69). The installed JDK 23's `javap` refuses it, and the game's
`jre64` has no `javap`. What works:

```bash
JAVA="/c/Program Files (x86)/Steam/steamapps/common/ProjectZomboid/jre64/bin/java.exe"   # OpenJDK 25
curl -sL -o vineflower.jar https://repo1.maven.org/maven2/org/vineflower/vineflower/1.11.1/vineflower-1.11.1.jar
mkdir cls out && (cd cls && unzip -q -o "/c/Program Files (x86)/Steam/steamapps/common/ProjectZomboid/projectzomboid.jar" 'zombie/ai/states/AttackState*.class')
"$JAVA" -jar vineflower.jar -log=WARN cls out
```

A few classes take seconds. To find which classes call a method, scan the jar's class files for the name with
Python (`zipfile` + `b'getSoundRadius' in data`), then decompile those. Zomboid Fixes B42's `CLAUDE.md` holds most
engine findings and a full-decompile recipe.

### pzopt on the user's install

The game folder runs PZ_Optimization (pzopt), a self-built 42.22.2 port loaded through a Java agent
(`-javaagent:pzopt/agent/pzopt-agent.jar`, classes under `pzopt/overrides/`). It overrides classes such as
`KahluaTableImpl`, `zombie/Lua/Event`, `IsoGameCharacter`, `IsoPlayer`, `IsoWorld`, `WorldSoundManager` and
`scripting/objects/Item`, and the user's fork adds gameplay overrides (`NetworkPlayerAI`: no `-debug` Ctrl
shortcuts). When a decompile of the jar does not match what happens in game, check whether pzopt overrides that
class. The build and release steps live in the fork (`D:\PZ_Optimization`, `tieeeeen1994/PZ_Optimization`).

### Mods this one meets on the user's server

Guns of Marz (Workshop 3722134990) with the Gunworks gang framework (mod id `SWMG`, 3722064198, Lua under
`WeaponSystems/`), VWP2GoM, Hot Brass Tactical Reload (3610677934), Plysken Attachments Reborn, and the user's own
TienMagazineBag, TienInspectWeapon, Guns of Tien and Zomboid Fixes B42. A fix for behaviour another of the user's mods
triggers belongs in that mod. Gunworks matters here for Firearms' signatures (its reload hooks and `new` parameters,
see `shared/TienSkillMastery_Signatures.lua`) and for the throw (its grenade numbers set Distraction Throw's range).

## This mod's history in short

Started 2026-11-05 as a standalone mod: mastery past skill level 10, earned only by experience, never by reading,
with prestige after mastery 10; a Skill Journal (workshop 3776641628) that restores it is wanted later, low priority.
v2 (picked masteries over groups of skills, at most three, permanent) replaced v1; its design and every decision are
in `docs/v2-draft.md`. 0.4.0 merged to master 2026-11-09; 0.4.1 and 0.4.2 (Freerunning opened) on 2026-11-10; 0.4.3
(Stealth opened) on 2026-11-11; the Workshop item is unlisted by choice. What has been played, what is built but unplayed, and what is still to do are
at the top of `CLAUDE.md`.
