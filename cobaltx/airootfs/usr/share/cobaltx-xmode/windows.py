"""Window control for X Mode (KWin).

- A small KWin script reports every open app window to X Mode over D-Bus, so
  X Mode knows what is running (task view, plain background behind apps).
- One-shot KWin scripts bring a window to the front, close it, or bring X Mode
  itself back (the Guide/PS button).
- Games launched from X Mode are made fullscreen (tools and launchers are not).

All KWin calls go through gdbus in one background thread, so the UI never
waits on them. Under gamescope none of this applies (gamescope manages focus).
"""
import json
import os
import queue
import subprocess
import threading
from pathlib import Path

from PyQt6.QtCore import QObject, pyqtClassInfo, pyqtSignal, pyqtSlot

SERVICE = "org.cobaltx.XMode"
PATH = "/XMode"
IFACE = "org.cobaltx.XMode"

TRACKER = "cobaltx-xmode-tracker"
ACTION = "cobaltx-xmode-action"
FULLSCREEN = "cobaltx-xmode-fullscreen"
FULLSCREEN_SECONDS = 120

# Windows that are never "apps" in the task view
IGNORED = ["cobaltx-xmode", "cobaltx-keyboard", "plasmashell", "org.kde.plasmashell", "krunner",
           "org.kde.krunner", "xdg-desktop-portal-kde", "kwin_wayland",
           "org.kde.polkit-kde-authentication-agent-1", "polkit-kde-authentication-agent-1"]

# Never forced fullscreen (launcher clients, login windows, ...)
NO_FULLSCREEN = IGNORED + ["steam", "steamwebhelper", "heroic", "com.heroicgameslauncher.hgl",
                           "com.usebottles.bottles", "bottles", "net.lutris.lutris", "lutris"]

_JS_FIND = """
function findWindow(id) {
    var list = workspace.windowList();
    for (var i = 0; i < list.length; i++) {
        if (String(list[i].internalId) === id) return list[i];
    }
    return null;
}
"""

TRACKER_JS = """
// CobaltX X Mode: tell X Mode which app windows are open
const ignored = %(ignored)s;
function report(gone) {
    var out = [];
    var wins = workspace.stackingOrder;          // bottom -> top
    for (var i = 0; i < wins.length; i++) {
        var w = wins[i];
        // windowRemoved fires while the closed window is still listed: skip it
        if (!w || w === gone || w.deleted || !w.normalWindow || w.skipTaskbar) continue;
        var cls = String(w.resourceClass || "").toLowerCase();
        if (ignored.indexOf(cls) >= 0) continue;
        out.push({ id: String(w.internalId), title: String(w.caption || cls), cls: cls,
                   pid: Number(w.pid || 0), active: w === workspace.activeWindow });
    }
    callDBus("%(service)s", "%(path)s", "%(iface)s", "setWindows", JSON.stringify(out));
}
workspace.windowAdded.connect(function (w) {
    if (w && w.captionChanged) w.captionChanged.connect(function () { report(null); });
    report(null);
});
workspace.windowRemoved.connect(function (w) { report(w); });
workspace.windowActivated.connect(function () { report(null); });

%(extra)s
report(null);
"""

SHORTCUT_JS = """
// Alt+F12 from anywhere (even inside a game): back to X Mode with the task view
registerShortcut("CobaltX X Mode: Task View", "Open X Mode's task view", "Alt+F12", function () {
    var list = workspace.windowList();
    for (var i = 0; i < list.length; i++) {
        if (String(list[i].resourceClass).toLowerCase() === "cobaltx-xmode") {
            list[i].minimized = false;
            workspace.activeWindow = list[i];
            break;
        }
    }
    callDBus("%(service)s", "%(path)s", "%(iface)s", "showTaskView");
});
"""

FULLSCREEN_JS = """
// CobaltX X Mode: fullscreen the FIRST window of a game launched from X Mode
// (later windows - settings, dialogs, tools - stay normal)
const skip = %(skip)s;
var done = false;
workspace.windowAdded.connect(function (w) {
    if (done || !w || !w.normalWindow || w.skipTaskbar) return;
    if (w.fullScreenable === false) return;       // KWin's own windows, OSDs
    var cls = String(w.resourceClass || "").toLowerCase();
    if (!cls || skip.indexOf(cls) >= 0) return;
    w.fullScreen = true;
    done = true;
});
"""


def under_gamescope():
    return ("gamescope" in os.environ.get("XDG_CURRENT_DESKTOP", "").lower()
            or bool(os.environ.get("GAMESCOPE_WAYLAND_DISPLAY")))


def _js_str(s):
    return json.dumps(str(s))


@pyqtClassInfo("D-Bus Interface", IFACE)
class _BusObject(QObject):
    """Receives the window list from the KWin tracker script."""
    received = pyqtSignal(list)
    taskViewRequested = pyqtSignal()
    keyboardVisible = pyqtSignal(bool)

    @pyqtSlot(bool)
    def setKeyboardVisible(self, visible):
        """Called by the on-screen keyboard when it opens/closes."""
        self.keyboardVisible.emit(bool(visible))

    @pyqtSlot(str)
    def setWindows(self, payload):
        try:
            data = json.loads(payload)
            if isinstance(data, list):
                self.received.emit(data)
        except ValueError:
            pass

    @pyqtSlot()
    def showTaskView(self):
        self.taskViewRequested.emit()


class WindowManager(QObject):
    windowsChanged = pyqtSignal(list)
    taskViewRequested = pyqtSignal()       # Alt+F12
    keyboardVisible = pyqtSignal(bool)     # on-screen keyboard opened/closed

    def __init__(self, parent=None, service=SERVICE, prefix="cobaltx-xmode", shortcut=True):
        """service/prefix let the desktop helper run its own tracker next to X Mode."""
        super().__init__(parent)
        self.service = service
        self.names = {"tracker": f"{prefix}-tracker", "action": f"{prefix}-action",
                      "fullscreen": f"{prefix}-fullscreen"}
        self.shortcut = shortcut
        self.enabled = not under_gamescope()
        self.windows = []
        self._queue = queue.Queue()
        self._fs_generation = 0
        runtime = Path(os.environ.get("XDG_RUNTIME_DIR") or "/tmp")
        self._dir = runtime / "cobaltx-xmode"
        self._bus = None
        if not self.enabled:
            return
        try:
            self._dir.mkdir(parents=True, exist_ok=True)
        except OSError:
            self.enabled = False
            return
        threading.Thread(target=self._worker, name="xmode-kwin", daemon=True).start()
        self._register_bus()
        names = {"service": self.service, "path": PATH, "iface": IFACE}
        extra = SHORTCUT_JS % names if self.shortcut else ""
        self._load(self.names["tracker"], TRACKER_JS % dict(names, ignored=json.dumps(IGNORED), extra=extra))

    # -------------------------------------------------------------- D-Bus
    def _register_bus(self):
        try:
            from PyQt6.QtDBus import QDBusConnection
        except ImportError:
            print("[xmode] QtDBus not available - task view disabled")
            return
        bus = QDBusConnection.sessionBus()
        if not bus.isConnected():
            print("[xmode] no session D-Bus - task view disabled")
            return
        self._bus = _BusObject(self)
        self._bus.received.connect(self._on_windows)
        self._bus.taskViewRequested.connect(self.taskViewRequested)
        self._bus.keyboardVisible.connect(self.keyboardVisible)
        bus.registerService(self.service)
        bus.registerObject(PATH, self._bus, QDBusConnection.RegisterOption.ExportAllSlots)

    def _on_windows(self, windows):
        self.windows = windows
        self.windowsChanged.emit(windows)

    # --------------------------------------------------------- KWin calls
    def _worker(self):
        while True:
            fn = self._queue.get()
            try:
                fn()
            except Exception as e:
                print("[xmode] kwin call failed:", e)

    @staticmethod
    def _gdbus(method, *args):
        subprocess.run(["gdbus", "call", "--session", "--dest", "org.kde.KWin",
                        "--object-path", "/Scripting", "--method",
                        f"org.kde.kwin.Scripting.{method}", *args],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=5)

    def _load(self, name, code):
        def job():
            path = self._dir / f"{name}.js"
            path.write_text(code)
            self._gdbus("unloadScript", name)
            self._gdbus("loadScript", str(path), name)
            self._gdbus("start")
        self._queue.put(job)

    def _unload(self, name):
        self._queue.put(lambda: self._gdbus("unloadScript", name))

    def _action(self, body):
        if self.enabled:
            self._load(self.names["action"], _JS_FIND + body)

    # ------------------------------------------------------------ actions
    def activate(self, window_id):
        self._action(f"""
var w = findWindow({_js_str(window_id)});
if (w) {{ w.minimized = false; workspace.activeWindow = w; }}
""")

    def close(self, window_id):
        self._action(f"""
var w = findWindow({_js_str(window_id)});
if (w) w.closeWindow();
""")

    def pid_of(self, window_id):
        for w in self.windows:
            if w.get("id") == window_id:
                try:
                    return int(w.get("pid") or 0)
                except (TypeError, ValueError):
                    return 0
        return 0

    def is_open(self, window_id):
        return any(w.get("id") == window_id for w in self.windows)

    def raise_xmode(self):
        self._action("""
var list = workspace.windowList();
for (var i = 0; i < list.length; i++) {
    if (String(list[i].resourceClass).toLowerCase() === "cobaltx-xmode") {
        list[i].minimized = false; workspace.activeWindow = list[i]; break;
    }
}
""")

    def game_launched(self, fullscreen):
        """Call right after starting something. fullscreen=False for tools/launchers."""
        if not self.enabled:
            return
        self._fs_generation += 1
        gen = self._fs_generation
        if not fullscreen:
            # a tool/launcher: drop any rule still waiting from an earlier game
            self._unload(self.names["fullscreen"])
            return
        self._load(self.names["fullscreen"], FULLSCREEN_JS % {"skip": json.dumps(NO_FULLSCREEN)})

        def stop():
            if gen == self._fs_generation:
                self._unload(self.names["fullscreen"])
        t = threading.Timer(FULLSCREEN_SECONDS, stop)
        t.daemon = True
        t.start()

    def shutdown(self):
        if self.enabled:
            for name in self.names.values():
                try:
                    self._gdbus("unloadScript", name)
                except Exception:
                    pass
