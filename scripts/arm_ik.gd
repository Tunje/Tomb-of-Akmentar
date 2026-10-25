class_name ArmIK
extends RefCounted
## Two-bone arm reach, ported from Wreck Wreckers (armour/armour_fit.gd, ArmourFit.reach).
## Works in skeleton space on the current pose; call it after the pose is set for the frame.

## Never quite straight (a straight arm has no bend side to keep).
const MAX_REACH := 0.999


## Turn upper + lower so the hand bone's origin lands on `goal` (skeleton space). The elbow bends
## toward `bend_hint` (else where it sits now); out of reach, the arm points at the goal. The hand
## keeps its global turn.
static func reach(sk: Skeleton3D, upper: int, lower: int, hand: int, goal: Vector3, bend_hint := Vector3.ZERO) -> void:
	var gu := sk.get_bone_global_pose(upper)
	var gl := sk.get_bone_global_pose(lower)
	var gh := sk.get_bone_global_pose(hand)
	var s := gu.origin
	var e := gl.origin
	var h := gh.origin
	var a := (e - s).length()
	var b := (h - e).length()
	var to_goal := goal - s
	if a < 1e-5 or b < 1e-5 or to_goal.length() < 1e-5:
		return
	var dir := to_goal.normalized()
	var d := clampf(to_goal.length(), absf(a - b) + 1e-4, (a + b) * MAX_REACH)
	var bend := bend_hint - dir * bend_hint.dot(dir)
	if bend.length() < 1e-4:
		bend = (e - s) - dir * (e - s).dot(dir)
	if bend.length() < 1e-5:
		bend = dir.cross(Vector3.RIGHT if absf(dir.x) < 0.9 else Vector3.UP)
	bend = bend.normalized()
	var cos_s := clampf((a * a + d * d - b * b) / (2.0 * a * d), -1.0, 1.0)
	var elbow := s + dir * (a * cos_s) + bend * (a * sqrt(1.0 - cos_s * cos_s))
	var hand_at := s + dir * d
	var r1 := _arc((e - s).normalized(), (elbow - s).normalized())
	var gl_turned := r1 * gl.basis
	var r2 := _arc((r1 * (h - e)).normalized(), (hand_at - elbow).normalized())
	_set_global(sk, upper, r1 * gu.basis)
	_set_global(sk, lower, r2 * gl_turned)
	_set_global(sk, hand, gh.basis)


static func _set_global(sk: Skeleton3D, bone: int, g: Basis) -> void:
	var p := sk.get_bone_parent(bone)
	var parent_g: Basis = sk.get_bone_global_pose(p).basis if p >= 0 else Basis.IDENTITY
	sk.set_bone_pose_rotation(bone, (parent_g.orthonormalized().inverse() * g.orthonormalized()).get_rotation_quaternion())


static func _arc(a: Vector3, b: Vector3) -> Basis:
	var axis := a.cross(b)
	var d := clampf(a.dot(b), -1.0, 1.0)
	if axis.length() < 1e-6:
		return Basis.IDENTITY if d > 0.0 else Basis(Vector3.UP if absf(a.y) < 0.9 else Vector3.RIGHT, PI)
	return Basis(axis.normalized(), acos(d))
