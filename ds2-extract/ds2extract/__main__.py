import argparse
import sys
from pathlib import Path

DEFAULT_GAME = Path.home() / ".local/share/Steam/steamapps/common/Dark Souls II Scholar of the First Sin/Game"
REPO = Path(__file__).resolve().parents[2]


def main():
    p = argparse.ArgumentParser(
        prog="extract",
        description="Pull the Dark Souls II menu art, font and item texts out of your own copy of the game "
                    "and build the rofi, font and boot-screen assets from them.")
    p.add_argument("--game", type=Path, default=DEFAULT_GAME,
                   help="the game's Game folder (default: the Steam library in your home folder)")
    p.add_argument("--out", type=Path, default=REPO / "ds2-assets",
                   help="where to write everything (default: ds2-assets/ in the repo)")
    p.add_argument("steps", nargs="*", choices=["extract", "font", "rofi", "boot", "desktop", "kvantum", "all"], default=["all"],
                   help="what to do (default: all)")
    a = p.parse_args()
    steps = {"extract", "font", "rofi", "boot", "desktop", "kvantum"} if "all" in a.steps else set(a.steps)
    raw, build = a.out / "raw", a.out / "build"

    if "extract" in steps:
        if not (a.game / "GameDataEbl.bhd").exists():
            sys.exit(f"Dark Souls II not found in {a.game}\nPass the game's Game folder with --game.")
        print("==> Extracting from the game")
        from . import extract
        extract.run(a.game, raw)
    if not (raw / "font").exists():
        sys.exit(f"Nothing extracted yet in {raw}; run the extract step first.")
    if "font" in steps:
        print("==> Building the Drangleic font")
        from . import font
        font.run(raw, build)
    if "rofi" in steps:
        print("==> Building the bonfire menu (rofi)")
        from . import bonfire
        bonfire.run(raw, build)
    if "boot" in steps:
        print("==> Building the loading screen (Plymouth)")
        from . import loading
        loading.run(raw, build)
    if "desktop" in steps:
        print("==> Building the cursor and notification art")
        from . import desktop
        desktop.run(raw, build)
    if "kvantum" in steps:
        print("==> Building the Kvantum theme for Qt apps (Dolphin)")
        from . import kvantum
        kvantum.run(raw, build)
    print(f"Done. Everything is in {a.out}")


main()
