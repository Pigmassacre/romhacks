extends SceneTree
## Runs the real main scene for a while with random input, to catch script errors.
var main: Node
var n := 0
func _initialize() -> void:
	main = load("res://game/main.tscn").instantiate()
	root.add_child(main)
	seed(7)
func _process(_d: float) -> bool:
	n += 1
	if n % 20 == 0:
		for a in ["gim_left", "gim_right", "gim_jump", "gim_star"]:
			if randf() < 0.5: Input.action_press(a)
			else: Input.action_release(a)
	if n % 400 == 0:
		main.sim.spawn_player((randi_range(2, 108) << 8) | 0x80, 0x0500)
	return n > 6000
