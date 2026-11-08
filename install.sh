#!/usr/bin/env bash
# Installs the Majula dotfiles into your home folder.
# Files that would be replaced are first moved to ~/.local/state/majula-backup/<date>/.
# Root-only parts (login screen, Num Lock on boot, no hibernation): sudo bash system/apply-system.sh
set -euo pipefail

repo="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ds2="$repo/ds2-assets/build"   # built from your copy of Dark Souls II by ds2-extract/extract
backup="${XDG_STATE_HOME:-$HOME/.local/state}/majula-backup/$(date +%Y-%m-%d_%H-%M-%S)"

# Without the DS2 art (built, or installed by an earlier run) the configs fall back to the
# plain Majula look: Rofi theme, Adwaita cursor, Fusion style with the Majula palette.
ds2_ready=false
[[ -d $ds2 || -f $HOME/.config/rofi/ds2/window.png ]] && ds2_ready=true
cursor=Drangleic
$ds2_ready || cursor=Adwaita

# The plain Majula look for the few settings that name DS2 art that is not there.
without_ds2() {
  if $ds2_ready; then
    cat
  else
    sed -e 's|^@theme "bonfire"|@theme "majula"|' -e 's|=Drangleic$|=Adwaita|' \
        -e 's|^style=kvantum|style=Fusion|' -e 's|^widgetStyle=kvantum|widgetStyle=Fusion|' \
        -e 's|^custom_palette=false|custom_palette=true|'
  fi
}

# A repo file as it should look on this machine.
render() {
  if [[ $1 == */.config/qt6ct/qt6ct.conf ]]; then
    sed "s|^color_scheme_path=~/|color_scheme_path=$HOME/|" "$1" | without_ds2   # qt6ct needs an absolute path
  else
    without_ds2 < "$1"
  fi
}

echo "==> Dotfiles"
cd "$repo/home"
while IFS= read -r -d '' file; do
  rel=${file#./}
  dest="$HOME/$rel"
  if [[ -e $dest ]] && ! cmp -s <(render "$file") "$dest"; then
    mkdir -p "$backup/$(dirname "$rel")"
    mv "$dest" "$backup/$rel"
  fi
  mkdir -p "$(dirname "$dest")"
  render "$file" > "$dest"
  chmod --reference="$file" "$dest"
done < <(find . -type f -print0)

mkdir -p "$HOME/.local/bin"
ln -sf "$HOME/.config/hypr/scripts/rice" "$HOME/.local/bin/rice"

echo "==> Dark Souls II art"
if [[ -d $ds2 ]]; then
  install -Dm644 "$ds2/fonts/Drangleic.otf" "$HOME/.local/share/fonts/Drangleic.otf"
  fc-cache -f "$HOME/.local/share/fonts" >/dev/null
  install -Dm644 -t "$HOME/.config/rofi/ds2" "$ds2/rofi/window.png" "$ds2/rofi/selected.png"
  rm -rf "$HOME/.config/hypr/ds2"   # banners and sounds from an older version
  rm -rf "$HOME/.config/swaync/ds2" "$HOME/.local/share/icons/Drangleic" "$HOME/.config/Kvantum/Drangleic"
  cp -r "$ds2/desktop/notifications" "$HOME/.config/swaync/ds2"
  mkdir -p "$HOME/.local/share/icons" "$HOME/.config/Kvantum"
  cp -a "$ds2/desktop/icons/Drangleic" "$HOME/.local/share/icons/Drangleic"
  [[ -d $ds2/kvantum/Drangleic ]] && cp -r "$ds2/kvantum/Drangleic" "$HOME/.config/Kvantum/Drangleic"
  echo "    font, bonfire menu, cursor, notifications and the Kvantum theme installed"
else
  echo "    Not built yet; run ds2-extract/extract (needs the game) and then ./install.sh again."
fi

echo "==> Icons: Papirus-Dark with brown folders (Papirus-Dark-Majula)"
# A small theme on top of Papirus-Dark: every folder icon points to Papirus' own brown one.
icons="$HOME/.local/share/icons/Papirus-Dark-Majula"
rm -rf "$icons"
dirs=()
for dir in /usr/share/icons/Papirus/*/places; do
  size=$(basename "$(dirname "$dir")")
  mkdir -p "$icons/$size/places"
  while IFS= read -r -d '' link; do
    target=$(basename "$(readlink -f "$link")")   # follow chains like inode-directory -> folder -> folder-blue
    brown=${target//-blue/-brown}
    [[ $brown != "$target" && -e $dir/$brown ]] && ln -s "$dir/$brown" "$icons/$size/places/$(basename "$link")"
  done < <(find "$dir" -maxdepth 1 -type l -print0)
  dirs+=("$size/places")
done
{
  printf '[Icon Theme]\nName=Papirus-Dark-Majula\nComment=Papirus-Dark with brown folders\nInherits=Papirus-Dark,breeze-dark,hicolor\n'
  printf 'Directories=%s\n\n' "$(IFS=,; echo "${dirs[*]}")"
  for d in "${dirs[@]}"; do
    size=${d%%/*}; px=${size%%x*}; scale=1
    [[ $size == *@2x ]] && scale=2
    printf '[%s]\nContext=Places\nSize=%s\nScale=%s\nType=Fixed\n\n' "$d" "$px" "$scale"
  done
} > "$icons/index.theme"
gtk-update-icon-cache -q -f "$icons" 2>/dev/null || true

echo "==> Hyprland"
# Keep Hyprland's own generated config and load the theme from its last line.
hypr="$HOME/.config/hypr/hyprland.lua"
[[ -e $hypr ]] || cp /usr/share/hypr/hyprland.lua "$hypr"
grep -q 'require("majula")' "$hypr" ||
  printf '\n-- Majula theme (look, autostart and extra keybinds)\nrequire("majula")\n' >> "$hypr"

echo "==> GTK dark mode"
if command -v gsettings >/dev/null; then
  gsettings set org.gnome.desktop.interface color-scheme prefer-dark
  gsettings set org.gnome.desktop.interface gtk-theme Adwaita-dark
  gsettings set org.gnome.desktop.interface icon-theme Papirus-Dark-Majula
  gsettings set org.gnome.desktop.interface cursor-theme "$cursor"
  gsettings set org.gnome.desktop.interface cursor-size 24
  gsettings set org.gnome.desktop.interface font-name 'Inter 10'
  gsettings set org.gnome.desktop.interface monospace-font-name 'JetBrainsMono Nerd Font 10'
fi

echo "==> Bluetooth"
# Waybar's bluetooth module is the bar icon, so blueman's own tray icon is turned off.
if command -v gsettings >/dev/null && gsettings list-schemas | grep -qx org.blueman.general; then
  gsettings set org.blueman.general plugin-list "['!StatusIcon', '!ShowConnected']"
fi

echo "==> VS Code theme"
if command -v code >/dev/null; then
  vsix="$(mktemp -d)/majula-theme.vsix"
  python3 "$repo/vscode/build-vsix.py" "$repo/vscode/majula-theme" "$vsix"
  code --install-extension "$vsix" --force >/dev/null
  rm -rf "$(dirname "$vsix")"
else
  echo "    VS Code is not installed yet; run ./install.sh again after installing it."
fi

echo
[[ -d $backup ]] && echo "Replaced files were backed up to $backup"
echo "Done. Log out and back in to load everything."
echo "Login screen, Num Lock on boot and no hibernation: sudo bash $repo/system/apply-system.sh"
