# Gimmick! (J) reverse-engineering notes

Findings from porting Yumetaro into SMB3. Everything here was verified against
`ref/gimmick` (JP disassembly) and/or by tracing in Mesen. Items marked
**(unverified)** are educated guesses.

For a complete, checked account of how Yumetaro and the star move, see
[yumetaro-physics-guide.md](yumetaro-physics-guide.md). Where the two disagree, the guide is right.

## Navigating the disassembly

- Mapper: Sunsoft FME-7, 8 KB PRG banks. 16 files of 16 KB, `GIMMICK-JPN<N>.asm`
  holds 8 KB banks `2N` (offsets `0000-1FFF`) and `2N+1` (offsets `2000-3FFF`).
- Labels `B<N>_xxxx` are **file offsets**, not CPU addresses. CPU address =
  window base + (`xxxx & $1FFF`), where the window depends on where the bank is
  mapped at runtime. Every file is labelled as if based at `$8000`, so operands
  like `jsr $8d5c` are CPU addresses, not label names.
- Bank `$1F` (file 15, offsets `2000-3FFF`) is fixed at `$E000`: `$F596` is
  `B15_3596`.
- The disassembler sometimes decodes data as code and misaligns the following
  instructions (e.g. `$F051` sits inside `B15_3050`). Dump raw bytes instead:
  `python3 tools/gimdump.py <bank> <cpu addr> [len]`, for example
  `python3 tools/gimdump.py 1E 83A1 3D`.
- Bank switching (fixed bank):
  - `$F051`: map bank `Y` at `$8000` (FME-7 cmd 9, shadow `$40`)
  - `$F05E`: map bank `Y` at `$A000` (FME-7 cmd `$0A`, shadow `$41`)
- `$F319`: inline jump table. `JSR $F319` with `A` = index, followed by `.word`s.
- `$F285`: queue sound effect `A` (4-entry queue at `$56`, write index `$5A`).
- Mesen write callbacks report the PC **after** the writing instruction.

### Main gameplay loop (`$E36D`, `B15_236D`)

```
jsr $8000          ; bank $1E: player update + draw  (B15_0000)
ldy #$1D / jsr $F051
jsr $8006          ; bank $1D: weapon (slot 1) update (B14_2006)
ldy #$10 / jsr $F051
jsr $8003          ; bank $10: objects/enemies      (B8_0003)
lda $0346 / bne +  ; health == 0 and not already dying ->
  $038C = 0, $90 = $D0 (death)
```

## RAM

See `ref/docs/gimmick_ram_map.txt` (Datacrystal) for the base map. Object
arrays have 10 slots: slot 0 = Yumetaro, slot 1 = weapon (star / fireball / bomb).
So `$90/$91` = status of player/star, `$C2/$C3` = Y vel, `$CC/$CD` = X vel, etc.

Additions / clarifications found while tracing:

| Address | Meaning |
|---|---|
| `$2B` | Max health. Set to **2** on new game (`$E135`). |
| `$0346` | Player health. |
| `$36-$38`, `$39` | Item inventory (3 slots) and item count. Item ids: 0 none, 1 medicine, 2 fireball, 3 bomb. |
| `$4B` | Jump hold: `$AC` on jump, 0 when A is released. |
| `$53` | Previous frame's `$036E` (to detect landing). |
| `$55` | Weapon lockout timer after using an item (`$50`). |
| `$E1`-`$E4` | Sprite CHR 1 KB slot shadows. `$E1` = PPU `$0000` (player page). |
| `$0300` | Player animation frame (0-21, see below). |
| `$0301` | Weapon animation frame. |
| `$030A` / `$030B` | Facing (0 = left, 1 = right) of player / weapon. |
| `$033C` | Half-width used for side tile probes (1/16 px units). |
| `$0351` | Weapon type in slot 1: 0 star, 1 fireball, 2 bomb. |
| `$035A` | Floor type under the object (from `$7D00`, see physics). `$88` = standing on something special (treated like ice for walking). |
| `$0364,x` | "Being stood on" flag for object x. |
| `$036E,x` | On floor (`$80`). `$036F` for the star. |
| `$0378,x` | Hit wall (`$80`). `$0379` for the star. |
| `$0382` | Player walk-animation counter (0-60). `$0383` = star's previous-frame floor flag. |
| `$038C` | **Player hurt timer** (`$7F` on hit, counts down). `$038D` = star still/vanish counter. |
| `$0397` | Star saved Y vel (pre-collision). |
| `$03A1` | Star saved X vel. |
| `$03C8,x` | Sprite flags: `$20` = behind background; bit0 toggles palette (star flicker). |
| `$7D00,t` | Per-metatile floor type table (0 = lethal, 1 = air **(unverified)**, 2+ see physics). |
| `$F5`/`$F7` bits | `$80` A, `$40` B, `$20` Select, `$10` Start, `$08` Up, `$04` Down, `$02` Left, `$01` Right. |
| `$7E00,t` | Per-metatile collision attributes (see physics). |
| `$7F00,t` | Per-metatile death variant, used when `$7D00,t == 0` (lethal tile). |

Positions are 16-bit, `tile:sub` with 1/16 px precision (`$B8:$AE` = X,
`$A4:$9A` = Y, 16 px tiles). The low nibble of the Y tile is the row on screen
(0-11; rows >= 12 are below the playfield). Velocities are signed 4.4 fixed
point in 1/16 px per frame, **the same convention as SMB3**, so constants port
1:1.

## Player control (bank `$1E` at `$8000`, `B15_0000`)

| CPU | What |
|---|---|
| `$8000` | Entry. If the player is dying (`$90 >= $D0`), a charging star vanishes (`>= $A0`) or is cancelled. |
| `$8026` | B held + Up held: use the item in `$36` (inline jump table after `jsr $F319`: 0 none `$804A`, 1 medicine `$804D`, 2 fireball `$807F`, 3 bomb `$808B`). Medicine refills `$0346 = $2B` (sound `$1C`). |
| `$8094` | Down newly pressed with >= 2 items: rotate item slots (sound `$14`). |
| `$80E4` | Normal update: status = 1, default frame = stand, or blink when `($ED & $DC) == 0`. |
| `$8116` | Tile under feet `$7E00 == $30` -> `$FCFD`, frame `$15` **(unverified: level exit/door)**. |
| `$8132` | If hurt timer >= `$66`: **stunned**. Skips all input; a charging star is released (`jmp $81FB`). |
| `$8149` | Horizontal input (below). |
| `$8186` | Landing sound `$0F` when `$036E` goes from clear to set. |
| `$8199` | Jump. |
| `$81C3` | Star charge. |
| `$81FB` | B released: throw or cancel. |
| `$82A1` | Walk animation. |
| `$82EA` | `ldx #0 / jsr $F596`: generic physics. |
| `$82EF-$83A0` | Stand-on-objects loop (slots 9..1). |
| `$83F5` | Draw: air frame, hurt frames, CHR page, metasprite. |

### Walking

- Accel per frame while holding L/R: `+2` (`$00`), or alternating `0/1` on ice
  (floor type 7, accel = `$ED & 1`). Only applied if `|vx| < 23` (`$17`, `$E9`).
- Holding a direction sets facing `$030A` (right = 1).
- Friction comes from the floor type in `$F596` (normal ground: -1/frame toward 0),
  so net ground accel is +1/frame and air accel is +2/frame. Ground speed
  oscillates 22/23 at the cap.

### Jumping

- `A` newly pressed (`$F5 & $80`) and on floor (`$036E` bit7): `vy = $AC` (-84),
  `$4B = $AC`, sound `$0D`.
- While `$4B != 0` and A is released: if `vy < -24` then `vy = -24` (`$E8`),
  `$4B = 0`.
- Gravity +4/frame, clamp at `$7F` (no real terminal velocity, about 8 px/frame).
- Peak about 53 px with A held.

### Stand on objects (`$82EF`)

Only runs when `vy >= 0`. For each slot y = 9..1 with `$D6,y` (standable) set:
`$FF13` tests if the player overlaps the object's top; then the tile at the
object's top is checked (no stand if solid there). On success:
`$0364,y = 1`, player `vx` gets ground friction (toward 0 by 1), `vy = 0`,
`$036E = $80` (player is "on floor" and can jump). Score combo bump if the
object has `$03B4/$03BE` set. The rider's position is carried by the generic
physics (`$F596` reads `$0364` to snap the rider onto the carrier's top).

### Walk animation (`$82A1`)

- If `|vx| < 2`: counter `$0382 = 4`, keep stand/blink frame unless L/R held.
- Otherwise `counter += 1 + (|vx| >> 4)`, wrap at 61 (`$3D`), and
  `frame = $83A1[counter]`.
- On ice / special floor with L/R held: the counter advances by 3 (A = 2, then `sec / adc`).
- Table `$83A1` (61 bytes): `7x2, 16x3, 7x4, 7x5, 17x6, 7x7`.
- In the air (not on floor, frame != `$15`): frame 8, `$0382 = $3B`.

## Generic object physics (`$F596`, fixed bank, X = slot)

Shared by the player, the star, and most objects.

1. Metatile at the object's own position: if `$7D00 == 0` it's a **lethal
   tile**. `$7F00` picks the variant: 0 gives status `$D0`; nonzero snaps Y
   (`$F5F9`), plays sound `$1E` and gives status `$D1`. Health, timer, vy and
   frame are zeroed.
2. If `$7E00 & $40`: slope handling at `$F9D1`.
3. Floor type = `max($7D00[x - $033C], $7D00[x + $033C])` -> `$035A,x`.
4. Jump on floor type via table `$F65C`:

   | Type | Handler | Effect |
   |---|---|---|
   | 0, 1 | `$F6F3` | air: gravity only |
   | 2 | `$F689` | normal ground: vx toward 0 by 1 |
   | 3 | `$F670` | conveyor right: X += 1 px, then friction |
   | 4 | `$F67E` | conveyor left: X -= 1 px, then friction |
   | 5 | `$F6CD` | push right: vx += 3 while vx < `$20` |
   | 6 | `$F6DB` | vx = max(vx, -`$10`), +1 while < `$20`, **skips gravity** |
   | 7 | `$F6A5` | ice: friction 1 only every 8th frame |

5. `$F6F3`: `vy += 4`, clamp to `$7F` on overflow.
6. `$F6FE`: X += vx, Y += vy (sign-extended 4.4).
7. Clear `$036E,x`/`$0378,x`, then collide: `$7E00` bit7 = solid. Ceiling
   (vy < 0) snaps below the tile. Floor uses `$7E00 & $C0 == $80` at both
   foot probes, then `vy = 0` and `$036E = $80`. Walls set `$0378`.

## Star (weapon slot 1, bank `$1D` at `$8000`, `B14_2000`)

`$8006` returns if `$91 == 0`, otherwise dispatches on `$0351`:
star `$8023`, fireball `$8171`, bomb `$82AB`.

### Status `$91`

| Value | State |
|---|---|
| 0 | none |
| `$7F`-`$A9` | charging (held over head) |
| 1 | thrown / active |
| 2 | (unverified) dying via `$FD6D`, same as player status 2 |
| `$D0` | vanish (16 frames, anim `$8C23[t]`) |
| `$D1` | vanish variant (32 frames, anim `$1B + t/4`) |

### Charge and throw (player bank, `$81C3` / `$81FB`)

- B held, no lockout (`$55`), not behind background (`$03C8`): if `$91 == 0` then sound
  `$10`, `$91 = $7F`, `$030B = 0`. Then `$91++` until `$A9` (42 frames).
- B released (or stunned while charging):
  - `$91 < $A0`: cancel (`$91 = 0`, `$D7 = 0`, `$0351 = 0`).
  - otherwise throw: `$91 = 1`, clear star wall/floor/counters, consume the
    inventory item if `$0351 != 0`, sound `$8608[type]` (star `$13`).
  - Spawn: X = player X, Y = player Y - `$83EC/$83E9[type]` (star: 16 px above).
  - Hitbox: `$0315 = $83EF[type]`, `$031F = $83F2[type]`, `$0329 = $70`, `$033D = $20`.
  - `vy = asr(player vy) + $83DE[type]`, clamp `$7F` on overflow (fireball: vy = 0).
  - `vx = asr(player vx) + $83E1[facing*4 + type]`.
  - Both are also stored in `$0397`/`$03A1` (saved velocities).

| Type | `$83DE` vy | `$83E1` vx (L / R) | Sound |
|---|---|---|---|
| 0 star | `$30` (+48, thrown downward) | `$D8` / `$28` (±40) | `$13` |
| 1 fireball | 0 (forced) | `$E8` / `$18` | `$44` |
| 2 bomb | `$D0` (-48) | `$E4` / `$1C` | `$13` |

### While charging (`$8071`)

The star follows the player (X = player X, Y = player Y - 16 px) and
`$0301 = $8C33[$91 & $7F]`. Table `$8C33` (`$2B` bytes) steps frames 0..17,
then frame `$14` at full charge.

### Thrown (`$80E7`)

In this order, every frame:

1. Tile at the star == `$30` -> `$FCFD`.
2. Wall hit last frame (`$0379` bit7): `vx = -saved_vx`, standable (`$D7 = $40`).
   Then `saved_vx = vx`.
3. Inside a solid tile (`$7E00` bit7): vanish (`$D0`).
4. `vx | vy == 0`: `$038D++`. When it reaches 8 (cumulative, never reset): vanish.
5. Floor hit last frame (`$036F` bit7):
   - sound `$15` if the star wasn't on the floor the frame before (`$0383`)
   - `vy = 8 - saved_vy`
   - standable
6. `saved_vy = vy`, `$0383 = $036F`.
7. `jsr $F596` with X = 1 (friction on floor, gravity, move, collide).
8. `$0301 = $14`. Palette flickers via `$03C9` bit0 = `$ED & 1`.

So the star only becomes standable after its first bounce or wall hit. With
gravity and the -1 floor friction, bounces go -52, -40, -28, ... and then it
rolls to a stop. The player rides it through the generic stand-on-objects loop
(`$D7 = $40`).

### Fireball (`$8171`, type 1)

Charge anim `$8C5E`. At full charge (`$A9`) frames `$3D + (($ED>>1)&3)`. Thrown:
`vx += 3` (right) / `-3` (left) per frame unless overflow; rolling animation
`$29 + n` (n 0..11, advanced by |vx|). Vanish anim `$35 + t/2`.

## Hurt / health

Contact-damage routine: `$8C7F` in bank `$10` (`B8_0C7F`).
`$8C76` / `$8CC1` is the player-vs-object box test, with `$04` = size.

- Only if `$038C == 0` and the player isn't dying (`$90 < $D0`).
- `$030A` = direction from the box test (face the enemy).
- `$0346--`, sound `$17`, `$038C = $7F`.
- Knockback: `vx = $12` (+18), negated when facing right, so he's pushed away
  from the enemy. `vy = $E8` (-24).
  **The SMB3 port does not apply this knockback.**
- Returns A = `$FF` if hurt, 0 if not.

Effects of the hurt timer (`$83F5` draw / `$8132` control):

- `$038C >= $66` (first 26 frames): stunned (no input), frame =
  `$85EE[$038C - $66]`.
  - Table `$85EE`: `14 14 13 13 12 12 11 11 10 10 0F 0F 0E 0E 0D 0D 0C 0C 0C 0C 0A 0A 0C 0C 0C 0C`
  - Read backwards in time: frame 12 (burst), 10, 12, then dizzy 13..20.
- `$038C < $66`: invincible and blinking (not drawn when `$038C & 2`).
- Health 0: status `$D0` (death), handled in the main loop.

## Graphics

### Player metasprites

- Frame pointer table: `$843D` (bank `$1E`), 22 frames, pointers into `$8469+`.
- Frame data: groups of `[dy, tile, attr, dx]`, terminated by `dy == 0`.
  dy/dx are signed offsets from the object position (Y is the feet, so the body
  is at about dy -17, the horn at about -33). 8x16 sprite mode; tile is an even
  index in the `$0000` pattern table.
- Facing left mirrors: `attr ^= $40` and the X offset is reflected around the
  object X.
- CHR page per frame: `$85CE` (written to `$E1`, PPU `$0000-$03FF`).
  Frames 0-9 and 21 use page `$0C`; frames 10-20 use page `$0D`.
- Attribute low bits pick the palette: 0 = body, 1 = horn.
- Draw routine: `$F468` (generic, fixed bank) with `$00/$01` = pointer table.

| Frame | Pose |
|---|---|
| 0 | stand |
| 1 | blink |
| 2-7 | walk cycle |
| 8 | jump / air |
| 9 | jump variant (mouth open) |
| 10 | hurt squint |
| 11 | hurt / angry face (used as SMB3 death toss in the port) |
| 12 | orange impact burst |
| 13-20 | dizzy stars orbiting the head, fading |
| 21 | facing the camera (level transitions, `$15`) |

`tools/render_gim_frames.py` renders all of them, as in `out/gim_frames.png`.

### Star and effect tiles

- Page `$08` is mapped in the second sprite slot (PPU `$0400`) during stages.
- Star: tile `$40` (left half) drawn twice, the right half H-flipped.
- Charge sparkle: `$50`. Charge rays: `$2E`/`$3E` on page `$0C`.
- Trail: 3 past positions kept in `$0420-$043D`.

### Palettes

Sprite palettes in ROM at `$F041` (fixed bank; BG palette just before it):

```
pal0 0F 0B 2A 30   body: dark green / green / white
pal1 0F 06 30 27   horn: brown / white / orange (runtime PPU showed $07 for colour 1)
pal2 0F 0F 00 30
pal3 0F 05 25 30
```

The star alternates pal0/pal1 every frame.

## Sound effect ids (`jsr $F285`)

| Id | Use |
|---|---|
| `$0D` | jump |
| `$0F` | land |
| `$10` | star charge start |
| `$13` | star / bomb throw |
| `$14` | item select rotate |
| `$15` | star bounce (first floor contact) |
| `$17` | player hurt |
| `$1C` | medicine |
| `$1E` | lethal tile (death variant `$D1`) |
| `$1F` | stop music (queued the moment health hits 0) |
| `$2F` | death jingle, queued 24 frames after `$1F` |
| `$44` | fireball throw |

The death jingle (`$2F`) is 100 frames of 2A03 square 1, square 2 and noise plus all three 5B
channels. The squares play retriggered 4-frame notes with the hardware sweep on (`$8B`, rising
chirps), periods `1FC 153 07F 054` on square 1 and `1FE 155 081 056` on square 2, 3 frames
later. Volume steps down every 16 frames: `F B 9 6 3 1`. Noise steps through periods
`14 13 12 11` with the same fade. Each 5B channel plays a 20-frame falling sweep (P `$7F` to
`$1AB`), loud then repeated quieter: A starts on frame 1, B on frame 6, C on frame 21.

## Where this went in the SMB3 port

| Gimmick | Port |
|---|---|
| Walk/jump/gravity constants | `GIM_*` in `src/smb3.asm`, `Gim_GndMov` in `src/PRG/gim_player.asm` |
| Walk table `$83A1` | `Gim_WalkFrames` |
| Hurt table `$85EE`, stun at `$66` | `Gim_HurtFrames`, `GIM_STUNTIME`, `Gim_AnimHurt` |
| Metasprites `$843D` / `$85CE` | generated by `tools/gen_frames.py` -> `src/PRG/gim_frames.asm` |
| CHR pages `$0C`/`$0D` + star tiles from `$08` | `tools/build_chr.py` -> SMB3 CHR pages `$50`/`$51` (written to `out/chr/` at build time) |
| Star (`B14_2023`) | `src/PRG/gim_star.asm` |
| Stand on objects | `Gim_StandOnEnemy` / `Gim_RideRotate`, `Gim_StarRide`, `Gim_Cannonball` (cannonball special objects, also star hits) |
| Health `$2B`/`$0346` | `Gim_MaxHealth` / `Gim_Health` (port starts at 3, cap 6) |
| Death sounds `$1F` + `$2F` | `Player_Die` queues `MUS1_STOPMUSIC` and `GimDeath_Data`; 2A03 writes replayed, the 5B voices folded onto the triangle (`tools/gim_death_data.py`) |

Not ported yet: hurt knockback, star bounce sound `$15`, star trail, the
fireball and bomb items, the medicine item, and conveyor / push floor types.

## Tracing tips

- `tools/gim_trace.lua` / `gim_boot.lua`: boot the Gimmick ROM to stage 1
  (about 600 frames; press Start only until gameplay starts, or it pauses) and
  log writes to chosen RAM with the PC and the `$40`/`$41` bank shadows.
- `tools/gim_ppu.lua` / `pal_dump.lua`: dump OAM, pattern tables and palettes.
- Run headless: `./Mesen --testRunner "Gimmick! (Japan).nes" tools/<script>.lua`.
