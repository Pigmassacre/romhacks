# Yumetaro Physics Guide

How Yumetaro and his star move in *Gimmick!* (Sunsoft, Famicom, 1992), written so that you can rebuild them exactly.

Everything here comes from the Japanese ROM's code. Each rule names the routine it comes from, so you can check it. A reference implementation in Godot is in [`godot/`](../godot); it reproduces the real game frame for frame (see [How this was checked](#how-this-was-checked)).

**Contents**

1. [Basics](#1-basics)
2. [The world](#2-the-world)
3. [One frame](#3-one-frame)
4. [Walking](#4-walking)
5. [Jumping](#5-jumping)
6. [Object physics](#6-object-physics)
7. [Slopes](#7-slopes)
8. [Standing on things](#8-standing-on-things)
9. [The star](#9-the-star)
10. [Getting hurt](#10-getting-hurt)
11. [Dying](#11-dying)
12. [Tubes](#12-tubes)
13. [Items](#13-items)
14. [Animation](#14-animation)
15. [Quirks](#15-quirks)
16. [Constants](#16-constants)
17. [The reference implementation](#17-the-reference-implementation)
18. [How this was checked](#how-this-was-checked)

---

## 1. Basics

### Units

The game runs at 60 frames per second and does everything once per frame. There is no delta time.

| Quantity | Unit | Notes |
|---|---|---|
| Position | 1/16 pixel | 16-bit. High byte = tile, low byte = position inside the tile. 16 units = 1 px, 256 units = 1 tile (16 px). |
| Velocity | 1/16 pixel per frame | Signed byte, -128 to 127. So the fastest anything can move is just under 8 px per frame. |
| Time | frame | 1/60 s. |

This guide writes positions as `tile.sub` in hex, for example `1A.00`, and velocities as plain signed numbers. A velocity of 16 is 1 px per frame.

**An object's position is the middle of its feet.** X is its centre, Y is its bottom edge. Y grows downward.

The Y tile byte holds two things: the high nibble is the *vertical screen* (0-3) and the low nibble is the *row* on that screen (0-11). See [Screens](#screens).

### Object slots

There are ten object slots. Every per-object variable is an array of ten.

| Slot | Used for |
|---|---|
| 0 | Yumetaro |
| 1 | His weapon: the star (or a fireball or bomb) |
| 2-9 | Enemies, platforms, pickups |

Yumetaro and the star run their own code, then call one shared routine for movement and tile collision ([Object physics](#6-object-physics)). Most enemies call the same routine. That is why the star slides on slopes and rides conveyors exactly as Yumetaro does.

### Variables

`x` is the slot number. For Yumetaro read the address as written, for the star add 1.

| Address | Name here | Meaning |
|---|---|---|
| `$90,x` | status | 0 = empty, 1 = active, 2 = in a tube, `$D0`+ = dying. The star has more values, see [The star](#9-the-star). |
| `$B8,x` : `$AE,x` | X | tile : sub |
| `$A4,x` : `$9A,x` | Y | tile : sub |
| `$CC,x` | vx | signed |
| `$C2,x` | vy | signed, positive is down |
| `$D6,x` | standable | `$40` = Yumetaro can stand on this object |
| `$0300,x` | frame | animation frame |
| `$030A,x` | facing | 0 = left, 1 = right |
| `$031E,x` : `$0314,x` | height | feet to head |
| `$0332,x` : `$0328,x` | half width | used for walls and for hits |
| `$033C,x` | foot half width | used for floors |
| `$0346,x` | health | |
| `$035A,x` | floor type | what the object is standing in, see [Floor types](#floor-types) |
| `$0364,x` | rider | 1 = Yumetaro is standing on this object |
| `$036E,x` | on floor | `$80` = yes |
| `$0378,x` | hit wall | `$80` = yes |
| `$0382,x` | timer 1 | Yumetaro: walk animation counter. Star: was it on the floor last frame. |
| `$038C,x` | timer 2 | Yumetaro: hurt timer. Star: rest and vanish counter. |
| `$03C8,x` | flags | `$20` = drawn behind the background; bit 0 = palette flicker |

Globals:

| Address | Meaning |
|---|---|
| `$F7` / `$F5` | Buttons held / newly pressed this frame. `$80` A, `$40` B, `$20` Select, `$10` Start, `$08` Up, `$04` Down, `$02` Left, `$01` Right. |
| `$ED` | Frame counter, plus one every frame. Several effects key off its low bits. |
| `$16` | Current vertical screen, 0-3. |
| `$15` : `$14` | Camera X, same units as a position. |
| `$2B` | Maximum health. 2 at the start of a new game. |
| `$4B` | Jump hold. `$AC` while a jump can still be cut short. |
| `$53` | Was Yumetaro on the floor last frame (for the landing sound). |
| `$55` | B lockout timer, set after using medicine. |
| `$0351` | Weapon type in slot 1: 0 star, 1 fireball, 2 bomb. |
| `$0397` / `$03A1` | The star's vy and vx as they were before its last move. |

### Sizes

| | Height | Half width | Foot half width |
|---|---|---|---|
| Yumetaro | 14 px (`$E0`) | 6 px (`$60`) | 3 px (`$30`) |
| Star | 15 px (`$F0`) | 7 px (`$70`) | 2 px (`$20`) |

Yumetaro's sprite is 16 px wide and about 17 px tall plus his horn. His collision box is smaller: 12 px wide, 14 px tall. Against enemies he is narrower still, 3 px either side of centre ([Getting hurt](#10-getting-hurt)).

Tile collision never uses a box. It uses **five points**:

```
          C            C  ceiling point: centre, at the top of the box
       .-----.
       |     |
     W |     | W       W  wall points: half width out, 8 px above the feet
       |     |
       '-F-F-'         F  floor points: foot half width out, at the feet
```

Because the floor points are only 3 px from centre, Yumetaro can hang 3 px of his box, and 5 px of his sprite, over an edge.

---

## 2. The world

### The map

A stage is a grid of 16 px metatiles held in RAM at `$6000`. It is four vertical screens, each 128 columns wide and 12 rows tall, stored column by column (`$600` bytes per screen, 12 bytes per column). The tile at column `c`, row `r` of screen `s` is at `$6000 + s*$600 + c*12 + r`.

The code only ever reads the map of the **current** vertical screen (`$16`). An object's own screen nibble is ignored for collision.

Three 256-byte tables give each metatile its behaviour:

| Table | Meaning |
|---|---|
| `$7D00` | Floor type: what standing in this tile does. 0 = deadly. |
| `$7E00` | Collision attributes (bits below). |
| `$7F00` | Variant: which death a deadly tile gives, or which behaviour a slope has. |

Collision attribute bits (`$7E00`):

| Bit | Meaning |
|---|---|
| `$80` | Solid. Blocks walls and ceilings. It is a floor only if `$40` is clear. |
| `$40` | Slope. The floor is a curve inside the tile, chosen by the low nibble. |
| `$20` | Objects here are drawn behind the background (doorways, tube mouths). |
| `$10` | With `$40`: this tile is filler under a slope, and the surface belongs to the tile above. |
| `$0F` | Slope shape, 0-15. |

The exact value `$30` means a **tube** tile ([Tubes](#12-tubes)).

In practice four kinds of solid tile exist: plain solid (`$80`), slope (`$40 | shape`), slope filler (`$D0`), and tube (`$30`). The whole inside of the ground is usually filler (`$D0`), not plain solid.

### Floor types

`$7D00` for the tile an object's feet are in. Standing on the ground means the feet are at the very top of the ground tile, so this is the tile being stood on. In the air it is the tile of air the feet are in, which is type 1.

| Type | Effect each frame | Used in |
|---|---|---|
| 0 | Deadly. See [Dying](#11-dying). | all stages |
| 1 | Nothing. Air, and solid tiles nobody is meant to stand on. | all stages |
| 2 | Friction: vx moves 1 toward 0. Normal ground. | all stages |
| 3 | X + 1 px, then friction. Conveyor to the right. | stages 1, 5 |
| 4 | X - 1 px, then friction. Conveyor to the left. | stages 1, 5, 7 |
| 5 | If vx < 32: vx + 3. | never |
| 6 | vx is raised to at least -16; if vx < 32: vx + 1. **No gravity this frame.** | never |
| 7 | Friction of 1, but only on frames where `$ED & 7` is 0. Ice. | stage 6 |

Types 5 and 6 are in the code but no stage map uses them.

A solid tile with floor type 1 has no friction at all: anything standing on it keeps its speed. The stage maps use type 1 for wall and corner tiles, where it rarely matters.

Slopes set the floor type themselves, to `$80`, `$87` or `$88` ([Slopes](#7-slopes)).

### Screens

A vertical screen is 12 rows, but rows 0 and 11 are shared with its neighbours: row 11 of one screen is the same strip of the world as row 0 of the screen below. So screens are 176 px apart, and the playable rows of a screen are 1-11.

At the start of each frame (`$E2F6`) the game looks at Yumetaro's row:

- **Row 0:** he moves to row 11 of the screen above.
- **Row 12:** he moves to row 1 of the screen below.

The screen number wraps around 0-3. His position inside the tile and his velocity are untouched, so he keeps falling or rising straight through.

When the screen changes:

- Every object in slots 2-9 is removed.
- The star is removed too, unless it is still being charged.
- The game then stops completely for 4 frames while the new screen is drawn. Even the frame counter stops.

There is no vertical scrolling. The camera only moves sideways.

An object whose row is 12 or more is off the map: the physics routine skips all tile checks for it and it falls freely.

### World edges

After everything has moved (`$E394`), Yumetaro is kept inside the map:

- If X < `00.80`: X = `00.80`, vx = 0.
- If X ≥ `7F.80`: X = `7F.7F`, vx = 0.

Only Yumetaro is clamped. Nothing stops other objects.

### Camera

Routine: bank `$1E` `$8FA3`. The camera wants Yumetaro exactly 8 tiles (128 px) from its left edge:

```
target = Yumetaro X - 08.00
delta  = target - camera X
camera X += clamp(delta, -128, +127)       ; units, so at most about 8 px per frame
```

Since Yumetaro never moves that fast on his own, the camera is normally locked to him with no lag and no dead zone.

A table at `$7BE0`, indexed by `(X tile & $70) / 4 + vertical screen` (one entry per 16-column screen), can hold the camera still. If bit 7 is set and Yumetaro is in the left half of that screen (`X tile & 8` is 0), or bit 6 is set and he is in the right half, then `target = start of that screen`. Stages use this to stop the camera at the ends of rooms. The low six bits of the entry choose the music.

---

## 3. One frame

The main loop is at `$E26A`. In order:

| Step | Routine | What |
|---|---|---|
| 1 | `$E2F6` | Vertical screen change, if Yumetaro reached row 0 or 12. |
| 2 | bank `$1E` `$8000` | **Yumetaro**: items, input, his animation, his physics, standing on objects. |
| 3 | bank `$1D` `$8006` | **The star**: its own logic, then its physics. Carries Yumetaro if he rides it. |
| 4 | bank `$10` `$8003` | **Everything else**: each enemy tests the star against itself, moves, then tests itself against Yumetaro. |
| 5 | `$E380` | If health is 0, start the death. Keep Yumetaro inside the map. |
| 6 | bank `$1E` `$8FA3` | Camera. |
| 7 | bank `$1D` `$8003` | Draw the star and its after-images. Remove a star that left the screen. |
| 8 | bank `$10` `$8000` | Draw the other objects. |
| 9 | bank `$1E` `$83F5` | Draw Yumetaro. This also picks his in-air frame and counts down the hurt timer. If he is dying, the death routine (bank `$1D` `$8D85`) runs instead. |

The order matters in a few places:

- Yumetaro moves before the star. On the frame he throws it, the star appears where he was at the end of the *previous* frame and then moves once.
- Yumetaro tests whether he is standing on an object (step 2) before that object moves (step 3 or 4). The object then drags him along when it moves.
- An enemy's touch is tested after Yumetaro's input for the frame. The knockback velocity is set in step 4 and first moves him on the next frame.

---

## 4. Walking

Routine: bank `$1E` `$8149`. Skipped while stunned ([Getting hurt](#10-getting-hurt)).

```
accel = 2
if (floor type & $7F) == 7:  accel = $ED & 1        ; ice: 0, 1, 0, 1, ...

if Right held:
    facing = right
    if vx - 23 is negative:   vx += accel           ; so only while vx <= 22
if Left held:
    facing = left
    if vx + 23 is not negative:  vx -= accel        ; so only while vx >= -23
```

Then the [physics routine](#6-object-physics) applies the floor's friction (1 per frame on normal ground), and moves him.

That is the whole of it. There is no separate top speed, no run button, and no separate air control: the same code runs in the air, where there is no friction.

Both directions are tested if both are held (on a real controller they cannot be). Right is tested first, so facing ends up left and the two accelerations cancel.

### What that gives

| | Ground | Air |
|---|---|---|
| Speeding up | +1 per frame (2 from input, -1 friction) | +2 per frame |
| Slowing down, nothing held | -1 per frame | none: he keeps his speed |
| Turning round | -3 per frame until 0 | -2 per frame |
| Top speed, right | 22 and 23 on alternate frames = **1.406 px/frame** | 24 = 1.5 px/frame |
| Top speed, left | 23 and 24 on alternate frames = **1.469 px/frame** | 25 = 1.5625 px/frame |

**He is faster going left.** The two tests are not mirror images: right accelerates while `vx <= 22`, left while `vx >= -23`. See [Quirks](#15-quirks).

From a standstill on flat ground, holding Right, vx at the end of each frame is 1, 2, 3 ... 22, 23, 22, 23, ... He reaches top speed on frame 23 and has covered 27 px after 30 frames. Letting go at top speed he stops in 22 frames after 14.4 px.

### On ice

Acceleration is 0 or 1 on alternate frames (half a unit per frame on average, a quarter of normal), and friction is 1 every eighth frame. From a standstill he takes 59 frames to reach top speed instead of 23. Letting go at top speed he slides for 177 frames and 126 px, instead of 22 frames and 14 px.

Ice also changes the walk animation: while a direction is held the animation counter advances by 3 per frame whatever his real speed, so his feet spin on the spot.

### On a conveyor

A conveyor moves him 1 px per frame (16 units) on top of whatever vx does, and has normal friction. Walking with it is about 2.4 px/frame. Walking against it he still makes headway, at about 0.4 px/frame.

The conveyor shift happens **before** the move and is not part of vx. Jumping off a conveyor does not carry its speed into the air.

### Facing

Facing is set by the direction held, at once, whichever way he is actually moving. With nothing held it keeps its last value. Being hurt also sets it ([Getting hurt](#10-getting-hurt)).

---

## 5. Jumping

Routine: bank `$1E` `$8199`.

```
if A newly pressed and on floor:
    vy = -84                      ; $AC
    jump hold = $AC
    play jump sound

if jump hold != 0 and A not held:
    if vy < -24:  vy = -24        ; $E8
    jump hold = 0
```

Gravity is in the physics routine: `vy += 4` every frame, capped at 127.

- "On floor" is the flag from the **previous** frame's collision. It is set by ground, by slopes, and by standing on an object.
- There is no coyote time: one frame after walking off an edge the flag is clear and A does nothing.
- There is no jump buffering: A must be newly pressed on a frame where he is on the floor. Holding A does not re-jump on landing.
- Jumping does not change vx. A jump from a standstill goes straight up; a jump at a run carries the run speed.

### Jump height

Releasing A while he is still rising faster than 24 sets his upward speed to 24. Once A has been released the jump cannot be cut again (and pressing A again in the air does nothing).

The first frame of a jump already includes one step of gravity, so he leaves the ground at 80, not 84.

| A held for | Peak height | Time in the air |
|---|---|---|
| 1 frame | 8.75 px | 14 frames |
| 2 | 13.5 | 17 |
| 3 | 18.0 | 20 |
| 4 | 22.25 | 22 |
| 5 | 26.25 | 24 |
| 6 | 30.0 | 26 |
| 8 | 36.75 | 30 |
| 10 | 42.5 | 33 |
| 12 | 47.25 | 36 |
| 14 | 51.0 | 39 |
| 15 or more | **52.5** | **40** |

A full jump peaks 20 frames after leaving the ground. At a full run to the right it covers 58.9 px, a little over three and a half tiles.

vy at the end of each frame of a full jump:

```
-80 -76 -72 -68 -64 -60 -56 -52 -48 -44 -40 -36 -32 -28 -24 -20 -16 -12 -8 -4
  0   4   8  12  16  20  24  28  32  36  40  44  48  52  56  60  64  68  72  76   (lands)
```

### Falling

`vy += 4` per frame with no limit until it would pass 127, where it stays. That is 7.94 px per frame, reached after 32 frames and about 124 px of falling.

Because the cap is under 8 px, a falling object can never skip over the top half of a tile, which is all the floor test looks at.

### Hitting his head

A ceiling sets vy to 0 and puts his head exactly at the underside of the tile ([Ceilings](#ceilings)). He starts falling from rest on the next frame. The jump hold stays set, so nothing odd happens when A is released later.

---

## 6. Object physics

Routine: `$F596`, in the fixed bank. Called with the slot in X. This one routine moves Yumetaro, the star, and most enemies.

In outline:

```
1. remember the old X (for carrying a rider)
2. if the row is 12 or more:  gravity, move, skip to 9
3. look at the tile the feet are in
     deadly?  -> die, return
     slope?   -> slope code replaces steps 4 and 5
4. floor type effect (friction, conveyor, ...)
5. gravity
6. move:  X += vx,  Y += vy
7. clear "on floor" and "hit wall"
8. collide:   slope tile -> slope landing
              else rising -> ceiling
              else        -> floor
              then walls
9. if something is riding this object, carry it
```

### Step 3: the tile at the feet

The tile at `(X tile, row)`. If its floor type is 0, the object dies on the spot: see [Dying](#11-dying). Note the test is on the **centre** of the feet only, so he can stand with one foot over spikes.

If the tile has the slope bit, jump to the slope code ([Slopes](#7-slopes)).

### Step 4: floor type

Two tiles are read, on the same row: the one under the left foot point (`X - foot half width`) and the one under the right (`X + foot half width`). The floor type used is the **larger** of the two. So with one foot on a conveyor (3) and one on ground (2), he is on the conveyor; with one foot on ice (7) and one on anything else, he is on ice.

The effect is then applied as in the [floor type table](#floor-types). Friction never takes vx through 0:

```
friction(vx, n):
    if vx >= 0:  vx -= n;  if vx < 0:  vx = 0
    else:        vx += n;  if vx >= 0: vx = 0
```

### Step 5: gravity

```
vy += 4
if that overflowed past 127:  vy = 127
```

Gravity is applied every frame, on the ground too. Standing still, an object's vy goes 0 → 4, it moves 0.25 px into the floor, and the floor test puts it back and zeroes vy.

### Step 6: move

`X += vx` and `Y += vy` as 16-bit additions. X and Y move together, in one step, with no sub-stepping.

If the new row is 12 or more, skip to step 9.

### Floors

Routine: `$F7D3`. Used when vy ≥ 0 and the tile at the feet is not a slope.

```
row = Y tile & 15
for the left foot point, then the right:
    tile = map[point's column][row]
    if (attributes & $C0) == $80:              ; solid and not a slope
        if Y sub < $80:                        ; feet in the top half of the tile
            Y sub = 0
            vy = 0
            on floor = yes
        stop
```

So landing means: a foot point is inside a solid tile and no more than 8 px deep. The object is lifted to the tile's top edge.

Things that follow from this:

- If the feet are in the bottom half of a solid tile, there is no floor. The object keeps falling through it. This cannot happen from a fall (the cap is under 8 px per frame) but can if something else puts him there.
- If the left foot point's X is negative, the whole test is skipped.
- The right point is only tested if it lies in a different column from the left one.

### Ceilings

Routine: `$F761`. Used when vy < 0 and the tile at the feet is not a slope.

```
head = Y - height
row  = head tile & 15;   if row >= 14:  row = 0
tile = map[X tile][row]                         ; one point, at the centre
if solid:
    vy = 0
    Y = (head tile + 1 + height tile) : height sub      ; head against the underside
```

Only the centre is tested. A ceiling corner that the centre misses does not stop him: the wall test deals with it instead, pushing him sideways.

If the object is carrying Yumetaro, his height is added to the probe, and on a hit the object is put directly under him instead ([Standing on things](#8-standing-on-things)).

### Walls

Routine: `$F88C`. Runs after the floor or ceiling test, every frame.

```
row = (Y - 8 px) tile & 15
left:   tile = map[(X - half width) tile][row]
        if solid:
            if vx < 0:  vx = 0
            hit wall = yes
            X += 1 px
            done                                  ; the right side is not tested
right:  tile = map[(X + half width) tile][row]
        if solid:
            if vx >= 0: vx = 0
            hit wall = yes
            X -= 1 px
```

**A wall pushes back by exactly 1 px per frame.** It does not snap the object to the wall's edge. An object that moves into a wall by more than 1 px in a frame stays partly inside it and is squeezed out over the following frames. Yumetaro walks at under 1.5 px per frame, so he sinks in by half a pixel at most. The star moves at 2.5 px per frame or more and goes several pixels in; that is fine, because it turns round the next frame.

Each side has one point, 8 px above the feet. A wall that is only 8 px or less above the floor (the bottom half of a tile) is not seen, and neither is one that starts above head height.

While walking into a wall with the direction held, vx is zeroed each frame, input adds 2, friction takes 1, so he moves 1/16 px in, and the wall pushes 1 px out. His X jitters by a pixel. "Hit wall" is set every frame, which matters to the star.

### Out of range

The map reads are not bounds-checked. A row above the top of the screen wraps into the previous column, and a column past 127 reads whatever follows the map. The ceiling test treats rows 14 and 15 as row 0, and several tests skip themselves when X is negative. Stages are walled in, so none of this is normally reachable.

---

## 7. Slopes

A slope tile has attribute `$40 | shape`. The surface is a height for each of the 16 pixel columns of the tile, from the table at `$FBE8` (index = pixel column × 16 + shape). The value is the distance from the **top** of the tile down to the surface, in 1/16 px.

### Shapes

Surface depth in pixels below the top of the tile, for pixel columns 0 to 15 left to right:

| Shape | Depths | What it is |
|---|---|---|
| 0 | 15 14 13 12 11 10 9 8 7 6 5 4 3 2 1 0 | 45° rising to the right |
| 1 | 0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 | 45° falling to the right |
| 2 | 15 15 14 14 13 13 12 12 11 11 10 10 9 9 8 8 | gentle rise, lower half |
| 3 | 7 7 6 6 5 5 4 4 3 3 2 2 1 1 0 0 | gentle rise, upper half |
| 4 | 0 0 1 1 2 2 3 3 4 4 5 5 6 6 7 7 | gentle fall, upper half |
| 5 | 8 8 9 9 10 10 11 11 12 12 13 13 14 14 15 15 | gentle fall, lower half |
| 6 | 9 8 7 6 5 4 3 3 2 2 1 1 1 0 0 0 | curve rising to the right, levelling off |
| 7 | 0 0 0 1 1 1 2 2 3 3 4 5 6 7 8 9 | curve falling to the right, steepening |
| 8 | 15 15 14 14 14 13 13 13 12 12 12 12 11 11 11 11 | shallow rise, lowest quarter |
| 9 | 11 11 11 11 12 12 12 12 13 13 13 14 14 14 15 15 | shallow fall, lowest quarter |
| A | 0 0 1 1 1 2 2 2 3 3 3 3 4 4 4 4 | shallow fall, top quarter |
| B | 4 4 4 4 3 3 3 3 2 2 2 1 1 1 0 0 | shallow rise, top quarter |
| C | 6 4 3 2 2 1 1 1 1 1 1 2 2 3 4 6 | hump |
| D | 0 0 1 1 2 2 3 3 4 4 5 5 6 7 8 10 | fall, steepening at the end |
| E | 6 4 3 2 1 1 0 0 0 0 0 0 0 0 0 0 | rounded left corner |
| F | 0 0 0 0 0 0 0 0 0 0 1 1 2 3 4 6 | rounded right corner |

Shapes 2+3 and 4+5 are pairs: two tiles side by side make a ramp that rises one tile over two.

### Landing on a slope

Routine: `$F838`. After the move, if the tile at the centre of the feet is a slope:

```
tile = map[X tile][row]
if tile has the filler bit ($10):
    Y tile -= 1;  Y sub = $F0            ; step up to the bottom of the tile above
    tile = the tile above
depth = height table[(X sub & $F0) | (tile attributes & 15)]
if Y sub >= depth:
    Y sub = depth
    vy = 0
    on floor = yes
```

Notes:

- Only the **centre** of the feet is used on slopes. The two foot points are for flat floors only, and they ignore slope tiles.
- This runs whatever the sign of vy. An object moving upward that is below the surface is snapped to it too.
- The tile under a slope must be filler (`$D0`). Walking from flat ground into the column of a rising slope puts the feet into the filler; the filler rule lifts him into the slope tile above, and the depth test puts him on the surface.
- Walls and ceilings still use only the solid bit. A slope tile (`$40`, no `$80`) does not block from the side, which is what lets him walk into it. Filler (`$D0`) does block.

### On a slope

Routine: `$F9D1`. If the tile at the feet is a slope at the *start* of the physics routine, this replaces the floor type and gravity steps.

```
floor type = $80
depth = height table[...]
if Y sub < depth:                        ; above the surface: just fall
    vy += 4   (capped at 127)
    go to "move"

run the slope's behaviour ($7F00 of the tile)      ; changes vx and maybe X
Y += 3 px                                ; press into the slope
go to "move"                             ; no gravity this frame
```

The 3 px push is what keeps an object glued to a slope while going downhill: it is pushed under the surface, and the landing code lifts it back onto it. At more than 3 px per frame downhill on a 45° slope an object would leave the surface, and nothing goes that fast.

Because gravity is skipped, vy stays 0 on a slope. Because the normal floor type step is skipped, **a slope has no friction unless its behaviour gives it some**.

### Behaviours

The tile's `$7F00` byte picks one of 20. "wobble" is `2 + ($ED & 1)`: 2 and 3 on alternate frames. The floor type decides how the walk input and animation treat it: `$87` counts as ice (acceleration 0/1), and `$87` and `$88` both use the fixed animation speed.

| # | Floor type | Effect on vx (and X) each frame |
|---|---|---|
| 0 | `$80` | vx -= wobble, no lower than -48. Steep: slides left. |
| 1 | `$80` | vx += wobble, no higher than 48. Steep: slides right. |
| 2 | `$80` | if vx ≥ -40: vx -= 1. Gentle: slides left. |
| 3 | `$80` | if vx < 40: vx += 1. Gentle: slides right. |
| 4 | `$80` | if vx ≥ -32: vx -= pull, where pull by pixel column is 4 4 3 3 2 2 1 1 1 1 0 0 0 0 0 0 |
| 5 | `$80` | if vx < 32: vx += pull, where pull is 0 0 0 0 0 0 1 1 1 1 2 2 3 3 4 4 |
| 6 | `$88` | X -= 1 px; vx -= wobble, no lower than -16 |
| 7 | `$88` | X += 1 px; vx += wobble, no higher than 16 |
| 8 | `$88` | if vx ≥ -32: vx -= 1 |
| 9 | `$88` | if vx < 32: vx += 1 |
| 10 | `$88` | friction 1. A slope you can stand still on. |
| 11 | `$80` | X += 1 px; friction 1. Conveyor slope to the right. |
| 12 | `$80` | X -= 1 px; friction 1. Conveyor slope to the left. |
| 13 | `$87` | as 0 |
| 14 | `$87` | as 1 |
| 15 | `$87` | as 2 |
| 16 | `$87` | as 3 |
| 17 | `$80` | X += 10/16 px; friction 1 |
| 18 | `$80` | X += 7/16 px; friction 1 |
| 19 | `$80` | X -= 7/16 px; friction 1 |

Which shape goes with which behaviour, in the seven stage maps:

| Stage | Shape / behaviour pairs |
|---|---|
| 1 | 0/0, 1/1, 2/2, 3/2, 4/3, 5/3 |
| 2 | none |
| 3 | 0/0, 1/1, 2/2, 3/2, 4/3, 5/3, 6/4, 7/5, 0/6, 1/7 |
| 4 | 0/8, 2/8, 3/8, 4/9, 5/9, 8/10, 9/10, A/10, B/10 |
| 5 | 2/2, 3/2, 4/3, 5/3, 6/4, 7/5, and 2-5 and D-F with 11 or 12 |
| 6 | 0/13, 1/14, 2/15, 3/15, 4/16, 5/16, 6/17, 7/17, C/18, C/19 |
| 7 | none |

### What Yumetaro does on the common slopes

**Gentle slopes (behaviours 2 and 3)** pull him downhill by 1 per frame up to a speed of 40, which is well above his walking speed.

- Standing still, he slides down, speeding up.
- Walking uphill: +2 from input, -1 from the slope. He climbs, gaining 1 per frame as on flat ground, to the usual top speed.
- Walking downhill: input stops at the usual 23, but the slope keeps adding until 40 (2.5 px/frame).
- He cannot stop on one. There is no friction, so only input holds him, and input alone is too strong: holding uphill makes him climb.

**Steep slopes (behaviours 0 and 1)** pull by 2.5 per frame up to 48 (3 px/frame). Input gives 2, so walking uphill loses half a unit per frame. He can be carried a short way up by speed he already has, and no further: from a full run he gets 29 px up a 45° slope, not quite two tiles.

**Standable slopes (behaviour 10)** have ordinary friction. They behave like flat ground that is not flat.

Jumping from a slope works as from ground: "on floor" is set, vy is 0 at the moment of the jump, and vx is whatever the slope has made it. A jump from a downhill slide can be much longer than a normal one.

---

## 8. Standing on things

Yumetaro can stand on any object whose standable flag (`$D6,x`) is `$40`. This is how he rides the star, and it is the same code for enemies and platforms. He never "stomps": standing on an enemy does nothing to it.

### The test

Routine: bank `$1E` `$82EF`, after his own physics. It only runs when his vy ≥ 0. If he is moving up, every object's rider flag is cleared and nothing else happens.

Slots are tried from 9 down to 1. For each standable object:

```
top = object Y - object height
d   = Yumetaro Y - top
need:  0 <= d < 8 px                                  ; feet at the top or up to 7 15/16 px below it
need:  -(reach) <= Yumetaro X - object X < reach      ; reach = object half width + his foot half width
need:  the tile 9 px above the object's top, at the object's X, is not solid
```

On the first object that passes:

```
object's rider flag = 1
vx = friction(vx, 1)
vy = 0
on floor = yes
(all lower slots' rider flags are cleared)
```

Only the flags change here. His position is not touched. "On floor" being set means he can jump off, and the landing sound plays.

For the star the reach is 7 + 3 = 10 px either side of its centre. For an enemy of his own size it is 6 + 3 = 9 px.

The third condition means he cannot stand on an object that is tight under a ceiling.

### Being carried

Routine: `$F926`, the last step of the *object's* physics, when its rider flag is set.

```
dx = (object X, sub rounded down to a whole pixel) - (the same before the move)
Yumetaro X += dx
Yumetaro Y = object Y - object height            ; feet on its top

s = |object vx|
if the tile at Yumetaro's left wall point is solid:    Yumetaro X += s
else if the tile at his right wall point is solid:     Yumetaro X -= s
```

- He is moved by whole pixels of the object's movement, so he keeps his own sub-pixel position on top of it.
- His own vx still applies: he can walk about on the object. His feet are in air, so the floor gives him no friction, but the stand test takes 1 off vx each frame. Walking on an object therefore feels the same as walking on ground.
- If the ride takes him into a wall, he is pushed back by the object's speed each frame, so he is scraped off as it goes on without him.
- His Y is set from the object every frame, so he follows it up and down exactly, including each bounce of the star.

### A carrier under a ceiling

When an object with a rider moves upward, its ceiling test adds Yumetaro's height to its own, so the test point is the top of his head. On a hit the object's vy becomes 0 and the object is placed directly beneath him, where he is now. So the star cannot push him into a ceiling.

### Frame order

He tests for standing before the object moves, using the object's position from the previous frame. Each frame while riding: his physics adds gravity and drops him 0.25 px, the stand test passes and zeroes vy, then the object moves and sets his Y back onto its top.

Jumping off: A sets vy to -84, his physics moves him up, the stand test sees vy < 0 and clears the rider flag.

---

## 9. The star

The star lives in slot 1. Its status (`$91`) is its whole state:

| Status | State |
|---|---|
| `$00` | None. |
| `$80`-`$A9` | Being charged, held over Yumetaro's head. Counts up one per frame. |
| `$01` | Thrown. |
| `$02` | Travelling through a tube. |
| `$D0` | Vanishing, 16 frames. |
| `$D1` | Vanishing, 32 frames (used by other weapons and some enemies). |

There is only ever one. A new one cannot be started until the old one is completely gone, including its vanish animation.

### Charging

Routine: bank `$1E` `$81C3`. Skipped while stunned, and while the star is thrown, in a tube or vanishing.

```
if Yumetaro is behind the background ($03C8 != 0)  or  B lockout != 0  or  B not held:
    release                                       ; see below
else:
    if status == 0:
        play charge sound
        status = $7F
    if status != $A9:  status += 1
```

So on the first frame B is held the status becomes `$80`, and it rises by one each frame to `$A9`, where it stays for as long as B is held.

| Frames B has been held | Status | |
|---|---|---|
| 1 | `$80` | charge starts |
| 33 | `$A0` | can now be thrown |
| 42 | `$A9` | fully charged |

**Release** (`$81FB`): if the status is below `$A0`, the star is simply dropped (status 0). At `$A0` or above it is thrown. So B must be held for at least 33 frames, a little over half a second. Nothing is gained by charging past that point except the animation: a throw at 33 frames is identical to a throw at 42.

While charging, the star is placed each frame at Yumetaro's X and exactly 16 px (one tile) above his feet, so its bottom edge rests 2 px above the top of his head. He can walk and jump freely.

Other ways a charge ends:

- **Stunned** by a hit: the release runs at once. A charge of 33 frames or more is thrown; a shorter one is lost.
- **Dying**: a charge of 33 or more turns into the vanish animation; a shorter one disappears.
- **Behind the background** (a tile with attribute `$20`, such as a doorway): treated as letting go of B.
- **Vertical screen change**: the charge survives. A thrown star does not.

### The throw

Routine: bank `$1E` `$820D`.

```
star X = Yumetaro X
star Y = Yumetaro Y - 16 px
star height = 15 px,  half width = 7 px,  foot half width = 2 px
star facing = Yumetaro facing
clear the star's on floor, hit wall and rest counter

star vy = half(Yumetaro vy) + 48          ; if that overflows a signed byte: 127
star vx = half(Yumetaro vx) + 40          ; facing right
        = half(Yumetaro vx) - 40          ; facing left
saved vy = star vy;  saved vx = star vx
status = 1
play throw sound
```

`half` is an arithmetic shift right: it halves and rounds toward minus infinity (`half(23) = 11`, `half(-23) = -12`).

**The star is thrown downward**, at 3 px per frame, and forward at 2.5 px per frame. Half of Yumetaro's own velocity is added to each.

| Thrown while | Star vx | Star vy |
|---|---|---|
| standing | ±40 | 48 |
| running, same direction | 51 (right), -52 (left) | 48 |
| just after jumping (vy -80) | ±40 | 8 |
| at the top of a jump | ±40 | 48 |
| falling at 60 | ±40 | 78 |
| falling at 126 | ±40 | 111 |
| falling at 127 (the cap) | ±40 | **-17**, see [Quirks](#15-quirks) |

The direction is his facing on the frame of the throw. The walk input runs earlier in the same frame, so pressing a direction on the frame B is released aims the throw that way.

The star is not standable yet: its standable flag stays clear until its first bounce or wall hit.

### In flight

Routine: bank `$1D` `$80E7`. Each frame, in this order:

```
 1. t = the tile at the star's centre (its X, 8 px above its bottom; rows 12+ count as row 11)
    star's "behind background" flag = t's $20 bit
 2. if t is a tube tile:  enter the tube, return
 3. if hit wall (from last frame's physics):
        vx = -saved vx
        standable = yes
 4. saved vx = vx
 5. if t is solid:  vanish, return
 6. if vx == 0 and vy == 0:  rest counter += 1
 7. if rest counter >= 8:  vanish, return
 8. if on floor (from last frame's physics):
        if it was not on the floor the frame before:  play bounce sound
        vy = 8 - saved vy
        standable = yes
 9. saved vy = vy
10. remember whether it was on the floor
11. run the shared object physics on it            ; friction, gravity, move, collide, carry rider
12. frame = star;  palette flicker bit = $ED & 1
```

The star has no physics of its own beyond steps 3 and 8. Gravity, friction, slopes, conveyors, ice, walls, floors and ceilings are all the [shared routine](#6-object-physics), with the star's sizes.

### Bouncing

The physics routine lands the star like anything else: it snaps to the floor and its vy becomes 0. On the next frame, step 8 gives it `vy = 8 - saved vy`, where saved vy is the vy it had going into the move that landed it (before that frame's gravity).

So each bounce reverses the fall speed and takes 8 off. Counting the gravity step on each side, a bounce comes back about 12 slower than it went down.

A star thrown while standing on flat ground:

| Event | Frame after throw | Distance from throw point | Height of the arc before it |
|---|---|---|---|
| 1st landing | 5 | 10 px | (falls 16 px from his head) |
| 2nd landing | 32 | 76 px | 22.8 px |
| 3rd landing | 51 | 121 px | 11.2 px |
| 4th landing | 62 | 146 px | 3.8 px |
| 5th landing | 65 | 153 px | 0.2 px |
| stops rolling | 101 | 192 px | |
| starts to vanish | 109 | 192 px | |
| gone | 125 | | |

A harder throw bounces higher. Thrown while falling at 44, the first bounce reaches 69 px.

**Rolling.** Once the bounces are too small to leave the ground, the star is "on floor" every frame. Step 8 then settles at `saved vy = 4, vy = 4` each frame, which gravity and the floor cancel.

**Friction.** The star only gets floor friction on frames where its feet are in a floor tile at the start of the physics routine: the frame after each landing, and every frame while rolling. So each bounce costs 1 of vx, and rolling costs 1 per frame. From a standing throw it lands with vx 40, 39, 38, 37, then rolls from 36 down to 0.

On ice the star hardly slows. On a conveyor it is carried. On a gentle slope it speeds up downhill to 40, and on a steep slope to 48.

### Walls and ceilings

A wall zeroes the star's vx, sets "hit wall", and pushes it out 1 px. On the next frame step 3 sets `vx = -saved vx`: the speed it had before hitting, reversed, with nothing lost. A wall hit also makes the star standable.

A ceiling just zeroes vy. The star does not bounce off ceilings; it starts to fall.

### When it disappears

| Cause | How |
|---|---|
| Its centre is inside a solid tile | vanish animation |
| It has been at rest (vx and vy both 0 at step 6) for 8 frames in total | vanish animation |
| It is 13 or more rows down the screen | removed at once |
| Its tile is 3 or more columns left of the camera's left edge, or 18 or more right of it | removed at once |
| The vertical screen changes | removed at once |
| Some enemies, when it hits them | vanish animation |

The off-screen test (bank `$1D` `$84FD`) works in whole tiles: `d = star X tile - camera X tile`; the star is kept only while `-3 <= d < 18`. The screen is 16 tiles wide, so a star can go about two tiles off the right edge or three off the left. With the camera centred on Yumetaro, that is about 10 tiles ahead of him or 11 behind. On open ground a thrown star usually leaves the screen before it stops.

The **rest counter** is never reset during a flight. It counts every frame on which both velocities are exactly 0 at step 6, which includes the frame after each landing if vx is 0. A star bouncing straight up and down therefore uses up one count per landing, and one more for any frame at the top of an arc where vy is exactly 0.

The vanish animation (status `$D0`) takes 16 frames. The star does not move or collide during it, cannot be stood on, and blocks a new charge until it ends.

### Riding it

Once standable, the star passes the [stand test](#8-standing-on-things) like any object. While Yumetaro is on it:

- He is carried by whole pixels of its movement and his Y follows its top.
- It keeps bouncing, rolling and slowing exactly as it would without him. He adds no weight.
- When it reverses off a wall he goes with it, unless the wall is beside him too, in which case he is pushed off.
- When it stops, the rest counter runs out in 8 frames and it vanishes from under him.

Since it only becomes standable at its first bounce, and the first bounce is the highest, the usual way to board is to throw it and jump onto it as it comes up.

### Against enemies

There is no general rule in the star's code. **Each enemy tests the star against itself** by calling a shared box test (bank `$10` `$8D48`) and then does what it likes with the answer.

The test, which only counts a star with status 1:

```
dy = star Y - enemy Y                               ; both are bottoms
if dy < 0:   need  enemy height + dy >= 0           ; star's bottom not above the enemy's top
else:        need  dy <= star height                ; star's top not below the enemy's bottom
need  |star X - enemy X| < enemy half width + star half width      (7 px for the star)
```

On a hit the test takes 1 from the enemy's health, and adds to the score if that kills it. What the caller does next falls into three patterns:

1. **Weak enemies** die and the star carries on through them, unchanged.
2. **Tough enemies** make the star vanish (status `$D0`) whether or not they die.
3. **Solid objects** (platforms, shells) call a second routine, `$8E8F`, which does no damage. If the star's bottom is within 8 px below the object's top, the star is put on the top and flagged "on floor", so it bounces off it next frame. Otherwise it is flagged "hit wall" and moved to the object's edge, so it reverses. This only happens while the star is moving down or level.

### After-images and flicker

The star's last five positions are kept (bank `$1D` `$8469`). Besides the star itself, the positions from 2 and 4 frames ago are drawn, as long as those were plain star frames. That is the trail.

The star's palette alternates every frame (`$ED & 1`), and the same bit applies while charging.

---

## 10. Getting hurt

### The touch test

Like the star test, this is called by each enemy on itself (bank `$10` `$8C7F`). It does nothing if the hurt timer is not 0 or Yumetaro is already dying.

```
dy = Yumetaro Y - enemy Y
if dy < 0:   need  (Yumetaro Y - 8 px) >= enemy top       ; the point 8 px above his feet is at or below its top
else:        need  dy <= 6 px
need  |Yumetaro X - enemy X| < enemy half width + 3 px
```

Yumetaro is only 3 px wide either side of centre for this, and vertically he is a single point 8 px above his feet. That is much smaller than his sprite.

Standing on an enemy is safe: his feet are at its top, so the point 8 px above them is above the top, and the test fails.

### The hit

```
facing = toward the enemy
health -= 1
play hurt sound
hurt timer = $7F
vx = 18 away from the enemy
vy = -24
```

If that takes health to 0, the death starts at the end of the same frame.

### The hurt timer

The timer drops by 1 each frame when Yumetaro is drawn, starting on the frame of the hit. Call that frame 0.

| Frames | Timer | State |
|---|---|---|
| 0 | `$7F` → `$7E` | Hit. Knockback velocity set. |
| 1-25 | `$7E`-`$66` | **Stunned.** No input is read: no walking, jumping, charging or items. Physics still runs, so he flies back and lands. A star being charged is released. |
| 26-126 | `$65`-`$01` | Control is back. **Cannot be hurt.** He flickers: drawn for 2 frames, hidden for 2. |
| 127 | `$00` | Can be hurt again. |

During the stun he is not on a normal animation: see [Animation](#14-animation).

The knockback is an ordinary velocity. On open flat ground he hops 3.75 px, lands after 10 frames, and friction then stops him: 20 px back in all, at rest 28 frames after the hit, just as the stun ends. A wall behind him stops it at once.

Only enemy contact uses this. Deadly tiles kill outright ([Dying](#11-dying)) and ignore the timer.

---

## 11. Dying

Yumetaro dies when his health reaches 0, or when the centre of his feet is in a tile with floor type 0.

### Deadly tiles

Routine: `$F5D6`, at the top of the physics routine. The tile's variant (`$7F00`) picks the kind:

| Variant | Y sub set to | Status | Sound |
|---|---|---|---|
| 0 | unchanged | `$D0` | none |
| 1 | `$70` | `$D1` | `$1E` |
| 2, 3 | `$00` | `$D1` | `$1E` |

Health, the hurt timer, vy and the animation frame are all set to 0, and the physics routine returns without moving the object. Variant 0 is used for pits, the others for spikes and the like.

This applies to **any** object that uses the shared physics. A star whose feet enter a deadly tile gets status `$D0` or `$D1`, which for the star is its vanish animation.

### Status `$D0`: the burst

Routine: bank `$1D` `$8DD7`.

| When | What |
|---|---|
| First frame | Music stops. He holds his pose (the jump frame if in the air). **The whole game stops for 24 frames.** |
| Then | The death jingle starts. Four frames of a short animation, one frame each. |
| Then | He is replaced by 16 balls that fly apart in 16 directions at 63/16 px per frame (just under 4). The respawn timer is set to 192. |
| 192 frames later | The stage reloads from the last checkpoint with full health, one life less. |

The ball velocities are `63 × (sin, -cos)` of multiples of 22.5°, in 1/16 px per frame: X = 0, -24, -45, -58, -63, -58, -45, -24, 0, 24, 45, 58, 63, 58, 45, 24, and Y is the same list starting four places earlier (-63, -58, -45, -24, 0, 24, ...).

### Status `$D1`: spikes

Routine: bank `$1D` `$8DA3`. The status becomes `$D2` at once, the music stops, and the respawn timer is set to 192. He plays an 8-frame animation at 4 game frames each (32 frames), then is not drawn. There is no 24-frame stop and no burst.

### While dying

His update is skipped entirely: no input, no physics. If a star was being charged it vanishes or is dropped ([Charging](#charging)). Everything else keeps running, except during the 24-frame stop.

---

## 12. Tubes

A tube is a chain of tiles with attribute `$30`. An object that touches one is carried along it at 2 px per frame. Yumetaro and the star both use them.

### Entering

Yumetaro: at the start of his update, the tile at his X and **8 px above his feet** is read. If it is a tube tile he enters it, his animation frame becomes "facing the camera", and the rest of his update (input, physics) is skipped. The star does the same with the tile at its centre.

Routine `$FCFD`. The low three bits of the **metatile id** choose one of six paths. Whether the path is run forward or backward depends on where in the tile the object is:

```
q = 2 * (bit 7 of (Y sub - $10))  +  (1 if X sub >= $80)
reverse = entry table[path * 4 + q]        ; $FEDB
```

| Path | Forward | Reverse when |
|---|---|---|
| 0 | left → right | entered in the right half |
| 1 | top → bottom | **the object is moving up** (vy < 0); the table is ignored for this path |
| 2 | right → centre → down | Y sub is `$10`-`$8F` |
| 3 | bottom → centre → left | Y sub is below `$10` or above `$8F` |
| 4 | top → centre → right | Y sub is below `$10` or above `$8F` |
| 5 | left → centre → up | Y sub is `$10`-`$8F` |

For path 0 only, the Y tile is also adjusted on entry so the object's feet sit on the bottom edge of the tube tile.

### Travelling

Routine `$FD6D`. Status is 2. For 8 frames the object's position **inside the tile** is set straight from a table: X sub and Y sub each step by `$20` (2 px) along the path. Velocity is not used. Horizontal runs keep the feet on the tile's bottom edge (Y sub 0 of the next row down) and vertical runs keep X centred (`$80`).

On the 8th step the object is put just inside the next tile, its status goes back to 1, and it is given an exit velocity of 32 (2 px per frame) in the direction of travel.

On the next frame, if it is in another tube tile, it enters that one and the journey continues: each tile takes 8 frames. If not, it is out, moving at 2 px per frame, and ordinary physics takes over.

A vertical tube that crosses row 0 or row 12 changes the vertical screen in the usual way, mid-journey.

Tube tiles are not solid. Something standing over the open end of a vertical tube falls in.

---

## 13. Items

Yumetaro can carry up to three items (`$36`-`$38`, count in `$39`): 1 medicine, 2 fireball, 3 bomb. Only the first slot is used. The reference implementation covers the inventory and medicine but **not** the fireball and bomb, and this section is less thoroughly checked than the rest.

- **Down** (newly pressed) rotates the slots, if there are at least two items and no charge is in progress.
- **Up + B** uses the first slot.
  - **Medicine**: needs B newly pressed. Refills health to the maximum, and sets the B lockout to 80 frames. The lockout only counts down while B is held, and is cleared when B is released; until then B does not start a charge. It is refused at full health unless he holds three items.
  - **Fireball / bomb**: sets the weapon type, if no weapon is out. The charge that starts on the same frame is then that weapon instead of a star. The item is used up when it is thrown, not when it is selected, so a cancelled charge keeps it.

**Fireball** (bank `$1D` `$8171`): thrown from 8 px above his feet with vx ±24 plus half of his, and no vertical speed. It ignores gravity and tiles. Each frame its vx grows by 3 in the direction it faces, without limit other than a signed byte. It leaves sparks behind and is removed off-screen like the star.

**Bomb** (bank `$1D` `$82AB`): thrown with vx ±28 and vy -48, plus half of his. It uses the shared physics. It can be stood on from the start. On landing it bounces with half the speed it came down with, and loses 1 extra vx per landing. It explodes when its centre is in a solid tile or it has been at rest for 8 frames. The explosion lasts 25 frames with a growing hit box.

---

## 14. Animation

Yumetaro has 22 frames (0-21):

| Frame | Pose |
|---|---|
| 0 | standing |
| 1 | blink |
| 2-7 | walk cycle |
| 8 | in the air |
| 10, 12, 13-20 | hurt: squint, impact burst, then dizzy stars fading out |
| 21 | facing the camera (in tubes and doorways) |

Each frame, in this order:

1. **Stand or blink** (`$80E4`): frame 1 if `$ED & $DC` is 0, else frame 0. That is two blinks of 4 frames each, 32 frames apart, in every 256 frames.
2. **Walk** (`$82A1`): see below. Overrides step 1 when he is moving.
3. **Air** (`$83F5`, at draw time): if not on the floor and not frame 21, frame 8, and the walk counter is set to `$3B`.
4. **Hurt** (`$83F5`): while the hurt timer is `$66` or more, the frame comes from the stun table.

### Walk cycle

A counter (`$0382`) runs from 0 to 60 and the frame is looked up from it.

```
if floor type is $88, or (floor type & $7F) is 7:        ; ice and some slopes
    if neither Left nor Right is held:  leave the frame alone
    step = 3
else if |vx| < 2:
    counter = 4
    if neither Left nor Right is held:  leave the frame alone
    step = 1
else:
    step = 1 + |vx| / 16                                  ; 1 while walking, 2 from speed 16 up

counter = (counter + step) mod 61
frame = walk table[counter]
```

Walk table: counter 0-6 → frame 2, 7-22 → 3, 23-29 → 4, 30-36 → 5, 37-53 → 6, 54-60 → 7.

Landing leaves the counter at `$3B` (frame 7), so the cycle restarts from the same place after every jump. Pushing against a wall with vx at 0 or 1 holds the counter at 4-5, frame 2.

### Stun table

Indexed by hurt timer minus `$66`. Shown here in the order it plays, one entry per game frame, starting on the frame of the hit:

```
12 12 12 12 10 10 12 12 12 12 13 13 14 14 15 15 16 16 17 17 18 18 19 19 20 20
```

(Frame 12 is the impact burst, 10 the squint, 13-20 the dizzy stars.)

### The star

| Status | Frame |
|---|---|
| Charging, `$80`-`$9B` | 0 to 13, two game frames each |
| Charging, `$9C`-`$9F` | 14 |
| Charging, `$A0`-`$A8` | 15, 15, 15, 16, 16, 16, 17, 17, 17 |
| Charging, `$A9` | 20: the finished star |
| Thrown | 20 |
| Vanishing `$D0` | 21 21 22 22 23 23 24 24 23 23 24 24 25 25 26 26 |

---

## 15. Quirks

Things the original does that you might not expect, and would have to copy on purpose.

**Left is faster than right.** The speed tests are `CMP #$17 / BPL` and `CMP #$E9 / BMI`. The first stops acceleration at 23; the second stops it at -24. On the ground that is 1.406 px/frame right against 1.469 left, about 4% faster.

**The comparisons are not really signed.** `CMP / BPL` only looks at the sign of the 8-bit difference. For values more than 127 apart it gives the wrong answer. Nothing in normal play reaches those values, but it means, for example, that Right stops accelerating him when vx is -106 or lower.

**A throw at terminal velocity goes up.** The throw halves his velocity with `CMP #$7F / ROR`, which uses the carry to copy the sign bit. `CMP #$7F` sets the carry for any value from `$7F` up, so exactly 127, the falling speed cap, is treated as negative and becomes -65. The star is then thrown at vy -17 instead of +111. This follows from the code and the reference implementation reproduces it, but it was not caught in a recording of the real game.

**Walls push 1 px per frame.** See [Walls](#walls). Fast objects sink into walls and come back out slowly.

**Only the top half of a tile is a floor.** Feet more than 8 px into a solid tile fall through it.

**No friction on slopes or type 1 tiles.** A slope only has friction if its behaviour says so, and a solid tile with floor type 1 has none.

**The floor is decided by three different sets of points.** Flat floors by the two foot points, slopes by the centre, deadly tiles by the centre. He can stand with a foot over a pit, and standing on the join of ground and ice counts as ice.

**Conveyor speed is not momentum.** It is a position shift, lost the moment he leaves.

**The star does not become rideable until it touches something.**

**The rest counter never resets**, so a star can vanish mid-bounce if its earlier landings used up the count.

**Charging past 33 frames changes nothing but the picture.**

**The release code runs every frame.** Whenever B is not held and no star is out, the "drop the star" branch runs and clears the weapon type. That is why an item selection only holds if the charge starts on the same frame.

**Everything stops for 24 frames when he dies**, and for 4 frames on a vertical screen change.

---

## 16. Constants

Velocities are in 1/16 px per frame; divide by 16 for pixels.

| | Value | Hex | Where |
|---|---|---|---|
| **Yumetaro** | | | |
| Walk acceleration | 2 | `$02` | `$1E:8149` |
| Ice acceleration | 0 / 1 alternating | | `$1E:8156` |
| Speed test, right / left | 23 / -23 | `$17` / `$E9` | `$1E:8167`, `$817D` |
| Jump velocity | -84 | `$AC` | `$1E:81A0` |
| Jump cut velocity | -24 | `$E8` | `$1E:81B7` |
| Gravity | 4 | `$04` | `$F6F5` |
| Fall speed cap | 127 | `$7F` | `$F6FA` |
| Ground friction | 1 | | `$F689` |
| Ice friction | 1 every 8th frame | | `$F6A5` |
| Conveyor shift | 16 (1 px) | `$10` | `$F670`, `$F67E` |
| Height / half width / foot half width | 224 / 96 / 48 | `$E0` / `$60` / `$30` | RAM |
| Half width against enemies | 48 | `$30` | `$10:8C7F` |
| Hurt timer | 127 | `$7F` | `$10:8CA0` |
| Stunned while timer ≥ | 102 | `$66` | `$1E:8135` |
| Knockback vx / vy | 18 / -24 | `$12` / `$E8` | `$10:8CA5` |
| Starting maximum health | 2 | | `$E135` |
| **Star** | | | |
| Charge start / throwable / full | | `$7F` / `$A0` / `$A9` | `$1E:81E9`, `$81FD`, `$81F2` |
| Frames to throwable / full | 33 / 42 | | |
| Throw vx | ±40 | `$28` / `$D8` | `$1E:83E1` |
| Throw vy | 48 | `$30` | `$1E:83DE` |
| Spawn height above his feet | 256 (16 px) | `$0100` | `$1E:83E9` |
| Height / half width / foot half width | 240 / 112 / 32 | `$F0` / `$70` / `$20` | `$1E:83EF`, `$825C`, `$8261` |
| Bounce | vy = 8 - saved vy | | `$1D:8143` |
| Rest frames before vanishing | 8 | | `$1D:812D` |
| Vanish length | 16 frames | `$10` | `$1D:80E2` |
| Kept on screen while | -3 ≤ tile − camera tile < 18 | | `$1D:8510` |
| **Slopes** | | | |
| Steep pull / limit | 2 or 3 / 48 | / `$30` | `$FA40` |
| Gentle pull / limit | 1 / 40 | / `$28` | `$FA85` |
| Push into slope | 48 (3 px) | `$30` | `$FA55` |
| **Other** | | | |
| Tube step / exit speed | 32 (2 px) | `$20` | `$FE1B`, `$FEF3` |
| Death stop | 24 frames | `$18` | `$1D:8E07` |
| Respawn delay | 192 frames | `$C0` | `$1D:8E78` |
| Screen change stop | 4 frames | | measured |
| Camera offset / top speed | 8 tiles / 127 | `$0800` / `$7F` | `$1E:8FA9`, `$9007` |

### Sound cues

| Id | When |
|---|---|
| `$0D` | jump |
| `$0F` | landing (the first frame "on floor" after a frame without it) |
| `$10` | charge starts |
| `$13` | star thrown |
| `$15` | star's first frame on a floor after being off it |
| `$17` | hurt |
| `$1E` | spikes |
| `$1F` | stop music (death) |
| `$2F` | death jingle |

---

## 17. The reference implementation

[`godot/`](../godot) is a Godot 4 project. Open it in the editor and run it, or:

```bash
godot --path godot
```

Arrow keys or WASD move, Z or Space jumps, X charges and throws the star. F1 toggles the debug overlay (collision boxes, the five collision points, and the live numbers), P pauses, `.` advances one frame, R restarts.

| Section of this guide | Code |
|---|---|
| Units, variables | `sim/gimmick_body.gd` |
| The map and attribute tables | `sim/gimmick_world.gd` |
| Every data table | `sim/gimmick_tables.gd` |
| One frame | `GimmickSim.step` |
| Walking, jumping | `_walk_input`, `_player_update` |
| Object physics | `physics`, `_floor`, `_ceiling`, `_walls` |
| Slopes | `_slope_floor`, `_slope_land` |
| Standing on things | `_stand_on_objects`, `_stand_test`, `_carry_rider` |
| The star | `_charge_input`, `_release_star`, `_throw`, `_weapon_update`, `_star_draw_phase` |
| Star against enemies | `star_touches`, `star_collide_solid` |
| Getting hurt | `hurt_player`, `touch_test`, `_player_draw_phase` |
| Dying | `_lethal_tile`, `_death_update` |
| Tubes | `_tube_enter`, `_tube_step` |
| Camera, screens | `_update_camera`, `_vertical_screen_change` |
| Animation | `_walk_animation`, `_player_draw_phase` |

`sim/` has no dependency on the scene tree. It is a plain model you step with the controller state, and it uses integers throughout, in the game's own units. `game/` draws it with rectangles and adds two demo objects, a walking enemy and a moving platform, written the way the original's enemies are: they call `star_touches`, `physics` or `move_object`, and `hurt_player` on themselves.

The demo level (`game/demo_level.gd`) is not from the game. It is a test course with one of everything: steps and a low ceiling, gentle, steep and standable slopes, conveyors, ice with an icy hill, spikes, a pit, enemies, a platform, a hole down to a second screen, and a tube back up.

Not implemented: the fireball and bomb, item pickups, score, lives and checkpoints (a death simply restarts the course), and the original's enemies.

---

## How this was checked

The rules were read from the ROM, then tested against the game itself.

`tools/gim_physics_trace.py` runs the real game in Mesen through 21 scripted scenarios on stage 1 and records Yumetaro's and the star's full state at the end of every frame, along with the buttons, the frame counter and the map. `godot/tests/verify_traces.gd` feeds the same buttons to the reference implementation and compares 45 values per frame: both objects' status, position, velocity, flags, timers, animation frame and sizes, plus the camera and the jump, lockout and saved-velocity variables.

```bash
python3 tools/gim_physics_trace.py
```

```bash
godot --headless --path godot -s tests/verify_traces.gd -- ../out/gimtrace
```

**All 26,612 frames match exactly.**

What the scenarios cover: walking, turning, every length of jump, walls, edges, ceilings, cancelled and minimum charges, throws while standing, running, rising and falling, bounces, wall rebounds, riding the star (including into walls), gentle slopes, conveyors, the tube at the end of the first room including its vertical screen change, a hit, a fatal hit, both tile deaths, respawn timing, and a star left behind by the camera.

Some things stage 1 does not have near its start, so the scenarios create them by changing the game's memory: the ground's floor type is set to ice (7) and to the unused types 5 and 6, and the two hills' slope behaviour is set to each of the 20 values in turn. That checks the code for each, on the shapes stage 1 has.

What was **not** compared against the running game, and rests on reading the code alone:

- The enemy touch test and the star-against-enemy tests. The traces confirm the *result* of a hit (knockback, timers, stun, death) but the enemy positions were not recorded, so the box tests themselves are unverified.
- Slope shapes 6 to F. Their heights come straight from the table, and the code that uses them is shape-independent.
- Tube paths 2, 4 and 5, and upward travel. The stage 1 tube uses paths 0, 1 and 3, downward.
- Upward vertical screen changes.
- Items, the fireball and the bomb.
- The terminal-velocity throw.

The traces are made from your own ROM and are not in the repository.

### Routine index

| Address | Routine |
|---|---|
| `$E26A` | Main loop |
| `$E2F6` | Vertical screen change |
| `$E380` | Health check, world edges |
| `$F596` | Object physics |
| `$F5D6` | Deadly tile |
| `$F60D` | Floor type |
| `$F6F3` / `$F6FE` | Gravity / move |
| `$F761` / `$F7D3` / `$F838` / `$F88C` | Ceiling / floor / slope landing / walls |
| `$F926` | Carry rider |
| `$F9D1` | On a slope; behaviours at `$FA13` |
| `$FBE8` | Slope height table |
| `$FCE8` | Move and collide only (platforms) |
| `$FCFD` / `$FD6D` | Tube enter / step |
| `$FF13` | Stand test |
| `$1E:8000` | Yumetaro update |
| `$1E:8149` / `$8199` / `$81C3` / `$81FB` / `$820D` | Walk / jump / charge / release / throw |
| `$1E:82A1` / `$82EF` / `$83F5` | Walk animation / stand on objects / draw |
| `$1E:8FA3` | Camera |
| `$1D:8006` | Weapon update; star at `$8023`, in flight at `$80E7` |
| `$1D:8469` | Star draw, after-images, off-screen removal |
| `$1D:8D85` | Death |
| `$10:8C7F` / `$8CC1` | Hurt / touch test |
| `$10:8D48` / `$8E8F` | Star hit test / star against a solid object |

`$1E:` and `$1D:` are 8 KB PRG banks mapped at `$8000`; `$10:` likewise. Addresses with no bank are in the fixed bank at `$E000`. See [gimmick-notes.md](gimmick-notes.md) for how to find them in the disassembly.
