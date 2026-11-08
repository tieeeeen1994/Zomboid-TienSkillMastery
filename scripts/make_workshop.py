"""Writes forum.txt and workshop.txt from README.md (everything after the title), Markdown to Steam BBCode.

forum.txt: the whole README, every effect and signature in full; it is the pinned thread in the Workshop page's
Discussions tab (user, 2026-11-08). workshop.txt: a summary for the Workshop description, which Steam caps at 8000
characters (a longer one fails the in-game upload): the intro and the rules, each mastery's name and skills, each
mastery's signature names, and a pointer to that thread.

    py scripts/make_workshop.py
"""
import os
import re

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

TITLE = "Tien's Skill Mastery"
FORUM_TITLE = "Tien's Skill Mastery: every mastery, effect and signature"
MASTERIES = "Masteries and their effects at mastery 10"
SIGNATURES = "Signature abilities"
SUMMARY_TITLES = {MASTERIES: "Masteries"}
POINTER = ("Every mastery's effects and every signature ability in full: see the pinned thread in the Discussions tab, "
           "or click a mastery in the in-game Mastery tab.")


def bb(line):
    line = re.sub(r"\*\*(.+?)\*\*", r"[b]\1[/b]", line)
    return re.sub(r"(?<![\w*])\*([^*]+?)\*(?![\w*])", r"[i]\1[/i]", line)


def parse(body):
    """README body -> list of (section, blocks); a block is ("para", text) or ("list", [items])."""
    sections, section, blocks = [], None, []
    para, items, cur = [], [], None

    def flush():
        nonlocal cur
        if para:
            blocks.append(("para", " ".join(para)))
            para.clear()
        if cur is not None:
            items.append(cur)
            cur = None
        if items:
            blocks.append(("list", list(items)))
            items.clear()

    for line in body.split("\n"):
        if line.startswith("## "):
            flush()
            sections.append((section, blocks))
            section, blocks = line[3:].strip(), []
        elif line.startswith("- "):
            if para:
                blocks.append(("para", " ".join(para)))
                para.clear()
            if cur is not None:
                items.append(cur)
            cur = line[2:]
        elif line.startswith("  ") and cur is not None:
            cur += " " + line.strip()
        elif not line.strip():
            flush()
        else:
            if cur is not None:
                items.append(cur)
                cur = None
            para.append(line.strip())
    flush()
    sections.append((section, blocks))
    return sections


def mastery_head(item):
    """'**Firearms** (Aiming, Reloading): ...' -> '**Firearms** (Aiming, Reloading)'."""
    cut = item.find("):")
    return item[:cut + 1] if cut >= 0 else item


def signature_names(item):
    """'**Construction:** *Clean Cuts*: ... *Clean Breaks*: ...' -> '**Construction:** Clean Cuts, Clean Breaks'."""
    head = re.match(r"\*\*[^*]+\*\*", item)
    names = re.findall(r"(?<![\w*])\*([^*]+?)\*:", item)
    return (head.group(0) if head else "") + " " + ", ".join(names)


def render(sections, summary):
    out = []
    for section, blocks in sections:
        if section is not None:
            out.append("")
            title = SUMMARY_TITLES.get(section, section) if summary else section
            out.append("[h2]" + title + "[/h2]")
        for kind, data in blocks:
            if summary and section in (MASTERIES, SIGNATURES):
                if kind != "list":
                    continue
                pick = mastery_head if section == MASTERIES else signature_names
                data = [pick(i) for i in data]
            if kind == "para":
                out.append(bb(data))
            else:
                out.append("[list]")
                out.extend("[*]" + bb(i) for i in data)
                out.append("[/list]")
    return out


def main():
    readme = open(os.path.join(REPO, "README.md"), encoding="utf-8").read()
    sections = parse(readme.split("\n", 2)[2])

    forum = ["[h1]" + FORUM_TITLE + "[/h1]", ""] + render(sections, summary=False)
    with open(os.path.join(REPO, "forum.txt"), "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(forum).strip() + "\n")

    desc = render(sections, summary=True) + ["", POINTER]
    # The game writes id= into workshop.txt on the first upload; losing it makes the next upload a new Workshop item.
    # Visibility is also the file's own, so regenerating never changes who can see the mod.
    workshop = os.path.join(REPO, "workshop.txt")
    kept = {}
    if os.path.exists(workshop):
        with open(workshop, encoding="utf-8") as f:
            for l in f:
                key, sep, value = l.rstrip("\r\n").partition("=")
                if sep and key in ("id", "visibility"):
                    kept[key] = value
    head = ["version=1"] + (["id=" + kept["id"]] if "id" in kept else [])
    out = head + ["title=" + TITLE] + ["description=" + l for l in desc]
    out += ["tags=Build 42;Misc;Multiplayer", "visibility=" + kept.get("visibility", "unlisted")]
    with open(workshop, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(out) + "\n")
    chars = sum(len(l) + 1 for l in desc)
    print("forum.txt written,", sum(len(l) + 1 for l in forum), "characters")
    print("workshop.txt written,", chars, "description characters (Steam limit 8000)")


if __name__ == "__main__":
    main()
