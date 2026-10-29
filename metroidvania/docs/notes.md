# Notes on the two ROMs

Working notes from making Metroidvania: what was found in Castlevania (USA) and Metroid (USA), and why the hack does things the way it does. Castlevania's names follow the partly labelled disassembly by josephstevenspgh (`Castlevania-Labelled-Disassembly`); Metroid's follow [m1disasm](https://github.com/metroidret/m1disasm).

## Castlevania

### Banks and the NMI

UNROM: 8 banks of 16 KB, bank 7 fixed at `$C000`. `SwitchBank` (`$C1D6`) maps bank Y by writing to `$C000,Y`, where bytes `$C000-$C007` hold 0-7 (so there is no bus conflict), and remembers it in `$27`.

The whole game runs in the NMI (`$C052`); the main loop only stirs a random number. In order: OAM DMA, the update buffer (`$800A`, bank 0), PPUMASK, the status bar split (`$F87D`), the scroll, the music (`$838A`, bank 0), the controllers, the game logic (`$C1E4`, bank 6), the sprites (`$8052`, bank 0). If the logic overruns, the next NMI finds `$1B` set and only does PPUMASK, the split, the scroll and the music (if `$7F`, "in the sound code", is clear), and then returns into the interrupted code. Its music path maps bank 0 and then maps `$27` back, so `$27` has to be right whenever the hack's bank is in.

### RAM the hack uses

Over the attract demos and long stretches of play, Castlevania never writes `$0100-$012F`, `$01B2-$01E5` (its stack stays above `$01E6`) or `$07CF-$07F0`. With the hack the stack reaches `$01D9`, so the hack uses `$01B2-$01C0` only. `tests/t_ramguard.lua` checks both.

### Objects

28 slots of arrays from `$0300`: slot 0 is Simon, 1-3 the whip and the gate cutscene, 4-`$13` enemies, candles and items, `$14-$16` subweapons, `$17-$1A` moving platforms (stages 4, 5 and 10). Positions are on the screen (`$038C` x, `$0354` y); when the level scrolls, `$EB08` moves every object by `$49`, if `$3C` (bits 0-1 the direction, bit 2 "Simon moves, not the screen") says the screen scrolled.

Enemies come from six generators (`$0166`, with their x on the screen in `$0172` and side in `$0160`), and candles are objects; both are loaded a 64 pixel column at a time as the screen scrolls (`$D196`, the column ahead by `$3C`). `$F5EA` does that once a frame, when the frame ends with the scroll on a column's edge, which Simon, scrolling a pixel a frame, always does. Samus can scroll two pixels a frame and step over an edge; the column is then never loaded, and its generator not replaced: the hall's zombies went on coming in the Phantom Bat's room. The hack loads the column at every pixel it scrolls onto an edge; `$D196` doesn't load one twice.

The boss lock (`$9967`, from Simon's walking code) locks the screen when it scrolls to exactly the boss's screen (`$FC5E`: floor and screen); Samus can scroll 2 pixels a frame, so the hack checks at every pixel.

Simon's handlers are dispatched at `$9369` by `$046C`: 0 walk, 1 jump, 2 whip, 3 crouch, 4 on the stairs, 5 hurt, 6 walking to the stairs, 7 falling, 8 dead, 9 landing. Before that, every frame, `$9363` checks the water in stages 2 and 10. The hack takes over at `$9366` and leaves 4, 6 and 8 to Castlevania.

`$9C10` starts the stairs when Up or Down is held near their foot or top. The hack calls it only on a new press, since Samus aims up with Up held. Stage 1's first stairs start from x `$504` to `$51C`, and their top is the stage's exit (mode 8).

On the stairs Castlevania moves Simon a pixel every other frame. Through a door (mode 8) it hides him (pose 0) while the screen scrolls to the door and the door opens (parts 0 and 1), walks him through it (part 2), and then the screen carries him along, standing. The status bar stays up through all of it, as in modes 7 to `$0B`, where `$F87D` splits the screen.

Where the screen can't scroll (a stage's ends, a boss), Simon walks on it, between screen x `$09` and `$EF` (`$98CB`, `$98E9`); a stage's exit can be as far right as `$F0`, give or take 2 (stage 1's is).

Castlevania takes Simon's x in the level (`$41:$40`) to be the scroll plus `$80`, unless `$3C` bit 2 is set; then it is the scroll plus his screen x. Metroid's camera leaves Samus anywhere between `$71` and `$8F`, so before handing over to the stairs the hack sets that bit unless she is at `$80`.

### Collision

`$F9A0` (fixed bank): `$10` = y, `$13:$12` = x in the level, returns `$14` = the 2-bit collision value of that 8x8 cell, 0 for empty. The map is at `$05A0`: two screens of 22 rows of 8 bytes, four cells a byte, for y from `$30` to `$DF`. Points above or below that are empty.

### Damage

`$E6BB` tests each object against Simon (within `$5F` of his y) unless he is hurt, dead or invincible (`$5B`), takes 8, 12 or 16 off `$45` (of `$40`), and calls `$96C1`, which turns him towards the enemy and starts action 5. The hack keeps `$45` at `$20` and turns each change into Metroid's energy (`src/cv.asm`).

Subweapons hit things at `$E5EB`: any object in slots `$14-$16` with an AI type (`$17` for a thrown one) and a type (`$0584`) below 6. After its AI, every object's pose is animated by `$F1DB` from its pose table (`$04C0`), timed by `$0488`; bit 7 there turns that off, as for items. A shot's dagger sets it, or the spark of the last hit in that slot goes on animating, drawn over the next shot. A dagger (type 0) that hits becomes AI `$32`, a spark, which is also what Castlevania turns objects into when they leave the screen (`$EA72`).

### Breakable blocks

`$A825` (bank 6), every frame: if Simon is on frame 9 of a whip attack, his whip's box is tested against the stage's list of blocks (`$FC71`): two bytes each, y and floor, x and screen. A hit block's tiles are replaced, and its item is spawned once (`$0146`). The hack runs the same test from `$A837` for each shot that just exploded on a wall.

### The CHR loader and the font

`$FD23` copies a list of blocks (bank, source, destination, length) into CHR RAM with the screen off, then `$C102` turns it back on. Simon's tiles are sprite tiles `$00-$6F`, from bank 1 `$9008` (tile 0); only Simon and the whip use `$02-$3E`, `$46-$4E`, `$52-$5E` and `$6A-$6E`. The status bar's font is background tiles `$D0-$FF`, from bank 3 `$BC08`, loaded with each stage. The Game Over screen uses it without loading it again.

Items and dropped weapons are drawn with background-table tiles (odd tile numbers, in 8x16 mode).

### The status bar split

Sprite 0 (`$C13B`) sits on the status bar; `$F87D` waits for its hit, waits 221 cycles more, and writes the scroll, at about line 40. Both waits give up after 256 tries, so the game doesn't hang without a hit. Every status bar write goes through the update buffer at `$0700` (entries: increment, address, data, `$FF`; a `$FF` followed by a byte of 3 or more is a literal `$FF`). `ClearSpriteUpdateList` (`$CCEE`), at the end of each NMI, writes a 0 at the buffer's end and moves past it.

The hack blanks rows 0-5 of both name tables, puts one opaque pixel at row 5, column 1, and covers it with sprite 0 in black (palette 3's colour 3 is `$0F`), so the hit happens at line 40. In play, through doors and walking in (where Metroid's HUD shows too), it does the split itself (`Bank6_Split`): Castlevania's loop looks for the hit only every 17 cycles, which moves everything after it by up to 50 dots; the hack's looks every 11. Then, with rendering off from the end of line 43, it writes palette 2 back, sets the PPU's address to line 45, and turns rendering on in line 44's horizontal blank, so line 45 is fetched whole. While rendering is off the PPU shows the colour its address points at; the 42 dots in which that is a palette entry being written fall in line 43's horizontal blank, and after the last write the address points at `$3F1C`, which is black. Turning rendering on in the middle of a line instead shows stale background pixels there. `tests/t_split.lua` checks the lines stay black.

### Sound

The music engine runs channels `$80` (square 1), `$90` (square 2), `$A0` (triangle), `$B0` (noise), `$C0` and `$D0` (its sound effects, on the squares). The loop at `$83B3` keeps the channel's register offset in `$AC` (0, 4, 8, `$C`), and every register write goes to `$4000,$AC`. The hack moves `$AC` to `$18` (`$4018-$401B`, which nothing reads) while one of Samus's sounds has the channel, and works out the next offset from the channel base instead.

### Sprite palettes

The four sprite palettes are the same in every stage: Simon `0F 27 37 07`, then `0F 23 34 0F`, `0F 37 11 0F`, `0F 16 25 0F`.

## Metroid

### Samus

Samus is object 0 at `$0300` (`status`, `radiusY`, `radiusX`, `animFrame`, ..., `y` at `$030D`, `x` at `$030E`). `UpdateSamus` (`$CC0D`) runs her handler, which animates, checks her health and moves her (`LavaAndMoveCheck`), then draws her; it returns at `$CC17`. Her projectiles move before she does, in `UpdateWorld`.

Collision is only looked at when an edge of Samus is on an 8 pixel line, then for every 8x8 cell beyond it. Her radii come from the frame she was last drawn with.

Metroid's main loop sometimes takes more than a frame; then Samus doesn't move that frame. That is why the physics reference is recorded per call of `UpdateSamus`, not per frame, and why its sequences avoid scrolling (scrolling is what most often makes it late).

### Frames

`ObjFramePtrTable` (`$860B`), `ObjPlacePtrTable` (`$86DF`) and `ObjectAnimIndexTbl` (`$8572`) are in bank 1 (and each area bank). A frame is a header (flips, palette, placement table), the radii, then tiles with control bytes: `$FC` move, `$FD` new attributes, `$FE` skip a place, `$FF` end. The sprites have the priority bit set, which the hack drops: Castlevania's backgrounds are opaque where Metroid's are not. Samus's graphics are bank 6 `$8000` (tiles `$00-$99`), the HUD's digits bank 6 `$B4C0` (tiles `$A0-$A9`).

Samus's 37 frames need 52 distinct 8x16 tile pairs, counting a pair and its mirror images once; with the HUD's and the explosion's, 65 of the 70 the hack has.

### HUD and palettes

`DisplayHUD` draws 10 sprites: "EN" and ".." at y `$21`, the energy digits beside them, the missile and its count at y `$2B`, energy tanks at y `$17`. Samus's palette is sprite palette 0, `0F 16 19 27`; with missiles armed its colour 2 is `$2C`. The HUD's is palette 1, `0F 12 30 21`.

### Sound effects

Init flags at `$0680` (noise), `$0681` (square 1), `$0683` (triangle), `$0684` (both squares); a bit there starts an effect, and its bit in the continue flags (`$0688-$068C`) stays set while it plays.
