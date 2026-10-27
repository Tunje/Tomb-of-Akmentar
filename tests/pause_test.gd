extends Node3D
## PauseMenu test: Esc and the pad's Start open and close it (paused, the mouse free, then captured
## again); Options and Load game open their pages over it and come back; Journal closes it and
## opens the journal; Quit game asks first (No goes back); Restart from checkpoint fires
## Checkpoint.retry (this scene reloads: the test carries on from a SceneTree meta); Quit to title
## loads main.tscn (a watcher on the root sees it). The objective shows in the menu.
## Prints RESULT lines; exits 0 when every check passed. Run with args after "--".

var _fails := 0
var player: Player
var hud: Hud


func _ready() -> void:
	Settings.test_mode = true
	get_window().set_flag(Window.FLAG_NO_FOCUS, true)
	Checkpoint.take(self)
	Controls.setup()
	var level := Level.new()
	add_child(level)
	player = Player.new()
	add_child(player)
	player.global_position = level.player_spawn
	hud = Hud.new()
	hud.player = player
	add_child(hud)
	for i in 3:
		await get_tree().process_frame
	var tree := get_tree()
	if tree.has_meta("pause_test_fails"):  # back after Restart from checkpoint
		_fails = int(tree.get_meta("pause_test_fails"))
		tree.remove_meta("pause_test_fails")
		_check(true, "Restart from checkpoint reloaded the scene (Checkpoint.retry)")
		_check(not Subtitles.current._label.visible, "the failed try's subtitle is gone after the retry")
		_check(Objective.current() == "Test the pause menu", "the objective carries over a retry of the same scene")
		await _quit_to_title()
		return
	await _open_close()
	await _pages()
	await _journal()
	await _quit_asks()
	# Restart: the scene reloads; _ready carries on above.
	tree.set_meta("pause_test_fails", _fails)
	Objective.set_goal("Test the pause menu")
	var m := await _open_menu()
	_check(_has_label(m, "Objective: Test the pause menu"), "the objective shows in the menu")
	var restart := _find(m, "Restart from checkpoint")
	_check(restart != null, "a scene with a checkpoint offers Restart from checkpoint")
	if restart == null:
		_finish()
		return
	Subtitles.say(get_tree(), "mahmoud", "Mahmoud Fawzi", "Reloading!", 30.0)  # still up at the retry
	restart.pressed.emit()


func _open_close() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_key(KEY_ESCAPE)
	await _frames(3)
	_check(PauseMenu.is_open() and get_tree().paused, "Esc opens the pause menu and pauses")
	_check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "the mouse is free while it's up")
	_key(KEY_ESCAPE)
	await _frames(3)
	_check(not PauseMenu.is_open() and not get_tree().paused, "Esc again resumes")
	if DisplayServer.get_name() != "headless":  # (headless can't capture the mouse at all)
		_check(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "and captures the mouse again (as before)")
	_pad(JOY_BUTTON_START)
	await _frames(3)
	_check(PauseMenu.is_open(), "the pad's Start opens it")
	_pad(JOY_BUTTON_START)
	await _frames(3)
	_check(not PauseMenu.is_open() and not get_tree().paused, "Start again resumes")
	_pad(JOY_BUTTON_START)
	await _frames(3)
	_pad(JOY_BUTTON_B)
	await _frames(3)
	_check(not PauseMenu.is_open(), "B resumes too")


func _pages() -> void:
	var m := await _open_menu()
	_find(m, "Options").pressed.emit()
	await _frames(2)
	_check(OptionsScreen.is_open(), "Options opens the options")
	_key(KEY_ESCAPE)
	await _frames(2)
	_check(not OptionsScreen.is_open() and PauseMenu.is_open() and get_tree().paused, "Esc there comes back to the pause menu")
	_find(PauseMenu.current, "Load game").pressed.emit()
	await _frames(2)
	_check(LoadScreen.is_open(), "Load game opens the Load screen")
	_key(KEY_ESCAPE)
	await _frames(2)
	_check(not LoadScreen.is_open() and PauseMenu.is_open(), "and back")
	PauseMenu.current.resume()
	await _frames(2)


func _journal() -> void:
	var m := await _open_menu()
	_find(m, "Journal").pressed.emit()
	await _frames(3)
	_check(not PauseMenu.is_open() and ActionMenu.ui_open(), "Journal closes the menu and opens the journal")
	JournalScreen.toggle(self, player)
	await _frames(3)


func _quit_asks() -> void:
	var m := await _open_menu()
	_find(m, "Quit game").pressed.emit()
	await _frames(2)
	_check(_has_label(m, "Quit the game? Progress since your last rest will be lost."), "Quit game asks first")
	_find(m, "No").pressed.emit()
	await _frames(2)
	_check(_find(m, "Resume") != null, "No goes back to the menu")
	_find(m, "Quit to title").pressed.emit()
	await _frames(2)
	_check(_has_label(m, "Quit to the title? Progress since your last rest will be lost."), "Quit to title asks first")
	_find(m, "No").pressed.emit()
	await _frames(2)
	m.resume()
	await _frames(2)


func _quit_to_title() -> void:
	var w := Watcher.new()
	w.test = self
	get_tree().root.add_child(w)
	var m := await _open_menu()
	_find(m, "Quit to title").pressed.emit()
	await _frames(2)
	_find(m, "Yes").pressed.emit()  # -> main.tscn; the watcher reports


## On the root (it outlives this scene): main.tscn loaded after Quit to title.
class Watcher extends Node:
	var test: Node
	var fails := 0
	var _t := 0.0

	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS
		fails = test._fails

	func _process(delta: float) -> void:
		_t += delta
		var s := get_tree().current_scene
		var at_title := s != null and s.scene_file_path == "res://title.tscn"
		if at_title or _t > 8.0:
			print("RESULT %s Quit to title loads title.tscn (%s)" % ["ok  " if at_title else "FAIL", s.scene_file_path if s else "-"])
			fails += int(not at_title)
			print("RESULT %s (%d failed)" % ["PASS" if fails == 0 else "FAIL", fails])
			get_tree().quit(0 if fails == 0 else 1)
			set_process(false)


func _finish() -> void:
	print("RESULT %s (%d failed)" % ["PASS" if _fails == 0 else "FAIL", _fails])
	get_tree().quit(0 if _fails == 0 else 1)


func _open_menu() -> PauseMenu:
	if not PauseMenu.is_open():
		_key(KEY_ESCAPE)
		await _frames(3)
	return PauseMenu.current


func _find(root: Node, text: String) -> Button:
	if root == null:
		return null
	for b in root.find_children("*", "Button", true, false):
		if (b as Button).text == text and not b.is_queued_for_deletion():
			return b
	return null


func _has_label(root: Node, text: String) -> bool:
	for l in root.find_children("*", "Label", true, false):
		if (l as Label).text == text and not l.is_queued_for_deletion():
			return true
	return false


func _key(code: Key) -> void:
	for down in [true, false]:
		var e := InputEventKey.new()
		e.keycode = code
		e.physical_keycode = code
		e.pressed = down
		Input.parse_input_event(e)


func _pad(b: JoyButton) -> void:
	for down in [true, false]:
		var e := InputEventJoypadButton.new()
		e.device = 0
		e.button_index = b
		e.pressed = down
		Input.parse_input_event(e)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _check(ok: bool, what: String) -> void:
	print("RESULT %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_fails += 1
