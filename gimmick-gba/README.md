# Gimmick! for GBA

A work-in-progress port of Sunsoft's *Gimmick!* (Famicom, 1992) to the Game Boy Advance. It is a
native port: the game's 6502 code is translated to C and compiled for the GBA, not run in an
emulator on the GBA, and the NES's graphics hardware is replaced by code that draws with the GBA's.

You bring your own copy of the Japanese *Gimmick!*. The build makes the GBA ROM from it, and the
repository holds none of the original game's code or graphics.

This hack is AI-assisted, using Claude.

## State

A proof of concept: stage 1 plays, with no sound yet. Code seen running in a recording is
translated, and anything else runs in a slower interpreter, so later stages may not hold full speed.

## Build it

Put `Gimmick! (Japan).nes` and the Linux build of [Mesen 2](https://www.mesen.ca/) (as `Mesen`) in
this folder. It also needs Python 3, gcc, and devkitARM.

```bash
python3 tools/record.py 6000
```

```bash
python3 tools/record.py --idle 4000
```

```bash
tools/check_host.sh
```

```bash
python3 tools/build_gba.py
```

That writes `out/gimmick.gba`. Open it in [mGBA](https://mgba.io/).

## How it is checked

- `tools/record.py` plays the NES game in Mesen and records RAM at every NMI, what code ran, and
  every value read from the pads.
- `tools/check_host.sh` translates the game, runs it on the PC with those pad values, and compares
  RAM with the recording (`tools/compare.py`). `tools/stepdiff.py` finds the first block that
  differs, from step logs of a frame on both sides.
- `python3 tools/build_gba.py --replay` builds a ROM that plays the recording on the GBA and checks
  RAM every frame. `python3 tools/run_gba.py` runs it in mGBA and prints the check and frame timing.

## How it works

- `tools/recomp.py` turns each basic block into a C function that returns the next PC. The blocks
  that ran most go in the GBA's fast internal RAM as ARM code, the rest stay in ROM as Thumb.
- `runtime/core.c` is the FME-7 mapper, the PPU's registers and the loop that runs blocks and takes
  interrupts. `runtime/gba.c` draws each frame from the NES's nametables and sprites. The game's
  status bar, which is a mid-frame split, has its own GBA background layer.
- The GBA's screen is 160 lines tall, and the NES playfield is 192, so the camera follows Yumetaro.
