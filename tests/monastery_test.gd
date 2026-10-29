extends Node3D
## Act 6's night stop, the ruined monastery (Monastery in MonasteryNight; gameplan/act6_camp_options.md):
##   every place on the navmesh and walkable from the way in (the fire, the well, the keep's roof
##   up its ramp, the church and refectory doors, the picket, the truck's place, the beds, both
##   breaches, the graves out through the east breach);
##   CampJobs finding every job its spot round the fire at its distance, the scout up on the keep;
##   every servant's way in (the points out in the dark, the graves) has a path to the fire, and
##   they come by three ways and the cemetery;
##   windowed, at night: views and shots, each with its frame rate (vsync off).
##   godot --headless --path . res://tests/monastery_test.tscn
##   godot --path . res://tests/monastery_test.tscn -- --shot-dir=C:/path

const VIEWS := {
	"overview": [Vector3(30, 60, 85), Vector3(8, 0, -2)],
	"by_the_fire": [Vector3(4, 1.7, 9), Vector3(-6, 1.5, -12)],
	"the_keep": [Vector3(-2, 1.8, 4), Vector3(19, 4.5, -8)],
	"from_the_keep": [Vector3(19, 6.8, -6), Vector3(-4, 0.5, 6)],
	"gate_in": [Vector3(0, 1.7, 40), Vector3(0, 2.0, 0)],
	"east_breach": [Vector3(46, 1.7, -2), Vector3(26, 1.5, -8)],
	"north_breach": [Vector3(10, 1.7, -40), Vector3(10, 1.5, -10)],
}

var _level: MonasteryNight
var _fails := 0
var _dir := "user://monastery"


func _ready() -> void:
	get_window().set_flag(Window.FLAG_NO_FOCUS, true)
	_dir = str(TestDriver.parse_args().get("shot-dir", _dir))
	DirAccess.make_dir_recursive_absolute(_dir)
	var t0 := Time.get_ticks_msec()
	_level = MonasteryNight.new()
	add_child(_level)
	var nc: Dictionary = NavCache.last.get("monastery_night", {})
	print("RESULT info build_ms %d (navmesh %s in %d ms)" % [Time.get_ticks_msec() - t0, nc.get("from", "?"), int(nc.get("ms", -1))])
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print("RESULT %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_fails += 1


func _run() -> void:
	var map := get_world_3d().navigation_map
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 30000:
		if NavigationServer3D.map_get_iteration_id(map) > 0 and NavigationServer3D.map_get_closest_point(map, _level.player_spawn) != Vector3.ZERO:
			break
		await get_tree().physics_frame
	await get_tree().physics_frame
	var m := _level.monastery
	print("RESULT info the map synced in %d ms, navmesh %d polygons" % [Time.get_ticks_msec() - t0, _level._nav.navigation_mesh.get_polygon_count()])
	_walk(map, m)
	_jobs(m)
	_ways(map, m)
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.max_fps = 0
		var cam := Camera3D.new()
		cam.far = 800.0
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
			print("RESULT fps %-13s %.0f (draw calls %d)" % [name, 60.0e6 / float(Time.get_ticks_usec() - f0),
				RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)])
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(_dir.path_join("monastery_%s.png" % name))
	print("RESULT monastery_test %s fails=%d" % ["PASS" if _fails == 0 else "FAIL", _fails])
	get_tree().quit(0 if _fails == 0 else 1)


## A path's length from `a` to `b` on the navmesh (`b` must be on it, within 1 m), or -1.
func _path(map: RID, a: Vector3, b: Vector3) -> float:
	var from := NavigationServer3D.map_get_closest_point(map, a)
	var to := NavigationServer3D.map_get_closest_point(map, b)
	if Vector2(to.x - b.x, to.z - b.z).length() > 1.0 or absf(to.y - b.y) > 0.8:
		return -1.0
	var p := NavigationServer3D.map_get_path(map, from, to, true)
	if p.size() < 2 or p[-1].distance_to(to) > 0.5:
		return -1.0
	var len := 0.0
	for i in p.size() - 1:
		len += p[i].distance_to(p[i + 1])
	return len


## Every place on the navmesh and walkable from the way in.
func _walk(map: RID, m: Monastery) -> void:
	var places := {"fire": m.anchor, "well": m.spots.well, "keep roof": m.spots.keep_roof, "church door": m.spots.church_door,
		"refectory door": m.spots.refectory_door, "truck": m.spots.truck, "gate (inside)": m.spots.gate,
		"north breach": m.spots.breach_north, "east breach": m.spots.breach_east}
	for k in (m.spots.picket as Array).size():
		places["picket %d" % k] = m.spots.picket[k]
	for k in (m.spots.beds as Array).size():
		places["bed %d" % k] = m.spots.beds[k]
	var graves: Array = m.spots.graves
	for k in range(0, graves.size(), 4):
		places["grave %d" % k] = graves[k]
	for id: String in places:
		var len := _path(map, m.spots.gate_out, places[id])
		_check(len > 0.0, "walk: %-15s %s" % [id, "%.0f m from the way in" % len if len > 0.0 else "NOT reached (%s)" % (places[id] as Vector3).snapped(Vector3.ONE * 0.1)])


## CampJobs round the fire: every job gets its spot, at about its distance (the scout up high: the
## keep's roof); four seats at the fire.
func _jobs(m: Monastery) -> void:
	var h := CampJobs.host(_level)
	h.jobs.clear()
	h.anchor = m.anchor
	for kind: String in CampJobs.KINDS:
		var seats := 4 if kind == "fire" else 1
		for s in seats:
			var j: Dictionary = h._camp_job(kind, s if kind == "fire" else -1)
			if j.is_empty():
				_check(false, "jobs: no spot for %s" % kind)
				continue
			j.g = null
			h.jobs["%s_%d" % [kind, s]] = j
			var spot: Vector3 = j.spot
			var d := Vector2(spot.x - m.anchor.x, spot.z - m.anchor.z).length()
			var r := float(CampJobs.KINDS[kind].r)
			var ok := absf(d - r) <= 2.5
			if kind == "scout":
				ok = spot.y > m.anchor.y + 4.0
			_check(ok, "jobs: %-9s at %.1f m (wants %.1f)%s" % [kind, d, r, " up %.1f m (the keep)" % (spot.y - m.anchor.y) if kind == "scout" else ""])
	h.jobs.clear()


## Every way the servants come has a path to the fire: from the dark past each gap, and the graves.
func _ways(map: RID, m: Monastery) -> void:
	var ways: Dictionary = m.spots.ways
	_check(ways.keys().size() == 3, "ways: three ways in (%s) and the cemetery" % ", ".join(ways.keys()))
	for id: String in ways:
		for p: Vector3 in ways[id]:
			var len := _path(map, p, m.anchor)
			_check(len > 0.0, "ways: %-5s from %s to the fire: %s" % [id, p.snapped(Vector3.ONE), "%.0f m" % len if len > 0.0 else "NO PATH"])
	for id: String in m.spots.mouths:
		var p: Vector3 = m.spots.mouths[id]
		var len := _path(map, p, m.anchor)
		_check(len > 0.0, "ways: %-5s mouth %s to the fire: %s" % [id, p.snapped(Vector3.ONE), "%.0f m" % len if len > 0.0 else "NO PATH"])
	var bad := 0
	for g: Vector3 in m.spots.graves:
		if _path(map, g, m.anchor) <= 0.0:
			bad += 1
	_check(bad == 0, "ways: all %d graves have a path to the fire (%d not)" % [(m.spots.graves as Array).size(), bad])
