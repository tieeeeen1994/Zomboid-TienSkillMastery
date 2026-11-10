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
| `unfazed_test.py` | Unfazed Runner: sprint held off among trees and hedges (not bushes) and before touching a character, the bump-repeat timer and a leftover bumped character cleared, others not solid during a stagger and put back, only for masters, never against the tutorial's sprint setting |
| `preflight.py` | Release report: Lua compiles, translations and labels, scripts, leftovers, values, mod.info |

Lua 5.5 is stricter than the game's Kahlua in places, and it has things Kahlua lacks, so passing here is not proof the
code runs in game. Mocks are plain Lua tables with methods.
