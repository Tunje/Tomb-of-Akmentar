class_name WorldMarker
extends Node3D
## A small name over something you can use, the same everywhere (Simon: "I can't see where things
## are"): every Interactable gets one (the place's name for an ActionSpot, the person's for an Npc
## with a talk, the prompt for the rest: "Rest by the fire (save)"). It shows within `range` m,
## fading in at the edge and down close up (the E prompt takes over there), in the menus' cream;
## something you can't use now is greyed red with the reason under its name ("No time left today").
## Far ones hide behind walls (a ray every UPDATE s); near ones always show. The Accessibility
## option "Show markers" turns them off; the options' text size applies.
##   var m := WorldMarker.attach(node, "Isabelle")          # at the node, 2.3 m up
##   m.reason_of = func() -> String: return ""               # "" = usable; else why not

const UPDATE := 0.2        # s between a marker's looks at the camera and the walls
const RANGE := 15.0        # m: seen within this
const NEAR := 3.0          # m: closer, it dims to NEAR_ALPHA (the E prompt says the rest)
const NEAR_ALPHA := 0.35
const CLEAR := 7.0         # m: nearer than this it shows even with something in between
const TEXT := Color(0.95, 0.88, 0.7)
const BARRED := Color(0.75, 0.42, 0.34)

var text := ""
var reason_of: Callable    # () -> String: why it can't be used now ("" = it can); optional
var visible_if: Callable   # () -> bool: false hides it altogether (a gone or done thing); optional
var range := RANGE
var label: Label3D

var _t := 0.0
var _alpha := 0.0
var _goal := 0.0


static func attach(to: Node3D, name_text: String, height := 2.3) -> WorldMarker:
	var m := WorldMarker.new()
	m.text = name_text
	m.name = "Marker"
	to.add_child(m)
	m.position = Vector3.UP * height
	return m


func _ready() -> void:
	add_to_group("world_marker")
	label = Label3D.new()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true  # walls are the ray's job (far); near, it should show
	label.fixed_size = true
	label.pixel_size = 0.0009
	label.outline_size = 10
	label.outline_modulate = Color(0, 0, 0, 0.75)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	label.modulate.a = 0.0
	label.render_priority = 2
	add_child(label)
	_t = randf() * UPDATE  # spread the markers' looks over the frames


func _process(delta: float) -> void:
	_t += delta
	if _t >= UPDATE:
		_t = 0.0
		_look()
	_alpha = move_toward(_alpha, _goal, delta * 4.0)
	label.modulate.a = _alpha
	label.outline_modulate.a = 0.75 * _alpha
	label.visible = _alpha > 0.01


## Where it stands now: shown or not, how strongly, its text and tint.
func _look() -> void:
	_goal = 0.0
	if not Settings.value("show_markers") or not is_inside_tree():
		return
	if visible_if.is_valid() and not bool(visible_if.call()):
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null or ActionMenu.ui_open():
		return
	var d := cam.global_position.distance_to(global_position)
	if d > range:
		return
	if d > CLEAR and _blocked(cam.global_position):
		return
	_goal = clampf((range - d) / 2.5, 0.0, 1.0)  # fades in over the last 2.5 m of its range
	if d < NEAR:
		_goal = lerpf(NEAR_ALPHA, 1.0, clampf((d - 1.5) / (NEAR - 1.5), 0.0, 1.0))
	var why: String = str(reason_of.call()) if reason_of.is_valid() else ""
	var k := Subtitles.scale()
	label.font_size = roundi(26 * k)
	if why == "":
		label.text = "%s\n▼" % text
		label.modulate = Color(TEXT, label.modulate.a)
	else:
		label.text = "%s\n%s\n▼" % [text, why] if d < maxf(range * 0.75, 11.0) else "%s\n▼" % text  # the reason on approach
		label.modulate = Color(BARRED, label.modulate.a)


## Something solid between the camera and the marker (the world's layer 1, not people).
func _blocked(from: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(from, global_position, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return false
	# Its own body (a crate, a desk) or anything within a metre of it doesn't count.
	return (hit.position as Vector3).distance_to(global_position) > 1.5


## Shown now (tests).
func shown() -> bool:
	return _goal > 0.0
