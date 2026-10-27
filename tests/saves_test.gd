extends Node3D
## Save slots test (run with args after "--": every slot goes to its "test_" file): a save in
## slot 2 loads back with its place, flags and party; its thumbnail exists (windowed runs); its
## summary reads right; the last rest copies into a slot; a slot deletes (the last rest won't);
## the migration keeps the old save (in its own folder); the rest prompt keeps a copy; the Load
## screen lists the four entries; Simon's real saves and thumbnails are untouched.
## Prints RESULT lines; exits 0 when every check passed. --shot-dir=C:/path for its screenshot.

const REAL := ["main.json", "slot1.json", "slot2.json", "slot3.json", "main.png", "slot1.png", "slot2.png", "slot3.png", "main.before-slots.json"]
const MIGRATE_DIR := "user://saves_migrate_test"

var _fails := 0
var _dir := "user://saves_shots"


func _ready() -> void:
	Settings.test_mode = true
	get_window().set_flag(Window.FLAG_NO_FOCUS, true)
	var args := TestDriver.parse_args()
	_dir = str(args.get("shot-dir", _dir))
	_check(not OS.get_cmdline_user_args().is_empty(), "run with args after \"--\" (the test slots)")
	var before := _real_times()
	var level := Level.new()  # something on screen for the thumbnail
	add_child(level)
	var cam := Camera3D.new()
	add_child(cam)
	cam.position = level.player_spawn + Vector3(0, 3, 8)
	cam.make_current()
	for i in 5:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	_save_and_load()
	_copy_and_delete()
	_migrate()
	await _prompt()
	await _load_screen()
	_check(_real_times() == before, "Simon's real saves and thumbnails untouched")
	var own := str(TestDriver.parse_args().get("save-slot", "test"))
	# Its own files (the shared test.json stays: other sessions' bots use it).
	for s in ([own] if own != "test" else []) + [own + "_slot1", own + "_slot2", own + "_slot3"]:
		for ext in [".json", ".png"]:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(Game.SAVE_DIR.path_join(s + ext)))
	print("RESULT %s (%d failed)" % ["PASS" if _fails == 0 else "FAIL", _fails])
	get_tree().quit(0 if _fails == 0 else 1)


func _save_and_load() -> void:
	Game.reset()
	Game.act = 4
	Game.place = "act4_camp"
	Game.money = 123
	Game.set_flag("saves_test_flag", 7)
	Game.companion("mahmoud")["recruited"] = true
	Game.play_time = 3725.0
	_check(Game.save_game("slot2"), "saved to slot 2")
	var own := str(TestDriver.parse_args().get("save-slot", "test"))
	_check(Game._slot("main") == own and Game._slot("slot2") == own + "_slot2" and Game._slot("test") == own,
		"this run's own save files (--save-slot): %s, %s" % [Game._slot("main"), Game._slot("slot2")])
	_check(FileAccess.file_exists(Game.SAVE_DIR.path_join(own + "_slot2.json")), "it went to the test file (%s_slot2.json)" % own)
	if DisplayServer.get_name() != "headless":
		_check(FileAccess.file_exists(SaveSlots.thumb_path("slot2")), "its thumbnail exists (%s)" % SaveSlots.thumb_path("slot2"))
		var img := Image.load_from_file(ProjectSettings.globalize_path(SaveSlots.thumb_path("slot2")))
		_check(img and img.get_size() == SaveSlots.THUMB, "at %s" % (img.get_size() if img else Vector2i.ZERO))
	var want := Game.to_dict().duplicate(true)
	Game.reset()
	_check(Game.load_game("slot2"), "loaded slot 2")
	# (JSON brings numbers back as floats: compare the flag's value, not the dictionaries' types)
	_check(Game.place == want.place and Game.flags.keys() == want.flags.keys() and int(Game.flag("saves_test_flag", 0)) == 7
		and Game.party() == ["mahmoud"] and Game.money == 123,
		"place, flags, party and money are back (%s, %s)" % [Game.place, Game.party()])
	_check(is_equal_approx(Game.play_time, 3725.0), "and the play time")
	var info := SaveSlots.info("slot2")
	_check(info.exists and info.act == 4 and info.place == "Akmentar, the camp" and info.money == 123 and info.party.size() == 1
		and info.saved_at > 0.0, "its summary: Act %d, %s, %s, £%d" % [info.act, info.place, info.party, info.money])
	_check(SaveSlots.play_time_text(info.play_time) == "1:02 played", "play time shown as %s" % SaveSlots.play_time_text(info.play_time))
	_check(SaveSlots.date_text(info.saved_at).length() > 10, "saved %s" % SaveSlots.date_text(info.saved_at))


func _copy_and_delete() -> void:
	Game.place = "act4_end"
	Game.save_game()  # the last rest (test.json)
	_check(Game.resume_slot == "main", "a save makes the last rest the one a death loads")
	_check(SaveSlots.copy("main", "slot1"), "the last rest copied into slot 1")
	_check(SaveSlots.info("slot1").place == SaveSlots.place_name("act4_end"), "slot 1 holds it")
	_check(SaveSlots.delete("slot1") and not SaveSlots.info("slot1").exists, "slot 1 deleted")
	_check(not SaveSlots.delete("main") and SaveSlots.info("main").exists, "the last rest can't be deleted from the slots")


func _migrate() -> void:
	var dir := ProjectSettings.globalize_path(MIGRATE_DIR)
	DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(MIGRATE_DIR.path_join("main.json"), FileAccess.WRITE)
	f.store_string("{\"act\": 3, \"place\": \"act3_end\"}")
	f.close()
	_check(SaveSlots.migrate(MIGRATE_DIR), "the migration ran")
	var old := FileAccess.get_file_as_string(MIGRATE_DIR.path_join("main.json"))
	var kept := FileAccess.get_file_as_string(MIGRATE_DIR.path_join(SaveSlots.BACKUP))
	_check(old != "" and old == kept, "it kept the old save as it was, and copied it beside")
	_check(not SaveSlots.migrate(MIGRATE_DIR), "only once (the copy is never overwritten)")
	for n in ["main.json", SaveSlots.BACKUP]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(MIGRATE_DIR.path_join(n)))
	DirAccess.remove_absolute(dir)


func _prompt() -> void:
	var p := SavePrompt.new()
	get_tree().root.add_child(p)
	SavePrompt.current = p
	await get_tree().process_frame
	_check(get_tree().paused, "the rest prompt pauses while it's up")
	for b in p.find_children("*", "Button", true, false):
		if (b as Button).text.begins_with("Keep a copy in slot 3"):
			(b as Button).pressed.emit()
	_check(SaveSlots.info("slot3").exists, "keep a copy in slot 3: it's there")
	p.close()
	await get_tree().process_frame
	_check(not get_tree().paused and not SavePrompt.is_open(), "Done: the game goes on")


func _load_screen() -> void:
	Game.save_game("slot2")
	var l := LoadScreen.open(get_tree())
	await get_tree().process_frame
	await get_tree().process_frame
	var names := []
	for lab in l.find_children("*", "Label", true, false):
		if (lab as Label).text in ["Last rest", "Slot 1", "Slot 2", "Slot 3"]:
			names.append((lab as Label).text)
	_check(names.size() == 4, "the Load screen lists the last rest and 3 slots (%s)" % [names])
	var loads := 0
	for b in l.find_children("*", "Button", true, false):
		loads += int((b as Button).text == "Load")
	_check(loads == 3, "with Load on the 3 that have a save (%d)" % loads)
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute(_dir)
		get_viewport().get_texture().get_image().save_png(_dir.path_join("load_screen.png"))
		print("RESULT shot %s" % _dir.path_join("load_screen.png"))
	l.close()


func _real_times() -> Dictionary:
	var out := {}
	for n in REAL:
		out[n] = FileAccess.get_modified_time(Game.SAVE_DIR.path_join(n))
	return out


func _check(ok: bool, what: String) -> void:
	print("RESULT %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_fails += 1
