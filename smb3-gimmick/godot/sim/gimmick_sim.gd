class_name GimmickSim
extends RefCounted
## A frame-exact model of Yumetaro and his star from Gimmick! (Sunsoft, 1992).
##
## This is a port of the original 6502 routines, kept in the same order and with
## the same integer arithmetic, so that it produces the same numbers as the game.
## Each function names the routine it comes from. Addresses are CPU addresses in
## the Japanese ROM; "bank $1E" is the player bank, "bank $1D" the weapon bank,
## and anything at $E000 or above is the fixed bank.
##
## docs/yumetaro-physics-guide.md explains all of it in prose.

# Controller bits, as the game stores them in $F7 (held) and $F5 (newly pressed).
const BTN_A := 0x80
const BTN_B := 0x40
const BTN_SELECT := 0x20
const BTN_START := 0x10
const BTN_UP := 0x08
const BTN_DOWN := 0x04
const BTN_LEFT := 0x02
const BTN_RIGHT := 0x01

# Status values ($90,x).
const ST_NONE := 0x00
const ST_ACTIVE := 0x01
const ST_TUBE := 0x02
const ST_CHARGE_START := 0x7F  ## the star's status counts from here up to ST_CHARGE_FULL
const ST_CHARGE_READY := 0xA0  ## released at or above this: the star is thrown
const ST_CHARGE_FULL := 0xA9
const ST_DEAD := 0xD0          ## Yumetaro: dying. Star: vanishing (16 frames)
const ST_DEAD_ALT := 0xD1      ## Yumetaro: dying on spikes. Star: vanishing (32 frames)

# Player constants.
const WALK_ACCEL := 2          ## $8149
const WALK_SPEED_CAP := 0x17   ## $8167 / $817D ($E9 = -$17)
const JUMP_VELOCITY := -84     ## $AC, $81A0
const JUMP_CUT_VELOCITY := -24 ## $E8, $81B7
const GRAVITY := 4             ## $F6F5
const MAX_FALL := 0x7F         ## $F6FA
const HURT_TIME := 0x7F        ## $8CA0
const STUN_UNTIL := 0x66       ## $8135: stunned while the hurt timer is at or above this
const HURT_VX := 0x12          ## $8CA5
const HURT_VY := -24           ## $8CA9
const PLAYER_HIT_Y := 0xE0     ## 14 px
const PLAYER_HIT_X := 0x60     ## 6 px
const PLAYER_PROBE_X := 0x30   ## 3 px
const HURT_BOX_X := 0x30       ## $8C7F: Yumetaro's half width against enemies

# Star constants.
const STAR_HIT_Y := 0xF0       ## $83EF: 15 px
const STAR_HIT_X := 0x70       ## $825C: 7 px
const STAR_PROBE_X := 0x20     ## $8261: 2 px
const STAR_HEAD_OFFSET := 0x100  ## $83E9/$83EC: the star is held and thrown 16 px above Yumetaro's feet
const STAR_BOUNCE_LOSS := 8    ## $8143: vy = 8 - (vy before the landing)
const STAR_REST_FRAMES := 8    ## $812D
const STAR_VANISH_FRAMES := 0x10
const STAR_VANISH_ALT_FRAMES := 0x20

# Sound ids ($F285).
const SND_JUMP := 0x0D
const SND_LAND := 0x0F
const SND_CHARGE := 0x10
const SND_THROW := 0x13
const SND_ITEM_ROTATE := 0x14
const SND_BOUNCE := 0x15
const SND_HURT := 0x17
const SND_MEDICINE := 0x1C
const SND_SPIKES := 0x1E
const SND_STOP_MUSIC := 0x1F
const SND_DEATH := 0x2F

const DEATH_FREEZE := 24       ## bank $1D $8E07
const RESPAWN_TIME := 0xC0     ## bank $1D $8E78
const SCREEN_CHANGE_FREEZE := 4

const SLOTS := 10

var world: GimmickWorld
var objects: Array[GimmickBody] = []
var player: GimmickBody
var star: GimmickBody

var frame_counter := 0   ## $ED, low byte of the global timer
var yscreen := 0         ## $16
var camera_x := 0        ## $15:$14, same units as an X position
var max_health := 2      ## $2B
var jump_hold := 0       ## $4B
var was_on_floor := false  ## $53
var b_lockout := 0       ## $55
var weapon_type := 0     ## $0351: 0 star, 1 fireball, 2 bomb
var items: Array[int] = [0, 0, 0]  ## $36-$38: 0 none, 1 medicine, 2 fireball, 3 bomb
var item_count := 0      ## $39
var combo := 0           ## $35
var star_saved_vy := 0   ## $0397
var star_saved_vx := 0   ## $03A1
var screen_changed := false  ## set for one frame when Yumetaro moves to another vertical screen
var pause_frames := 0        ## frames left of the freeze after a screen change
var death_wait := 0          ## frames left of the freeze at the start of a death
var respawn_timer := 0       ## $EA
var needs_respawn := false   ## set when the respawn timer runs out; the game decides what happens
## The 16 balls Yumetaro bursts into. Each entry is [x, y] in position units.
var death_particles: Array = []
var player_hidden := false   ## the hurt blink: Yumetaro is not drawn this frame

## History of the star for its after-images: [0] is 4 frames old, [4] is this frame.
## Each entry is [x, y, frame, status].
var star_trail: Array = []

## Sound ids queued this frame, in order.
var sounds: Array[int] = []

## Called once per frame between the star and the end-of-frame steps, where the
## original runs the enemy bank. Use it to move slots 2-9.
var update_objects := Callable()


func _init(p_world: GimmickWorld = null) -> void:
	world = p_world if p_world != null else GimmickWorld.new()
	for i in SLOTS:
		objects.append(GimmickBody.new())
	player = objects[0]
	star = objects[1]
	for i in 5:
		star_trail.append([0, 0, 0, 0])
	player.hit_y = PLAYER_HIT_Y
	player.hit_x = PLAYER_HIT_X
	player.probe_x = PLAYER_PROBE_X


func spawn_player(x: int, y: int) -> void:
	player.clear()
	player.status = ST_ACTIVE
	player.x = x
	player.y = y
	player.facing = 1
	player.health = max_health
	player.hit_y = PLAYER_HIT_Y
	player.hit_x = PLAYER_HIT_X
	player.probe_x = PLAYER_PROBE_X
	yscreen = (y >> 12) & 3
	star.clear()
	weapon_type = 0
	jump_hold = 0
	b_lockout = 0
	was_on_floor = false
	pause_frames = 0
	death_wait = 0
	respawn_timer = 0
	needs_respawn = false
	death_particles.clear()


# ---------------------------------------------------------------------------
# Byte helpers
# ---------------------------------------------------------------------------

static func s8(b: int) -> int:
	b &= 0xFF
	return b - 256 if b >= 128 else b


## "CMP #k / BPL": true when the branch is taken. This is not a true signed
## comparison: it only looks at bit 7 of (value - k), so it is wrong when the two
## are more than 127 apart. The original relies on it, so we do too.
static func cmp_bpl(value: int, k: int) -> bool:
	return ((value - k) & 0xFF) < 0x80


## "CMP #$7F / ROR A": halves a signed byte. $7F is treated as negative and
## becomes $BF (-65), a quirk of how the carry is prepared.
static func halve(value: int) -> int:
	var b := value & 0xFF
	var carry := 0x80 if b >= 0x7F else 0
	return s8((b >> 1) | carry)


## Moves a velocity toward zero by `amount` without crossing it ($F689).
static func friction(v: int, amount: int) -> int:
	if v >= 0:
		v -= amount
		return v if v >= 0 else 0
	v += amount
	return v if v < 0 else 0


func sound(id: int) -> void:
	sounds.append(id)


# ---------------------------------------------------------------------------
# One frame
# ---------------------------------------------------------------------------

## Runs one 60 Hz frame. `held` and `pressed` use the BTN_* bits.
func step(held: int, pressed: int) -> void:
	sounds.clear()
	screen_changed = false
	if pause_frames > 0:
		# The screen is being redrawn after a vertical screen change. Nothing
		# runs, not even the frame counter.
		pause_frames -= 1
		return
	if death_wait > 0:
		# The whole game stands still for 24 frames when Yumetaro dies.
		frame_counter = (frame_counter + 1) & 0xFF
		death_wait -= 1
		if death_wait == 0:
			player.timer2 = 1
			sound(SND_DEATH)
		return
	_vertical_screen_change()       # $E2F6
	_player_update(held, pressed)   # bank $1E $8000
	_weapon_update()                # bank $1D $8006
	if update_objects.is_valid():
		update_objects.call()       # bank $10 $8003
	_end_of_frame()                 # $E380
	_update_camera()                # bank $1E $8FA3
	_star_draw_phase()              # bank $1D $8469
	if player.status >= ST_DEAD:
		_death_update()             # bank $1D $8D85
	else:
		_player_draw_phase()        # bank $1E $83F5
	# $E59B: the respawn countdown.
	if respawn_timer != 0:
		respawn_timer -= 1
		if respawn_timer == 0:
			needs_respawn = true
			player.status = ST_NONE
	if screen_changed:
		pause_frames = SCREEN_CHANGE_FREEZE
	frame_counter = (frame_counter + 1) & 0xFF


## $E2F6. The playfield is rows 1-11 of a 12-row screen. Reaching row 0 moves
## Yumetaro to row 11 of the screen above; reaching row 12 moves him to row 1 of
## the screen below. Both wrap around the four screens.
func _vertical_screen_change() -> void:
	var tile := player.y_tile()
	var row := tile & 0x0F
	var new_tile := 0
	if row == 0:
		new_tile = ((tile & 0xF0) - 0x10) | 0x0B
		if new_tile < 0:
			new_tile = 0x3B
	elif row == 0x0C:
		new_tile = (tile & 0xF0) + 0x11
		if new_tile >= 0x40:
			new_tile = 0x01
	else:
		return
	player.y = (new_tile << 8) | player.y_sub()
	yscreen = new_tile >> 4
	screen_changed = true
	# Every other object is removed. A star that is still being charged survives.
	var first := 2
	if star.status < 0x80 or star.status >= ST_DEAD:
		first = 1
		weapon_type = 0
	for i in range(first, SLOTS):
		objects[i].status = ST_NONE
		objects[i].standable = 0


## $E380. Health 0 starts the death, and Yumetaro is kept inside the level.
func _end_of_frame() -> void:
	if player.health == 0 and player.status < ST_DEAD:
		player.timer2 = 0
		player.status = ST_DEAD
	var xt := player.x_tile()
	if xt == 0:
		if player.x_sub() < 0x80:
			player.x = 0x0080
			player.vx = 0
	elif xt >= 0x7F:
		if player.x_sub() >= 0x80:
			player.x = (xt << 8) | 0x7F
			player.vx = 0


## Bank $1E $8FA3. The camera puts Yumetaro 8 tiles from its left edge and moves
## at most 127 units (just under 8 px) per frame. A screen can lock it.
func _update_camera() -> void:
	var target := (player.x - 0x0800) & 0xFFFF
	var xt := player.x_tile()
	var lock := world.camera_lock[(((xt & 0x70) >> 2) | yscreen) & 0x1F]
	var locked := (lock & 0x40) != 0 if (xt & 0x08) != 0 else (lock & 0x80) != 0
	if locked:
		target = (xt & 0xF0) << 8
	var delta := (target - camera_x) & 0xFFFF
	if delta == 0:
		return
	if delta < 0x8000:
		camera_x = (camera_x + mini(delta, 0x7F)) & 0xFFFF
	else:
		camera_x = (camera_x - mini(0x10000 - delta, 0x80)) & 0xFFFF


# ---------------------------------------------------------------------------
# Yumetaro (bank $1E)
# ---------------------------------------------------------------------------

func _player_update(held: int, pressed: int) -> void:
	var p := player
	# $8000: while dying, a star being charged is dropped.
	if p.status >= ST_DEAD:
		if star.status >= 0x80 and star.status < ST_DEAD:
			if star.status >= ST_CHARGE_READY:
				star.status = ST_DEAD
				star.timer2 = 0
				weapon_type = 0
			else:
				star.status = ST_NONE
				star.standable = 0
		return

	# $8026: the B lockout only runs down while B is held.
	if (held & BTN_B) == 0:
		b_lockout = 0
	else:
		if b_lockout != 0:
			b_lockout -= 1
		if (held & BTN_UP) != 0:
			_use_item(pressed)
	# $8094: Down rotates the items.
	if (pressed & BTN_DOWN) != 0 and not (star.status >= 0x80 and star.status < ST_DEAD) and item_count >= 2:
		if item_count == 2:
			items = [items[1], items[0], items[2]]
		else:
			items = [items[1], items[2], items[0]]
		sound(SND_ITEM_ROTATE)

	# $80CE: riding a tube.
	if p.status == ST_TUBE:
		p.flags = GimmickWorld.BEHIND
		_tube_step(p)
		p.frame = 0x15
		return

	# $80E4
	p.status = ST_ACTIVE
	p.frame = 1 if (frame_counter & 0xDC) == 0 else 0   # stand, or blink
	# The tile 8 px above his feet decides tubes and "behind the background".
	var t := world.tile_flat(yscreen, p.x_tile() * 12 + (((p.y - 0x80) >> 8) & 0x0F))
	var a := world.attr[t]
	if a == GimmickWorld.TUBE:
		p.flags = GimmickWorld.BEHIND
		_tube_enter(p, t)
		p.frame = 0x15
		return
	p.flags = a & GimmickWorld.BEHIND

	if p.timer2 >= STUN_UNTIL:
		# $8132: stunned. No input at all, and a star being charged is let go.
		if star.status >= 3 and star.status < ST_DEAD:
			_release_star()
	else:
		_walk_input(held)
		# $8186: landing sound.
		if not was_on_floor and p.on_floor:
			sound(SND_LAND)
		was_on_floor = p.on_floor
		# $8199: jump.
		if (pressed & BTN_A) != 0 and p.on_floor:
			p.vy = JUMP_VELOCITY
			jump_hold = 0xAC
			sound(SND_JUMP)
		# $81AB: letting go of A cuts the rise.
		if jump_hold != 0 and (held & BTN_A) == 0:
			if p.vy < 0 and not cmp_bpl(p.vy, 0xE8):
				p.vy = JUMP_CUT_VELOCITY
			jump_hold = 0
		_charge_input(held)

	_walk_animation(held)        # $82A1
	physics(p)                   # $82EA
	_stand_on_objects()          # $82EF


## $8149
func _walk_input(held: int) -> void:
	var p := player
	var accel := WALK_ACCEL
	if (p.floor_type & 0x7F) == 7:
		accel = frame_counter & 1   # ice: half the acceleration, in alternate frames
	if (held & BTN_RIGHT) != 0:
		p.facing = 1
		if not cmp_bpl(p.vx, WALK_SPEED_CAP):
			p.vx = s8(p.vx + accel)
	if (held & BTN_LEFT) != 0:
		p.facing = 0
		if cmp_bpl(p.vx, 0x100 - WALK_SPEED_CAP):
			p.vx = s8(p.vx - accel)


## $81C3
func _charge_input(held: int) -> void:
	var st := star.status
	if st == ST_ACTIVE or st == ST_TUBE or st >= ST_DEAD:
		return
	if player.flags != 0 or b_lockout != 0 or (held & BTN_B) == 0:
		_release_star()
		return
	if st == ST_NONE:
		sound(SND_CHARGE)
		star.status = ST_CHARGE_START
		star.facing = 0
		st = 0
	if st != ST_CHARGE_FULL:
		star.status += 1


## $81FB. Below ST_CHARGE_READY the star is simply dropped. This also runs on
## every frame in which nothing is being charged, where it does nothing useful.
func _release_star() -> void:
	if star.status < ST_CHARGE_READY:
		star.status = ST_NONE
		star.standable = 0
		weapon_type = 0
		return
	_throw()


## $820D
func _throw() -> void:
	var p := player
	var s := star
	s.hit_wall = false
	s.on_floor = false
	s.timer2 = 0
	combo = 0
	s.status = ST_ACTIVE
	var type := weapon_type
	if type != 0:
		_consume_item()
	sound(GimmickTables.THROW_SOUND[type])
	s.x = p.x
	s.y = (p.y - [0x0100, 0x0080, 0x0100][type]) & 0xFFFF
	s.hit_y = [0x00F0, 0x0200, 0x00E0][type]
	s.hit_x = STAR_HIT_X
	s.probe_x = STAR_PROBE_X
	s.facing = p.facing
	# Half of Yumetaro's velocity is added to the throw.
	var vy := 0 if type == 1 else halve(p.vy)
	vy += s8(GimmickTables.THROW_VY[type])
	if vy > 127 or vy < -128:
		vy = 127
	s.vy = vy
	star_saved_vy = vy
	var vx := s8(halve(p.vx) + GimmickTables.THROW_VX[p.facing * 4 + type])
	s.vx = vx
	star_saved_vx = vx


## $803D. Up + B uses the first item.
func _use_item(pressed: int) -> void:
	match items[0]:
		1:  # medicine
			if (pressed & BTN_B) == 0:
				return
			if item_count != 3 and max_health == player.health:
				return
			sound(SND_MEDICINE)
			b_lockout = 0x50
			player.health = max_health
			_consume_item()
		2:  # fireball
			if star.status == ST_NONE:
				weapon_type = 1
		3:  # bomb
			if star.status == ST_NONE:
				weapon_type = 2


func _consume_item() -> void:
	items = [items[1], items[2], 0]
	item_count -= 1


## $82A1
func _walk_animation(held: int) -> void:
	var p := player
	var step := 0
	if p.floor_type == 0x88 or (p.floor_type & 0x7F) == 7:
		if (held & (BTN_LEFT | BTN_RIGHT)) == 0:
			return
		step = 2
	else:
		var speed := absi(p.vx)
		if speed < 2:
			p.timer1 = 4
			if (held & (BTN_LEFT | BTN_RIGHT)) == 0:
				return
			step = 0
		else:
			step = speed >> 4
	var counter := p.timer1 + step + 1
	if counter >= 0x3D:
		counter -= 0x3D
	p.timer1 = counter & 0xFF
	p.frame = GimmickTables.WALK_FRAMES[mini(p.timer1, 60)]


## $82EF. Yumetaro lands on the highest-numbered standable object under his feet.
func _stand_on_objects() -> void:
	var p := player
	if p.vy < 0:
		for i in range(1, SLOTS):
			objects[i].rider = 0
		return
	var i := SLOTS - 1
	while i >= 1:
		var o := objects[i]
		if _stand_test(o) and not _blocked_above(o):
			o.rider = 1
			p.vx = friction(p.vx, 1)
			p.vy = 0
			p.on_floor = true
			for j in range(1, i):
				objects[j].rider = 0
			return
		o.rider = 0
		i -= 1


## $FF13. His feet must be 0 to 7 15/16 px below the object's top, and his centre
## within (object half width + his feet half width) of the object's centre.
func _stand_test(o: GimmickBody) -> bool:
	if (o.standable & 0x40) == 0:
		return false
	var top := (o.y - o.hit_y) & 0xFFFF
	var d := (player.y - top) & 0xFFFF
	if (d >> 8) != 0 or (d & 0x80) != 0:
		return false
	var dx := (player.x - o.x) & 0xFFFF
	var reach := (o.hit_x + player.probe_x) & 0xFFFF
	if dx < 0x8000:
		return ((dx - reach) & 0xFFFF) >= 0x8000
	return ((dx + reach) & 0xFFFF) < 0x8000


## $8300. No standing if the tile 9 px above the object's top is solid.
func _blocked_above(o: GimmickBody) -> bool:
	var row := (((o.y - ((o.hit_y + 0x90) & 0xFFFF)) & 0xFFFF) >> 8) & 0x0F
	if row >= 0x0C:
		row = 0
	return (world.attr[world.tile_flat(yscreen, o.x_tile() * 12 + row)] & GimmickWorld.SOLID) != 0


## Bank $10 $8C7F. Call this when an enemy touches Yumetaro. `enemy` is only used
## for its position. Returns true if he was hurt.
func hurt_player(enemy: GimmickBody) -> bool:
	var p := player
	if p.timer2 != 0 or p.status >= ST_DEAD:
		return false
	var side := touch_test(enemy)
	if side < 0:
		return false
	p.facing = side              # he turns to face the enemy
	p.health -= 1
	sound(SND_HURT)
	p.timer2 = HURT_TIME
	p.vx = -HURT_VX if side == 1 else HURT_VX
	p.vy = HURT_VY
	return true


## Bank $10 $8CC1. Returns -1 for no contact, 1 if Yumetaro is to the left of the
## object and 0 if he is to the right or level with it.
func touch_test(o: GimmickBody) -> int:
	var p := player
	var dy := (p.y - o.y) & 0xFFFF
	if dy >= 0x8000:
		# Yumetaro's feet are above the object's feet: the point 8 px above his
		# feet must be at or below the object's top.
		if ((dy - 0x80 + o.hit_y) & 0xFFFF) >= 0x8000:
			return -1
	elif dy > 0x60:
		return -1    # his feet are more than 6 px below the object's feet
	var dx := (p.x - o.x) & 0xFFFF
	var reach := (o.hit_x + HURT_BOX_X) & 0xFFFF
	if dx < 0x8000:
		return 0 if ((dx - reach) & 0xFFFF) >= 0x8000 else -1
	return 1 if ((dx + reach) & 0xFFFF) < 0x8000 else -1


## $83F5. Runs when Yumetaro is drawn, after everything else in the frame.
func _player_draw_phase() -> void:
	var p := player
	player_hidden = false
	if p.frame != 0x15 and not p.on_floor:
		p.frame = 8
		p.timer1 = 0x3B
	if p.timer2 != 0:
		var t := p.timer2 - STUN_UNTIL
		p.timer2 -= 1
		if t >= 0:
			p.frame = GimmickTables.HURT_FRAMES[t]
		elif (t & 2) != 0:
			player_hidden = true


## Bank $1D $8D85. Runs instead of the normal drawing while Yumetaro is dying.
func _death_update() -> void:
	var p := player
	player_hidden = false
	for i in range(1, SLOTS):
		objects[i].rider = 0
	match p.status:
		ST_DEAD:
			if p.timer2 == 0:
				# $8DD7: stop the music, hold the pose for 24 frames.
				sound(SND_STOP_MUSIC)
				if p.frame != 0x15 and not p.on_floor:
					p.frame = 8
				death_wait = DEATH_FREEZE
			elif p.timer2 != 5:
				# $8E3C: four frames of the burst animation.
				p.frame = p.timer2
				p.timer2 += 1
				if p.timer2 == 5:
					death_particles.clear()
					for i in 16:
						death_particles.append([p.x, p.y])
					if respawn_timer == 0:
						respawn_timer = RESPAWN_TIME
			else:
				# $8E81: sixteen balls fly outward at just under 4 px per frame.
				for i in death_particles.size():
					death_particles[i][0] += GimmickTables.DEATH_VX[i]
					death_particles[i][1] += GimmickTables.DEATH_VY[i]
		ST_DEAD_ALT, 0xD2:
			# $8DA3 / $8DBA: death on spikes. Eight animation frames, four game frames each.
			if p.status == ST_DEAD_ALT:
				p.status = 0xD2
				if respawn_timer == 0:
					sound(SND_STOP_MUSIC)
					respawn_timer = RESPAWN_TIME
			if (p.timer2 >> 2) != 8:
				p.frame = p.timer2 >> 2
				p.timer2 += 1
			else:
				player_hidden = true


# ---------------------------------------------------------------------------
# The star (bank $1D)
# ---------------------------------------------------------------------------

## $8006. Only the star is modelled; the fireball and bomb are other routines.
func _weapon_update() -> void:
	var s := star
	if s.status == ST_NONE:
		return
	if s.status == ST_TUBE:
		s.flags = GimmickWorld.BEHIND
		_tube_step(s)
		s.flags |= frame_counter & 1
		return
	# $8042: the tile at the star's centre (8 px above its bottom).
	var row := (((s.y - 0x80) & 0xFFFF) >> 8) & 0x0F
	if row >= 0x0C:
		row = 0x0B
	var t := world.tile_flat(yscreen, s.x_tile() * 12 + row)
	s.flags = world.attr[t] & GimmickWorld.BEHIND

	if s.status >= 0x80:
		if s.status == ST_DEAD_ALT:
			# $80A4
			s.standable = 0
			s.frame = 0x1B + (s.timer2 >> 2)
			s.timer2 += 1
			if s.timer2 == STAR_VANISH_ALT_FRAMES:
				s.status = ST_NONE
				weapon_type = 0
		elif s.status == ST_DEAD:
			_star_vanish_step()
		else:
			# $807D: charging. The star sits 16 px above Yumetaro.
			s.frame = GimmickTables.CHARGE_FRAMES[mini(s.status & 0x7F, 41)]
			s.x = player.x
			s.y = (player.y - STAR_HEAD_OFFSET) & 0xFFFF
			s.flags |= frame_counter & 1
		return

	# $80E7: thrown.
	if world.attr[t] == GimmickWorld.TUBE:
		_tube_enter(s, t)
		s.flags |= frame_counter & 1
		s.frame = 0x14
		return
	s.status = ST_ACTIVE
	if s.hit_wall:
		s.vx = s8(-star_saved_vx)
		s.standable = 0x40
	star_saved_vx = s.vx
	if (world.attr[t] & GimmickWorld.SOLID) != 0:
		_star_vanish()
		return
	if s.vx == 0 and s.vy == 0:
		s.timer2 += 1
	if s.timer2 >= STAR_REST_FRAMES:
		_star_vanish()
		return
	if s.on_floor:
		if s.timer1 == 0:
			sound(SND_BOUNCE)
		s.vy = s8(STAR_BOUNCE_LOSS - star_saved_vy)
		s.standable = 0x40
	star_saved_vy = s.vy
	s.timer1 = 0x80 if s.on_floor else 0
	physics(s)
	s.frame = 0x14
	s.flags |= frame_counter & 1


## $80C6
func _star_vanish() -> void:
	star.status = ST_DEAD
	star.timer2 = 0
	_star_vanish_step()


## $80CF
func _star_vanish_step() -> void:
	var s := star
	s.standable = 0
	s.frame = GimmickTables.VANISH_FRAMES[mini(s.timer2, 15)]
	s.timer2 += 1
	if s.timer2 == STAR_VANISH_FRAMES:
		s.status = ST_NONE
		weapon_type = 0


## Bank $1D $8469. Records the after-images and removes a thrown star that has
## left the screen.
func _star_draw_phase() -> void:
	var s := star
	star_trail.pop_front()
	star_trail.append([s.x, s.y, s.frame, s.status])
	if s.status >= 0x80:
		return
	var d := (s.x_tile() - (camera_x >> 8)) & 0xFF
	if (s.y_tile() & 0x0F) >= 0x0D or s.x_tile() >= 0x80 or cmp_bpl(d, 0x12) or not cmp_bpl(d, 0xFD):
		s.status = ST_NONE
		s.standable = 0
		weapon_type = 0


## Bank $10 $8D48. True if the thrown star overlaps `o`. Enemies call this
## themselves and decide what a hit means.
func star_touches(o: GimmickBody) -> bool:
	var s := star
	if s.status != ST_ACTIVE:
		return false
	var dy := (s.y - o.y) & 0xFFFF
	if dy >= 0x8000:
		if ((dy + o.hit_y) & 0xFFFF) >= 0x8000:
			return false
	elif dy > s.hit_y:
		return false
	var dx := (s.x - o.x) & 0xFFFF
	var reach := (o.hit_x + s.hit_x) & 0xFFFF
	if dx < 0x8000:
		return ((dx - reach) & 0xFFFF) >= 0x8000
	return ((dx + reach) & 0xFFFF) < 0x8000


## Bank $10 $8E8F. Makes `o` solid to the star: the star lands on its top or
## bounces off its side. Platforms and shielded enemies use this.
func star_collide_solid(o: GimmickBody) -> void:
	var s := star
	if weapon_type == 1 or s.status >= 0x80 or s.vy < 0:
		return
	if not star_touches(o):
		return
	var top := (o.y - o.hit_y) & 0xFFFF
	var d := (s.y - top) & 0xFFFF
	if (d >> 8) == 0 and (d & 0x80) == 0:
		s.on_floor = true
		s.y = top
		return
	s.hit_wall = true
	var dx := (s.x - o.x) & 0xFFFF
	if dx < 0x8000:
		s.x = (o.x + o.hit_x + s.hit_x) & 0xFFFF
	else:
		s.x = (o.x - o.hit_x - s.hit_x) & 0xFFFF


# ---------------------------------------------------------------------------
# Shared object physics ($F596, fixed bank)
# ---------------------------------------------------------------------------

## Friction or push from the floor, gravity, movement and tile collision for one
## object. Yumetaro, the star and most enemies all use this.
func physics(o: GimmickBody) -> void:
	var old_x := o.x & 0xFFF0
	var w := world
	var gravity := true
	if o.row() < 0x0C:
		var index := o.x_tile() * 12 + o.row()
		var t := w.tile_flat(yscreen, index)
		if w.floor_type[t] == 0:
			_lethal_tile(o, t)
			return
		if (w.attr[t] & GimmickWorld.SLOPE) != 0:
			gravity = false
			_slope_floor(o, t)       # $F9D1
		else:
			# $F60D: the floor type is the larger of the two under his feet.
			var left := index - 12 if o.x_sub() < o.probe_x else index
			var right := index + 12 if o.x_sub() + o.probe_x > 0xFF else index
			var ft := maxi(w.floor_type[w.tile_flat(yscreen, left)], w.floor_type[w.tile_flat(yscreen, right)])
			o.floor_type = ft
			match ft:
				2:  # $F689 normal ground
					o.vx = friction(o.vx, 1)
				3:  # $F670 conveyor to the right
					o.x = (o.x + 0x10) & 0xFFFF
					o.vx = friction(o.vx, 1)
				4:  # $F67E conveyor to the left
					o.x = (o.x - 0x10) & 0xFFFF
					o.vx = friction(o.vx, 1)
				5:  # $F6CD
					if not cmp_bpl(o.vx, 0x20):
						o.vx = s8(o.vx + 3)
				6:  # $F6DB
					if not cmp_bpl(o.vx, 0xF0):
						o.vx = -16
					if not cmp_bpl(o.vx, 0x20):
						o.vx = s8(o.vx + 1)
					gravity = false
				7:  # $F6A5 ice
					o.vx = friction(o.vx, 1 if (frame_counter & 7) == 0 else 0)
	if gravity:
		# $F6F3
		o.vy = mini(o.vy + GRAVITY, MAX_FALL)
	_move_and_collide(o, old_x)


## $FCE8. Movement and collision only: no floor effects and no gravity. Moving
## platforms and flying enemies use this entry, and it still carries a rider.
func move_object(o: GimmickBody) -> void:
	_move_and_collide(o, o.x & 0xFFF0)


## $F6FE
func _move_and_collide(o: GimmickBody, old_x: int) -> void:
	var w := world
	o.x = (o.x + o.vx) & 0xFFFF
	o.y = (o.y + o.vy) & 0xFFFF

	if o.row() < 0x0C:
		o.on_floor = false
		o.hit_wall = false
		var index := o.x_tile() * 12 + o.row()
		if (w.attr[w.tile_flat(yscreen, index)] & GimmickWorld.SLOPE) != 0:
			_slope_land(o)           # $F838
		elif o.vy < 0:
			_ceiling(o)              # $F761
		else:
			_floor(o)                # $F7D3
		_walls(o)                    # $F88C
	if o.rider != 0:
		_carry_rider(o, old_x)       # $F926


## $F5D6
func _lethal_tile(o: GimmickBody, t: int) -> void:
	var v := world.variant[t] & 3
	if v != 0:
		o.y = (o.y & 0xFF00) | GimmickTables.LETHAL_Y[v]
		sound(SND_SPIKES)
	o.status = GimmickTables.LETHAL_STATUS[v]
	o.health = 0
	o.timer2 = 0
	o.vy = 0
	o.frame = 0


## $F761. One probe at the centre of the head.
func _ceiling(o: GimmickBody) -> void:
	if o.x_tile() >= 0x80:
		return
	var head := (o.y - o.hit_y) & 0xFFFF
	var probe := head
	if o.rider != 0:
		probe = (head - player.hit_y) & 0xFFFF   # a carried Yumetaro makes it taller
	var row := (probe >> 8) & 0x0F
	if row >= 0x0E:
		row = 0
	if (world.attr[world.tile_flat(yscreen, o.x_tile() * 12 + row)] & GimmickWorld.SOLID) == 0:
		return
	o.vy = 0
	if o.rider != 0:
		o.y = (player.y + o.hit_y) & 0xFFFF
	else:
		# Head against the underside of the tile.
		o.y = ((((head >> 8) + 1 + (o.hit_y >> 8)) & 0xFF) << 8) | (o.hit_y & 0xFF)


## $F7D3. Two probes, at the left and right edge of the feet.
func _floor(o: GimmickBody) -> void:
	var left := (o.x - o.probe_x) & 0xFFFF
	if left >= 0x8000:
		return
	var index := (left >> 8) * 12 + o.row()
	var land := (world.attr[world.tile_flat(yscreen, index)] & 0xC0) == GimmickWorld.SOLID
	if not land:
		if ((o.probe_x << 1) & 0xFF) + (left & 0xFF) > 0xFF:
			index += 12
		land = (world.attr[world.tile_flat(yscreen, index)] & 0xC0) == GimmickWorld.SOLID
	# Only the top half of a tile catches a falling object.
	if land and (o.y & 0x80) == 0:
		o.vy = 0
		o.y &= 0xFF00
		o.on_floor = true


## $F838. Slope tiles are tested at the centre of the feet only.
func _slope_land(o: GimmickBody) -> void:
	if o.x_tile() >= 0x80:
		return
	var index := o.x_tile() * 12 + o.row()
	var t := world.tile_flat(yscreen, index)
	if (world.attr[t] & GimmickWorld.SLOPE_FILL) != 0:
		# Inside the filler under a slope: step up to the bottom of the tile above.
		o.y = ((((o.y >> 8) - 1) & 0xFF) << 8) | 0xF0
		t = world.tile_flat(yscreen, index - 1)
	var h := GimmickTables.SLOPE_HEIGHT[(o.x_sub() & 0xF0) | (world.attr[t] & GimmickWorld.SHAPE_MASK)]
	if o.y_sub() >= h:
		o.y = (o.y & 0xFF00) | h
		o.vy = 0
		o.on_floor = true


## $F88C. One probe on each side, 8 px above the feet. A wall pushes the object
## out by exactly 1 px per frame.
func _walls(o: GimmickBody) -> void:
	var row := (((o.y - 0x80) & 0xFFFF) >> 8) & 0x0F
	var left := (o.x - o.hit_x) & 0xFFFF
	if left < 0x8000:
		if (world.attr[world.tile_flat(yscreen, (left >> 8) * 12 + row)] & GimmickWorld.SOLID) != 0:
			if o.vx < 0:
				o.vx = 0
			o.hit_wall = true
			o.x = (o.x + 0x10) & 0xFFFF
			return
	var right := (o.x + o.hit_x) & 0xFFFF
	if right < 0x8000:
		if (world.attr[world.tile_flat(yscreen, (right >> 8) * 12 + row)] & GimmickWorld.SOLID) != 0:
			if o.vx >= 0:
				o.vx = 0
			o.hit_wall = true
			o.x = (o.x - 0x10) & 0xFFFF


## $F926. Moves Yumetaro with the object he stands on.
func _carry_rider(o: GimmickBody, old_x: int) -> void:
	var p := player
	p.x = (p.x + (o.x & 0xFFF0) - old_x) & 0xFFFF
	p.y = (o.y - o.hit_y) & 0xFFFF
	var speed := absi(o.vx) & 0xFF
	var row := (((p.y - 0x80) & 0xFFFF) >> 8) & 0x0F
	var left := ((p.x - p.hit_x) & 0xFFFF) >> 8
	if (world.attr[world.tile_flat(yscreen, left * 12 + row)] & GimmickWorld.SOLID) != 0:
		p.x = (p.x + speed) & 0xFFFF
		return
	var right := ((p.x + p.hit_x) & 0xFFFF) >> 8
	if (world.attr[world.tile_flat(yscreen, right * 12 + row)] & GimmickWorld.SOLID) != 0:
		p.x = (p.x - speed) & 0xFFFF


## $F9D1. Runs instead of friction and gravity when the object's feet are in a slope tile.
func _slope_floor(o: GimmickBody, t: int) -> void:
	o.floor_type = 0x80
	var h := GimmickTables.SLOPE_HEIGHT[(o.x_sub() & 0xF0) | (world.attr[t] & GimmickWorld.SHAPE_MASK)]
	if o.y_sub() < h:
		# Above the surface: plain gravity.
		var v := (o.vy + GRAVITY) & 0xFF
		if v >= 0x80 and v < 0x84:
			v = MAX_FALL
		o.vy = s8(v)
		return
	var wobble := (frame_counter & 1) | 2   # 2 or 3, alternating
	var col := o.x_sub() >> 4
	var behaviour := world.variant[t]
	match behaviour:
		0, 13:  # $FA40 / $FA3B: steep, slides left
			if behaviour == 13: o.floor_type = 0x87
			o.vx = s8(o.vx - wobble)
			if not cmp_bpl(o.vx, 0xD0): o.vx = -48
		1, 14:  # $FA68 / $FA63: steep, slides right
			if behaviour == 14: o.floor_type = 0x87
			o.vx = s8(o.vx + wobble)
			if cmp_bpl(o.vx, 0x30): o.vx = 48
		2, 15:  # $FA85 / $FA80: gentle, slides left
			if behaviour == 15: o.floor_type = 0x87
			if cmp_bpl(o.vx, 0xD8): o.vx = s8(o.vx - 1)
		3, 16:  # $FA98 / $FA93: gentle, slides right
			if behaviour == 16: o.floor_type = 0x87
			if not cmp_bpl(o.vx, 0x28): o.vx = s8(o.vx + 1)
		4:  # $FAA6: curve, pull to the left that fades across the tile
			if cmp_bpl(o.vx, 0xE0): o.vx = s8(o.vx - GimmickTables.CURVE_LEFT[col])
		5:  # $FABC: curve, pull to the right that grows across the tile
			if not cmp_bpl(o.vx, 0x20): o.vx = s8(o.vx + GimmickTables.CURVE_RIGHT[col])
		6:  # $FAD2: moving slope, carries left
			o.floor_type = 0x88
			o.x = (o.x - 0x10) & 0xFFFF
			o.vx = s8(o.vx - wobble)
			if not cmp_bpl(o.vx, 0xF0): o.vx = -16
		7:  # $FAFA: moving slope, carries right
			o.floor_type = 0x88
			o.x = (o.x + 0x10) & 0xFFFF
			o.vx = s8(o.vx + wobble)
			if cmp_bpl(o.vx, 0x10): o.vx = 16
		8:  # $FB22
			o.floor_type = 0x88
			if cmp_bpl(o.vx, 0xE0): o.vx = s8(o.vx - 1)
		9:  # $FB35
			o.floor_type = 0x88
			if not cmp_bpl(o.vx, 0x20): o.vx = s8(o.vx + 1)
		10:  # $FB48: a slope you can stand still on
			o.floor_type = 0x88
			o.vx = friction(o.vx, 1)
		11:  # $FB69
			o.x = (o.x + 0x10) & 0xFFFF
			o.vx = friction(o.vx, 1)
		12:  # $FB77
			o.x = (o.x - 0x10) & 0xFFFF
			o.vx = friction(o.vx, 1)
		17:  # $FB9E
			o.x = (o.x + 0x0A) & 0xFFFF
			o.vx = friction(o.vx, 1)
		18:  # $FBAC
			o.x = (o.x + 0x07) & 0xFFFF
			o.vx = friction(o.vx, 1)
		19:  # $FBBA
			o.x = (o.x - 0x07) & 0xFFFF
			o.vx = friction(o.vx, 1)
	# $FA55: press the object 3 px into the slope so it stays on it going downhill.
	o.y = (o.y + 0x30) & 0xFFFF


# ---------------------------------------------------------------------------
# Tubes ($FCFD / $FD6D)
# ---------------------------------------------------------------------------

## $FCFD. `tile_id` is the metatile id: its low 3 bits pick one of six paths.
func _tube_enter(o: GimmickBody, tile_id: int) -> void:
	o.on_floor = false
	o.hit_wall = false
	match tile_id & 0xF0:
		0x20:
			if o.vy < 0:
				o.y = (o.y - 0x1000) & 0xFFFF
		0x30:
			if o.vy >= 0:
				o.y = (o.y + 0x1000) & 0xFFFF
	var path := tile_id & 7
	var quadrant := (2 if ((o.y_sub() - 0x10) & 0x80) != 0 else 0) | (1 if o.x_sub() >= 0x80 else 0)
	var t := GimmickTables.TUBE_ENTRY[mini(path * 4 + quadrant, 23)] | (path << 3)
	o.timer1 = t
	if (t & 0x38) == 0:
		var yt := o.y_tile() + (0 if o.y_sub() < 0x10 else 1)
		o.y = ((yt & 0xFF) << 8) | o.y_sub()
	elif (t & 0x38) == 0x08:
		o.timer1 = (t | (o.vy & 0xFF)) & 0x88
	o.status = ST_TUBE
	_tube_step(o)


## $FD6D. One of eight steps through a tube tile.
func _tube_step(o: GimmickBody) -> void:
	var t := o.timer1
	var xs := 0
	var ys := 0
	if (t & 0x80) != 0:
		xs = GimmickTables.TUBE_X_REV[mini(t & 0x3F, 47)]
		ys = GimmickTables.TUBE_Y_REV[mini(t & 0x3F, 47)]
	else:
		xs = GimmickTables.TUBE_X_FWD[mini(t, 47)]
		ys = GimmickTables.TUBE_Y_FWD[mini(t, 47)]
	var xt := o.x_tile()
	if (xs & 0x0F) != 0:
		xt = (xt + (1 if (xs & 0x0F) == 1 else -1)) & 0xFF
	o.x = (xt << 8) | (xs & 0xF0)
	var yt := o.y_tile()
	if (ys & 0x0F) != 0:
		yt = (yt + (1 if (ys & 0x0F) == 1 else -1)) & 0xFF
	o.y = (yt << 8) | (ys & 0xF0)
	if (t & 7) == 7:
		o.status = ST_ACTIVE
		var i := ((t >> 7) & 1) << 3 | ((t >> 5) & 1) << 2 | ((t >> 4) & 1) << 1 | ((t >> 3) & 1)
		o.vy = s8(GimmickTables.TUBE_EXIT_VY[i])
		o.vx = s8(GimmickTables.TUBE_EXIT_VX[i])
		o.timer1 = 0
	else:
		o.timer1 = t + 1
