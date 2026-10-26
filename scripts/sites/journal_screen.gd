class_name JournalScreen
extends ModalScreen
## The journal (J): clues by place, the newest place first on its own page. A / D or the arrow
## keys turn pages; J, Esc or a click outside closes. JournalScreen.toggle(self, player).

const ACTION := "journal"   # the input action main.gd binds to J

static var current: JournalScreen

var page := 0
var _pages: Array = []


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
	_pages = Journal.by_place()
	page = maxi(_pages.size() - 1, 0)
	closed.connect(func() -> void:
		if current == self:
			current = null)


func _on_key(key: int) -> bool:
	match key:
		KEY_J, KEY_ESCAPE:
			close()
		KEY_A, KEY_LEFT:
			page = maxi(page - 1, 0)
		KEY_D, KEY_RIGHT:
			page = mini(page + 1, maxi(_pages.size() - 1, 0))
		_:
			return false
	return true


func _on_click(at: Vector2) -> void:
	if not _book().has_point(at):
		close()


func _book() -> Rect2:
	var s := root.size
	return Rect2(s.x * 0.5 - 520, s.y * 0.5 - 330, 1040, 660)


func _draw_screen() -> void:
	dim_background(0.7)
	var r := _book()
	panel(r, PAPER, Color(INK, 0.7))
	root.draw_line(Vector2(r.position.x + r.size.x * 0.5, r.position.y + 16), Vector2(r.position.x + r.size.x * 0.5, r.end.y - 16), Color(INK, 0.25), 2.0)
	text("Expedition journal", Vector2(r.position.x + 40, r.position.y + 54), 30, INK, HORIZONTAL_ALIGNMENT_LEFT, false)
	text("Day %d" % Game.day, Vector2(r.end.x - 40, r.position.y + 54), 18, Color(INK, 0.6), HORIZONTAL_ALIGNMENT_RIGHT, false)
	if _pages.is_empty():
		para("Nothing written yet. Inspect what you find on the way.", Vector2(r.position.x + 40, r.position.y + 110), 440, 19, Color(INK, 0.7))
		return
	var place: String = _pages[page][0]
	var clues: Array = _pages[page][1]
	text(place, Vector2(r.position.x + 40, r.position.y + 98), 22, Color(0.45, 0.2, 0.08), HORIZONTAL_ALIGNMENT_LEFT, false)
	# Two columns: the left page, then the right page.
	var col := 0
	var y := r.position.y + 136
	for e: Dictionary in clues:
		var x := r.position.x + 40 + col * r.size.x * 0.5
		var w := r.size.x * 0.5 - 80
		var h := 36.0 + font.get_multiline_string_size(str(e.get("text", "")), HORIZONTAL_ALIGNMENT_LEFT, w, 16).y + 24.0
		if y + h > r.end.y - 50 and col == 0:
			col = 1
			y = r.position.y + 98
			x = r.position.x + 40 + r.size.x * 0.5
		text("%s · day %d" % [e.get("site", ""), int(e.get("day", 0))], Vector2(x, y), 15, Color(INK, 0.6), HORIZONTAL_ALIGNMENT_LEFT, false)
		text(str(e.get("title", "")), Vector2(x, y + 24), 19, INK, HORIZONTAL_ALIGNMENT_LEFT, false)
		para(str(e.get("text", "")), Vector2(x, y + 48), w, 16, Color(INK, 0.85))
		y += h + 6
	if _pages.size() > 1:
		text("◀ A   %d / %d   D ▶" % [page + 1, _pages.size()], Vector2(r.position.x + r.size.x * 0.5, r.end.y - 22), 16, Color(INK, 0.6), HORIZONTAL_ALIGNMENT_CENTER, false)
