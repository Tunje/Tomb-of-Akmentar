extends Node3D
## Horse test (build plan step 8 prep): the capsule stand-in on the agreed skeleton, ridden by a
## god-mode Player: E "Ride", W up through walk, trot and gallop (each held a few seconds, with a
## side screenshot and its footfall order), a turn, Space to pull up, E to get off, then the horse
## is shot dead (Game.transport, lying down, no more "Ride"). Prints RESULT lines; exits 0 when
## every check passed. Args after "--":
##   --shot-dir=C:/path   where PNGs go (default user://horse_shots)
## Never takes focus or captures the mouse (Simon plays while we test).

var player: Player
var horse: Horse
var _side: Camera3D
var _dir := "user://horse_shots"
var _fails := 0
var _track := false
var _air := {}       # leg -> airborne now
var _lifts: Array = []   # [time, leg] of each lift-off while tracking
var _air_t := {}     # leg -> seconds airborne while tracking
var _track_t := 0.0
var _prev_hoof := {}
var _was_stance := {}
var _st_min := {}
var _st_max := {}
var _sw_min := {}
var _slip_sum := 0.0
var _slip_n := 0


func _ready() -> void:
	get_window().set_flag(Window.FLAG_NO_FOCUS, true)
	process_physics_priority = 100  # sample after the horse moved
	_setup_input()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot-dir="):
			_dir = a.substr(11)
	DirAccess.make_dir_recursive_absolute(_dir)
	Game.reset()
	_build_ground()
	horse = Horse.make(self, "bay", Vector3(0, 0, 0))
	player = Player.new()
	add_child(player)
	player.set_process_unhandled_input(false)
	player.max_health = 100000.0
	player.health = 100000.0
	player.global_position = Vector3(-1.5, 0, 0.2)
	player.yaw = -PI * 0.5  # facing east, at the horse's near side
	_side = Camera3D.new()
	_side.fov = 50.0
	add_child(_side)
	_run.call_deferred()


func _build_ground() -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.68, 0.74, 0.8)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.7, 0.65, 0.58)
	env.environment.ambient_light_energy = 0.6
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 25, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var b := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	cs.shape = BoxShape3D.new()
	cs.shape.size = Vector3(600, 1, 600)
	cs.position.y = -0.5
	b.add_child(cs)
	var mi := MeshInstance3D.new()
	mi.mesh = PlaneMesh.new()
	mi.mesh.size = Vector2(600, 600)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.74, 0.62, 0.42)
	mi.material_override = m
	b.add_child(mi)
	add_child(b)
	# Marker stones every 5 m along the track so speed shows in pictures.
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color(0.45, 0.38, 0.3)
	for k in 80:
		var s := MeshInstance3D.new()
		s.mesh = BoxMesh.new()
		s.mesh.size = Vector3(0.4, 0.5, 0.4)
		s.material_override = stone
		s.position = Vector3(3.5, 0.25, -k * 5.0)
		add_child(s)


# ---------------------------------------------------------------- the run

func _run() -> void:
	await _wait(0.6)
	_check(horse.rig.stand_in and horse.rig.skeleton.get_bone_count() == HorseRig.BONES.size(),
			"stand-in skeleton with the %d agreed bones" % HorseRig.BONES.size())
	_side_cam(true)
	await _wait(1.5)
	await _shot("horse_1_idle_side.png")

	# Mount.
	var it := Interactable.pick(get_tree(), player.global_position, -Basis(Vector3.UP, player.yaw).z)
	_check(it == horse.ride and it.prompt == "Ride", "E picks 'Ride' (%s)" % (it.prompt if it else "none"))
	if it:
		it.use(player)
	await _wait(0.3)
	_check(player.vehicle == horse and horse.driver == player, "mounted")
	player.yaw = horse.global_rotation.y
	await _wait(0.8)
	player.camera.current = true
	await _shot("horse_2_mounted_rider_view.png")

	# Up through the gaits: hold W until the next gait's speed, let go, hold the gait.
	for g: Array in [["walk", 1.7], ["trot", 3.8], ["gallop", 10.0]]:
		_press("move_forward", true)
		var t := 0.0
		while horse.speed < float(g[1]) - 0.25 and t < 8.0:
			await get_tree().physics_frame
			t += get_physics_process_delta_time()
		_press("move_forward", false)
		await _wait(1.5)
		_start_track()
		await _wait(2.0)
		_track = false
		_check(horse.gait() == g[0] and absf(horse.speed - float(g[1])) < 0.3,
				"%s: gait %s at %.2f m/s" % [g[0], horse.gait(), horse.speed])
		_report_feet(g[0])
		_side_cam(true)
		await _shot("horse_3_%s_side.png" % g[0])
		player.camera.current = true
		await _shot("horse_4_%s_rider.png" % g[0])

	# Turn (at a gallop), then pull up with Space.
	var yaw0 := horse.global_rotation.y
	_press("move_right", true)
	await _wait(1.5)
	_side_cam(false)
	await _shot("horse_5_turning.png")
	_press("move_right", false)
	var turned := rad_to_deg(angle_difference(yaw0, horse.global_rotation.y))
	_check(turned < -20.0, "D turns it right (%.0f deg in 1.5 s at a gallop)" % turned)
	_press("dodge", true)
	var stop_t := 0.0
	while horse.speed > 0.05 and stop_t < 4.0:
		await get_tree().physics_frame
		stop_t += get_physics_process_delta_time()
	_press("dodge", false)
	_check(horse.speed <= 0.05, "Space pulls up from a gallop in %.1f s" % stop_t)
	await _wait(1.0)
	_check(horse.gait() == "idle", "standing (gait %s)" % horse.gait())

	# Dismount.
	_press("cover", true)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_press("cover", false)
	await _wait(0.4)
	_check(player.vehicle == null and horse.driver == null, "E gets off")
	var off := horse.to_local(player.global_position)
	_check(off.x < -0.8 and absf(player.global_position.y - horse.global_position.y) < 0.3,
			"on the ground at the near side (local %s)" % off.snapped(Vector3.ONE * 0.01))
	_side_cam(true)
	await _shot("horse_6_dismounted.png")

	# Hurt and killed.
	horse.take_hit("body", 50.0, Vector3.LEFT, horse.global_position, 0.0, 0.0)
	var entry: Dictionary = Game.transport.horses.filter(func(e): return e.id == "bay")[0]
	_check(int(entry.health) == int(Horse.MAX_HEALTH) - 50, "Game.transport.horses health %d" % int(entry.health))
	horse.damage(500.0)
	await _wait(1.6)
	entry = Game.transport.horses.filter(func(e): return e.id == "bay")[0]
	_check(not horse.alive and int(entry.health) == 0, "killed; transport health %d" % int(entry.health))
	it = Interactable.pick(get_tree(), player.global_position, horse.global_position - player.global_position)
	_check(it != horse.ride, "no 'Ride' on a dead horse")
	await _shot("horse_7_dead.png")
	_check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "mouse never captured")

	print("RESULT horse_test %s fails=%d" % ["PASS" if _fails == 0 else "FAIL", _fails])
	await _wait(0.2)
	get_tree().quit(0 if _fails == 0 else 1)


# ---------------------------------------------------------------- footfalls

func _start_track() -> void:
	_track = true
	_track_t = 0.0
	_lifts.clear()
	for leg in HorseRig.LEGS:
		_air[leg] = false
		_air_t[leg] = 0.0
	_prev_hoof.clear()
	_st_min.clear()
	_st_max.clear()
	_sw_min.clear()
	_slip_sum = 0.0
	_slip_n = 0


func _physics_process(delta: float) -> void:
	if _side.current:
		_side_cam(_side_from_side)
	if not _track:
		return
	_track_t += delta
	for leg: String in HorseRig.LEGS:  # world hoof speed while low (planted = about 0)
		var w := horse.rig.bone_point("leg_%s_hoof" % leg)
		if _prev_hoof.has(leg) and horse.rig.stance[leg] and _was_stance.get(leg, false):
			_slip_sum += Vector2(w.x - _prev_hoof[leg].x, w.z - _prev_hoof[leg].z).length() / delta
			_slip_n += 1
		_prev_hoof[leg] = w
		var hy := w.y - horse.global_position.y
		if horse.rig.stance[leg]:
			_st_min[leg] = minf(_st_min.get(leg, INF), hy)
			_st_max[leg] = maxf(_st_max.get(leg, -INF), hy)
		else:
			_sw_min[leg] = minf(_sw_min.get(leg, INF), hy)
		_was_stance[leg] = horse.rig.stance[leg]
	for leg: String in HorseRig.LEGS:  # lift-offs and time on the ground, from the rig's stance phases
		var up: bool = not horse.rig.stance[leg]
		if up:
			_air_t[leg] += delta
		if up and not _air[leg] and _track_t > 0.2:
			_lifts.append([_track_t, leg])
		_air[leg] = up


func _report_feet(gait: String) -> void:
	var order := _lifts.map(func(l): return l[1])
	var duty := HorseRig.LEGS.map(func(leg): return "%s %.0f%%" % [leg, 100.0 * (1.0 - _air_t[leg] / maxf(_track_t, 0.01))])
	print("RESULT %s planted hooves slip %.2f m/s (body %.2f m/s)" % [gait, _slip_sum / maxf(_slip_n, 1), horse.speed])
	print("RESULT %s hoof heights: stance %s; lowest in swing %s" % [gait, " ".join(HorseRig.LEGS.map(func(l): return "%s %.2f-%.2f" % [l, _st_min.get(l, 0.0), _st_max.get(l, 0.0)])), " ".join(HorseRig.LEGS.map(func(l): return "%s %.2f" % [l, _sw_min.get(l, 0.0)]))])
	var lows: Array = HorseRig.LEGS.map(func(l): return float(_st_min.get(l, 0.0)))
	var highs: Array = HorseRig.LEGS.map(func(l): return float(_st_max.get(l, 0.0)))
	var top := 0.27 if gait == "gallop" else 0.23  # at a gallop the fetlock rises at push-off, like a heel
	_check(lows.min() > 0.1 and highs.max() < top, "%s: planted hooves stay at the ground (fetlock %.2f-%.2f m; 0.16 at rest)" % [gait, lows.min(), highs.max()])
	_check(_slip_sum / maxf(_slip_n, 1) < 0.1 * maxf(horse.speed, 1.0), "%s: planted hooves don't skate (%.2f m/s)" % [gait, _slip_sum / maxf(_slip_n, 1)])
	print("RESULT %s footfalls: lift-off order %s; on the ground %s" % [gait, " ".join(order.slice(0, 8)), ", ".join(duty)])
	# Footfall pattern: which legs leave the ground together (within 0.06 s).
	var together := 0
	for k in _lifts.size() - 1:
		if _lifts[k + 1][0] - _lifts[k][0] < 0.06:
			together += 1
	match gait:
		"walk":  # 4-beat lateral: LH, LF, RH, RF
			_check(_cyclic(order, ["hl", "fl", "hr", "fr"]), "walk is 4-beat lateral (hl fl hr fr): %s" % " ".join(order.slice(0, 8)))
		"trot":  # diagonal pairs lift together
			_check(together >= 2 and _pairs_ok(["fl", "hr"], ["fr", "hl"]), "trot moves in diagonal pairs (fl+hr, fr+hl)")
		"gallop":
			_check(_cyclic(order, ["hl", "hr", "fl", "fr"]), "gallop is 4-beat transverse (hl hr fl fr): %s" % " ".join(order.slice(0, 8)))


## The lift-offs follow `cycle` (from wherever they start).
func _cyclic(order: Array, cycle: Array) -> bool:
	if order.size() < 4:
		return false
	var start := cycle.find(order[0])
	for k in order.size():
		if order[k] != cycle[(start + k) % cycle.size()]:
			return false
	return true


## Each lift-off has its pair partner lifting within 0.06 s.
func _pairs_ok(a: Array, b: Array) -> bool:
	for k in _lifts.size():
		var leg: String = _lifts[k][1]
		var mate: String = a[1 - a.find(leg)] if leg in a else b[1 - b.find(leg)]
		var found := false
		for j in _lifts.size():
			if j != k and _lifts[j][1] == mate and absf(_lifts[j][0] - _lifts[k][0]) < 0.06:
				found = true
		if not found and k > 0 and k < _lifts.size() - 1:
			return false
	return true


# ---------------------------------------------------------------- helpers

var _side_from_side := true


func _side_cam(from_side: bool) -> void:
	_side_from_side = from_side
	_side.current = true
	var off := Vector3(7.5, 1.5, 0.0) if from_side else Vector3(-6, 5, 9)
	_side.look_at_from_position(horse.global_transform * off, horse.global_position + Vector3.UP * 1.1)


func _press(action: String, on: bool) -> void:
	if on and not Input.is_action_pressed(action):
		Input.action_press(action)
	elif not on and Input.is_action_pressed(action):
		Input.action_release(action)


func _setup_input() -> void:
	var keys := {
		"move_forward": [KEY_W], "move_back": [KEY_S], "move_left": [KEY_A], "move_right": [KEY_D],
		"sprint": [KEY_SHIFT], "crouch": [KEY_C], "dodge": [KEY_SPACE], "reload": [KEY_R], "cover": [KEY_E],
		"weapon_1": [KEY_1], "weapon_2": [KEY_2], "weapon_3": [KEY_3], "holster": [KEY_X],
	}
	for action in keys:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
			for k in keys[action]:
				var e := InputEventKey.new()
				e.physical_keycode = k
				InputMap.action_add_event(action, e)
	for action in ["fire", "aim", "weapon_next", "weapon_prev"]:
		if not InputMap.has_action(action):
			InputMap.add_action(action)


func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _check(ok: bool, what: String) -> void:
	print("RESULT %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_fails += 1


func _shot(file: String) -> void:
	await RenderingServer.frame_post_draw
	var p := _dir.path_join(file)
	get_viewport().get_texture().get_image().save_png(p)
	print("RESULT shot %s" % ProjectSettings.globalize_path(p))
