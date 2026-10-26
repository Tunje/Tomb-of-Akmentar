extends Node3D
## Companions: 2 follow a god-mode Player bot through three rooms (offset doorways), are told to
## hold for a while and to follow again (the G order), then fight 3 bandits from cover in the
## arena beyond. Args after "--":
##   --seconds=80        quit after this long
##   --mummies           2 mummies also come at the party during the fight
##   --shots=10,40,55    screenshot times (s): player view, overview, close-up of a companion
##   --shot-dir=C:/path  where PNGs go (default user://shots)
## Prints RESULT lines: follow distances, stuck counts, hold drift, then hit rates and who died.

const COMPANIONS := [["eleanor", "res://assets/characters/explorer/explorer.glb"],
	["hassan", "res://assets/characters/bandits/bandit_scout.glb"]]
## The bot's walk: start room, doorway, middle room, doorway, last room, doorway, arena.
const ROUTE := [Vector3(0, 0, 15), Vector3(6, 0, 8), Vector3(6, 0, 4), Vector3(-5, 0, 1),
	Vector3(-5, 0, -2), Vector3(0, 0, -4.4)]
const HOLD_AT := 1  # on reaching ROUTE[1], order hold, wait, then order follow
const WALLS := [
	# centre, size
	[Vector3(0, 1.5, 30), Vector3(24, 3, 0.6)], [Vector3(0, 1.5, -30), Vector3(24, 3, 0.6)],
	[Vector3(-12, 1.5, 0), Vector3(0.6, 3, 60)], [Vector3(12, 1.5, 0), Vector3(0.6, 3, 60)],
	[Vector3(-6.5, 1.5, 20), Vector3(11, 3, 0.6)], [Vector3(6.5, 1.5, 20), Vector3(11, 3, 0.6)],  # door x -1..1
	[Vector3(-3.5, 1.5, 10), Vector3(17, 3, 0.6)], [Vector3(9.5, 1.5, 10), Vector3(5, 3, 0.6)],  # door x 5..7
	[Vector3(-9, 1.5, 0), Vector3(6, 3, 0.6)], [Vector3(4, 1.5, 0), Vector3(16, 3, 0.6)],  # door x -6..-4
]
const COVER_BOXES := [
	[Vector3(0, 0.55, -5.5), Vector3(3.0, 1.1, 0.7)],  # the player's
	[Vector3(-5, 0.55, -8), Vector3(2.4, 1.1, 0.7)],
	[Vector3(5, 0.55, -7.5), Vector3(2.4, 1.1, 0.7)],
	[Vector3(-8, 0.55, -13), Vector3(2.4, 1.1, 0.7)],
	[Vector3(7, 0.55, -13), Vector3(2.4, 1.1, 0.7)],
	[Vector3(0, 1.1, -16), Vector3(1.6, 2.2, 0.9)],
	[Vector3(-5, 0.55, -20), Vector3(2.4, 1.1, 0.7)],
	[Vector3(4, 0.55, -21), Vector3(2.4, 1.1, 0.7)],
	[Vector3(9, 0.55, -18), Vector3(2.4, 1.1, 0.7)],
]

var args := {}
var player: Player
var companions: Array[Gunman] = []
var bandits: Array[Gunman] = []
var mummies: Array[Mummy] = []
var _nav: NavigationRegion3D
var _cam: Camera3D
var _t := 0.0
var _shots: Array[float] = []
var _dir := "user://shots"
var _route_i := 0
var _path := PackedVector3Array()
var _repath := 0.0
var _phase := "walk"  # walk, hold, walk2, cover, fight
var _phase_t := 0.0
var _hold_from := {}
var _hold_drift := {}
var _max_gap := {}
var _far_time := {}
var _hp_start := {}
var _fight_t := 0.0
var _player_hits := 0
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
	_build_map()

	player = Player.new()
	add_child(player)
	player.set_process_unhandled_input(false)
	player.max_health = 100000.0
	player.health = 100000.0
	player.global_position = Vector3(0, 0, 25)
	player.damaged.connect(func(_a): _player_hits += 1)
	var hud := Hud.new()
	hud.player = player
	add_child(hud)

	Game.reset()
	for c: Array in COMPANIONS:
		Game.apply([{"recruit": c[0]}])
	Game.apply([{"recruit": "nobody"}, {"kill": "nobody"}])  # dead: must not spawn
	for i in COMPANIONS.size() + 1:
		var id: String = COMPANIONS[i][0] if i < COMPANIONS.size() else "nobody"
		var g := Gunman.make_companion(id, player, COMPANIONS[i][1] if i < COMPANIONS.size() else "")
		if g == null:
			print("RESULT companion %s not in party, not spawned" % id)
			continue
		add_child(g)
		g.global_position = Vector3(-1.5 + i * 3.0, 0, 27)
		companions.append(g)
		_max_gap[g.name] = 0.0
		_far_time[g.name] = 0.0
		_hp_start[g.name] = g.health

	for i in 3:
		var b := Gunman.new()
		b.glb = GunmanBody.BANDITS[i]
		b.name = ["Raider", "Brute", "Gunhand"][i]
		add_child(b)
		b.global_position = Vector3(-5 + i * 5, 0, -25)
		bandits.append(b)

	_cam = Camera3D.new()
	_cam.fov = 60.0
	add_child(_cam)
	print("RESULT start companions=%d party=%s" % [companions.size(), str(Game.party())])


func _build_map() -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.55, 0.62, 0.7)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.6, 0.58, 0.55)
	env.environment.ambient_light_energy = 0.6
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-60, 30, 0)
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
	_box(Vector3(0, -0.5, 0), Vector3(24, 1, 60), sand)
	for w: Array in WALLS:
		_box(w[0], w[1], stone)
	for c: Array in COVER_BOXES:
		var b := _box(c[0], c[1], stone)
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
	_phase_t += delta
	match _phase:
		"walk", "walk2":
			_walk(delta)
		"hold":
			_stand()
			if _phase_t > 6.0:
				for c in companions:
					_hold_drift[c.name] = c.global_position.distance_to(_hold_from[c.name])
				var order := Gunman.toggle_party_order(get_tree())
				print("RESULT order %s t=%.1f drift=%s" % [order, _t, _fmt(_hold_drift)])
				_phase = "walk2"
				_phase_t = 0.0
		"cover":
			_stand()
			player.yaw = 0.0
			_press("cover", _phase_t > 0.2 and _phase_t < 0.3)
			if _phase_t > 0.5:
				_phase = "fight"
				_phase_t = 0.0
		"fight":
			_fight_t += delta
			_bot_fight()
	_track(delta)
	if _phase == "fight" and fmod(_fight_t, 5.0) < delta:
		_report()
	if _shots.size() > 0 and _t >= _shots[0]:
		var at: float = _shots.pop_front()
		_screenshot("companion_%05.1f" % at)
	if _t >= float(args.get("seconds", "80")):
		_finish()


func _walk(delta: float) -> void:
	var goal: Vector3 = ROUTE[_route_i]
	if _flat(goal - player.global_position).length() < 0.4:
		print("RESULT route %d reached t=%.1f gaps=%s" % [_route_i, _t, _gaps()])
		_route_i += 1
		_path = PackedVector3Array()
		if _route_i - 1 == HOLD_AT and _phase == "walk":
			var order := Gunman.toggle_party_order(get_tree())
			for c in companions:
				_hold_from[c.name] = c.global_position
			print("RESULT order %s t=%.1f" % [order, _t])
			_phase = "hold"
			_phase_t = 0.0
			return
		if _route_i >= ROUTE.size():
			_phase = "cover"
			_phase_t = 0.0
			for b in bandits:
				b.target = player  # the ambush starts
			if args.has("mummies"):
				_spawn_mummies()
			return
		return
	_repath -= delta
	if _repath <= 0.0 or _path.is_empty():
		_repath = 0.5
		_path = NavigationServer3D.map_get_path(get_world_3d().navigation_map, player.global_position, goal, true)
	while _path.size() > 1 and _flat(_path[0] - player.global_position).length() < 0.5:
		_path.remove_at(0)
	var wp: Vector3 = _path[0] if not _path.is_empty() else goal
	var d := _flat(wp - player.global_position)
	if d.length() > 0.05:
		player.yaw = atan2(-d.x, -d.z)
	_press("move_forward", true)


func _stand() -> void:
	for a in ["move_forward", "move_back", "move_left", "move_right", "aim", "fire"]:
		_press(a, false)


## Every 6 s pop up for 2.5 s and shoot the nearest enemy that's up.
func _bot_fight() -> void:
	var cycle := fmod(_fight_t, 6.0)
	var pop := _fight_t > 2.0 and cycle > 3.5
	_press("aim", pop)
	var g := _nearest_enemy()
	if not pop or g == null:
		_press("fire", false)
		return
	var at := g.global_position + Vector3.UP * (1.3 if not (g is Gunman and (g as Gunman).crouched) else 0.9)
	var d := at - player.camera.global_position
	var want_yaw := atan2(-d.x, -d.z)
	var want_pitch := asin(clampf(d.normalized().y, -1, 1))
	var k := minf(get_physics_process_delta_time() * 8.0, 1.0)
	player.yaw = lerp_angle(player.yaw, want_yaw, k)
	player.pitch = lerpf(player.pitch, want_pitch, k)
	var err := absf(angle_difference(player.yaw, want_yaw)) + absf(player.pitch - want_pitch)
	_press("fire", err < deg_to_rad(2.0) and cycle > 4.0 and not (g is Gunman and (g as Gunman).crouched))


func _nearest_enemy() -> Node3D:
	var best: Node3D = null
	var bd := INF
	var space := get_world_3d().direct_space_state
	var eye := player.global_position + Vector3.UP * 1.6
	var all: Array = []
	all.append_array(bandits)
	all.append_array(mummies)
	for n in all:
		if not is_instance_valid(n) or not n.is_active():
			continue
		var q := PhysicsRayQueryParameters3D.create(eye, (n as Node3D).global_position + Vector3.UP * 1.2, 1)
		var dd := eye.distance_to((n as Node3D).global_position)
		if space.intersect_ray(q).is_empty() and dd < bd:
			bd = dd
			best = n
	return best


func _spawn_mummies() -> void:
	for x in [-9.0, 9.0]:
		var m := Mummy.new()
		add_child(m)
		m.add_to_group("mummies")  # until mummy.gd joins the group itself
		m.global_position = Vector3(x, 0, -24)
		m.target = player
		m.wake()
		mummies.append(m)


func _track(delta: float) -> void:
	if _phase in ["walk", "walk2"]:
		for c in companions:
			if not c.is_active():
				continue
			var gap := _flat(c.global_position - player.global_position).length()
			_max_gap[c.name] = maxf(_max_gap[c.name], gap)
			if gap > Gunman.CATCH_UP + 2.0:
				_far_time[c.name] += delta


func _press(action: String, on: bool) -> void:
	if on and not Input.is_action_pressed(action):
		Input.action_press(action)
	elif not on and Input.is_action_pressed(action):
		Input.action_release(action)


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0, v.z)


func _gaps() -> String:
	var parts := PackedStringArray()
	for c in companions:
		parts.append("%s=%.1f" % [c.companion_id, _flat(c.global_position - player.global_position).length()])
	return ",".join(parts)


func _fmt(d: Dictionary) -> String:
	var parts := PackedStringArray()
	for k in d:
		parts.append("%s=%.2f" % [k, d[k]])
	return ",".join(parts)


# ---------------------------------------------------------------- output

func _report() -> void:
	var parts := PackedStringArray()
	for g in companions + bandits:
		var to: Vector3 = g._spot.get("pos", g.global_position)
		parts.append("%s:%s hp=%d at=(%.1f,%.1f) spot=(%.1f,%.1f) tgt=%s" % [g.name.trim_prefix("Companion_"), Gunman.State.keys()[g.state],
			int(g.health), g.global_position.x, g.global_position.z, to.x, to.z, g.target.name.trim_prefix("Companion_") if g.target else "-"])
	print("RESULT t=%.0f %s" % [_t, " | ".join(parts)])


func _screenshot(base: String) -> void:
	if DisplayServer.get_name() == "headless":  # frame_post_draw never fires headless
		return
	await RenderingServer.frame_post_draw
	_save(base + "_play.png")
	_cam.look_at_from_position(Vector3(0, 34, 22), Vector3(0, 0, 2))
	_cam.current = true
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	_save(base + "_top.png")
	for c in companions:
		if c.is_active():
			var chest := c.global_position + Vector3.UP * 1.2
			_cam.look_at_from_position(chest + c.global_basis * Vector3(1.4, 0.3, -2.2), chest)
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw
			_save(base + "_near_%s.png" % c.companion_id)
			break
	player.camera.current = true


func _save(file: String) -> void:
	var path := _dir.path_join(file)
	get_viewport().get_texture().get_image().save_png(path)
	print("RESULT shot %s" % ProjectSettings.globalize_path(path))


func _finish() -> void:
	_done = true
	for c in companions:
		print("RESULT companion %s state=%s hp=%d/%d alive=%s in_party=%s fired=%d hit=%d (%.0f%%) max_gap=%.1f far=%.1fs stuck=%d hold_drift=%.2f" % [
			c.companion_id, Gunman.State.keys()[c.state], int(c.health), int(_hp_start[c.name]), c.is_active(),
			Game.in_party(c.companion_id), c.shots_fired, c.shots_hit, 100.0 * c.shots_hit / maxf(c.shots_fired, 1),
			_max_gap[c.name], _far_time[c.name], c.stuck_count, _hold_drift.get(c.name, -1.0)])
	for b in bandits:
		print("RESULT bandit %s state=%s hp=%d fired=%d hit=%d (%.0f%%) target=%s stuck=%d" % [b.name, Gunman.State.keys()[b.state],
			int(b.health), b.shots_fired, b.shots_hit, 100.0 * b.shots_hit / maxf(b.shots_fired, 1),
			b.target.name if b.target else "-", b.stuck_count])
	var mummies_dead := 0
	for m in mummies:
		if not is_instance_valid(m) or not m.is_active():
			mummies_dead += 1
		else:
			print("RESULT mummy state=%s hp=%d target=%s" % [Mummy.State.keys()[m.state], int(m.health), m.target.name if m.target else "-"])
	if not mummies.is_empty():
		print("RESULT mummies dead=%d/%d" % [mummies_dead, mummies.size()])
	# A companion who dies leaves the party (Game kill).
	var c := companions[0]
	if c.is_active():
		c.take_damage(10000.0, c.global_position + Vector3.FORWARD)
	print("RESULT death_check %s alive=%s in_party=%s party=%s" % [c.companion_id, c.is_active(), Game.in_party(c.companion_id), str(Game.party())])
	print("RESULT summary t=%.1f phase=%s route=%d/%d hits_on_player=%d bandits_alive=%d companions_alive=%d" % [
		_t, _phase, _route_i, ROUTE.size(), _player_hits, bandits.filter(func(b): return b.is_active()).size(),
		companions.filter(func(c): return c.is_active()).size()])
	await get_tree().create_timer(0.3).timeout
	get_tree().quit(0)


## Copied from main.gd's _setup_input (plus G for party orders).
func _setup_input() -> void:
	var keys := {
		"move_forward": [KEY_W], "move_back": [KEY_S], "move_left": [KEY_A], "move_right": [KEY_D],
		"sprint": [KEY_SHIFT], "crouch": [KEY_C, KEY_CTRL], "dodge": [KEY_SPACE],
		"reload": [KEY_R], "cover": [KEY_E], "weapon_1": [KEY_1], "weapon_2": [KEY_2], "weapon_3": [KEY_3],
		"party_order": [KEY_G],
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
