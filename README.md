[README_1.md](https://github.com/user-attachments/files/28712811/README_1.md)
<div align="center">

# CobaltX

### 🎮 Forged for play.

**A gaming-focused Arch-based Linux distribution.**

[![License: GPL v3](https://img.shields.io/badge/License-GPL%20v3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)
[![Version](https://img.shields.io/badge/version-0.1.0-00E5FF.svg)](https://github.com/MrDomination/cobaltx/releases)
[![Arch Based](https://img.shields.io/badge/based%20on-Arch%20Linux-0047AB.svg)](https://archlinux.org/)
[![Desktop](https://img.shields.io/badge/desktop-KDE%20Plasma%206-1d99f3.svg)](https://kde.org/plasma-desktop/)
[![Buy Me A Coffee](https://img.shields.io/badge/support-Buy%20Me%20A%20Coffee-FFDD00.svg)](https://buymeacoffee.com/cobaltx)

[**🌐 Website**](https://mrdomination.github.io/cobaltx/) · [**📥 Download**](https://mrdomination.github.io/cobaltx/) · [**☕ Support**](https://buymeacoffee.com/cobaltx) · [**🐛 Issues**](https://github.com/MrDomination/cobaltx/issues)

</div>

---

## 💎 What is CobaltX?

CobaltX is a Linux distribution built specifically for **gamers**, on the rock-solid foundation of Arch Linux. It comes pre-configured with the complete Linux gaming stack — no setup required, no driver hunting, no terminal tinkering. Just install, sign in, and play.

Built from scratch using `archiso` with a custom Calamares installer, custom branding, and the linux-zen kernel for low-latency desktop performance.

## ✨ Features

- 🎮 **Complete gaming stack pre-installed** — Steam, Heroic Games Launcher, Bottles, Lutris, Wine, RetroArch, MangoHud, GameMode
- ⚡ **linux-zen kernel** — Optimized for low-latency desktop and gaming workloads
- 🖥️ **KDE Plasma 6** — Modern, beautiful, fully-featured desktop environment
- 📦 **Arch Linux foundation** — Bleeding-edge packages, full AUR access, rolling release
- 🎨 **Custom CobaltX branding** — Polished UI from boot to desktop
- 🛡️ **systemd-boot** — Fast, reliable UEFI boot
- 🚀 **Mesa + Vulkan stack** — Full Intel/AMD GPU support out of the box
- 📥 **Calamares installer** — Graphical, beginner-friendly installation

## 💻 System Requirements

| Component | Minimum | Recommended |
|-----------|---------|-------------|
| **CPU** | x86_64 (Intel/AMD 64-bit) | Modern multi-core |
| **RAM** | 4 GB | 8 GB+ |
| **Storage** | 30 GB | 50 GB+ |
| **Boot** | UEFI (required) | UEFI |
| **GPU** | Intel / AMD (out of box) | Dedicated GPU |

> 📝 **NVIDIA users:** Install proprietary drivers via `sudo pacman -S nvidia` after first boot.

## 📥 Download

The latest CobaltX ISO is available at the [**official website**](https://mrdomination.github.io/cobaltx/).

**File:** `cobaltx-0.1.0-x86_64.iso` · **Size:** ~5.6 GB

## 🚀 Installation

1. **Download** the ISO from the website above
2. **Verify** the checksum (optional but recommended)
3. **Flash** to USB with [Ventoy](https://www.ventoy.net/), [Rufus](https://rufus.ie/), [balenaEtcher](https://etcher.balena.io/), or `dd`:
   ```bash
   sudo dd if=cobaltx-0.1.0-x86_64.iso of=/dev/sdX bs=4M status=progress
   ```
   *(Replace `/dev/sdX` with your USB device — be careful!)*
4. **Boot** from USB (UEFI mode required)
5. **Click "Install CobaltX"** on the desktop
6. **Follow** the Calamares installer wizard
7. **Reboot** and enjoy!

## 🎮 Gaming Stack

CobaltX includes everything you need to game on Linux out of the box:

| Tool | Purpose |
|------|---------|
| **Steam** | Steam library + Proton |
| **Heroic Games Launcher** | Epic Games, GOG, Amazon Games |
| **Bottles** | Run Windows applications |
| **Lutris** | Unified game manager |
| **Wine + Winetricks** | Windows compatibility layer |
| **RetroArch** | Retro game emulation |
| **MangoHud** | In-game performance overlay |
| **GameMode** | System optimizations during gaming |
| **OBS Studio** | Game streaming/recording |
| **Discord** | Gaming chat |

## 🛠️ Tech Stack

- **Base:** Arch Linux
- **Kernel:** linux-zen
- **Desktop:** KDE Plasma 6
- **Display Manager:** SDDM
- **Bootloader:** systemd-boot
- **Installer:** Calamares
- **Init System:** systemd
- **Package Manager:** pacman + AUR

## 🤝 Contributing

CobaltX is open source! Contributions are welcome:

- 🐛 **Report bugs** in [Issues](https://github.com/MrDomination/cobaltx/issues)
- 💡 **Suggest features** in [Discussions](https://github.com/MrDomination/cobaltx/discussions)
- 📝 **Improve documentation**
- 🌍 **Translate** the distro

## ☕ Support CobaltX

CobaltX is a one-person project built in spare time. If you find it useful, consider supporting development:

- ☕ **[Buy me a coffee](https://buymeacoffee.com/cobaltx)** — directly funds late-night coding for v0.2
- ⭐ **Star this repo** — free, instant, and means a lot
- 📢 **Share CobaltX** — tell other Linux gamers about it
- 🐛 **Report bugs and feedback** — helps make v0.2 better

## 🗺️ Roadmap

### v0.2 — Planned
- 🎨 Custom SDDM login theme
- 🦊 First-boot Welcome App with NVIDIA driver installer
- 🚀 Custom GRUB splash screen
- 📦 Pre-installed Proton-GE
- 🎮 Steam Deck-style game mode
- 🛡️ Improved security defaults

## ⚠️ Known Issues

- **Steam may take 1-2 minutes to launch in VirtualBox** — Use real hardware for full performance
- **NVIDIA drivers require manual install** — Run `sudo pacman -S nvidia` after first boot
- **First release** — Some rough edges expected; please report what you find!

## 📜 License

CobaltX is licensed under the **GNU General Public License v3.0**. See [LICENSE](LICENSE) for the full text.

Individual software packages included in CobaltX retain their own licenses.

## 🙏 Credits

CobaltX stands on the shoulders of giants:

- **[Arch Linux](https://archlinux.org/)** — The rock-solid foundation
- **[KDE Plasma](https://kde.org/)** — Beautiful desktop environment
- **[Calamares](https://calamares.io/)** — Universal installer framework
- **[EndeavourOS](https://endeavouros.com/)** — Inspiration for Calamares configuration
- **[archiso](https://wiki.archlinux.org/title/Archiso)** — ISO build tool
- The entire **Linux gaming community** ❤️

## 💙 Made With Love

CobaltX is crafted in **Phuket, Thailand** by a passionate gamer who wanted Linux to be the best gaming OS possible.

---

<div align="center">

**[🌐 Website](https://mrdomination.github.io/cobaltx/)** · **[📥 Download](https://mrdomination.github.io/cobaltx/)** · **[☕ Support](https://buymeacoffee.com/cobaltx)** · **[🐛 Issues](https://github.com/MrDomination/cobaltx/issues)**

Made with 💙 in Phuket · Forged for play

</div>
