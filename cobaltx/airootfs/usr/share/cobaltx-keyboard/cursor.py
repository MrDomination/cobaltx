"""Controller cursor: use the controller as a mouse on the desktop.

  Left stick    move the cursor (gentle near the centre, fast at the edge)
  Right stick   scroll
  A             left click (hold to drag)
  Menu (☰)      right click
  B             Escape
  D-pad         arrow keys

Typed through its own virtual mouse (/dev/uinput). Paused while the
on-screen keyboard or Quick Settings is open, so the stick drives those.
"""
import json
import time
from pathlib import Path

from PyQt6.QtCore import QObject, QTimer, pyqtSignal

try:
    from evdev import UInput, ecodes as E
except ImportError:
    UInput = E = None

SETTINGS = Path.home() / ".config/cobaltx/handheld.json"

# SDL button / axis numbers
A, B, BACK, START = 0, 1, 4, 6
UP, DOWN, LEFT, RIGHT = 11, 12, 13, 14
LX, LY, RX, RY = 0, 1, 2, 3

DEADZONE = 5000
MAX_SPEED = 1600.0          # pixels per second at full tilt
SCROLL_SPEED = 1440.0       # hi-res wheel units per second (120 = one notch -> 12 notches/s)
TICK_MS = 8


def _load():
    try:
        return json.loads(SETTINGS.read_text())
    except (OSError, ValueError):
        return {}


def _save(data):
    try:
        SETTINGS.parent.mkdir(parents=True, exist_ok=True)
        SETTINGS.write_text(json.dumps(data))
    except OSError:
        pass


def _curve(v):
    """stick value -> -1..1 with a deadzone and a squared curve for precision"""
    a = abs(v)
    if a < DEADZONE:
        return 0.0
    n = min(1.0, (a - DEADZONE) / (32767 - DEADZONE))
    return (n * n) * (1 if v > 0 else -1)


class PadCursor(QObject):
    changed = pyqtSignal()

    def __init__(self, parent=None, key="cursor"):
        super().__init__(parent)
        self.key = key                           # setting name (desktop and X Mode remember it separately)
        self.ui = None
        self.error = ""
        self.suspended = False
        self.axes = [0] * 6
        self.acc = [0.0, 0.0, 0.0, 0.0]          # x, y, scroll v, scroll h (sub-unit remainders)
        self.lo = [0.0, 0.0]                     # hi-res scroll waiting to become a whole notch
        self.last = time.monotonic()
        self.timer = QTimer(self)
        self.timer.timeout.connect(self._tick)
        self.enabled = bool(_load().get(self.key, False))
        if self.enabled:
            self._open()

    # ------------------------------------------------------------- device
    def _open(self):
        if self.ui or not UInput:
            self.error = "" if self.ui else "python-evdev is not installed"
            return bool(self.ui)
        rel = [E.REL_X, E.REL_Y, E.REL_WHEEL, E.REL_HWHEEL]
        for name in ("REL_WHEEL_HI_RES", "REL_HWHEEL_HI_RES"):
            if hasattr(E, name):
                rel.append(getattr(E, name))
        keys = [E.BTN_LEFT, E.BTN_RIGHT, E.BTN_MIDDLE, E.KEY_ESC,
                E.KEY_UP, E.KEY_DOWN, E.KEY_LEFT, E.KEY_RIGHT]
        try:
            self.ui = UInput({E.EV_REL: rel, E.EV_KEY: keys}, name="CobaltX Controller Cursor")
            self.error = ""
        except Exception as e:
            self.error = f"can't open /dev/uinput ({e})"
            print("[cursor]", self.error)
        return bool(self.ui)

    @property
    def active(self):
        return self.enabled and not self.suspended and self.ui is not None

    def set_enabled(self, on):
        on = bool(on)
        if on and not self._open():
            on = False
        if on == self.enabled:
            self.changed.emit()
            return
        self.enabled = on
        data = _load()
        data[self.key] = on
        _save(data)
        if not on:
            self._release_all()
        else:
            self._wake()
        self.changed.emit()

    def set_suspended(self, s):
        self.suspended = bool(s)
        if self.suspended:
            self._release_all()
        else:
            self._wake()

    def _wake(self):
        """start ticking if a stick is already pushed"""
        if self.active and not self.timer.isActive() and any(abs(self.axes[a]) >= DEADZONE for a in (LX, LY, RX, RY)):
            self.last = time.monotonic()
            self.timer.start(TICK_MS)

    def _release_all(self):
        if not self.ui:
            return
        for code in (E.BTN_LEFT, E.BTN_RIGHT, E.KEY_UP, E.KEY_DOWN, E.KEY_LEFT, E.KEY_RIGHT):
            self.ui.write(E.EV_KEY, code, 0)
        self.ui.syn()

    # -------------------------------------------------------------- input
    def on_axis(self, axis, value):
        if axis < len(self.axes):
            self.axes[axis] = value
        self._wake()

    def on_button(self, button, pressed):
        if not self.active:
            return
        code = {A: E.BTN_LEFT, START: E.BTN_RIGHT, UP: E.KEY_UP, DOWN: E.KEY_DOWN,
                LEFT: E.KEY_LEFT, RIGHT: E.KEY_RIGHT}.get(button)
        if button == B:
            code = E.KEY_ESC
        if code is None:
            return
        self.ui.write(E.EV_KEY, code, 1 if pressed else 0)
        self.ui.syn()

    def _tick(self):
        now = time.monotonic()
        dt, self.last = min(0.05, now - self.last), now
        mx, my = _curve(self.axes[LX]), _curve(self.axes[LY])
        sx, sy = _curve(self.axes[RX]), _curve(self.axes[RY])
        if not self.active or (mx == my == sx == sy == 0):
            self.timer.stop()
            return
        ui = self.ui
        self.acc[0] += mx * MAX_SPEED * dt
        self.acc[1] += my * MAX_SPEED * dt
        dx, dy = int(self.acc[0]), int(self.acc[1])
        self.acc[0] -= dx
        self.acc[1] -= dy
        if dx:
            ui.write(E.EV_REL, E.REL_X, dx)
        if dy:
            ui.write(E.EV_REL, E.REL_Y, dy)
        # scrolling: stick up = scroll up
        for i, (val, hi, lo) in enumerate(((-sy, "REL_WHEEL_HI_RES", E.REL_WHEEL),
                                           (sx, "REL_HWHEEL_HI_RES", E.REL_HWHEEL))):
            if not val:
                continue
            self.acc[2 + i] += val * SCROLL_SPEED * dt
            step = int(self.acc[2 + i])
            self.acc[2 + i] -= step
            if not step:
                continue
            if hasattr(E, hi):
                ui.write(E.EV_REL, getattr(E, hi), step)
            self.lo[i] += step
            notches = int(self.lo[i] / 120)
            if notches:
                self.lo[i] -= notches * 120
                ui.write(E.EV_REL, lo, notches)
        ui.syn()
