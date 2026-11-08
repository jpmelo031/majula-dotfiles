"""Draws text the way the game does: glyphs straight from its font pages, light fill over a dark outline."""
import json
from pathlib import Path

import numpy as np
from PIL import Image

from .font import load_pages


class GameFont:
    def __init__(self, raw, size="Big"):
        raw_font = Path(raw) / "font"
        m = json.loads((raw_font / f"FeFont_{size}.json").read_text())
        self.line = m["height"]
        self.glyphs = {int(k): v for k, v in m["glyphs"].items()}
        self.pages = load_pages(raw_font, size)

    def width(self, text, tracking=0):
        return sum(self.glyphs.get(ord(c), self.glyphs[0x20])["advance"] + tracking for c in text)

    def render(self, text, color=(222, 216, 200), outline=(0, 0, 0), outline_opacity=0.6, tracking=0):
        """One line of text as an RGBA image at the font's native size (41 px line)."""
        w = max(1, self.width(text, tracking) + 4)
        fill = np.zeros((self.line + 1, w), np.float32)
        edge = np.zeros_like(fill)
        x = 0
        for c in text:
            g = self.glyphs.get(ord(c)) or self.glyphs[0x20]
            x1, y1, x2, y2 = g["box"]
            page = self.pages[g["page"]]
            cell = page[y1:y2, x1:x2].astype(np.float32) / 255
            h = min(cell.shape[0], fill.shape[0])
            cw = min(cell.shape[1], w - (x + g["pre"]))
            if cw > 0 and g["page"] != 0:
                sl = (slice(0, h), slice(x + g["pre"], x + g["pre"] + cw))
                fill[sl] = np.maximum(fill[sl], (cell[:h, :cw, 1] - 0.051) / (0.871 - 0.051))
                edge[sl] = np.maximum(edge[sl], cell[:h, :cw, 3])
            x += g["advance"] + tracking
        fill = fill.clip(0, 1) ** 1.2   # the game draws slightly thinner strokes
        a = np.maximum(fill, edge * outline_opacity)
        rgb = np.zeros((*fill.shape, 3), np.float32)
        safe = np.where(a > 0, a, 1)[..., None]
        rgb = (fill[..., None] * np.array(color) + (a - fill)[..., None] * np.array(outline)) / safe
        out = np.dstack([rgb.clip(0, 255), (a * 255)[..., None]]).astype(np.uint8)
        return Image.fromarray(out, "RGBA")

    def render_scaled(self, text, px_line, **kw):
        """The same, scaled so one line is `px_line` pixels tall."""
        img = self.render(text, **kw)
        s = px_line / self.line
        return img.resize((max(1, round(img.width * s)), max(1, round(img.height * s))), Image.LANCZOS)
