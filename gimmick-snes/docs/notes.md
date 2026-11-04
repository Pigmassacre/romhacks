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
  access to hardware is 3 bytes, and so is a `JSR`: it becomes one, to a stub in fast ROM at `$C000`
  (see below), which every ROM bank can reach. `$4016` and `$4017` would need no change: the SNES's
  pads are read the same way, at the same addresses. Interrupts reach the game by `JML` through a pointer
  updated with each bank switch.

An interrupt can land inside a stub, so a stub must leave things as an interrupt would expect. `tmp`
is for the main thread and `itmp` for code interrupts can reach; `nmi_work` saves `tmp`.

## The picture

The NES's vblank is 20 lines and each `sta $2007` is 4 cycles; the SNES's is 37 lines, but a stub
takes far longer than a store. Anything late is lost, or worse, so the slow parts moved:

- `frame_done` replaces `lda #$AC / sta $F0`, where the game finishes a frame and waits. Sprites are
  converted there, and with the picture off, CHR pages are loaded there. The main thread may be
  part way through writing a map at other times, and a DMA would move the VRAM address under it.
- `vram_flush` and `chr_all` replace the game's `$F3D3` and `$F06B`, which write its VRAM buffer and
  CHR banks. `vram_flush` sends long runs by DMA: as a stage starts or Yumetaro comes back, the game
  draws the whole screen this way with the picture off.
- `clear_nt` replaces `$F32E`, which fills a nametable and its colours as a screen starts: through
  the stubs that took 4 frames longer than on the NES, and two DMAs do it with the picture off.
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

**Sprites are written directly.** NES sprites are a different shape and format, and converting a whole list every frame
was the biggest cost that grew with what is on screen, where the NES only copies them. So the game's general sprite routine, `$F4CA` and its
mirrored twin `$F52F`, is replaced: `spr_body` reads the same tables and writes the SNES's
sprites at once, field by field, and marks `spr_flag`. Tiles for the second table and the portal's blanks take the slow way. `convert_oam` then only has to deal with slots without that mark: what the game's
other routines wrote, such as the status bar's sprites and the portal's blanks, and empty slots. It runs after `frame_done`
says the frame is done, in time the game would spend waiting. `$0200` no longer holds sprites that `spr_body`
wrote, so anything reading them from it sees old values. `TEST_SPR_SHADOW=1 python3 tools/build.py` makes a ROM that still fills it in,
to compare the two.

**Sprites keep their order.** The game reverses the sprites' order every other frame, to spread out the flicker of the
NES's 8 sprites on a line. The SNES has no such limit, and overlapping sprites would swap in front and behind 30
times a second, so `ORDER_FIXED` in `tools/build.py` makes every frame an even one for that.

**Fast ROM at `$C000`.** Every code bank has that window free, since the game's `$C000` holds only DPCM samples, so
the port's code goes there (`ROMC`) and runs faster than from RAM: a byte of fast ROM takes 6 master clocks and one
of RAM 8. Bank 0 has a copy too, at its own `$C000`, for the interrupts' code, which runs there, and for
`jmp (abs)`, which reads its pointer from bank 0. A bank switch carries on in the same code in the new bank. Only
`fme_6000`, which changes its own addresses, stays in RAM at `$1000` (`WCODE`). The stubs were a third of every
frame when they ran from RAM.

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

**hblank is short.** About 33 cycles from RAM, and a write after that spoils the first pixels of the line, as old tiles
at the status bar's top left showed. So `mid_scroll` and `show_split_set` work out their values first and write them straight after the wait.

**The status bar.** The game takes an FME-7 interrupt, counted in CPU cycles, and changes CHR pages and
scroll for what is below. The SNES interrupts on a line (`arm_irq`). Its handler takes much longer here,
so the interrupt comes 12 lines early, and what shows waits for the line (`wait_line`). CHR cannot be
copied during the picture, so a second tile set and second sprite tables hold what the last frame's
splits asked for (`load_page`), and the split flips to them.

## Parallax and layers

The picture is Mode 0, for its order of layers, front to back: sprites in front of the background, BG1, sprites behind
the background, BG3, BG4. BG2 is above them all, for the title's notices and menu. On the NES a sprite behind the
background shows through colour 0 and is hidden by the rest, so with sky behind everything colour 0 has to be black over
the sky and yet behind that sprite: only a layer of its own can do that.

- **BG2** has the title's additions: SUPER in the logo, on white over its small print (`src/logo_super.txt`, at
  most as many different tiles as BG2 has left; `tools/super_edit.py` counts them). It has the logo's four
  colours in two palettes, 4 with the dark grey and 6 with the light, so each tile has one of the greys; OPTIONS under CONTINUE in
  the menu's own font and colours, and the warning on a white plate like the logo's. That font is the options menu's
  too, white on black in palette 2 and black on white in palette 3. BG2 scrolls down 6 lines on the title
  (`NOTICE_DOWN`), so that OPTIONS is as far under CONTINUE as that is under START.
- **BG1** is the NES's background, 2 bits a pixel as it is on the NES, in 4 palettes of 4.
- **BG3** uses BG1's map, with its own tiles: colour 1, always the backdrop's colour, where the NES has colour 0.
- **BG4** is sky and clouds, at half the camera's speed (`bg2_now`). The bank of cloud is the title screen's rows, which meet at their ends and so loop: the tables are near the top of `tools/build.py`.

BG3 and BG4 are on only for stages with clouds, and go off at the status bar's split, where the backdrop, the game's own,
shows again. In the versions of pages made by `build_parallax_pages` the sky and the cloud tiles BG4 draws are blank in both BG1 and BG3,
and slopes lose the white of the clouds behind them. A page is 1 KB, or 2 KB with its BG3 tiles.

The BG scroll registers share one latch, as the Mode 7 ones do: each gets both its bytes in turn.

## The world map

The island is fixed nametable data. `tools/survey.py` captures it, and `build_mode7` makes a Mode 7 map
and tiles from it (129 tile and palette pairs). Mode 7 needs the first half of VRAM, so sprites move
to their second tables and everything is reloaded on the way out; `dma_bg_page` refuses while the island
is up, as the NMI that brings it in can land between a page's check for time and its copy.

The map is a plane seen at a slant. HDMA writes M7A and M7Y on every line, with M7B, M7C and M7D at 0, so
that each line shows one row of the picture at its own scale. `plane_tables` in `tools/build.py` makes a
pair of tables for each frame of the island's arrival, as it grows in from far away, and a M7Y table
for each step of the camera's pan before the last stage; `map_now` points the two HDMA channels at the
frame's. Once it has arrived, `plane_sprites` puts the game's sprites on the plane at their own size:
sprites that come one after another and touch are one group, which moves to where its bottom edge lands
(`PlaneDY` and `PlaneE`). It runs after the frame counts as done, so the game never waits for it, and the
NMI leaves last frame's sprites up until it is finished. It eases the pan too, which reaches `map_now`
only with the sprites done, so that they and the island move together.

The first screen, who made the port and the warning, is `splash` in `src/boot.s`, before the game
starts. Its map is the overlay's last 2 KB, put at VRAM word 0 and cleared after.

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

`pad_all` takes the place of the game's read of both pads, `$F2CB`, to keep a copy for the menu and to show the
game nothing while the menu is open, nor after it closes until the pad is let go. `title_menu` takes the place
of the game's title cursor at `$1B:813C`: `$05` goes to 2 for OPTIONS, which flashes as START and CONTINUE do,
and Start there opens the menu. `pad_all` also keeps the SNES's A, which the game never sees but the menu uses. `menu_tick` runs the menu from the NMI, on BG2. The choices last until
the power goes off: cartridge RAM holds the stage's tables, so there is nowhere to save them.

## Sound

The game's own sound driver runs on the 65816 and writes the NES's registers, which the stubs keep a copy
of. `sound_hook`, right after that in the NMI, sends what changed to `src/sound.spc`, which keeps the
NES's sequencer going (length, envelope, sweep, linear counter) and sets the DSP's voices. There are
exactly enough: pulse, pulse, triangle, noise, DPCM and three 5B squares.

From about 1 kHz a voice switches to a wave with fewer harmonics (`band_sample`, picked in `set_pitch`): the DSP has no
filter to speak of when it steps over samples, and a square's edges would fold back as scratchy noise.

Waves are short looped samples, and DPCM samples are converted to BRR at build time, at a third of their
rate to fit. Which samples there are comes from the game's own table, at `$FD68` in the PRG (`DPCM_TABLE`): the
survey's play-through hears only some of them.

No sample has its lowest value, -8 at the top shift, three times in a row. The DSP's Gaussian interpolation adds
three of its four points with no clamp, and its weights come to a little over 1 at some positions, so three of
those wrap round to the highest value: a full-scale pop, once a cycle at some pitches, which made the pulses and
the 5B crackle. The squares go from +7 to -7, and DPCM is scaled to stay clear of it. The DSP also clamps as it
adds up the voices, before the main volume, so their volumes are low enough that all of them together stay
under that, and the main volume is at its highest to make up for it.

A DPCM sample stops by fading out, with GAIN, in 2 ms, and a new one starts once the old one has (`dpcm_key`),
as a cut clicks where the NES's level stays put. Key off was missed: the DSP looks at it every 64 cycles, and the
driver let go of it sooner, so a stopped sample played on, as when the intro is skipped. `tools/spcasm.py` is a small assembler for the SPC700. The noise channel's short mode is a
sample too, as its 93 steps have a pitch. The 5B's envelope and noise are not handled: the game writes the
mixer's noise bits only rarely, and never sets an envelope volume.

A frame's registers are sent between messages `$1E` and `$1F`, and the driver does not read them in between: a
period is two registers, and half of a new one is a wildly wrong note for 4 ms. A message holds two registers,
in the four ports, as the runtime waits for each answer, in the NMI; and the driver's update of its voices
stops for a message, as the NMI would wait for all of it, up to 15% of a frame. `$1F` runs it again in full. The 5B takes 32 clocks a step and
the period itself, where a pulse takes 16 and period + 1, so its voices are an octave below a pulse's with the same
number. The driver's sweep moves its own copy of a period, so a new note sends the period again even if the
game's value has not changed.

## Speed

The NES's slowdown is not wanted here: where the NES lags, the port should not. So the frame's work, the game's and
the port's, has to fit in a frame with room to spare. `tools/lag.py` counts the frames lost at each checkpoint and
in the first boss's room, on both machines, and how many lines of the frame the work took, from the start of
vblank to where the game says the frame is done. `tools/prof.py` adds up where the time went, by routine, split
into the NMI, the status bar's interrupt, the game's frame and the wait after it.

The game's own code is little of it. In a busy frame the NMI alone took a third, nearly all of it the port's
stubs, which ran from RAM; they are in fast ROM now. Besides that:

- **The pads.** The game reads both pads until two reads agree, against the NES's DPCM, a bit at a time: 32 reads
  through a stub, 3% of a frame. `pad_all` replaces the whole read with what the SNES reads by itself at the
  start of vblank (`NMITIMEN` bit 0, which every write of it keeps on).
- **The SPC700.** Each message waited for the driver to answer, and when it was updating its voices that took up
  to 15% of a frame. Now that update stops for a message, and each message carries two registers.
- **Bank switches.** The game's own two routines for `$8000` and `$A000`, `$F051` and `$F05E`, are done whole
  (`sw_bank8`, `sw_bankA`), not as two stubs and a jump table, and a switch to the bank already there does not
  jump.

That took the busiest frames found from all of the frame to about 92% of it, and the median frame in the first
boss's room from 64% to 54%. The first boss's arrival lost frames the NES did not, and no longer does. What is left is
mostly the DMAs for sprites and CHR pages, the game's sound driver, and `spr_body`.

## What was found out along the way

- `$6000` is not cartridge RAM as `gimmick-1.5/docs/notes.md` says: FME-7 register 8 holds the stage number
  with bit 6 clear, which is ROM. Nothing writes there.
- The game's `$44` is a copy of `$2000` that only its NMI sets, and the NMI writes it back. On the SNES,
  turning on NMI during vblank brings one at once, which would turn NMI off again, so the stub sets `$44`.
- The status bar's icons are sprites, on CHR page `$1B`, switched in by the second interrupt.
- `$2B` is Yumetaro's most health. A test that keeps `$346` above it, as at 3 with `$2B` at 2, sends the
  status bar's loop at `$E3E2` round 256 times a frame, writing over the sprites: the NES then lags in every
  scene. `tests/s_lag.lua` keeps it at `$2B`.
