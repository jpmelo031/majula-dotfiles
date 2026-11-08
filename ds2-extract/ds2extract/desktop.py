"""Step 5: the rest of the desktop in Dark Souls II style.

  cursor/         the game's menu cursor as an Xcursor theme ("Drangleic")
  ../windows/     the same cursor as a Windows .cur, for windows/theme.ps1
  notifications/  panel textures for swaync
"""
import struct
from pathlib import Path

import numpy as np
from PIL import Image


# ------------------------------------------------------------------ cursor

def xcursor(images):
    """An Xcursor file from [(nominal size, RGBA image, (hot x, hot y))]."""
    head = struct.pack("<4sIII", b"Xcur", 16, 0x10000, len(images))
    toc, chunks, pos = b"", b"", 16 + 12 * len(images)
    for nominal, img, (hx, hy) in images:
        px = np.asarray(img.convert("RGBA")).astype(np.uint32)
        a = px[..., 3]
        argb = (a << 24) | (px[..., 0] * a // 255 << 16) | (px[..., 1] * a // 255 << 8) | (px[..., 2] * a // 255)
        chunk = struct.pack("<9I", 36, 0xFFFD0002, nominal, 1, img.width, img.height, hx, hy, 0)
        chunk += argb.astype("<u4").tobytes()
        toc += struct.pack("<3I", 0xFFFD0002, nominal, pos)
        chunks += chunk
        pos += len(chunk)
    return head + toc + chunks


def wincursor(images):
    """A Windows .cur file from [(RGBA image, (hot x, hot y))]: 32-bit images with alpha."""
    head = struct.pack("<3H", 0, 2, len(images))
    entries, blobs, pos = b"", b"", 6 + 16 * len(images)
    for img, (hx, hy) in images:
        w, h = img.size
        px = np.asarray(img.convert("RGBA"))[::-1]                 # rows bottom-up
        color = px[..., [2, 1, 0, 3]].tobytes()                    # BGRA
        mask = np.packbits(px[..., 3] == 0, axis=1)                # 1 = see-through
        mask = np.pad(mask, ((0, 0), (0, (w + 31) // 32 * 4 - mask.shape[1]))).tobytes()
        dib = struct.pack("<IiiHHIIiiII", 40, w, h * 2, 1, 32, 0, len(color) + len(mask), 0, 0, 0, 0)
        dib += color + mask
        entries += struct.pack("<4B2H2I", w % 256, h % 256, 0, 0, hx, hy, len(dib), pos)
        blobs += dib
        pos += len(dib)
    return head + entries + blobs


def cursor(raw, out):
    img = Image.open(raw / "menu/windows/cursor.png").convert("RGBA")
    a = np.asarray(img)[..., 3]
    top = int(np.where((a > 128).any(1))[0][0])
    hot = (int(np.where(a[top] > 128)[0][0]), top)
    sizes = [(24, 1.0), (36, 1.5), (48, 2.0), (64, 2.75)]
    images = [(n, img if k == 1 else img.resize((round(32 * k),) * 2, Image.LANCZOS),
               (round(hot[0] * k), round(hot[1] * k))) for n, k in sizes]
    theme = out / "Drangleic"
    (theme / "cursors").mkdir(parents=True, exist_ok=True)
    (theme / "cursors" / "left_ptr").write_bytes(xcursor(images))
    for alias in ("default", "arrow", "top_left_arrow", "left_arrow"):
        link = theme / "cursors" / alias
        link.unlink(missing_ok=True)
        link.symlink_to("left_ptr")
    (theme / "index.theme").write_text(
        "[Icon Theme]\nName=Drangleic\nComment=The Dark Souls II menu cursor\nInherits=Adwaita\n")
    print(f"    cursor: Drangleic (hotspot {hot})")
    # Windows draws cursors at 32 px on a 100% screen and picks the closest size when scaled.
    win = out.parent.parent / "windows"
    win.mkdir(parents=True, exist_ok=True)
    (win / "Drangleic.cur").write_bytes(wincursor(
        [(img if n == 32 else img.resize((n, n), Image.LANCZOS), (round(hot[0] * n / 32), round(hot[1] * n / 32)))
         for n in (32, 48, 64, 96, 128)]))
    print(f"    cursor: {win / 'Drangleic.cur'}")


# ----------------------------------------------------------- notifications

def notifications(raw, out):
    out.mkdir(parents=True, exist_ok=True)
    w = raw / "menu/windows"
    # The dark leather of the in-game menus with its torn edge, and the parchment.
    Image.open(w / "Big_Dialog_BG.png").convert("RGBA").save(out / "leather.png", optimize=True)
    Image.open(w / "Help_Sort_02.png").convert("RGBA").crop((70, 0, 507, 256)).save(out / "parchment.png", optimize=True)
    line = Image.open(w / "waku.png").convert("RGBA").crop((7, 67, 504, 69))
    line.save(out / "line.png", optimize=True)
    print(f"    notifications: textures -> {out}")


def run(raw, build):
    raw, build = Path(raw), Path(build)
    out = build / "desktop"
    cursor(raw, out / "icons")
    notifications(raw, out / "notifications")
