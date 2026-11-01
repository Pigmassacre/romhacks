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

**Sprites.** `nmi_work` sends them first thing in vblank, and the game's own `$4014` then does nothing. Late, they would
corrupt OAM, and they include the high table so that such damage cannot last. `convert_sprites` keeps to `spr_tmp`, as
it runs at the end of the main thread's frame, and a split's interrupt can land in it and use `tmp`.

**The order in vblank.** Everything does not fit, so `nmi_work` decides: sprites, palette, scroll, the game's tile
buffer, sprites' CHR pages, colours, then second-set pages. Anything written to VRAM after vblank is lost, so a copy
must not start where it cannot finish, and a line number from the next picture is not "early". `vram_flush` writes runs
and columns directly, as the game resends a column of 24 tiles every frame. The game's own calls then find little left.

**Fast ROM at `$C000`.** Every code bank has that window free, since the game's `$C000` holds only DPCM samples, so
code the game itself calls can go there and run faster than from RAM. `convert_oam` does: the more sprites, the more
it costs, where the NES only copies them, and that is what slows the game when the screen is busy.

**CHR pages.** The NES's bank switch is instant and a page here takes 12 lines of vblank, so the game's own
order, with CHR last, is usually too late. `top_pages` runs first in `nmi_work`, from what the game has at `$E1-$E8`:
sprites' pages, then the background's if no colours are waiting (`attr_work`), one page a frame, or two if there
is no tile buffer. Yumetaro's own page changes as Yumetaro animates, so this matters all the time. Only one stale page
is sure of being copied, so `spr_check` keeps sprites on any other off for that frame, rather than draw garbage.

**Behind the background, with parallax.** Colour 0 there is solid and the sky is not there, the reverse of what
such a sprite needs, so it would vanish in a pipe's mouth. So with parallax they all go in front (`spr_pri`).

**The portal.** It hides what comes out of it with the NES's limit of 8 sprites on a line: 16 blank sprites, tile
`$80` with attribute `$20`, in two stacks of 8, ahead of the others. The SNES has no such limit, so `spr_check` notes them
and `band_now` turns sprites off for those lines, by HDMA on TM.

**Splits take longer than on the NES.** A split changes scroll and then tiles, and the stubs for that take several
lines. So `split_early` changes tiles along with the scroll that came before them last frame. A handler's `$2005` just
before a `$2000` becomes `ppu_scroll_hold`, so that both apply at once and no line shows the wrong nametable.

**The status bar.** The game takes an FME-7 interrupt, counted in CPU cycles, and changes CHR pages and
scroll for what is below. The SNES interrupts on a line (`arm_irq`). Its handler takes much longer here,
so the interrupt comes 12 lines early, and what shows waits for the line (`wait_line`). CHR cannot be
copied during the picture, so a second tile set and second sprite tables hold what the last frame's
splits asked for (`load_page`), and the split flips to them.

## Parallax

Sky is a solid tile on the NES, and black outlines are colour 0, which the SNES would see through. BG1
is 16 colours in Mode 1 so both can work: in the versions of pages made by `build_parallax_pages`, colour
0 becomes solid colour 4 (the backdrop's colour) and sky tiles and the cloud tiles BG3 draws are blank. The rest
of the clouds' page stays, because it holds foreground too, such as the shadows under platforms. The sky's colour
becomes the backdrop's. The clouds are on BG3, at half the camera's speed (`bg2_now`). Their bank is the title
screen's rows, which meet at their ends and so loop: the tables are near the top of `tools/build.py`. Below the status bar's split BG3 goes off and the
backdrop goes back.

## The world map

The island is fixed nametable data. `tools/survey.py` captures it, and `build_mode7` makes a Mode 7 map
and tiles from it (129 tile and palette pairs). Mode 7 needs the first half of VRAM, so sprites move
to their second tables and everything is reloaded on the way out. `map_now` runs the arrival from
a table of scales, then sets the identity, at which it lines up with the sprites.

## Gimmick! 1.5, as options

`src/gimmick-1.5/` and `tests/gimmick-1.5/` are copies of that hack's source and tests, so this folder
builds alone. The source has lost its title screen and nothing else; a fix to one copy has to be made in the
other by hand. `assemble_15` in `tools/build.py` assembles it. Its code becomes bank `$20` and its far calls go
where they do there, in the fixed bank's dead block; its bigger ROM is left out. Its hooks in banks `$1D` and
`$1E` go through switches in `src/runtime.s` (`opt_jump` and so on): off runs what the game had there, on runs
1.5's routine. Hack and game then share the RAM 1.5 already keeps to.

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

From about 1 kHz a voice switches to a wave with fewer harmonics (`band_sample`, picked in `set_pitch`): the DSP has no
filter to speak of when it steps over samples, and a square's edges would fold back as scratchy noise.

Waves are short looped samples, and DPCM samples are converted to BRR at build time, at a third of their
rate to fit. `tools/spcasm.py` is a small assembler for the SPC700. The noise channel's short mode is a
sample too, as its 93 steps have a pitch. The 5B's envelope and noise are not handled: the game writes the
mixer's noise bits only rarely, and never sets an envelope volume.

A frame's registers are sent between messages `$1E` and `$1F`, and the driver does not read them in between: a
period is two registers, and half of a new one is a wildly wrong note for 4 ms. The 5B takes 32 clocks a step and
the period itself, where a pulse takes 16 and period + 1, so its voices are an octave below a pulse's with the same
number. The driver's sweep moves its own copy of a period, so a new note sends the period again even if the
game's value has not changed.

## What was found out along the way

- `$6000` is not cartridge RAM as `gimmick-1.5/docs/notes.md` says: FME-7 register 8 holds the stage number
  with bit 6 clear, which is ROM. Nothing writes there.
- The game's `$44` is a copy of `$2000` that only its NMI sets, and the NMI writes it back. On the SNES,
  turning on NMI during vblank brings one at once, which would turn NMI off again, so the stub sets `$44`.
- The status bar's icons are sprites, on CHR page `$1B`, switched in by the second interrupt.
