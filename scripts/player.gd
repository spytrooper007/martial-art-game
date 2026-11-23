extends Node3D
## The player fighter, on its own: a movement and dodge lab.
## Movement is camera-relative and the fighter turns to face where it walks.
## Dodges go in the stick direction; the pose (sidestep, backstep, slip in) is
## picked from that direction relative to where the fighter is facing.
## Also: block stance (hold), duck (hold), hop, and a jab, so the whole
## movement set can be felt out before an opponent comes back.

signal shake(amount: float)
signal dodged(kind: String)

const Poses = preload("res://scripts/poses.gd")
const Stickman = preload("res://scripts/stickman.gd")

enum S { IDLE, BLOCK, DUCK, DODGE, JUMP, STRIKE }
enum DodgeMode { BACK, SIDE, FORWARD }

# --- Tuning (seconds / metres). These numbers ARE the feel. ---
const MOVE_SPEED := 3.2
const BLOCK_MOVE_SPEED := 1.4
const MOVE_ACCEL := 11.0        # higher = snappier footwork, lower = more momentum
const TURN_SPEED := 14.0        # how fast the fighter turns to face its walking direction
const DODGE_TIME := 0.42
const DODGE_IFRAMES := 0.30     # shown as blue afterimages
const DODGE_DISTANCE := 1.9
const FORWARD_DODGE_DISTANCE := 1.0
const JUMP_TIME := 0.55
const JUMP_HEIGHT := 0.55
const STRIKE_TIME := 0.30
const ARENA_RADIUS := 7.4
const INPUT_BUFFER := 0.15
const FLICK_RESET := 0.3        # right stick must come back near centre to re-arm
const FLICK_TRIGGER := 0.7      # and then pass this...
const FLICK_TIME := 0.18        # ...within this long, so a slow push isn't a flick

var body: Node3D
var fx: Node3D                  # optional effects node (scripts/fx.gd); purely visual
var camera: Camera3D            # movement is relative to this camera's yaw

var state := S.IDLE
var state_time := 0.0
var clock := 0.0
var dodge_mode := DodgeMode.BACK
var dodge_dir := Vector3.BACK   # world-space direction of the current dodge
var dodge_side := 1.0
var dodge_progress := 0.0
var move_vel := Vector3.ZERO
var flick_armed := true
var flick_low_at := 0.0
var flick_vec := Vector2.ZERO
var jump_height := 0.0
var buffer := {"dodge": -10.0, "jump": -10.0, "strike": -10.0, "flick": -10.0}
var stats := {"dodges": 0, "sidesteps": 0, "backsteps": 0, "slips": 0, "hops": 0, "jabs": 0, "distance": 0.0}

var _pose_dodge_l: Dictionary
var _pose_dodge_r: Dictionary
var _yaw := 0.0


func _ready() -> void:
	_pose_dodge_l = Poses.DODGE_LEFT
	_pose_dodge_r = Poses.mirror(Poses.DODGE_LEFT)
	body = Stickman.new()
	body.base_color = Color(0.94, 0.93, 0.9)      # white gi
	body.joint_color = Color(0.86, 0.84, 0.8)
	body.belt_color = Color(0.06, 0.06, 0.07)     # black belt
	body.band_color = Color(0.85, 0.12, 0.1)      # red headband
	add_child(body)
	_yaw = rotation.y


func reset() -> void:
	for k in stats:
		stats[k] = 0
	stats["distance"] = 0.0
	position = Vector3.ZERO
	move_vel = Vector3.ZERO
	_yaw = 0.0
	rotation.y = 0.0
	jump_height = 0.0
	_set_state(S.IDLE)


func is_invulnerable() -> bool:
	return state == S.DODGE and state_time <= DODGE_IFRAMES


func _process(delta: float) -> void:
	clock += delta
	state_time += delta
	_read_presses()
	var before := global_position

	match state:
		S.IDLE, S.BLOCK:
			if not _try_actions():
				var want_block := Input.is_action_pressed("block")
				if want_block and state != S.BLOCK:
					_set_state(S.BLOCK)
				elif not want_block and state != S.IDLE:
					_set_state(S.IDLE)
				_move(delta, BLOCK_MOVE_SPEED if want_block else MOVE_SPEED, not want_block)
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
			# Keep a little air control so hops don't feel stuck in place.
			_move(delta, MOVE_SPEED * 0.6, false)
			if state_time >= JUMP_TIME:
				jump_height = 0.0
				_set_state(S.IDLE)
				_fx_dust()
				body.impulse("hips", Vector3(0, -1.6, 0))
				body.impulse("chest", Vector3(0, -1.8, 0))
				body.impulse("head", Vector3(0, -2.0, 0))
		S.STRIKE:
			if state_time > 0.17:
				body.set_pose(Poses.GUARD, 14.0)
			if _consume("flick"):
				_start_dodge(flick_vec)   # dodges cancel strikes
			elif _consume("dodge"):
				_start_dodge(_move_input())
			elif state_time > 0.12 and Input.is_action_pressed("duck"):
				_set_state(S.DUCK)
			elif state_time > 0.12 and _consume("jump"):
				_set_state(S.JUMP)
			elif state_time >= STRIKE_TIME:
				_set_state(S.IDLE)

	if state != S.IDLE and state != S.BLOCK and state != S.JUMP:
		move_vel = move_vel.lerp(Vector3.ZERO, 1.0 - exp(-MOVE_ACCEL * delta))
	rotation.y = _yaw
	body.position.y = jump_height
	body.locomotion = global_transform.basis.inverse() * move_vel
	body.locomotion_weight = 1.0 if state == S.IDLE else (0.6 if state == S.BLOCK else 0.0)
	stats["distance"] += _flat(global_position - before).length()


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
		stats["hops"] += 1
		_set_state(S.JUMP)
		return true
	if Input.is_action_pressed("duck"):
		_set_state(S.DUCK)
		return true
	if _consume("strike"):
		stats["jabs"] += 1
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
			body.set_pose(Poses.BLOCK_OVER, 32.0)
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
			_fx_dust()
		S.STRIKE:
			body.set_pose(Poses.STRIKE, 38.0)
			body.trail(Color(0.35, 0.33, 0.3), 0.12, "r_arm", 0.025)


## stick: x = right/left, y = up/down on the stick, i.e. camera-relative.
## No direction (dodge button with the stick centred) = backstep.
func _start_dodge(stick: Vector2) -> void:
	var facing := _facing()
	var right := facing.cross(Vector3.UP)
	if stick.length() < 0.35:
		dodge_dir = -facing
	else:
		dodge_dir = _stick_to_world(stick).normalized()
	# Classify relative to where the fighter faces, to pick the pose.
	var lx := dodge_dir.dot(right)
	var ly := dodge_dir.dot(facing)
	if absf(lx) > 0.35 and absf(lx) >= absf(ly) * 0.75:
		dodge_mode = DodgeMode.SIDE
		dodge_side = signf(lx)
		stats["sidesteps"] += 1
	elif ly > 0.5:
		dodge_mode = DodgeMode.FORWARD
		stats["slips"] += 1
	else:
		dodge_mode = DodgeMode.BACK
		stats["backsteps"] += 1
	stats["dodges"] += 1
	dodge_progress = 0.0
	jump_height = 0.0
	_set_state(S.DODGE)
	# Afterimages for exactly the invulnerable part of the dodge, so you can see your i-frames.
	body.trail(Color(0.3, 0.5, 0.75), DODGE_IFRAMES, "", 0.045)
	_fx_dust()
	dodged.emit(["BACKSTEP", "SIDESTEP", "SLIP"][dodge_mode])


func _update_dodge() -> void:
	var p := clampf(state_time / DODGE_TIME, 0.0, 1.0)
	var eased := 1.0 - pow(1.0 - p, 3.0)
	var dist := FORWARD_DODGE_DISTANCE if dodge_mode == DodgeMode.FORWARD else DODGE_DISTANCE
	var step := (eased - dodge_progress) * dist
	dodge_progress = eased
	global_position += dodge_dir * step
	_clamp_position()
	if state_time >= DODGE_TIME:
		_set_state(S.IDLE)


func _move(delta: float, speed: float, turn: bool) -> void:
	var inp := _move_input()
	var desired := _stick_to_world(inp) * speed
	move_vel = move_vel.lerp(desired, 1.0 - exp(-MOVE_ACCEL * delta))
	global_position += move_vel * delta
	# Turn toward the walking direction (blocking keeps your facing, so you can strafe).
	if turn and inp.length() > 0.2:
		var d := _stick_to_world(inp)
		var yaw := atan2(-d.x, -d.z)
		_yaw = lerp_angle(_yaw, yaw, 1.0 - exp(-TURN_SPEED * delta))
	_clamp_position()


func _move_input() -> Vector2:
	return Input.get_vector("move_left", "move_right", "move_down", "move_up")


## Stick (x right, y up) to a flat world direction, relative to the camera's yaw.
func _stick_to_world(v: Vector2) -> Vector3:
	var fwd := Vector3.FORWARD
	if camera != null:
		fwd = _flat(-camera.global_transform.basis.z)
		fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
	var right := fwd.cross(Vector3.UP)
	return right * v.x + fwd * v.y


func _facing() -> Vector3:
	return Vector3(-sin(_yaw), 0.0, -cos(_yaw))


func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


func _clamp_position() -> void:
	var from_center := _flat(global_position)
	if from_center.length() > ARENA_RADIUS:
		from_center = from_center.normalized() * ARENA_RADIUS
		global_position = Vector3(from_center.x, global_position.y, from_center.z)


func _fx_dust() -> void:
	if fx != null:
		fx.dust(Vector3(global_position.x, 0.06, global_position.z), 8)


func state_name() -> String:
	return ["IDLE", "BLOCK", "DUCK", "DODGE", "HOP", "JAB"][state]
