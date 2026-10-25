class_name ExplorerBody
extends Node3D
## Simon's explorer (image-to-3d GLB, Armour 01 52-bone rig) animated with the Quaternius UAL1
## clips, the way Wreck Wreckers does it: a hidden UAL body plays the clips through an
## AnimationTree, and ModelRetarget copies its pose onto the explorer every frame.
## The player feeds it state (update / shoot / reload / roll / die); it never reads input.

const EXPLORER := "res://assets/characters/explorer/explorer.glb"
const DRIVER := "res://assets/characters/driver/Superhero_Male_FullBody.gltf"
const UAL1 := "res://assets/characters/animations/UAL1_Standard.glb"
## UAL bone -> explorer bone (Armour 01 rig, same map as Wreck Wreckers' armour_01_body.tres).
const BONE_MAP := {
	"pelvis": "bone_0", "spine_01": "bone_1", "spine_02": "bone_2", "spine_03": "bone_3",
	"neck_01": "bone_4", "Head": "bone_5",
	"clavicle_l": "bone_6", "upperarm_l": "bone_7", "lowerarm_l": "bone_8", "hand_l": "bone_9",
	"clavicle_r": "bone_25", "upperarm_r": "bone_26", "lowerarm_r": "bone_27", "hand_r": "bone_28",
	"thigh_l": "bone_44", "calf_l": "bone_45", "foot_l": "bone_46", "ball_l": "bone_47",
	"thigh_r": "bone_48", "calf_r": "bone_49", "foot_r": "bone_50", "ball_r": "bone_51",
}
const LOOPED := ["Idle", "Walk", "Jog_Fwd", "Sprint", "Crouch_Idle", "Crouch_Fwd",
	"Pistol_Aim_Down", "Pistol_Aim_Neutral", "Pistol_Aim_Up"]
## Ground speed (m/s) -> locomotion blend points, and the speed each clip naturally covers
## (Wreck Wreckers measured Walk 1.03, Jog 6.1, Sprint 9.4 on the same clips).
const GAIT := [[0.0, 1.0], [1.6, 1.03], [4.0, 6.1], [6.6, 9.4]]
const CROUCH_FWD_NATURAL := 1.4

static var _lib: AnimationLibrary

var driver: Node3D
var body: Node3D
var skeleton: Skeleton3D
## Point the gun along this (world) every frame; zero = let it hang with the hand.
var aim_dir := Vector3.ZERO
var gun_holder: Node3D

var _tree: AnimationTree
var _src: Skeleton3D
var _retarget: ModelRetarget


## Null when an asset is missing; the caller keeps its stand-in then.
static func create() -> ExplorerBody:
	for p in [EXPLORER, DRIVER, UAL1]:
		if not ResourceLoader.exists(p):
			push_warning("ExplorerBody: missing %s, using the stand-in" % p)
			return null
	var b := ExplorerBody.new()
	b.name = "ExplorerBody"
	return b


func _ready() -> void:
	driver = (load(DRIVER) as PackedScene).instantiate()
	driver.rotation.y = PI  # glTF faces +Z, ours is -Z
	add_child(driver)
	_src = driver.find_children("*", "Skeleton3D", true, false)[0]
	for mi in driver.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).visible = false  # only its skeleton is used

	body = (load(EXPLORER) as PackedScene).instantiate()
	body.rotation.y = PI
	add_child(body)
	skeleton = body.find_children("*", "Skeleton3D", true, false)[0]
	_fit_size()

	_build_tree()
	_retarget = ModelRetarget.new()
	add_child(_retarget)
	_retarget.setup(_src, skeleton, BONE_MAP)

	var hand := BoneAttachment3D.new()
	hand.bone_name = BONE_MAP["hand_r"]
	skeleton.add_child(hand)
	gun_holder = Node3D.new()
	hand.add_child(gun_holder)
	skeleton.skeleton_updated.connect(_orient_gun)


## Head as high as the driver's (~1.8 m), feet on the ground: the GLB is 1.0 unit tall.
func _fit_size() -> void:
	var s_head := (_src.global_transform * _src.get_bone_global_rest(_src.find_bone("Head")).origin).y
	var s_foot := (_src.global_transform * _src.get_bone_global_rest(_src.find_bone("foot_l")).origin).y
	var t_head := (skeleton.global_transform * skeleton.get_bone_global_rest(skeleton.find_bone(BONE_MAP["Head"])).origin).y
	var t_foot := (skeleton.global_transform * skeleton.get_bone_global_rest(skeleton.find_bone(BONE_MAP["foot_l"])).origin).y
	var k := (s_head - s_foot) / maxf(0.01, t_head - t_foot)
	body.scale = Vector3.ONE * k
	body.position.y += s_foot - global_position.y - (t_foot - global_position.y) * k


static func _library() -> AnimationLibrary:
	if _lib == null:
		var ual: Node = (load(UAL1) as PackedScene).instantiate()
		var ap: AnimationPlayer = ual.find_children("*", "AnimationPlayer", true, false)[0]
		_lib = ap.get_animation_library("").duplicate(true)
		ual.free()
		for n in _lib.get_animation_list():
			_lib.get_animation(n).loop_mode = Animation.LOOP_LINEAR if String(n) in LOOPED else Animation.LOOP_NONE
	return _lib


func _build_tree() -> void:
	var ap := AnimationPlayer.new()
	ap.name = "AnimationPlayer"
	driver.add_child(ap)
	ap.add_animation_library("", _library())

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
	bt.connect_node("state", 0, "roll")
	bt.connect_node("state", 1, "death_anim")
	bt.connect_node("output", 0, "state")

	_tree = AnimationTree.new()
	_tree.name = "AnimationTree"
	driver.add_child(_tree)
	_tree.anim_player = _tree.get_path_to(ap)
	_tree.root_node = _tree.get_path_to(driver)
	_tree.tree_root = bt
	_tree.active = true


func _anim(clip: String) -> AnimationNodeAnimation:
	var a := AnimationNodeAnimation.new()
	a.animation = clip
	return a


## Filter a node to the spine_02 branch (chest, neck, head, arms, fingers): legs keep walking.
func _upper_only(node: AnimationNode) -> void:
	node.filter_enabled = true
	var path := String(driver.get_path_to(_src))
	var top := _src.find_bone("spine_02")
	for i in _src.get_bone_count():
		var b := i
		while b >= 0 and b != top:
			b = _src.get_bone_parent(b)
		if b == top:
			node.set_filter_path(NodePath("%s:%s" % [path, _src.get_bone_name(i)]), true)


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
	var clip := _library().get_animation("Pistol_Reload").length
	_tree.set("parameters/reload_ts/scale", clip / maxf(seconds, 0.1))
	_tree.set("parameters/reload/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


func cancel_reload() -> void:
	_tree.set("parameters/reload/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FADE_OUT)


func roll(seconds: float) -> void:
	var clip := _library().get_animation("Roll").length
	_tree.set("parameters/roll_ts/scale", clip / maxf(seconds, 0.1))
	_tree.set("parameters/roll/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


## Test only: "rest" = the GLB's own rest pose (no retarget), otherwise hold one UAL clip.
func debug_pose(what: String) -> void:
	if what == "rest":
		_retarget.set_block_signals(true)
		if _src.skeleton_updated.is_connected(_retarget.apply):
			_src.skeleton_updated.disconnect(_retarget.apply)
		skeleton.reset_bone_poses()
		return
	if not _src.skeleton_updated.is_connected(_retarget.apply):
		_src.skeleton_updated.connect(_retarget.apply)
	_tree.active = false
	var ap: AnimationPlayer = driver.get_node("AnimationPlayer")
	ap.play(what)
	ap.seek(0.3, true)
	ap.pause()


## Test only: how far each explorer bone has turned from its rest (degrees, world), mapped or not.
func debug_report() -> String:
	var out := PackedStringArray()
	for i in skeleton.get_bone_count():
		var rest := skeleton.get_bone_global_rest(i).basis.orthonormalized()
		var pose := skeleton.get_bone_global_pose(i).basis.orthonormalized()
		var deg := rad_to_deg((pose * rest.inverse()).get_rotation_quaternion().get_angle())
		var ual := ""
		for k in BONE_MAP:
			if BONE_MAP[k] == skeleton.get_bone_name(i):
				ual = k
		out.append("%s(%s,p=%d)=%.0f" % [skeleton.get_bone_name(i), ual, skeleton.get_bone_parent(i), deg])
	return " ".join(out)


func die() -> void:
	_tree.set("parameters/state/transition_request", "dead")


func _orient_gun() -> void:
	if gun_holder == null:
		return
	var dir := aim_dir
	if dir.length() < 0.01:
		# Lowered: along the body, tipped down.
		dir = (-global_basis.z + Vector3.DOWN * 0.7).normalized()
	gun_holder.global_basis = Basis.looking_at(dir, Vector3.UP)
