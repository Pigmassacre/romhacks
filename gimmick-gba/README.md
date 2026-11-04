# Gimmick! Advance

A port of Sunsoft's *Gimmick!* (Famicom, 1992) to the Game Boy Advance. It is a native port: the
game's 6502 code is translated to C and compiled for the GBA, not run in an emulator on the GBA,
and the NES's graphics and sound hardware are replaced by code for the GBA's.

You bring your own copy of the Japanese *Gimmick!*. The build makes the GBA ROM from it, and the
repository holds none of the original game's code or graphics.

This port is AI-assisted, using Claude.

## Build it

Put `Gimmick! (Japan).nes` in this folder (either common dump) and loopy's asm6 at `tools/asm6`,
for Gimmick! 1.5's source in `src/gimmick-1.5/`, then:

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

The title screen says ADVANCE in the logo's bar, where the original has its name in katakana.
Before the game's own SUNSOFT PRESENTS comes a screen of the port's own, saying who made it and
that it is AI slop; Start or A skips it. The title keeps the warning above the logo, and has a
third entry, OPTIONS, under START and CONTINUE. Select, up and down move between them. The logo
sits higher on the screen than before, and the three entries 8 lines closer to it than on the NES,
to make room for both on the GBA's shorter screen.

**Parallax clouds.** In stages 1, 2 and 4 the sky and clouds are on a layer of their own,
behind the stage, at half its speed, as in the SNES port.

**The world map in Mode 7.** The map is a plane seen at a slant, as in Yoshi's Island: the
island lies on the GBA's affine layer, its far edge smaller than its near one. It grows in from
far away when the map opens and stays tilted while the map is up. The ohagis, flags, clouds and
the ship stand up on it at their own size, where their feet are, the nearer ones in front.
Before the last stage the camera moves up the map, to the tower and the airship that flies up
past it.

**Gimmick! 1.5's features, as options.** Choose OPTIONS on the title screen, with Start or A,
for star recall, water skipping, tap to summon, coyote time and jump buffering. Up and down pick
one, A or left and right switch it, and Start, Select or B goes back. They start off, so the game plays as it always did, and
the cartridge's save memory keeps them. See [Gimmick! 1.5](../gimmick-1.5/) for what each one does.

## Known limits

- It has been run in mGBA, and not on a real GBA.
- Normal play takes about 70% of the GBA's time for a frame, and the busiest about 85%. With all
  of Gimmick! 1.5's options on it takes about 80%, as their code is not in fast RAM. Some single
  frames take more, up to about 140%, mostly where the NES itself runs long.
- It has no slowdown where the NES has it: when the game's work for a frame runs past vblank,
  vblank waits for it, by up to a frame, instead of the game losing that frame as on the NES.
  But a heavy frame can still run over the GBA's own time for a frame. Then that frame is not
  drawn and the next starts straight away. The next is always drawn, so under a sustained load
  the game slows and the sound repeats. Loading a room can take a few frames.
- The sound runs on the NES's frame clock, so changes land at most a frame apart from the NES.
- A few things are simplified: a sprite that crosses a mid-frame graphics change uses the upper
  set of graphics, and a picture is only ever split in two.
- Code that no recording reached runs in an interpreter. It gives the same results, more slowly.

## How it works

- `tools/recomp.py` turns each basic block into C. The blocks that run most go in the GBA's fast
  internal RAM, as one function that jumps straight between them, with the 6502's registers and
  flags in its own variables: the compiler keeps them in the GBA's registers where it can, and
  skips flags nothing reads. The rest stay in ROM, and anything never seen running goes through an
  interpreter. Both are Thumb code, which is about half the size of ARM, so more fits. A block in ROM that
  goes on to another of its bank's, or the fixed bank's, names it, and the dispatcher calls that
  one straight away instead of looking it up. `data/` says where code
  ran and how often: only addresses, so a build needs no recording.
  Fast RAM is shared with the stack, and how much the hot code takes is only estimated when it
  is picked: `tools/build_gba.py` shrinks it until 1.5 KB is left for the stack. Test builds mark
  that space at start-up, and `tools/run_gba.py` reports how much of it the stack never reached.
- `tools/parallax.py` makes the game's tiles into the GBA's, with versions of the cloud stages'
  pages whose sky and clouds are blank, and a mask of each page: the sky's colour where the NES
  shows its colour 0 outside the sky, on a layer between the stage and the clouds. Sprites behind
  the background go between the stage and the mask, where the NES shows them.
- The world map's arrival builds the island's tiles from the NES's nametable when it opens: the
  affine layer has 8-bit tiles and one byte a cell, so each tile and palette pair becomes a tile.
  Each line's scale and place on the picture comes from a table that an HBlank DMA copies into
  the affine registers, set up again at every VBlank. Sprites that touch are one thing, placed by
  where its bottom edge lands on the plane.
- Gimmick! 1.5's code goes in a bank after the game's, and its far calls in the fixed bank's dead
  block, as in 1.5 itself. Each of its five hooks, a JSR to a far call, is a switch at the start of
  the block there: with the options it answers to off, the game's own code runs, cycle for cycle.
  `src/gimmick-1.5/` is a copy of that hack's source without its title screen: a fix to one copy
  has to be made in the other by hand.
- `runtime/core.c` is the FME-7 mapper, the PPU's registers and the loop that runs blocks and takes
  interrupts. `runtime/apu.c` mixes the NES's five sound channels and the Sunsoft 5B's three.
  `runtime/video.c` draws each frame from the NES's nametables and sprites. A split low on the
  screen is the status bar, on its own background layer, with its own sprites. A higher one, like the title's logo over
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

```bash
python3 tools/record.py --boss 2600
```

```bash
python3 tools/record.py --crowd 3000
```

```bash
python3 tools/record.py --15 6000
```

These play the NES game in [Mesen 2](https://www.mesen.ca/) (put the Linux build at `./Mesen`) and
record RAM at every NMI, what code ran, and what the pads gave. `--tour` warps through every stage
and checkpoint, sweeps across each stage's map, clears each stage, and goes through the world map,
both endings and a game over (`tests/s_tour.lua`). `--boss` fights a crowd of ohagis in the first stage,
the heaviest frames found so far (`tests/s_boss.lua`), and its code counts 20 times over when the
translator picks what goes in fast RAM. `--crowd` stands still in the boss's room while it
throws (`tests/s_crowd.lua`): with nothing pressed, the game plays the same without the NES's
slowdown, so `--timing --no-slowdown` can time the build you play there. `--15` plays the default run on a NES ROM with all of 1.5 on
(`out/gen/gimmick-1.5.nes`), and the PC build replays it with `OPTIONS=31` set: every byte of RAM
should match there too.

```bash
tools/check_host.sh out/trace_tour
```

This runs the translated game on a PC with the same inputs and compares all of RAM at every NMI
(`tools/compare.py`). Test builds count cycles exactly, and take each NMI at the instruction the
recording took it. `tools/stepdiff.py` finds the first block that differs.

| Tool | What it checks |
|---|---|
| `tools/build_gba.py --replay out/trace_tour`, then `tools/run_gba.py 1600` | The same replay on the GBA in mGBA, with RAM checked every frame |
| `tools/build_gba.py --replay --timing`, then `tools/run_gba.py` | How much of each frame the game, the drawing and the sound take in the build you play, with the NES's slowdown kept so that the recording plays the same; and how much of the stack's room was never used |
| `tools/compare_screens.py` | Every marked moment of the tour as the GBA would show it, beside Mesen's screenshot of that frame, on contact sheets in `out/screens/` |
| `tools/compare_sound.py` | The sound chips' state in Mesen against `runtime/apu.c`'s, frame by frame |
| `tools/record.py --audio 2600`, then `tools/compare_audio.py` | The sound itself: what each of Mesen's channels outputs, through Mesen's mixer formulas, against this port's, for loudness and spectrum |
| `tools/press_keys.py` | Runs the real build in mGBA and presses its keys |

## Credits

*Gimmick!* is © Sunsoft. The title screen's notices and ADVANCE are in the game's own menu font,
with the letters it lacks drawn to match.
