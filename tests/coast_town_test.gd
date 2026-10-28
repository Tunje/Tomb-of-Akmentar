extends Node3D
## The coast fishing town (CoastTown, gameplan/route_stops_plan.md stage 1), walked: it builds, every spot stands
## on the navmesh and can be walked to from the arrival on the shore road, and how long each
## walk is (at 4 m/s). Windowed, it also saves an overview and street views, each with its frame
## rate (vsync off, so it is the headroom).
##   godot --headless --path . res://tests/coast_town_test.tscn -- --ci
##   godot --path . res://tests/coast_town_test.tscn -- --shot-dir=C:/path

const VIEWS := {
	"overview": [Vector3(30, 200, 330), Vector3(30, 0, 110)],
	"arrival": [Vector3(201, 1.7, 252), Vector3(150, 4.0, 160)],
	"harbour_street": [Vector3(190, 1.7, 78), Vector3(-30, 2.0, 78)],
	"quay": [Vector3(-26, 1.7, 112), Vector3(-80, 3.0, 40)],
	"lighthouse": [Vector3(-110, 1.7, 40), Vector3(-122, 10.0, 114)],
	"beach": [Vector3(-14, 1.7, 236), Vector3(-18, 1.0, 140)],
	"fish_market": [Vector3(56, 1.7, 72), Vector3(10, 1.5, 36)],
	"coffee_house": [Vector3(66, 1.7, 80), Vector3(120, 2.5, 64)],
	"boatyard": [Vector3(90, 1.7, 145), Vector3(115, 2.0, 115)],
	"mosque": [Vector3(67, 1.7, 86), Vector3(40, 9.0, 120)],
}

var _level: CoastTown
var _fails := 0
var _dir := "user://coast_town"


func _ready() -> void:
	get_window().set_flag(Window.FLAG_NO_FOCUS, true)
	_dir = str(TestDriver.parse_args().get("shot-dir", _dir))
	DirAccess.make_dir_recursive_absolute(_dir)
	var t0 := Time.get_ticks_msec()
	_level = CoastTown.new()
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
	for pair: Array in [["arrival", "coffee_house"], ["coffee_house", "quay"], ["quay", "keeper"], ["fish_market", "trader"],
			["keeper", "nets"], ["road_north", "arrival"]]:
		var a := NavigationServer3D.map_get_closest_point(map, _level.spots[pair[0]])
		var b := NavigationServer3D.map_get_closest_point(map, _level.spots[pair[1]])
		var l := _length(map, a, b)
		print("RESULT walk %s -> %s: %.0f m (%.0f s)" % [pair[0], pair[1], l, l / Player.WALK])
	# Every district has a spot of its own (walked above).
	for id: String in CoastTown.COAST_DISTRICTS:
		var r: Rect2 = CoastTown.COAST_DISTRICTS[id]
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
			get_viewport().get_texture().get_image().save_png(_dir.path_join("coast_town_%s.png" % name))
	print("RESULT coast_town_test %s (%d failed)" % ["PASS" if _fails == 0 else "FAIL", _fails])
	get_tree().quit(0 if _fails == 0 else 1)
