#!/usr/bin/env python3
"""Compare this port's sound with Mesen's, channel by channel.

    python3 tools/record.py --audio 2600
    python3 tools/compare_audio.py

The recording holds what each of Mesen's channels outputs, sampled every few
instructions. This builds the sound from that with Mesen's own mixer formulas, renders
the same run on the PC build, and compares loudness and spectrum.
"""
import os
import subprocess

import numpy as np

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REF = os.path.join(REPO, "out", "audio_ref")
OUT = os.path.join(REPO, "out", "audio_cmp")
RATE = 18157
PER_FRAME = 304
FRAME_CYCLES = 29780.5
WINDOW = 2048
NAMES = ["pulse 1", "pulse 2", "triangle", "noise", "DPCM", "5B"]


def high_pass(x):
    """The same filter as runtime/apu.c."""
    out, level = np.zeros(len(x)), 0.0
    for i, v in enumerate(x):
        level += (v - level) / 32
        out[i] = v - level
    return out


def reference():
    """Each channel of Mesen's sound, on the same clock as the PC build's."""
    d = np.loadtxt(os.path.join(REF, "channels.txt"), dtype=np.int64)
    pos = (d[:, 0] / FRAME_CYCLES * PER_FRAME).astype(np.int64)
    n = pos[-1] + 1
    held = np.zeros((n, 6))
    at = np.searchsorted(pos, np.arange(n), side="right") - 1
    held[:, :6] = d[np.maximum(at, 0), 1:7]
    return held


def mesen_mix(c):
    """Mesen's mixer: two non-linear groups, and the 5B times 15."""
    s = c[:, 0] + c[:, 1]
    t = 3 * c[:, 2] + 2 * c[:, 3] + c[:, 4]
    with np.errstate(divide="ignore"):
        square = np.where(s > 0, 477600 / (8128 / np.maximum(s, 1) + 100), 0)
        tnd = np.where(t > 0, 818350 / (24329 / np.maximum(t, 1) + 100), 0)
    return square + tnd + 15 * c[:, 5]


def solo(c, i):
    z = np.zeros_like(c)
    z[:, i] = c[:, i]
    return mesen_mix(z)


def render(mask, frames):
    path = os.path.join(OUT, "mine_%d.raw" % mask)
    env = dict(os.environ, WAV=path, APU_ONLY=str(mask))
    subprocess.run([os.path.join(REPO, "out", "host"), os.path.join(REPO, "Gimmick! (Japan).nes"), REF, str(frames), "/dev/null"],
                   env=env, check=True, stderr=subprocess.DEVNULL)
    return np.fromfile(path, dtype=np.int8).astype(float)


def spectrum(x):
    frames = len(x) // WINDOW
    w = np.hanning(WINDOW)
    return np.array([np.abs(np.fft.rfft(x[i * WINDOW:(i + 1) * WINDOW] * w)) for i in range(frames)])


def similarity(a, b):
    n = min(len(a), len(b))
    sa, sb = spectrum(a[:n]), spectrum(b[:n])
    sa, sb = np.log1p(sa).ravel(), np.log1p(sb).ravel()
    return np.corrcoef(sa, sb)[0, 1]


def main():
    os.makedirs(OUT, exist_ok=True)
    frames = sum(1 for _ in open(os.path.join(REF, "cpu.txt")))
    c = reference()
    whole_ref = high_pass(mesen_mix(c))
    whole = render(0xFF, frames)
    n = min(len(whole), len(whole_ref))
    scale = whole[:n].std() / whole_ref[:n].std()
    print("whole mix: spectrum similarity %.3f, peak %d, clipped %.2f%%, rms %.1f" % (
        similarity(whole, whole_ref), np.abs(whole).max(), 100 * np.mean(np.abs(whole) >= 127), whole.std()))
    print("%-9s %8s %8s %6s %s" % ("channel", "Mesen", "mine", "ratio", "spectrum similarity"))
    for i, name in enumerate(NAMES):
        ref = high_pass(solo(c, i)) * scale
        mine = render(1 << i, frames)
        m = min(len(ref), len(mine))
        r, q = ref[:m].std(), mine[:m].std()
        print("%-9s %8.2f %8.2f %6.2f %.3f" % (name, r, q, q / r if r else 0, similarity(mine, ref) if r > 0.01 and q > 0.01 else 0))
    (whole_ref[:n] * scale).clip(-128, 127).astype(np.int8).tofile(os.path.join(OUT, "mesen.raw"))


if __name__ == "__main__":
    main()
