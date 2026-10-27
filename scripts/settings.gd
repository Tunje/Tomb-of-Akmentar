class_name Settings
extends RefCounted
## The player's options (OptionsScreen), kept in user://settings.cfg apart from the game saves and
## applied at boot (Hud calls ensure() in every scene). Test runs (args after "--") neither read
## nor write it: bots always run on the defaults, and never touch Simon's choices.
##   Settings.value("fov")         # read one
##   Settings.set_value("fov", 80)  # change, apply and save

const FILE := "user://settings.cfg"
const DEFAULTS := {
	"master": 1.0, "effects": 1.0, "ambience": 1.0, "music": 1.0,     # volumes, 0..1
	"mouse_sens": 1.0, "invert_y": false, "fov": 72.0,
	"quality": "high",                                  # low / medium / high
	"fullscreen": false, "barks": true, "hints": true,
	"vibration": true, "aim_assist": true,              # the pad: rumble, the aim slowdown
	"keys": {},                                         # rebound keys (Controls.bindings); {} = defaults
	# Accessibility (the options' second page).
	"subtitles": true,              # remarks and spoken lines in the subtitle line (Subtitles)
	"text_size": "M",               # S / M / L / XL: the HUD, toasts, hints, subtitles, the talk wheel
	"subtitle_bg": 0.5,             # the box behind subtitles, 0..1
	"aim_mode": "hold",             # hold / toggle
	"sprint_mode": "auto",          # auto (hold on keys, toggle on a pad) / hold / toggle
	"crouch_mode": "hold",          # hold / toggle
	"shake": 1.0,                   # camera shake, 0..1
	"crosshair": "normal",          # normal / bold / large
	"crosshair_color": "white",     # white / yellow / cyan
	"show_markers": true,		   # names over the places, people and things you can use (WorldMarker)
	"show_objective": true,         # the objective line top left (Objective)
}
## Quality presets: shadowed lights near you (RenderBudget), the sun's shadows, 3D render scale,
## anti-aliasing.
const QUALITY := {
	"low": {"lights": 0, "sun": false, "scale": 0.75, "msaa": Viewport.MSAA_DISABLED, "fxaa": false},
	"medium": {"lights": 2, "sun": true, "scale": 1.0, "msaa": Viewport.MSAA_DISABLED, "fxaa": true},
	"high": {"lights": 4, "sun": true, "scale": 1.0, "msaa": Viewport.MSAA_2X, "fxaa": false},
}
const BUSES := ["SFX", "Ambience", "Music"]

static var values := {}
static var _loaded := false


static func value(key: String) -> Variant:
	if not _loaded:
		_load()
	return values.get(key, DEFAULTS.get(key))


static func set_value(key: String, v: Variant, tree: SceneTree = null) -> void:
	if not _loaded:
		_load()
	values[key] = v
	apply(tree if tree else Engine.get_main_loop() as SceneTree)
	save()


## Load once and apply (each scene: some settings live on its nodes, like the sun's shadows).
static func ensure(tree: SceneTree) -> void:
	if not _loaded:
		_load()
	apply(tree)
	MusicDirector.ensure(tree)  # once, on the root: the music carries across scenes (not in test runs)


## Set by a test before anything reads the settings (options_test): never touch the real file.
static var test_mode := false


## A test run: args after "--", a scene under res://tests/, or test_mode. (A headless options_test
## with no args once wrote its values into Simon's settings.cfg.)
static func _testing() -> bool:
	if test_mode or not OS.get_cmdline_user_args().is_empty():
		return true
	var tree := Engine.get_main_loop() as SceneTree
	return tree != null and tree.current_scene != null and tree.current_scene.scene_file_path.begins_with("res://tests/")


## Where the options are kept: FILE, except a test that wants persistence points this at a file of
## its own (a test never reads or writes FILE).
static var file_path := FILE


static func _may_use_file() -> bool:
	return file_path != FILE or not _testing()


static func _load() -> void:
	_loaded = true
	values = DEFAULTS.duplicate(true)
	if not _may_use_file():
		return
	var cf := ConfigFile.new()
	if cf.load(file_path) != OK:
		return
	for k in DEFAULTS:
		values[k] = cf.get_value("options", k, DEFAULTS[k])


## Forget what's loaded and read the file again (tests: does a setting persist?). Not "reload":
## Settings.reload() is the script resource's own (it resets every static to its default).
static func reload_file() -> void:
	_loaded = false
	_load()


static func save() -> void:
	if not _may_use_file():
		return
	var cf := ConfigFile.new()
	for k in values:
		cf.set_value("options", k, values[k])
	cf.save(file_path)


static func apply(tree: SceneTree) -> void:
	var keys: Variant = value("keys")
	if keys is Dictionary and not (keys as Dictionary).is_empty():
		Controls.apply(keys)
	_buses()
	_volume("Master", float(value("master")))
	_volume("SFX", float(value("effects")))
	_volume("Ambience", float(value("ambience")))
	_volume("Music", float(value("music")))
	var q: Dictionary = QUALITY.get(str(value("quality")), QUALITY.high)
	RenderBudget.max_shadowed = int(q.lights)
	if tree:
		var vp := tree.root
		vp.scaling_3d_scale = float(q.scale)
		vp.msaa_3d = q.msaa
		vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if q.fxaa else Viewport.SCREEN_SPACE_AA_DISABLED
		for n in vp.find_children("*", "DirectionalLight3D", true, false):
			if not n.has_meta("shadow_wanted"):
				n.set_meta("shadow_wanted", (n as Light3D).shadow_enabled)
			(n as Light3D).shadow_enabled = bool(n.get_meta("shadow_wanted")) and bool(q.sun)
		for p in vp.find_children("*", "", true, false):
			if p is Player:
				(p as Player).apply_settings()
	if not _testing():
		var full := bool(value("fullscreen"))
		var mode := DisplayServer.window_get_mode()
		if full and mode != DisplayServer.WINDOW_MODE_FULLSCREEN:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		elif not full and mode == DisplayServer.WINDOW_MODE_FULLSCREEN:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)


## The effects and ambience buses (made here, sent to Master): Sfx and Ambience play on them.
static func _buses() -> void:
	for b in BUSES:
		if AudioServer.get_bus_index(b) < 0:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, b)
			AudioServer.set_bus_send(i, "Master")


static func _volume(bus: String, v: float) -> void:
	var i := AudioServer.get_bus_index(bus)
	if i >= 0:
		AudioServer.set_bus_volume_db(i, linear_to_db(maxf(v, 0.0001)))
		AudioServer.set_bus_mute(i, v <= 0.001)
