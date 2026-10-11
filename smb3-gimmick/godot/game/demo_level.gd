class_name DemoLevel
extends RefCounted
## A test course for the reference implementation, drawn as text.
##
## It is not a level from Gimmick!. It is laid out to put every kind of terrain
## the physics knows about next to each other. Each character is one 16 px
## metatile; LEGEND gives the three attribute bytes the original keeps per
## metatile ($7D00 floor type, $7E00 collision, $7F00 variant).
##
## A screen is 12 rows. Screens stack with one shared row: row 11 of a screen is
## row 0 of the screen below it, exactly as in the original's maps.

const S := GimmickWorld.SOLID
const SL := GimmickWorld.SLOPE
const FILL := GimmickWorld.SOLID | GimmickWorld.SLOPE | GimmickWorld.SLOPE_FILL

## char: [metatile id, floor type, collision attribute, variant, colour, note]
const LEGEND := {
	".": [0x00, 1, 0x00, 0, Color(0, 0, 0, 0), "air"],
	"#": [0x01, 2, S, 0, Color("5a4632"), "solid ground"],
	"%": [0x02, 1, FILL, 0, Color("4a3a2a"), "filler under a slope"],
	"i": [0x03, 7, S, 0, Color("9fd8ef"), "ice"],
	">": [0x04, 3, S, 0, Color("b0703a"), "conveyor to the right"],
	"<": [0x05, 4, S, 0, Color("3a8ab0"), "conveyor to the left"],
	"X": [0x06, 0, 0x00, 0, Color("400000"), "pit: death"],
	"^": [0x07, 0, 0x00, 2, Color("c03030"), "spikes: death"],
	":": [0x08, 1, GimmickWorld.BEHIND, 0, Color("26303c"), "objects are drawn behind this"],
	# Tubes. The low three bits of the id choose the path.
	"0": [0x10, 1, GimmickWorld.TUBE, 0, Color("7a7a90"), "tube: left <-> right"],
	"1": [0x11, 1, GimmickWorld.TUBE, 0, Color("7a7a90"), "tube: up <-> down"],
	"2": [0x12, 1, GimmickWorld.TUBE, 0, Color("7a7a90"), "tube: right <-> down"],
	"3": [0x13, 1, GimmickWorld.TUBE, 0, Color("7a7a90"), "tube: left <-> down"],
	"4": [0x14, 1, GimmickWorld.TUBE, 0, Color("7a7a90"), "tube: right <-> up"],
	"5": [0x15, 1, GimmickWorld.TUBE, 0, Color("7a7a90"), "tube: left <-> up"],
	# Slopes: collision = SLOPE | shape, variant = behaviour.
	"/": [0x40, 1, SL | 0, 0, Color("6a8a3a"), "steep, slides left"],
	"\\": [0x41, 1, SL | 1, 1, Color("6a8a3a"), "steep, slides right"],
	"a": [0x42, 1, SL | 2, 2, Color("7a9a4a"), "gentle rise, lower half, slides left"],
	"b": [0x43, 1, SL | 3, 2, Color("7a9a4a"), "gentle rise, upper half, slides left"],
	"c": [0x44, 1, SL | 4, 3, Color("7a9a4a"), "gentle fall, upper half, slides right"],
	"d": [0x45, 1, SL | 5, 3, Color("7a9a4a"), "gentle fall, lower half, slides right"],
	"q": [0x48, 1, SL | 8, 10, Color("8a7a4a"), "shallow rise you can stand on"],
	"t": [0x49, 1, SL | 9, 10, Color("8a7a4a"), "shallow fall you can stand on"],
	"s": [0x4A, 1, SL | 10, 10, Color("8a7a4a"), "shallow dip, left half"],
	"r": [0x4B, 1, SL | 11, 10, Color("8a7a4a"), "shallow dip, right half"],
	"A": [0x52, 1, SL | 2, 15, Color("a8dcec"), "icy gentle rise, lower half"],
	"B": [0x53, 1, SL | 3, 15, Color("a8dcec"), "icy gentle rise, upper half"],
	"C": [0x54, 1, SL | 4, 16, Color("a8dcec"), "icy gentle fall, upper half"],
	"D": [0x55, 1, SL | 5, 16, Color("a8dcec"), "icy gentle fall, lower half"],
}

## Characters that place something and leave air behind.
const ENTITIES := {"P": "player", "E": "walker", "M": "platform"}

## Signs drawn above the course: [column, row, text].
const SIGNS := [
	[2, 3, "JUMP"], [17, 3, "SLOPES"], [41, 3, "CONVEYORS"], [58, 3, "ICE"],
	[74, 3, "HAZARDS"], [90, 3, "CAVE BELOW"], [98, 6, "TUBE"],
]

const SCREEN_0 := [
	"################################################################################################################",
	"#..............................................................................................................#",
	"#..............................................................................................................#",
	"#..............................................................................................................#",
	"#..............................................................................................................#",
	"#..............................................................................................................#",
	"#..........................................#######.............................................................#",
	"#....###........................................................................M..............................#",
	"#............##............/##\\................................................................................#",
	"#..P.....##..##...ab##cd../%##%\\..qt..........................ABCD............E.......E.............2....E.....#",
	"##################%%##%%##%%##%%##%%#sr##>>>>>#<<<<<#####iiiii%%%%iiiii####^^####...########..######1###########",
	"#####################################%%##########################################XXX########..######1###########",
]

const SCREEN_1 := [
	"#####################################%%##########################################XXX########..######1###########",
	"########################################################################################............1...########",
	"########################################################################################............1...########",
	"########################################################################################............1...########",
	"########################################################################################............1...########",
	"########################################################################################............1...########",
	"########################################################################################............1...########",
	"########################################################################################............1...########",
	"########################################################################################............1...########",
	"########################################################################################........E.005...########",
	"##########################################################################################iiiiii################",
	"################################################################################################################",
]


## Returns {world, start, entities, colors}. `entities` is a list of
## {kind, screen, x, y} with positions in the game's units.
static func build() -> Dictionary:
	var world := GimmickWorld.new()
	var colors := {}
	for ch in LEGEND:
		var def: Array = LEGEND[ch]
		world.floor_type[def[0]] = def[1]
		world.attr[def[0]] = def[2]
		world.variant[def[0]] = def[3]
		colors[def[0]] = def[4]
	var entities := []
	var start := Vector2i(0x0380, 0x0A00)
	var screens := [SCREEN_0, SCREEN_1]
	for screen in screens.size():
		var rows: Array = screens[screen]
		for row in rows.size():
			var line: String = rows[row]
			for column in line.length():
				var ch := line[column]
				if ENTITIES.has(ch):
					# Entities stand on the tile below the one they are written in.
					var x := (column << 8) | 0x80
					var y := (((screen << 4) | (row + 1)) << 8)
					if ENTITIES[ch] == "player":
						start = Vector2i(x, y)
					else:
						entities.append({"kind": ENTITIES[ch], "screen": screen, "x": x, "y": y})
					ch = "."
				world.set_tile(screen, column, row, LEGEND[ch][0])
	# Hold the camera at both ends of the course ($7BE0: bit 7 locks it while
	# Yumetaro is in the left half of a 16-column screen, bit 6 in the right half).
	var last := (SCREEN_0[0].length() >> 4) - 1
	for screen in GimmickWorld.SCREENS:
		world.camera_lock[screen] = 0x80
		world.camera_lock[last * 4 + screen] = 0x40
	return {"world": world, "start": start, "entities": entities, "colors": colors}
