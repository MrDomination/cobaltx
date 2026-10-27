"""X Mode game library scanner.

Finds games from:
  - Steam (installed games + non-Steam shortcuts added to Steam)
  - Heroic (Epic, GOG, Amazon, sideloaded)
  - Bottles (programs added to bottles)
  - Any installed app in the "Game" category (catch-all for other launchers,
    emulators, Lutris, Minecraft launchers, ...)

Every scanner is wrapped so one broken launcher config never breaks the rest.
"""
import glob
import json
import os
import re
import shlex
import shutil
import struct
from pathlib import Path

HOME = Path.home()


# ---------------------------------------------------------------- helpers ---

def _file_url(path):
    return Path(path).resolve().as_uri() if path else ""


def _first_existing(paths):
    for p in paths:
        if p and Path(p).is_file():
            return str(p)
    return ""


def _load_json(path):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return None


def _game(key, title, source, label, launch, cover="", hero="", icon="",
          logo="", playtime=-1, ext_last=0, open_cmd=None, open_label=""):
    return {
        "key": key,
        "title": title.strip() or "Unknown",
        "source": source,        # steam | heroic | bottles | other
        "sourceLabel": label,    # what the badge on the tile says
        "cover": cover,          # portrait artwork (url) or ""
        "hero": hero,            # wide background artwork (url) or ""
        "icon": icon,            # app icon (url / image://icon/name) or ""
        "logo": logo,            # transparent title logo (url) or ""
        "playtime": playtime,    # minutes played (from the launcher), -1 = unknown
        "extLastPlayed": ext_last,  # last played according to the launcher (unix time)
        "openLabel": open_label,    # e.g. "Open in Steam" ("" = no such button)
        "tool": False,           # settings/utility app: never forced fullscreen
        "launch": launch,        # argv list, stays on the Python side
        "open": open_cmd,        # argv list, stays on the Python side
    }


def _ci(d, *keys):
    """Case-insensitive nested dict lookup (Valve files mix 'apps' / 'Apps')."""
    for k in keys:
        if not isinstance(d, dict):
            return None
        d = next((v for kk, v in d.items() if kk.lower() == k.lower()), None)
    return d


# ------------------------------------------------------------------ Steam ---

def parse_vdf(text):
    """Parse Valve's text KeyValues format (libraryfolders.vdf, *.acf)."""
    root = {}
    stack = [root]
    key = None
    for m in re.finditer(r'"((?:[^"\\]|\\.)*)"|([{}])', text):
        brace = m.group(2)
        if brace == "{":
            d = {}
            stack[-1][key if key is not None else ""] = d
            stack.append(d)
            key = None
        elif brace == "}":
            if len(stack) > 1:
                stack.pop()
            key = None
        else:
            s = m.group(1).replace("\\\\", "\\").replace('\\"', '"')
            if key is None:
                key = s
            else:
                stack[-1][key] = s
                key = None
    return root


def parse_binary_vdf(data):
    """Parse Valve's binary KeyValues format (shortcuts.vdf)."""
    pos = 0

    def read_str():
        nonlocal pos
        end = data.index(b"\x00", pos)
        s = data[pos:end].decode("utf-8", "replace")
        pos = end + 1
        return s

    def read_map():
        nonlocal pos
        d = {}
        while pos < len(data):
            t = data[pos]
            pos += 1
            if t == 0x08:
                return d
            k = read_str()
            if t == 0x00:
                d[k] = read_map()
            elif t == 0x01:
                d[k] = read_str()
            elif t == 0x02:
                d[k] = struct.unpack_from("<i", data, pos)[0]
                pos += 4
            elif t == 0x07:
                d[k] = struct.unpack_from("<Q", data, pos)[0]
                pos += 8
            else:
                raise ValueError(f"unknown vdf type {t}")
        return d

    return read_map()


STEAM_TOOL_PREFIXES = ("proton", "steam linux runtime", "steamworks common")


def _steam_roots():
    candidates = [
        HOME / ".local/share/Steam",
        HOME / ".steam/steam",
        HOME / ".steam/root",
        HOME / ".var/app/com.valvesoftware.Steam/.local/share/Steam",
    ]
    seen, roots = set(), []
    for c in candidates:
        if (c / "steamapps").is_dir():
            real = c.resolve()
            if real not in seen:
                seen.add(real)
                roots.append(real)
    return roots


def _steam_cmd(url):
    if (HOME / ".var/app/com.valvesoftware.Steam").is_dir() and not shutil.which("steam"):
        return ["flatpak", "run", "com.valvesoftware.Steam", "-silent", url]
    return ["steam", "-silent", url]


def _steam_art(root, appid):
    """Return (cover, hero, logo) file URLs for a Steam app, newest layout first."""
    cover = hero = logo = ""
    # Custom artwork the user set in Steam (userdata/<id>/config/grid)
    for grid in glob.glob(str(root / "userdata/*/config/grid")):
        g = Path(grid)
        cover = cover or _first_existing([g / f"{appid}p.png", g / f"{appid}p.jpg"])
        hero = hero or _first_existing([g / f"{appid}_hero.png", g / f"{appid}_hero.jpg"])
    lc = root / "appcache/librarycache"
    # New client: librarycache/<appid>/[hash/]library_600x900.jpg
    d = lc / str(appid)
    if d.is_dir():
        if not cover:
            hits = sorted(d.rglob("library_600x900*.jpg"))
            cover = str(hits[0]) if hits else ""
        if not hero:
            hits = sorted(d.rglob("library_hero*.jpg")) or sorted(d.rglob("header*.jpg"))
            hero = str(hits[0]) if hits else ""
        hits = sorted(d.rglob("logo*.png"))
        logo = str(hits[0]) if hits else ""
    # Old client: librarycache/<appid>_library_600x900.jpg
    cover = cover or _first_existing([lc / f"{appid}_library_600x900.jpg"])
    hero = hero or _first_existing([lc / f"{appid}_library_hero.jpg", lc / f"{appid}_header.jpg"])
    logo = logo or _first_existing([lc / f"{appid}_logo.png"])
    return _file_url(cover), _file_url(hero), _file_url(logo)


def _steam_stats(root):
    """appid -> (last played unix time, minutes played) from Steam's localconfig.vdf."""
    stats = {}
    for path in glob.glob(str(root / "userdata/*/config/localconfig.vdf")):
        apps = _ci(parse_vdf(_read_text(path) or ""),
                   "UserLocalConfigStore", "Software", "Valve", "Steam", "apps")
        for appid, v in (apps or {}).items():
            if not isinstance(v, dict):
                continue
            try:
                last = int(_ci(v, "LastPlayed") or 0)
                mins = int(_ci(v, "Playtime") or 0)
            except ValueError:
                continue
            old = stats.get(appid, (0, 0))
            stats[appid] = (max(old[0], last), max(old[1], mins))
    return stats


def scan_steam():
    games = []
    for root in _steam_roots():
        # Library folders (games can live on several drives)
        stats = _steam_stats(root)
        libs = {root / "steamapps"}
        lf = _read_text(root / "steamapps/libraryfolders.vdf")
        if lf:
            data = parse_vdf(lf).get("libraryfolders", {})
            for entry in data.values():
                if isinstance(entry, dict) and entry.get("path"):
                    libs.add(Path(entry["path"]) / "steamapps")
        for lib in libs:
            for acf in lib.glob("appmanifest_*.acf"):
                st = parse_vdf(_read_text(acf) or "").get("AppState", {})
                appid, name = st.get("appid"), st.get("name", "")
                if not appid or name.lower().startswith(STEAM_TOOL_PREFIXES):
                    continue
                if not int(st.get("StateFlags", "4") or 4) & 4:   # 4 = fully installed
                    continue
                cover, hero, logo = _steam_art(root, appid)
                last, mins = stats.get(appid, (0, -1))
                games.append(_game(f"steam:{appid}", name, "steam", "Steam",
                                   _steam_cmd(f"steam://rungameid/{appid}"), cover, hero,
                                   logo=logo, playtime=mins if appid in stats else -1, ext_last=last,
                                   open_cmd=_steam_cmd(f"steam://nav/games/details/{appid}"),
                                   open_label="Open in Steam"))
        games += _steam_shortcuts(root)
    return games


def _steam_shortcuts(root):
    """Non-Steam games the user added to Steam."""
    games = []
    for path in glob.glob(str(root / "userdata/*/config/shortcuts.vdf")):
        try:
            data = parse_binary_vdf(Path(path).read_bytes())
        except Exception:
            continue
        grid = Path(path).parent / "grid"
        for sc in data.get("shortcuts", {}).values():
            if not isinstance(sc, dict):
                continue
            sc = {k.lower(): v for k, v in sc.items()}
            name = sc.get("appname", "")
            appid = sc.get("appid", 0) & 0xFFFFFFFF
            if not name or not appid:
                continue
            gameid = (appid << 32) | 0x02000000
            cover = _first_existing([grid / f"{appid}p.png", grid / f"{appid}p.jpg"])
            hero = _first_existing([grid / f"{appid}_hero.png", grid / f"{appid}_hero.jpg"])
            logo = _first_existing([grid / f"{appid}_logo.png"])
            games.append(_game(f"steam-sc:{appid}", name, "steam", "Steam",
                               _steam_cmd(f"steam://rungameid/{gameid}"),
                               _file_url(cover), _file_url(hero), logo=_file_url(logo),
                               open_cmd=_steam_cmd("steam://open/games"), open_label="Open in Steam"))
    return games


def _read_text(path):
    try:
        return Path(path).read_text(encoding="utf-8", errors="replace")
    except Exception:
        return None


# ----------------------------------------------------------------- Heroic ---

HEROIC_FLATPAK = "com.heroicgameslauncher.hgl"


def _heroic_roots():
    roots = []
    for p, flatpak in ((HOME / ".config/heroic", False),
                       (HOME / f".var/app/{HEROIC_FLATPAK}/config/heroic", True)):
        if p.is_dir():
            roots.append((p, flatpak))
    return roots


def _heroic_open(flatpak):
    if flatpak:
        return ["flatpak", "run", HEROIC_FLATPAK]
    return ["heroic"]


def _heroic_cmd(flatpak, runner, app):
    url = f"heroic://launch?appName={app}&runner={runner}"
    if flatpak:
        return ["flatpak", "run", HEROIC_FLATPAK, url]
    return ["heroic", url] if shutil.which("heroic") else ["xdg-open", url]


def _art_index(path, list_key):
    """app_name -> library entry, from Heroic's store cache."""
    data = _load_json(path) or {}
    items = data.get(list_key, []) if isinstance(data, dict) else []
    return {i.get("app_name"): i for i in items if isinstance(i, dict)}


def _art(entry):
    if not entry:
        return "", ""
    return (entry.get("art_square") or entry.get("art_cover") or "",
            entry.get("art_background") or entry.get("art_cover") or "")


def scan_heroic():
    games = []
    for root, flatpak in _heroic_roots():
        cache = root / "store_cache"

        # Epic (legendary)
        art = _art_index(cache / "legendary_library.json", "library")
        installed = _load_json(root / "legendaryConfig/legendary/installed.json") or {}
        for app, info in installed.items():
            if not isinstance(info, dict) or info.get("is_dlc"):
                continue
            cover, hero = _art(art.get(app))
            games.append(_game(f"epic:{app}", info.get("title", app), "heroic", "Epic",
                               _heroic_cmd(flatpak, "legendary", app), cover, hero,
                               open_cmd=_heroic_open(flatpak), open_label="Open in Heroic"))

        # GOG
        art = _art_index(cache / "gog_library.json", "games")
        data = _load_json(root / "gog_store/installed.json") or {}
        for info in data.get("installed", []) if isinstance(data, dict) else []:
            app = str(info.get("appName", ""))
            if not app:
                continue
            entry = art.get(app, {})
            cover, hero = _art(entry)
            games.append(_game(f"gog:{app}", entry.get("title", app), "heroic", "GOG",
                               _heroic_cmd(flatpak, "gog", app), cover, hero,
                               open_cmd=_heroic_open(flatpak), open_label="Open in Heroic"))

        # Amazon (nile)
        art = _art_index(cache / "nile_library.json", "library")
        data = _load_json(root / "nile_config/nile/installed.json") or []
        for info in data if isinstance(data, list) else []:
            app = str(info.get("id", ""))
            if not app:
                continue
            entry = art.get(app, {})
            cover, hero = _art(entry)
            games.append(_game(f"amazon:{app}", entry.get("title", app), "heroic", "Amazon",
                               _heroic_cmd(flatpak, "nile", app), cover, hero,
                               open_cmd=_heroic_open(flatpak), open_label="Open in Heroic"))

        # Games/apps sideloaded into Heroic
        data = _load_json(root / "sideload_apps/library.json") or {}
        for info in data.get("games", []) if isinstance(data, dict) else []:
            app = info.get("app_name", "")
            if not app or info.get("is_installed") is False:
                continue
            cover, hero = _art(info)
            games.append(_game(f"heroic-side:{app}", info.get("title", app), "heroic", "Heroic",
                               _heroic_cmd(flatpak, "sideload", app), cover, hero,
                               open_cmd=_heroic_open(flatpak), open_label="Open in Heroic"))
    return games


# ---------------------------------------------------------------- Bottles ---

BOTTLES_FLATPAK = "com.usebottles.bottles"


def scan_bottles():
    try:
        import yaml
    except ImportError:
        return []
    games = []
    for base, flatpak in ((HOME / f".var/app/{BOTTLES_FLATPAK}/data/bottles/bottles", True),
                          (HOME / ".local/share/bottles/bottles", False)):
        if not base.is_dir():
            continue
        for cfg in base.glob("*/bottle.yml"):
            try:
                data = yaml.safe_load(cfg.read_text(encoding="utf-8")) or {}
            except Exception:
                continue
            bottle = data.get("Name") or cfg.parent.name
            for prog in (data.get("External_Programs") or {}).values():
                if not isinstance(prog, dict) or not prog.get("name"):
                    continue
                name = prog["name"]
                if flatpak:
                    cmd = ["flatpak", "run", "--command=bottles-cli", BOTTLES_FLATPAK,
                           "run", "-b", bottle, "-p", name]
                else:
                    cmd = ["bottles-cli", "run", "-b", bottle, "-p", name]
                opener = (["flatpak", "run", BOTTLES_FLATPAK] if flatpak else ["bottles"])
                games.append(_game(f"bottles:{bottle}:{name}", name, "bottles", "Bottles", cmd,
                                   icon=f"image://icon/{BOTTLES_FLATPAK}",
                                   open_cmd=opener, open_label="Open in Bottles"))
    return games


# ------------------------------------------------- catch-all (.desktop) ---

DESKTOP_DIRS = [
    HOME / ".local/share/applications",
    HOME / ".local/share/flatpak/exports/share/applications",
    Path("/var/lib/flatpak/exports/share/applications"),
    Path("/usr/local/share/applications"),
    Path("/usr/share/applications"),
]

LAUNCHER_IDS = {
    "steam", "com.valvesoftware.Steam", "com.heroicgameslauncher.hgl", "heroic",
    "com.usebottles.bottles", "net.lutris.Lutris", "lutris",
}

# Shortcuts that point back into a library we already scan -> skip duplicates
DUPLICATE_MARKERS = ("steam://rungameid", "heroic://", "bottles-cli")

FIELD_CODES = re.compile(r"%[fFuUdDnNickvm]")


def _parse_desktop(path):
    entry, in_section = {}, False
    for line in (_read_text(path) or "").splitlines():
        line = line.strip()
        if line.startswith("["):
            in_section = line == "[Desktop Entry]"
            continue
        if in_section and "=" in line and not line.startswith("#"):
            k, v = line.split("=", 1)
            entry.setdefault(k.strip(), v.strip())
    return entry


def _icon_source(icon):
    if not icon:
        return ""
    if icon.startswith("/"):
        return _file_url(icon) if Path(icon).is_file() else ""
    return f"image://icon/{icon}"


def scan_desktop():
    games, seen = [], set()
    for d in DESKTOP_DIRS:
        if not d.is_dir():
            continue
        for path in sorted(d.rglob("*.desktop")):
            app_id = path.stem
            if app_id in seen:
                continue
            seen.add(app_id)            # first dir wins (user overrides system)
            e = _parse_desktop(path)
            cats = e.get("Categories", "").split(";")
            if (e.get("Type") != "Application" or "Game" not in cats
                    or e.get("NoDisplay", "").lower() == "true"
                    or e.get("Hidden", "").lower() == "true"
                    or app_id.startswith("cobaltx-")):
                continue
            exec_line = e.get("Exec", "")
            if not exec_line or any(m in exec_line for m in DUPLICATE_MARKERS):
                continue
            try:
                argv = shlex.split(FIELD_CODES.sub("", exec_line).replace("%%", "%"))
            except ValueError:
                continue
            if not argv:
                continue
            if app_id in LAUNCHER_IDS:          # launchers get their own tab (scan_launchers)
                continue
            g = _game(f"app:{app_id}", e.get("Name", app_id), "other", "Game", argv,
                      icon=_icon_source(e.get("Icon", "")))
            # e.g. tuning apps listed under Game that are really settings tools
            g["tool"] = any(c in cats for c in ("Utility", "Settings", "System", "Development"))
            games.append(g)
    return games


# -------------------------------------------------------------- launchers ---

FLATPAK_APP_DIRS = [HOME / ".local/share/flatpak/app", Path("/var/lib/flatpak/app")]

# (key, name, native command, flatpak id, icon, what it is)
LAUNCHERS = [
    ("steam",   "Steam",   ["steam", "-gamepadui"], "com.valvesoftware.Steam",
     "steam", "Opens Steam in Big Picture mode - the store, your library, friends and settings, all controller-friendly."),
    ("heroic",  "Heroic",  ["heroic"], HEROIC_FLATPAK,
     HEROIC_FLATPAK, "Opens Heroic to browse, install and update Epic, GOG and Amazon games."),
    ("bottles", "Bottles", ["bottles"], BOTTLES_FLATPAK,
     BOTTLES_FLATPAK, "Opens Bottles to install and manage Windows programs and launchers."),
    ("lutris",  "Lutris",  ["lutris"], "net.lutris.Lutris",
     "net.lutris.Lutris", "Opens Lutris to install and manage games from many sources."),
]


def _flatpak_installed(app_id):
    return any((d / app_id).is_dir() for d in FLATPAK_APP_DIRS)


def scan_launchers():
    """The game stores/launchers themselves, so they can be opened from X Mode."""
    found = []
    for key, name, native, flatpak_id, icon, about in LAUNCHERS:
        if shutil.which(native[0]):
            cmd = native
        elif _flatpak_installed(flatpak_id):
            cmd = ["flatpak", "run", flatpak_id] + native[1:]
        else:
            continue
        g = _game(f"launcher:{key}", name, "launcher", "Launcher", cmd,
                  icon=f"image://icon/{icon}")
        g["about"] = about
        found.append(g)
    return found


# ------------------------------------------------- added by the user (+) ---

CUSTOM_FILE = HOME / ".local/share/cobaltx-xmode/custom.json"
WINDOWS_EXT = {".exe", ".msi", ".bat", ".lnk"}


def file_kind(path):
    """What X Mode would do with a file -> (label shown in the file browser, can_run)"""
    p = Path(path)
    ext = p.suffix.lower()
    if ext == ".desktop":
        return "App shortcut", True
    if ext == ".appimage":
        return "AppImage", True
    if ext in WINDOWS_EXT:
        return "Windows program", True
    if ext == ".sh":
        return "Script", True
    if p.is_file() and os.access(p, os.X_OK):
        return "Program", True
    return "File", True                          # opened with its default app (ROMs, ...)


def _custom_launch(path):
    p = Path(path)
    ext = p.suffix.lower()
    if ext == ".desktop":
        entry = _parse_desktop(p)
        cmd = re.sub(r"\s%[fFuUdDnNickvm]", "", entry.get("Exec", ""))
        try:
            argv = shlex.split(cmd)
        except ValueError:
            argv = []
        return argv or ["xdg-open", str(p)], entry.get("Name", ""), entry.get("Icon", "")
    if ext in WINDOWS_EXT:
        return (["wine", str(p)] if shutil.which("wine") else ["xdg-open", str(p)]), "", ""
    if ext == ".sh":
        return ["bash", str(p)], "", ""
    if ext == ".appimage" or (p.is_file() and os.access(p, os.X_OK)):
        return [str(p)], "", ""
    return ["xdg-open", str(p)], "", ""


def nice_title(path):
    stem = Path(path).stem
    t = re.sub(r"[_\.]+", " ", stem)
    t = re.sub(r"\s+-\s+|-", " ", t).strip()
    t = re.sub(r"\s*(x86_64|x64|amd64|linux)\s*$", "", t, flags=re.I).strip()
    return t[:1].upper() + t[1:] if t else stem


def load_custom():
    data = _load_json(CUSTOM_FILE)
    return data if isinstance(data, list) else []


def save_custom(items):
    CUSTOM_FILE.parent.mkdir(parents=True, exist_ok=True)
    CUSTOM_FILE.write_text(json.dumps(items, indent=1))


def add_custom(path):
    """-> the new entry, or None if it was already in the library"""
    path = str(Path(path).resolve())
    items = load_custom()
    if any(i.get("path") == path for i in items):
        return None
    if path.lower().endswith(".appimage"):
        try:                                     # AppImages need to be executable
            os.chmod(path, os.stat(path).st_mode | 0o111)
        except OSError:
            pass
    _, name, _ = _custom_launch(path)
    import hashlib
    item = {"key": "custom:" + hashlib.sha1(path.encode()).hexdigest()[:12],
            "title": name or nice_title(path), "path": path}
    items.append(item)
    save_custom(items)
    return item


def remove_custom(key):
    items = [i for i in load_custom() if i.get("key") != key]
    save_custom(items)


def scan_custom():
    found = []
    for item in load_custom():
        path = item.get("path", "")
        if not path or not Path(path).exists():
            continue                             # file moved / drive unplugged
        argv, _, icon = _custom_launch(path)
        g = _game(item["key"], item.get("title") or nice_title(path), "custom", "Added by you",
                  argv, icon=_icon_source(icon), open_label="Remove from Library")
        g["about"] = path
        found.append(g)
    return found


# -------------------------------------------------------------- everything ---

SCANNERS = (scan_launchers, scan_steam, scan_heroic, scan_bottles, scan_desktop, scan_custom)


def scan_all():
    games, keys = [], set()
    for scanner in SCANNERS:
        try:
            found = scanner()
        except Exception as e:          # never let one launcher break X Mode
            print(f"[xmode] {scanner.__name__} failed: {e}")
            continue
        for g in found:
            if g["key"] not in keys:
                keys.add(g["key"])
                games.append(g)
    return games


if __name__ == "__main__":
    for g in scan_all():
        print(f'{g["sourceLabel"]:9} {g["title"]:40} {g["launch"]}')
