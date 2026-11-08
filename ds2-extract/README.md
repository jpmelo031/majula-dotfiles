# ds2-extract

Builds the Dark Souls II look of this desktop from **your own copy of the game**:

- **Drangleic**, the game's menu font, traced from its glyph pages into a real font (`Drangleic.otf`)
- the **bonfire menu** for Rofi (the parchment window, title band, ornate frame, ruled rows and the glowing selection bar)
- the **loading screen** for Plymouth (the book, the animated bonfire, the DARK SOULS II logo and a random item with its icon and description on every boot)
- the menu **cursor** and a **Kvantum theme** for Qt apps like Dolphin

Nothing from the game is stored in this repository. The tool reads the game files, and everything it makes goes to `ds2-assets/` (ignored by git).

## Requirements

- Dark Souls II: Scholar of the First Sin (Steam). It looks in `~/.local/share/Steam/steamapps/common/Dark Souls II Scholar of the First Sin/Game` by default.
- Python 3 (the tool creates its own environment in `ds2-extract/.venv` on the first run and installs Pillow, NumPy, cryptography, fontTools and potracer there).
- `kvantum` installed, for the Qt theme (it starts from Kvantum's KvDark).

## Usage

```bash
ds2-extract/extract                 # everything: extract, font, rofi, boot, desktop, kvantum
ds2-extract/extract --game /path/to/Game
ds2-extract/extract boot            # rebuild only the loading screen (picks 48 new random items)
```

Then install the results:

```bash
./install.sh                        # font, bonfire menu, cursor, Qt theme
sudo bash system/apply-system.sh    # loading screen (needs the plymouth package)
```

Steps you can run on their own: `extract`, `font`, `rofi`, `boot`, `desktop`, `kvantum` (`all` is the default). Everything after `extract` works from the extracted files, so the game is only read once.

## What ends up where

```
ds2-assets/
├── raw/                      straight from the game
│   ├── menu/bonfire/         bonfire menu textures
│   ├── menu/loading/         loading screen: background, bonfire animation, logo
│   ├── menu/windows/         shared window pieces: parchment, frames, arrows, icon plate
│   ├── icons/                1029 high-quality item icons
│   ├── text/                 English item names and descriptions (JSON)
│   └── font/                 FeFont_Big / FeFont_Small glyph pages and metrics
└── build/                    what the desktop uses
    ├── fonts/Drangleic.otf
    ├── rofi/                 window.png, selected.png
    ├── plymouth/             majula-ds2/ theme, preview.png
    ├── desktop/              cursor (icons/), notifications/
    └── kvantum/Drangleic/    the Qt theme
```

`build/plymouth/preview.png` shows how the loading screen will look; `build/plymouth/majula-ds2/items.txt` lists the items it can show.

## How it works

The game keeps its menus, texts and icons in `GameDataEbl.bdt`. Its index (`GameDataEbl.bhd`) is RSA-encrypted with the public key that ships next to it (`GameDataKeyCode.pem`), and some files inside are AES-encrypted with keys stored in that index. The tool decrypts the index, reads the files it needs (only reading the game folder, never writing), and unpacks the FromSoftware formats with the small readers in `ds2extract/formats.py`: DCX (zlib), BND4 (file bundles), TPF (DDS textures), CCM (font metrics) and FMG (text tables).

The positions, sizes and colours of the bonfire menu and the loading screen were measured on 1366x768 screenshots of the game itself, so they match it pixel for pixel on this notebook's screen. The constants are at the top of `ds2extract/bonfire.py` and `ds2extract/loading.py`.

| File | Step |
|---|---|
| `ds2extract/archive.py` | opens the encrypted archive |
| `ds2extract/formats.py` | DCX, BND4, TPF, CCM and FMG readers |
| `ds2extract/extract.py` | step 1: copies the pieces into `raw/` |
| `ds2extract/font.py` | step 2: traces the font |
| `ds2extract/bonfire.py` | step 3: the Rofi window and selection bar |
| `ds2extract/text.py` | draws text exactly like the game, from its glyph pages |
| `ds2extract/loading.py`, `plymouth.script` | step 4: the Plymouth theme |
| `ds2extract/desktop.py` | step 5: cursor, notification art |
| `ds2extract/kvantum.py` | step 6: the Kvantum theme |

The game's art and texts belong to FromSoftware and Bandai Namco. Keep what this tool builds for your own use.
