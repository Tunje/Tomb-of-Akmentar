extends Node3D
## Board screens test (build plan step 12): the Act 3 route map (desert, then the temple branch),
## countdown bars, the Act 6 return map (desert at severe risk without horses, river unavailable, the
## coast ticking both countdowns), the Act 4 site draft played in full (3 rounds, rivals by
## priority, the Egyptologist's advice), the draft order when you arrive last, and the epilogue.
## Prints RESULT lines and saves screenshots; exits 0 when every check passed. Args after "--":
##   --shot-dir=C:/path   where PNGs go (default user://boards_shots)
## Never takes focus or captures the mouse (Simon plays while we test).

class FakePlayer extends Node3D:
	var controls_enabled := true

var _dir := "user://boards_shots"
var _player: FakePlayer
var _fails := 0


var _events: Array[String] = []

func _ready() -> void:
	get_window().set_flag(Window.FLAG_NO_FOCUS, true)
	if DisplayServer.get_name() == "headless":
		get_window().size = Vector2i(1600, 900)  # the boards lay out from the screen size
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot-dir="):
			_dir = a.substr(11)
	DirAccess.make_dir_recursive_absolute(_dir)
	Game.reset()
	Game.money = 300
	Game.event.connect(func(e: String) -> void: _events.append(e))
	DayLog.begin_day()
	var we := WorldEnvironment.new()
	we.environment = Environment.new()
	we.environment.background_mode = Environment.BG_COLOR
	we.environment.background_color = Color(0.5, 0.42, 0.3)
	add_child(we)
	var cam := Camera3D.new()
	add_child(cam)
	cam.current = true
	_player = FakePlayer.new()
	add_child(_player)
	_run.call_deferred()


func _run() -> void:
	await _wait(0.3)

	# ---- Act 3 route map
	var b := RouteBoard.open(self, "act3_route", _player)
	await _wait(0.3)
	_check(not _player.controls_enabled, "controls off on the map")
	await _shot("board_1_route_map.png")
	_click(b.option_point(0))
	await _wait(0.2)
	_check(b.selected == 0, "click selects the desert route")
	await _shot("board_2_route_desert.png")
	_click(b.option_point(0))  # a second click takes it
	await _wait(0.2)
	# No guide hired: the desert takes 4 days, not 3; the fork talk (event desert_fork) comes next.
	_check(Game.money == 240 and Game.day == 5 and Game.flag("route_act3_route") == "desert",
			"desert: £60 paid (money %d), 4 days without a guide (day %d)" % [Game.money, Game.day])
	_check(_gone(b) and "desert_fork" in _events, "the desert board closes and raises desert_fork (%s)" % [_events])
	Game.set_flag("fork_temple")  # what act3_fork decided
	b = RouteBoard.open(self, "act3_desert_branch", _player)
	await _wait(0.3)
	_check(b.reason(1) == "You chose the temple" and b.reason(0) == "", "the branch follows the fork (%s)" % b.reason(1))
	await _shot("board_3_branch.png")
	var picks: Array = []
	b.finished.connect(func(p: Array): picks.append_array(p))
	_key(KEY_1)
	_key(KEY_ENTER)
	await _wait(0.2)
	_check(_gone(b) and picks.size() == 1, "temple taken, board closed (picks %s)" % [picks])
	_check(int(Game.flag("race_step")) == 3 and Game.flag("visited_temple") and Game.day == 6, "race_step 3, day 6")
	# A guide saves the day; a booked riverboat is free.
	Game.set_flag("hired_youssef")
	Game.set_flag("booked_riverboat")
	var o: Array = RouteBoard.load_board("act3_route").options
	_check(RouteBoard.num(o[0], "days") == 3 and RouteBoard.num(o[1], "cost") == 0 and RouteBoard.num(o[2], "days") == 6,
			"days_if / cost_if (%d days, £%d)" % [RouteBoard.num(o[0], "days"), RouteBoard.num(o[1], "cost")])

	# ---- Countdowns and the Act 6 return
	Game.apply([{"countdown": ["thieves", 5]}, {"countdown": ["mummy", 8]}])
	var bars := CountdownBars.new()
	add_child(bars)
	await _wait(0.2)
	_check(bars.visible, "countdown bars show when countdowns exist")
	await _shot("board_4_countdown_bars.png")
	Game.flags.erase("has_horses")  # lost the horses in the attack
	Game.set_flag("trucks_running")
	b = RouteBoard.open(self, "act6_return", _player)
	await _wait(0.2)
	# Without enough horses the desert can still be picked, at Severe risk (act6.gd ends it).
	_check(b.reason(0) == "" and RouteBoard.num(b.options()[0], "risk") == 3 and b.reason(2) == "No boats left" and b.reason(1) == "",
			"desert severe, river unavailable, coast open (%s / %s / %s)" % [b.reason(0), b.reason(2), b.reason(1)])
	_key(KEY_3)
	_key(KEY_ENTER)
	await _wait(0.2)
	_check(not _gone(b) and b.message == "No boats left", "the river can't be taken ('%s')" % b.message)
	_key(KEY_2)
	await _wait(0.3)
	await _shot("board_5_return_coast.png")
	_key(KEY_ENTER)
	await _wait(0.3)
	_check(int(Game.countdowns.thieves) == 0 and int(Game.countdowns.mummy) == 3,
			"coast: 5 days, thieves %d mummy %d" % [Game.countdowns.thieves, Game.countdowns.mummy])
	await _shot("board_6_countdowns_after.png")
	bars.queue_free()

	# ---- Site draft, arriving last (race_step 5): the rivals take Anubis and Horus first.
	Game.apply([{"recruit": "eleanor"}])
	Game.set_flag("race_step", 5)
	var d := SiteDraft.open(self, "akmentar_surface", _player)
	_check(d.order == ["germans", "americans", "player"], "arriving last: order %s" % [d.order])
	await _wait(2.2)
	_check(d.claims.get("horus") == "germans" and d.claims.get("anubis") == "americans" and d.whose_turn() == "player",
			"Germans took Horus, Americans Anubis, now you (%s)" % [d.claims])
	_check(d.advice() == "ra", "Eleanor now suggests Ra (%s)" % d.advice())
	await _shot("board_7_draft_last.png")
	d.close()
	for k in Game.flags.keys().filter(func(f): return str(f).begins_with("claimed_")):
		Game.flags.erase(k)

	# ---- Site draft, arriving first: three full rounds.
	Game.set_flag("race_step", 3)
	d = SiteDraft.open(self, "akmentar_surface", _player)
	_check(d.order == ["player", "germans", "americans"], "arriving first: order %s" % [d.order])
	_check(d.advice() == "anubis", "Eleanor suggests Anubis first")
	await _wait(0.3)
	await _shot("board_8_draft_first.png")
	_click(d.site_point("anubis"))
	await _wait(2.2)
	_check(d.claims.get("horus") == "germans" and d.claims.get("scarabs") == "americans",
			"round 1: Germans Horus, Americans the scarab wall (%s)" % [d.claims])
	_check(d.advice() == "ra", "then Ra")
	_key(KEY_1 + d.sites.find("ra"))
	await _wait(2.2)
	_click(d.site_point("astronomer"))
	await _wait(2.2)
	_check(d.done(), "draft done after 9 claims (%d)" % d.claims.size())
	var mine := d.claims.keys().filter(func(s): return d.claims[s] == "player")
	_check(mine == ["anubis", "ra", "astronomer"], "yours: %s" % [mine])
	var want := {"horus": "germans", "hieroglyphs": "germans", "obelisk": "germans",
		"scarabs": "americans", "storeroom": "americans", "mummification": "americans"}
	var rivals_ok := want.keys().all(func(s): return d.claims.get(s) == want[s])
	_check(rivals_ok, "rivals by priority: %s" % [d.claims])
	_check(Game.flag("claimed_horus") == "germans" and Game.flag("claimed_anubis_player"), "claims saved as flags")
	await _shot("board_9_draft_done.png")
	_key(KEY_ENTER)
	await _wait(0.2)
	_check(_gone(d), "Enter closes the finished draft")

	# ---- Epilogue
	Game.apply([{"stat": ["eleanor", "trust", 2]}])
	var cards := EpilogueShow.pick_cards("akmentar")
	var variants := cards.map(func(c): return "%s:%s" % [c.who, c.variant])
	print("RESULT epilogue cards %s" % [variants])
	_check(variants == ["player:survived", "eleanor:published", "archivist:denied", "americans:home"], "epilogue picks by state")
	var e := EpilogueShow.open(self, "akmentar", _player)
	await _wait(0.8)
	await _shot("board_10_epilogue_1.png")
	_key(KEY_SPACE)
	await _wait(0.8)
	await _shot("board_11_epilogue_2.png")
	for k in 3:
		_key(KEY_SPACE)
		await _wait(0.1)
	_check(_gone(e), "the slideshow closes after the last card")
	_check(not ActionMenu.ui_open() and _player.controls_enabled, "nothing left open, controls on")
	_check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "mouse never captured")

	print("RESULT boards_test %s fails=%d" % ["PASS" if _fails == 0 else "FAIL", _fails])
	await _wait(0.2)
	get_tree().quit(0 if _fails == 0 else 1)


func _gone(screen) -> bool:
	return not is_instance_valid(screen) or screen.is_closed()


func _key(k: int) -> void:
	for pressed in [true, false]:
		var e := InputEventKey.new()
		e.keycode = k as Key
		e.physical_keycode = k as Key
		e.pressed = pressed
		Input.parse_input_event(e)


func _click(p: Vector2) -> void:
	var m := InputEventMouseMotion.new()
	m.position = p
	m.global_position = p
	Input.parse_input_event(m)
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
	if DisplayServer.get_name() == "headless":
		return  # no pictures with the dummy renderer
	await RenderingServer.frame_post_draw
	var path := _dir.path_join(file)
	get_viewport().get_texture().get_image().save_png(path)
	print("RESULT shot %s" % ProjectSettings.globalize_path(path))
