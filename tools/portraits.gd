extends Node3D
## Album portraits: a head-and-shoulders picture of every named character (Characters.MODELS) in
## their idle pose, a soft key light from the front left, a fill, a plain warm background that
## takes a sepia tint well. Saves res://assets/portraits/<id>.png (512 x 512). Windowed only:
##   godot --path . --resolution 512x512 --position -6000,-6000 res://tools/portraits.tscn [-- --only=eleanor,hassan]

const OUT := "res://assets/portraits"
const SIZE := 512
const HEAD_BONE := "bone_5"   # the Armour 01 rig's head (RiggedBody.BONE_MAP "Head")

var _cam: Camera3D


func _ready() -> void:
	get_window().set_flag(Window.FLAG_NO_FOCUS, true)
	get_window().size = Vector2i(SIZE, SIZE)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.8, 0.72, 0.58)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.85, 0.78, 0.68)
	env.ambient_light_energy = 0.35
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var key := DirectionalLight3D.new()
	key.light_energy = 1.3
	key.light_color = Color(1.0, 0.94, 0.85)
	key.rotation_degrees = Vector3(-25, 145, 0)  # onto the faces (they look at -Z, toward the camera), from their right
	add_child(key)
	var fill := DirectionalLight3D.new()
	fill.light_energy = 0.45
	fill.rotation_degrees = Vector3(-10, -140, 0)  # and a softer fill from their left
	add_child(fill)
	_cam = Camera3D.new()
	_cam.fov = 30.0
	add_child(_cam)
	_cam.current = true
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		print("RESULT portraits: headless, nothing drawn")
		get_tree().quit(0)
		return
	var only: Array = []
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.substr(7).split(",", false)
	var done := 0
	for id in Characters.MODELS:
		if not only.is_empty() and not id in only:
			continue
		var glb := Characters.DIR + str(Characters.MODELS[id])
		if not ResourceLoader.exists(glb):
			print("RESULT portrait %s: no model yet (%s)" % [id, glb])
			continue
		var body := NpcBody.create(glb)
		if body == null:
			continue
		add_child(body)
		body.global_position = Vector3.ZERO
		for i in 20:  # let the idle settle
			await get_tree().process_frame
		var head := _head(body)
		var fwd := Vector3(0, 0, -1)  # the bodies face -Z; the camera stands in front, a little to the left
		_cam.global_position = head + fwd * 1.15 + Vector3(-0.18, -0.08, 0)  # at eye level
		_cam.look_at(head + Vector3(0, -0.14, 0), Vector3.UP)
		for i in 3:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		if img.get_width() != SIZE or img.get_height() != SIZE:
			img.resize(SIZE, SIZE, Image.INTERPOLATE_LANCZOS)
		var path := OUT.path_join("%s.png" % id)
		img.save_png(ProjectSettings.globalize_path(path))
		print("RESULT portrait %s -> %s (head at %s)" % [id, path, head.snapped(Vector3.ONE * 0.01)])
		done += 1
		body.queue_free()
		await get_tree().process_frame
	print("RESULT portraits done=%d" % done)
	get_tree().quit(0)


## The head bone's position (world), or a usual head height if the rig can't say.
func _head(body: NpcBody) -> Vector3:
	var sk := body.skeleton
	if sk:
		var i := sk.find_bone(HEAD_BONE)
		if i >= 0:
			return sk.global_transform * sk.get_bone_global_pose(i).origin + Vector3.UP * 0.08
	return Vector3(0, 1.62, 0)
