class_name DaySummary
extends CanvasLayer
## The end-of-day screen: "Day N ends" and what happened (DayLog.summary), over a dark screen.
## A click or Space / Enter closes it; that runs Game.end_day(), starts the next day's log, and
## emits `closed`. Opened by ActionSpot when the last action is spent, and by sleeping.
##   DaySummary.open(self, player).closed.connect(func(): ...)

signal closed

const TEXT := Color(0.95, 0.88, 0.7)
const GOLD := Color(0.95, 0.72, 0.35)

## The screen showing now, or null.
static var current: DaySummary

var day := 1
var lines: Array[String] = []

var _root: Control
var _player: Node
var _old_mouse := Input.MOUSE_MODE_VISIBLE
var _font: Font
var _t := 0.0


static func open(parent: Node, player: Node = null) -> DaySummary:
	if current:
		return current
	var s := DaySummary.new()
	s._player = player
	parent.add_child(s)
	return s


func _ready() -> void:
	layer = 8
	current = self
	day = Game.day
	lines = DayLog.summary()
	if lines.is_empty():
		lines = ["A quiet day."]
	if _player and "controls_enabled" in _player:
		_player.controls_enabled = false
	_old_mouse = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_font = ThemeDB.fallback_font
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.draw.connect(_draw)
	_root.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed:
			_root.accept_event()
			_close())
	add_child(_root)


func _process(delta: float) -> void:
	_t += delta
	_root.queue_redraw()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo \
			and event.keycode in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER, KEY_E]:
		get_viewport().set_input_as_handled()
		_close()


func _close() -> void:
	if _t < 0.4:  # a click meant for the menu underneath mustn't skip the screen
		return
	if current == self:
		current = null
	Game.end_day()
	DayLog.begin_day()
	if _player and "controls_enabled" in _player:
		_player.controls_enabled = true
	Input.mouse_mode = _old_mouse
	closed.emit()
	queue_free()


func _draw() -> void:
	var s := _root.size
	var a := clampf(_t / 0.5, 0.0, 1.0)
	_root.draw_rect(Rect2(Vector2.ZERO, s), Color(0.03, 0.025, 0.02, 0.92 * a))
	var y := s.y * 0.26
	_centre("Day %d ends" % day, y, 48, Color(GOLD, a))
	y += 70
	for l in lines:
		_centre(l, y, 22, Color(TEXT, a))
		y += 34
	_centre("Click or press Space to begin day %d" % (day + 1), maxf(y + 40, s.y * 0.8), 18, Color(TEXT, a * 0.7))


func _centre(t: String, y: float, size: int, color: Color) -> void:
	var w := _font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var p := Vector2((_root.size.x - w) * 0.5, y)
	_root.draw_string_outline(_font, p, t, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 6, Color(0, 0, 0, color.a * 0.8))
	_root.draw_string(_font, p, t, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)
