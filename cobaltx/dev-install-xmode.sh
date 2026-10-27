#!/bin/bash
# Installs X Mode from the build tree onto THIS machine (Domin) for testing,
# without building an ISO:  sudo bash ~/cobaltx/dev-install-xmode.sh
set -e
R="${COBALTX_DIR:-/home/${SUDO_USER:-$USER}/cobaltx}/airootfs"
[ -d "$R/usr/share/cobaltx-xmode" ] || R="$(dirname "$(readlink -f "$0")")/airootfs"   # run from an extracted zip
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }

install -Dm755 "$R/usr/local/bin/cobaltx-xmode"                 /usr/local/bin/cobaltx-xmode
install -Dm755 "$R/usr/local/bin/cobaltx-xmode-session"         /usr/local/bin/cobaltx-xmode-session
install -Dm755 "$R/usr/local/bin/cobaltx-session-select"        /usr/local/bin/cobaltx-session-select
install -Dm755 "$R/usr/local/bin/cobaltx-xmode-installer-setup" /usr/local/bin/cobaltx-xmode-installer-setup
install -Dm755 "$R/usr/local/lib/cobaltx/session-helper"        /usr/local/lib/cobaltx/session-helper
install -Dm755 "$R/usr/local/lib/cobaltx/xmode-session-apps"    /usr/local/lib/cobaltx/xmode-session-apps
install -Dm755 "$R/usr/local/bin/cobaltx-keyboard"              /usr/local/bin/cobaltx-keyboard
install -Dm755 "$R/usr/local/lib/cobaltx/tdp-helper"            /usr/local/lib/cobaltx/tdp-helper
install -Dm755 "$R/usr/local/lib/cobaltx/handheld-setup"        /usr/local/lib/cobaltx/handheld-setup
rm -rf /usr/share/cobaltx-xmode /usr/share/cobaltx-keyboard
cp -r "$R/usr/share/cobaltx-xmode" /usr/share/cobaltx-xmode
cp -r "$R/usr/share/cobaltx-keyboard" /usr/share/cobaltx-keyboard
for f in etc/udev/rules.d/60-cobaltx-uinput.rules etc/udev/rules.d/90-cobaltx-tdp.rules \
         etc/modules-load.d/cobaltx-uinput.conf etc/xdg/autostart/cobaltx-keyboard.desktop \
         usr/share/applications/cobaltx-keyboard.desktop usr/share/polkit-1/actions/org.cobaltx.tdp.policy \
         etc/systemd/system/cobaltx-tdp.service etc/systemd/system/cobaltx-tdp-resume.service \
         etc/systemd/system/cobaltx-handheld.service; do
    install -Dm644 "$R/$f" "/$f"
done
systemctl daemon-reload
systemctl enable cobaltx-handheld.service cobaltx-tdp.service cobaltx-tdp-resume.service 2>/dev/null || true
modprobe uinput 2>/dev/null; udevadm control --reload; udevadm trigger /dev/uinput 2>/dev/null || true
install -Dm644 "$R/usr/share/wayland-sessions/cobaltx-xmode.desktop"   /usr/share/wayland-sessions/cobaltx-xmode.desktop
install -Dm644 "$R/usr/share/applications/cobaltx-xmode.desktop"       /usr/share/applications/cobaltx-xmode.desktop
install -Dm644 "$R/usr/share/applications/cobaltx-xmode-switch.desktop" /usr/share/applications/cobaltx-xmode-switch.desktop
install -Dm644 "$R/etc/xdg/autostart/cobaltx-session-consume.desktop"  /etc/xdg/autostart/cobaltx-session-consume.desktop
install -Dm644 "$R/usr/share/polkit-1/actions/org.cobaltx.session.policy" /usr/share/polkit-1/actions/org.cobaltx.session.policy
for f in "$R"/usr/share/icons/hicolor/*/apps/cobaltx-xmode.*; do
    [ -e "$f" ] && install -Dm644 "$f" "/usr/share/icons/hicolor/${f#"$R"/usr/share/icons/hicolor/}"
done
gtk-update-icon-cache -q /usr/share/icons/hicolor 2>/dev/null || true

pacman -Syu --needed --noconfirm libpulse gamescope sdl2-compat python-yaml qt6-declarative qt6-svg python-pyqt6 python-evdev >/dev/null \
    || echo "! package install failed - run: sudo pacman -Syu"
echo "✓ X Mode installed on this system."
echo "  Test: app menu -> 'X Mode'  (or on the login screen: bottom-left session menu -> 'CobaltX X Mode')"
echo "  In a VM gamescope can't start, so the session falls back to KWin automatically."
