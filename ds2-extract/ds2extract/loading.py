"""Step 4: the Dark Souls II loading screen as a Plymouth boot theme.

Positions, sizes and colours were measured on a 1366x768 screenshot of the game's own
loading screen: the game lays it out at 1280x720 and scales by 768/720, and it darkens
and warms the picture slightly (GRADE below). Each boot shows one random item.
"""
import json
import random
import shutil
from pathlib import Path

import numpy as np
from PIL import Image

from .text import GameFont

THEME = "majula-ds2"
W, H = 1366, 768
K = H / 720                                   # the game's 720p layout scaled to this screen
GRADE = (np.array([0.884, 0.902, 0.896]), np.array([20.2, 14.7, 8.4]))

BG_X = W - round(1024 * K)                    # background art, right-aligned
BONFIRE = (110, 560)
LOGO = (110, 667)
PLATE = (402, 216)
ICON = (406, 127)
NAME = (483, 197, 0.753)                      # x, y, scale of the game font
DESC = (485, 256, 0.595, 24.53)               # x, first line y, scale, line spacing
BLOCK = (380, 110, 1110, 660)                 # the area an item overlay covers
MAX_LINES = 14
ICON_KINDS = ("HQ_WP_IC_", "HQ_SD_IC_", "HQ_HD_IC_", "HQ_BD_IC_", "HQ_AM_IC_", "HQ_LG_IC_")


def grade(img):
    a = np.asarray(img.convert("RGBA")).astype(np.float32)
    a[..., :3] = a[..., :3] * GRADE[0] + GRADE[1]
    return Image.fromarray(a.clip(0, 255).astype(np.uint8), "RGBA")


def scaled(img, k):
    return img.resize((max(1, round(img.width * k)), max(1, round(img.height * k))), Image.LANCZOS)


def items(raw):
    names = {int(k): v for k, v in json.loads((raw / "text/item_names.json").read_text()).items()}
    descs = {int(k): v for k, v in json.loads((raw / "text/item_descriptions.json").read_text()).items()}
    out = []
    for icon in sorted((raw / "icons").glob("*.png")):
        if not icon.stem.startswith(ICON_KINDS):
            continue
        num = int(icon.stem.rsplit("_", 1)[1])
        text = descs.get(num, "").strip()
        if num in names and text and text.count("\n") < MAX_LINES:
            out.append((names[num], text, icon))
    return out


def item_overlay(font, plate, name, text, icon):
    x0, y0, x1, y1 = BLOCK
    canvas = Image.new("RGBA", (x1 - x0, y1 - y0), (0, 0, 0, 0))

    def put(img, x, y):
        canvas.alpha_composite(img, (round(x) - x0, round(y) - y0))

    put(plate, *PLATE)
    put(scaled(Image.open(icon).convert("RGBA"), 0.5 * K), *ICON)
    put(scaled(font.render(name, color=(232, 226, 224)), NAME[2]), NAME[0], NAME[1])
    x, y, k, step = DESC
    for i, line in enumerate(text.split("\n")):
        if line.strip():
            put(scaled(font.render(line.rstrip(), color=(222, 216, 214)), k), x, y + i * step)
    return grade(canvas)


def run(raw, build, count=48, seed=None):
    raw, out = Path(raw), Path(build) / "plymouth" / THEME
    if out.exists():
        shutil.rmtree(out)
    (out / "items").mkdir(parents=True)
    (out / "bonfire").mkdir()

    loading = Image.open(raw / "menu/loading/16_Loading.png").convert("RGBA")
    bg = Image.new("RGBA", (W, H), (0, 0, 0, 255))
    bg.alpha_composite(scaled(loading.crop((0, 0, 1024, 720)), K), (BG_X, 0))
    grade(bg).convert("RGB").save(out / "background.png", optimize=True)

    soul = Image.open(raw / "menu/loading/soul_sequence.png").convert("RGBA")
    for n in range(32):
        r, c = divmod(n, 8)
        frame = scaled(soul.crop((c * 128, r * 128, c * 128 + 128, r * 128 + 100)), K)
        grade(frame).convert("RGB").save(out / "bonfire" / f"{n}.png", optimize=True)
    grade(scaled(soul.crop((0, 100, 128, 128)), K)).convert("RGB").save(out / "logo.png", optimize=True)

    font = GameFont(raw)
    plate = scaled(Image.open(raw / "menu/windows/IconBase.png").convert("RGBA").crop((81, 224, 150, 255)), K)
    pool = items(raw)
    chosen = random.Random(seed).sample(pool, min(count, len(pool)))
    for n, (name, text, icon) in enumerate(chosen):
        item_overlay(font, plate, name, text, icon).save(out / "items" / f"{n}.png", optimize=True)
    (out / "items.txt").write_text("".join(f"{n}\t{name}\n" for n, (name, _, _) in enumerate(chosen)))

    script = (Path(__file__).parent / "plymouth.script").read_text()
    script = script.replace("@ITEMS@", str(len(chosen))).replace("@BG_X@", str(BG_X))
    for key, (x, y) in {"BONFIRE": BONFIRE, "LOGO": LOGO, "BLOCK": BLOCK[:2]}.items():
        script = script.replace(f"@{key}_X@", str(x)).replace(f"@{key}_Y@", str(y))
    (out / f"{THEME}.script").write_text(script)
    (out / f"{THEME}.plymouth").write_text(
        "[Plymouth Theme]\n"
        "Name=Majula DS2\n"
        "Description=The Dark Souls II loading screen, with a random item each boot\n"
        "ModuleName=script\n\n"
        "[script]\n"
        f"ImageDir=/usr/share/plymouth/themes/{THEME}\n"
        f"ScriptFile=/usr/share/plymouth/themes/{THEME}/{THEME}.script\n")

    preview = Image.open(out / "background.png").convert("RGBA")
    preview.alpha_composite(Image.open(out / "bonfire" / "0.png").convert("RGBA"), BONFIRE)
    preview.alpha_composite(Image.open(out / "logo.png").convert("RGBA"), LOGO)
    preview.alpha_composite(Image.open(out / "items" / "0.png"), BLOCK[:2])
    preview.convert("RGB").save(Path(build) / "plymouth" / "preview.png")
    size = sum(f.stat().st_size for f in out.rglob("*") if f.is_file()) / 1e6
    print(f"    {len(chosen)} items (of {len(pool)}), {size:.1f} MB -> {out}")
