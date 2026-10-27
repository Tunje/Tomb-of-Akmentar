extends Node3D
## The crowds outside Cairo's streets (scripts/crowd.gd), on their own maps, the player at the spawn:
##   --place=town    Act 3's desert town (crowd/desert_town.json on DesertRoute): villagers, goats,
##                   donkeys; shots in the wadi far south scatter them
##   --place=camps   Act 4's dig camps (crowd/akmentar_camps.json on AkmentarSurface): diggers by day,
##                   by the fire or asleep at night, back to work at dawn; a wiped camp's crew leaves
##   --place=docks   Cairo's docks (cairo.json's docks group): porters on their routes, fishermen
## Checks per place, then a frame rate (PERF / PERFSUM, windowed) and screenshots.
##   --mode=off      no crowd (the before)   --look   no checks, just --seconds   --cam=<preset>
##   --seconds=N  --shots=t1,t2  --shot-dir=path
## Never takes focus or captures the mouse.

const CAMS := {
	"town": [Vector3(89, 3.0, 55), Vector3(88, 0.8, 30)],
	"well": [Vector3(92, 2.4, 47), Vector3(83.4, 0.8, 40)],
	"camps": [Vector3(36, 3.0, 128), Vector3(36, 0.5, 106)],
	"dig": [Vector3(44, 2.4, 108), Vector3(36, 0.6, 101)],
	"docks": [Vector3(104, 2.6, 44), Vector3(118, 0.4, 50)],
}

var level: Node3D
var player: Player
var crowd: Crowd
var args := {}
var place := "town"
var _fails := 0
var _t := 0.0
var _shots: Array[float] = []
var _frames: Array[float] = []
var _sec: Array[float] = []
var _next_perf := 6.0


func _ready() -> void:
	get_window().set_flag(Window.FLAG_NO_FOCUS, true)
	args = TestDriver.parse_args()
	Controls.setup()
	place = str(args.get("place", "town"))
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.max_fps = 0
	for s in str(args.get("shots", "")).split(",", false):
		_shots.append(float(s))
	match place:
		"town":
			level = DesertRoute.new()
		"camps":
			level = AkmentarSurface.new()
		_:
			level = Cairo.new()
	add_child(level)
	player = Player.new()
	add_child(player)
	player.global_position = level.player_spawn
	if place == "town":
		player.global_position = DesertRoute.road_point(DesertRoute.TOWN_Z + 22.0)
	player.set_armed(false)
	var hud := Hud.new()
	hud.player = player
	add_child(hud)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if args.has("cam"):
		var c: Array = CAMS.get(str(args.cam), CAMS.town)
		var cam := Camera3D.new()
		add_child(cam)
		cam.look_at_from_position(c[0], c[1])
		cam.make_current()
	await get_tree().physics_frame
	await get_tree().physics_frame
	var own: Crowd = level.get("crowd") if "crowd" in level else null
	if str(args.get("mode", "")) == "off":
		if own:
			own.queue_free()
	elif own:
		crowd = own
	else:
		crowd = Crowd.populate(level, {"town": "desert_town", "camps": "akmentar_camps"}.get(place, "cairo"))
	if crowd == null or args.has("look"):
		await get_tree().create_timer(float(args.get("seconds", "30"))).timeout
	else:
		match place:
			"town":
				await _town()
			"camps":
				await _camps()
			_:
				await _docks()
	print("RESULT crowd_places_test %s %s fails=%d" % [place, "PASS" if _fails == 0 else "FAIL", _fails])
	get_tree().quit(0 if _fails == 0 else 1)


func _roles() -> Dictionary:
	var r := {}
	for p in crowd.people:
		r[p.role] = int(r.get(p.role, 0)) + 1
	return r


func _town() -> void:
	var r := _roles()
	_check(crowd.people.size() == Crowd.density(crowd.data) and crowd.beasts.size() == 4, "town: %d villagers %s, %d animals" % [crowd.people.size(), r, crowd.beasts.size()])
	_check(int(r.get("stall", 0)) > 0 and int(r.get("sit", 0)) > 0, "town: some at the well, some sitting")
	await get_tree().create_timer(6.0).timeout
	# The ambush down in the wadi, ~150 m south.
	var at := DesertRoute.road_point(DesertRoute.WADI_N + 8.0)
	var goats := crowd.beasts.map(func(b: Node3D) -> Vector3: return b.global_position)
	Crowd.alarm(get_tree(), at)
	await get_tree().create_timer(0.5).timeout
	# Those already at the town's far end have nowhere farther to go: they crouch where they are.
	var running := crowd.people.filter(func(p: CrowdPerson) -> bool: return p.state == "flee")
	var reacted := crowd.people.filter(func(p: CrowdPerson) -> bool: return p.state in ["flee", "hide"])
	_check(reacted.size() == crowd.people.size() and running.size() >= crowd.people.size() / 2,
		"town: shots in the wadi, %d of %d run, the rest crouch" % [running.size(), crowd.people.size()])
	await get_tree().create_timer(2.0).timeout
	var moved := 0
	for i in crowd.beasts.size():
		if crowd.beasts[i].global_position.distance_to(goats[i]) > 2.0:
			moved += 1
	_check(moved == crowd.beasts.size(), "town: the animals bolt (%d of %d)" % [moved, crowd.beasts.size()])


func _camps() -> void:
	var r := _roles()
	var teams := {}
	for p in crowd.people:
		teams[p.group.team] = int(teams.get(p.group.team, 0)) + 1
	_check(int(r.get("dig", 0)) > 0 and teams.size() == 2, "camps: %d people %s in %s" % [crowd.people.size(), r, teams])
	_check(get_tree().get_nodes_in_group("gunmen").filter(func(n: Node) -> bool: return n is CrowdPerson).is_empty()
		and get_tree().get_nodes_in_group("party").filter(func(n: Node) -> bool: return n is CrowdPerson).is_empty(),
		"camps: nobody in the gunmen or party groups")
	await get_tree().create_timer(4.0).timeout
	var digging := crowd.people.filter(func(p: CrowdPerson) -> bool: return p.state == "dig")
	_check(digging.size() >= 3, "camps by day: %d digging" % digging.size())
	(level as AkmentarSurface).set_night(1.0)
	await get_tree().create_timer(18.0).timeout
	var at_night := crowd.people.filter(func(p: CrowdPerson) -> bool: return p.state == "night")
	var asleep := at_night.filter(func(p: CrowdPerson) -> bool: return p.anim == "sleep")
	_check(at_night.size() >= crowd.people.size() - 2 and asleep.size() > 0, "camps at night: %d by the fire or asleep (%d asleep)" % [at_night.size(), asleep.size()])
	if args.has("shot-dir"):
		_shot("crowd_places_night_%s.png" % str(args.get("cam", "player")))
		await get_tree().create_timer(0.5).timeout
	(level as AkmentarSurface).set_night(0.0)
	await get_tree().create_timer(14.0).timeout
	var working := crowd.people.filter(func(p: CrowdPerson) -> bool: return p.state != "night")
	_check(working.size() == crowd.people.size(), "camps at dawn: all %d back up" % working.size())
	var gone := crowd.remove_team("germans")
	_check(gone > 0 and crowd.people.all(func(p: CrowdPerson) -> bool: return p.group.team == "americans"), "camps: the German crew leaves (%d)" % gone)


func _docks() -> void:
	var dock := crowd.people.filter(func(p: CrowdPerson) -> bool: return p.group.name == "docks")
	var porters := dock.filter(func(p: CrowdPerson) -> bool: return p.role == "porter")
	var fishers := dock.filter(func(p: CrowdPerson) -> bool: return p.role == "sit")
	_check(porters.size() > 0 and fishers.size() > 0, "docks: %d porters, %d fishermen" % [porters.size(), fishers.size()])
	var start := porters.map(func(p: CrowdPerson) -> Vector3: return p.global_position)
	await get_tree().create_timer(8.0).timeout
	var moved := 0
	for i in porters.size():
		if porters[i].global_position.distance_to(start[i]) > 2.0:
			moved += 1
	_check(moved >= porters.size() - 1, "docks: porters moving (%d of %d)" % [moved, porters.size()])
	_check(fishers.all(func(p: CrowdPerson) -> bool: return p.state == "sit" and p.global_position.x > 113.0), "docks: fishermen sitting on the pier")


func _process(delta: float) -> void:
	_t += delta
	if _t > 4.0:
		_frames.append(delta * 1000.0)
		_sec.append(delta * 1000.0)
	if _t >= _next_perf and not _sec.is_empty():
		_next_perf += 1.0
		var mean := 0.0
		for f in _sec:
			mean += f
		print("PERF t=%.0f fps=%d mean_ms=%.2f" % [_t, _sec.size(), mean / _sec.size()])
		_sec.clear()
	if _shots.size() > 0 and _t >= _shots[0]:
		_shots.pop_front()
		_shot("crowd_places_%s_%s_%04.1f.png" % [place, str(args.get("cam", "player")), _t])


func _exit_tree() -> void:
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
	var dir: String = args.get("shot-dir", "user://crowd_shots")
	DirAccess.make_dir_recursive_absolute(dir)
	get_viewport().get_texture().get_image().save_png(dir.path_join(file))
	print("RESULT shot %s" % dir.path_join(file))


func _check(ok: bool, what: String) -> void:
	print("RESULT %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_fails += 1
