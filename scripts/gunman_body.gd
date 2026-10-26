class_name GunmanBody
extends ExplorerBody
## A gunman (bandits / guardian order, rival expedition gunmen) on the UAL1 pistol clips. Reuses
## ExplorerBody's gait, aim, shoot, reload, death and gun-in-hand code; adds flinch, stagger,
## a hit flash and bone hitboxes (same parts as the mummies). Image-to-3d's four bandits, on the
## same Armour 01 rig (each has holstered revolvers modelled on the hip; the gun in hand is extra).

const BANDITS := [
	"res://assets/characters/bandits/bandit_raider.glb",
	"res://assets/characters/bandits/bandit_brute.glb",
	"res://assets/characters/bandits/bandit_gunhand.glb",
	"res://assets/characters/bandits/bandit_scout.glb",
]

## The arms of the surrender pose (no hands-up clip in UAL: the pistol aim held high, empty-handed).
const HANDS_UP := "Pistol_Aim_Up"

## Tests can point gunmen at another GLB on the same rig ("" = a random bandit).
static var default_glb := ""

var _glb: String = BANDITS[0]
## part -> Array of StaticBody3D hitboxes; Gunman reads these.
var hitboxes := {}
var _overlay: StandardMaterial3D


## Null when an asset is missing; the caller keeps its stand-in then.
static func create(glb := "") -> GunmanBody:
	var path := glb if glb != "" else default_glb
	if path == "":
		path = BANDITS.pick_random()
	if not assets_present(path):
		return null
	var b := GunmanBody.new()
	b._glb = path
	b.name = "GunmanBody"
	return b


func _ready() -> void:
	_setup_rig(_glb)
	var hand := BoneAttachment3D.new()
	hand.bone_name = BONE_MAP["hand_r"]
	skeleton.add_child(hand)
	gun_holder = Node3D.new()
	hand.add_child(gun_holder)
	skeleton.skeleton_updated.connect(_orient_gun)
	_src.skeleton_updated.connect(_reach_left)
	_overlay = StandardMaterial3D.new()
	_overlay.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_overlay.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_overlay.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_overlay.albedo_color = Color(1, 0.9, 0.8, 0.0)
	for mi in body.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_overlay = _overlay


## ExplorerBody's tree without roll / vault, plus flinch and stagger. The parameter names match
## ExplorerBody so its update / shoot / reload / die drive this tree too.
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
	var flinch := AnimationNodeOneShot.new()
	flinch.fadein_time = 0.04
	flinch.fadeout_time = 0.2
	_upper_only(flinch)
	bt.add_node("flinch", flinch)
	bt.add_node("flinch_anim", _anim("Hit_Chest"))
	var stagger := AnimationNodeOneShot.new()
	stagger.fadein_time = 0.05
	stagger.fadeout_time = 0.25
	bt.add_node("stagger", stagger)
	bt.add_node("stagger_anim", _anim("Hit_Chest"))
	bt.add_node("stagger_ts", AnimationNodeTimeScale.new())
	var state := AnimationNodeTransition.new()
	state.input_count = 2
	state.set_input_name(0, "alive")
	state.set_input_name(1, "dead")
	state.xfade_time = 0.15
	bt.add_node("state", state)
	# Surrender: kneeling (crouch legs), hands raised (the pistol aim-up pose, arms only).
	var hands := AnimationNodeBlend2.new()
	_upper_only(hands)
	bt.add_node("hands_up", hands)
	bt.add_node("kneel_anim", _anim("Crouch_Idle"))
	bt.add_node("hands_anim", _anim(HANDS_UP))
	bt.add_node("give_up", AnimationNodeBlend2.new())
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
	bt.connect_node("flinch", 0, "reload")
	bt.connect_node("flinch", 1, "flinch_anim")
	bt.connect_node("stagger_ts", 0, "stagger_anim")
	bt.connect_node("stagger", 0, "flinch")
	bt.connect_node("stagger", 1, "stagger_ts")
	bt.connect_node("hands_up", 0, "kneel_anim")
	bt.connect_node("hands_up", 1, "hands_anim")
	bt.connect_node("give_up", 0, "stagger")
	bt.connect_node("give_up", 1, "hands_up")
	bt.connect_node("state", 0, "give_up")
	bt.connect_node("state", 1, "death_anim")
	bt.connect_node("output", 0, "state")
	_start_tree(bt)
	_tree.set("parameters/hands_up/blend_amount", 1.0)


## Capsule hitboxes along the bones, in the mummies' parts (player bullets read meta "mummy").
func build_hitboxes(owner_node: Node) -> void:
	var k := body.scale.x
	_capsule(owner_node, "torso", "spine_01", "neck_01", 0.22 / k, 1.0)
	_capsule(owner_node, "head", "neck_01", "Head", 0.12 / k, 2.2)
	for s in ["l", "r"]:
		_capsule(owner_node, "arm_" + s, "upperarm_" + s, "lowerarm_" + s, 0.07 / k, 1.0)
		_capsule(owner_node, "arm_" + s, "lowerarm_" + s, "hand_" + s, 0.06 / k, 1.25)
		_capsule(owner_node, "leg_" + s, "thigh_" + s, "calf_" + s, 0.1 / k, 1.0)
		_capsule(owner_node, "leg_" + s, "calf_" + s, "foot_" + s, 0.08 / k, 1.0)


## A capsule from bone `a` toward bone `b` (stretched by `reach`), riding bone `a`.
func _capsule(owner_node: Node, part: String, a: String, b: String, radius: float, reach: float) -> void:
	var ia := skeleton.find_bone(BONE_MAP[a])
	var ib := skeleton.find_bone(BONE_MAP[b])
	var ra := skeleton.get_bone_global_rest(ia)
	var off := ra.affine_inverse() * skeleton.get_bone_global_rest(ib).origin * reach
	var att := BoneAttachment3D.new()
	att.bone_name = BONE_MAP[a]
	skeleton.add_child(att)
	var box := StaticBody3D.new()
	box.collision_layer = 8
	box.collision_mask = 0
	box.set_meta("mummy", owner_node)
	box.set_meta("part", part)
	var cs := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = radius
	shape.height = maxf(off.length() + radius * 2.0, radius * 2.0)
	cs.shape = shape
	box.add_child(cs)
	att.add_child(box)
	box.transform = Transform3D(MummyBody._basis_y_to(off.normalized()), off * 0.5)
	if not hitboxes.has(part):
		hitboxes[part] = []
	hitboxes[part].append(box)


func flash(amount: float) -> void:
	_overlay.albedo_color.a = amount


func flinch() -> void:
	_tree.set("parameters/flinch/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


func stagger(seconds: float) -> void:
	cancel_reload()
	_tree.set("parameters/stagger_ts/scale", clip_length("Hit_Chest") / maxf(seconds, 0.1))
	_tree.set("parameters/stagger/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


## Kneel with the hands up (on = surrendered).
func surrender(on := true) -> void:
	cancel_reload()
	_tree.set("parameters/give_up/blend_amount", 1.0 if on else 0.0)


## Down on one knee, hands free (a stumble in the escape): the surrender kneel without the hands up.
func kneel(on := true) -> void:
	cancel_reload()
	_tree.set("parameters/hands_up/blend_amount", 0.0 if on else 1.0)
	_tree.set("parameters/give_up/blend_amount", 1.0 if on else 0.0)
