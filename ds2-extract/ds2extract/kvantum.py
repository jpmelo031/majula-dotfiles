"""Step 6: a Kvantum theme ("Drangleic") for Qt apps like Dolphin, from the game's menus.

It starts from the KvDark theme that ships with Kvantum and replaces the pieces that make
the look: the dark leather of the in-game menus behind windows, toolbars and menus, the
bonfire menu's glowing orange bar for selections, the ruled dark bands for buttons, and
the game's colours. Everything else is KvDark's.
"""
import base64
import io
import re
import shutil
import xml.etree.ElementTree as ET
from pathlib import Path

from PIL import Image, ImageEnhance

BASE = Path("/usr/share/Kvantum/KvDark")
SVG, XLINK = "http://www.w3.org/2000/svg", "http://www.w3.org/1999/xlink"

TEXT = "#C5C0BC"
BRIGHT = "#F2E6D2"
LINE = "#755D4A"
EMBER = "#E0783E"

COLORS = {
    "window.color": "#16120E",
    "base.color": "#100D0A",
    "alt.base.color": "#18140F",
    "button.color": "#221B15",
    "light.color": "#5A4A3A",
    "mid.light.color": "#4A3C2E",
    "dark.color": "#0A0806",
    "mid.color": "#2A221A",
    "highlight.color": "#8C5A2E",
    "inactive.highlight.color": "#5A3E26",
    "text.color": TEXT,
    "window.text.color": TEXT,
    "button.text.color": TEXT,
    "disabled.text.color": "#7A7266",
    "tooltip.text.color": TEXT,
    "highlight.text.color": BRIGHT,
    "link.color": "#D1A35C",
    "link.visited.color": EMBER,
    "progress.indicator.text.color": BRIGHT,
}

SECTIONS = """
[Window]
interior=true
interior.element=window
frame=false

[Menu]
inherits=PanelButtonCommand
frame.top=1
frame.bottom=1
frame.left=1
frame.right=1
frame.element=menu
interior.element=menu
text.normal.color={text}
text.shadow=false
frame.expansion=0

[ToolTip]
inherits=GenericFrame
frame.top=1
frame.bottom=1
frame.left=1
frame.right=1
interior=true
interior.element=menu
frame.element=menu
text.normal.color={text}
text.shadow=false
""".format(text=TEXT)


def png_uri(img):
    buf = io.BytesIO()
    img.save(buf, "PNG", optimize=True)
    return "data:image/png;base64," + base64.b64encode(buf.getvalue()).decode()


class Pieces:
    """New SVG elements, laid out in a column far from KvDark's own drawings."""

    def __init__(self):
        self.elements, self.y = [], 0

    def _place(self, h):
        y = self.y
        self.y += h + 10
        return 10000, y

    def image(self, eid, img, w, h, opacity=1.0):
        x, y = self._place(h)
        el = ET.Element(f"{{{SVG}}}image", {
            "id": eid, "x": str(x), "y": str(y), "width": str(w), "height": str(h),
            "preserveAspectRatio": "none", "opacity": str(opacity), f"{{{XLINK}}}href": png_uri(img)})
        self.elements.append(el)

    def rect(self, eid, color, opacity, w=10, h=10):
        x, y = self._place(h)
        self.elements.append(ET.Element(f"{{{SVG}}}rect", {
            "id": eid, "x": str(x), "y": str(y), "width": str(w), "height": str(h),
            "fill": color, "fill-opacity": str(opacity)}))

    def edge(self, eid, side, color, opacity):
        """A frame piece: a 1/3-thick line on its outer side, transparent elsewhere."""
        x, y = self._place(9)
        g = ET.Element(f"{{{SVG}}}g", {"id": eid})
        ET.SubElement(g, f"{{{SVG}}}rect", {"x": str(x), "y": str(y), "width": "9", "height": "9", "fill-opacity": "0"})
        line = {"top": (x, y, 9, 3), "bottom": (x, y + 6, 9, 3), "left": (x, y, 3, 9), "right": (x + 6, y, 3, 9)}.get(side)
        if line:
            lx, ly, lw, lh = line
            ET.SubElement(g, f"{{{SVG}}}rect", {"x": str(lx), "y": str(ly), "width": str(lw), "height": str(lh),
                                               "fill": color, "fill-opacity": str(opacity)})
        self.elements.append(g)

    def frame(self, prefix, sides, color, opacity):
        """All eight frame pieces of prefix; lines only on the given sides."""
        for part in ("top", "bottom", "left", "right", "topleft", "topright", "bottomleft", "bottomright"):
            self.edge(f"{prefix}-{part}", part if part in sides else "none", color, opacity)


def run(raw, build):
    raw, build = Path(raw), Path(build)
    if not BASE.exists():
        print("    Kvantum is not installed (sudo pacman -S kvantum); skipping")
        return
    out = build / "kvantum" / "Drangleic"
    if out.exists():
        shutil.rmtree(out)
    out.mkdir(parents=True)

    # Textures: the big leather panel of the in-game menus, its smaller dialog strip, the
    # bonfire menu's selection bar (built by the rofi step).
    leather = Image.open(raw / "menu/bonfire/BonFire_01.png").convert("RGB").crop((70, 80, 960, 500))
    strip = Image.open(raw / "menu/windows/Big_Dialog_BG.png").convert("RGB").crop((40, 40, 980, 215))
    leather = ImageEnhance.Brightness(leather).enhance(0.85)
    selected = Image.open(build / "rofi/selected.png").convert("RGBA")

    p = Pieces()
    p.image("window-normal", leather, 890, 420)
    p.image("toolbar-normal", strip, 940, 175)
    p.frame("toolbar-normal", ("bottom",), LINE, 0.8)
    p.image("menu-normal", strip, 940, 175)
    p.frame("menu-normal", ("top", "bottom", "left", "right"), LINE, 0.9)

    # Selected files and menu entries: the glowing orange bar; hovering shows it faintly.
    for state, opacity in (("pressed", 1.0), ("toggled", 1.0), ("focused", 0.35)):
        p.image(f"itemview-{state}", selected, 358, 29, opacity)
        p.frame(f"itemview-{state}", (), LINE, 0)
    for state in ("pressed", "toggled"):
        p.image(f"menuitem-{state}", selected, 358, 29)
        p.frame(f"menuitem-{state}", (), LINE, 0)

    # Buttons: dark ruled bands; pressed and checked ones glow orange.
    for state, line, fill in (("normal", LINE, 0.35), ("focused", "#9A6A40", 0.45)):
        p.rect(f"button-{state}", "#000000", fill)
        p.frame(f"button-{state}", ("top", "bottom"), line, 0.95)
    for state in ("pressed", "toggled"):
        p.image(f"button-{state}", selected, 358, 29)
        p.frame(f"button-{state}", (), LINE, 0)

    # Scrollbars in the menus' brown, orange while dragged.
    for state, color in (("normal", "#6E5A46"), ("focused", "#9A6A40"), ("pressed", EMBER)):
        for part in ("top", "bottom", "left", "right", "topleft", "topright", "bottomleft", "bottomright"):
            p.rect(f"scrollbarslider-{state}-{part}", color, 0.9)

    replaced = {el.get("id") for el in p.elements}
    for ns, prefix in (("svg", SVG), ("xlink", XLINK), ("inkscape", "http://www.inkscape.org/namespaces/inkscape"),
                       ("sodipodi", "http://sodipodi.sourceforge.net/DTD/sodipodi-0.dtd")):
        ET.register_namespace("" if ns == "svg" else ns, prefix)
    tree = ET.parse(BASE / "KvDark.svg")
    root = tree.getroot()
    for parent in list(root.iter()):
        for child in list(parent):
            if child.get("id") in replaced:
                parent.remove(child)
    root.extend(p.elements)
    tree.write(out / "Drangleic.svg", xml_declaration=True, encoding="UTF-8")

    cfg = (BASE / "KvDark.kvconfig").read_text()
    for key, value in COLORS.items():
        cfg = re.sub(rf"^{re.escape(key)}=.*$", f"{key}={value}", cfg, flags=re.M)
    cfg = re.sub(r"^(text\.\w+\.color)=black$", rf"\1={BRIGHT}", cfg, flags=re.M)
    cfg = re.sub(r"^(text\.\w+\.color)=white$", rf"\1={TEXT}", cfg, flags=re.M)
    cfg = re.sub(r"^comment=.*$", "comment=Dark Souls II menus, built by ds2-extract from KvDark", cfg, flags=re.M)
    # drop KvDark's own [Menu]/[ToolTip]/[Window] sections; ours follow
    for name in ("Menu", "ToolTip", "Window"):
        cfg = re.sub(rf"^\[{name}\]\n(?:(?!\[).*\n?)*", "", cfg, flags=re.M)
    (out / "Drangleic.kvconfig").write_text(cfg.rstrip() + "\n" + SECTIONS)
    size = sum(f.stat().st_size for f in out.iterdir()) / 1e6
    print(f"    Kvantum theme Drangleic ({size:.1f} MB) -> {out}")
