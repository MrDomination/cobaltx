#!/bin/bash
# Builds Handheld Daemon (AUR: hhd) during the ISO build. Runs inside the
# archiso chroot from customize_airootfs.sh. Never fails the build: if this
# breaks, the ISO still works, handhelds just lack back buttons until
# `yay -S hhd` is run.
LOG=/var/log/cobaltx-build-hhd.log
exec > >(tee -a "$LOG") 2>&1
echo "=== building hhd $(date) ==="
if pacman -Q hhd >/dev/null 2>&1; then echo "hhd already installed"; exit 0; fi

B=/var/tmp/cobaltx-hhd
U=hhdbuild
cp /etc/pacman.conf /etc/pacman.conf.cobaltx-bak
sed -i 's/^CheckSpace/#CheckSpace/' /etc/pacman.conf    # pacman can't measure space inside the chroot
useradd -m -s /bin/bash "$U" 2>/dev/null || true
rm -rf "$B"; mkdir -p "$B"; chown "$U:" "$B"

ok=0
if pacman -S --needed --noconfirm base-devel git \
   && runuser -u "$U" -- git clone --depth 1 https://aur.archlinux.org/hhd.git "$B/hhd"; then
    cd "$B/hhd"
    deps=$(runuser -u "$U" -- makepkg --printsrcinfo \
           | awk -F' = ' '/^\t(make|check)?depends = / {print $2}' | sed 's/[<>=].*//' | sort -u)
    echo "dependencies: $deps"
    if pacman -S --needed --noconfirm --asdeps $deps \
       && runuser -u "$U" -- env TMPDIR=/var/tmp makepkg --noconfirm --nocheck \
       && pacman -U --noconfirm "$B"/hhd/*.pkg.tar.zst; then
        ok=1
    fi
    cd /
fi

mv /etc/pacman.conf.cobaltx-bak /etc/pacman.conf
userdel -r "$U" 2>/dev/null
rm -rf "$B"
if [ "$ok" = 1 ]; then
    echo "hhd installed: $(pacman -Q hhd)"
else
    echo "!!! hhd build FAILED - handhelds will work, but without back buttons (see $LOG)"
fi
exit 0
