#!/usr/bin/env python3
"""Generates the NapStop alarm sounds (spec T16, PO Q3 = A) as 16-bit mono WAV loops.

Synthesised from sine partials only: no recording, no sample library. The output is
dedicated to the public domain (CC0 1.0), see docs/third_party/alarm_sounds.md.
Deterministic: running it again gives byte-identical files.

  python3 tools/alarm_sounds/generate.py            # writes app/android/app/src/main/res/raw/alarm_*.wav
  python3 tools/alarm_sounds/generate.py --out DIR
"""
import argparse
import math
import os
import struct
import wave

RATE = 22050


def envelope(t, length, attack=0.02, release=0.08):
    """Linear attack / release so a loop never clicks."""
    if t < attack:
        return t / attack
    if t > length - release:
        return max(0.0, (length - t) / release)
    return 1.0


def tone(length, partials, attack=0.02, release=0.08, decay=None):
    """partials: list of (frequency Hz, amplitude). decay: exponential decay rate (1/s) or None."""
    n = int(length * RATE)
    out = []
    for i in range(n):
        t = i / RATE
        v = sum(a * math.sin(2 * math.pi * f * t) for f, a in partials)
        e = envelope(t, length, attack, release)
        if decay is not None:
            e *= math.exp(-decay * t)
        out.append(v * e)
    return out


def silence(length):
    return [0.0] * int(length * RATE)


def normalise(samples, peak=0.85):
    m = max(abs(s) for s in samples) or 1.0
    return [s / m * peak for s in samples]


def horn():
    # "Còi tàu": a low three-note chord (like a train horn, F#4-A4-C#5 lowered an octave) with
    # odd harmonics, two blasts per loop.
    chord = []
    for f in (185.0, 220.0, 277.2):
        chord += [(f, 1.0), (f * 2, 0.45), (f * 3, 0.3), (f * 5, 0.12)]
    blast = tone(0.9, chord, attack=0.05, release=0.12)
    return normalise(blast + silence(0.25) + blast + silence(0.6))


def bell():
    # "Chuông": struck bell partials (inharmonic ratios), two strikes per loop.
    partials = [(660.0, 1.0), (660.0 * 2.0, 0.5), (660.0 * 2.76, 0.35), (660.0 * 5.4, 0.15)]
    strike = tone(1.0, partials, attack=0.005, release=0.1, decay=3.0)
    return normalise(strike + strike)


def beep():
    # "Bíp": four short 1 kHz beeps, then a pause.
    b = tone(0.12, [(1000.0, 1.0), (2000.0, 0.2)], attack=0.005, release=0.02)
    gap = silence(0.08)
    return normalise((b + gap) * 4 + silence(0.6))


def write(path, samples):
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1.0, min(1.0, s)) * 32767)) for s in samples))


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    default_out = os.path.normpath(os.path.join(here, "..", "..", "app", "android", "app", "src", "main", "res", "raw"))
    p = argparse.ArgumentParser()
    p.add_argument("--out", default=default_out)
    args = p.parse_args()
    os.makedirs(args.out, exist_ok=True)
    for name, gen in (("alarm_horn", horn), ("alarm_bell", bell), ("alarm_beep", beep)):
        path = os.path.join(args.out, name + ".wav")
        write(path, gen())
        print(path, os.path.getsize(path), "bytes")


if __name__ == "__main__":
    main()
