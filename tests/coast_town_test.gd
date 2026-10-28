extends Node3D
## The coast fishing town (CoastTown, gameplan/route_stops_plan.md stage 1), walked: it builds,
## every spot stands on the navmesh and can be walked to from the arrival on the shore road, and
## how long each walk is (at 4 m/s); every crowd point is on the navmesh, and CampJobs finds every
## job its spot round the beach camp. Windowed, it also saves an overview and street views, each
## with its frame rate (vsync off, so it is the headroom).
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
	"beach_camp": [Vector3(-26, 2.2, 346), Vector3(0, 0.5, 328)],
	"camp_from_dune": [Vector3(20, 4.2, 330), Vector3(-30, 0.0, 330)],
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
	_crowd_points(map, "coast_town")
	_camp_jobs()
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


## Every point in the place's crowd data on the navmesh: where people walk, stand and sit, and
## both ends of each animal's beat.
func _crowd_points(map: RID, place: String) -> void:
	var d := Crowd.load_data(place)
	var bad: Array = []
	var n := 0
	var all: Array = []
	for g: Dictionary in d.get("groups", []):
		for key: String in ["waypoints", "stalls", "seats"]:
			for p: Array in g.get(key, []):
				all.append(["%s %s" % [g.name, key], p])
	for b: Array in d.get("beasts", []):
		all.append(["beast", b[0]])
		all.append(["beast", b[1]])
	for e: Array in all:
		var p: Array = e[1]
		var at := Vector3(float(p[0]), 0, float(p[1]))
		var q := NavigationServer3D.map_get_closest_point(map, at)
		n += 1
		if Vector2(q.x - at.x, q.z - at.z).length() > 0.8 or absf(q.y) > 0.6:
			bad.append("%s %s" % [e[0], at])
	_check(bad.is_empty(), "%s crowd: %d points, all on the navmesh%s" % [place, n, "" if bad.is_empty() else "; OFF: %s" % [bad]])
	var crowd := _level.get_node_or_null("Crowd") as Crowd
	if crowd:
		print("RESULT %s crowd: %d people, %d beasts" % [place, crowd.people.size(), crowd.beasts.size()])


## CampJobs round the beach camp's fire: every job gets its spot at about its distance (the scout
## up on the dune), no two within 1.6 m; four seats at the fire.
func _camp_jobs() -> void:
	var h := CampJobs.host(_level)
	h.jobs.clear()
	h.anchor = _level.camp.anchor
	for kind: String in CampJobs.KINDS:
		for s in (4 if kind == "fire" else 1):
			var j: Dictionary = h._camp_job(kind, s if kind == "fire" else -1)
			if j.is_empty():
				_check(false, "beach camp: no spot for %s" % kind)
				continue
			j.g = null  # (CampJobs' _process skips a job without its Gunman)
			h.jobs["%s_%d" % [kind, s]] = j
			var spot: Vector3 = j.spot
			var d := Vector2(spot.x - h.anchor.x, spot.z - h.anchor.z).length()
			var r := float(CampJobs.KINDS[kind].r)
			_check(spot.y > h.anchor.y + 0.6 if kind == "scout" else absf(d - r) <= 2.5,
				"beach camp: %-9s at %.1f m (wants %.1f)%s" % [kind, d, r, " up %.1f m" % (spot.y - h.anchor.y) if kind == "scout" else ""])
	h.jobs.clear()
