"""X Mode UI sounds, played outside of Qt.

Qt Multimedia's PipeWire connection could break and spin Qt's event loop
forever (the whole UI froze). So sounds are mixed here in a background thread
and streamed to a small external player (pacat / pw-cat / aplay). If audio
breaks, only that helper process dies - it is restarted on the next sound and
the interface never waits on audio.
"""
import array
import fcntl
import os
import shutil
import subprocess
import threading
import time
import wave
from pathlib import Path

RATE = 48000
CHANNELS = 2
CHUNK_FRAMES = 480                 # 10 ms per chunk
LEAD = 0.03                        # keep at most ~30 ms queued ahead of real time
IDLE_CLOSE = 8.0                   # close the audio stream after 8 s of silence
F_SETPIPE_SZ = 1031


def _player_cmd():
    override = os.environ.get("XMODE_AUDIO_CMD")
    if override:
        return override.split()
    if shutil.which("pacat"):
        return ["pacat", "--playback", "--format=s16le", f"--rate={RATE}", f"--channels={CHANNELS}",
                "--latency-msec=30", "--client-name=X Mode", "--stream-name=UI sounds"]
    if shutil.which("pw-cat"):
        return ["pw-cat", "--playback", "--raw", "--format", "s16", "--rate", str(RATE),
                "--channels", str(CHANNELS), "--latency", "30ms", "-"]
    if shutil.which("aplay"):
        return ["aplay", "-q", "-t", "raw", "-f", "S16_LE", "-r", str(RATE), "-c", str(CHANNELS),
                "--buffer-time=40000", "-"]
    return None


class SoundPlayer:
    def __init__(self, sound_dir, volume=0.8):
        self.volume = volume
        self.enabled = True
        self.sounds = {}
        self.voices = []                 # [samples, position]
        self.lock = threading.Lock()
        self.wake = threading.Event()
        self.cmd = _player_cmd()
        for wav in sorted(Path(sound_dir).glob("*.wav")):
            try:
                self.sounds[wav.stem] = self._load(wav)
            except Exception as e:
                print(f"[xmode] could not load sound {wav.name}: {e}")
        if not self.cmd:
            print("[xmode] no audio player found (pacat/pw-cat/aplay) - UI sounds disabled")
        else:
            threading.Thread(target=self._run, name="xmode-sound", daemon=True).start()

    def _load(self, path):
        with wave.open(str(path)) as w:
            if w.getsampwidth() != 2 or w.getframerate() != RATE:
                raise ValueError("expected 16-bit 48 kHz")
            data = array.array("h", w.readframes(w.getnframes()))
            if w.getnchannels() == 1:                       # mono -> stereo
                data = array.array("h", (s for s in data for _ in (0, 1)))
        if self.volume != 1.0:
            v = self.volume
            data = array.array("h", (int(s * v) for s in data))
        return data

    def play(self, name):
        if not self.enabled or not self.cmd:
            return
        snd = self.sounds.get(name)
        if snd is None:
            return
        with self.lock:
            if name == "move":                              # fast scrolling: keep at most 2 moves overlapping
                others = [v for v in self.voices if v[2] != "move"]
                moves = [v for v in self.voices if v[2] == "move"]
                self.voices = others + moves[-1:]
            self.voices.append([snd, 0, name])
        self.wake.set()

    # ------------------------------------------------------- audio thread
    def _mix(self):
        n = CHUNK_FRAMES * CHANNELS
        with self.lock:
            voices = self.voices
            if not voices:
                return None
            if len(voices) == 1:
                snd, pos, _ = voices[0]
                chunk = snd[pos:pos + n]
                voices[0][1] = pos + n
            else:
                acc = [0] * n
                for v in voices:
                    snd, pos = v[0], v[1]
                    part = snd[pos:pos + n]
                    for i, s in enumerate(part):
                        acc[i] += s
                    v[1] = pos + n
                chunk = array.array("h", (32767 if s > 32767 else -32768 if s < -32768 else s for s in acc))
            self.voices = [v for v in voices if v[1] < len(v[0])]
        if len(chunk) < n:
            chunk.extend([0] * (n - len(chunk)))
        return chunk

    def _start(self):
        try:
            proc = subprocess.Popen(self.cmd, stdin=subprocess.PIPE,
                                    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                                    start_new_session=True)
            try:                                            # tiny pipe = low latency
                fcntl.fcntl(proc.stdin.fileno(), F_SETPIPE_SZ, 4096)
            except OSError:
                pass
            return proc
        except Exception as e:
            print("[xmode] audio player failed to start:", e)
            return None

    @staticmethod
    def _stop(proc):
        if proc is None:
            return
        try:
            proc.stdin.close()
        except Exception:
            pass
        try:
            proc.kill()
            proc.wait(timeout=1)
        except Exception:
            pass

    def _run(self):
        silence = array.array("h", [0] * (CHUNK_FRAMES * CHANNELS)).tobytes()
        proc = None
        t0 = 0.0
        frames = 0
        last_sound = 0.0
        while True:
            if proc is None:
                self.wake.wait()                            # sleep until a sound is played
                self.wake.clear()
                proc = self._start()
                if proc is None:
                    time.sleep(2)
                    continue
                t0, frames = time.monotonic(), 0
            chunk = self._mix()
            now = time.monotonic()
            if chunk is not None:
                last_sound = now
                data = chunk.tobytes()
            elif now - last_sound > IDLE_CLOSE:
                self._stop(proc)                            # free the audio device when idle
                proc = None
                continue
            else:
                data = silence
            try:
                proc.stdin.write(data)
                proc.stdin.flush()
            except Exception:                               # player died (audio hiccup) -> restart later
                self._stop(proc)
                proc = None
                time.sleep(0.3)
                continue
            frames += CHUNK_FRAMES
            ahead = t0 + frames / RATE - time.monotonic()
            if ahead > LEAD:
                time.sleep(ahead - LEAD)
