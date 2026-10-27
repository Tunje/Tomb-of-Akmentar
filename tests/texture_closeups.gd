extends Node3D
## Close-ups for judging texture compression: each model as imported (its bind pose), framed from
## the front at a fixed spot (a face, a chest of bandages) under fixed lights, 1024 x 1024. Run it
## before and after an import change and compare. Windowed only:
##   godot --path . res://tests/texture_closeups.tscn -- --shot-dir=C:/path [--tag=before]

## name -> [glb, height to look at (0.9 = the head bone, lower = down the body), distance in m]
const SHOTS := {
	"eleanor_face": ["res://assets/characters/act4/eleanor.glb", 0.9, 1.0],
	"eleanor_body": ["res://assets/characters/act4/eleanor.glb", 0.6, 1.6],
	"mummy_bandages": ["res://assets/characters/mummies/tomb_guard.glb", 0.72, 0.9],
	"priest_face": ["res://assets/characters/mummies/high_priest.glb", 0.9, 0.8],
}


func _ready() -> void:
	var args := TestDriver.parse_args()
	var dir := str(args.get("shot-dir", "user://closeups"))
	var tag := str(args.get("tag", "shot"))
	DirAccess.make_dir_recursive_absolute(dir)
	var w := get_window()
	w.size = Vector2i(1024, 1024)
	w.position = Vector2i(-1400, 40)
	w.set_flag(Window.FLAG_NO_FOCUS, true)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.32, 0.28, 0.24)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.5, 0.48, 0.45)
	add_child(env)
	var key := DirectionalLight3D.new()
	key.rotation = Vector3(deg_to_rad(-30), deg_to_rad(-35), 0)
	add_child(key)
	var cam := Camera3D.new()
	cam.fov = 35.0
	add_child(cam)
	cam.make_current()
	for name: String in SHOTS:
		var s: Array = SHOTS[name]
		if not ResourceLoader.exists(s[0]):
			print("CLOSEUP %s: no %s" % [name, s[0]])
			continue
		var model: Node3D = (load(s[0]) as PackedScene).instantiate()
		add_child(model)
		# Skinned: the meshes' own bounds aren't where the body is drawn, so frame on the skeleton:
		# its head bone (`height` of the way from the root's feet up to it).
		var at := Vector3(0, 1.5, 0)
		var sk: Skeleton3D = model.find_children("*", "Skeleton3D", true, false).front() if not model.find_children("*", "Skeleton3D", true, false).is_empty() else null
		if sk:
			var head := -1
			for b in sk.get_bone_count():
				if sk.get_bone_name(b).to_lower().contains("head") or (head < 0 and sk.get_bone_name(b) == "bone_5"):
					head = b
			if head >= 0:
				var hp := sk.global_transform * sk.get_bone_global_pose(head).origin
				at = Vector3(hp.x, hp.y * float(s[1]) / 0.9, hp.z)
		cam.global_position = at + Vector3(0, 0, float(s[2]))  # models face +Z
		cam.look_at(at, Vector3.UP)
		for i in 4:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(dir.path_join("%s_%s.png" % [name, tag]))
		print("CLOSEUP %s saved" % name)
		model.queue_free()
		await get_tree().process_frame
	get_tree().quit(0)
