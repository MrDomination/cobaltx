"""Make games launched from X Mode open fullscreen.

Inside the gamescope session every window is fullscreen anyway. Everywhere
else (the KDE desktop, or the KWin fallback session) X Mode loads a tiny KWin
script for a short while after each launch that makes new game windows
fullscreen. Launcher windows (Steam client, Heroic, ...) are left alone.
"""
import os
import subprocess
import threading
from pathlib import Path

PLUGIN = "cobaltx-xmode-fullscreen"
ACTIVE_SECONDS = 120          # windows opening this long after a launch get fullscreened

SCRIPT = r"""
// CobaltX X Mode: fullscreen windows of games launched from X Mode
const skip = ["steam", "steamwebhelper", "cobaltx-xmode", "python3", "plasmashell",
              "krunner", "org.kde.plasmashell", "org.kde.polkit-kde-authentication-agent-1",
              "polkit-kde-authentication-agent-1", "xdg-desktop-portal-kde", "kwin_wayland",
              "heroic", "com.heroicgameslauncher.hgl", "com.usebottles.bottles", "bottles",
              "net.lutris.lutris", "lutris"];
workspace.windowAdded.connect(function (w) {
    if (!w || !w.normalWindow) return;
    var cls = String(w.resourceClass || "").toLowerCase();
    if (skip.indexOf(cls) >= 0) return;
    w.fullScreen = true;
});
"""


def under_gamescope():
    return ("gamescope" in os.environ.get("XDG_CURRENT_DESKTOP", "").lower()
            or bool(os.environ.get("GAMESCOPE_WAYLAND_DISPLAY")))


def _gdbus(method, *args):
    try:
        subprocess.run(["gdbus", "call", "--session", "--dest", "org.kde.KWin",
                        "--object-path", "/Scripting", "--method",
                        f"org.kde.kwin.Scripting.{method}", *args],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=5)
    except Exception:
        pass


class Fullscreener:
    def __init__(self):
        self.enabled = not under_gamescope()
        self._generation = 0
        runtime = os.environ.get("XDG_RUNTIME_DIR") or "/tmp"
        self.path = Path(runtime) / f"{PLUGIN}.js"

    def game_launched(self, is_launcher=False):
        """Call right after starting a game. Never blocks the UI."""
        if not self.enabled or is_launcher:
            return
        self._generation += 1
        gen = self._generation
        threading.Thread(target=self._activate, args=(gen,), daemon=True).start()

    def _activate(self, gen):
        try:
            self.path.write_text(SCRIPT)
        except OSError:
            return
        _gdbus("unloadScript", PLUGIN)              # restart the window clock
        _gdbus("loadScript", str(self.path), PLUGIN)
        _gdbus("start")
        timer = threading.Timer(ACTIVE_SECONDS, self._deactivate, args=(gen,))
        timer.daemon = True
        timer.start()

    def _deactivate(self, gen):
        if gen == self._generation:                 # no newer launch since then
            _gdbus("unloadScript", PLUGIN)

    def shutdown(self):
        if self.enabled:
            _gdbus("unloadScript", PLUGIN)
