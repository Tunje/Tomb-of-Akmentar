extends Node3D
## Act 2's museum brawl on the real Cairo map: runs res://act2.tscn as a child, stands the player
## at the museum and raises fight_museum_guards (as the archivist's talk does when threatened).
## Args after "--":
##   --mode=fight|lose   fight: the bot brawls (brawl_test's bot); lose: it stands and takes it
##   --seconds=90        give up after this long
##   --shots=3,8         screenshot times (s) after the brawl starts; --shot-dir=C:/path
## RESULT lines on knockdowns / yields, every 2 s, and the outcome with flags and where he ended up.

const START := Vector3(0, 0, 1.9)  # from the museum's spot: before its doors (either Cairo)

var args := {}
var act: Node
var player: Player
var pm: Melee
var brawl: GuardBrawl
var _t := 0.0
var _report := 0.0
var _shots: Array[float] = []
var _attack_cd := 0.0
var _blocking_t := -1.0
var _started := false


func _ready() -> void:
	get_window().set_flag(Window.FLAG_NO_FOCUS, true)
	args = TestDriver.parse_args()
	for s in str(args.get("shots", "")).split(",", false):
		_shots.append(float(s))
	Game.reset()
	act = (load("res://act2.tscn") as PackedScene).instantiate()
	add_child(act)
	await get_tree().create_timer(3.5).timeout
	player = act.get("player")
	pm = player.melee
	player.global_position = (act.get("level") as Cairo).spots.museum + START
	player.yaw = 0.0  # facing the doors (-Z)
	for i in 3:
		await get_tree().physics_frame
	pm.knocked_down.connect(func(): print("RESULT player down t=%.1f hp=%d" % [_t, int(pm.hp)]))
	pm.ko.connect(func(): print("RESULT player KO t=%.1f" % _t))
	Game.apply([{"event": "fight_museum_guards"}])
	await get_tree().process_frame
	brawl = act.find_child("GuardBrawl", true, false)
	if brawl == null:
		print("RESULT no GuardBrawl started")
		get_tree().quit(1)
		return
	print("RESULT start mode=%s melee=%s armed=%s" % [args.get("mode", "fight"), pm.enabled, player.armed])
	_started = true
	var won: bool = await brawl.finished
	_press("move_forward", false)
	await get_tree().create_timer(0.3).timeout
	print("RESULT guard_brawl won=%s t=%.1f player alive=%s health=%d melee=%s hp=%d at=%s" % [won, _t, player.alive, int(player.health),
		pm.enabled, int(pm.hp), player.global_position.snapped(Vector3.ONE * 0.1)])
	print("RESULT flags beaten=%s hostile=%s guards_left=%d" % [Game.flag("museum_guards_beaten", false),
		Game.flag("archivist_hostile", false), get_tree().get_nodes_in_group("brawlers").size()])
	get_tree().quit(0)


func _physics_process(delta: float) -> void:
	if not _started or not is_instance_valid(brawl):
		return
	_t += delta
	if _shots.size() > 0 and _t >= _shots[0]:
		_shots.pop_front()
		_shot("guards_%04.1f.png" % _t)
	if args.has("seconds") and _t > float(args.seconds):
		print("RESULT timeout t=%.1f" % _t)
		get_tree().quit(1)
	_report += delta
	if _report >= 2.0:
		_report = 0.0
		var parts := PackedStringArray()
		for b in brawl.guards:
			if is_instance_valid(b):
				parts.append("%s %s hp=%d" % [b.name.right(1), Melee.State.keys()[b.melee.state], int(b.melee.hp)])
		print("RESULT t=%.0f player %s hp=%d | %s" % [_t, Melee.State.keys()[pm.state], int(pm.hp), ", ".join(parts)])
	if args.get("mode", "fight") == "fight":
		_bot(delta)


func _bot(delta: float) -> void:
	var b := _nearest()
	if b == null or pm.busy():
		_press("move_forward", false)
		return
	var to := _flat(b.global_position - player.global_position)
	var d := to.length()
	player.yaw = lerp_angle(player.yaw, atan2(-to.x, -to.z), minf(delta * 10.0, 1.0))
	_blocking_t -= delta
	for o in brawl.guards:
		if not is_instance_valid(o):
			continue
		var m := o.melee
		if m.state == Melee.State.ATTACK and m._t < float(Melee.MOVES[m._kind].hit) \
				and _flat(o.global_position - player.global_position).length() < 2.0 and _blocking_t < -0.3:
			_blocking_t = 0.45 if randf() < 0.5 else -0.0001
	pm.set_block(_blocking_t > 0.0)
	if pm.state == Melee.State.BLOCK:
		_press("move_forward", false)
		return
	if d > 1.15:
		_press("move_forward", true)
		return
	_press("move_forward", false)
	_attack_cd -= delta
	if _attack_cd > 0.0:
		return
	_attack_cd = randf_range(0.3, 0.6)
	if b.melee.state == Melee.State.BLOCK and randf() < 0.5:
		pm.attack("shove", to)
	else:
		pm.attack("jab", to)


func _nearest() -> Brawler:
	var best: Brawler = null
	var bd := INF
	for b in brawl.guards:
		if not is_instance_valid(b) or b.melee.out() or not b.melee.can_be_hit():
			continue
		var d := b.global_position.distance_to(player.global_position)
		if d < bd:
			bd = d
			best = b
	return best


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0, v.z)


func _press(action: String, on: bool) -> void:
	if on and not Input.is_action_pressed(action):
		Input.action_press(action)
	elif not on and Input.is_action_pressed(action):
		Input.action_release(action)


func _shot(file: String) -> void:
	if DisplayServer.get_name() == "headless":  # frame_post_draw never fires headless
		return
	await RenderingServer.frame_post_draw
	if DisplayServer.get_name() == "headless":
		return
	var dir: String = args.get("shot-dir", "user://shots")
	DirAccess.make_dir_recursive_absolute(dir)
	get_viewport().get_texture().get_image().save_png(dir.path_join(file))
	print("RESULT shot %s" % dir.path_join(file))
