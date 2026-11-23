extends Node3D
## Movement lab: the player fighter alone in the dojo, a follow camera and a small
## readout, so dodges and footwork can be tuned without an opponent in the way.
## Everything is built in code so the prototype reads as plain scripts.

const InputSetup = preload("res://scripts/input_setup.gd")
const PlayerScript = preload("res://scripts/player.gd")
const Dojo = preload("res://scripts/dojo.gd")
const FxScript = preload("res://scripts/fx.gd")

# Follow camera: fixed yaw (always looking the same way), so "up on the stick"
# always means the same direction on screen and dodges read clearly.
const CAM_OFFSET := Vector3(0.0, 2.4, 4.8)
const CAM_FOLLOW := 6.0        # higher = tighter follow
const CAM_LEAD := 0.35         # seconds of velocity the camera looks ahead by

var player: Node3D
var camera: Camera3D
var fx: Node3D

var base_time_scale := 1.0
var cam_shake := 0.0
var _shake_t := 0.0
var cam_look := Vector3(0, 0.95, 0)

var readout: Label
var stats_label: Label
var feedback_label: Label
var hint_label: Label
var mode_label: Label
var iframe_lamp: Panel
var iframe_style: StyleBoxFlat
var feedback_time := 0.0


func _ready() -> void:
	InputSetup.setup()
	_build_world()
	_build_actors()
	_build_camera()
	_build_hud()
	Input.joy_connection_changed.connect(func(_device: int, _connected: bool) -> void: _update_hint())
	_update_hint()


func _process(delta: float) -> void:
	if Input.is_action_just_pressed("reset"):
		player.reset()
		_show_feedback("RESET")
	if Input.is_action_just_pressed("slowmo"):
		base_time_scale = 0.5 if base_time_scale == 1.0 else 1.0
		Engine.time_scale = base_time_scale
		mode_label.text = "SLOW-MO 50%" if base_time_scale < 1.0 else ""

	_update_camera(delta)
	_refresh_readout()

	feedback_time -= delta
	feedback_label.modulate.a = clampf(feedback_time / 0.3, 0.0, 1.0)
	var pop := 1.0 + maxf(0.0, feedback_time - 0.45) * 1.2
	feedback_label.scale = Vector2(pop, pop)


# ---------------------------------------------------------------- world

func _build_world() -> void:
	Dojo.build(self)
	fx = FxScript.new()
	add_child(fx)


func _build_actors() -> void:
	player = PlayerScript.new()
	player.fx = fx
	add_child(player)
	player.shake.connect(func(amount: float) -> void: cam_shake = maxf(cam_shake, amount))
	player.dodged.connect(func(kind: String) -> void: _show_feedback(kind))


func _build_camera() -> void:
	camera = Camera3D.new()
	camera.fov = 60.0
	add_child(camera)
	camera.position = CAM_OFFSET
	camera.current = true
	camera.look_at(cam_look, Vector3.UP)
	player.camera = camera


func _update_camera(delta: float) -> void:
	var pp: Vector3 = player.global_position
	var vel: Vector3 = player.move_vel
	var focus := Vector3(pp.x, 0.0, pp.z) + Vector3(vel.x, 0.0, vel.z) * CAM_LEAD
	var desired := focus + CAM_OFFSET
	camera.global_position = camera.global_position.lerp(desired, 1.0 - exp(-CAM_FOLLOW * delta))
	cam_look = cam_look.lerp(focus + Vector3.UP * 0.95, 1.0 - exp(-(CAM_FOLLOW + 2.0) * delta))
	camera.look_at(cam_look, Vector3.UP)
	# Smooth shake: summed sines at unrelated rates instead of per-frame random jitter.
	cam_shake = maxf(0.0, cam_shake - delta * 2.5)
	_shake_t += delta * 38.0
	var k := minf(1.0, cam_shake * 1.6)
	k *= k
	camera.h_offset = (sin(_shake_t * 1.7) + 0.5 * sin(_shake_t * 3.1 + 1.0)) * k * 0.09
	camera.v_offset = (sin(_shake_t * 2.3 + 2.0) + 0.5 * sin(_shake_t * 3.7)) * k * 0.09


# ---------------------------------------------------------------- HUD

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 28)
	layer.add_child(margin)

	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(col)

	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(top)

	# Left: what the fighter is doing right now.
	var panel := PanelContainer.new()
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color(0.04, 0.03, 0.03, 0.55)
	ps.set_corner_radius_all(6)
	ps.set_content_margin_all(12)
	panel.add_theme_stylebox_override("panel", ps)
	var left := VBoxContainer.new()
	panel.add_child(left)
	left.add_child(_label("MOVEMENT LAB", 18, Color.WHITE))
	readout = _label("", 15, Color(0.88, 0.88, 0.88))
	left.add_child(readout)
	var lamp_row := HBoxContainer.new()
	iframe_lamp = Panel.new()
	iframe_lamp.custom_minimum_size = Vector2(14, 14)
	iframe_style = StyleBoxFlat.new()
	iframe_style.set_corner_radius_all(7)
	iframe_style.bg_color = Color(0.2, 0.2, 0.22)
	iframe_lamp.add_theme_stylebox_override("panel", iframe_style)
	lamp_row.add_child(iframe_lamp)
	lamp_row.add_child(_label(" invulnerable (dodge i-frames)", 14, Color(0.75, 0.75, 0.78)))
	left.add_child(lamp_row)
	top.add_child(panel)

	top.add_child(_spacer(true))
	var mid := VBoxContainer.new()
	stats_label = _label("", 16, Color(0.9, 0.9, 0.9))
	stats_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mid.add_child(stats_label)
	mode_label = _label("", 16, Color(0.5, 0.9, 1.0))
	mode_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mid.add_child(mode_label)
	top.add_child(mid)
	top.add_child(_spacer(true))

	col.add_child(_spacer(false, 1.0))
	feedback_label = _label("", 40, Color(0.75, 0.88, 1.0))
	feedback_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	feedback_label.add_theme_constant_override("outline_size", 10)
	feedback_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	col.add_child(feedback_label)
	col.add_child(_spacer(false, 1.6))

	hint_label = _label("", 16, Color(0.85, 0.85, 0.85))
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	col.add_child(hint_label)


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _spacer(horizontal: bool, ratio: float = 1.0) -> Control:
	var c := Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if horizontal:
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	else:
		c.size_flags_vertical = Control.SIZE_EXPAND_FILL
		c.size_flags_stretch_ratio = ratio
	return c


func _refresh_readout() -> void:
	var speed: float = Vector3(player.move_vel.x, 0.0, player.move_vel.z).length()
	var st: String = player.state_name()
	if st == "IDLE" and speed > 0.3:
		st = "MOVE"
	readout.text = "State   %s\nSpeed   %.1f m/s" % [st, speed]
	iframe_style.bg_color = Color(0.35, 0.65, 1.0) if player.is_invulnerable() else Color(0.2, 0.2, 0.22)
	var s: Dictionary = player.stats
	stats_label.text = "Dodges %d   (sidestep %d   backstep %d   slip %d)   Hops %d   Distance %.0f m" % [
		s["dodges"], s["sidesteps"], s["backsteps"], s["slips"], s["hops"], s["distance"]]


func _show_feedback(text: String) -> void:
	feedback_label.text = text
	feedback_label.pivot_offset = feedback_label.size * 0.5
	feedback_time = 0.6


func _update_hint() -> void:
	if Input.get_connected_joypads().size() > 0:
		hint_label.text = "Left stick move   |   Right stick FLICK to dodge   |   RB/R1 dodge (left-stick direction)   |   LB/L1 hold guard   |   B/Circle duck   |   A/Cross hop   |   X/Square jab   |   Start reset   |   Back/Select slow-mo"
	else:
		hint_label.text = "WASD move   |   Arrow keys flick-dodge   |   Shift dodge (+WASD)   |   K or Right-click guard   |   C or Ctrl duck   |   Space hop   |   J or Left-click jab   |   R reset   |   T slow-mo   (plug in a controller any time)"
