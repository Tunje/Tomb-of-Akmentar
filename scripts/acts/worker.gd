class_name Worker
extends RiggedBody
## Someone busy at a dig: an image-to-3d character on the shared rig, looping one work clip
## (kneeling and fixing, swinging a tool, picking things up). Decoration with no AI.

const CLIPS := ["Fixing_Kneeling", "ual2/TreeChopping", "ual2/Farm_Harvest", "PickUp_Table"]

var glb := ""
var clip := ""


static func make(parent: Node3D, at: Vector3, face: Vector3, model: String, work_clip := "") -> Worker:
	if not assets_present(model):
		return null
	var w := Worker.new()
	w.glb = model
	w.clip = work_clip if work_clip != "" else CLIPS[randi() % CLIPS.size()]
	parent.add_child(w)
	w.global_position = at
	w.look_at(Vector3(face.x, at.y, face.z), Vector3.UP)
	return w


func _ready() -> void:
	_setup_rig(glb)


func _build_tree() -> void:
	var parts := clip.split("/")
	var anim := library(parts[0] if parts.size() > 1 else "").get_animation(parts[-1])
	anim.loop_mode = Animation.LOOP_LINEAR
	var bt := AnimationNodeBlendTree.new()
	var a := _anim(clip)
	bt.add_node("work", a)
	var ts := AnimationNodeTimeScale.new()
	bt.add_node("speed", ts)
	bt.connect_node("speed", 0, "work")
	bt.connect_node("output", 0, "speed")
	_start_tree(bt)
	_tree.set("parameters/speed/scale", randf_range(0.85, 1.1))
	# Not all in step: start each somewhere in its loop.
	anim_player.seek(randf() * anim.length, true)
