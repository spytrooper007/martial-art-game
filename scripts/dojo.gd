extends RefCounted
## Builds the dojo set in code: plank floor, canvas fight mat, shoji walls, wooden
## pillars and beams, paper lanterns, hanging scrolls, and the lighting / environment.
## Everything is primitives plus small procedural shaders, so there are no asset files.
## Works on the Compatibility renderer (no SSAO / SDFGI needed).

const ROOM := 14.0      # half-width of the square room
const HEIGHT := 7.0

const FLOOR_SHADER := """
shader_type spatial;
uniform vec3 wood_a : source_color = vec3(0.42, 0.27, 0.16);
uniform vec3 wood_b : source_color = vec3(0.27, 0.16, 0.10);
varying vec3 wpos;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	float pw = 0.34;
	float row = floor(wpos.z / pw);
	float off = hash(vec2(row, 7.0)) * 3.0;
	float pl = 4.2;
	float col = floor((wpos.x + off) / pl);
	float id = hash(vec2(row, col));
	vec2 local = vec2(fract((wpos.x + off) / pl), fract(wpos.z / pw));
	float grain = noise(vec2(wpos.x * 1.2 + id * 13.0, wpos.z * 26.0)) * 0.6 + noise(vec2(wpos.x * 0.35 + id * 3.0, wpos.z * 70.0)) * 0.4;
	vec3 c = mix(wood_b, wood_a, 0.3 + 0.7 * id);
	c *= 0.8 + 0.35 * grain;
	float gy = fwidth(local.y) + 0.012;
	float gx = fwidth(local.x) + 0.002;
	float gap = smoothstep(0.0, gy, local.y) * smoothstep(0.0, gy, 1.0 - local.y);
	gap *= smoothstep(0.0, gx, local.x) * smoothstep(0.0, gx, 1.0 - local.x);
	// Fade the seams out with distance so far planks don't shimmer.
	float far_fade = clamp(1.0 - fwidth(wpos.z) * 9.0, 0.0, 1.0);
	c *= mix(1.0, mix(0.45, 1.0, gap), far_fade);
	ALBEDO = c;
	ROUGHNESS = mix(0.5, 0.32, id);
	SPECULAR = 0.45;
}
"""

const MAT_SHADER := """
shader_type spatial;
uniform vec3 canvas : source_color = vec3(0.17, 0.21, 0.30);
uniform vec3 edge : source_color = vec3(0.09, 0.11, 0.16);
uniform vec3 line : source_color = vec3(0.78, 0.14, 0.10);
uniform float radius = 7.8;
varying vec3 wpos;
float band(float r, float a, float b) {
	float w = fwidth(r);
	return smoothstep(a - w, a + w, r) * (1.0 - smoothstep(b - w, b + w, r));
}
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	float r = length(wpos.xz);
	float weave = sin(wpos.x * 90.0) * sin(wpos.z * 90.0);
	float fade = clamp(1.0 - fwidth(wpos.x * 90.0) * 1.5, 0.0, 1.0);
	vec3 c = canvas * (0.975 + 0.025 * weave * fade);
	c *= 0.9 + 0.1 * smoothstep(7.0, 0.0, r);
	c = mix(c, edge, smoothstep(7.25, 7.32, r));
	c = mix(c, line, band(r, 7.42, 7.6));
	c = mix(c, vec3(0.82, 0.8, 0.76), band(r, 1.0, 1.05) * 0.45);
	c = mix(c, vec3(0.82, 0.8, 0.76), band(r, 4.2, 4.24) * 0.18);
	ALBEDO = c;
	ROUGHNESS = 0.85;
	SPECULAR = 0.25;
}
"""

const SHOJI_SHADER := """
shader_type spatial;
uniform vec3 paper : source_color = vec3(0.95, 0.86, 0.7);
uniform vec3 frame : source_color = vec3(0.16, 0.1, 0.06);
uniform float glow = 0.32;
varying vec3 lpos;
float grid(float v, float cell, float half_w) {
	float d = abs(fract(v / cell + 0.5) - 0.5) * cell;
	float w = fwidth(v);
	return 1.0 - smoothstep(half_w - w, half_w + w, d);
}
void vertex() { lpos = VERTEX; }
void fragment() {
	float u = lpos.x;
	float v = lpos.y;
	float lattice = max(grid(u, 0.45, 0.018), grid(v, 0.55, 0.018));
	float panel = grid(u, 1.8, 0.05);
	float f = max(lattice, panel);
	float hot = 0.75 + 0.25 * sin(v * 0.8 + 1.0);
	ALBEDO = mix(paper, frame, f);
	EMISSION = paper * glow * hot * (1.0 - f);
	ROUGHNESS = 0.9;
}
"""

const SCROLL_SHADER := """
shader_type spatial;
render_mode cull_disabled;
uniform vec3 paper : source_color = vec3(0.9, 0.85, 0.74);
uniform vec3 ink : source_color = vec3(0.06, 0.05, 0.05);
uniform float aspect = 2.4;
void fragment() {
	vec2 p = (UV - vec2(0.5, 0.4)) * vec2(1.0, aspect);
	float r = length(p);
	float ang = atan(p.y, p.x);
	// Brush circle: thickness swells and tapers, with a gap like an enso.
	float t = fract((ang + 2.2) / 6.2831853);
	float thick = mix(0.02, 0.075, smoothstep(0.0, 0.35, t)) * (1.0 - smoothstep(0.82, 0.96, t));
	float ring = 1.0 - smoothstep(thick - 0.008, thick + 0.008, abs(r - 0.3));
	float dry = 0.8 + 0.2 * sin(ang * 37.0 + r * 90.0);
	vec3 c = mix(paper, ink, ring * dry);
	float edge = smoothstep(0.0, 0.04, UV.x) * smoothstep(0.0, 0.04, 1.0 - UV.x);
	ALBEDO = c * mix(0.75, 1.0, edge);
	ROUGHNESS = 0.95;
}
"""


static func build(parent: Node3D) -> void:
	_environment(parent)
	_lights(parent)

	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(ROOM * 2.0 + 2.0, ROOM * 2.0 + 2.0)
	parent.add_child(_shaded(floor_mesh, FLOOR_SHADER, Vector3.ZERO))

	var mat := CylinderMesh.new()
	mat.top_radius = 7.8
	mat.bottom_radius = 7.85
	mat.height = 0.04
	mat.radial_segments = 96
	parent.add_child(_shaded(mat, MAT_SHADER, Vector3(0, 0.0, 0)))

	var dark_wood := _std(Color(0.17, 0.1, 0.065), 0.6)
	var mid_wood := _std(Color(0.3, 0.19, 0.11), 0.55)

	# Four walls: wooden skirting, glowing shoji screens, plain upper wall.
	for i in 4:
		var yaw := PI * 0.5 * float(i)
		var basis := Basis(Vector3.UP, yaw)
		var inward := basis * Vector3(0, 0, 1)
		var at := -inward * ROOM

		var skirt := BoxMesh.new()
		skirt.size = Vector3(ROOM * 2.0, 1.0, 0.3)
		parent.add_child(_placed(skirt, mid_wood, at + Vector3.UP * 0.5, basis))

		var shoji := BoxMesh.new()
		shoji.size = Vector3(ROOM * 2.0, 3.6, 0.12)
		var sh := _shaded(shoji, SHOJI_SHADER, Vector3.ZERO)
		sh.transform = Transform3D(basis, at + Vector3.UP * 2.8 - inward * 0.05)
		parent.add_child(sh)

		var upper := BoxMesh.new()
		upper.size = Vector3(ROOM * 2.0, HEIGHT - 4.6, 0.3)
		parent.add_child(_placed(upper, _std(Color(0.55, 0.47, 0.38), 0.9), at + Vector3.UP * (4.6 + (HEIGHT - 4.6) * 0.5), basis))

		# Rails above and below the screens.
		for y in [1.0, 4.6]:
			var rail := BoxMesh.new()
			rail.size = Vector3(ROOM * 2.0, 0.16, 0.36)
			parent.add_child(_placed(rail, dark_wood, at + Vector3.UP * y, basis))

		# Pillars along the wall.
		for k in 7:
			var along := -ROOM + float(k) * (ROOM * 2.0 / 6.0)
			var pillar := BoxMesh.new()
			pillar.size = Vector3(0.36, HEIGHT, 0.36)
			var pos := at + basis * Vector3(along, 0, 0) + inward * 0.2 + Vector3.UP * HEIGHT * 0.5
			parent.add_child(_placed(pillar, dark_wood, pos, basis))

		# A hanging scroll in the middle of each wall.
		var backing := BoxMesh.new()
		backing.size = Vector3(1.25, 2.9, 0.04)
		parent.add_child(_placed(backing, _std(Color(0.35, 0.07, 0.06), 0.8), at + inward * 0.32 + Vector3.UP * 3.0, basis))
		var paper := QuadMesh.new()
		paper.size = Vector2(1.0, 2.4)
		var scroll := _shaded(paper, SCROLL_SHADER, Vector3.ZERO)
		scroll.transform = Transform3D(basis, at + inward * 0.345 + Vector3.UP * 3.05)
		parent.add_child(scroll)
		for y in [1.53, 4.47]:
			var rod := CylinderMesh.new()
			rod.top_radius = 0.03
			rod.bottom_radius = 0.03
			rod.height = 1.4
			var rb := basis * Basis(Vector3(0, 0, 1), PI * 0.5)
			parent.add_child(_placed(rod, dark_wood, at + inward * 0.36 + Vector3.UP * y, rb))

	# Ceiling and cross beams.
	var ceil_mesh := PlaneMesh.new()
	ceil_mesh.size = Vector2(ROOM * 2.0, ROOM * 2.0)
	ceil_mesh.flip_faces = true
	parent.add_child(_placed(ceil_mesh, _std(Color(0.2, 0.14, 0.1), 0.9), Vector3(0, HEIGHT, 0), Basis()))
	for k in 5:
		var z := -ROOM + float(k + 1) * (ROOM * 2.0 / 6.0)
		var beam := BoxMesh.new()
		beam.size = Vector3(ROOM * 2.0, 0.35, 0.3)
		parent.add_child(_placed(beam, dark_wood, Vector3(0, HEIGHT - 0.2, z), Basis()))

	# Paper lanterns with warm point lights.
	var paper_mat := _std(Color(1.0, 0.78, 0.5), 0.9)
	paper_mat.emission_enabled = true
	paper_mat.emission = Color(1.0, 0.62, 0.3)
	paper_mat.emission_energy_multiplier = 2.2
	for c in [Vector2(-9, -9), Vector2(9, -9), Vector2(-9, 9), Vector2(9, 9)]:
		var pos := Vector3(c.x, 4.3, c.y)
		var body := SphereMesh.new()
		body.radius = 0.38
		body.height = 0.95
		parent.add_child(_placed(body, paper_mat, pos, Basis()))
		for dy in [-0.5, 0.5]:
			var cap := CylinderMesh.new()
			cap.top_radius = 0.2
			cap.bottom_radius = 0.2
			cap.height = 0.08
			parent.add_child(_placed(cap, dark_wood, pos + Vector3.UP * dy, Basis()))
		var cord := CylinderMesh.new()
		cord.top_radius = 0.012
		cord.bottom_radius = 0.012
		cord.height = HEIGHT - pos.y - 0.5
		parent.add_child(_placed(cord, dark_wood, pos + Vector3.UP * (0.5 + cord.height * 0.5), Basis()))
		var lamp := OmniLight3D.new()
		lamp.light_color = Color(1.0, 0.7, 0.42)
		lamp.light_energy = 1.6
		lamp.omni_range = 11.0
		lamp.omni_attenuation = 1.4
		lamp.position = pos
		parent.add_child(lamp)


static func _environment(parent: Node3D) -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.03, 0.025, 0.025)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.55, 0.52)
	env.ambient_light_energy = 0.45
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.05
	env.tonemap_white = 6.0
	env.glow_enabled = true
	env.glow_intensity = 0.7
	env.glow_strength = 1.0
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.1
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.fog_enabled = true
	env.fog_light_color = Color(0.22, 0.16, 0.12)
	env.fog_density = 0.012
	env.fog_aerial_perspective = 0.0
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.08
	env.adjustment_saturation = 1.08
	var we := WorldEnvironment.new()
	we.environment = env
	parent.add_child(we)


static func _lights(parent: Node3D) -> void:
	# Warm key light from above, like light through a skylight.
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-58, 30, 0)
	key.light_energy = 1.15
	key.light_color = Color(1.0, 0.9, 0.78)
	key.shadow_enabled = true
	key.shadow_blur = 1.5
	key.directional_shadow_max_distance = 30.0
	key.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	parent.add_child(key)
	# Cool back light, no shadows: gives the fighters a rim so they separate from the room.
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-25, -150, 0)
	rim.light_energy = 0.55
	rim.light_color = Color(0.55, 0.68, 1.0)
	rim.shadow_enabled = false
	parent.add_child(rim)


static func _std(color: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	return m


static func _shaded(mesh: Mesh, code: String, pos: Vector3) -> MeshInstance3D:
	var sh := Shader.new()
	sh.code = code
	var sm := ShaderMaterial.new()
	sm.shader = sh
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = sm
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


static func _placed(mesh: Mesh, mat: Material, pos: Vector3, basis: Basis) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.transform = Transform3D(basis, pos)
	# Only the fighters cast shadows: set pieces would stripe the mat with beam shadows.
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi
