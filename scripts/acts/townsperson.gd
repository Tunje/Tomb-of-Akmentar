class_name Townsperson
extends RiggedBody
## Someone going about their business: walks a loop of points (UAL Walk), stopping a few seconds
## at each (Idle). No physics collision, but manners: when the player or a companion is just
## ahead they slow, stop and step aside off their line (back onto it once you've passed), and one
## that ends up between the camera and the player fades out so it doesn't fill the view.
##   Townsperson.make(level, [Vector3(4, 0, 49), Vector3(34, 0, 49)], model)

const SPEED := 1.25           # m/s, about the Walk clip's own pace
const TURN := 5.0
const NOTICE := 2.6           # m: someone this close ahead and they start to step aside
const HALT := 1.2             # m: this close and they stop walking until they're clear
const ASIDE := 1.0            # m off their line
const PASS_CLEAR := 0.85      # m to the side: stood this far aside, they walk on past
const SIDE_SPEED := 1.1       # m/s sideways

var glb := ""
var route: Array = []
var _i := 0
var _wait := 0.0
var _move := 0.0              # 0 idle .. 1 walking (blend)
var _base := Vector3.ZERO     # where they are on their own line
var _side := 0.0              # how far they've stepped off it (+ = to their right)
var _aside_sign := 0.0        # the side picked while someone's in the way (0 = none yet)
var _fade := 0.0              # 0 seen .. 1 faded out
var _faded_meshes: Array[GeometryInstance3D] = []
var _player: Node3D


static func make(parent: Node3D, points: Array, model: String) -> Townsperson:
	if points.is_empty() or not assets_present(model):
		return null
	var t := Townsperson.new()
	t.glb = model
	t.route = points
	parent.add_child(t)
	# Start somewhere along the way, not all at the first point.
	t._i = randi() % points.size()
	t._base = points[t._i]
	t.global_position = t._base
	t._wait = randf_range(0.0, 3.0)
	return t


func _ready() -> void:
	_setup_rig(glb)


func _build_tree() -> void:
	var bt := AnimationNodeBlendTree.new()
	bt.add_node("idle", _anim("Idle"))
	bt.add_node("walk", _anim("Walk"))
	bt.add_node("move", AnimationNodeBlend2.new())
	bt.connect_node("move", 0, "idle")
	bt.connect_node("move", 1, "walk")
	bt.connect_node("output", 0, "move")
	_start_tree(bt)


func _process(delta: float) -> void:
	if route.size() < 2:
		return
	var goal: Vector3 = route[(_i + 1) % route.size()]
	var to := goal - _base
	to.y = 0.0
	var d := to.length()
	var fwd := to / d if d > 0.01 else -global_basis.z
	var right := fwd.cross(Vector3.UP)
	# Who's in the way: the player and the party, just ahead of where they're going.
	var block := _blocker(fwd)
	var want_side := 0.0
	var pace := 1.0
	if not block.is_empty():
		var rel: Vector3 = block.rel
		# Step to the side away from them (their right if dead ahead), unless a wall or a stall is
		# there: then the other way; with no room either side, they just stop. Chosen once.
		if _aside_sign == 0.0:
			var pref := -signf(rel.dot(right)) if absf(rel.dot(right)) > 0.1 else 1.0
			_aside_sign = pref if _room(right * pref) else (-pref if _room(-right * pref) else 0.001)
		want_side = ASIDE * _aside_sign if absf(_aside_sign) >= 1.0 else 0.0
		pace = clampf((float(block.dist) - HALT) / (NOTICE - HALT), 0.0, 1.0)
		if absf(rel.dot(right)) >= PASS_CLEAR and absf(_side) >= ASIDE * 0.95:
			pace = 1.0  # stepped well aside: walk on past them
	else:
		_aside_sign = 0.0
	_side = move_toward(_side, want_side, SIDE_SPEED * delta)
	var walking := _wait <= 0.0
	if not walking:
		_wait -= delta
	elif d < 0.1:
		_i = (_i + 1) % route.size()
		_wait = randf_range(1.0, 4.5)
	else:
		_base += fwd * minf(SPEED * _move * pace * delta, d)
	var moving := walking and pace > 0.05
	global_position = _base + right * _side
	var face := fwd
	if not block.is_empty() and pace < 0.5:
		face = (block.rel as Vector3).normalized()  # stood aside, they watch you pass
	rotation.y = lerp_angle(rotation.y, atan2(-face.x, -face.z), minf(delta * TURN, 1.0))
	_move = move_toward(_move, 1.0 if moving else 0.0, delta * 3.0)
	if _tree:
		_tree.set("parameters/move/blend_amount", _move)
	_update_fade(delta)


## The nearest of the player and the party ahead of them within NOTICE: {"rel", "dist"}, or {}.
func _blocker(fwd: Vector3) -> Dictionary:
	var best := {}
	var others: Array = get_tree().get_nodes_in_group("party")
	var p := _find_player()
	if p:
		others.append(p)
	for n in others:
		var o := n as Node3D
		if o == null or not is_instance_valid(o) or not o.is_visible_in_tree():
			continue
		var rel := o.global_position - global_position
		rel.y = 0.0
		var dist := rel.length()
		var ahead := fwd.dot(rel / dist) if dist > 0.01 else 1.0
		if dist > NOTICE or (ahead < 0.2 and (dist > 1.8 or ahead < -0.6)):
			continue  # far, or well behind them (one alongside still holds them aside)
		if best.is_empty() or dist < float(best.dist):
			best = {"rel": rel, "dist": dist}
	return best


## Room to step aside that way: a short ray at waist height off their line hits nothing solid.
func _room(dir: Vector3) -> bool:
	var from := _base + Vector3.UP * 0.9
	var q := PhysicsRayQueryParameters3D.create(from, from + dir.normalized() * (ASIDE + 0.4), 1)
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func _find_player() -> Node3D:
	if is_instance_valid(_player):
		return _player
	var scene := get_tree().current_scene
	if scene:
		for c in scene.get_children():
			if c is Player:
				_player = c
				break
	return _player


## Fade out while standing between the camera and the player (they'd fill the screen).
func _update_fade(delta: float) -> void:
	_fade = CameraFade.step(self, _fade, delta, _faded_meshes)
