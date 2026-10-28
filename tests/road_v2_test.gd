extends Node3D
## The desert road v2 (RoadV2, gameplan/route_stops_plan.md stage 1), walked and timed: it builds
## (the navmesh in tiles), every stop, both canyon shelves, the tower's top, the night camp and
## every spot in the town can be walked to from the start, the road's length and its drive time
## (truck, galloping, the convoy's pace, on foot). Windowed, it also saves views along the road,
## each with its frame rate (vsync off, so it is the headroom).
##   godot --headless --path . res://tests/road_v2_test.tscn -- --ci
##   godot --path . res://tests/road_v2_test.tscn -- --shot-dir=C:/path

const VIEWS := {
	"overview": [Vector3(520, 520, 1100), Vector3(180, 0, 620)],
	"start": [Vector3(184, 1.7, 1235), Vector3(170, 2.0, 1150)],
	"dead_camel": [Vector3(186, 1.7, 1096), Vector3(170, 0.5, 1078)],
	"tower_view": [Vector3(0, 0, 0), Vector3(0, 0, 0)],       # from its top, down the road (set in _run)
	"canyon_road": [Vector3(0, 0, 0), Vector3(0, 0, 0)],      # from the south, into it
	"canyon_shelf": [Vector3(0, 0, 0), Vector3(0, 0, 0)],     # a bandit's view from the west shelf
	"fork": [Vector3(0, 0, 0), Vector3(0, 0, 0)],
	"camp": [Vector3(0, 0, 0), Vector3(0, 0, 0)],
	"town_approach": [Vector3(0, 0, 0), Vector3(180, 6.0, 150)],
	"left_edge": [Vector3(0, 0, 0), Vector3(0, 0, 0)],          # the banks at the map's west side
}
## Town spots walked as well (the town's own test has every one).
const TOWN := ["south_gate", "well", "caravanserai", "souk", "store", "inn"]

var _level: RoadV2
var _fails := 0
var _dir := "user://road_v2"


func _ready() -> void:
	get_window().set_flag(Window.FLAG_NO_FOCUS, true)
	_dir = str(TestDriver.parse_args().get("shot-dir", _dir))
	DirAccess.make_dir_recursive_absolute(_dir)
	var t0 := Time.get_ticks_msec()
	_level = RoadV2.new()
	add_child(_level)
	print("RESULT build_ms %d (the navmesh %d tiles in %d ms)" % [Time.get_ticks_msec() - t0, _level.tiles, _level.bake_ms])
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
	print("RESULT the map synced in %d ms, %d regions" % [Time.get_ticks_msec() - t0, NavigationServer3D.map_get_regions(map).size()])
	var road := RoadV2.road_length(RoadV2.START_Z, RoadV2.GATE_Z)
	print("RESULT the road, start to gate: %.0f m. Truck flat out (%.1f m/s) %.0f s; galloping (%.0f m/s) %.0f s; the convoy's pace (3.4 m/s, the act3 bot's) %.0f s; walking %.0f s" % [
		road, Truck.MAX_SPEED, road / Truck.MAX_SPEED, Horse.GALLOP, road / Horse.GALLOP, road / 3.4, road / Player.WALK])
	_check(road > 950.0 and road < 1150.0, "about 1 km of road (%.0f m)" % road)
	for name: String in ["start", "start_well", "dead_camel", "tower", "tower_view", "storm", "ambush", "fork", "temple_track", "camp", "camp_lookout"]:
		_walk(map, name, _level.spots[name])
	for k in _level.bandit_posts.size():
		_walk(map, "bandit_post_%d" % k, _level.bandit_posts[k])
	for k in (_level.camp.spots.beds as Array).size():
		_walk(map, "camp_bed_%d" % k, _level.camp.spots.beds[k])
	for name: String in TOWN:
		_walk(map, name, _level.spots[name])
	# The map is closed: nothing walkable past the banks round its sides, and the canyon is the
	# only way north (the walk from the start to the gate goes down it).
	var outside := [Vector3(-160, 0, 700), Vector3(460, 0, 700), Vector3(180, 0, -120), Vector3(180, 0, 1340)]
	var inside := RoadV2.GROUND.grow(1.0)
	var from := NavigationServer3D.map_get_closest_point(map, _level.player_spawn)
	var escaped := outside.filter(func(p: Vector3) -> bool:
		var q := NavigationServer3D.map_get_closest_point(map, p)
		var path := NavigationServer3D.map_get_path(map, from, q, true)
		return not inside.has_point(Vector2(q.x, q.z)) and path.size() > 1 and path[-1].distance_to(q) < 1.0)
	_check(escaped.is_empty(), "nothing walkable past the banks (%s)" % [escaped])
	var through := NavigationServer3D.map_get_path(map, NavigationServer3D.map_get_closest_point(map, _level.spots.start),
		NavigationServer3D.map_get_closest_point(map, _level.spots.south_gate), true)
	var in_canyon := true
	for q: Vector3 in through:
		if q.z > RoadV2.CANYON.x and q.z < RoadV2.CANYON.y and (absf(q.x - RoadV2.road_x(q.z)) > RoadV2.SHELF.y or q.y > 0.6):
			in_canyon = false
	_check(in_canyon and through.size() > 1, "the way north runs down the canyon (%d path points)" % through.size())
	# Each stop from the one before it, along the road (on foot).
	var order := ["start", "dead_camel", "tower", "ambush", "camp", "fork", "south_gate", "caravanserai"]
	for i in range(1, order.size()):
		var l := _length(map, _level.spots[order[i - 1]], _level.spots[order[i]])
		print("RESULT walk %s -> %s: %.0f m (%.0f s)" % [order[i - 1], order[i], l, l / Player.WALK])
	if DisplayServer.get_name() != "headless":
		var views := VIEWS.duplicate(true)
		var tw: Vector3 = _level.spots.tower_view
		views.tower_view = [tw + Vector3(0, 1.7, 0), RoadV2.road_point(RoadV2.TOWER_Z - 120.0)]
		views.canyon_road = [RoadV2.road_point(RoadV2.CANYON.y + 40.0) + Vector3(0, 1.7, 0), RoadV2.road_point(RoadV2.AMBUSH_Z) + Vector3(0, 3, 0)]
		var post: Vector3 = _level.bandit_posts[4]
		views.canyon_shelf = [post + Vector3(-1.0, 1.7, 0), RoadV2.road_point(RoadV2.CANYON.y + 30.0)]
		views.fork = [RoadV2.road_point(RoadV2.FORK_Z - 20.0) + Vector3(4, 1.7, 0), RoadV2.road_point(RoadV2.FORK_Z) + Vector3(-12, 0, 8)]
		views.camp = [RoadV2.road_point(RoadV2.CAMP_Z) + Vector3(30, 6.0, 20), _level.camp.anchor]
		views.left_edge = [RoadV2.road_point(800) + Vector3(-60, 1.7, 0), Vector3(-80, 8.0, 760)]
		views.town_approach = [RoadV2.road_point(RoadV2.GATE_Z + 160.0) + Vector3(0, 1.7, 0), Vector3(180, 6.0, 150)]
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		var cam := Camera3D.new()
		cam.far = 2000.0
		add_child(cam)
		cam.make_current()
		for name: String in views:
			var v: Array = views[name]
			cam.global_position = v[0]
			cam.look_at(v[1], Vector3.UP)
			for i in 10:
				await get_tree().process_frame
			var f0 := Time.get_ticks_usec()
			for i in 60:
				await get_tree().process_frame
			print("RESULT fps %-14s %.0f (draw calls %d)" % [name, 60.0e6 / float(Time.get_ticks_usec() - f0),
				RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)])
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(_dir.path_join("road_v2_%s.png" % name))
	print("RESULT road_v2_test %s (%d failed)" % ["PASS" if _fails == 0 else "FAIL", _fails])
	get_tree().quit(0 if _fails == 0 else 1)


func _length(map: RID, a: Vector3, b: Vector3) -> float:
	var p := NavigationServer3D.map_get_path(map, NavigationServer3D.map_get_closest_point(map, a),
		NavigationServer3D.map_get_closest_point(map, b), true)
	var l := 0.0
	for k in range(1, p.size()):
		l += p[k].distance_to(p[k - 1])
	return l


func _walk(map: RID, id: String, to: Vector3) -> void:
	var from := NavigationServer3D.map_get_closest_point(map, _level.player_spawn)
	var near := NavigationServer3D.map_get_closest_point(map, to)
	var path := NavigationServer3D.map_get_path(map, from, near, true)
	var on := Vector2(near.x - to.x, near.z - to.z).length() < 1.5 and absf(near.y - to.y) < 0.7
	var reached := path.size() > 1 and path[path.size() - 1].distance_to(near) < 1.0
	var l := 0.0
	for k in range(1, path.size()):
		l += path[k].distance_to(path[k - 1])
	_check(on and reached, "%-15s at %s: %s, walk %.0f m (%.0f s)" % [id, to.snapped(Vector3.ONE * 0.1),
		("on the navmesh" if on else "OFF the navmesh (%s)" % near.snapped(Vector3.ONE * 0.1)) + ("" if reached else ", NOT reached"),
		l, l / Player.WALK])
