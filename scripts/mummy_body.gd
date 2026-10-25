class_name MummyBody
extends RiggedBody
## An image-to-3d mummy on the UAL2 zombie clips (walk, idle, scratch), UAL1 hit/death and
## UAL2 knockback. Hitboxes ride the bones; a severed limb collapses by scaling its bone to 0.

const TOMB_GUARD := "res://assets/characters/mummies/tomb_guard.glb"
const WALK_NATURAL := 0.9  # m/s the zombie walk covers at 1x (estimate)

## Tests can point mummies at another GLB on the same rig.
static var glb_path := TOMB_GUARD

## part -> Array of StaticBody3D hitboxes; Mummy reads these.
var hitboxes := {}
var _overlay: StandardMaterial3D


static func create() -> MummyBody:
	if not assets_present(glb_path):
		return null
	var b := MummyBody.new()
	b.name = "MummyBody"
	return b


func _ready() -> void:
	_setup_rig(glb_path)
	_overlay = StandardMaterial3D.new()
	_overlay.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_overlay.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_overlay.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_overlay.albedo_color = Color(1, 0.9, 0.8, 0.0)
	for mi in body.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_overlay = _overlay


func _build_tree() -> void:
	var bt := AnimationNodeBlendTree.new()
	var loco := AnimationNodeBlendSpace1D.new()
	loco.add_blend_point(_anim("ual2/Zombie_Idle"), 0.0, -1, "Zombie_Idle")
	loco.add_blend_point(_anim("ual2/Zombie_Walk_Fwd"), 1.0, -1, "Zombie_Walk_Fwd")
	loco.max_space = 2.0
	bt.add_node("loco", loco)
	bt.add_node("speed_ts", AnimationNodeTimeScale.new())
	var flinch := AnimationNodeOneShot.new()
	flinch.fadein_time = 0.04
	flinch.fadeout_time = 0.2
	_upper_only(flinch)
	bt.add_node("flinch", flinch)
	bt.add_node("flinch_anim", _anim("Hit_Chest"))
	var attack := AnimationNodeOneShot.new()
	attack.fadein_time = 0.1
	attack.fadeout_time = 0.2
	_upper_only(attack)
	bt.add_node("attack", attack)
	bt.add_node("attack_anim", _anim("ual2/Zombie_Scratch"))
	bt.add_node("attack_ts", AnimationNodeTimeScale.new())
	var stagger := AnimationNodeOneShot.new()
	stagger.fadein_time = 0.05
	stagger.fadeout_time = 0.25
	bt.add_node("stagger", stagger)
	bt.add_node("stagger_anim", _anim("ual2/Hit_Knockback"))
	bt.add_node("stagger_ts", AnimationNodeTimeScale.new())
	var state := AnimationNodeTransition.new()
	state.input_count = 2
	state.set_input_name(0, "alive")
	state.set_input_name(1, "dead")
	state.xfade_time = 0.1
	bt.add_node("state", state)
	bt.add_node("death_anim", _anim("Death01"))

	bt.connect_node("speed_ts", 0, "loco")
	bt.connect_node("flinch", 0, "speed_ts")
	bt.connect_node("flinch", 1, "flinch_anim")
	bt.connect_node("attack_ts", 0, "attack_anim")
	bt.connect_node("attack", 0, "flinch")
	bt.connect_node("attack", 1, "attack_ts")
	bt.connect_node("stagger_ts", 0, "stagger_anim")
	bt.connect_node("stagger", 0, "attack")
	bt.connect_node("stagger", 1, "stagger_ts")
	bt.connect_node("state", 0, "stagger")
	bt.connect_node("state", 1, "death_anim")
	bt.connect_node("output", 0, "state")
	_start_tree(bt)


## Capsule hitboxes along the bones, in the same parts the stand-in had.
func build_hitboxes(owner_mummy: Node) -> void:
	var k := body.scale.x
	_capsule(owner_mummy, "torso", "spine_01", "neck_01", 0.24 / k, 1.0)
	_capsule(owner_mummy, "head", "neck_01", "Head", 0.13 / k, 2.2)
	for s in ["l", "r"]:
		_capsule(owner_mummy, "arm_" + s, "upperarm_" + s, "lowerarm_" + s, 0.08 / k, 1.0)
		_capsule(owner_mummy, "arm_" + s, "lowerarm_" + s, "hand_" + s, 0.07 / k, 1.25)
		_capsule(owner_mummy, "leg_" + s, "thigh_" + s, "calf_" + s, 0.11 / k, 1.0)
		_capsule(owner_mummy, "leg_" + s, "calf_" + s, "foot_" + s, 0.09 / k, 1.0)


## A capsule from bone `a` toward bone `b` (stretched by `reach`), riding bone `a`.
func _capsule(owner_mummy: Node, part: String, a: String, b: String, radius: float, reach: float) -> void:
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
	box.set_meta("mummy", owner_mummy)
	box.set_meta("part", part)
	var cs := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = radius
	shape.height = maxf(off.length() + radius * 2.0, radius * 2.0)
	cs.shape = shape
	box.add_child(cs)
	att.add_child(box)
	# Capsules stand along +Y: turn Y onto the bone and centre it.
	box.transform = Transform3D(_basis_y_to(off.normalized()), off * 0.5)
	if not hitboxes.has(part):
		hitboxes[part] = []
	hitboxes[part].append(box)


static func _basis_y_to(dir: Vector3) -> Basis:
	var y := dir if dir.length() > 0.001 else Vector3.UP
	var x := y.cross(Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	return Basis(x, y, x.cross(y).normalized())


## speed in m/s along the ground.
func update(speed: float) -> void:
	if _tree == null:
		return
	_tree.set("parameters/loco/blend_position", clampf(speed / WALK_NATURAL, 0.0, 1.0))
	_tree.set("parameters/speed_ts/scale", clampf(speed / WALK_NATURAL, 0.7, 2.0) if speed > 0.1 else 1.0)


func flash(amount: float) -> void:
	_overlay.albedo_color.a = amount


func flinch() -> void:
	_tree.set("parameters/flinch/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


## The scratch spread over the windup + recovery, so the swipe lands at the windup's end.
func attack(seconds: float) -> void:
	_tree.set("parameters/attack_ts/scale", clip_length("ual2/Zombie_Scratch") / maxf(seconds, 0.1))
	_tree.set("parameters/attack/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


func cancel_attack() -> void:
	_tree.set("parameters/attack/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FADE_OUT)


func stagger(seconds: float) -> void:
	cancel_attack()
	_tree.set("parameters/stagger_ts/scale", clip_length("ual2/Hit_Knockback") / maxf(seconds, 0.1))
	_tree.set("parameters/stagger/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


func die() -> void:
	_tree.set("parameters/state/transition_request", "dead")


## The limb from this UAL bone down collapses into its joint (the retarget only sets rotations,
## so the scale stays).
func collapse(ual: String) -> void:
	var i := skeleton.find_bone(BONE_MAP[ual])
	if i >= 0:
		skeleton.set_bone_pose_scale(i, Vector3.ONE * 0.001)
