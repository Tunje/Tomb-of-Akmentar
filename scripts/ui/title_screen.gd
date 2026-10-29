class_name TitleScreen
extends Node3D
## The title screen (title.tscn; main.tscn comes here when started without test args): Akmentar at
## dusk with the camera drifting round it, and Continue (when there's a last rest: its summary on
## focus), New game (asks if a save exists), Load game, Chapters (Acts 1-9 and the playtest range,
## titles in menus/title.json; and the Prototypes, new maps to walk), Options, Credits
## (menus/title.json) and Quit. Keyboard, mouse or
## pad. The number keys 1-9 still start an act straight away (testing).
##   TitleScreen.request: what main.tscn should do when the title sends it there ("range" = the
##   playtest range, "continue" = a last rest made there), read once by main.gd.

const DATA := "res://menus/title.json"
const INK := Color(0.95, 0.88, 0.7)
const DIM := Color(0.7, 0.64, 0.5)
const GOLD := Color(0.98, 0.8, 0.45)
const CENTRE := Vector3(70, 0, 66)   # the ruins' middle (AkmentarSurface)
const DRIFT := 0.018                  # rad/s round the ruins

static var request := ""

var _cam: Camera3D
var _angle := 0.6
var _menu: VBoxContainer
var _info: Label
var _data := {}


## main.gd: what the title asked for ("" = nothing: show the title).
static func take_request() -> String:
	var r := request
	request = ""
	return r


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = false
	Controls.setup()
	Settings.ensure(get_tree())
	RenderBudget.max_shadowed = 0  # a backdrop: no torch shadows (the next scene's Hud restores it)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if FileAccess.file_exists(DATA):
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA))
		_data = d if d is Dictionary else {}
	_backdrop()
	_ui()
	_main_menu()
	print("RESULT title shown (continue=%s)" % Game.has_save())


func _backdrop() -> void:
	var level := AkmentarSurface.new()
	add_child(level)
	level.set_night(0.35)  # dusk
	_cam = Camera3D.new()
	_cam.fov = 55.0
	_cam.far = 900.0
	add_child(_cam)
	_cam.make_current()
	_place_camera()
	Ambience.play(self, "desert")


func _place_camera() -> void:
	var at := CENTRE + Vector3(cos(_angle), 0, sin(_angle)) * 78.0 + Vector3.UP * 16.0
	_cam.global_position = at
	_cam.look_at(CENTRE + Vector3.UP * 5.0, Vector3.UP)


func _process(delta: float) -> void:
	_angle += DRIFT * delta
	_place_camera()


func _ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	var shade := ColorRect.new()
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var grad := GradientTexture2D.new()  # dark on the left, where the menu is
	var g := Gradient.new()
	g.set_color(0, Color(0.03, 0.025, 0.02, 0.85))
	g.set_color(1, Color(0.03, 0.025, 0.02, 0.0))
	grad.gradient = g
	grad.fill_to = Vector2(0.75, 0)
	var tex := TextureRect.new()
	tex.texture = grad
	tex.set_anchors_preset(Control.PRESET_FULL_RECT)
	tex.stretch_mode = TextureRect.STRETCH_SCALE
	tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(tex)
	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	col.offset_left = 90
	col.offset_top = 120
	col.offset_right = 600
	col.add_theme_constant_override("separation", 14)
	layer.add_child(col)
	col.add_child(_label("TOMBS OF AKMENTAR", 64, GOLD))
	col.add_child(_label("Egypt, 1926", 22, DIM))
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 30)
	col.add_child(gap)
	_menu = VBoxContainer.new()
	_menu.add_theme_constant_override("separation", 8)
	col.add_child(_menu)
	_info = _label("", 17, DIM)
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.custom_minimum_size = Vector2(480, 0)
	col.add_child(_info)


# ---------------------------------------------------------------- menus

func _clear() -> void:
	for c in _menu.get_children():
		c.queue_free()
	_info.text = ""


func _main_menu() -> void:
	_clear()
	var first: Button = null
	if Game.has_save():
		var info := SaveSlots.info("main")
		var cont := _button("Continue", _continue)
		var summary := "Act %d · %s · %s" % [info.get("act", 1), info.get("place", ""), SaveSlots.date_text(info.get("saved_at", 0.0))]
		cont.focus_entered.connect(func() -> void: _info.text = summary)
		cont.mouse_entered.connect(func() -> void: _info.text = summary)
		cont.focus_exited.connect(func() -> void: _info.text = "")
		_menu.add_child(cont)
		first = cont
	var new_game := _button("New game", _new_game)
	_menu.add_child(new_game)
	if first == null:
		first = new_game
	_menu.add_child(_button("Load game", func() -> void: LoadScreen.open(get_tree())))
	_menu.add_child(_button("Chapters", _chapters))
	_menu.add_child(_button("Options", func() -> void: OptionsScreen.open(get_tree())))
	_menu.add_child(_button("Credits", _credits))
	_menu.add_child(_button("Quit", func() -> void: get_tree().quit()))
	first.grab_focus.call_deferred()


func _continue() -> void:
	if not Game.load_game():
		return
	Game.resume_slot = "main"
	var scene := SaveRoute.scene_for(Game.place)
	var photo := SaveSlots.thumb_path("main")  # the loading card shows where you rested
	if scene != "" and ResourceLoader.exists(scene):
		Loader.go(get_tree(), scene, photo)
	else:
		request = "continue"  # a rest in the playtest range: main.tscn picks it up
		Loader.go(get_tree(), "res://main.tscn", photo)


func _new_game() -> void:
	if Game.has_save():
		_ask("Start a new game? Your last rest stays until you rest again.", _start_new)
	else:
		_start_new()


## A new game: first the difficulty (Normal picked), then Act 1. The act's first save records it.
func _start_new() -> void:
	_clear()
	_menu.add_child(_label("How hard should it be?", 24, INK))
	var normal: Button = null
	for id: String in Difficulty.IDS:
		var b := _button(Difficulty.name_of(id), _begin.bind(id))
		_menu.add_child(b)
		var blurb := _label(Difficulty.BLURBS[id], 16, DIM)
		blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		blurb.custom_minimum_size = Vector2(380, 0)
		_menu.add_child(blurb)
		if id == "normal":
			normal = b
	_menu.add_child(_button("Back", _main_menu))
	normal.grab_focus.call_deferred()


func _begin(difficulty: String) -> void:
	Game.reset()
	Difficulty.set_level(difficulty)
	DayLog.begin_day()
	Loader.go(get_tree(), "res://act1.tscn")


func _chapters() -> void:
	_clear()
	var first: Button = null
	for ch: Dictionary in _data.get("chapters", []):
		var act := int(ch.get("act", 1))
		var b := _button("Act %d · %s" % [act, ch.get("title", "")], _start_act.bind(act))
		_menu.add_child(b)
		if first == null:
			first = b
	_menu.add_child(_button("Playtest range", _range))
	_menu.add_child(_button("Prototypes", _prototypes))
	var back := _button("Back", _main_menu)
	_menu.add_child(back)
	(first if first else back).grab_focus.call_deferred()


## An act from its start, with the default party it fills in (as the number keys did).
func _start_act(act: int) -> void:
	if not ResourceLoader.exists("res://act%d.tscn" % act):
		return
	Game.reset()
	Game.set_flag("quickstart_act")
	Loader.go(get_tree(), "res://act%d.tscn" % act)


## New maps no act uses yet, to walk (Prototype; Simon: "much better than writing"): each map's
## entry in Prototype.ENTRIES, and the monastery night (-7f's).
func _prototypes() -> void:
	_clear()
	var first: Button = null
	for pid: String in Prototype.ENTRIES:
		var b := _button(str(Prototype.ENTRIES[pid][0]), _prototype.bind(pid))
		_menu.add_child(b)
		if first == null:
			first = b
	_menu.add_child(_button("The monastery night (Act 6's fight)", _monastery_night))
	var back := _button("Back", _chapters)
	_menu.add_child(back)
	(first if first else back).grab_focus.call_deferred()


func _prototype(pid: String) -> void:
	Game.reset()
	Game.set_flag("prototype", pid)
	Loader.go(get_tree(), "res://prototype.tscn")


## Act 6's night fight at -f9's monastery on its own (off in Act 6 itself: Simon plays it to decide
## whether it stays). Act 6 sees the flag, fights it, and comes back here.
func _monastery_night() -> void:
	Game.reset()
	Game.set_flag("monastery_night")
	Loader.go(get_tree(), "res://act6.tscn")


func _range() -> void:
	request = "range"
	Loader.go(get_tree(), "res://main.tscn")


func _credits() -> void:
	_clear()
	for line in _data.get("credits", []):
		_menu.add_child(_label(str(line), 22 if str(line) != "" else 10, INK))
	var back := _button("Back", _main_menu)
	_menu.add_child(back)
	back.grab_focus.call_deferred()


func _ask(question: String, then: Callable) -> void:
	_clear()
	var q := _label(question, 20, INK)
	q.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	q.custom_minimum_size = Vector2(480, 0)
	_menu.add_child(q)
	var no := _button("No", _main_menu)
	_menu.add_child(no)
	_menu.add_child(_button("Yes", then))
	no.grab_focus.call_deferred()


## Esc or B: back to the main list from a sub-list (the other pages handle their own). The number
## keys start an act at once (testing, as before).
func _unhandled_input(event: InputEvent) -> void:
	if OptionsScreen.is_open() or LoadScreen.is_open() or ControlsScreen.is_open():
		return
	var back: bool = event.is_action_pressed("ui_cancel") or (event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_B)
	if back:
		get_viewport().set_input_as_handled()
		_main_menu()
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode >= KEY_1 and event.keycode <= KEY_9:
		_start_act(event.keycode - KEY_0)


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", Subtitles.size(size))
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("outline_size", 6)
	return l


func _button(text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(380, 44)
	b.add_theme_font_size_override("font_size", Subtitles.size(22))
	b.pressed.connect(on_press)
	return b
