class_name Subtitles
extends CanvasLayer
## The one subtitle path (accessibility): companions' remarks (Barks) and spoken lines (a toast
## that's a quote) show here, low in the middle, the speaker's name in their colour, over a box
## as dark as the options say ("subtitle_bg"); off with the "subtitles" option. Also the text
## size every screen uses (S / M / L / XL: Subtitles.size(24)) and the speakers' colours, which
## the conversation wheel shares.
##   Subtitles.say(get_tree(), "mahmoud", "Mahmoud", "Keep the pace.")

const SCALES := {"S": 0.85, "M": 1.0, "L": 1.25, "XL": 1.5}
const BASE_SIZE := 24
const INK := Color(0.95, 0.88, 0.7)
## Who speaks in which colour (others get one from PALETTE by their name).
const COLORS := {
	"you": Color(0.95, 0.72, 0.35), "eleanor": Color(0.62, 0.82, 1.0), "mahmoud": Color(0.55, 0.9, 0.55),
	"khalil": Color(1.0, 0.65, 0.45), "hassan": Color(0.95, 0.85, 0.4), "hargreaves": Color(0.8, 0.7, 1.0),
	"isabelle": Color(1.0, 0.6, 0.75), "idris": Color(0.5, 0.9, 0.9), "pembroke": Color(0.85, 0.85, 0.6),
	"noura": Color(0.9, 0.75, 1.0), "omar": Color(0.7, 0.95, 0.75),
}
const PALETTE := [Color(0.62, 0.82, 1.0), Color(0.55, 0.9, 0.55), Color(1.0, 0.65, 0.45), Color(0.95, 0.85, 0.4),
	Color(0.8, 0.7, 1.0), Color(1.0, 0.6, 0.75), Color(0.5, 0.9, 0.9)]

static var current: Subtitles
static var last := ""   # tests read this: "Name: text"

var _label: RichTextLabel
var _t := 0.0
var _secs := 3.0


## The options' text size as a factor (1 = M).
static func scale() -> float:
	return float(SCALES.get(str(Settings.value("text_size")), 1.0))


## `base` px at the options' text size.
## The top of the line on screen while one shows (a Notice stacks above it); INF when none.
static func top() -> float:
	if current == null or not is_instance_valid(current) or not current._label.visible or current._label.modulate.a <= 0.01:
		return INF
	return current._label.position.y


static func size(base: int) -> int:
	return roundi(base * scale())


static func speaker_color(who: String) -> Color:
	var key := who.to_lower().get_slice(" ", 0)
	if COLORS.has(key):
		return COLORS[key]
	return PALETTE[absi(key.hash()) % PALETTE.size()] if key != "" else INK


## The box behind subtitle text, as dark as the options say.
static func box() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.0, 0.0, 0.0, clampf(float(Settings.value("subtitle_bg")), 0.0, 1.0))
	sb.set_content_margin_all(8)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.set_corner_radius_all(4)
	return sb


## Show a line (the last one replaces any before). Nothing when the option is off. `who` is an id
## or a name for the colour, `name` what's shown ("" = no name).
static func say(tree: SceneTree, who: String, name: String, text: String, secs := 3.0) -> bool:
	if tree == null or not Settings.value("subtitles") or text == "":
		return false
	if not is_instance_valid(current) or not current.is_inside_tree():
		current = Subtitles.new()
		tree.root.add_child(current)
	current._show(who, name, text, secs)
	return true


func _ready() -> void:
	layer = 8
	process_mode = Node.PROCESS_MODE_ALWAYS
	_label = RichTextLabel.new()
	_label.bbcode_enabled = true
	_label.fit_content = true
	_label.scroll_active = false
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.add_theme_color_override("default_color", INK)
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_label.add_theme_constant_override("outline_size", 6)
	add_child(_label)
	_label.visible = false
	# It lives on the root: a new scene (a retry, the next act) mustn't keep the last one's line.
	get_tree().scene_changed.connect(func() -> void: _label.visible = false)


func _show(who: String, name: String, text: String, secs: float) -> void:
	_t = 0.0
	_secs = secs
	var shown := text if name == "" else "[color=#%s]%s:[/color] %s" % [speaker_color(who if who != "" else name).to_html(false), name, text]
	_label.text = "[center]%s[/center]" % shown
	last = (name + ": " if name != "" else "") + text
	_label.add_theme_font_size_override("normal_font_size", size(BASE_SIZE))
	_label.add_theme_stylebox_override("normal", box())
	_label.modulate.a = 1.0
	_label.visible = true
	print("SUBTITLE %s" % last)
	_place()


func font_size() -> int:
	return _label.get_theme_font_size("normal_font_size")


func _place() -> void:
	var s := get_viewport().get_visible_rect().size
	var w := minf(s.x * 0.7, 1000.0)
	_label.size = Vector2(w, 0)
	_label.position = Vector2((s.x - w) * 0.5, s.y - 230.0 - _label.get_content_height())


func _process(delta: float) -> void:
	if not _label.visible:
		return
	_t += delta
	_label.modulate.a = clampf((_secs - _t) / 0.5, 0.0, 1.0)
	if Conversation.current != null:
		_label.modulate.a = 0.0  # never over a talk's own line
	_place()
	if _t >= _secs:
		_label.visible = false
