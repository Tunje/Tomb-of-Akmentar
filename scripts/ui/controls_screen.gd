class_name ControlsScreen
extends CanvasLayer
## The controls page (from the options): every action and its key. Click a key (or Enter on it),
## then press the new one: Esc cancels, a key another action had swaps the two. Mouse buttons and
## shared keys are shown, not rebound. Saved with the options (settings.cfg "keys").
##   ControlsScreen.open(get_tree())

const INK := Color(0.95, 0.88, 0.7)
const DIM := Color(0.7, 0.64, 0.5)

static var current: ControlsScreen

var _buttons := {}        # row index -> Button (key rows)
var _shared := {}         # row index -> Label (mouse and shared rows)
var _waiting := -1        # the row listening for a key, or -1
var _note: Label


static func open(tree: SceneTree) -> ControlsScreen:
	if is_instance_valid(current):
		return current
	var c := ControlsScreen.new()
	tree.root.add_child(c)
	current = c
	return c


static func is_open() -> bool:
	return is_instance_valid(current)


func _ready() -> void:
	layer = 121
	process_mode = Node.PROCESS_MODE_ALWAYS
	Controls.setup()
	var shade := ColorRect.new()
	shade.color = Color(0.05, 0.04, 0.03, 1.0)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(shade)
	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.add_child(centre)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(640, 0)
	box.add_theme_constant_override("separation", 12)
	centre.add_child(box)
	box.add_child(_label("CONTROLS", 40, INK, HORIZONTAL_ALIGNMENT_CENTER))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(640, 560)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 6)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(grid)
	var first: Control = null
	for i in Controls.LIST.size():
		var row: Array = Controls.LIST[i]
		var l := _label(str(row[0]), 19, INK)
		l.custom_minimum_size = Vector2(340, 0)
		grid.add_child(l)
		if row[2] == "key":
			var b := Button.new()
			b.custom_minimum_size = Vector2(200, 34)
			b.pressed.connect(_listen.bind(i))
			grid.add_child(b)
			_buttons[i] = b
			if first == null:
				first = b
		else:
			var v := _label("", 19, DIM)
			v.custom_minimum_size = Vector2(200, 34)
			v.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			grid.add_child(v)
			_shared[i] = v
	_note = _label("", 16, DIM, HORIZONTAL_ALIGNMENT_CENTER)
	box.add_child(_note)
	var row2 := HBoxContainer.new()
	row2.alignment = BoxContainer.ALIGNMENT_CENTER
	row2.add_theme_constant_override("separation", 20)
	var reset := Button.new()
	reset.text = "Reset to defaults"
	reset.custom_minimum_size = Vector2(200, 40)
	reset.pressed.connect(func() -> void:
		Controls.reset()
		Settings.set_value("keys", {}, get_tree())
		_refresh("Back to the default keys."))
	var back := Button.new()
	back.text = "Back"
	back.custom_minimum_size = Vector2(160, 40)
	back.pressed.connect(close)
	row2.add_child(reset)
	row2.add_child(back)
	box.add_child(row2)
	box.add_child(_label("Click a key (or Enter on it), then press the new one · Esc cancels · Esc again goes back", 15, DIM, HORIZONTAL_ALIGNMENT_CENTER))
	_refresh("")
	if first:
		first.grab_focus.call_deferred()


func close() -> void:
	current = null
	queue_free()


func _refresh(note: String) -> void:
	for i in _buttons:
		(_buttons[i] as Button).text = Controls.key_name(Controls.LIST[i][1])
	for i in _shared:
		var row: Array = Controls.LIST[i]
		var name := Controls.key_name(row[1])
		(_shared[i] as Label).text = {"mouse": name, "vault": Controls.key_name("move_forward") + " + " + name,
			"same": name + "  (as " + _label_of(row[1]) + ")"}.get(row[2], name)
	_note.text = note


func _label_of(action: String) -> String:
	for row: Array in Controls.LIST:
		if row[1] == action and row[2] in ["key", "mouse"]:
			return str(row[0])
	return action


func _listen(i: int) -> void:
	_waiting = i
	(_buttons[i] as Button).text = "Press a key…"
	_note.text = "Press the new key for %s (Esc cancels)." % Controls.LIST[i][0]


## While listening, the next key is the binding; otherwise Esc goes back. Every key stops here
## (a paused act quits on Q).
func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		if event is InputEventKey:
			get_viewport().set_input_as_handled()
		return
	var k := event as InputEventKey
	if _waiting >= 0:
		get_viewport().set_input_as_handled()
		var i := _waiting
		_waiting = -1
		if k.physical_keycode == KEY_ESCAPE:
			_refresh("Unchanged.")
			return
		var action: String = Controls.LIST[i][1]
		var before := Controls.bindings()
		Controls.rebind(action, int(k.physical_keycode))
		Settings.set_value("keys", Controls.bindings(), get_tree())
		var swapped := ""
		for other in before:
			if other != action and before[other] != Controls.bindings()[other]:
				swapped = " It was %s's: that now has %s." % [_label_of(other), Controls.key_name(other)]
		_refresh("%s is now %s.%s" % [Controls.LIST[i][0], Controls.key_name(action), swapped])
		(_buttons[i] as Button).grab_focus()
		return
	if k.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		close()
		return
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
