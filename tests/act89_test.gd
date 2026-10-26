extends Node3D
## Acts 8 and 9 data test: every act8 / act9 dialogue validates, the route board's transport locks,
## and the talks run through the real Conversation: who carries the amulet, the plane's one seat,
## the last night and the rearguard, every way the surrender can end, the temple, the guardians,
## the knowledge-or-fight threats, the ritual with one voice or none, and the ending album.
## Prints RESULT lines; exits 0 when every check passed.
##   --shot-dir=C:/path   where PNGs go (default user://act89_shots)
## Never takes focus or captures the mouse (Simon plays while we test).

class FakePlayer extends Node3D:
	var controls_enabled := true
	var yaw := 0.0

var _dir := "user://act89_shots"
var _player: FakePlayer
var _npc: Node3D
var _fails := 0
var _events: Array[String] = []


func _ready() -> void:
	get_window().set_flag(Window.FLAG_NO_FOCUS, true)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot-dir="):
			_dir = a.substr(11)
	DirAccess.make_dir_recursive_absolute(_dir)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.12, 0.1, 0.08)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.7, 0.6, 0.5)
	add_child(env)
	var cam := Camera3D.new()
	add_child(cam)
	cam.position = Vector3(0, 3, 6)
	cam.make_current()
	_player = FakePlayer.new()
	add_child(_player)
	_player.position = Vector3(0, 0, 1.5)
	_npc = Node3D.new()
	add_child(_npc)
	Game.event.connect(func(e: String) -> void: _events.append(e))
	await get_tree().process_frame
	await _run()
	print("RESULT %s (%d failed)" % ["PASS" if _fails == 0 else "FAIL", _fails])
	get_tree().quit(0 if _fails == 0 else 1)


func _run() -> void:
	for f in DirAccess.get_files_at("res://dialogue"):
		if (f.begins_with("act8_") or f.begins_with("act9_")) and f.ends_with(".json"):
			var id := f.get_basename()
			var probs := Conversation.validate(Conversation.load_data(id))
			_check(probs.is_empty(), "%s validates %s" % [id, probs])

	# ---- Act 8
	_fresh(["eleanor"])
	Game.set_flag("plane_ready")
	var o: Array = RouteBoard.load_board("act8_route").options
	var open_routes: Array = o.filter(func(x: Dictionary) -> bool: return Game.check(x.get("if", {}))).map(func(x: Dictionary) -> String: return x.id)
	_check(open_routes == ["plane"], "act8 board: only the plane without boat, horses or trucks (%s)" % [open_routes])
	var r := await _talk("act8_carrier", ["The scholars", "Eleanor"])
	_check(Game.flag("carrier") == "eleanor" and Game.flag("carrier_eleanor"), "Eleanor carries the amulet")

	_fresh(["eleanor", "isabelle"])
	r = await _talk("act8_plane", ["The fighters", "Isabelle"])
	_check(Game.flag("plane_isabelle") and Game.flag("left_in_cairo"), "the plane: Isabelle's seat")
	r = await _talk("act8_final", ["Walk out to him"])
	_check(r.end == "end_sacrifice" and Game.flag("sacrifice_heroic") and not Game.in_party("isabelle") and Game.in_party("eleanor"),
		"plane, surrender: Isabelle dies beside you, Eleanor lives in Cairo")

	_fresh(["eleanor", "hargreaves"])
	r = await _talk("act8_final", ["Walk out to him"])
	_check(Game.flag("sacrifice_failed") and not Game.in_party("eleanor") and not Game.in_party("hargreaves"), "surrender with everyone near: all die")

	_fresh(["eleanor", "isabelle"])
	Game.apply([{"stat": ["isabelle", "trust", 3]}])
	r = await _talk("act8_final", ["Send the others away", "Walk out to him"])
	_check(Game.flag("sacrifice_heroic") and Game.flag("isabelle_stayed") and not Game.in_party("isabelle") and Game.in_party("eleanor"),
		"sent away: Eleanor lives, Isabelle refuses to go and dies")

	_fresh(["hargreaves"])
	r = await _talk("act8_last_night", ["Talk to the fighters", "Tom", "Go on", "Let him hold the rear"])
	_check(Game.flag("rear_held") and Game.flag("hargreaves_rearguard"), "the last night: Tom holds the rear")
	r = await _talk("act8_final", ["Go down into the tomb"])
	_check(r.end == "end_descend" and Game.flag("act8_choice") == "descend", "descend into the tomb")

	_fresh(["pembroke"])
	Game.set_flag("temple_studied")
	r = await _talk("act8_temple", [])
	_check(Game.flag("temple_known") and "fight_at_temple" in _events, "the temple battle, with Pembroke's survey")

	# ---- Act 9
	_fresh(["eleanor"])
	Game.set_flag("recognized_bandits")
	r = await _talk("act9_arrival", ["Answer Omar", "Go"])
	_check(Game.flag("noura_alive") and Game.flag("omar_alive") and int(Game.companion("omar").trust) == 1, "the two guardians; Omar answered")
	Game.set_flag("clue_greetings")
	r = await _talk("act9_surface", ["Speak the greeting"])
	_check(r.end == "end_safe" and Game.flag("act9_greeted"), "surface: the greeting gets you past")
	r = await _talk("act9_halls", ["Force it"])
	_check(r.end == "end_fight" and "act9_halls_fight" in _events, "halls: no clue, a fight")
	Game.set_flag("noura_alive", false)
	r = await _talk("act9_ritual", [])
	_check(r.end == "end_defend" and int(Game.flag("ritual_voices", 0)) == 1 and r.speakers.has("omar"), "ritual: Omar alone")
	Game.set_flag("ritual_done")
	r = await _talk("act9_end", [])
	_check(r.end == "end_restored" and Game.flag("barrier_restored") and r.speakers.has("omar"), "the barrier restored")
	Game.set_flag("omar_alive", false)
	Game.set_flag("ritual_done", false)
	r = await _talk("act9_ritual", [])
	_check(r.end == "end_failed" and Game.flag("ritual_failed"), "ritual: no voices left")

	# ---- The album
	_fresh(["eleanor"])
	Game.set_flag("promised_eleanor_publish")
	Game.apply([{"stat": ["eleanor", "trust", 2]}, {"recruit": "hassan"}, {"kill": "hassan"}])
	Game.set_flag("hired_eleanor")
	Game.set_flag("hired_hassan")
	Game.set_flag("barrier_restored")
	Game.set_flag("act9_started")
	Game.set_flag("omar_alive")
	Game.set_flag("thieves_germans")
	Game.set_flag("lockdown")
	var v: Array = EpilogueShow.pick_cards("akmentar").map(func(c: Dictionary) -> String: return "%s:%s" % [c.who, c.variant])
	print("RESULT album %s" % [v])
	_check("eleanor:published" in v and "hassan:died" in v and "noura:fell" in v and "omar:guardian" in v and "adler:stubborn" in v
		and "archivist:signed" in v and "keepers:restored" in v and "player:survived" in v, "the album follows the flags")


func _fresh(party: Array, thieves := "") -> void:
	Game.reset()
	for id in party:
		Game.apply([{"recruit": id}])
	if thieves != "":
		Game.set_flag("thieves", thieves)
		Game.set_flag("thieves_" + thieves)


func _talk(id: String, picks: Array) -> Dictionary:
	var out := {"end": "", "lines": [], "speakers": []}
	var c := Conversation.new()
	add_child(c)
	c.finished.connect(func(e: String) -> void: out.end = e if e != "" else "<none>")
	c.line_started.connect(func(sp: String, _t: String) -> void:
		out.lines.append(sp)
		if not sp in out.speakers:
			out.speakers.append(sp))
	c.start(id, _player, _npc)
	var frames := 0
	var todo := picks.duplicate()
	while out.end == "" and frames < 3000:
		frames += 1
		await get_tree().process_frame
		if not is_instance_valid(c):
			break
		if c.state == Conversation.State.LINE or c.state == Conversation.State.PLAYER_LINE:
			c.wheel.advance.emit()
		elif c.state == Conversation.State.CHOICES:
			var labels: Array = c.visible_choices.map(func(x: Dictionary) -> String: return x.label)
			var want: String = todo.pop_front() if not todo.is_empty() else ""
			var i := labels.find(want)
			if i < 0:
				_check(false, "%s: choice '%s' on the wheel %s" % [id, want, labels])
				c.choose(labels.size() - 1)
			else:
				c.choose(i)
	print("RESULT %s -> %s via %s" % [id, out.end, " / ".join(out.lines)])
	return out


func _check(ok: bool, what: String) -> void:
	print("RESULT %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_fails += 1


func _shot(file: String) -> void:
	if DisplayServer.get_name() == "headless":
		return  # no pictures with the dummy renderer
	await RenderingServer.frame_post_draw
	var p := _dir.path_join(file)
	get_viewport().get_texture().get_image().save_png(p)
	print("RESULT shot %s" % ProjectSettings.globalize_path(p))
