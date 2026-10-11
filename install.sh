#!/usr/bin/env bash
# Installs the Majula dotfiles into your home folder.
# Files that would be replaced are first moved to ~/.local/state/majula-backup/<date>/.
# Root-only parts (login screen, Num Lock on boot, no hibernation): sudo bash system/apply-system.sh
set -euo pipefail

repo="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
backup="${XDG_STATE_HOME:-$HOME/.local/state}/majula-backup/$(date +%Y-%m-%d_%H-%M-%S)"

# A repo file as it should look on this machine.
render() {
  if [[ $1 == */.config/qt6ct/qt6ct.conf ]]; then
    sed "s|^color_scheme_path=~/|color_scheme_path=$HOME/|" "$1"   # qt6ct needs an absolute path
  else
    cat "$1"
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
  gsettings set org.gnome.desktop.interface icon-theme Papirus-Dark
  gsettings set org.gnome.desktop.interface cursor-theme Adwaita
  gsettings set org.gnome.desktop.interface cursor-size 24
  gsettings set org.gnome.desktop.interface font-name 'Inter 10'
  gsettings set org.gnome.desktop.interface monospace-font-name 'JetBrainsMono Nerd Font 10'
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
