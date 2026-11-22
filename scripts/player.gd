extends Node3D
## The player stickman. Always locked on to the training dummy.
## Defensive toolkit: block (hold), parry (tap block as the hit lands),
## dodge / sidestep (i-frames), duck (beats high attacks), hop (beats low sweeps).

signal feedback(text: String, color: Color, sub: String)
signal shake(amount: float)
signal stats_changed

const Poses = preload("res://scripts/poses.gd")
const Stickman = preload("res://scripts/stickman.gd")

# No stun states: getting hit never takes control away from you.
enum S { IDLE, BLOCK, DUCK, DODGE, JUMP, STRIKE }

# --- Tuning (seconds / metres). These numbers ARE the game feel. ---
const MOVE_SPEED := 3.2
const BLOCK_MOVE_SPEED := 1.4
const PARRY_WINDOW := 0.16      # block pressed this close to impact = parry
const PARRY_LOCKOUT := 0.35     # re-pressing block faster than this won't open a new parry window (anti-mash)
const PERFECT_WINDOW := 0.22    # dodge / duck started this close to impact = perfect avoid
const DODGE_TIME := 0.42
const DODGE_IFRAMES := 0.30
const DODGE_DISTANCE := 1.9
const JUMP_TIME := 0.55
const JUMP_HEIGHT := 0.55
const STRIKE_TIME := 0.30
const STRIKE_HIT_AT := 0.11
const STRIKE_RANGE := 2.1
const ATTACK_RANGE := 2.5       # dummy attacks miss beyond this
const MIN_DIST := 1.1
const ARENA_RADIUS := 7.4
const INPUT_BUFFER := 0.15
const FLICK_RESET := 0.3        # right stick must come back near centre to re-arm
const FLICK_TRIGGER := 0.7      # and then pass this...
const FLICK_TIME := 0.18        # ...within this long, so a slow push isn't a flick
const FORWARD_DODGE_DISTANCE := 1.0
const MOVE_ACCEL := 11.0        # higher = snappier footwork, lower = more momentum
const TURN_SPEED := 16.0
const GUARD_BREAK_LOCK := 0.8   # can't block for this long after a guard break (you can still move and dodge)

const WHITE := Color(1, 1, 1)
const GOLD := Color(1.0, 0.82, 0.25)
const CYAN := Color(0.45, 0.95, 1.0)
const GREY := Color(0.75, 0.75, 0.8)
const RED := Color(1.0, 0.3, 0.25)

var dummy: Node3D
var body: Node3D

var state := S.IDLE
var state_time := 0.0
var clock := 0.0
var hp := 100.0
var structure := 0.0
var last_structure_gain := -10.0
var block_pressed_at := -10.0
var last_block_press := -10.0
enum DodgeMode { BACK, SIDE, FORWARD }
var dodge_mode := DodgeMode.BACK
var move_vel := Vector3.ZERO
var flick_armed := true
var flick_low_at := 0.0
var flick_vec := Vector2.ZERO
var dodge_side := 1.0
var dodge_radius := 1.6
var dodge_progress := 0.0
var strike_done := false
var jump_height := 0.0
var buffer := {"dodge": -10.0, "jump": -10.0, "strike": -10.0, "flick": -10.0}
var stats := {"parries": 0, "perfect": 0, "avoids": 0, "blocks": 0, "hits": 0, "counters": 0}

var guard_locked_until := -10.0
var _pose_dodge_l: Dictionary
var _pose_dodge_r: Dictionary
var _pose_block: Dictionary


func _ready() -> void:
	_pose_dodge_l = Poses.DODGE_LEFT
	_pose_dodge_r = Poses.mirror(Poses.DODGE_LEFT)
	_pose_block = Poses.BLOCK_OVER
	body = Stickman.new()
	body.base_color = Color(0.95, 0.95, 0.98)
	add_child(body)


func reset() -> void:
	hp = 100.0
	structure = 0.0
	for k in stats:
		stats[k] = 0
	position = Vector3(0, 0, 1.7)
	_set_state(S.IDLE)
	stats_changed.emit()


func _process(delta: float) -> void:
	if dummy == null:
		return
	clock += delta
	state_time += delta
	_read_presses()

	if clock - last_structure_gain > 1.5:
		structure = maxf(0.0, structure - 12.0 * delta)

	match state:
		S.IDLE, S.BLOCK:
			if not _try_actions():
				var want_block := Input.is_action_pressed("block") and clock >= guard_locked_until
				if want_block and state != S.BLOCK:
					_set_state(S.BLOCK)
				elif not want_block and state != S.IDLE:
					_set_state(S.IDLE)
				_move(delta, BLOCK_MOVE_SPEED if want_block else MOVE_SPEED)
		S.DUCK:
			if _consume("flick"):
				_start_dodge(flick_vec)
			elif _consume("dodge"):
				_start_dodge(_move_input())
			elif not Input.is_action_pressed("duck"):
				_set_state(S.IDLE)
		S.DODGE:
			_update_dodge()
		S.JUMP:
			var p := clampf(state_time / JUMP_TIME, 0.0, 1.0)
			jump_height = sin(PI * p) * JUMP_HEIGHT
			if state_time >= JUMP_TIME:
				jump_height = 0.0
				_set_state(S.IDLE)
				body.impulse("hips", Vector3(0, -1.6, 0))
				body.impulse("chest", Vector3(0, -1.8, 0))
				body.impulse("head", Vector3(0, -2.0, 0))
		S.STRIKE:
			if not strike_done and state_time >= STRIKE_HIT_AT:
				strike_done = true
				_resolve_strike()
			if state_time > STRIKE_HIT_AT + 0.06:
				body.set_pose(Poses.GUARD, 14.0)
			if _consume("flick"):
				_start_dodge(flick_vec)   # dodges cancel strikes
			elif _consume("dodge"):
				_start_dodge(_move_input())
			elif strike_done and Input.is_action_pressed("duck"):
				_set_state(S.DUCK)
			elif strike_done and _consume("jump"):
				_set_state(S.JUMP)
			elif state_time >= STRIKE_TIME:
				_set_state(S.IDLE)

	if state != S.IDLE and state != S.BLOCK:
		move_vel = move_vel.lerp(Vector3.ZERO, 1.0 - exp(-MOVE_ACCEL * delta))
	body.position.y = jump_height
	_face_dummy(delta)
	body.locomotion = global_transform.basis.inverse() * move_vel
	body.locomotion_weight = 1.0 if state == S.IDLE else (0.6 if state == S.BLOCK else 0.0)


func _read_presses() -> void:
	for a in ["dodge", "jump", "strike"]:
		if Input.is_action_just_pressed(a):
			buffer[a] = clock
	# Right-stick flick (or arrow key tap) = dodge in that direction.
	var r := Input.get_vector("flick_left", "flick_right", "flick_down", "flick_up")
	var m := r.length()
	if m < FLICK_RESET:
		flick_armed = true
		flick_low_at = clock
	elif m > FLICK_TRIGGER:
		if flick_armed and clock - flick_low_at <= FLICK_TIME:
			flick_vec = r
			buffer["flick"] = clock
		flick_armed = false
	if Input.is_action_just_pressed("block"):
		if clock - last_block_press >= PARRY_LOCKOUT:
			block_pressed_at = clock
		last_block_press = clock


func _consume(action: String) -> bool:
	if clock - buffer[action] <= INPUT_BUFFER:
		buffer[action] = -10.0
		return true
	return false


func _try_actions() -> bool:
	if _consume("flick"):
		_start_dodge(flick_vec)
		return true
	if _consume("dodge"):
		_start_dodge(_move_input())
		return true
	if _consume("jump"):
		_set_state(S.JUMP)
		return true
	if Input.is_action_pressed("duck"):
		_set_state(S.DUCK)
		return true
	if _consume("strike"):
		_set_state(S.STRIKE)
		return true
	return false


func _set_state(s: int) -> void:
	state = s
	state_time = 0.0
	match s:
		S.IDLE:
			body.set_pose(Poses.GUARD, 12.0)
		S.BLOCK:
			body.set_pose(_pose_block, 32.0)
		S.DUCK:
			body.set_pose(Poses.DUCK, 30.0)
		S.DODGE:
			match dodge_mode:
				DodgeMode.SIDE:
					body.set_pose(_pose_dodge_r if dodge_side > 0.0 else _pose_dodge_l, 22.0)
				DodgeMode.FORWARD:
					body.set_pose(Poses.DODGE_FORWARD, 22.0)
				_:
					body.set_pose(Poses.DODGE_BACK, 22.0)
		S.JUMP:
			body.set_pose(Poses.JUMP, 20.0)
		S.STRIKE:
			strike_done = false
			body.set_pose(Poses.STRIKE, 38.0)


## dir: x = right/left, y = forward/back (relative to facing the dummy).
## Sideways = sidestep arc, back = backstep, forward = slip in under the attack.
func _start_dodge(dir: Vector2) -> void:
	dodge_radius = _flat(dummy.global_position - global_position).length()
	if absf(dir.x) > 0.35 and absf(dir.x) >= absf(dir.y) * 0.75:
		dodge_mode = DodgeMode.SIDE
		dodge_side = signf(dir.x)
	elif dir.y > 0.5:
		dodge_mode = DodgeMode.FORWARD
	else:
		dodge_mode = DodgeMode.BACK
	dodge_progress = 0.0
	jump_height = 0.0
	_set_state(S.DODGE)


func _update_dodge() -> void:
	var p := clampf(state_time / DODGE_TIME, 0.0, 1.0)
	var eased := 1.0 - pow(1.0 - p, 3.0)
	var dist := FORWARD_DODGE_DISTANCE if dodge_mode == DodgeMode.FORWARD else DODGE_DISTANCE
	var step := (eased - dodge_progress) * dist
	dodge_progress = eased
	var f := _forward()
	if dodge_mode == DodgeMode.FORWARD:
		global_position += f * step
	elif dodge_mode == DodgeMode.SIDE:
		var right := f.cross(Vector3.UP)
		global_position += right * dodge_side * step
		# Keep the same distance so the sidestep arcs around the attacker.
		var off := _flat(global_position - dummy.global_position)
		if off.length() > 0.01:
			var target := dummy.global_position + off.normalized() * dodge_radius
			global_position = Vector3(target.x, global_position.y, target.z)
	else:
		global_position -= f * step
	_clamp_position()
	if state_time >= DODGE_TIME:
		_set_state(S.IDLE)


func _move(delta: float, speed: float) -> void:
	var inp := _move_input()
	var f := _forward()
	var r := f.cross(Vector3.UP)
	var desired := (r * inp.x + f * inp.y) * speed
	move_vel = move_vel.lerp(desired, 1.0 - exp(-MOVE_ACCEL * delta))
	global_position += move_vel * delta
	if absf(inp.x) > 0.3:
		dodge_side = signf(inp.x)
	_clamp_position()


func _move_input() -> Vector2:
	return Input.get_vector("move_left", "move_right", "move_down", "move_up")


func _forward() -> Vector3:
	var f := _flat(dummy.global_position - global_position)
	return f.normalized() if f.length() > 0.01 else Vector3.FORWARD


func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


func _clamp_position() -> void:
	var off := _flat(global_position - dummy.global_position)
	if off.length() < MIN_DIST:
		off = (off.normalized() if off.length() > 0.01 else Vector3.BACK) * MIN_DIST
		global_position = Vector3(dummy.global_position.x + off.x, global_position.y, dummy.global_position.z + off.z)
	var from_center := _flat(global_position)
	if from_center.length() > ARENA_RADIUS:
		from_center = from_center.normalized() * ARENA_RADIUS
		global_position = Vector3(from_center.x, global_position.y, from_center.z)


func _face_dummy(delta: float) -> void:
	var d := _flat(dummy.global_position - global_position)
	if d.length() > 0.05:
		var yaw := atan2(-d.x, -d.z)
		rotation.y = lerp_angle(rotation.y, yaw, 1.0 - exp(-TURN_SPEED * delta))


func _resolve_strike() -> void:
	var dist := _flat(dummy.global_position - global_position).length()
	if dist > STRIKE_RANGE:
		return
	var result: String = dummy.receive_strike()
	match result:
		"counter":
			stats["counters"] += 1
			feedback.emit("COUNTER", GOLD, "")
			shake.emit(0.25)
		"hit":
			feedback.emit("HIT", GOLD, "")
			shake.emit(0.2)
		"blocked":
			feedback.emit("", GREY, "The dummy guards normal strikes. Hit it after a parry or a perfect avoid.")
	stats_changed.emit()


## Called by the dummy at the exact moment an attack lands.
## kind is "high" or "low". Returns the outcome as a short string.
func resolve_attack(kind: String, unblockable: bool) -> String:
	var dist := _flat(dummy.global_position - global_position).length()
	if dist > ATTACK_RANGE:
		feedback.emit("WHIFF", GREY, "Out of range. Stay close so you can counter.")
		return "miss"

	if state == S.DODGE and state_time <= DODGE_IFRAMES:
		return _avoid("DODGE", state_time <= PERFECT_WINDOW)
	if kind == "high" and state == S.DUCK:
		return _avoid("DUCK", state_time <= PERFECT_WINDOW)
	if kind == "low" and state == S.JUMP and jump_height > 0.12:
		return _avoid("HOP", state_time <= PERFECT_WINDOW + 0.08)

	var can_guard := state == S.IDLE or state == S.BLOCK
	if not unblockable and can_guard and Input.is_action_pressed("block") and clock - block_pressed_at <= PARRY_WINDOW:
		stats["parries"] += 1
		structure = maxf(0.0, structure - 10.0)
		body.flash(CYAN, 0.18)
		_set_state(S.BLOCK)
		body.impulse("l_hand", Vector3(0, 0.8, -1.5))
		body.impulse("r_hand", Vector3(0, 0.8, -1.5))
		feedback.emit("PARRY!", CYAN, "")
		shake.emit(0.18)
		stats_changed.emit()
		return "parry"

	if not unblockable and state == S.BLOCK:
		structure += 28.0 if kind == "low" else 22.0
		last_structure_gain = clock
		stats["blocks"] += 1
		if structure >= 100.0:
			structure = 40.0
			hp -= 8.0
			body.flash(RED, 0.3)
			body.recoil(Vector3(0, -0.5, 4.0))
			guard_locked_until = clock + GUARD_BREAK_LOCK
			move_vel = -_forward() * 4.0   # shoved back, but you keep control
			_set_state(S.IDLE)
			feedback.emit("GUARD BROKEN", RED, "Can't block for a moment. Blocking fills your structure, so parry or avoid instead.")
			shake.emit(0.5)
		else:
			body.flash(GREY, 0.1)
			body.recoil(Vector3(0, 0, 1.4))
			feedback.emit("BLOCKED", GREY, "Tap block right as the hit lands to parry.")
			shake.emit(0.08)
		stats_changed.emit()
		return "block"

	# Clean hit.
	var dmg := 18.0 if unblockable else (12.0 if kind == "high" else 10.0)
	var hint := "Yellow = high (duck), blue = low (hop), red = can't be blocked."
	if unblockable and state == S.BLOCK:
		hint = "Red attacks can't be blocked. Duck/hop it or dodge."
	elif kind == "high" and state == S.JUMP:
		hint = "High attack: duck, dodge or parry."
	elif kind == "low" and state == S.DUCK:
		hint = "Low sweep: hop, dodge or parry."
	elif state == S.DODGE:
		hint = "Dodged too early. Wait for the flash."
	hp -= dmg
	structure = minf(100.0, structure + 8.0)
	last_structure_gain = clock
	stats["hits"] += 1
	body.flash(RED, 0.25)
	move_vel += -_forward() * 1.5     # small knockback slide, no stun
	body.recoil(Vector3(0, 0.4 if kind == "high" else -0.6, 3.0))
	shake.emit(0.4)
	if hp <= 0.0:
		hp = 100.0
		structure = 0.0
		feedback.emit("DOWN!", RED, "Health refilled. Keep practising.")
	else:
		feedback.emit("HIT", RED, hint)
	stats_changed.emit()
	return "hit"


func _avoid(what: String, perfect: bool) -> String:
	stats["avoids"] += 1
	if perfect:
		stats["perfect"] += 1
		dummy.open_for_counter(0.9)
		body.flash(GOLD, 0.2)
		feedback.emit("PERFECT " + what, GOLD, "It's open. Counter now!")
	else:
		var past := {"DODGE": "DODGED", "DUCK": "DUCKED", "HOP": "HOPPED"}
		feedback.emit(past[what], WHITE, "")
	stats_changed.emit()
	return "perfect" if perfect else "avoid"


func is_busy() -> bool:
	return state != S.IDLE and state != S.BLOCK
