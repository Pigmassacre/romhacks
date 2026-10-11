extends SceneTree
## Prints the numbers quoted in docs/yumetaro-physics-guide.md, measured from GimmickSim.
##
##   godot --headless --path godot -s tests/measure.gd

const A := GimmickSim.BTN_A
const B := GimmickSim.BTN_B
const L := GimmickSim.BTN_LEFT
const R := GimmickSim.BTN_RIGHT


func make(floor_type := 2) -> GimmickSim:
	var w := GimmickWorld.new()
	w.floor_type[1] = floor_type
	w.attr[1] = GimmickWorld.SOLID
	for c in GimmickWorld.COLUMNS:
		w.set_tile(0, c, 10, 1)
		w.set_tile(0, c, 11, 1)
	var sim := GimmickSim.new(w)
	sim.frame_counter = 1
	sim.spawn_player(0x4080, 0x0A00)
	sim.camera_x = 0x3880
	sim.step(0, 0)
	return sim


func px(v: int) -> String:
	return "%.4f" % (v / 16.0)


func _init() -> void:
	var sim := make()
	print("== walk right from rest: frame, vx after frame, x travelled (px)")
	var x0 := sim.player.x
	var line := ""
	for f in range(1, 31):
		sim.step(R, 0)
		line += "%d:%d " % [f, sim.player.vx]
	print(line)
	print("distance after 30 frames: ", px(sim.player.x - x0))
	x0 = sim.player.x
	for f in 160:
		sim.step(R, 0)
	print("top speed right: px per frame = ", px(sim.player.x - x0).to_float() / 160.0)
	x0 = sim.player.x
	var n := 0
	while sim.player.vx != 0:
		sim.step(0, 0)
		n += 1
	print("stop from top speed: %d frames, %s px" % [n, px(sim.player.x - x0)])
	sim = make()
	for f in 200:
		sim.step(L, 0)
	x0 = sim.player.x
	for f in 160:
		sim.step(L, 0)
	print("top speed left: px per frame = ", px(x0 - sim.player.x).to_float() / 160.0)
	x0 = sim.player.x
	n = 0
	while sim.player.vx < 0 or n == 0:
		sim.step(R, 0)
		n += 1
		if sim.player.vx >= 0:
			break
	print("turn around from top speed left to vx>=0: %d frames, slid %s px" % [n, px(x0 - sim.player.x)])

	print("== jump: hold frames -> peak height px, frames in air")
	for hold in [1, 2, 3, 4, 5, 6, 8, 10, 12, 14, 16, 18, 20, 21, 22, 30]:
		sim = make()
		var y0 := sim.player.y
		var peak := 0
		var air := 0
		sim.step(A, A)
		for f in range(1, 200):
			if not sim.player.on_floor:
				air += 1
			peak = maxi(peak, y0 - sim.player.y)
			if f > 2 and sim.player.on_floor:
				break
			sim.step(A if f < hold else 0, 0)
		print("hold %2d: peak %s px, %d frames airborne" % [hold, px(peak), air])
	sim = make()
	for f in 100:
		sim.step(R, 0)
	x0 = sim.player.x
	sim.step(R | A, A)
	n = 0
	for f in 200:
		sim.step(R | A, 0)
		n += 1
		if sim.player.on_floor:
			break
	print("running full jump: %s px far, %d frames" % [px(sim.player.x - x0), n + 1])
	sim = make()
	print("vy per frame of a full jump: ")
	line = ""
	sim.step(A, A)
	for f in 48:
		line += "%d " % sim.player.vy
		sim.step(A, 0)
	print(line)

	print("== star")
	for case in ["standing", "running", "rising", "falling"]:
		sim = make()
		var pre := 0
		if case == "running":
			pre = R
		for f in 60:
			sim.step(pre, 0)
		for f in 43:
			sim.step(pre | B, 0)
		if case == "rising":
			sim.step(B | A, A)
			sim.step(B | A, 0)
		if case == "falling":
			sim.step(B | A, A)
			for f in 30:
				sim.step(B | A, 0)
		var px0 := sim.player.x
		sim.step(pre, 0)
		var s := sim.star
		print("%s throw: vx=%d vy=%d (player vx=%d vy=%d)" % [case, sim.star_saved_vx, sim.star_saved_vy, sim.player.vx, sim.player.vy])
		var sx0 := s.x
		var sy0 := 0x0A00
		var bounces := []
		var peak := 0
		var frames := 1
		var last_floor := false
		while s.status == GimmickSim.ST_ACTIVE and frames < 2000:
			sim.camera_x = (s.x - 0x0800) & 0xFFFF  # keep the star on screen so it is not removed
			sim.step(0, 0)
			frames += 1
			peak = maxi(peak, sy0 - s.y)
			if s.on_floor and not last_floor:
				bounces.append("f%d x%+.1f prev-peak %.1f vx %d" % [frames, (s.x - sx0) / 16.0, peak / 16.0, s.vx])
				peak = 0
			last_floor = s.on_floor
		print("  active %d frames, ends %s px from the throw point, then vanishes" % [frames, px(s.x - sx0)])
		for b in bounces:
			print("   ", b)
	quit()
