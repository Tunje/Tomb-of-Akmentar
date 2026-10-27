class_name SavePrompt
extends CanvasLayer
## After a rest (a bed, a campfire): "Saved as your last rest", and the choice to keep a copy in
## a numbered slot as well. Done is the default (Enter, A, Esc or B: one press and you're back);
## a slot button copies the last rest there (SaveSlots.copy), showing what it would replace.
## Test runs skip it (bots rest without a prompt).
##   SavePrompt.after_rest(self, hud)    # where an act used to toast "Game saved"

const INK := Color(0.95, 0.88, 0.7)
const DIM := Color(0.7, 0.64, 0.5)

static var current: SavePrompt

var _was_paused := false
var _mouse_was := Input.MOUSE_MODE_VISIBLE
var _note: Label


static func after_rest(parent: Node, hud: Hud) -> void:
	if hud:
		hud.toast("Game saved")
	if not OS.get_cmdline_user_args().is_empty() or is_instance_valid(current):
		return
	var p := SavePrompt.new()
	parent.get_tree().root.add_child(p)
	current = p


static func is_open() -> bool:
	return is_instance_valid(current)


func _ready() -> void:
	layer = 115
	process_mode = Node.PROCESS_MODE_ALWAYS
	_was_paused = get_tree().paused
	get_tree().paused = true
	_mouse_was = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(centre)
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.09, 0.075, 0.06, 0.97)
	style.border_color = Color(0.45, 0.36, 0.22)
	style.set_border_width_all(2)
	style.set_content_margin_all(24)
	panel.add_theme_stylebox_override("panel", style)
	centre.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	box.custom_minimum_size = Vector2(520, 0)
	panel.add_child(box)
	box.add_child(_label("Rested. Saved as your last rest.", 24, INK))
	box.add_child(_label("Continue, or a death, picks up from here. Keep a copy as well?", 17, DIM))
	var done := _button("Done", close)
	box.add_child(done)
	for i in 3:
		var slot := "slot%d" % (i + 1)
		var info := SaveSlots.info(slot)
		var was := "empty" if not info.exists else "Act %d, %s (%s)" % [info.act, info.place, SaveSlots.date_text(info.saved_at)]
		box.add_child(_button("Keep a copy in slot %d  ·  now: %s" % [i + 1, was], _keep.bind(slot, i + 1)))
	_note = _label("", 16, DIM)
	box.add_child(_note)
	done.grab_focus.call_deferred()


func _keep(slot: String, n: int) -> void:
	if SaveSlots.copy("main", slot):
		_note.text = "Kept in slot %d." % n
		get_tree().create_timer(0.8, true, false, true).timeout.connect(close)
	else:
		_note.text = "Couldn't write slot %d." % n


func close() -> void:
	if not is_instance_valid(self) or is_queued_for_deletion():
		return
	get_tree().paused = _was_paused
	Input.mouse_mode = _mouse_was
	current = null
	queue_free()


## Esc or the pad's B: Done. Other keys stay here (the act behind is paused).
func _input(event: InputEvent) -> void:
	var back: bool = event.is_action_pressed("ui_cancel") or (event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_B)
	if back:
		get_viewport().set_input_as_handled()
		close()
		return
	if event is InputEventKey:
		for a in ["ui_up", "ui_down", "ui_left", "ui_right", "ui_accept", "ui_select", "ui_focus_next", "ui_focus_prev"]:
			if event.is_action(a):
				return
		get_viewport().set_input_as_handled()


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", Subtitles.size(size))
	l.add_theme_color_override("font_color", color)
	return l


func _button(text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(0, 38)
	b.pressed.connect(on_press)
	return b
