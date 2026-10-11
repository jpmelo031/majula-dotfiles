#!/usr/bin/env bash
# Copies your live config back into the repo (only files the repo already tracks),
# so changes made on the machine can be reviewed with git diff and committed.
set -euo pipefail

repo="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$repo"

while IFS= read -r -d '' file; do
  src="$HOME/${file#home/}"
  [[ -f $src ]] && cp -p "$src" "$file"
done < <(git ls-files -z home)

# Keep machine-specific paths out of the repo (install.sh writes the real one).
sed -i 's|^color_scheme_path=.*|color_scheme_path=~/.config/qt6ct/colors/Majula.conf|' home/.config/qt6ct/qt6ct.conf

git status --short
