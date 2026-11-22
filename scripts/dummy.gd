extends Node3D
## Training dummy. Throws telegraphed strings of high, low and unblockable attacks.
## Telegraph: the attacking limb glows during the windup, then flashes bright right
## before impact. That flash is your timing cue for parry / dodge / duck / hop.

signal feedback(text: String, color: Color, sub: String)
signal structure_changed

const Poses = preload("res://scripts/poses.gd")
const Stickman = preload("res://scripts/stickman.gd")

enum D { IDLE, WINDUP, RECOVER, STAGGER, BROKEN }

const YELLOW := Color(1.0, 0.85, 0.2)
const BLUE := Color(0.3, 0.75, 1.0)
const RED := Color(1.0, 0.2, 0.15)
const GREEN := Color(0.4, 1.0, 0.5)

const ATTACKS := {
	"high": {"kind": "high", "unblockable": false, "windup": 0.62, "color": YELLOW, "label": "HIGH", "limb": "r_arm"},
	"low": {"kind": "low", "unblockable": false, "windup": 0.66, "color": BLUE, "label": "LOW", "limb": "r_leg"},
	"red_high": {"kind": "high", "unblockable": true, "windup": 0.85, "color": RED, "label": "UNBLOCKABLE", "limb": "r_arm"},
	"red_low": {"kind": "low", "unblockable": true, "windup": 0.85, "color": RED, "label": "UNBLOCKABLE", "limb": "r_leg"},
}
const FLASH_LEAD := 0.14       # bright flash this long before impact
const RECOVER_TIME := 0.38
const STAGGER_TIME := 0.85
const BROKEN_TIME := 2.2
const APPROACH_DIST := 1.7
const ATTACK_START_DIST := 2.4

var player: Node3D
var body: Node3D
var label: Label3D

var state := D.IDLE
var state_time := 0.0
var clock := 0.0
var combo: Array = []
var current: Dictionary = {}
var current_windup := 0.6
var next_attack_in := 1.6
var structure := 0.0
var last_structure_gain := -10.0
var open_until := -1.0
var speed_mult := 1.0
var _guard_flash_until := -1.0


func _ready() -> void:
	body = Stickman.new()
	body.base_color = Color(0.32, 0.36, 0.44)
	add_child(body)
	label = Label3D.new()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.font_size = 72
	label.outline_size = 18
	label.pixel_size = 0.004
	label.position = Vector3(0, 2.25, 0)
	label.visible = false
	add_child(label)


func reset() -> void:
	position = Vector3.ZERO
	structure = 0.0
	speed_mult = 1.0
	combo.clear()
	open_until = -1.0
	_enter(D.IDLE)
	next_attack_in = 1.6
	structure_changed.emit()


func is_open() -> bool:
	return state == D.STAGGER or state == D.BROKEN or clock < open_until


func _process(delta: float) -> void:
	if player == null:
		return
	clock += delta
	state_time += delta

	if clock - last_structure_gain > 2.0 and state != D.BROKEN and structure > 0.0:
		structure = maxf(0.0, structure - 6.0 * delta)
		structure_changed.emit()

	var to_player := player.global_position - global_position
	to_player.y = 0.0
	var dist := to_player.length()
	if dist > 0.01 and state != D.BROKEN and state != D.STAGGER:
		var yaw := atan2(-to_player.x, -to_player.z)
		rotation.y = lerp_angle(rotation.y, yaw, 1.0 - exp(-8.0 * delta))

	match state:
		D.IDLE:
			if _guard_flash_until > 0.0 and clock > _guard_flash_until:
				_guard_flash_until = -1.0
				body.set_pose(Poses.GUARD, 10.0)
			if dist > APPROACH_DIST:
				global_position += to_player.normalized() * 1.6 * delta
			next_attack_in -= delta
			if next_attack_in <= 0.0 and dist < ATTACK_START_DIST:
				_start_combo()
		D.WINDUP:
			var left := current_windup - state_time
			var c: Color = current["color"]
			if left <= FLASH_LEAD:
				body.set_glow(current["limb"], c, 6.0)
				label.modulate = Color.WHITE
				label.scale = Vector3.ONE * 1.25
			else:
				body.set_glow(current["limb"], c, lerpf(0.6, 2.0, state_time / current_windup))
			if state_time >= current_windup:
				_impact()
		D.RECOVER:
			if state_time >= RECOVER_TIME:
				if not combo.is_empty():
					_begin_attack(combo.pop_front(), true)
				else:
					_enter(D.IDLE)
					next_attack_in = randf_range(0.9, 1.8) / speed_mult
		D.STAGGER:
			if state_time >= STAGGER_TIME:
				_enter(D.IDLE)
				next_attack_in = randf_range(0.5, 1.0) / speed_mult
		D.BROKEN:
			if state_time >= BROKEN_TIME:
				structure = 0.0
				structure_changed.emit()
				_enter(D.IDLE)
				next_attack_in = 1.0


func _start_combo() -> void:
	var r := randf()
	var n := 1 if r < 0.45 else (2 if r < 0.8 else 3)
	combo.clear()
	for i in n:
		var pick := randf()
		var key := "high"
		if pick < 0.45:
			key = "high"
		elif pick < 0.82:
			key = "low"
		else:
			key = "red_high" if randf() < 0.5 else "red_low"
		combo.append(key)
	_begin_attack(combo.pop_front(), false)


func _begin_attack(key: String, followup: bool) -> void:
	current = ATTACKS[key]
	current_windup = current["windup"] * (0.72 if followup else 1.0) / speed_mult
	_enter(D.WINDUP)
	body.set_pose(Poses.WINDUP_HIGH if current["kind"] == "high" else Poses.WINDUP_LOW, 9.0)
	label.text = current["label"]
	label.modulate = current["color"]
	label.scale = Vector3.ONE
	label.visible = true


func _impact() -> void:
	body.set_pose(Poses.PUNCH_HIGH if current["kind"] == "high" else Poses.SWEEP_LOW, 45.0)
	body.clear_glow()
	label.visible = false
	_enter(D.RECOVER)
	var result: String = player.resolve_attack(current["kind"], current["unblockable"])
	if result == "parry":
		_add_structure(20.0)
		body.flash(Color(0.45, 0.95, 1.0), 0.15)
		if combo.is_empty() and state != D.BROKEN:
			_enter(D.STAGGER)
	elif result == "hit":
		pass


func _enter(s: int) -> void:
	state = s
	state_time = 0.0
	match s:
		D.IDLE:
			body.set_pose(Poses.GUARD, 8.0)
			body.clear_glow()
			label.visible = false
		D.STAGGER:
			body.set_pose(Poses.HIT, 18.0)
			body.clear_glow()
			label.text = "OPEN"
			label.modulate = GREEN
			label.scale = Vector3.ONE
			label.visible = true
		D.BROKEN:
			combo.clear()
			body.set_pose(Poses.KNEEL, 12.0)
			body.clear_glow()
			label.text = "BROKEN"
			label.modulate = GREEN
			label.visible = true


## Player perfectly avoided an attack: cancel the string and open up.
func open_for_counter(duration: float) -> void:
	if state == D.BROKEN:
		return
	combo.clear()
	open_until = clock + duration
	_enter(D.STAGGER)


## Player strike connected range-wise. Returns "counter", "hit" or "blocked".
func receive_strike() -> String:
	if state == D.BROKEN:
		body.flash(Color(1, 0.85, 0.3), 0.12)
		return "hit"
	if is_open():
		body.flash(Color(1, 0.85, 0.3), 0.12)
		body.set_pose(Poses.HIT, 30.0)
		_add_structure(18.0)
		return "counter"
	_add_structure(4.0)
	if state == D.IDLE:
		body.set_pose(Poses.BLOCK_OVER, 30.0)
		_guard_flash_until = clock + 0.25
	return "blocked"


func _add_structure(amount: float) -> void:
	structure = minf(100.0, structure + amount)
	last_structure_gain = clock
	if structure >= 100.0 and state != D.BROKEN:
		_enter(D.BROKEN)
		speed_mult = minf(1.4, speed_mult + 0.08)
		feedback.emit("STRUCTURE BROKEN!", GREEN, "Free hits! The dummy gets a bit faster each time.")
	structure_changed.emit()
