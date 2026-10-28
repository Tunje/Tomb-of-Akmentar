extends Node3D
## MarketChase test on the Cairo map: round 1 the bot sprints after the thief (straight at
## him in sight, the navmesh round corners; E when he's in reach) and must catch him; round 2 it stands still and must lose him (the
## note gone: freddie_note false). Prints RESULT lines; exits 0 when every check passed.
##   --plan=chase|idle    one round only
##   --shots=t1,t2  --shot-dir=C:/path   screenshots (windowed runs) at round-1 times
##   --seed=N
## Never takes focus or captures the mouse (Simon plays while we test).

var level: Cairo
var player: Player
var hud: Hud
var args := {}
var _fails := 0
var _shots: Array[float] = []
var _chase: MarketChase
var _follow := false
var _bot: FightBot
var _e_held := false
var _stuck := 0.0
var _side_t := 0.0
var _side := "move_left"


func _ready() -> void:
	get_window().set_flag(Window.FLAG_NO_FOCUS, true)
	Controls.setup()
	args = TestDriver.parse_args()
	seed(int(args.get("seed", 7)))
	for s in str(args.get("shots", "")).split(",", false):
		_shots.append(float(s))
	level = Cairo.new()
	add_child(level)
	player = Player.new()
	add_child(player)
	player.set_armed(false)
	hud = Hud.new()
	hud.player = player
	add_child(hud)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	for i in 3:
		await get_tree().physics_frame
	# The navmesh syncs in real time (a big map, Cairo v2, takes longer): the thief paths on it.
	var map := get_world_3d().navigation_map
	var t0 := Time.get_ticks_msec()
	while NavigationServer3D.map_get_iteration_id(map) == 0 and Time.get_ticks_msec() - t0 < 30000:
		await get_tree().physics_frame
	var plan := str(args.get("plan", "both"))
	if plan in ["both", "chase"]:
		var r := await _round(true)
		_check(r.result == "caught", "the bot catches him (%s)" % r)
		_check(Game.flag("act1_chase_caught", false) and Game.flag("freddie_note", false), "caught: act1_chase_caught, the note kept")
	if plan in ["both", "idle"]:
		var r := await _round(false)
		_check(r.result == "lost", "standing still loses him (%s)" % r)
		_check(Game.flag("act1_chase_lost", false) and not Game.flag("freddie_note", true), "lost: act1_chase_lost, freddie_note false")
	print("RESULT %s (%d failed)" % ["PASS" if _fails == 0 else "FAIL", _fails])
	get_tree().quit(0 if _fails == 0 else 1)


func _round(follow: bool) -> Dictionary:
	for f in ["act1_chase_caught", "act1_chase_lost", "suitcase_lost"]:
		Game.set_flag(f, false)
	Game.set_flag("freddie_note")
	# Outside the club, where the brawl happens.
	player.global_position = level.open_point(level.near_spot("club", 0.0, 4.0))
	player.velocity = Vector3.ZERO
	player.yaw = -PI * 0.5  # facing east, the way he runs
	for i in 2:
		await get_tree().physics_frame
	_follow = follow
	_bot = FightBot.new(player)
	_chase = MarketChase.start(level, player, player.global_position + Vector3(2, 0, 0))
	var timer := get_tree().create_timer(60.0)
	timer.timeout.connect(func():
		if is_instance_valid(_chase) and not _chase.over:
			_chase.finished.emit({"result": "timeout", "t": 60.0}))
	var r: Dictionary = await _chase.finished
	_follow = false
	FightBot.release_moves()
	Input.action_release("sprint")
	Input.action_release("cover")
	await get_tree().create_timer(3.0).timeout
	return r


func _physics_process(delta: float) -> void:
	if not _follow or not is_instance_valid(_chase) or _chase.over:
		return
	var thief := _chase.thief
	if args.has("trace") and Engine.get_physics_frames() % 30 == 0:
		print("TRACE t=%.1f thief=%s player=%s v=%.1f gap=%.1f" % [_chase.t, thief.global_position.snappedf(0.1),
			player.global_position.snappedf(0.1), _flat(player.velocity).length(), _flat(thief.global_position - player.global_position).length()])
	# Snagged on someone: step sideways for a moment.
	_stuck = _stuck + delta if _flat(player.velocity).length() < 2.0 else 0.0
	if _stuck > 0.4:
		_side_t = 0.6
		_side = "move_left" if _side == "move_right" else "move_right"
		_stuck = 0.0
	_side_t = maxf(_side_t - delta, 0.0)
	FightBot.press("move_right", _side_t > 0.0 and _side == "move_right")
	FightBot.press("move_left", _side_t > 0.0 and _side == "move_left")
	var space := player.get_world_3d().direct_space_state
	var ray := PhysicsRayQueryParameters3D.create(player.global_position + Vector3.UP, thief.global_position + Vector3.UP, 1)
	if space.intersect_ray(ray).is_empty():
		var d := _flat(thief.global_position - player.global_position)  # in sight: straight at him
		player.yaw = lerp_angle(player.yaw, atan2(-d.x, -d.z), minf(delta * 12.0, 1.0))
		Input.action_press("move_forward")
	else:
		_bot.walk(thief.global_position, delta)  # round the corner on the navmesh
		Input.action_press("move_forward")
	Input.action_press("sprint")
	# E on alternate frames while he's the thing in front (a fresh press each time).
	_e_held = not _e_held and player.focus == _chase.grab
	FightBot.press("cover", _e_held)


func _process(_delta: float) -> void:
	if _shots.size() > 0 and is_instance_valid(_chase) and _chase.t >= _shots[0]:
		var at: float = _shots.pop_front()
		var dir: String = args.get("shot-dir", "user://chase_shots")
		DirAccess.make_dir_recursive_absolute(dir)
		var file := "market_chase_%05.1f.png" % at
		get_viewport().get_texture().get_image().save_png(dir.path_join(file))
		print("RESULT shot %s" % dir.path_join(file))


func _check(ok: bool, what: String) -> void:
	print("RESULT %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_fails += 1


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0, v.z)
