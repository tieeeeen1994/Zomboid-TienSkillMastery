"""Writes media/sandbox-options.txt and Translate/EN/Sandbox.json for Tien's Skill Mastery.

    python -I scripts/make_options.py

Every mastery effect gets a sandbox option (user, 2026-11-20: "sandbox options for each mastery value so everything is
flexible"), read from the real effect definitions in shared/TienSkillMastery.lua, which it runs in lupa (tests/.lupa):

- a passive: `TienSkillMastery.<Mastery>_<Name>`, double, the amount at mastery 10 (each level a tenth), 0 = off;
- a signature with a `unit`: the same name, its fixed amount, 0 = off;
- a signature without one: the same name, boolean, on / off;
- a step effect: `<Mastery>_<Name>_Step<i>Level` (integer 1-10) and `<Mastery>_<Name>_Step<i>` (double) per step.

Pages: the general page (Masteries Per Character) and one per mastery group, masteries in the panel's order,
signatures first. Labels come from the panel's (IG_UI.json); run it again after adding, removing or renaming an effect
or changing a default or a label. Renaming an option resets it on existing servers (the old value is dropped).
A literal percent sign in a translation is written %% (the Translator formats every string at load).
"""
import json
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO / 'tests' / '.lupa'))
import lupa  # noqa: E402

MEDIA = REPO / 'Contents/mods/TienSkillMastery/42/media'
LUA = MEDIA / 'lua'
NS = 'TienSkillMastery'

GENERAL = [
    ('MaxMasteries', 'integer', 1, 21, 3,
     'Masteries Per Character',
     'How many masteries one character can pick (default 3). A mastery can be picked once every skill in it is at '
     'level 10, and picks are permanent: once a character has this many, every other mastery is closed for them.\\n'
     'Raising it opens more slots at once, for characters who already filled theirs too. Lowering it never takes a '
     'mastery away: a character who already has more keeps them all and cannot pick another.'),
    ('MasteryCostBase', 'double', 1, 1000, 100,
     'Mastery Cost Base (%%)',
     'What a mastery level costs before growth, in percent of one level-10 step of a skill (9000 XP for most '
     'skills). Default 100.\\nLevel n costs Base x (1 + Growth x n): with the defaults 105%% of a step for mastery 1, '
     '110%% for mastery 2, 150%% for mastery 10. 50 halves every cost, 200 doubles it.\\nOnly points are kept, so a '
     'change moves the mastery levels of every character at once (cheaper raises them); no progress is lost. Changes apply '
     'at once.'),
    ('MasteryCostGrowth', 'double', 0, 100, 5,
     'Mastery Cost Growth (%%)',
     'How much each mastery level adds to the cost, in percent of the base cost, without compounding. Default 5 '
     '(105, 110, 115%%...). 0 makes every level cost the same.\\nOnly points are kept, so a change moves the '
     'mastery levels of every character at once; no progress is lost. Changes apply at once.'),
]

# Skill names as the game shows them (perk id -> English name), for the contribution options.
SKILL_NAMES = {
    'Aiming': 'Aiming', 'Reloading': 'Reloading', 'Axe': 'Axe', 'Strength': 'Strength', 'Blunt': 'Long Blunt',
    'LongBlade': 'Long Blade', 'Nimble': 'Nimble', 'Spear': 'Spear', 'Carving': 'Carving', 'SmallBlunt': 'Short Blunt',
    'Fitness': 'Fitness', 'SmallBlade': 'Short Blade', 'Sneak': 'Sneaking', 'Sprinting': 'Sprinting',
    'Lightfoot': 'Lightfooted', 'Blacksmith': 'Metalworking', 'MetalWelding': 'Welding', 'Maintenance': 'Maintenance',
    'Woodwork': 'Carpentry', 'Masonry': 'Masonry', 'Mechanics': 'Mechanics', 'Electricity': 'Electrical',
    'FlintKnapping': 'Knapping', 'Glassmaking': 'Glassmaking', 'Pottery': 'Pottery', 'Tailoring': 'Tailoring',
    'Doctor': 'First Aid', 'Cooking': 'Cooking', 'Butchering': 'Butchering', 'Tracking': 'Tracking',
    'Trapping': 'Trapping', 'Fishing': 'Fishing', 'PlantScavenging': 'Foraging', 'Farming': 'Farming',
    'Husbandry': 'Animal Care',
}

# Short words after a passive's label: what the number is.
KIND_HINT = {'pct': ' (+%%)', 'pts': ' (+%%)', 'less': ' (-%%)', 'ptsoff': ' (-%%)', 'int': '', 'flat': ''}
KIND_TEXT = {
    'pct': 'Percent added to the vanilla amount',
    'pts': 'Percentage points added to the chance',
    'less': 'Percent taken off the vanilla amount',
    'ptsoff': 'Percentage points taken off the chance',
    'int': 'Whole amount added (a fraction is the chance of one more)',
    'flat': 'Amount added',
}
UNIT_HINT = {'pct': '%%', 'times': 'times', 'tiles': 'tiles', 'seconds': 'seconds', 'flat': 'amount'}
APPLIES = 'Changes apply at once.'
OFF = 'An effect that is off is no longer listed in the Mastery tab.'


def load_defs():
    core = (LUA / 'shared/TienSkillMastery.lua').read_bytes().decode('utf-8').replace('\r\n', '\n')
    lua = lupa.LuaRuntime()
    lua.globals().core_source = core
    return lua.execute(r'''
unpack = table.unpack
local dummy
dummy = setmetatable({}, { __index = function() return dummy end, __call = function() return dummy end })
setmetatable(_G, { __index = function(_, k) return dummy end })
isClient = function() return false end
isServer = function() return false end
SandboxVars = nil
assert(load(core_source, "TienSkillMastery.lua"))()
local M = TienSkillMastery
local out = {}
for _, m in ipairs(M.masteries) do
    local defs = {}
    local order = {}
    for _, d in ipairs(m.defs) do if d.kind == "sig" then order[#order + 1] = d end end
    for _, d in ipairs(m.defs) do if d.kind ~= "sig" then order[#order + 1] = d end end
    for _, d in ipairs(order) do
        local steps = {}
        for i, s in ipairs(d.steps or {}) do steps[i] = { s[1], s[2] } end
        defs[#defs + 1] = { id = d.id, name = d.name, opt = d.opt, at10 = d.at10, kind = d.kind, unit = d.unit,
            max = d.max, steps = steps, conditional = d.when ~= nil, parked = d.parked == true }
    end
    local members = {}
    for i, p in ipairs(m.members) do members[i] = { id = p, pace = M.PACE[p] or 1 } end
    out[#out + 1] = { id = m.id, group = m.group, defs = defs, members = members }
end
return out
''')


def lua_list(t):
    return [t[i] for i in range(1, len(t) + 1)] if t is not None else []


def num(v):
    v = float(v)
    return str(int(v)) if v == int(v) else repr(v)


def split_name(name):
    return re.sub(r'(?<=[a-z])(?=[A-Z])', ' ', name)


def main():
    tr = json.loads((LUA / 'shared/Translate/EN/IG_UI.json').read_text(encoding='utf-8'))
    masteries = lua_list(load_defs())

    lines = ['VERSION = 1,', '']
    texts = {'Sandbox_' + NS: "Tien's Skill Mastery"}

    def option(name, typ, page, default, label, tooltip, lo=None, hi=None):
        lines.append(f'option {NS}.{name}')
        lines.append('{')
        lines.append(f'    type = {typ},')
        if lo is not None:
            lines.append(f'    min = {num(lo)},')
            lines.append(f'    max = {num(hi)},')
        lines.append(f'    default = {default},')
        lines.append(f'    page = {page},')
        lines.append(f'    translation = {NS}_{name},')
        lines.append('}')
        lines.append('')
        texts[f'Sandbox_{NS}_{name}'] = label
        texts[f'Sandbox_{NS}_{name}_tooltip'] = tooltip

    for name, typ, lo, hi, default, label, tooltip in GENERAL:
        option(name, typ, NS, default, label, tooltip, lo, hi)

    def label_of(mastery, name):
        return tr.get(f'IGUI_TienSkillMastery_Bonus_{mastery}_{name}') or tr.get(f'IGUI_TienSkillMastery_Bonus_{name}') \
            or split_name(name)

    count = 0
    for m in masteries:
        page = NS + m.group
        group = tr.get(f'IGUI_TienSkillMastery_Group_{m.group}', m.group)
        texts.setdefault('Sandbox_' + page, f"Skill Mastery: {group}")
        mname = tr.get(f'IGUI_TienSkillMastery_Mastery_{m.id}', m.id)
        for s in lua_list(m.members):
            skill = SKILL_NAMES.get(s.id, split_name(s.id))
            pace = num(s.pace)
            slow = '' if s.pace == 1 else f' ({skill} earns experience slowly, so it counts {pace} times by default)'
            option(f'{m.id}_Skill_{s.id}', 'double', page, pace, f'{mname}: {skill} experience (x)',
                   f'How much {skill} experience counts towards {mname}, as a multiplier. Default {pace}{slow}.\\n'
                   f'At 1, one mastery level takes about one level-10 step of {skill} (plus the mastery cost), 2 '
                   f'halves that, 0.5 doubles it. Decay of {skill} is paid from {mname} the same way.\\n0: {skill} '
                   f'no longer feeds {mname} at all (it must still be at level 10 for the mastery to work). '
                   f'{APPLIES}', 0, 100)
        for d in lua_list(m.defs):
            if d.parked:
                continue
            full = label_of(m.id, d.name)
            short = re.sub(r'\s*\(.*\)$', '', full)   # the sandbox screen's label column is narrow
            if d.kind == 'sig':
                sig = tr.get(f'IGUI_TienSkillMastery_SigName_{d.name}', split_name(d.name))
                if d.unit is None:
                    option(d.opt, 'boolean', page, 'true', f'{mname}: {sig}',
                           f'{full}.\\nA signature: unlocked in full when the mastery is picked. Off: nobody has it '
                           f'and the Mastery tab no longer lists it. {APPLIES}')
                else:
                    shown = full.replace('%1', num(d.at10))
                    hint = UNIT_HINT.get(d.unit, d.unit)
                    option(d.opt, 'double', page, num(d.at10), f'{mname}: {sig} ({hint})',
                           f'{shown}.\\nA signature: unlocked in full when the mastery is picked, not scaled by '
                           f'mastery level. Default {num(d.at10)}, 0 turns it off. {OFF} {APPLIES}',
                           0, d.max or 100)
            elif d.kind == 'step':
                steps = lua_list(d.steps)
                unit = d.unit or 'flat'
                cond = '\\nOnly while the sandbox option to hit several zombies at once is ' + \
                    ('on.' if d.name == 'ExtraTarget' else 'off.') if d.conditional else ''
                for i, s in enumerate(steps, 1):
                    lvl, val = int(lua_list(s)[0]), lua_list(s)[1]
                    option(f'{d.opt}_Step{i}Level', 'integer', page, lvl,
                           f'{mname}: {short}, step {i} level',
                           f'{full}.\\nThe mastery level step {i} starts at (default {lvl}). Of the steps reached, '
                           f'the one starting highest counts.{cond} {APPLIES}', 1, 10)
                    pct = unit == 'pct'
                    option(f'{d.opt}_Step{i}', 'double', page, num(val),
                           f'{mname}: {short}, step {i}{" (+%%)" if pct else ""}',
                           f'{full}.\\n{"Percent added" if pct else "Amount"} from step {i}\'s mastery level on '
                           f'(default {num(val)}); 0 gives nothing from that step.{cond} {APPLIES}',
                           0, d.max or (1000 if pct else 10))
            else:
                hi = d.max or {'pct': 1000, 'less': 100, 'pts': 100, 'ptsoff': 100}.get(d.kind) \
                    or max(100, float(d.at10) * 10)
                option(d.opt, 'double', page, num(d.at10), f'{mname}: {short}{KIND_HINT[d.kind]}',
                       f'{full}.\\n{KIND_TEXT[d.kind]} at mastery 10; each mastery level gives a tenth. '
                       f'Default {num(d.at10)}, 0 turns it off. {OFF} {APPLIES}', 0, hi)
            count += 1

    (MEDIA / 'sandbox-options.txt').write_bytes(('\r\n'.join(lines)).encode('utf-8'))
    body = json.dumps(texts, indent=4, ensure_ascii=False)
    (LUA / 'shared/Translate/EN/Sandbox.json').write_bytes((body + '\n').encode('utf-8'))
    print(f'{count} effects, {sum(line.startswith("option ") for line in lines)} options written')


if __name__ == '__main__':
    main()
