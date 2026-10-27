class_name FaceRig
extends Node
## Eyes, blinks and jaw for image-to-3d's named-character heads. It finds what the head has and
## drives only that; on a body without any of it, attach() returns null and nothing runs.
##   eyes:  nodes or bones named eye_l / eye_r (any case, "eye.L", "Eye_Left" too): aimed at `look_at`
##   blink: blend shapes "blink", "eyeBlink_L/R", "eyes_closed"...: closed every 2-6 s for 0.15 s
##   jaw:   a "jaw" bone (rotated open) or a "jawOpen" / "mouthOpen" shape, flapped while `talking`
##   FaceRig.attach(body)              -> FaceRig or null
##   FaceRig.of(body).talking = true   (Barks / the conversation set it while a line plays)

const BLINK_SHAPES := ["blink", "eyeblink", "eyes_closed", "eyesclosed", "eye_close"]
const JAW_SHAPES := ["jawopen", "jaw_open", "mouthopen", "mouth_open"]
const EYE_TURN := deg_to_rad(28.0)  # how far the eyes turn before the head would have to
const JAW_OPEN := deg_to_rad(14.0)

## Where the eyes look (global); null = straight ahead.
var look_at: Variant = null
var talking := false

var _root: Node3D
var _skeleton: Skeleton3D
var _eye_nodes: Array[Node3D] = []
var _eye_rest: Array[Basis] = []
var _eye_bones: Array[int] = []
var _jaw_bone := -1
var _blink: Array = []  # [MeshInstance3D, shape index]
var _jaw: Array = []
var _next_blink := 0.0
var _blink_t := -1.0
var _jaw_f := 0.0
var _t := 0.0


static func attach(body: Node3D) -> FaceRig:
	var f := FaceRig.new()
	f.name = "FaceRig"
	f._root = body
	if not f._scan():
		f.free()
		return null
	body.add_child(f)
	return f


static func of(body: Node) -> FaceRig:
	return body.get_node_or_null("FaceRig") as FaceRig if body else null


static func _key(s: String) -> String:
	return s.to_lower().replace(".", "_").replace(" ", "_")


static func _is_eye(s: String) -> int:  # 0 no, 1 left, 2 right
	var k := _key(s)
	if not k.begins_with("eye") or "lid" in k or "brow" in k or "lash" in k:
		return 0
	if k.ends_with("_l") or k.ends_with("left"):
		return 1
	if k.ends_with("_r") or k.ends_with("right"):
		return 2
	return 0


func _scan() -> bool:
	for n in _root.find_children("*", "Node3D", true, false):
		if _is_eye(n.name) > 0 and not n is Skeleton3D:
			_eye_nodes.append(n)
			_eye_rest.append((n as Node3D).basis)
	var sks := _root.find_children("*", "Skeleton3D", true, false)
	if not sks.is_empty():
		_skeleton = sks[0]
		for i in _skeleton.get_bone_count():
			var bn := _skeleton.get_bone_name(i)
			if _is_eye(bn) > 0:
				_eye_bones.append(i)
			elif _key(bn) in ["jaw", "jaw_bone", "lowerjaw", "jaw_01"]:
				_jaw_bone = i
	for mi: MeshInstance3D in _root.find_children("*", "MeshInstance3D", true, false):
		if not mi.mesh is ArrayMesh:  # primitives have no blend shapes
			continue
		for s in mi.mesh.get_blend_shape_count():
			var k := _key(String(mi.mesh.get_blend_shape_name(s)))
			for b in BLINK_SHAPES:
				if k.begins_with(b):
					_blink.append([mi, s])
			if k in JAW_SHAPES:
				_jaw.append([mi, s])
	_next_blink = randf_range(1.0, 4.0)
	return not (_eye_nodes.is_empty() and _eye_bones.is_empty() and _blink.is_empty() and _jaw.is_empty() and _jaw_bone < 0)


func _process(delta: float) -> void:
	_t += delta
	_blinks(delta)
	_eyes()
	_mouth(delta)


func _blinks(delta: float) -> void:
	if _blink.is_empty():
		return
	_next_blink -= delta
	if _next_blink <= 0.0 and _blink_t < 0.0:
		_blink_t = 0.0
		_next_blink = randf_range(2.0, 6.0) if randf() > 0.15 else 0.35  # now and then a double blink
	var w := 0.0
	if _blink_t >= 0.0:
		_blink_t += delta
		w = sin(clampf(_blink_t / 0.15, 0.0, 1.0) * PI)
		if _blink_t >= 0.15:
			_blink_t = -1.0
	for b in _blink:
		if is_instance_valid(b[0]):
			(b[0] as MeshInstance3D).set_blend_shape_value(b[1], w)


## The eyes' yaw/pitch toward look_at, clamped, in the head's frame.
func _aim(from: Vector3, head: Basis) -> Vector2:
	if look_at == null:
		return Vector2.ZERO
	var d: Vector3 = head.inverse() * ((look_at as Vector3) - from)
	if d.length() < 0.01:
		return Vector2.ZERO
	d = d.normalized()
	# glTF heads face +Z
	return Vector2(clampf(atan2(d.x, d.z), -EYE_TURN, EYE_TURN), clampf(asin(clampf(-d.y, -1, 1)), -EYE_TURN * 0.6, EYE_TURN * 0.6))


func _eyes() -> void:
	for i in _eye_nodes.size():
		var e := _eye_nodes[i]
		if not is_instance_valid(e):
			continue
		var parent_b: Basis = (e.get_parent() as Node3D).global_basis if e.get_parent() is Node3D else Basis()
		var a := _aim(e.global_position, parent_b * _eye_rest[i])
		e.basis = _eye_rest[i] * Basis.from_euler(Vector3(a.y, a.x, 0.0))
	if _skeleton == null:
		return
	for b in _eye_bones:
		var p := _skeleton.get_bone_parent(b)  # aim from the eye at rest, not last frame's aim
		var rest := (_skeleton.get_bone_global_pose(p) if p >= 0 else Transform3D()) * _skeleton.get_bone_rest(b)
		var g := _skeleton.global_transform * rest
		var a := _aim(g.origin, g.basis.orthonormalized())
		_skeleton.set_bone_pose_rotation(b, _skeleton.get_bone_rest(b).basis.get_rotation_quaternion() * Quaternion.from_euler(Vector3(a.y, a.x, 0.0)))


func _mouth(delta: float) -> void:
	var want := 0.0
	if talking:  # syllable-ish flapping: two out-of-step waves, never fully shut for long
		want = clampf(0.55 + 0.45 * sin(_t * 17.0) * sin(_t * 6.3 + 1.1), 0.0, 1.0)
	_jaw_f = move_toward(_jaw_f, want, delta * 9.0)
	for j in _jaw:
		if is_instance_valid(j[0]):
			(j[0] as MeshInstance3D).set_blend_shape_value(j[1], _jaw_f)
	if _jaw_bone >= 0 and _skeleton:
		_skeleton.set_bone_pose_rotation(_jaw_bone, _skeleton.get_bone_rest(_jaw_bone).basis.get_rotation_quaternion() * Quaternion(Vector3.RIGHT, _jaw_f * JAW_OPEN))
