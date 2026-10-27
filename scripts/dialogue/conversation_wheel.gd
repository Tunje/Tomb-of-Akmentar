class_name ConversationWheel
extends CanvasLayer
## The conversation UI, drawn in code: letterbox bars, the subtitle (speaker + line) and a
## Mass Effect-style wheel of 2-6 short choices. Mouse: point at a slot from the wheel's centre
## and click. Keys: 1-6 pick by the number shown. During a line, a click or Space / Enter / E
## skips it (signal `advance`). The full-screen root eats every click while it's up, so nothing
## underneath (main.gd's click-to-capture) sees them.

signal chosen(index: int)
signal advance

const TEXT := Color(0.95, 0.88, 0.7)
const TEXT_DIM := Color(0.75, 0.7, 0.58)
const SPEAKER := Color(0.95, 0.72, 0.35)
const RING := Color(0.1, 0.08, 0.06, 0.72)
const RING_HOVER := Color(0.62, 0.45, 0.2, 0.9)
const EDGE := Color(0.95, 0.8, 0.5, 0.55)
const BAR := Color(0, 0, 0, 0.85)
const BAR_FRACTION := 0.08
const INNER_R := 34.0
const OUTER_R := 86.0
const LABEL_R := 104.0
const DEADZONE := 22.0
const HALF_WEDGE := 26.0  # degrees
## Screen angles of the slots (0 = right, positive = down), named as in the dialogue files.
const SLOT_ANGLES := {"ur": -50.0, "r": 0.0, "lr": 50.0, "ll": 130.0, "l": 180.0, "ul": -130.0}
## Where choices go when the file doesn't say, by how many there are (right side first).
const DEFAULT_SLOTS := {
	1: ["r"], 2: ["ur", "lr"], 3: ["ur", "r", "lr"], 4: ["ur", "lr", "ul", "ll"],
	5: ["ur", "r", "lr", "ul", "ll"], 6: ["ur", "r", "lr", "ul", "l", "ll"],
}

var hovered := -1

var _root: Control
var _speaker: Label
var _line: Label
var _labels: Array[Label] = []
var _slots: Array[String] = []
var _open := false


func _ready() -> void:
	layer = 5
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.draw.connect(_draw)
	_root.gui_input.connect(_on_gui_input)
	add_child(_root)
	_speaker = _label(20, SPEAKER)
	_line = _label(26, TEXT)
	_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_speaker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


func _label(font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 6)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(l)
	return l


# ---------------------------------------------------------------- API

func show_line(speaker_name: String, text: String) -> void:
	_speaker.text = speaker_name
	_line.text = text


func clear_line() -> void:
	_speaker.text = ""
	_line.text = ""


## `labels` in file order; `slots` the matching slot names ("" = default placement).
func show_choices(labels: Array, slots: Array = []) -> void:
	for l in _labels:
		l.queue_free()
	_labels.clear()
	var n := clampi(labels.size(), 1, 6)
	var defaults: Array = DEFAULT_SLOTS[n]
	_slots.clear()
	for i in mini(labels.size(), 6):
		var s: String = slots[i] if i < slots.size() else ""
		if not SLOT_ANGLES.has(s) or s in _slots:
			s = ""
		_slots.append(s)
	# Fill unnamed slots from the defaults that are still free.
	var free := defaults.filter(func(d): return not d in _slots)
	if free.size() < _slots.count(""):
		free = SLOT_ANGLES.keys().filter(func(d): return not d in _slots)
	for i in _slots.size():
		if _slots[i] == "":
			_slots[i] = free.pop_front()
	for i in _slots.size():
		var l := _label(21, TEXT_DIM)
		l.text = "%d  %s" % [i + 1, labels[i]] if _is_right(i) else "%s  %d" % [labels[i], i + 1]
		_labels.append(l)
	hovered = -1
	_open = true
	_layout()


func hide_choices() -> void:
	for l in _labels:
		l.queue_free()
	_labels.clear()
	_slots.clear()
	hovered = -1
	_open = false
	_root.queue_redraw()


func choices_open() -> bool:
	return _open


## Screen point in the middle of slot `i`'s wedge (tests aim the mouse here).
func slot_point(i: int) -> Vector2:
	return _center() + _dir(SLOT_ANGLES[_slots[i]]) * (INNER_R + OUTER_R) * 0.5


# ---------------------------------------------------------------- input

func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_hover_at(event.position)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _open:
			_hover_at(event.position)
			if hovered >= 0:
				chosen.emit(hovered)
		else:
			advance.emit()
		_root.accept_event()


func _input(event: InputEvent) -> void:
	# A pad: the left stick points at a choice (_process), A takes it or moves a line on.
	if event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_A:
		get_viewport().set_input_as_handled()
		if not _open:
			advance.emit()
		elif hovered >= 0:
			chosen.emit(hovered)
		return
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var k: int = event.keycode
	if _open and k >= KEY_1 and k < KEY_1 + _slots.size():
		get_viewport().set_input_as_handled()
		chosen.emit(k - KEY_1)
	elif not _open and k in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER, KEY_E]:
		get_viewport().set_input_as_handled()
		advance.emit()


func _hover_at(p: Vector2) -> void:
	var was := hovered
	hovered = -1
	var v := p - _center()
	if _open and v.length() > DEADZONE:
		var best := 999.0
		var ang := rad_to_deg(v.angle())
		for i in _slots.size():
			var d := absf(angle_difference(deg_to_rad(ang), deg_to_rad(SLOT_ANGLES[_slots[i]])))
			if d < best:
				best = d
				hovered = i
	if hovered != was:
		_layout()


# ---------------------------------------------------------------- drawing

func _process(_delta: float) -> void:
	if _open and Controls.last_pad:
		var v := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		if v.length() > 0.5:  # the last direction held stays picked when the stick comes back
			_hover_at(_center() + v.normalized() * (INNER_R + OUTER_R) * 0.5)
	_layout()


func _center() -> Vector2:
	var s := _root.size
	# Lower middle, but always clear of the subtitle (a long line wraps to three rows).
	var clear := _speaker.position.y - OUTER_R - 34.0 if _speaker.text != "" else s.y
	return Vector2(s.x * 0.5, minf(s.y * 0.66, clear))


func _dir(deg: float) -> Vector2:
	return Vector2.from_angle(deg_to_rad(deg))


func _is_right(i: int) -> bool:
	return cos(deg_to_rad(SLOT_ANGLES[_slots[i]])) > 0.01 or _slots[i] == "r"


func _layout() -> void:
	var s := _root.size
	var bar := s.y * BAR_FRACTION
	var w := minf(s.x * 0.7, 1100.0)
	_line.size = Vector2(w, 0)
	_line.position = Vector2((s.x - w) * 0.5, s.y - bar - 12 - _line.get_minimum_size().y)
	_speaker.size = Vector2(w, 0)
	_speaker.position = Vector2((s.x - w) * 0.5, _line.position.y - 30)
	var c := _center()
	for i in _labels.size():
		var l := _labels[i]
		l.add_theme_color_override("font_color", TEXT if i == hovered else TEXT_DIM)
		var sz := l.get_minimum_size()
		var p := c + _dir(SLOT_ANGLES[_slots[i]]) * LABEL_R
		var x := p.x if _is_right(i) else p.x - sz.x
		if _slots[i] == "r" or _slots[i] == "l":
			x += 8.0 if _is_right(i) else -8.0
		l.position = Vector2(x, p.y - sz.y * 0.5)
	_root.queue_redraw()


func _draw() -> void:
	var s := _root.size
	var bar := s.y * BAR_FRACTION
	_root.draw_rect(Rect2(0, 0, s.x, bar), BAR)
	_root.draw_rect(Rect2(0, s.y - bar, s.x, bar), BAR)
	if not _open:
		return
	var c := _center()
	for i in _slots.size():
		var a := deg_to_rad(SLOT_ANGLES[_slots[i]])
		var h := deg_to_rad(HALF_WEDGE)
		var pts := PackedVector2Array()
		var steps := 12
		for k in steps + 1:
			pts.append(c + Vector2.from_angle(a - h + 2.0 * h * k / steps) * OUTER_R)
		for k in steps + 1:
			pts.append(c + Vector2.from_angle(a + h - 2.0 * h * k / steps) * INNER_R)
		_root.draw_colored_polygon(pts, RING_HOVER if i == hovered else RING)
		pts.append(pts[0])
		_root.draw_polyline(pts, EDGE, 1.5, true)
	_root.draw_circle(c, 5.0, EDGE)
