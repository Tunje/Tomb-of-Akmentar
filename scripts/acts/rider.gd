class_name Rider
extends Node
## Someone on horseback (or at a truck's wheel) who isn't the player: a companion riding with the
## convoy, a Keeper of the Veil galloping in, the hired drover. The body is any Armour 01 GLB
## on ExplorerBody's riding pose (UAL1 Sitting_Idle, feet in the stirrups, hands on the reins)
## or driving pose; the Rider steers its mount toward `goal` by calling the mount's drive(), the
## same interface Player uses. dismount() takes the body off and returns where to stand, so the
## caller can put a Gunman there.
##   var r := Rider.mount(level, horse, Characters.glb("mahmoud"))
##   r.goal = Vector3(...); r.want_speed = 3.8

## How hard it steers per radian off course, and how far ahead it looks along a path.
const STEER_GAIN := 2.2
const ARRIVE := 2.5

var mount_node: Node3D  # Horse or Truck
## 0 = the driver's seat / saddle (this Rider steers); higher = a truck's passenger (it just sits).
var seat := 0
var body: ExplorerBody
## Where to ride (INF = hold still) and how fast (m/s; a horse settles into the nearest gait).
var goal := Vector3.INF
var want_speed := 3.8
## Optional route: the Rider rides to each point in turn, then to `goal`.
var path: Array[Vector3] = []
var arrived := false
var _glb := ""


## Puts a rider with `glb`'s look on `m` (a Horse or Truck) and returns its controller (added
## under `parent`).
static func mount(parent: Node, m: Node3D, glb: String, seat_index := 0) -> Rider:
	var r := Rider.new()
	r.name = "Rider_%s_%d" % [m.name, seat_index]
	r.seat = seat_index
	r.mount_node = m
	r._glb = glb
	parent.add_child(r)
	return r


func _ready() -> void:
	mount_node.board(_seat_holder(), seat)
	if seat > 0:
		set_physics_process(false)
	body = RiderBody.make(_glb)
	if body:
		mount_node.add_child(body)
		if mount_node is Horse:
			body.set_riding(true, mount_node)
		else:
			body.set_driving(true)
	_place_body()


## Vehicles keep a Node3D as their driver; ours is a marker on the mount.
var _holder: Node3D


func _seat_holder() -> Node3D:
	if _holder == null:
		_holder = Node3D.new()
		_holder.name = "RiderSeat"
		mount_node.add_child(_holder)
	return _holder


func _place_body() -> void:
	if body == null or not is_instance_valid(mount_node):
		return
	var m: Marker3D = mount_node.seats[mini(seat, mount_node.seats.size() - 1)]
	body.global_position = m.global_position - Vector3.UP * 0.55
	body.rotation = Vector3.ZERO


func _process(_delta: float) -> void:
	_place_body()


func _physics_process(delta: float) -> void:
	if not is_instance_valid(mount_node) or body == null:
		return
	if mount_node is Horse and not (mount_node as Horse).alive:
		return
	var to := goal
	while not path.is_empty() and _flat(path[0] - mount_node.global_position).length() < ARRIVE * 2.0:
		path.pop_front()
	if not path.is_empty():
		to = path[0]
	if to == Vector3.INF:
		mount_node.drive(-1.0, 0.0, true, delta)
		return
	var d := _flat(to - mount_node.global_position)
	if path.is_empty() and d.length() < ARRIVE:
		arrived = true
		mount_node.drive(-1.0, 0.0, true, delta)
		return
	arrived = false
	var fwd := _flat(-mount_node.global_basis.z).normalized()
	var err := fwd.signed_angle_to(d.normalized(), Vector3.UP)  # positive = to the left
	var steer := clampf(err * STEER_GAIN, -1.0, 1.0)
	var speed := _speed()
	var want := want_speed
	if path.is_empty():
		want = minf(want, d.length() * 0.8)  # ease in to the goal
	var throttle := clampf((want - speed) * 0.6, -1.0, 1.0)
	if mount_node is Horse:
		# A horse holds a gait on its own: ask for more only while short of it.
		throttle = 1.0 if speed < want - 0.6 else (-0.5 if speed > want + 1.5 else 0.0)
	mount_node.drive(throttle, steer, false, delta)


func _speed() -> float:
	if mount_node is Horse:
		return (mount_node as Horse).speed
	return -(mount_node.global_basis.inverse() * (mount_node as RigidBody3D).linear_velocity).z


## Off the mount: the body goes, the seat is free. Returns where the rider now stands.
func dismount() -> Vector3:
	var at: Vector3 = mount_node.exit_point() if is_instance_valid(mount_node) else Vector3.ZERO
	if seat > 0 and is_instance_valid(mount_node):  # passengers climb down each side, front to back
		at = mount_node.global_transform * Vector3(1.6 if seat % 2 == 1 else -1.6, 0.2, 0.4 + seat * 0.6)
	if is_instance_valid(mount_node):
		mount_node.leave(_holder)
		mount_node.idle()
	if body:
		body.queue_free()
		body = null
	if _holder:
		_holder.queue_free()
	queue_free()
	return at


## Shot in the saddle (the drover in the first volley): slumps where he sits.
func kill() -> void:
	if body:
		body.die()
	if is_instance_valid(mount_node):
		mount_node.leave(_holder)
		mount_node.idle()
	set_physics_process(false)
	goal = Vector3.INF


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0, v.z)


## ExplorerBody with another GLB on the same rig (ExplorerBody itself loads one static path).
class RiderBody extends ExplorerBody:
	var _look := ""

	static func make(glb: String) -> RiderBody:
		if not assets_present(glb):
			return null
		var b := RiderBody.new()
		b.name = "RiderBody"
		b._look = glb
		return b

	func _ready() -> void:
		_setup_rig(_look)
		var hand := BoneAttachment3D.new()
		hand.bone_name = BONE_MAP["hand_r"]
		skeleton.add_child(hand)
		gun_holder = Node3D.new()
		hand.add_child(gun_holder)
		skeleton.skeleton_updated.connect(_orient_gun)
		_src.skeleton_updated.connect(_reach_left)
		_src.skeleton_updated.connect(_ride_pose)
