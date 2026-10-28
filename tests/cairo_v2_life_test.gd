extends Node3D
## -f9's life on Cairo v2 (-7f's CairoV2, stage 1): the interiors against the moved buildings, the
## crowd per district (crowd/cairo_v2.json), the ambient life, the souk's murmur. Builds them
## itself (and re-bakes) where CairoV2 doesn't yet.
##   checks   every room spot (the café, Freddie's office) reachable from the start; every crowd
##            waypoint on the navmesh; each district's people there; stalls and seats taken;
##            nobody from the street indoors; pigeons and kites; the souk murmuring
## --perf[=off]  instead: a frame rate on a walk through the Boulevard, the mosque square and the
##               souk (windowed): with the life, or CairoV2 bare; --freeze=both (the crowd's own
##               cost: on minus this); --seconds=N --shots=t1,.. --cam=<view> --shot-dir=path
## Never takes focus or captures the mouse.

const CAMS := {
	"souk": [Vector3(152, 1.8, 135), Vector3(180, 1.2, 135)],
	"boulevard": [Vector3(96, 2.0, 62), Vector3(130, 1.2, 62)],
	"mosque": [Vector3(146, 2.2, 108), Vector3(124, 2.0, 132)],
	"quay": [Vector3(218, 2.2, 90), Vector3(220, 1.0, 140)],
	"tavern": [Vector3(103, 1.8, 120), Vector3(92, 1.0, 130)],
	"club": [Vector3(158, 1.7, 63.6), Vector3(158, 0.6, 72.0)],
}

var level: Node3D
var player: Player
var args := {}
var crowd: Crowd
var ints: CairoInteriors
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
	Crowd.debug_freeze = str(args.get("freeze", ""))
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.max_fps = 0
	for s in str(args.get("shots", "")).split(",", false):
		_shots.append(float(s))
	level = CairoV2.new()
	add_child(level)
	if str(args.get("perf", "")) != "off":
		_life()
	player = Player.new()
	add_child(player)
	player.global_position = level.player_spawn
	player.set_armed(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	for k in 30:
		await get_tree().physics_frame
	if args.has("cam"):
		var c: Array = CAMS.get(str(args.cam), CAMS.souk)
		var cam := Camera3D.new()
		add_child(cam)
		cam.look_at_from_position(c[0], c[1])
		cam.make_current()
	if args.has("perf") or args.has("look"):
		_perf = true
		await _walk(float(args.get("seconds", "40")))
	else:
		_rooms()
		_waypoints()
		await _districts()
	print("RESULT cairo_v2_life_test %s fails=%d" % ["PASS" if _fails == 0 else "FAIL", _fails])
	get_tree().quit(0 if _fails == 0 else 1)


## The life onto CairoV2 where it doesn't do it itself yet: the interiors (then a re-bake), their
## spots, the crowd.
func _life() -> void:
	ints = level.get("interiors") as CairoInteriors if "interiors" in level else null
	if ints == null:
		ints = CairoInteriors.build(level)
		level.set("interiors", ints)
		(level.get("_nav") as NavigationRegion3D).bake_navigation_mesh(false)
		var spots: Dictionary = level.get("spots")
		for id in ints.room_spots:
			spots[id] = ints.room_spots[id]
		print("RESULT info CairoV2 has no interiors yet: built here, re-baked")
	crowd = level.get("crowd") as Crowd if "crowd" in level else null
	if crowd == null:
		crowd = Crowd.populate(level, "cairo_v2")
		level.set("crowd", crowd)
		print("RESULT info CairoV2 has no crowd yet: populated here")


func _rooms() -> void:
	_check(ints != null and ints.rooms.size() == 10, "rooms: %d built against the moved buildings" % (ints.rooms.size() if ints else 0))
	if ints == null:
		return
	var map := get_world_3d().navigation_map
	var from := NavigationServer3D.map_get_closest_point(map, level.player_spawn)
	var bad := []
	for id in ints.room_spots:
		var spot: Vector3 = ints.room_spots[id]
		var path := NavigationServer3D.map_get_path(map, from, spot, true)
		if path.size() < 2 or Vector2(path[-1].x - spot.x, path[-1].z - spot.z).length() > 0.6:
			bad.append(id)
	_check(bad.is_empty(), "rooms: every room spot reachable from the start (the café, Freddie's office...) (not: %s)" % str(bad))
	var seated := 0
	for id in ["karim", "idris", "isabelle", "clara", "archivist", "hargreaves"]:
		if not ints.seat_at(ints.room_people[id][0]).is_empty():
			seated += 1
	_check(seated == 6, "rooms: the seated hosts' chairs moved with them (%d of 6)" % seated)


func _waypoints() -> void:
	if crowd == null:
		return
	var map := get_world_3d().navigation_map
	var bad := []
	var total := 0
	for g: Dictionary in crowd.groups:
		if g.indoor:
			continue
		for w: Vector3 in g.waypoints:
			total += 1
			var q := NavigationServer3D.map_get_closest_point(map, w)
			if Vector2(q.x - w.x, q.z - w.z).length() > 0.6:
				bad.append("%s %s" % [g.name, Vector2(w.x, w.z)])
	_check(bad.is_empty(), "crowd: all %d waypoints on the navmesh (off: %s)" % [total, str(bad)])


func _districts() -> void:
	if crowd == null:
		return
	var by := {}
	for p in crowd.people:
		by[p.group.name] = int(by.get(p.group.name, 0)) + 1
	print("RESULT info crowd by district: %s (%d people)" % [str(by), crowd.people.size()])
	_check(by.get("souk", 0) >= by.get("boulevard", 0) and by.get("quay", 0) >= 2 and by.get("mosque", 0) >= 2, "crowd: the souk busiest, porters on the quay, worshippers at the mosque")
	var life := level.find_children("AmbientLife", "", true, false)
	_check(not life.is_empty() and (life[0] as AmbientLife).pigeons.size() >= 14 and (life[0] as AmbientLife).birds.size() == 6, "life: pigeons in the squares, kites over the Nile")
	Engine.time_scale = 3.0
	var strays := {}
	var murmur := 0
	for k in 30:
		await get_tree().create_timer(1.5).timeout
		player.global_position = Vector3(160 + 10 * sin(k * 0.4), 0.1, 135)  # in the souk lane
		for p in crowd.people:
			var room := ints.room_at(p.global_position) if ints else ""
			if room != "" and str(p.group.name) != "patrons":
				strays[p.name] = room
		murmur = maxi(murmur, crowd._murmurs.filter(func(m: AudioStreamPlayer3D) -> bool: return m.playing and not m.stream_paused).size())
	Engine.time_scale = 1.0
	var at_stalls := crowd.people.filter(func(p: CrowdPerson) -> bool: return p.state == "stall").size()
	_check(at_stalls >= 3, "crowd: %d at the souk's stalls and before the mosque" % at_stalls)
	_check(strays.is_empty(), "crowd: nobody from the street indoors (%s)" % str(strays))
	_check(murmur >= 1, "sound: the souk murmurs (%d loops)" % murmur)


## The frame-rate walk: the Boulevard east, down the Old Street, across the mosque square, along
## the souk lane to the corniche.
func _walk(secs: float) -> void:
	var pts := [Vector3(100, 0.1, 62), Vector3(150, 0.1, 62), Vector3(100, 0.1, 64), Vector3(100, 0.1, 108),
		Vector3(140, 0.1, 112), Vector3(150, 0.1, 135), Vector3(200, 0.1, 135), Vector3(218, 0.1, 120)]
	var t := 0.0
	while t < secs:
		var f := fmod(t / secs * (pts.size() - 1), float(pts.size() - 1))
		var i := int(f)
		player.global_position = (pts[i] as Vector3).lerp(pts[mini(i + 1, pts.size() - 1)], f - i)
		await get_tree().process_frame
		t += get_process_delta_time()


func _process(delta: float) -> void:
	_t += delta
	if _perf and _t > 4.0:
		_frames.append(delta * 1000.0)
	if _shots.size() > 0 and _t >= _shots[0]:
		_shots.pop_front()
		_shot("cairo_v2_%s_%s_%04.1f.png" % [str(args.get("cam", "walk")), str(args.get("perf", "on")), _t])


func _exit_tree() -> void:
	Crowd.debug_freeze = ""
	if _frames.size() > 10:
		var s := _frames.duplicate()
		s.sort()
		var mean := 0.0
		for f in s:
			mean += f
		mean /= s.size()
		print("PERFSUM frames=%d mean_ms=%.2f (%.0f fps) p95_ms=%.1f" % [s.size(), mean, 1000.0 / mean, s[int(s.size() * 0.95)]])


func _shot(file: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var dir: String = args.get("shot-dir", "user://cairo_v2_shots")
	DirAccess.make_dir_recursive_absolute(dir)
	get_viewport().get_texture().get_image().save_png(dir.path_join(file))
	print("RESULT shot %s" % dir.path_join(file))


func _check(ok: bool, what: String) -> void:
	print("RESULT %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_fails += 1
