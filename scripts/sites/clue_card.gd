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
	var r := Rect2(s.x * 0.5 - 340, s.y * 0.5 - 200, 680, 400)
	panel(r, PAPER, Color(INK, 0.6))
	text("CLUE FOUND", Vector2(r.position.x + 34, r.position.y + 46), 16, Color(INK, 0.7), HORIZONTAL_ALIGNMENT_LEFT, false)
	text(site_name, Vector2(r.position.x + 34, r.position.y + 84), 30, INK, HORIZONTAL_ALIGNMENT_LEFT, false)
	text(str(clue.get("title", "")), Vector2(r.position.x + 34, r.position.y + 124), 21, Color(0.45, 0.2, 0.08), HORIZONTAL_ALIGNMENT_LEFT, false)
	para(str(clue.get("text", "")), Vector2(r.position.x + 34, r.position.y + 164), r.size.x - 68, 19, INK)
	text(Controls.fill("Written into your journal ({journal})"), Vector2(r.end.x - 30, r.end.y - 24), 15, Color(INK, 0.6), HORIZONTAL_ALIGNMENT_RIGHT, false)
