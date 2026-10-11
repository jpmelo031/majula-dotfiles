#!/usr/bin/env bash
# Parts of the Majula theme that live outside the home folder (need root).
# Usage: sudo bash ~/.config/hypr/system/apply-system.sh
# Safe to run as many times as you like; it reapplies everything from scratch.
set -euo pipefail

[[ $EUID -eq 0 ]] || { echo "Run it with sudo: sudo bash $0" >&2; exit 1; }
here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

echo "==> Majula SDDM theme"
install -d /usr/share/sddm/themes/majula
install -m 0644 "$here"/sddm-majula/* /usr/share/sddm/themes/majula/
# Pre-fill the login with the user who ran sudo (until SDDM remembers the last one).
[[ -n ${SUDO_USER:-} ]] && sed -i "s/^defaultUser=.*/defaultUser=$SUDO_USER/" /usr/share/sddm/themes/majula/theme.conf

echo "==> SDDM settings (theme, Num Lock and cursor)"
install -d /etc/sddm.conf.d
cat > /etc/sddm.conf.d/10-majula.conf <<'CONF'
[General]
Numlock=on

[Theme]
Current=majula
CursorTheme=Adwaita
CursorSize=24
CONF

echo "==> ABNT2 keyboard on the login screen and in the TTYs"
localectl set-keymap br-abnt2
localectl set-x11-keymap br abnt2

echo "==> Num Lock on in the TTYs from boot"
cat > /etc/systemd/system/numlock.service <<'CONF'
[Unit]
Description=Turn on Num Lock in the virtual consoles
Before=getty.target display-manager.service

[Service]
Type=oneshot
ExecStart=/bin/sh -c 'for tty in /dev/tty[1-6]; do /usr/bin/setleds -D +num < "$tty"; done'

[Install]
WantedBy=multi-user.target
CONF
systemctl daemon-reload
systemctl enable numlock.service

echo "==> Never hibernate; closing the lid only locks the screen"
install -d /etc/systemd/logind.conf.d
cat > /etc/systemd/logind.conf.d/10-majula.conf <<'CONF'
[Login]
HandleLidSwitch=lock
HandleLidSwitchExternalPower=lock
HandleLidSwitchDocked=ignore
IdleAction=ignore
CONF
systemctl mask hibernate.target hybrid-sleep.target suspend-then-hibernate.target

echo
echo "Done. Reboot to see the new login (SDDM is not restarted now so your session stays open)."
