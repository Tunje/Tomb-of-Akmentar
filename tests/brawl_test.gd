extends Node3D
## Brawl: the player (fists, through a Melee the test attaches the way player.gd's hooks will)
## vs 3 Brawlers in a walled yard. The bot walks in, jabs (often into a cross), shoves blockers,
## and blocks punches it sees coming. Args after "--":
##   --seconds=90        quit after this long (or when one side is out)
##   --block=0.6         how often the bot blocks a punch it sees coming
##   --shots=4,10,20     screenshot times (s): player view, overview, close-up of the nearest brawler
##   --shot-dir=C:/path  where PNGs go (default user://shots)
## RESULT lines: punches thrown / landed / blocked, knockdowns, yields, KOs, who won.

const NAMES := ["Collector", "Heavy", "Runner"]
const DOWN_GETUP_SHOT := Melee.DOWN_TIME + 0.6  # mid get-up

var args := {}
var player: Player
var pm: Melee
var brawlers: Array[Brawler] = []
var _cam: Camera3D
var _t := 0.0
var _shots: Array[float] = []
var _dir := "user://shots"
var _block_skill := 0.6
var _blocking_t := 0.0
var _attack_cd := 0.0
var _events := PackedStringArray()
var _winner := ""
var _down_shot := false
var _done := false


func _ready() -> void:
	get_window().set_flag(Window.FLAG_NO_FOCUS, true)
	_setup_input()
	args = TestDriver.parse_args()
	for s in str(args.get("shots", "")).split(",", false):
		_shots.append(float(s))
	_shots.sort()
	_dir = args.get("shot-dir", _dir)
	_block_skill = float(args.get("block", "0.6"))
	DirAccess.make_dir_recursive_absolute(_dir)
	_build_yard()
	Game.reset()
	Game.event.connect(func(e: String): _events.append(e))

	player = Player.new()
	add_child(player)
	player.set_process_unhandled_input(false)
	player.global_position = Vector3(0, 0, 4)
	player.set_armed(false)
	# What player.gd's hooks will do: own a Melee, face the punch with the model.
	pm = Melee.new()
	pm.visual = player.model
	pm.max_hp = 150.0  # the hero takes more than a regular (suggested for player.gd's hook too)
	pm.hp = 150.0
	pm.power = 1.3
	pm.toughness = 1.5
	player.add_child(pm)
	if player.explorer:
		pm.install(player.explorer)
	pm.knocked_down.connect(func(): print("RESULT player down t=%.1f hp=%d" % [_t, int(pm.hp)]))
	pm.ko.connect(func(): _end("brawlers"))

	for i in 3:
		var b := Brawler.new()
		b.glb = GunmanBody.BANDITS[[1, 0, 3][i]]
		b.name = NAMES[i]
		b.skill = [0.55, 0.35, 0.6][i]
		b.max_hp = [70.0, 90.0, 55.0][i]
		add_child(b)
		b.global_position = Vector3(-3 + i * 3, 0, -4)
		brawlers.append(b)
		b.melee.knocked_down.connect(func():
			print("RESULT %s down t=%.1f hp=%d" % [b.name, _t, int(b.melee.hp)])
			if not _down_shot:
				_down_shot = true
				get_tree().create_timer(1.0).timeout.connect(func(): _screenshot("brawl_knockdown"))
				get_tree().create_timer(DOWN_GETUP_SHOT).timeout.connect(func(): _screenshot("brawl_getup")))
		b.melee.yielded.connect(func(): print("RESULT %s yields t=%.1f" % [b.name, _t]))
		b.melee.ko.connect(func(): print("RESULT %s KO t=%.1f" % [b.name, _t]))
		b.out_of_fight.connect(func(_b):
			if Brawler.fighting_count(get_tree()) == 0:
				_end("player"))

	_cam = Camera3D.new()
	_cam.fov = 55.0
	add_child(_cam)
	print("RESULT start")


func _build_yard() -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.55, 0.62, 0.7)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.6, 0.58, 0.55)
	env.environment.ambient_light_energy = 0.6
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 30, 0)
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	add_child(sun)
	var sand := _mat(Color(0.72, 0.62, 0.45))
	var stone := _mat(Color(0.55, 0.5, 0.42))
	_box(Vector3(0, -0.5, 0), Vector3(20, 1, 20), sand)
	for w: Array in [[Vector3(0, 1.5, -10), Vector3(20, 3, 0.6)], [Vector3(0, 1.5, 10), Vector3(20, 3, 0.6)],
			[Vector3(-10, 1.5, 0), Vector3(0.6, 3, 20)], [Vector3(10, 1.5, 0), Vector3(0.6, 3, 20)]]:
		_box(w[0], w[1], stone)


func _box(pos: Vector3, size: Vector3, mat: Material) -> void:
	var body := StaticBody3D.new()
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
	add_child(body)
	body.position = pos


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
	if _winner == "":
		_bot(delta)
	else:
		_press("move_forward", false)
	if _shots.size() > 0 and _t >= _shots[0]:
		var at: float = _shots.pop_front()
		_screenshot("brawl_%05.1f" % at)
	if _t >= float(args.get("seconds", "90")):
		_finish()


func _bot(delta: float) -> void:
	var b := _nearest()
	if b == null or pm.busy():
		_press("move_forward", false)
		return
	var to := _flat(b.global_position - player.global_position)
	var d := to.length()
	player.yaw = lerp_angle(player.yaw, atan2(-to.x, -to.z), minf(delta * 10.0, 1.0))
	player.model.rotation.y = player.yaw  # hook: face the camera's way while brawling
	# A punch coming from anyone close: block it (by skill), hold the block a moment.
	_blocking_t -= delta
	for o in brawlers:
		var m := o.melee
		if m.state == Melee.State.ATTACK and m._t < float(Melee.MOVES[m._kind].hit) \
				and _flat(o.global_position - player.global_position).length() < 2.0 and _blocking_t < -0.3:
			if randf() < _block_skill:
				_blocking_t = 0.45
			else:
				_blocking_t = -0.0001  # decided not to: don't re-roll for this punch
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
		return  # guard up between combos, like a person would
	_attack_cd = randf_range(0.3, 0.6)
	if b.melee.state == Melee.State.BLOCK and randf() < 0.5:
		pm.attack("shove", to)
	else:
		pm.attack("jab", to)
		if randf() < 0.6:
			_queue_cross()


func _queue_cross() -> void:
	await get_tree().create_timer(Melee.CHAIN_FROM + 0.02).timeout
	pm.attack("jab")


func _nearest() -> Brawler:
	var best: Brawler = null
	var bd := INF
	for b in brawlers:
		if b.melee.out() or not b.melee.can_be_hit():
			continue
		var d := b.global_position.distance_to(player.global_position)
		if d < bd:
			bd = d
			best = b
	return best


func _press(action: String, on: bool) -> void:
	if on and not Input.is_action_pressed(action):
		Input.action_press(action)
	elif not on and Input.is_action_pressed(action):
		Input.action_release(action)


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0, v.z)


# ---------------------------------------------------------------- output

func _end(who: String) -> void:
	if _winner != "":
		return
	_winner = who
	print("RESULT winner=%s t=%.1f" % [who, _t])
	get_tree().create_timer(3.0).timeout.connect(_finish)


func _screenshot(base: String) -> void:
	if DisplayServer.get_name() == "headless":  # frame_post_draw never fires headless
		return
	await RenderingServer.frame_post_draw
	_save(base + "_play.png")
	_cam.look_at_from_position(Vector3(0, 13, 12), Vector3(0, 0, 0))
	_cam.current = true
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	_save(base + "_top.png")
	var b := _nearest()
	if b:
		var mid := (b.global_position + player.global_position) * 0.5 + Vector3.UP * 1.2
		var across := _flat(b.global_position - player.global_position).normalized().cross(Vector3.UP)
		_cam.look_at_from_position(mid + across * 3.2 + Vector3.UP * 0.3, mid)
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		_save(base + "_near.png")
	player.camera.current = true


func _save(file: String) -> void:
	var path := _dir.path_join(file)
	get_viewport().get_texture().get_image().save_png(path)
	print("RESULT shot %s" % ProjectSettings.globalize_path(path))


func _finish() -> void:
	if _done:
		return
	_done = true
	print("RESULT player hp=%d/%d state=%s thrown=%d landed=%d blocked_by_me=%d knockdowns=%d guard=%d" % [
		int(pm.hp), int(pm.max_hp), Melee.State.keys()[pm.state], pm.thrown_count, pm.landed_count,
		pm.blocked_count, pm.knockdowns, int(pm.guard)])
	for b in brawlers:
		var m := b.melee
		print("RESULT brawler %s hp=%d/%d state=%s thrown=%d landed=%d blocked_by_him=%d knockdowns=%d" % [
			b.name, int(m.hp), int(m.max_hp), Melee.State.keys()[m.state], m.thrown_count, m.landed_count,
			m.blocked_count, m.knockdowns])
	print("RESULT summary t=%.1f winner=%s events=%s flags won=%s lost=%s player_health=%d" % [_t,
		_winner if _winner != "" else "none", ",".join(_events), Game.flag("brawl_won"), Game.flag("brawl_lost"),
		int(player.health)])
	await get_tree().create_timer(0.3).timeout
	get_tree().quit(0)


## Copied from main.gd's _setup_input.
func _setup_input() -> void:
	var keys := {
		"move_forward": [KEY_W], "move_back": [KEY_S], "move_left": [KEY_A], "move_right": [KEY_D],
		"sprint": [KEY_SHIFT], "crouch": [KEY_C, KEY_CTRL], "dodge": [KEY_SPACE],
		"reload": [KEY_R], "cover": [KEY_E], "weapon_1": [KEY_1], "weapon_2": [KEY_2], "weapon_3": [KEY_3],
		"shove": [KEY_F],
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
