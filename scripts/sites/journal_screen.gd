class_name JournalScreen
extends ModalScreen
## The journal (J, the pad's D-pad up, or the pause menu): an open book in the menus' leather and
## brass, five tabs:
## - Objectives: the one now and the ones done, by act (Objective's log).
## - Clues: by place, as found.
## - People: everyone you've met (Codex): a list on the left, their page on the right.
## - Places: where you've been (codex/places.json): the way you went and the clues found there.
## - Map: Cairo, Akmentar and the routes taken (the route boards' maps).
## Keys: Tab / Shift+Tab, Q / E or 1-5 the tabs; A / D or the arrows the pages; W / S or the
## arrows a name in a list; J or Esc closes. Pad: LB / RB the tabs, the D-pad or the left stick
## the pages and the names, B closes. Mouse: the tabs, the names, the page arrows and the wheel; a
## click off the book closes. The text follows the options' text size: the pages flow to fit.
##   JournalScreen.toggle(self, player)

const ACTION := "journal"   # the input action main.gd binds to J

const TABS := ["objectives", "clues", "people", "places", "map"]
const TAB_NAMES := {"objectives": "Objectives", "clues": "Clues", "people": "People", "places": "Places", "map": "Map"}
const PLACES := "res://codex/places.json"
## The route boards on the map (their maps share Cairo and Akmentar), with what each journey was.
const MAP_BOARDS := [["act3_route", "Out"], ["act6_return", "Back"], ["act8_route", "Return"]]

static var current: JournalScreen

var tab := "objectives"
var page := 0   # the spread shown (Objectives, Clues), or the list's page (People, Places)
var pick := 0   # the name picked (People, Places)

var _people: Array = []
var _places: Array = []
var _flow := {}         # tab -> its spreads (see _spreads), for _flow_key's sizes
var _flow_key := ""
var _arrows := {}       # -1 / 1 -> the page arrows' rects (clicks)
var _stick := Vector2i.ZERO   # the left stick's held direction: one step per push


static func toggle(parent: Node, by: Node = null) -> JournalScreen:
	if current:
		current.close()
		return null
	if ActionMenu.ui_open():
		return null
	var j := JournalScreen.new()
	j.player = by
	parent.add_child(j)
	return j


func _opened() -> void:
	current = self
	_people = Codex.pages()
	_places = places()
	_go_tab(tab)
	closed.connect(func() -> void:
		if current == self:
			current = null)


# ---------------------------------------------------------------- the data

## The objectives by act: [[act, title, [{text, now, day}]]], the current one marked now.
static func objectives() -> Array:
	var now := Objective.current()
	var by_act := {}
	var order: Array = []
	for e: Dictionary in Game.flag("objectives", []):
		var act := int(e.get("act", 0))
		if not by_act.has(act):
			by_act[act] = []
			order.append(act)
		by_act[act].append({"text": str(e.get("text", "")), "now": false, "day": int(e.get("day", 0))})
	# The one now: the newest of that text in this act (a scene's goal set before the log began
	# is added here so the page is never empty while there is one).
	if now != "":
		if not by_act.has(Game.act):
			by_act[Game.act] = []
			order.append(Game.act)
		var list: Array = by_act[Game.act]
		var found := false
		for i in range(list.size() - 1, -1, -1):
			if list[i].text == now:
				list[i].now = true
				found = true
				break
		if not found:
			list.append({"text": now, "now": true, "day": Game.day})
	order.sort()
	return order.map(func(a): return [a, act_title(a), by_act[a]])


static func act_title(act: int) -> String:
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(TitleScreen.DATA)) if FileAccess.file_exists(TitleScreen.DATA) else null
	if d is Dictionary:
		for ch: Dictionary in d.get("chapters", []):
			if int(ch.get("act", 0)) == act:
				return str(ch.get("title", ""))
	return ""


## The places you've been: [{id, name, role, text, notes, way, clues}] in the file's order.
static func places() -> Array:
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(PLACES)) if FileAccess.file_exists(PLACES) else null
	var all: Dictionary = d.get("places", {}) if d is Dictionary else {}
	var counts := {}
	for e: Dictionary in Journal.entries():
		var p := str(e.get("place", ""))
		counts[p] = int(counts.get(p, 0)) + 1
	var out := []
	for id: String in all:
		var p: Dictionary = all[id]
		if not (Game.check(p.get("if", {"flag": "-"})) or counts.has(id)):
			continue
		var notes: Array = []
		for n: Dictionary in p.get("notes", []):
			if Game.check(n.get("if", {})):
				notes.append(str(n.text))
		out.append({"id": id, "name": str(p.get("name", id)), "role": str(p.get("role", "")), "text": str(p.get("text", "")),
			"notes": notes, "way": route_taken(str(p.get("route", ""))), "clues": int(counts.get(id, 0))})
	return out


## The label of the way picked on route board `board` ("" if none yet).
static func route_taken(board: String) -> String:
	if board == "":
		return ""
	var picked := str(Game.flag("route_" + board, ""))
	if picked == "":
		return ""
	for o: Dictionary in RouteBoard.load_board(board).get("options", []):
		if str(o.get("id", "")) == picked:
			return str(o.get("label", picked))
	return ""


## Where you've been along the roads, for the map's ink dots: [{name, at (0-1 of the map)}].
## The branch boards have their own little maps (the fork to Akmentar); their points are laid
## along the main map's road from its last bend to Akmentar.
static func map_marks() -> Array:
	var out := []
	var main := RouteBoard.load_board("act3_route")
	var branches := {"act3_desert_branch": ["desert", {"temple": "the temple", "town": "the desert town"}],
		"act3_coast_branch": ["coast", {"town": "the town"}]}
	for id: String in branches:
		var picked := str(Game.flag("route_" + id, ""))
		var names: Dictionary = branches[id][1]
		if not names.has(picked):
			continue
		var board := RouteBoard.load_board(id)
		var road: Array = []
		for o: Dictionary in main.get("options", []):
			if o.get("id", "") == branches[id][0]:
				road = o.get("path", [])
		for o: Dictionary in board.get("options", []):
			var pts: Array = o.get("path", [])
			if o.get("id", "") == picked and pts.size() >= 3 and road.size() >= 2:
				out.append({"name": names[picked], "at": _branch_to_main(pts[pts.size() / 2], board, road)})
	if Game.flag("boat_attacked", false):  # mid-river, between the riverboat road's bends
		for o: Dictionary in main.get("options", []):
			var pts: Array = o.get("path", [])
			if o.get("id", "") == "riverboat" and pts.size() >= 3:
				out.append({"name": "the riverboat attack", "at": (_v(pts[1]) + _v(pts[2])) * 0.5})
	return out


static func _v(a: Array) -> Vector2:
	return Vector2(float(a[0]), float(a[1]))


## A branch board's point on the main map: along the road's last leg (fork -> Akmentar) by its x,
## off it by its y.
static func _branch_to_main(p: Array, board: Dictionary, road: Array) -> Vector2:
	var f0 := _v(board.from.at)
	var t0 := _v(board.to.at)
	var fork := _v(road[road.size() - 2])
	var end := _v(road[road.size() - 1])
	var k := clampf((float(p[0]) - f0.x) / maxf(t0.x - f0.x, 0.01), 0.0, 1.0)
	var off := (float(p[1]) - lerpf(f0.y, t0.y, k)) * (end - fork).length() * 0.6
	return fork.lerp(end, k) + Vector2(0, off)


## The routes taken, for the map: [{board, journey, label, path}] in the order travelled.
static func map_routes() -> Array:
	var out := []
	for b: Array in MAP_BOARDS:
		var picked := str(Game.flag("route_" + b[0], ""))
		if picked == "":
			continue
		for o: Dictionary in RouteBoard.load_board(b[0]).get("options", []):
			if str(o.get("id", "")) == picked:
				out.append({"board": b[0], "journey": b[1], "label": str(o.get("label", "")), "path": o.get("path", [])})
	return out


# ---------------------------------------------------------------- input

func _input(e: InputEvent) -> void:
	if is_closed():
		return
	Controls.note_device(e)
	var used := false
	if e is InputEventKey and e.pressed:
		used = _on_key(e.keycode) if not e.echo else _on_repeat(e.keycode)
		if e.keycode == KEY_TAB and e.shift_pressed and not e.echo:
			_step_tab(-2)  # (_on_key went one on already)
	elif e is InputEventJoypadButton and e.pressed:
		used = _on_pad(e.button_index)
	elif e is InputEventJoypadMotion and (e.axis == JOY_AXIS_LEFT_X or e.axis == JOY_AXIS_LEFT_Y):
		used = _on_stick(e.axis, e.axis_value)
	if used:
		get_viewport().set_input_as_handled()


func _on_key(key: int) -> bool:
	match key:
		KEY_J, KEY_ESCAPE:
			close()
		KEY_TAB, KEY_E:
			_step_tab(1)
		KEY_Q:
			_step_tab(-1)
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5:
			_go_tab(TABS[key - KEY_1])
		_:
			return _on_repeat(key)
	return true


## The keys that repeat while held: the pages and the list.
func _on_repeat(key: int) -> bool:
	match key:
		KEY_A, KEY_LEFT:
			_step_page(-1)
		KEY_D, KEY_RIGHT:
			_step_page(1)
		KEY_W, KEY_UP:
			_step_pick(-1)
		KEY_S, KEY_DOWN:
			_step_pick(1)
		_:
			return false
	return true


func _on_pad(button: int) -> bool:
	match button:
		JOY_BUTTON_B, JOY_BUTTON_BACK:
			close()
		JOY_BUTTON_LEFT_SHOULDER:
			_step_tab(-1)
		JOY_BUTTON_RIGHT_SHOULDER:
			_step_tab(1)
		JOY_BUTTON_DPAD_LEFT:
			_step_page(-1)
		JOY_BUTTON_DPAD_RIGHT:
			_step_page(1)
		JOY_BUTTON_DPAD_UP:
			_step_pick(-1)
		JOY_BUTTON_DPAD_DOWN:
			_step_pick(1)
		_:
			return false
	return true


func _on_stick(axis: int, v: float) -> bool:
	var dir := 0 if absf(v) < 0.55 else int(signf(v))
	var was := _stick.x if axis == JOY_AXIS_LEFT_X else _stick.y
	if axis == JOY_AXIS_LEFT_X:
		_stick.x = dir
	else:
		_stick.y = dir
	if dir == 0 or dir == was:
		return dir != 0
	if axis == JOY_AXIS_LEFT_X:
		_step_page(dir)
	else:
		_step_pick(dir)
	return true


func _gui(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed and (e.button_index == MOUSE_BUTTON_WHEEL_UP or e.button_index == MOUSE_BUTTON_WHEEL_DOWN):
		root.accept_event()
		_step_pick(-1 if e.button_index == MOUSE_BUTTON_WHEEL_UP else 1)
		return
	super(e)


func _on_click(at: Vector2) -> void:
	for t: String in TABS:
		if _tab_rect(t).has_point(at):
			_go_tab(t)
			return
	for d: int in _arrows:
		if (_arrows[d] as Rect2).has_point(at):
			_step_page(d)
			return
	if not _book().grow(14).has_point(at):
		close()
		return
	if _is_list():
		for i in _list().size():
			if _row_rect(i).has_point(at):
				pick = i
				return


func _go_tab(t: String) -> void:
	tab = t
	pick = 0
	page = 0 if _is_list() or t == "map" else _newest_spread(t)


## The next tab (as Tab).
func switch_tab() -> void:
	_step_tab(1)


func _step_tab(d: int) -> void:
	_go_tab(TABS[posmod(TABS.find(tab) + d, TABS.size())])


func _step_page(d: int) -> void:
	if _is_list():
		var rows := _rows_per_page()
		pick = clampi((pick / rows + d) * rows, 0, maxi(_list().size() - 1, 0))
		page = pick / rows
	else:
		page = clampi(page + d, 0, maxi(_spreads(tab).size() - 1, 0))


func _step_pick(d: int) -> void:
	if _is_list():
		pick = clampi(pick + d, 0, maxi(_list().size() - 1, 0))
		page = pick / _rows_per_page()
	else:
		_step_page(d)


func _is_list() -> bool:
	return tab == "people" or tab == "places"


func _list() -> Array:
	return _people if tab == "people" else _places


# ---------------------------------------------------------------- layout

func _tab_h() -> float:
	return fs(19) + 18.0


func _book() -> Rect2:
	var s := root.size if root.size != Vector2.ZERO else get_viewport().get_visible_rect().size
	var th := _tab_h()
	var size := Vector2(minf(s.x - 60.0, 1180.0), minf(s.y - 70.0 - th, 700.0))
	return Rect2(Vector2((s.x - size.x) * 0.5, (s.y - size.y + th) * 0.5), size)


func _tab_rect(t: String) -> Rect2:
	var r := _book()
	var x := r.position.x + 30.0
	for other: String in TABS:
		var w := font.get_string_size(TAB_NAMES[other], HORIZONTAL_ALIGNMENT_LEFT, -1, fs(19)).x + 40.0
		if other == t:
			return Rect2(x, r.position.y - 14.0 - _tab_h(), w, _tab_h() + 2.0)
		x += w + 6.0
	return Rect2()


## The writing area of the left (0) or right (1) page, under the heading and over the footer.
func _page_rect(side: int) -> Rect2:
	var r := _book()
	var half := r.size.x * 0.5
	var top := r.position.y + fs(28) + 44.0
	return Rect2(r.position.x + side * half + 40.0, top, half - 80.0, r.end.y - fs(15) - 30.0 - top)


func _row_h() -> float:
	return fs(18) + 16.0


func _rows_per_page() -> int:
	return maxi(int(_page_rect(0).size.y / _row_h()), 1)


## Where name i sits in the list (only those on the list's page shown).
func _row_rect(i: int) -> Rect2:
	var rows := _rows_per_page()
	if i / rows != page:
		return Rect2()
	var p := _page_rect(0)
	return Rect2(p.position.x - 10.0, p.position.y + (i % rows) * _row_h(), p.size.x + 20.0, _row_h() - 2.0)


## The flowing tabs' spreads: [[left column blocks], [right column blocks]] each, a block
## {kind, h, ...}; a heading never ends a column. Rebuilt when the book or the text size changes.
func _spreads(t: String) -> Array:
	var p := _page_rect(0)
	var key := "%s %s %d" % [p, root.size, fs(100)]
	if key != _flow_key:
		_flow = {}
		_flow_key = key
	if _flow.has(t):
		return _flow[t]
	var blocks := _blocks(t)
	for b: Dictionary in blocks:
		b.h = _measure(b, p.size.x)
	var spreads: Array = []
	var cols: Array = [[]]
	var y := 0.0
	var section := {}   # the heading the blocks are under: a column going on under it repeats it
	for i in blocks.size():
		var b: Dictionary = blocks[i]
		var heading: bool = b.kind in ["act", "place"]
		var need: float = b.h
		if heading and i + 1 < blocks.size():
			need += blocks[i + 1].h  # a heading goes with its first line
		if y + need > p.size.y and not cols[-1].is_empty():
			if cols.size() == 2:
				spreads.append(cols)
				cols = [[]]
			else:
				cols.append([])
			y = 0.0
			if not heading and not section.is_empty():
				cols[-1].append({"kind": section.kind, "text": section.text + " (cont.)", "h": section.h})
				y += section.h
		if heading:
			section = b
		cols[-1].append(b)
		y += b.h
	spreads.append(cols)
	_flow[t] = spreads
	return spreads


## The spread with the newest: the current act's objectives, the last clue.
func _newest_spread(t: String) -> int:
	var spreads := _spreads(t)
	if t == "objectives":
		for i in spreads.size():
			for col: Array in spreads[i]:
				for b: Dictionary in col:
					if b.kind == "goal" and b.now:
						return i
	return maxi(spreads.size() - 1, 0)


func _blocks(t: String) -> Array:
	var out: Array = []
	if t == "objectives":
		for a: Array in objectives():
			out.append({"kind": "act", "text": ("Act %d · %s" % [a[0], a[1]]) if a[1] != "" else "Act %d" % a[0]})
			for g: Dictionary in a[2]:
				out.append({"kind": "goal", "text": g.text, "now": g.now})
		if out.is_empty():
			out.append({"kind": "empty", "text": "No objectives yet."})
	else:
		for p: Array in Journal.by_place():
			out.append({"kind": "place", "text": str(p[0])})
			for e: Dictionary in p[1]:
				out.append({"kind": "clue", "meta": "%s · day %d" % [e.get("site", ""), int(e.get("day", 0))],
					"title": str(e.get("title", "")), "text": str(e.get("text", ""))})
		if out.is_empty():
			out.append({"kind": "empty", "text": "Nothing written yet. Inspect what you find on the way."})
	return out


func _measure(b: Dictionary, w: float) -> float:
	match b.kind:
		"act", "place":
			return font.get_height(fs(22)) + 16.0
		"goal":
			return _para_h(b.text, w - 30.0, fs(17)) + 12.0
		"clue":
			return font.get_height(fs(14)) + font.get_height(fs(18)) + _para_h(b.text, w, fs(16)) + 22.0
	return _para_h(b.text, w, fs(18)) + 10.0


func _para_h(s: String, w: float, size: int) -> float:
	return font.get_multiline_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, w, size).y


# ---------------------------------------------------------------- drawing

func _draw_screen() -> void:
	dim_background(0.75)
	var r := _book()
	_arrows = {}
	# The tabs: bookmarks along the top, the open one paper and joined to the page.
	for t: String in TABS:
		var tr := _tab_rect(t)
		var on := t == tab
		root.draw_rect(tr, PAPER if on else PAPER.darkened(0.35))
		root.draw_rect(tr, BRASS if on else Color(BRASS, 0.6), false, 1.5)
		text(TAB_NAMES[t], Vector2(tr.get_center().x, tr.position.y + (tr.size.y + font.get_ascent(fs(19)) - font.get_descent(fs(19))) * 0.5),
			fs(19), INK if on else Color(INK, 0.6), HORIZONTAL_ALIGNMENT_CENTER, false)
	book(r)
	var open_tab := _tab_rect(tab)
	root.draw_rect(Rect2(open_tab.position.x + 1.5, r.position.y - 15.0, open_tab.size.x - 3.0, 16.0), PAPER)  # the open tab runs into the page
	_line("Expedition journal", Vector2(r.position.x + 40.0, r.position.y + 22.0), fs(28), INK)
	text("Day %d" % Game.day, Vector2(r.end.x - 40.0, r.position.y + 22.0 + font.get_ascent(fs(28))), fs(16), Color(INK, 0.6), HORIZONTAL_ALIGNMENT_RIGHT, false)
	root.draw_line(Vector2(r.position.x + 40.0, r.position.y + fs(28) + 34.0), Vector2(r.end.x - 40.0, r.position.y + fs(28) + 34.0), Color(INK, 0.3), 1.0)
	match tab:
		"objectives", "clues":
			_draw_flow()
		"people", "places":
			_draw_list()
		"map":
			_draw_map()
	var hint := ("LB / RB  tabs · D-pad  pages · B  close" if Controls.last_pad
		else Controls.fill("Tab  tabs · A / D  pages · {journal}  close"))
	text(hint, Vector2(r.end.x - 40.0, r.end.y - 14.0), fs(14), Color(INK, 0.5), HORIZONTAL_ALIGNMENT_RIGHT, false)


## Text with its top at `top` (the helpers' own take a baseline); returns its height.
func _line(s: String, top: Vector2, size: int, color: Color, align := HORIZONTAL_ALIGNMENT_LEFT) -> float:
	text(s, top + Vector2(0, font.get_ascent(size)), size, color, align, false)
	return font.get_height(size)


func _para_top(s: String, top: Vector2, w: float, size: int, color: Color) -> float:
	return para(s, top + Vector2(0, font.get_ascent(size)), w, size, color)


func _draw_flow() -> void:
	var spreads := _spreads(tab)
	page = clampi(page, 0, spreads.size() - 1)
	var cols: Array = spreads[page]
	for side in cols.size():
		var p := _page_rect(side)
		var y := p.position.y
		for b: Dictionary in cols[side]:
			_draw_block(b, Vector2(p.position.x, y), p.size.x)
			y += b.h
	_draw_pager(page, spreads.size(), _book().get_center().x)


func _draw_block(b: Dictionary, at: Vector2, w: float) -> void:
	match b.kind:
		"act", "place":
			var h := _line(b.text, at + Vector2(0, 4), fs(22), RUST)
			root.draw_line(at + Vector2(0, h + 8.0), at + Vector2(w, h + 8.0), Color(RUST, 0.35), 1.0)
		"goal":
			var size := fs(17)
			var mid := at + Vector2(10.0, font.get_ascent(size) * 0.6)
			if b.now:  # the one now: a red diamond, full ink
				var k := 5.0 * Subtitles.scale()
				root.draw_colored_polygon(PackedVector2Array([mid + Vector2(0, -k), mid + Vector2(k, 0), mid + Vector2(0, k), mid + Vector2(-k, 0)]), RUST)
				_para_top(b.text, at + Vector2(30.0, 0), w - 30.0, size, INK)
			else:  # done: ticked, the ink faded
				var k := 5.0 * Subtitles.scale()
				root.draw_polyline(PackedVector2Array([mid + Vector2(-k, 0), mid + Vector2(-k * 0.3, k * 0.8), mid + Vector2(k, -k)]), Color(INK, 0.6), 2.0)
				_para_top(b.text, at + Vector2(30.0, 0), w - 30.0, size, Color(INK, 0.55))
		"clue":
			var y := at.y
			y += _line(b.meta, Vector2(at.x, y), fs(14), Color(INK, 0.6))
			y += _line(b.title, Vector2(at.x, y), fs(18), INK) + 4.0
			_para_top(b.text, Vector2(at.x, y), w, fs(16), Color(INK, 0.85))
		_:
			_para_top(b.text, at, w, fs(18), Color(INK, 0.7))


## "◀  2 / 3  ▶" centred at x over the footer, its arrows clickable.
func _draw_pager(at: int, count: int, x: float) -> void:
	if count <= 1:
		return
	var y := _book().end.y - 14.0
	var size := fs(16)
	text("%d / %d" % [at + 1, count], Vector2(x, y), size, Color(INK, 0.7), HORIZONTAL_ALIGNMENT_CENTER, false)
	var half := font.get_string_size("%d / %d" % [at + 1, count], HORIZONTAL_ALIGNMENT_LEFT, -1, size).x * 0.5 + 26.0
	var mid_y := y - font.get_ascent(size) * 0.35
	for d: int in [-1, 1]:
		var c := Vector2(x + d * half, mid_y)
		var k := 7.0 * Subtitles.scale()
		var on := (d < 0 and at > 0) or (d > 0 and at < count - 1)
		root.draw_colored_polygon(PackedVector2Array([c + Vector2(d * k, 0), c + Vector2(-d * k * 0.6, -k), c + Vector2(-d * k * 0.6, k)]), Color(INK, 0.75 if on else 0.2))
		_arrows[d] = Rect2(c - Vector2(16, 16), Vector2(32, 32))


func _draw_list() -> void:
	var list := _list()
	if list.is_empty():
		_para_top("No one yet. The people you meet will be written here." if tab == "people" else "Nowhere yet.",
			_page_rect(0).position, _page_rect(0).size.x, fs(18), Color(INK, 0.7))
		return
	pick = clampi(pick, 0, list.size() - 1)
	var rows := _rows_per_page()
	page = pick / rows
	for i in range(page * rows, mini((page + 1) * rows, list.size())):
		var rr := _row_rect(i)
		if i == pick:
			root.draw_rect(rr, Color(INK, 0.1))
			root.draw_rect(Rect2(rr.position, Vector2(4, rr.size.y)), RUST)
		_line(str(list[i].name), rr.position + Vector2(14, (rr.size.y - font.get_height(fs(18))) * 0.5), fs(18), INK)
	_draw_pager(page, int(ceil(list.size() / float(rows))), _page_rect(0).get_center().x)
	# The page: name, role, what you know, then the notes.
	var sel: Dictionary = list[pick]
	var p := _page_rect(1)
	var y := p.position.y
	y += _line(str(sel.name), Vector2(p.position.x, y), fs(26), INK)
	if str(sel.role) != "":
		y += _line(str(sel.role), Vector2(p.position.x, y), fs(16), RUST)
	y += 14.0
	y += _para_top(str(sel.text), Vector2(p.position.x, y), p.size.x, fs(17), Color(INK, 0.9)) + 14.0
	var notes: Array = sel.notes.duplicate()
	if tab == "places":
		if str(sel.way) != "":
			notes.push_front("Your way: " + str(sel.way))
		if int(sel.clues) > 0:
			notes.append("%d clue%s found here (Clues)" % [sel.clues, "" if sel.clues == 1 else "s"])
	for n in notes:
		y += _para_top("· " + str(n), Vector2(p.position.x, y), p.size.x, fs(16), Color(INK, 0.8)) + 8.0


## The land under the roads: the river in blue ink (wavy), the coast with the sea hatched below,
## the desert lettered, a compass rose, and ink dots where you've been (map_marks).
func _draw_geography(board: Dictionary, m: Rect2, to_px: Callable) -> void:
	var marks: Array = board.get("marks", [])
	var water := Color(0.16, 0.3, 0.5, 0.75)
	if marks.size() > 0:  # the river
		var pts: PackedVector2Array = []
		var line: Array = marks[0]
		for i in line.size() - 1:
			var a: Vector2 = to_px.call(line[i])
			var b: Vector2 = to_px.call(line[i + 1])
			var n := (b - a).orthogonal().normalized()
			var steps := maxi(int(a.distance_to(b) / 6.0), 1)
			for j in steps:
				var q := a.lerp(b, j / float(steps))
				pts.append(q + n * sin(q.x * 0.11 + q.y * 0.07) * 3.0)
		pts.append(to_px.call(line[-1]))
		root.draw_polyline(pts, water, 2.5, true)
		_hand("the Nile", to_px.call(line[1]) + Vector2(-30, 14), fs(17), water)
	if marks.size() > 1:  # the coast, the sea hatched on its far side
		var line: Array = marks[1]
		for i in line.size() - 1:
			var a: Vector2 = to_px.call(line[i])
			var b: Vector2 = to_px.call(line[i + 1])
			root.draw_line(a, b, Color(INK, 0.6), 2.0, true)
			var steps := maxi(int(a.distance_to(b) / 14.0), 1)
			for j in steps:
				var q := a.lerp(b, (j + 0.5) / steps)
				root.draw_line(q + Vector2(0, 4), q + Vector2(-6, 12), Color(water, 0.35), 1.0)
		_hand("the sea", to_px.call(line[1]) + Vector2(0, 18), fs(16), Color(water, 0.9))
	_hand("Western  Desert", m.position + m.size * Vector2(0.47, 0.06), fs(22), Color(INK, 0.35))
	# The compass rose, top right.
	var c := Vector2(m.end.x - 30.0, m.position.y + 34.0)
	var k := 24.0 * Subtitles.scale()
	for d: Vector2 in [Vector2.UP, Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT]:
		var side := d.orthogonal() * k * 0.22
		root.draw_colored_polygon(PackedVector2Array([c + d * k, c + side, c - side]), INK if d == Vector2.UP else Color(INK, 0.55))
	root.draw_arc(c, k * 0.55, 0, TAU, 32, Color(INK, 0.6), 1.2, true)
	_line("N", c + Vector2(0, -k - font.get_height(fs(15)) - 2.0), fs(15), INK, HORIZONTAL_ALIGNMENT_CENTER)


## Ink dots where you've been (map_marks), over the roads.
func _draw_marks(m: Rect2) -> void:
	for mk: Dictionary in map_marks():
		var at: Vector2 = m.position + (mk.at as Vector2) * m.size
		root.draw_circle(at, 4.5, INK)
		var w := font.get_string_size(str(mk.name), HORIZONTAL_ALIGNMENT_LEFT, -1, fs(15)).x
		root.draw_rect(Rect2(at + Vector2(-w * 0.5 - 4.0, 8.0), Vector2(w + 8.0, font.get_height(fs(15)))), Color(PAPER, 0.75))
		_hand(str(mk.name), at + Vector2(0, 8), fs(15), Color(INK, 0.85))


## A hand-lettered label: centred on `at` (its top), in faded ink with no outline.
func _hand(s: String, top: Vector2, size: int, color: Color) -> void:
	_line(s, top, size, color, HORIZONTAL_ALIGNMENT_CENTER)


## A map sheet laid over the spread: Cairo and Akmentar, every way the boards offered faint, the
## ones taken in ink and colour, with a key.
func _draw_map() -> void:
	var r := _book()
	var sheet := Rect2(r.position.x + 50.0, _page_rect(0).position.y, r.size.x - 100.0, _page_rect(0).size.y)
	paper(sheet)
	var key_h := (font.get_height(fs(16)) + 6.0) * 3.0 + 10.0
	var m := Rect2(sheet.position + Vector2(40, 30), sheet.size - Vector2(80, 60 + key_h))
	var to_px := func(v: Array) -> Vector2: return m.position + Vector2(float(v[0]), float(v[1])) * m.size
	var first := RouteBoard.load_board(MAP_BOARDS[0][0])
	_draw_geography(first, m, to_px)
	# Nobody has heard of Akmentar before Karim's offer, and the roads there are only known once
	# you sit down to choose one (Act 3's board): until then the map is just Egypt and Cairo.
	var knows_tomb: bool = Game.act >= 2 or bool(Game.flag("act1_offer_accepted", false))
	var knows_roads: bool = Game.act >= 3
	for b: Array in (MAP_BOARDS if knows_roads else []):  # the ways not taken
		for o: Dictionary in RouteBoard.load_board(b[0]).get("options", []):
			var pts: Array = o.get("path", [])
			for i in pts.size() - 1:
				root.draw_dashed_line(to_px.call(pts[i]), to_px.call(pts[i + 1]), Color(INK, 0.18), 1.5, 8.0)
	var taken := map_routes()
	var key_y := m.end.y + 24.0
	for j in taken.size():
		var t: Dictionary = taken[j]
		var col: Color = RouteBoard.ROUTE_COLORS[j % RouteBoard.ROUTE_COLORS.size()]
		var pts: Array = t.path
		var off := Vector2(0, (j - 1) * 4.0)  # the same road twice stays two lines
		for i in pts.size() - 1:
			root.draw_line(to_px.call(pts[i]) + off, to_px.call(pts[i + 1]) + off, col, 4.0)
		root.draw_line(Vector2(m.position.x, key_y + j * (font.get_height(fs(16)) + 6.0) + font.get_height(fs(16)) * 0.5),
			Vector2(m.position.x + 30.0, key_y + j * (font.get_height(fs(16)) + 6.0) + font.get_height(fs(16)) * 0.5), col, 4.0)
		_line("%s: %s" % [t.journey, t.label], Vector2(m.position.x + 42.0, key_y + j * (font.get_height(fs(16)) + 6.0)), fs(16), INK)
	_draw_marks(m)
	if taken.is_empty():
		_line("No road taken yet.", Vector2(m.position.x, key_y), fs(16), Color(INK, 0.6))
	for end: String in (["from", "to"] if knows_tomb else ["from"]):
		var c: Dictionary = first.get(end, {})
		if c.is_empty():
			continue
		var at: Vector2 = to_px.call(c.at)
		root.draw_circle(at, 7.0, INK)
		root.draw_circle(at, 4.0, PAPER)
		var nw := font.get_string_size(str(c.name), HORIZONTAL_ALIGNMENT_LEFT, -1, fs(20)).x
		root.draw_rect(Rect2(at + Vector2(-nw * 0.5 - 6.0, 12.0), Vector2(nw + 12.0, font.get_height(fs(20)))), Color(PAPER, 0.85))
		_line(str(c.name), at + Vector2(0, 12), fs(20), INK, HORIZONTAL_ALIGNMENT_CENTER)
