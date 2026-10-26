class_name JournalScreen
extends ModalScreen
## The journal (J), two tabs (Tab or a click on them switches):
## - Clues: by place, the newest place on its own page; A / D or the arrow keys turn pages.
## - People: everyone you've met (Codex), a list on the left and their page on the right;
##   W / S or the arrows pick, A / D turn the list's pages.
## J, Esc or a click outside closes. JournalScreen.toggle(self, player).

const ACTION := "journal"   # the input action main.gd binds to J

static var current: JournalScreen

const PEOPLE_PER_PAGE := 14

var page := 0
var tab := "clues"            # "clues" or "people"
var person := 0               # the selected person (People)
var _pages: Array = []
var _people: Array = []


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
	_people = Codex.pages()
	closed.connect(func() -> void:
		if current == self:
			current = null)


func _on_key(key: int) -> bool:
	match key:
		KEY_J, KEY_ESCAPE:
			close()
		KEY_TAB:
			switch_tab()
		KEY_A, KEY_LEFT:
			if tab == "clues":
				page = maxi(page - 1, 0)
			else:
				person = maxi(person - PEOPLE_PER_PAGE, 0)
		KEY_D, KEY_RIGHT:
			if tab == "clues":
				page = mini(page + 1, maxi(_pages.size() - 1, 0))
			else:
				person = mini(person + PEOPLE_PER_PAGE, maxi(_people.size() - 1, 0))
		KEY_W, KEY_UP:
			person = maxi(person - 1, 0)
		KEY_S, KEY_DOWN:
			person = mini(person + 1, maxi(_people.size() - 1, 0))
		_:
			return false
	return true


func switch_tab() -> void:
	tab = "people" if tab == "clues" else "clues"


func _on_click(at: Vector2) -> void:
	if not _book().has_point(at):
		close()
		return
	for t in ["clues", "people"]:
		if _tab_rect(t).has_point(at):
			tab = t
			return
	if tab == "people":
		for i in _people.size():
			if _name_rect(i).has_point(at):
				person = i
				return


func _tab_rect(t: String) -> Rect2:
	var r := _book()
	return Rect2(r.end.x - (300 if t == "clues" else 170), r.position.y + 26, 120, 36)


## Where person i's name sits in the list (only those on the current list page).
func _name_rect(i: int) -> Rect2:
	var r := _book()
	if i / PEOPLE_PER_PAGE != person / PEOPLE_PER_PAGE:
		return Rect2()
	return Rect2(r.position.x + 30, r.position.y + 112 + (i % PEOPLE_PER_PAGE) * 36, r.size.x * 0.5 - 60, 34)


func _book() -> Rect2:
	var s := root.size
	return Rect2(s.x * 0.5 - 520, s.y * 0.5 - 330, 1040, 660)


func _draw_screen() -> void:
	dim_background(0.7)
	var r := _book()
	panel(r, PAPER, Color(INK, 0.7))
	root.draw_line(Vector2(r.position.x + r.size.x * 0.5, r.position.y + 16), Vector2(r.position.x + r.size.x * 0.5, r.end.y - 16), Color(INK, 0.25), 2.0)
	text("Expedition journal", Vector2(r.position.x + 40, r.position.y + 54), 30, INK, HORIZONTAL_ALIGNMENT_LEFT, false)
	for t in ["clues", "people"]:
		var tr := _tab_rect(t)
		if t == tab:
			root.draw_rect(tr, Color(INK, 0.12))
		text("Clues" if t == "clues" else "People", tr.get_center() + Vector2(0, 7), 19, INK if t == tab else Color(INK, 0.5), HORIZONTAL_ALIGNMENT_CENTER, false)
	text("Day %d · Tab" % Game.day, Vector2(r.end.x - 40, r.position.y + 84), 14, Color(INK, 0.5), HORIZONTAL_ALIGNMENT_RIGHT, false)
	if tab == "people":
		_draw_people(r)
		return
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


func _draw_people(r: Rect2) -> void:
	if _people.is_empty():
		para("No one yet. The people you meet will be written here.", Vector2(r.position.x + 40, r.position.y + 110), 440, 19, Color(INK, 0.7))
		return
	person = clampi(person, 0, _people.size() - 1)
	var first := (person / PEOPLE_PER_PAGE) * PEOPLE_PER_PAGE
	for i in range(first, mini(first + PEOPLE_PER_PAGE, _people.size())):
		var nr := _name_rect(i)
		if i == person:
			root.draw_rect(nr, Color(INK, 0.1))
		var p: Dictionary = _people[i]
		text(str(p.name), nr.position + Vector2(10, 23), 18, INK, HORIZONTAL_ALIGNMENT_LEFT, false)
	var pages := int(ceil(_people.size() / float(PEOPLE_PER_PAGE)))
	if pages > 1:
		text("◀ A   %d / %d   D ▶" % [person / PEOPLE_PER_PAGE + 1, pages], Vector2(r.position.x + r.size.x * 0.25, r.end.y - 22), 16, Color(INK, 0.6), HORIZONTAL_ALIGNMENT_CENTER, false)
	# The page: name, role, what you know, then the notes.
	var sel: Dictionary = _people[person]
	var x := r.position.x + r.size.x * 0.5 + 40
	var w := r.size.x * 0.5 - 80
	var y := r.position.y + 128
	text(str(sel.name), Vector2(x, y), 24, INK, HORIZONTAL_ALIGNMENT_LEFT, false)
	text(str(sel.role), Vector2(x, y + 28), 16, Color(0.45, 0.2, 0.08), HORIZONTAL_ALIGNMENT_LEFT, false)
	y += 58
	para(str(sel.text), Vector2(x, y), w, 17, Color(INK, 0.9))
	y += font.get_multiline_string_size(str(sel.text), HORIZONTAL_ALIGNMENT_LEFT, w, 17).y + 18
	for n in sel.notes:
		para("· " + str(n), Vector2(x, y), w, 16, Color(INK, 0.8))
		y += font.get_multiline_string_size("· " + str(n), HORIZONTAL_ALIGNMENT_LEFT, w, 16).y + 10
