extends Node3D
## Title screen test (run with --save-slot=<name>: its own last rest). Without a save there's no
## Continue; New game, Load game, Chapters (Acts 1-9 + Playtest range), Options, Credits and Quit
## are there and reach their screens; New game asks first once a save exists; with a save,
## Continue shows its summary and goes into the act it was saved in (a watcher on the root sees
## the scene). Prints RESULT lines; exits 0 when every check passed. --shot-dir=C:/path (windowed).

var _fails := 0
var _dir := "user://title_shots"
var title: TitleScreen


func _ready() -> void:
	Settings.test_mode = true
	get_window().set_flag(Window.FLAG_NO_FOCUS, true)
	var args := TestDriver.parse_args()
	_dir = str(args.get("shot-dir", _dir))
	_check(args.has("save-slot"), "run with --save-slot (its own last rest)")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveSlots.path("main")))
	title = (load("res://title.tscn") as PackedScene).instantiate()
	add_child(title)
	await _frames(3)
	_check(_find("Continue") == null, "no save: no Continue")
	for b in ["New game", "Load game", "Chapters", "Options", "Credits", "Quit"]:
		_check(_find(b) != null, "%s is there" % b)
	_find("Load game").pressed.emit()
	await _frames(2)
	_check(LoadScreen.is_open(), "Load game opens the Load screen")
	LoadScreen.current.close()
	_find("Options").pressed.emit()
	await _frames(2)
	_check(OptionsScreen.is_open(), "Options opens the options")
	OptionsScreen.current.close()
	_find("Chapters").pressed.emit()
	await _frames(2)
	var acts := 0
	for b in title.find_children("*", "Button", true, false):
		acts += int((b as Button).text.begins_with("Act ") and not b.is_queued_for_deletion())
	_check(acts == 9 and _find("Playtest range") != null, "Chapters: 9 acts and the playtest range (%d)" % acts)
	_check(_find("Act 5 · The Awakening of Akmentar") != null, "with their titles (Act 5 · The Awakening of Akmentar)")
	_find("Back").pressed.emit()
	await _frames(2)
	_find("Credits").pressed.emit()
	await _frames(2)
	_check(_has_label("A game by Simon") and _has_label("Made with Godot Engine"), "Credits from menus/title.json")
	_find("Back").pressed.emit()
	await _frames(2)
	# A save: Continue appears, with its summary; New game asks first.
	Game.reset()
	Game.act = 4
	Game.place = "act4_camp"
	Game.save_game()
	title._main_menu()
	await _frames(2)
	var cont := _find("Continue")
	_check(cont != null, "with a save: Continue")
	cont.grab_focus()
	await _frames(2)
	_check(title._info.text.begins_with("Act 4 · Akmentar, the camp"), "its summary on focus (%s)" % title._info.text)
	_find("New game").pressed.emit()
	await _frames(2)
	_check(_has_label("Start a new game? Your last rest stays until you rest again."), "New game asks first when there's a save")
	_find("No").pressed.emit()
	await _frames(3)
	if DisplayServer.get_name() != "headless":
		await get_tree().create_timer(1.0).timeout
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute(_dir)
		get_viewport().get_texture().get_image().save_png(_dir.path_join("title.png"))
		print("RESULT shot %s" % _dir.path_join("title.png"))
	var w := Watcher.new()
	w.fails = _fails
	get_tree().root.add_child(w)
	_find("Continue").pressed.emit()  # -> act4.tscn; the watcher reports


class Watcher extends Node:
	var fails := 0
	var _t := 0.0

	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS

	func _process(delta: float) -> void:
		_t += delta
		var s := get_tree().current_scene
		var there := s != null and s.scene_file_path == "res://act4.tscn"
		if there or _t > 10.0:
			print("RESULT %s Continue goes into the act it was saved in (%s)" % ["ok  " if there else "FAIL", s.scene_file_path if s else "-"])
			fails += int(not there)
			DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveSlots.path("main")))
			print("RESULT %s (%d failed)" % ["PASS" if fails == 0 else "FAIL", fails])
			get_tree().quit(0 if fails == 0 else 1)
			set_process(false)


func _find(text: String) -> Button:
	for b in title.find_children("*", "Button", true, false):
		if (b as Button).text == text and not b.is_queued_for_deletion():
			return b
	return null


func _has_label(text: String) -> bool:
	for l in title.find_children("*", "Label", true, false):
		if (l as Label).text == text and not l.is_queued_for_deletion():
			return true
	return false


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _check(ok: bool, what: String) -> void:
	print("RESULT %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_fails += 1
