extends Node3D
## The caravan town v2 (gameplan/route_stops_plan.md, stage 1), walked: it builds, every spot stands
## on the navmesh and can be walked to from the arrival outside the south gate, and how long each
## walk is (at 4 m/s). Windowed, it also saves an overview and street views, each with its frame
## rate (vsync off, so it is the headroom).
##   godot --headless --path . res://tests/town_v2_test.tscn -- --ci
##   godot --path . res://tests/town_v2_test.tscn -- --shot-dir=C:/path

const VIEWS := {
	"overview": [Vector3(150, 210, 330), Vector3(150, 0, 105)],
	"arrival": [Vector3(180, 1.7, 240), Vector3(180, 3.0, 150)],
	"gate_street": [Vector3(180, 1.7, 200), Vector3(170, 2.0, 96)],
	"well_square": [Vector3(186, 1.7, 84), Vector3(130, 3.0, 40)],
	"souk_lane": [Vector3(192, 1.7, 30), Vector3(296, 2.0, 30)],
	"caravanserai": [Vector3(86, 1.7, 76), Vector3(24, 3.0, 36)],
	"mosque": [Vector3(116, 1.7, 156), Vector3(150, 8.0, 112)],
	"grove": [Vector3(54, 1.7, 214), Vector3(54, 3.0, 110)],
}

var _level: TownV2
var _fails := 0
var _dir := "user://town_v2"


func _ready() -> void:
	get_window().set_flag(Window.FLAG_NO_FOCUS, true)
	_dir = str(TestDriver.parse_args().get("shot-dir", _dir))
	DirAccess.make_dir_recursive_absolute(_dir)
	var t0 := Time.get_ticks_msec()
	_level = TownV2.new()
	add_child(_level)
	print("RESULT build_ms %d" % (Time.get_ticks_msec() - t0))
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print("RESULT %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_fails += 1


func _length(map: RID, a: Vector3, b: Vector3) -> float:
	var p := NavigationServer3D.map_get_path(map, a, b, true)
	var l := 0.0
	for k in range(1, p.size()):
		l += p[k].distance_to(p[k - 1])
	return l


func _run() -> void:
	for i in 4:
		await get_tree().physics_frame
	var map := get_world_3d().navigation_map
	# The map syncs on a worker thread, in real time: under --fixed-fps frames run far faster than that.
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 30000:
		if NavigationServer3D.map_get_closest_point(map, _level.player_spawn) != Vector3.ZERO:
			break
		await get_tree().physics_frame
	print("RESULT the map synced in %d ms" % (Time.get_ticks_msec() - t0))
	var from := NavigationServer3D.map_get_closest_point(map, _level.player_spawn)
	print("RESULT navmesh %d polygons, closest to the arrival %s" % [_level._nav.navigation_mesh.get_polygon_count(), from])
	_check(from.distance_to(_level.player_spawn) < 0.6, "the arrival (%s) is on the navmesh" % _level.player_spawn)
	var longest := 0.0
	var longest_id := ""
	for id: String in _level.spots:
		var to: Vector3 = _level.spots[id]
		var near := NavigationServer3D.map_get_closest_point(map, to)
		var path := NavigationServer3D.map_get_path(map, from, near, true)
		var length := _length(map, from, near)
		var reached := path.size() > 1 and path[path.size() - 1].distance_to(near) < 1.0
		var on := Vector2(near.x - to.x, near.z - to.z).length() < 1.5 and absf(near.y - to.y) < 0.6
		_check(on and reached, "%-17s at %s: %s, walk %.0f m (%.0f s)" % [id, to.snapped(Vector3.ONE * 0.1),
			"on the navmesh" if on else "OFF the navmesh (%s)" % near.snapped(Vector3.ONE * 0.1), length, length / Player.WALK])
		if reached and length > longest:
			longest = length
			longest_id = id
	print("RESULT longest walk from the arrival: %s, %.0f m (%.0f s walking, %.0f s sprinting)" % [longest_id, longest,
		longest / Player.WALK, longest / Player.SPRINT])
	for pair: Array in [["south_gate", "well"], ["south_gate", "caravanserai"], ["well", "store"], ["store", "inn"],
			["grove", "souk_east"], ["caravanserai", "mosque"]]:
		var a := NavigationServer3D.map_get_closest_point(map, _level.spots[pair[0]])
		var b := NavigationServer3D.map_get_closest_point(map, _level.spots[pair[1]])
		var l := _length(map, a, b)
		print("RESULT walk %s -> %s: %.0f m (%.0f s)" % [pair[0], pair[1], l, l / Player.WALK])
	# Every district has a spot of its own (walked above).
	for id: String in TownV2.DISTRICTS:
		var r: Rect2 = TownV2.DISTRICTS[id]
		var in_it: Array = _level.spots.keys().filter(func(s: String) -> bool:
			var p: Vector3 = _level.spots[s]
			return r.grow(1.0).has_point(Vector2(p.x, p.z)))
		_check(not in_it.is_empty(), "district %-13s has %s" % [id, in_it])
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		var cam := Camera3D.new()
		cam.far = 1200.0
		add_child(cam)
		cam.make_current()
		for name: String in VIEWS:
			var v: Array = VIEWS[name]
			cam.global_position = v[0]
			cam.look_at(v[1], Vector3.UP)
			for i in 10:
				await get_tree().process_frame
			var f0 := Time.get_ticks_usec()
			for i in 60:
				await get_tree().process_frame
			var fps := 60.0e6 / float(Time.get_ticks_usec() - f0)
			print("RESULT fps %-12s %.0f (draw calls %d)" % [name, fps,
				RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)])
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(_dir.path_join("town_v2_%s.png" % name))
	print("RESULT town_v2_test %s (%d failed)" % ["PASS" if _fails == 0 else "FAIL", _fails])
	get_tree().quit(0 if _fails == 0 else 1)
