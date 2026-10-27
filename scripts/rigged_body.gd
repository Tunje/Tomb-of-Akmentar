class_name RiggedBody
extends Node3D
## Shared base for image-to-3d characters on the Armour 01 52-bone rig (explorer, mummies),
## animated the way Wreck Wreckers does it: a hidden Quaternius body plays the UAL clips
## (UAL1 in library "", UAL2 in library "ual2") and ModelRetarget copies its pose onto ours.
## Subclasses build their AnimationTree on `anim_player` in _build_tree().

const DRIVER := "res://assets/characters/driver/Superhero_Male_FullBody.gltf"
const UAL := {"": "res://assets/characters/animations/UAL1_Standard.glb",
	"ual2": "res://assets/characters/animations/UAL2_Standard.glb"}
## UAL bone -> our bone (Armour 01 rig, same map as Wreck Wreckers' armour_01_body.tres).
const BONE_MAP := {
	"pelvis": "bone_0", "spine_01": "bone_1", "spine_02": "bone_2", "spine_03": "bone_3",
	"neck_01": "bone_4", "Head": "bone_5",
	"clavicle_l": "bone_6", "upperarm_l": "bone_7", "lowerarm_l": "bone_8", "hand_l": "bone_9",
	"clavicle_r": "bone_25", "upperarm_r": "bone_26", "lowerarm_r": "bone_27", "hand_r": "bone_28",
	"thigh_l": "bone_44", "calf_l": "bone_45", "foot_l": "bone_46", "ball_l": "bone_47",
	"thigh_r": "bone_48", "calf_r": "bone_49", "foot_r": "bone_50", "ball_r": "bone_51",
}
## Bones that copy the clip's motion without being re-aimed like UAL's at rest (see ModelRetarget).
const UNALIGNED := ["clavicle_l", "clavicle_r"]
## Clips that loop; everything else plays once.
const LOOPED := ["Idle", "Walk", "Jog_Fwd", "Sprint", "Crouch_Idle", "Crouch_Fwd",
	"Pistol_Aim_Down", "Pistol_Aim_Neutral", "Pistol_Aim_Up", "Zombie_Idle", "Zombie_Walk_Fwd", "Driving",
	"Sitting_Idle"]

static var _libs := {}

var driver: Node3D
var body: Node3D
var skeleton: Skeleton3D
var anim_player: AnimationPlayer
## BONE_MAP plus the fingers found on this body (see with_fingers).
var bone_map := {}
var _tree: AnimationTree
var _src: Skeleton3D
var _retarget: ModelRetarget


static func assets_present(glb: String) -> bool:
	for p in [glb, DRIVER] + UAL.values():
		if not ResourceLoader.exists(p):
			push_warning("RiggedBody: missing %s, using the stand-in" % p)
			return false
	return true


## Builds driver + body + retarget; call from the subclass's _ready().
func _setup_rig(glb: String) -> void:
	driver = (load(DRIVER) as PackedScene).instantiate()
	driver.rotation.y = PI  # glTF faces +Z, ours is -Z
	add_child(driver)
	_src = driver.find_children("*", "Skeleton3D", true, false)[0]
	for mi in driver.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).visible = false  # only its skeleton is used

	body = (load(glb) as PackedScene).instantiate()
	body.rotation.y = PI
	add_child(body)
	skeleton = body.find_children("*", "Skeleton3D", true, false)[0]
	_fit_size()

	anim_player = AnimationPlayer.new()
	anim_player.name = "AnimationPlayer"
	driver.add_child(anim_player)
	for lib_name in UAL:
		anim_player.add_animation_library(lib_name, library(lib_name))
	_build_tree()
	bone_map = with_fingers(BONE_MAP, skeleton, _src)
	_retarget = ModelRetarget.new()
	add_child(_retarget)
	_retarget.setup(_src, skeleton, bone_map, UNALIGNED)


func _build_tree() -> void:
	pass


## `map` plus its fingers -> UAL's (thumb, index, middle, ring, pinky; 3 joints each), found from
## each hand's children: the thumb is the one nearest the wrist, the others ordered across the
## knuckles from the thumb's side. Unmapped, the fingers stayed spread open around the gun.
## Ported from Wreck Wreckers (game/armour/player_body.gd, with_fingers).
const FINGERS := ["thumb", "index", "middle", "ring", "pinky"]


static func with_fingers(map: Dictionary, sk: Skeleton3D, ours: Skeleton3D) -> Dictionary:
	var out := map.duplicate()
	for side: String in ["l", "r"]:
		var hand := sk.find_bone(String(map.get("hand_" + side, "")))
		if hand < 0:
			continue
		var kids := Array(sk.get_bone_children(hand))
		if kids.size() != 5:
			continue
		kids.sort_custom(func(a: int, b: int) -> bool: return sk.get_bone_rest(a).origin.length() < sk.get_bone_rest(b).origin.length())
		var thumb: int = kids.pop_front()
		var mid := Vector3.ZERO
		for k: int in kids:
			mid += sk.get_bone_rest(k).origin / 4.0
		var along := mid.normalized()
		var toward := sk.get_bone_rest(thumb).origin - mid
		toward = (toward - along * toward.dot(along)).normalized()
		kids.sort_custom(func(a: int, b: int) -> bool: return sk.get_bone_rest(a).origin.dot(toward) > sk.get_bone_rest(b).origin.dot(toward))
		kids.push_front(thumb)
		for f in 5:
			var bone: int = kids[f]
			for j in 3:
				var ual := "%s_0%d_%s" % [FINGERS[f], j + 1, side]
				if ours.find_bone(ual) >= 0:
					out[ual] = sk.get_bone_name(bone)
				var next := sk.get_bone_children(bone)
				if next.is_empty():
					break
				bone = next[0]
	return out


## Head as high as the driver's (~1.8 m), feet on the ground: the GLBs are 1.0 unit tall.
func _fit_size() -> void:
	var s_head := (_src.global_transform * _src.get_bone_global_rest(_src.find_bone("Head")).origin).y
	var s_foot := (_src.global_transform * _src.get_bone_global_rest(_src.find_bone("foot_l")).origin).y
	var t_head := (skeleton.global_transform * skeleton.get_bone_global_rest(skeleton.find_bone(BONE_MAP["Head"])).origin).y
	var t_foot := (skeleton.global_transform * skeleton.get_bone_global_rest(skeleton.find_bone(BONE_MAP["foot_l"])).origin).y
	var k := (s_head - s_foot) / maxf(0.01, t_head - t_foot)
	body.scale = Vector3.ONE * k
	body.position.y += s_foot - global_position.y - (t_foot - global_position.y) * k


static func library(lib_name: String) -> AnimationLibrary:
	if not _libs.has(lib_name):
		var ual: Node = (load(UAL[lib_name]) as PackedScene).instantiate()
		var ap: AnimationPlayer = ual.find_children("*", "AnimationPlayer", true, false)[0]
		var lib: AnimationLibrary = ap.get_animation_library("").duplicate(true)
		ual.free()
		for n in lib.get_animation_list():
			lib.get_animation(n).loop_mode = Animation.LOOP_LINEAR if String(n) in LOOPED else Animation.LOOP_NONE
		_libs[lib_name] = lib
	return _libs[lib_name]


static func clip_length(clip: String) -> float:
	var parts := clip.split("/")
	var lib := library(parts[0] if parts.size() > 1 else "")
	return lib.get_animation(parts[-1]).length


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


func _start_tree(root: AnimationNode) -> void:
	_tree = AnimationTree.new()
	_tree.name = "AnimationTree"
	driver.add_child(_tree)
	_tree.anim_player = _tree.get_path_to(anim_player)
	_tree.root_node = _tree.get_path_to(driver)
	_tree.tree_root = root
	_tree.active = true


## Our bone (by UAL name) as a world point now.
func bone_point(ual: String) -> Vector3:
	if not is_inside_tree():
		return Vector3.ZERO  # a scene being freed: no world transform to give
	var i := skeleton.find_bone(bone_map.get(ual, BONE_MAP.get(ual, "")))
	return skeleton.global_transform * skeleton.get_bone_global_pose(i).origin if i >= 0 else global_position


## Test only: "rest" = the GLB's own rest pose (no retarget), otherwise hold one UAL clip.
func debug_pose(what: String) -> void:
	if what == "rest":
		if _src.skeleton_updated.is_connected(_retarget.apply):
			_src.skeleton_updated.disconnect(_retarget.apply)
		skeleton.reset_bone_poses()
		return
	if not _src.skeleton_updated.is_connected(_retarget.apply):
		_src.skeleton_updated.connect(_retarget.apply)
	_tree.active = false
	anim_player.play(what)
	anim_player.seek(0.3, true)
	anim_player.pause()


## Test only: how far each bone has turned from its rest (degrees, world).
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
