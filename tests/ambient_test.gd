extends Node3D
## The steamer's passengers, the ambient animals and the tomb's dust, each on its own map:
##   --what=boat    RiverRoute + a RiverBoat with add_folk(): six folk aboard (they ride with it),
##                  kites over it; at a shot the deckhand ducks and the rest go below
##   --what=cairo   Cairo (its crowd's ambient): kites, pigeon flocks that take off when the player
##                  runs at them or a shot goes off, and come back
##   --what=desert  DesertRoute + the town crowd: vultures, lizards and scorpions round the player
##   --what=tomb    AkmentarBelow + TombDust: motes round the player, grit from the ceiling
## Checks, then a frame rate (PERFSUM, windowed) and screenshots.
##   --mode=off   without them (the before)   --look   no checks, just --seconds   --cam=<preset>
##   --seconds=N  --shots=t1,t2  --shot-dir=path
## Never takes focus or captures the mouse.

const CAMS := {
	"boat": [Vector3(-7, 5.5, 8), Vector3(0, 2.0, -2)],
	"boat_aft": [Vector3(-3.5, 3.2, 18.5), Vector3(-0.8, 1.6, 12.0)],
	"cairo_sky": [Vector3(62, 1.7, 50.5), Vector3(60, 38, 30)],
	"pigeons": [Vector3(43.5, 0.9, 50.6), Vector3(40, 0.15, 50.2)],
	"desert": [Vector3(89, 1.6, 60), Vector3(89, 0.0, 52)],
}

var level: Node3D
var player: Player
var args := {}
var what := "boat"
var boat: RiverBoat
var _fails := 0
var _t := 0.0
var _shots: Array[float] = []
var _frames: Array[float] = []
var _cam: Camera3D


func _ready() -> void:
	get_window().set_flag(Window.FLAG_NO_FOCUS, true)
	args = TestDriver.parse_args()
	Controls.setup()
	what = str(args.get("what", "boat"))
	var off := str(args.get("mode", "")) == "off"
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.max_fps = 0
	for s in str(args.get("shots", "")).split(",", false):
		_shots.append(float(s))
	match what:
		"boat":
			level = RiverRoute.new()
		"desert":
			level = DesertRoute.new()
		"tomb":
			level = AkmentarBelow.new()
		_:
			level = Cairo.new()
	add_child(level)
	player = Player.new()
	add_child(player)
	player.global_position = level.player_spawn
	if what == "desert":
		player.global_position = DesertRoute.road_point(DesertRoute.TOWN_Z + 24.0)
	player.set_armed(false)
	if what == "tomb":
		player.add_lantern()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await get_tree().physics_frame
	await get_tree().physics_frame
	var own: Crowd = level.get("crowd") if "crowd" in level else null
	match what:
		"boat":
			boat = RiverBoat.make(level, level.get("path"), "test_steamer", 30.0)
			await get_tree().physics_frame
			player.global_position = boat.to_global(Vector3(-3.4, 1.3, 2.0))
			if not off:
				boat.add_folk()
		"cairo":
			if off and own:
				own.queue_free()
				for n in level.find_children("AmbientLife", "", false, false):
					n.queue_free()
		"desert":
			if not off:
				Crowd.populate(level, "desert_town")
		"tomb":
			if not off:
				TombDust.add(self, player)
	if args.has("cam"):
		var c: Array = CAMS.get(str(args.cam), CAMS.boat)
		_cam = Camera3D.new()
		if what == "boat":
			boat.add_child(_cam)
			_cam.position = c[0]
			_cam.look_at(boat.to_global(c[1]))
		else:
			add_child(_cam)
			_cam.look_at_from_position(c[0], c[1])
		_cam.make_current()
	if off or args.has("look"):
		await get_tree().create_timer(float(args.get("seconds", "25"))).timeout
	else:
		match what:
			"boat":
				await _boat()
			"cairo":
				await _cairo()
			"desert":
				await _desert()
			"tomb":
				await _tomb()
	print("RESULT ambient_test %s %s fails=%d" % [what, "PASS" if _fails == 0 else "FAIL", _fails])
	get_tree().quit(0 if _fails == 0 else 1)


func _boat() -> void:
	var folk := boat.get_children().filter(func(n: Node) -> bool: return n is BoatFolk)
	_check(folk.size() == 6, "boat: %d folk aboard" % folk.size())
	boat.sail()
	var local := folk.map(func(f: BoatFolk) -> Vector3: return f.position)
	var world := folk.map(func(f: BoatFolk) -> Vector3: return f.global_position)
	await get_tree().create_timer(6.0).timeout
	var rode := 0
	for i in folk.size():
		var f: BoatFolk = folk[i]
		if f.position.distance_to(local[i]) < 0.05 and f.global_position.distance_to(world[i]) > 3.0:
			rode += 1
	_check(rode == folk.size(), "boat: under way, all %d ride with it (%d)" % [folk.size(), rode])
	var kites := level.find_children("AmbientLife", "", true, false)
	_check(not kites.is_empty() and (kites[0] as AmbientLife).birds.size() == 4, "boat: kites over the boat")
	Crowd.alarm(get_tree(), boat.global_position)
	await get_tree().create_timer(5.0).timeout
	var ducked := folk.filter(func(f: BoatFolk) -> bool: return f.job == "wheel" and f.state == "duck")
	var below := folk.filter(func(f: BoatFolk) -> bool: return f.state == "below")
	_check(ducked.size() == 1 and below.size() == folk.size() - 1, "boat: a shot; the deckhand ducks (%d), %d go below" % [ducked.size(), below.size()])
	_check(get_tree().get_nodes_in_group("gunmen").filter(func(n: Node) -> bool: return n is BoatFolk).is_empty(), "boat: none of them is a gunman")


func _cairo() -> void:
	var life := level.find_children("AmbientLife", "", true, false)
	_check(not life.is_empty(), "cairo: ambient life from the crowd's data")
	if life.is_empty():
		return
	var a := life[0] as AmbientLife
	_check(a.birds.size() == 6 and a.pigeons.size() == 28, "cairo: %d kites, %d pigeons" % [a.birds.size(), a.pigeons.size()])
	await get_tree().create_timer(2.0).timeout
	var flock := a.pigeons.filter(func(p: Dictionary) -> bool: return (p.home as Vector3).distance_to(Vector3(40, 0, 50.2)) < 0.5)
	# The player runs at them.
	player.global_position = Vector3(48, 0.1, 50.2)  # up the street, running west at them
	player.yaw = PI * 0.5
	Input.action_press("move_forward")
	Input.action_press("sprint")
	await get_tree().create_timer(1.6).timeout
	Input.action_release("move_forward")
	Input.action_release("sprint")
	var up := flock.filter(func(p: Dictionary) -> bool: return p.state != "ground")
	_check(up.size() >= flock.size() - 1, "cairo: running at a flock, %d of %d take off" % [up.size(), flock.size()])
	var other := a.pigeons.filter(func(p: Dictionary) -> bool: return (p.home as Vector3).distance_to(Vector3(88, 0, 51)) < 0.5)
	Crowd.alarm(get_tree(), Vector3(88, 0, 51))
	await get_tree().create_timer(0.3).timeout
	_check(other.all(func(p: Dictionary) -> bool: return p.state != "ground"), "cairo: a shot, the other flock goes up")
	player.global_position = Vector3(100, 0.1, 10)  # far away: they come back
	await get_tree().create_timer(AmbientLife.BACK_AFTER + 6.0).timeout
	_check(flock.all(func(p: Dictionary) -> bool: return p.state == "ground"), "cairo: they come back once you're gone")


func _desert() -> void:
	await get_tree().create_timer(3.0).timeout
	var life := level.find_children("AmbientLife", "", true, false)
	_check(not life.is_empty(), "desert: ambient life from the town's data")
	if life.is_empty():
		return
	var a := life[0] as AmbientLife
	_check(a.critters.size() == 8 and a.critters.all(func(c: Dictionary) -> bool: return (c.pos as Vector3).distance_to(player.global_position) < 26.0),
		"desert: %d lizards and scorpions round the player" % a.critters.size())
	var before := a.critters.map(func(c: Dictionary) -> Vector3: return c.pos)
	await get_tree().create_timer(5.0).timeout
	var moved := 0
	for i in a.critters.size():
		if (a.critters[i].pos as Vector3).distance_to(before[i]) > 0.2:
			moved += 1
	_check(moved >= a.critters.size() / 2, "desert: %d skittered about" % moved)


func _tomb() -> void:
	await get_tree().create_timer(12.0).timeout
	var dust := find_children("TombDust", "", true, false)
	_check(not dust.is_empty(), "tomb: the dust is there")
	var grit := dust[0].get_children().filter(func(n: Node) -> bool: return n is GPUParticles3D).size() - 1 if not dust.is_empty() else 0
	_check(grit >= 1, "tomb: grit has fallen (%d trickles)" % grit)


func _process(delta: float) -> void:
	_t += delta
	if _t > 4.0:
		_frames.append(delta * 1000.0)
	if _shots.size() > 0 and _t >= _shots[0]:
		_shots.pop_front()
		_shot("ambient_%s_%s_%04.1f.png" % [what, str(args.get("cam", "player")), _t])


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
	var dir: String = args.get("shot-dir", "user://ambient_shots")
	DirAccess.make_dir_recursive_absolute(dir)
	get_viewport().get_texture().get_image().save_png(dir.path_join(file))
	print("RESULT shot %s" % dir.path_join(file))


func _check(ok: bool, what_: String) -> void:
	print("RESULT %s %s" % ["ok  " if ok else "FAIL", what_])
	if not ok:
		_fails += 1
