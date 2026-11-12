# Tests

No game needed: these load the real mod Lua in a real Lua (lupa, 5.5) against mocks of the game's objects. They cover what
the mod does with what the game gives it, not how the game behaves: `docs/test-checklist.md` is for that.

Setup, once per computer (`py` is the Python launcher on Windows; use `python3` on a Mac):

    py -m pip install --target tests/.lupa lupa

Run:

    py tests/run_all.py            every test
    py tests/run_all.py --release  every test, then the release checks; read that report before an upload

Each test also takes the name of a deliberate break, to prove its checks can fail (`py tests/spear_test.py nosend`; the names
are at the top of each file). A break should print FAILED.

| File | Covers |
|---|---|
| `sync_test.py` | Battering Ram shown on other clients, throw flinches, zombie posture on a server |
| `spear_test.py` | Carved spear bonus, and that it stays near but under forged at mastery 10 |
| `torch_test.py` | Torch Fuel on builds, Handicraft tool wear by category |
| `weld_test.py` | Smithing's tool wear and Masterwork on welding and metalworking recipes |
| `partcount_test.py` | Butchering part count: no extra feet or whole birds |
| `parking_test.py` | Only picked masteries' skills are parked: no XP halo for unpicked level-10 skills, anti-cheat-safe moves |
| `evasion_test.py` | Evasion: zombie swings made toothless on a dodge and given back, who owns the attack on each side, the server's list of masters, 0-damage player hits |
| `unfazed_test.py` | Unfazed Runner: sprint held off among trees and hedges (not bushes), a bump into a zombie, animal or player a stagger and never a fall, nobody else bumped into mid-stagger and put back after, Toggle to Sprint put back after the stagger while a movement key is held (not after a stop, not for hold to sprint, at most 1.5 s), only for masters, never against the tutorial's sprint setting |
| `falls_test.py` | Safe falls on a port of `updateFalling` at 1x and 5x: safe drops harmless, higher drops one floor lower, non-masters vanilla |
| `stealth_test.py` | Stealth: own-square work noise cut, admin noises and non-masters left alone, a master's melee weapon quieter while held and put back after, guns left alone |
| `distraction_test.py` | Distraction Throw: what is throwable, only from the hand and for a master, the server's checks, the arc (walls, low fences), glass breaking, landing noise and sound by material |
| `losethem_test.py` | Stealth's Lose Them and Unseen: the server's list of masters, Lose Them timed on the master's game (crouched, out of sight, 3 s) and applied on the zombie's owner, here or through the server, Unseen dropping only new targets of a crouched and still master and walking them on or away, the cleared "last spotted" |
| `crit_test.py` | Firearms crit: a trigger pull with a target crits at vanilla's chance plus the bonus, never for non-masters or NoCriticals guns; the gun's crit chance raised for the shot (Guns of Tien's per-target rolls) and put back |
| `preflight.py` | Release report: Lua compiles, translations and labels, scripts, leftovers, values, mod.info |

Lua 5.5 is stricter than the game's Kahlua in places, and it has things Kahlua lacks, so passing here is not proof the
code runs in game. Mocks are plain Lua tables with methods.
