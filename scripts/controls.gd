class_name Controls
extends RefCounted
## The game's key and mouse bindings, registered in code (shared by every scene).

const KEYS := {
	"move_forward": [KEY_W], "move_back": [KEY_S], "move_left": [KEY_A], "move_right": [KEY_D],
	"sprint": [KEY_SHIFT], "crouch": [KEY_C, KEY_CTRL], "dodge": [KEY_SPACE],
	"reload": [KEY_R], "cover": [KEY_E], "holster": [KEY_X], "journal": [KEY_J], "party_order": [KEY_G],
	"shove": [KEY_F], "weapon_1": [KEY_1], "weapon_2": [KEY_2], "weapon_3": [KEY_3],
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
