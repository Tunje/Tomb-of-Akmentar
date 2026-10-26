class_name Notice
extends CanvasLayer
## A short message low on the screen that fades by itself ("The door won't move.").
##   Notice.say(self, "No time left today")

static var last := ""   # tests read this

var _label: Label
var _t := 0.0
var _seconds := 2.5


static func say(parent: Node, message: String, seconds := 2.5) -> Notice:
	for n in parent.get_tree().get_nodes_in_group("notice"):
		n.queue_free()
	var n := Notice.new()
	n._seconds = seconds
	parent.add_child(n)
	n._label.text = message
	last = message
	print("NOTICE %s" % message)
	return n


func _init() -> void:
	layer = 9
	add_to_group("notice")
	_label = Label.new()
	_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_label.offset_bottom = -170
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 24)
	_label.add_theme_color_override("font_color", Color(0.95, 0.88, 0.7))
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_label.add_theme_constant_override("outline_size", 6)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)


func _process(delta: float) -> void:
	_t += delta
	_label.modulate.a = clampf((_seconds - _t) / 0.5, 0.0, 1.0)
	if _t >= _seconds:
		queue_free()
