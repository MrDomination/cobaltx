#!/bin/bash
# CobaltX NVIDIA Driver Installer (v0.3)
# Picks the right driver for the GPU generation, and refuses cards that
# no current driver supports (instead of breaking the desktop).

CYAN='\033[0;36m'; GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; NC='\033[0m'

pause_exit() { echo ""; read -rp "Press Enter to close..."; exit "${1:-0}"; }

clear
echo -e "${CYAN}"
echo "╔════════════════════════════════════════╗"
echo "║    CobaltX NVIDIA Driver Installer     ║"
echo "║            Forged for play             ║"
echo "╚════════════════════════════════════════╝"
echo -e "${NC}"

# --- Find the NVIDIA GPU (vendor 10de) ---------------------------------------
GPU_LINE=$(lspci -nn | grep -Ei "vga|3d|display" | grep -i "\[10de:" | head -1)
if [ -z "$GPU_LINE" ]; then
    echo -e "${YELLOW}⚠  No NVIDIA GPU detected.${NC}"
    echo "This installer is only needed for NVIDIA graphics cards."
    echo "Intel and AMD GPUs already work out of the box on CobaltX."
    pause_exit 0
fi

GPU_NAME=$(echo "$GPU_LINE" | sed -E 's/.*: //; s/ \[10de:[0-9a-f]+\].*//; s/ \(rev .*//')
DEV_ID=$(echo "$GPU_LINE" | grep -oiE "\[10de:[0-9a-f]{4}\]" | cut -d: -f2 | tr -d ']')
DEV_DEC=$((16#$DEV_ID))

echo -e "${GREEN}✓ NVIDIA GPU detected:${NC} $GPU_NAME"
echo "  Device ID: 10de:$DEV_ID"
echo ""

# --- Decide driver by GPU generation ------------------------------------------
# Device IDs:  >= 0x1E00  Turing and newer (GTX 16xx, RTX 20xx+)  -> nvidia-open (official repos)
#              0x1340-0x1DFF  Maxwell / Pascal / Volta (GTX 7xx-9xx, 10xx) -> nvidia-580xx (AUR legacy)
#              <  0x1340  Kepler / Fermi and older (e.g. GT 730)   -> no supported driver, keep nouveau
if [ "$DEV_DEC" -ge $((16#1E00)) ]; then
    TIER="modern"
elif [ "$DEV_DEC" -ge $((16#1340)) ]; then
    TIER="legacy"
else
    TIER="unsupported"
fi

if [ "$TIER" = "unsupported" ]; then
    echo -e "${YELLOW}⚠  This GPU is too old for NVIDIA's current drivers.${NC}"
    echo ""
    echo "NVIDIA stopped supporting this generation (Kepler or older)."
    echo "The last driver that supported it does not work with the"
    echo "KDE Plasma 6 desktop that CobaltX uses, and installing it"
    echo "would leave you with a broken desktop."
    echo ""
    echo -e "${GREEN}Good news:${NC} your card already works with the built-in"
    echo "open-source driver (nouveau). Nothing needs to be installed."
    echo ""
    echo "Tip: for games, use lower settings - nouveau runs these cards"
    echo "at reduced clock speeds."
    pause_exit 0
fi

if [ "$TIER" = "modern" ]; then
    echo "Driver: NVIDIA open kernel modules (latest, official Arch repos)"
    PKGS="nvidia-open-dkms nvidia-utils lib32-nvidia-utils nvidia-settings"
else
    echo -e "Driver: NVIDIA 580 legacy branch ${YELLOW}(from the AUR)${NC}"
    echo "Your card (Maxwell/Pascal era) is no longer supported by the"
    echo "newest driver, so the long-term 580 branch is used instead."
    echo "Building it takes a few minutes."
    PKGS="nvidia-580xx-dkms nvidia-580xx-utils lib32-nvidia-580xx-utils nvidia-580xx-settings"
fi
echo ""
echo -e "${YELLOW}A reboot is required after installation.${NC}"
echo ""
read -rp "Continue with installation? (Y/n): " REPLY
[[ $REPLY =~ ^[Nn]$ ]] && { echo "Installation cancelled."; pause_exit 0; }

set -e
trap 'echo -e "\n${RED}✗ Installation failed. Nothing was changed in your boot setup.${NC}"; pause_exit 1' ERR

echo -e "\n${CYAN}▶ Updating system...${NC}"
sudo pacman -Syu --noconfirm

echo -e "\n${CYAN}▶ Installing kernel headers...${NC}"
sudo pacman -S --needed --noconfirm linux-zen-headers

echo -e "\n${CYAN}▶ Installing NVIDIA drivers...${NC}"
if [ "$TIER" = "modern" ]; then
    sudo pacman -S --needed --noconfirm $PKGS
else
    yay -S --needed --noconfirm --answerdiff None --answerclean None $PKGS
fi

trap - ERR
set +e

# --- Only touch boot config after the driver installed successfully -----------
echo -e "\n${CYAN}▶ Configuring early KMS...${NC}"
if ! grep -q "nvidia_drm" /etc/mkinitcpio.conf; then
    sudo sed -i 's/^MODULES=(\(.*\))/MODULES=(\1 nvidia nvidia_modeset nvidia_uvm nvidia_drm)/' /etc/mkinitcpio.conf
fi

echo -e "${CYAN}▶ Enabling DRM modesetting (Wayland)...${NC}"
for entry in /boot/loader/entries/cobaltx*.conf /efi/loader/entries/cobaltx*.conf; do
    [ -f "$entry" ] || continue
    grep -q "nvidia_drm.modeset" "$entry" || sudo sed -i '/^options/ s/$/ nvidia_drm.modeset=1/' "$entry"
done

echo -e "${CYAN}▶ Disabling nouveau...${NC}"
printf "blacklist nouveau\noptions nouveau modeset=0\n" | sudo tee /etc/modprobe.d/blacklist-nouveau.conf > /dev/null

echo -e "${CYAN}▶ Regenerating initramfs...${NC}"
sudo mkinitcpio -P

echo ""
echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║        ✓ Installation Complete!        ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
echo ""
read -rp "Reboot now? (y/N): " REPLY
if [[ $REPLY =~ ^[Yy]$ ]]; then sudo reboot; else echo "Please reboot when ready."; pause_exit 0; fi
