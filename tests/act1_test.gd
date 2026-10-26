extends Node3D
## Act 1 data test: every act1 dialogue validates, and the Act 1 talks run through the real
## Conversation: Freddie's office (the note, the warning), the debt collectors (give Freddie up,
## promise, fight), the brawl's aftermath (Musa's respect), the armed men at Freddie's (Musa, the note, a fight)
## and Karim's offer, a talk only, with Finch paid off from the advance.
## Prints RESULT lines; exits 0 when every check passed.
##   --shot-dir=C:/path   where PNGs go (default user://act1_shots)
## Never takes focus or captures the mouse (Simon plays while we test).

class FakePlayer extends Node3D:
	var controls_enabled := true
	var yaw := 0.0

var _dir := "user://act1_shots"
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
		if f.begins_with("act1_") and f.ends_with(".json"):
			var id := f.get_basename()
			var probs := Conversation.validate(Conversation.load_data(id))
			_check(probs.is_empty(), "%s validates %s" % [id, probs])
	var plan := ActionSpot.load_data("act1_plan")

	_fresh([])
	Game.apply(plan.start)
	var r := await _talk("act1_office", ["Search his desk", "Ask who else came", "Leave"])
	_check(Game.flag("freddie_note") and Game.flag("warned_finch") and Game.flag("clue_freddie_note") and Game.money == 25,
		"office: the note and the warning")
	r = await _talk("act1_debt_collectors", ["Give up Freddie"])
	_check(r.end == "end_talked" and Game.flag("freddie_betrayed"), "collectors: Freddie given up")
	r = await _talk("act1_debt_collectors", ["Promise to pay"])
	_check(r.end == "end_talked" and int(Game.flag("owe_finch", 0)) == 50, "collectors: promised 50")
	r = await _talk("act1_debt_collectors", ["Hit him"])
	_check(r.end == "end_fight" and "fight_debt_collectors" in _events, "collectors: the brawl")
	r = await _talk("act1_after_brawl", ["Help him up"])
	_check(Game.flag("musa_respect") and r.speakers.has("finch"), "after the brawl: Musa helped up")
	r = await _talk("act1_armed_men", [])
	_check(r.end == "end_avoided" and Game.flag("act1_gunfight_avoided") and Game.flag("act1_confrontation_done") and r.speakers.has("musa"),
		"armed men at Freddie's: Musa won't shoot")
	r = await _talk("act1_offer", ["Accept", "Pay Finch off"])
	_check(r.end == "end_accepted" and Game.flag("clue_fragment") and Game.flag("finch_paid") and Game.money == 25
		and r.speakers == ["karim", "player"], "offer: a talk only, accepted, Finch paid (%d)" % Game.money)

	# No friends among the gunmen and no warning: the talk fails and you draw; Karim has heard.
	_fresh([])
	Game.apply(plan.start)
	r = await _talk("act1_armed_men", ["Talk him down", "Draw"])
	_check(r.end == "end_fight" and "fight_armed_men" in _events and not Game.flag("act1_gunfight_avoided"), "armed men: the gunfight")
	Game.set_flag("act1_gunfight_won")
	Game.set_flag("act1_confrontation_done")
	r = await _talk("act1_offer", ["Ask for more up front", "Accept"])
	_check(r.end == "end_accepted" and Game.money == 100 and not r.speakers.has("gunman"), "offer after the gunfight: 75 advance (%d)" % Game.money)
	# The note buys them off too (and gives Freddie away).
	_fresh([])
	Game.set_flag("freddie_note")
	r = await _talk("act1_armed_men", ["Give them the note"])
	_check(r.end == "end_avoided" and Game.flag("freddie_betrayed"), "armed men: Freddie's note sends them to Alexandria")


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
