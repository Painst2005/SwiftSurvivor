"""Generate compact PCM sound effects for Thunder Swift."""

import math
import os
import random
import struct
import wave

RATE = 22050
OUT_DIR = os.path.join(os.path.dirname(os.path.dirname(__file__)), "Resources", "Audio")


def write_wav(name, duration, synth):
    count = int(RATE * duration)
    frames = []
    for index in range(count):
        t = index / RATE
        value = max(-1.0, min(1.0, synth(t, duration)))
        frames.append(struct.pack("<h", int(value * 28000)))
    path = os.path.join(OUT_DIR, name + ".wav")
    with wave.open(path, "wb") as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(RATE)
        wav.writeframes(b"".join(frames))


def tone(start, end, length, amplitude=0.4, wobble=0.0):
    def synth(t, duration):
        p = min(1.0, t / length)
        freq = start + (end - start) * p
        env = max(0.0, 1.0 - p) ** 1.8
        return amplitude * env * math.sin(2 * math.pi * freq * t + wobble * math.sin(t * 40))
    return synth


random.seed(4)

write_wav("sfx_shoot", 0.075, tone(980, 460, 0.075, 0.28))
write_wav("sfx_hit", 0.12, tone(240, 120, 0.12, 0.35))
write_wav("sfx_powerup", 0.32, lambda t, d: sum(
    0.18 * max(0.0, 1.0 - (t - offset) / 0.16) * math.sin(2 * math.pi * (520 + index * 130) * max(0.0, t - offset))
    for index, offset in enumerate((0.0, 0.075, 0.15))
))
write_wav("sfx_explosion", 0.28, lambda t, d: (
    0.46 * max(0.0, 1.0 - t / d) ** 1.4 * math.sin(2 * math.pi * (120 - 70 * t / d) * t)
    + 0.22 * max(0.0, 1.0 - t / d) * random.uniform(-1.0, 1.0)
))
write_wav("sfx_boss", 0.8, lambda t, d: (
    0.25 * max(0.0, 1.0 - t / d) * math.sin(2 * math.pi * (75 + 180 * t) * t)
    + 0.18 * math.sin(2 * math.pi * 390 * t) * max(0.0, min(1.0, t * 8))
))
write_wav("sfx_upgrade", 0.42, lambda t, d: (
    0.24 * max(0.0, 1.0 - t / d) * math.sin(2 * math.pi * (420 + 360 * t) * t)
))
write_wav("sfx_achievement", 0.55, lambda t, d: (
    0.22 * max(0.0, 1.0 - t / d) * math.sin(2 * math.pi * (660 + 220 * t) * t)
))
print("Generated Thunder Swift sound effects")
