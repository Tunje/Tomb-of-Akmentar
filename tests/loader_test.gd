extends Node
## Loading card test: with test args the change is at once and there's no card; the card (forced,
## as in play) names the act, has its photograph and a tip with the keys filled in, holds the old
## scene paused and the pause menu off, stays at least 1.2 s, then changes and fades away; a load
## over 4 s waits for a key. Windowed: a screenshot of Act 4's card (--shot-dir). The test drives
## from the root (the scenes it changes to replace its own). Prints RESULT lines; exits 0 when
## every check passed. Run with args after "--".

const DEST := "res://tests/loader_dest.tscn"

var _fails := 0
var _dir := "user://loader_shots"


func _ready() -> void:
	Settings.test_mode = true
	get_window().set_flag(Window.FLAG_NO_FOCUS, true)
	_dir = str(TestDriver.parse_args().get("shot-dir", _dir))
	Controls.setup()
	# Off the scene and onto the root: the changes below replace the scene, not the test.
	_run.call_deferred()


func _run() -> void:
	var tree := get_tree()
	get_parent().remove_child(self)
	tree.root.add_child(self)
	_check(Loader.titles_for("res://act4.tscn") == ["Act 4", "The Tombs of Akmentar"], "Act 4's card: its title (%s)" % [Loader.titles_for("res://act4.tscn")])
	_check(Loader.titles_for("res://act8_boat.tscn")[0] == "Act 8", "a piece of an act: the act's")
	for a in range(1, 10):
		if not ResourceLoader.exists("res://assets/ui/loading/act%d.png" % a):
			_check(false, "Act %d has its photograph" % a)

	# Test args: at once, no card.
	Loader.go(tree, DEST)
	await _frames(3)
	_check(Loader.current == null and tree.current_scene and tree.current_scene.scene_file_path == DEST, "with test args: at once, no card")

	# A card that stays (a slow load), for the picture: Act 4's.
	Loader.force = true
	Loader.fake_load = 100.0
	Loader.go(tree, "res://act4.tscn")
	await _frames(3)
	var card := Loader.current
	_check(card != null and card._photo != null, "the card: Act 4's photograph")
	_check(Loader.last_title == "The Tombs of Akmentar" and Loader.last_tip != "" and not "{" in Loader.last_tip, "its title, and a tip with the keys in (%s)" % Loader.last_tip)
	_check(tree.paused and not PauseMenu.allowed(tree, null), "the old scene waits, paused; no pause menu over the card")
	await _shot("loading_card.png")
	if card:
		card.queue_free()  # (never let it switch: Act 4 isn't wanted here)
	tree.paused = false
	await _frames(2)

	# A quick load: the card stays 1.2 s, then the scene changes and the card fades.
	Loader.fake_load = 0.0
	tree.change_scene_to_file(DEST)
	await _frames(3)
	var from := tree.current_scene
	var t0 := Time.get_ticks_msec()
	Loader.go(tree, DEST)
	while tree.current_scene == from and Time.get_ticks_msec() - t0 < 8000:
		await tree.process_frame
	var took := (Time.get_ticks_msec() - t0) / 1000.0
	_check(tree.current_scene != from and took >= Loader.MIN_SHOW - 0.05, "the card stays at least %.1f s (%.2f s)" % [Loader.MIN_SHOW, took])
	_check(took < 3.0, "and no longer than the load needs (%.2f s)" % took)
	await tree.create_timer(0.8).timeout
	_check(tree.root.find_children("*", "Loader", true, false).is_empty() and not tree.paused, "then fades away; the game runs")

	# A slow load: after 4 s, a key to go on.
	Loader.fake_load = 4.3
	from = tree.current_scene
	Loader.go(tree, DEST)
	await tree.create_timer(5.0).timeout
	_check(tree.current_scene == from and Loader.current != null and Loader.current._asked, "a load over 4 s: 'Press any key', and it waits")
	await _shot("loading_card_key.png")
	var key := InputEventKey.new()
	key.keycode = KEY_SPACE
	key.pressed = true
	Input.parse_input_event(key)
	Input.flush_buffered_events()
	await _frames(4)
	_check(tree.current_scene != from, "a key: on")
	Loader.force = false
	Loader.fake_load = 0.0
	await tree.create_timer(0.6).timeout
	print("RESULT %s (%d failed)" % ["PASS" if _fails == 0 else "FAIL", _fails])
	tree.quit(0 if _fails == 0 else 1)


func _shot(file: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await get_tree().create_timer(0.5).timeout
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
