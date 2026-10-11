extends SceneTree
## Plays the demo level with scripted input and checks that each part of it
## does what it was built to show.
##
##   godot --headless --path godot -s tests/play_level.gd

const A := GimmickSim.BTN_A
const B := GimmickSim.BTN_B
const L := GimmickSim.BTN_LEFT
const R := GimmickSim.BTN_RIGHT

var sim: GimmickSim
var prev := 0
var failed := 0


func place(column: int, row: int, screen := 0) -> void:
	sim.spawn_player((column << 8) | 0x80, ((screen << 4) | row) << 8)
	sim.camera_x = maxi(sim.player.x - 0x800, 0)
	prev = 0
	run(0, 2)


func run(held: int, frames: int) -> void:
	for i in frames:
		sim.step(held, held & ~prev)
		prev = held


func check(what: String, ok: bool) -> void:
	print("%s  %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		failed += 1


func _init() -> void:
	var level := DemoLevel.build()
	sim = GimmickSim.new(level.world)
	var p := sim.player

	place(3, 10)
	check("stands on the ground at the start", p.on_floor and p.y == 0x0A00)
	run(A, 20)
	run(0, 40)
	check("lands again after a jump", p.on_floor and p.y == 0x0A00)
	place(6, 10)
	run(A, 30)
	check("low ceiling stops the jump", p.on_floor)

	place(16, 10)
	run(R, 70)
	check("walks up the gentle slope onto the hill top", p.y == 0x0900 and p.on_floor)
	place(19, 9)
	run(0, 60)
	check("slides back down the gentle slope when idle", p.y == 0x0A00 and p.x < 0x1200)
	place(25, 10)
	run(R, 200)
	check("cannot walk up the steep slope from a standstill", p.x < 0x1C00)
	place(27, 8)
	run(0, 25)
	check("slides down the steep slope when idle", p.y == 0x0A00 and p.x < 0x1A00)
	place(33, 10)
	run(R, 20)
	run(0, 40)
	check("can stand still on a shallow slope", p.on_floor and p.vx == 0 and (p.y & 0xFF) != 0)

	place(43, 10)
	run(0, 30)
	check("conveyor carries him right", p.x > 0x2B80 + 0x100)
	place(57, 10)
	run(R, 40)
	var x0 := p.x
	run(0, 30)
	check("keeps sliding on ice", p.x - x0 > 0x100 and p.vx > 0)

	place(73, 10)
	run(R, 60)
	check("spikes kill", p.status >= GimmickSim.ST_DEAD)
	place(79, 10)
	run(R, 60)
	check("the pit kills", p.status >= GimmickSim.ST_DEAD)

	place(90, 10)
	run(R, 80)
	check("falls through the hole into the cave below", sim.yscreen == 1 and p.on_floor)
	run(R, 400)
	check("the tube carries him back up to the surface", sim.yscreen == 0 and p.on_floor and p.x > 0x6500)

	place(3, 10)
	run(B, 50)
	check("star is fully charged after 42 frames", sim.star.status == GimmickSim.ST_CHARGE_FULL)
	run(0, 6)
	check("star is thrown on release and bounces", sim.star.status == GimmickSim.ST_ACTIVE and sim.star.standable == 0x40)
	run(0, 200)
	check("star has gone", sim.star.status == GimmickSim.ST_NONE)

	# An object under his feet: he stands on it and it carries him.
	place(3, 10)
	var o: GimmickBody = sim.objects[2]
	o.status = GimmickSim.ST_ACTIVE
	o.standable = 0x40
	o.hit_y = 0x80
	o.hit_x = 0x180
	o.x = p.x
	o.y = 0x0880
	p.y = 0x0800
	p.vy = 0
	run(0, 1)
	check("stands on a standable object", p.on_floor and o.rider == 1)
	o.vx = 16
	sim.move_object(o)
	check("is carried by it", p.x == 0x0390 and p.y == 0x0800)
	o.status = GimmickSim.ST_NONE
	o.standable = 0

	# An enemy at his side hurts; one under his feet does not.
	place(3, 10)
	o.x = p.x + 0x80
	o.y = p.y
	o.hit_y = 0xE0
	o.hit_x = 0x60
	check("touching an enemy's side hurts and knocks him away", sim.hurt_player(o) and p.vx == -18 and p.vy == -24 and p.health == 1)
	check("no second hit while the timer runs", not sim.hurt_player(o))
	run(R, 25)
	check("no input while stunned", p.vx <= 0)
	place(3, 10)
	o.x = p.x
	o.y = p.y + 0xE0
	check("standing on an enemy is safe", sim.touch_test(o) == -1)

	# Medicine.
	place(3, 10)
	p.health = 1
	sim.items = [1, 0, 0]
	sim.item_count = 1
	run(B | GimmickSim.BTN_UP, 1)
	check("medicine refills health and is used up", p.health == sim.max_health and sim.item_count == 0)
	run(B | GimmickSim.BTN_UP, 40)
	check("no charge while B is still held after medicine", sim.star.status == GimmickSim.ST_NONE)
	print("FAILED: %d" % failed)
	quit(1 if failed > 0 else 0)
