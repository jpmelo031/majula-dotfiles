"""Step 2: turn the game's bitmap font into a real font (Drangleic.otf).

Dark Souls II draws text from pre-rendered glyph pages (42 px tall cells). Each glyph is
cut out of its page, upscaled, traced into curves and placed with the game's own spacing,
so the result is the same typeface at any size.
"""
import json
from pathlib import Path

import numpy as np
import potrace
from fontTools.fontBuilder import FontBuilder
from fontTools.pens.t2CharStringPen import T2CharStringPen
from PIL import Image

FAMILY = "Drangleic"
UNITS_PER_PX = 25          # 40 px of the game's font = 1000 units = 1 em
UPSCALE = 8                # trace at 8x for smooth curves


def load_pages(raw_font, size="Big"):
    files = sorted(Path(raw_font).glob(f"FeFont_{size}_*.png"), key=lambda p: int(p.stem.split("_")[2]))
    return [np.asarray(Image.open(f).convert("RGBA")) for f in files]


def wanted(code):
    # Latin, Greek, Cyrillic, punctuation and symbols; no CJK or button icons.
    return 0x20 <= code < 0x3000 and not (0x7F <= code < 0xA0)


def ink_rows(fill):
    rows = np.where(fill.max(axis=1) > 110)[0]
    return (rows[0], rows[-1]) if len(rows) else (None, None)


def glyph_fill(pages, g):
    x1, y1, x2, y2 = g["box"]
    return pages[g["page"]][y1:y2, x1:x2, 1].astype(np.float32)  # green = glyph fill, alpha = outline


def trace(fill):
    h, w = fill.shape
    if h == 0 or w == 0:
        return []
    big = Image.fromarray(fill.clip(0, 255).astype(np.uint8)).resize((w * UPSCALE, h * UPSCALE), Image.LANCZOS)
    ink = np.asarray(big) > 135            # 61% of the game's 222 text white: the game draws thin strokes
    if not ink.any():
        return []
    return potrace.Bitmap(~ink).trace(turdsize=6, alphamax=1.0, opticurve=True, opttolerance=0.2)


def draw(pen, curves, x0, baseline):
    def pt(p):
        return (round((x0 + p.x / UPSCALE) * UNITS_PER_PX), round((baseline - p.y / UPSCALE) * UNITS_PER_PX))

    for curve in curves:
        pen.moveTo(pt(curve.start_point))
        for seg in curve.segments:
            if seg.is_corner:
                pen.lineTo(pt(seg.c))
                pen.lineTo(pt(seg.end_point))
            else:
                pen.curveTo(pt(seg.c1), pt(seg.c2), pt(seg.end_point))
        pen.closePath()


def run(raw, build):
    raw_font = Path(raw) / "font"
    metrics = json.loads((raw_font / "FeFont_Big.json").read_text())
    glyphs = {int(k): v for k, v in metrics["glyphs"].items()}
    pages = load_pages(raw_font)

    baseline = ink_rows(glyph_fill(pages, glyphs[ord("H")]))[1] + 1
    cap_top = ink_rows(glyph_fill(pages, glyphs[ord("H")]))[0]
    x_top = ink_rows(glyph_fill(pages, glyphs[ord("x")]))[0]
    desc = ink_rows(glyph_fill(pages, glyphs[ord("p")]))[1] + 1
    line = metrics["height"]

    order, cmap, charstrings, advances = [".notdef"], {}, {}, {}
    pen = T2CharStringPen(500, None)
    pen.moveTo((50, 0)); pen.lineTo((450, 0)); pen.lineTo((450, 700)); pen.lineTo((50, 700)); pen.closePath()
    charstrings[".notdef"] = pen.getCharString()
    advances[".notdef"] = 500

    codes = sorted(c for c in glyphs if wanted(c))
    for n, code in enumerate(codes):
        g = glyphs[code]
        name = f"uni{code:04X}"
        curves = trace(glyph_fill(pages, g)) if code != 0x20 else []
        pen = T2CharStringPen(round(g["advance"] * UNITS_PER_PX), None)
        draw(pen, curves, g["pre"], baseline)
        charstrings[name] = pen.getCharString()
        advances[name] = round(g["advance"] * UNITS_PER_PX)
        order.append(name)
        cmap[code] = name
        if n % 100 == 0:
            print(f"    traced {n}/{len(codes)} glyphs", flush=True)

    ascent = round(baseline * UNITS_PER_PX)
    descent = -round((line - baseline) * UNITS_PER_PX)
    fb = FontBuilder(1000, isTTF=False)
    fb.setupGlyphOrder(order)
    fb.setupCharacterMap(cmap)
    fb.setupCFF(FAMILY, {"FullName": FAMILY}, charstrings, {})
    lsb = {}
    for name, cs in charstrings.items():
        bounds = cs.calcBounds(None)
        lsb[name] = bounds[0] if bounds else 0
    fb.setupHorizontalMetrics({n: (advances[n], lsb[n]) for n in order})
    fb.setupHorizontalHeader(ascent=ascent, descent=descent)
    fb.setupNameTable({"familyName": FAMILY, "styleName": "Regular",
                       "uniqueFontIdentifier": f"{FAMILY}-Regular",
                       "fullName": f"{FAMILY} Regular", "psName": f"{FAMILY}-Regular",
                       "version": "Version 1.000",
                       "description": "Traced from the Dark Souls II in-game font. Personal use only."})
    fb.setupOS2(sTypoAscender=ascent, sTypoDescender=descent, sTypoLineGap=0,
                usWinAscent=ascent, usWinDescent=-descent,
                sxHeight=round((baseline - x_top) * UNITS_PER_PX),
                sCapHeight=round((baseline - cap_top) * UNITS_PER_PX))
    fb.setupPost()
    out = Path(build) / "fonts"
    out.mkdir(parents=True, exist_ok=True)
    fb.save(out / f"{FAMILY}.otf")
    print(f"    {len(codes)} glyphs -> {out / f'{FAMILY}.otf'} (descender row {desc})")
