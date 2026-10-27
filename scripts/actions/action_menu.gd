class_name ActionMenu
extends CanvasLayer
## The list of things to do at a location, drawn in code: title, "Day N · actions left" with
## pips, one row per action with its cost, greyed when locked or too costly (the reason on the
## right), and a Leave row. Mouse click or number keys; Esc / Q / the last number leaves.
## Picking a greyed row doesn't run it: the reason flashes instead ("No time left today").

signal picked(index: int)
signal closed

const TEXT := Color(0.95, 0.88, 0.7)
const GREY := Color(0.55, 0.52, 0.46)
const GOLD := Color(0.95, 0.72, 0.35)
const PANEL := Color(0.07, 0.06, 0.05, 0.88)
const HOVER := Color(0.62, 0.45, 0.2, 0.55)
const WIDTH := 640.0
const ROW_H := 40.0
const HEAD_H := 96.0

## The menu open now, or null.
static var current: ActionMenu

var title := ""
var rows: Array = []     # {"label", "cost", "enabled", "reason"}
var hovered := -1
var message := ""

var _root: Control
var _player: Node
var _old_mouse := Input.MOUSE_MODE_VISIBLE
var _msg_t := 0.0
var _font: Font


## True while any talk / action / day-end / board UI owns the mouse (main.gd and hud.gd check this).
static func ui_open() -> bool:
	return Conversation.current != null or current != null or DaySummary.current != null \
			or ModalScreen.open_count > 0


static func open(parent: Node, menu_title: String, menu_rows: Array, player: Node = null) -> ActionMenu:
	var m := ActionMenu.new()
	m.title = menu_title
	m.rows = menu_rows
	m._player = player
	parent.add_child(m)
	return m


func _ready() -> void:
	layer = 6
	current = self
	if _player and "controls_enabled" in _player:
		_player.controls_enabled = false
	_old_mouse = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_font = ThemeDB.fallback_font
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.draw.connect(_draw)
	_root.gui_input.connect(_on_gui_input)
	add_child(_root)


## Replace the rows (after the day changed, say) and redraw.
func set_rows(menu_rows: Array) -> void:
	rows = menu_rows
	_root.queue_redraw()


func flash(text: String) -> void:
	message = text
	_msg_t = 2.0
	_root.queue_redraw()


func close() -> void:
	if current == self:
		current = null
	if _player and "controls_enabled" in _player:
		_player.controls_enabled = true
	Input.mouse_mode = _old_mouse
	closed.emit()
	queue_free()


## Screen centre of row `i` (rows.size() = the Leave row); tests aim the mouse here.
func row_point(i: int) -> Vector2:
	var r := _panel_rect()
	return Vector2(r.position.x + r.size.x * 0.5, r.position.y + HEAD_H + (i + 0.5) * ROW_H)


func _process(delta: float) -> void:
	if _msg_t > 0.0:
		_msg_t -= delta
		if _msg_t <= 0.0:
			message = ""
		_root.queue_redraw()


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var k: int = event.keycode
	if k >= KEY_1 and k <= KEY_9 and k - KEY_1 <= rows.size():
		get_viewport().set_input_as_handled()
		_pick(k - KEY_1)
	elif k in [KEY_ESCAPE, KEY_Q]:
		get_viewport().set_input_as_handled()
		close()


func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var was := hovered
		hovered = _row_at(event.position)
		if hovered != was:
			_root.queue_redraw()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var i := _row_at(event.position)
		if i >= 0:
			_pick(i)
		_root.accept_event()


func _pick(i: int) -> void:
	if i == rows.size():
		close()
		return
	if not rows[i].get("enabled", true):
		flash(str(rows[i].get("reason", "Not now")))
		return
	picked.emit(i)


func _row_at(p: Vector2) -> int:
	var r := _panel_rect()
	if not r.has_point(p) or p.y < r.position.y + HEAD_H:
		return -1
	var i := int((p.y - r.position.y - HEAD_H) / ROW_H)
	return i if i <= rows.size() else -1


func _panel_rect() -> Rect2:
	var s := _root.size
	var h := HEAD_H + (rows.size() + 1) * ROW_H + 48.0
	return Rect2((s.x - WIDTH) * 0.5, (s.y - h) * 0.45, WIDTH, h)


func _draw() -> void:
	var r := _panel_rect()
	_root.draw_rect(r, PANEL)
	_root.draw_rect(r, Color(GOLD, 0.5), false, 1.5)
	var x := r.position.x + 24.0
	_text(title, Vector2(x, r.position.y + 40), 28, GOLD)
	# The objective, just over the panel: the HUD's line hides while a menu is up.
	if Objective.current() != "" and Settings.value("show_objective"):
		_text("Objective: " + Objective.current(), Vector2(r.position.x + r.size.x * 0.5, r.position.y - 14), 18, Color(0.98, 0.84, 0.5), false, true)
	_text("Day %d" % Game.day, Vector2(x, r.position.y + 74), 19, TEXT)
	_pips(Vector2(x + 84, r.position.y + 67))
	for i in rows.size() + 1:
		var y := r.position.y + HEAD_H + i * ROW_H
		if i == hovered:
			_root.draw_rect(Rect2(r.position.x + 8, y + 2, r.size.x - 16, ROW_H - 4), HOVER)
		var leave := i == rows.size()
		var on: bool = leave or rows[i].get("enabled", true)
		var label := "Leave" if leave else str(rows[i].label)
		_text("%d   %s" % [i + 1, label], Vector2(x, y + 27), 21, TEXT if on else GREY)
		if not leave:
			var cost := int(rows[i].get("cost", 1))
			var right := "%d action%s" % [cost, "" if cost == 1 else "s"] if cost > 0 else "free"
			if not on:
				right = str(rows[i].get("reason", ""))
			_text(right, Vector2(r.end.x - 24, y + 27), 17, GOLD if on else GREY, true)
	if message != "":
		_text(message, Vector2(r.position.x + r.size.x * 0.5, r.end.y - 16), 20, Color(1, 0.55, 0.4), false, true)


func _pips(at: Vector2) -> void:
	var total := maxi(Game.ACTIONS_PER_DAY, Game.actions_left)
	for i in total:
		var c := at + Vector2(i * 20, 0)
		if i < Game.actions_left:
			_root.draw_circle(c, 6.5, GOLD)
		else:
			_root.draw_arc(c, 6.0, 0, TAU, 20, GREY, 1.5)
	_text("%d action%s left" % [Game.actions_left, "" if Game.actions_left == 1 else "s"], at + Vector2(total * 20 + 6, 7), 17, TEXT)


func _text(t: String, at: Vector2, size: int, color: Color, right := false, centre := false) -> void:
	var w := _font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var p := at - Vector2(w if right else (w * 0.5 if centre else 0.0), 0)
	_root.draw_string_outline(_font, p, t, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 5, Color(0, 0, 0, 0.8))
	_root.draw_string(_font, p, t, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)
