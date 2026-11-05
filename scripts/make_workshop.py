"""Writes workshop.txt from README.md (everything after the title), Markdown to Steam BBCode.

    py scripts/make_workshop.py
"""
import os
import re

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def bb(line):
    return re.sub(r"\*\*(.+?)\*\*", r"[b]\1[/b]", line)


def main():
    readme = open(os.path.join(REPO, "README.md"), encoding="utf-8").read()
    body = readme.split("\n", 2)[2]
    out = ["version=1", "title=Tien's Skill Mastery"]
    para, items, cur = [], [], None

    def flush_para():
        if para:
            out.append("description=" + bb(" ".join(para)))
            para.clear()

    def flush_items():
        if items:
            out.append("description=[list]")
            out.extend("description=[*]" + bb(i) for i in items)
            out.append("description=[/list]")
            items.clear()

    for line in body.split("\n"):
        if line.startswith("## "):
            flush_para()
            if cur is not None:
                items.append(cur)
                cur = None
            flush_items()
            out.append("description=")
            out.append("description=[h2]" + line[3:] + "[/h2]")
        elif line.startswith("- "):
            flush_para()
            if cur is not None:
                items.append(cur)
            cur = line[2:]
        elif line.startswith("  ") and cur is not None:
            cur += " " + line.strip()
        elif not line.strip():
            if cur is not None:
                items.append(cur)
                cur = None
            flush_items()
            flush_para()
        else:
            para.append(line.strip())
    flush_para()
    if cur is not None:
        items.append(cur)
    flush_items()
    out += ["tags=Build 42;Misc;Multiplayer", "visibility=public"]
    with open(os.path.join(REPO, "workshop.txt"), "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(out) + "\n")
    chars = sum(len(l) - len("description=") + 1 for l in out if l.startswith("description="))
    print("workshop.txt written,", chars, "description characters (Steam limit 8000)")


if __name__ == "__main__":
    main()
