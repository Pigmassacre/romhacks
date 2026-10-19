# Gimmick! 1.5

A hack of Sunsoft's *Gimmick!* (Famicom, 1992) that adds features from *Gimmick! 2* (2024),
halfway between the two. The big one: summon a new star while one is already out, and the old
one is recalled.

You bring your own copy of the Japanese *Gimmick!*. The hack is a small BPS patch.

## What's new

| | |
|---|---|
| **Star recall** | Press B while your star is out (bouncing, rolling, in a tube or vanishing) and a new one starts charging at once. The old star flies back to Yumetaro. In the original, B does nothing until the old star is gone. |
| **Skipping stones** | A star that hits water fast enough skips off it, a little lower and slower each time, until it sinks. You can ride it while it skips. In the original it sinks at once. |
| **Tap to summon** | Press Select to switch between holding B to charge the star (as in the original) and tapping B: tap to summon, tap again to throw. A tap that comes too early throws the star as soon as it is ready. Select again switches back. |
| **Coyote time** | You can still jump for 6 frames after walking off a ledge, an enemy, or a star that was just recalled from under you. |
| **Jump buffering** | Press A a little too early, just before you land, and you jump as soon as you land. Up to 5 frames early counts. |
| **Title screen** | The logo says *Gimmick! 1.5*. |

Everything else is the original game: the same physics, levels, enemies and items. Fireballs and
bombs are items, so B does not recall them. B+Up with a fireball or bomb in your first item slot
recalls the star and charges the item.

*Gimmick! 2* has all of these: its binary has `RecallStar`, `EDoohickeyStarState::Skipping`,
`StarWaterBounceReduction`, `EDoohickeyOptionsSaveGameSummonStarOption::Tap`,
`CoyoteTimeDuration` and `MaxJumpBufferingDuration`. The numbers here are tuned to the original
game's physics, not taken from *Gimmick! 2*.

## Play it

Patch your ROM with `gimmick-1.5.bps` using [Flips](https://github.com/Alcaro/Flips) or
[Rom Patcher JS](https://www.marcrobledo.com/RomPatcher.js/). There are two patches because the
two common dumps of *Gimmick! (Japan)* differ only in their 16-byte header:

| Your ROM's CRC32 | Patch |
|---|---|
| `EEB6B362` (iNES header) | `gimmick-1.5.bps` |
| `EE8879D5` (NES 2.0 header) | `gimmick-1.5 (NES 2.0 header).bps` |

Both give the same 768 KB ROM: 512 KB of PRG ROM and 256 KB of CHR ROM, the most the Sunsoft
FME-7 mapper (mapper 69) can address. Your emulator or flash cart has to support that. It has
been tested in Mesen.

## Build it

Put your ROM in this folder as `Gimmick! (Japan).nes` (either dump), then:

```bash
python3 tools/build.py
```

That writes `out/gimmick-1.5.nes` and both patches. It needs Python 3 and
[asm6](https://www.romhacking.net/utilities/674/) at `tools/asm6`. If `tools/asm6` is missing and
the disassembly is in `ref/gimmick/`, the build compiles it from the `asm6.c` there.

### Tests

The tests play the game in [Mesen](https://www.mesen.ca/) (`./Mesen`, headless) and check RAM:

```bash
python3 tests/run.py
```

Each test also runs against the original game to check that it really is a change:

```bash
python3 tests/run.py --rom "Gimmick! (Japan).nes"
```

| Test | What it checks |
|---|---|
| `recall` | Recall from flight, from under Yumetaro, during the vanish; the old star flies to him; fireballs are left alone; B+Up charges an item |
| `tube` | Recall a star that is inside a tube |
| `water` | The star skips across stage 2's lake with Yumetaro on it, then sinks |
| `splash` | A skip's splash plays the star's sink frames |
| `tap` | Tap mode on and off, early taps, recall in tap mode |
| `coyote` | Jumping 1-6 frames after walking off a ledge, and not 7 or 12 |
| `jumpbuf` | A press 1-5 frames before landing jumps, a tap gives a short hop, holding A a full jump |
| `ramguard` | The original game never touches the RAM the hack uses: every stage, deaths, game over, the credits and the intro |
| `title` | The title screen shows the new logo, and Start still begins the game |

`tests/survey/` has measurements rather than tests: sound effects, the frame budget
(`perf`), the stages' water and tubes, screenshots of the recall effect and the title.

## How it works

The source is `src/`. `tools/build.py` assembles `src/main.asm` with asm6. Each `;@ seg <bank>
<start> <end>` line in it starts a segment, assembled at that address and written into that bank.
The repository holds none of the original game's code or graphics, and the patch holds only
the new code and tiles.

1. **More room.** The ROM grows from 256 KB to 512 KB of PRG and from 128 KB to 256 KB of CHR.
   The original banks keep their numbers. The fixed bank is copied from `$1F` to `$3F`, because
   the FME-7 always maps the last bank at `$E000`. The new code is in bank `$20`.
2. **Far calls.** The fixed bank has a disabled developer cheat at `$E271-$E2D4` that nothing can
   reach. `FarCall` lives there: it maps bank `$20` at `$A000`, calls a routine and puts back
   what was there, keeping the bank shadows right for NMI.
3. **Hooks.** Each hook replaces a few instructions with `jsr` to a far call, and the new code
   does what was replaced:

| Where | Was | Now |
|---|---|---|
| `1E:8199` | A newly pressed and on the floor? | `JumpCheck` (`src/jump.asm`): coyote time, jump buffering, Select for tap mode |
| `1E:81C3` | Skip the charge code while a star is out | `StarButton` (`src/recall.asm`): recall it on a new B press |
| `1E:81DA` | Is B held? | `BHeld` (`src/tap.asm`): hold or tap mode |
| `1D:8151` | Save the star's vy before its physics | `WaterSkip` (`src/water.asm`): bounce it off water |
| `1D:8469` | Start of the star's draw routine | `FxDraw` (`src/fx.asm`): draw the recalled star and splashes |

4. **The title.** The title screen's panel is stored as plain nametable rows in bank `$1B`.
   `tools/title.py` widens the panel by three columns on each side, moves the logo left, and
   draws "1.5" in the logo's black brush style: thick strokes, rasterised at 4x and shaded with
   the logo's two greys. Its tiles go into copies of the title's four CHR pages (`$80-$83`), so
   no other screen changes. `python3 tools/title.py` writes a before and after preview to `out/`.

The hack's RAM is `$0470-$048C`, which the original game never uses. `src/defs.asm` has every
address and the tuning values (coyote and buffer frames, skip speeds, effect lengths).

`docs/notes.md` has what was learnt about the ROM along the way: free RAM, the debug block, the
map layout, water and tubes, the star's animation frames, the title screen, and how the sound
driver layers effects. `ref/docs/` has smb3-gimmick's notes and its physics guide.

## Credits

*Gimmick!* is © Sunsoft. *Gimmick! 2* is © Sunsoft and Bitwave Games. asm6 is by loopy. The
Gimmick! disassembly in `ref/gimmick/` and the notes in `ref/docs/` come from the smb3-gimmick
project and are not part of this repository.
