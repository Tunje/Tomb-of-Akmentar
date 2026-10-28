extends Node3D
## The desert night camp (DesertCamp, gameplan/route_stops_plan.md stage 1), walked: two camps on a
## flat test ground (one turned), every place in each on the navmesh and walkable from the way in,
## and CampJobs finding every job its own spot round the fire at its distance (the crest up on the
## knoll). Windowed, at night: an overview and views round the camp, each with its frame rate
## (vsync off, so it is the headroom).
##   godot --headless --path . res://tests/desert_camp_test.tscn -- --ci
##   godot --path . res://tests/desert_camp_test.tscn -- --shot-dir=C:/path

## A bare level: sand to the horizon, night.
class Host extends Level:
	var camps: Array[DesertCamp] = []

	func _ready() -> void:
		_make_materials()
		_nav = NavigationRegion3D.new()
		_nav.navigation_mesh = Level.nav_mesh()
		add_child(_nav)
		_box(_nav, Vector3(100, -0.5, 0), Vector3(340, 1.0, 160), _sand)
		camps.append(DesertCamp.build(self, Vector3.ZERO, 0.0))
		camps.append(DesertCamp.build(self, Vector3(200, 0, 0), 2.3))
		_environment()
		_sun.rotation = Vector3(deg_to_rad(-40), deg_to_rad(-60), 0)  # the moon
		_sun.light_color = Color(0.55, 0.65, 0.9)
		_sun.light_energy = 0.12
		var sky := _env.sky.sky_material as ProceduralSkyMaterial
		sky.sky_top_color = Color(0.02, 0.03, 0.08)
		sky.sky_horizon_color = Color(0.08, 0.08, 0.14)
		sky.ground_horizon_color = Color(0.06, 0.05, 0.06)
		sky.ground_bottom_color = Color(0.03, 0.03, 0.03)
		_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		_env.ambient_light_color = Color(0.1, 0.12, 0.2)
		_env.ambient_light_energy = 0.6
		_env.fog_enabled = false
		_nav.bake_navigation_mesh(false)
		player_spawn = camps[0].spots.gate


const VIEWS := {
	"overview": [Vector3(10, 34, 46), Vector3(2, 0, -4)],
	"by_the_fire": [Vector3(3, 1.7, 9), Vector3(0, 1.2, -8)],
	"from_the_spring": [Vector3(-9, 1.7, 2), Vector3(8, 1.0, 2)],
	"from_the_lookout": [Vector3(20, 3.5, -17), Vector3(0, 0.0, 2)],
	"way_in": [Vector3(0, 1.7, 22), Vector3(0, 1.5, -6)],
	"turned_overview": [Vector3(200, 34, 46), Vector3(200, 0, 0)],
}

var _level: Host
var _fails := 0
var _dir := "user://desert_camp"


func _ready() -> void:
	get_window().set_flag(Window.FLAG_NO_FOCUS, true)
	_dir = str(TestDriver.parse_args().get("shot-dir", _dir))
	DirAccess.make_dir_recursive_absolute(_dir)
	var t0 := Time.get_ticks_msec()
	_level = Host.new()
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
		if NavigationServer3D.map_get_closest_point(map, _level.player_spawn) != Vector3.ZERO:
			break
		await get_tree().physics_frame
	print("RESULT the map synced in %d ms, navmesh %d polygons" % [Time.get_ticks_msec() - t0, _level._nav.navigation_mesh.get_polygon_count()])
	for n in _level.camps.size():
		_walk(map, _level.camps[n], "camp %d (yaw %.1f)" % [n, _level.camps[n].yaw])
		_jobs(_level.camps[n], "camp %d" % n)
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
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
			print("RESULT fps %-17s %.0f (draw calls %d)" % [name, 60.0e6 / float(Time.get_ticks_usec() - f0),
				RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)])
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(_dir.path_join("desert_camp_%s.png" % name))
	print("RESULT desert_camp_test %s (%d failed)" % ["PASS" if _fails == 0 else "FAIL", _fails])
	get_tree().quit(0 if _fails == 0 else 1)


## Every place in the camp on the navmesh and walkable from the way in.
func _walk(map: RID, camp: DesertCamp, what: String) -> void:
	var from := NavigationServer3D.map_get_closest_point(map, camp.spots.gate)
	var places := {"fire": camp.anchor, "spring": camp.spots.spring, "shelter": camp.spots.shelter, "lookout": camp.spots.lookout}
	for k in (camp.spots.beds as Array).size():
		places["bed %d" % k] = camp.spots.beds[k]
	for k in (camp.spots.picket as Array).size():
		places["picket %d" % k] = camp.spots.picket[k]
	for id: String in places:
		var to: Vector3 = places[id]
		var near := NavigationServer3D.map_get_closest_point(map, to)
		var path := NavigationServer3D.map_get_path(map, from, near, true)
		var on := Vector2(near.x - to.x, near.z - to.z).length() < 1.0 and absf(near.y - to.y) < 0.6
		var reached := path.size() > 1 and path[path.size() - 1].distance_to(near) < 0.5
		_check(on and reached, "%s: %-9s %s" % [what, id, "on the navmesh, walkable" if on and reached
			else "near %s, reached %s" % [near.snapped(Vector3.ONE * 0.1), reached]])


## CampJobs round this camp's fire: every job gets its spot, at about its distance (the scout up
## on the knoll), no two within 1.6 m; four seats at the fire.
func _jobs(camp: DesertCamp, what: String) -> void:
	var h := CampJobs.host(_level)
	h.jobs.clear()
	h.anchor = camp.anchor
	for kind: String in CampJobs.KINDS:
		var seats := 4 if kind == "fire" else 1
		for s in seats:
			var j: Dictionary = h._camp_job(kind, s if kind == "fire" else -1)
			if j.is_empty():
				_check(false, "%s: no spot for %s" % [what, kind])
				continue
			j.g = null  # (CampJobs' _process skips a job without its Gunman)
			h.jobs["%s_%d" % [kind, s]] = j
			var spot: Vector3 = j.spot
			var d := Vector2(spot.x - camp.anchor.x, spot.z - camp.anchor.z).length()
			var r := float(CampJobs.KINDS[kind].r)
			var ok := absf(d - r) <= 2.5
			if kind == "scout":
				ok = spot.y > camp.anchor.y + 0.6
			_check(ok, "%s: %-9s at %.1f m (wants %.1f)%s" % [what, kind, d, r, " up %.1f m" % (spot.y - camp.anchor.y) if kind == "scout" else ""])
	h.jobs.clear()
