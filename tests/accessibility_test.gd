extends Node3D
## Accessibility options test: each setting persists (written to and read back from a scratch
## file, never the real settings.cfg) and applies: text size (the HUD's toast, a notice, a subtitle,
## the talk wheel), subtitles (a remark in the subtitle line, the speaker coloured, the box's
## opacity; off: nothing), aim / sprint / crouch toggle (stays on after release) and hold, camera
## shake 0 (no camera offset), the crosshair's size and colour, and the options' accessibility page.
## Prints RESULT lines; exits 0 when every check passed.

const SCRATCH := "user://accessibility_test_settings.cfg"

var _fails := 0
var player: Player
var hud: Hud


func _ready() -> void:
	Settings.test_mode = true
	get_window().set_flag(Window.FLAG_NO_FOCUS, true)
	var cfg_time := FileAccess.get_modified_time(Settings.FILE)
	Controls.setup()
	var level := Level.new()
	add_child(level)
	player = Player.new()
	add_child(player)
	player.global_position = level.player_spawn
	hud = Hud.new()
	hud.player = player
	add_child(hud)
	for i in 5:
		await get_tree().physics_frame
	_persist()
	await _text_size()
	await _subtitles()
	await _toggles()
	await _shake()
	_crosshair()
	await _page()
	_check(FileAccess.get_modified_time(Settings.FILE) == cfg_time, "the real settings.cfg untouched")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH))
	Settings.file_path = Settings.FILE
	print("RESULT %s (%d failed)" % ["PASS" if _fails == 0 else "FAIL", _fails])
	get_tree().quit(0 if _fails == 0 else 1)


## Every accessibility setting, changed, saved to a scratch file and read back.
func _persist() -> void:
	Settings.file_path = SCRATCH
	var want := {"subtitles": false, "text_size": "XL", "subtitle_bg": 0.8, "aim_mode": "toggle",
		"sprint_mode": "toggle", "crouch_mode": "toggle", "shake": 0.25, "crosshair": "large", "crosshair_color": "cyan"}
	for k in want:
		Settings.set_value(k, want[k], get_tree())
	Settings.values = {}  # forget them: what comes back is what the file kept
	Settings.reload_file()
	var differ := []
	for k in want:
		if Settings.value(k) != want[k]:
			differ.append("%s=%s" % [k, Settings.value(k)])
	_check(differ.is_empty(), "every accessibility setting persists (saved and read back) %s" % [differ])
	for k in want:  # back to the defaults for the rest
		Settings.set_value(k, Settings.DEFAULTS[k], get_tree())


func _text_size() -> void:
	hud.toast("A plain line")
	await get_tree().process_frame
	var m := hud._toast.get_theme_font_size("font_size")
	Settings.set_value("text_size", "XL", get_tree())
	await get_tree().process_frame
	await get_tree().process_frame
	var xl := hud._toast.get_theme_font_size("font_size")
	_check(xl == roundi(m * 1.5), "text size XL: the toast %d -> %d px" % [m, xl])
	var n := Notice.say(self, "A notice")
	_check(n._label.get_theme_font_size("font_size") == roundi(24 * 1.5), "and a notice (hints) at %d" % n._label.get_theme_font_size("font_size"))
	var w := ConversationWheel.new()
	add_child(w)
	await get_tree().process_frame
	w.show_line("Mahmoud", "Keep the pace.")
	_check(w._line.get_theme_font_size("font_size") == roundi(26 * 1.5), "and the talk wheel's line at %d" % w._line.get_theme_font_size("font_size"))
	_check(w._speaker.get_theme_color("font_color") == Subtitles.speaker_color("mahmoud"), "the talk's speaker in his colour")
	w.queue_free()
	Subtitles.say(get_tree(), "khalil", "Khalil", "Cover me!")
	_check(Subtitles.current.font_size() == roundi(24 * 1.5), "and a subtitle at %d" % Subtitles.current.font_size())
	Settings.set_value("text_size", "M", get_tree())
	await get_tree().process_frame
	_check(hud._toast.get_theme_font_size("font_size") == m, "back to M: %d" % hud._toast.get_theme_font_size("font_size"))


func _subtitles() -> void:
	Settings.set_value("subtitle_bg", 0.7, get_tree())
	Subtitles.last = ""
	var c := Node3D.new()  # someone to speak from
	add_child(c)
	c.global_position = player.global_position + Vector3(2, 0, 0)
	await get_tree().process_frame
	Barks.reset()
	Barks.say(c, "combat_start", "mahmoud")
	_check(Subtitles.last.begins_with("Mahmoud") and ": " in Subtitles.last, "a remark goes to the subtitle line (%s)" % Subtitles.last)
	var text := Subtitles.current._label.text
	_check(Subtitles.speaker_color("mahmoud").to_html(false) in text, "his name in his colour")
	var box := Subtitles.current._label.get_theme_stylebox("normal") as StyleBoxFlat
	_check(box != null and is_equal_approx(box.bg_color.a, 0.7), "the box at the options' opacity (%.2f)" % (box.bg_color.a if box else -1.0))
	hud.toast("\"Mister O'Connell. A word.\"")
	_check(Subtitles.last == "\"Mister O'Connell. A word.\"", "a spoken toast goes to the subtitle line")
	Settings.set_value("subtitles", false, get_tree())
	Subtitles.last = ""
	_check(not Subtitles.say(get_tree(), "khalil", "Khalil", "Cover me!") and Subtitles.last == "", "subtitles off: nothing")
	hud.toast("\"Spoken, but subtitles are off.\"")
	_check(hud._toast.text.begins_with("\"Spoken"), "off: a spoken toast stays a toast")
	Settings.set_value("subtitles", true, get_tree())
	c.queue_free()


func _toggles() -> void:
	player.set_armed(true)
	await _wait(0.6)
	# Aim: hold (default) lets go on release; toggle stays.
	await _mouse(MOUSE_BUTTON_RIGHT, true)
	_check(player.aiming, "hold: aiming while the button's down")
	await _mouse(MOUSE_BUTTON_RIGHT, false)
	_check(not player.aiming, "hold: let go, not aiming")
	Settings.set_value("aim_mode", "toggle", get_tree())
	await _mouse(MOUSE_BUTTON_RIGHT, true)
	await _mouse(MOUSE_BUTTON_RIGHT, false)
	_check(player.aiming, "toggle aim: still aiming after release")
	await _mouse(MOUSE_BUTTON_RIGHT, true)
	await _mouse(MOUSE_BUTTON_RIGHT, false)
	_check(not player.aiming, "toggle aim: pressed again, not aiming")
	await _mouse(MOUSE_BUTTON_RIGHT, true)
	await _mouse(MOUSE_BUTTON_RIGHT, false)
	player.set_armed(false)
	await _wait(0.1)
	_check(not player.aiming and not player._latched.has("aim"), "holstering ends a toggled aim")
	Settings.set_value("aim_mode", "hold", get_tree())
	# Crouch.
	Settings.set_value("crouch_mode", "toggle", get_tree())
	await _key(KEY_C, true)
	await _key(KEY_C, false)
	_check(player.crouching, "toggle crouch: still down after release")
	await _key(KEY_C, true)
	await _key(KEY_C, false)
	_check(not player.crouching, "toggle crouch: pressed again, up")
	Settings.set_value("crouch_mode", "hold", get_tree())
	# Sprint: toggle on the keyboard; it ends when you stop.
	Settings.set_value("sprint_mode", "toggle", get_tree())
	await _key(KEY_W, true)
	await _key(KEY_SHIFT, true)
	await _key(KEY_SHIFT, false)
	await _wait(0.1)
	_check(player.sprinting, "toggle sprint: still running after Shift's let go")
	await _key(KEY_W, false)
	await _wait(0.1)
	_check(not player.sprinting and not player._latched.has("sprint"), "stopping ends a toggled sprint")
	# Auto: held on the keyboard.
	Settings.set_value("sprint_mode", "auto", get_tree())
	await _key(KEY_W, true)
	await _key(KEY_SHIFT, true)
	await _key(KEY_SHIFT, false)
	await _wait(0.1)
	_check(not player.sprinting, "auto on the keyboard: held (let go, walking)")
	await _key(KEY_W, false)


func _shake() -> void:
	Settings.set_value("shake", 0.0, get_tree())
	player.trauma = 1.0
	await get_tree().process_frame
	await get_tree().process_frame
	_check(player.camera.h_offset == 0.0 and player.camera.v_offset == 0.0, "camera shake 0%: no offset at full trauma")
	Settings.set_value("shake", 1.0, get_tree())
	player.trauma = 1.0
	await get_tree().process_frame
	await get_tree().process_frame
	_check(absf(player.camera.h_offset) + absf(player.camera.v_offset) > 0.001, "at 100% it shakes")
	player.trauma = 0.0


func _crosshair() -> void:
	var normal := hud.crosshair_style()
	Settings.set_value("crosshair", "large", get_tree())
	Settings.set_value("crosshair_color", "yellow", get_tree())
	var big := hud.crosshair_style()
	_check(float(big.width) > float(normal.width) and float(big.length) > float(normal.length), "crosshair large: longer and thicker")
	_check((big.color as Color).is_equal_approx(Hud.CROSSHAIR_COLORS.yellow), "crosshair yellow")
	Settings.set_value("crosshair_color", "cyan", get_tree())
	_check((hud.crosshair_style().color as Color).is_equal_approx(Hud.CROSSHAIR_COLORS.cyan), "crosshair cyan")
	Settings.set_value("crosshair", "normal", get_tree())
	Settings.set_value("crosshair_color", "white", get_tree())


func _page() -> void:
	var o := OptionsScreen.open(get_tree())
	await get_tree().process_frame
	var found: Button = null
	for b in o.find_children("*", "Button", true, false):
		if (b as Button).text == "Accessibility…":
			found = b
	_check(found != null, "the options have an Accessibility… button")
	found.pressed.emit()
	await get_tree().process_frame
	_check(is_instance_valid(OptionsScreen.accessibility), "it opens the accessibility page")
	var rows := 0
	for l in OptionsScreen.accessibility.find_children("*", "Label", true, false):
		if (l as Label).text in ["Subtitles", "Text size", "Subtitle background", "Aim", "Sprint", "Crouch", "Camera shake", "Crosshair", "Crosshair colour", "Show objective"]:
			rows += 1
	_check(rows == 10, "with its 10 settings (%d)" % rows)
	OptionsScreen.accessibility.close()
	o.close()


# ---------------------------------------------------------------- input

func _mouse(button: MouseButton, down: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = button
	e.pressed = down
	Input.parse_input_event(e)
	await _wait(0.1)


func _key(code: Key, down: bool) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.pressed = down
	Input.parse_input_event(e)
	await _wait(0.1)


func _wait(secs: float) -> void:
	await get_tree().create_timer(secs).timeout


func _check(ok: bool, what: String) -> void:
	print("RESULT %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_fails += 1
