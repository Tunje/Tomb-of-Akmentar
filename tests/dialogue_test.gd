extends Node3D
## Conversation wheel test: two capsules and dialogue/archivist.json, played through twice.
##   Run 1 (number keys): ask for an Egyptologist -> ask about his staff -> ask for Miss Whitmore = recruit.
##   Run 2 (mouse on the wheel, second visit, 100 money): ask -> threaten him = event fight_museum_guards.
## Prints RESULT lines and saves screenshots; exits 0 when every check passed. Args after "--":
##   --shot-dir=C:/path   where PNGs go (default user://dialogue_shots)
## Never takes focus or captures the mouse (Simon plays while we test).

class FakePlayer extends Node3D:
	var controls_enabled := true
	var yaw := 0.0

var _dir := "user://dialogue_shots"
var _player: FakePlayer
var _npc: Node3D
var _game_cam: Camera3D
var _events: Array[String] = []
var _fails := 0
var _conv: Conversation
var _ended := ""


func _ready() -> void:
	get_window().set_flag(Window.FLAG_NO_FOCUS, true)
	var args := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv := a.substr(2).split("=", true, 1)
			args[kv[0]] = kv[1] if kv.size() > 1 else "true"
	_dir = args.get("shot-dir", _dir)
	DirAccess.make_dir_recursive_absolute(_dir)
	_build_scene()
	Game.event.connect(func(e: String): _events.append(e))
	_run.call_deferred()


func _build_scene() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.12, 0.1, 0.08)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.45, 0.4)
	env.ambient_light_energy = 0.6
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	sun.light_color = Color(1.0, 0.9, 0.75)
	sun.shadow_enabled = true
	add_child(sun)
	_box(Vector3(0, -0.05, 0), Vector3(20, 0.1, 20), Color(0.55, 0.48, 0.38))
	_box(Vector3(0, 2, -4), Vector3(12, 4, 0.3), Color(0.45, 0.4, 0.33))
	_box(Vector3(-1.6, 0.5, -3.3), Vector3(1.6, 1.0, 0.8), Color(0.35, 0.25, 0.16))  # a desk
	_player = FakePlayer.new()
	_player.name = "Player"
	add_child(_player)
	_capsule(_player, Color(0.62, 0.5, 0.32))
	_player.position = Vector3(0.6, 0, 1.2)
	_npc = Node3D.new()
	_npc.name = "Archivist"
	add_child(_npc)
	_capsule(_npc, Color(0.2, 0.22, 0.28))
	_npc.position = Vector3(-0.5, 0, -0.8)
	# The "gameplay" camera that must come back afterwards.
	_game_cam = Camera3D.new()
	add_child(_game_cam)
	_game_cam.look_at_from_position(Vector3(4, 3, 5), Vector3(0, 1, 0))
	_game_cam.current = true


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


func _capsule(n: Node3D, c: Color) -> void:
	var mi := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.32
	cap.height = 1.8
	mi.mesh = cap
	mi.position.y = 0.9
	mi.material_override = _mat(c)
	n.add_child(mi)
	var nose := MeshInstance3D.new()  # shows which way it faces
	nose.mesh = BoxMesh.new()
	nose.mesh.size = Vector3(0.12, 0.08, 0.2)
	nose.position = Vector3(0, 1.55, -0.34)
	nose.material_override = _mat(c.lightened(0.4))
	n.add_child(nose)


func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.9
	return m


# ---------------------------------------------------------------- the runs

func _run() -> void:
	await _wait(0.3)
	var probs := Conversation.validate(Conversation.load_data("archivist"))
	_check(probs.is_empty(), "validate problems=%d %s" % [probs.size(), "; ".join(probs)])

	# Run 1: number keys, recruit.
	Game.reset()
	_begin()
	await _wait_line("archivist")
	_check(_conv.node_id == "first", "run1 first visit greets with 'first' (got %s)" % _conv.node_id)
	_check(not _player.controls_enabled, "run1 controls off while talking")
	_check(_game_cam.current == false and _conv.camera.current, "run1 conversation camera is current")
	await _shot("dlg_1_npc_line.png")
	_key(KEY_SPACE)
	await _wait_choices()
	_check(_conv.node_id == "menu", "run1 menu")
	await _hover(0)
	await _shot("dlg_2_wheel.png")
	await _pick_key("Ask for an Egyptologist")
	await _wait_line("player")
	await _shot("dlg_3_player_line.png")
	_key(KEY_ENTER)
	await _wait_line("archivist")
	_key(KEY_SPACE)
	await _wait_choices()
	_check(not _labels().has("Offer a donation"), "run1 donation hidden with 0 money (labels %s)" % [_labels()])
	await _shot("dlg_4_ask_wheel.png")
	await _pick_key("Ask about his staff")
	await _skip_to_choices()
	await _pick_key("Ask for Miss Whitmore")
	await _wait_end()
	_check(_ended == "end_recruited", "run1 ended at end_recruited (got '%s')" % _ended)
	_check(Game.in_party("eleanor"), "run1 eleanor recruited")
	_check(Game.flag("met_archivist") and Game.flag("knows_eleanor"), "run1 flags met_archivist knows_eleanor")
	_restored("run1")
	await _shot("dlg_5_after_recruit.png")

	# Run 2: mouse on the wheel, second visit, fight.
	Game.reset()
	Game.set_flag("met_archivist")
	Game.money = 100
	_events.clear()
	_begin()
	await _wait_line("archivist")
	_check(_conv.node_id == "again", "run2 second visit greets with 'again' (got %s)" % _conv.node_id)
	_click_empty()
	await _wait_choices()
	await _pick_mouse("Ask for an Egyptologist")
	await _skip_to_choices()
	_check(_labels().has("Offer a donation"), "run2 donation shown with 100 money (labels %s)" % [_labels()])
	await _hover(_labels().find("Threaten him"))
	await _shot("dlg_6_threat_hover.png")
	await _pick_mouse("Threaten him")
	await _wait_line("archivist")
	await _shot("dlg_7_guards.png")
	_click_empty()
	await _wait_end()
	_check(_ended == "end_fight", "run2 ended at end_fight (got '%s')" % _ended)
	_check(_events.has("fight_museum_guards"), "run2 event fight_museum_guards (events %s)" % [_events])
	_check(not Game.in_party("eleanor"), "run2 nobody recruited")
	_check(Game.money == 100, "run2 money untouched (%d)" % Game.money)
	_restored("run2")

	# Run 3: let lines run out on their own (no input at all) until the wheel shows.
	Game.reset()
	_begin()
	var t0 := Time.get_ticks_msec()
	await _wait_choices(20.0)
	_check(_conv.node_id == "menu", "run3 lines auto-advance to the wheel in %.1f s" % ((Time.get_ticks_msec() - t0) / 1000.0))
	await _pick_key("Leave")
	await _wait_end(20.0)
	_check(_ended == "end_left", "run3 leave ends at end_left (got '%s')" % _ended)
	_restored("run3")

	print("RESULT dialogue_test %s fails=%d" % ["PASS" if _fails == 0 else "FAIL", _fails])
	await _wait(0.2)
	get_tree().quit(0 if _fails == 0 else 1)


func _begin() -> void:
	_ended = ""
	_conv = Conversation.new()
	add_child(_conv)
	_conv.finished.connect(func(e: String): _ended = e if e != "" else "<none>")
	_conv.line_started.connect(func(s: String, t: String): print("RESULT line %s: %s" % [s, t]))
	_conv.choices_shown.connect(func(l: Array): print("RESULT wheel %s" % [l]))
	_conv.start("archivist", _player, _npc)


func _restored(run: String) -> void:
	_check(_player.controls_enabled, "%s controls back on" % run)
	_check(_game_cam.current, "%s gameplay camera current again" % run)
	_check(Conversation.current == null, "%s Conversation.current cleared" % run)
	_check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "%s mouse mode restored (never captured)" % run)


func _labels() -> Array:
	return _conv.visible_choices.map(func(c): return c.label) if is_instance_valid(_conv) else []


func _pick_key(label: String) -> void:
	var i := _labels().find(label)
	_check(i >= 0, "choice '%s' on the wheel" % label)
	print("RESULT pick key %d '%s'" % [i + 1, label])
	_key(KEY_1 + maxi(i, 0))
	await _wait(0.1)


func _pick_mouse(label: String) -> void:
	var i := _labels().find(label)
	_check(i >= 0, "choice '%s' on the wheel" % label)
	print("RESULT pick mouse slot %d '%s'" % [i, label])
	var p := _conv.wheel.slot_point(maxi(i, 0))
	_mouse_move(p)
	await _wait(0.1)
	_check(_conv.wheel.hovered == i, "mouse hovers slot %d (hovered %d)" % [i, _conv.wheel.hovered])
	_mouse_click(p)
	await _wait(0.1)


func _skip_to_choices() -> void:
	for k in 8:
		if is_instance_valid(_conv) and _conv.state == Conversation.State.CHOICES:
			return
		await _wait(0.15)
		_key(KEY_SPACE)
		await _wait(0.1)
	await _wait_choices()


func _hover(i: int) -> void:
	_mouse_move(_conv.wheel.slot_point(maxi(i, 0)))
	await _wait(0.15)
	_check(_conv.wheel.hovered == i, "hover shows slot %d (hovered %d)" % [i, _conv.wheel.hovered])


func _click_empty() -> void:
	_mouse_click(Vector2(200, 300))


# ---------------------------------------------------------------- input and waits

func _key(k: int) -> void:
	for pressed in [true, false]:
		var e := InputEventKey.new()
		e.keycode = k as Key
		e.physical_keycode = k as Key
		e.pressed = pressed
		Input.parse_input_event(e)


func _mouse_move(p: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = p
	e.global_position = p
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


func _wait_line(speaker: String, limit := 8.0) -> void:
	var t := 0.0
	while t < limit:
		if is_instance_valid(_conv) and _conv.state in [Conversation.State.LINE, Conversation.State.PLAYER_LINE] \
				and (speaker == "player") == (_conv.state == Conversation.State.PLAYER_LINE):
			await _wait(0.15)
			return
		await _wait(0.05)
		t += 0.05
	_check(false, "timed out waiting for a %s line" % speaker)


func _wait_choices(limit := 8.0) -> void:
	var t := 0.0
	while t < limit:
		if is_instance_valid(_conv) and _conv.state == Conversation.State.CHOICES:
			await _wait(0.15)
			return
		await _wait(0.05)
		t += 0.05
	_check(false, "timed out waiting for the wheel")


func _wait_end(limit := 12.0) -> void:
	var t := 0.0
	while t < limit and _ended == "":
		await _wait(0.05)
		t += 0.05
	await _wait(0.1)


func _check(ok: bool, what: String) -> void:
	print("RESULT %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_fails += 1


func _shot(file: String) -> void:
	await RenderingServer.frame_post_draw
	var path := _dir.path_join(file)
	get_viewport().get_texture().get_image().save_png(path)
	print("RESULT shot %s" % ProjectSettings.globalize_path(path))
