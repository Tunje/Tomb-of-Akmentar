class_name SlabDoor
extends StaticBody3D
## A drop-slab across a maze corridor (Act 5's escape). It hangs in a slot in the ceiling, only
## its lip showing; once armed it sinks slowly when `target` runs at it down the corridor (or
## after `drop_after` seconds, wherever anyone is). A sprint gets you under; whoever lags behind
## (a companion helping another up, the guardian) is cut off and has to find another way round.
## Anyone still under it near the end is shoved out to the side they're on, never crushed.
##   var s := SlabDoor.make(level._nav, floor_point, Vector3(2, 5, 0.5), 0.0, stone)
##   s.target = player; s.armed = true; s.shut.connect(rebake)

signal started
signal shut

const DROP_TIME := 4.5     # floor to ceiling, slow: the pass window is about the first 2.9 s
const TRIGGER := 7.0       # how far ahead of the runner it starts down
const LIP := 0.4           # how much shows under the ceiling while it hangs open

var target: Node3D
var people: Array = []     # bodies outside the "party"/"mummies" groups to keep clear (player, guardian)
var armed := false
var drop_after := -1.0     # > 0: it comes down on its own this long after arming
var is_shut := false
var _falling := false
var _armed_t := 0.0
var _floor := Vector3.ZERO
var _size := Vector3.ONE


static func make(parent: Node, floor_point: Vector3, size: Vector3, rot_y: float, mat: Material) -> SlabDoor:
	var s := SlabDoor.new()
	s._floor = floor_point
	s._size = size
	s.collision_layer = 1
	s.collision_mask = 0
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	s.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	s.add_child(mi)
	parent.add_child(s)
	s.add_to_group("slab_door")
	s.rotation.y = rot_y
	s.global_position = floor_point + Vector3.UP * (size.y * 1.5 - LIP)  # up in its slot
	return s


func _physics_process(delta: float) -> void:
	if not armed or _falling or is_shut:
		return
	_armed_t += delta
	if drop_after > 0.0 and _armed_t >= drop_after:
		fall()
		return
	if target == null or not is_instance_valid(target):
		return
	# Runs at it: close, in line with the corridor (not just behind a wall), and coming this way.
	var local := to_local(target.global_position)
	if absf(local.z) < TRIGGER and absf(local.z) > 1.0 and absf(local.x) < _size.x * 0.6 \
			and absf(target.global_position.y - _floor.y) < 2.0:
		var v: Vector3 = target.get("velocity") if "velocity" in target else Vector3.ZERO
		var toward := global_basis.z * -signf(local.z)
		if v.dot(toward) > 1.0:
			fall()


func fall() -> void:
	if _falling or is_shut:
		return
	_falling = true
	started.emit()
	Barks.say_any(get_tree(), "slab_falling", global_position)
	Hints.once("slabs")
	Sfx.play_at(get_parent(), Sfx.groan(), _floor + Vector3.UP * 3.0, 6.0, 0.0)
	for i in 4:
		Fx.impact(get_parent(), _floor + global_basis.x * randf_range(-0.8, 0.8) + Vector3.UP * (_size.y - 0.2),
			Vector3.DOWN, Fx.Kind.STONE)
	var tw := create_tween()
	tw.tween_property(self, "global_position:y", _floor.y + _size.y * 0.5, DROP_TIME)
	tw.tween_callback(_land)


func _land() -> void:
	_clear_under()
	is_shut = true
	Sfx.play_at(get_parent(), Sfx.impact(), _floor + Vector3.UP * 0.5, 8.0, 0.0)
	Fx.impact(get_parent(), _floor + Vector3.UP * 0.1, Vector3.UP, Fx.Kind.STONE)
	Controls.rumble_at(get_tree(), _floor, 0.8, 1.0, 0.35, 20.0)  # the thud through the pad, by distance
	shut.emit()


func _process(_delta: float) -> void:
	# Low enough to hit a head: push anyone under it out to their side.
	if _falling and not is_shut and global_position.y - _size.y * 0.5 < _floor.y + 2.0:
		_clear_under()


func _clear_under() -> void:
	var all: Array = people + get_tree().get_nodes_in_group("party") + get_tree().get_nodes_in_group("mummies")
	for n in all:
		if n == null or not is_instance_valid(n):
			continue
		var b := n as Node3D
		if b:
			var local := to_local(b.global_position)
			if absf(local.x) < _size.x * 0.5 and absf(local.z) < _size.z * 0.5 + 0.45 \
					and absf(b.global_position.y - _floor.y) < 2.0:
				local.z = (_size.z * 0.5 + 0.5) * (1.0 if local.z >= 0.0 else -1.0)
				b.global_position = to_global(local)
