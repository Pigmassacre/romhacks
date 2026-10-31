# SMB3 Gimmick

Yumetaro, from Sunsoft's *Gimmick!*, in the worlds of *Super Mario Bros. 3*. He keeps his own jump, his star, and his health. The levels are Super Mario Bros. 3.

You bring your own copy of Super Mario Bros. 3. The hack is a BPS patch.

This hack is AI-assisted, using Claude.

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
- Health instead of Mario's power-ups. A mushroom heals. Other power-ups raise the maximum, up to 6.
- Gimmick! sounds for jumping, the star, and the death jingle.
- Yumetaro on the world map, and the Gimmick! logo on the title screen.

## Credits

Yumetaro's movement was written for this project, on top of [Southbird's Super Mario Bros. 3 disassembly](https://github.com/captainsouthbird/smb3). *Super Mario Bros. 3* is © Nintendo. *Gimmick!* is © Sunsoft; the patch includes Yumetaro's graphics, his star, and the Gimmick! logo from it.

The original code in this folder is under the MIT license. See [LICENSE](LICENSE) for what it covers.

## Working on the game

The disassembly is in `src/`, based on [Southbird's Super Mario Bros. 3 disassembly](https://github.com/captainsouthbird/smb3). Yumetaro's code is in `src/PRG/gim_player.asm`, `gim_star.asm`, `gim_frames.asm`, and `gim_death.asm`.

`docs/yumetaro-physics-guide.md` describes exactly how Yumetaro and the star move in the original *Gimmick!*, and `godot/` is a Godot 4 project that implements it and is checked frame by frame against the real game. `docs/gimmick-notes.md` has the working notes on the Gimmick! ROM.

This folder holds no ROMs and no Gimmick! graphics. Put your own copies in it, named exactly `Super Mario Bros III.nes` and `Gimmick! (Japan).nes`. The build and the release script read them from there.

`./build.sh` assembles `out/smb3-gimmick.nes` and writes the patch, `out/smb3-gimmick.bps`. It needs Python 3 and expects [NESASM](https://github.com/camsaul/nesasm) at `ref/nesasm/nesasm`. Before assembling, `tools/build_chr.py` and `tools/build_title.py` copy Yumetaro's tiles and the logo from the Gimmick! ROM into `out/chr/`, so `src/CHR` only ever holds the stock SMB3 graphics. Then `tools/patch.py` makes the patch. It copies every run of 8 or more bytes that is anywhere in Super Mario Bros. 3 from the player's ROM, so the patch holds only Yumetaro's code and the graphics from Gimmick!. It also checks that the patch reproduces the game.

`./release.sh v2.0.0` publishes a GitHub release. You need the [GitHub CLI](https://cli.github.com/), logged in, and a clean working tree. It checks that no ROMs or Gimmick! graphics are tracked anywhere in the git history, builds the game and the patch, tags `smb3-gimmick-v2.0.0`, and publishes `smb3-gimmick.bps` as the release.
