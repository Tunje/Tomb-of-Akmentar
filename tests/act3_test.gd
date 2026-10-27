extends Node3D
## Act 3 data test: every act3 dialogue validates, and the road talks run through the real
## Conversation: the fork (who argues, who minds), Hassan's misdirection at the temple, staying or
## leaving, the ambush aftermath with a prisoner, the town's resupply, Whitfield's wager on the
## boat, stranded with the Americans, the camp, and Youssef's shortcut both ways.
## Prints RESULT lines; exits 0 when every check passed.
##   --shot-dir=C:/path   where PNGs go (default user://act3_shots)
## Never takes focus or captures the mouse (Simon plays while we test).

class FakePlayer extends Node3D:
	var controls_enabled := true
	var yaw := 0.0

var _dir := "user://act3_shots"
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
		if f.begins_with("act3_") and f.ends_with(".json"):
			var id := f.get_basename()
			var probs := Conversation.validate(Conversation.load_data(id))
			_check(probs.is_empty(), "%s validates %s" % [id, probs])

	# The fork: Eleanor wants the temple, Saleh the town; you pick the temple.
	_fresh(["eleanor", "saleh"])
	var r := await _talk("act3_fork", ["The temple"])
	_check(r.end == "end_temple" and Game.flag("fork_temple") and _trust("eleanor") == 1 and _trust("saleh") == -1
		and r.speakers.has("eleanor") and r.speakers.has("saleh"), "fork: temple, Eleanor pleased, Saleh not")
	# Hassan, who heard you talk treasure in Cairo, plays the temple down.
	_fresh(["hassan"])
	Game.set_flag("hassan_heard_greed")
	r = await _talk("act3_fork", ["The town"])
	_check(r.end == "end_town" and Game.flag("hassan_misdirected") and _trust("hassan") == 1, "fork: Hassan steers you to the town")
	r = await _talk("act3_temple", ["Look for yourself"])
	_check(r.end == "end_stay" and Game.flag("hassan_caught") and Game.flag("clue_road_temple") and int(Game.flag("race_step")) == 4,
		"temple: looking anyway catches Hassan")
	# Eleanor at the temple, and you won't wait.
	_fresh(["eleanor"])
	r = await _talk("act3_temple", ["Leave at once"])
	_check(r.end == "end_leave" and int(Game.flag("race_step")) == 3 and _trust("eleanor") == -1 and not Game.flag("clue_road_temple"),
		"temple: leave at once keeps step 3")
	_fresh(["eleanor"])
	r = await _talk("act3_temple", ["Stay and study"])
	_check(r.end == "end_stay" and int(Game.flag("race_step")) == 4 and _trust("eleanor") == 1 and Game.flag("clue_road_temple"),
		"temple: stay studies, step 4")

	# After the ambush, with a prisoner; then the town.
	_fresh(["hargreaves"])
	Game.set_flag("ambush_prisoners", 2)
	Game.set_flag("supplies_lost", true)
	Game.money = 500
	r = await _talk("act3_after_ambush", ["Question him"])
	_check(Game.flag("recognized_bandits") and Game.flag("keepers_named") and r.speakers.has("hargreaves"), "ambush: the prisoner names the Veil")
	r = await _talk("act3_town", ["Resupply", "Move on"])
	_check(not Game.flag("supplies_lost") and Game.money == 350 and int(Game.inventory.get("water", 0)) == 7, "town: resupplied for 150")

	# The riverboat and after.
	_fresh(["isabelle"])
	r = await _talk("act3_riverboat", ["Hear his bet", "Accept", "Excuse yourself"])
	_check(Game.flag("wager_accepted") and Game.flag("wager_offered"), "boat: wager accepted")
	r = await _talk("act3_stranded", ["Walk with the Americans"])
	_check(int(Game.flag("race_step")) == 5 and Game.flag("walked_with_americans") and r.speakers.has("isabelle"), "stranded with the Americans")

	# Camp.
	_fresh(["eleanor", "khalil"])
	r = await _talk("act3_camp", ["Talk to the scholars", "Eleanor", "Laugh with her", "Talk to the crews", "Khalil",
		"Say yes", "Turn in"])
	_check(_trust("eleanor") == 1 and _trust("khalil") == 1 and Game.flag("camp3_eleanor") and Game.flag("rapport_eleanor_0")
		and not Game.flag("rapport_eleanor_1"), "camp, the first night: small talk only (rung 0 of their ladders)")
	# The ladder (tools/dialogue/rapport.py): one rung a stop; the personal one needs 3 talks and trust 2.
	r = await _talk("camp_eleanor", ["Ask her why"])
	_check(Game.flag("heard_forgotten_king") and int(Game.companion("eleanor").get("talks", 0)) == 2, "next stop: the work (the forgotten king)")
	r = await _talk("camp_eleanor", ["Say it's a payday"])
	_check(Game.flag("rapport_eleanor_2") and _trust("eleanor") == 1, "then her opinion (trust %d)" % _trust("eleanor"))
	r = await _talk("camp_eleanor", [])
	_check(not Game.flag("rapport_eleanor_3") and not Game.flag("promised_eleanor_publish"), "trust 1: nothing personal yet")
	Game.apply([{"stat": ["eleanor", "trust", 1]}])
	r = await _talk("camp_eleanor", ["Promise her"])
	_check(Game.flag("rapport_eleanor_3") and Game.flag("promised_eleanor_publish"), "trust 2, three talks on: her name on the work")

	# The race: Whitfield's wager on the road, Youssef's shortcut works with his trust...
	_fresh(["youssef"])
	Game.set_flag("race_step", 4)
	Game.apply([{"stat": ["youssef", "trust", 1]}])
	r = await _talk("act3_race", ["Accept", "Trust him"])
	_check(Game.flag("wager_accepted") and int(Game.flag("race_step")) == 3, "race: wager on the road, shortcut wins (step 3)")
	# ... and without it.
	_fresh(["youssef"])
	Game.set_flag("race_step", 4)
	Game.set_flag("wager_offered")
	r = await _talk("act3_race", ["Trust him"])
	_check(int(Game.flag("race_step")) == 5 and not r.speakers.has("whitfield"), "race: the shortcut fails without his trust (step 5)")


func _fresh(party: Array) -> void:
	Game.reset()
	for id in party:
		Game.apply([{"recruit": id}])


func _trust(id: String) -> int:
	return int(Game.companion(id).trust)


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
