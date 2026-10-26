class_name ExplorerBody
extends RiggedBody
## Simon's explorer (image-to-3d GLB) on the UAL1 clips: gait, crouch, upper-body pistol aim,
## shoot, reload, roll, death. The player feeds it state; it never reads input.

const EXPLORER := "res://assets/characters/explorer/explorer.glb"
## Tests can show another GLB on the same rig in the player's place (--explorer-glb).
static var glb_path := EXPLORER
## Ground speed (m/s) -> locomotion blend points, and the speed each clip naturally covers
## (Wreck Wreckers measured Walk 1.03, Jog 6.1, Sprint 9.4 on the same clips).
const GAIT := [[0.0, 1.0], [1.6, 1.03], [4.0, 6.1], [6.6, 9.4]]
const CROUCH_FWD_NATURAL := 1.4
## Gun rotation relative to the right hand bone, measured in Pistol_Aim_Neutral with the gun
## along the aim (test_driver --scenario=pose prints it as "RESULT grip").
const GRIP := Quaternion(0.246879, -0.645783, 0.311249, 0.652027)
## How far an aimed gun turns from the hand's grip toward the exact aim (0 = hand only).
const AIM_PULL := 0.5

## Point the gun along this (world) every frame; zero = let it hang with the hand.
var aim_dir := Vector3.ZERO
var gun_holder: Node3D
## The gun's foregrip in its own space (from WeaponData); zero = no left-hand reach.
var foregrip := Vector3.ZERO
var _armed := 1.0


## Null when an asset is missing; the caller keeps its stand-in then.
static func create() -> ExplorerBody:
	if not assets_present(glb_path):
		return null
	var b := ExplorerBody.new()
	b.name = "ExplorerBody"
	return b


func _ready() -> void:
	_setup_rig(glb_path)
	var hand := BoneAttachment3D.new()
	hand.bone_name = BONE_MAP["hand_r"]
	skeleton.add_child(hand)
	gun_holder = Node3D.new()
	hand.add_child(gun_holder)
	skeleton.skeleton_updated.connect(_orient_gun)
	# Connected after the retarget's own connection, so it runs on the retargeted pose.
	_src.skeleton_updated.connect(_reach_left)
	_src.skeleton_updated.connect(_ride_pose)


func _build_tree() -> void:
	var bt := AnimationNodeBlendTree.new()
	var loco := AnimationNodeBlendSpace1D.new()
	loco.add_blend_point(_anim("Idle"), 0.0, -1, "Idle")
	loco.add_blend_point(_anim("Walk"), 1.6, -1, "Walk")
	loco.add_blend_point(_anim("Jog_Fwd"), 4.0, -1, "Jog_Fwd")
	loco.add_blend_point(_anim("Sprint"), 6.6, -1, "Sprint")
	loco.min_space = 0.0
	loco.max_space = 7.0
	bt.add_node("loco", loco)
	var crouch := AnimationNodeBlendSpace1D.new()
	crouch.add_blend_point(_anim("Crouch_Idle"), 0.0, -1, "Crouch_Idle")
	crouch.add_blend_point(_anim("Crouch_Fwd"), 2.1, -1, "Crouch_Fwd")
	crouch.max_space = 3.0
	bt.add_node("crouch_bs", crouch)
	bt.add_node("crouch_mix", AnimationNodeBlend2.new())
	bt.add_node("speed_ts", AnimationNodeTimeScale.new())
	var aim := AnimationNodeBlendSpace1D.new()
	aim.add_blend_point(_anim("Pistol_Aim_Down"), -1.0, -1, "Pistol_Aim_Down")
	aim.add_blend_point(_anim("Pistol_Aim_Neutral"), 0.0, -1, "Pistol_Aim_Neutral")
	aim.add_blend_point(_anim("Pistol_Aim_Up"), 1.0, -1, "Pistol_Aim_Up")
	aim.min_space = -1.0
	bt.add_node("aim_bs", aim)
	# Armed (Simon: "the guns look bad when walking"): the arms hold the gun at low ready instead
	# of swinging with the walk, and blend to the aim pose.
	bt.add_node("ready_anim", _anim("Pistol_Idle"))
	bt.add_node("armed_mix", AnimationNodeBlend2.new())
	var aim_mix := AnimationNodeBlend2.new()
	_upper_only(aim_mix)
	bt.add_node("aim_mix", aim_mix)
	var shoot := AnimationNodeOneShot.new()
	shoot.fadein_time = 0.03
	shoot.fadeout_time = 0.15
	_upper_only(shoot)
	bt.add_node("shoot", shoot)
	bt.add_node("shoot_anim", _anim("Pistol_Shoot"))
	var reload := AnimationNodeOneShot.new()
	reload.fadein_time = 0.12
	reload.fadeout_time = 0.2
	_upper_only(reload)
	bt.add_node("reload", reload)
	bt.add_node("reload_anim", _anim("Pistol_Reload"))
	bt.add_node("reload_ts", AnimationNodeTimeScale.new())
	var roll := AnimationNodeOneShot.new()
	roll.fadein_time = 0.05
	roll.fadeout_time = 0.15
	bt.add_node("roll", roll)
	bt.add_node("roll_anim", _anim("Roll"))
	bt.add_node("roll_ts", AnimationNodeTimeScale.new())
	var vault := AnimationNodeOneShot.new()
	vault.fadein_time = 0.08
	vault.fadeout_time = 0.15
	bt.add_node("vault", vault)
	bt.add_node("vault_anim", _anim("ual2/ClimbUp_1m"))
	bt.add_node("vault_ts", AnimationNodeTimeScale.new())
	var state := AnimationNodeTransition.new()
	state.input_count = 4
	state.set_input_name(0, "alive")
	state.set_input_name(1, "dead")
	state.set_input_name(2, "drive")
	state.set_input_name(3, "ride")
	state.xfade_time = 0.15
	bt.add_node("state", state)
	bt.add_node("death_anim", _anim("Death01"))

	bt.connect_node("crouch_mix", 0, "loco")
	bt.connect_node("crouch_mix", 1, "crouch_bs")
	bt.connect_node("speed_ts", 0, "crouch_mix")
	bt.connect_node("aim_mix", 0, "speed_ts")
	bt.connect_node("armed_mix", 0, "ready_anim")
	bt.connect_node("armed_mix", 1, "aim_bs")
	bt.connect_node("aim_mix", 1, "armed_mix")
	bt.connect_node("shoot", 0, "aim_mix")
	bt.connect_node("shoot", 1, "shoot_anim")
	bt.connect_node("reload_ts", 0, "reload_anim")
	bt.connect_node("reload", 0, "shoot")
	bt.connect_node("reload", 1, "reload_ts")
	bt.connect_node("roll_ts", 0, "roll_anim")
	bt.connect_node("roll", 0, "reload")
	bt.connect_node("roll", 1, "roll_ts")
	bt.connect_node("vault_ts", 0, "vault_anim")
	bt.connect_node("vault", 0, "roll")
	bt.connect_node("vault", 1, "vault_ts")
	bt.connect_node("state", 0, "vault")
	bt.add_node("drive_anim", _anim("Driving"))
	bt.connect_node("state", 1, "death_anim")
	bt.connect_node("state", 2, "drive_anim")
	bt.add_node("ride_anim", _anim("Sitting_Idle"))
	bt.connect_node("state", 3, "ride_anim")
	bt.connect_node("output", 0, "state")
	_start_tree(bt)


## speed m/s along the ground; armed 0..1 (arms hold the gun); aim 0..1 (low ready -> aimed);
## pitch radians (up positive).
func update(speed: float, crouching: bool, aim: float, pitch: float, armed := 1.0) -> void:
	if _tree == null:
		return
	_tree.set("parameters/loco/blend_position", minf(speed, 7.0))
	_tree.set("parameters/crouch_bs/blend_position", speed)
	_tree.set("parameters/crouch_mix/blend_amount", 1.0 if crouching else 0.0)
	_tree.set("parameters/aim_bs/blend_position", clampf(pitch / 0.9, -1.0, 1.0))
	_tree.set("parameters/armed_mix/blend_amount", aim)
	_tree.set("parameters/aim_mix/blend_amount", maxf(armed, aim))
	_armed = maxf(armed, aim)
	# Play the gait near the speed it was made for so the feet don't skate.
	var natural := CROUCH_FWD_NATURAL if crouching else _natural(speed)
	_tree.set("parameters/speed_ts/scale", clampf(speed / natural, 0.6, 1.4) if speed > 0.2 else 1.0)


func _natural(speed: float) -> float:
	for i in range(1, GAIT.size()):
		if speed <= GAIT[i][0]:
			var t := inverse_lerp(GAIT[i - 1][0], GAIT[i][0], speed)
			return lerpf(GAIT[i - 1][1] if i > 1 else GAIT[1][1], GAIT[i][1], t)
	return GAIT[-1][1]


func shoot() -> void:
	_tree.set("parameters/shoot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


func reload(seconds: float) -> void:
	_tree.set("parameters/reload_ts/scale", clip_length("Pistol_Reload") / maxf(seconds, 0.1))
	_tree.set("parameters/reload/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


func cancel_reload() -> void:
	_tree.set("parameters/reload/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FADE_OUT)


func roll(seconds: float) -> void:
	_tree.set("parameters/roll_ts/scale", clip_length("Roll") / maxf(seconds, 0.1))
	_tree.set("parameters/roll/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


## The gun's rotation relative to the hand bone right now (test: measured in the aim pose).
func grip_now() -> Quaternion:
	var hb := (skeleton.global_basis * skeleton.get_bone_global_pose(skeleton.find_bone(BONE_MAP["hand_r"])).basis).orthonormalized()
	return (hb.inverse() * gun_holder.global_basis.orthonormalized()).get_rotation_quaternion()


func vault(seconds: float) -> void:
	_tree.set("parameters/vault_ts/scale", clip_length("ual2/ClimbUp_1m") / maxf(seconds, 0.1))
	_tree.set("parameters/vault/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


func die() -> void:
	_tree.set("parameters/state/transition_request", "dead")


func _orient_gun() -> void:
	if gun_holder:
		gun_holder.global_transform = _gun_transform()


## Where the gun is this frame (world): it turns with the right hand at a fixed grip (Simon: "the
## guns don't turn naturally in the hands" when forced along the aim), leaning part-way to the aim
## while aiming so the barrel lines up with the crosshair; the grip sits in the palm (between the
## wrist and the middle knuckle), not at the wrist joint.
func _gun_transform() -> Transform3D:
	var hb := (skeleton.global_basis * skeleton.get_bone_global_pose(skeleton.find_bone(BONE_MAP["hand_r"])).basis).orthonormalized()
	var held := Quaternion(hb) * GRIP
	# Simon: "they don't point along the arms" / "the pistols are even worse now": the grip was
	# measured in the aim pose, so in other poses (low ready) the wrist's turn sent the barrel off
	# sideways. The barrel now runs along the forearm (elbow -> hand); the grip keeps only its roll.
	var forearm := bone_point("hand_r") - bone_point("lowerarm_r")
	if forearm.length() > 0.01:
		var fwd := Basis(held) * Vector3.FORWARD
		held = Quaternion(fwd.normalized(), forearm.normalized()) * held
	if aim_dir.length() > 0.01:
		held = held.slerp(Quaternion(Basis.looking_at(aim_dir, Vector3.UP)), AIM_PULL)
	var at := bone_point("hand_r")
	if bone_map.has("middle_01_r"):
		at = (at + bone_point("middle_01_r")) * 0.5
	return Transform3D(Basis(held), at)


## After the retarget each frame: the left palm onto the gun's foregrip (two-bone reach, as
## Wreck Wreckers' PlayerBody does). foregrip = zero (the revolver): the clip's own two-hand hold.
func _reach_left() -> void:
	if foregrip == Vector3.ZERO or _armed < 0.5 or gun_holder == null:
		return
	var up := skeleton.find_bone(BONE_MAP["upperarm_l"])
	var lo := skeleton.find_bone(BONE_MAP["lowerarm_l"])
	var hd := skeleton.find_bone(BONE_MAP["hand_l"])
	var to_sk := skeleton.global_transform.affine_inverse()
	var grip_w := _gun_transform() * foregrip
	# Palm, not wrist, on the grip: back off by the wrist -> palm offset of this pose.
	var palm := Vector3.ZERO
	if bone_map.has("middle_01_l"):
		var mid := skeleton.find_bone(bone_map["middle_01_l"])
		palm = (skeleton.get_bone_global_pose(mid).origin - skeleton.get_bone_global_pose(hd).origin) * 0.5
	var s := skeleton.get_bone_global_pose(up).origin
	var e := skeleton.get_bone_global_pose(lo).origin
	var h := skeleton.get_bone_global_pose(hd).origin
	var line := (h - s).normalized()
	ArmIK.reach(skeleton, up, lo, hd, to_sk * grip_w - palm, (e - s) - line * (e - s).dot(line))


## Seated at a steering wheel (UAL1 Driving) while true; back to the normal body after.
func set_driving(on: bool) -> void:
	_tree.set("parameters/state/transition_request", "drive" if on else "alive")


## Riding: the horse whose ride_points() the body follows (null = not riding).
var _mount: Node3D


## Astride a horse (true, with the Horse) or off it (false; also leaves the driving pose). The
## upper body plays UAL1 Sitting_Idle; after the retarget each frame the pelvis goes onto the
## saddle, the feet into the stirrups and the hands to the reins (two-bone reaches, as _reach_left).
## Written by -f9.
func set_riding(on: bool, mount: Node3D = null) -> void:
	_mount = mount if on else null
	_tree.set("parameters/state/transition_request", "ride" if on else "alive")


func _ride_pose() -> void:
	if _mount == null or not is_instance_valid(_mount) or not _mount.has_method("ride_points"):
		return
	var p: Dictionary = _mount.ride_points()
	var to_sk := skeleton.global_transform.affine_inverse()
	var fwd: Vector3 = p.forward
	var up: Vector3 = p.up
	var right := fwd.cross(up).normalized()
	# Pelvis onto the saddle: the hip joint sits about 0.1 m above what you sit on.
	var pel := skeleton.find_bone(BONE_MAP["pelvis"])
	var goal := to_sk * ((p.saddle as Vector3) + up * 0.1)
	var parent := skeleton.get_bone_parent(pel)
	skeleton.set_bone_pose_position(pel, goal if parent < 0 else skeleton.get_bone_global_pose(parent).affine_inverse() * goal)
	for side: String in ["l", "r"]:
		var out := -right if side == "l" else right
		# Feet in the stirrups, knees forward and a little out round the barrel.
		ArmIK.reach(skeleton, skeleton.find_bone(BONE_MAP["thigh_" + side]), skeleton.find_bone(BONE_MAP["calf_" + side]),
			skeleton.find_bone(BONE_MAP["foot_" + side]), to_sk * (p["stirrup_" + side] as Vector3),
			to_sk.basis * (fwd + out * 0.35))
		# Hands on the reins, elbows down and out.
		var hd := skeleton.find_bone(BONE_MAP["hand_" + side])
		var palm := Vector3.ZERO
		if bone_map.has("middle_01_" + side):
			palm = (skeleton.get_bone_global_pose(skeleton.find_bone(bone_map["middle_01_" + side])).origin - skeleton.get_bone_global_pose(hd).origin) * 0.5
		ArmIK.reach(skeleton, skeleton.find_bone(BONE_MAP["upperarm_" + side]), skeleton.find_bone(BONE_MAP["lowerarm_" + side]),
			hd, to_sk * (p["reins_" + side] as Vector3) - palm, to_sk.basis * (-up + out * 0.6 - fwd * 0.3))
