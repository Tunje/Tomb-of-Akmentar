extends Node3D
## Gunman arena: floor, cover boxes, baked navmesh, a god-mode Player bot and 3 bandits. Args after "--":
##   --scenario=fight    bot holds cover and pops up to shoot the nearest gunman (default)
##   --scenario=passive  bot crouches in cover and never shoots (they should flank)
##   --scenario=open     bot strafes in the open and never shoots (their hit rate on a mover)
##   --seconds=45        quit after this long
##   --shots=5,12,20     screenshot times (s); each gives a player view and an overview
##   --shot-dir=C:/path  where PNGs go (default user://shots)
## Prints RESULT lines: gunman states every 5 s, then shots fired, hits on the player, time in cover.

const COVER_BOXES := [
	# centre, size (x length, y height, z depth), yaw degrees
	[Vector3(0, 0.55, 10.5), Vector3(2.4, 1.1, 0.7), 0.0],  # the player's
	[Vector3(-6, 0.55, 2), Vector3(2.4, 1.1, 0.7), 0.0],
	[Vector3(6, 0.55, 1), Vector3(2.4, 1.1, 0.7), 0.0],
	[Vector3(-2.5, 1.1, -3), Vector3(1.6, 2.2, 0.9), 0.0],
	[Vector3(3, 1.1, -4), Vector3(2.0, 2.2, 0.9), 0.0],
	[Vector3(-8, 0.55, -7), Vector3(2.4, 1.1, 0.7), 0.0],
	[Vector3(8, 0.55, -6), Vector3(2.4, 1.1, 0.7), 0.0],
	[Vector3(0, 0.55, -10), Vector3(3.0, 1.1, 0.7), 0.0],
	[Vector3(11, 0.55, 9), Vector3(2.4, 1.1, 0.7), 90.0],  # flank spots
	[Vector3(-11, 0.55, 9), Vector3(2.4, 1.1, 0.7), 90.0],
]
const HALF := 22.0

var args := {}
var player: Player
var hud: Hud
var gunmen: Array[Gunman] = []
var _nav: NavigationRegion3D
var _top_cam: Camera3D
var _t := 0.0
var _shots: Array[float] = []
var _dir := "user://shots"
var _player_hits := 0
var _player_damage := 0.0
var _player_fired := 0
var _player_hits_on_them := 0
var _kills := 0
var _report_t := 0.0
var _done := false


func _ready() -> void:
	get_window().set_flag(Window.FLAG_NO_FOCUS, true)
	_setup_input()
	args = TestDriver.parse_args()
	for s in str(args.get("shots", "")).split(",", false):
		_shots.append(float(s))
	_shots.sort()
	_dir = args.get("shot-dir", _dir)
	DirAccess.make_dir_recursive_absolute(_dir)
	_build_arena()

	player = Player.new()
	add_child(player)
	player.set_process_unhandled_input(false)
	player.max_health = 100000.0
	player.health = 100000.0
	player.global_position = Vector3(0, 0, 11.4)
	player.yaw = 0.0
	player.damaged.connect(func(amount: float):
		_player_hits += 1
		_player_damage += amount)
	player.fired.connect(func(): _player_fired += 1)
	player.hit_confirmed.connect(func(killed: bool, _head: bool):
		_player_hits_on_them += 1
		if killed:
			_kills += 1)
	hud = Hud.new()
	hud.player = player
	add_child(hud)
	player.hit_confirmed.connect(hud.on_hit)
	player.damaged.connect(hud.on_damaged)

	for i in 3:
		var g := Gunman.new()
		g.glb = GunmanBody.BANDITS[i]
		g.name = ["Raider", "Brute", "Gunhand"][i]
		add_child(g)
		g.global_position = Vector3(-6 + i * 6, 0, -17)
		g.target = player
		gunmen.append(g)

	_top_cam = Camera3D.new()
	_top_cam.fov = 60.0
	add_child(_top_cam)
	_top_cam.look_at_from_position(Vector3(0, 26, 24), Vector3(0, 0, -1))
	print("RESULT start scenario=%s" % args.get("scenario", "fight"))


func _build_arena() -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.55, 0.62, 0.7)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.6, 0.58, 0.55)
	env.environment.ambient_light_energy = 0.6
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 35, 0)
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	add_child(sun)

	_nav = NavigationRegion3D.new()
	var nm := NavigationMesh.new()
	nm.agent_radius = 0.4
	nm.agent_height = 1.8
	nm.agent_max_climb = 0.2
	nm.cell_size = 0.2
	nm.cell_height = 0.2
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_collision_mask = 1
	_nav.navigation_mesh = nm
	add_child(_nav)
	var map := get_world_3d().navigation_map
	NavigationServer3D.map_set_cell_size(map, nm.cell_size)
	NavigationServer3D.map_set_cell_height(map, nm.cell_height)

	var sand := _mat(Color(0.72, 0.62, 0.45))
	var stone := _mat(Color(0.55, 0.5, 0.42))
	_box(Vector3(0, -0.5, 0), Vector3(HALF * 2, 1, HALF * 2), sand)
	for side in [Vector3(0, 1.5, -HALF), Vector3(0, 1.5, HALF)]:
		_box(side, Vector3(HALF * 2, 3, 1), stone)
	for side in [Vector3(-HALF, 1.5, 0), Vector3(HALF, 1.5, 0)]:
		_box(side, Vector3(1, 3, HALF * 2), stone)
	for c: Array in COVER_BOXES:
		var b := _box(c[0], c[1], stone)
		b.rotation_degrees.y = c[2]
		# Tagged like level.gd's _mark_cover.
		b.set_meta("cover_size", c[1])
		b.add_to_group("cover")
	_nav.bake_navigation_mesh(false)


func _box(pos: Vector3, size: Vector3, mat: Material) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	shape.shape = bs
	body.add_child(shape)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	body.add_child(mi)
	_nav.add_child(body)
	body.position = pos
	return body


func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.95
	return m


# ---------------------------------------------------------------- bot

func _physics_process(delta: float) -> void:
	if _done:
		return
	_t += delta
	match str(args.get("scenario", "fight")):
		"fight":
			_bot_cover(true)
		"passive":
			_bot_cover(false)
		"open":
			_bot_open()
	_report_t += delta
	if _report_t >= 5.0:
		_report_t = 0.0
		_report()
	if _shots.size() > 0 and _t >= _shots[0]:
		var at: float = _shots.pop_front()
		_screenshot("gunman_%05.1f" % at)
	if _t >= float(args.get("seconds", "45")):
		_finish()


## Take cover behind the box in front (E), then every 6 s pop up for 2.5 s and shoot.
func _bot_cover(shoot: bool) -> void:
	if _t > 0.3 and _t < 0.4:
		_press("cover", true)
	elif _t >= 0.4:
		_press("cover", false)
	var cycle := fmod(_t, 6.0)
	var pop := shoot and _t > 3.0 and cycle > 3.5
	var g := _nearest_visible()
	_press("aim", pop)
	if not pop or g == null:
		_press("fire", false)
		return
	var err := _aim_at(g, get_physics_process_delta_time())
	_press("fire", err < deg_to_rad(2.0) and cycle > 4.0 and g.state != Gunman.State.COVER and g.state != Gunman.State.RELOAD)


## Strafe left and right in the open, facing them.
func _bot_open() -> void:
	if _t < 0.1:
		player.global_position = Vector3(0, 0, 15)
	var right := fmod(_t, 4.0) < 2.0
	_press("move_right", right)
	_press("move_left", not right)
	var g := _nearest_visible()
	if g:
		_aim_at(g, get_physics_process_delta_time())


func _aim_at(g: Gunman, delta: float) -> float:
	var at := g.global_position + Vector3.UP * (1.3 if g.state == Gunman.State.AIM or g.state == Gunman.State.MOVE else 0.9)
	var d := at - player.camera.global_position
	var want_yaw := atan2(-d.x, -d.z)
	var want_pitch := asin(clampf(d.normalized().y, -1, 1))
	player.yaw = lerp_angle(player.yaw, want_yaw, minf(delta * 8.0, 1.0))
	player.pitch = lerpf(player.pitch, want_pitch, minf(delta * 8.0, 1.0))
	return absf(angle_difference(player.yaw, want_yaw)) + absf(player.pitch - want_pitch)


func _nearest_visible() -> Gunman:
	var best: Gunman = null
	var bd := INF
	var space := get_world_3d().direct_space_state
	for g in gunmen:
		if not is_instance_valid(g) or not g.is_active():
			continue
		var eye := player.global_position + Vector3.UP * 1.6
		var q := PhysicsRayQueryParameters3D.create(eye, g.global_position + Vector3.UP * 1.3, 1)
		var dd := eye.distance_to(g.global_position)
		if space.intersect_ray(q).is_empty() and dd < bd:
			bd = dd
			best = g
	return best


func _press(action: String, on: bool) -> void:
	if on and not Input.is_action_pressed(action):
		Input.action_press(action)
	elif not on and Input.is_action_pressed(action):
		Input.action_release(action)


# ---------------------------------------------------------------- output

func _report() -> void:
	var parts := PackedStringArray()
	for g in gunmen:
		if is_instance_valid(g):
			var at := g.global_position
			var to: Vector3 = g._spot.get("pos", at)
			parts.append("%s hp=%d ammo=%d %s%s at=(%.1f,%.1f) spot=(%.1f,%.1f)" % [Gunman.State.keys()[g.state], int(g.health),
				g.ammo, "F" if g.flanking else "", "R" if g.retreating else "", at.x, at.z, to.x, to.z])
	print("RESULT t=%.0f player_cover=%s gunmen=[%s]" % [_t, Cover.State.keys()[player.cover.state], ", ".join(parts)])


func _screenshot(base: String) -> void:
	await RenderingServer.frame_post_draw
	_save(base + "_play.png")
	_top_cam.current = true
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	_save(base + "_top.png")
	# Close up on the first living gunman, from his front quarter.
	for g in gunmen:
		if is_instance_valid(g) and g.is_active():
			var chest := g.global_position + Vector3.UP * 1.2
			_top_cam.look_at_from_position(chest + g.global_basis * Vector3(1.6, 0.3, -2.4), chest)
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw
			_save(base + "_near_%s.png" % g.name)
			_top_cam.look_at_from_position(Vector3(0, 26, 24), Vector3(0, 0, -1))
			break
	player.camera.current = true


func _save(file: String) -> void:
	var path := _dir.path_join(file)
	get_viewport().get_texture().get_image().save_png(path)
	print("RESULT shot %s" % ProjectSettings.globalize_path(path))


func _finish() -> void:
	_done = true
	var fired := 0
	var hit := 0
	var cover := 0.0
	var alive := 0.0
	var flanks := 0
	for g in gunmen:
		if not is_instance_valid(g):
			continue
		fired += g.shots_fired
		hit += g.shots_hit
		cover += g.cover_time
		alive += g.alive_time
		flanks += g.flanks
		print("RESULT gunman %s state=%s hp=%d fired=%d hit=%d cover=%.1fs/%.1fs flanks=%d retreated=%s" % [
			g.name, Gunman.State.keys()[g.state], int(g.health), g.shots_fired, g.shots_hit,
			g.cover_time, g.alive_time, g.flanks, g.retreating])
	print("RESULT summary t=%.1f scenario=%s gunmen_fired=%d hits_on_player=%d (damage %.0f) hit_rate=%.0f%% cover_time=%.0f%% flanks=%d player_fired=%d player_hits=%d kills=%d" % [
		_t, args.get("scenario", "fight"), fired, _player_hits, _player_damage,
		100.0 * hit / maxf(fired, 1), 100.0 * cover / maxf(alive, 0.01), flanks, _player_fired,
		_player_hits_on_them, _kills])
	await get_tree().create_timer(0.3).timeout
	get_tree().quit(0)


## Copied from main.gd's _setup_input.
func _setup_input() -> void:
	var keys := {
		"move_forward": [KEY_W], "move_back": [KEY_S], "move_left": [KEY_A], "move_right": [KEY_D],
		"sprint": [KEY_SHIFT], "crouch": [KEY_C, KEY_CTRL], "dodge": [KEY_SPACE],
		"reload": [KEY_R], "cover": [KEY_E], "weapon_1": [KEY_1], "weapon_2": [KEY_2], "weapon_3": [KEY_3],
	}
	var mouse := {
		"fire": [MOUSE_BUTTON_LEFT], "aim": [MOUSE_BUTTON_RIGHT],
		"weapon_next": [MOUSE_BUTTON_WHEEL_DOWN], "weapon_prev": [MOUSE_BUTTON_WHEEL_UP],
	}
	for action in keys:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for k in keys[action]:
			var e := InputEventKey.new()
			e.physical_keycode = k
			InputMap.action_add_event(action, e)
	for action in mouse:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for b in mouse[action]:
			var e := InputEventMouseButton.new()
			e.button_index = b
			InputMap.action_add_event(action, e)
