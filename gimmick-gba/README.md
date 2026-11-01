# Gimmick! for GBA

A port of Sunsoft's *Gimmick!* (Famicom, 1992) to the Game Boy Advance. It is a native port: the
game's 6502 code is translated to C and compiled for the GBA, not run in an emulator on the GBA,
and the NES's graphics and sound hardware are replaced by code for the GBA's.

You bring your own copy of the Japanese *Gimmick!*. The build makes the GBA ROM from it, and the
repository holds none of the original game's code or graphics.

This port is AI-assisted, using Claude.

## Build it

Put `Gimmick! (Japan).nes` in this folder (either common dump), then:

```bash
python3 tools/build_gba.py
```

That writes `out/gimmick.gba`. Open it in [mGBA](https://mgba.io/), or put it on a flash cart. It
needs Python 3 and [devkitARM](https://devkitpro.org/)'s `gba-dev` group.

## Playing

The buttons are the NES's: A jumps, hold B to charge the star and let go to throw it, Start pauses
and Select does nothing. In mGBA's default keys that is X, Z, Enter and Backspace.

The GBA's screen is 160 lines tall and the NES playfield is 192, so the camera follows Yumetaro
up and down, and the title and cutscenes show the part with something on it.

## Known limits

- It has been run in mGBA, and not on a real GBA.
- Normal play takes about 70% of the GBA's time for a frame, and the busiest about 85%. Some single
  frames take more, up to about 140%, mostly where the NES itself runs long.
- A heavy frame can run over the GBA's time for a frame. Then that frame is not drawn and the next
  starts straight away. The next is always drawn, so under a sustained load the game slows, as it
  does on the NES, and the sound repeats. Loading a room can take a few frames.
- The sound runs on the NES's frame clock, so changes land at most a frame apart from the NES.
- A few things are simplified: a sprite that crosses a mid-frame graphics change uses the upper
  set of graphics, and a picture is only ever split in two.
- Code that no recording reached runs in an interpreter. It gives the same results, more slowly.

## How it works

- `tools/recomp.py` turns each basic block into C. The blocks that run most go in the GBA's fast
  internal RAM as ARM code, as one function that jumps straight between them. The rest stay in ROM
  as Thumb, and anything never seen running goes through an interpreter. `data/` says where code
  ran and how often: only addresses, so a build needs no recording.
- `runtime/core.c` is the FME-7 mapper, the PPU's registers and the loop that runs blocks and takes
  interrupts. `runtime/apu.c` mixes the NES's five sound channels and the Sunsoft 5B's three.
  `runtime/video.c` draws each frame from the NES's nametables and sprites. A split low on the
  screen is the status bar, on its own background layer. A higher one, like the title's logo over
  its scrolling ground, is one picture in two parts.

## How it is checked

```bash
python3 tools/record.py 6000
```

```bash
python3 tools/record.py --idle 4000
```

```bash
python3 tools/record.py --tour
```

These play the NES game in [Mesen 2](https://www.mesen.ca/) (put the Linux build at `./Mesen`) and
record RAM at every NMI, what code ran, and what the pads gave. `--tour` warps through every stage
and checkpoint, sweeps across each stage's map, clears each stage, and goes through the world map,
both endings and a game over (`tests/s_tour.lua`).

```bash
tools/check_host.sh out/trace_tour
```

This runs the translated game on a PC with the same inputs and compares all of RAM at every NMI
(`tools/compare.py`). Test builds count cycles exactly, and take each NMI at the instruction the
recording took it. `tools/stepdiff.py` finds the first block that differs.

| Tool | What it checks |
|---|---|
| `tools/build_gba.py --replay out/trace_tour`, then `tools/run_gba.py 1600` | The same replay on the GBA in mGBA, with RAM checked every frame |
| `tools/build_gba.py --replay --timing`, then `tools/run_gba.py` | How much of each frame the game, the drawing and the sound take in the build you play |
| `tools/compare_screens.py` | Every marked moment of the tour as the GBA would show it, beside Mesen's screenshot of that frame, on contact sheets in `out/screens/` |
| `tools/compare_sound.py` | The sound chips' state in Mesen against `runtime/apu.c`'s, frame by frame |
| `tools/record.py --audio 2600`, then `tools/compare_audio.py` | The sound itself: what each of Mesen's channels outputs, through Mesen's mixer formulas, against this port's, for loudness and spectrum |
| `tools/press_keys.py` | Runs the real build in mGBA and presses its keys |

## Credits

*Gimmick!* is © Sunsoft. The font on the title screen's notices is this port's own.
