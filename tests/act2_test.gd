extends Node3D
## Act 2 data test: every act2 dialogue validates, every act2 ActionSpot file loads and names real
## talks, and the main recruitment paths run through the real Conversation with the right money,
## flags and recruits (museum refusal -> Pembroke via the archive, Isabelle's proof and fight,
## Karim's advance, Khalil's half pay, the Hassan fallback), plus the shop buys and an action.
## Prints RESULT lines; exits 0 when every check passed.
##   --shot-dir=C:/path   where PNGs go (default user://act2_shots)
## Never takes focus or captures the mouse (Simon plays while we test).

class FakePlayer extends Node3D:
	var controls_enabled := true
	var yaw := 0.0

var _dir := "user://act2_shots"
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
	# Every file.
	for f in DirAccess.get_files_at("res://dialogue"):
		if f.begins_with("act2_") and f.ends_with(".json"):
			var id := f.get_basename()
			var probs := Conversation.validate(Conversation.load_data(id))
			_check(probs.is_empty(), "%s validates %s" % [id, probs])
	var plan := ActionSpot.load_data("act2_plan")
	for spot_id: String in plan.get("spots", {}):
		var d := ActionSpot.load_data(plan.spots[spot_id])
		_check(not d.get("actions", []).is_empty(), "%s has actions" % plan.spots[spot_id])
		for a: Dictionary in d.get("actions", []):
			if a.has("conversation"):
				_check(FileAccess.file_exists("res://dialogue/%s.json" % a.conversation), "%s talk %s exists" % [spot_id, a.conversation])

	Game.reset()
	Game.apply(plan.start)
	_check(Game.money == 300, "Act 2 starts with 300 (%d)" % Game.money)

	# The museum: a fresh visit offers the archivist and the archive only.
	var museum := ActionSpot.make(self, "act2_museum", Vector3(4, 0, 0))
	await get_tree().process_frame
	var labels: Array = museum.rows().map(func(r: Dictionary) -> String: return r.label)
	_check(labels.size() == 2, "museum, first: %s" % [labels])
	var r := await _talk("act2_museum", ["Ask for an Egyptologist", "Ask about his staff", "Approach Dr. Pembroke",
		"Offer him the job", "Admit you can't afford him"])
	_check(r.end == "end_left" and Game.flag("knows_hassan") and not Game.in_party("pembroke") and Game.money == 300,
		"Pembroke turned down for money, points to Hassan")
	labels = museum.rows().map(func(rr: Dictionary) -> String: return rr.label)
	_check("Find Miss Whitmore in the reading room" in labels and "Find Dr. Pembroke in his office" in labels
		and not "Ask the chief archivist for an Egyptologist" in labels, "museum, after: %s" % [labels])
	r = await _talk("act2_archive", [])
	_check(Game.flag("researched_akmentar") and Game.flag("clue_cairo_archive") and not Game.flag("clue_cairo_first_report"),
		"archive research writes the journal")
	r = await _talk("act2_pembroke", ["Offer him the job", "Show him the archive papers"])
	_check(r.end == "end_recruited" and Game.in_party("pembroke") and Game.money == 250, "Pembroke for 50 with the archive (%d)" % Game.money)

	# Isabelle: money alone won't do; the bounty men will.
	r = await _talk("act2_isabelle", ["Offer her work", "Leave"])
	_check(r.end == "end_left" and not Game.in_party("isabelle"), "Isabelle says come back")
	Game.set_flag("heard_isabelle_trouble")
	r = await _talk("act2_isabelle", ["Offer her work", "Offer to deal with her trouble"])
	_check(r.end == "end_fight" and "fight_bounty_hunters" in _events, "Isabelle's trouble starts the fight")
	Game.set_flag("isabelle_trouble_settled")
	r = await _talk("act2_isabelle", ["Agree"])
	_check(Game.in_party("isabelle") and Game.money == 205 and int(Game.companion("isabelle").trust) == 3,
		"Isabelle joins after the fight (%d, trust %d)" % [Game.money, Game.companion("isabelle").trust])

	# Karim, pressed first: the truth and 50.
	r = await _talk("act2_karim", ["Ask about the first expedition", "Push harder", "Ask for more money"])
	_check(Game.flag("heard_blackwood_silence") and Game.money == 255, "Karim pressed: truth and 50 (%d)" % Game.money)

	# Khalil, half now (Fatima introduces him).
	r = await _talk("act2_khalil", ["Hire the crew", "Half now, half later"])
	_check(Game.in_party("khalil") and int(Game.flag("owe_khalil", 0)) == 12 and Game.money == 242
		and r.speakers.has("fatima"), "Khalil half pay (%d)" % Game.money)

	# The fallback: no Egyptologist hired -> Hassan for free.
	r = await _talk("act2_hassan_fallback", ["Ask what he wants", "Promise"])
	_check(Game.in_party("hassan") and Game.money == 242, "Hassan fallback joins free")

	# Shops: a free buy, then a one-action deal.
	var gun := ActionSpot.make(self, "act2_gunsmith", Vector3(-4, 0, 0))
	await get_tree().process_frame
	var rows := gun.rows()
	var rifle: Dictionary = rows.filter(func(x: Dictionary) -> bool: return x.action.id == "rifle")[0].action
	_check(gun.run(rifle) and int(Game.inventory.get("rifle", 0)) == 1 and Game.money == 217 and Game.actions_left == 3,
		"buy a rifle (free action, %d)" % Game.money)
	_check(gun.rows().all(func(x: Dictionary) -> bool: return x.action.id != "rifle"), "rifle gone (once)")
	var arm: Dictionary = gun.rows().filter(func(x: Dictionary) -> bool: return x.action.id == "arm_party")[0].action
	_check(gun.run(arm) and Game.flag("party_armed") and Game.actions_left == 2 and Game.money == 177,
		"arm the party (1 action, %d)" % Game.money)
	await _shot("act2_gunsmith.png")


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
	await RenderingServer.frame_post_draw
	var p := _dir.path_join(file)
	get_viewport().get_texture().get_image().save_png(p)
	print("RESULT shot %s" % ProjectSettings.globalize_path(p))
