extends Node3D
## Act 4's night attack (NightRaid) on a stand-in surface: three camps on a dark plain, each
## ringed by cover (crates, tall wagon stacks), moonlight and torches. A god-mode Player bot with
## two companions stands at the camp the choice sends him to and shoots the nearest bandit in
## bursts. Args after "--":
##   --choice=barricade|americans|germans   (default barricade)
##   --seed=N            the barricade dice (default random)
##   --seconds=180       quit after this long if the raid hasn't finished
##   --shots=20,40,60    screenshot times (s): player view, overview, close-up of the fight
##   --shot-dir=C:/path  where PNGs go (default user://shots)
## RESULT lines: waves, deaths per side, then the result dict and whether it matches the choice.

const CAMPS := {"party": Vector3(0, 0, 20), "americans": Vector3(-38, 0, -14), "germans": Vector3(38, 0, -14)}
const COMPANIONS := [["eleanor", "res://assets/characters/explorer/explorer.glb"],
	["hassan", "res://assets/characters/bandits/bandit_scout.glb"]]
const HALF := 70.0

var args := {}
var player: Player
var raid: NightRaid
var companions: Array[Gunman] = []
var _nav: NavigationRegion3D
var _cam: Camera3D
var _torches: Array[OmniLight3D] = []
var _t := 0.0
var _shots: Array[float] = []
var _dir := "user://shots"
var _here := Vector3.ZERO
var _result := {}
var _player_hits := 0
var _player_fired := 0
var _player_landed := 0
var _events := PackedStringArray()
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
	Game.reset()
	Game.event.connect(func(e: String): _events.append("%s@%.0f" % [e, _t]))

	var choice: String = args.get("choice", "barricade")
	_here = CAMPS[choice if choice in ["americans", "germans"] else "party"]
	player = Player.new()
	add_child(player)
	player.set_process_unhandled_input(false)
	player.max_health = 100000.0
	player.health = 100000.0
	player.global_position = _here + Vector3(0, 0, 1.2)
	player.damaged.connect(func(_a): _player_hits += 1)
	player.fired.connect(func(): _player_fired += 1)
	player.hit_confirmed.connect(func(_k, _h): _player_landed += 1)
	var hud := Hud.new()
	hud.player = player
	add_child(hud)
	for i in COMPANIONS.size():
		Game.apply([{"recruit": COMPANIONS[i][0]}])
		var c := Gunman.make_companion(COMPANIONS[i][0], player, COMPANIONS[i][1])
		add_child(c)
		c.global_position = _here + Vector3(-1.2 + i * 2.4, 0, 2.6)
		companions.append(c)

	_cam = Camera3D.new()
	_cam.fov = 60.0
	add_child(_cam)
	# Let the navmesh sync before anyone paths.
	await get_tree().physics_frame
	await get_tree().physics_frame
	var seed := int(args.get("seed", "-1"))
	raid = NightRaid.start(self, choice, CAMPS, player, seed)
	raid.finished.connect(_on_finished)
	print("RESULT start choice=%s here=%s seed=%d" % [choice, raid.here, seed])


func _build_map() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.02, 0.03, 0.07)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.25, 0.3, 0.45)
	e.ambient_light_energy = 0.35
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.fog_enabled = true
	e.fog_light_color = Color(0.05, 0.06, 0.1)
	e.fog_density = 0.006
	env.environment = e
	add_child(env)
	var moon := DirectionalLight3D.new()
	moon.rotation_degrees = Vector3(-35, 140, 0)
	moon.light_color = Color(0.6, 0.7, 1.0)
	moon.light_energy = 0.3
	moon.shadow_enabled = true
	add_child(moon)

	_nav = NavigationRegion3D.new()
	var nm := NavigationMesh.new()
	nm.agent_radius = 0.4
	nm.agent_height = 1.8
	nm.agent_max_climb = 0.2
	nm.cell_size = 0.25
	nm.cell_height = 0.2
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_collision_mask = 1
	_nav.navigation_mesh = nm
	add_child(_nav)
	var map := get_world_3d().navigation_map
	NavigationServer3D.map_set_cell_size(map, nm.cell_size)
	NavigationServer3D.map_set_cell_height(map, nm.cell_height)

	var sand := _mat(Color(0.55, 0.47, 0.36))
	var wood := _mat(Color(0.42, 0.3, 0.2))
	var stone := _mat(Color(0.5, 0.46, 0.4))
	_box(Vector3(0, -0.5, 0), Vector3(HALF * 2, 1, HALF * 2), sand, false)
	# Each camp: 8 pieces in a ring, length along the ring; every other one a tall wagon stack.
	for k in CAMPS:
		var c: Vector3 = CAMPS[k]
		for i in 8:
			var a := TAU * i / 8.0
			var tall := i % 2 == 1
			var size := Vector3(1.6, 2.0, 1.2) if tall else Vector3(2.2, 1.1, 0.7)
			var b := _box(c + Vector3(cos(a), 0, sin(a)) * 5.5 + Vector3.UP * size.y * 0.5, size, wood, true)
			b.rotation.y = -a + PI * 0.5
		_torch(c + Vector3(1.0, 1.6, -0.8))
		_torch(c + Vector3(-3.5, 1.8, 3.5))
		_fire(c)
	# Ruins between the camps (the bandits come through them).
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 22:
		var p := Vector3(rng.randf_range(-HALF + 6, HALF - 6), 0, rng.randf_range(-HALF + 6, HALF - 6))
		var near := false
		for k in CAMPS:
			if p.distance_to(CAMPS[k]) < 11.0:
				near = true
		if near:
			continue
		var size := Vector3(rng.randf_range(2.5, 5.0), rng.randf_range(0.95, 1.2), 0.7)
		var w := _box(p + Vector3.UP * size.y * 0.5, size, stone, true)
		w.rotation.y = rng.randf() * PI
	_nav.bake_navigation_mesh(false)


func _box(pos: Vector3, size: Vector3, mat: Material, cover: bool) -> StaticBody3D:
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
	if cover:
		body.set_meta("cover_size", size)
		body.add_to_group("cover")
	return body


func _torch(p: Vector3) -> void:
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.6, 0.3)
	l.light_energy = 2.2
	l.omni_range = 9.0
	l.shadow_enabled = false
	add_child(l)
	l.global_position = p
	l.set_meta("base", l.light_energy)
	_torches.append(l)
	var flame := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.08
	sm.height = 0.16
	flame.mesh = sm
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.albedo_color = Color(1.0, 0.7, 0.35)
	flame.material_override = fm
	l.add_child(flame)


func _fire(c: Vector3) -> void:
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.55, 0.25)
	l.light_energy = 3.0
	l.omni_range = 12.0
	l.shadow_enabled = true
	add_child(l)
	l.global_position = c + Vector3(0, 0.6, 0)
	l.set_meta("base", l.light_energy)
	_torches.append(l)


func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.95
	return m


# ---------------------------------------------------------------- bot

func _process(_delta: float) -> void:
	for i in _torches.size():
		var l := _torches[i]
		var base: float = l.get_meta("base")
		l.light_energy = base * (0.85 + 0.1 * sin(_t * 13.0 + i * 1.7) + 0.06 * sin(_t * 31.0 + i * 4.1))


func _physics_process(delta: float) -> void:
	if _done:
		return
	_t += delta
	if raid:
		_bot(delta)
	if _shots.size() > 0 and _t >= _shots[0]:
		var at: float = _shots.pop_front()
		_screenshot("night_%05.1f" % at)
	if _t >= float(args.get("seconds", "180")):
		print("RESULT timeout: the raid did not finish")
		_finish()


## Every 5 s: 2.5 s of aimed bursts at the nearest bandit in sight.
func _bot(delta: float) -> void:
	var b := _nearest_bandit()
	var cycle := fmod(_t, 5.0)
	var up := b != null and cycle > 2.5
	_press("aim", up)
	if not up:
		_press("fire", false)
		return
	var at := b.global_position + Vector3.UP * (0.9 if b.crouched else 1.3)
	var d := at - player.camera.global_position
	var want_yaw := atan2(-d.x, -d.z)
	var want_pitch := asin(clampf(d.normalized().y, -1, 1))
	var k := minf(delta * 8.0, 1.0)
	player.yaw = lerp_angle(player.yaw, want_yaw, k)
	player.pitch = lerpf(player.pitch, want_pitch, k)
	var err := absf(angle_difference(player.yaw, want_yaw)) + absf(player.pitch - want_pitch)
	_press("fire", err < deg_to_rad(2.0) and cycle > 3.0 and not b.crouched)


func _nearest_bandit() -> Gunman:
	var best: Gunman = null
	var bd := 40.0
	var space := get_world_3d().direct_space_state
	var eye := player.global_position + Vector3.UP * 1.6
	for b in raid.bandits:
		if not is_instance_valid(b) or not b.is_active() or b.surrendered:
			continue
		var dd := eye.distance_to(b.global_position)
		var q := PhysicsRayQueryParameters3D.create(eye, b.global_position + Vector3.UP * 1.3, 1)
		if dd < bd and space.intersect_ray(q).is_empty():
			bd = dd
			best = b
	return best


func _press(action: String, on: bool) -> void:
	if on and not Input.is_action_pressed(action):
		Input.action_press(action)
	elif not on and Input.is_action_pressed(action):
		Input.action_release(action)


# ---------------------------------------------------------------- output

func _on_finished(result: Dictionary) -> void:
	_result = result
	print("RESULT finished t=%.1f result=%s" % [_t, result])
	get_tree().create_timer(1.0).timeout.connect(_finish)


func _screenshot(base: String) -> void:
	if DisplayServer.get_name() == "headless":  # frame_post_draw never fires headless
		return
	await RenderingServer.frame_post_draw
	_save(base + "_play.png")
	_cam.look_at_from_position(_here + Vector3(0, 30, 34), _here + Vector3(0, 0, -6))
	_cam.current = true
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	_save(base + "_camp.png")
	_cam.look_at_from_position(Vector3(0, 70, 60), Vector3(0, 0, -4))
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	_save(base + "_all.png")
	player.camera.current = true


func _save(file: String) -> void:
	var path := _dir.path_join(file)
	get_viewport().get_texture().get_image().save_png(path)
	print("RESULT shot %s" % ProjectSettings.globalize_path(path))


func _finish() -> void:
	if _done:
		return
	_done = true
	var choice: String = args.get("choice", "barricade")
	for team in ["americans", "germans"]:
		var parts := PackedStringArray()
		for g: Gunman in raid.rivals[team]:
			parts.append("%s:%s hp=%d fired=%d hit=%d" % [g.name, Gunman.State.keys()[g.state], int(g.health), g.shots_fired, g.shots_hit])
		print("RESULT %s %s" % [team, ", ".join(parts)])
	var bf := 0
	var bh := 0
	for b in raid.bandits:
		bf += b.shots_fired
		bh += b.shots_hit
		if b.is_active() and not b.surrendered:
			print("RESULT still fighting %s %s at=%s hp=%d target=%s dist=%.0f" % [b.name, Gunman.State.keys()[b.state],
				b.global_position.snapped(Vector3.ONE * 0.1), int(b.health), b.target.name if b.target else "-",
				b.global_position.distance_to(_here)])
	for c in companions:
		print("RESULT companion %s state=%s hp=%d fired=%d hit=%d" % [c.companion_id, Gunman.State.keys()[c.state], int(c.health), c.shots_fired, c.shots_hit])
	print("RESULT bandits n=%d fired=%d hit=%d (%.0f%%) hits_on_player=%d player fired=%d landed=%d events=%s" % [
		raid.bandits.size(), bf, bh, 100.0 * bh / maxf(bf, 1), _player_hits, _player_fired, _player_landed, ",".join(_events)])
	if not _result.is_empty():
		var ok := true
		if choice == "americans":
			ok = _result.americans_alive and not _result.germans_alive
		elif choice == "germans":
			ok = _result.germans_alive and not _result.americans_alive
		print("RESULT outcome %s for choice=%s" % ["matches" if ok else "WRONG", choice])
	print("RESULT summary t=%.1f finished=%s" % [_t, not _result.is_empty()])
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
