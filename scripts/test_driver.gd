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
##   --mummy-glb=res://...  mummies use this GLB (same rig) instead of the Tomb Guard

var args := {}
var game: Node
var _t := 0.0
var _shots: Array[float] = []
var _dir := "user://shots"
var _kills := 0
var _fired := 0
var _hits := 0
var _bot_target: Mummy
var _tour_i := 0
var _path := PackedVector3Array()
var _repath := 0.0

## Bot route: down the stairs, entrance hall, great hall, west room, east room, burial chamber.
const TOUR := [
	Vector3(40, -6, 48), Vector3(40, -6, 32), Vector3(10, -6, 32), Vector3(10, -6, 10),
	Vector3(10, -6, 30), Vector3(70, -6, 30), Vector3(70, -6, 10), Vector3(70, -6, 30),
	Vector3(40, -6, 30), Vector3(40, -6, 12),
]


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
	elif args.get("scenario", "") == "pose":
		_pose_check()
	if _shots.size() > 0 and _t >= _shots[0]:
		var at: float = _shots.pop_front()
		_screenshot("shot_%05.1f.png" % at)
	if _t >= float(args.get("seconds", "30")) or (game.over and _t > 1.0 and _shots.is_empty()):
		_finish()


func _bot(delta: float) -> void:
	var p: Player = game.player
	if not p.alive:
		return
	# Tour the rooms along the navmesh; stop and fight whatever comes into view.
	_bot_target = _nearest(p)
	var goal: Vector3 = TOUR[mini(_tour_i, TOUR.size() - 1)]
	if p.global_position.distance_to(goal) < 2.5 and _tour_i < TOUR.size() - 1:
		_tour_i += 1
		print("RESULT tour reached %d t=%.1f" % [_tour_i, _t])
	var move := Vector2.ZERO
	if _bot_target == null or p.global_position.distance_to(_bot_target.global_position) > 7.0:
		var wp := _waypoint(p, goal)
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


func _waypoint(p: Player, goal: Vector3) -> Vector3:
	_repath -= get_physics_process_delta_time()
	if _repath <= 0.0 or _path.is_empty():
		_repath = 0.5
		_path = NavigationServer3D.map_get_path(p.get_world_3d().navigation_map, p.global_position, goal, true)
	while _path.size() > 1 and Vector2(_path[0].x - p.global_position.x, _path[0].z - p.global_position.z).length() < 0.7:
		_path.remove_at(0)
	return _path[0] if not _path.is_empty() else goal


## --scenario=pose: the explorer close up from the front and at 45 degrees, in his own rest
## pose (no retarget) and then in a few held clips. Shots are taken here, not by --shots.
const POSES := ["rest", "A_TPose", "Idle", "Pistol_Aim_Neutral", "Walk"]
var _pose_i := -1
var _pose_cam: Camera3D


func _pose_check() -> void:
	var p: Player = game.player
	if p.explorer == null:
		print("RESULT pose no explorer body")
		_finish()
		return
	if _pose_cam == null:
		_pose_cam = Camera3D.new()
		_pose_cam.fov = 40.0
		game.add_child(_pose_cam)
		_pose_cam.current = true
	# --poses=A,B limits the list; Pistol poses hold the gun along the aim, and get a hand close-up.
	var poses: Array = str(args["poses"]).split(",") if args.has("poses") else POSES
	var i := int((_t - 1.0) / 1.5)
	if i >= poses.size():
		_finish()
		return
	if i < 0:
		return
	if i != _pose_i:
		_pose_i = i
		p.explorer.debug_pose(poses[i])
		_press("aim", str(poses[i]).begins_with("Pistol"))
		_pose_shot_front = false
		_pose_shot_side = false
		_pose_shot_hand = not str(poses[i]).begins_with("Pistol")
	if not _pose_shot_hand and _t - 1.0 - i * 1.5 > 1.3:
		_pose_shot_hand = true
		var hand := p.explorer.bone_point("hand_r")
		_pose_cam.look_at_from_position(hand + p.model.global_basis * Vector3(0.55, 0.12, 0.05), hand + p.model.global_basis * Vector3(0, 0, -0.12))
		print("RESULT grip %s" % p.explorer.grip_now())
		_screenshot("pose_%d_%s_%s_hand.png" % [i, poses[i], p.weapons[p.current].id])
		return
	var POSES := poses
	var chest := p.global_position + Vector3.UP * 1.2
	var local_t := _t - 1.0 - i * 1.5
	if local_t > 0.4 and not _pose_shot_front:
		_pose_shot_front = true
		print("RESULT bones %s: %s" % [POSES[i], p.explorer.debug_report()])
		_pose_cam.look_at_from_position(chest + p.model.global_basis * Vector3(0, 0.15, -2.8), chest)
		_screenshot("pose_%d_%s_front.png" % [i, POSES[i]])
	elif local_t > 1.0 and not _pose_shot_side:
		_pose_shot_side = true
		_pose_cam.look_at_from_position(chest + p.model.global_basis * Vector3(1.6, 0.4, -1.6), chest + Vector3.UP * 0.2)
		_screenshot("pose_%d_%s_side.png" % [i, POSES[i]])


var _pose_shot_front := false
var _pose_shot_side := false
var _pose_shot_hand := true


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
