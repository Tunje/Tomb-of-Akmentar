extends Node3D
## The steamer (Steamer on SteamerV2, gameplan/route_stops_plan.md stage 1), walked: every place
## aboard, down in the hold, up on the sun deck, in the saloon, each cabin, the galley and the
## wheelhouse, can be walked to from the foredeck, and how long each walk is. Windowed, it saves
## views outside and in every room, each with its frame rate (vsync off, so it is the headroom).
##   godot --headless --path . res://tests/steamer_test.tscn -- --ci
##   godot --path . res://tests/steamer_test.tscn -- --shot-dir=C:/path

## [camera, look at], in the boat's frame (the boat is at the map's origin, unturned).
const VIEWS := {
	"from_the_bank": [Vector3(52, 9, -40), Vector3(0, 2, 0)],
	"broadside": [Vector3(-34, 3, 4), Vector3(0, 2.5, 0)],
	"foredeck": [Vector3(0, 2.9, -25.5), Vector3(0, 2.5, -10)],
	"saloon": [Vector3(-2.8, 2.9, -9.2), Vector3(1.5, 2.0, 1.0)],
	"saloon_bar": [Vector3(-1.0, 2.9, -2.0), Vector3(3.0, 2.0, 1.8)],
	"corridor": [Vector3(0, 2.9, 2.6), Vector3(0, 2.4, 12)],
	"cabin": [Vector3(1.0, 2.9, 3.0), Vector3(3.6, 1.8, 5.0)],
	"galley": [Vector3(-1.4, 2.9, 15.6), Vector3(-3.4, 1.8, 12.4)],
	"hold": [Vector3(3.0, 0.9, 19.0), Vector3(-2.6, -0.4, 11.0)],
	"sun_deck": [Vector3(4.6, 5.9, 15.6), Vector3(-1.0, 4.6, -8.0)],
	"wheelhouse": [Vector3(0, 5.9, -5.4), Vector3(0, 5.2, -10)],
	"side_walkway": [Vector3(4.6, 2.9, 11.0), Vector3(4.6, 2.4, -10.0)],
}

var _level: SteamerV2
var _fails := 0
var _dir := "user://steamer"


func _ready() -> void:
	get_window().set_flag(Window.FLAG_NO_FOCUS, true)
	_dir = str(TestDriver.parse_args().get("shot-dir", _dir))
	DirAccess.make_dir_recursive_absolute(_dir)
	var t0 := Time.get_ticks_msec()
	_level = SteamerV2.new()
	add_child(_level)
	print("RESULT build_ms %d" % (Time.get_ticks_msec() - t0))
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print("RESULT %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_fails += 1


func _run() -> void:
	for i in 4:
		await get_tree().physics_frame
	var map := get_world_3d().navigation_map
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 30000:
		if NavigationServer3D.map_get_iteration_id(map) > 0 and NavigationServer3D.map_get_closest_point(map, _level.player_spawn) != Vector3.ZERO:
			break
		await get_tree().physics_frame
	var from := NavigationServer3D.map_get_closest_point(map, _level.player_spawn)
	print("RESULT the map synced in %d ms, navmesh %d polygons" % [Time.get_ticks_msec() - t0, _level._nav.navigation_mesh.get_polygon_count()])
	_check(from.distance_to(_level.player_spawn) < 0.6, "the foredeck (%s) is on the navmesh" % _level.player_spawn)
	for id: String in _level.spots:
		var to: Vector3 = _level.spots[id]
		var near := NavigationServer3D.map_get_closest_point(map, to)
		var path := NavigationServer3D.map_get_path(map, from, near, true)
		var l := 0.0
		for k in range(1, path.size()):
			l += path[k].distance_to(path[k - 1])
		# (The navmesh rides about 0.5 m over a deck, more where one polygon spans a deck and a stair's foot.)
		var on := Vector2(near.x - to.x, near.z - to.z).length() < 1.0 and absf(near.y - to.y) < 0.8
		var reached := path.size() > 1 and path[path.size() - 1].distance_to(near) < 0.5
		_check(on and reached, "%-17s at %s: %s, walk %.0f m (%.0f s)" % [id, to.snapped(Vector3.ONE * 0.1),
			("on the navmesh" if on else "OFF the navmesh (%s)" % near.snapped(Vector3.ONE * 0.1)) + ("" if reached else ", NOT reached"),
			l, l / Player.WALK])
	_check(_level.interactables.has("steamer_bed"), "your cabin's bunk: sleep and save")
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		var cam := Camera3D.new()
		cam.far = 900.0
		cam.near = 0.05
		add_child(cam)
		cam.make_current()
		for name: String in VIEWS:
			var v: Array = VIEWS[name]
			var up := Vector3.UP * (Steamer.DECK - 1.2)   # (the views were set for a 1.2 m deck)
			cam.global_position = v[0] + up
			cam.look_at(v[1] + up, Vector3.UP)
			for i in 10:
				await get_tree().process_frame
			var f0 := Time.get_ticks_usec()
			for i in 60:
				await get_tree().process_frame
			print("RESULT fps %-13s %.0f (draw calls %d)" % [name, 60.0e6 / float(Time.get_ticks_usec() - f0),
				RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)])
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(_dir.path_join("steamer_%s.png" % name))
	print("RESULT steamer_test %s (%d failed)" % ["PASS" if _fails == 0 else "FAIL", _fails])
	get_tree().quit(0 if _fails == 0 else 1)
