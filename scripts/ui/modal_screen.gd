class_name ModalScreen
extends CanvasLayer
## Base for full-screen 2D screens drawn in code (journal, clue card, route map, site draft,
## epilogue): while one is open the player's controls are off and the mouse is visible; close()
## puts both back and emits `closed`. Subclasses override _draw_screen, _on_key and _on_click,
## and use the text helpers here. ActionMenu.ui_open() counts these too.

signal closed

const TEXT := Color(0.95, 0.88, 0.7)
const DIM := Color(0.62, 0.58, 0.5)
const GOLD := Color(0.95, 0.72, 0.35)
const RED := Color(1, 0.55, 0.4)
const INK := Color(0.2, 0.14, 0.08)
const PAPER := Color(0.86, 0.78, 0.6)
const PANEL := Color(0.07, 0.06, 0.05, 0.9)

static var open_count := 0

var player: Node
var root: Control
var font: Font
var t := 0.0   # seconds since it opened
var mouse := Vector2.ZERO

var _old_mouse := Input.MOUSE_MODE_VISIBLE
var _closed := false


func _ready() -> void:
	layer = 7
	open_count += 1
	if player and "controls_enabled" in player:
		player.controls_enabled = false
	_old_mouse = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	font = ThemeDB.fallback_font
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.draw.connect(func() -> void: _draw_screen())
	root.gui_input.connect(_gui)
	add_child(root)
	_opened()


func close() -> void:
	if _closed:
		return
	_closed = true
	open_count -= 1
	if player and "controls_enabled" in player and not ActionMenu.ui_open():
		player.controls_enabled = true
	Input.mouse_mode = _old_mouse
	closed.emit()
	queue_free()


func is_closed() -> bool:
	return _closed


# ---------------------------------------------------------------- for subclasses

func _opened() -> void:
	pass


func _draw_screen() -> void:
	pass


## Return true when the key was used.
func _on_key(_key: int) -> bool:
	return false


func _on_click(_at: Vector2) -> void:
	pass


# ---------------------------------------------------------------- plumbing

func _process(delta: float) -> void:
	t += delta
	root.queue_redraw()


func _gui(e: InputEvent) -> void:
	if e is InputEventMouseMotion:
		mouse = e.position
	elif e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		mouse = e.position
		root.accept_event()
		_on_click(e.position)


func _input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo and not _closed and _on_key(e.keycode):
		get_viewport().set_input_as_handled()


# ---------------------------------------------------------------- drawing helpers

func text(s: String, at: Vector2, size: int, color: Color, align := HORIZONTAL_ALIGNMENT_LEFT, outline := true) -> void:
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var p := at
	if align == HORIZONTAL_ALIGNMENT_CENTER:
		p.x -= w * 0.5
	elif align == HORIZONTAL_ALIGNMENT_RIGHT:
		p.x -= w
	if outline:
		root.draw_string_outline(font, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 5, Color(0, 0, 0, 0.75 * color.a))
	root.draw_string(font, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


## Word-wrapped text in `width`; returns the height used.
func para(s: String, at: Vector2, width: float, size: int, color: Color, align := HORIZONTAL_ALIGNMENT_LEFT) -> float:
	root.draw_multiline_string(font, at, s, align, width, size, -1, color)
	return font.get_multiline_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, width, size).y


func panel(r: Rect2, fill := PANEL, edge := Color(0.95, 0.72, 0.35, 0.5)) -> void:
	root.draw_rect(r, fill)
	root.draw_rect(r, edge, false, 1.5)


func dim_background(alpha := 0.75) -> void:
	root.draw_rect(Rect2(Vector2.ZERO, root.size), Color(0.02, 0.015, 0.01, alpha * clampf(t / 0.25, 0.0, 1.0)))
