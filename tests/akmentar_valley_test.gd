extends Node3D
## The Akmentar valley blockout (scripts/acts/akmentar_valley.gd, stage 1 of
## gameplan/akmentar_valley_plan.md), walked:
##   every study site reachable from each camp (its SiteSpot's place), with the path's length and
##   the time walking (4 m/s), sprinting (6.6) and at a gallop (10); the door's stair down, the boat
##   landing, the airstrip and our horse spot reachable from our camp; a horse at the spot
## --perf  instead: a frame rate on a walk up the axis from the approach to the door (windowed);
##         --quality=low|medium|high, --seconds=N; --shots=t1,.. --cam=<view> --shot-dir=path
## Never takes focus or captures the mouse.

const CAMS := {
	"axis": [Vector3(0, 3.0, 520), Vector3(0, 22, 0)],
	"facade": [Vector3(0, 24, 92), Vector3(0, 30, 0)],
	"overview": [Vector3(260, 170, 640), Vector3(0, 0, 210)],
	"statues": [Vector3(150, 6, 395), Vector3(200, 4, 290)],
	"gardens": [Vector3(-100, 5, 340), Vector3(-200, 15, 210)],
	"gorge": [Vector3(-110, 2, 455), Vector3(0, -2, 425)],
	"plaza": [Vector3(30, 4, 238), Vector3(0, 6, 150)],
}

var level: AkmentarValley
var player: Player
var args := {}
var _fails := 0
var _t := 0.0
var _frames: Array[float] = []
var _shots: Array[float] = []
var _perf := false


func _ready() -> void:
	get_window().set_flag(Window.FLAG_NO_FOCUS, true)
	args = TestDriver.parse_args()
	Controls.setup()
	Settings.ensure(get_tree())
	if args.has("quality"):
		Settings.set_value("quality", str(args.quality), get_tree())
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.max_fps = 0
	for s in str(args.get("shots", "")).split(",", false):
		_shots.append(float(s))
	var t0 := Time.get_ticks_msec()
	level = AkmentarValley.new()
	add_child(level)
	var nc: Dictionary = NavCache.last.get("akmentar_valley", {})
	print("RESULT info valley built in %d ms (its navmesh %s in %d ms)" % [Time.get_ticks_msec() - t0, nc.get("from", "?"), int(nc.get("ms", -1))])
	player = Player.new()
	add_child(player)
	player.global_position = level.player_spawn
	player.set_armed(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var map := get_world_3d().navigation_map
	var w := 0
	# (The first sync can be empty: wait until it answers with a point.)
	var probe: Vector3 = AkmentarValley.VALLEY_CAMPS.party + Vector3(0, 0, 4)
	while (NavigationServer3D.map_get_iteration_id(map) == 0 or NavigationServer3D.map_get_closest_point(map, probe) == Vector3.ZERO) and w < 600:
		await get_tree().physics_frame
		w += 1
	await get_tree().physics_frame
	var nav: NavigationRegion3D = level.get("_nav")
	var c0: Vector3 = AkmentarValley.VALLEY_CAMPS.party + Vector3(0, 0, 4)
	var cq := NavigationServer3D.map_get_closest_point(map, c0)
	var sq := NavigationServer3D.map_get_closest_point(map, Vector3(-14, 0, 241))
	print("RESULT info navmesh: %d polygons, map iteration %d (waited %d frames); camp's closest %s, horus' %s; path %d points" % [nav.navigation_mesh.get_polygon_count(),
		NavigationServer3D.map_get_iteration_id(map), w, cq, sq, NavigationServer3D.map_get_path(map, cq, sq, true).size()])
	if args.has("cam"):
		var c: Array = CAMS.get(str(args.cam), CAMS.axis)
		var cam := Camera3D.new()
		add_child(cam)
		cam.far = 2000.0
		cam.look_at_from_position(c[0], c[1])
		cam.make_current()
	if args.has("perf") or args.has("look"):
		_perf = true
		await _walk(float(args.get("seconds", "40")))
	else:
		_sites()
		_places()
		await _horse()
	print("RESULT akmentar_valley_test %s fails=%d" % ["PASS" if _fails == 0 else "FAIL", _fails])
	get_tree().quit(0 if _fails == 0 else 1)


## A path's length from `a` to `b` on the navmesh, or -1 if it doesn't get there (within 1 m).
func _path_len(a: Vector3, b: Vector3) -> float:
	var map := get_world_3d().navigation_map
	var from := NavigationServer3D.map_get_closest_point(map, a)
	var to := NavigationServer3D.map_get_closest_point(map, b)
	if Vector2(to.x - b.x, to.z - b.z).length() > 1.0:
		return -1.0
	var path := NavigationServer3D.map_get_path(map, from, to, true)
	if path.size() < 2 or path[-1].distance_to(to) > 1.0:
		return -1.0
	var len := 0.0
	for i in path.size() - 1:
		len += path[i].distance_to(path[i + 1])
	return len


func _sites() -> void:
	var bad := []
	var table := "RESULT info site            ours          americans     germans   (m, walk / gallop s)\n"
	var near := {}
	for id: String in AkmentarValley.VALLEY_SITES:
		var spot := level.site_spot(id)
		var row := "RESULT info %-14s" % id
		var best := ""
		var best_len := INF
		for camp: String in ["party", "americans", "germans"]:
			var c: Vector3 = AkmentarValley.VALLEY_CAMPS[camp] + Vector3(0, 0, 4)
			var len := _path_len(c, spot)
			if len < 0.0:
				bad.append("%s from %s" % [id, camp])
				row += "  unreachable "
				continue
			row += "  %4.0f %3.0f/%2.0f" % [len, len / 4.0, len / 10.0]
			if len < best_len:
				best_len = len
				best = camp
		near[best] = int(near.get(best, 0)) + 1
		table += row + "\n"
	print(table)
	print("RESULT info nearest camp per site: %s" % str(near))
	_check(bad.is_empty(), "sites: all 12 reachable from all 3 camps (not: %s)" % str(bad))
	_check(near.size() == 3, "sites: each camp is nearest to some (the claim race): %s" % str(near))


func _places() -> void:
	var ours: Vector3 = AkmentarValley.VALLEY_CAMPS.party + Vector3(0, 0, 4)
	if args.has("probe"):
		var map := get_world_3d().navigation_map
		for q: Vector3 in [Vector3(144, 0, 250), Vector3(144, 17, 196), Vector3(144, 34, 136), Vector3(146, 35, 131), Vector3(160, 35, 120), Vector3(205, 35, 90)]:
			print("RESULT info probe %s: closest %s, path %.0f" % [q, NavigationServer3D.map_get_closest_point(map, q), _path_len(ours, q)])
	for p: Array in [["the door's stair down", level.stair_down], ["the boat landing", level.boat_landing],
			["the airstrip", level.airstrip], ["our horse spot", level.horse_spot + Vector3(0, 0, 1.5)]]:
		var len := _path_len(ours, p[1])
		_check(len > 0.0, "places: %s reachable from our camp (%.0f m, %.0f s walking, %.0f at a gallop)" % [p[0], len, len / 4.0, len / 10.0])
	var axis := _path_len(Vector3(0, 0, 520), Vector3(0, AkmentarValley.TERRACE_Y, 4))
	_check(axis > 0.0, "places: the approach to the Golden Facade: %.0f m, %.0f s walking, %.0f s sprinting, %.0f s at a gallop" % [axis, axis / 4.0, axis / 6.6, axis / 10.0])


func _horse() -> void:
	var h := Horse.make(level, "valley_test", level.horse_spot + Vector3(0, 0.1, 1.5), "", false)
	await get_tree().create_timer(0.5).timeout
	_check(is_instance_valid(h) and h.is_inside_tree(), "horse: one at our camp's rail, to ride between the sites")


## The frame-rate walk: up the axis from the approach to the door, the camera following.
func _walk(secs: float) -> void:
	var pts := [Vector3(0, 0.1, 520), Vector3(0, 0.1, 384), Vector3(0, 0.1, 250), Vector3(0, 0.1, 140),
		Vector3(0, 0.1, 119), Vector3(0, AkmentarValley.TERRACE_Y + 0.1, 68), Vector3(0, AkmentarValley.TERRACE_Y + 0.1, 6)]
	var t := 0.0
	while t < secs:
		var f := fmod(t / secs * (pts.size() - 1), float(pts.size() - 1))
		var i := int(f)
		player.global_position = (pts[i] as Vector3).lerp(pts[mini(i + 1, pts.size() - 1)], f - i)
		player.yaw = 0.0
		await get_tree().process_frame
		t += get_process_delta_time()


func _process(delta: float) -> void:
	_t += delta
	if _perf and _t > 4.0:
		_frames.append(delta * 1000.0)
	if _shots.size() > 0 and _t >= _shots[0]:
		_shots.pop_front()
		_shot("valley_%s_%04.1f.png" % [str(args.get("cam", "walk")), _t])


func _exit_tree() -> void:
	if _frames.size() > 10:
		var s := _frames.duplicate()
		s.sort()
		var mean := 0.0
		for f in s:
			mean += f
		mean /= s.size()
		print("PERFSUM frames=%d mean_ms=%.2f (%.0f fps) p95_ms=%.1f draws=%d" % [s.size(), mean, 1000.0 / mean, s[int(s.size() * 0.95)],
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)])


func _shot(file: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var dir: String = args.get("shot-dir", "user://valley_shots")
	DirAccess.make_dir_recursive_absolute(dir)
	get_viewport().get_texture().get_image().save_png(dir.path_join(file))
	print("RESULT shot %s" % dir.path_join(file))


func _check(ok: bool, what: String) -> void:
	print("RESULT %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_fails += 1
