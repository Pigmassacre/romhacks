# Romhacks

NES romhacks, one per folder. Each folder is its own project, with its own README, build,
tests and license.

| Hack | What it is | Get it |
|---|---|---|
| [Gimmick! 1.5](gimmick-1.5/) | *Gimmick!* with features from *Gimmick! 2*: summon a new star while one is out, skip stars across water, tap to summon, coyote time and jump buffering. | A BPS patch for your *Gimmick! (Japan)* ROM, from the releases named Gimmick! 1.5 |
| [SMB3 Gimmick](smb3-gimmick/) | Yumetaro from *Gimmick!* in the worlds of *Super Mario Bros. 3*, with his own jump, star and health. | A program for Windows, Mac and Linux that builds the game from your own ROMs, from the releases named SMB3 Gimmick |

Downloads are on the [releases](https://github.com/Pigmassacre/romhacks/releases) page. Release
tags start with the folder's name, like `gimmick-1.5-v1.0` or `smb3-gimmick-v1.6.0`.

## Your own ROMs

There are no ROMs in this repository, and nothing from *Gimmick!*. SMB3 Gimmick includes
[Southbird's Super Mario Bros. 3 disassembly](https://github.com/captainsouthbird/smb3) and its
stock graphics, as that project always has. Every hack builds from copies of the games you
provide, put in that hack's folder. Each `.gitignore` keeps ROMs, emulators and build output out
of git.
