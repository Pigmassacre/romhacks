# Gimmick! for SNES

A port of Sunsoft's *Gimmick!* (Famicom, 1992) to the Super Nintendo. It is a native port: the
game's own 6502 code runs directly on the SNES's 65816, and only what touches NES hardware is
replaced. It runs the whole game, with its sound, at full speed.

And since it is on a SNES now, three things the original could not do:

- **Parallax scrolling.** The clouds in stages 1, 2 and 4 are on their own layer, behind the
  stage, at half its speed.
- **The world map in Mode 7.** The island spins in from far away when the map opens, then settles
  to the same picture as the original.
- **Gimmick! 1.5's features, as options.** Press Select on the title screen for star recall,
  skipping stones, tap to summon, coyote time and jump buffering, each on or off. They start off, so
  the game plays as it always did. See [Gimmick! 1.5](../gimmick-1.5/) for what each one does.

You bring your own copy of the Japanese *Gimmick!*. The build makes the SNES ROM from it, and the
repository holds none of the original game's code, graphics or sound.

This hack is AI-assisted, using Claude.

## Build it

Put `Gimmick! (Japan).nes` and the Linux build of [Mesen 2](https://www.mesen.ca/) (as `Mesen`) in
this folder. It also needs Python 3 with Pillow, [cc65](https://cc65.github.io/) (`ca65`, `ld65`), and
loopy's asm6 at `tools/asm6`, which assembles Gimmick! 1.5's source from `../gimmick-1.5/src/`.

```bash
python3 tools/survey.py
```

```bash
python3 tools/build.py
```

The first plays the game in Mesen once, which takes a few minutes, to see what the code and sound
do. The second writes `out/gimmick.sfc`. It needs an accurate emulator or real hardware that can
map a 4 MB ROM with cartridge RAM (HiROM). It has run in Mesen 2 and bsnes; it has not been tried
on real hardware.

On the pad, B is the NES's A (jump) and Y is the NES's B (star): the same places on the controller.

## How it is checked

Each tool plays both machines with the same buttons, in Mesen.

- `tools/ramdiff.py` compares all the game's RAM, frame by frame. The game runs in step with the NES.
- `tools/ntdiff.py` compares the NES's nametables and palettes with the SNES's map at the same frame.
- `tools/tour.py` warps through every checkpoint of every stage, the ending and a game over, taking
  screenshots and nametables on both, and `tools/tourdiff.py` and `tools/tourmontage.py` compare them.
- `tools/sounddiff.py` compares each sound channel with its DSP voice.
- `tools/test15.py` runs Gimmick! 1.5's own tests here, with the options off (they expect the original
  game) and on (they expect 1.5).

`tools/shots.py` and `tools/montage.py` take and pair screenshots at given frames, and
`TEST_AUTOPLAY=1 python3 tools/build.py` makes a ROM that presses its own buttons, for emulators
without a script. [docs/notes.md](docs/notes.md) has how it works.

## Credits

*Gimmick!* is © Sunsoft. Mesen is by Sour. cc65 is by its contributors.
