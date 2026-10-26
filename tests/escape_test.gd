extends Node3D
## Act 5's escape in miniature: a tomb chamber, a long corridor north with a room halfway and a
## collapsed section to vault, torches (group "fire"), the guardian waking behind the player, two
## scarab bursts, and a companion who stumbles near the end. The bot sprints the route, vaults the
## rubble (Cover W+E), and goes back to help her up, shooting the guardian first if it's close.
## Args after "--":
##   --scenario=escape|trap   escape (default), or trap: the forced royal door's traps on two
##                            American gunmen standing before it (prints who died)
##   --help=yes|no      help the stumbling companion (default yes)
##   --god              the player can't die
##   --seconds=90       quit after this long
##   --shots=6,20,34    screenshot times (s): player view and a view down the corridor
##   --shot-dir=C:/path where PNGs go (default user://shots)
## RESULT lines every 2 s (guardian distance, health), then escaped / damage / guardian stats.

const RUBBLE_Z := -30.0
const BURSTS := [[-16.0, Vector3(2.0, 0.6, -22.0), Vector3(-1, 0, 0)], [-44.0, Vector3(-6.0, 0.6, -52.0), Vector3(1, 0, 0)]]
const STUMBLE_Z := -60.0
const EXIT_Z := -92.0
const ROUTE := [Vector3(0, 0, -8), Vector3(0, 0, -28.6), Vector3(0, 0, -46), Vector3(0, 0, -57), Vector3(0, 0, -93)]

var args := {}
var player: Player
var guardian: Guardian
var eleanor: Gunman
var swarms: Array[ScarabSwarm] = []
var _nav: NavigationRegion3D
var _cam: Camera3D
var _t := 0.0
var _shots: Array[float] = []
var _dir := "user://shots"
var _route_i := 0
var _path := PackedVector3Array()
var _repath := 0.0
var _phase := "run"   # run, vault, help, done
var _phase_t := 0.0
var _bursts_done := 0
var _stumbled := false
var _helped := false
var _damage := 0.0
var _min_gap := INF
var _gaps := PackedStringArray()
var _report_t := 0.0
var _escaped := false
var _done := false
var _lights: Array[OmniLight3D] = []


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

	player = Player.new()
	add_child(player)
	player.set_process_unhandled_input(false)
	if args.has("god"):
		player.max_health = 100000.0
		player.health = 100000.0
	player.global_position = Vector3(0, 0, 3)
	player.damaged.connect(func(a: float): _damage += a)
	var hud := Hud.new()
	hud.player = player
	add_child(hud)
	Game.apply([{"recruit": "eleanor"}])
	eleanor = Gunman.make_companion("eleanor", player, "res://assets/characters/explorer/explorer.glb")
	add_child(eleanor)
	eleanor.global_position = Vector3(1.5, 0, 5)
	eleanor.escape = true
	eleanor.stumbled_down.connect(func(_g): print("RESULT eleanor stumbles t=%.1f" % _t))
	eleanor.helped_up.connect(func(_g):
		_helped = true
		print("RESULT eleanor helped up t=%.1f" % _t))
	eleanor.killed.connect(func(_g): print("RESULT eleanor dies t=%.1f stumbled=%s" % [_t, eleanor.stumbled]))
	_cam = Camera3D.new()
	_cam.fov = 60.0
	add_child(_cam)
	await get_tree().physics_frame
	await get_tree().physics_frame
	if args.get("scenario", "escape") == "trap":
		_trap_scenario()
		return
	guardian = Guardian.new()
	add_child(guardian)
	guardian.global_position = Vector3(0, 0, 10)
	guardian.rotation.y = 0.0
	guardian.target = player
	guardian.caught.connect(func(v): print("RESULT guardian catches %s t=%.1f" % [v.name, _t]))
	guardian.awaken(1.5)
	print("RESULT start escape help=%s" % args.get("help", "yes"))


func _build_map() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.01, 0.01, 0.015)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.35, 0.3, 0.25)
	e.ambient_light_energy = 0.25
	env.environment = e
	add_child(env)
	_nav = NavigationRegion3D.new()
	var nm := NavigationMesh.new()
	nm.agent_radius = 0.45
	nm.agent_height = 1.8
	nm.agent_max_climb = 0.2
	nm.cell_size = 0.15
	nm.cell_height = 0.2
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_collision_mask = 1
	_nav.navigation_mesh = nm
	add_child(_nav)
	var map := get_world_3d().navigation_map
	NavigationServer3D.map_set_cell_size(map, nm.cell_size)
	NavigationServer3D.map_set_cell_height(map, nm.cell_height)
	var floor_m := _mat(Color(0.45, 0.4, 0.32))
	var wall := _mat(Color(0.5, 0.44, 0.35))
	_box(Vector3(0, -0.5, -40), Vector3(16, 1, 110), floor_m)
	# Chamber z +2..+12, x -5..5; corridor x -2..2 from z +2 to -95; room z -46..-56, x -6..6.
	_box(Vector3(0, 2, 12.3), Vector3(10.6, 4, 0.6), wall)
	for x in [-5.3, 5.3]:
		_box(Vector3(x, 2, 7), Vector3(0.6, 4, 10.6), wall)
	for x in [-3.65, 3.65]:
		_box(Vector3(x, 2, 2), Vector3(3.3, 4, 0.6), wall)   # chamber's south face, round the corridor mouth
	for x in [-2.3, 2.3]:
		_box(Vector3(x, 2, -22), Vector3(0.6, 4, 48), wall)  # z +2 .. -46
		_box(Vector3(x, 2, -75.5), Vector3(0.6, 4, 39), wall) # z -56 .. -95
	for z in [-46.0, -56.0]:
		for x in [-4.3, 4.3]:
			_box(Vector3(x, 2, z), Vector3(3.4, 4, 0.6), wall)
	for x in [-6.3, 6.3]:
		_box(Vector3(x, 2, -51), Vector3(0.6, 4, 10.6), wall)
	_box(Vector3(0, 2, -95.3), Vector3(4.6, 4, 0.6), wall)
	# The collapse: a low heap right across the corridor (vault it).
	var rubble := _box(Vector3(0, 0.45, RUBBLE_Z), Vector3(4.0, 0.9, 0.7), _mat(Color(0.55, 0.48, 0.38)))
	rubble.set_meta("cover_size", Vector3(4.0, 0.9, 0.7))
	rubble.add_to_group("cover")
	_nav.bake_navigation_mesh(false)
	var link := NavigationLink3D.new()
	link.start_position = Vector3(0, 0, RUBBLE_Z + 1.1)
	link.end_position = Vector3(0, 0, RUBBLE_Z - 1.1)
	link.bidirectional = true
	add_child(link)
	# Torches on the walls (fire: the scarabs keep off them) and a brazier in the room.
	var zs := [-6.0, -38.0, -64.0, -82.0]
	for i in zs.size():
		_torch(Vector3(2.05 if i % 2 == 0 else -2.05, 1.9, zs[i]), 1.2)
	_torch(Vector3(0, 1.0, -51), FIRE_BRAZIER)
	_torch(Vector3(0, 2.5, 8), 0.0)  # the chamber's light (not fire: just to see the guardian)


const FIRE_BRAZIER := 2.4


func _torch(p: Vector3, fire_radius: float) -> void:
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.6, 0.3)
	l.light_energy = 2.5
	l.omni_range = 10.0
	add_child(l)
	l.global_position = p
	_lights.append(l)
	if fire_radius > 0.0:
		l.add_to_group("fire")
		l.set_meta("fire_radius", fire_radius)
		var flame := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.07
		sm.height = 0.14
		flame.mesh = sm
		var fm := StandardMaterial3D.new()
		fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		fm.albedo_color = Color(1.0, 0.7, 0.35)
		flame.material_override = fm
		l.add_child(flame)


func _box(pos: Vector3, size: Vector3, mat: Material) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
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


# ---------------------------------------------------------------- the run

func _physics_process(delta: float) -> void:
	if _done or guardian == null:
		return
	_t += delta
	_phase_t += delta
	var pz := player.global_position.z
	# Scarab bursts as the player passes.
	while _bursts_done < BURSTS.size() and pz < float(BURSTS[_bursts_done][0]):
		var b: Array = BURSTS[_bursts_done]
		swarms.append(ScarabSwarm.pour(self, b[1], b[2]))
		print("RESULT scarabs burst %d t=%.1f" % [_bursts_done + 1, _t])
		_bursts_done += 1
	if not _stumbled and eleanor.is_active() and eleanor.global_position.z < STUMBLE_Z:
		_stumbled = true
		eleanor.stumble()
		if args.get("help", "yes") == "yes":
			_set_phase("help")
	if player.alive:
		match _phase:
			"run":
				_run(delta)
			"vault":
				_vault()
			"help":
				_help(delta)
	var gap := Vector2(guardian.global_position.x - player.global_position.x, guardian.global_position.z - pz).length()
	_min_gap = minf(_min_gap, gap)
	_report_t += delta
	if _report_t >= 2.0:
		_report_t = 0.0
		_gaps.append("%.0f" % gap)
		print("RESULT t=%.0f z=%.1f phase=%s guardian=%.1fm (%s, slow %.2f) hp=%d eleanor=%s/%d at z=%.1f" % [_t, pz, _phase, gap,
			Guardian.State.keys()[guardian.state], guardian._slow, int(player.health),
			"down" if eleanor.stumbled else Gunman.State.keys()[eleanor.state], int(eleanor.health), eleanor.global_position.z])
	if _shots.size() > 0 and _t >= _shots[0]:
		var at: float = _shots.pop_front()
		_screenshot("escape_%05.1f" % at)
	if player.alive and pz < EXIT_Z and not _escaped:
		_escaped = true
		print("RESULT escaped t=%.1f" % _t)
		get_tree().create_timer(1.0).timeout.connect(_finish)
	if not player.alive:
		print("RESULT player died t=%.1f z=%.1f" % [_t, pz])
		_finish()
	if _t >= float(args.get("seconds", "90")):
		_finish()


func _set_phase(p: String) -> void:
	_phase = p
	_phase_t = 0.0
	for a in ["move_forward", "sprint", "aim", "fire", "cover", "move_back"]:
		_press(a, false)


func _run(delta: float) -> void:
	if _route_i >= ROUTE.size():
		_press("move_forward", false)
		return
	var goal: Vector3 = ROUTE[_route_i]
	if _flat(goal - player.global_position).length() < 0.6:
		_route_i += 1
		_path = PackedVector3Array()
		if _route_i == 2:
			_set_phase("vault")  # at the rubble
		return
	_walk_to(goal, delta, true)


func _walk_to(goal: Vector3, delta: float, sprint: bool) -> void:
	_repath -= delta
	if _repath <= 0.0 or _path.is_empty():
		_repath = 0.4
		_path = NavigationServer3D.map_get_path(get_world_3d().navigation_map, player.global_position, goal, true)
	while _path.size() > 1 and _flat(_path[0] - player.global_position).length() < 0.5:
		_path.remove_at(0)
	var wp: Vector3 = _path[0] if not _path.is_empty() else goal
	var d := _flat(wp - player.global_position)
	if d.length() > 0.05:
		player.yaw = atan2(-d.x, -d.z)
	_press("move_forward", true)
	_press("sprint", sprint)


## E at the rubble's face, then W+E over it.
func _vault() -> void:
	player.yaw = 0.0
	_press("move_forward", false)
	_press("sprint", false)
	var st := player.cover.state
	if _phase_t < 0.1:
		return
	if st == Cover.State.FREE and player.global_position.z > RUBBLE_Z:
		_press("cover", fmod(_phase_t, 0.3) < 0.05)
	elif st == Cover.State.IN_COVER or st == Cover.State.POP_OUT:
		_press("move_forward", true)
		_press("cover", fmod(_phase_t, 0.3) < 0.05)
	elif st == Cover.State.FREE and player.global_position.z < RUBBLE_Z - 0.3:
		print("RESULT vaulted t=%.1f" % _t)
		_set_phase("run")
	if _phase_t > 4.0:
		print("RESULT vault failed t=%.1f state=%s" % [_t, Cover.State.keys()[st]])
		player.global_position.z = RUBBLE_Z - 1.2  # don't sit there forever
		_set_phase("run")


## Back to Eleanor: if the guardian is close, turn and shoot it till it reels; then E on her.
func _help(delta: float) -> void:
	if not eleanor.stumbled or not eleanor.is_active() or _phase_t > 12.0:
		_path = PackedVector3Array()
		_set_phase("run")
		return
	var gd := guardian.global_position.distance_to(player.global_position)
	if gd < 9.0 and guardian.state != Guardian.State.STAGGER and _phase_t < 6.0:
		var at := guardian.global_position + Vector3.UP * 2.0
		var d := at - player.camera.global_position
		var want_yaw := atan2(-d.x, -d.z)
		player.yaw = lerp_angle(player.yaw, want_yaw, minf(delta * 10.0, 1.0))
		player.pitch = lerpf(player.pitch, asin(clampf(d.normalized().y, -1, 1)), minf(delta * 10.0, 1.0))
		_press("move_forward", false)
		_press("sprint", false)
		_press("aim", true)
		_press("fire", absf(angle_difference(player.yaw, want_yaw)) < 0.05 and fmod(_phase_t, 0.5) < 0.25)
		return
	_press("aim", false)
	_press("fire", false)
	var to := _flat(eleanor.global_position - player.global_position)
	if to.length() > 1.3:
		_walk_to(eleanor.global_position, delta, true)
		_press("cover", false)
		return
	_press("move_forward", false)
	_press("sprint", false)
	player.yaw = atan2(-to.x, -to.z)
	_press("cover", fmod(_phase_t, 0.3) < 0.05)


func _press(action: String, on: bool) -> void:
	if on and not Input.is_action_pressed(action):
		Input.action_press(action)
	elif not on and Input.is_action_pressed(action):
		Input.action_release(action)


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0, v.z)


# ---------------------------------------------------------------- the door trap

func _trap_scenario() -> void:
	var doomed: Array = []
	for i in 2:
		var g := Gunman.new()
		g.team = "americans"
		g.name = "American_%d" % (i + 1)
		g.glb = "res://assets/characters/explorer/explorer.glb"
		add_child(g)
		g.global_position = Vector3(-1.2 + i * 2.6, 0, 4.0 + i * 1.2)
		g.rotation.y = 0.0
		doomed.append(g)
	Gunman.set_allies(Gunman.PARTY, "americans")
	player.global_position = Vector3(0.3, 0, 8.0)
	eleanor.global_position = Vector3(3.2, 0, 6.5)
	eleanor.set_order("hold")
	await get_tree().create_timer(1.0).timeout
	# The door: the corridor's mouth at z = +2, the room (+Z) in front of it.
	var door := Transform3D(Basis(Vector3.UP, PI), Vector3(0, 0, 2.0))
	print("RESULT trap springs t=%.1f" % _t)
	var trap := TombTrap.spring(self, door, doomed)
	get_tree().create_timer(1.6).timeout.connect(func(): _screenshot("trap"))
	var killed: Array = await trap.done
	var names := PackedStringArray()
	for k in killed:
		names.append(str((k as Node).name))
	print("RESULT trap killed=[%s] player hp=%d alive=%s eleanor hp=%d alive=%s" % [", ".join(names), int(player.health),
		player.alive, int(eleanor.health), eleanor.is_active()])
	await get_tree().create_timer(1.0).timeout
	_done = true
	get_tree().quit(0)


# ---------------------------------------------------------------- output

func _screenshot(base: String) -> void:
	await RenderingServer.frame_post_draw
	_save(base + "_play.png")
	var p := player.global_position
	_cam.look_at_from_position(p + Vector3(1.6, 3.2, 7.5), p + Vector3(0, 1.0, 1.0))
	_cam.current = true
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	_save(base + "_behind.png")
	player.camera.current = true


func _save(file: String) -> void:
	var path := _dir.path_join(file)
	get_viewport().get_texture().get_image().save_png(path)
	print("RESULT shot %s" % ProjectSettings.globalize_path(path))


func _finish() -> void:
	if _done:
		return
	_done = true
	var scarab_dmg := 0.0
	var contact := 0.0
	for s in swarms:
		if is_instance_valid(s):
			scarab_dmg += s.damage_dealt
			contact += s.contact_time
	print("RESULT guardian hits=%d staggers=%d catches=%d min_gap=%.1fm gaps_every_2s=[%s]" % [guardian.hits_taken,
		guardian.staggers, guardian.catches, _min_gap, ",".join(_gaps)])
	print("RESULT summary t=%.1f escaped=%s player_alive=%s damage_taken=%.0f (scarabs %.0f over %.1fs; live swarms only) eleanor alive=%s stumbled=%s helped=%s hp=%d" % [
		_t, _escaped, player.alive, _damage, scarab_dmg, contact, eleanor.is_active(), _stumbled, _helped, int(eleanor.health)])
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
