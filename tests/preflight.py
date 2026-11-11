"""Release checks for Tien's Skill Mastery: compile, translations, labels, scripts, leftovers, numbers."""
import json
import re
import sys
import xml.dom.minidom
from pathlib import Path

here = Path(__file__).resolve().parent
repo = here.parent
sys.path.insert(0, str(here / '.lupa'))
import lupa

mod = repo / 'Contents/mods/TienSkillMastery'
root = mod / '42/media/lua'
files = {f: f.read_text(encoding='utf-8', errors='replace') for f in root.rglob('*.lua')}
core = files[root / 'shared/TienSkillMastery.lua']
joined = '\n'.join(files.values())

print('== layout')
for p in sorted(mod.iterdir()):
    print('  ', p.name, 'dir' if p.is_dir() else 'file')
print('   42/', sorted(p.name for p in (mod / '42').iterdir()))

print('== Lua compiles (Lua 5.5 syntax, stricter than Kahlua):', len(files), 'files')
lua = lupa.LuaRuntime()
load = lua.globals().load
bad = 0
for f, s in files.items():
    r = load(s.replace('\r\n', '\n'), f.name)
    fn = r[0] if isinstance(r, tuple) else r
    if fn is None:
        bad += 1
        print('   FAIL', f.name, r[1] if isinstance(r, tuple) else '')
print('   failures:', bad)

print('== translations')
for name in ['IG_UI', 'UI', 'Recipes']:
    p = root / f'shared/Translate/EN/{name}.json'
    d = json.loads(p.read_text(encoding='utf-8'))
    pct = [k for k, v in d.items() if re.search(r'(?<!%)%(?![%\d])', str(v).replace('%%', ''))]
    print(f'   {name}: {len(d)} keys, lone % in: {pct or "none"}')
tr = json.loads((root / 'shared/Translate/EN/IG_UI.json').read_text(encoding='utf-8'))
ui = json.loads((root / 'shared/Translate/EN/UI.json').read_text(encoding='utf-8'))
used = set(re.findall(r'"(IGUI_TienSkillMastery_[A-Za-z0-9_]+)"', joined))
print('   literal keys missing:', sorted(k for k in used if k not in tr and not k.endswith('_')) or 'none')

print('== every effect has a panel label, every signature a name, every mastery a name')
defs = re.findall(r'^\s*def\(\s*"(\w+)"\s*,\s*"(\w+)"', core, re.M)
weapon = re.findall(r'^\s*def\(\s*id\s*,\s*"(\w+)"', core, re.M)
missing = [f'{m}.{n}' for m, n in defs
           if f'IGUI_TienSkillMastery_Bonus_{m}_{n}' not in tr and f'IGUI_TienSkillMastery_Bonus_{n}' not in tr]
print('   no label:', missing or 'none')
print('   weapon loop labels missing:', [n for n in weapon if f'IGUI_TienSkillMastery_Bonus_{n}' not in tr and not any(k.endswith('_' + n) for k in tr)] or 'none')
print('   signature names missing:', [n for _, n in defs if n.startswith('Sig') and f'IGUI_TienSkillMastery_SigName_{n}' not in tr] or 'none')
print('   mastery names missing:', [m for m in re.findall(r'M\.mastery\("(\w+)"', core) if f'IGUI_TienSkillMastery_Mastery_{m}' not in tr] or 'none')
print('   leftovers of removed effects:', [k for k in tr if re.search('ForgedSpears|SpearCondition|spearmaker|Bonus_QuietWork$', k)] or 'none')

print('== scripts and anim xml')
for p in (mod / '42/media/scripts').rglob('*.txt'):
    s = p.read_text(encoding='utf-8', errors='replace')
    print('  ', p.name, 'braces', s.count('{'), s.count('}'), 'recipes', re.findall(r'craftRecipe\s+(\w+)', s))
for p in (mod / '42/media/AnimSets').rglob('*.xml'):
    xml.dom.minidom.parse(str(p))
    print('  ', p.name, 'well formed')

print('== leftovers')
for f, s in sorted(files.items(), key=lambda x: x[0].name):
    for i, line in enumerate(s.splitlines(), 1):
        code = line.split('--')[0]
        if re.search(r'\b(TODO|FIXME|XXX|HACK)\b', line) and 'SkillsTab' not in f.name:
            print(f'   mark {f.name}:{i}: {line.strip()[:90]}')
        if re.search(r'(?i)temporar|for testing|debugprint|print\(".*(debug|test)', line) and 'SkillsTab' not in f.name:
            print(f'   temp {f.name}:{i}: {line.strip()[:90]}')
        if re.search(r'\bprint\(', code) and not re.search(r'\[TienSkillMastery\]', code):
            print(f'   bare print {f.name}:{i}: {code.strip()[:90]}')
print('   prints with the mod tag:', len(re.findall(r'print\(.*\[TienSkillMastery\]', joined)))
print('   M.SETTINGS:', re.findall(r'M\.SETTINGS\s*=\s*[^\n]*', core))

print('== numbers: effect values at mastery 10')
start = core.index('M.WEAPON_MASTERY') if 'M.WEAPON_MASTERY' in core else 0
loop = re.search(r'for\s+\w+\s*,\s*row\s+in\s+.*?\nend', core, re.S)
tbl = core[core.rfind('local', 0, loop.start()) - 900:loop.start()] if loop else ''
print(tbl[-900:])
print(loop.group(0)[:700] if loop else 'no loop')
print('   other defs:')
for m, n, v in re.findall(r'^\s*def\(\s*"(\w+)"\s*,\s*"(\w+)"\s*,\s*([\d.]+)', core, re.M):
    if m in ('Axemanship', 'Bludgeoning', 'Swordsmanship', 'Spearcraft', 'StreetFighting', 'Knifework'):
        print(f'     {m}.{n} {v}')
print('== mod.info'); print((mod / '42/mod.info').read_text())
w = (repo / 'workshop.txt').read_text(encoding='utf-8')
print('== workshop.txt header/footer:', [l for l in w.splitlines() if not l.startswith('description')])
for p in [mod / '42/poster.png', mod / '42/icon.png', repo / 'preview.png']:
    print('  ', p.name, p.stat().st_size, 'bytes')
