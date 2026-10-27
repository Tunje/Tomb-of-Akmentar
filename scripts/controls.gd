class_name Controls
extends RefCounted
## The game's key and mouse bindings, registered in code (shared by every scene).

const KEYS := {
	"move_forward": [KEY_W], "move_back": [KEY_S], "move_left": [KEY_A], "move_right": [KEY_D],
	"sprint": [KEY_SHIFT], "crouch": [KEY_C, KEY_CTRL], "dodge": [KEY_SPACE],
	"reload": [KEY_R], "cover": [KEY_E], "holster": [KEY_X], "journal": [KEY_J], "party_order": [KEY_G], "party_focus": [KEY_T],
	"shove": [KEY_F], "weapon_1": [KEY_1], "weapon_2": [KEY_2], "weapon_3": [KEY_3],
	"swap_seat": [KEY_V],  # in a truck: a companion takes the wheel, you take the gun (GunnerSeat)
	"objective": [KEY_TAB],  # held: the objective line in full (Objective)
}
const MOUSE := {
	"fire": [MOUSE_BUTTON_LEFT], "aim": [MOUSE_BUTTON_RIGHT],
	"weapon_next": [MOUSE_BUTTON_WHEEL_DOWN], "weapon_prev": [MOUSE_BUTTON_WHEEL_UP],
}


static func setup() -> void:
	for action in KEYS:
		if InputMap.has_action(action):
			continue  # already registered (scene reload)
		InputMap.add_action(action)
		for k in KEYS[action]:
			var e := InputEventKey.new()
			e.physical_keycode = k
			InputMap.action_add_event(action, e)
	for action in MOUSE:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for b in MOUSE[action]:
			var e := InputEventMouseButton.new()
			e.button_index = b
			InputMap.action_add_event(action, e)
	_setup_pad()


# ---------------------------------------------------------------- the gamepad (Xbox layout)

## Pad bindings, added once beside the keys and mouse: a button (int) or an axis [axis, sign].
## Left stick moves, right stick looks (look_*), RT fires, LT aims; A dodge, B crouch, X use /
## cover, Y reload (and the brawl's shove: unarmed, nothing to reload), LB / RB guns, the d-pad
## holster / orders / journal / the truck's wheel swap, L3 sprint (Player latches it), Start
## pauses (ui_cancel), Back opens the options when paused. pad_throttle / pad_brake are the
## triggers alone: a truck or horse speeds up on RT and slows on LT, not on a mouse click.
const PAD := {
	"move_forward": [[JOY_AXIS_LEFT_Y, -1]], "move_back": [[JOY_AXIS_LEFT_Y, 1]],
	"move_left": [[JOY_AXIS_LEFT_X, -1]], "move_right": [[JOY_AXIS_LEFT_X, 1]],
	"look_left": [[JOY_AXIS_RIGHT_X, -1]], "look_right": [[JOY_AXIS_RIGHT_X, 1]],
	"look_up": [[JOY_AXIS_RIGHT_Y, -1]], "look_down": [[JOY_AXIS_RIGHT_Y, 1]],
	"fire": [[JOY_AXIS_TRIGGER_RIGHT, 1]], "aim": [[JOY_AXIS_TRIGGER_LEFT, 1]],
	"pad_throttle": [[JOY_AXIS_TRIGGER_RIGHT, 1]], "pad_brake": [[JOY_AXIS_TRIGGER_LEFT, 1]],
	"dodge": [JOY_BUTTON_A], "crouch": [JOY_BUTTON_B], "cover": [JOY_BUTTON_X], "reload": [JOY_BUTTON_Y],
	"shove": [JOY_BUTTON_Y], "weapon_next": [JOY_BUTTON_RIGHT_SHOULDER], "weapon_prev": [JOY_BUTTON_LEFT_SHOULDER],
	"holster": [JOY_BUTTON_DPAD_DOWN], "party_order": [JOY_BUTTON_DPAD_LEFT], "journal": [JOY_BUTTON_DPAD_UP],
	"swap_seat": [JOY_BUTTON_DPAD_RIGHT], "sprint": [JOY_BUTTON_LEFT_STICK], "objective": [JOY_BUTTON_BACK],
}
const STICK_DEADZONE := 0.2
const TRIGGER_DEADZONE := 0.3
const BUTTON_NAMES := {
	JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "X", JOY_BUTTON_Y: "Y",
	JOY_BUTTON_LEFT_SHOULDER: "LB", JOY_BUTTON_RIGHT_SHOULDER: "RB", JOY_BUTTON_LEFT_STICK: "L3",
	JOY_BUTTON_RIGHT_STICK: "R3", JOY_BUTTON_START: "Start", JOY_BUTTON_BACK: "Back",
	JOY_BUTTON_DPAD_UP: "D-pad up", JOY_BUTTON_DPAD_DOWN: "D-pad down", JOY_BUTTON_DPAD_LEFT: "D-pad left",
	JOY_BUTTON_DPAD_RIGHT: "D-pad right",
}

## True while the last input came from a pad (Hud watches): key names then show pad buttons.
static var last_pad := false
static var _pad_done := false


static func _setup_pad() -> void:
	if _pad_done:
		return
	_pad_done = true
	for action in PAD:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		var stick := false
		for b in PAD[action]:
			if b is Array:
				var m := InputEventJoypadMotion.new()
				m.device = -1  # any pad
				m.axis = b[0]
				m.axis_value = float(b[1])
				InputMap.action_add_event(action, m)
				stick = b[0] in [JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y, JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y]
				InputMap.action_set_deadzone(action, STICK_DEADZONE if stick else TRIGGER_DEADZONE)
			else:
				var e := InputEventJoypadButton.new()
				e.device = -1
				e.button_index = b
				InputMap.action_add_event(action, e)
	# Start pauses; B is crouch in play, so it comes off ui_cancel (menus take B back themselves).
	for e in InputMap.action_get_events("ui_cancel"):
		if e is InputEventJoypadButton:
			InputMap.action_erase_event("ui_cancel", e)
	var start := InputEventJoypadButton.new()
	start.device = -1
	start.button_index = JOY_BUTTON_START
	InputMap.action_add_event("ui_cancel", start)
	# Menus on a pad: A confirms, the d-pad moves (if the project's defaults lack them).
	for pair in [["ui_accept", JOY_BUTTON_A], ["ui_up", JOY_BUTTON_DPAD_UP], ["ui_down", JOY_BUTTON_DPAD_DOWN],
			["ui_left", JOY_BUTTON_DPAD_LEFT], ["ui_right", JOY_BUTTON_DPAD_RIGHT]]:
		var has := false
		for e in InputMap.action_get_events(pair[0]):
			has = has or (e is InputEventJoypadButton and e.button_index == pair[1])
		if not has:
			var b := InputEventJoypadButton.new()
			b.device = -1
			b.button_index = pair[1]
			InputMap.action_add_event(pair[0], b)


## The pad's name for an action's first pad binding ("A", "RT", "Left stick"), or "" if none.
static func pad_name(action: String) -> String:
	if not InputMap.has_action(action):
		return ""
	for e in InputMap.action_get_events(action):
		if e is InputEventJoypadButton:
			return BUTTON_NAMES.get(e.button_index, "Button %d" % e.button_index)
		if e is InputEventJoypadMotion:
			return {JOY_AXIS_TRIGGER_LEFT: "LT", JOY_AXIS_TRIGGER_RIGHT: "RT", JOY_AXIS_LEFT_X: "Left stick",
				JOY_AXIS_LEFT_Y: "Left stick", JOY_AXIS_RIGHT_X: "Right stick", JOY_AXIS_RIGHT_Y: "Right stick"}.get(e.axis, "Stick")
	return ""


## Notes the device of `event` for key_name (keyboard and mouse vs pad). A stick or trigger counts
## past half way, the mouse only when it really moves.
static func note_device(event: InputEvent) -> void:
	if event is InputEventJoypadButton and event.pressed:
		last_pad = true
	elif event is InputEventJoypadMotion and absf(event.axis_value) > 0.5:
		last_pad = true
	elif event is InputEventKey and event.pressed:
		last_pad = false
	elif event is InputEventMouseButton and event.pressed:
		last_pad = false
	elif event is InputEventMouseMotion and event.relative.length() > 4.0:
		last_pad = false


# ---------------------------------------------------------------- the controls page, rebinding

## The controls page's rows, in order: [label, action, how it's bound]. "key" rows can be rebound;
## "mouse" rows show their button; "same" rows share another action's key (shown, not rebound).
const LIST := [
	["Move forward", "move_forward", "key"], ["Move back", "move_back", "key"],
	["Move left", "move_left", "key"], ["Move right", "move_right", "key"],
	["Sprint", "sprint", "key"], ["Crouch", "crouch", "key"], ["Dodge roll", "dodge", "key"],
	["Aim", "aim", "mouse"], ["Fire", "fire", "mouse"], ["Reload", "reload", "key"],
	["Holster or draw", "holster", "key"], ["Gun 1", "weapon_1", "key"], ["Gun 2", "weapon_2", "key"],
	["Gun 3", "weapon_3", "key"], ["Use / take cover", "cover", "key"],
	["Vault (in cover)", "cover", "vault"], ["Journal", "journal", "key"],
	["Companions: follow / hold (hold: focus my target)", "party_order", "key"],
	["Companions: focus my target", "party_focus", "key"], ["Truck: hand a companion the wheel", "swap_seat", "key"],
	["Vehicle: look back (hold)", "crouch", "same"], ["Brawl: punch", "fire", "same"],
	["Brawl: block", "aim", "same"], ["Brawl: shove", "shove", "key"],
	["Show the objective (hold)", "objective", "key"],
]


## A readable name for an action's first key or button ("E", "Shift", "Right mouse").
static func key_name(action: String, allow_pad := true) -> String:
	if not InputMap.has_action(action):
		return "?"
	if last_pad and allow_pad:
		var p := pad_name(action)
		if p != "":
			return p
	for e in InputMap.action_get_events(action):
		if e is InputEventKey:
			return OS.get_keycode_string(e.physical_keycode if e.physical_keycode != 0 else e.keycode)
	for e in InputMap.action_get_events(action):
		if e is InputEventMouseButton:
			return {MOUSE_BUTTON_LEFT: "Left mouse", MOUSE_BUTTON_RIGHT: "Right mouse",
				MOUSE_BUTTON_WHEEL_UP: "Wheel up", MOUSE_BUTTON_WHEEL_DOWN: "Wheel down"}.get(e.button_index, "Mouse")
	return "-"


## Every key action's physical keys now: {action: [keycode, ...]} (what settings.cfg keeps).
static func bindings() -> Dictionary:
	var out := {}
	for action in KEYS:
		out[action] = _keys_of(action)
	return out


static func _keys_of(action: String) -> Array:
	var ks: Array = []
	if InputMap.has_action(action):
		for e in InputMap.action_get_events(action):
			if e is InputEventKey:
				ks.append(int(e.physical_keycode))
	return ks


static func _set_keys(action: String, keys: Array) -> void:
	for e in InputMap.action_get_events(action):
		if e is InputEventKey:
			InputMap.action_erase_event(action, e)
	for k in keys:
		var e := InputEventKey.new()
		e.physical_keycode = int(k)
		InputMap.action_add_event(action, e)


## `action`'s first key becomes `key`. Another action that had it takes `action`'s old first key
## (a swap: nothing ends up unbound). Its other keys (Crouch's Ctrl) stay.
static func rebind(action: String, key: int) -> void:
	setup()
	var mine := _keys_of(action)
	var old: int = mine[0] if not mine.is_empty() else 0
	if old == key:
		return
	for other in KEYS:
		if other == action:
			continue
		var theirs := _keys_of(other)
		var i := theirs.find(key)
		if i >= 0:
			if old != 0 and not theirs.has(old):
				theirs[i] = old
			else:
				theirs.remove_at(i)
			_set_keys(other, theirs)
	mine.erase(key)
	if not mine.is_empty():
		mine[0] = key
	else:
		mine.append(key)
	_set_keys(action, mine)


## Keys as settings.cfg kept them (unknown actions skipped).
static func apply(saved: Dictionary) -> void:
	setup()
	for action in saved:
		if KEYS.has(action) and saved[action] is Array and not (saved[action] as Array).is_empty():
			_set_keys(action, saved[action])


static func reset() -> void:
	setup()
	for action in KEYS:
		_set_keys(action, KEYS[action])


## The start screen's key help, from the bindings now (two lines).
static func help_text() -> String:
	setup()
	if last_pad:
		var p := func(a: String) -> String: return pad_name(a)
		return "Left stick move · Right stick look · %s sprint · %s crouch · %s dodge · %s use / cover" % [p.call("sprint"),
			p.call("crouch"), p.call("dodge"), p.call("cover")] + "\n" + "%s aim · %s fire · %s reload · %s %s guns · %s holster" % [
			p.call("aim"), p.call("fire"), p.call("reload"), p.call("weapon_prev"), p.call("weapon_next"), p.call("holster")]
	var k := func(a: String) -> String: return key_name(a)
	return "%s%s%s%s move · %s sprint · %s crouch · %s dodge · %s use / cover (%s+%s vault)" % [k.call("move_forward"),
		k.call("move_left"), k.call("move_back"), k.call("move_right"), k.call("sprint"), k.call("crouch"),
		k.call("dodge"), k.call("cover"), k.call("move_forward"), k.call("cover")] + "\n" \
		+ "%s aim · %s fire · %s reload · %s %s %s guns · %s holster" % [k.call("aim"), k.call("fire"),
		k.call("reload"), k.call("weapon_1"), k.call("weapon_2"), k.call("weapon_3"), k.call("holster")]


## `text` with each "{action}" token as that action's key now ("{dodge}: roll" -> "Space: roll",
## or "K: roll" once rebound), so hints, toasts and prompts follow the controls page. Tokens that
## aren't actions stay as they are.
static func fill(text: String) -> String:
	if not "{" in text:
		return text
	setup()
	var re := RegEx.create_from_string("\\{([a-z_0-9]+)\\}")
	var out := text
	for m in re.search_all(text):
		var action := m.get_string(1)
		if InputMap.has_action(action):
			out = out.replace(m.get_string(), key_name(action))
	return out


# ---------------------------------------------------------------- rumble

## Rumble pulses so far (tests read these: no pad has to be plugged in to check the calls).
static var rumble_count := 0
static var last_rumble: Array = []


## A short pulse on every connected pad, only while the pad is the device in use and the options
## allow it ("Controller vibration"). weak / strong: the two motors, 0..1. True if it rumbled.
static func rumble(weak: float, strong: float, secs: float) -> bool:
	if not last_pad or not Settings.value("vibration"):
		return false
	rumble_count += 1
	last_rumble = [weak, strong, secs]
	for d in Input.get_connected_joypads():
		Input.start_joy_vibration(d, clampf(weak, 0.0, 1.0), clampf(strong, 0.0, 1.0), secs)
	return true


## rumble() for something at `pos` in the world: full at the camera, nothing past `reach` m.
static func rumble_at(tree: SceneTree, pos: Vector3, weak: float, strong: float, secs: float, reach := 25.0) -> bool:
	var cam := tree.root.get_camera_3d() if tree else null
	if cam == null:
		return false
	var k := 1.0 - cam.global_position.distance_to(pos) / reach
	return k > 0.05 and rumble(weak * k, strong * k, secs)
