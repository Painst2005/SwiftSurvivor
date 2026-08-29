"""Generate the original Thunder Swift arcade loop as a small PCM WAV file."""

import math
import os
import random
import struct
import wave

SAMPLE_RATE = 22050
DURATION = 48.0
BPM = 120.0
BEAT = 60.0 / BPM
TOTAL = int(SAMPLE_RATE * DURATION)
OUT_DIR = os.path.join(os.path.dirname(os.path.dirname(__file__)), "Resources", "Audio")
OUT_FILE = os.path.join(OUT_DIR, "thunder_swift_bgm.wav")


def midi(note: int) -> float:
    return 440.0 * (2.0 ** ((note - 69) / 12.0))


def phase(freq: float, t: float) -> float:
    return (freq * t) % 1.0


def sine(freq: float, t: float) -> float:
    return math.sin(2.0 * math.pi * freq * t)


def saw(freq: float, t: float) -> float:
    return phase(freq, t) * 2.0 - 1.0


def square(freq: float, t: float, duty: float = 0.5) -> float:
    return 1.0 if phase(freq, t) < duty else -1.0


random.seed(7)
chords = [
    (40, [52, 55, 59]),  # Em
    (36, [48, 52, 55]),  # C
    (43, [55, 59, 62]),  # G
    (38, [50, 54, 57]),  # D
    (40, [52, 55, 59]),
    (36, [48, 52, 55]),
    (45, [57, 60, 64]),  # Am
    (47, [59, 63, 66]),  # B7 flavour
]
arp_offsets = [0, 1, 2, 1, 0, 2, 3, 2]
lead_scale = [0, 3, 5, 7, 10, 12, 15, 17]

samples = []
for index in range(TOTAL):
    t = index / SAMPLE_RATE
    beat_number = t / BEAT
    bar = int(beat_number // 4)
    chord_index = bar % len(chords)
    root, chord = chords[chord_index]
    local_beat = beat_number % 4.0
    beat_in_bar = int(local_beat)
    sixteen = int((beat_number % 1.0) * 4.0)
    value = 0.0

    # Warm chord pad: a slow, wide-sounding bed behind the attack pattern.
    for note in chord:
        value += 0.075 * sine(midi(note), t)
        value += 0.025 * sine(midi(note + 12) * 0.997, t)

    # Driving bass on every beat.
    bass_freq = midi(root)
    bass_t = (beat_number % 1.0) * BEAT
    bass_env = min(1.0, bass_t * 18.0) * max(0.0, 1.0 - bass_t / BEAT)
    value += 0.18 * square(bass_freq, t, 0.42) * bass_env
    value += 0.08 * sine(bass_freq / 2.0, t) * bass_env

    # 16th-note arpeggio gives the track a game-shooter pulse.
    arp_note = chord[arp_offsets[int(beat_number * 4) % len(arp_offsets)] % len(chord)] + 12
    arp_t = (beat_number * 4.0 % 1.0) * (BEAT / 4.0)
    arp_env = max(0.0, 1.0 - arp_t / (BEAT / 4.0)) ** 1.5
    value += 0.13 * saw(midi(arp_note), t) * arp_env

    # Lead motif enters every other bar and stays in the same minor key.
    if bar % 2 == 1:
        step = int((beat_number * 2.0) % len(lead_scale))
        lead_note = root + 24 + lead_scale[step]
        lead_t = (beat_number * 2.0 % 1.0) * (BEAT / 2.0)
        lead_env = max(0.0, 1.0 - lead_t / (BEAT / 2.0)) ** 1.8
        value += 0.095 * sine(midi(lead_note), t) * lead_env
        value += 0.035 * square(midi(lead_note) * 2.0, t) * lead_env

    # Kick and snare accents.
    kick_t = (beat_number % 1.0) * BEAT
    kick_env = max(0.0, 1.0 - kick_t / 0.20) ** 2.0
    value += 0.48 * sine(105.0 - 55.0 * min(1.0, kick_t / 0.20), t) * kick_env if beat_in_bar in (0, 2) else 0.0
    snare_t = ((beat_number - 0.5) % 1.0) * BEAT
    snare_env = max(0.0, 1.0 - snare_t / 0.13) ** 2.0
    noise = random.uniform(-1.0, 1.0)
    value += 0.15 * noise * snare_env if beat_in_bar in (1, 3) else 0.0

    # Bright hi-hat ticks on off-beats.
    hat_t = (beat_number % 0.5) * (BEAT / 2.0)
    hat_env = max(0.0, 1.0 - hat_t / 0.055) ** 2.5
    value += 0.045 * random.uniform(-1.0, 1.0) * hat_env

    # A tiny master tremolo makes the loop breathe without changing tempo.
    value *= 0.88 + 0.12 * (0.5 + 0.5 * sine(0.55, t))
    fade = min(1.0, t / 0.03, (DURATION - t) / 0.03)
    samples.append(max(-1.0, min(1.0, value * fade)))

os.makedirs(OUT_DIR, exist_ok=True)
with wave.open(OUT_FILE, "wb") as wav:
    wav.setnchannels(1)
    wav.setsampwidth(2)
    wav.setframerate(SAMPLE_RATE)
    wav.writeframes(b"".join(struct.pack("<h", int(sample * 30000)) for sample in samples))

print(f"Generated {OUT_FILE} ({os.path.getsize(OUT_FILE)} bytes)")
