"""Step 3: the bonfire menu (rofi) built from the game's own window pieces.

The layout follows a 1366x768 screenshot of the game's bonfire menu ("The Far Fire"),
minus the controller hints at the bottom: a parchment window, a dark title band, an
ornate list frame with 11 ruled rows, ^ and v arrows, and the glowing orange bar that
marks the selected row. Window coordinates below are pixels in that screenshot minus
the window's top-left corner.
"""
from pathlib import Path

import numpy as np
from PIL import Image, ImageOps

K = 768 / 720                      # the game's 720p UI scaled to a 768-px-tall screen
WIN = (448, 504)                   # window size
TITLE_BAND = (34, 24, 418, 80)     # x0, y0, x1, y1
ROWS = (132, 29, 11)               # first row top, row height, number of rows
LIST = (28, 129, 418, 452)         # dark list area behind the rows
ROW_X = (39, 397)                  # where the separator lines and the selection bar run
FRAME_X = (23, 423)                # outer edges of the list frame
FRAME_TOP = 103
FRAME_BOTTOM = 434
ARROW_X = 216                      # centre of the ^ and v arrows
ARROW_UP_Y, ARROW_DOWN_Y = 91, 478
ROW_LINE_LIGHT, ROW_LINE_DARK = (117, 93, 74), (54, 41, 30)
# Colour of the selected row by distance from its edge, outer edge first (measured in the game).
SELECTION_PROFILE = [(129, 87, 46), (150, 98, 45), (139, 92, 44), (127, 83, 44), (117, 78, 46),
                     (109, 74, 47), (104, 72, 47), (100, 70, 47), (96, 69, 47), (94, 68, 47),
                     (93, 68, 46), (92, 67, 46), (91, 67, 46)]


def scaled(img, kx, ky=None):
    ky = kx if ky is None else ky
    return img.resize((max(1, round(img.width * kx)), max(1, round(img.height * ky))), Image.LANCZOS)


def with_opacity(img, opacity):
    a = np.asarray(img).copy()
    a[..., 3] = (a[..., 3].astype(np.float32) * opacity).astype(np.uint8)
    return Image.fromarray(a, "RGBA")


def parchment_window(parchment):
    """The parchment stretched to the window: top half as drawn, bottom half mirrored."""
    w, h = WIN
    k = w / parchment.width
    half = scaled(parchment, k)
    top = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    top.alpha_composite(half, (0, 0))
    bottom = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    bottom.alpha_composite(ImageOps.flip(half), (0, h - half.height))
    # cross-fade where the two halves overlap
    overlap0, overlap1 = h - half.height, half.height
    t = np.clip((np.arange(h) - overlap0) / max(1, overlap1 - overlap0), 0, 1)[:, None, None]
    out = np.asarray(top).astype(np.float32) * (1 - t) + np.asarray(bottom).astype(np.float32) * t
    return Image.fromarray(out.clip(0, 255).astype(np.uint8), "RGBA")


def darken(img, box, top_factor, bottom_factor):
    """Multiplies the colours inside box by a factor that changes from top to bottom."""
    x0, y0, x1, y1 = box
    a = np.asarray(img).astype(np.float32)
    t = np.linspace(0, 1, y1 - y0)[:, None, None] ** 1.3
    f = top_factor + (bottom_factor - top_factor) * t
    a[y0:y1, x0:x1, :3] *= f
    return Image.fromarray(a.clip(0, 255).astype(np.uint8), "RGBA")


def run(raw, build):
    win_dir = Path(raw) / "menu" / "windows"
    out = Path(build) / "rofi"
    out.mkdir(parents=True, exist_ok=True)
    help_sort = Image.open(win_dir / "Help_Sort_02.png").convert("RGBA")
    coution = Image.open(win_dir / "coution.png").convert("RGBA")
    waku = Image.open(win_dir / "waku.png").convert("RGBA")
    waku2 = Image.open(win_dir / "waku_02.png").convert("RGBA")

    # Parchment window and the darker list area (the game shades it towards the bottom).
    win = parchment_window(help_sort.crop((70, 0, 507, 256)))
    win = darken(win, LIST, 0.56, 0.25)

    # Title band: the caution panel's dark centre, half transparent over the parchment.
    band = coution.crop((15, 14, 492, 114))
    x0, y0, x1, y1 = TITLE_BAND
    band = with_opacity(band.resize((x1 - x0, y1 - y0), Image.LANCZOS), 0.56)
    a = np.asarray(band).astype(np.float32)
    ramp = np.clip(np.minimum(np.arange(x1 - x0), np.arange(x1 - x0)[::-1]) / 14, 0, 1)
    a[..., 3] *= ramp[None, :]
    win.alpha_composite(Image.fromarray(a.astype(np.uint8), "RGBA"), (x0, y0))
    edge = with_opacity(waku.crop((7, 67, 504, 69)).resize((x1 - x0 - 16, 2), Image.LANCZOS), 0.7)
    win.alpha_composite(edge, (x0 + 8, y0 - 1))
    win.alpha_composite(edge, (x0 + 8, y1))

    # Ruled rows: a light line over a dark one under every row (colours measured in the game).
    top, step, count = ROWS
    a = np.asarray(win).copy()
    for i in range(1, count + 1):
        y = top + i * step - 1
        a[y, ROW_X[0]:ROW_X[1], :3] = ROW_LINE_LIGHT
        a[y + 1, ROW_X[0]:ROW_X[1], :3] = ROW_LINE_DARK
    win = Image.fromarray(a, "RGBA")

    # List frame: corners with filigree, the centre ornament, mirrored on the right.
    corner_top = scaled(waku.crop((5, 1, 310, 52)), K)
    corner_bottom = scaled(waku.crop((5, 84, 310, 126)), K)
    ornament_top = scaled(waku.crop((314, 2, 508, 24)), K)
    ornament_bottom = scaled(waku.crop((314, 103, 508, 125)), K)
    fl, fr = FRAME_X
    side = scaled(waku.crop((5, 46, 30, 47)), K, 1)
    side_y0 = FRAME_TOP + corner_top.height - 2
    side_y1 = FRAME_BOTTOM + 4
    side = side.resize((side.width, side_y1 - side_y0))
    win.alpha_composite(side, (fl, side_y0))
    win.alpha_composite(ImageOps.mirror(side), (fr - side.width, side_y0))
    win.alpha_composite(corner_top, (fl, FRAME_TOP))
    win.alpha_composite(ImageOps.mirror(corner_top), (fr - corner_top.width, FRAME_TOP))
    win.alpha_composite(corner_bottom, (fl, FRAME_BOTTOM))
    win.alpha_composite(ImageOps.mirror(corner_bottom), (fr - corner_bottom.width, FRAME_BOTTOM))
    win.alpha_composite(ornament_top, (110, FRAME_TOP + 1))
    win.alpha_composite(ornament_bottom, (112, FRAME_BOTTOM + 21))

    # ^ and v: the menu chevron turned up and down.
    chevron = scaled(waku2.crop((180, 94, 195, 117)), 0.7)
    up, down = chevron.rotate(90, expand=True), chevron.rotate(-90, expand=True)
    for _ in range(2):   # drawn twice: the game's arrows glow brighter than the bare texture
        win.alpha_composite(up, (ARROW_X - up.width // 2, ARROW_UP_Y))
        win.alpha_composite(down, (ARROW_X - down.width // 2, ARROW_DOWN_Y))
    win.save(out / "window.png", optimize=True)

    # Selection: an orange-edged bar. Its colours by distance from the edge were measured on
    # the game's highlighted row; the grain comes from the bonfire menu's orange box texture.
    w, h = ROW_X[1] - ROW_X[0], step
    yy, xx = np.mgrid[0:h, 0:w]
    d = np.minimum(np.minimum(yy, h - 1 - yy), np.minimum(xx, w - 1 - xx))
    prof = np.array(SELECTION_PROFILE, np.float32)
    rgb = prof[np.minimum(d, len(prof) - 1)]
    grain = np.asarray(Image.open(Path(raw) / "menu/bonfire/BonFire_01.png").convert("L")
                       .crop((235, 855, 358, 912)).resize((w, h), Image.LANCZOS)).astype(np.float32)
    rgb *= (1 + 0.35 * (grain - grain.mean()) / grain.mean())[..., None]
    bar = np.dstack([rgb.clip(0, 255), np.full((h, w), 255.0)]).astype(np.uint8)
    Image.fromarray(bar, "RGBA").save(out / "selected.png", optimize=True)
    print(f"    window.png ({WIN[0]}x{WIN[1]}) and selected.png -> {out}")
