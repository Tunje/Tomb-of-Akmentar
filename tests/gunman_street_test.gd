extends Node3D
## Act 2's street fight on the real Cairo map: runs res://act2.tscn as a child, stands the player
## at the tavern and raises fight_bounty_hunters (as Isabelle's talk does). The bot crouches
## behind the upturned table and pops up to shoot whoever it can see.
## Args after "--":
##   --mode=fight|idle   idle: stays down behind the table and never shoots (do they come for him?)
##   --god               the player can't die
##   --seconds=120       give up after this long
##   --shots=4,12        screenshot times (s) after the fight starts; --shot-dir=C:/path
## RESULT lines every 2 s, on each man down / surrendering, and the result and flags at the end.

const BEHIND := Vector3(29.6, 0, 70.7)  # north of StreetFight's upturned table

var args := {}
var act: Node
var player: Player
var fight: StreetFight
var _t := 0.0
var _report := 0.0
var _shots: Array[float] = []
var _tap := 0.0
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
	if args.has("god"):
		player.max_health = 100000.0
		player.health = 100000.0
	player.global_position = BEHIND
	player.yaw = PI
	for i in 3:
		await get_tree().physics_frame
	Game.apply([{"event": "fight_bounty_hunters"}])
	await get_tree().process_frame
	fight = act.find_child("StreetFight", true, false)
	if fight == null:
		print("RESULT no StreetFight started")
		get_tree().quit(1)
		return
	print("RESULT start mode=%s" % args.get("mode", "fight"))
	_started = true
	var r: Dictionary = await fight.finished
	print("RESULT street_fight killed=%s surrendered=%s player_alive=%s hp=%d t=%.1f" % [r.killed, r.surrendered,
		r.player_alive, int(player.health), _t])
	print("RESULT flags settled=%s killed=%s surrendered=%s shot_surrendered=%s" % [Game.flag("isabelle_trouble_settled", false),
		Game.flag("bounty_men_killed", -1), Game.flag("bounty_men_surrendered", -1), Game.flag("shot_surrendered", false)])
	_release()
	await get_tree().create_timer(0.5).timeout
	get_tree().quit(0)


func _physics_process(delta: float) -> void:
	if not _started or fight == null or not is_instance_valid(player):
		return
	_t += delta
	if _shots.size() > 0 and _t >= _shots[0]:
		_shots.pop_front()
		_shot("street_%04.1f.png" % _t)
	if args.has("seconds") and _t > float(args.seconds):
		print("RESULT timeout t=%.1f" % _t)
		get_tree().quit(1)
	_report += delta
	if _report >= 2.0:
		_report = 0.0
		var parts := PackedStringArray()
		for g in fight.men:
			if is_instance_valid(g):
				parts.append("%s %s hp=%d %.0fm" % [g.name.right(1), "HANDS_UP" if g.surrendered else Gunman.State.keys()[g.state],
					int(g.health), g.global_position.distance_to(player.global_position)])
		print("RESULT t=%.0f player hp=%d %s | %s" % [_t, int(player.health), Cover.State.keys()[player.cover.state], ", ".join(parts)])
	if not player.alive:
		_release()
		return
	_bot(delta)


func _bot(delta: float) -> void:
	var g := _visible_target()
	if args.get("mode", "fight") == "idle" or g == null:
		_press("aim", false)
		_press("fire", false)
		_press("crouch", true)
		return
	_press("crouch", false)
	var at := g.global_position + Vector3.UP * (1.0 if g.crouched else 1.35)
	var d := at - player.camera.global_position
	var want_yaw := atan2(-d.x, -d.z)
	player.yaw = lerp_angle(player.yaw, want_yaw, minf(delta * 8.0, 1.0))
	player.pitch = lerpf(player.pitch, asin(clampf(d.normalized().y, -1, 1)), minf(delta * 8.0, 1.0))
	_press("aim", true)
	_tap += delta
	_press("fire", absf(angle_difference(player.yaw, want_yaw)) < 0.03 and fmod(_tap, 0.45) < 0.1)


## The nearest bounty man still fighting that the camera can see.
func _visible_target() -> Gunman:
	var best: Gunman = null
	var bd := INF
	var space := get_world_3d().direct_space_state
	for g in fight.men:
		if not is_instance_valid(g) or not g.is_active() or g.surrendered:
			continue
		var from := player.global_position + Vector3.UP * 1.5
		var to := g.global_position + Vector3.UP * 1.2
		var q := PhysicsRayQueryParameters3D.create(from, to, 1)
		q.exclude = [player.get_rid()]
		if not space.intersect_ray(q).is_empty():
			continue
		var dist := from.distance_to(to)
		if dist < bd:
			bd = dist
			best = g
	return best


func _press(action: String, on: bool) -> void:
	if on and not Input.is_action_pressed(action):
		Input.action_press(action)
	elif not on and Input.is_action_pressed(action):
		Input.action_release(action)


func _release() -> void:
	for a in ["aim", "fire", "crouch"]:
		_press(a, false)


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
