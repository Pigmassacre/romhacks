extends SceneTree
## Replays traces recorded from the real game in Mesen and checks that
## GimmickSim produces the same state on every frame.
##
##   godot --headless --path godot -s tests/verify_traces.gd -- <trace dir> [name ...]
##
## The traces are made by tools/gim_physics_trace.py from your own ROM; they are
## not part of the repository.

const SHOW := 6

var addrs: Array = []
var index := {}


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		print("usage: -- <trace dir> [name ...]")
		quit(2)
		return
	var dir: String = args[0]
	addrs = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join("addrs.json")))
	for i in addrs.size():
		index[int(addrs[i])] = i
	var names: Array = args.slice(1)
	if names.is_empty():
		for f in DirAccess.get_files_at(dir):
			if f.ends_with(".trc"):
				names.append(f.get_basename())
		names.sort()
	var bad := 0
	for n in names:
		bad += run_trace(dir.path_join(n + ".trc"), n)
	print("TOTAL mismatched frames: %d" % bad)
	quit(1 if bad > 0 else 0)


func g(rec: PackedByteArray, addr: int) -> int:
	return rec[index[addr]]


func g16(rec: PackedByteArray, hi: int, lo: int) -> int:
	return (g(rec, hi) << 8) | g(rec, lo)


func load_state(sim: GimmickSim, r: PackedByteArray) -> void:
	var p := sim.player
	var s := sim.star
	for i in 2:
		var o: GimmickBody = sim.objects[i]
		o.status = g(r, 0x90 + i)
		o.x = g16(r, 0xB8 + i, 0xAE + i)
		o.y = g16(r, 0xA4 + i, 0x9A + i)
		o.vy = GimmickSim.s8(g(r, 0xC2 + i))
		o.vx = GimmickSim.s8(g(r, 0xCC + i))
		o.standable = g(r, 0xD6 + i)
		o.frame = g(r, 0x300 + i)
		o.facing = g(r, 0x30A + i)
		o.hit_y = g16(r, 0x31E + i, 0x314 + i)
		o.hit_x = g16(r, 0x332 + i, 0x328 + i)
		o.probe_x = g(r, 0x33C + i)
		o.floor_type = g(r, 0x35A + i)
		o.rider = g(r, 0x364 + i)
		o.on_floor = g(r, 0x36E + i) >= 0x80
		o.hit_wall = g(r, 0x378 + i) >= 0x80
		o.timer1 = g(r, 0x382 + i)
		o.timer2 = g(r, 0x38C + i)
		o.flags = g(r, 0x3C8 + i)
	p.health = g(r, 0x346)
	sim.max_health = g(r, 0x2B)
	sim.yscreen = g(r, 0x16)
	sim.camera_x = g16(r, 0x15, 0x14)
	sim.jump_hold = g(r, 0x4B)
	sim.was_on_floor = g(r, 0x53) >= 0x80
	sim.b_lockout = g(r, 0x55)
	sim.weapon_type = g(r, 0x351)
	sim.combo = g(r, 0x35)
	sim.star_saved_vy = GimmickSim.s8(g(r, 0x397))
	sim.star_saved_vx = GimmickSim.s8(g(r, 0x3A1))
	sim.items = [g(r, 0x36), g(r, 0x37), g(r, 0x38)]
	sim.item_count = g(r, 0x39)


func diff(sim: GimmickSim, r: PackedByteArray) -> Array:
	var out := []
	var names := ["P", "S"]
	for i in 2:
		var o: GimmickBody = sim.objects[i]
		var n: String = names[i]
		var exp := {
			"status": g(r, 0x90 + i), "x": g16(r, 0xB8 + i, 0xAE + i), "y": g16(r, 0xA4 + i, 0x9A + i),
			"vy": GimmickSim.s8(g(r, 0xC2 + i)), "vx": GimmickSim.s8(g(r, 0xCC + i)),
			"standable": g(r, 0xD6 + i), "frame": g(r, 0x300 + i), "facing": g(r, 0x30A + i),
			"floor_type": g(r, 0x35A + i), "rider": g(r, 0x364 + i),
			"on_floor": g(r, 0x36E + i) >= 0x80, "hit_wall": g(r, 0x378 + i) >= 0x80,
			"timer1": g(r, 0x382 + i), "timer2": g(r, 0x38C + i), "flags": g(r, 0x3C8 + i),
			"hit_y": g16(r, 0x31E + i, 0x314 + i), "hit_x": g16(r, 0x332 + i, 0x328 + i), "probe_x": g(r, 0x33C + i),
		}
		for k in exp:
			if o.get(k) != exp[k]:
				out.append("%s.%s sim=%s game=%s" % [n, k, fmt(o.get(k)), fmt(exp[k])])
	var glob := {
		"health": [sim.player.health, g(r, 0x346)],
		"yscreen": [sim.yscreen, g(r, 0x16)],
		"camera_x": [sim.camera_x, g16(r, 0x15, 0x14)],
		"jump_hold": [sim.jump_hold, g(r, 0x4B)],
		"was_on_floor": [sim.was_on_floor, g(r, 0x53) >= 0x80],
		"b_lockout": [sim.b_lockout, g(r, 0x55)],
		"weapon_type": [sim.weapon_type, g(r, 0x351)],
		"saved_vy": [sim.star_saved_vy, GimmickSim.s8(g(r, 0x397))],
		"saved_vx": [sim.star_saved_vx, GimmickSim.s8(g(r, 0x3A1))],
	}
	for k in glob:
		if glob[k][0] != glob[k][1]:
			out.append("%s sim=%s game=%s" % [k, fmt(glob[k][0]), fmt(glob[k][1])])
	return out


func fmt(v) -> String:
	if v is bool:
		return str(v)
	return "%d($%X)" % [v, v & 0xFFFF]


func run_trace(path: String, name: String) -> int:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		print("%s: cannot open" % path)
		return 1
	var world := GimmickWorld.new()
	var sim := GimmickSim.new(world)
	var n := addrs.size()
	var frame := -1
	var bad := 0
	var checked := 0
	var hurts := 0
	var prev: PackedByteArray
	var settle := 0  # frames to take as given after the level is reloaded
	while f.get_position() < f.get_length():
		var tag := f.get_8()
		if tag == 0x4D:  # 'M'
			world.load_ram_dump(f.get_buffer(0x2000))
			continue
		var flags := f.get_8()
		var rec := f.get_buffer(n)
		frame += 1
		# Pokes made by the trace script, and the reload after a death, are taken as given.
		if g(rec, 0x90) == 0:
			settle = 6
		if (flags & 1) != 0 or settle > 0:
			settle = maxi(settle - 1, 0)
			load_state(sim, rec)
			sim.respawn_timer = 0
			sim.death_wait = 0
			sim.pause_frames = 0
			prev = rec
			continue
		# A frame in which the game's frame counter did not move is a frame it spent
		# redrawing the screen. The sim models the one after a screen change; the
		# one after a level load is skipped.
		if g(rec, 0xED) == g(prev, 0xED) and sim.pause_frames == 0:
			prev = rec
			continue
		sim.frame_counter = g(rec, 0xED)
		# Enemy contact is not modelled here: when the game starts a hurt, apply the
		# same hurt to the sim. The enemy's side is read from the knockback.
		var held := g(rec, 0xF7)
		var pressed := g(rec, 0xF5)
		var hurt_now := g(prev, 0x38C) == 0 and g(rec, 0x346) < g(prev, 0x346) and g(rec, 0xC2) == 0xE8
		if hurt_now:
			sim.update_objects = func():
				var p := sim.player
				p.facing = g(rec, 0x30A)
				p.health -= 1
				p.timer2 = GimmickSim.HURT_TIME
				p.vx = -GimmickSim.HURT_VX if p.facing == 1 else GimmickSim.HURT_VX
				p.vy = GimmickSim.HURT_VY
			hurts += 1
		else:
			sim.update_objects = Callable()
		sim.step(held, pressed)
		var d := diff(sim, rec)
		checked += 1
		if not d.is_empty():
			bad += 1
			if bad <= SHOW:
				print("  %s frame %d: %s" % [name, frame, ", ".join(d)])
			load_state(sim, rec)
		prev = rec
	print("%-12s %5d frames checked, %d mismatched%s" % [name, checked, bad, (", %d hurts injected" % hurts) if hurts > 0 else ""])
	return bad
