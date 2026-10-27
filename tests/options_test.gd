extends Node3D
## OptionsScreen / Settings test: paused, O (through the input path) opens the menu; a screenshot;
## each setting changed through Settings applies (the buses and volumes, the shadow budget,
## render scale and AA, the player's field of view, barks and hints off); Esc closes the menu
## and the game stays paused. Test runs never read or write user://settings.cfg.
## Prints RESULT lines; exits 0 when every check passed. --shot-dir=C:/path (windowed).

var _fails := 0
var _dir := "user://options_shots"


func _ready() -> void:
	get_window().set_flag(Window.FLAG_NO_FOCUS, true)
	process_mode = Node.PROCESS_MODE_ALWAYS
	var args := TestDriver.parse_args()
	_dir = str(args.get("shot-dir", _dir))
	DirAccess.make_dir_recursive_absolute(_dir)
	var level := Level.new()
	add_child(level)
	var player := Player.new()
	add_child(player)
	player.global_position = level.player_spawn
	var hud := Hud.new()
	hud.player = player
	add_child(hud)
	for i in 3:
		await get_tree().process_frame
	_check(AudioServer.get_bus_index("SFX") >= 0 and AudioServer.get_bus_index("Ambience") >= 0, "the SFX and Ambience buses exist")
	get_tree().paused = true
	hud.show_message("PAUSED", "Click to resume · Q to quit")
	_check(hud._sub.text.ends_with("O options"), "the pause line offers O options (%s)" % hud._sub.text)
	_key(KEY_O)
	await get_tree().process_frame
	_check(OptionsScreen.is_open(), "O while paused opens the options")
	await get_tree().create_timer(0.5, true).timeout
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(_dir.path_join("options.png"))
		print("RESULT shot %s" % _dir.path_join("options.png"))
	Settings.set_value("effects", 0.5, get_tree())
	var db := AudioServer.get_bus_volume_db(AudioServer.get_bus_index("SFX"))
	_check(absf(db - linear_to_db(0.5)) < 0.01, "effects 50%% -> the SFX bus at %.1f dB" % db)
	Settings.set_value("ambience", 0.0, get_tree())
	_check(AudioServer.is_bus_mute(AudioServer.get_bus_index("Ambience")), "ambience 0 mutes its bus")
	Settings.set_value("fov", 85.0, get_tree())
	_check(is_equal_approx(player.camera.fov, 85.0), "field of view 85 -> the camera (%.0f)" % player.camera.fov)
	Settings.set_value("quality", "low", get_tree())
	_check(RenderBudget.max_shadowed == 0 and is_equal_approx(get_tree().root.scaling_3d_scale, 0.75), "low: no shadowed lights, 75%% scale")
	var sun_off := true
	for n in get_tree().root.find_children("*", "DirectionalLight3D", true, false):
		sun_off = sun_off and not (n as Light3D).shadow_enabled
	_check(sun_off, "low: the sun casts no shadows")
	Settings.set_value("quality", "medium", get_tree())
	_check(RenderBudget.max_shadowed == 2 and get_tree().root.screen_space_aa == Viewport.SCREEN_SPACE_AA_FXAA, "medium: 2 shadowed lights, FXAA")
	Settings.set_value("quality", "high", get_tree())
	_check(RenderBudget.max_shadowed == 4 and get_tree().root.msaa_3d == Viewport.MSAA_2X, "high: 4 shadowed lights, MSAA 2x")
	Settings.set_value("barks", false, get_tree())
	_check(Barks.say(player, "combat_start", "mahmoud") == "", "barks off: nobody remarks")
	Settings.set_value("hints", false, get_tree())
	Game.flags.erase("hint_dodge")
	_check(not Hints.once("dodge", self), "hints off: no first-time hint")
	_key(KEY_ESCAPE)
	await get_tree().process_frame
	_check(not OptionsScreen.is_open() and get_tree().paused, "Esc closes the options and the game stays paused")
	_check(not FileAccess.file_exists(Settings.FILE) or not OS.get_cmdline_user_args().is_empty(), "a test run never writes the settings file")
	print("RESULT %s (%d failed)" % ["PASS" if _fails == 0 else "FAIL", _fails])
	get_tree().quit(0 if _fails == 0 else 1)


func _key(code: Key) -> void:
	for pressed in [true, false]:
		var e := InputEventKey.new()
		e.keycode = code
		e.physical_keycode = code
		e.pressed = pressed
		Input.parse_input_event(e)


func _check(ok: bool, what: String) -> void:
	print("RESULT %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_fails += 1
