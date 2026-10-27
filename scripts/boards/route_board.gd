class_name RouteBoard
extends ModalScreen
## The route map: a parchment with the start and the destination, each route drawn as a line
## you can point at or pick with its number. The side card shows the chosen route's days, risk
## and cost. Picking (click / number, then Enter or a second click) pays the cost, travels the
## days (Game.end_day per day, so countdowns tick), applies its effects and opens its "next"
## board (a branch) or closes. res://routes/<id>.json:
##   {"title": "The road to Akmentar", "intro": "...",
##    "from": {"name": "Cairo", "at": [0.12, 0.45]},  "to": {"name": "Akmentar", "at": [0.86, 0.55]},
##    "options": [
##      {"id": "desert", "label": "Across the desert", "desc": "...",
##       "days": 3, "risk": 2, "cost": 120,            risk 0-3 (none / low / high / severe)
##       "days_if": [{"if": {...}, "days": 2}],         first match overrides (also cost_if, risk_if)
##       "if": {conditions}, "locked_text": "...",     greyed when it fails
##       "unavailable": "No riverboats are left.",     always greyed with this reason
##       "path": [[0.12, 0.45], [0.5, 0.35], [0.86, 0.55]],   the line on the map (0-1 of the map)
##       "do": [effects], "next": "<board id>"}]}
## Each pick also sets flag "route_<board id>" to the option id. `finished` gets every pick made.

signal finished(picks: Array)

const DIR := "res://routes"
const RISK := ["None", "Low", "High", "Severe"]
const ROUTE_COLORS := [Color(0.62, 0.3, 0.12), Color(0.15, 0.32, 0.5), Color(0.2, 0.42, 0.22), Color(0.45, 0.2, 0.42)]

var board_id := ""
var data := {}
var selected := -1
var hovered := -1
var picks: Array = []
var message := ""

var _msg_t := 0.0


static func load_board(id: String) -> Dictionary:
	var path := DIR.path_join(id + ".json")
	if not FileAccess.file_exists(path):
		push_error("RouteBoard: no file %s" % path)
		return {}
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return d if d is Dictionary else {}


static func open(parent: Node, id: String, by: Node = null) -> RouteBoard:
	var b := RouteBoard.new()
	b.player = by
	b._load(id)
	parent.add_child(b)
	return b


func _load(id: String) -> void:
	Hints.once("route_board")
	board_id = id
	data = load_board(id)
	selected = -1
	hovered = -1


func options() -> Array:
	return data.get("options", [])


## An option's days / cost / risk now: the first "<key>_if" entry whose "if" passes, else "<key>".
static func num(o: Dictionary, key: String) -> int:
	for e: Dictionary in o.get(key + "_if", []):
		if Game.check(e.get("if", {})):
			return int(e.get(key, 0))
	return int(o.get(key, 0))


## Why option `i` can't be taken ("" = it can).
func reason(i: int) -> String:
	var o: Dictionary = options()[i]
	if o.has("unavailable"):
		return str(o.unavailable)
	if not Game.check(o.get("if", {})):
		return str(o.get("locked_text", "Not possible"))
	if Game.money < num(o, "cost"):
		return "Needs £%d" % num(o, "cost")
	return ""


## Take option `i` now (what the confirm does). False if it isn't possible.
func choose(i: int) -> bool:
	if i < 0 or i >= options().size():
		return false
	var why := reason(i)
	if why != "":
		_flash(why)
		return false
	var o: Dictionary = options()[i]
	Game.apply([{"money": -num(o, "cost")}])
	Game.set_flag("route_" + board_id, str(o.get("id", i)))
	for d in num(o, "days"):
		Game.end_day()
	DayLog.begin_day()
	Game.apply(o.get("do", []))
	picks.append({"board": board_id, "id": str(o.get("id", i)), "label": str(o.get("label", ""))})
	print("ROUTE %s -> %s (%d days, £%d)" % [board_id, o.get("id", i), num(o, "days"), num(o, "cost")])
	var next := str(o.get("next", ""))
	if next != "":
		_load(next)
	else:
		finished.emit(picks)
		close()
	return true


func _flash(s: String) -> void:
	message = s
	_msg_t = 2.2


func _process(delta: float) -> void:
	super(delta)
	_msg_t -= delta
	if _msg_t <= 0.0:
		message = ""
	var h := _option_at(mouse)
	hovered = h


func _on_key(key: int) -> bool:
	if key >= KEY_1 and key < KEY_1 + options().size():
		_select(key - KEY_1)
	elif key in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE] and selected >= 0:
		choose(selected)
	elif key == KEY_ESCAPE and data.get("can_cancel", false):
		close()
	else:
		return false
	return true


func _on_click(at: Vector2) -> void:
	if _confirm_rect().has_point(at) and selected >= 0:
		choose(selected)
		return
	var i := _option_at(at)
	if i >= 0:
		if i == selected:
			choose(i)
		else:
			_select(i)


func _select(i: int) -> void:
	selected = i
	var why := reason(i)
	if why != "":
		_flash(why)


# ---------------------------------------------------------------- layout

func _map() -> Rect2:
	var s := root.size
	return Rect2(40, 90, maxf(s.x - 80 - 420, 1.0), maxf(s.y - 150, 1.0))  # headless: a zero-size root


func _card() -> Rect2:
	var m := _map()
	return Rect2(m.end.x + 20, m.position.y, 400, m.size.y)


func _confirm_rect() -> Rect2:
	var c := _card()
	return Rect2(c.position.x + 24, c.end.y - 74, c.size.x - 48, 50)


func _pt(v: Variant) -> Vector2:
	var m := _map()
	return m.position + Vector2(float(v[0]), float(v[1])) * m.size


func _path(i: int) -> PackedVector2Array:
	var o: Dictionary = options()[i]
	var pts := PackedVector2Array()
	for p in o.get("path", [data.get("from", {}).get("at", [0.1, 0.5]), data.get("to", {}).get("at", [0.9, 0.5])]):
		pts.append(_pt(p))
	return pts


## The route line nearest `p` (within 28 px), or -1.
func _option_at(p: Vector2) -> int:
	if not _map().has_point(p):
		return -1
	var best := -1
	var bd := 28.0
	for i in options().size():
		var pts := _path(i)
		for k in pts.size() - 1:
			var d := p.distance_to(Geometry2D.get_closest_point_to_segment(p, pts[k], pts[k + 1]))
			if d < bd:
				bd = d
				best = i
	return best


## Screen point on route `i`'s line (its middle; tests click here).
func option_point(i: int) -> Vector2:
	var pts := _path(i)
	var k := pts.size() / 2
	return pts[k] if pts.size() % 2 == 1 else (pts[k - 1] + pts[k]) * 0.5


func _draw_screen() -> void:
	var s := root.size
	root.draw_rect(Rect2(Vector2.ZERO, s), Color(0.08, 0.06, 0.04))
	text(str(data.get("title", "Choose a route")), Vector2(40, 56), 32, GOLD)
	text(str(data.get("intro", "")), Vector2(s.x - 40, 56), 17, DIM, HORIZONTAL_ALIGNMENT_RIGHT)
	var m := _map()
	panel(m, PAPER, Color(INK, 0.6))
	# A few dunes and the river / coast drawn as faint marks.
	for k in 14:
		var c := m.position + Vector2(fmod(k * 0.379, 1.0), fmod(k * 0.613 + 0.1, 1.0)) * m.size
		root.draw_arc(c, 26.0 + (k % 3) * 8, PI * 1.1, PI * 1.9, 10, Color(INK, 0.12), 2.0)
	for line: Array in data.get("marks", []):
		var pts := PackedVector2Array()
		for p in line:
			pts.append(_pt(p))
		root.draw_polyline(pts, Color(0.3, 0.45, 0.6, 0.5), 5.0, true)
	for i in options().size():
		var pts := _path(i)
		var on := reason(i) == ""
		var col: Color = ROUTE_COLORS[i % ROUTE_COLORS.size()]
		if not on:
			col = Color(INK, 0.3)
		var w := 7.0 if i == selected else (5.0 if i == hovered else 3.5)
		_dashed(pts, col, w, not on)
		var mid := option_point(i)
		root.draw_circle(mid, 15.0, Color(col, 1.0) if on else Color(INK, 0.35))
		text(str(i + 1), mid + Vector2(0, 6), 17, PAPER, HORIZONTAL_ALIGNMENT_CENTER, false)
		text(str(options()[i].get("label", "")), mid + Vector2(0, -24), 18, INK if on else Color(INK, 0.45), HORIZONTAL_ALIGNMENT_CENTER, false)
	for end: String in ["from", "to"]:
		var e: Dictionary = data.get(end, {})
		if e.is_empty():
			continue
		var p := _pt(e.get("at", [0.5, 0.5]))
		root.draw_circle(p, 9.0, INK)
		root.draw_circle(p, 5.0, PAPER)
		text(str(e.get("name", "")), p + Vector2(0, 32), 20, INK, HORIZONTAL_ALIGNMENT_CENTER, false)
	_draw_card()
	if message != "":
		text(message, Vector2(m.position.x + m.size.x * 0.5, m.end.y - 20), 21, Color(0.6, 0.12, 0.05), HORIZONTAL_ALIGNMENT_CENTER, false)


func _dashed(pts: PackedVector2Array, col: Color, w: float, dashed: bool) -> void:
	if not dashed:
		root.draw_polyline(pts, col, w, true)
		return
	for k in pts.size() - 1:
		root.draw_dashed_line(pts[k], pts[k + 1], col, w, 12.0)


func _draw_card() -> void:
	var c := _card()
	panel(c)
	var x := c.position.x + 24
	var i := selected if selected >= 0 else hovered
	if i < 0:
		para("Point at a route on the map, or press its number.", Vector2(x, c.position.y + 50), c.size.x - 48, 19, DIM)
		_countdowns(Vector2(x, c.position.y + 160), c.size.x - 48)
		return
	var o: Dictionary = options()[i]
	text(str(o.get("label", "")), Vector2(x, c.position.y + 46), 26, GOLD)
	var y := c.position.y + 90
	var days := num(o, "days")
	text("Days", Vector2(x, y), 18, DIM)
	text("%d" % days, Vector2(c.end.x - 24, y), 20, TEXT, HORIZONTAL_ALIGNMENT_RIGHT)
	y += 32
	var risk := clampi(num(o, "risk"), 0, 3)
	text("Risk", Vector2(x, y), 18, DIM)
	text(RISK[risk], Vector2(c.end.x - 24, y), 20, [TEXT, TEXT, Color(1, 0.7, 0.4), RED][risk], HORIZONTAL_ALIGNMENT_RIGHT)
	for k in 3:
		root.draw_rect(Rect2(c.end.x - 150 + k * 18, y - 13, 12, 12), RED if k < risk else Color(DIM, 0.4))
	y += 32
	text("Cost", Vector2(x, y), 18, DIM)
	text("£%d" % num(o, "cost"), Vector2(c.end.x - 24, y), 20, TEXT, HORIZONTAL_ALIGNMENT_RIGHT)
	y += 22
	text("You have £%d" % Game.money, Vector2(c.end.x - 24, y), 15, DIM, HORIZONTAL_ALIGNMENT_RIGHT)
	y += 30
	y += para(str(o.get("desc", "")), Vector2(x, y), c.size.x - 48, 17, TEXT) + 16
	if not Game.countdowns.is_empty():
		_countdowns(Vector2(x, y), c.size.x - 48, days)
	var why := reason(i)
	var b := _confirm_rect()
	panel(b, Color(0.3, 0.2, 0.1, 0.9) if why == "" else Color(0.15, 0.13, 0.11, 0.9))
	text("Take this route (Enter)" if why == "" else why, b.get_center() + Vector2(0, 7), 19, TEXT if why == "" else DIM, HORIZONTAL_ALIGNMENT_CENTER)


## Each countdown now, and what this route would leave of it.
func _countdowns(at: Vector2, w: float, days := 0) -> void:
	var y := at.y
	for k: String in Game.countdowns:
		var left := int(Game.countdowns[k])
		var after := left - days
		text(CountdownBars.title(k), Vector2(at.x, y), 16, DIM)
		var s := "%d days" % left if days == 0 else "%d → %d days" % [left, after]
		text(s, Vector2(at.x + w, y), 16, RED if after <= 0 else TEXT, HORIZONTAL_ALIGNMENT_RIGHT)
		y += 26
