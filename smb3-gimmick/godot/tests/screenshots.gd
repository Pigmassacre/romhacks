extends SceneTree
## Saves pictures of the running game to the folder given after "--".
##
##   godot --path godot -s tests/screenshots.gd -- /tmp/shots

var main: Node
var frame := 0
var out := ""


func _initialize() -> void:
	out = OS.get_cmdline_user_args()[0]
	main = load("res://game/main.tscn").instantiate()
	root.add_child(main)


func _process(_delta: float) -> bool:
	frame += 1
	var sim: GimmickSim = main.sim
	if frame == 30:
		Input.action_press("gim_star")
	if frame == 80:
		_shot("charge")
		Input.action_release("gim_star")
	if frame == 88:
		_shot("throw")
		main.sim.spawn_player(0x1380, 0x0900)
	if frame == 100:
		_shot("slope")
		main.sim.spawn_player(0x2C80, 0x0A00)
		main.sim.camera_x = 0x2480
	if frame == 110:
		_shot("conveyor")
		main.sim.spawn_player(0x4D80, 0x0A00)
		main.sim.camera_x = 0x4580
		Input.action_press("gim_right")
	if frame == 150:
		_shot("hazards")
		Input.action_release("gim_right")
		main.sim.spawn_player(0x5E80, 0x1900)
		main.sim.camera_x = 0x5680
		main._spawn_screen_objects()
	if frame == 160:
		_shot("cave")
		return true
	return false


func _shot(name: String) -> void:
	root.get_texture().get_image().save_png(out.path_join(name + ".png"))
