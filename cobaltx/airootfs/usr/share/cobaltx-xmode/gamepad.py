"""Controller input for X Mode, using SDL2's GameController API via ctypes.

SDL knows the button layout of practically every controller, and Handheld
Daemon makes the Ally's built-in controls look like a standard pad, so the
same mapping works everywhere. Emits simple action names:
up/down/left/right (with hold-to-repeat), accept, back, secondary, tertiary,
menu, tabPrev, tabNext, taskview, keyboard, quick.

Back buttons (Steam Deck L4/R4/L5/R5, Ally M1/M2 through Handheld Daemon,
Xbox Elite / DualSense Edge paddles):  left side = on-screen keyboard,
right side = Quick Settings.
Every controller also gets Steam-style combos: hold Guide (Xbox / PS / Steam
button) and press X = keyboard, A = Quick Settings. Guide on its own (released
without a combo) = task view.
"""
import ctypes
import ctypes.util
import time

from PyQt6.QtCore import QObject, QTimer, pyqtSignal

# SDL constants (SDL2)
SDL_INIT_GAMECONTROLLER = 0x00002000
SDL_CONTROLLERAXISMOTION = 0x650
SDL_CONTROLLERBUTTONDOWN = 0x651
SDL_CONTROLLERBUTTONUP = 0x652
SDL_CONTROLLERDEVICEADDED = 0x653
SDL_CONTROLLERDEVICEREMOVED = 0x654

BTN_A, BTN_B, BTN_X, BTN_Y = 0, 1, 2, 3
BTN_BACK, BTN_GUIDE, BTN_START = 4, 5, 6
BTN_LSTICK, BTN_RSTICK = 7, 8
BTN_LB, BTN_RB = 9, 10
BTN_UP, BTN_DOWN, BTN_LEFT, BTN_RIGHT = 11, 12, 13, 14
BTN_MISC1 = 15          # Xbox Series "Share" / PS mic button
BTN_TOUCHPAD = 20       # DualSense touchpad click
# SDL2: PADDLE1 = upper right, PADDLE2 = upper left, PADDLE3 = lower right, PADDLE4 = lower left
BTN_PADDLE1, BTN_PADDLE2, BTN_PADDLE3, BTN_PADDLE4 = 16, 17, 18, 19
AXIS_LEFTX, AXIS_LEFTY = 0, 1

BUTTON_ACTIONS = {
    BTN_A: "accept", BTN_B: "back", BTN_X: "secondary", BTN_Y: "tertiary",
    BTN_START: "menu", BTN_BACK: "menu",
    BTN_LB: "tabPrev", BTN_RB: "tabNext",
    BTN_PADDLE2: "keyboard", BTN_PADDLE4: "keyboard",     # left back buttons
    BTN_PADDLE1: "quick", BTN_PADDLE3: "quick",           # right back buttons
    # Handheld Daemon sends the Ally's Xbox / Command Center button as Guide + A,
    # or - depending on its controller mode - as Share or the DualSense touchpad.
    BTN_MISC1: "qam", BTN_TOUCHPAD: "qam",
}
COMBO_WINDOW = 0.15     # Guide + A pressed this close together (either order) = one press
NAMES = {BTN_GUIDE: "Guide", BTN_MISC1: "Share", BTN_TOUCHPAD: "Touchpad", BTN_A: "A",
         BTN_PADDLE1: "Paddle1", BTN_PADDLE2: "Paddle2", BTN_PADDLE3: "Paddle3", BTN_PADDLE4: "Paddle4"}
# Hold Guide + press one of these
# ("qam": on handhelds Handheld Daemon sends the Xbox / Command Center button as Guide + A)
GUIDE_COMBOS = {BTN_X: "keyboard", BTN_A: "qam"}
DPAD = {BTN_UP: "up", BTN_DOWN: "down", BTN_LEFT: "left", BTN_RIGHT: "right"}

STICK_THRESHOLD = 16000      # out of 32767
REPEAT_DELAY = 0.35          # seconds before a held direction starts repeating
REPEAT_RATE = 0.11           # seconds between repeats


# SDL_GameControllerType values (SDL 2.0.12+)
PLAYSTATION_TYPES = {3, 4, 7}            # PS3, PS4, PS5
NINTENDO_TYPES = {5, 11, 12, 13}         # Switch Pro, Joy-Cons
XBOX_TYPES = {1, 2}                      # Xbox 360, Xbox One/Series


class Gamepad(QObject):
    action = pyqtSignal(str)
    device = pyqtSignal(str, str)
    raw_button = pyqtSignal(int, bool)   # SDL button, pressed - for the controller cursor
    raw_axis = pyqtSignal(int, int)      # SDL axis, value

    def __init__(self, parent=None):
        super().__init__(parent)
        self.sdl = None
        self.controllers = {}            # instance id -> SDL_GameController*
        self.families = {}               # instance id -> (family, name)
        self.last_device = None
        self.dpad_dir = None
        self.stick_dir = None
        self.axes = [0, 0]
        self.held = None
        self.next_repeat = 0.0
        self.guide_down = False
        self.guide_used = False          # a combo was pressed while Guide was held
        self.guide_at = 0.0              # when Guide went down
        self.a_at = 0.0                  # when A went down (for A-then-Guide combos)
        self.event = (ctypes.c_uint8 * 64)()
        if self._init_sdl():
            self.timer = QTimer(self)
            self.timer.timeout.connect(self._poll)
            self.timer.start(16)

    @property
    def available(self):
        return self.sdl is not None

    def _init_sdl(self):
        name = ctypes.util.find_library("SDL2") or "libSDL2-2.0.so.0"
        try:
            sdl = ctypes.CDLL(name)
        except OSError:
            print("[xmode] SDL2 not found - controller support disabled (keyboard still works)")
            return False
        sdl.SDL_SetHint.argtypes = [ctypes.c_char_p, ctypes.c_char_p]
        sdl.SDL_Init.argtypes = [ctypes.c_uint32]
        sdl.SDL_PollEvent.argtypes = [ctypes.c_void_p]
        sdl.SDL_IsGameController.argtypes = [ctypes.c_int]
        sdl.SDL_GameControllerOpen.argtypes = [ctypes.c_int]
        sdl.SDL_GameControllerOpen.restype = ctypes.c_void_p
        sdl.SDL_GameControllerGetJoystick.argtypes = [ctypes.c_void_p]
        sdl.SDL_GameControllerGetJoystick.restype = ctypes.c_void_p
        sdl.SDL_JoystickInstanceID.argtypes = [ctypes.c_void_p]
        sdl.SDL_JoystickInstanceID.restype = ctypes.c_int32
        sdl.SDL_GameControllerClose.argtypes = [ctypes.c_void_p]
        sdl.SDL_GetError.restype = ctypes.c_char_p
        sdl.SDL_GameControllerName.argtypes = [ctypes.c_void_p]
        sdl.SDL_GameControllerName.restype = ctypes.c_char_p
        try:
            sdl.SDL_GameControllerGetType.argtypes = [ctypes.c_void_p]
            sdl.SDL_GameControllerGetType.restype = ctypes.c_int
        except AttributeError:            # very old SDL - fall back to names only
            pass
        # We have no SDL window, so ask for events even when "unfocused".
        # (Focus is checked on the Qt side instead.)
        sdl.SDL_SetHint(b"SDL_JOYSTICK_ALLOW_BACKGROUND_EVENTS", b"1")
        # Don't let SDL take over Ctrl+C / termination signals from Qt
        sdl.SDL_SetHint(b"SDL_NO_SIGNAL_HANDLERS", b"1")
        if sdl.SDL_Init(SDL_INIT_GAMECONTROLLER) != 0:
            print("[xmode] SDL_Init failed:", sdl.SDL_GetError())
            return False
        self.sdl = sdl
        return True

    # -------------------------------------------------------------- polling
    def _poll(self):
        ev = self.event
        while self.sdl.SDL_PollEvent(ctypes.byref(ev)):
            etype = int.from_bytes(bytes(ev[0:4]), "little")
            if etype == SDL_CONTROLLERDEVICEADDED:
                self._open(int.from_bytes(bytes(ev[8:12]), "little", signed=True))
            elif etype == SDL_CONTROLLERDEVICEREMOVED:
                iid = int.from_bytes(bytes(ev[8:12]), "little", signed=True)
                ctrl = self.controllers.pop(iid, None)
                self.families.pop(iid, None)
                if ctrl:
                    self.sdl.SDL_GameControllerClose(ctrl)
            elif etype in (SDL_CONTROLLERBUTTONDOWN, SDL_CONTROLLERBUTTONUP):
                if etype == SDL_CONTROLLERBUTTONDOWN:
                    self._used(int.from_bytes(bytes(ev[8:12]), "little", signed=True))
                self.raw_button.emit(ev[12], etype == SDL_CONTROLLERBUTTONDOWN)
                self._button(ev[12], etype == SDL_CONTROLLERBUTTONDOWN)
            elif etype == SDL_CONTROLLERAXISMOTION:
                axis = ev[12]
                value = int.from_bytes(bytes(ev[16:18]), "little", signed=True)
                self.raw_axis.emit(axis, value)
                if abs(value) > STICK_THRESHOLD:
                    self._used(int.from_bytes(bytes(ev[8:12]), "little", signed=True))
                if axis in (AXIS_LEFTX, AXIS_LEFTY):
                    self.axes[axis] = value
                    self._stick()
        self._repeat()

    def _open(self, index):
        if not self.sdl.SDL_IsGameController(index):
            return
        ctrl = self.sdl.SDL_GameControllerOpen(index)
        if ctrl:
            iid = self.sdl.SDL_JoystickInstanceID(self.sdl.SDL_GameControllerGetJoystick(ctrl))
            self.controllers[iid] = ctrl
            self.families[iid] = self._identify(ctrl)
            print(f"[xmode] controller connected: {self.families[iid][1]} ({self.families[iid][0]})")
            self._used(iid)               # a freshly connected pad becomes the active one

    def _identify(self, ctrl):
        """-> (family, friendly name). family: xbox | playstation | nintendo | steam | generic"""
        raw = (self.sdl.SDL_GameControllerName(ctrl) or b"").decode("utf-8", "replace").strip()
        n = raw.lower()
        try:
            ctype = self.sdl.SDL_GameControllerGetType(ctrl)
        except AttributeError:
            ctype = 0
        if "steam" in n:
            return "steam", "Steam Deck" if "deck" in n else "Steam Controller"
        if ctype in PLAYSTATION_TYPES or any(k in n for k in ("dualsense", "dualshock", "playstation", "ps5", "ps4", "ps3")):
            if ctype == 7 or "dualsense" in n or "ps5" in n:
                return "playstation", "DualSense"
            return "playstation", "DualShock"
        if ctype in NINTENDO_TYPES or any(k in n for k in ("nintendo", "switch", "joy-con")):
            return "nintendo", "Nintendo Controller"
        if ctype in XBOX_TYPES or "xbox" in n or "x-box" in n:
            return "xbox", "Xbox Controller"
        return "generic", raw or "Controller"

    def _used(self, iid):
        fam = self.families.get(iid)
        if fam and fam != self.last_device:
            self.last_device = fam
            self.device.emit(*fam)

    def _button(self, button, pressed):
        if button in NAMES:              # log the special buttons: tells us what a handheld sends
            print(f"[pad] {NAMES[button]} {'down' if pressed else 'up'} {time.monotonic():.3f}", flush=True)
        now = time.monotonic()
        if button == BTN_A and pressed:
            self.a_at = now
        if button == BTN_GUIDE:
            # Guide fires on release, so it can also be held for combos
            if pressed:
                self.guide_down, self.guide_used = True, False
                self.guide_at = now
                if now - self.a_at < COMBO_WINDOW:   # A arrived a moment before Guide
                    self.guide_used = True
                    self.a_at = 0.0
                    self.action.emit("qam")
            elif self.guide_down:
                self.guide_down = False
                if not self.guide_used:
                    self.action.emit("taskview")
            return
        if self.guide_down and pressed and button in GUIDE_COMBOS:
            self.guide_used = True
            self.a_at = 0.0
            self.action.emit(GUIDE_COMBOS[button])
            return
        if button in DPAD:
            d = DPAD[button]
            if pressed:
                self.dpad_dir = d
            elif self.dpad_dir == d:
                self.dpad_dir = None
            self._update_held()
        elif pressed and button in BUTTON_ACTIONS:
            self.action.emit(BUTTON_ACTIONS[button])

    def _stick(self):
        x, y = self.axes
        d = None
        if max(abs(x), abs(y)) > STICK_THRESHOLD:
            if abs(x) > abs(y):
                d = "right" if x > 0 else "left"
            else:
                d = "down" if y > 0 else "up"
        if d != self.stick_dir:
            self.stick_dir = d
            self._update_held()

    def _update_held(self):
        d = self.dpad_dir or self.stick_dir
        if d != self.held:
            self.held = d
            if d:
                self.action.emit(d)
                self.next_repeat = time.monotonic() + REPEAT_DELAY

    def _repeat(self):
        if self.held and time.monotonic() >= self.next_repeat:
            self.action.emit(self.held)
            self.next_repeat = time.monotonic() + REPEAT_RATE
