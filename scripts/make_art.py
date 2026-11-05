"""Builds the mod's icon, poster and Workshop preview (Pillow).

    py scripts/make_art.py

Writes:
  Contents/mods/TienSkillMastery/42/icon.png     128x128
  Contents/mods/TienSkillMastery/42/poster.png   512x512
  preview.png                                     512x512
A gold star over the ten mastery boxes of the Mastery tab, on a solid dark green.
"""

import math
import os

from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
MOD = os.path.join(REPO, "Contents", "mods", "TienSkillMastery", "42")

BG = (28, 32, 27)
GOLD = (255, 209, 64)
GOLD_RIM = (255, 240, 170)
BOX_EMPTY = (38, 38, 38)
BOX_RIM = (150, 150, 150)
GLOW = (255, 214, 140)
FONT_PATHS = ["C:/Windows/Fonts/arialbd.ttf", "C:/Windows/Fonts/segoeuib.ttf"]


def font(size):
    for p in FONT_PATHS:
        if os.path.exists(p):
            return ImageFont.truetype(p, size)
    return ImageFont.load_default()


def background(size):
    # Solid colour (user, 2026-11-06).
    return Image.new("RGBA", (size, size), BG + (255,))


def star_points(cx, cy, r_out, r_in, n=5):
    pts = []
    for i in range(n * 2):
        r = r_out if i % 2 == 0 else r_in
        a = -math.pi / 2 + i * math.pi / n
        pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return pts


def draw_star(img, cx, cy, r):
    glow = Image.new("RGBA", img.size, (0, 0, 0, 0))
    ImageDraw.Draw(glow).polygon(star_points(cx, cy, r * 1.1, r * 0.48), fill=GLOW + (150,))
    img.alpha_composite(glow.filter(ImageFilter.GaussianBlur(r * 0.18)))
    d = ImageDraw.Draw(img)
    d.polygon(star_points(cx, cy, r, r * 0.44), fill=GOLD, outline=GOLD_RIM)


def draw_boxes(img, cx, y, width, filled=10):
    d = ImageDraw.Draw(img)
    gap = width / 10 * 0.22
    box = (width - gap * 9) / 10
    x0 = cx - width / 2
    for i in range(10):
        x = x0 + i * (box + gap)
        fill = GOLD if i < filled else BOX_EMPTY
        d.rectangle([x, y, x + box, y + box], fill=fill, outline=BOX_RIM, width=max(1, int(box / 10)))
    return box


def icon():
    s = 128
    img = background(s)
    draw_star(img, s / 2, s * 0.42, s * 0.33)
    draw_boxes(img, s / 2, s * 0.80, s * 0.86)
    img.convert("RGB").save(os.path.join(MOD, "icon.png"))


def poster(path):
    s = 512
    img = background(s)
    draw_star(img, s / 2, s * 0.38, s * 0.24)
    box = draw_boxes(img, s / 2, s * 0.67, s * 0.80, filled=7)
    d = ImageDraw.Draw(img)
    f = font(56)
    text = "Skill Mastery"
    w = d.textlength(text, font=f)
    d.text(((s - w) / 2, s * 0.67 + box + 32), text, font=f, fill=(240, 236, 220))
    img.convert("RGB").save(path)


if __name__ == "__main__":
    icon()
    poster(os.path.join(MOD, "poster.png"))
    poster(os.path.join(REPO, "preview.png"))
    print("art written")
