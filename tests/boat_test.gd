extends Node3D
## Riverboat test (build plan step 10): a stretch of river with banks and a pier, the steamer
## docked; a god-mode Player boards by the gangplank prompt, walks to the bow, rings the bell, stands
## still while it gets under way and turns (drift and jitter on the deck), walks bow to stern,
## takes cover behind a crate, then two bandits on the bow fight him while the boat moves; last he
## is thrown overboard and should come back on deck. Prints RESULT lines and saves screenshots
## (player view and a chase view); exits 0 when every check passed. Args after "--":
##   --shot-dir=C:/path   where PNGs go (default user://boat_shots)
## Never takes focus or captures the mouse (Simon plays while we test).

const ROUTE := [   # boat-local waypoints, bow to stern down the starboard passage
	Vector3(1.4, 0, -7.0), Vector3(2.4, 0, -5.3), Vector3(2.4, 0, 5.6), Vector3(1.2, 0, 6.9),
	Vector3(1.2, 0, 8.8), Vector3(3.95, 0, 8.75),  # behind the aft passage crate (against the rail)
]
const TO_BOW := [Vector3(2.4, 0, -2.5), Vector3(2.4, 0, -5.3), Vector3(1.4, 0, -7.0), Vector3(0.3, 0, -9.2)]

var player: Player
var boat: RiverBoat
var path: Path3D
var gunmen: Array[Gunman] = []
var _chase: Camera3D
var _dir := "user://boat_shots"
var _fails := 0
var _route: Array = []
var _route_i := 0
var _aim_at: Node3D
var _fire := false
var _hits := 0
var _hurt := 0
var _fired := 0
# Deck drift / smoothness while standing still.
var _measure := false
var _local_prev := Vector3.INF
var _steps: Array[float] = []
var _big: Array[String] = []
var _cam_hist: Array[Vector3] = []
var _cam_jerk := 0.0
var _boat_hist: Array[Vector3] = []
var _boat_jerk := 0.0
var _off_floor := 0
var _frames := 0


func _ready() -> void:
	get_window().set_flag(Window.FLAG_NO_FOCUS, true)
	process_physics_priority = 100  # measure after the boat and the player have moved this tick
	_setup_input()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot-dir="):
			_dir = a.substr(11)
	DirAccess.make_dir_recursive_absolute(_dir)
	Game.reset()
	DayLog.begin_day()
	_build_river()
	boat = RiverBoat.make(self, path, "test")
	player = Player.new()
	add_child(player)
	player.set_process_unhandled_input(false)
	player.max_health = 100000.0
	player.health = 100000.0
	player.global_position = boat.to_global(Vector3(RiverBoat.BEAM * 0.5 + 4.3, 1.2, RiverBoat.PLANK_Z + 0.2))
	player.yaw = PI * 0.5  # facing the boat (west)
	player.damaged.connect(func(_a: float): _hurt += 1)
	player.fired.connect(func(): _fired += 1)
	player.hit_confirmed.connect(func(_k: bool, _h: bool): _hits += 1)
	boat.watch(player)
	var hud := Hud.new()
	hud.player = player
	add_child(hud)
	_chase = Camera3D.new()
	_chase.fov = 55.0
	add_child(_chase)
	_run.call_deferred()


func _build_river() -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.62, 0.7, 0.78)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.7, 0.66, 0.6)
	env.environment.ambient_light_energy = 0.6
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	add_child(sun)
	# The river: straight past the pier, then a long S-bend.
	path = Path3D.new()
	var c := Curve3D.new()
	for k in 41:
		var z := -k * 9.0
		var u := clampf((-z - 30.0) / 300.0, 0.0, 1.0)
		c.add_point(Vector3(26.0 * sin(u * TAU * 0.75) * (u * u * (3.0 - 2.0 * u)), 0, z))
	c.bake_interval = 0.5
	path.curve = c
	add_child(path)
	RiverWater.make(self, Vector2(220, 460), 0.0, Vector3(10, 0, -170))
	# Banks either side, a few palms, and the pier.
	var sand := _mat(Color(0.76, 0.64, 0.44))
	var green := _mat(Color(0.25, 0.4, 0.18))
	var trunk := _mat(Color(0.4, 0.3, 0.2))
	var length := c.get_baked_length()
	var s := 0.0
	var k := 0
	while s < length:
		var p := c.sample_baked(s)
		var q := c.sample_baked(minf(s + 1.0, length))
		var f := (q - p).normalized()
		var right := f.cross(Vector3.UP).normalized()
		for side in [-1.0, 1.0]:
			var at: Vector3 = p + right * side * 24.0
			_box(at + Vector3(0, 0.4, 0), Vector3(22, 1.2, 14), sand, atan2(-f.x, -f.z))
			if k % 3 == 0:
				var palm: Vector3 = p + right * side * (16.0 + (k % 5))
				_cyl(palm + Vector3(0, 4.0, 0), 0.18, 7.0, trunk)
				_sphere(palm + Vector3(0, 7.8, 0), 1.6, green)
		s += 12.0
		k += 1
	_box(Vector3(RiverBoat.BEAM * 0.5 + 3.3, 0.5, RiverBoat.PLANK_Z), Vector3(5.2, 1.1, 8.0), _mat(Color(0.42, 0.3, 0.18)))


func _box(at: Vector3, size: Vector3, m: Material, yaw := 0.0) -> void:
	var b := StaticBody3D.new()
	b.position = at
	b.rotation.y = yaw
	var cs := CollisionShape3D.new()
	cs.shape = BoxShape3D.new()
	cs.shape.size = size
	b.add_child(cs)
	var mi := MeshInstance3D.new()
	mi.mesh = BoxMesh.new()
	mi.mesh.size = size
	mi.material_override = m
	b.add_child(mi)
	add_child(b)


func _cyl(at: Vector3, r: float, h: float, m: Material) -> void:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r * 0.7
	cm.bottom_radius = r
	cm.height = h
	mi.mesh = cm
	mi.material_override = m
	mi.position = at
	add_child(mi)


func _sphere(at: Vector3, r: float, m: Material) -> void:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 1.1
	mi.mesh = sm
	mi.material_override = m
	mi.position = at
	add_child(mi)


func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.9
	return m


# ---------------------------------------------------------------- the run

func _run() -> void:
	await _wait(0.8)
	_chase_cam(true)
	await _shot("boat_1_docked.png")
	player.camera.current = true

	# Board by the gangplank prompt, walk to the bow, ring the bell.
	var it := _e()
	_check(it != null and it.prompt == "Board the riverboat", "E on the pier: '%s'" % (it.prompt if it else "none"))
	await _wait(0.2)
	_check(boat.on_deck(player.global_position), "boarded (local %s)" % boat.to_local(player.global_position).snapped(Vector3.ONE * 0.01))
	await _walk(TO_BOW, 20.0)
	player.yaw = _boat_yaw()
	await _wait(0.3)
	it = _e()
	_check(it != null and it.prompt == "Ring the bell (cast off)", "E at the bell: '%s'" % (it.prompt if it else "none"))
	_check(boat.state == RiverBoat.State.SAILING, "the boat casts off")

	# Stand still while it gets under way and into the first bend.
	await _wait(0.5)
	_measure = true
	var start_local := boat.to_local(player.global_position)
	await _wait(9.0)
	_measure = false
	var drift := boat.to_local(player.global_position) - start_local
	_report_still("standing", drift)
	await _shot("boat_2_player_view.png")
	_chase_cam(true)
	await _shot("boat_3_chase.png")
	player.camera.current = true

	# Walk bow to stern down the starboard passage.
	var t0 := Time.get_ticks_msec()
	var ok := await _walk(ROUTE, 30.0)
	_check(ok, "walked bow to stern in %.1f s at %.1f m/s boat speed" % [(Time.get_ticks_msec() - t0) / 1000.0, boat.speed])
	# Into cover behind the stern crate, facing the bow.
	player.yaw = _boat_yaw()
	await _wait(0.2)
	print("RESULT before cover: local %s, yaw vs boat %.1f deg" % [boat.to_local(player.global_position).snapped(Vector3.ONE * 0.01), rad_to_deg(angle_difference(player.yaw, _boat_yaw()))])
	Input.action_press("cover")
	await get_tree().physics_frame
	await get_tree().physics_frame
	Input.action_release("cover")
	await _wait(0.4)
	_check(player.cover.state == Cover.State.IN_COVER, "in cover behind the crate (state %s)" % Cover.State.keys()[player.cover.state])
	await _wait(1.0)  # let the 0.2 s snap into cover settle before measuring
	_measure = true
	_steps.clear()
	start_local = boat.to_local(player.global_position)
	await _wait(4.0)
	_measure = false
	_report_still("in cover", boat.to_local(player.global_position) - start_local)
	await _shot("boat_4_cover.png")

	# Ballistics on the moving deck: a round down the deck (bow-ward, along the motion) and one
	# across it; where they land against where they were aimed, in the deck's frame.
	await _shoot_check("down the deck", boat.to_global(Vector3(2.4, RiverBoat.DECK_Y + 1.5, 8.6)), Vector3(2.4, RiverBoat.DECK_Y + 0.5, -6.45))
	await _shoot_check("across the deck", boat.to_global(Vector3(2.5, RiverBoat.DECK_Y + 1.6, 9.8)), Vector3(-RiverBoat.BEAM * 0.5 + 0.08, RiverBoat.DECK_Y + 0.5, 9.8))

	# Two bandits on the bow.
	for i in 2:
		var g := Gunman.new()
		g.glb = GunmanBody.BANDITS[i]
		g.name = ["Raider", "Brute"][i]
		add_child(g)
		g.global_position = boat.to_global([Vector3(2.4, 1.3, -9.7), Vector3(-0.4, 1.3, -9.8)][i])
		g.target = player
		boat.watch(g)
		gunmen.append(g)
	var fight_t := 0.0
	var shots_taken := false
	while fight_t < 22.0:
		var phase := fmod(fight_t, 3.2)
		var up := phase > 1.4
		_aim_at = _nearest_gunman()
		_press("aim", up and _aim_at != null)
		_fire = up and phase > 1.9 and _aim_at != null and fight_t > 8.0  # first 8 s: pop up, don't shoot
		if fight_t > 10.0 and not shots_taken:
			shots_taken = true
			await _shot("boat_5_fight_view.png")
			_chase_cam(false)
			await _shot("boat_6_fight_chase.png")
			player.camera.current = true
		if fmod(fight_t, 2.0) < get_physics_process_delta_time():
			for g in gunmen:
				if is_instance_valid(g):
					var sp: Variant = g._spot.get("pos", null)
					print("RESULT gunman t=%.0f %s %s local %s spot %s sees=%s aimed=%.2f ammo=%d" % [fight_t, g.name,
						Gunman.State.keys()[g.state], boat.to_local(g.global_position).snapped(Vector3.ONE * 0.1),
						boat.to_local(sp).snapped(Vector3.ONE * 0.1) if sp != null else "-", g._sees, g._aimed, g.ammo])
		await get_tree().physics_frame
		fight_t += get_physics_process_delta_time()
	_press("aim", false)
	_fire = false
	var states := gunmen.map(func(g): return "%s:%s fired %d" % [g.name, Gunman.State.keys()[g.state], g.shots_fired] if is_instance_valid(g) else "gone")
	var on_board := gunmen.filter(func(g): return is_instance_valid(g) and boat.on_deck(g.global_position)).size()
	print("RESULT fight: player fired %d, hits on them %d, hits on player %d, gunmen %s" % [_fired, _hits, _hurt, states])
	var their_shots: int = gunmen.reduce(func(acc, g): return acc + (g.shots_fired if is_instance_valid(g) else 0), 0)
	_check(_fired > 0 and their_shots > 0, "both sides fired on the moving deck (player %d, bandits %d)" % [_fired, their_shots])
	print("RESULT hit rates (aim balance, not boat): player %d / %d, bandits %d / %d" % [_hits, _fired, _hurt, their_shots])
	_check(on_board == gunmen.filter(func(g): return is_instance_valid(g)).size(), "living gunmen still on the deck (%d)" % on_board)

	# Overboard.
	var falls_before := boat.falls
	player.cover.leave()
	player.global_position = boat.to_global(Vector3(6.0, 2.5, 0.0))
	player.velocity = Vector3.ZERO
	await _wait(3.0)
	_check(boat.falls == falls_before + 1 and boat.on_deck(player.global_position),
			"fell in and came back on deck (falls %d, on deck %s)" % [boat.falls, boat.on_deck(player.global_position)])
	await _shot("boat_7_after_fall.png")
	print("RESULT falls total %d (player and gunmen), boat at %.0f / %.0f m, speed %.1f m/s" % [boat.falls, boat.progress, boat.length_m(), boat.speed])
	_check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "mouse never captured")

	print("RESULT boat_test %s fails=%d" % ["PASS" if _fails == 0 else "FAIL", _fails])
	await _wait(0.2)
	get_tree().quit(0 if _fails == 0 else 1)


## Fire one round (Bullets, the player's speed) from `from` at deck-local `aim_local`; check it lands
## within 0.15 m of the aimed point in the deck's frame (rounds don't inherit the boat's speed).
func _shoot_check(what: String, from: Vector3, aim_local: Vector3) -> void:
	var aim := boat.to_global(aim_local)
	var landed: Array = []
	var ex: Array[RID] = [player.get_rid()]
	Bullets.fire(get_tree(), from, aim - from, player.weapons[player.current].bullet_speed, 100.0, 1, ex,
		func(hit: Dictionary, _d: Vector3, _t: float): landed.append(boat.to_local(hit.position)))
	var t := 0.0
	while landed.is_empty() and t < 1.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	var off: float = (landed[0] - aim_local).length() if not landed.is_empty() else INF
	print("RESULT round %s: aimed %s landed %s (%.3f m off, %.1f m)" % [what, aim_local.snapped(Vector3.ONE * 0.01),
		landed[0].snapped(Vector3.ONE * 0.01) if not landed.is_empty() else "nothing", off, from.distance_to(aim)])
	_check(off < 0.15, "round %s lands where aimed on the moving deck (%.3f m)" % [what, off])


func _report_still(what: String, drift: Vector3) -> void:
	var flat := Vector2(drift.x, drift.z).length()
	var mx := 0.0
	var sum := 0.0
	for s in _steps:
		mx = maxf(mx, s)
		sum += s
	var mean := sum / maxf(_steps.size(), 1)
	print("RESULT %s on deck: drift %.3f m flat (%.3f up), per-frame local step mean %.4f max %.4f m, off floor %d/%d frames, camera jerk %.4f (boat %.4f) m, boat %.1f m/s" % [
		what, flat, drift.y, mean, mx, _off_floor, _frames, _cam_jerk, _boat_jerk, boat.speed])
	_check(flat < 0.05, "%s: no slide on the deck (%.3f m)" % [what, flat])
	_check(mx < 0.01, "%s: no jitter (max step %.4f m)" % [what, mx])
	_check(_off_floor <= 2, "%s: feet stay on the deck (%d frames off)" % [what, _off_floor])
	print("RESULT %s big steps (>5 mm): %s" % [what, _big])
	_steps.clear()
	_big.clear()
	_off_floor = 0
	_frames = 0
	_cam_jerk = 0.0
	_boat_jerk = 0.0
	_cam_hist.clear()
	_boat_hist.clear()
	_local_prev = Vector3.INF


func _physics_process(_delta: float) -> void:
	if _measure:
		var l := boat.to_local(player.global_position)
		if _local_prev != Vector3.INF:
			_steps.append((l - _local_prev).length())
			if _steps[-1] > 0.005:
				_big.append("f%d %.3f m v%.2f %s" % [_frames, _steps[-1], boat.speed, (l - _local_prev).snapped(Vector3.ONE * 0.001)])
		_local_prev = l
		_frames += 1
		if not player.is_on_floor():
			_off_floor += 1
	if _aim_at != null and is_instance_valid(_aim_at):
		var d := (_aim_at.global_position + Vector3.UP * 1.3) - player.camera.global_position
		player.yaw = lerp_angle(player.yaw, atan2(-d.x, -d.z), 0.3)
		player.pitch = lerpf(player.pitch, asin(clampf(d.normalized().y, -1, 1)), 0.3)
		var err := absf(angle_difference(player.yaw, atan2(-d.x, -d.z)))
		_press("fire", _fire and err < deg_to_rad(3.0))
	else:
		_press("fire", false)
	if _route_i < _route.size():
		var goal := boat.to_global(_route[_route_i] + Vector3(0, RiverBoat.DECK_Y, 0))
		var d := goal - player.global_position
		if Vector2(d.x, d.z).length() < 0.3:
			_route_i += 1
		else:
			player.yaw = atan2(-d.x, -d.z)
		_press("move_forward", _route_i < _route.size())
	if _chase.current:
		_chase.look_at_from_position(boat.to_global(Vector3(16, 11, 20)), boat.to_global(Vector3(0, 2, 0)))


func _process(_delta: float) -> void:
	if not _measure:
		return
	# Smoothness: the second difference of the camera's world position per drawn frame, against
	# the same for a point on the deck (what the boat's own motion gives).
	_cam_hist.append(player.camera.global_position)
	_boat_hist.append(boat.to_global(Vector3(0, 3, 0)))
	if _cam_hist.size() > 3:
		_cam_hist.pop_front()
		_boat_hist.pop_front()
	if _cam_hist.size() == 3:
		_cam_jerk = maxf(_cam_jerk, (_cam_hist[2] - 2.0 * _cam_hist[1] + _cam_hist[0]).length())
		_boat_jerk = maxf(_boat_jerk, (_boat_hist[2] - 2.0 * _boat_hist[1] + _boat_hist[0]).length())


func _walk(points: Array, limit: float) -> bool:
	_route = points
	_route_i = 0
	var t := 0.0
	while _route_i < _route.size() and t < limit:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	_press("move_forward", false)
	return _route_i >= _route.size()


func _e() -> Interactable:
	var it := Interactable.pick(get_tree(), player.global_position, -Basis(Vector3.UP, player.yaw).z)
	if it:
		it.use(player)
	return it


func _boat_yaw() -> float:
	var f := -boat.global_basis.z
	return atan2(-f.x, -f.z)


func _nearest_gunman() -> Gunman:
	var best: Gunman = null
	var bd := INF
	var space := get_world_3d().direct_space_state
	for g in gunmen:
		if not is_instance_valid(g) or g.state == Gunman.State.DEAD:
			continue
		var q := PhysicsRayQueryParameters3D.create(player.camera.global_position, g.global_position + Vector3.UP * 1.3, 1)
		if not space.intersect_ray(q).is_empty():
			continue
		var d := g.global_position.distance_to(player.global_position)
		if d < bd:
			bd = d
			best = g
	return best


func _chase_cam(behind: bool) -> void:
	_chase.current = true
	var off := Vector3(16, 11, 20) if behind else Vector3(12, 8, -6)
	_chase.look_at_from_position(boat.to_global(off), boat.to_global(Vector3(0, 2, 0)))


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
	var path_png := _dir.path_join(file)
	get_viewport().get_texture().get_image().save_png(path_png)
	print("RESULT shot %s" % ProjectSettings.globalize_path(path_png))
