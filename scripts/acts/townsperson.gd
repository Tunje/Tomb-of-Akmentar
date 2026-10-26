class_name Townsperson
extends RiggedBody
## Someone going about their business: walks a loop of points (UAL Walk), stopping a few seconds
## at each (Idle). Decoration with no AI or collision; the player walks through them.
##   Townsperson.make(level, [Vector3(4, 0, 49), Vector3(34, 0, 49)], model)

const SPEED := 1.25           # m/s, about the Walk clip's own pace
const TURN := 5.0

var glb := ""
var route: Array = []
var _i := 0
var _wait := 0.0
var _move := 0.0              # 0 idle .. 1 walking (blend)


static func make(parent: Node3D, points: Array, model: String) -> Townsperson:
	if points.is_empty() or not assets_present(model):
		return null
	var t := Townsperson.new()
	t.glb = model
	t.route = points
	parent.add_child(t)
	# Start somewhere along the way, not all at the first point.
	t._i = randi() % points.size()
	t.global_position = points[t._i]
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
	var walking := _wait <= 0.0
	if not walking:
		_wait -= delta
	else:
		var goal: Vector3 = route[(_i + 1) % route.size()]
		var to := goal - global_position
		to.y = 0.0
		var d := to.length()
		if d < 0.1:
			_i = (_i + 1) % route.size()
			_wait = randf_range(1.0, 4.5)
		else:
			global_position += to / d * minf(SPEED * _move * delta, d)
			rotation.y = lerp_angle(rotation.y, atan2(-to.x, -to.z), minf(delta * TURN, 1.0))
	_move = move_toward(_move, 1.0 if walking else 0.0, delta * 3.0)
	if _tree:
		_tree.set("parameters/move/blend_amount", _move)
