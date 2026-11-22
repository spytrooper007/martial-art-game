extends Node3D
## Builds the dojo, the two fighters, the lock-on camera and the HUD in code,
## so the whole prototype is readable as plain scripts.

const InputSetup = preload("res://scripts/input_setup.gd")
const PlayerScript = preload("res://scripts/player.gd")
const DummyScript = preload("res://scripts/dummy.gd")

var player: Node3D
var dummy: Node3D
var camera: Camera3D

var base_time_scale := 1.0
var cam_shake := 0.0
var _hitstop_token := 0

var hp_bar: ProgressBar
var struct_bar: ProgressBar
var dummy_bar: ProgressBar
var feedback_label: Label
var sub_label: Label
var stats_label: Label
var hint_label: Label
var mode_label: Label
var feedback_time := 0.0


func _ready() -> void:
	InputSetup.setup()
	_build_world()
	_build_actors()
	_build_camera()
	_build_hud()
	Input.joy_connection_changed.connect(func(_device: int, _connected: bool) -> void: _update_hint())
	_update_hint()
	_refresh_bars()


func _process(delta: float) -> void:
	if Input.is_action_just_pressed("reset"):
		player.reset()
		dummy.reset()
		_show_feedback("RESET", Color.WHITE, "")
	if Input.is_action_just_pressed("slowmo"):
		base_time_scale = 0.5 if base_time_scale == 1.0 else 1.0
		Engine.time_scale = base_time_scale
		mode_label.text = "SLOW-MO TRAINING 50%" if base_time_scale < 1.0 else ""

	_update_camera(delta)
	_refresh_bars()

	feedback_time -= delta
	var a := clampf(feedback_time / 0.4, 0.0, 1.0)
	feedback_label.modulate.a = a
	sub_label.modulate.a = clampf(feedback_time / 0.6, 0.0, 1.0)
	var pop := 1.0 + maxf(0.0, feedback_time - 0.9) * 1.5
	feedback_label.scale = Vector2(pop, pop)


# ---------------------------------------------------------------- world

func _build_world() -> void:
	var env := Environment.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.12, 0.14, 0.22)
	sky_mat.sky_horizon_color = Color(0.55, 0.42, 0.38)
	sky_mat.ground_horizon_color = Color(0.3, 0.25, 0.24)
	sky_mat.ground_bottom_color = Color(0.08, 0.08, 0.1)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_bloom = 0.1
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 35, 0)
	sun.light_energy = 1.1
	sun.light_color = Color(1.0, 0.92, 0.82)
	sun.shadow_enabled = true
	add_child(sun)

	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(60, 60)
	add_child(_mesh(floor_mesh, Color(0.16, 0.13, 0.12), Vector3.ZERO))

	var mat := CylinderMesh.new()
	mat.top_radius = 7.8
	mat.bottom_radius = 7.8
	mat.height = 0.02
	mat.radial_segments = 64
	add_child(_mesh(mat, Color(0.42, 0.33, 0.24), Vector3(0, 0.01, 0)))

	var ring := TorusMesh.new()
	ring.inner_radius = 7.55
	ring.outer_radius = 7.7
	ring.rings = 96
	var ring_mi := _mesh(ring, Color(0.75, 0.2, 0.15), Vector3(0, 0.02, 0))
	ring_mi.scale = Vector3(1, 0.15, 1)
	add_child(ring_mi)

	# Pillars so you can read motion and sidesteps against the background.
	for i in 10:
		var ang := TAU * float(i) / 10.0
		var pillar := BoxMesh.new()
		pillar.size = Vector3(0.6, 4.0, 0.6)
		add_child(_mesh(pillar, Color(0.35, 0.12, 0.1), Vector3(cos(ang) * 11.0, 2.0, sin(ang) * 11.0)))


func _mesh(m: Mesh, color: Color, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	var sm := StandardMaterial3D.new()
	sm.albedo_color = color
	sm.roughness = 0.9
	mi.material_override = sm
	mi.position = pos
	return mi


func _build_actors() -> void:
	dummy = DummyScript.new()
	player = PlayerScript.new()
	player.dummy = dummy
	dummy.player = player
	add_child(dummy)
	add_child(player)
	player.position = Vector3(0, 0, 1.7)

	player.feedback.connect(_show_feedback)
	dummy.feedback.connect(_show_feedback)
	player.hitstop.connect(_hitstop)
	player.shake.connect(func(amount: float) -> void: cam_shake = maxf(cam_shake, amount))
	player.stats_changed.connect(_refresh_stats)


func _build_camera() -> void:
	camera = Camera3D.new()
	camera.fov = 62.0
	add_child(camera)
	camera.position = Vector3(0.9, 1.9, 5.0)
	camera.current = true


func _update_camera(delta: float) -> void:
	var pp := player.global_position
	var dp := dummy.global_position
	var back := Vector3(pp.x - dp.x, 0.0, pp.z - dp.z)
	back = back.normalized() if back.length() > 0.05 else Vector3.BACK
	var right := (-back).cross(Vector3.UP)
	var desired := pp + back * 3.3 + Vector3.UP * 1.85 + right * 0.85
	camera.global_position = camera.global_position.lerp(desired, 1.0 - exp(-7.0 * delta))
	camera.look_at(pp.lerp(dp, 0.55) + Vector3.UP * 1.05, Vector3.UP)
	cam_shake = maxf(0.0, cam_shake - delta * 2.5)
	camera.h_offset = randf_range(-1.0, 1.0) * cam_shake * 0.12
	camera.v_offset = randf_range(-1.0, 1.0) * cam_shake * 0.12


func _hitstop(duration: float) -> void:
	_hitstop_token += 1
	var token := _hitstop_token
	Engine.time_scale = 0.05
	await get_tree().create_timer(duration, true, false, true).timeout
	if token == _hitstop_token:
		Engine.time_scale = base_time_scale


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

	var left := VBoxContainer.new()
	left.add_child(_label("YOU", 18, Color.WHITE))
	hp_bar = _bar(Color(0.85, 0.2, 0.2))
	left.add_child(hp_bar)
	left.add_child(_label("Structure (fills when you block or get hit)", 13, Color(0.8, 0.8, 0.8)))
	struct_bar = _bar(Color(1.0, 0.6, 0.15))
	left.add_child(struct_bar)
	top.add_child(left)

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

	var right := VBoxContainer.new()
	var dl := _label("TRAINING DUMMY", 18, Color.WHITE)
	dl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.add_child(dl)
	var dsl := _label("Structure (parry and counter to break it)", 13, Color(0.8, 0.8, 0.8))
	dsl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.add_child(dsl)
	dummy_bar = _bar(Color(0.4, 1.0, 0.5))
	right.add_child(dummy_bar)
	top.add_child(right)

	col.add_child(_spacer(false, 1.0))
	feedback_label = _label("", 64, Color.WHITE)
	feedback_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	feedback_label.add_theme_constant_override("outline_size", 12)
	feedback_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	col.add_child(feedback_label)
	sub_label = _label("", 20, Color(0.92, 0.92, 0.92))
	sub_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub_label.add_theme_constant_override("outline_size", 6)
	sub_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	col.add_child(sub_label)
	col.add_child(_spacer(false, 1.4))

	hint_label = _label("", 16, Color(0.85, 0.85, 0.85))
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	col.add_child(hint_label)
	_refresh_stats()


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


func _bar(color: Color) -> ProgressBar:
	var b := ProgressBar.new()
	b.custom_minimum_size = Vector2(340, 16)
	b.max_value = 100.0
	b.show_percentage = false
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.55)
	b.add_theme_stylebox_override("fill", fill)
	b.add_theme_stylebox_override("background", bg)
	return b


func _refresh_bars() -> void:
	hp_bar.value = player.hp
	struct_bar.value = player.structure
	dummy_bar.value = dummy.structure


func _refresh_stats() -> void:
	if stats_label == null:
		return
	var s: Dictionary = player.stats
	stats_label.text = "Parries %d   Perfect avoids %d   Avoids %d   Counters %d   Hits taken %d" % [
		s["parries"], s["perfect"], s["avoids"], s["counters"], s["hits"]]


func _show_feedback(text: String, color: Color, sub: String) -> void:
	if text != "":
		feedback_label.text = text
		feedback_label.add_theme_color_override("font_color", color)
		feedback_label.pivot_offset = feedback_label.size * 0.5
		feedback_time = 1.1
	elif feedback_time <= 0.0:
		feedback_label.text = ""
		feedback_time = 1.1
	sub_label.text = sub


func _update_hint() -> void:
	if Input.get_connected_joypads().size() > 0:
		hint_label.text = "Left stick move   |   LB/L1 hold block, tap on impact to PARRY   |   RB/R1 dodge (+stick to sidestep)   |   B/Circle duck   |   A/Cross hop   |   X/Square counter   |   Start reset   |   Back/Select slow-mo"
	else:
		hint_label.text = "WASD move   |   K or Right-click hold block, tap on impact to PARRY   |   Shift or L dodge (+A/D to sidestep)   |   C or Ctrl duck   |   Space hop   |   J or Left-click counter   |   R reset   |   T slow-mo   (plug in a controller any time)"
