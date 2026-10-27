extends Node3D
## Cairo's interiors (scripts/sites/cairo_interiors.gd). Builds them itself (and re-bakes the
## navmesh) if Cairo's hook isn't in yet.
##   rooms    every room: its doorway open, its walls closed, a walkable path in from the street
##            to its talk spot, its lights unshadowed (and few)
##   seats    the seated hosts' chairs are found; an Npc put there sits down, facing the chair's way
##   crowd    (with the hook) the bar's patrons are seated inside; nobody from the street comes in
## --perf[=off]  instead: frame rate on a walk past the venues (windowed), with the interiors or
##               without (CairoInteriors.disabled); --seconds=N, --shots=t1,..., --cam=<venue>
##               (a view in through its door), --shot-dir=path
## Never takes focus or captures the mouse.

## A view in through each door: [camera, look at].
const CAMS := {
	"bar": [Vector3(28.5, 1.7, 66.0), Vector3(18.0, 1.0, 65.0)],
	"cafe": [Vector3(25.0, 1.7, 63.0), Vector3(20.0, 0.8, 70.0)],
	"lobby": [Vector3(47.5, 1.7, 45.0), Vector3(46.0, 1.2, 38.0)],
	"museum_hall": [Vector3(92.0, 2.2, 25.0), Vector3(92.0, 1.6, 14.0)],
	"museum_office": [Vector3(92.0, 2.0, 11.4), Vector3(92.0, 0.8, 7.0)],
	"outfitter": [Vector3(45.0, 1.7, 54.8), Vector3(45.0, 1.0, 61.0)],
	"telegraph": [Vector3(71.2, 1.7, 9.0), Vector3(65.0, 1.0, 9.0)],
	"club": [Vector3(63.0, 1.7, 54.8), Vector3(66.0, 0.8, 61.0)],
	"freddie_office": [Vector3(58.15, 1.7, 54.6), Vector3(58.0, 0.6, 61.0)],
	"gunsmith": [Vector3(32.6, 1.7, 61.0), Vector3(39.0, 1.2, 61.0)],
	"dealer": [Vector3(40.0, 1.7, 80.5), Vector3(40.0, 1.0, 87.0)],
}
## Each room's talk spot (CairoInteriors.ROOM_SPOTS id), for the walk in.
const ROOM_SPOT := {"bar": "tavern", "lobby": "hotel", "museum_hall": "museum", "museum_office": "museum",
	"outfitter": "outfitter", "telegraph": "telegraph", "club": "club", "freddie_office": "freddie",
	"gunsmith": "gunsmith", "dealer": "dealer"}

var level: Cairo
var player: Player
var ints: CairoInteriors
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
	var off := str(args.get("perf", "")) == "off"
	CairoInteriors.disabled = off
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.max_fps = 0
	for s in str(args.get("shots", "")).split(",", false):
		_shots.append(float(s))
	level = Cairo.new()
	add_child(level)
	ints = level.get("interiors") as CairoInteriors if "interiors" in level else null
	if ints == null and not off:
		ints = CairoInteriors.build(level)
		(level.get("_nav") as NavigationRegion3D).bake_navigation_mesh(false)
		print("RESULT info no hook in cairo.gd yet: built here, navmesh re-baked")
	player = Player.new()
	add_child(player)
	player.global_position = level.player_spawn
	player.set_armed(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().create_timer(0.5).timeout
	if args.has("cam"):
		var c: Array = CAMS.get(str(args.cam), CAMS.bar)
		var cam := Camera3D.new()
		add_child(cam)
		cam.look_at_from_position(c[0], c[1])
		cam.make_current()
		cam.fov = 70.0
	if args.has("perf") or args.has("look"):
		_perf = true
		await _walk(float(args.get("seconds", "30")))
	else:
		_rooms()
		await _seats()
		await _crowd()
	print("RESULT interiors_test %s fails=%d" % ["PASS" if _fails == 0 else "FAIL", _fails])
	get_tree().quit(0 if _fails == 0 else 1)


func _rooms() -> void:
	_check(ints != null and ints.rooms.size() == 10, "rooms: %d built" % (ints.rooms.size() if ints else 0))
	if ints == null:
		return
	var space := get_world_3d().direct_space_state
	var map := get_world_3d().navigation_map
	for v: Dictionary in CairoInteriors.VENUES:
		var d: Array = v.doors[0]
		var at: Vector3 = d[0]
		var n := Vector3((d[1] as Vector2).x, 0, (d[1] as Vector2).y)
		var outside := at + n * 1.5 + Vector3.UP * 1.2
		var through := space.intersect_ray(PhysicsRayQueryParameters3D.create(outside, at - n * 1.0 + Vector3.UP * 1.2, 1))
		_check(through.is_empty(), "%s: its door is open" % v.id)
	for r: Dictionary in ints.rooms:
		var rect: Rect2 = r.rect
		var mid := Vector3(rect.get_center().x, float(r.floor) + 1.5, rect.get_center().y)
		var shut := 0
		for k in 8:
			var a := TAU * k / 8.0
			var far := mid + Vector3(cos(a), 0, sin(a)) * 30.0
			var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(mid, far, 1))
			if hit and rect.grow(0.8).has_point(Vector2((hit.position as Vector3).x, (hit.position as Vector3).z)):
				shut += 1
		_check(shut >= 6, "%s: walled in (%d of 8 rays stop at its walls)" % [r.id, shut])
		var spot: Vector3 = CairoInteriors.ROOM_SPOTS[ROOM_SPOT[r.id]]
		var door := _door_for(str(r.id))
		var path := NavigationServer3D.map_get_path(map, door, spot, true)
		var end_ok := path.size() > 1 and Vector2(path[-1].x - spot.x, path[-1].z - spot.z).length() < 0.6
		_check(end_ok, "%s: a path in from the street to its spot (%d points, ends %s)" % [r.id, path.size(), str(path[-1].snapped(Vector3.ONE * 0.1)) if path.size() > 0 else "-"])
	_check(ints._lights.size() <= ints.rooms.size() * 3 and ints._lights.all(func(l: OmniLight3D) -> bool: return not l.shadow_enabled and l.distance_fade_enabled),
		"lights: %d, none shadowed, all fade with distance" % ints._lights.size())


## The street in front of a room's building's (first) door.
func _door_for(room_id: String) -> Vector3:
	for v: Dictionary in CairoInteriors.VENUES:
		for r: Dictionary in v.rooms:
			if r.id == room_id:
				var d: Array = v.doors[0]
				var n := Vector3((d[1] as Vector2).x, 0, (d[1] as Vector2).y)
				return (d[0] as Vector3) + n * 2.0
	return Vector3.ZERO


func _seats() -> void:
	if ints == null:
		return
	var sat := 0
	for id in ["karim", "idris", "isabelle", "clara", "archivist", "hargreaves"]:
		var p: Vector3 = CairoInteriors.ROOM_PEOPLE[id][0]
		if not ints.seat_at(p).is_empty():
			sat += 1
	_check(sat == 6, "seats: chairs under the 6 seated hosts (%d)" % sat)
	var karim_at: Vector3 = CairoInteriors.ROOM_PEOPLE.karim[0]
	var n := Npc.make(level, "karim", karim_at, "", Characters.glb("karim"))
	await get_tree().process_frame
	await get_tree().process_frame
	var s := ints.seat_at(karim_at)
	_check(n.seated and (n.body == null or n.body.sitting) and is_equal_approx(n.rotation.y, float(s.yaw)), "seats: an Npc put on the café chair sits, facing the table")
	n.face_towards(n.global_position + Vector3(5, 0, 0))
	await get_tree().create_timer(0.5).timeout
	_check(is_equal_approx(n.rotation.y, float(s.yaw)), "seats: and stays facing it when someone talks to him")
	n.queue_free()


func _crowd() -> void:
	var crowd: Crowd = level.get("crowd")
	if crowd == null or not "interiors" in level:
		print("RESULT info crowd: no hook in cairo.gd yet, the patrons aren't checked")
		return
	var patrons := crowd.people.filter(func(p: CrowdPerson) -> bool: return str(p.group.name) == "patrons")
	_check(not patrons.is_empty(), "crowd: patrons in the bar (%d)" % patrons.size())
	Engine.time_scale = 3.0
	var strays := {}
	for k in 40:
		await get_tree().create_timer(1.5).timeout
		for p in crowd.people:
			var room := ints.room_at(p.global_position)
			if room != "" and str(p.group.name) != "patrons":
				strays[p.name] = room
	Engine.time_scale = 1.0
	var seated := patrons.filter(func(p: CrowdPerson) -> bool: return p.state == "sit").size()
	_check(seated >= 1, "crowd: %d patrons seated" % seated)
	_check(strays.is_empty(), "crowd: nobody from the street came in (%s)" % str(strays))


## The frame-rate walk: down the avenue past the hotel and the club, round by the tavern.
func _walk(secs: float) -> void:
	var pts := [Vector3(40, 0.1, 50), Vector3(66, 0.1, 50), Vector3(66, 0.1, 52.5), Vector3(46, 0.1, 52.5),
		Vector3(29, 0.1, 54), Vector3(29, 0.1, 68), Vector3(27.5, 0.1, 66), Vector3(22, 0.1, 66)]
	var t := 0.0
	while t < secs:
		var f := fmod(t / secs * (pts.size() - 1), float(pts.size() - 1))
		var i := int(f)
		player.global_position = (pts[i] as Vector3).lerp(pts[mini(i + 1, pts.size() - 1)], f - i)
		await get_tree().process_frame
		t += get_process_delta_time()


func _process(delta: float) -> void:
	_t += delta
	if _perf and _t > 3.0:
		_frames.append(delta * 1000.0)
	if _shots.size() > 0 and _t >= _shots[0]:
		_shots.pop_front()
		_shot("interior_%s_%s_%04.1f.png" % [str(args.get("cam", "walk")), str(args.get("perf", "on")), _t])


func _exit_tree() -> void:
	CairoInteriors.disabled = false
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
	var dir: String = args.get("shot-dir", "user://interior_shots")
	DirAccess.make_dir_recursive_absolute(dir)
	get_viewport().get_texture().get_image().save_png(dir.path_join(file))
	print("RESULT shot %s" % dir.path_join(file))


func _check(ok: bool, what: String) -> void:
	print("RESULT %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_fails += 1
