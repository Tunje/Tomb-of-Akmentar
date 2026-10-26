extends Node3D
## Screenshots of the Akmentar surface (AkmentarSurface) by day and at dusk: the whole site, our
## camp and its fire pillars, a dressed relief wall, the colonnade, the statues. Windowed only.
## Args after "--": --shot-dir=C:/path (default user://surface_shots). Never takes focus.

const VIEWS := [
	["overview", Vector3(70, 46, 152), Vector3(70, 0, 66)],
	["camp", Vector3(84, 4.5, 130), Vector3(70, 1.5, 114)],
	["relief_wall", Vector3(49, 2.2, 66), Vector3(42, 2.0, 60)],
	["colonnade", Vector3(52, 2.4, 94), Vector3(46, 3.0, 40)],
	["statues", Vector3(70, 3.0, 58), Vector3(70, 3.5, 38)],
]

var _dir := "user://surface_shots"


func _ready() -> void:
	get_window().set_flag(Window.FLAG_NO_FOCUS, true)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot-dir="):
			_dir = a.substr(11)
	DirAccess.make_dir_recursive_absolute(_dir)
	var level := AkmentarSurface.new()
	add_child(level)
	var cam := Camera3D.new()
	cam.fov = 62.0
	cam.far = 900.0
	add_child(cam)
	cam.current = true
	_run.call_deferred(level, cam)


func _run(level: AkmentarSurface, cam: Camera3D) -> void:
	if DisplayServer.get_name() == "headless":
		print("RESULT surface_shots: headless, no shots")
		get_tree().quit(0)
		return
	for when in [["day", 0.0], ["dusk", 0.55]]:
		level.set_night(when[1])
		for v in VIEWS:
			cam.look_at_from_position(v[1], v[2])
			for i in 8:
				await get_tree().process_frame
			var path := _dir.path_join("surface_%s_%s.png" % [v[0], when[0]])
			get_viewport().get_texture().get_image().save_png(path)
			print("RESULT shot ", ProjectSettings.globalize_path(path))
	get_tree().quit(0)
