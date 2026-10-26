class_name NpcBody
extends RiggedBody
## A townsperson / companion on the image-to-3d rig: UAL1 Idle, blending into Idle_Talking while
## they speak (Npc sets `talk` 0..1). Stand-in GLBs until the real characters arrive.

const SCOUT := "res://assets/characters/bandits/bandit_scout.glb"
const EXPLORER := "res://assets/characters/explorer/explorer.glb"

var talk := 0.0
var _glb := SCOUT


## Null when an asset is missing; the caller keeps its stand-in then.
static func create(glb := "") -> NpcBody:
	var path := glb if glb != "" else SCOUT
	if not assets_present(path):
		return null
	var b := NpcBody.new()
	b._glb = path
	b.name = "NpcBody"
	return b


func _ready() -> void:
	_setup_rig(_glb)


func _build_tree() -> void:
	# RiggedBody.LOOPED doesn't list the talking idle; loop it here (the library is shared).
	var lib := anim_player.get_animation_library("")
	if lib.has_animation("Idle_Talking"):
		lib.get_animation("Idle_Talking").loop_mode = Animation.LOOP_LINEAR
	var bt := AnimationNodeBlendTree.new()
	bt.add_node("idle", _anim("Idle"))
	bt.add_node("talking", _anim("Idle_Talking" if lib.has_animation("Idle_Talking") else "Idle"))
	bt.add_node("talk", AnimationNodeBlend2.new())
	bt.connect_node("talk", 0, "idle")
	bt.connect_node("talk", 1, "talking")
	bt.connect_node("output", 0, "talk")
	_start_tree(bt)


func _process(_delta: float) -> void:
	if _tree:
		_tree.set("parameters/talk/blend_amount", talk)
