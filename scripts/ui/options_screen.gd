class_name OptionsScreen
extends CanvasLayer
## The options (Settings): sound, controls, picture, and what the game tells you. Opened with O
## from the start screen or a pause (Hud listens), closed with Esc or Back. Every change applies
## at once and is saved to user://settings.cfg. Mouse, or the arrows to move and change, Enter.
##   OptionsScreen.open(get_tree())

const INK := Color(0.95, 0.88, 0.7)
const DIM := Color(0.7, 0.64, 0.5)
const QUALITY_NAMES := ["low", "medium", "high"]

static var current: OptionsScreen

var _first: Control
var _mouse_was := Input.MOUSE_MODE_VISIBLE


static func open(tree: SceneTree) -> OptionsScreen:
	if is_instance_valid(current):
		return current
	var o := OptionsScreen.new()
	tree.root.add_child(o)
	current = o
	return o


static func is_open() -> bool:
	return is_instance_valid(current)


func _ready() -> void:
	layer = 120
	process_mode = Node.PROCESS_MODE_ALWAYS
	_mouse_was = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var shade := ColorRect.new()
	shade.color = Color(0.05, 0.04, 0.03, 0.94)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP  # clicks stay here (a click resumes a paused act)
	add_child(shade)
	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.add_child(centre)
	# An opaque panel: the pause card behind (PAUSED, its keys) showed through the shade.
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.09, 0.075, 0.06)
	style.border_color = Color(0.45, 0.36, 0.22)
	style.set_border_width_all(2)
	style.set_content_margin_all(28)
	panel.add_theme_stylebox_override("panel", style)
	centre.add_child(panel)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(620, 0)
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)
	box.add_child(_label("OPTIONS", 40, INK, HORIZONTAL_ALIGNMENT_CENTER))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 10)
	box.add_child(grid)
	_first = _slider(grid, "Master volume", "master", 0.0, 1.0, 0.05, true)
	_slider(grid, "Effects volume", "effects", 0.0, 1.0, 0.05, true)
	_slider(grid, "Ambience volume", "ambience", 0.0, 1.0, 0.05, true)
	_slider(grid, "Mouse sensitivity", "mouse_sens", 0.3, 2.5, 0.05, false)
	_check(grid, "Invert mouse Y", "invert_y")
	_slider(grid, "Field of view", "fov", 60.0, 90.0, 1.0, false)
	_quality(grid)
	_check(grid, "Fullscreen", "fullscreen")
	_check(grid, "Companions' remarks", "barks")
	_check(grid, "First-time hints", "hints")
	_check(grid, "Controller vibration", "vibration")
	_check(grid, "Aim assist (controller)", "aim_assist")
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 20)
	var keys := Button.new()
	keys.text = "Controls…"
	keys.custom_minimum_size = Vector2(160, 40)
	keys.pressed.connect(func() -> void: ControlsScreen.open(get_tree()))
	var back := Button.new()
	back.text = "Back"
	back.custom_minimum_size = Vector2(160, 40)
	back.pressed.connect(close)
	buttons.add_child(keys)
	buttons.add_child(back)
	box.add_child(buttons)
	box.add_child(_label("Esc  back · arrows and Enter, or the mouse · changes are kept", 16, DIM, HORIZONTAL_ALIGNMENT_CENTER))
	_first.grab_focus.call_deferred()


func close() -> void:
	if ControlsScreen.is_open():
		ControlsScreen.current.close()
	Settings.save()
	Input.mouse_mode = _mouse_was
	current = null
	queue_free()


## Esc closes it here, before a paused act sees it (where Esc would un-pause).
func _input(event: InputEvent) -> void:
	var pad_back: bool = event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_B
	if event.is_action_pressed("ui_cancel") or pad_back:
		get_viewport().set_input_as_handled()
		close()
		return
	# Other keys stop here too (a paused act quits on Q); only the menu's own reach its controls.
	if event is InputEventKey:
		for a in ["ui_up", "ui_down", "ui_left", "ui_right", "ui_accept", "ui_select", "ui_focus_next", "ui_focus_prev"]:
			if event.is_action(a):
				return
		get_viewport().set_input_as_handled()


func _label(text: String, size: int, color: Color, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = align
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _row(grid: GridContainer, name: String) -> void:
	var l := _label(name, 20, INK)
	l.custom_minimum_size = Vector2(240, 0)
	grid.add_child(l)


func _slider(grid: GridContainer, name: String, key: String, lo: float, hi: float, step: float, percent: bool) -> HSlider:
	_row(grid, name)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = float(Settings.value(key))
	s.custom_minimum_size = Vector2(260, 28)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var shown := _label("", 18, DIM)
	shown.custom_minimum_size = Vector2(60, 0)
	var show := func(v: float) -> void:
		shown.text = ("%d%%" % roundi(v * 100.0)) if percent else ("%.2f" % v if step < 1.0 else "%d" % roundi(v))
	show.call(s.value)
	s.value_changed.connect(func(v: float) -> void:
		show.call(v)
		Settings.set_value(key, v, get_tree()))
	row.add_child(s)
	row.add_child(shown)
	grid.add_child(row)
	return s


func _check(grid: GridContainer, name: String, key: String) -> CheckButton:
	_row(grid, name)
	var c := CheckButton.new()
	c.button_pressed = bool(Settings.value(key))
	c.text = "On" if c.button_pressed else "Off"
	c.toggled.connect(func(on: bool) -> void:
		c.text = "On" if on else "Off"
		Settings.set_value(key, on, get_tree()))
	grid.add_child(c)
	return c


func _quality(grid: GridContainer) -> void:
	_row(grid, "Graphics")
	var o := OptionButton.new()
	for q in QUALITY_NAMES:
		o.add_item({"low": "Low (no torch shadows, 75% scale)", "medium": "Medium (near shadows, FXAA)",
			"high": "High (shadows, MSAA)"}[q])
	o.selected = maxi(QUALITY_NAMES.find(str(Settings.value("quality"))), 0)
	o.item_selected.connect(func(i: int) -> void: Settings.set_value("quality", QUALITY_NAMES[i], get_tree()))
	grid.add_child(o)
