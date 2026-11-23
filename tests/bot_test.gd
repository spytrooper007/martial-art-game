extends SceneTree
## Headless smoke test: drives the player with scripted input and prints movement stats.
## Run: godot --headless --path . --fixed-fps 60 -s tests/bot_test.gd -- <mode>
## Modes: walk (circles the room), dodge (dodge button in rotating directions),
##        flick (right-stick flicks in rotating directions), mixed (everything), idle
## Exits with code 1 if the fighter leaves the arena or a dodge doesn't move it.

var main: Node
var frames := 0
var mode := "mixed"
var released := {}
var failures := []
const DIRS := ["left", "right", "up", "down"]


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		mode = args[0]
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)


func _press(a: String, hold: int = 6) -> void:
	Input.action_press(a)
	released[a] = frames + hold


func _process(_delta: float) -> bool:
	frames += 1
	for a in released.keys():
		if frames >= released[a]:
			Input.action_release(a)
			released.erase(a)
	var p = main.player
	var beat := frames % 40
	var step := frames / 40
	match mode:
		"walk":
			# Change stick direction every 40 frames.
			for d in DIRS:
				Input.action_release("move_" + d)
			Input.action_press("move_" + DIRS[step % 4])
		"dodge":
			if beat == 0:
				_check_dodge(p, func() -> void:
					_press("move_" + DIRS[step % 4], 4)
					_press("dodge"))
		"flick":
			if beat == 0:
				_check_dodge(p, func() -> void: _press("flick_" + DIRS[step % 4], 4))
		"mixed":
			Input.action_press("move_" + DIRS[(step / 3) % 4])
			if beat == 0:
				_press(["dodge", "jump", "strike", "flick_left", "flick_right", "duck"][step % 6], 8)

	if _flat(p.global_position).length() > p.ARENA_RADIUS + 0.01:
		failures.append("left the arena at frame %d" % frames)
	if frames >= 60 * 30:
		print("MODE=%s stats=%s end_pos=%s" % [mode, p.stats, p.global_position.snapped(Vector3.ONE * 0.01)])
		if not failures.is_empty():
			print("FAIL: ", failures.slice(0, 5))
			quit(1)
		return true
	return false


var _pending_check := {}

## Fire a dodge and, 30 frames later, confirm the fighter actually travelled.
func _check_dodge(p, fire: Callable) -> void:
	if not _pending_check.is_empty():
		var moved: float = _flat(p.global_position - _pending_check["from"]).length()
		var at_wall: bool = _flat(p.global_position).length() > p.ARENA_RADIUS - 0.05
		if moved < 0.8 and not at_wall:
			failures.append("dodge at frame %d moved only %.2f m" % [_pending_check["frame"], moved])
	_pending_check = {"from": p.global_position, "frame": frames}
	fire.call()


func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)
