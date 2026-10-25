class_name TestDriver
extends Node
## Bot playtest + screenshots for off-screen runs. Args after "--":
##   --scenario=demo        bot walks to the chamber and fights
##   --seconds=40           quit after this long
##   --shots=3,6.5,10       screenshot times (s)
##   --shot-dir=C:/path     where PNGs go (default user://shots)
##   --gun=0|1|2            starting gun;  --cycle-guns  switch gun after each kill
##   --god                  player can't die (for long looks at the AI)
##   --no-dodge             bot never rolls (checks that mummy hits land)

var args := {}
var game: Node
var _t := 0.0
var _shots: Array[float] = []
var _dir := "user://shots"
var _kills := 0
var _fired := 0
var _hits := 0
var _bot_target: Mummy


static func parse_args() -> Dictionary:
	var out := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv := a.substr(2).split("=", true, 1)
			out[kv[0]] = kv[1] if kv.size() > 1 else "true"
	return out


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for s in str(args.get("shots", "")).split(",", false):
		_shots.append(float(s))
	_shots.sort()
	_dir = args.get("shot-dir", _dir)
	DirAccess.make_dir_recursive_absolute(_dir)
	var p: Player = game.player
	p.switch_to(int(args.get("gun", "0")))
	p.hit_confirmed.connect(func(killed, _head):
		_hits += 1
		if killed:
			_kills += 1
			if args.has("cycle-guns"):
				p.switch_to((p.current + 1) % p.weapons.size()))
	p.fired.connect(func(): _fired += 1)
	if args.has("god"):
		p.max_health = 100000.0
		p.health = 100000.0
	print("RESULT start scenario=%s" % args.get("scenario", "none"))


func _physics_process(delta: float) -> void:
	_t += delta
	if args.get("scenario", "") == "demo":
		_bot(delta)
	if _shots.size() > 0 and _t >= _shots[0]:
		var at: float = _shots.pop_front()
		_screenshot("shot_%05.1f.png" % at)
	if _t >= float(args.get("seconds", "30")) or (game.over and _t > 1.0 and _shots.is_empty()):
		_finish()


func _bot(delta: float) -> void:
	var p: Player = game.player
	if not p.alive:
		return
	# Walk up the corridor until the chamber is in sight, then hold there and fight.
	var hold := Vector3(20.0, 0.0, 13.5)
	var to_hold := hold - p.global_position
	to_hold.y = 0
	_bot_target = _nearest(p)
	var move := Vector2.ZERO
	if to_hold.length() > 0.8 and (_bot_target == null or p.global_position.distance_to(_bot_target.global_position) > 7.0):
		var wp := _corridor_waypoint(p.global_position)
		var d := wp - p.global_position
		var local := Basis(Vector3.UP, -p.yaw) * Vector3(d.x, 0, d.z).normalized()
		move = Vector2(local.x, local.z)
		if _bot_target == null:
			p.yaw = lerp_angle(p.yaw, atan2(-d.x, -d.z), minf(delta * 6.0, 1.0))
	_press("move_right", move.x > 0.3)
	_press("move_left", move.x < -0.3)
	_press("move_back", move.y > 0.3)
	_press("move_forward", move.y < -0.3)

	if _bot_target == null:
		_press("aim", false)
		_press("fire", false)
		return
	var aim_at := _bot_target.global_position + Vector3.UP * (0.6 if _bot_target.crawling else 1.3)
	var d := aim_at - p.camera.global_position
	var want_yaw := atan2(-d.x, -d.z)
	var want_pitch := asin(clampf(d.normalized().y, -1, 1))
	p.yaw = lerp_angle(p.yaw, want_yaw, minf(delta * 10.0, 1.0))
	p.pitch = lerpf(p.pitch, want_pitch, minf(delta * 10.0, 1.0))
	var err := absf(angle_difference(p.yaw, want_yaw)) + absf(p.pitch - want_pitch)
	var dist := p.global_position.distance_to(_bot_target.global_position)
	_press("aim", dist > 3.0)
	_press("fire", err < deg_to_rad(2.5) and dist < 25.0)
	if not args.has("no-dodge") and _bot_target.state == Mummy.State.WINDUP and dist < 2.2 and _bot_target._t > 0.3:
		_press("move_back", true)
		p.dodge()


func _corridor_waypoint(pos: Vector3) -> Vector3:
	# Corridor centreline: north up the first leg, east along the bend, north to the mouth.
	if pos.z > 27.6 and pos.x < 12.0:
		return Vector3(10, 0, 26.5)
	if pos.x < 19.6:
		return Vector3(20.5, 0, 27)
	return Vector3(20, 0, 17)


func _nearest(p: Player) -> Mummy:
	var best: Mummy = null
	var bd := 30.0
	for m in game.mummies:
		if not is_instance_valid(m) or m.state in [Mummy.State.DEAD, Mummy.State.RISING]:
			continue
		var dd := p.global_position.distance_to(m.global_position)
		if dd < bd and _visible(p, m):
			bd = dd
			best = m
	return best


func _visible(p: Player, m: Mummy) -> bool:
	var q := PhysicsRayQueryParameters3D.create(p.camera.global_position, m.global_position + Vector3.UP * 1.0, 1)
	return p.get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func _press(action: String, on: bool) -> void:
	if on and not Input.is_action_pressed(action):
		Input.action_press(action)
	elif not on and Input.is_action_pressed(action):
		Input.action_release(action)


func _screenshot(file: String) -> void:
	await RenderingServer.frame_post_draw
	var path := _dir.path_join(file)
	get_viewport().get_texture().get_image().save_png(path)
	print("RESULT shot %s" % ProjectSettings.globalize_path(path))


func _finish() -> void:
	set_physics_process(false)
	var p: Player = game.player
	print("RESULT summary t=%.1f fired=%d hits=%d kills=%d alive_mummies=%d health=%d over=%s spawned=%d" % [
		_t, _fired, _hits, _kills, game.alive_count(), int(p.health), str(game.over), game.spawned])
	await get_tree().create_timer(0.3).timeout
	get_tree().quit(0)
