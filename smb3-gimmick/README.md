# SMB3 Gimmick

Yumetaro, from Sunsoft's *Gimmick!*, in the worlds of *Super Mario Bros. 3*. He keeps his own jump, his star, and his health. The levels are Super Mario Bros. 3.

You bring your own copies of the two NES games. The SMB3 Gimmick program builds the new game from them on your computer.

## Play it

Download SMB3 Gimmick from the [GitHub releases](https://github.com/Pigmassacre/smb3-gimmick/releases) page.

| Computer | File |
|---|---|
| Windows | `SMB3-Gimmick-windows.zip` |
| Mac | `SMB3-Gimmick-mac.zip` |
| Linux | `SMB3-Gimmick-linux.zip` |

Unzip it and open **SMB3 Gimmick**. Drop Super Mario Bros. 3 (the original US release) and Gimmick! (the Japanese game) on its window, or choose them with **Choose files**. Then choose **Make the game** and pick where to save `SMB3 Gimmick.nes`. Open that in an NES emulator.

The first time you open it, Windows or macOS may ask you to confirm. On Windows, choose **More info**, then **Run anyway**. On a Mac, right-click the app and choose **Open**.

The Linux version needs a 2023 or newer distribution, such as Ubuntu 24.04 or Linux Mint 22. **Choose files** and the save window use `zenity` or `kdialog`. Without either, drop the files on the window, and the game is saved next to Super Mario Bros. 3.

## What you get

- Yumetaro's walk, jump, and slide down slopes.
- Hold B to charge the star, then let go to throw it. It bounces, rolls, hits enemies and blocks, and you can ride it.
- He stands on enemies instead of stomping them.
- Health instead of Mario's power-ups. A mushroom heals. Other power-ups raise the maximum, up to 6.
- Gimmick! sounds for jumping, the star, and the death jingle.
- Yumetaro on the world map, and the Gimmick! logo on the title screen.

## Credits

Yumetaro's movement was written for this project, on top of [Southbird's Super Mario Bros. 3 disassembly](https://github.com/captainsouthbird/smb3). *Super Mario Bros. 3* is © Nintendo. *Gimmick!* is © Sunsoft.

The builder program uses [Dear ImGui](https://github.com/ocornut/imgui) through [giu](https://github.com/AllenDang/giu), and the [Noto Sans](https://notofonts.github.io/) font under the SIL Open Font License (`cmd/smb3-gimmick/fonts/OFL.txt`).

The original code in this repository is under the MIT license. See [LICENSE](LICENSE) for what it covers.

## Working on the game

The disassembly is in `src/`, based on [Southbird's Super Mario Bros. 3 disassembly](https://github.com/captainsouthbird/smb3). Yumetaro's code is in `src/PRG/gim_player.asm`, `gim_star.asm`, `gim_frames.asm`, and `gim_death.asm`.

`docs/yumetaro-physics-guide.md` describes exactly how Yumetaro and the star move in the original *Gimmick!*, and `godot/` is a Godot 4 project that implements it and is checked frame by frame against the real game. `docs/gimmick-notes.md` has the working notes on the Gimmick! ROM.

The ROM files are not included, and neither are any Gimmick! graphics. Put your own copies in the repository folder, named exactly `Super Mario Bros III.nes` and `Gimmick! (Japan).nes`. The build, the tests, and the release script read them from there.

`./build.sh` assembles `out/smb3-gimmick.nes`. It needs Python 3 and expects [NESASM](https://github.com/camsaul/nesasm) at `ref/nesasm/nesasm`. Before assembling, `tools/build_chr.py` and `tools/build_title.py` copy Yumetaro's tiles and the logo from the Gimmick! ROM into `out/chr/`, so `src/CHR` only ever holds the stock SMB3 graphics. After a build, `python3 tools/gen_patch.py` rebuilds `internal/build/patch.bin`. `go test ./...` then checks that the builder produces the same game.

The builder program is in `cmd/smb3-gimmick`. It needs cgo: on Linux, a C compiler plus the OpenGL and X11 development packages (`libgl1-mesa-dev xorg-dev` on Ubuntu). `go run ./cmd/smb3-gimmick` opens it. The Windows version cross-compiles from Linux with MinGW (`CGO_ENABLED=1 GOOS=windows CC=x86_64-w64-mingw32-gcc CXX=x86_64-w64-mingw32-g++`). The Mac version has to be built on a Mac.

`./release.sh v1.0.0` publishes a GitHub release. You need [Go](https://go.dev/dl/) and the [GitHub CLI](https://cli.github.com/), logged in. It checks that no ROMs or Gimmick! graphics are tracked anywhere in the git history, and it runs the tests. Then it pushes the version tag, and `.github/workflows/release.yml` builds the program for Windows, Mac, and Linux and publishes it.
