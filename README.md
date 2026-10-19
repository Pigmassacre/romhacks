# Romhacks

NES romhacks, one per folder. Each folder is its own project, with its own README, build,
tests and license.

| Hack | What it is | Get it |
|---|---|---|
| [Gimmick! 1.5](gimmick-1.5/) | *Gimmick!* with features from *Gimmick! 2*: summon a new star while one is out, skip stars across water, tap to summon, coyote time and jump buffering. | A BPS patch for your *Gimmick! (Japan)* ROM, from the releases named Gimmick! 1.5 |
| [SMB3 Gimmick](smb3-gimmick/) | Yumetaro from *Gimmick!* in the worlds of *Super Mario Bros. 3*, with his own jump, star and health. | A BPS patch for your *Super Mario Bros. 3* ROM, from the releases named SMB3 Gimmick |

Downloads are on the [releases](https://github.com/Pigmassacre/romhacks/releases) page. Release
tags start with the folder's name, like `gimmick-1.5-v1.0` or `smb3-gimmick-v2.0.0`.

## Your own ROMs

There are no ROMs in this repository, and no graphics from *Gimmick!*. SMB3 Gimmick includes
[Southbird's Super Mario Bros. 3 disassembly](https://github.com/captainsouthbird/smb3) and its
stock graphics, and data it converted from *Gimmick!*: Yumetaro's sprite layouts and sounds.
Every hack builds from copies of the games you provide, put in that hack's folder. Each
`.gitignore` keeps ROMs, emulators and build output out of git.

The patches copy everything they can from the player's own ROM. Gimmick! 1.5's holds only new
code and tiles. SMB3 Gimmick's also carries Yumetaro's graphics, his star and the logo from
*Gimmick!*, since its players only bring Super Mario Bros. 3.
