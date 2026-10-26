extends Node3D
## Act 2 map test: builds Cairo, checks every named spot is reachable on the navmesh from the
## spawn and that no spot or person stands inside something solid, then (with a window) takes
## day and dusk screenshots round the quarter. Prints RESULT lines; exits 0 when every check
## passed. Args after "--":
##   --shot-dir=C:/path   where PNGs go (default user://cairo_shots)
##   --no-shots           checks only (headless)
## Never takes focus or captures the mouse (Simon plays while we test).

const VIEWS := [
	["avenue_west", Vector3(4, 3.0, 50), Vector3(60, 2, 50)],
	["hotel", Vector3(47, 2.2, 58), Vector3(47, 4, 44)],
	["museum", Vector3(92, 2.5, 45), Vector3(92, 4, 26)],
	["bazaar", Vector3(70, 2.0, 77), Vector3(36, 1.6, 77)],
	["caravanserai", Vector3(100, 3.0, 96), Vector3(84, 1.0, 64)],
	["docks", Vector3(96, 4.0, 40), Vector3(122, 0, 54)],
	["tavern", Vector3(36, 2.0, 74), Vector3(26, 2, 64)],
	["overview", Vector3(-6, 45, 120), Vector3(56, 0, 46)],
]

var _dir := "user://cairo_shots"
var _shots := true
var _level: Cairo
var _cam: Camera3D
var _fails := 0


func _ready() -> void:
	get_window().set_flag(Window.FLAG_NO_FOCUS, true)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot-dir="):
			_dir = a.substr(11)
		elif a == "--no-shots":
			_shots = false
	if DisplayServer.get_name() == "headless":
		_shots = false
	DirAccess.make_dir_recursive_absolute(_dir)
	var t0 := Time.get_ticks_msec()
	_level = Cairo.new()
	add_child(_level)
	print("RESULT build_ms %d" % (Time.get_ticks_msec() - t0))
	_level.place_people()
	_cam = Camera3D.new()
	_cam.fov = 62.0
	_cam.far = 900.0
	add_child(_cam)
	_cam.current = true
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print("RESULT %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_fails += 1


func _run() -> void:
	for i in 4:
		await get_tree().physics_frame
	var map := get_world_3d().navigation_map
	NavigationServer3D.map_force_update(map)
	await get_tree().physics_frame
	var space := get_world_3d().direct_space_state
	var from := NavigationServer3D.map_get_closest_point(map, _level.player_spawn)
	_check(from.distance_to(_level.player_spawn) < 0.6, "spawn is on the navmesh")
	for id in _level.spots:
		var to: Vector3 = _level.spots[id]
		if id == "museum":
			to.y = 0.15
		var path := NavigationServer3D.map_get_path(map, from, to, true)
		var end := path[path.size() - 1] if path.size() > 0 else from
		_check(path.size() > 0 and Vector2(end.x, end.z).distance_to(Vector2(to.x, to.z)) < 0.9, "reach %s (path end %.1f m off)" % [id, Vector2(end.x, end.z).distance_to(Vector2(to.x, to.z))])
		_check(not _inside(space, to + Vector3.UP * 1.0), "%s spot is clear" % id)
	for id in _level.npcs:
		var p: Vector3 = (_level.npcs[id] as Node3D).global_position
		_check(not _inside(space, p + Vector3.UP * 1.0), "%s stands clear" % id)
	_check(_level.interactables.has("hotel_bed"), "the hotel bed is usable")
	if _shots:
		for night in [0.0, 1.0]:
			_level.set_night(night)
			for v in VIEWS:
				if night > 0.0 and not v[0] in ["avenue_west", "bazaar", "museum", "overview"]:
					continue
				_cam.look_at_from_position(v[1], v[2])
				for i in 6:
					await get_tree().process_frame
				var img := get_viewport().get_texture().get_image()
				var path := _dir.path_join("cairo_%s_%s.png" % [v[0], "dusk" if night > 0.0 else "day"])
				img.save_png(path)
				print("SHOT ", ProjectSettings.globalize_path(path))
	print("RESULT %s (%d failed)" % ["PASS" if _fails == 0 else "FAIL", _fails])
	get_tree().quit(0 if _fails == 0 else 1)


## Is `p` inside a solid (anything on layer 1)?
func _inside(space: PhysicsDirectSpaceState3D, p: Vector3) -> bool:
	var q := PhysicsPointQueryParameters3D.new()
	q.position = p
	q.collision_mask = 1
	return not space.intersect_point(q, 1).is_empty()
