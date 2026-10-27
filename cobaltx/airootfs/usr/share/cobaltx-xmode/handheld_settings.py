"""Small settings shared by X Mode and the desktop helper (~/.config/cobaltx/handheld.json)."""
import json
from pathlib import Path

FILE = Path.home() / ".config/cobaltx/handheld.json"

# What the right back button does (default: nothing)
RIGHT_BACK_CHOICES = ["nothing", "quick", "apps", "keyboard", "cursor"]


def load():
    try:
        data = json.loads(FILE.read_text())
        return data if isinstance(data, dict) else {}
    except (OSError, ValueError):
        return {}


def get(key, default=None):
    return load().get(key, default)


def put(key, value):
    data = load()
    data[key] = value
    try:
        FILE.parent.mkdir(parents=True, exist_ok=True)
        FILE.write_text(json.dumps(data))
    except OSError:
        pass


def right_back():
    v = get("right_back", "nothing")
    return v if v in RIGHT_BACK_CHOICES else "nothing"
