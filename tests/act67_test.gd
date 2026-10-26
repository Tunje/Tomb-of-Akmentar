extends Node3D
## Acts 6 and 7 data test: every act6 / act7 dialogue validates, and the talks run through the real
## Conversation: the Keepers (countdowns, horses, the temple ritual), the road back (the thieves'
## trail, the night camp), the Cairo investigation per thief, Fletcher's delay, Nabil, Hassan's
## confession and lockdown, every way the confrontation can go, Blackwood, and the endings.
## Prints RESULT lines; exits 0 when every check passed.
##   --shot-dir=C:/path   where PNGs go (default user://act67_shots)
## Never takes focus or captures the mouse (Simon plays while we test).

class FakePlayer extends Node3D:
	var controls_enabled := true
	var yaw := 0.0

var _dir := "user://act67_shots"
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
		if (f.begins_with("act6_") or f.begins_with("act7_")) and f.ends_with(".json"):
			var id := f.get_basename()
			var probs := Conversation.validate(Conversation.load_data(id))
			_check(probs.is_empty(), "%s validates %s" % [id, probs])

	# ---- Act 6
	_fresh([], "germans")
	Game.set_flag("temple_studied")
	var r := await _talk("act6_keepers", ["Share the temple ritual", "Ask for horses", "Go"])
	_check(int(Game.countdowns.thieves) == 7 and int(Game.countdowns.mummy) == 10 and int(Game.flag("keeper_horses", 0)) == 2,
		"keepers: countdowns 7 / 10 with the ritual, two horses")
	Game.apply([{"recruit": "isabelle"}])
	Game.set_flag("act6_desert_pick")
	r = await _talk("act6_road", ["Break camp and ride"])
	_check(Game.flag("lead_station") and Game.flag("clue_trail_germans") and int(Game.companion("isabelle").fear) == 1,
		"road: the German trail, ride on (fear)")
	_fresh([], "italians")
	Game.set_flag("act6_desert_pick")
	r = await _talk("act6_road", ["Hold the camp"])
	_check(r.end == "end_fight" and "fight_mummy_servants" in _events and not Game.flag("lead_police"), "road: no trail on the wrong road; hold = fight")

	# ---- Act 7 investigation
	_fresh([], "americans")
	Game.set_flag("clara_watching")
	r = await _talk("act7_hotel", [])
	_check(Game.flag("thieves_lodging") and Game.flag("thieves_plan_known") and Game.flag("clue_plan_americans"), "hotel: lodging and, watched, the plan")
	_fresh([], "germans")
	r = await _talk("act7_docks", ["Leave"])
	_check(not Game.flag("thieves_plan_known"), "docks: nothing on the Germans")
	r = await _talk("act7_station", ["Leave"])
	_check(Game.flag("thieves_plan_known") and Game.flag("clue_plan_germans"), "station: the Germans' night express")
	_fresh([], "italians")
	r = await _talk("act7_police", ["Ask for his help", "Leave"])
	_check(Game.flag("thieves_plan_known") and Game.flag("police_help"), "police: the Italians' permit, police help")
	_fresh(["idris"], "americans")
	Game.set_flag("idris_contacts")
	r = await _talk("act7_bazaar", [])
	_check(Game.flag("lead_docks") and Game.flag("thieves_plan_known") and r.speakers.has("idris"), "bazaar: a lead, and Idris's friends")
	_fresh([], "germans")
	Game.set_flag("freddie_note")
	r = await _talk("act7_tavern", [])
	_check(Game.flag("freddie_helped") and Game.flag("thieves_plan_known"), "tavern: Freddie pays his debt")
	_fresh([], "italians")
	Game.set_flag("fletcher_wired")
	Game.apply([{"countdown": ["thieves", 3]}, {"stat": ["nabil", "trust", 1]}])
	r = await _talk("act7_telegraph", ["Wire Danny Fletcher"])
	_check(int(Game.countdowns.thieves) == 5 and Game.flag("fletcher_delay"), "telegraph: Fletcher buys two days")
	r = await _talk("act7_telegraph", ["Ask about their wires"])
	_check(Game.flag("thieves_plan_known") and Game.flag("clue_plan_italians"), "telegraph: Nabil reads their wires")
	_fresh(["hassan"], "americans")
	Game.apply([{"stat": ["hassan", "trust", 2]}])
	r = await _talk("act7_hassan", ["Forgive him"])
	_check(Game.flag("hassan_offered_lockdown") and Game.flag("hassan_revealed"), "Hassan confesses and offers the lockdown")
	r = await _talk("act7_lockdown", [])
	_check(Game.flag("lockdown") and Game.flag("clue_lockdown"), "the lockdown")
	var spot := ActionSpot.make(self, "act7_intercept", Vector3(3, 0, 0))
	await get_tree().process_frame
	var labels: Array = spot.rows().map(func(x: Dictionary) -> String: return x.label)
	_check(labels == ["Wait for them at the road gate"], "intercept under the lockdown: %s" % [labels])

	# ---- The confrontation
	_fresh([], "americans")
	Game.set_flag("sky_dark")
	Game.apply([{"stat": ["whitfield", "trust", 2]}])
	r = await _talk("act7_confront", ["Point at the sky"])
	_check(r.end == "end_recovered" and Game.flag("recovered_peacefully") and Game.flag("artifacts_recovered"), "Whitfield, a friend, yields under the dark sky")
	_fresh([], "americans")
	Game.set_flag("sky_dark")
	Game.money = 200
	r = await _talk("act7_confront", ["Point at the sky", "Buy them back", "Pay him"])
	_check(r.end == "end_recovered" and Game.money == 100 and Game.flag("bought_artifacts"), "Whitfield sells them for 100")
	_fresh([], "germans")
	Game.set_flag("sky_dark")
	Game.set_flag("stones_falling")
	r = await _talk("act7_confront", ["Appeal to Vogel"])
	_check(r.end == "end_recovered" and r.speakers.has("vogel"), "Vogel overrules Adler when stones fall")
	_fresh([], "italians")
	r = await _talk("act7_confront", ["Take them"])
	_check(r.end == "end_fight" and "fight_thieves" in _events, "Bellini: a fight")
	_fresh([], "italians")
	Game.set_flag("sickness")
	r = await _talk("act7_confront", ["Appeal to Sofia"])
	_check(r.end == "end_recovered" and r.speakers.has("sofia"), "Sofia turns Bellini once the sickness comes")

	# ---- After
	Game.set_flag("fletcher_delay")
	r = await _talk("act7_recovered", [])
	_check(Game.flag("new_objective") == "return_artifacts" and Game.flag("fletcher_offers_plane"), "recovered: back to Akmentar, Fletcher's plane")
	Game.set_flag("heard_blackwood_silence")
	Game.money = 0
	r = await _talk("act7_blackwood", ["Confront him"])
	_check(Game.flag("blackwood_confessed") and Game.money == 100, "Blackwood confesses")
	_fresh([], "germans")
	r = await _talk("act7_too_late", [])
	_check(Game.flag("thieves_escaped"), "too late")


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
