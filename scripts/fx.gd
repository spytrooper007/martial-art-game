extends Node3D
## One-shot combat effects: spark bursts, shockwave rings, glow pops, dust and a
## pooled flash light. Purely visual: nothing here touches gameplay timing.

const CYAN := Color(0.45, 0.95, 1.0)
const GOLD := Color(1.0, 0.78, 0.25)
const RED := Color(1.0, 0.28, 0.18)
const ORANGE := Color(1.0, 0.55, 0.2)
const GREEN := Color(0.45, 1.0, 0.55)
const GREY := Color(0.8, 0.82, 0.88)

var _spark_mesh: BoxMesh
var _spark_mat: StandardMaterial3D
var _dust_mesh: SphereMesh
var _dust_mat: StandardMaterial3D
var _billboard_mat: StandardMaterial3D
var _floor_mat: StandardMaterial3D
var _ring_tex: GradientTexture2D
var _glow_tex: GradientTexture2D
var _shrink: Curve
var _light: OmniLight3D
var _light_energy := 0.0
var _light_decay := 1.0


func _ready() -> void:
	_spark_mesh = BoxMesh.new()
	_spark_mesh.size = Vector3(0.016, 0.14, 0.016)
	_spark_mat = StandardMaterial3D.new()
	_spark_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_spark_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_spark_mat.vertex_color_use_as_albedo = true
	_spark_mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	_dust_mesh = SphereMesh.new()
	_dust_mesh.radius = 0.06
	_dust_mesh.height = 0.12
	_dust_mesh.radial_segments = 8
	_dust_mesh.rings = 4
	_dust_mat = StandardMaterial3D.new()
	_dust_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_dust_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_dust_mat.vertex_color_use_as_albedo = true

	_ring_tex = _radial([[0.0, Color(1, 1, 1, 0)], [0.62, Color(1, 1, 1, 0)], [0.82, Color(1, 1, 1, 1)], [0.9, Color(1, 1, 1, 0.6)], [1.0, Color(1, 1, 1, 0)]])
	_glow_tex = _radial([[0.0, Color(1, 1, 1, 1)], [0.18, Color(1, 1, 1, 0.85)], [0.45, Color(1, 1, 1, 0.25)], [1.0, Color(1, 1, 1, 0)]])

	_billboard_mat = StandardMaterial3D.new()
	_billboard_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_billboard_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_billboard_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_billboard_mat.billboard_keep_scale = true
	_billboard_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_billboard_mat.albedo_texture = _ring_tex

	_floor_mat = StandardMaterial3D.new()
	_floor_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_floor_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_floor_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_floor_mat.albedo_texture = _ring_tex

	_shrink = Curve.new()
	_shrink.add_point(Vector2(0.0, 1.0))
	_shrink.add_point(Vector2(1.0, 0.0))

	_light = OmniLight3D.new()
	_light.omni_range = 4.5
	_light.light_energy = 0.0
	_light.shadow_enabled = false
	add_child(_light)

	# Fire every effect once, out of sight under the floor, so their shaders compile
	# during loading instead of hitching the first parry.
	var hidden := Vector3(0, -0.6, 0)
	sparks(hidden, CYAN, 2, 1.0)
	dust(hidden, 2)
	ring(hidden, CYAN, 0.5, 0.05)
	glow(hidden, CYAN, 0.3, 0.05)
	floor_ring(hidden, GOLD, 0.5, 0.05)


func _process(delta: float) -> void:
	if _light_energy > 0.0:
		_light_energy = maxf(0.0, _light_energy - _light_decay * delta)
		_light.light_energy = _light_energy


## Named effect bundles, so every event stays proportional.
func burst(kind: String, pos: Vector3) -> void:
	match kind:
		"parry":
			sparks(pos, CYAN, 30, 6.0)
			ring(pos, CYAN, 1.5, 0.22)
			glow(pos, Color(0.7, 1.0, 1.0), 0.9, 0.12)
			flash_light(pos, CYAN, 5.0, 0.25)
		"block":
			sparks(pos, GREY, 10, 3.2)
			glow(pos, GREY, 0.45, 0.08)
		"hit":
			sparks(pos, ORANGE, 18, 4.5)
			ring(pos, RED, 0.9, 0.16)
			glow(pos, RED, 0.75, 0.1)
			flash_light(pos, RED, 3.0, 0.2)
		"counter":
			sparks(pos, GOLD, 24, 5.5)
			ring(pos, GOLD, 1.2, 0.2)
			glow(pos, Color(1.0, 0.9, 0.6), 0.8, 0.1)
			flash_light(pos, GOLD, 4.0, 0.22)
		"guard_hit":
			sparks(pos, GREY, 6, 2.5)
			glow(pos, GREY, 0.35, 0.07)
		"perfect":
			floor_ring(Vector3(pos.x, 0.035, pos.z), GOLD * 0.7, 3.0, 0.4)
			ring(pos, GOLD * 0.45, 1.3, 0.25)
			flash_light(pos, GOLD, 2.5, 0.35)
		"guard_break":
			sparks(pos, RED, 28, 5.0)
			ring(pos, RED, 2.0, 0.3)
			floor_ring(Vector3(pos.x, 0.035, pos.z), RED, 2.6, 0.35)
			flash_light(pos, RED, 5.0, 0.3)
		"break":
			sparks(pos, GREEN, 40, 6.5)
			ring(pos, GREEN, 2.4, 0.35)
			floor_ring(Vector3(pos.x, 0.035, pos.z), GREEN, 4.0, 0.5)
			flash_light(pos, GREEN, 6.0, 0.45)
		"glint":
			glow(pos, Color(1, 1, 1), 0.5, 0.1)


func sparks(pos: Vector3, color: Color, count: int, speed: float) -> void:
	var p := CPUParticles3D.new()
	p.mesh = _spark_mesh
	p.material_override = _spark_mat
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = count
	p.lifetime = 0.38
	p.local_coords = false
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = speed * 0.45
	p.initial_velocity_max = speed
	p.gravity = Vector3(0, -9.0, 0)
	p.damping_min = 3.0
	p.damping_max = 6.0
	p.particle_flag_align_y = true
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.3
	p.scale_amount_curve = _shrink
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1).lerp(color, 0.35) * 1.6)
	ramp.set_color(1, Color.BLACK)
	ramp.add_point(0.35, color)
	p.color_ramp = ramp
	_spawn(p, pos, 0.6)
	p.emitting = true


func dust(pos: Vector3, count: int = 8) -> void:
	var p := CPUParticles3D.new()
	p.mesh = _dust_mesh
	p.material_override = _dust_mat
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.one_shot = true
	p.explosiveness = 0.9
	p.amount = count
	p.lifetime = 0.5
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.12
	p.direction = Vector3.UP
	p.spread = 80.0
	p.flatness = 0.6
	p.initial_velocity_min = 0.4
	p.initial_velocity_max = 1.1
	p.gravity = Vector3(0, 0.3, 0)
	p.damping_min = 1.5
	p.damping_max = 2.5
	p.scale_amount_min = 0.7
	p.scale_amount_max = 1.6
	var grow := Curve.new()
	grow.add_point(Vector2(0.0, 0.5))
	grow.add_point(Vector2(1.0, 1.4))
	p.scale_amount_curve = grow
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.75, 0.68, 0.6, 0.45))
	ramp.set_color(1, Color(0.75, 0.68, 0.6, 0.0))
	p.color_ramp = ramp
	_spawn(p, pos, 0.8)
	p.emitting = true


## Camera-facing expanding shockwave ring.
func ring(pos: Vector3, color: Color, size: float, life: float) -> void:
	_expanding(pos, color, size, life, _billboard_mat, _ring_tex, false)


## Soft camera-facing glow pop.
func glow(pos: Vector3, color: Color, size: float, life: float) -> void:
	_expanding(pos, color, size, life, _billboard_mat, _glow_tex, false)


## Flat shockwave along the floor.
func floor_ring(pos: Vector3, color: Color, size: float, life: float) -> void:
	_expanding(pos, color, size, life, _floor_mat, _ring_tex, true)


func flash_light(pos: Vector3, color: Color, energy: float, life: float) -> void:
	_light.global_position = pos
	_light.light_color = color
	_light_energy = maxf(_light_energy, energy)
	_light_decay = energy / maxf(life, 0.01)
	_light.light_energy = _light_energy


func _expanding(pos: Vector3, color: Color, size: float, life: float, proto: StandardMaterial3D, tex: Texture2D, flat: bool) -> void:
	var mi := MeshInstance3D.new()
	var mesh: Mesh
	if flat:
		var pm := PlaneMesh.new()
		pm.size = Vector2.ONE
		mesh = pm
	else:
		var qm := QuadMesh.new()
		qm.size = Vector2.ONE
		mesh = qm
	mi.mesh = mesh
	var mat: StandardMaterial3D = proto.duplicate()
	mat.albedo_texture = tex
	mat.albedo_color = color * 1.4
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_spawn(mi, pos, -1.0)
	mi.scale = Vector3.ONE * size * 0.25
	var tw := mi.create_tween().set_parallel(true)
	tw.tween_property(mi, "scale", Vector3.ONE * size, life).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "albedo_color", Color.BLACK, life).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(mi.queue_free)


func _spawn(n: Node3D, pos: Vector3, free_after: float) -> void:
	add_child(n)
	n.global_position = pos
	if free_after > 0.0:
		get_tree().create_timer(free_after).timeout.connect(n.queue_free)


func _radial(stops: Array) -> GradientTexture2D:
	var g := Gradient.new()
	var offs := PackedFloat32Array()
	var cols := PackedColorArray()
	for st in stops:
		offs.append(st[0])
		var c: Color = st[1]
		# Premultiplied (fades to black, alpha 1) so additive blending needs no alpha pass.
		cols.append(Color(c.r * c.a, c.g * c.a, c.b * c.a, 1.0))
	g.offsets = offs
	g.colors = cols
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 128
	t.height = 128
	return t
