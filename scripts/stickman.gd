extends Node3D
## A stickman built from primitive meshes. Poses are joint positions; the body
## blends toward a target pose each frame and re-orients every limb cylinder.

const Poses = preload("res://scripts/poses.gd")
const JOINTS := ["hips", "chest", "head", "l_elbow", "l_hand", "r_elbow", "r_hand", "l_knee", "l_foot", "r_knee", "r_foot"]
const GROUPS := ["torso", "l_arm", "r_arm", "l_leg", "r_leg"]

# [from, to, radius, group]
const BONES := [
	["hips", "chest", 0.06, "torso"],
	["chest", "neck", 0.04, "torso"],
	["l_shoulder", "r_shoulder", 0.045, "torso"],
	["l_hip", "r_hip", 0.05, "torso"],
	["l_shoulder", "l_elbow", 0.045, "l_arm"],
	["l_elbow", "l_hand", 0.04, "l_arm"],
	["r_shoulder", "r_elbow", 0.045, "r_arm"],
	["r_elbow", "r_hand", 0.04, "r_arm"],
	["l_hip", "l_knee", 0.055, "l_leg"],
	["l_knee", "l_foot", 0.05, "l_leg"],
	["r_hip", "r_knee", 0.055, "r_leg"],
	["r_knee", "r_foot", 0.05, "r_leg"],
]

# [joint, radius, group]
const CAPS := [
	["l_shoulder", 0.05, "torso"], ["r_shoulder", 0.05, "torso"],
	["l_hip", 0.055, "torso"], ["r_hip", 0.055, "torso"],
	["l_elbow", 0.045, "l_arm"], ["l_hand", 0.065, "l_arm"],
	["r_elbow", 0.045, "r_arm"], ["r_hand", 0.065, "r_arm"],
	["l_knee", 0.055, "l_leg"], ["l_foot", 0.06, "l_leg"],
	["r_knee", 0.055, "r_leg"], ["r_foot", 0.06, "r_leg"],
]

var base_color := Color(0.93, 0.93, 0.96)
var blend_speed := 12.0
var bob_amount := 1.0

var current := {}
var target := {}
var _materials := {}
var _glow := {}        # group -> [Color, energy]
var _flash_color := Color.WHITE
var _flash_left := 0.0
var _flash_total := 0.1
var _bones := []       # [MeshInstance3D, from, to]
var _caps := []        # [MeshInstance3D, joint]
var _head: MeshInstance3D
var _time := 0.0


func _ready() -> void:
	for g in GROUPS:
		var m := StandardMaterial3D.new()
		m.albedo_color = base_color
		m.roughness = 0.55
		_materials[g] = m
		_glow[g] = [Color.BLACK, 0.0]
	current = Poses.GUARD.duplicate()
	target = Poses.GUARD.duplicate()

	for b in BONES:
		var mesh := CylinderMesh.new()
		mesh.top_radius = b[2]
		mesh.bottom_radius = b[2]
		mesh.height = 1.0
		mesh.radial_segments = 10
		mesh.rings = 1
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = _materials[b[3]]
		add_child(mi)
		_bones.append([mi, b[0], b[1]])
	for c in CAPS:
		var s := SphereMesh.new()
		s.radius = c[1]
		s.height = c[1] * 2.0
		s.radial_segments = 10
		s.rings = 6
		var mi := MeshInstance3D.new()
		mi.mesh = s
		mi.material_override = _materials[c[2]]
		add_child(mi)
		_caps.append([mi, c[0]])
	var hs := SphereMesh.new()
	hs.radius = 0.125
	hs.height = 0.25
	_head = MeshInstance3D.new()
	_head.mesh = hs
	_head.material_override = _materials["torso"]
	add_child(_head)
	_update_meshes()


## Blend toward a pose. Missing joints keep the guard stance.
func set_pose(pose: Dictionary, speed: float = 12.0) -> void:
	target = Poses.with(Poses.GUARD, pose)
	blend_speed = speed


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


func _process(delta: float) -> void:
	_time += delta
	var k := 1.0 - exp(-blend_speed * delta)
	for j in JOINTS:
		current[j] = (current[j] as Vector3).lerp(target[j], k)
	_flash_left = maxf(0.0, _flash_left - delta)
	_update_materials()
	_update_meshes()


func _update_materials() -> void:
	var f := _flash_left / _flash_total if _flash_total > 0.0 else 0.0
	for g in GROUPS:
		var m: StandardMaterial3D = _materials[g]
		var gc: Color = _glow[g][0]
		var ge: float = _glow[g][1]
		var col := base_color
		var emit := Color.BLACK
		var energy := 0.0
		if ge > 0.0:
			col = base_color.lerp(gc, 0.75)
			emit = gc
			energy = ge
		if f > 0.0:
			col = col.lerp(_flash_color, f)
			emit = _flash_color
			energy = maxf(energy, 2.5 * f)
		m.albedo_color = col
		m.emission_enabled = energy > 0.0
		m.emission = emit
		m.emission_energy_multiplier = energy


func _update_meshes() -> void:
	var p := current.duplicate()
	var bob := sin(_time * 3.2) * 0.012 * bob_amount
	p["hips"] += Vector3(0, bob * 0.6, 0)
	p["chest"] += Vector3(0, bob, 0)
	p["head"] += Vector3(0, bob * 1.1, 0)

	var hips: Vector3 = p["hips"]
	var chest: Vector3 = p["chest"]
	var head: Vector3 = p["head"]
	var up := (chest - hips).normalized()
	var side := up.cross(Vector3(0, 0, 1)).normalized()
	if side.length() < 0.01:
		side = Vector3.RIGHT
	p["l_shoulder"] = chest - side * 0.17 - up * 0.03
	p["r_shoulder"] = chest + side * 0.17 - up * 0.03
	p["l_hip"] = hips - side * 0.10
	p["r_hip"] = hips + side * 0.10
	p["neck"] = head + (chest - head).normalized() * 0.11

	for b in _bones:
		_place_bone(b[0], p[b[1]], p[b[2]])
	for c in _caps:
		(c[0] as MeshInstance3D).position = p[c[1]]
	_head.position = head


func _place_bone(mi: MeshInstance3D, a: Vector3, b: Vector3) -> void:
	var d := b - a
	var length := d.length()
	if length < 0.001:
		mi.visible = false
		return
	mi.visible = true
	var y := d / length
	var x := y.cross(Vector3.FORWARD)
	if x.length() < 0.01:
		x = y.cross(Vector3.RIGHT)
	x = x.normalized()
	var z := x.cross(y).normalized()
	mi.transform = Transform3D(Basis(x, y * length, z), (a + b) * 0.5)
