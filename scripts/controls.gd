class_name Controls
extends RefCounted
## The game's key and mouse bindings, registered in code (shared by every scene).

const KEYS := {
	"move_forward": [KEY_W], "move_back": [KEY_S], "move_left": [KEY_A], "move_right": [KEY_D],
	"sprint": [KEY_SHIFT], "crouch": [KEY_C, KEY_CTRL], "dodge": [KEY_SPACE],
	"reload": [KEY_R], "cover": [KEY_E], "holster": [KEY_X], "journal": [KEY_J], "party_order": [KEY_G],
	"shove": [KEY_F], "weapon_1": [KEY_1], "weapon_2": [KEY_2], "weapon_3": [KEY_3],
	"swap_seat": [KEY_V],  # in a truck: a companion takes the wheel, you take the gun (GunnerSeat)
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
	["Companions: follow / hold", "party_order", "key"], ["Truck: hand a companion the wheel", "swap_seat", "key"],
	["Vehicle: look back (hold)", "crouch", "same"], ["Brawl: punch", "fire", "same"],
	["Brawl: block", "aim", "same"], ["Brawl: shove", "shove", "key"],
]


## A readable name for an action's first key or button ("E", "Shift", "Right mouse").
static func key_name(action: String) -> String:
	if not InputMap.has_action(action):
		return "?"
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
	var k := func(a: String) -> String: return key_name(a)
	return "%s%s%s%s move · %s sprint · %s crouch · %s dodge · %s use / cover (%s+%s vault)" % [k.call("move_forward"),
		k.call("move_left"), k.call("move_back"), k.call("move_right"), k.call("sprint"), k.call("crouch"),
		k.call("dodge"), k.call("cover"), k.call("move_forward"), k.call("cover")] + "\n" \
		+ "%s aim · %s fire · %s reload · %s %s %s guns · %s holster" % [k.call("aim"), k.call("fire"),
		k.call("reload"), k.call("weapon_1"), k.call("weapon_2"), k.call("weapon_3"), k.call("holster")]
