"""Step 1: copy the pieces we use out of the game into ds2-assets/raw/."""
import json
from pathlib import Path

from . import formats
from .archive import GameArchive

# Menu bundles, by the layout file (or texture) each one carries. The hashes are the ones in the
# Steam release of Scholar of the First Sin; if a patch moves them, the bundles are
# found again by scanning for the layout file name.
BUNDLES = {
    "bonfire": (0x5C9C5AC4, "l03_01_Bonfire.flo"),
    "loading": (0xC5555D93, "l20_01_Loading.flo"),
    "windows": (0xB1FA153F, "l80_01_window.flo"),
}
# English item names and long item descriptions, recognised by the Uchigatana (1700000).
TEXTS = {
    "item_names": (0x70C958C8, lambda t: t.get(1700000) == "Uchigatana" and t.get(1000000) == "Dagger"),
    "item_descriptions": (0x4CE6C467, lambda t: t.get(1700000, "").startswith("A katana of unknown origin")),
}
# High-quality item icons shown on the loading screen: weapons, shields and armour.
ICON_PREFIXES = ("HQ_WP_IC_", "HQ_SD_IC_", "HQ_HD_IC_", "HQ_BD_IC_", "HQ_AM_IC_", "HQ_LG_IC_", "HQ_IT_IC_")


def log(msg):
    print(f"    {msg}", flush=True)


def _find_bundle(arc, known_hash, flo):
    rec = arc.records.get(known_hash)
    if rec is not None:
        data = formats.undcx(arc.read(rec))
        if data[:4] == b"BND4" and flo in formats.bnd4_names(data):
            return data
    log(f"{flo} moved; scanning the archive for it")
    for rec in arc:
        head = arc.read(rec, 4)
        if head not in (b"BND4", b"DCX\0") or rec.size > 8_000_000:
            continue
        data = formats.undcx(arc.read(rec))
        if data[:4] == b"BND4" and flo in formats.bnd4_names(data):
            return data
    raise SystemExit(f"Could not find {flo} in the game data.")


def _find_text(arc, known_hash, check):
    rec = arc.records.get(known_hash)
    if rec is not None:
        try:
            table = formats.fmg(arc.read(rec))
            if check(table):
                return table
        except ValueError:
            pass
    log("text table moved; scanning the archive for it")
    for rec in arc:
        if arc.read(rec, 4) != b"\0\0\1\0":
            continue
        try:
            table = formats.fmg(arc.read(rec))
        except Exception:
            continue
        if check(table):
            return table
    raise SystemExit("Could not find the English item texts in the game data.")


def run(game_dir, raw_dir):
    game_dir, raw_dir = Path(game_dir), Path(raw_dir)
    arc = GameArchive(game_dir)
    log(f"opened GameDataEbl ({len(arc.records)} files)")

    for name, (h, flo) in BUNDLES.items():
        out = raw_dir / "menu" / name
        out.mkdir(parents=True, exist_ok=True)
        count = 0
        for fname, blob in formats.bnd4(_find_bundle(arc, h, flo)):
            blob = formats.undcx(blob)
            if blob[:4] != b"TPF\0":
                continue
            for tex_name, img in formats.tpf(blob):
                img.save(out / f"{tex_name}.png")
                count += 1
        log(f"menu/{name}: {count} textures")

    out = raw_dir / "text"
    out.mkdir(parents=True, exist_ok=True)
    for name, (h, check) in TEXTS.items():
        table = _find_text(arc, h, check)
        (out / f"{name}.json").write_text(json.dumps(table, ensure_ascii=False, indent=1))
        log(f"text/{name}.json: {len(table)} entries")

    out = raw_dir / "icons"
    out.mkdir(parents=True, exist_ok=True)
    count = 0
    for rec in arc:
        if rec.size > 200_000 or arc.read(rec, 4) != b"TPF\0":
            continue
        data = arc.read(rec)
        names = formats.tpf_names(data)
        if len(names) != 1 or not names[0].startswith(ICON_PREFIXES):
            continue
        for tex_name, img in formats.tpf(data):
            img.save(out / f"{tex_name}.png")
            count += 1
    log(f"icons: {count} item icons")

    out = raw_dir / "font"
    out.mkdir(parents=True, exist_ok=True)
    for size in ("Big", "Small"):
        bnd = formats.undcx((game_dir / "font" / "English" / f"FeFont_{size}.fontbnd.dcx").read_bytes())
        for fname, blob in formats.bnd4(bnd):
            blob = formats.undcx(blob)
            if fname.endswith(".ccm"):
                metrics = formats.ccm(blob)
                metrics["glyphs"] = {str(k): v for k, v in metrics["glyphs"].items()}
                (out / f"FeFont_{size}.json").write_text(json.dumps(metrics))
            elif blob[:4] == b"TPF\0":
                for tex_name, img in formats.tpf(blob):
                    img.save(out / f"{tex_name}.png")
    log("font: FeFont_Big and FeFont_Small (glyph pages and metrics)")
