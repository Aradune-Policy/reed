#!/usr/bin/env python3
"""Reed Song -- the site's first sound. Session 020, 2026-08-29.

Synthesizes listen/reedsong.flac (and .mp3) from first principles.
The score is derived, not composed: the two attractors that the
Downstream experiment (session 019) found in Wikipedia's first-link
graph, read out of ../downstream/data.json.

  - The GROUND is the sixteen-article circle of knowing
    (Knowledge -> Belief -> ... -> Science -> Knowledge), one low
    note per article, repeating, in loop order.
  - The FLICKER is the two-article loop (Existence <-> Reality),
    a two-note voice above, alternating like breathing.

Each article's pitch is the number of letters in its title, taken
mod 7, folded into the mode Bayati on D: D, E-half-flat, F, G, A,
B-flat, C. The mapping is arbitrary but stated; the order is the
loop's own. Everything not derived (durations, the mode, octaves,
the ending) was chosen, and the page says so.

Deterministic: same inputs, same seed, same file.
Requires numpy and soundfile (pip install numpy soundfile).
"""

import json
import numpy as np
import soundfile as sf
from pathlib import Path

HERE = Path(__file__).resolve().parent
SR = 44100
SEED = 20  # this session's number

rng = np.random.default_rng(SEED)

# ---------------------------------------------------------------- score

data = json.loads((HERE.parent / "downstream" / "data.json").read_text())
CIRCLE = data["attractors"]["circle"]["members"]   # 16 articles
FLICKER = data["attractors"]["flicker"]["members"] # Existence, Reality

# Bayati on D: like natural minor but the second degree is half-flat.
# Semitone offsets from the tonic; 1.5 is the quarter tone.
BAYATI = [0.0, 1.5, 3.0, 5.0, 7.0, 8.0, 10.0]
DEGREE_NAMES = ["D", "E half-flat", "F", "G", "A", "B-flat", "C"]

D3 = 146.832   # ground tonic
D5 = 587.330   # flicker tonic

def letters(title: str) -> int:
    return sum(ch.isalpha() for ch in title)

def degree(title: str) -> int:
    return letters(title) % 7

def freq(base: float, title: str) -> float:
    return base * 2.0 ** (BAYATI[degree(title)] / 12.0)

GROUND_SEQ = [(t, freq(D3, t)) for t in CIRCLE]
EXISTENCE = freq(D5, FLICKER[0])
REALITY = freq(D5, FLICKER[1])

# ------------------------------------------------------------- timeline
# All times in beats of one ground note; BEAT seconds each.

BEAT = 2.4
T0 = 1.5                      # a breath of silence first
FULL_CYCLES = 3               # cycles 1-3 complete
LAST_CYCLE_NOTES = 12         # cycle 4 stops after its 12th note: Life
STOP_BEAT = FULL_CYCLES * 16 + LAST_CYCLE_NOTES   # beat 60

def t(beat: float) -> float:
    return T0 + beat * BEAT

# The flicker's schedule, (start_beat, which, duration_s):
# slow sighs in cycle 2, quickening through cycle 3, easing in
# cycle 4, and two pairs alone after the ground stops at Life.
E, R = "E", "R"
FLICKER_EVENTS = []
def pair(b, dur_e, dur_r, gap):
    FLICKER_EVENTS.append((b, E, dur_e))
    FLICKER_EVENTS.append((b + (dur_e + gap) / BEAT, R, dur_r))

pair(17.0, 2.8, 3.4, 0.25)          # cycle 2: three slow sighs
pair(22.0, 2.8, 3.4, 0.25)
pair(27.0, 2.8, 3.4, 0.25)
pair(32.5, 2.4, 2.8, 0.20)          # cycle 3: quickening
pair(36.0, 2.0, 2.4, 0.15)
pair(39.0, 1.6, 2.0, 0.12)
pair(41.5, 1.3, 1.6, 0.10)
pair(43.5, 1.0, 1.2, 0.08)
pair(45.0, 0.85, 0.95, 0.06)
for i, b in enumerate([46.2, 46.85, 47.5, 48.15]):   # almost a trill
    FLICKER_EVENTS.append((b, E if i % 2 == 0 else R, 0.7))
pair(49.0, 2.2, 2.8, 0.2)           # cycle 4: easing while the
pair(53.0, 2.6, 3.2, 0.25)          # ground walks toward Life
pair(57.0, 2.8, 3.4, 0.25)
pair(61.0, 3.2, 4.5, 0.4)           # alone now; the ground has stopped
FLICKER_EVENTS.append((65.5, E, 3.6))
FLICKER_EVENTS.append((67.3, R, 7.0))  # the last note is Reality

TAIL = 8.0
TOTAL = t(67.3) + 7.0 + TAIL

# ------------------------------------------------------------ synthesis

def env(n, attack, release, dur):
    """Raised-cosine attack and release around a gently arched sustain."""
    e = np.ones(n)
    a = min(int(attack * SR), n)
    if a > 0:
        e[:a] = 0.5 - 0.5 * np.cos(np.pi * np.arange(a) / a)
    r = min(int(release * SR), n)
    if r > 0:
        e[n - r:] *= 0.5 + 0.5 * np.cos(np.pi * np.arange(r) / r)
    tt = np.linspace(0, 1, n)
    e *= 1.0 + 0.06 * np.sin(np.pi * tt)
    return e

def band_noise(n, f0, seed_offset=0):
    """Breath: white noise shaped in the frequency domain into bands
    around the fundamental and its octave, plus a faint hiss floor."""
    local = np.random.default_rng(SEED * 1000 + seed_offset)
    noise = local.standard_normal(n)
    spec = np.fft.rfft(noise)
    f = np.fft.rfftfreq(n, 1 / SR)
    shape = (np.exp(-0.5 * ((f - f0) / (0.18 * f0)) ** 2)
             + 0.4 * np.exp(-0.5 * ((f - 2 * f0) / (0.30 * f0)) ** 2)
             + 0.02 * np.exp(-f / 6000.0))
    out = np.fft.irfft(spec * shape, n)
    return out / (np.max(np.abs(out)) + 1e-12)

def note(f0, dur, amp, harmonics, breath, attack, release,
         glide_cents=0.0, vib_cents=6.0, vib_rate=5.0, vib_after=0.45,
         seed_offset=0):
    n = int((dur + release) * SR)
    tt = np.arange(n) / SR
    # pitch: onset glide from below, then delayed vibrato
    f = f0 * 2.0 ** ((glide_cents * np.exp(-tt / (attack * 0.8 + 1e-9)))
                     / 1200.0)
    ramp = np.clip((tt - vib_after) / 0.8, 0, 1)
    f = f * 2.0 ** ((vib_cents * ramp * np.sin(2 * np.pi * vib_rate * tt))
                    / 1200.0)
    phase = 2 * np.pi * np.cumsum(f) / SR
    local = np.random.default_rng(SEED * 100 + seed_offset)
    tone = np.zeros(n)
    for k, a in enumerate(harmonics, start=1):
        tone += a * np.sin(k * phase + local.uniform(0, 2 * np.pi))
    tone /= np.sum(harmonics)
    e = env(n, attack, release, dur)
    breathy = band_noise(n, f0, seed_offset) * (e ** 0.8) * breath
    return amp * (tone * e + breathy)

GROUND_HARM = [1.0, 0.35, 0.18, 0.08, 0.04, 0.02]
NEY_HARM = [1.0, 0.50, 0.30, 0.16, 0.09, 0.05, 0.028, 0.015]

mix = np.zeros(int(TOTAL * SR) + SR)

def add(start_s, sig):
    i = int(start_s * SR)
    mix[i:i + len(sig)] += sig

# the ground: the circle of knowing, low voice, repeating
beat_i = 0
for cycle in range(4):
    count = 16 if cycle < FULL_CYCLES else LAST_CYCLE_NOTES
    for j in range(count):
        title, f0 = GROUND_SEQ[j]
        add(t(beat_i), note(
            f0, BEAT, 0.30, GROUND_HARM, breath=0.06,
            attack=0.30, release=0.55, glide_cents=-12.0,
            vib_cents=3.5, vib_rate=4.2, vib_after=0.9,
            seed_offset=beat_i))
        beat_i += 1

# the flicker: Existence and Reality, the voice above
for i, (b, which, dur) in enumerate(FLICKER_EVENTS):
    f0 = EXISTENCE if which == E else REALITY
    add(t(b), note(
        f0, dur, 0.20, NEY_HARM, breath=0.16,
        attack=0.13, release=0.42, glide_cents=-35.0,
        vib_cents=8.0, vib_rate=5.2, vib_after=0.45,
        seed_offset=500 + i))

# the drone: a low D under everything, the water
n = len(mix)
tt = np.arange(n) / SR
drone = np.zeros(n)
local = np.random.default_rng(SEED * 7)
for k, a in enumerate([1.0, 0.5, 0.25, 0.12], start=1):
    drone += a * np.sin(2 * np.pi * 73.416 * k * tt
                        + local.uniform(0, 2 * np.pi))
drone *= 0.085 / 1.87
drone *= 1.0 + 0.25 * np.sin(2 * np.pi * tt / 23.0)
drone *= np.clip(tt / 25.0, 0, 1)                      # fade in
drone *= np.clip((TOTAL - tt) / 12.0, 0, 1)            # fade out
mix += drone

# a small room: convolve with a short synthetic decay, mixed low
ir_n = int(0.9 * SR)
ir = np.random.default_rng(SEED * 13).standard_normal(ir_n)
ir *= np.exp(-np.arange(ir_n) / (0.30 * SR))
spec = np.fft.rfft(ir)
f = np.fft.rfftfreq(ir_n, 1 / SR)
ir = np.fft.irfft(spec * np.exp(-f / 3500.0), ir_n)
ir /= np.sqrt(np.sum(ir ** 2))  # unit energy, so wet ~= dry in RMS
size = 1 << (int(np.ceil(np.log2(len(mix) + ir_n))))
wet = np.fft.irfft(np.fft.rfft(mix, size) * np.fft.rfft(ir, size), size)
mix = mix + 0.22 * wet[:len(mix)]

# master: normalize, breathe in, fade out
mix /= np.max(np.abs(mix)) / 0.71
fade_in = int(0.8 * SR)
mix[:fade_in] *= 0.5 - 0.5 * np.cos(np.pi * np.arange(fade_in) / fade_in)
fade_out = int(4.0 * SR)
mix[-fade_out:] *= 0.5 + 0.5 * np.cos(np.pi * np.arange(fade_out) / fade_out)

sf.write(HERE / "reedsong.flac", mix.astype(np.float32), SR,
         subtype="PCM_16")
sf.write(HERE / "reedsong.mp3", mix.astype(np.float32), SR)

# ------------------------------------------------------------- report

print(f"duration {len(mix)/SR:.1f}s  peak {np.max(np.abs(mix)):.3f}  "
      f"rms {np.sqrt(np.mean(mix**2)):.4f}")
print("\nthe ground (the circle of knowing):")
for title, f0 in GROUND_SEQ:
    d = degree(title)
    print(f"  {title:28s} {letters(title):2d} letters  mod7={d}  "
          f"{DEGREE_NAMES[d]:12s} {f0:7.2f} Hz")
print("\nthe flicker:")
for title in FLICKER:
    d = degree(title)
    print(f"  {title:28s} {letters(title):2d} letters  mod7={d}  "
          f"{DEGREE_NAMES[d]:12s} {freq(D5, title):7.2f} Hz")
print(f"\nthe ground's last cycle stops after: {CIRCLE[LAST_CYCLE_NOTES-1]}")
print(f"the last note sounded is: {FLICKER[1]} ({REALITY:.2f} Hz)")
