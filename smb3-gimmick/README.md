# SMB3 Gimmick

Yumetaro, from Sunsoft's *Gimmick!*, in the worlds of *Super Mario Bros. 3*. He keeps his own jump, his star, and his health. The levels are Super Mario Bros. 3.

You bring your own copies of the two NES games. The SMB3 Gimmick program builds the new game from them on your computer.

## Play it

Download SMB3 Gimmick from the [GitHub releases](https://github.com/Pigmassacre/smb3-gimmick/releases) page.

| Computer | File |
|---|---|
| Windows | `SMB3-Gimmick-windows.zip` |
| Mac (2020 or newer) | `SMB3-Gimmick-mac.zip` |
| Mac (older Intel Mac) | `SMB3-Gimmick-mac-intel.zip` |
| Linux | `SMB3-Gimmick-linux.zip` |

Unzip it and open **SMB3 Gimmick**. A page opens in your web browser. Drop in Super Mario Bros. 3 (the original US release) and Gimmick! (the Japanese game), then choose **Make the game**. The result is `SMB3 Gimmick.nes` in your downloads folder. Open that in an NES emulator.

The first time you open it, Windows or macOS may ask you to confirm. On Windows, choose **More info**, then **Run anyway**. On a Mac, right-click the app and choose **Open**.

Leave the small text window open while you use the page. Close it when you are finished.

## What you get

- Yumetaro's walk, jump, and slide down slopes.
- Hold B to charge the star, then let go to throw it. It bounces, rolls, hits enemies and blocks, and you can ride it.
- He stands on enemies instead of stomping them.
- Health instead of Mario's power-ups. A mushroom heals. Other power-ups raise the maximum, up to 6.
- Gimmick! sounds for jumping, the star, and the death jingle.
- Yumetaro on the world map, and the Gimmick! logo on the title screen.

## Credits

Yumetaro's movement was written for this project. *Super Mario Bros. 3* is © Nintendo. *Gimmick!* is © Sunsoft.

## Working on the game

`./release.sh v1.0.0` builds the program for Windows, Mac, and Linux and publishes those files as a GitHub release. You need [Go](https://go.dev/dl/) and the [GitHub CLI](https://cli.github.com/), logged in.

The assembly for Yumetaro is in `hack/`. `tools/gen_patch.py` rebuilds `internal/build/patch.bin` after a local build of the game. The original game's code and graphics are not in this repository. `build.sh` only works where that private source is present.
