# Notes on the Gimmick! (J) ROM

Findings from making Gimmick! 1.5 that are not in smb3-gimmick's
[notes on the ROM](../../smb3-gimmick/docs/gimmick-notes.md) or its [physics guide](../../smb3-gimmick/docs/yumetaro-physics-guide.md). Addresses are CPU
addresses; `1D:8469` means bank `$1D` mapped where the game maps it.

## Banks during play

- `$8000`: switched per task. Bank `$1E` (Yumetaro), `$1D` (the star), `$10` (objects).
- `$A000`: bank `$11` for the whole stage. The sound driver maps song banks here during NMI,
  and NMI then restores `$A000` from the shadow `$41`.
- `$C000`: bank `$0F` (DPCM samples), never switched.
- `$E000`: the fixed bank, `$1F`.
- `$6000-$7FFF`: cartridge RAM (the map and the tile tables).

The FME-7 always maps the last 8 KB bank at `$E000`, and it can address 512 KB of PRG. So the
ROM can grow to 64 banks if the fixed bank moves to `$3F`. Nothing in the game writes a bank
number above `$1F`.

NMI and IRQ both restore the FME-7 command register from `$3F`, and NMI restores the `$8000` and
`$A000` banks from `$40`/`$41`. Code that switches a bank must write the shadow before the
register, as `$F051`/`$F05E` do.

## The disabled debug block (`$E271-$E2D4`)

`$E26D` is `lda #0 / beq $E2D5`, so this code never runs. It is the developers' cheats:
Select refills health, and controller 2 A+B adds a life. After that comes code for controller
2 B (next stage: `inc $1B`, `jmp $E0EE`, with A held skipping the world map) and the d-pad
(restart at checkpoint 0-3: `$1C`, `jmp $E152`), but even with the block enabled nothing reaches
it: four NOPs at `$E287` replaced whatever led there.

Nothing jumps into it. The two `$E2xx` references elsewhere (`B2_0365`, `B8_36d1`) are data
read as code by the disassembler. Gimmick! 1.5 puts its far-call code here.

Select is not read anywhere else during play.

## Free RAM

`$0440-$04FF` is never read or written during play, on any stage, in the intro, the credits, or
after a game over. The only write is the reset code clearing RAM (`$E078`). The few references
to `$04xx` in the disassembly are data read as code. Gimmick! 1.5 uses `$0470-$048C`.

## The map

The map is in cartridge RAM. A column's tiles are found the same way everywhere:

```
lo  = $F0BC[x tile]
hi  = $F13C[x tile] + $F66C[vertical screen]
tile = ($hi:$lo)[row]          ; 12 rows (0-11) per column per screen
```

Neighbouring columns are 12 bytes apart. Per tile: `$7D00` floor type, `$7E00` attributes
(bit 7 solid, bit 6 slope, `$20` behind the background, `$30` tube), `$7F00` death variant.

## Water and other deadly tiles

A tile with floor type 0 kills whatever has its feet in it when the physics routine (`$F596`)
starts. `$7F00` picks what happens:

| Variant | Y in the tile (`$F5F9`) | Splash sound `$1E` | Status (`$F5FD`) |
|---|---|---|---|
| 0 | unchanged | no | `$D0` (vanish) |
| 1 | `$70` | yes | `$D1` (sink) |
| 2, 3 | `$00` | yes | `$D1` |

Variants 1-3 are water. Stage 1 has a lake on vertical screen 0 (columns `$5A-$67`), and stage 2
a long one after column `$1E` on screen 2, with rafts (object type `$0E`, standable).

The star's sink animation is frames `$1B-$22`, a splash, 4 game frames each.

## Tubes

A tile whose `$7E00` attribute is exactly `$30` is a tube entrance. Stage 1 has a short tunnel
into one at column `$3D`, row 9 of screen 1.

## The star's frames (bank `$1D`, pointer table `$8523`)

| Frames | What |
|---|---|
| `$00-$0D` | five sparkles closing in (the charge) |
| `$0E` | one sparkle |
| `$0F-$13` | the star with rays |
| `$14` | the star |
| `$15-$1A` | its vanish puff (`$8C23` plays them over 16 frames) |
| `$1B-$22` | the splash when it sinks |
| `$23-$41` | fireball and bomb (fireball: rolling `$29-$34`, vanishing `$35-$3C`, charged `$3D-$40`) |
| `$42-$44` | sparkles |

The star's tiles are on CHR page `$08`, mapped at PPU `$0400` on every stage.

## The title screen

Bank `$1B`, mapped at `$8000`; its entry is `$8003`.

- It fills both nametables with tile `$10` (sky), then copies `$8242-$85C1` to PPU
  `$2080-$23FF`: nametable rows 4-29 and the attribute table (at `$8582`), raw. The logo panel
  is rows 4-14, columns 4-27.
- Background CHR (`$E5-$E8`, PPU `$1000-$1FFF`) is set by `lda #$00`, `#$65`, `#$66`, `#$67` at
  `$808A-$8097`. Pages `$65-$67` hold the logo; only 12 of their tiles are unused.
- The palette is at `$8222`. Palette 0 is the panel (black, two greys, white), palette 1 the
  sky, palette 2 the panel's bottom row. Tile `$01` is plain colour 3, white in every palette.
- The sprites start at `$819A`. Sprites 0 and 1 sit behind the background at y `$60`, x `$20` and
  `$D8`: on the panel's white side margins, where they cannot be seen. Nothing reads the
  sprite-0 hit, so what they are for is not known. Moved onto black pixels they show as blue
  dots. START and CONTINUE are sprites too.
- Everything from y 120 down (row 15 on) scrolls. The only sky that stays put is rows 0-3, above
  the panel. Those are the fill's plain `$10`, not loaded, so the hack draws its AI SLOP notice on
  row 2 with a hook at `$8082`, after the copies and with the screen still off.

## Sound

`jsr $F285` queues a sound. The driver is in bank 7 and runs in NMI. `$80FC` starts sound `A`:
the table at `$8F85` holds two bytes per id. If the high byte is `$80` or more it is a pointer
into bank 7; otherwise it is a bank number, and the low byte indexes a pointer table at `$A000`
in that bank (songs).

A sound is a list of `[track, priority, pointer]` entries ended by a byte with bit 7 set. Tracks
below 6 drive the 2A03, 6-11 the Sunsoft 5B. Star sounds are on tracks 9, 10 and 11, which all
play on 5B channel C. Measured: while track 11 plays, track 10 is not heard, and track 10 wins
over track 9. The quieter track keeps running underneath and is heard again, at its own
position, when the louder one ends.

| Id | Track | What |
|---|---|---|
| `$0F` | 9 | land |
| `$15` | 9 | star bounce |
| `$10` | 10 | star charge (59 frames) |
| `$13` | 10 | star throw |
| `$14` | 11 | item select: a quick rising arpeggio |
| `$1C` | 11 | medicine |
| `$16` | 4 (square 1) | item pickup: an arpeggio repeated as it fades |
| `$44` | 5 (square 1) | fireball throw |
| `$1E` | 4 and 9 | splash |

`$11`, `$64` and `$6D` are track-11 sounds that nothing plays.

Note periods come from `$8828` (low byte) and `$87C7` (high byte), indexed by note plus
transpose. The run of `$FF` at `$87F4` is the top of the high-byte table, not free space.

## Warping in tests

Set `$1B` (stage 0-6) and `$1C` (checkpoint), then set health `$0346` to 0: the respawn loads
that stage. Set lives `$0104` too, or a game over ends it.

## Timing

The main loop waits at `$F29F`. On busy screens the original already misses frames now and
then. Gimmick! 1.5's routines cost about 400 cycles a frame on average and 1,800 at most
(when it draws effects), out of 29,780 (`tests/survey/s_perf.lua`).
