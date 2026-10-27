"""Quick Settings for X Mode: performance mode / TDP, brightness, volume.

Everything that touches the system runs in one background thread, so a slow
pkexec or pactl never freezes the UI. QML sees the `state` property (a dict)
and calls the slots.
"""
import glob
import json
import queue
import re
import shutil
import subprocess
import threading
from pathlib import Path

from PyQt6.QtCore import QObject, pyqtProperty, pyqtSignal, pyqtSlot

TDP_HELPER = "/usr/local/lib/cobaltx/tdp-helper"


def _run(argv, timeout=10):
    try:
        r = subprocess.run(argv, capture_output=True, text=True, timeout=timeout)
        return r.returncode, r.stdout
    except Exception as e:
        print("[xmode] quick settings:", argv[0], e)
        return 1, ""


# ------------------------------------------------------------------ brightness
def _backlight():
    devs = sorted(glob.glob("/sys/class/backlight/*"))
    # prefer the built-in panel (amdgpu_bl*, intel_backlight) over others
    devs.sort(key=lambda d: 0 if re.search(r"amdgpu|intel|acpi_video0", d) else 1)
    return Path(devs[0]) if devs else None


def read_brightness():
    d = _backlight()
    if not d:
        return None
    try:
        cur = int((d / "brightness").read_text())
        mx = int((d / "max_brightness").read_text())
        return round(cur * 100 / mx) if mx else None
    except (OSError, ValueError):
        return None


def set_brightness(pct):
    d = _backlight()
    if not d:
        return
    mx = int((d / "max_brightness").read_text())
    value = max(1, round(mx * max(5, min(100, pct)) / 100))     # never fully black
    # logind lets the logged-in user change the backlight without root
    _run(["busctl", "call", "org.freedesktop.login1", "/org/freedesktop/login1/session/auto",
          "org.freedesktop.login1.Session", "SetBrightness", "ssu", "backlight", d.name, str(value)])


# ---------------------------------------------------------------------- volume
def read_volume():
    if not shutil.which("pactl"):
        return None, False
    _, out = _run(["pactl", "get-sink-volume", "@DEFAULT_SINK@"], 3)
    m = re.search(r"(\d+)%", out)
    _, mute = _run(["pactl", "get-sink-mute", "@DEFAULT_SINK@"], 3)
    return (int(m.group(1)) if m else None), "yes" in mute


class QuickSettings(QObject):
    stateChanged = pyqtSignal()
    toast = pyqtSignal(str)
    _done = pyqtSignal(dict)

    def __init__(self, parent=None):
        super().__init__(parent)
        self._state = {"tdp": None, "profiles": [], "profile": "", "mode": "profile", "custom": None,
                       "brightness": None, "volume": None, "muted": False, "busy": False}
        self._jobs = queue.Queue()
        self._done.connect(self._merge)
        threading.Thread(target=self._worker, name="xmode-quick", daemon=True).start()

    # ------------------------------------------------------------------ plumbing
    def _worker(self):
        while True:
            jobs = [self._jobs.get()]
            while not self._jobs.empty():
                jobs.append(self._jobs.get_nowait())
            latest = {}                     # a burst of slider moves -> only the last one runs
            for kind, job in jobs:
                latest.pop(kind, None)
                latest[kind] = job
            for job in latest.values():
                try:
                    res = job()
                    if res:
                        self._done.emit(res)
                except Exception as e:
                    print("[xmode] quick settings job failed:", e)

    def _job(self, kind, fn):
        self._jobs.put((kind, fn))

    def _merge(self, data):
        self._state = {**self._state, **data}
        self.stateChanged.emit()

    @pyqtProperty("QVariantMap", notify=stateChanged)
    def state(self):
        return self._state

    # ------------------------------------------------------------------- reading
    def _read_all(self):
        data = {}
        code, out = _run(["/usr/bin/python3", "-I", TDP_HELPER, "info"], 5)
        if code == 0 and out.strip():
            try:
                data.update(json.loads(out))
            except ValueError:
                pass
        data["brightness"] = read_brightness()
        data["volume"], data["muted"] = read_volume()
        return data

    @pyqtSlot()
    def refresh(self):
        self._job("refresh", self._read_all)

    # ------------------------------------------------------------------ changing
    def _helper(self, *args):
        code, out = _run(["pkexec", TDP_HELPER, *args], 20)
        if code != 0:
            self.toast.emit("Couldn't change the performance setting")
            return {}
        try:
            return json.loads(out)
        except ValueError:
            return {}

    @pyqtSlot(str)
    def setProfile(self, name):
        self._merge({"profile": name, "mode": "profile"})          # instant feedback
        self._job("profile", lambda: self._helper("set-profile", name))

    @pyqtSlot(int)
    def setTdp(self, watts):
        self._merge({"custom": watts, "mode": "custom"})
        self._job("tdp", lambda: self._helper("set-tdp", str(watts)))

    @pyqtSlot(int)
    def setBrightness(self, pct):
        self._merge({"brightness": pct})
        self._job("brightness", lambda: set_brightness(pct))   # returns None: nothing to merge

    @pyqtSlot(int)
    def setVolume(self, pct):
        pct = max(0, min(100, pct))
        self._merge({"volume": pct, "muted": False})

        def job():
            _run(["pactl", "set-sink-mute", "@DEFAULT_SINK@", "0"], 3)
            _run(["pactl", "set-sink-volume", "@DEFAULT_SINK@", f"{pct}%"], 3)
        self._job("volume", job)

    @pyqtSlot()
    def toggleMute(self):
        self._merge({"muted": not self._state.get("muted")})
        self._job("mute", lambda: _run(["pactl", "set-sink-mute", "@DEFAULT_SINK@", "toggle"], 3) and {})
