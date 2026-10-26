class_name CountdownBars
extends CanvasLayer
## HUD bars for Game.countdowns (the thieves leaving Cairo, the mummy reaching it), top right:
## one bar per countdown, its days left and the most it has shown (the bar's full length).
## Hidden when there are none or while a talk / menu / board is open. main.gd: add_child(CountdownBars.new())
## Titles come from res://routes/countdowns.json ({"thieves": "The thieves leave Cairo", ...}).

const TITLES := "res://routes/countdowns.json"
const TEXT := Color(0.95, 0.88, 0.7)
const RED := Color(0.85, 0.25, 0.15)
const AMBER := Color(0.95, 0.65, 0.25)

static var _titles := {}

var _root: Control
var _font: Font
var _max := {}   # countdown -> the most days it has shown


static func title(id: String) -> String:
	if _titles.is_empty() and FileAccess.file_exists(TITLES):
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(TITLES))
		_titles = d if d is Dictionary else {"_": ""}
	return str(_titles.get(id, id.capitalize()))


func _ready() -> void:
	layer = 4
	_font = ThemeDB.fallback_font
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.draw.connect(_draw)
	add_child(_root)


func _process(_delta: float) -> void:
	for k: String in Game.countdowns:
		_max[k] = maxi(int(_max.get(k, 0)), int(Game.countdowns[k]))
	visible = not Game.countdowns.is_empty() and Conversation.current == null and ActionMenu.current == null
	_root.queue_redraw()


func _draw() -> void:
	var w := 300.0
	var x := _root.size.x - w - 24
	var y := 24.0
	for k: String in Game.countdowns:
		var left := maxi(int(Game.countdowns[k]), 0)
		var full := maxi(int(_max.get(k, left)), 1)
		var col := RED if left <= 2 else AMBER
		_root.draw_rect(Rect2(x - 10, y - 4, w + 20, 52), Color(0, 0, 0, 0.55))
		_text(title(k), Vector2(x, y + 14), 16, TEXT)
		_text("%d day%s" % [left, "" if left == 1 else "s"], Vector2(x + w, y + 14), 16, col, true)
		_root.draw_rect(Rect2(x, y + 24, w, 12), Color(1, 1, 1, 0.12))
		_root.draw_rect(Rect2(x, y + 24, w * float(left) / float(full), 12), col)
		for d in full:  # a tick per day
			var tx := x + w * float(d) / float(full)
			_root.draw_line(Vector2(tx, y + 24), Vector2(tx, y + 36), Color(0, 0, 0, 0.5), 1.0)
		y += 60


func _text(t: String, at: Vector2, size: int, color: Color, right := false) -> void:
	var p := at - Vector2(_font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x if right else 0.0, 0)
	_root.draw_string_outline(_font, p, t, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 5, Color(0, 0, 0, 0.8))
	_root.draw_string(_font, p, t, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)
