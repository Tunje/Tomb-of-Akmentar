class_name OptionsScreen
extends CanvasLayer
## The options (Settings): sound, controls, picture, and what the game tells you; a second page
## for accessibility (subtitles, text size, hold or toggle, camera shake, the crosshair). Opened
## with O (or the pad's Back) from the start screen or a pause (Hud listens), closed with Esc, B
## or Back. Every change applies at once and is saved to user://settings.cfg. Mouse, or the
## arrows to move and change, Enter.
##   OptionsScreen.open(get_tree())

const INK := Color(0.95, 0.88, 0.7)
const DIM := Color(0.7, 0.64, 0.5)

static var current: OptionsScreen        # the main page
static var accessibility: OptionsScreen  # the accessibility page, over it

var page := "main"
var _first: Control
var _mouse_was := Input.MOUSE_MODE_VISIBLE


static func open(tree: SceneTree) -> OptionsScreen:
	if is_instance_valid(current):
		return current
	var o := OptionsScreen.new()
	tree.root.add_child(o)
	current = o
	return o


static func open_accessibility(tree: SceneTree) -> OptionsScreen:
	if is_instance_valid(accessibility):
		return accessibility
	var o := OptionsScreen.new()
	o.page = "accessibility"
	tree.root.add_child(o)
	accessibility = o
	return o


static func is_open() -> bool:
	return is_instance_valid(current)


func _ready() -> void:
	layer = 120 if page == "main" else 122
	process_mode = Node.PROCESS_MODE_ALWAYS
	_mouse_was = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var shade := ColorRect.new()
	shade.color = Color(0.05, 0.04, 0.03, 0.94 if page == "main" else 1.0)
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
	box.custom_minimum_size = Vector2(660, 0)
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)
	box.add_child(_label("OPTIONS" if page == "main" else "ACCESSIBILITY", 40, INK, HORIZONTAL_ALIGNMENT_CENTER))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 10)
	box.add_child(grid)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 20)
	if page == "main":
		_first = _slider(grid, "Master volume", "master", 0.0, 1.0, 0.05, true)
		_slider(grid, "Effects volume", "effects", 0.0, 1.0, 0.05, true)
		_slider(grid, "Ambience volume", "ambience", 0.0, 1.0, 0.05, true)
		_slider(grid, "Music volume", "music", 0.0, 1.0, 0.05, true)
		_slider(grid, "Mouse sensitivity", "mouse_sens", 0.3, 2.5, 0.05, false)
		_check(grid, "Invert mouse Y", "invert_y")
		_slider(grid, "Field of view", "fov", 60.0, 90.0, 1.0, false)
		_choice(grid, "Graphics", "quality", ["low", "medium", "high"],
			["Low (no torch shadows, 75% scale)", "Medium (near shadows, FXAA)", "High (shadows, MSAA)"])
		_check(grid, "Fullscreen", "fullscreen")
		_check(grid, "Companions' remarks", "barks")
		_check(grid, "First-time hints", "hints")
		_check(grid, "Controller vibration", "vibration")
		_check(grid, "Aim assist (controller)", "aim_assist")
		_row(grid, "Difficulty")  # this game's (saved with it); changeable mid-game
		var diff := OptionButton.new()
		for id in Difficulty.IDS:
			diff.add_item(Difficulty.name_of(id))
		diff.selected = maxi(Difficulty.IDS.find(Difficulty.level()), 0)
		diff.tooltip_text = "
".join(Difficulty.IDS.map(func(id): return "%s: %s" % [Difficulty.name_of(id), Difficulty.BLURBS[id]]))
		diff.item_selected.connect(func(i: int) -> void: Difficulty.set_level(Difficulty.IDS[i]))
		grid.add_child(diff)
		buttons.add_child(_button("Controls…", func() -> void: ControlsScreen.open(get_tree())))
		buttons.add_child(_button("Accessibility…", func() -> void: OptionsScreen.open_accessibility(get_tree())))
	else:
		_first = _check(grid, "Subtitles", "subtitles")
		_choice(grid, "Text size", "text_size", ["S", "M", "L", "XL"], ["Small", "Medium", "Large", "Extra large"])
		_slider(grid, "Subtitle background", "subtitle_bg", 0.0, 1.0, 0.05, true)
		var modes := ["hold", "toggle"]
		_choice(grid, "Aim", "aim_mode", modes, ["Hold", "Toggle"])
		_choice(grid, "Sprint", "sprint_mode", ["auto", "hold", "toggle"], ["Hold (toggle on a pad)", "Hold", "Toggle"])
		_choice(grid, "Crouch", "crouch_mode", modes, ["Hold", "Toggle"])
		_slider(grid, "Camera shake", "shake", 0.0, 1.0, 0.05, true)
		_choice(grid, "Crosshair", "crosshair", ["normal", "bold", "large"], ["Normal", "Bold", "Large"])
		_choice(grid, "Crosshair colour", "crosshair_color", ["white", "yellow", "cyan"], ["White", "Yellow", "Cyan"])
		_check(grid, "Show objective", "show_objective")
		_check(grid, "Show markers", "show_markers")
	buttons.add_child(_button("Back", close))
	box.add_child(buttons)
	box.add_child(_label("Esc  back · arrows and Enter, or the mouse · changes are kept", 16, DIM, HORIZONTAL_ALIGNMENT_CENTER))
	_first.grab_focus.call_deferred()


func close() -> void:
	if page == "main":
		if ControlsScreen.is_open():
			ControlsScreen.current.close()
		if is_instance_valid(accessibility):
			accessibility.close()
		Input.mouse_mode = _mouse_was
		current = null
	else:
		accessibility = null
	Settings.save()
	queue_free()


## Esc (or the pad's B) closes the top page here, before a paused act sees it (where Esc would
## un-pause). The accessibility page sits over the main one and takes it first.
func _input(event: InputEvent) -> void:
	if page == "main" and (is_instance_valid(accessibility) or ControlsScreen.is_open()):
		return  # the page on top has it
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


func _button(text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(160, 40)
	b.pressed.connect(on_press)
	return b


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


## A choice among `values` (shown as `labels`), kept as the value.
func _choice(grid: GridContainer, name: String, key: String, values: Array, labels: Array) -> OptionButton:
	_row(grid, name)
	var o := OptionButton.new()
	for l in labels:
		o.add_item(str(l))
	o.selected = maxi(values.find(str(Settings.value(key))), 0)
	o.item_selected.connect(func(i: int) -> void: Settings.set_value(key, values[i], get_tree()))
	grid.add_child(o)
	return o
