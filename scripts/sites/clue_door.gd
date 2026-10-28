class_name ClueDoor
extends StaticBody3D
## A stone door (or slab over a passage) that only opens for someone who knows the trick: E on it
## opens it when Game has `needs` (a flag, e.g. a clue's), else says `locked_text`. It sinks into
## the floor over OPEN_TIME and stays open (flag "door_<id>_open", saved).
## `can_force`: without the trick, E twice (the second within FORCE_WINDOW s of being told it
## won't move) forces it anyway: it opens, loudly ("forced" signal, flag "door_<id>_forced"), and
## whatever's near hears it (the act's business: Simon's rule, a clue is never required).
##   ClueDoor.make(level, "anubis_door", Vector3(4, 0, 9), Vector3(2, 3, 0.4), "clue_anubis", ...)

signal opened
signal forced

const FORCE_WINDOW := 4.0

const OPEN_TIME := 1.6

@export var door_id := ""
@export var needs := ""
var size := Vector3(2, 3, 0.4)
var locked_text := "The door won't move."
var open_text := "The slab grinds down into the floor."
var interactable: Interactable
var is_open := false
var can_force := false
var force_text := "You set your shoulder to it and heave. Something gives with a crack that rolls away down the dark."

var _t := -1.0
var _force_until := -1.0
var _closed_y := 0.0


static func make(parent: Node3D, id: String, pos: Vector3, door_size: Vector3, needs_flag: String,
		locked := "", opening := "") -> ClueDoor:
	var d := ClueDoor.new()
	d.door_id = id
	d.name = "Door_" + id
	d.size = door_size
	d.needs = needs_flag
	if locked != "":
		d.locked_text = locked
	if opening != "":
		d.open_text = opening
	parent.add_child(d)
	d.global_position = pos
	d._closed_y = d.position.y
	d.interactable = Interactable.make(parent, pos + Vector3.UP * 1.0, "Push the slab", "door_" + id, 1.4)
	d.interactable.used.connect(func(_by: Node) -> void: d.try_open())
	if Game.flag(d._open_flag()):
		d._set_open_now()
	return d


func _ready() -> void:
	collision_layer = 1
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	cs.position.y = size.y * 0.5
	add_child(cs)
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.position.y = size.y * 0.5
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.5, 0.42, 0.3)
	m.roughness = 0.95
	mi.material_override = m
	add_child(mi)


func try_open() -> bool:
	if is_open:
		return true
	var now := Time.get_ticks_msec() / 1000.0
	var by_force := false
	if needs != "" and not Game.flag(needs):
		if not can_force or now > _force_until:
			_force_until = now + FORCE_WINDOW
			Notice.say(get_parent(), locked_text + (" You could force it. It would be loud." if can_force else ""))
			return false
		by_force = true
	is_open = true
	_t = 0.0
	Game.set_flag(_open_flag())
	if by_force:
		Game.set_flag("door_%s_forced" % door_id)
		Notice.say(get_parent(), force_text)
		forced.emit()
	else:
		Notice.say(get_parent(), open_text)
	interactable.when = {"not_flag": _open_flag()}
	opened.emit()
	return true


func _process(delta: float) -> void:
	if _t < 0.0:
		return
	_t += delta
	var k := clampf(_t / OPEN_TIME, 0.0, 1.0)
	position.y = _closed_y - size.y * 0.98 * (k * k * (3.0 - 2.0 * k))
	if k >= 1.0:
		_t = -1.0
		_set_open_now()


func _set_open_now() -> void:
	is_open = true
	position.y = _closed_y - size.y * 0.98
	for c in get_children():
		if c is CollisionShape3D:
			c.disabled = true
	if interactable:
		interactable.when = {"not_flag": _open_flag()}


func _open_flag() -> String:
	return "door_%s_open" % door_id
