class_name ExplorerBody
extends RiggedBody
## Simon's explorer (image-to-3d GLB) on the UAL1 clips: gait, crouch, upper-body pistol aim,
## shoot, reload, roll, death. The player feeds it state; it never reads input.

const EXPLORER := "res://assets/characters/explorer/explorer.glb"
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


## Null when an asset is missing; the caller keeps its stand-in then.
static func create() -> ExplorerBody:
	if not assets_present(EXPLORER):
		return null
	var b := ExplorerBody.new()
	b.name = "ExplorerBody"
	return b


func _ready() -> void:
	_setup_rig(EXPLORER)
	var hand := BoneAttachment3D.new()
	hand.bone_name = BONE_MAP["hand_r"]
	skeleton.add_child(hand)
	gun_holder = Node3D.new()
	hand.add_child(gun_holder)
	skeleton.skeleton_updated.connect(_orient_gun)


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
	state.input_count = 2
	state.set_input_name(0, "alive")
	state.set_input_name(1, "dead")
	state.xfade_time = 0.15
	bt.add_node("state", state)
	bt.add_node("death_anim", _anim("Death01"))

	bt.connect_node("crouch_mix", 0, "loco")
	bt.connect_node("crouch_mix", 1, "crouch_bs")
	bt.connect_node("speed_ts", 0, "crouch_mix")
	bt.connect_node("aim_mix", 0, "speed_ts")
	bt.connect_node("aim_mix", 1, "aim_bs")
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
	bt.connect_node("state", 1, "death_anim")
	bt.connect_node("output", 0, "state")
	_start_tree(bt)


## speed m/s along the ground; aim 0..1; pitch radians (up positive).
func update(speed: float, crouching: bool, aim: float, pitch: float) -> void:
	if _tree == null:
		return
	_tree.set("parameters/loco/blend_position", minf(speed, 7.0))
	_tree.set("parameters/crouch_bs/blend_position", speed)
	_tree.set("parameters/crouch_mix/blend_amount", 1.0 if crouching else 0.0)
	_tree.set("parameters/aim_bs/blend_position", clampf(pitch / 0.9, -1.0, 1.0))
	_tree.set("parameters/aim_mix/blend_amount", aim)
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
	if gun_holder == null:
		return
	# The gun turns with the hand at a fixed grip (Simon: "the guns don't turn naturally in the
	# hands" when they were forced along the aim). While aiming it leans part-way to the aim so
	# the barrel still lines up with the crosshair.
	var hb := (skeleton.global_basis * skeleton.get_bone_global_pose(skeleton.find_bone(BONE_MAP["hand_r"])).basis).orthonormalized()
	var held := Quaternion(hb) * GRIP
	if aim_dir.length() > 0.01:
		held = held.slerp(Quaternion(Basis.looking_at(aim_dir, Vector3.UP)), AIM_PULL)
	gun_holder.global_basis = Basis(held)
	# The grip in the palm (between the wrist and the middle knuckle), not at the wrist joint.
	if bone_map.has("middle_01_r"):
		gun_holder.global_position = (bone_point("hand_r") + bone_point("middle_01_r")) * 0.5
