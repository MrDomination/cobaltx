[README.md](https://github.com/user-attachments/files/33615122/README.md)
<div align="center">

# CobaltX

### 🎮 Forged for play.

**A gaming-focused Arch-based Linux distribution.**

[![License: GPL v3](https://img.shields.io/badge/License-GPL%20v3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)
[![Version](https://img.shields.io/badge/version-0.3-00E5FF.svg)](https://github.com/MrDomination/cobaltx/releases)
[![Codename](https://img.shields.io/badge/codename-Fullscreened-00E5FF.svg)](https://mrdomination.github.io/cobaltx/)
[![Arch Based](https://img.shields.io/badge/based%20on-Arch%20Linux-0047AB.svg)](https://archlinux.org/)
[![Desktop](https://img.shields.io/badge/desktop-KDE%20Plasma%206-1d99f3.svg)](https://kde.org/plasma-desktop/)
[![Buy Me A Coffee](https://img.shields.io/badge/support-Buy%20Me%20A%20Coffee-FFDD00.svg)](https://buymeacoffee.com/cobaltx)

[**🌐 Website**](https://mrdomination.github.io/cobaltx/) · [**📥 Download**](https://mrdomination.github.io/cobaltx/) · [**☕ Support**](https://buymeacoffee.com/cobaltx) · [**🐛 Issues**](https://github.com/MrDomination/cobaltx/issues)

</div>

---

## 🎯 About

CobaltX is a Linux distribution built specifically for **gamers**, on the rock-solid foundation of **Arch Linux**. It comes pre-configured with the complete Linux gaming stack — no setup required, no driver hunting, no terminal tinkering. Just install, sign in, and play.

Built from scratch using `archiso` with a custom Calamares installer, custom branding, and the `linux-zen` kernel for low-latency desktop performance.

## ✨ What's New in v0.3 "Fullscreened"

- 🎮 **X Mode** — a full-screen, controller-first game launcher with its own login session. Steam, Heroic, Bottles, Lutris and your own games in one place
- 🚀 **Boot into X Mode** — pick X Mode or the desktop in the installer, switch between them anytime
- 🕹️ **Handheld support** — built-in controls and back buttons on the ROG Ally family, Legion Go, MSI Claw and more via Handheld Daemon
- ⚡ **Quick Settings & TDP** — performance modes, power limit in watts, brightness and volume, in X Mode and on the desktop
- ⌨️ **CobaltX Keyboard** — themed on-screen keyboard that types into any app or game (controller or touch)
- 🖱️ **Controller cursor** — use the stick as a mouse on the desktop
- 📚 **Library + Add a game** — add AppImages, `.exe` files, scripts or ROMs that weren't found automatically
- 🪟 **Open apps** — resume or close running apps, with Force close for frozen ones
- 🛠️ **Real-hardware fixes** — safer install next to other systems on a shared EFI partition, smarter NVIDIA driver setup, new wallpapers, CobaltX fastfetch logo

## ✨ Highlights

- 🎮 **Complete gaming stack pre-installed** — Steam, Heroic Games Launcher, Bottles, Lutris, Wine, RetroArch, MangoHud, GameMode
- ⚡ **linux-zen kernel** — Optimized for low-latency desktop and gaming workloads
- 🖥️ **KDE Plasma 6** — Modern, beautiful, fully-featured desktop environment
- 📦 **Arch Linux foundation** — Bleeding-edge packages, full AUR access, rolling release
- 🎨 **Custom CobaltX branding** — Polished UI from boot to desktop
- 🎮 **X Mode** — Console-style, controller-first launcher for TVs and handhelds
- 🚀 **Modern boot** — systemd-boot with UEFI support, plus Plymouth splash
- 🛡️ **Ready for NVIDIA** — Intel and AMD GPUs work out of the box; NVIDIA via one-click installer
- 🦊 **Custom Welcome App** — First-boot greeter with quick actions & system info

## 📥 Download

The latest CobaltX ISO is available at the [**official website**](https://mrdomination.github.io/cobaltx/).

**Current release:** CobaltX 0.3 "Fullscreened" — [`cobaltx-0.3-x86_64.iso`](https://pub-cccf87fd7a134c0c9247dd0695e84377.r2.dev/cobaltx-0.3-x86_64.iso) (~6.4 GB)

## 🚀 Installation

1. **Download** the CobaltX ISO from the [website](https://mrdomination.github.io/cobaltx/)
2. **Flash** it to a USB stick (8 GB+) using:
   - **Ventoy** (recommended — multiboot USB)
   - **Rufus** (Windows)
   - **balenaEtcher** (cross-platform)
   - Or `dd`:
     ```bash
     sudo dd if=cobaltx-0.3-x86_64.iso of=/dev/sdX bs=4M status=progress
     ```
     *(Replace `/dev/sdX` with your USB device — be careful!)*
3. **Boot** from USB (UEFI mode required)
4. **Click** "Install CobaltX" on the desktop
5. **Follow** the Calamares installer wizard
6. **Choose** Desktop or X Mode on the X Mode page of the installer
7. **Reboot** and enjoy!

## 🎮 What's Inside

CobaltX includes everything you need to game on Linux out of the box:

### Gaming Platforms
- 🎮 **Steam** — with Proton for Windows games
- 🦊 **Heroic Games Launcher** — Epic Games, GOG, Amazon Prime Gaming
- 🍶 **Bottles** — Run Windows apps in isolated environments
- 🎯 **Lutris** — Universal game manager
- 🕹️ **RetroArch** — Retro game emulation frontend

### Compatibility & Tools
- 🍷 **Wine** — Windows compatibility layer
- ⚙️ **GameMode** — CPU/GPU optimization during gameplay
- 📊 **MangoHud** — Performance overlay (FPS, temps, etc.)
- 🎥 **OBS Studio** — Screen recording & streaming
- 💬 **Discord** — Voice chat with your team

### CobaltX Extras
- 🎮 **X Mode** — Full-screen controller launcher and session
- 🕹️ **Handheld Daemon** — Handheld controls (ROG Ally, Legion Go, MSI Claw, …)
- ⌨️ **CobaltX Keyboard** — On-screen keyboard
- 💻 **NVIDIA installer** — One-click GPU driver setup
- 🦊 **CobaltX Welcome App** — First-boot experience
- 🎨 **Plymouth** — Animated boot splash
- 📦 **yay** — AUR helper pre-installed

## 🔧 System Requirements

| Component | Requirement |
|-----------|-------------|
| **CPU** | x86_64 (Intel/AMD 64-bit) |
| **RAM** | 4 GB minimum · 8 GB recommended |
| **Storage** | 30 GB minimum |
| **Boot** | UEFI required |
| **GPU** | Intel/AMD (out of box) · NVIDIA (one-click installer) |
| **Handhelds** | ROG Ally / Ally X / Xbox Ally, Legion Go, MSI Claw, Steam Deck and more |

## 🛠️ Build From Source

Advanced users can build CobaltX from source:

```bash
# Clone this repository
git clone https://github.com/MrDomination/cobaltx.git
cd cobaltx

# Build the ISO (requires archiso, ~50-70 min)
sudo rm -rf cobaltx-buildwork
sudo mkarchiso -v -w cobaltx-buildwork -o out .
```

The built ISO will appear in `out/cobaltx-0.3-x86_64.iso`.

## 🤝 Contributing

CobaltX is open source! Contributions are welcome:

- 🐛 **Report bugs** in [Issues](https://github.com/MrDomination/cobaltx/issues)
- 💡 **Suggest features** in [Discussions](https://github.com/MrDomination/cobaltx/discussions)
- 📝 **Improve documentation**
- 🌍 **Translate** the distro

## ☕ Support CobaltX

CobaltX is a one-person project built in spare time. If you find it useful, consider supporting development:

- ☕ **[Buy me a coffee](https://buymeacoffee.com/cobaltx)** — directly funds late-night coding for v0.4
- ⭐ **Star this repo** — free, instant, and means a lot
- 📢 **Share CobaltX** — tell other Linux gamers about it
- 🐛 **Report bugs and feedback** — helps make v0.4 better

## 📋 Roadmap

Ideas for future releases:

- 🎛️ Per-game gamescope (FSR upscaling, frame limits) from X Mode
- 🖼️ Task view with live window previews
- 🌍 More keyboard layouts for the on-screen keyboard
- 🛡️ Security hardening defaults
- 🖥️ Better hardware detection & recommendations

## ⚠️ Known Issues

- The on-screen keyboard uses the US layout
- The controller cursor in X Mode also moves the mouse in games — turn it off before playing
- GOverlay was removed (crashes on first start in its current version); MangoHud is still included

## 📝 License

CobaltX is licensed under the **GNU General Public License v3.0**. See [LICENSE](LICENSE) for the full text.

Individual software packages included in CobaltX retain their own licenses.

## 👤 Author

CobaltX is crafted in Phuket, Thailand by a passionate gamer who wanted Linux to be the best gaming OS possible.

---

<div align="center">

**[🌐 Website](https://mrdomination.github.io/cobaltx/)** · **[📥 Download](https://mrdomination.github.io/cobaltx/)** · **[☕ Support](https://buymeacoffee.com/cobaltx)** · **[🐛 Issues](https://github.com/MrDomination/cobaltx/issues)**

Made with 💙 in Phuket · Forged for play

</div>
