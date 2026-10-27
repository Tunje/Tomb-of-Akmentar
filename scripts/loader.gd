class_name Loader
extends CanvasLayer
## Every scene change between acts, Continue and Load goes through here: a card on paper with the
## act's title (menus/title.json), a sepia photograph of where you're going (assets/ui/loading/,
## made by tools/render_load_cards; a save's own thumbnail for a Load; drawn dunes if there's
## none) and a tip in turn (menus/tips.json, keys as bound now). The scene loads on a thread
## (ResourceLoader.load_threaded_request) while the old one waits, paused; the card stays at least
## MIN_SHOW s, and asks for a key only when the load took longer than ASK_AFTER s.
## Runs with test args (--auto, --chain, any args after "--") and headless runs change at once,
## with no card. Checkpoint.retry and the deaths' SaveRoute.resume stay instant.
##   Loader.go(get_tree(), "res://act4.tscn")

const MIN_SHOW := 1.2
const ASK_AFTER := 4.0
const FADE := 0.35
const PHOTOS := "res://assets/ui/loading"
const TIPS := "res://menus/tips.json"
const TIP_EVERY := 6.0

static var current: Loader
static var force := false       # tests: show the card despite the test args
static var fake_load := 0.0     # tests: seconds the load pretends to take on top
static var last_title := ""     # tests read these
static var last_tip := ""
static var _tip_i := -1

var path := ""
var photo_path := ""
var title := ""
var subtitle := ""
var tip := ""
var _t := 0.0
var _loaded_at := -1.0   # when the load finished (s since the card came up)
var _res: PackedScene
var _asked := false      # "press any key" is up
var _gone_t := -1.0      # s since the scene changed (the card fades)
var _photo: Texture2D
var _canvas: Control
var _font: Font


## Go to `path`, with the card unless it's a test run. `photo`: a picture of the place (a save's
## thumbnail) instead of the act's.
static func go(tree: SceneTree, to: String, photo := "") -> void:
	if is_instance_valid(current):
		return  # already on the way somewhere
	if skip():
		tree.change_scene_to_file(to)
		return
	var l := Loader.new()
	l.path = to
	l.photo_path = photo
	tree.root.add_child(l)


## No card: test args, a headless run, or the settings' test mode (tests), unless a test forces it.
static func skip() -> bool:
	if force:
		return false
	return not OS.get_cmdline_user_args().is_empty() or DisplayServer.get_name() == "headless" or Settings.test_mode


static func is_loading() -> bool:
	return is_instance_valid(current) and current._gone_t < 0.0


## "Act 4", "The Tombs of Akmentar" for a scene path (act4_*.tscn too); the title screen and the
## playtest range their own.
static func titles_for(to: String) -> Array:
	var file := to.get_file().get_basename()
	var m := RegEx.create_from_string("^act(\\d+)").search(file)
	if m:
		var act := int(m.get_string(1))
		return ["Act %d" % act, JournalScreen.act_title(act)]
	if file == "title":
		return ["", "Tombs of Akmentar"]
	return ["", "The proving ground"]


static func next_tip() -> String:
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(TIPS)) if FileAccess.file_exists(TIPS) else null
	var tips: Array = d.get("tips", []) if d is Dictionary else []
	if tips.is_empty():
		return ""
	_tip_i = randi() % tips.size() if _tip_i < 0 else (_tip_i + 1) % tips.size()
	return Controls.fill(str(tips[_tip_i]))


func _ready() -> void:
	current = self
	layer = 120
	process_mode = Node.PROCESS_MODE_ALWAYS
	var names := titles_for(path)
	subtitle = names[0]
	title = names[1]
	tip = next_tip()
	last_title = title
	last_tip = tip
	_photo = _load_photo()
	_font = ThemeDB.fallback_font
	_canvas = Control.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_STOP
	_canvas.draw.connect(_draw_card)
	add_child(_canvas)
	get_tree().paused = true  # the old scene waits under the card
	if ResourceLoader.load_threaded_request(path) != OK:
		push_warning("Loader: can't load %s; changing the plain way" % path)
		_switch_plain()


func _process(delta: float) -> void:
	_t += delta
	_canvas.queue_redraw()
	if _gone_t >= 0.0:
		_gone_t += delta
		_canvas.modulate.a = clampf(1.0 - (_gone_t - 0.1) / FADE, 0.0, 1.0)
		if _gone_t > FADE + 0.15:
			queue_free()
		return
	if _loaded_at < 0.0 and _t >= fake_load:
		match ResourceLoader.load_threaded_get_status(path):
			ResourceLoader.THREAD_LOAD_LOADED:
				_res = ResourceLoader.load_threaded_get(path) as PackedScene
				_loaded_at = _t
			ResourceLoader.THREAD_LOAD_FAILED, ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
				_switch_plain()
				return
	if _loaded_at < 0.0 or _t < MIN_SHOW:
		if fmod(_t, TIP_EVERY) < delta and _t > delta:  # a long load: the next tip
			tip = next_tip()
		return
	if _loaded_at > ASK_AFTER:
		_asked = true  # waits for a key (_input)
		return
	_switch()


func _input(e: InputEvent) -> void:
	if _gone_t >= 0.0:
		return
	var press: bool = (e is InputEventKey or e is InputEventJoypadButton or e is InputEventMouseButton) and e.is_pressed() and not e.is_echo()
	if press or e is InputEventKey or e is InputEventJoypadButton or e is InputEventMouseButton:
		get_viewport().set_input_as_handled()  # nothing reaches the waiting scene
	if press and _asked:
		_switch()


func _switch() -> void:
	_gone_t = 0.0
	get_tree().paused = false
	if _res:
		get_tree().change_scene_to_packed(_res)
	else:
		get_tree().change_scene_to_file(path)
	if current == self:
		current = null


func _switch_plain() -> void:
	_res = null
	_switch()


func _exit_tree() -> void:
	if current == self:
		current = null


# ---------------------------------------------------------------- the picture

func _load_photo() -> Texture2D:
	if photo_path != "" and FileAccess.file_exists(photo_path):
		var img := Image.load_from_file(ProjectSettings.globalize_path(photo_path))
		if img and not img.is_empty():
			return ImageTexture.create_from_image(sepia(img))
	var file := path.get_file().get_basename()
	for name in [file, file.get_slice("_", 0)]:
		var p := PHOTOS.path_join(name + ".png")
		if ResourceLoader.exists(p):
			return load(p)
	return null


## A photograph's brown: the image's light in sepia (used by the card and the card renderer).
static func sepia(src: Image) -> Image:
	var img := src.duplicate() as Image
	img.convert(Image.FORMAT_RGB8)
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			var l := c.r * 0.3 + c.g * 0.59 + c.b * 0.11
			l = clampf((l - 0.5) * 1.1 + 0.52, 0.0, 1.0)
			img.set_pixel(x, y, Color(l * 1.07, l * 0.9, l * 0.68).clamp())
	return img


# ---------------------------------------------------------------- drawing

func _sz(base: int) -> int:
	return Subtitles.size(base)


func _draw_card() -> void:
	var s := _canvas.size
	_canvas.draw_rect(Rect2(Vector2.ZERO, s), Color(0.08, 0.05, 0.03))
	_canvas.draw_texture_rect(ModalScreen.burn_texture(), Rect2(Vector2.ZERO, s), false, Color(0, 0, 0, 1))
	var w := minf(s.x - 80.0, 920.0)
	var photo_w := w - 120.0
	var photo_h := photo_w * 9.0 / 16.0
	var tip_h := _font.get_multiline_string_size(tip, HORIZONTAL_ALIGNMENT_CENTER, w - 120.0, _sz(18)).y
	var head := (_font.get_height(_sz(18)) if subtitle != "" else 0.0) + _font.get_height(_sz(34))
	var h := 36.0 + head + 22.0 + photo_h + 28.0 + tip_h + 56.0
	if h > s.y - 60.0:  # a small window or big text: the photograph gives way
		photo_h = maxf(photo_h - (h - (s.y - 60.0)), 60.0)
		photo_w = photo_h * 16.0 / 9.0
		h = 36.0 + head + 22.0 + photo_h + 28.0 + tip_h + 56.0
	var r := Rect2((s - Vector2(w, h)) * 0.5, Vector2(w, h))
	_canvas.draw_rect(r.grow(12), ModalScreen.LEATHER)
	_canvas.draw_rect(r.grow(12), ModalScreen.BRASS, false, 2.0)
	ModalScreen.draw_paper(_canvas, r)
	var y := r.position.y + 36.0
	var cx := r.get_center().x
	if subtitle != "":
		y += _text(subtitle.to_upper(), Vector2(cx, y), _sz(18), ModalScreen.RUST)
	y += _text(title, Vector2(cx, y), _sz(34), ModalScreen.INK) + 22.0
	_draw_photo(Rect2(cx - photo_w * 0.5, y, photo_w, photo_h))
	y += photo_h + 28.0
	_canvas.draw_multiline_string(_font, Vector2(r.position.x + 60.0, y + _font.get_ascent(_sz(18))), tip,
		HORIZONTAL_ALIGNMENT_CENTER, w - 120.0, _sz(18), -1, Color(ModalScreen.INK, 0.85))
	# Underfoot: the load's progress as an ink line, or the key to go on.
	var by := r.end.y - 26.0
	if _asked:
		var a := 0.55 + 0.45 * sin(_t * 4.0)
		_text(Controls.fill("Press any key"), Vector2(cx, by - _font.get_ascent(_sz(16))), _sz(16), Color(ModalScreen.INK, a))
	else:
		var p := [0.0]
		var k := 1.0 if _loaded_at >= 0.0 else 0.0
		if _loaded_at < 0.0 and ResourceLoader.load_threaded_get_status(path, p) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			k = float(p[0])
		var line := Rect2(cx - 120.0, by - 2.0, 240.0, 2.0)
		_canvas.draw_rect(line, Color(ModalScreen.INK, 0.15))
		_canvas.draw_rect(Rect2(line.position, Vector2(line.size.x * maxf(k, minf(_t / MIN_SHOW, 1.0) * 0.3), 2.0)), Color(ModalScreen.INK, 0.6))


## Centred text with its top at `top`; returns its height.
func _text(s: String, top: Vector2, size: int, color: Color) -> float:
	var w := _font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	_canvas.draw_string(_font, Vector2(top.x - w * 0.5, top.y + _font.get_ascent(size)), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)
	return _font.get_height(size)


## A photograph tucked into the page, a little askew: a pale border, the picture in sepia, its
## edges darkened as old prints are. Without one, dunes and pyramids drawn in its browns.
func _draw_photo(r: Rect2) -> void:
	var c := r.get_center()
	_canvas.draw_set_transform(c, -0.012, Vector2.ONE)
	var local := Rect2(-r.size * 0.5, r.size)
	_canvas.draw_rect(local.grow(10).grow_individual(0, 0, 0, 4), Color(0, 0, 0, 0.25))
	_canvas.draw_rect(local.grow(9), Color(0.93, 0.89, 0.8))
	if _photo:
		_canvas.draw_texture_rect(_photo, local, false)
	else:
		_draw_dunes(local)
	_canvas.draw_texture_rect(ModalScreen.burn_texture(), local, false, Color(0.25, 0.15, 0.05, 1.0))
	_canvas.draw_rect(local, Color(0.25, 0.16, 0.08, 0.5), false, 1.0)
	_canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_dunes(r: Rect2) -> void:
	var sky := Color(0.78, 0.66, 0.48)
	_canvas.draw_rect(r, sky)
	_canvas.draw_rect(Rect2(r.position, Vector2(r.size.x, r.size.y * 0.35)), Color(0.85, 0.75, 0.58))
	var base := r.position.y + r.size.y * 0.62
	for p: Array in [[0.62, 0.22, 0.3], [0.78, 0.14, 0.2], [0.5, 0.1, 0.13]]:  # pyramids: x, height, half-width
		var x := r.position.x + r.size.x * float(p[0])
		_canvas.draw_colored_polygon(PackedVector2Array([Vector2(x, base - r.size.y * float(p[1])),
			Vector2(x + r.size.x * float(p[2]) * 0.5, base), Vector2(x - r.size.x * float(p[2]) * 0.5, base)]), Color(0.48, 0.36, 0.22))
	for i in 3:  # dunes, nearer and darker
		var pts := PackedVector2Array()
		var top := base + r.size.y * (0.02 + i * 0.1)
		for j in 25:
			var x := r.position.x + r.size.x * j / 24.0
			pts.append(Vector2(x, top + sin(j * 0.55 + i * 1.7) * r.size.y * 0.03))
		pts.append(r.end)
		pts.append(Vector2(r.position.x, r.end.y))
		_canvas.draw_colored_polygon(pts, Color(0.66 - i * 0.1, 0.52 - i * 0.09, 0.34 - i * 0.07))
