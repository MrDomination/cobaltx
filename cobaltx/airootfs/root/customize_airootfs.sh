#!/usr/bin/env bash
set -e -u

# Apply CobaltX Calamares customizations after pacman installed default configs
if [ -d /root/cobaltx-configs ]; then
    mkdir -p /etc/calamares/branding
    cp -rf /root/cobaltx-configs/branding/cobaltx /etc/calamares/branding/
    cp -f /root/cobaltx-configs/settings.conf /etc/calamares/settings.conf
    mkdir -p /etc/calamares/modules
    cp -rf /root/cobaltx-configs/modules/. /etc/calamares/modules/
    rm -rf /root/cobaltx-configs
fi

# Create yaml-cpp symlink for Calamares (compat with version 0.8)
[ -f /usr/lib/libyaml-cpp.so.0.9 ] && ln -sf /usr/lib/libyaml-cpp.so.0.9 /usr/lib/libyaml-cpp.so.0.8 || true

# Patch grubcfg to use grub as default bootloader when not in global storage
if [ -f /usr/lib/calamares/modules/grubcfg/main.py ]; then
    sed -i 's|return f"Key missing", f"Failed to find {gs_name} in global storage"|bootloader_name = "grub"|' /usr/lib/calamares/modules/grubcfg/main.py
fi

# Make fix-boot-entries script executable
chmod +x /usr/local/bin/fix-boot-entries.sh

# Make bootloader install script executable
chmod +x /usr/local/bin/install-bootloader.sh

# Initialize pacman keyring so installed system can verify packages
pacman-key --init || true
pacman-key --populate archlinux || true
[ -f /usr/share/pacman/keyrings/endeavouros-trusted ] && pacman-key --populate endeavouros || true

# Create cobalt user
useradd -m -k /etc/skel -G wheel,audio,video,storage,input,network -s /bin/bash cobalt
passwd -d cobalt

# Force-copy skel files
cp -rT /etc/skel /home/cobalt 2>/dev/null || true
chown -R cobalt:cobalt /home/cobalt

# Restore Desktop folder for live cobalt user (not in /etc/skel anymore)
mkdir -p /home/cobalt/Desktop
chmod +x /home/cobalt/Desktop/install-cobaltx.desktop 2>/dev/null
chown -R cobalt:cobalt /home/cobalt/Desktop

# Passwordless sudo for wheel
sed -i 's/^# %wheel ALL=(ALL:ALL) NOPASSWD: ALL/%wheel ALL=(ALL:ALL) NOPASSWD: ALL/' /etc/sudoers

# Override default KDE wallpaper with CobaltX wallpaper
WALLPAPER_SRC="/usr/share/backgrounds/cobaltx/cobaltx-wallpaper.png"

# Replace Next wallpaper (KDE Plasma 6 default)
if [ -d "/usr/share/wallpapers/Next/contents/images" ]; then
    for f in /usr/share/wallpapers/Next/contents/images/*.png; do
        cp -f "$WALLPAPER_SRC" "$f"
    done
fi

# Also replace Next dark mode if present
if [ -d "/usr/share/wallpapers/Next/contents/images_dark" ]; then
    for f in /usr/share/wallpapers/Next/contents/images_dark/*.png; do
        cp -f "$WALLPAPER_SRC" "$f"
    done
fi

# Replace Breeze fallback if Next isn't the default
if [ -d "/usr/share/wallpapers/Breeze/contents/images" ]; then
    for f in /usr/share/wallpapers/Breeze/contents/images/*.png; do
        cp -f "$WALLPAPER_SRC" "$f"
    done
fi 

# Set up Flathub repository
if command -v flatpak >/dev/null 2>&1; then
    flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
    # Pre-install gaming apps
    flatpak install -y flathub com.heroicgameslauncher.hgl
    flatpak install -y flathub com.usebottles.bottles
fi

# Apply CobaltX breeze icon overrides AFTER breeze-icons package installed
if [ -d /root/cobaltx-icons-staging ]; then
    cp -rf /root/cobaltx-icons-staging/breeze/. /usr/share/icons/breeze/
    cp -rf /root/cobaltx-icons-staging/breeze-dark/. /usr/share/icons/breeze-dark/
    rm -rf /root/cobaltx-icons-staging
fi

# Apply CobaltX Welcome icon override AFTER plasma-welcome package installed
if [ -d /root/cobaltx-welcome-staging ]; then
    cp -f /root/cobaltx-welcome-staging/org.kde.plasma-welcome.desktop /usr/share/applications/
    rm -rf /root/cobaltx-welcome-staging
fi

# Set CobaltX as default Plymouth theme
if command -v plymouth-set-default-theme >/dev/null 2>&1; then
    plymouth-set-default-theme -R cobaltx 2>/dev/null || true
fi



# Install yay (AUR helper) - compile from source during ISO build
if ! command -v yay >/dev/null 2>&1; then
    useradd -m -G wheel -s /bin/bash builduser 2>/dev/null || true
    echo 'builduser ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/builduser
    
    mkdir -p /var/tmp/go-build
    chown builduser:builduser /var/tmp/go-build
    
    # Temporarily disable pacman disk space check (chroot filesystem issue)
    sed -i 's/^CheckSpace/#CheckSpace/' /etc/pacman.conf
    
    cd /var/tmp
    sudo -u builduser git clone https://aur.archlinux.org/yay.git
    cd yay
    sudo -u builduser env \
        GOCACHE=/var/tmp/go-build \
        GOMODCACHE=/var/tmp/go-mod \
        GOPATH=/var/tmp/go \
        TMPDIR=/var/tmp \
        makepkg -si --noconfirm
    
    # Re-enable disk space check
    sed -i 's/^#CheckSpace/CheckSpace/' /etc/pacman.conf
    
    cd /
    rm -rf /var/tmp/yay /var/tmp/go-build /var/tmp/go-mod /var/tmp/go
    userdel -r builduser 2>/dev/null || true
    rm /etc/sudoers.d/builduser
fi

# Suppress KDE Welcome (A+B combined approach)
# A: Pre-set "already seen" config flag for new users
mkdir -p /etc/skel/.config
cat > /etc/skel/.config/PlasmaWelcome.conf << 'INNER_EOF'
[General]
LastSeenVersion=99999
INNER_EOF


# B: Replace plasma-welcome with silent no-op (prevents error popups)
if [ -f /usr/bin/plasma-welcome ]; then
    cat > /usr/bin/plasma-welcome << 'INNER_EOF'
#!/bin/bash
# CobaltX: plasma-welcome disabled (replaced by CobaltX Welcome App)
exit 0
INNER_EOF
    chmod 755 /usr/bin/plasma-welcome
fi

# v0.3: don't auto-open Welcome App on the live ISO (installed users still get it from /etc/skel)
rm -f /home/cobalt/.config/autostart/cobaltx-welcome-firstboot.desktop

# v0.3: enable multilib in the installed system's pacman.conf
sed -i '/^#\[multilib\]/,/^#Include/ s/^#//' /etc/pacman.conf

# CobaltX: Handheld Daemon (AUR) for handheld controls - never fails the build
bash /root/cobaltx-build-hhd.sh
rm -f /root/cobaltx-build-hhd.sh
