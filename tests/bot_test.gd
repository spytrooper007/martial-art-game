extends SceneTree
## Headless smoke test: plays the prototype with a scripted "bot" and prints stats.
## Run: godot --headless --path . --fixed-fps 60 -s tests/bot_test.gd -- <mode>
## Modes: perfect (reads every telegraph), hold_block, idle, dodge

var main: Node
var frames := 0
var mode := "perfect"
var released := {}
var handled_attack := -1.0

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		mode = args[0]
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)

func _press(a: String) -> void:
	Input.action_press(a)
	released[a] = frames + 6

func _process(_delta: float) -> bool:
	frames += 1
	for a in released.keys():
		if frames >= released[a]:
			Input.action_release(a)
			released.erase(a)
	var d = main.dummy
	var p = main.player
	if mode == "hold_block":
		Input.action_press("block")
	elif d.state == d.D.WINDUP and d.clock - handled_attack > 0.2:
		var left: float = d.current_windup - d.state_time
		if left <= 0.07:
			handled_attack = d.clock
			if mode == "perfect":
				if not d.current["unblockable"]:
					_press("block")
				elif d.current["kind"] == "high":
					_press("duck")
				else:
					_press("jump")
			elif mode == "dodge":
				Input.action_press("move_left")
				_press("dodge")
				released["move_left"] = frames + 4
	if mode == "perfect" and d.is_open() and frames % 12 == 0:
		_press("strike")
	if frames >= 60 * 60:
		print("MODE=%s stats=%s hp=%.0f structure=%.0f dummy_structure=%.0f dummy_speed=%.2f" % [mode, p.stats, p.hp, p.structure, d.structure, d.speed_mult])
		return true
	return false
