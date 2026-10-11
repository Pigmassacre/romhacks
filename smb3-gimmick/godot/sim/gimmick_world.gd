class_name GimmickWorld
extends RefCounted
## The tile map and the three per-metatile attribute tables.
##
## In the original the map sits in cartridge RAM at $6000: four vertical screens,
## each 128 columns of 12 metatile ids ($600 bytes per screen, column-major).
## The attribute tables are at $7D00 (floor type), $7E00 (collision) and $7F00
## (variant), each indexed by metatile id.

const COLUMNS := 128
const ROWS := 12
const SCREENS := 4
const SCREEN_BYTES := COLUMNS * ROWS

## Collision attribute bits ($7E00).
const SOLID := 0x80        ## blocks walls and ceilings; a floor if SLOPE is clear
const SLOPE := 0x40        ## the floor is a height curve, not the top of the tile
const BEHIND := 0x20       ## objects here are drawn behind the background
const SLOPE_FILL := 0x10   ## with SLOPE: the surface belongs to the tile above
const SHAPE_MASK := 0x0F   ## slope shape, 0-15
const TUBE := 0x30         ## exactly $30: a tube tile

var map := PackedByteArray()
var floor_type := PackedByteArray()  ## $7D00
var attr := PackedByteArray()        ## $7E00
var variant := PackedByteArray()     ## $7F00
## $7BE0: per 16-column screen, bit 7 = camera locked while Yumetaro is in the
## left half, bit 6 = locked while he is in the right half. Index = screen column * 4 + vertical screen.
var camera_lock := PackedByteArray()


func _init() -> void:
	map.resize(SCREENS * SCREEN_BYTES)
	floor_type.resize(256)
	attr.resize(256)
	variant.resize(256)
	camera_lock.resize(32)
	floor_type.fill(1)


## Reads the map the way the game does: a flat offset into one vertical screen.
## A row of 12 or more therefore lands in the next column, as it does on the NES.
func tile_flat(screen: int, index: int) -> int:
	if index < 0 or index >= SCREEN_BYTES:
		return 0
	return map[(screen & 3) * SCREEN_BYTES + index]


func tile(screen: int, column: int, row: int) -> int:
	return tile_flat(screen, column * ROWS + row)


func set_tile(screen: int, column: int, row: int, id: int) -> void:
	map[(screen & 3) * SCREEN_BYTES + column * ROWS + row] = id


## Loads an 8 KB dump of $6000-$7FFF (used by the trace verifier).
func load_ram_dump(dump: PackedByteArray) -> void:
	map = dump.slice(0, SCREENS * SCREEN_BYTES)
	camera_lock = dump.slice(0x1BE0, 0x1C00)
	floor_type = dump.slice(0x1D00, 0x1E00)
	attr = dump.slice(0x1E00, 0x1F00)
	variant = dump.slice(0x1F00, 0x2000)
