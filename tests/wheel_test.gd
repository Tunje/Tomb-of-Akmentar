extends Node3D
## Conversation wheel look test: the letterbox slides in; a speaker with a portrait (Eleanor) gets
## it in the brass oval, and it stays through the wheel; six choices, one of each tone, sit at their
## Mass Effect places (friendly top right, neutral right, hostile bottom right, asks on the left,
## leaving bottom left) in their tone's ink; the pad's stick points at them; the text size scales
## the slips. Windowed: a screenshot (--shot-dir). Prints RESULT lines; exits 0 when every check
## passed. Run with args after "--".

var _fails := 0
var _dir := "user://wheel_shots"


func _ready() -> void:
	Settings.test_mode = true
	get_window().set_flag(Window.FLAG_NO_FOCUS, true)
	_dir = str(TestDriver.parse_args().get("shot-dir", _dir))
	Controls.setup()
	var level := Level.new()
	add_child(level)
	var cam := Camera3D.new()
	add_child(cam)
	cam.position = level.player_spawn + Vector3(0, 1.7, 6)
	cam.make_current()
	var w := ConversationWheel.new()
	add_child(w)
	await get_tree().process_frame
	_check(w.letterbox() < 0.5, "the letterbox starts sliding in (%.2f)" % w.letterbox())
	w.show_line("Eleanor Whitmore", "You came back. I wasn't sure you would.", "eleanor")
	await get_tree().create_timer(0.6).timeout
	_check(is_equal_approx(w.letterbox(), 1.0), "and is in after %.2f s" % ConversationWheel.LETTERBOX_IN)
	_check(w.portrait_id == "eleanor", "Eleanor's portrait in the oval")
	w.show_line("You", "I said I would.", "player")
	_check(w.portrait_id == "eleanor", "it stays while you answer")
	w.show_line("Professor El-Gohary", "Well?", "archivist")
	_check(w.portrait_id == "eleanor", "someone without a portrait doesn't take it away")
	w.show_line("Eleanor Whitmore", "Well? What now?", "eleanor")
	var labels := ["Promise her the credit", "Ask about the tomb", "Tell her the plan", "Mention the guardian", "Make no promises", "Leave"]
	var slots := ["ur", "ul", "r", "l", "lr", "ll"]
	var tones := ["friendly", "ask", "neutral", "ask", "hostile", "leave"]
	w.show_choices(labels, slots, tones)
	await _frames(3)
	var c := w._center()
	var places := {"ur": Vector2(1, -1), "r": Vector2(1, 0), "lr": Vector2(1, 1), "ul": Vector2(-1, -1), "l": Vector2(-1, 0), "ll": Vector2(-1, 1)}
	var placed := true
	for i in labels.size():
		var at: Vector2 = w._labels[i].get_global_rect().get_center() - c
		var want: Vector2 = places[slots[i]]
		placed = placed and signf(at.x) == want.x and (want.y == 0 or signf(at.y) == want.y)
	_check(placed, "each at its tone's place on the wheel")
	_check(w.tone_of(0) == "friendly" and w.tone_of(4) == "hostile" and w.tone_of(5) == "leave", "in its tone")
	var ink_hostile := w._labels[4].get_theme_color("font_color")
	var ink_friendly := w._labels[0].get_theme_color("font_color")
	_check(ink_hostile.r > ink_hostile.b and ink_friendly.b > ink_friendly.r, "hostile in red ink, friendly in blue")
	# The pad: the stick points.
	Controls.last_pad = true
	Input.action_press("move_right")
	await _frames(2)
	_check(w.hovered == 2, "the stick right: the neutral one (%d)" % w.hovered)
	Input.action_release("move_right")
	Input.action_press("move_left")
	Input.action_press("move_back")
	await _frames(2)
	_check(w.hovered == 5, "down-left: leave (%d)" % w.hovered)
	Input.action_release("move_left")
	Input.action_release("move_back")
	Input.action_press("move_right")
	Input.action_press("move_back")
	await _frames(2)
	Input.action_release("move_right")
	Input.action_release("move_back")
	_check(w.hovered == 4, "down-right: the hostile one (%d)" % w.hovered)
	await _frames(2)
	await _shot("wheel.png")
	# Text size: the slips grow.
	var h := w._labels[0].get_minimum_size().y
	Settings.set_value("text_size", "XL", get_tree())
	w.show_choices(labels, slots, tones)
	await _frames(3)
	_check(w._labels[0].get_minimum_size().y > h * 1.3, "text size XL: the slips grow (%.0f -> %.0f px)" % [h, w._labels[0].get_minimum_size().y])
	await _shot("wheel_xl.png")
	Settings.set_value("text_size", "M", get_tree())
	Controls.last_pad = false
	print("RESULT %s (%d failed)" % ["PASS" if _fails == 0 else "FAIL", _fails])
	get_tree().quit(0 if _fails == 0 else 1)


func _shot(file: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(_dir)
	get_viewport().get_texture().get_image().save_png(_dir.path_join(file))
	print("RESULT shot %s" % _dir.path_join(file))


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _check(ok: bool, what: String) -> void:
	print("RESULT %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_fails += 1
