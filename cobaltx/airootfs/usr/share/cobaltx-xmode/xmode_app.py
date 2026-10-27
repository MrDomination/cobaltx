"""X Mode - CobaltX's fullscreen handheld game launcher (Python side)."""
import faulthandler
import glob
import json
import os
import re
import signal
import shutil
import subprocess
import sys
import threading
import time
from pathlib import Path

from PyQt6.QtCore import (QObject, QSize, Qt, QTimer, QUrl, pyqtProperty,
                          pyqtSignal, pyqtSlot, qInstallMessageHandler)
from PyQt6.QtGui import QGuiApplication, QIcon, QImage, QImageReader
from PyQt6.QtQml import QQmlApplicationEngine
from PyQt6.QtQuick import QQuickImageProvider

import library
import handheld_settings
from gamepad import Gamepad
from sound import SoundPlayer
from windows import WindowManager
from quicksettings import QuickSettings

VERSION = "0.3"
DATA_DIR = Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share")) / "cobaltx-xmode"
HISTORY_FILE = DATA_DIR / "history.json"
SETTINGS_FILE = DATA_DIR / "settings.json"
PLAYS_FILE = DATA_DIR / "plays.json"
LOG_FILE = DATA_DIR / "xmode.log"
FREEZE_SECONDS = 8
LAUNCH_COOLDOWN = 3.0


ICON_DIRS = [Path.home() / ".local/share/icons", Path.home() / ".local/share/flatpak/exports/share/icons",
             Path("/var/lib/flatpak/exports/share/icons"), Path("/usr/share/icons")]
ICON_THEMES = ["hicolor", "breeze", "breeze-dark", "Adwaita"]
ICON_SIZES = ["scalable", "512x512", "256x256", "128x128", "96x96", "64x64", "48x48"]


def find_icon_file(name):
    """Theme icon name -> file path. Plain file lookups only, so it is safe to
    run in Qt Quick's image-loading thread (QIcon there caused thread warnings)."""
    if not name:
        return None
    if name.startswith("/"):
        return name if os.path.isfile(name) else None
    for base in ICON_DIRS:
        for theme in ICON_THEMES:
            for size in ICON_SIZES:
                for sub in ("apps", "places", "devices"):
                    for ext in (".svg", ".png"):
                        f = base / theme / size / sub / (name + ext)
                        if f.is_file():
                            return str(f)
        # breeze uses apps/48 style folders
        for f in glob.glob(str(base / "breeze*" / "apps" / "*" / (name + ".svg"))):
            return f
    for ext in (".svg", ".png", ".xpm"):
        f = Path("/usr/share/pixmaps") / (name + ext)
        if f.is_file():
            return str(f)
    return None


class IconProvider(QQuickImageProvider):
    """image://icon/<name> -> icon from the icon theme folders."""

    def __init__(self):
        super().__init__(QQuickImageProvider.ImageType.Image)
        self._cache = {}

    def requestImage(self, icon_id, requested_size):
        size = requested_size if requested_size.isValid() and requested_size.width() > 0 else QSize(256, 256)
        if icon_id not in self._cache:
            # "net.lutris.Lutris" -> also try "lutris"
            names = [icon_id] + ([icon_id.rsplit(".", 1)[-1].lower()] if "." in icon_id and not icon_id.startswith("/") else [])
            self._cache[icon_id] = next((f for f in map(find_icon_file, names) if f), None)
        path = self._cache[icon_id]
        img = QImage()
        if path:
            reader = QImageReader(path)
            if path.endswith(".svg"):
                reader.setScaledSize(size)
            img = reader.read()
            if not img.isNull() and not path.endswith(".svg"):
                img = img.scaled(size, Qt.AspectRatioMode.KeepAspectRatio,
                                 Qt.TransformationMode.SmoothTransformation)
        return img, img.size()


class Backend(QObject):
    gamesChanged = pyqtSignal()
    scanningChanged = pyqtSignal()
    batteryChanged = pyqtSignal()
    action = pyqtSignal(str)       # controller -> QML
    toast = pyqtSignal(str)
    launched = pyqtSignal()
    soundsChanged = pyqtSignal()
    inputChanged = pyqtSignal()
    startAtLoginChanged = pyqtSignal()
    appsChanged = pyqtSignal()
    keyboardVisibleChanged = pyqtSignal()
    cursorChanged = pyqtSignal()
    removed = pyqtSignal()                 # a custom game was removed (close its page)
    _scanned = pyqtSignal(list)    # scanner thread -> main thread

    def __init__(self, fullscreen, in_session, sounds=None):
        super().__init__()
        self._sounds = sounds
        self._wm = WindowManager(self)
        self._apps = []
        self._wm.windowsChanged.connect(self._on_windows)
        self._wm.taskViewRequested.connect(lambda: self.action.emit("apps"))   # Alt+F12: open apps
        self._closing = {}                 # window id -> time Close was pressed
        self._kb_visible = False           # on-screen keyboard open?
        self._pad = None                   # last controller seen (family, name)
        self._cursor = None                # controller cursor (for apps opened from X Mode)
        self._wm.keyboardVisible.connect(self._on_kb_visible)
        self._fullscreen = fullscreen
        self._in_session = in_session
        self._games = []
        self._launch = {}
        self._scanning = False
        self._battery = -1
        self._charging = False
        self._last_launch = 0.0
        self._history = self._load_json(HISTORY_FILE)
        self._plays = self._load_json(PLAYS_FILE)
        self._open = {}
        self._input = "keyboard"
        self._input_name = "Keyboard & Mouse"
        self._settings = {"sounds": True, **self._load_json(SETTINGS_FILE)}
        if self._sounds:
            self._sounds.enabled = self.soundsOn
        self._scanned.connect(self._on_scanned)
        self.updateBattery()

    # ------------------------------------------------------------ properties
    @pyqtProperty("QVariantList", notify=gamesChanged)
    def games(self):
        return self._games

    @pyqtProperty(bool, notify=scanningChanged)
    def scanning(self):
        return self._scanning

    @pyqtProperty(bool, constant=True)
    def fullscreen(self):
        return self._fullscreen

    @pyqtProperty(bool, constant=True)
    def inSession(self):
        return self._in_session

    @pyqtProperty(str, constant=True)
    def version(self):
        return VERSION

    @pyqtProperty(int, notify=batteryChanged)
    def battery(self):
        return self._battery

    @pyqtProperty(bool, notify=batteryChanged)
    def charging(self):
        return self._charging

    # ---------------------------------------------------------------- library
    @pyqtSlot()
    def refresh(self):
        if self._scanning:
            return
        self._scanning = True
        self.scanningChanged.emit()
        threading.Thread(target=lambda: self._scanned.emit(library.scan_all()), daemon=True).start()

    def _on_scanned(self, games):
        self._launch = {g["key"]: g.pop("launch") for g in games}
        self._open = {g["key"]: g.pop("open") for g in games}
        self._games = games
        self._apply_history()
        self._scanning = False
        self.scanningChanged.emit()

    def _apply_history(self):
        for g in self._games:
            # newest of: launched from X Mode, or played through Steam/Heroic directly
            g["lastPlayed"] = max(self._history.get(g["key"], 0), g.get("extLastPlayed", 0))
            g["plays"] = self._plays.get(g["key"], 0)
        self.gamesChanged.emit()

    @staticmethod
    def _load_json(path):
        try:
            data = json.loads(path.read_text())
            return data if isinstance(data, dict) else {}
        except Exception:
            return {}

    @staticmethod
    def _save_json(path, data):
        try:
            DATA_DIR.mkdir(parents=True, exist_ok=True)
            path.write_text(json.dumps(data))
        except Exception as e:
            print(f"[xmode] could not save {path.name}:", e)

    def _save_history(self):
        self._save_json(HISTORY_FILE, self._history)

    # ------------------------------------------------------- input method
    # Like Steam: whatever you touched last decides which button glyphs show.
    @pyqtProperty(str, notify=inputChanged)
    def inputMode(self):
        return self._input

    @pyqtProperty(str, notify=inputChanged)
    def inputName(self):
        return self._input_name

    def set_input(self, family, name):
        if family != "keyboard":
            self._pad = (family, name)         # the controller to go back to
        if (family, name) != (self._input, self._input_name):
            self._input, self._input_name = family, name
            self.inputChanged.emit()
            if self._kb_visible and self._in_session:
                self._keyboard("SetFamily", family)

    @pyqtSlot()
    def useKeyboard(self):
        self.set_input("keyboard", "Keyboard & Mouse")

    # ---------------------------------------------------------------- sounds
    @pyqtProperty(bool, notify=soundsChanged)
    def soundsOn(self):
        return bool(self._settings.get("sounds", True))

    @pyqtSlot()
    def toggleSounds(self):
        self._settings["sounds"] = not self.soundsOn
        self._save_json(SETTINGS_FILE, self._settings)
        if self._sounds:
            self._sounds.enabled = self.soundsOn
        self.soundsChanged.emit()

    @pyqtSlot(str)
    def playSound(self, name):
        if self._sounds:
            self._sounds.play(name)

    # ---------------------------------------------------------------- launch
    @pyqtSlot(str)
    def launch(self, key):
        now = time.monotonic()
        if now - self._last_launch < LAUNCH_COOLDOWN:
            return                                  # ignore double presses
        argv = self._launch.get(key)
        game = next((g for g in self._games if g["key"] == key), None)
        if not argv or not game:
            return
        self._last_launch = now
        try:
            subprocess.Popen(argv, start_new_session=True,
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except Exception as e:
            print("[xmode] launch failed:", argv, e)
            self.toast.emit(f"Couldn't start {game['title']}")
            return
        is_launcher = game.get("source") == "launcher"
        self.toast.emit(f"Opening {game['title']}…" if is_launcher else f"Launching {game['title']}…")
        self._wm.game_launched(fullscreen=not is_launcher and not game.get("tool"))
        self.launched.emit()
        self._history[key] = int(time.time())
        self._plays[key] = self._plays.get(key, 0) + 1
        self._save_history()
        self._save_json(PLAYS_FILE, self._plays)
        self._apply_history()

    # ------------------------------------------------- add your own game (+)
    @pyqtSlot(result=str)
    def homeDir(self):
        return str(Path.home())

    @pyqtSlot(str, result="QVariantList")
    def listDir(self, path):
        """Folder contents for X Mode's file browser: places first, then folders, then files."""
        home = Path.home()
        out = []
        places = [("Home", home), ("Downloads", home / "Downloads"),
                  ("Drives", Path("/run/media") / home.name), ("Whole system", Path("/"))]
        for name, p in places:
            if p.is_dir():
                out.append({"name": name, "path": str(p), "kind": "place", "isDir": True})
        try:
            items = sorted(Path(path).iterdir(), key=lambda p: p.name.lower())
        except OSError:
            items = []
        dirs, files = [], []
        for p in items:
            if p.name.startswith("."):
                continue
            try:
                if p.is_dir():
                    dirs.append({"name": p.name, "path": str(p), "kind": "folder", "isDir": True})
                elif p.is_file():
                    files.append({"name": p.name, "path": str(p), "kind": library.file_kind(p)[0], "isDir": False})
            except OSError:
                continue
        return out + dirs[:400] + files[:600]

    @pyqtSlot(str, result=str)
    def parentDir(self, path):
        return str(Path(path).parent)

    @pyqtSlot(str)
    def addCustom(self, path):
        item = library.add_custom(path)
        if item is None:
            self.toast.emit("That's already in your library")
            return
        self.toast.emit(f"Added {item['title']} to your library")
        self.refresh()

    def _remove_custom(self, key):
        now = time.monotonic()
        if getattr(self, "_remove_ask", None) == key and now - self._remove_at < 4:
            library.remove_custom(key)
            self._remove_ask = None
            self.toast.emit("Removed from your library")
            self.removed.emit()
            self.refresh()
            return
        self._remove_ask, self._remove_at = key, now
        self.toast.emit("Press again to remove it from your library")

    @pyqtSlot(str)
    def openInLauncher(self, key):
        if key.startswith("custom:"):
            self._remove_custom(key)
            return
        argv = self._open.get(key)
        if not argv:
            return
        try:
            subprocess.Popen(argv, start_new_session=True,
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except Exception as e:
            print("[xmode] open failed:", argv, e)

    # ------------------------------------------------------------------ menu
    @pyqtSlot(str)
    def menuAction(self, action):
        if action == "refresh":
            self.refresh()
            self.toast.emit("Refreshing library…")
        elif action == "desktop":                   # X Mode session -> Plasma
            if self._switch_session("desktop"):     # the login manager restarts into Plasma
                self.toast.emit("Switching to the desktop…")
        elif action == "session":                   # Plasma -> X Mode session
            if self._switch_session("xmode"):
                self.toast.emit("Switching to X Mode…")
        elif action == "close":
            QGuiApplication.quit()
        elif action in ("suspend", "reboot", "poweroff"):
            subprocess.Popen(["systemctl", action], start_new_session=True)

    def _switch_session(self, target):
        tool = shutil.which("cobaltx-session-select") or "/usr/local/bin/cobaltx-session-select"
        if not os.path.exists(tool):
            self.toast.emit("Session switching isn't installed")
            return False
        try:
            r = subprocess.run([tool, target], timeout=20,
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except Exception as e:
            print("[xmode] session switch failed:", e)
            r = None
        if r is None or r.returncode != 0:
            self.toast.emit("Couldn't switch sessions")
            return False
        return True

    def shutdown(self):
        self._wm.shutdown()

    # ------------------------------------------------------ open apps / task view
    def _on_windows(self, windows):
        # top-most first, X Mode itself is already filtered out by the tracker
        ids = {w.get("id") for w in windows}
        self._closing = {k: v for k, v in self._closing.items() if k in ids}
        self._apps = [{"id": w.get("id", ""), "title": w.get("title", ""), "active": bool(w.get("active")),
                       "stuck": w.get("id") in self._closing}
                      for w in reversed(windows)]
        self.appsChanged.emit()

    @pyqtProperty("QVariantList", notify=appsChanged)
    def apps(self):
        return self._apps

    @pyqtProperty(bool, constant=True)
    def taskViewAvailable(self):
        return self._wm.enabled

    @pyqtSlot(str)
    def activateApp(self, window_id):
        self._wm.activate(window_id)

    @pyqtSlot(str)
    def closeApp(self, window_id):
        """First press: ask the app to close nicely. If it is still open after
        that (frozen, or a hidden 'are you sure?' prompt), the button turns into
        Force close, and the next press ends the process."""
        if window_id in self._closing and time.monotonic() - self._closing[window_id] > 1.5:
            self._force_close(window_id)
            return
        self._closing[window_id] = time.monotonic()
        self._wm.close(window_id)
        QTimer.singleShot(4000, lambda: self._on_windows(self._wm.windows))   # show "Force close"

    def _force_close(self, window_id):
        pid = self._wm.pid_of(window_id)
        title = next((a["title"] for a in self._apps if a["id"] == window_id), "the app")
        if pid <= 1 or pid == os.getpid():
            self.toast.emit(f"Couldn't force close {title}")
            return
        try:
            if os.stat(f"/proc/{pid}").st_uid != os.getuid():
                raise PermissionError
            os.kill(pid, signal.SIGTERM)
        except (OSError, PermissionError) as e:
            print("[xmode] force close failed:", pid, e)
            self.toast.emit(f"Couldn't force close {title}")
            return
        self.toast.emit(f"Force closing {title}…")

        def finish():
            if self._wm.is_open(window_id):
                try:
                    os.kill(pid, signal.SIGKILL)
                except OSError:
                    pass
        QTimer.singleShot(3000, finish)

    # --------------------------------------------- start in X Mode at login
    @pyqtProperty(bool, notify=startAtLoginChanged)
    def startAtLogin(self):
        try:
            return "AUTOLOGIN=1" in Path("/etc/cobaltx/xmode.conf").read_text().split()
        except OSError:
            return False

    @pyqtSlot()
    def toggleStartAtLogin(self):
        want = "off" if self.startAtLogin else "on"
        tool = shutil.which("cobaltx-session-select") or "/usr/local/bin/cobaltx-session-select"
        try:
            r = subprocess.run([tool, "--start-in-xmode", want], timeout=20,
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            ok = r.returncode == 0
        except Exception as e:
            print("[xmode] start-at-login change failed:", e)
            ok = False
        if not ok:
            self.toast.emit("Couldn't change the startup setting")
        else:
            self.toast.emit("CobaltX will start in X Mode" if want == "on"
                            else "CobaltX will start in the desktop")
        self.startAtLoginChanged.emit()

    # --------------------------------------------------------------- battery
    @pyqtSlot()
    def updateBattery(self):
        level, charging = -1, False
        for bat in sorted(glob.glob("/sys/class/power_supply/BAT*")):
            try:
                level = int(Path(bat, "capacity").read_text().strip())
                charging = Path(bat, "status").read_text().strip() in ("Charging", "Full")
                break
            except Exception:
                continue
        if (level, charging) != (self._battery, self._charging):
            self._battery, self._charging = level, charging
            self.batteryChanged.emit()

    # ------------------------------------------------------------ controller
    def on_pad(self, name):
        # any controller press means the controller is in use again: show its buttons
        if self._input == "keyboard" and self._pad:
            self.set_input(*self._pad)
        focused = QGuiApplication.focusWindow() is not None
        # In the X Mode session X Mode owns the controller and drives the
        # on-screen keyboard. (On the desktop the keyboard reads the pad itself.)
        if self._in_session:
            if name == "keyboard":
                self._keyboard("Toggle")
                return
            if self._kb_visible:
                if name in ("taskview", "quick", "qam"):
                    self._keyboard("Hide")         # and carry on below
                else:
                    self._keyboard("Input", name)  # typing: X Mode stays out of it
                    return
        elif self._kb_visible or name == "keyboard":
            return
        # X Mode's controller layout: the Xbox / PS / Steam button opens the menu
        # (everything else - Quick Settings, open apps, ... - is in there).
        # The Menu button and the right back button do nothing here.
        if name == "menu":
            return
        if name == "quick":            # right back button: whatever the user picked
            choice = handheld_settings.right_back()
            if choice == "keyboard":
                self._keyboard("Toggle")
                return
            if choice == "cursor":
                self.toggleCursor()
                self.toast.emit("Controller cursor " + ("on" if self.cursorOn else "off"))
                return
            if choice not in ("quick", "apps"):
                return
            name = "quickpanel" if choice == "quick" else "apps"
        if name == "qam":
            name = "taskview"          # Xbox button on the Ally (or Guide + A): the menu
        elif name == "taskview" and Path("/etc/cobaltx/handheld").exists():
            name = "apps"              # on handhelds plain Guide is the Armoury Crate button: open apps
        if name in ("taskview", "apps", "quickpanel") and not focused:
            # inside a game: bring X Mode back with the menu / open apps
            self._wm.raise_xmode()
            self.action.emit(name)
            return
        # Everything else only while X Mode itself is focused - otherwise pressing
        # A inside a game would launch another game behind it.
        if focused:
            self.action.emit(name)

    # ---------------------------------------------------- on-screen keyboard
    KB_SERVICE, KB_PATH, KB_IFACE = "org.cobaltx.Keyboard", "/Keyboard", "org.cobaltx.Keyboard"

    def _keyboard(self, method, *args):
        try:
            from PyQt6.QtDBus import QDBusConnection, QDBusMessage
        except ImportError:
            return
        bus = QDBusConnection.sessionBus()
        try:
            running = bool(bus.interface().isServiceRegistered(self.KB_SERVICE).value())
        except Exception:
            running = True
        if not running:
            if method in ("Toggle", "Show"):      # not running (crashed?): start it shown
                tool = shutil.which("cobaltx-keyboard") or "/usr/local/bin/cobaltx-keyboard"
                try:
                    subprocess.Popen([tool, "--no-gamepad", "--show"], start_new_session=True,
                                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                except OSError as e:
                    print("[xmode] can't start the on-screen keyboard:", e)
                    self.toast.emit("On-screen keyboard isn't installed")
            return
        msg = QDBusMessage.createMethodCall(self.KB_SERVICE, self.KB_PATH, self.KB_IFACE, method)
        if args:
            msg.setArguments(list(args))
        bus.asyncCall(msg)

    def _on_kb_visible(self, visible):
        if visible != self._kb_visible:
            self._kb_visible = visible
            if visible and self._in_session:
                self._keyboard("SetFamily", self._input)
            self.keyboardVisibleChanged.emit()

    @pyqtProperty(bool, notify=keyboardVisibleChanged)
    def keyboardVisible(self):
        return self._kb_visible

    @pyqtSlot()
    def toggleKeyboard(self):
        self._keyboard("Toggle")

    # ------------------------------------------------------ controller cursor
    def attach_cursor(self, cursor):
        """The cursor only runs while another app is in front of X Mode (X Mode
        itself is driven by the controller), and never while the keyboard is open."""
        self._cursor = cursor
        cursor.changed.connect(self.cursorChanged)
        QGuiApplication.instance().focusWindowChanged.connect(lambda _w: self._update_cursor())
        self.keyboardVisibleChanged.connect(self._update_cursor)
        self._update_cursor()

    def _update_cursor(self):
        if self._cursor:
            self._cursor.set_suspended(QGuiApplication.focusWindow() is not None or self._kb_visible)

    @pyqtProperty(bool, constant=True)
    def cursorAvailable(self):
        return self._cursor is not None    # attach_cursor runs before the UI loads

    rightBackChanged = pyqtSignal()

    @pyqtProperty(bool, constant=True)
    def handheld(self):
        return Path("/etc/cobaltx/handheld").exists()

    @pyqtProperty(str, notify=rightBackChanged)
    def rightBack(self):
        return handheld_settings.right_back()

    @pyqtSlot(str)
    def setRightBack(self, choice):
        handheld_settings.put("right_back", choice)
        self.rightBackChanged.emit()

    @pyqtProperty(bool, notify=cursorChanged)
    def cursorOn(self):
        return bool(self._cursor and self._cursor.enabled)

    @pyqtSlot()
    def toggleCursor(self):
        if self._cursor:
            self._cursor.set_enabled(not self._cursor.enabled)
            if self._cursor.enabled is False and self._cursor.error:
                self.toast.emit("Controller cursor unavailable")
            self._update_cursor()


def _open_log():
    try:
        DATA_DIR.mkdir(parents=True, exist_ok=True)
        # keep the log small: start fresh when it grows past 1 MB
        mode = "w" if LOG_FILE.exists() and LOG_FILE.stat().st_size > 1_000_000 else "a"
        return open(LOG_FILE, mode, buffering=1)
    except Exception:
        return None


def _fd_table():
    rows = []
    for fd in sorted(os.listdir("/proc/self/fd"), key=int):
        try:
            rows.append(f"    fd {fd}: {os.readlink('/proc/self/fd/' + fd)}")
        except OSError:
            pass
    return "\n".join(rows)


def _install_qt_log(log):
    """Send Qt's warnings to our log file instead of the terminal.

    A Qt warning written to a blocked terminal froze the whole UI once, so
    X Mode never writes Qt messages to stderr. Repeats are counted, not spammed."""
    seen = {}

    def handler(_mode, _ctx, msg):
        n = seen.get(msg, 0) + 1
        seen[msg] = n
        if n > 3 and n not in (10, 100, 1000, 10000):
            return
        line = f"{time.strftime('%H:%M:%S')} [qt] {msg}" + (f"  (x{n})" if n > 1 else "")
        m = re.search(r"Invalid socket (\d+)", msg)
        if m and n == 1:                 # record what that file descriptor was
            try:
                line += f"\n    -> fd {m.group(1)} is now: {os.readlink('/proc/self/fd/' + m.group(1))}"
            except OSError:
                line += f"\n    -> fd {m.group(1)} was already closed"
            line += "\n  open files at that moment:\n" + _fd_table()
        try:
            log.write(line + "\n")
        except Exception:
            pass

    qInstallMessageHandler(handler)


def _start_freeze_recorder(app, log):
    """If the interface stops responding for FREEZE_SECONDS, write what every
    thread was doing to ~/.local/share/cobaltx-xmode/xmode.log."""
    if log is None:
        return
    log.write(f"\n=== X Mode {VERSION} started {time.ctime()} ===\n")
    faulthandler.enable(log)

    def heartbeat():
        faulthandler.cancel_dump_traceback_later()
        faulthandler.dump_traceback_later(FREEZE_SECONDS, repeat=False, file=log)

    timer = QTimer(app)
    timer.timeout.connect(heartbeat)
    timer.start(1000)
    heartbeat()
    app._freeze_log = (log, timer)        # keep alive


def main(share_dir):
    os.environ.setdefault("QT_QUICK_CONTROLS_STYLE", "Basic")
    signal.signal(signal.SIGINT, signal.SIG_DFL)     # Ctrl+C in a terminal really quits
    args = sys.argv[1:]
    in_session = os.environ.get("XMODE_SESSION") == "1"
    # Fullscreen by default (it's a console-style UI). --windowed for development.
    fullscreen = "--windowed" not in args

    log = _open_log()
    if log is not None:
        _install_qt_log(log)
        sys.stdout = sys.stderr = log    # our own prints go to the log too
    app = QGuiApplication(sys.argv)
    app.setApplicationName("X Mode")
    app.setOrganizationName("CobaltX")
    app.setDesktopFileName("cobaltx-xmode")
    app.setWindowIcon(QIcon(str(Path(share_dir) / "xmode-icon.svg")))

    _start_freeze_recorder(app, log)
    sounds = SoundPlayer(Path(share_dir) / "sounds")
    backend = Backend(fullscreen, in_session, sounds)
    qs = QuickSettings(app)
    qs.toast.connect(backend.toast)
    backend.playSound("startup")
    pad = Gamepad(app)
    pad.action.connect(backend.on_pad)
    pad.device.connect(backend.set_input)
    try:                                  # controller cursor lives with the on-screen keyboard
        if not in_session:                # inside the desktop, the desktop's own cursor is used
            raise RuntimeError("not in the X Mode session")
        sys.path.insert(0, str(Path(share_dir).parent / "cobaltx-keyboard"))
        from cursor import PadCursor
        cursor = PadCursor(app, key="cursor_xmode")
        pad.raw_button.connect(cursor.on_button)
        pad.raw_axis.connect(cursor.on_axis)
        backend.attach_cursor(cursor)
    except Exception as e:
        print("[xmode] controller cursor unavailable:", e)

    engine = QQmlApplicationEngine()
    engine.addImageProvider("icon", IconProvider())
    engine.rootContext().setContextProperty("backend", backend)
    engine.rootContext().setContextProperty("qs", qs)
    engine.load(QUrl.fromLocalFile(str(Path(share_dir) / "Main.qml")))
    if not engine.rootObjects():
        print("[xmode] failed to load the interface")
        return 1

    backend.refresh()
    rc = app.exec()
    backend.shutdown()
    return rc
