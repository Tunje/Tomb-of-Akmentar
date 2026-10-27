class_name ClueCard
extends ModalScreen
## "Clue found": the site, the clue's title and text on a journal page. Any click or key closes it.

var site_name := ""
var clue := {}


static func open(parent: Node, site: String, clue_data: Dictionary, by: Node = null) -> ClueCard:
	var c := ClueCard.new()
	c.site_name = site
	c.clue = clue_data
	c.player = by
	parent.add_child(c)
	return c


func _on_key(_key: int) -> bool:
	if t > 0.4:
		close()
	return true


func _on_click(_at: Vector2) -> void:
	if t > 0.4:
		close()


func _draw_screen() -> void:
	dim_background(0.6)
	var s := root.size
	var w := minf(680.0 * lerpf(1.0, Subtitles.scale(), 0.6), s.x - 60.0)
	var inner := w - 68.0
	var body := font.get_multiline_string_size(str(clue.get("text", "")), HORIZONTAL_ALIGNMENT_LEFT, inner, fs(19)).y
	var h := minf(fs(16) + fs(30) + fs(21) + body + fs(15) + 150.0, s.y - 60.0)
	var r := Rect2((s - Vector2(w, h)) * 0.5, Vector2(w, h))
	var frame := r.grow(10)
	root.draw_rect(frame, LEATHER)
	root.draw_rect(frame, BRASS, false, 2.0)
	paper(r)
	var x := r.position.x + 34.0
	var y := r.position.y + 26.0
	text("CLUE FOUND", Vector2(x, y + font.get_ascent(fs(16))), fs(16), Color(INK, 0.7), HORIZONTAL_ALIGNMENT_LEFT, false)
	y += font.get_height(fs(16)) + 8.0
	text(site_name, Vector2(x, y + font.get_ascent(fs(30))), fs(30), INK, HORIZONTAL_ALIGNMENT_LEFT, false)
	y += font.get_height(fs(30)) + 4.0
	text(str(clue.get("title", "")), Vector2(x, y + font.get_ascent(fs(21))), fs(21), RUST, HORIZONTAL_ALIGNMENT_LEFT, false)
	y += font.get_height(fs(21)) + 6.0
	root.draw_line(Vector2(x, y), Vector2(r.end.x - 34.0, y), Color(RUST, 0.35), 1.0)
	para(str(clue.get("text", "")), Vector2(x, y + 14.0 + font.get_ascent(fs(19))), inner, fs(19), INK)
	text(Controls.fill("Written into your journal ({journal})"), Vector2(r.end.x - 30.0, r.end.y - 20.0), fs(15), Color(INK, 0.6), HORIZONTAL_ALIGNMENT_RIGHT, false)
