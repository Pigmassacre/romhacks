# Romhacks

NES romhacks and ports, one per folder. Each folder is its own project, with its own README, build,
tests and license. All of these hacks are AI-assisted, using Claude.

| Hack | What it is | Get it |
|---|---|---|
| [Gimmick! 1.5](gimmick-1.5/) | *Gimmick!* with features from *Gimmick! 2*: summon a new star while one is out, skip stars across water, tap to summon, coyote time and jump buffering. | A BPS patch for your *Gimmick! (Japan)* ROM, from the releases named Gimmick! 1.5 |
| [SMB3 Gimmick](smb3-gimmick/) | Yumetaro from *Gimmick!* in the worlds of *Super Mario Bros. 3*, with his own jump, star and health. | A BPS patch for your *Super Mario Bros. 3* ROM, from the releases named SMB3 Gimmick |
| [Metroidvania](metroidvania/) | Samus from *Metroid* in *Castlevania*, moving, shooting and rolling exactly as in Metroid, with Metroid's HUD and sounds. | A BPS patch for your *Castlevania* ROM, from the releases named Metroidvania |
| [Gimmick! for GBA](gimmick-gba/) | A native port of *Gimmick!* to the Game Boy Advance, in progress. | Nothing to download yet: build it from your *Gimmick! (Japan)* ROM |

Downloads are on the [releases](https://github.com/Pigmassacre/romhacks/releases) page. Release
tags start with the folder's name, like `gimmick-1.5-v1.0`, `smb3-gimmick-v2.0.0` or `metroidvania-v1.0.0`.

## Your own ROMs

There are no ROMs in this repository, and no graphics from *Gimmick!* or *Metroid*. SMB3
Gimmick includes [Southbird's Super Mario Bros. 3 disassembly](https://github.com/captainsouthbird/smb3)
and its stock graphics, and data it converted from *Gimmick!*: Yumetaro's sprite layouts and
sounds. Metroidvania includes sound effect data recorded from *Metroid*, and converts Samus's
graphics from your own Metroid ROM when it builds. Every hack builds from copies of the games
you provide, put in that hack's folder. Each `.gitignore` keeps ROMs, emulators and build
output out of git.

The patches copy everything they can from the player's own ROM. Gimmick! 1.5's holds only new
code and tiles. SMB3 Gimmick's also carries Yumetaro's graphics, his star and the logo from
*Gimmick!*, since its players only bring Super Mario Bros. 3, and Metroidvania's carries
Samus's graphics and sounds from *Metroid*, since its players only bring Castlevania.
