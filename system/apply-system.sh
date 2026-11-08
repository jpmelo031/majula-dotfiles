#!/usr/bin/env bash
# Parts of the Majula theme that live outside the home folder (need root).
# Usage: sudo bash system/apply-system.sh
# Safe to run as many times as you like; it reapplies everything from scratch.
# Run it again after installing Windows: it then adds Windows to the boot menu and the
# bonfire's Travel list, and puts Limine back if the Windows installer replaced it.
set -euo pipefail

[[ $EUID -eq 0 ]] || { echo "Run it with sudo: sudo bash $0" >&2; exit 1; }
# The desktop user (works with sudo and with pkexec).
user=${SUDO_USER:-$(id -nu "${PKEXEC_UID:-0}")}
here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo="$(dirname -- "$here")"
ds2="$repo/ds2-assets/build/plymouth"   # built from your copy of Dark Souls II by ds2-extract/extract

echo "==> Majula SDDM theme"
install -d /usr/share/sddm/themes/majula
install -m 0644 "$here"/sddm-majula/* /usr/share/sddm/themes/majula/
# Pre-fill the login with the user who ran sudo (until SDDM remembers the last one).
[[ $user != root ]] && sed -i "s/^defaultUser=.*/defaultUser=$user/" /usr/share/sddm/themes/majula/theme.conf
# The game's cursor on the login screen, when ds2-extract built it.
# (An older version put a Dark Souls II title screen and its font here; removed.)
rm -rf /usr/share/sddm/themes/majula/ds2
if [[ -e /usr/local/share/fonts/Drangleic.otf ]]; then
  rm -f /usr/local/share/fonts/Drangleic.otf
  fc-cache -f /usr/local/share/fonts >/dev/null
fi
cursor=Adwaita
if [[ -d $repo/ds2-assets/build/desktop/icons/Drangleic ]]; then
  rm -rf /usr/share/icons/Drangleic
  cp -a "$repo/ds2-assets/build/desktop/icons/Drangleic" /usr/share/icons/Drangleic
  cursor=Drangleic
fi

echo "==> SDDM settings (theme, Num Lock and cursor)"
install -d /etc/sddm.conf.d
# x11-user: the login screen's X server runs as the sddm user and starts only when the login
# screen is shown. With automatic login nothing starts before the desktop, so the boot goes
# from the loading screen straight to Hyprland on tty1 (a root X server on tty2 first made the
# screen blink while switching back and forth).
cat > /etc/sddm.conf.d/10-majula.conf <<CONF
[General]
Numlock=on
DisplayServer=x11-user

[Theme]
Current=majula
CursorTheme=$cursor
CursorSize=24
CONF

echo "==> Straight into the desktop after the loading screen (automatic login)"
# The password is still asked by the lock screen (lid, idle, Super+L). Remove
# /etc/sddm.conf.d/20-majula-autologin.conf to get the login screen back.
cat > /etc/sddm.conf.d/20-majula-autologin.conf <<CONF
[Autologin]
User=$user
Session=hyprland-uwsm.desktop
Relogin=false
CONF
# The desktop starts once the system reaches graphical.target (uwsm waits for it), and that
# waited for the Wi-Fi to connect (ZeroTier wants the network online): seconds of black screen.
# NetworkManager still connects as usual; boot just does not wait for it.
systemctl disable NetworkManager-wait-online.service 2>/dev/null || true

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

echo "==> Bluetooth on from boot"
systemctl enable --now bluetooth.service

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

echo "==> Backup of the boot partition (before touching anything on it)"
esp=/boot
install -d -m 0700 /var/backups/majula
backup="/var/backups/majula/esp-$(date +%Y-%m-%d_%H-%M-%S).tar.gz"
tar -C "$esp" -czf "$backup" .
ls -1t /var/backups/majula/esp-*.tar.gz | tail -n +6 | xargs -r rm --   # keep the last 5
echo "    $backup"

echo "==> Dark Souls II loading screen (Plymouth) and a silent boot"
if ! command -v plymouth-set-default-theme >/dev/null; then
  echo "    plymouth is not installed: sudo pacman -S plymouth, then run this again"
elif [[ ! -d $ds2/majula-ds2 ]]; then
  echo "    The DS2 art is not built: run ds2-extract/extract (needs the game), then this again"
else
  rm -rf /usr/share/plymouth/themes/majula-ds2
  cp -r "$ds2/majula-ds2" /usr/share/plymouth/themes/majula-ds2
  rm -rf /usr/share/majula   # an old version put a kernel splash here
  install -d /etc/plymouth
  printf '[Daemon]\nTheme=majula-ds2\nShowDelay=0\n' > /etc/plymouth/plymouthd.conf

  # Plymouth starts right after udev in the initramfs.
  grep -Eq '^HOOKS=\(.*\bplymouth\b' /etc/mkinitcpio.conf ||
    sed -i -E 's/^(HOOKS=\(.*\budev\b)/\1 plymouth/' /etc/mkinitcpio.conf

  # No text while booting. The safe image (fallback) keeps the plain text boot.
  # fbcon=nodefer: the console turns the screen black as soon as the kernel starts, so the
  # firmware logo is not shown again between the loading screen and the login.
  cmdline=$(sed 's/ *$//' /etc/kernel/cmdline)
  plain=$cmdline
  for opt in quiet splash loglevel=3 rd.udev.log_level=3 udev.log_level=3 vt.global_cursor_default=0 fbcon=nodefer; do
    plain=${plain// $opt/}
    [[ " $cmdline " == *" $opt "* ]] || cmdline+=" $opt"
  done
  echo "$cmdline" > /etc/kernel/cmdline
  echo "$plain" > /etc/kernel/cmdline-fallback

  # No picture from the kernel image itself (the loading screen fades in from black), and a
  # second image without Plymouth is kept up to date for emergencies.
  preset=/etc/mkinitcpio.d/linux.preset
  [[ -e $preset.majula-orig ]] || cp "$preset" "$preset.majula-orig"
  cat > "$preset" <<'CONF'
# mkinitcpio preset for 'linux' (written by majula-dotfiles system/apply-system.sh;
# the original is linux.preset.majula-orig)
ALL_kver="/boot/vmlinuz-linux"
PRESETS=('default' 'fallback')

default_uki="/boot/EFI/Linux/arch-linux.efi"
default_options=""

fallback_uki="/boot/EFI/Linux/arch-linux-fallback.efi"
fallback_options="-S autodetect,plymouth --cmdline /etc/kernel/cmdline-fallback"
CONF
  # The loading screen stays at least ~10 s (time to read the item, like in the game), then
  # gets 0.7 s to fade to black before the desktop starts.
  install -d /usr/local/lib/majula
  cat > /usr/local/lib/majula/hold-loading-screen <<'SH'
#!/bin/sh
# Waits until the system has been up for 11 s: about 10 s of loading screen.
until [ "$(cut -d. -f1 /proc/uptime)" -ge 11 ]; do sleep 0.2; done
SH
  chmod 755 /usr/local/lib/majula/hold-loading-screen
  install -d /etc/systemd/system/plymouth-quit.service.d
  cat > /etc/systemd/system/plymouth-quit.service.d/10-majula-fade.conf <<'CONF'
# The Majula DS2 loading screen: shown at least ~10 s, then it fades to black when it gets
# this status (see majula-ds2.script).
[Service]
ExecStartPre=-/usr/local/lib/majula/hold-loading-screen
ExecStartPre=-/usr/bin/plymouth update --status=majula-fade-out
ExecStartPre=-/usr/bin/sleep 0.7
CONF
  # Shutting down and rebooting show the same screen, which used to flash by in about a
  # second: it now stays 5 s, fades to black, and only then the power goes off.
  cat > /etc/systemd/system/majula-hold-shutdown-screen.service <<'CONF'
[Unit]
Description=Keep the Dark Souls II screen up for a moment while shutting down
DefaultDependencies=no
After=plymouth-poweroff.service plymouth-reboot.service
Before=systemd-poweroff.service systemd-reboot.service
ConditionKernelCommandLine=!plymouth.enable=0

[Service]
Type=oneshot
ExecCondition=/usr/bin/plymouth --ping
ExecStart=/usr/bin/sleep 5
ExecStart=-/usr/bin/plymouth update --status=majula-fade-out
ExecStart=/usr/bin/sleep 0.7
TimeoutStartSec=15

[Install]
WantedBy=poweroff.target reboot.target
CONF
  systemctl daemon-reload
  systemctl enable majula-hold-shutdown-screen.service 2>/dev/null

  mkinitcpio -P
fi

echo "==> Limine: no menu (hold a key while booting to see it), Windows entry when installed"
# The config next to Limine's fallback path is the main one; the copy in \EFI\limine (see below)
# reads its own limine.conf from the same folder, so it gets the same file.
conf="$esp/EFI/BOOT/limine.conf"
[[ -f $conf ]] || conf=$(find "$esp" -maxdepth 4 -iname limine.conf -print -quit)
# Windows counts as installed when its boot manager is on the ESP and an NTFS partition exists
# (an old \EFI\Microsoft folder alone could be left over from the notebook's original Windows).
windows_efi=$(find "$esp/EFI" -maxdepth 3 -ipath '*/Microsoft/Boot/bootmgfw.efi' -print -quit 2>/dev/null || true)
lsblk -rno FSTYPE | grep -qx ntfs || windows_efi=""
if [[ -z $conf ]]; then
  echo "    limine.conf not found on $esp; skipping"
else
  [[ -e $conf.majula-orig ]] || cp "$conf" "$conf.majula-orig"
  WINDOWS_EFI="${windows_efi#"$esp"}" python3 - "$conf" <<'PY'
import os, re, sys
path = sys.argv[1]
lines = open(path).read().splitlines()
# Global options sit before the first entry (a line starting with "/").
first = next((i for i, l in enumerate(lines) if l.lstrip().startswith("/")), len(lines))
head, body = lines[:first], lines[first:]
head = [l for l in head if not re.match(r"\s*(timeout|quiet)\s*:", l, re.I)]
head = ["timeout: 1", "quiet: yes"] + head
# Split the entries and drop "cmdline:" from the ones that start a kernel image (UKI): the
# image carries its own command line (/etc/kernel/cmdline), and a cmdline here would replace it.
entries, cur = [], []
for l in body:
    if l.lstrip().startswith("/") and cur:
        entries.append(cur)
        cur = []
    cur.append(l)
if cur:
    entries.append(cur)
for e in entries:
    if any(re.search(r"path:\s*\S*/EFI/Linux/\S+\.efi", l, re.I) for l in e):
        e[:] = [l for l in e if not re.match(r"\s*cmdline\s*:", l, re.I)]
body = [l for e in entries for l in e]
# The protocol the Arch entry uses (the same works for any EFI program).
m = re.search(r"protocol:\s*(\S+)", "\n".join(body))
proto = m.group(1) if m else "efi"
out = "\n".join(head + body).rstrip() + "\n"
def entry(title, efi):
    return f"\n/{title}\n    protocol: {proto}\n    path: boot():{efi}\n"
if "arch-linux-fallback.efi" not in out:
    out += entry("Arch Linux (safe, text boot)", "/EFI/Linux/arch-linux-fallback.efi")
win = os.environ.get("WINDOWS_EFI", "")
if win and "bootmgfw.efi" not in out.lower():
    out += entry("Windows", win.replace("\\", "/"))
open(path, "w").write(out)
PY
  echo "    $conf"
fi

echo "==> Keeping Limine safe from the Windows installer"
# Windows writes its own \EFI\BOOT\BOOTX64.EFI, which is how this notebook starts Limine.
# A second copy in \EFI\limine with its own firmware entry keeps Arch reachable, and the
# fallback path is put back whenever it no longer holds Limine.
install -Dm644 /usr/share/limine/BOOTX64.EFI "$esp/EFI/limine/BOOTX64.EFI"
[[ -n $conf && $conf != "$esp/EFI/limine/limine.conf" ]] && install -Dm644 "$conf" "$esp/EFI/limine/limine.conf"
if ! cmp -s /usr/share/limine/BOOTX64.EFI "$esp/EFI/BOOT/BOOTX64.EFI"; then
  install -Dm644 /usr/share/limine/BOOTX64.EFI "$esp/EFI/BOOT/BOOTX64.EFI"
  echo "    Limine restored at \\EFI\\BOOT\\BOOTX64.EFI"
fi
part=$(findmnt -no SOURCE "$esp")
disk="/dev/$(lsblk -no PKNAME "$part")"
partnum=$(cat "/sys/class/block/$(basename "$part")/partition")
entry=$(efibootmgr | sed -n 's/^Boot\([0-9A-Fa-f]\{4\}\)\*\{0,1\} Majula (Limine).*/\1/p' | head -n1)
if [[ -z $entry ]]; then
  efibootmgr --create --disk "$disk" --part "$partnum" --loader '\EFI\limine\BOOTX64.EFI' --label 'Majula (Limine)' >/dev/null
  entry=$(efibootmgr | sed -n 's/^Boot\([0-9A-Fa-f]\{4\}\)\*\{0,1\} Majula (Limine).*/\1/p' | head -n1)
fi
order=$(efibootmgr | sed -n 's/^BootOrder: //p')
efibootmgr --bootorder "$(echo "$entry,${order}" | tr ',' '\n' | awk 'NF && !seen[$0]++' | paste -sd,)" >/dev/null
echo "    firmware entry Boot$entry (Majula (Limine)) is first"

echo "==> Travel to Windows from the bonfire"
if [[ -n $windows_efi ]]; then
  cat > /usr/local/bin/reboot-to-windows <<'SH'
#!/bin/sh
# Boots Windows once on the next restart, then restarts (used by the bonfire menu).
set -e
num=$(efibootmgr | sed -n 's/^Boot\([0-9A-Fa-f]\{4\}\)\*\{0,1\} Windows Boot Manager.*/\1/p' | head -n1)
[ -n "$num" ] || { echo "No Windows Boot Manager entry in the firmware" >&2; exit 1; }
efibootmgr --bootnext "$num" >/dev/null
exec systemctl reboot
SH
  chmod 0755 /usr/local/bin/reboot-to-windows
  printf '%s ALL=(root) NOPASSWD: /usr/local/bin/reboot-to-windows\n' "$user" > /etc/sudoers.d/50-majula-windows
  chmod 0440 /etc/sudoers.d/50-majula-windows
  visudo -cf /etc/sudoers.d/50-majula-windows >/dev/null
  echo "    Windows found: \"Drangleic (Windows)\" in Travel and \"Reboot into Windows\" in Burn"
else
  rm -f /usr/local/bin/reboot-to-windows /etc/sudoers.d/50-majula-windows
  echo "    Windows is not installed yet; run this again after installing it"
fi

echo
echo "Done. Reboot to see the new boot and login (SDDM is not restarted now so your session stays open)."
