class_name LoadScreen
extends CanvasLayer
## Load game (from the start screen): the last rest and slots 1-3, each with its thumbnail, the
## act and place, the companions, the money, when it was saved and the time played. Load goes
## on from it (SaveSlots.load_and_go); Delete (numbered slots only) asks first. Mouse, keyboard
## (arrows, Enter) or a pad (stick or d-pad, A); Esc or B goes back.
##   LoadScreen.open(get_tree())

const INK := Color(0.95, 0.88, 0.7)
const DIM := Color(0.7, 0.64, 0.5)
const NAMES := {"main": "Last rest", "slot1": "Slot 1", "slot2": "Slot 2", "slot3": "Slot 3"}

static var current: LoadScreen

var _list: VBoxContainer
var _first: Control


static func open(tree: SceneTree) -> LoadScreen:
	if is_instance_valid(current):
		return current
	var l := LoadScreen.new()
	tree.root.add_child(l)
	current = l
	return l


static func is_open() -> bool:
	return is_instance_valid(current)


func _ready() -> void:
	layer = 118
	process_mode = Node.PROCESS_MODE_ALWAYS
	var shade := ColorRect.new()
	shade.color = Color(0.05, 0.04, 0.03, 0.97)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(shade)
	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.add_child(centre)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	box.custom_minimum_size = Vector2(900, 0)
	centre.add_child(box)
	box.add_child(_label("LOAD GAME", 40, INK, HORIZONTAL_ALIGNMENT_CENTER))
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 10)
	box.add_child(_list)
	var back := Button.new()
	back.text = "Back"
	back.custom_minimum_size = Vector2(160, 40)
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back.pressed.connect(close)
	box.add_child(back)
	box.add_child(_label("Esc or B  back · arrows / stick and Enter / A, or the mouse", 15, DIM, HORIZONTAL_ALIGNMENT_CENTER))
	_build()
	if _first:
		_first.grab_focus.call_deferred()
	else:
		back.grab_focus.call_deferred()


func close() -> void:
	current = null
	queue_free()


func _build() -> void:
	for c in _list.get_children():
		c.queue_free()
	_first = null
	for slot in SaveSlots.SLOTS:
		_list.add_child(_row(slot, SaveSlots.info(slot)))


func _row(slot: String, info: Dictionary) -> Control:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.085, 0.07)
	style.border_color = Color(0.4, 0.32, 0.2)
	style.set_border_width_all(1)
	style.set_content_margin_all(10)
	panel.add_theme_stylebox_override("panel", style)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	panel.add_child(row)
	var thumb := TextureRect.new()
	thumb.custom_minimum_size = Vector2(192, 108)
	thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	if info.get("thumb", "") != "":
		var img := Image.load_from_file(ProjectSettings.globalize_path(info.thumb))
		if img:
			thumb.texture = ImageTexture.create_from_image(img)
	row.add_child(thumb)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_child(_label(NAMES.get(slot, slot), 22, INK))
	if info.exists:
		text.add_child(_label("Act %d · %s · day %d" % [info.act, info.place, info.day], 18, INK))
		text.add_child(_label("With: " + (", ".join(info.party) if not info.party.is_empty() else "nobody"), 16, DIM))
		text.add_child(_label("£%d · %s · %s" % [info.money, SaveSlots.date_text(info.saved_at), SaveSlots.play_time_text(info.play_time)], 16, DIM))
	else:
		text.add_child(_label("Empty", 18, DIM))
	row.add_child(text)
	var buttons := VBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 6)
	row.add_child(buttons)
	if info.exists:
		var load_btn := _button("Load", func() -> void:
			close()
			SaveSlots.load_and_go(get_tree(), slot))
		buttons.add_child(load_btn)
		if _first == null:
			_first = load_btn
		if slot != "main":
			buttons.add_child(_button("Delete", _confirm_delete.bind(slot, buttons)))
	return panel


## Delete asks in its own row: "Delete slot 2?  Yes / No".
func _confirm_delete(slot: String, buttons: VBoxContainer) -> void:
	for c in buttons.get_children():
		c.queue_free()
	buttons.add_child(_label("Delete %s?" % NAMES.get(slot, slot), 16, INK))
	var no := _button("No", _build)
	var yes := _button("Yes, delete", func() -> void:
		SaveSlots.delete(slot)
		_build()
		if _first:
			_first.grab_focus.call_deferred())
	buttons.add_child(no)
	buttons.add_child(yes)
	no.grab_focus.call_deferred()


## Esc or the pad's B: back. Other keys stay here (a number would start an act behind it).
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


func _label(text: String, size: int, color: Color, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = align
	l.add_theme_font_size_override("font_size", Subtitles.size(size))
	l.add_theme_color_override("font_color", color)
	return l


func _button(text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(150, 36)
	b.pressed.connect(on_press)
	return b
