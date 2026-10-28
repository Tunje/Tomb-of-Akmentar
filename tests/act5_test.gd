extends Node3D
## Act 5 talk and investigation test: the Level 2 budget (3 alone; 3 + the ally's 2 picks), the
## royal tomb's interruption (after the 2nd, after the 1st with german_delay), the door's delay
## feeding the tomb budget, and every path of act5_morning, act5_royal_door and act5_revelation,
## driven through the real Conversation. Prints RESULT lines; exits 0 when every check passed.
##   --shot-dir=C:/path   where PNGs go (default user://act5_shots)
## Never takes focus or captures the mouse (Simon plays while we test).

class FakePlayer extends Node3D:
	var controls_enabled := true
	var yaw := 0.0

const BELOW := "akmentar_below"
const TOMB := "royal_tomb"

var _dir := "user://act5_shots"
var _player: FakePlayer
var _npc: Node3D
var _fails := 0
var _shoot := ""
var _events: Array[String] = []
var _spots := {}   # "area/site" -> SiteSpot


func _ready() -> void:
	get_window().set_flag(Window.FLAG_NO_FOCUS, true)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot-dir="):
			_dir = a.substr(11)
	DirAccess.make_dir_recursive_absolute(_dir)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.1, 0.08, 0.06)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.7, 0.55, 0.4)
	add_child(env)
	var ground := MeshInstance3D.new()
	ground.mesh = PlaneMesh.new()
	ground.mesh.size = Vector2(60, 60)
	add_child(ground)
	_player = FakePlayer.new()
	add_child(_player)
	_capsule(_player, Color(0.62, 0.5, 0.32))
	_player.position = Vector3(0.5, 0, 1.0)
	_npc = Node3D.new()
	add_child(_npc)
	_capsule(_npc, Color(0.35, 0.3, 0.28))
	_npc.position = Vector3(-0.5, 0, -0.9)
	var cam := Camera3D.new()
	add_child(cam)
	cam.current = true
	# Every site of both areas, spread out so only the one we use is in reach.
	var k := 0
	for area: String in [BELOW, TOMB]:
		for id: String in SiteSpot.load_area(area).sites:
			_spots[area + "/" + id] = SiteSpot.make(self, area, id, Vector3(20 + k * 4, 0, 20))
			k += 1
	Game.event.connect(func(e: String): _events.append(e))
	_run.call_deferred()


func _capsule(n: Node3D, c: Color) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = CapsuleMesh.new()
	mi.position.y = 0.9
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	mi.material_override = m
	n.add_child(mi)


func _run() -> void:
	await get_tree().process_frame
	for id in ["act5_morning", "act5_royal_door", "act5_revelation", "act4_dawn"]:
		var probs := Conversation.validate(Conversation.load_data(id))
		_check(probs.is_empty(), "%s validates (%s)" % [id, "; ".join(probs)])
	_check(SiteSpot.load_area(BELOW).sites.size() == 9 and SiteSpot.load_area(TOMB).sites.size() == 5, "9 Level 2 points, 5 royal tomb points")

	# ---- Level 2, alone: 3 investigations.
	_fresh({})
	for id in ["weeping_stair", "opening_chapel", "embalmers"]:
		_check(await _inspect(BELOW, id), "alone: inspect %s" % id)
	_check(Game.flag("found_warning") and Game.flag("found_ritual") and Game.flag("found_funerary"), "found_warning / found_ritual / found_funerary set")
	_check(not await _inspect(BELOW, "wards") and Notice.last.begins_with("You've spent your time"), "alone: a 4th is refused ('%s')" % Notice.last)
	_check(Game.actions_left == Game.ACTIONS_PER_DAY, "no day actions spent below ground")

	# ---- Level 2 with the Germans: 3 of yours + their 2 picks.
	_fresh({"ally": "germans"})
	var s: SiteSpot = _spots[BELOW + "/erased_king"]
	s.refusal()  # starts the budget
	_check(Game.flag("ally_site_erased_king") and Game.flag("ally_site_builders") and not Game.flag("ally_site_wards"), "Germans insist on the erased king and the builders' wall")
	_check(s.prompt() == "Inspect Hall of the Erased King (the Germans' pick)", "prompt: '%s'" % s.prompt())
	for id in ["erased_king", "builders", "weeping_stair", "opening_chapel", "wards"]:
		_check(await _inspect(BELOW, id), "with the Germans: inspect %s" % id)
	_check(not await _inspect(BELOW, "treasury"), "with the Germans: a 6th is refused")
	_check(Game.flag("found_history") and Game.flag("found_symbols"), "found_history / found_symbols set")
	_fresh({"ally": "americans"})
	_spots[BELOW + "/treasury"].refusal()
	_check(Game.flag("ally_site_treasury") and Game.flag("ally_site_chariots"), "Americans insist on the treasury and the chariots")

	# ---- Royal tomb: cut off after the 2nd.
	_fresh({})
	_check(await _inspect(TOMB, "sarcophagus") and not Game.flag("tomb_interrupted"), "tomb: 1st, not cut yet")
	_check(await _inspect(TOMB, "amulet"), "tomb: 2nd")
	_check(Game.flag("tomb_interrupted") and _events.has("royal_tomb_interrupted"), "tomb: cut off after the 2nd (event royal_tomb_interrupted)")
	_check(not await _inspect(TOMB, "canopic") and Notice.last.begins_with("Something has woken"), "tomb: the 3rd is lost ('%s')" % Notice.last)
	_check(Game.flag("tomb_sarcophagus") and Game.flag("tomb_amulet") and not Game.flag("tomb_canopic"), "tomb_<poi> flags for what was seen")
	# The German delay from the door feeds the tomb's budget.
	_fresh({"ally_is_germans": true, "ally": "germans"})
	var r := await _talk("act5_royal_door", ["Agree"])
	_check(Game.flag("german_delay") and r.end == "end_delay", "door, Germans, no ritual: german_delay")
	_check(await _inspect(TOMB, "altar") and Game.flag("tomb_interrupted"), "tomb with the delay: cut off after the 1st")
	_check(SiteBudget.state(TOMB).slots == 2, "tomb with the delay: 2 slots (%s)" % [SiteBudget.state(TOMB)])

	# ---- Morning
	_fresh({"ally_is_americans": true, "ally": "americans", "claimed_anubis_americans": true,
		"claimed_scarabs_americans": true, "claimed_storeroom_americans": true})
	Game.apply([{"recruit": "eleanor"}, {"stat": ["whitfield", "trust", 1]}])
	_shoot = "act5_morning.png"
	r = await _talk("act5_morning", ["Ask Eleanor", "Press him", "Let it go"])
	_check(Game.flag("ally_shared_anubis") and Game.flag("ally_shared_scarabs"), "Whitfield shares his first two (anubis, scarabs)")
	_check(_said(r, "under my hat"), "he withholds the third")
	_check(Game.flag("ally_shared_storeroom") and not Game.flag("ally_withheld"), "pressed with trust 1: he gives up the storeroom")
	_check(Journal.has("clue_anubis") and Journal.has("clue_storeroom") and Game.flag("clue_scarabs"), "shared clues are in the journal (and their clue flags)")
	_check(r.speakers.has("eleanor"), "Eleanor chimes in")
	_fresh({"ally_is_germans": true, "ally": "germans", "claimed_horus_germans": true, "claimed_obelisk_germans": true, "claimed_souls_germans": true})
	r = await _talk("act5_morning", ["Press him", "Let it go"])
	_check(Game.flag("ally_shared_horus") and Game.flag("ally_shared_obelisk") and Game.flag("ally_withheld_souls") and not Game.flag("ally_shared_souls"),
			"Adler shares horus and obelisk, holds the Hall of Souls; pressed at trust 0 he refuses")
	_check(r.labels.count("Challenge him") == 1 and r.labels.count("Press him") == 1, "after pressing, no second go (press / challenge offered once)")
	_fresh({"ally_is_germans": true, "ally": "germans", "claimed_horus_germans": true, "claimed_obelisk_germans": true, "claimed_souls_germans": true})
	Game.apply([{"recruit": "eleanor"}])
	r = await _talk("act5_morning", ["Challenge him", "Let it go"])
	_check(int(Game.companions.adler.trust) == -1 and _said(r, "Let him keep his secret"), "challenge: Adler's trust -1, Eleanor calms it")
	_fresh({})
	Game.apply([{"recruit": "eleanor"}])
	r = await _talk("act5_morning", [])
	_check(r.speakers.has("eleanor") and r.end == "end", "no ally: Eleanor's short line")

	# ---- Royal door
	_fresh({"ally_is_americans": true, "ally": "americans"})
	r = await _talk("act5_royal_door", ["Tell him to wait"])
	_check(Game.flag("door_forced") == true and r.end == "end_forced", "Americans, no warning: they force it")
	_fresh({"ally_is_americans": true, "ally": "americans", "found_warning": true})
	r = await _talk("act5_royal_door", ["Show him the warning"])
	_check(Game.flag("door_forced", null) == false and r.end == "end_safe", "Americans, with the warning: they back down")
	_fresh({"ally_is_germans": true, "ally": "germans", "found_ritual": true})
	r = await _talk("act5_royal_door", ["Show him the ritual"])
	_check(Game.flag("german_delay", null) == false and r.end == "end_safe", "Germans, with the ritual: no delay")
	_fresh({"found_ritual": true})
	r = await _talk("act5_royal_door", ["Use the ritual"])
	_check(r.end == "end_safe" and not Game.flag("door_forced") and not Game.flag("german_delay"), "no ally: your call, no penalty")

	# ---- Revelation
	_fresh({"recognized_bandits": true, "thieves_germans": true, "clue_embalmers": true})
	Game.apply([{"recruit": "eleanor"}])
	_shoot = "act5_revelation.png"
	r = await _talk("act5_revelation", ["Ask about the guardian", "Ask why they attacked", "Ask what to do", "Accept"])
	_check(_said(r, "I know your face") and _said(r, "German partners"), "Bashir recognises you; the Germans took it")
	_check(_said(r, "built him to wake"), "Eleanor remembers the embalmers' instructions")
	_check(Game.flag("new_objective") == "recover_amulet" and int(Game.companions.rashad.trust) == 1, "accepted: new_objective = recover_amulet, Rashad's trust +1")
	_fresh({"thieves_italians": true})
	r = await _talk("act5_revelation", ["Blame them", "Ask what to do", "Accept, grudgingly"])
	_check(_said(r, "Italians") and not _said(r, "I know your face"), "Italians took it; Bashir doesn't know you")
	_check(int(Game.companions.rashad.trust) == -1 and Game.flag("new_objective") == "recover_amulet", "blamed: trust -1, objective still set")
	_check(DayLog.person("rashad") == "Sheikh Rashad al-Khatib", "people.json names the Keepers")

	print("RESULT act5_test %s fails=%d" % ["PASS" if _fails == 0 else "FAIL", _fails])
	await get_tree().create_timer(0.2).timeout
	get_tree().quit(0 if _fails == 0 else 1)


func _fresh(flags: Dictionary) -> void:
	Game.reset()
	DayLog.begin_day()
	_events.clear()
	for k in flags:
		Game.set_flag(k, flags[k])
	# (No first-time hints: the journal's, queued again after every reset, would land on the
	# notice line between an inspect and its check.)
	Game.set_flag("hints_off", true)
	Hints.reset()


## Inspect a site as E would, then read and close its clue card.
func _inspect(area: String, id: String) -> bool:
	var s: SiteSpot = _spots[area + "/" + id]
	var ok := s.inspect(_player)
	await get_tree().create_timer(0.45).timeout
	for n in get_children():
		if n is ClueCard and not (n as ClueCard).is_closed():
			(n as ClueCard).close()
	await get_tree().process_frame
	print("RESULT inspect %s/%s -> %s (budget %s)" % [area, id, ok, SiteBudget.state(area)])
	return ok


func _talk(id: String, picks: Array) -> Dictionary:
	var out := {"end": "", "lines": [], "speakers": [], "labels": []}
	var c := Conversation.new()
	add_child(c)
	c.finished.connect(func(e: String): out.end = e if e != "" else "<none>")
	c.line_started.connect(func(sp: String, t: String):
		out.lines.append([sp, t])
		if not sp in out.speakers:
			out.speakers.append(sp))
	c.choices_shown.connect(func(l: Array): out.labels.append_array(l))
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
			if _shoot != "":
				await _shot(_shoot)
				_shoot = ""
			var labels: Array = c.visible_choices.map(func(x): return x.label)
			var want: String = todo.pop_front() if not todo.is_empty() else ""
			var i := labels.find(want)
			if i < 0:
				_check(false, "%s: choice '%s' on the wheel %s" % [id, want, labels])
				c.choose(labels.size() - 1)
			else:
				c.choose(i)
	print("RESULT %s -> %s via %s" % [id, out.end, " / ".join(out.lines.map(func(l): return l[0]))])
	return out


func _said(r: Dictionary, bit: String) -> bool:
	return r.lines.any(func(l): return bit in str(l[1]))


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
