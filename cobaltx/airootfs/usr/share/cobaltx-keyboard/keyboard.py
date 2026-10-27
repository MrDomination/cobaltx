#!/usr/bin/env python3
"""CobaltX On-Screen Keyboard.

A small always-running helper that shows a controller- and touch-friendly
keyboard at the bottom of the screen and types into whatever app is in front.

How it works
- The window is an X11 "override-redirect" window (through XWayland). Those
  never take keyboard focus and are drawn above everything, even fullscreen
  games, so the game/app keeps focus while you type.
- Keys are typed through a virtual keyboard device (/dev/uinput), so it works
  for every app: Wayland, XWayland, Proton games, browsers, Steam.
- In the X Mode session X Mode owns the controller and forwards buttons here
  over D-Bus (started with --no-gamepad). In the Plasma desktop the keyboard
  reads the controller itself.

  cobaltx-keyboard               start the helper (hidden)
  cobaltx-keyboard --toggle      show/hide (starts the helper if needed)
"""
import os
import signal
import sys
import time
from pathlib import Path

XMODE_DIR = Path(os.environ.get("COBALTX_XMODE_DIR", "/usr/share/cobaltx-xmode"))
sys.path.insert(0, str(XMODE_DIR))

from PyQt6.QtCore import (QObject, QUrl, pyqtClassInfo, pyqtProperty, pyqtSignal,
                          pyqtSlot)
from PyQt6.QtGui import QGuiApplication
from PyQt6.QtQml import QQmlApplicationEngine

SERVICE = "org.cobaltx.Keyboard"
PATH = "/Keyboard"
IFACE = "org.cobaltx.Keyboard"
XMODE_SERVICE, XMODE_PATH, XMODE_IFACE = "org.cobaltx.XMode", "/XMode", "org.cobaltx.XMode"

# ------------------------------------------------------------ typing (uinput)
try:
    from evdev import UInput, ecodes as E
except ImportError:            # python-evdev missing: the keyboard shows, but can't type
    UInput = E = None

if E:
    _SHIFTED = '~!@#$%^&*()_+{}|:"<>?'
    _PLAIN = '`1234567890-=[]\\;\',./'
    _SYMBOL_KEYS = dict(zip(_PLAIN, [E.KEY_GRAVE, E.KEY_1, E.KEY_2, E.KEY_3, E.KEY_4, E.KEY_5,
                                    E.KEY_6, E.KEY_7, E.KEY_8, E.KEY_9, E.KEY_0, E.KEY_MINUS,
                                    E.KEY_EQUAL, E.KEY_LEFTBRACE, E.KEY_RIGHTBRACE,
                                    E.KEY_BACKSLASH, E.KEY_SEMICOLON, E.KEY_APOSTROPHE,
                                    E.KEY_COMMA, E.KEY_DOT, E.KEY_SLASH]))
    # '~!@#...' are Shift + the same physical keys as '`12...'
    _SHIFT_OF = dict(zip(_SHIFTED, _PLAIN))
    SPECIAL = {"backspace": E.KEY_BACKSPACE, "enter": E.KEY_ENTER, "tab": E.KEY_TAB,
               "left": E.KEY_LEFT, "right": E.KEY_RIGHT, "up": E.KEY_UP, "down": E.KEY_DOWN,
               "esc": E.KEY_ESC, "space": E.KEY_SPACE}


def char_to_key(ch):
    """-> (keycode, needs_shift) on a US layout, or None."""
    if not E:
        return None
    if "a" <= ch <= "z":
        return getattr(E, "KEY_" + ch.upper()), False
    if "A" <= ch <= "Z":
        return getattr(E, "KEY_" + ch), True
    if ch == " ":
        return E.KEY_SPACE, False
    if ch in _SYMBOL_KEYS:
        return _SYMBOL_KEYS[ch], False
    if ch in _SHIFT_OF:
        return _SYMBOL_KEYS[_SHIFT_OF[ch]], True
    return None


class Typer:
    def __init__(self):
        self.ui = None
        self.error = ""
        if not UInput:
            self.error = "python-evdev is not installed"
            return
        keys = list(SPECIAL.values()) + [E.KEY_LEFTSHIFT]
        keys += [getattr(E, "KEY_" + c) for c in "ABCDEFGHIJKLMNOPQRSTUVWXYZ"]
        keys += list(_SYMBOL_KEYS.values())
        try:
            self.ui = UInput({E.EV_KEY: sorted(set(keys))}, name="CobaltX On-Screen Keyboard")
        except Exception as e:           # /dev/uinput not accessible
            self.error = f"can't open /dev/uinput ({e})"
        if self.error:
            print("[keyboard]", self.error)

    def _tap(self, code, shift=False):
        if not self.ui:
            return
        if shift:
            self.ui.write(E.EV_KEY, E.KEY_LEFTSHIFT, 1)
        self.ui.write(E.EV_KEY, code, 1)
        self.ui.syn()
        time.sleep(0.004)
        self.ui.write(E.EV_KEY, code, 0)
        if shift:
            self.ui.write(E.EV_KEY, E.KEY_LEFTSHIFT, 0)
        self.ui.syn()

    def text(self, s):
        for ch in s:
            k = char_to_key(ch)
            if k:
                self._tap(*k)

    def special(self, name):
        if E and name in SPECIAL:
            self._tap(SPECIAL[name])


# ------------------------------------------------------------ D-Bus + QML side
@pyqtClassInfo("D-Bus Interface", IFACE)
class _Bus(QObject):
    def __init__(self, kb):
        super().__init__(kb)
        self.kb = kb

    @pyqtSlot()
    def Toggle(self):
        self.kb.setVisible(not self.kb.visible)

    @pyqtSlot()
    def Show(self):
        self.kb.setVisible(True)

    @pyqtSlot()
    def Hide(self):
        self.kb.setVisible(False)

    @pyqtSlot(str)
    def Input(self, action):
        self.kb.input.emit(action)

    @pyqtSlot(str)
    def SetFamily(self, family):
        self.kb.setFamily(family)


class Keyboard(QObject):
    visibleChanged = pyqtSignal()
    familyChanged = pyqtSignal()
    quickVisibleChanged = pyqtSignal()
    input = pyqtSignal(str)              # controller action -> keyboard QML
    quickInput = pyqtSignal(str)         # controller action -> desktop Quick Settings
    appsVisibleChanged = pyqtSignal()
    appsInput = pyqtSignal(str)          # controller action -> desktop open-apps view

    def __init__(self, sounds=None):
        super().__init__()
        self._visible = False
        self._family = "keyboard"
        self._sounds = sounds
        self._quick = False
        self._apps = False
        self.typer = Typer()

    @pyqtProperty(bool, notify=visibleChanged)
    def visible(self):
        return self._visible

    @pyqtSlot(bool)
    def setVisible(self, v):
        v = bool(v)
        if v == self._visible:
            return
        self._visible = v
        self.visibleChanged.emit()
        self.playSound("menu_open" if v else "menu_close")
        _call_xmode("setKeyboardVisible", v)

    @pyqtProperty(bool, notify=quickVisibleChanged)
    def quickVisible(self):
        return self._quick

    @pyqtSlot(bool)
    def setQuickVisible(self, v):
        v = bool(v)
        if v != self._quick:
            self._quick = v
            self.quickVisibleChanged.emit()

    @pyqtProperty(bool, notify=appsVisibleChanged)
    def appsVisible(self):
        return self._apps

    @pyqtSlot(bool)
    def setAppsVisible(self, v):
        v = bool(v)
        if v != self._apps:
            self._apps = v
            self.appsVisibleChanged.emit()

    @pyqtProperty(str, notify=familyChanged)
    def family(self):
        return self._family

    def setFamily(self, family):
        if family and family != self._family:
            self._family = family
            self.familyChanged.emit()

    @pyqtProperty(str, constant=True)
    def problem(self):
        return self.typer.error

    @pyqtProperty(str, constant=True)
    def brand(self):
        return QUrl.fromLocalFile(str(XMODE_DIR / "logo.svg")).toString()

    @pyqtSlot(str)
    def typeText(self, s):
        self.typer.text(s)

    @pyqtSlot(str)
    def typeSpecial(self, name):
        self.typer.special(name)

    @pyqtSlot(str)
    def playSound(self, name):
        if self._sounds:
            self._sounds.play(name)

    def on_pad(self, action):
        """Desktop only (in X Mode, X Mode handles the controller)."""
        if action == "keyboard":
            self.setQuickVisible(False)
            self.setVisible(not self._visible)
        elif action == "quick":                   # right back button: whatever the user picked
            import handheld_settings
            choice = handheld_settings.right_back()
            if choice == "quick":
                self.on_pad("qam")
            elif choice == "apps":
                self.on_pad("taskview")
            elif choice == "keyboard":
                self.on_pad("keyboard")
            elif choice == "cursor" and getattr(self, "cursor", None):
                self.cursor.set_enabled(not self.cursor.enabled)
                self.playSound("select")
        elif action == "qam":                     # Xbox button (Ally) / Guide + A
            self.setVisible(False)
            self.setAppsVisible(False)
            self.setQuickVisible(not self._quick)
        elif action == "taskview":                # Armoury Crate (Ally) / Guide: open apps
            self.setVisible(False)
            self.setQuickVisible(False)
            self.setAppsVisible(not self._apps)
        elif self._visible:
            self.input.emit(action)
        elif self._quick:
            self.quickInput.emit(action)
        elif self._apps:
            self.appsInput.emit(action)

    def on_device(self, family, _name):
        self.setFamily(family)


class DesktopBackend(QObject):
    """The bits of X Mode's backend that Quick Settings uses, for the desktop."""
    inputChanged = pyqtSignal()
    cursorChanged = pyqtSignal()

    appsChanged = pyqtSignal()
    batteryChanged = pyqtSignal()
    toast = pyqtSignal(str)

    def __init__(self, kb, cursor, wm=None):
        super().__init__(kb)
        self.kb, self.cursor, self.wm = kb, cursor, wm
        self._apps, self._closing = [], {}
        self._battery, self._charging = -1, False
        kb.familyChanged.connect(self.inputChanged)
        if cursor:
            cursor.changed.connect(self.cursorChanged)
        if wm:
            wm.windowsChanged.connect(self._on_windows)
        from PyQt6.QtCore import QTimer
        self._bt = QTimer(self)
        self._bt.timeout.connect(self._read_battery)
        self._bt.start(30000)
        self._read_battery()

    # ---- battery (for the status in Quick Settings)
    def _read_battery(self):
        import glob
        level, charging = -1, False
        for bat in sorted(glob.glob("/sys/class/power_supply/BAT*")):
            try:
                level = int(Path(bat, "capacity").read_text().strip())
                charging = Path(bat, "status").read_text().strip() in ("Charging", "Full")
                break
            except (OSError, ValueError):
                continue
        if (level, charging) != (self._battery, self._charging):
            self._battery, self._charging = level, charging
            self.batteryChanged.emit()

    @pyqtProperty(int, notify=batteryChanged)
    def battery(self):
        return self._battery

    @pyqtProperty(bool, notify=batteryChanged)
    def charging(self):
        return self._charging

    @pyqtProperty(bool, constant=True)
    def cursorAvailable(self):
        return self.cursor is not None

    rightBackChanged = pyqtSignal()

    @pyqtProperty(bool, constant=True)
    def handheld(self):
        return Path("/etc/cobaltx/handheld").exists()

    @pyqtProperty(str, notify=rightBackChanged)
    def rightBack(self):
        import handheld_settings
        return handheld_settings.right_back()

    @pyqtSlot(str)
    def setRightBack(self, choice):
        import handheld_settings
        handheld_settings.put("right_back", choice)
        self.rightBackChanged.emit()

    # ---- open apps (Armoury Crate button on the desktop)
    def _on_windows(self, windows):
        ids = {w.get("id") for w in windows}
        self._closing = {k: v for k, v in self._closing.items() if k in ids}
        self._apps = [{"id": w.get("id", ""), "title": w.get("title", ""), "active": bool(w.get("active")),
                       "stuck": w.get("id") in self._closing} for w in reversed(windows)]
        self.appsChanged.emit()

    @pyqtProperty("QVariantList", notify=appsChanged)
    def apps(self):
        return self._apps

    @pyqtSlot(str)
    def activateApp(self, window_id):
        if self.wm:
            self.wm.activate(window_id)

    @pyqtSlot(str)
    def closeApp(self, window_id):
        import os, signal, time
        from PyQt6.QtCore import QTimer
        if not self.wm:
            return
        if window_id in self._closing and time.monotonic() - self._closing[window_id] > 1.5:
            pid = self.wm.pid_of(window_id)       # second press on a stuck app: force close
            try:
                if pid > 1 and os.stat(f"/proc/{pid}").st_uid == os.getuid():
                    os.kill(pid, signal.SIGTERM)
                    QTimer.singleShot(3000, lambda: self.wm.is_open(window_id) and os.kill(pid, signal.SIGKILL))
            except OSError:
                pass
            return
        self._closing[window_id] = time.monotonic()
        self.wm.close(window_id)
        QTimer.singleShot(4000, lambda: self._on_windows(self.wm.windows))

    @pyqtProperty(bool, constant=True)
    def desktopMode(self):
        return True

    @pyqtProperty(str, notify=inputChanged)
    def inputMode(self):
        return self.kb.family

    @pyqtProperty(bool, notify=cursorChanged)
    def cursorOn(self):
        return bool(self.cursor and self.cursor.enabled)

    @pyqtSlot()
    def toggleKeyboard(self):
        self.kb.setQuickVisible(False)
        self.kb.setVisible(not self.kb.visible)

    @pyqtSlot()
    def switchToXMode(self):
        import shutil, subprocess
        tool = shutil.which("cobaltx-session-select") or "/usr/local/bin/cobaltx-session-select"
        subprocess.Popen([tool, "xmode"], start_new_session=True)

    @pyqtSlot(str)
    def power(self, action):
        cmd = {"sleep": "suspend", "restart": "reboot", "poweroff": "poweroff"}.get(action)
        if cmd:
            import subprocess
            subprocess.Popen(["systemctl", cmd], start_new_session=True)

    @pyqtSlot()
    def toggleCursor(self):
        if self.cursor:
            self.cursor.set_enabled(not self.cursor.enabled)


def _call_xmode(method, *args):
    """Tell X Mode (if it's running) that the keyboard opened/closed."""
    try:
        from PyQt6.QtDBus import QDBusConnection, QDBusMessage
        msg = QDBusMessage.createMethodCall(XMODE_SERVICE, XMODE_PATH, XMODE_IFACE, method)
        msg.setArguments(list(args))
        QDBusConnection.sessionBus().asyncCall(msg)
    except Exception:
        pass


def _send(method):
    """--toggle etc.: talk to the running helper. Returns True if one answered."""
    from PyQt6.QtDBus import QDBusConnection, QDBusMessage
    bus = QDBusConnection.sessionBus()
    msg = QDBusMessage.createMethodCall(SERVICE, PATH, IFACE, method)
    reply = bus.call(msg)
    return reply.type() != QDBusMessage.MessageType.ErrorMessage


def main():
    args = sys.argv[1:]
    os.environ.setdefault("QT_QPA_PLATFORM", "xcb")     # override-redirect needs X11
    signal.signal(signal.SIGINT, signal.SIG_DFL)
    app = QGuiApplication(sys.argv)
    app.setApplicationName("cobaltx-keyboard")
    app.setDesktopFileName("cobaltx-keyboard")

    from PyQt6.QtDBus import QDBusConnection
    bus = QDBusConnection.sessionBus()
    toggle = "--toggle" in args or "--show" in args
    if not bus.registerService(SERVICE):
        # already running: just pass the request on
        if toggle:
            _send("Toggle" if "--toggle" in args else "Show")
        return 0

    sounds = None
    try:
        from sound import SoundPlayer
        sounds = SoundPlayer(XMODE_DIR / "sounds", volume=0.6)
    except Exception as e:
        print("[keyboard] no sounds:", e)

    kb = Keyboard(sounds)
    bus.registerObject(PATH, _Bus(kb), QDBusConnection.RegisterOption.ExportAllSlots)

    # On the desktop this helper owns the controller: keyboard, Quick Settings
    # and the controller cursor. In X Mode (--no-gamepad) X Mode does all that.
    desktop = "--no-gamepad" not in args
    cursor = None
    if desktop:
        try:
            from gamepad import Gamepad
            from cursor import PadCursor
            pad = Gamepad(app)
            cursor = PadCursor(app)
            pad.action.connect(kb.on_pad)
            pad.device.connect(kb.on_device)
            kb.cursor = cursor
            pad.raw_button.connect(cursor.on_button)
            pad.raw_axis.connect(cursor.on_axis)
            pause = lambda: cursor.set_suspended(kb.visible or kb.quickVisible or kb.appsVisible)
            kb.visibleChanged.connect(pause)
            kb.quickVisibleChanged.connect(pause)
            kb.appsVisibleChanged.connect(pause)
        except Exception as e:
            print("[keyboard] no controller support:", e)
            cursor = None

    engine = QQmlApplicationEngine()
    engine.rootContext().setContextProperty("kb", kb)
    engine.load(QUrl.fromLocalFile(str(Path(__file__).with_name("Keyboard.qml"))))
    if not engine.rootObjects():
        return 1
    if desktop:
        try:
            from quicksettings import QuickSettings
            qs = QuickSettings(app)
            qs.toast.connect(lambda m: print("[quick]", m))
            engine.rootContext().setContextProperty("qs", qs)
            wm = None
            try:
                from windows import WindowManager
                wm = WindowManager(app, service="org.cobaltx.Desktop", prefix="cobaltx-desktop", shortcut=False)
            except Exception as e:
                print("[keyboard] open-apps view unavailable:", e)
            engine.rootContext().setContextProperty("backend", DesktopBackend(kb, cursor, wm))
            engine.load(QUrl.fromLocalFile(str(Path(__file__).with_name("DesktopQuick.qml"))))
            engine.load(QUrl.fromLocalFile(str(Path(__file__).with_name("DesktopApps.qml"))))
            if wm:
                app.aboutToQuit.connect(wm.shutdown)
        except Exception as e:
            print("[keyboard] desktop Quick Settings unavailable:", e)
    if toggle:
        kb.setVisible(True)
    return app.exec()


if __name__ == "__main__":
    sys.exit(main())
