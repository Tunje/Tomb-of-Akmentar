extends Node3D
## The Cairo crowd (scripts/crowd.gd) on -7f's Cairo map, the player at the spawn. Checks: the crowd
## fills (density for the quality, every role), people move, nobody stops within keep_clear of a
## door / spot / NPC, an alarm scatters those near it (running, then crouched away from it) and
## they come back to their roles about 20 s later. Windowed runs also measure the frame rate (a PERF
## line a second, a PERFSUM) and take screenshots.
##   --mode=old        no crowd (Cairo's chatting pairs only), the before for the frame rate
##   --look            no checks: just run --seconds (frame rate, screenshots)
##   --count=N         this many instead of the density
##   --seconds=N       how long (default 45; the return check waits at least 45 s after the alarm)   --shots=t1,t2   --shot-dir=path   --cam=market|cafe|museum
## Never takes focus or captures the mouse.

const CAMS := {
	"market": [Vector3(44, 1.7, 77.0), Vector3(62, 1.2, 77.0)],
	"cafe": [Vector3(34.0, 1.9, 66.0), Vector3(27.6, 0.7, 66.0)],
	"museum": [Vector3(92, 2.4, 47), Vector3(92, 1.0, 37)],
	"street": [Vector3(40, 2.0, 50.0), Vector3(70, 1.2, 50.5)],
}

var level: Cairo
var player: Player
var crowd: Crowd
var args := {}
var _fails := 0
var _t := 0.0
var _shots: Array[float] = []
var _frames: Array[float] = []
var _sec: Array[float] = []
var _next_perf := 6.0
var _cam: Camera3D


func _ready() -> void:
	get_window().set_flag(Window.FLAG_NO_FOCUS, true)
	args = TestDriver.parse_args()
	Controls.setup()  # the player's input actions (without them it logs errors every frame)
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.max_fps = 0
	for s in str(args.get("shots", "")).split(",", false):
		_shots.append(float(s))
	level = Cairo.new()
	add_child(level)
	player = Player.new()
	add_child(player)
	player.global_position = level.player_spawn
	player.set_armed(false)
	var hud := Hud.new()
	hud.player = player
	add_child(hud)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if args.has("cam"):
		var c: Array = CAMS.get(str(args.cam), CAMS.market)
		_cam = Camera3D.new()
		add_child(_cam)
		_cam.look_at_from_position(c[0], c[1])
		_cam.make_current()
	await get_tree().physics_frame
	await get_tree().physics_frame
	# Cairo makes its own crowd (cairo.gd: level.crowd); --mode=old takes it away (only the chatting
	# pairs left), --count rebuilds it at another size.
	var own: Crowd = level.get("crowd") if "crowd" in level else null
	if str(args.get("mode", "")) == "old":
		if own:
			own.queue_free()
		print("RESULT crowd_test mode=old townsfolk=%d" % level.townsfolk.size())
	elif own and not args.has("count"):
		crowd = own
	else:
		if own:
			own.queue_free()
			await get_tree().process_frame
		crowd = Crowd.populate(level, "cairo", int(args.get("count", "-1")))
	await _run()
	print("RESULT crowd_test %s fails=%d" % ["PASS" if _fails == 0 else "FAIL", _fails])
	get_tree().quit(0 if _fails == 0 else 1)


func _run() -> void:
	var secs := float(args.get("seconds", "45"))
	if crowd == null or args.has("look"):  # --look: just run (frame rate, shots), no checks
		await get_tree().create_timer(secs).timeout
		return
	var roles := {}
	for p in crowd.people:
		roles[p.role] = int(roles.get(p.role, 0)) + 1
	_check(crowd.people.size() == Crowd.density(crowd.data) or args.has("count"), "%d people (quality %s)" % [crowd.people.size(), Settings.value("quality")])
	for r in ["walk", "carry", "stall", "sit"]:
		_check(int(roles.get(r, 0)) > 0, "role %s: %d" % [r, int(roles.get(r, 0))])
	var start := crowd.people.map(func(p: CrowdPerson) -> Vector3: return p.global_position)
	var blocked := 0
	for i in 8:
		await get_tree().create_timer(1.0).timeout
		blocked += _doorway_count()
	var moved := 0
	for i in crowd.people.size():
		if crowd.people[i].global_position.distance_to(start[i]) > 1.0:
			moved += 1
	_check(moved >= crowd.people.size() / 3, "%d of %d moved in 8 s" % [moved, crowd.people.size()])
	_check(blocked == 0, "nobody stopped in a doorway or at a spot (%d person-seconds)" % blocked)
	# The alarm: shots in the bazaar lane.
	var at := Vector3(54, 0, 77)
	var near := crowd.people.filter(func(p: CrowdPerson) -> bool: return p.global_position.distance_to(at) < Crowd.ALARM_RADIUS and p.about)
	Crowd.alarm(get_tree(), at)
	await get_tree().create_timer(0.5).timeout
	var running := near.filter(func(p: CrowdPerson) -> bool: return p.state == "flee")
	_check(not near.is_empty() and running.size() == near.size(), "%d near the shots, %d running" % [near.size(), running.size()])
	await get_tree().create_timer(9.0).timeout
	var hidden := near.filter(func(p: CrowdPerson) -> bool: return p.state == "hide")
	var away := near.filter(func(p: CrowdPerson) -> bool: return p.global_position.distance_to(at) > 18.0)
	var gone := near.filter(func(p: CrowdPerson) -> bool: return p.state in ["hide", "flee"])
	_check(gone.size() == near.size() and away.size() >= near.size() / 2, "after 9 s: %d crouched, %d still running, %d well away" % [hidden.size(), gone.size() - hidden.size(), away.size()])
	await get_tree().create_timer(maxf(secs - 10.0, 36.0)).timeout
	var back := near.filter(func(p: CrowdPerson) -> bool: return p.state != "hide" and p.state != "flee")
	_check(back.size() >= near.size() - 1, "%d of %d back about their business" % [back.size(), near.size()])


## People standing still (paused, at a stall, sitting) within keep_clear of a door, spot or NPC.
func _doorway_count() -> int:
	var n := 0
	var clear := float(crowd.data.get("keep_clear", 3.0)) - 0.6
	for p in crowd.people:
		if not p.about or p.state in ["walk", "flee"]:
			continue
		for k in crowd.keep_clear:
			if Vector2(p.global_position.x - k.x, p.global_position.z - k.z).length() < clear:
				if p.state != "sit" and p.state != "stall":
					n += 1
					print("RESULT blocking %s %s at %s near %s" % [p.name, p.state, p.global_position, k])
				break
	return n


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
		mean /= _sec.size()
		print("PERF t=%.0f fps=%d mean_ms=%.2f draws=%d" % [_t, _sec.size(), mean,
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)])
		_sec.clear()
	if _shots.size() > 0 and _t >= _shots[0]:
		_shots.pop_front()
		_shot("crowd_%s_%04.1f.png" % [str(args.get("cam", "player")), _t])


func _exit_tree() -> void:
	if _frames.size() > 10:
		var s := _frames.duplicate()
		s.sort()
		var mean := 0.0
		for f in s:
			mean += f
		mean /= s.size()
		print("PERFSUM frames=%d mean_ms=%.2f (%.0f fps) p95_ms=%.1f max_ms=%.1f" % [s.size(), mean, 1000.0 / mean, s[int(s.size() * 0.95)], s[-1]])


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
