# SMB3 Gimmick

Yumetaro, from Sunsoft's *Gimmick!*, in the worlds of *Super Mario Bros. 3*. He keeps his own jump, his star, and his health. The levels are Super Mario Bros. 3.

You bring your own copy of Super Mario Bros. 3. The hack is a BPS patch.

## Play it

Download `smb3-gimmick.bps` from the [releases](https://github.com/Pigmassacre/romhacks/releases) page (the releases named SMB3 Gimmick) and apply it to your Super Mario Bros. 3 with [Flips](https://github.com/Alcaro/Flips) or [Rom Patcher JS](https://www.marcrobledo.com/RomPatcher.js/). It is made for the original US release, not Revision A:

| Your ROM's CRC32 | Patch |
|---|---|
| `85A79D9C` (`A0B0B742` without its 16-byte header) | `smb3-gimmick.bps` |

The result is a 640 KB ROM: 512 KB of PRG ROM and 128 KB of CHR ROM on the MMC3 mapper (mapper 4). It has been tested in Mesen.

Versions 1.5.0 and earlier were a program that built the game from both Super Mario Bros. 3 and Gimmick!. They are on the [old smb3-gimmick repository](https://github.com/Pigmassacre/smb3-gimmick/releases).

## What you get

- Yumetaro's walk, jump, and slide down slopes.
- Hold B to charge the star, then let go to throw it. It bounces, rolls, hits enemies and blocks, and you can ride it.
- He stands on enemies instead of stomping them.
- Health instead of Mario's power-ups. A mushroom heals. Flowers, leaves and suits raise the maximum, up to 6, and fill it. A ? block gives its mushroom while he's hurt, and otherwise the flower or leaf it holds. A power-up used from the map's inventory raises the maximum too, each player's their own.
- Gimmick! sounds for jumping, the star, and the death jingle.
- Yumetaro on the world map, in the title's curtain scene, the 2-player battle, the Game Over box and the ending, and the Gimmick! logo on the title screen. The second player is the Ohagi from Gimmick!, marked with an O and named OHAGI: it plays exactly like Yumetaro, star and all, a nod to the Ohagi you control on one screen of the pirate ship. It turns grey where the background is black, so it doesn't vanish.

## Credits

Yumetaro's movement was written for this project, on top of [Southbird's Super Mario Bros. 3 disassembly](https://github.com/captainsouthbird/smb3). *Super Mario Bros. 3* is © Nintendo. *Gimmick!* is © Sunsoft; the patch includes Yumetaro's graphics, his star, and the Gimmick! logo from it.

The original code in this folder is under the MIT license. See [LICENSE](LICENSE) for what it covers.

## Working on the game

The disassembly is in `src/`, based on [Southbird's Super Mario Bros. 3 disassembly](https://github.com/captainsouthbird/smb3). Yumetaro's code is in `src/PRG/gim_player.asm`, `gim_star.asm`, `gim_frames.asm`, and `gim_death.asm`.

`docs/yumetaro-physics-guide.md` describes exactly how Yumetaro and the star move in the original *Gimmick!*, and `godot/` is a Godot 4 project that implements it and is checked frame by frame against the real game. `docs/gimmick-notes.md` has the working notes on the Gimmick! ROM.

This folder holds no ROMs and no Gimmick! graphics. Put your own copies in it, named exactly `Super Mario Bros III.nes` and `Gimmick! (Japan).nes`. The build and the release script read them from there.

`./build.sh` assembles `out/smb3-gimmick.nes` and writes the patch, `out/smb3-gimmick.bps`. It needs Python 3 and expects [NESASM](https://github.com/camsaul/nesasm) at `ref/nesasm/nesasm`. Before assembling, `tools/build_chr.py` and `tools/build_title.py` copy Yumetaro's tiles and the logo from the Gimmick! ROM into `out/chr/`, so `src/CHR` only ever holds the stock SMB3 graphics. Then `tools/patch.py` makes the patch. It copies every run of 8 or more bytes that is anywhere in Super Mario Bros. 3 from the player's ROM, so the patch holds only Yumetaro's code and the graphics from Gimmick!. It also checks that the patch reproduces the game.

### Tests

The tests play the game headless in [Mesen 2](https://www.mesen.ca/) and check RAM, sprites and the PPU. Put the Linux build at `./Mesen`, then:

```bash
python3 tests/run.py
```

That first makes the savestates the tests start from (`tests/s_states.lua`: on the map, and just inside every area of the game, listed by `tests/levels.py`), then runs every test. Savestates hold addresses in the code, so after changing the code remake them with `tests/rb.sh`, which also builds.

| Test | What it checks |
|---|---|
| `2p` | The second player is the Ohagi, with an O where Mario's had an L: on the map, in levels and in the battle |
| `ohagi` | The Ohagi's name and sprite in the Game Over box, and its black colours in a bright level and grey in a black one |
| `airjump` | A jumps off a parabeetle: his jump obeys `Player_AllowAirJump`, as Mario's does (it once ignored it) |
| `battle` | Every map's battle room: stars kill the enemies, and the treasure box ends it |
| `bowser` | Stars wear Bowser down, he falls, the door appears, and Yumetaro is at the princess's side in the ending (it was once Mario) |
| `death` | Dying by an enemy, a pit and the clock: the jingle plays through, a life goes, and the map's music comes back |
| `items` | A power-up from the inventory raises the maximum, with no suit, and no change of colour on the map (they once gave Mario's suit moves) |
| `junction` | Through a pipe, health stays as it was and the star is gone |
| `koopaling` | Each Koopaling takes three hits from stars, and its wand can be reached |
| `levelfix` | 6-7's end, where a wall was too tall even for a jump from the star, can be climbed (`tools/gen_levelfix.py` lists the tiles changed in such places) |
| `names` | The title says AI SLOP, DO NOT PLAY, and the world's intro box YUMETARO, with his sprite and horn |
| `powerups` | What each power-up does to health, and what ? blocks give (flowers and leaves once only counted as mushrooms) |
| `ride` | Landing on a rolling star, it carries him, and he jumps higher from it (he was once pulled up 15 pixels onto it) |
| `rideedge` | Carried by an enemy to the screen's edge he stops there (he once counted as crushed, and died) |
| `sand` | A pressed A gets him across 2-Sun's quicksand |
| `shoe` | Kuribo's shoe is drawn under him (he once hopped about in nothing), and a hit knocks it off |
| `gameover` | Out of lives, Start on Continue gives 4 lives, and only that player's maximum health goes back to 3 |
| `starbump` | The star bumps ? blocks and breaks bricks, from the side and from below |
| `statusbar` | Health as arrows, the [P]'s two halves, and on the map the maximum (it once showed what the last level left) |
| `starscroll` | In a room that scrolls up and down over a fixed floor, the star lands on the floor shown (it once sank through it) |
| `whistle` | Every hop up the steps to world 1 fortress's high door, for the warp whistle Mario flew to |
| `toad` | A toad house's chest gives its item and goes back to the map |

Some scripts go through the whole game, for looking over rather than passing, each with `python3 tests/run.py <name>`:

- `solve` searches for buttons that clear a level, from the savestate at its start, with health and time topped up (`SOLVE_LEVELS`, `SOLVE_FRAMES`; `tests/solve_all.sh` runs it in parallel, and each result, with the winning buttons, goes in `out/test/solve_<level>.txt`).
- `fuzz` presses random buttons in every area with Yumetaro flown along now and then, watching every frame for code running from RAM, the stack, hangs, jumps of position, sprites using his page's tiles, and values out of range (`out/test/fuzz_<seed>.log`; `FUZZ_SEED`, `FUZZ_SLICE`, `FUZZ_FRAMES`). Keeping the clock full stops levels ending, so `halted` findings at a level's end are the fuzz's own.
- `objects` tries every object ID with the star and underfoot.
- `maps` writes each area's tiles to `out/test/map_<name>.txt`, and `python3 tests/reach.py` then works out on those how far his jump gets, without a star and with one, for finding places to look at.
- `title` and `vs` take screenshots of the title and the 2-player battle.

`./release.sh v2.0.0` publishes a GitHub release. You need the [GitHub CLI](https://cli.github.com/), logged in, and a clean working tree. It checks that no ROMs or Gimmick! graphics are tracked anywhere in the git history, builds the game and the patch, tags `smb3-gimmick-v2.0.0`, and publishes `smb3-gimmick.bps` as the release.
