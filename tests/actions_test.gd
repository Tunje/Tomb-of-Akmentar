extends Node3D
## Action system test: Eleanor (a rigged Npc) recruited by talking (E), three actions in the old
## quarter spent until the day ends, "No time left today" on one too costly, the day-end screen,
## then a camp talk with Eleanor that raises her trust, and sleeping (the bed's day-end screen).
## Prints RESULT lines and saves screenshots; exits 0 when every check passed. Args after "--":
##   --shot-dir=C:/path   where PNGs go (default user://actions_shots)
## Never takes focus or captures the mouse (Simon plays while we test).

class FakePlayer extends Node3D:
	var controls_enabled := true
	var yaw := 0.0

const MUSEUM := Vector3(0, 0, 0)
const QUARTER := Vector3(5, 0, 0)
const CAMP := Vector3(14, 0, 0)

var _dir := "user://actions_shots"
var _player: FakePlayer
var _eleanor: Npc
var _quarter: ActionSpot
var _camp: ActionSpot
var _cam: Camera3D
var _fails := 0
var _ended := ""


func _ready() -> void:
	get_window().set_flag(Window.FLAG_NO_FOCUS, true)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot-dir="):
			_dir = a.substr(11)
	DirAccess.make_dir_recursive_absolute(_dir)
	Game.reset()
	Game.money = 50
	DayLog.begin_day()
	_build_scene()
	_run.call_deferred()


func _build_scene() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.3, 0.26, 0.2)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.55, 0.48)
	env.ambient_light_energy = 0.7
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 35, 0)
	sun.light_color = Color(1.0, 0.92, 0.78)
	sun.shadow_enabled = true
	add_child(sun)
	_box(Vector3(7, -0.05, 0), Vector3(30, 0.1, 14), Color(0.62, 0.52, 0.38))
	_box(MUSEUM + Vector3(0, 2, -3.2), Vector3(5, 4, 0.3), Color(0.55, 0.5, 0.42))   # museum wall
	_box(QUARTER + Vector3(0.6, 0.45, -1.6), Vector3(1.6, 0.9, 0.7), Color(0.4, 0.28, 0.16))  # a stall
	_box(CAMP + Vector3(0, 0.12, -1.0), Vector3(0.8, 0.24, 0.8), Color(0.25, 0.15, 0.08))  # campfire stones
	var fire := OmniLight3D.new()
	fire.light_color = Color(1, 0.6, 0.25)
	fire.light_energy = 2.0
	fire.position = CAMP + Vector3(0, 0.6, -1.0)
	add_child(fire)
	_player = FakePlayer.new()
	_player.name = "Player"
	add_child(_player)
	var mi := MeshInstance3D.new()
	mi.mesh = CapsuleMesh.new()
	mi.position.y = 0.9
	mi.material_override = _mat(Color(0.62, 0.5, 0.32))
	_player.add_child(mi)
	_player.position = MUSEUM + Vector3(0.4, 0, 0.4)
	_eleanor = Npc.make(self, "eleanor", MUSEUM + Vector3(-0.3, 0, -1.2), "eleanor_meet", NpcBody.SCOUT)
	_quarter = ActionSpot.make(self, "cairo_corner", QUARTER + Vector3(0, 0, -1.0))
	_camp = ActionSpot.make(self, "camp", CAMP + Vector3(0, 0, -1.0))
	_cam = Camera3D.new()
	_cam.fov = 50.0
	add_child(_cam)
	_cam.current = true
	_aim_cam(MUSEUM)


func _aim_cam(at: Vector3) -> void:
	_cam.look_at_from_position(at + Vector3(2.4, 1.9, 3.4), at + Vector3(-0.2, 1.0, -0.8))


func _box(at: Vector3, size: Vector3, c: Color) -> void:
	var body := StaticBody3D.new()
	body.position = at
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	shape.shape.size = size
	body.add_child(shape)
	var mi := MeshInstance3D.new()
	mi.mesh = BoxMesh.new()
	mi.mesh.size = size
	mi.material_override = _mat(c)
	body.add_child(mi)
	add_child(body)


func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.9
	return m


# ---------------------------------------------------------------- the run

func _run() -> void:
	await _wait(1.0)
	_check(_eleanor.body != null, "eleanor uses the rigged NpcBody (%s)" % NpcBody.SCOUT)
	_check(_camp.rows().is_empty(), "camp offers no companion talk before anyone joined")
	await _shot("act_1_npc.png")

	# Talk to Eleanor with E (the player's own pick + use).
	var it := _use_nearest(_eleanor.global_position)
	_check(it == _eleanor.interactable and it.prompt == "Talk", "E picks Eleanor's Talk prompt (%s)" % (it.prompt if it else "none"))
	var conv := Conversation.current
	_check(conv != null, "talking started a conversation")
	await _wait_state(Conversation.State.CHOICES)
	await _pick("Invite her along")
	await _skip_to_choices()
	await _wait(1.2)  # her talking gesture has blended in
	await _shot("act_2_talk_wheel.png")
	await _pick("Promise")
	await _wait_until(func(): return Conversation.current == null, 15.0)
	_check(Game.in_party("eleanor"), "eleanor recruited by the talk")
	_check(int(Game.companion("eleanor").trust) == 1, "promise raised her trust to 1")
	_check(Game.actions_left == 3, "talking to someone by E is free (actions %d)" % Game.actions_left)

	# Three actions in the old quarter.
	_player.global_position = QUARTER + Vector3(0, 0, 0.6)
	_aim_cam(QUARTER)
	_eleanor.global_position = QUARTER + Vector3(-1.6, 0, 0.6)
	it = _use_nearest(_quarter.global_position)
	_check(it == _quarter.interactable, "E picks the old quarter (%s)" % (it.prompt if it else "none"))
	var menu := ActionMenu.current
	_check(menu != null and menu.rows.size() == 3, "menu lists 3 actions")
	_check(not _player.controls_enabled, "controls off while the menu is up")
	_hover_row(menu, 2)
	await _wait(0.2)
	await _shot("act_3_menu.png")
	_key(KEY_3)  # the guide, 2 actions
	await _wait(0.2)
	_check(Game.actions_left == 1 and Game.flag("knows_city"), "guide spent 2 actions (left %d)" % Game.actions_left)
	_check(_player.controls_enabled, "controls back after the action")
	_use_nearest(_quarter.global_position)
	menu = ActionMenu.current
	_check(menu != null and not menu.rows[2].enabled and menu.rows[2].reason == ActionSpot.NO_TIME,
			"guide greyed: %s" % (menu.rows[2].reason if menu else "no menu"))
	_key(KEY_3)
	await _wait(0.2)
	_check(menu.message == ActionSpot.NO_TIME and Game.actions_left == 1, "picking it shows '%s' and spends nothing" % menu.message)
	await _shot("act_4_no_time.png")
	_mouse_click(menu.row_point(1))  # Haggle for supplies, with the mouse
	await _wait(0.6)
	_check(Game.actions_left == 0 and Game.money == 30 and int(Game.inventory.get("rations", 0)) == 6,
			"supplies bought (money %d, actions %d)" % [Game.money, Game.actions_left])
	_check(DaySummary.current != null, "the day-end screen opened at 0 actions")
	var lines: Array[String] = []
	if DaySummary.current:
		lines = DaySummary.current.lines
	print("RESULT summary day 1: %s" % [lines])
	for want in ["Talked with Eleanor Whitmore", "Spent the day with a city guide", "Haggled for six days of rations",
			"Money −£20", "Eleanor Whitmore joined the expedition", "Eleanor Whitmore: trust +1"]:
		_check(want in lines, "summary has '%s'" % want)
	await _wait(0.6)
	await _shot("act_5_day_end.png")
	_key(KEY_SPACE)
	await _wait(0.2)
	_check(Game.day == 2 and Game.actions_left == 3, "day 2 began with 3 actions (day %d, %d)" % [Game.day, Game.actions_left])

	# Camp: a talk with Eleanor.
	_player.global_position = CAMP + Vector3(0.9, 0, 0.3)
	_eleanor.global_position = CAMP + Vector3(-1.3, 0, -0.2)
	_aim_cam(CAMP)
	await _wait(0.3)
	it = _use_nearest(_camp.global_position)
	menu = ActionMenu.current
	_check(menu != null and menu.rows.size() == 1 and menu.rows[0].label == "Talk with Eleanor",
			"camp offers 'Talk with Eleanor' now she's in the party")
	await _shot("act_6_camp_menu.png")
	_key(KEY_1)
	await _wait(0.2)
	_check(Conversation.current != null and Game.actions_left == 2, "camp talk started and cost 1 action")
	await _wait_state(Conversation.State.CHOICES)
	await _shot("act_7_camp_talk.png")
	await _pick("Ask what it means")
	await _wait_until(func(): return Conversation.current == null, 20.0, true)
	var e := Game.companion("eleanor")
	_check(int(e.trust) == 2 and int(e.conviction) == 1, "camp talk: trust %d (want 2), conviction %d (want 1)" % [e.trust, e.conviction])
	_use_nearest(_camp.global_position)
	menu = ActionMenu.current
	_check(menu != null and menu.rows.is_empty() and menu.message != "", "her talk is done for today ('%s')" % (menu.message if menu else ""))
	_key(KEY_ESCAPE)
	await _wait(0.2)

	# Sleep: the bed opens the same day-end screen.
	DaySummary.open(self, _player)
	lines = DaySummary.current.lines
	print("RESULT summary day 2: %s" % [lines])
	for want in ["Talked with Eleanor by the fire", "Eleanor Whitmore: trust +1", "Eleanor Whitmore: conviction +1"]:
		_check(want in lines, "sleep summary has '%s'" % want)
	await _wait(0.7)
	await _shot("act_8_sleep.png")
	_mouse_click(Vector2(800, 450))
	await _wait(0.2)
	_check(Game.day == 3 and Game.actions_left == 3, "sleeping began day 3")
	_check(not ActionMenu.ui_open() and _player.controls_enabled, "no UI left open, controls on")
	_check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "mouse never captured")

	print("RESULT actions_test %s fails=%d" % ["PASS" if _fails == 0 else "FAIL", _fails])
	await _wait(0.2)
	get_tree().quit(0 if _fails == 0 else 1)


## What the player's E would use, facing `target` (Interactable.pick + use, as Player does).
func _use_nearest(target: Vector3) -> Interactable:
	var facing := target - _player.global_position
	var it := Interactable.pick(get_tree(), _player.global_position, facing)
	if it:
		it.use(_player)
	return it


func _labels() -> Array:
	var c := Conversation.current
	return c.visible_choices.map(func(x): return x.label) if c else []


func _pick(label: String) -> void:
	var i := _labels().find(label)
	_check(i >= 0, "choice '%s' on the wheel %s" % [label, _labels()])
	_key(KEY_1 + maxi(i, 0))
	await _wait(0.1)


func _skip_to_choices() -> void:
	for k in 10:
		var c := Conversation.current
		if c == null or c.state == Conversation.State.CHOICES:
			break
		_key(KEY_SPACE)
		await _wait(0.2)
	await _wait_state(Conversation.State.CHOICES)


func _wait_state(s: int, limit := 10.0) -> void:
	var ok: bool = await _wait_until(func(): return Conversation.current != null and Conversation.current.state == s, limit)
	if not ok:
		_check(false, "timed out waiting for conversation state %d" % s)
	await _wait(0.15)


## Waits for `cond`; with `skip`, presses Space every 0.3 s to move lines on.
func _wait_until(cond: Callable, limit: float, skip := false) -> bool:
	var t := 0.0
	while t < limit:
		if cond.call():
			return true
		if skip and fmod(t, 0.3) < 0.05:
			_key(KEY_SPACE)
		await _wait(0.05)
		t += 0.05
	return false


func _hover_row(menu: ActionMenu, i: int) -> void:
	var e := InputEventMouseMotion.new()
	e.position = menu.row_point(i)
	e.global_position = e.position
	Input.parse_input_event(e)


func _key(k: int) -> void:
	for pressed in [true, false]:
		var e := InputEventKey.new()
		e.keycode = k as Key
		e.physical_keycode = k as Key
		e.pressed = pressed
		Input.parse_input_event(e)


func _mouse_click(p: Vector2) -> void:
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.position = p
		e.global_position = p
		e.pressed = pressed
		Input.parse_input_event(e)


func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _check(ok: bool, what: String) -> void:
	print("RESULT %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_fails += 1


func _shot(file: String) -> void:
	await RenderingServer.frame_post_draw
	var path := _dir.path_join(file)
	get_viewport().get_texture().get_image().save_png(path)
	print("RESULT shot %s" % ProjectSettings.globalize_path(path))
