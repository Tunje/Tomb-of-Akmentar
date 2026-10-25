## Copied from Wreck Wreckers (game/enemies/model_retarget.gd, Rivet). Tombs change: setup()'s
## `unaligned` UAL bones skip the aim correction (the explorer's clavicles: aimed like UAL's they
## turned ~30 deg at rest and lifted his shoulders; they now copy the clip's motion only).
## ModelRetarget — D136 pilot: plays our Quaternius (UAL) animations on one of Simon's own
## enemy models, whose auto-rig has generic bones (bone_0..N) and a rest pose that is not
## our T-pose. Owner: Rivet.
## A SOURCE skeleton (a UAL body, hidden, animated as usual: AnimationPlayer/Tree) drives a
## TARGET skeleton every frame through a bone map (UAL name -> target name, from
## enemies/tools/propose_bone_map.py, reviewed by hand):
##   - each mapped target bone's rest is first turned so the bone points where the source
##     bone points at rest (head -> mapped child head), so the two rests agree;
##   - then the source bone's rotation away from ITS rest is applied on top (world space);
##   - the pelvis also moves by the source pelvis' offset from rest (scaled by the bodies);
##   - unmapped bones (fingers, tails, extra limbs) keep their rest and follow their parent.
## Both skeletons may sit under any transforms (facing, scale): all goes through world space.
## Purely cosmetic, like EnemyModel.
class_name ModelRetarget
extends Node

## UAL bone -> the UAL bone it points at (its aim at rest). Bones without one (Head, hand,
## ball) keep their parent's rest correction.
const AIM := {
	&"pelvis": &"spine_01", &"spine_01": &"spine_02", &"spine_02": &"spine_03",
	&"spine_03": &"neck_01", &"neck_01": &"Head",
	&"clavicle_l": &"upperarm_l", &"upperarm_l": &"lowerarm_l", &"lowerarm_l": &"hand_l",
	&"clavicle_r": &"upperarm_r", &"upperarm_r": &"lowerarm_r", &"lowerarm_r": &"hand_r",
	&"thigh_l": &"calf_l", &"calf_l": &"foot_l", &"foot_l": &"ball_l",
	&"thigh_r": &"calf_r", &"calf_r": &"foot_r", &"foot_r": &"ball_r",
}

var source: Skeleton3D
var target: Skeleton3D
var _src_of := {}  # target bone index -> source bone index
var _order: PackedInt32Array  # target bones, parents first
var _aligned := {}  # target bone index -> rest basis turned onto the source's rest (target space)
var _src_rest := {}  # source bone index -> global rest basis (source space)
var _pelvis_t := -1
var _pelvis_s := -1
## Target leg length / source leg length (world): the pelvis' moves scale with the body.
var _leg_ratio := 1.0


## `map`: UAL bone name -> target bone name. Call after both skeletons are in the tree.
func setup(src: Skeleton3D, tgt: Skeleton3D, map: Dictionary, unaligned: Array = []) -> void:
	if source != null and is_instance_valid(source) and source.skeleton_updated.is_connected(apply):
		source.skeleton_updated.disconnect(apply)
	source = src
	target = tgt
	_src_of.clear()
	_aligned.clear()
	_src_rest.clear()
	var tgt_of := {}  # source index -> target index
	for ual in map:
		var s := src.find_bone(String(ual))
		var t := tgt.find_bone(String(map[ual]))
		if s < 0 or t < 0 or _src_of.has(t):
			continue  # a target bone driven once (the first entry)
		_src_of[t] = s
		tgt_of[s] = t
		_src_rest[s] = src.get_bone_global_rest(s).basis.orthonormalized()
	_pelvis_s = src.find_bone("pelvis")
	_pelvis_t = tgt_of.get(_pelvis_s, -1)
	_order = _parents_first(tgt)
	var sl := _leg(src, src.find_bone("thigh_l"), src.find_bone("foot_l"))
	var tl := _leg(tgt, tgt_of.get(src.find_bone("thigh_l"), -1), tgt_of.get(src.find_bone("foot_l"), -1))
	_leg_ratio = tl / sl if sl > 0.0 and tl > 0.0 else 1.0
	# Rest correction: turn each mapped bone so it aims like its source bone at rest, rolled
	# about its aim to a reference: the body's forward (from the hips), and for a leg bone that
	# leg's own foot -> toe. Simon's Brutes stand with their feet splayed 30-60 deg; turned by
	# aim alone their knees and feet kept facing outwards, so a walk bent them sideways.
	_tgt_of = tgt_of
	var body_s := _body_forward(_src_pos("thigh_l"), _src_pos("thigh_r"), _src_basis() * Vector3.BACK)
	var body_t := _body_forward(_tgt_pos("thigh_l"), _tgt_pos("thigh_r"), body_s)
	var leg_s := {}
	var leg_t := {}
	for side in ["l", "r"]:
		leg_s[side] = _flat_dir(_src_pos("ball_" + side) - _src_pos("foot_" + side), body_s)
		leg_t[side] = _flat_dir(_tgt_pos("ball_" + side) - _tgt_pos("foot_" + side), body_t)
	var turn := {}  # target index -> world-space rotation applied to its rest
	for t in _order:
		var p := tgt.get_bone_parent(t)
		var q: Basis = turn.get(p, Basis.IDENTITY)
		if _src_of.has(t):
			var s: int = _src_of[t]
			var aim: StringName = AIM.get(StringName(src.get_bone_name(s)), &"")
			var sa := src.find_bone(String(aim)) if aim != &"" else -1
			if sa >= 0 and tgt_of.has(sa) and not String(src.get_bone_name(s)) in unaligned:
				var d_s := _src_dir(src.get_bone_global_rest(sa).origin - src.get_bone_global_rest(s).origin)
				var d_t := _tgt_dir(tgt.get_bone_global_rest(tgt_of[sa]).origin - tgt.get_bone_global_rest(t).origin)
				var name := String(src.get_bone_name(s))
				var side := name.right(1)
				var leg := (name.begins_with("thigh_") or name.begins_with("calf_") or name.begins_with("foot_")) \
					and (side == "l" or side == "r")
				q = _frame(d_s, leg_s.get(side, body_s) if leg else body_s) * _frame(d_t, leg_t.get(side, body_t) if leg else body_t).inverse()
		turn[t] = q
		if _src_of.has(t):
			var rest_w := _tgt_basis() * tgt.get_bone_global_rest(t).basis.orthonormalized()
			_aligned[t] = _tgt_basis().inverse() * (q * rest_w)
	_connect_source()


## Driven by the source's skeleton_updated (after its modifiers ran), not _process: Ferro's
## ragdoll (PhysicalBoneSimulator3D) is a skeleton modifier, so its pose exists only after
## that pass; read earlier, his body stood upright while ours fell (lifted-kill check).
func _enter_tree() -> void:
	set_process(false)
	_connect_source()


func _connect_source() -> void:
	if source != null and is_inside_tree() and not source.skeleton_updated.is_connected(apply):
		source.skeleton_updated.connect(apply)


func _exit_tree() -> void:
	if source != null and is_instance_valid(source) and source.skeleton_updated.is_connected(apply):
		source.skeleton_updated.disconnect(apply)


## One frame: the target follows the source's current pose.
func apply() -> void:
	if source == null or target == null:
		return
	var sb := _src_basis()
	var tb_inv := _tgt_basis().inverse()
	var global := {}  # target index -> global basis this frame (target space)
	for t in _order:
		var p := target.get_bone_parent(t)
		var parent_g: Basis = global[p] if p >= 0 else Basis.IDENTITY
		var g: Basis
		if _src_of.has(t):
			var s: int = _src_of[t]
			var pose := source.get_bone_global_pose(s).basis.orthonormalized()
			var delta_w := sb * (pose * (_src_rest[s] as Basis).inverse()) * sb.inverse()
			g = tb_inv * delta_w * _tgt_basis() * (_aligned[t] as Basis)
			target.set_bone_pose_rotation(t, (parent_g.inverse() * g).get_rotation_quaternion())
		else:
			g = parent_g * target.get_bone_rest(t).basis
		global[t] = g
	if _pelvis_t >= 0:
		var off := source.get_bone_global_pose(_pelvis_s).origin - source.get_bone_global_rest(_pelvis_s).origin
		var off_w := source.global_transform.basis * off * _leg_ratio
		var off_t := target.global_transform.basis.inverse() * off_w
		var p := target.get_bone_parent(_pelvis_t)
		var p_rest := target.get_bone_global_rest(p).basis if p >= 0 else Basis.IDENTITY
		target.set_bone_pose_position(_pelvis_t, target.get_bone_rest(_pelvis_t).origin + p_rest.inverse() * off_t)


func _src_basis() -> Basis:
	return source.global_transform.basis.orthonormalized()


func _tgt_basis() -> Basis:
	return target.global_transform.basis.orthonormalized()


func _src_dir(v: Vector3) -> Vector3:
	return (source.global_transform.basis * v).normalized()


func _tgt_dir(v: Vector3) -> Vector3:
	return (target.global_transform.basis * v).normalized()


var _tgt_of := {}  # source index -> target index (setup)


## World rest position of a source bone (INF = none).
func _src_pos(ual: String) -> Vector3:
	var i := source.find_bone(ual)
	return source.global_transform * source.get_bone_global_rest(i).origin if i >= 0 else Vector3.INF


## World rest position of the target bone mapped to a source bone (INF = not mapped).
func _tgt_pos(ual: String) -> Vector3:
	var t: int = _tgt_of.get(source.find_bone(ual), -1)
	return target.global_transform * target.get_bone_global_rest(t).origin if t >= 0 else Vector3.INF


## Forward from the hips: left thigh - right thigh, crossed with up (left = +x -> forward +z).
static func _body_forward(l: Vector3, r: Vector3, fallback: Vector3) -> Vector3:
	if l == Vector3.INF or r == Vector3.INF:
		return fallback
	return _flat_dir((l - r).cross(Vector3.UP), fallback)


static func _flat_dir(v: Vector3, fallback: Vector3) -> Vector3:
	if not v.is_finite():
		return fallback
	v.y = 0.0
	return v.normalized() if v.length() > 0.01 else fallback


## A frame from a bone's aim (y) and a reference direction (x = the reference made
## perpendicular to the aim): the body's forward, or up when the bone points forward/back.
static func _frame(aim: Vector3, forward: Vector3) -> Basis:
	var y := aim.normalized()
	var ref := forward.normalized()
	if absf(ref.dot(y)) > 0.9:
		ref = Vector3.UP
	var x := (ref - y * ref.dot(y)).normalized()
	return Basis(x, y, x.cross(y))


static func _leg(sk: Skeleton3D, thigh: int, foot: int) -> float:
	if thigh < 0 or foot < 0:
		return 0.0
	var v := sk.get_bone_global_rest(foot).origin - sk.get_bone_global_rest(thigh).origin
	return (sk.global_transform.basis * v).length()


static func _parents_first(sk: Skeleton3D) -> PackedInt32Array:
	var out := PackedInt32Array()
	var todo: Array = []
	for i in sk.get_bone_count():
		if sk.get_bone_parent(i) < 0:
			todo.append(i)
	while not todo.is_empty():
		var b: int = todo.pop_front()
		out.append(b)
		for c in sk.get_bone_children(b):
			todo.append(c)
	return out
