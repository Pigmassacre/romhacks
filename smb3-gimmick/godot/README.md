# Yumetaro physics reference (Godot)

A frame-exact model of Yumetaro and his star from *Gimmick!* (Sunsoft, 1992), with a small test course drawn in rectangles. It is the reference implementation for [the physics guide](../docs/yumetaro-physics-guide.md). Like the hack it belongs to, it is AI-assisted.

Made with Godot 4.7. Open this folder in the editor and press Play, or run:

```bash
godot --path godot
```

| Key | |
|---|---|
| Arrows / WASD | move |
| Z / Space | jump (hold for height) |
| X | hold to charge the star, release to throw |
| F1 | debug overlay: collision boxes, the five collision points, live numbers |
| P | pause |
| . | advance one frame |
| R | restart |

A gamepad works too: D-pad, A to jump, X for the star.

## Layout

- `sim/` is the model. It has no nodes and no floats: you call `GimmickSim.step(held, pressed)` once per frame and read the state back. Every function names the routine in the original it was ported from.
- `game/main.gd` reads input, draws, and runs two demo objects (a walking enemy and a moving platform).
- `game/demo_level.gd` is the test course, as text. It is not a level from the game.
- `tests/` has the checks below.

## Checks

Against the real game. This needs your own `Gimmick! (Japan).nes` and `Mesen` in the repository folder; the first command records traces from the game into `out/gimtrace/`, the second replays them:

```bash
python3 tools/gim_physics_trace.py
```

```bash
godot --headless --path godot -s tests/verify_traces.gd -- ../out/gimtrace
```

Without the ROM:

```bash
godot --headless --path godot -s tests/play_level.gd
```

plays the test course with scripted input and checks each part of it, and

```bash
godot --headless --path godot -s tests/measure.gd
```

prints the jump heights, walk speeds and star bounces quoted in the guide.
