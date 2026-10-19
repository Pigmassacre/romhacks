class_name GimmickBody
extends RefCounted
## One object slot. Gimmick! has ten of them: slot 0 is Yumetaro, slot 1 is his
## weapon (the star), slots 2-9 are enemies and platforms.
##
## Positions are 16-bit: the high byte is the tile and the low byte is the
## position inside the tile, in 1/16 px. So 16 units = 1 px and 256 units = 1 tile.
## The Y position is the object's feet. The high nibble of the Y tile is the
## vertical screen and the low nibble is the row on that screen.
## Velocities are signed bytes in 1/16 px per frame.

var status := 0        ## $90,x
var x := 0             ## $B8,x : $AE,x
var y := 0             ## $A4,x : $9A,x
var vx := 0            ## $CC,x  signed, -128..127
var vy := 0            ## $C2,x  signed, -128..127
var standable := 0     ## $D6,x  $40 = Yumetaro can stand on this
var frame := 0         ## $0300,x  animation frame
var facing := 0        ## $030A,x  0 = left, 1 = right
var hit_y := 0         ## $031E,x : $0314,x  height, feet to head
var hit_x := 0         ## $0332,x : $0328,x  half width for walls and hits
var probe_x := 0       ## $033C,x  half width of the feet
var health := 0        ## $0346,x
var floor_type := 0    ## $035A,x
var rider := 0         ## $0364,x  1 = Yumetaro is standing on this
var on_floor := false  ## $036E,x  bit 7
var hit_wall := false  ## $0378,x  bit 7
var timer1 := 0        ## $0382,x
var timer2 := 0        ## $038C,x
var flags := 0         ## $03C8,x  $20 = behind the background, bit 0 = palette flicker


func x_tile() -> int:
	return (x >> 8) & 0xFF


func x_sub() -> int:
	return x & 0xFF


func y_tile() -> int:
	return (y >> 8) & 0xFF


func y_sub() -> int:
	return y & 0xFF


func row() -> int:
	return (y >> 8) & 0x0F


## Position in pixels, for drawing. `screen_rows` is the height of one vertical
## screen in world rows (11, because neighbouring screens share a row).
func pixel_x() -> float:
	return x / 16.0


func pixel_y() -> float:
	var screen := (y >> 12) & 0x0F
	return screen * 176.0 + (y & 0x0FFF) / 16.0


func clear() -> void:
	status = 0
	standable = 0
	rider = 0
	on_floor = false
	hit_wall = false
	vx = 0
	vy = 0
	timer1 = 0
	timer2 = 0
	flags = 0
	frame = 0
