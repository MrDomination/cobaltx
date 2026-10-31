#!/usr/bin/env python3
"""
CobaltX Welcome App
Native PyQt6 + QtWebEngine launcher
"""

import json
import os
import platform
import re
import subprocess
import sys

from PyQt6.QtCore import QUrl
from PyQt6.QtGui import QIcon
from PyQt6.QtWidgets import QApplication, QMainWindow, QMessageBox
from PyQt6.QtWebEngineWidgets import QWebEngineView

APP_DIR = "/usr/share/cobaltx-welcome"
AUTOSTART_DIR = os.path.expanduser("~/.config/autostart")
AUTOSTART_FILE = os.path.join(AUTOSTART_DIR, "cobaltx-welcome-firstboot.desktop")


def read_os_name():
    try:
        with open("/etc/os-release") as f:
            for line in f:
                if line.startswith("PRETTY_NAME="):
                    return line.split("=", 1)[1].strip().strip('"')
    except Exception:
        pass
    return "CobaltX"


def read_cpu():
    try:
        with open("/proc/cpuinfo") as f:
            for line in f:
                if line.startswith("model name"):
                    name = line.split(":", 1)[1].strip()
                    return re.sub(r"\s+", " ", name.replace("(R)", "").replace("(TM)", ""))
    except Exception:
        pass
    return "Unknown"


def read_ram():
    try:
        with open("/proc/meminfo") as f:
            for line in f:
                if line.startswith("MemTotal"):
                    kb = int(line.split()[1])
                    return f"{kb / 1024 / 1024:.1f} GB"
    except Exception:
        pass
    return "Unknown"


def read_gpus():
    """Return a readable list of GPUs, e.g. 'NVIDIA GeForce GT 730'."""
    try:
        out = subprocess.run(["lspci"], capture_output=True, text=True, timeout=5).stdout
    except Exception:
        return "Unknown"
    gpus = []
    for line in out.splitlines():
        if not re.search(r"VGA compatible controller|3D controller|Display controller", line):
            continue
        desc = line.split(":", 2)[-1].strip()
        desc = re.sub(r"\s*\(rev [0-9a-f]+\)", "", desc)
        vendor = desc.split()[0] if desc else ""
        bracket = re.findall(r"\[([^\]]+)\]", desc)
        if bracket:
            name = bracket[-1]
            if vendor.upper() == "NVIDIA" and not name.upper().startswith("NVIDIA"):
                name = "NVIDIA " + name
            elif vendor.startswith("Advanced") and "AMD" not in name:
                name = "AMD " + name
            elif vendor == "Intel" and "Intel" not in name:
                name = "Intel " + name
        else:
            name = desc.replace(" Corporation", "").replace(" Technology Inc.", "")
        if len(name) > 60:
            name = name[:57] + "..."
        gpus.append(name)
    return " + ".join(gpus) if gpus else "Unknown"


def read_desktop():
    try:
        out = subprocess.run(["plasmashell", "--version"], capture_output=True, text=True, timeout=5).stdout
        ver = out.strip().split()[-1]
        if ver:
            return f"KDE Plasma {ver}"
    except Exception:
        pass
    return "KDE Plasma"


def get_system_info():
    return {
        "os": read_os_name(),
        "kernel": platform.release(),
        "cpu": read_cpu(),
        "ram": read_ram(),
        "gpu": read_gpus(),
        "desktop": read_desktop(),
    }


def open_url(url):
    subprocess.Popen(["xdg-open", url])


def run_action(action):
    if action == "update":
        subprocess.Popen([
            "konsole", "-e", "bash", "-c",
            "sudo pacman -Syu; flatpak update -y; echo; echo 'Press Enter to close.'; read"
        ])
    elif action == "nvidia":
        subprocess.Popen(["konsole", "-e", "/usr/local/bin/cobaltx-nvidia-install.sh"])
    elif action == "steam":
        subprocess.Popen(["steam"])
    elif action == "heroic":
        subprocess.Popen(["flatpak", "run", "com.heroicgameslauncher.hgl"])
    elif action == "bottles":
        subprocess.Popen(["flatpak", "run", "com.usebottles.bottles"])
    elif action == "discover":
        subprocess.Popen(["plasma-discover"])


def set_autostart(enabled):
    """Add or remove the login autostart entry."""
    if enabled:
        os.makedirs(AUTOSTART_DIR, exist_ok=True)
        with open(AUTOSTART_FILE, "w") as f:
            f.write(
                "[Desktop Entry]\n"
                "Type=Application\n"
                "Name=CobaltX Welcome\n"
                "Comment=Welcome screen\n"
                "Exec=/usr/local/bin/cobaltx-welcome-app\n"
                "Icon=cobaltx-welcome\n"
                "Terminal=false\n"
                "Categories=System;\n"
                "X-KDE-autostart-after=panel\n"
            )
    elif os.path.exists(AUTOSTART_FILE):
        os.remove(AUTOSTART_FILE)


class WelcomeWindow(QMainWindow):
    def __init__(self):
        super().__init__()
        self.setWindowTitle("Welcome to CobaltX")
        self.setMinimumSize(950, 720)
        self.resize(1000, 780)

        for path in ("/usr/share/icons/hicolor/256x256/apps/cobaltx-welcome.png",
                     "/usr/share/icons/hicolor/scalable/apps/cobaltx-welcome.svg"):
            if os.path.exists(path):
                self.setWindowIcon(QIcon(path))
                break

        html_path = os.path.join(APP_DIR, "index.html")
        if not os.path.exists(html_path):
            QMessageBox.critical(self, "Error", f"Welcome app not found at {html_path}")
            sys.exit(1)

        self.web = QWebEngineView()
        self.web.setUrl(QUrl.fromLocalFile(html_path))
        self.setCentralWidget(self.web)

        self.web.page().titleChanged.connect(self.handle_title_change)
        self.web.loadFinished.connect(self.on_loaded)

    def on_loaded(self, ok):
        # v0.3 fix: send system info straight into the page.
        # (v0.2 tried to write a JSON file into /usr/share, which normal users can't do.)
        if not ok:
            return
        info = json.dumps(get_system_info())
        autostart = "true" if os.path.exists(AUTOSTART_FILE) else "false"
        self.web.page().runJavaScript(f"setSysInfo({info}); setAutostart({autostart});")

    def handle_title_change(self, title):
        if title.startswith("ACTION:"):
            run_action(title.split(":", 1)[1])
        elif title.startswith("LINK:"):
            open_url(title.split(":", 1)[1])
        elif title.startswith("AUTOSTART:"):
            set_autostart(title.split(":", 1)[1] == "true")


def main():
    app = QApplication(sys.argv)
    app.setApplicationName("CobaltX Welcome")
    app.setOrganizationName("CobaltX")
    app.setDesktopFileName("cobaltx-welcome")
    window = WelcomeWindow()
    window.show()
    sys.exit(app.exec())


if __name__ == "__main__":
    main()
