# How the port works

## The code

A 65816 in emulation mode is a 6502 with a few more instructions, and its stack, zero page and
registers behave the same. So the game's code runs as it is, from the same addresses, at about
1.5 to 2 times the speed. The master clock is the NES's, so a frame is the same length.

- **Memory.** Banks `$A0-$BF` of a HiROM cartridge have RAM at `$0000-$1FFF`, the SNES's registers
  above that, cartridge RAM at `$6000-$7FFF` and 32 KB of ROM at `$8000`. So the NES's addresses
  mean almost the same thing already.
- **Bank switching.** The SNES has no mapper, so each ROM bank holds one mapping of the FME-7: the NES
  banks shown at `$8000` and `$A000`, then bank `$0F` and the fixed bank. A bank switch jumps to
  the same address in another ROM bank. `tools/survey.py` records which mappings occur and what each
  uses, and `plan_banks` in `tools/build.py` shares ROM banks between mappings that do not conflict:
  15 banks cover all 50 of them. The `$C000` window only holds DPCM samples, which the CPU never reads.
- **`$6000`.** The game maps a ROM bank here, the stage's tile tables, once per stage. The handler copies
  it to cartridge RAM.
- **Hardware.** `find_patches` decodes everything reachable from what ran in the survey. Each `abs`
  access to hardware is 3 bytes, and so is a `JSR`: it becomes one, to a stub in RAM at `$0800-$1FDF`,
  which the NES game does not use and every ROM bank can reach. `$4016` and `$4017` need no change:
  the SNES's pads are read the same way, at the same addresses. Interrupts reach the game by `JML` through
  a pointer updated with each bank switch.

An interrupt can land inside a stub, so a stub must leave things as an interrupt would expect. `tmp`
is for the main thread and `itmp` for code interrupts can reach; `nmi_work` saves `tmp`.

## The picture

The NES's vblank is 20 lines and each `sta $2007` is 4 cycles; the SNES's is 37 lines, but a stub
takes far longer than a store. Anything late is lost, or worse, so the slow parts moved:

- `frame_done` replaces `lda #$AC / sta $F0`, where the game finishes a frame and waits. Sprites are
  converted there, and with the picture off, CHR pages are loaded there. The main thread may be
  part way through writing a map at other times, and a DMA would move the VRAM address under it.
- `vram_flush` and `chr_all` replace the game's `$F3D3` and `$F06B`, which write its VRAM buffer and
  CHR banks.
- `scroll_now` sets the scroll at the very start of vblank from what the game has decided at `$FC-$FF`,
  because the game's own writes come after vblank on a busy frame.
- Attribute bytes change the palette of 16 map entries each, so they queue up (`attr_work`).
- A run of tiles goes straight to VRAM with no look at `v` (`plan_run`, `ppu_data_a`).

NES sprites are 8x16, which the SNES lacks: each is two 8x8 sprites, keeping its place in the order.
A tile row can wrap at line 240 on the NES; the SNES's map has 2 more rows there, so an HDMA table adds
16 to the vertical scroll where the picture crosses them.

**The status bar.** The game takes an FME-7 interrupt, counted in CPU cycles, and changes CHR pages and
scroll for what is below. The SNES interrupts on a line (`arm_irq`). Its handler takes much longer here,
so the interrupt comes 12 lines early, and what shows waits for the line (`wait_line`). CHR cannot be
copied during the picture, so a second tile set and second sprite tables hold what the last frame's
splits asked for (`load_page`), and the split flips to them.

## Parallax

Sky is a solid tile on the NES, and black outlines are colour 0, which the SNES would see through. BG1
is 16 colours in Mode 1 so both can work: in the versions of pages made by `build_parallax_pages`, colour
0 becomes solid colour 4 (the backdrop's colour) and sky tiles and the clouds' page are blank. The sky's colour
becomes the backdrop's. The clouds are on BG3, at half the camera's speed (`bg2_now`), arranged as in the
stages: the tables are near the top of `tools/build.py`. Below the status bar's split BG3 goes off and the
backdrop goes back.

## The world map

The island is fixed nametable data. `tools/survey.py` captures it, and `build_mode7` makes a Mode 7 map
and tiles from it (129 tile and palette pairs). Mode 7 needs the first half of VRAM, so sprites move
to their second tables and everything is reloaded on the way out. `map_now` runs the arrival from
a table of matrices, then sets the identity, at which it lines up with the sprites.

## Gimmick! 1.5, as options

`assemble_15` in `tools/build.py` assembles `../gimmick-1.5/src/` as it is. Its code becomes bank `$20`
and its far calls go where they do there, in the fixed bank's dead block; its logo and bigger ROM are left
out. Its hooks in banks `$1D` and `$1E` go through switches in `src/runtime.s` (`opt_jump` and so on): off
runs what the game had there, on runs 1.5's routine. Hack and game then share the RAM 1.5 already keeps to.

Coyote time, buffering and Select's tap toggle are one routine, `JumpCheck`, so `opt_jump` keeps what is off
from happening: an old stamp for the floor, no memory of the press, no Select bit. With all three off it does not
call the routine at all.

`pad_read` takes the place of the game's read of the first pad, to keep a copy for the menu and to show the
game nothing while the menu is open. `menu_tick` runs the menu from the NMI, on BG3. The choices last until
the power goes off: cartridge RAM holds the stage's tables, so there is nowhere to save them.

## Sound

The game's own sound driver runs on the 65816 and writes the NES's registers, which the stubs keep a copy
of. `sound_hook`, right after that in the NMI, sends what changed to `src/sound.spc`, which keeps the
NES's sequencer going (length, envelope, sweep, linear counter) and sets the DSP's voices. There are
exactly enough: pulse, pulse, triangle, noise, DPCM and three 5B squares.

Waves are short looped samples, and DPCM samples are converted to BRR at build time, at a third of their
rate to fit. `tools/spcasm.py` is a small assembler for the SPC700. Not done: the noise channel's short
mode sounds like plain noise, and the 5B's envelope and noise are unused by this game's music.

## What was found out along the way

- `$6000` is not cartridge RAM as `gimmick-1.5/docs/notes.md` says: FME-7 register 8 holds the stage number
  with bit 6 clear, which is ROM. Nothing writes there.
- The game's `$44` is a copy of `$2000` that only its NMI sets, and the NMI writes it back. On the SNES,
  turning on NMI during vblank brings one at once, which would turn NMI off again, so the stub sets `$44`.
- The status bar's icons are sprites, on CHR page `$1B`, switched in by the second interrupt.
