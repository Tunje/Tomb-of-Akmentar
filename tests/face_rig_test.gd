extends Node
## FaceRig on a made-up head (no image-to-3d head exists yet): eye bones aim at a target and stay
## clamped, the jaw flaps only while talking, a blink shape closes and opens, and a body with none
## of it gets no FaceRig. Headless:
##   godot --headless --path . res://tests/face_rig_test.tscn -- --ci

var _fails := 0


func _check(ok: bool, what: String) -> void:
	print("RESULT face_rig %s %s" % ["ok" if ok else "FAIL", what])
	if not ok:
		_fails += 1


func _blink_mesh() -> ArrayMesh:
	var base := BoxMesh.new().get_mesh_arrays()
	var m := ArrayMesh.new()
	m.add_blend_shape("eyeBlink_L")
	m.add_blend_shape("jawOpen")
	var shape: Array = []
	shape.resize(Mesh.ARRAY_MAX)
	shape[Mesh.ARRAY_VERTEX] = base[Mesh.ARRAY_VERTEX]
	shape[Mesh.ARRAY_NORMAL] = base[Mesh.ARRAY_NORMAL]
	shape[Mesh.ARRAY_TANGENT] = base[Mesh.ARRAY_TANGENT]
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, base, [shape, shape])
	return m


func _ready() -> void:
	var head := Node3D.new()
	add_child(head)
	var sk := Skeleton3D.new()
	head.add_child(sk)
	sk.add_bone("Head")
	for n in ["eye.L", "Eye_R", "jaw"]:
		var i := sk.add_bone(n)
		sk.set_bone_parent(i, 0)
		sk.set_bone_rest(i, Transform3D(Basis(), Vector3(0, 1.6, 0.1)))
	sk.reset_bone_poses()
	var mi := MeshInstance3D.new()
	mi.mesh = _blink_mesh()
	head.add_child(mi)
	var f := FaceRig.attach(head)
	_check(f != null, "attaches to a head with eyes, jaw and shapes")
	if f == null:
		_end()
		return
	_check(f._eye_bones.size() == 2 and f._jaw_bone >= 0, "found 2 eye bones and the jaw")
	_check(f._blink.size() == 1 and f._jaw.size() == 1, "found the blink and jaw shapes")

	f.look_at = head.global_position + Vector3(5, 1.6, 5)  # off to the side, glTF forward is +Z
	await _frames(3)
	var yaw := sk.get_bone_pose_rotation(1).get_euler().y
	_check(yaw > 0.1 and yaw <= FaceRig.EYE_TURN + 0.01, "eyes turn toward the target, clamped (yaw %.2f)" % yaw)
	f.look_at = head.global_position + Vector3(0, 1.6, -5)  # behind: clamped, not flipped round
	await _frames(3)
	yaw = absf(sk.get_bone_pose_rotation(1).get_euler().y)
	_check(yaw <= FaceRig.EYE_TURN + 0.01, "a target behind stays clamped (yaw %.2f)" % yaw)

	await _frames(10)
	_check(mi.get_blend_shape_value(1) < 0.01, "jaw shut while quiet")
	f.talking = true
	var most := 0.0
	for k in 40:
		await get_tree().process_frame
		most = maxf(most, mi.get_blend_shape_value(1))
	_check(most > 0.4, "jaw opens while talking (%.2f)" % most)
	f.talking = false

	f._next_blink = 0.0
	var closed := 0.0
	for k in 20:
		await get_tree().process_frame
		closed = maxf(closed, mi.get_blend_shape_value(0))
	await _frames(20)
	_check(closed > 0.8 and mi.get_blend_shape_value(0) < 0.05, "blinks shut (%.2f) and open again" % closed)

	var plain := Node3D.new()
	add_child(plain)
	var box := MeshInstance3D.new()
	box.mesh = BoxMesh.new()
	plain.add_child(box)
	_check(FaceRig.attach(plain) == null and FaceRig.of(plain) == null, "no FaceRig on a body without a face")
	_end()


func _frames(n: int) -> void:
	for k in n:
		await get_tree().process_frame


func _end() -> void:
	print("RESULT face_rig_test %s fails=%d" % ["PASS" if _fails == 0 else "FAIL", _fails])
	get_tree().quit(1 if _fails > 0 else 0)
