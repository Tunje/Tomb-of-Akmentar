extends Node3D
## Gamepad test (Xbox layout, Controls.PAD), with simulated pad events (InputEventJoypadButton /
## InputEventJoypadMotion through Input.parse_input_event): the bindings; the left stick walks,
## L3 latches sprint; the right stick looks with a dead zone, the options' sensitivity and invert
## Y; RT fires; X uses what's in front (the market chase's grab); key names follow the device;
## a truck drives on RT and slows on LT; the conversation wheel picks with the stick and A.
## Never touches settings.cfg (Settings.test_mode). Prints RESULT lines; exits 0 when all passed.

var _fails := 0
var player: Player


func _ready() -> void:
	Settings.test_mode = true
	get_window().set_flag(Window.FLAG_NO_FOCUS, true)
	Controls.setup()
	var level := Level.new()
	add_child(level)
	player = Player.new()
	add_child(player)
	player.global_position = level.player_spawn
	player.yaw = 0.0
	var hud := Hud.new()
	hud.player = player
	add_child(hud)
	for i in 5:
		await get_tree().physics_frame
	await _bindings()
	await _walk_and_sprint()
	await _look()
	await _fire_and_use()
	await _rumble()
	await _assist()
	_names()
	await _truck()
	await _wheel()
	print("RESULT %s (%d failed)" % ["PASS" if _fails == 0 else "FAIL", _fails])
	get_tree().quit(0 if _fails == 0 else 1)


func _bindings() -> void:
	var a := _button_event(JOY_BUTTON_A, true)
	_check(a.is_action("dodge") and _button_event(JOY_BUTTON_B, true).is_action("crouch")
		and _button_event(JOY_BUTTON_X, true).is_action("cover") and _button_event(JOY_BUTTON_Y, true).is_action("reload"),
		"A dodge, B crouch, X use / cover, Y reload")
	_check(_button_event(JOY_BUTTON_RIGHT_SHOULDER, true).is_action("weapon_next") and _button_event(JOY_BUTTON_LEFT_SHOULDER, true).is_action("weapon_prev"),
		"RB / LB cycle the guns")
	_check(_button_event(JOY_BUTTON_DPAD_DOWN, true).is_action("holster") and _button_event(JOY_BUTTON_DPAD_LEFT, true).is_action("party_order")
		and _button_event(JOY_BUTTON_DPAD_UP, true).is_action("journal"), "the d-pad: holster, orders, journal")
	_check(_button_event(JOY_BUTTON_START, true).is_action("ui_cancel") and not _button_event(JOY_BUTTON_B, true).is_action("ui_cancel"),
		"Start pauses (ui_cancel); B doesn't (it's crouch)")
	_check(_motion_event(JOY_AXIS_TRIGGER_RIGHT, 1.0).is_action("fire") and _motion_event(JOY_AXIS_TRIGGER_LEFT, 1.0).is_action("aim"),
		"RT fires, LT aims")
	_check(_button_event(JOY_BUTTON_Y, true).is_action("shove"), "the brawl's shove is Y (unarmed: nothing to reload)")


func _walk_and_sprint() -> void:
	var from := player.global_position
	_stick(JOY_AXIS_LEFT_Y, -1.0)
	await _wait(0.6)
	var moved := player.global_position - from
	_check(moved.length() > 1.0 and moved.z < 0.0, "the left stick walks forward (%s)" % moved.snappedf(0.1))
	_tap(JOY_BUTTON_LEFT_STICK)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check(player.sprinting, "L3 sprints, and stays on while the stick is held")
	_stick(JOY_AXIS_LEFT_Y, 0.0)
	await _wait(0.2)
	_check(not player.sprinting and not player._pad_sprint, "the stick back to rest ends the sprint")


func _look() -> void:
	var y0 := player.yaw
	_stick(JOY_AXIS_RIGHT_X, 0.1)  # inside the dead zone
	await _wait(0.3)
	_check(is_equal_approx(player.yaw, y0), "the right stick's dead zone: 0.1 does nothing")
	_stick(JOY_AXIS_RIGHT_X, 1.0)
	await _wait(0.3)
	var turned := y0 - player.yaw
	_check(turned > 0.3, "right stick right turns right (%.2f rad)" % turned)
	_stick(JOY_AXIS_RIGHT_X, 0.0)
	Settings.set_value("mouse_sens", 2.0, get_tree())
	var y1 := player.yaw
	_stick(JOY_AXIS_RIGHT_X, 1.0)
	await _wait(0.3)
	_stick(JOY_AXIS_RIGHT_X, 0.0)
	_check((y1 - player.yaw) > turned * 1.5, "sensitivity 2x turns faster (%.2f vs %.2f)" % [y1 - player.yaw, turned])
	Settings.set_value("mouse_sens", 1.0, get_tree())
	var p0 := player.pitch
	_stick(JOY_AXIS_RIGHT_Y, -1.0)  # up
	await _wait(0.2)
	_stick(JOY_AXIS_RIGHT_Y, 0.0)
	var up := player.pitch - p0
	Settings.set_value("invert_y", true, get_tree())
	var p1 := player.pitch
	_stick(JOY_AXIS_RIGHT_Y, -1.0)
	await _wait(0.2)
	_stick(JOY_AXIS_RIGHT_Y, 0.0)
	Settings.set_value("invert_y", false, get_tree())
	_check(up > 0.05 and player.pitch - p1 < -0.05, "stick up looks up; inverted, down (%.2f / %.2f)" % [up, player.pitch - p1])


func _fire_and_use() -> void:
	player.set_armed(true)
	await _wait(0.6)  # the draw
	var shots := [0]
	player.fired.connect(func(): shots[0] += 1)
	_stick(JOY_AXIS_TRIGGER_RIGHT, 1.0)
	await _wait(0.5)
	_stick(JOY_AXIS_TRIGGER_RIGHT, 0.0)
	_check(shots[0] > 0, "RT fires (%d shots)" % shots[0])
	var used := [false]
	var it := Interactable.make(self, player.global_position - Basis(Vector3.UP, player.yaw).z * 1.2 + Vector3.UP, "Grab him", "test_grab", 0.9)
	it.used.connect(func(_by): used[0] = true)
	await _wait(0.1)
	_tap(JOY_BUTTON_X)
	await _wait(0.1)
	_check(used[0], "X uses what's in front (the market chase's grab)")
	it.queue_free()


## Rumble: firing and a hit rumble on the pad, not after a key; the option turns it off; a slab
## door's thud rumbles near it, not far off.
func _rumble() -> void:
	player.max_health = 100000.0
	player.health = 100000.0
	Controls.note_device(_button_event(JOY_BUTTON_A, true))
	var n := Controls.rumble_count
	player.ammo[player.current] = 6
	player._fire_cd = 0.0
	player.try_fire()
	_check(Controls.rumble_count == n + 1 and not Controls.last_rumble.is_empty(), "firing rumbles on the pad (%s)" % [Controls.last_rumble])
	n = Controls.rumble_count
	player.take_damage(10.0, player.global_position + Vector3.FORWARD)
	_check(Controls.rumble_count == n + 1, "a hit rumbles")
	var key := InputEventKey.new()
	key.physical_keycode = KEY_W
	key.pressed = true
	Controls.note_device(key)
	n = Controls.rumble_count
	await _wait(0.5)
	player._fire_cd = 0.0
	player.try_fire()
	player.take_damage(10.0, player.global_position + Vector3.FORWARD)
	_check(Controls.rumble_count == n, "nothing rumbles with mouse and keyboard in use")
	Controls.note_device(_button_event(JOY_BUTTON_A, true))
	Settings.set_value("vibration", false, get_tree())
	await _wait(0.5)
	player._fire_cd = 0.0
	player.try_fire()
	_check(Controls.rumble_count == n, "the option off: no rumble")
	Settings.set_value("vibration", true, get_tree())
	var cam := get_viewport().get_camera_3d()
	n = Controls.rumble_count
	Controls.rumble_at(get_tree(), cam.global_position + Vector3(0, 0, -30), 0.8, 1.0, 0.3, 20.0)
	_check(Controls.rumble_count == n, "a slab's thud 30 m off: nothing")
	Controls.rumble_at(get_tree(), cam.global_position + Vector3(0, 0, -5), 0.8, 1.0, 0.3, 20.0)
	_check(Controls.rumble_count == n + 1 and float(Controls.last_rumble[0]) < 0.8, "5 m off: a lighter thud (%s)" % [Controls.last_rumble])


## Aim slowdown: aiming (LT) over a bandit the right stick turns slower; off him, or without LT,
## or with the option off, it doesn't. It never moves the aim by itself.
func _assist() -> void:
	player.set_armed(true)
	await _wait(0.5)
	var g := Gunman.new()
	g.team = Gunman.BANDITS
	add_child(g)
	var cam := player.camera
	var fwd := -Basis(Vector3.UP, player.yaw).z
	g.global_position = Vector3(cam.global_position.x, player.global_position.y, cam.global_position.z) + fwd * 10.0
	await _wait(0.3)
	g.set_physics_process(false)  # stands still, doesn't shoot
	g.set_process(false)
	var centre := g.global_position + Vector3.UP * 1.1
	var d := (centre - cam.global_position).normalized()
	player.pitch = asin(d.y)
	Controls.note_device(_button_event(JOY_BUTTON_A, true))
	_stick(JOY_AXIS_TRIGGER_LEFT, 1.0)  # aim
	await _wait(0.4)
	_check(player.aiming and player._enemy_near_crosshair(), "aiming at the bandit: he's under the crosshair")
	_check(player._assist < 0.45, "over him the stick eases (%.2f)" % player._assist)
	var y0 := player.yaw
	await _wait(0.3)
	_check(is_equal_approx(player.yaw, y0), "and nothing pulls the aim (yaw unchanged with the stick at rest)")
	var slow := await _turn(0.3)
	player.yaw = y0
	player.yaw = y0 + 1.2  # well off him
	await _wait(0.4)
	var fast := await _turn(0.3)
	_check(slow < fast * 0.7, "off him it turns at full speed (%.3f vs %.3f rad)" % [slow, fast])
	player.yaw = y0
	_stick(JOY_AXIS_TRIGGER_LEFT, 0.0)  # not aiming
	await _wait(0.4)
	await _turn(0.2)
	_check(player._assist > 0.95, "without LT, no slowdown (%.2f)" % player._assist)
	player.yaw = y0
	Settings.set_value("aim_assist", false, get_tree())
	_stick(JOY_AXIS_TRIGGER_LEFT, 1.0)
	await _wait(0.4)
	await _turn(0.2)
	_check(player._assist > 0.95, "the option off: no slowdown (%.2f)" % player._assist)
	Settings.set_value("aim_assist", true, get_tree())
	_stick(JOY_AXIS_TRIGGER_LEFT, 0.0)
	FightBot.remove_gunman(g)


## The right stick a little right for `secs`: how far it turned.
func _turn(secs: float) -> float:
	var y := player.yaw
	_stick(JOY_AXIS_RIGHT_X, 0.4)
	await _wait(secs)
	_stick(JOY_AXIS_RIGHT_X, 0.0)
	return absf(y - player.yaw)


func _names() -> void:
	Controls.note_device(_button_event(JOY_BUTTON_A, true))
	_check(Controls.fill("{dodge}: roll · {cover} grab · {fire} fire") == "A: roll · X grab · RT fire",
		"on the pad, names are buttons (%s)" % Controls.fill("{dodge}: roll · {cover} grab · {fire} fire"))
	var key := InputEventKey.new()
	key.physical_keycode = KEY_W
	key.pressed = true
	Controls.note_device(key)
	_check(Controls.fill("{dodge}: roll · {cover} grab") == "Space: roll · E grab", "on the keyboard, keys again")


func _truck() -> void:
	var truck := Truck.new()
	add_child(truck)
	truck.global_position = player.global_position + Vector3(4, 0.6, 0)
	await _wait(0.3)
	player.enter_vehicle(truck)
	await _wait(0.2)
	_stick(JOY_AXIS_TRIGGER_RIGHT, 1.0)
	await _wait(1.5)
	var speed := truck.linear_velocity.length()
	_check(speed > 1.5, "RT drives the truck (%.1f m/s)" % speed)
	_stick(JOY_AXIS_TRIGGER_RIGHT, 0.0)
	_stick(JOY_AXIS_TRIGGER_LEFT, 1.0)
	await _wait(1.0)
	_stick(JOY_AXIS_TRIGGER_LEFT, 0.0)
	_check(truck.linear_velocity.length() < speed * 0.6, "LT slows it (%.1f m/s)" % truck.linear_velocity.length())
	player.exit_vehicle()


func _wheel() -> void:
	var w := ConversationWheel.new()
	add_child(w)
	await get_tree().process_frame
	w.show_choices(["Ask", "Leave", "Threaten"], ["ur", "r", "ll"])
	var picked := [-1]
	w.chosen.connect(func(i: int): picked[0] = i)
	Controls.note_device(_button_event(JOY_BUTTON_A, true))
	_stick(JOY_AXIS_LEFT_X, 1.0)
	_stick(JOY_AXIS_LEFT_Y, 0.0)
	await _wait(0.1)
	_check(w.hovered == 1, "the stick right points at the right-hand choice (%d)" % w.hovered)
	_stick(JOY_AXIS_LEFT_X, 0.0)
	await _wait(0.1)
	_check(w.hovered == 1, "it stays picked when the stick comes back")
	_tap(JOY_BUTTON_A)
	await _wait(0.1)
	_check(picked[0] == 1, "A takes it (%d)" % picked[0])
	w.queue_free()


# ---------------------------------------------------------------- simulated pad

func _button_event(b: JoyButton, pressed: bool) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.device = 0
	e.button_index = b
	e.pressed = pressed
	return e


func _motion_event(axis: JoyAxis, v: float) -> InputEventJoypadMotion:
	var e := InputEventJoypadMotion.new()
	e.device = 0
	e.axis = axis
	e.axis_value = v
	return e


func _stick(axis: JoyAxis, v: float) -> void:
	Input.parse_input_event(_motion_event(axis, v))


func _tap(b: JoyButton) -> void:
	Input.parse_input_event(_button_event(b, true))
	await get_tree().physics_frame
	await get_tree().physics_frame
	Input.parse_input_event(_button_event(b, false))


func _wait(secs: float) -> void:
	await get_tree().create_timer(secs).timeout


func _check(ok: bool, what: String) -> void:
	print("RESULT %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_fails += 1
