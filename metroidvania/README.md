# Metroidvania

Samus, from Nintendo's *Metroid*, in Konami's *Castlevania*. She moves, jumps, rolls and shoots exactly as she does in Metroid, with Metroid's HUD and sounds. The stages, enemies and bosses are Castlevania.

You bring your own copy of Castlevania. The hack is a BPS patch.

## Play it

Download `metroidvania.bps` from the [releases](https://github.com/Pigmassacre/romhacks/releases) page (the releases named Metroidvania) and apply it to your Castlevania with [Flips](https://github.com/Alcaro/Flips) or [Rom Patcher JS](https://www.marcrobledo.com/RomPatcher.js/). It is made for the original US release:

| Your ROM's CRC32 | Patch |
|---|---|
| `856114C8` (`B668C7FC` without its 16-byte header) | `metroidvania.bps` |

The result is a 256 KB ROM: Castlevania's 128 KB of PRG ROM doubled, still on mapper 2 (UNROM, now UOROM), with CHR RAM. It has been tested in Mesen.

## What you get

- **Samus moves as in Metroid.** Running, turning, jumping and spin jumping, aiming up, the morph ball, being knocked back: Metroid's code, ported, with its numbers. A test plays the same inputs in both games and checks that Samus's position, animation frame and shots match frame by frame.
- **Her weapons.** B fires the power beam, short as at the start of Metroid. Castlevania's whip upgrade gives her the Long Beam. Select arms missiles, and missiles are Castlevania's hearts: each one costs a heart.
- **Metroid's HUD.** "EN", the energy and the missile count, in Metroid's font and colours. Castlevania's status bar is gone.
- **Metroid's energy.** 99 at most. Castlevania's hits take one and a half energy per point of Simon's health, so it takes as many hits to die as before; a pork chop gives energy back, and clearing a stage fills it up. Run out and Samus explodes as in Metroid.
- **Metroid's sounds** for jumping, shooting, missiles, rolling, steps, getting hit, the low energy beep and dying, taken from Metroid's sound engine.
- **Metroid's camera.** The screen follows Samus once she leaves the middle of it, as in Metroid.
- **The attract demo** is played by Samus, from Simon's recorded inputs.
- **Castlevania everywhere else.** Pressing Up or Down at the foot or top of stairs climbs them (holding Up is aiming, so walking past stairs with it held does not), and B fires forwards from them. Moving platforms carry her. Shots break candles, hurt enemies and bosses, and break the breakable walls. Stage exits, doors, items and deaths are Castlevania's.

The morph ball is there from the start: Down rolls, Up or A stands up again where there is room.

What doesn't carry over: Simon's subweapons. Their items still drop, but Samus can't throw them, and the double and triple shot items do nothing. The timer, score and lives still count, but nothing shows them; running out of time still kills.

## Credits

*Castlevania* is © Konami. *Metroid* is © Nintendo; the patch includes Samus's graphics, HUD and sound effects from it.

Samus's code is a port of Metroid's, written for this project from the [m1disasm](https://github.com/metroidret/m1disasm) disassembly's labels and comments. asm6 is by loopy.

The original code in this folder is under the MIT license. See [LICENSE](LICENSE) for what it covers.

## Build it

Put your ROMs in this folder as `Castlevania I.nes` (the one the patch is for) and `Metroid.nes` (Metroid (USA), CRC32 `A2C89CB9`, for Samus's graphics). Then:

```bash
python3 tools/build.py
```

That writes `out/metroidvania.nes` and the patch, `out/metroidvania.bps`. It needs Python 3 and loopy's asm6 at `tools/asm6` (the same one as Gimmick! 1.5's). The patch copies everything it can from Castlevania, so it holds only the new code, Samus's graphics and the sound data.

### Tests

The tests play the game headless in [Mesen 2](https://www.mesen.ca/) and check RAM, sprites and the PPU. Put the Linux build at `./Mesen`, then:

```bash
python3 tests/run.py
```

That first makes the savestates the tests start from (`tests/s_states.lua`: just inside the castle, and at the hall's first stairs), then runs every test.

| Test | What it checks |
|---|---|
| `physics` | Samus's position, animation frame and first shot match Metroid frame by frame, for 16 input sequences: jumps, runs, turns, the morph ball, beams, missiles, aiming up |
| `hud` | The HUD's sprites and digits, the blank status bar, the HUD's colours ending at the split, and Castlevania's own sprites (1-8) left alone |
| `split` | The status bar's last lines stay black: the HUD's palette change at the split never shows |
| `shots` | Shooting through zombies and candles: shots hit, and the daggers under them never get a sprite (Castlevania's hit flame used to show on every other shot) |
| `block` | A shot bursting on the hall's breakable block breaks it |
| `crusher` | Stage 6's crushers only hurt Samus in the air, as they only hurt Simon jumping (they once killed her mid-jump) |
| `damage` | A zombie takes 12 energy, with Metroid's knockback and invincibility |
| `stairs` | Up pressed at the foot of the stairs climbs them, drawn on the steps, to the stage exit; walking past with Up held does not |
| `stairhit` | Hits on the stairs come off Samus's energy as they land, she stays on the stairs, and running out of energy there kills her (three hits once read as a refill) |
| `stairshot` | On the stairs B fires Samus's beam (it once started Simon's whip, drawn with her tiles), and shots in flight keep moving |
| `door` | Up the hall's last stairs, running, and through the door into stage 2 as Castlevania shows Simon: hidden while the screen scrolls to the door, walking through it, with the HUD up throughout |
| `edges` | Where the screen can't scroll, Samus walks on it to Simon's edges: back along stage 4's middle floor to its stairs, and into the left half of a locked boss screen |
| `blink` | Samus blinks while enemies can't touch her, as Simon does: the invisibility potion used to show nothing |
| `shaft` | After the mummies, Samus falls down the shaft into stage 10, lands and walks on (she once came in stuck at the top, and died) |
| `platform` | Samus stands on one of stage 10's moving platforms and is carried along |
| `bosslock` | The screen locks for Medusa, at the left end of her stage, as Samus scrolls left onto her screen |
| `boss` | The screen locks for the Phantom Bat, no zombies come into the fight, and Samus's shots beat it |
| `shotsgone` | Shots end when Castlevania takes over for good (dying, doors, a stage's end): they once hung in the air through a death |
| `missiles` | Select arms missiles and each one costs a heart, also after B was pressed with all three shots in flight (that once broke missiles for good) |
| `sfx` | Jumping plays Metroid's jump sound, and the music keeps off its channel |
| `death` | Samus explodes; on the last life, the Game Over screen has its font, and continuing gives Samus her tiles back |
| `load` | The screen stays black while a stage loads (the hack's palette writes once showed there as a line) |
| `timeout` | Running out of time kills Samus wherever she is (she once lived on until she took the stairs) |
| `title` | The title screen is still Castlevania's: its bat flies and lands on the castle (the hack once covered the end of its path, and the attract demo never came) |
| `demo` | Samus plays the attract demo, with the HUD, and the title gives her full energy back for the next game |
| `ending` | The ending is Castlevania's: the castle falling (object slot 0, which in play is Simon) in its own colours, no Samus and no status bar |
| `ramguard` | Castlevania never writes the hack's RAM (run it against the original: `python3 tests/run.py --rom "Castlevania I.nes" ramguard`), and with the hack the stack stays clear of it |

`boss` and `platform` warp to their stages and fly Samus there through the walls (a debug flag in the hack's RAM, `DebugFlags`, which only the tests set).

Four sweeps go through the whole game, for looking over rather than passing: `tour` (every stage, with screenshots), `allstairs` (every staircase, up and down), `exits` (every stage's exit) and `bosses` (every boss, then the stage's end), each with `python3 tests/run.py <name>` and logging where Samus ends up.

`tests/s_bench.lua` and `tests/s_hot.lua` are measurements rather than tests: how much of each frame the game takes, and where the hack spends its time (`python3 tests/run.py bench`).

The reference for `physics` is `tests/ref/physics.txt`, recorded in Metroid with `python3 tools/lua.py tools/record_physics.lua Metroid.nes`. The sound effects in `src/sfxdata.asm` come from `python3 tools/lua.py tools/record_sfx.lua Metroid.nes` and `python3 tools/sfx_data.py`.

## How it works

The source is `src/`. `tools/build.py` assembles `src/main.asm` with asm6; each `;@ seg <bank> <start> <end>` line starts a segment, assembled at that address and written into that 16 KB bank.

1. **More room.** The PRG grows from 128 KB to 256 KB. Castlevania's banks keep their numbers; the fixed bank moves from 7 to `$0F`, since the mapper always puts the last bank at `$C000`. The hack lives in bank `$08`.
2. **Far calls.** `FarCall`, in padding before the vectors, maps bank `$08` and calls one of its routines. Castlevania runs its whole game in the NMI, and the NMI's sound code switches banks and back, so `FarCall` keeps Castlevania's bank shadow (`$27`) right.
3. **Samus.** `src/samus.asm` is Metroid's Samus code: its handlers, its animation, its acceleration and per-pixel movement. Where Metroid looks up its room, she looks up Castlevania's collision map (8x8 cells, like Metroid's), and where Metroid scrolls, she moves Castlevania's scroll. Her shots (`src/bullets.asm`) each hold one of Castlevania's three subweapon slots as an unmoving dagger, so Castlevania's own collision code hurts enemies and breaks candles with them.
4. **Castlevania around her** (`src/cv.asm`). Every frame Samus writes her position into Simon's variables, which Castlevania's enemies, items, stage exits and stairs use. For the stairs, walking in and dying, Castlevania moves Simon and Samus follows. Castlevania's damage arrives as changes to Simon's health, which is kept at a constant value and turned into Metroid's energy.
5. **Graphics.** `tools/samus_gfx.py` converts Samus's frames from Metroid's 8x8 sprites to Castlevania's 8x16 ones: it decodes each frame as Metroid draws it, pairs sprites into 8x16, and stores each distinct pair (and its mirror image) once. The pairs go over Simon's tiles in the sprite pattern table, and the rest over the status bar's font, which the hack copies back for the Game Over screen.
6. **The HUD** (`src/hud.asm`) is 7 sprites over the blanked status bar. Its digits are drawn into the pattern table when they change. Metroid's HUD colours go in sprite palette 2 at the top of the screen, and Castlevania's come back at the status bar split, on its last blank lines.
7. **Sounds** (`src/sfx.asm`) are Metroid's APU writes, played back after Castlevania's music each frame; while one plays, Castlevania's writes to that channel go to an unused register.

`docs/notes.md` has what was learnt about both ROMs along the way: the RAM, the hooks, Castlevania's object slots and actions, its collision map and loader, and the timing of the split.
