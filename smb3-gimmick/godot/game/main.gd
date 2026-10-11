extends Node2D
## Runs GimmickSim at 60 Hz and draws it with plain rectangles.
##
## Everything about how Yumetaro and the star move is in res://sim. This file
## only reads the controller, moves the demo enemies and platform through the
## same hooks the original's enemy bank uses, and draws.

const PLAY_HEIGHT := 192
const VIEW_WIDTH := 256
const WALKER_SPEED := 8        # 1/16 px per frame, before floor friction
const PLATFORM_SPEED := 8
const PLATFORM_RANGE := 0x300  # 3 tiles either side of where it starts

var sim: GimmickSim
var level: Dictionary
var extras := {}               # slot -> {kind, dir, home}
var puffs: Array = []          # [x, y, frames left] for defeated enemies
var paused := false
var show_debug := true
var prev_held := 0
var last_sounds: Array = []
var font: Font
var beeper: AudioStreamPlayer
var playback: AudioStreamGeneratorPlayback
var beep_queue: Array = []     # [frequency, samples left, phase]


func _ready() -> void:
	font = ThemeDB.fallback_font
	_setup_input()
	_setup_audio()
	level = DemoLevel.build()
	sim = GimmickSim.new(level.world)
	sim.update_objects = _update_objects
	_respawn()


func _setup_input() -> void:
	var keys := {
		"gim_left": [KEY_LEFT, KEY_A], "gim_right": [KEY_RIGHT, KEY_D],
		"gim_up": [KEY_UP, KEY_W], "gim_down": [KEY_DOWN, KEY_S],
		"gim_jump": [KEY_Z, KEY_SPACE, KEY_K], "gim_star": [KEY_X, KEY_J],
	}
	var pads := {
		"gim_left": JOY_BUTTON_DPAD_LEFT, "gim_right": JOY_BUTTON_DPAD_RIGHT,
		"gim_up": JOY_BUTTON_DPAD_UP, "gim_down": JOY_BUTTON_DPAD_DOWN,
		"gim_jump": JOY_BUTTON_A, "gim_star": JOY_BUTTON_X,
	}
	for action in keys:
		InputMap.add_action(action)
		for key in keys[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key
			InputMap.action_add_event(action, ev)
		var pad := InputEventJoypadButton.new()
		pad.button_index = pads[action]
		InputMap.action_add_event(action, pad)


func _respawn() -> void:
	sim.max_health = 2
	sim.spawn_player(level.start.x, level.start.y)
	sim.camera_x = 0
	_spawn_screen_objects()


## The original spawns enemies as the camera reaches them. Here each vertical
## screen simply gets all of its objects when Yumetaro enters it.
func _spawn_screen_objects() -> void:
	extras.clear()
	for i in range(2, GimmickSim.SLOTS):
		sim.objects[i].clear()
	var slot := 2
	for e in level.entities:
		if e.screen != sim.yscreen or slot >= GimmickSim.SLOTS:
			continue
		var o: GimmickBody = sim.objects[slot]
		o.clear()
		o.status = GimmickSim.ST_ACTIVE
		o.x = e.x
		o.y = e.y
		o.health = 1
		if e.kind == "walker":
			o.hit_y = 0xE0
			o.hit_x = 0x60
			o.probe_x = 0x30
		else:
			o.hit_y = 0x80
			o.hit_x = 0x180
			o.probe_x = 0x180
		extras[slot] = {"kind": e.kind, "dir": -1, "home": e.x}
		slot += 1


func _read_buttons() -> int:
	var held := 0
	if Input.is_action_pressed("gim_left"): held |= GimmickSim.BTN_LEFT
	if Input.is_action_pressed("gim_right"): held |= GimmickSim.BTN_RIGHT
	if Input.is_action_pressed("gim_up"): held |= GimmickSim.BTN_UP
	if Input.is_action_pressed("gim_down"): held |= GimmickSim.BTN_DOWN
	if Input.is_action_pressed("gim_jump"): held |= GimmickSim.BTN_A
	if Input.is_action_pressed("gim_star"): held |= GimmickSim.BTN_B
	return held


func _unhandled_key_input(event: InputEvent) -> void:
	if not event.pressed or event.echo:
		return
	match event.physical_keycode:
		KEY_F1: show_debug = not show_debug
		KEY_P: paused = not paused
		KEY_PERIOD:
			paused = true
			_advance()
		KEY_R: _respawn()
	queue_redraw()


func _physics_process(_delta: float) -> void:
	if not paused:
		_advance()
	queue_redraw()


func _advance() -> void:
	var held := _read_buttons()
	var pressed := held & ~prev_held
	prev_held = held
	sim.step(held, pressed)
	if not sim.sounds.is_empty():
		last_sounds = sim.sounds.duplicate()
		for id in sim.sounds:
			_beep(id)
	if sim.screen_changed:
		_spawn_screen_objects()
	if sim.needs_respawn:
		_respawn()
	for p in puffs:
		p[2] -= 1
	puffs = puffs.filter(func(p): return p[2] > 0)


## Called by the sim where the original runs its enemy bank: after Yumetaro and
## the star have moved, before the end-of-frame checks.
func _update_objects() -> void:
	for slot in extras:
		var o: GimmickBody = sim.objects[slot]
		if o.status != GimmickSim.ST_ACTIVE:
			continue
		var info: Dictionary = extras[slot]
		if info.kind == "walker":
			_update_walker(o, info)
		else:
			_update_platform(o, info)


## The pattern of the simplest enemies in the original: a star kills it and
## flies on, it can be stood on, and its side hurts.
func _update_walker(o: GimmickBody, info: Dictionary) -> void:
	if sim.star_touches(o):
		o.status = GimmickSim.ST_NONE
		o.standable = 0
		o.rider = 0
		puffs.append([o.x, o.y, 16])
		_beep(0x12)
		return
	o.standable = 0x40
	# Turn round rather than walk off a ledge or into spikes.
	var ahead := level.world.tile(sim.yscreen, ((o.x + info.dir * 0x80) >> 8) & 0xFF, o.row()) as int
	if o.on_floor and (level.world.attr[ahead] & 0xC0) != GimmickWorld.SOLID and (level.world.attr[ahead] & GimmickWorld.SLOPE) == 0:
		info.dir = -info.dir
	o.vx = info.dir * WALKER_SPEED
	o.facing = 1 if info.dir > 0 else 0
	sim.physics(o)
	if o.status >= GimmickSim.ST_DEAD or o.row() >= 0x0C:
		o.status = GimmickSim.ST_NONE   # walked into spikes or fell out of the screen
		o.standable = 0
		o.rider = 0
		return
	if o.hit_wall:
		info.dir = -info.dir
	sim.hurt_player(o)


## A platform: solid to the star, carries Yumetaro, ignores gravity.
func _update_platform(o: GimmickBody, info: Dictionary) -> void:
	o.standable = 0x40
	o.vx = info.dir * PLATFORM_SPEED
	o.vy = 0
	sim.star_collide_solid(o)
	sim.move_object(o)
	if o.hit_wall or absi(o.x - info.home) >= PLATFORM_RANGE:
		info.dir = -info.dir


# ---------------------------------------------------------------------------
# Drawing
# ---------------------------------------------------------------------------

func _cam() -> float:
	return float(sim.camera_x >> 4)


## Screen position of a game position on the current vertical screen.
func _pos(x: int, y: int) -> Vector2:
	return Vector2(floorf(x / 16.0) - _cam(), floorf((y & 0x0FFF) / 16.0))


func _on_screen(o: GimmickBody) -> bool:
	return ((o.y >> 12) & 3) == sim.yscreen


func _draw() -> void:
	draw_rect(Rect2(0, 0, VIEW_WIDTH, PLAY_HEIGHT), Color("1b2a3a"))
	_draw_behind_objects()
	_draw_tiles()
	_draw_signs()
	for slot in extras:
		var o: GimmickBody = sim.objects[slot]
		if o.status == GimmickSim.ST_ACTIVE and _on_screen(o):
			_draw_extra(o, extras[slot])
	for p in puffs:
		var c := _pos(p[0], p[1]) + Vector2(0, -8)
		var r: float = 16 - p[2]
		draw_arc(c, r, 0, TAU, 12, Color(1, 1, 1, p[2] / 16.0), 2.0)
	if (sim.star.flags & GimmickWorld.BEHIND) == 0:
		_draw_star()
	if (sim.player.flags & GimmickWorld.BEHIND) == 0:
		_draw_player()
	for p in sim.death_particles:
		if sim.player.status == GimmickSim.ST_DEAD and sim.player.timer2 == 5:
			var c := _pos(p[0], p[1]) + Vector2(0, -8)
			draw_rect(Rect2(c - Vector2(4, 4), Vector2(8, 8)), Color("7be07b") if (sim.frame_counter & 2) == 0 else Color.WHITE)
	if show_debug:
		_draw_debug()
	_draw_hud()


## Objects flagged "behind the background" are drawn first, so tiles cover them.
func _draw_behind_objects() -> void:
	if (sim.star.flags & GimmickWorld.BEHIND) != 0:
		_draw_star()
	if (sim.player.flags & GimmickWorld.BEHIND) != 0:
		_draw_player()


func _draw_tiles() -> void:
	var cam := _cam()
	var first := int(cam) >> 4
	var world: GimmickWorld = level.world
	for column in range(first, first + 17):
		if column < 0 or column >= GimmickWorld.COLUMNS:
			continue
		for row in GimmickWorld.ROWS:
			var id := world.tile(sim.yscreen, column, row)
			if id == 0:
				continue
			var color: Color = level.colors.get(id, Color.MAGENTA)
			var origin := Vector2(column * 16 - cam, row * 16)
			var a := world.attr[id]
			if a == GimmickWorld.TUBE:
				draw_rect(Rect2(origin, Vector2(16, 16)), Color(color, 0.55))
				draw_rect(Rect2(origin + Vector2(1, 1), Vector2(14, 14)), Color(1, 1, 1, 0.25), false, 1.0)
			elif (a & GimmickWorld.SLOPE) != 0 and (a & GimmickWorld.SLOPE_FILL) == 0:
				# One 1 px strip per pixel column, straight from the height table.
				for i in 16:
					var h := GimmickTables.SLOPE_HEIGHT[i * 16 + (a & 0x0F)] / 16.0
					draw_rect(Rect2(origin + Vector2(i, h), Vector2(1, 16 - h)), color)
			else:
				draw_rect(Rect2(origin, Vector2(16, 16)), color)
				if row > 0 and (a & 0xC0) == GimmickWorld.SOLID and (world.attr[world.tile(sim.yscreen, column, row - 1)] & GimmickWorld.SOLID) == 0:
					draw_rect(Rect2(origin, Vector2(16, 2)), color.lightened(0.25))
				var ft := world.floor_type[id]
				if ft == 3 or ft == 4:
					# Conveyor arrows that run with the belt (1 px per frame).
					var shift := (sim.frame_counter & 7) if ft == 3 else 7 - (sim.frame_counter & 7)
					for k in 2:
						draw_rect(Rect2(origin + Vector2((shift + k * 8) % 16, 5), Vector2(2, 6)), color.lightened(0.5))
				elif ft == 0:
					for k in 4:
						draw_colored_polygon([origin + Vector2(k * 4, 16), origin + Vector2(k * 4 + 2, 6), origin + Vector2(k * 4 + 4, 16)], color.lightened(0.3))


func _draw_signs() -> void:
	if sim.yscreen != 0:
		return
	for s in DemoLevel.SIGNS:
		draw_string(font, Vector2(s[0] * 16 - _cam(), s[1] * 16), s[2], HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(1, 1, 1, 0.5))


func _draw_extra(o: GimmickBody, info: Dictionary) -> void:
	var p := _pos(o.x, o.y)
	if info.kind == "walker":
		draw_rect(Rect2(p + Vector2(-7, -14), Vector2(14, 14)), Color("2a2a2a"))
		var eye := 2 if o.facing == 1 else -4
		draw_rect(Rect2(p + Vector2(eye, -11), Vector2(2, 3)), Color.WHITE)
		draw_rect(Rect2(p + Vector2(eye + 3, -11), Vector2(2, 3)), Color.WHITE)
	else:
		var half := o.hit_x / 16.0
		draw_rect(Rect2(p + Vector2(-half, -o.hit_y / 16.0), Vector2(half * 2, o.hit_y / 16.0)), Color("c9a227"))


func _draw_player() -> void:
	var p := sim.player
	if p.status == GimmickSim.ST_NONE or sim.player_hidden or not _on_screen(p):
		return
	if p.status == GimmickSim.ST_DEAD and p.timer2 == 5:
		return
	var at := _pos(p.x, p.y)
	var body := Color("3fbf5f")
	var dir := 1 if p.facing == 1 else -1
	var f := p.frame
	if p.status >= GimmickSim.ST_DEAD:
		body = Color("e8e8e8") if (sim.frame_counter & 2) == 0 else Color("3fbf5f")
	# Body: the sprite is 16 px wide and 16 px tall; the hitbox is 12 by 14.
	var squash := 0.0
	if f >= 2 and f <= 7:
		squash = 1.0 if (f & 1) == 0 else 0.0   # walk cycle bob
	elif f == 8:
		squash = -2.0                           # stretched in the air
	draw_rect(Rect2(at + Vector2(-8, -16 + squash), Vector2(16, 16 - squash)), body)
	draw_rect(Rect2(at + Vector2(-5 + dir, -9 + squash), Vector2(10, 7 - squash)), body.lightened(0.55))
	# Horn.
	draw_rect(Rect2(at + Vector2(-1 - dir * 2, -21 + squash), Vector2(3, 5)), Color("d98a2b"))
	# Eyes: closed on the blink frame and while hurt.
	var eye_h := 1 if (f == 1 or f == 10 or f == 11) else 4
	draw_rect(Rect2(at + Vector2(dir * 2 - 3, -14 + squash), Vector2(2, eye_h)), Color.BLACK)
	draw_rect(Rect2(at + Vector2(dir * 2 + 2, -14 + squash), Vector2(2, eye_h)), Color.BLACK)
	if f == 12:
		draw_arc(at + Vector2(0, -8), 12, 0, TAU, 12, Color("ff9a2e"), 2.0)
	elif f >= 13 and f <= 20:
		# Dizzy stars circling the head.
		for k in 3:
			var ang := sim.frame_counter * 0.4 + k * TAU / 3.0
			draw_rect(Rect2(at + Vector2(cos(ang) * 9 - 1, -22 + sin(ang) * 3), Vector2(2, 2)), Color("ffe45c", 1.0 - (f - 13) / 9.0))


func _draw_star() -> void:
	var s := sim.star
	if s.status == GimmickSim.ST_NONE or not _on_screen(s):
		return
	# After-images: the positions 4 and 2 frames ago, only while it is a plain star.
	if s.status == GimmickSim.ST_ACTIVE:
		for i in [0, 2]:
			var t: Array = sim.star_trail[i]
			if t[3] != 0 and t[2] < 0x15:
				_draw_star_shape(_pos(t[0], t[1]), t[2], Color(1.0, 0.9, 0.3, 0.25 + i * 0.12))
	var color := Color("ffe45c") if (s.flags & 1) == 0 else Color("fff6c8")
	_draw_star_shape(_pos(s.x, s.y), s.frame, color)


## `at` is the star's bottom centre; its middle is 8 px above that.
func _draw_star_shape(at: Vector2, frame: int, color: Color) -> void:
	var c := at + Vector2(0, -8)
	if frame == 0x14:
		var pts := PackedVector2Array()
		for k in 8:
			var r := 8.0 if (k & 1) == 0 else 3.5
			var ang := -PI / 2 + k * PI / 4
			pts.append(c + Vector2(cos(ang), sin(ang)) * r)
		draw_colored_polygon(pts, color)
	elif frame < 0x14:
		# Charging: sparks close in on the point above his head.
		var r := (0x12 - frame) * 1.4 + 2.0
		for k in 4:
			var ang := frame * 0.5 + k * PI / 2
			draw_rect(Rect2(c + Vector2(cos(ang), sin(ang)) * r - Vector2(1, 1), Vector2(2, 2)), color)
		if frame >= 0x0E:
			draw_rect(Rect2(c - Vector2(2, 2), Vector2(4, 4)), color)
	else:
		# Vanishing.
		var r := float(frame - 0x14) * 1.5 + 2.0
		draw_arc(c, r, 0, TAU, 10, Color(color, 0.8), 1.0)


func _draw_debug() -> void:
	var p := sim.player
	if p.status != GimmickSim.ST_NONE and _on_screen(p):
		_draw_box(p, Color(0.2, 1.0, 1.0, 0.9))
		var at := _pos(p.x, p.y)
		# Floor probes at the feet, wall probes 8 px up, ceiling probe at the head.
		for dx in [-p.probe_x, p.probe_x]:
			draw_rect(Rect2(at + Vector2(dx / 16.0, 0) - Vector2(0.5, 0.5), Vector2(1, 1)), Color.RED)
		for dx in [-p.hit_x, p.hit_x]:
			draw_rect(Rect2(at + Vector2(dx / 16.0, -8) - Vector2(0.5, 0.5), Vector2(1, 1)), Color.YELLOW)
		draw_rect(Rect2(at + Vector2(0, -p.hit_y / 16.0) - Vector2(0.5, 0.5), Vector2(1, 1)), Color.MAGENTA)
	var s := sim.star
	if s.status == GimmickSim.ST_ACTIVE and _on_screen(s):
		_draw_box(s, Color(1.0, 0.6, 0.1, 0.9) if s.standable != 0 else Color(1.0, 0.6, 0.1, 0.4))
	for slot in extras:
		var o: GimmickBody = sim.objects[slot]
		if o.status == GimmickSim.ST_ACTIVE and _on_screen(o):
			_draw_box(o, Color(1, 0.3, 0.3, 0.7))
	var lines := [
		"X %02X.%02X  Y %02X.%02X" % [p.x >> 8, p.x & 0xFF, p.y >> 8, p.y & 0xFF],
		"VX %+4d  VY %+4d  %s%s" % [p.vx, p.vy, "FLOOR " if p.on_floor else "AIR   ", "WALL" if p.hit_wall else ""],
		"FLOOR TYPE %02X  FRAME %02X  HURT %02X" % [p.floor_type, p.frame, p.timer2],
		"STAR %02X  VX %+4d VY %+4d  REST %d%s" % [s.status, s.vx, s.vy, s.timer2, "  RIDE" if s.rider != 0 else ""],
	]
	for i in lines.size():
		draw_string(font, Vector2(4, 10 + i * 8), lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(1, 1, 1, 0.9))


func _draw_box(o: GimmickBody, color: Color) -> void:
	var at := _pos(o.x, o.y)
	var w := o.hit_x / 16.0
	var h := o.hit_y / 16.0
	draw_rect(Rect2(at + Vector2(-w, -h), Vector2(w * 2, h)), color, false, 1.0)


func _draw_hud() -> void:
	draw_rect(Rect2(0, PLAY_HEIGHT, VIEW_WIDTH, 32), Color("101010"))
	for i in sim.max_health:
		var filled := i < sim.player.health
		draw_rect(Rect2(8 + i * 10, PLAY_HEIGHT + 6, 8, 8), Color("ff5a5a") if filled else Color("402020"))
	var text := "ARROWS MOVE  Z JUMP  X STAR (HOLD, RELEASE)"
	draw_string(font, Vector2(40, PLAY_HEIGHT + 13), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color("c0c0c0"))
	var text2 := "F1 DEBUG  P PAUSE  . STEP  R RESTART%s" % ("   [PAUSED]" if paused else "")
	draw_string(font, Vector2(8, PLAY_HEIGHT + 25), text2, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color("808080"))


# ---------------------------------------------------------------------------
# Sound: square-wave blips standing in for the original's effects
# ---------------------------------------------------------------------------

const BEEPS := {
	0x0D: [520.0, 0.07], 0x0F: [140.0, 0.04], 0x10: [880.0, 0.05], 0x13: [660.0, 0.09],
	0x15: [330.0, 0.04], 0x17: [110.0, 0.25], 0x12: [220.0, 0.12], 0x1E: [90.0, 0.3],
	0x2F: [180.0, 0.6], 0x14: [440.0, 0.04], 0x1C: [990.0, 0.2],
}


func _setup_audio() -> void:
	beeper = AudioStreamPlayer.new()
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = 22050.0
	gen.buffer_length = 0.1
	beeper.stream = gen
	beeper.volume_db = -14.0
	add_child(beeper)
	beeper.play()
	playback = beeper.get_stream_playback()


func _beep(id: int) -> void:
	if BEEPS.has(id):
		beep_queue = [[BEEPS[id][0], int(BEEPS[id][1] * 22050.0), 0.0]]


func _process(_delta: float) -> void:
	if playback == null:
		return
	var frames := playback.get_frames_available()
	while frames > 0:
		var v := 0.0
		if not beep_queue.is_empty():
			var b: Array = beep_queue[0]
			b[2] = fmod(b[2] + b[0] / 22050.0, 1.0)
			v = 0.25 if b[2] < 0.5 else -0.25
			b[1] -= 1
			if b[1] <= 0:
				beep_queue.pop_front()
		playback.push_frame(Vector2(v, v))
		frames -= 1
