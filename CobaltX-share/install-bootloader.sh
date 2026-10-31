#!/bin/bash
# CobaltX bootloader installer (runs inside the target system during Calamares install)
mkdir -p /var/log
exec > /var/log/cobaltx-bootloader-install.log 2>&1
set -x

ROOT_UUID=$(findmnt -no UUID /)
echo "ROOT_UUID=$ROOT_UUID"

# Remove live ISO auto-login config (so installed user can log in normally)
rm -f /etc/sddm.conf.d/autologin.conf 2>/dev/null
rm -f /etc/sddm.conf.d/kde_settings.conf 2>/dev/null
# Remove live cobalt user (Calamares creates the real user)
userdel -r cobalt 2>/dev/null || true

# Remove archiso-specific mkinitcpio configs that pollute initramfs
rm -f /etc/mkinitcpio.conf.d/archiso.conf
rm -f /etc/mkinitcpio.d/archiso.preset
rm -f /etc/mkinitcpio.d/linux.preset

# v0.3: remove the extra stock "linux" kernel (CobaltX only boots linux-zen).
# Leaving it installed made every kernel update throw mkinitcpio errors.
EXTRA_KERNEL=$(pacman -Qq linux linux-headers 2>/dev/null)
[ -n "$EXTRA_KERNEL" ] && pacman -Rdd --noconfirm $EXTRA_KERNEL
rm -f /boot/vmlinuz-linux /boot/initramfs-linux.img /boot/initramfs-linux-fallback.img

# Set HOOKS WITHOUT autodetect (so all drivers included for VM/hardware compat)
sed -i 's/^HOOKS=.*/HOOKS=(base systemd modconf kms keyboard sd-vconsole plymouth block filesystems fsck)/' /etc/mkinitcpio.conf

# Find kernel
KERNEL_VERSION=$(ls /usr/lib/modules/ | grep zen | head -1)
echo "Found kernel: $KERNEL_VERSION"

# Copy kernel to /boot
mkdir -p /boot
if [ -n "$KERNEL_VERSION" ] && [ -f "/usr/lib/modules/$KERNEL_VERSION/vmlinuz" ]; then
    cp "/usr/lib/modules/$KERNEL_VERSION/vmlinuz" /boot/vmlinuz-linux-zen
fi

# Generate initramfs using ONLY linux-zen preset
mkinitcpio -p linux-zen 2>&1 || echo "mkinitcpio failed, continuing"
ls -la /boot/initramfs-linux-zen* 2>&1

# v0.3: safety check - is the EFI partition big enough?
# (A small shared Windows/Hackintosh ESP filled up and broke the install.)
mkdir -p /efi
NEEDED_MB=$(( $(du -m /boot/vmlinuz-linux-zen /boot/initramfs-linux-zen.img | awk '{s+=$1} END {print s}') + 20 ))
FREE_MB=$(df --output=avail -m /efi | tail -1 | tr -d ' ')
echo "ESP free: ${FREE_MB} MB, needed: ${NEEDED_MB} MB"
if [ "$FREE_MB" -lt "$NEEDED_MB" ]; then
    echo "ERROR: EFI partition too small (${FREE_MB} MB free, ${NEEDED_MB} MB needed)."
    echo "Reinstall with Manual partitioning and create a new 1 GB FAT32 partition mounted at /efi."
    exit 1
fi

# Copy kernel + initramfs to ESP
cp /boot/vmlinuz-linux-zen /efi/ || { echo "kernel copy failed"; exit 1; }
cp /boot/initramfs-linux-zen.img /efi/ || { echo "initramfs copy failed"; exit 1; }

# Install systemd-boot
bootctl --esp-path=/efi install || echo "bootctl install failed"

mkdir -p /efi/EFI/systemd /efi/EFI/BOOT
cp /usr/lib/systemd/boot/efi/systemd-bootx64.efi /efi/EFI/systemd/ 2>/dev/null
# v0.3: never overwrite another OS's fallback loader (this broke OpenCore on a shared ESP)
if [ ! -f /efi/EFI/BOOT/BOOTX64.EFI ] || grep -qa "systemd-boot" /efi/EFI/BOOT/BOOTX64.EFI; then
    cp /usr/lib/systemd/boot/efi/systemd-bootx64.efi /efi/EFI/BOOT/BOOTX64.EFI 2>/dev/null
else
    echo "Existing non-systemd-boot BOOTX64.EFI found - leaving it alone"
fi

# Write loader config and entry
rm -f /efi/loader/entries/cobaltx*.conf 2>/dev/null
mkdir -p /efi/loader/entries

cat > /efi/loader/loader.conf <<EOF
default cobaltx.conf
timeout 5
console-mode auto
editor no
EOF

cat > /efi/loader/entries/cobaltx.conf <<EOF
title CobaltX 0.2 — Sparked
linux /vmlinuz-linux-zen
initrd /initramfs-linux-zen.img
options root=UUID=$ROOT_UUID rw quiet splash
EOF
# v0.3: no fallback entry - modern mkinitcpio doesn't build a fallback image,
# so that entry always pointed to a missing file.

# v0.3: mount the ESP at /boot from now on, so kernel updates write straight
# to the ESP. Before, updates went to /boot on the root disk while the old
# kernel kept booting from /efi -> emergency mode after the first kernel update.
sed -i 's#[[:space:]]/efi[[:space:]]# /boot #' /etc/fstab
echo "=== fstab ===" ; cat /etc/fstab

# Keep systemd-boot itself updated automatically
systemctl enable systemd-boot-update.service 2>/dev/null || true

echo "=== Final /efi contents ==="
ls -la /efi/ /efi/loader/entries/

exit 0
