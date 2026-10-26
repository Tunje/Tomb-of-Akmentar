class_name EpilogueShow
extends ModalScreen
## "Where are they now?": one album card per character, a photo (the portrait image, or a
## silhouette placeholder), a name, a place / date line and a paragraph. Each character's text is
## the first variant whose "if" passes (Game.check); a character with no passing variant is left
## out. Click / Space / → next, ← back; after the last card it closes. res://epilogue/<id>.json:
##   {"title": "Where are they now?",
##    "cards": [{"who": "eleanor", "name": "Eleanor Whitmore", "portrait": "res://...png",
##               "variants": [{"if": {...}, "caption": "London, 1932", "text": "..."}, {"text": "..."}]}]}

const DIR := "res://epilogue"

var show_id := ""
var title := ""
var cards: Array = []   # the chosen cards: {"who", "name", "caption", "text", "portrait"}
var index := 0

var _tex := {}


static func open(parent: Node, id: String, by: Node = null) -> EpilogueShow:
	var e := EpilogueShow.new()
	e.player = by
	e.show_id = id
	parent.add_child(e)
	return e


## The cards that `id` would show now (Game state decides each character's variant).
static func pick_cards(id: String) -> Array:
	var path := DIR.path_join(id + ".json")
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	if not d is Dictionary:
		push_error("EpilogueShow: can't read %s" % path)
		return []
	var out := []
	for c: Dictionary in d.get("cards", []):
		for v: Dictionary in c.get("variants", []):
			if Game.check(v.get("if", {})):
				out.append({"who": c.get("who", ""), "name": c.get("name", ""), "portrait": c.get("portrait", ""),
					"caption": v.get("caption", ""), "text": v.get("text", ""), "variant": v.get("id", "")})
				break
	return out


func _opened() -> void:
	var path := DIR.path_join(show_id + ".json")
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else {}
	title = str(d.get("title", "Where are they now?")) if d is Dictionary else ""
	cards = pick_cards(show_id)
	for c: Dictionary in cards:
		var p := str(c.portrait)
		if p != "" and ResourceLoader.exists(p):
			_tex[p] = load(p)
	if cards.is_empty():
		close()


func next() -> void:
	if index >= cards.size() - 1:
		close()
	else:
		index += 1
		t = 0.0


func back() -> void:
	if index > 0:
		index -= 1
		t = 0.0


func _on_key(key: int) -> bool:
	if key in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER, KEY_RIGHT, KEY_D]:
		next()
	elif key in [KEY_LEFT, KEY_A]:
		back()
	elif key == KEY_ESCAPE:
		close()
	else:
		return false
	return true


func _on_click(_at: Vector2) -> void:
	if t > 0.3:
		next()


func _draw_screen() -> void:
	var s := root.size
	root.draw_rect(Rect2(Vector2.ZERO, s), Color(0.06, 0.045, 0.03))
	if cards.is_empty():
		return
	var a := clampf(t / 0.3, 0.0, 1.0)
	text(title, Vector2(s.x * 0.5, 70), 30, Color(GOLD, a), HORIZONTAL_ALIGNMENT_CENTER)
	var c: Dictionary = cards[index]
	# The album page: a photo on the left with its corners, the story on the right.
	var page := Rect2(s.x * 0.5 - 560, s.y * 0.5 - 250, 1120, 500)
	panel(page, Color(PAPER, a), Color(INK, 0.5 * a))
	var photo := Rect2(page.position.x + 46, page.position.y + 46, 330, 408)
	root.draw_rect(photo.grow(10), Color(0.97, 0.94, 0.86, a))
	var p := str(c.portrait)
	if _tex.has(p):
		root.draw_texture_rect(_tex[p], photo, false, Color(1, 0.92, 0.8, a))
	else:
		_silhouette(photo, a)
	for k in 4:  # photo corners
		var cx := photo.position.x - 10 if k % 2 == 0 else photo.end.x + 10
		var cy := photo.position.y - 10 if k < 2 else photo.end.y + 10
		var dx := 24.0 if k % 2 == 0 else -24.0
		var dy := 24.0 if k < 2 else -24.0
		root.draw_colored_polygon(PackedVector2Array([Vector2(cx, cy), Vector2(cx + dx, cy), Vector2(cx, cy + dy)]), Color(INK, 0.8 * a))
	var x := photo.end.x + 50
	var w := page.end.x - x - 46
	text(str(c.name), Vector2(x, page.position.y + 86), 34, Color(INK, a), HORIZONTAL_ALIGNMENT_LEFT, false)
	text(str(c.caption), Vector2(x, page.position.y + 122), 18, Color(0.45, 0.2, 0.08, a), HORIZONTAL_ALIGNMENT_LEFT, false)
	para(str(c.text), Vector2(x, page.position.y + 172), w, 20, Color(INK, a))
	text("%d / %d   ·   click or Space for the next" % [index + 1, cards.size()], Vector2(s.x * 0.5, page.end.y + 44), 16, Color(DIM, a), HORIZONTAL_ALIGNMENT_CENTER)


## A sepia head-and-shoulders placeholder until real portraits exist.
func _silhouette(r: Rect2, a: float) -> void:
	root.draw_rect(r, Color(0.55, 0.45, 0.32, a))
	var c := r.get_center()
	var col := Color(0.28, 0.2, 0.12, a)
	root.draw_circle(c + Vector2(0, -40), 62.0, col)
	var shoulders := PackedVector2Array()
	for k in 25:
		var ang := PI + PI * k / 24.0
		shoulders.append(c + Vector2(cos(ang) * 130.0, 150.0 + sin(ang) * 120.0))
	root.draw_colored_polygon(shoulders, col)
