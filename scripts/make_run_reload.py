"""Writes the running-reload anim nodes (Firearms.SigRunReload) from the installed game and gun mods.

    python scripts/make_run_reload.py            # default Steam paths
    python scripts/make_run_reload.py --steam "D:/Steam/steamapps"

Run it again whenever the game, Gunworks or Guns of Marz change their reload animations, then commit the result.

Why (42.22.2, traced 2026-11-20; details in shared/TienSkillMastery_RunReload.lua): reload clips are nodes of the
`actions` substate, which `run` and `sprint` never enter. They do enter `maskingright` (an upper-body layer over the
running legs) whenever `RightHandMask` is not empty, and a node cannot take its clip from a variable, so every reload
node is copied into `AnimSets/player/maskingright/TsmRunReload/` with one more condition, RightHandMask =
TsmRunReload, which the Lua sets on a master who reloads on the run.

What it does, mirroring the game's own loading:
- Effective files: vanilla `media/AnimSets/player/actions`, then each mod's `common/media` and highest version folder
  in load order (Gunworks before Guns of Marz, which requires it). A later file at the same lower-case path replaces an
  earlier one, as `ZomboidFileSystem.activeFileMap` does. The old Guns of Marz (id MarzGuns) is skipped.
- `x_extends` / `x_include` resolved the way `PZXmlUtil.parseXml` / `resolve` do (42.22): a text-only child replaces,
  any other merges; children match by tag + `x_name`, else by tag + index among that tag's entries (`TagTable`);
  unmatched children are appended; attributes merge. The output has no `x_extends`: a relative extends path is
  lower-cased on Linux and fails there (Zomboid Fixes B42's CLAUDE.md, "AnimSet x_extends on Linux").
- Kept: nodes whose resolved conditions include PerformingAction Reload, InsertBullets or RemoveBullets (what every
  vanilla and Gunworks reload action passes to `setActionAnim`). Renamed `TsmRun_<name>`; transitions to another
  kept node follow the rename, transitions to anything else are dropped (that node is not in maskingright);
  transition-outs (no target) stay.
- Everything else (clip, speed, events with their sounds and model swaps, bone weights or the game's default ones,
  priority) is copied as resolved.
"""
import argparse
import copy
import os
import re
import shutil
import sys
import xml.etree.ElementTree as ET

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(REPO, "Contents", "mods", "TienSkillMastery", "42", "media", "AnimSets", "player", "maskingright",
                   "TsmRunReload")
MASK = "TsmRunReload"
PREFIX = "TsmRun_"
ACTIONS = {"Reload", "InsertBullets", "RemoveBullets"}
STATE = "animsets/player/actions/"

# (label, workshop id, mod folder) in load order
MODS = [
    ("Gunworks", "3722064198", "Gunworks_gang_framework"),
    ("GunsOfMarz", "3722134990", "GunsOfMarz"),
]


# ---------------------------------------------------------------------------------------------------------------
# Files
# ---------------------------------------------------------------------------------------------------------------

def version_key(name):
    return [int(p) for p in re.findall(r"\d+", name)]


def mod_media_roots(mod_dir):
    """common/media first, then the highest numbered version folder's media (the game's B42 layout)."""
    roots = []
    common = os.path.join(mod_dir, "common", "media")
    if os.path.isdir(common):
        roots.append(common)
    versions = [d for d in os.listdir(mod_dir) if re.fullmatch(r"\d+(\.\d+)*", d)
                and os.path.isdir(os.path.join(mod_dir, d, "media"))]
    if versions:
        roots.append(os.path.join(mod_dir, max(versions, key=version_key), "media"))
    return roots


def collect(media_root, origin, files):
    base = os.path.join(media_root, "AnimSets")
    if not os.path.isdir(base):
        return
    for dirpath, _, names in os.walk(base):
        for n in names:
            if not n.lower().endswith(".xml"):
                continue
            path = os.path.join(dirpath, n)
            key = os.path.relpath(path, media_root).replace("\\", "/").lower()
            files[key] = (path, origin)


# ---------------------------------------------------------------------------------------------------------------
# PZXmlUtil.resolve
# ---------------------------------------------------------------------------------------------------------------

def is_text_only(el):
    return len(el) == 0 and el.text is not None and el.text.strip() != ""


class Entry:
    def __init__(self, el, index):
        self.tag = el.tag
        self.name = el.get("x_name", "")
        self.element = el
        self.index = index

    def key(self):
        return self.name if self.name.strip() else "node_%d" % self.index


class TagTable:
    def __init__(self, root):
        self.tags = {}
        self.resolved = []
        for child in root:
            self.add(Entry(copy.deepcopy(child), len(self.tags.get(child.tag, {}))))

    def add(self, entry):
        self.resolved.append(entry)
        self.tags.setdefault(entry.tag, {})[entry.key()] = entry

    def find(self, child):
        named = self.tags.get(child.tag)
        if named is None:
            return None
        if not child.name.strip():
            for e in named.values():
                if e.index == child.index:
                    return e
            return None
        return named.get(child.name)

    def resolve_with(self, other):
        for ce in other.resolved:
            pe = self.find(ce)
            if pe is None:
                self.add(ce)
            else:
                pe.element = resolve(ce.element, pe.element)


def resolve(child, parent):
    if is_text_only(child):
        return copy.deepcopy(child)
    result = ET.Element(child.tag)
    attrs = dict(parent.attrib)
    attrs.update(child.attrib)
    result.attrib.update(attrs)
    table = TagTable(parent)
    table.resolve_with(TagTable(child))
    for e in table.resolved:
        result.append(e.element)
    return result


def parse_file(path):
    with open(path, "rb") as f:
        data = f.read()
    text = data.decode("utf-8-sig", errors="replace")
    text = re.sub(r"^\s*<\?xml[^>]*\?>", "", text)
    return ET.fromstring(text)


def resolve_relative(key, rel):
    folder = key.rsplit("/", 1)[0] if "/" in key else ""
    return os.path.normpath(os.path.join(folder, rel.replace("\\", "/"))).replace("\\", "/").lower()


def parse_xml(key, files, depth=0):
    if depth > 20:
        raise RuntimeError("x_extends loop at " + key)
    if key not in files:
        raise FileNotFoundError(key)
    root = parse_file(files[key][0])
    inc = root.get("x_include", "").strip()
    if inc:
        inc_root = parse_xml(resolve_relative(key, inc), files, depth + 1)
        if inc_root.tag == root.tag:
            merged = ET.Element(root.tag, dict(root.attrib))
            for c in inc_root:
                merged.append(copy.deepcopy(c))
            for c in root:
                merged.append(copy.deepcopy(c))
            root = merged
    ext = root.get("x_extends", "").strip()
    if ext:
        root = resolve(root, parse_xml(resolve_relative(key, ext), files, depth + 1))
    return root


# ---------------------------------------------------------------------------------------------------------------
# Selection and rewrite
# ---------------------------------------------------------------------------------------------------------------

def text_of(el, tag):
    c = el.find(tag)
    return (c.text or "").strip() if c is not None else ""


def cond_value(cond):
    """`AnimCondition.parseValue`: m_Value when given, else the typed field (Guns of Marz writes m_StringValue)."""
    return text_of(cond, "m_Value") or text_of(cond, "m_StringValue") or text_of(cond, "m_BoolValue") \
        or text_of(cond, "m_FloatValue")


def performing_action(node):
    """The node's PerformingAction (compared ignoring case, as `AnimCondition.check` does), normalised to ACTIONS."""
    for cond in node.findall("m_Conditions"):
        if text_of(cond, "m_Name") == "PerformingAction" and text_of(cond, "m_Type") in ("STRING", ""):
            v = cond_value(cond).lower()
            for a in ACTIONS:
                if a.lower() == v:
                    return a
            return v
    return None


def is_abstract(node):
    return not text_of(node, "m_AnimName") and node.find("m_2DBlends") is None


def strip_x(el):
    for k in [k for k in el.attrib if k.startswith("x_")]:
        del el.attrib[k]
    for c in el:
        strip_x(c)


def rewrite(node, kept_names):
    node.find("m_Name").text = PREFIX + text_of(node, "m_Name")
    for t in list(node.findall("m_Transitions")):
        target = text_of(t, "m_Target")
        if not target:
            continue
        if target.lower() in kept_names:
            t.find("m_Target").text = PREFIX + target
        else:
            node.remove(t)
    # `AnimCondition.pass`: an OR entry splits the list into groups that each must pass whole, so the mask joins every
    # group: before each OR and after the last condition (next to the others, before the events).
    children = list(node)
    last = max([i for i, c in enumerate(children) if c.tag == "m_Conditions"], default=len(children) - 1)
    for c in children:
        node.remove(c)
    for i, c in enumerate(children):
        if c.tag == "m_Conditions" and text_of(c, "m_Type") == "OR":
            node.append(mask_condition())
        node.append(c)
        if i == last:
            node.append(mask_condition())
    if last < 0:
        node.append(mask_condition())
    strip_x(node)


def mask_condition():
    cond = ET.Element("m_Conditions")
    for tag, value in (("m_Name", "RightHandMask"), ("m_Type", "STRING"), ("m_Value", MASK)):
        ET.SubElement(cond, tag).text = value
    return cond


def serialise(el, depth, out):
    pad = "\t" * depth
    attrs = "".join(' %s="%s"' % (k, v.replace("&", "&amp;").replace('"', "&quot;")) for k, v in el.attrib.items())
    text = (el.text or "").strip()
    if len(el) == 0:
        if text:
            out.append("%s<%s%s>%s</%s>" % (pad, el.tag, attrs, escape(text), el.tag))
        else:
            out.append("%s<%s%s />" % (pad, el.tag, attrs))
        return
    out.append("%s<%s%s>" % (pad, el.tag, attrs))
    for c in el:
        serialise(c, depth + 1, out)
    out.append("%s</%s>" % (pad, el.tag))


def escape(s):
    return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


# ---------------------------------------------------------------------------------------------------------------

def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--steam", default="C:/Program Files (x86)/Steam/steamapps",
                    help="the steamapps folder holding common/ProjectZomboid and workshop/content/108600")
    args = ap.parse_args()

    game_media = os.path.join(args.steam, "common", "ProjectZomboid", "media")
    if not os.path.isdir(game_media):
        sys.exit("game not found: " + game_media)
    files = {}
    collect(game_media, "vanilla", files)
    for label, wid, folder in MODS:
        mod_dir = os.path.join(args.steam, "workshop", "content", "108600", wid, "mods", folder)
        if not os.path.isdir(mod_dir):
            sys.exit("%s not installed (subscribe to Workshop item %s): %s" % (label, wid, mod_dir))
        for root in mod_media_roots(mod_dir):
            collect(root, label, files)

    kept = []      # (key, origin, node)
    errors = []
    for key in sorted(k for k in files if k.startswith(STATE)):
        try:
            node = parse_xml(key, files)
        except (ET.ParseError, FileNotFoundError, RuntimeError) as e:
            errors.append("%s: %s" % (key, e))
            continue
        if node.tag != "animNode" or performing_action(node) not in ACTIONS or is_abstract(node):
            continue
        kept.append((key, files[key][1], node))

    kept_names = {text_of(n, "m_Name").lower() for _, _, n in kept}
    if os.path.isdir(OUT):
        shutil.rmtree(OUT)
    counts = {}
    for key, origin, node in kept:
        rewrite(node, kept_names)
        rel = key[len(STATE):]
        folder, name = os.path.split(rel)
        src = files[key][0]
        dest = os.path.join(OUT, origin, folder, PREFIX + os.path.basename(src))
        os.makedirs(os.path.dirname(dest), exist_ok=True)
        lines = ['<?xml version="1.0" encoding="utf-8"?>',
                 "<!-- Generated by scripts/make_run_reload.py from %s %s; do not edit. -->" % (origin, rel)]
        serialise(node, 0, lines)
        with open(dest, "wb") as f:
            f.write(("\r\n".join(lines) + "\r\n").encode("utf-8"))
        counts[origin] = counts.get(origin, 0) + 1

    for origin in ["vanilla"] + [m[0] for m in MODS]:
        print("%-11s %3d nodes" % (origin, counts.get(origin, 0)))
    print("written to", os.path.relpath(OUT, REPO))
    for e in errors:
        print("skipped (error):", e)


if __name__ == "__main__":
    main()
