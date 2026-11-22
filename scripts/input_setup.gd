extends RefCounted
## Builds the input map in code so gamepad + keyboard bindings live in one readable place.
## Gamepad events use device = -1, so any connected controller works.

static func setup() -> void:
	_action("move_left", 0.25, [_key(KEY_A), _axis(JOY_AXIS_LEFT_X, -1.0), _btn(JOY_BUTTON_DPAD_LEFT)])
	_action("move_right", 0.25, [_key(KEY_D), _axis(JOY_AXIS_LEFT_X, 1.0), _btn(JOY_BUTTON_DPAD_RIGHT)])
	_action("move_up", 0.25, [_key(KEY_W), _axis(JOY_AXIS_LEFT_Y, -1.0), _btn(JOY_BUTTON_DPAD_UP)])
	_action("move_down", 0.25, [_key(KEY_S), _axis(JOY_AXIS_LEFT_Y, 1.0), _btn(JOY_BUTTON_DPAD_DOWN)])

	# Flick dodge: flick the right stick in a direction. Keyboard: tap an arrow key.
	_action("flick_left", 0.2, [_key(KEY_LEFT), _axis(JOY_AXIS_RIGHT_X, -1.0)])
	_action("flick_right", 0.2, [_key(KEY_RIGHT), _axis(JOY_AXIS_RIGHT_X, 1.0)])
	_action("flick_up", 0.2, [_key(KEY_UP), _axis(JOY_AXIS_RIGHT_Y, -1.0)])
	_action("flick_down", 0.2, [_key(KEY_DOWN), _axis(JOY_AXIS_RIGHT_Y, 1.0)])

	# Block / parry: LB (L1) or LT (L2). Keyboard: K or right mouse.
	_action("block", 0.3, [_key(KEY_K), _mouse(MOUSE_BUTTON_RIGHT), _btn(JOY_BUTTON_LEFT_SHOULDER), _axis(JOY_AXIS_TRIGGER_LEFT, 1.0)])
	# Dodge / sidestep: RB (R1) or RT (R2). Keyboard: Shift or L.
	_action("dodge", 0.3, [_key(KEY_SHIFT), _key(KEY_L), _btn(JOY_BUTTON_RIGHT_SHOULDER), _axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)])
	# Duck: B (Circle). Keyboard: C or Ctrl.
	_action("duck", 0.5, [_key(KEY_C), _key(KEY_CTRL), _btn(JOY_BUTTON_B)])
	# Hop over sweeps: A (Cross). Keyboard: Space.
	_action("jump", 0.5, [_key(KEY_SPACE), _btn(JOY_BUTTON_A)])
	# Counter strike: X (Square). Keyboard: J or left mouse.
	_action("strike", 0.5, [_key(KEY_J), _mouse(MOUSE_BUTTON_LEFT), _btn(JOY_BUTTON_X)])
	# Reset: Start/Options. Keyboard: R.
	_action("reset", 0.5, [_key(KEY_R), _btn(JOY_BUTTON_START)])
	# Toggle 50% slow-motion training: Back/View/Share. Keyboard: T.
	_action("slowmo", 0.5, [_key(KEY_T), _btn(JOY_BUTTON_BACK)])


static func _action(action_name: String, deadzone: float, events: Array) -> void:
	if InputMap.has_action(action_name):
		InputMap.erase_action(action_name)
	InputMap.add_action(action_name, deadzone)
	for e in events:
		InputMap.action_add_event(action_name, e)


static func _key(code: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = code
	return e


static func _mouse(button: MouseButton) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = button
	return e


static func _btn(button: JoyButton) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.button_index = button
	e.device = -1
	return e


static func _axis(axis: JoyAxis, value: float) -> InputEventJoypadMotion:
	var e := InputEventJoypadMotion.new()
	e.axis = axis
	e.axis_value = value
	e.device = -1
	return e
