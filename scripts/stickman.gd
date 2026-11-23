extends Node3D
## A fighter built from primitive meshes. Poses are joint positions; every joint is
## a damped spring toward the target pose, with procedural layers (walk, bounce,
## breathing) on top. Two-bone IK keeps limb lengths fixed in every pose, and the
## torso twists with the hands and feet, so poses read as a body, not a wireframe.
## Purely visual: nothing here affects gameplay timing.

const Poses = preload("res://scripts/poses.gd")
const JOINTS := ["hips", "chest", "head", "l_elbow", "l_hand", "r_elbow", "r_hand", "l_knee", "l_foot", "r_knee", "r_foot"]
const GROUPS := ["torso", "l_arm", "r_arm", "l_leg", "r_leg"]

# Fixed segment lengths (metres). Poses give hand / foot targets and elbow / knee hints.
const UPPER_ARM := 0.30
const FOREARM := 0.29
const THIGH := 0.50
const SHIN := 0.49
const SPINE := 0.47
const NECK := 0.25
const SHOULDER_HALF := 0.19
const HIP_HALF := 0.095

# [from, to, radius at from, radius at to, group]: tapered limb segments.
const LIMBS := [
	["l_shoulder", "l_elbow", 0.064, 0.05, "l_arm"],
	["l_elbow", "l_hand", 0.05, 0.04, "l_arm"],
	["r_shoulder", "r_elbow", 0.064, 0.05, "r_arm"],
	["r_elbow", "r_hand", 0.05, 0.04, "r_arm"],
	["l_hip", "l_knee", 0.088, 0.062, "l_leg"],
	["l_knee", "l_foot", 0.062, 0.045, "l_leg"],
	["r_hip", "r_knee", 0.088, 0.062, "r_leg"],
	["r_knee", "r_foot", 0.062, 0.045, "r_leg"],
	["chest", "head", 0.048, 0.042, "torso"],
]

# [joint, radius, group]: joint caps, in the darker joint tone.
const BALLS := [
	["l_shoulder", 0.07, "l_arm"], ["r_shoulder", 0.07, "r_arm"],
	["l_elbow", 0.052, "l_arm"], ["r_elbow", 0.052, "r_arm"],
	["l_knee", 0.066, "l_leg"], ["r_knee", 0.066, "r_leg"],
	["l_hand", 0.064, "l_arm"], ["r_hand", 0.064, "r_arm"],
]

## Colours: body, joint caps, belt, and an optional headband (alpha 0 = none).
var base_color := Color(0.93, 0.93, 0.96)
var joint_color := Color(0.8, 0.8, 0.84)
var belt_color := Color(0.08, 0.08, 0.09)
var band_color := Color(0, 0, 0, 0)
var blend_speed := 12.0
var bob_amount := 1.0

## Owner sets these every frame: local-space velocity (m/s) drives the walk cycle,
## locomotion_weight (0..1) fades the walk / fighter's bounce in and out.
var locomotion := Vector3.ZERO
var locomotion_weight := 1.0
## Spring damping. Below 1.0 gives a little overshoot and follow-through.
var damping_ratio := 0.72

# Per-joint stiffness multipliers: the head and hands trail the core slightly,
# which gives overlapping motion instead of everything snapping in lockstep.
const JOINT_STIFFNESS := {
	"hips": 1.0, "chest": 0.9, "head": 0.72,
	"l_elbow": 0.85, "l_hand": 0.78, "r_elbow": 0.85, "r_hand": 0.78,
	"l_knee": 0.95, "l_foot": 1.0, "r_knee": 0.95, "r_foot": 1.0,
}

var current := {}
var target := {}
var solved := {}       # joint -> local position after IK (what is drawn)
var _vel := {}
var _loco_w := 1.0
var _phase := 0.0
var _mats := {}        # group -> [body material, joint material]
var _accent_mats := []
var _glow := {}        # group -> [Color, energy]
var _flash_color := Color.WHITE
var _flash_left := 0.0
var _flash_total := 0.1
var _limbs := []       # [MeshInstance3D, from, to]
var _balls := []       # [MeshInstance3D, joint, radius]
var _parts := []       # every visible MeshInstance3D, for afterimages
var _torso: MeshInstance3D
var _chest_mi: MeshInstance3D
var _pelvis: MeshInstance3D
var _head: MeshInstance3D
var _belt: MeshInstance3D
var _belt_tails := []
var _band: MeshInstance3D
var _band_tails := []
var _feet := []
var _blob: MeshInstance3D
var _time := 0.0
var _trail_left := 0.0
var _trail_every := 0.04
var _trail_next := 0.0
var _trail_color := Color.WHITE
var _trail_group := ""
var _ghost_mat_proto: StandardMaterial3D


func _ready() -> void:
	for g in GROUPS:
		_mats[g] = [_make_mat(base_color, 0.6), _make_mat(joint_color, 0.45)]
		_glow[g] = [Color.BLACK, 0.0]
	current = Poses.GUARD.duplicate()
	target = Poses.GUARD.duplicate()
	for j in JOINTS:
		_vel[j] = Vector3.ZERO

	for l in LIMBS:
		var mesh := CylinderMesh.new()
		mesh.bottom_radius = l[2]
		mesh.top_radius = l[3]
		mesh.height = 1.0
		mesh.radial_segments = 14
		mesh.rings = 1
		var mi := _part(mesh, _mats[l[4]][0])
		_limbs.append([mi, l[0], l[1]])
	for b in BALLS:
		var mi := _part(_sphere(1.0), _mats[b[2]][1])
		_balls.append([mi, b[0], b[1]])

	var torso_mesh := CylinderMesh.new()
	torso_mesh.bottom_radius = 0.115
	torso_mesh.top_radius = 0.17
	torso_mesh.height = 1.0
	torso_mesh.radial_segments = 18
	torso_mesh.rings = 2
	_torso = _part(torso_mesh, _mats["torso"][0])
	_chest_mi = _part(_sphere(1.0), _mats["torso"][0])
	_pelvis = _part(_sphere(1.0), _mats["torso"][0])
	_head = _part(_sphere(1.0, 20, 12), _mats["torso"][0])
	for side in [-1.0, 1.0]:
		_feet.append([_part(_sphere(1.0), _mats["l_leg" if side < 0.0 else "r_leg"][1]), side])

	var belt_mat := _make_mat(belt_color, 0.8)
	_accent_mats.append([belt_mat, belt_color])
	var torus := TorusMesh.new()
	torus.inner_radius = 0.125
	torus.outer_radius = 0.152
	torus.rings = 24
	torus.ring_segments = 8
	_belt = _part(torus, belt_mat)
	for i in 2:
		var tail := BoxMesh.new()
		tail.size = Vector3(0.04, 1.0, 0.012)
		_belt_tails.append(_part(tail, belt_mat))

	if band_color.a > 0.0:
		var band_mat := _make_mat(band_color, 0.7)
		_accent_mats.append([band_mat, band_color])
		var bt := TorusMesh.new()
		bt.inner_radius = 0.104
		bt.outer_radius = 0.126
		bt.rings = 24
		bt.ring_segments = 8
		_band = _part(bt, band_mat)
		for i in 2:
			var tail := BoxMesh.new()
			tail.size = Vector3(0.035, 1.0, 0.01)
			_band_tails.append(_part(tail, band_mat))

	_build_blob_shadow()
	_ghost_mat_proto = StandardMaterial3D.new()
	_ghost_mat_proto.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ghost_mat_proto.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_ghost_mat_proto.no_depth_test = false
	_ghost_mat_proto.cull_mode = BaseMaterial3D.CULL_BACK
	_update_meshes()
	# Draw one invisible afterimage now so its shader compiles at load, not mid-fight.
	spawn_afterimage.call_deferred(Color.BLACK, 0.05)


func _make_mat(color: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.rim_enabled = true
	m.rim = 0.35
	m.rim_tint = 0.4
	# Emission stays enabled (energy 0 when unused) so glows/flashes never
	# switch shader variants mid-fight, which can hitch the frame.
	m.emission_enabled = true
	m.emission_energy_multiplier = 0.0
	return m


func _sphere(r: float, seg: int = 16, rings: int = 10) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = seg
	s.rings = rings
	return s


func _part(mesh: Mesh, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	add_child(mi)
	_parts.append(mi)
	return mi


func _build_blob_shadow() -> void:
	var grad := Gradient.new()
	grad.set_color(0, Color(0, 0, 0, 0.55))
	grad.set_color(1, Color(0, 0, 0, 0.0))
	grad.add_point(0.45, Color(0, 0, 0, 0.35))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 64
	tex.height = 64
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_texture = tex
	var plane := PlaneMesh.new()
	plane.size = Vector2(1.0, 1.0)
	_blob = MeshInstance3D.new()
	_blob.mesh = plane
	_blob.material_override = m
	_blob.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_blob.top_level = true
	add_child(_blob)


## Blend toward a pose. Missing joints keep the guard stance.
func set_pose(pose: Dictionary, speed: float = 12.0) -> void:
	target = Poses.with(Poses.GUARD, pose)
	blend_speed = speed


## Kick a joint's spring (m/s) for reactive secondary motion: hit recoil, landings, parry jolts.
func impulse(joint: String, v: Vector3) -> void:
	if _vel.has(joint):
		_vel[joint] += v


## Kick the whole upper body, with the head trailing more.
func recoil(v: Vector3) -> void:
	impulse("hips", v * 0.3)
	impulse("chest", v * 0.8)
	impulse("head", v * 1.2)
	impulse("l_hand", v * 0.9)
	impulse("r_hand", v * 0.9)


## Make a limb group glow (attack telegraphs). energy 0 turns it off.
func set_glow(group: String, color: Color, energy: float) -> void:
	_glow[group] = [color, energy]


func clear_glow() -> void:
	for g in GROUPS:
		_glow[g] = [Color.BLACK, 0.0]


## Flash the whole body a color (hit / parry feedback).
func flash(color: Color, duration: float = 0.15) -> void:
	_flash_color = color
	_flash_left = duration
	_flash_total = duration


## World position of a solved joint (for placing effects).
func joint_world(j: String) -> Vector3:
	if solved.has(j):
		return to_global(solved[j])
	return global_position


## Leave a fading afterimage trail for `duration` seconds. group "" = whole body.
func trail(color: Color, duration: float, group: String = "", every: float = 0.04) -> void:
	_trail_color = color
	_trail_left = duration
	_trail_group = group
	_trail_every = every
	_trail_next = 0.0


## One frozen, additive, fading copy of the body (or of one limb group).
func spawn_afterimage(color: Color, life: float = 0.28, group: String = "") -> void:
	var host := get_parent()
	if host == null or not is_inside_tree():
		return
	host = host.get_parent() if host.get_parent() != null else host
	var ghost := Node3D.new()
	host.add_child(ghost)
	var mat: StandardMaterial3D = _ghost_mat_proto.duplicate()
	mat.albedo_color = color
	var group_mats := []
	if group != "":
		group_mats = _mats[group]
	for mi in _parts:
		var part: MeshInstance3D = mi
		if not part.visible:
			continue
		if group != "" and not group_mats.has(part.material_override):
			continue
		var g := MeshInstance3D.new()
		g.mesh = part.mesh
		g.material_override = mat
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ghost.add_child(g)
		g.global_transform = part.global_transform
	var tw := ghost.create_tween()
	tw.tween_property(mat, "albedo_color", Color.BLACK, life).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tw.tween_callback(ghost.queue_free)


func _process(delta: float) -> void:
	_time += delta
	_loco_w = lerpf(_loco_w, locomotion_weight, 1.0 - exp(-10.0 * delta))
	var goal := _layered_goal(delta)
	# Critically-ish damped springs per joint, sub-stepped so it stays stable at low FPS.
	var steps := clampi(int(ceil(delta * 120.0)), 1, 8)
	var h := delta / float(steps)
	for i in steps:
		for j in JOINTS:
			var w: float = blend_speed * JOINT_STIFFNESS[j]
			var x: Vector3 = current[j]
			var v: Vector3 = _vel[j]
			var a: Vector3 = (goal[j] - x) * (w * w) - v * (2.0 * damping_ratio * w)
			v += a * h
			x += v * h
			_vel[j] = v
			current[j] = x
	_flash_left = maxf(0.0, _flash_left - delta)
	_update_materials()
	_update_meshes()
	if _trail_left > 0.0:
		_trail_left -= delta
		_trail_next -= delta
		if _trail_next <= 0.0:
			_trail_next = _trail_every
			spawn_afterimage(_trail_color, 0.26, _trail_group)


## Target pose plus procedural layers: walk cycle, lean into movement,
## a fighter's bounce and a slow breathing sway.
func _layered_goal(delta: float) -> Dictionary:
	var g := target.duplicate()
	var flat := Vector3(locomotion.x, 0.0, locomotion.z)
	var speed := flat.length()
	var amt := clampf(speed / 3.0, 0.0, 1.0) * _loco_w
	var dir := flat / speed if speed > 0.05 else Vector3.ZERO
	if amt > 0.01:
		_phase += delta * (7.0 + 5.0 * amt)
	var s := sin(_phase)
	var stride := 0.24 * amt
	var lift_l := maxf(0.0, cos(_phase)) * 0.12 * amt
	var lift_r := maxf(0.0, -cos(_phase)) * 0.12 * amt
	g["l_foot"] += dir * stride * s + Vector3(0, lift_l, 0)
	g["r_foot"] += -dir * stride * s + Vector3(0, lift_r, 0)
	g["l_knee"] += dir * stride * s * 0.6 + Vector3(0, lift_l * 1.3, 0)
	g["r_knee"] += -dir * stride * s * 0.6 + Vector3(0, lift_r * 1.3, 0)
	g["hips"] += Vector3(0, cos(_phase * 2.0) * 0.022 * amt, 0)
	var lean := dir * 0.08 * amt
	g["chest"] += lean
	g["head"] += lean * 1.35
	g["l_hand"] += lean * 0.8 - dir * stride * s * 0.25
	g["r_hand"] += lean * 0.8 + dir * stride * s * 0.25

	var idle := _loco_w * bob_amount
	var bounce := sin(_time * 4.4) * 0.018 * idle
	var sway := sin(_time * 1.3) * 0.016 * idle
	for j in ["hips", "chest", "head"]:
		g[j] += Vector3(0, bounce, 0)
	g["chest"] += Vector3(sway, 0, 0)
	g["head"] += Vector3(sway * 1.5, sin(_time * 1.7) * 0.006 * idle, 0)
	g["l_knee"] += Vector3(0, bounce * 0.5, -absf(bounce) * 0.6)
	g["r_knee"] += Vector3(0, bounce * 0.5, -absf(bounce) * 0.6)
	g["l_hand"] += Vector3(sway * 0.6, bounce * 0.7 + sin(_time * 2.1) * 0.01 * idle, 0)
	g["r_hand"] += Vector3(sway * 0.6, bounce * 0.7 + sin(_time * 2.1 + 1.3) * 0.01 * idle, 0)
	return g


func _update_materials() -> void:
	var f := _flash_left / _flash_total if _flash_total > 0.0 else 0.0
	for g in GROUPS:
		var gc: Color = _glow[g][0]
		var ge: float = _glow[g][1]
		var tones := [base_color, joint_color]
		for i in 2:
			var m: StandardMaterial3D = _mats[g][i]
			var col: Color = tones[i]
			var emit := Color.BLACK
			var energy := 0.0
			if ge > 0.0:
				col = col.lerp(gc, 0.75)
				emit = gc
				energy = ge
			if f > 0.0:
				col = col.lerp(_flash_color, f)
				emit = _flash_color
				energy = maxf(energy, 2.5 * f)
			m.albedo_color = col
			m.emission = emit
			m.emission_energy_multiplier = energy
	for am in _accent_mats:
		var m: StandardMaterial3D = am[0]
		var c: Color = am[1]
		m.albedo_color = c.lerp(_flash_color, f) if f > 0.0 else c
		m.emission = _flash_color
		m.emission_energy_multiplier = 2.5 * f


## Two-bone IK: returns [mid, end] with fixed segment lengths, bending toward `pole`.
static func _two_bone(root: Vector3, goal: Vector3, pole: Vector3, l1: float, l2: float, fallback: Vector3) -> Array:
	var d := goal - root
	var dist := clampf(d.length(), absf(l1 - l2) + 0.02, l1 + l2 - 0.0005)
	var dir := d.normalized() if d.length() > 0.0001 else Vector3.DOWN
	var end := root + dir * dist
	var a := clampf((l1 * l1 + dist * dist - l2 * l2) / (2.0 * l1 * dist), -1.0, 1.0)
	var bend := pole - root
	bend -= dir * bend.dot(dir)
	if bend.length() < 0.001:
		bend = fallback - dir * fallback.dot(dir)
	bend = bend.normalized()
	var mid := root + dir * (l1 * a) + bend * (l1 * sqrt(1.0 - a * a))
	return [mid, end]


func _update_meshes() -> void:
	var p := current
	var s := {}

	# Spine: keep fixed lengths, keep the posed directions.
	var hips: Vector3 = p["hips"]
	var up: Vector3 = (p["chest"] - hips)
	up = up.normalized() if up.length() > 0.001 else Vector3.UP
	var chest: Vector3 = hips + up * SPINE
	var neck_dir: Vector3 = (p["head"] - p["chest"])
	neck_dir = neck_dir.normalized() if neck_dir.length() > 0.001 else up
	var head: Vector3 = chest + neck_dir * NECK

	# Torso twist: the shoulders turn toward whichever hand is further forward
	# (a punch rotates the whole upper body), the hips toward the lead foot.
	var base_side: Vector3 = up.cross(Vector3(0, 0, 1))
	base_side = base_side.normalized() if base_side.length() > 0.01 else Vector3.RIGHT
	var sh_twist: float = clampf((p["l_hand"].z - p["r_hand"].z) * 0.9, -0.7, 0.7)
	var hip_twist: float = clampf((p["l_foot"].z - p["r_foot"].z) * 0.35, -0.45, 0.45)
	var side_sh: Vector3 = base_side.rotated(up, sh_twist)
	var hip_up: Vector3 = Vector3.UP.lerp(up, 0.5).normalized()
	var side_hp: Vector3 = base_side.rotated(hip_up, hip_twist)

	s["hips"] = hips
	s["chest"] = chest
	s["head"] = head
	s["l_shoulder"] = chest - side_sh * SHOULDER_HALF - up * 0.05
	s["r_shoulder"] = chest + side_sh * SHOULDER_HALF - up * 0.05
	s["l_hip"] = hips - side_hp * HIP_HALF - hip_up * 0.04
	s["r_hip"] = hips + side_hp * HIP_HALF - hip_up * 0.04

	var back: Vector3 = side_sh.cross(up)        # +Z when facing -Z
	var hip_back: Vector3 = side_hp.cross(hip_up)
	for side in ["l", "r"]:
		var sgn := -1.0 if side == "l" else 1.0
		var arm := _two_bone(s[side + "_shoulder"], p[side + "_hand"], p[side + "_elbow"],
				UPPER_ARM, FOREARM, -up * 0.6 + back * 0.4 + side_sh * sgn * 0.5)
		s[side + "_elbow"] = arm[0]
		s[side + "_hand"] = arm[1]
		var leg := _two_bone(s[side + "_hip"], p[side + "_foot"], p[side + "_knee"],
				THIGH, SHIN, -hip_back)
		s[side + "_knee"] = leg[0]
		s[side + "_foot"] = leg[1]
	solved = s

	# Limbs and caps.
	for l in _limbs:
		_place_segment(l[0], s[l[1]], s[l[2]], side_sh, 1.0)
	for b in _balls:
		var r: float = b[2]
		(b[0] as MeshInstance3D).transform = Transform3D(Basis().scaled(Vector3(r, r, r)), s[b[1]])

	# Torso: a flattened tapered column from the pelvis to the chest, rounded off
	# at both ends.
	var hip_top: Vector3 = hips + up * 0.04
	_place_segment(_torso, hip_top, chest - up * 0.03, side_sh, 0.62)
	var cb := _basis(side_sh, up)
	_chest_mi.transform = Transform3D(cb * Basis().scaled(Vector3(0.2, 0.11, 0.115)), chest - up * 0.05)
	var hb := _basis(side_hp, hip_up)
	_pelvis.transform = Transform3D(hb * Basis().scaled(Vector3(0.155, 0.11, 0.11)), hips - hip_up * 0.01)
	_belt.transform = Transform3D(hb * Basis().scaled(Vector3(1.0, 1.5, 0.8)), hips + hip_up * 0.065)
	var belt_front: Vector3 = hips + hip_up * 0.06 - hip_back * 0.105
	for i in _belt_tails.size():
		var off: Vector3 = side_hp * (0.035 if i == 0 else -0.03)
		var sway: Vector3 = -_vel["hips"] * 0.04
		var tip: Vector3 = belt_front + off * 1.6 - Vector3.UP * (0.17 - 0.02 * i) - hip_back * 0.03 + sway
		_place_box(_belt_tails[i], belt_front + off, tip, side_hp)

	# Head: a slightly tall egg facing forward, with a headband if this fighter has one.
	var hu := neck_dir
	var head_side: Vector3 = (side_sh - hu * side_sh.dot(hu)).normalized()
	var hdb := _basis(head_side, hu)
	_head.transform = Transform3D(hdb * Basis().scaled(Vector3(0.112, 0.132, 0.122)), head)
	if _band != null:
		var hb2 := hdb * Basis().scaled(Vector3(1.04, 1.7, 1.06))
		_band.transform = Transform3D(hb2, head + hu * 0.035)
		var hback: Vector3 = head_side.cross(hu)
		var knot: Vector3 = head + hu * 0.035 + hback * 0.128
		var drift: Vector3 = -_vel["head"] * 0.05
		for i in _band_tails.size():
			var spread := head_side * (0.05 if i == 0 else -0.045)
			var tip: Vector3 = knot + hback * 0.17 - Vector3.UP * (0.12 + 0.03 * i) + spread + drift
			_place_box(_band_tails[i], knot, tip, head_side)

	# Feet: flattened ellipsoids pointing the way the hips face.
	var fwd_h: Vector3 = Vector3(-hip_back.x, 0.0, -hip_back.z)
	fwd_h = fwd_h.normalized() if fwd_h.length() > 0.01 else Vector3.FORWARD
	var fside: Vector3 = fwd_h.cross(Vector3.UP).normalized()
	for f in _feet:
		var key := "l_foot" if f[1] < 0.0 else "r_foot"
		var fb := Basis(fside, Vector3.UP, -fwd_h)
		var pos: Vector3 = s[key] + fwd_h * 0.055 + Vector3(0, -0.01, 0)
		(f[0] as MeshInstance3D).transform = Transform3D(fb * Basis().scaled(Vector3(0.055, 0.042, 0.11)), pos)

	# Soft contact shadow that stays on the floor and shrinks when airborne.
	if _blob != null and is_inside_tree():
		var g := global_transform
		var centre: Vector3 = g * ((s["l_foot"] + s["r_foot"]) * 0.5 * 0.6 + hips * 0.4)
		var height := maxf(0.0, g.origin.y)
		var k := clampf(1.0 - height * 0.9, 0.4, 1.0)
		_blob.global_transform = Transform3D(Basis().scaled(Vector3(1.0 * k, 1.0, 0.85 * k)).rotated(Vector3.UP, global_rotation.y), Vector3(centre.x, 0.028, centre.z))


## Orthonormal basis with +X = side, +Y = up (side is re-orthogonalised against up).
static func _basis(side: Vector3, up: Vector3) -> Basis:
	var x := (side - up * side.dot(up)).normalized()
	var z := x.cross(up).normalized()
	return Basis(x, up, z)


## Stretch a unit-height mesh between a and b; side_hint orients its flat axis.
func _place_segment(mi: MeshInstance3D, a: Vector3, b: Vector3, side_hint: Vector3, depth: float) -> void:
	var d := b - a
	var length := d.length()
	if length < 0.001:
		mi.visible = false
		return
	mi.visible = true
	var y := d / length
	var x := side_hint - y * side_hint.dot(y)
	if x.length() < 0.01:
		x = y.cross(Vector3.FORWARD)
		if x.length() < 0.01:
			x = y.cross(Vector3.RIGHT)
	x = x.normalized()
	var z := x.cross(y).normalized()
	mi.transform = Transform3D(Basis(x, y * length, z * depth), (a + b) * 0.5)


func _place_box(mi: MeshInstance3D, a: Vector3, b: Vector3, side_hint: Vector3) -> void:
	_place_segment(mi, a, b, side_hint, 1.0)
