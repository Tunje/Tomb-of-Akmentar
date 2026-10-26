extends Node3D
## Act 4 talk test: every path of act4_whitfield, act4_adler, act4_night_choice and act4_dawn,
## driven through the real Conversation (lines skipped, choices picked by label), checking the
## flags and stats each one sets. Takes two screenshots (the night choice wheel, the dawn offer).
## Prints RESULT lines; exits 0 when every check passed. Args after "--":
##   --shot-dir=C:/path   where PNGs go (default user://act4_talk_shots)
## Never takes focus or captures the mouse (Simon plays while we test).

class FakePlayer extends Node3D:
	var controls_enabled := true
	var yaw := 0.0

const IDS := ["act4_whitfield", "act4_adler", "act4_night_choice", "act4_dawn"]

var _dir := "user://act4_talk_shots"
var _player: FakePlayer
var _npc: Node3D
var _fails := 0
var _shoot := ""   # take a screenshot at the next wheel


func _ready() -> void:
	get_window().set_flag(Window.FLAG_NO_FOCUS, true)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot-dir="):
			_dir = a.substr(11)
	DirAccess.make_dir_recursive_absolute(_dir)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.08, 0.09, 0.14)  # night
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.45, 0.5, 0.65)
	add_child(env)
	var fire := OmniLight3D.new()
	fire.light_color = Color(1, 0.6, 0.3)
	fire.light_energy = 2.5
	fire.omni_range = 8.0
	fire.position = Vector3(0.6, 0.8, -0.2)
	add_child(fire)
	var ground := MeshInstance3D.new()
	ground.mesh = PlaneMesh.new()
	ground.mesh.size = Vector2(30, 30)
	add_child(ground)
	_player = FakePlayer.new()
	add_child(_player)
	_capsule(_player, Color(0.62, 0.5, 0.32))
	_player.position = Vector3(0.5, 0, 1.0)
	_npc = Node3D.new()
	add_child(_npc)
	_capsule(_npc, Color(0.3, 0.32, 0.4))
	_npc.position = Vector3(-0.5, 0, -0.9)
	var cam := Camera3D.new()
	add_child(cam)
	cam.current = true
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
	for id in IDS:
		var probs := Conversation.validate(Conversation.load_data(id))
		_check(probs.is_empty(), "%s validates (%s)" % [id, "; ".join(probs)])

	# ---- Whitfield
	_fresh({"wager_accepted": true, "claimed_anubis_americans": true})
	var r := await _talk("act4_whitfield", ["Congratulate him", "Leave"])
	_check(_said(r, "Five hundred dollars says"), "Whitfield brings up the wager when wager_accepted")
	_check(_stat("whitfield") == 1 and Game.flag("hint_anubis") and not Game.flag("clue_anubis"), "congratulate: trust +1, hint_anubis (no clue)")
	_check(Game.flag("met_whitfield") and r.end == "end", "met_whitfield set, ends")
	r = await _talk("act4_whitfield", ["Leave"])
	_check(_said(r, "Back again?") and not r.labels.has("Congratulate him"), "second visit: 'Back again', the standing choice is used up")
	_fresh({"claimed_scarabs_americans": true})
	r = await _talk("act4_whitfield", ["Needle him", "Ask about his men", "Leave"])
	_check(_said(r, "Shame you wouldn't take my bet"), "no wager: he regrets it")
	_check(_stat("whitfield") == -1 and not Game.flag("hint_scarabs"), "needle: trust -1, no hint")
	_fresh({"claimed_storeroom_americans": true})
	await _talk("act4_whitfield", ["Congratulate him", "Leave"])
	_check(Game.flag("hint_storeroom") and not Game.flag("hint_anubis"), "hint follows what they claimed (storeroom)")
	_fresh({})
	r = await _talk("act4_whitfield", ["Congratulate him", "Leave"])
	_check(_said(r, "keep my cards close") and not _any_hint(), "nothing of theirs claimed: no hint")

	# ---- Adler
	_fresh({"claimed_horus_germans": true, "claimed_hieroglyphs_germans": true})
	r = await _talk("act4_adler", ["Offer to compare notes", "Leave"])
	_check(_stat("adler") == 1 and Game.flag("hint_horus") and not Game.flag("hint_hieroglyphs"), "compare notes: trust +1, hint_horus (their first priority)")
	_fresh({"claimed_obelisk_germans": true})
	await _talk("act4_adler", ["Offer to compare notes", "Leave"])
	_check(Game.flag("hint_obelisk"), "hint follows what they claimed (obelisk)")
	_fresh({"claimed_horus_germans": true})
	r = await _talk("act4_adler", ["Ask about Krüger", "Ask about treasure", "Leave"])
	_check(_stat("adler") == -1 and not Game.flag("hint_horus") and _said(r, "This is not a vault"), "treasure: trust -1, no hint")

	# ---- Night choice: with Eleanor, recognising the bandits; each choice.
	for pick: Array in [["Barricade the camp", "barricade"], ["Help the Americans", "americans"], ["Help the Germans", "germans"]]:
		_fresh({"recognized_bandits": true})
		Game.apply([{"recruit": "eleanor"}])
		if pick[1] == "americans":
			_shoot = "act4_night_choice_wheel.png"
		r = await _talk("act4_night_choice", [pick[0]])
		_check(r.speakers.has("eleanor") and _said(r, "same men from before"), "night (%s): Eleanor speaks, you recognise the men" % pick[1])
		_check(Game.flag("night_choice") == pick[1] and r.end == "end_" + pick[1], "night: '%s' sets night_choice=%s" % [pick[0], Game.flag("night_choice")])
	_fresh({})
	r = await _talk("act4_night_choice", ["Help the Germans"])
	_check(not r.speakers.has("eleanor") and not _said(r, "same men"), "night alone: only you, no recognition line")
	_check(Game.flag("night_choice") == "germans", "night alone: night_choice=germans")

	# ---- Dawn
	_fresh({"americans_alive": true, "germans_alive": false})
	_shoot = "act4_dawn_offer.png"
	r = await _talk("act4_dawn", ["Shake on it"])
	_check(Game.flag("ally") == "americans" and Game.flag("ally_terms_two_sites") and r.end == "end_americans", "dawn: Whitfield's deal, ally=americans")
	_fresh({"germans_alive": true})
	r = await _talk("act4_dawn", ["Agree"])
	_check(Game.flag("ally") == "germans" and r.speakers.has("adler"), "dawn: Adler's offer, ally=germans")
	_fresh({"germans_alive": true})
	await _talk("act4_dawn", ["Decline"])
	_check(Game.flag("ally", null) == "" and not Game.flag("ally_terms_two_sites"), "dawn: decline, ally empty")
	_fresh({"americans_alive": true, "germans_alive": true})
	r = await _talk("act4_dawn", ["Join the Germans"])
	_check(Game.flag("ally") == "germans" and r.labels.has("Join the Americans") and r.labels.has("Go alone"), "dawn, both alive: you choose (germans)")
	_fresh({})
	Game.apply([{"recruit": "eleanor"}])
	r = await _talk("act4_dawn", [])
	_check(r.speakers.has("eleanor") and _said(r, "Nobody to bury") and Game.flag("ally", null) == "" and r.end == "end_alone", "dawn, nobody left: Eleanor's grim line, ally empty")
	_fresh({})
	r = await _talk("act4_dawn", [])
	_check(not r.speakers.has("eleanor") and _said(r, "we face it alone"), "dawn, nobody left, alone: your line")
	# Names in day summaries.
	_check(DayLog.person("whitfield") == "Charlie Whitfield" and DayLog.person("adler") == "Professor Adler", "people.json names the leaders")

	print("RESULT act4_talk_test %s fails=%d" % ["PASS" if _fails == 0 else "FAIL", _fails])
	await get_tree().create_timer(0.2).timeout
	get_tree().quit(0 if _fails == 0 else 1)


func _fresh(flags: Dictionary) -> void:
	Game.reset()
	DayLog.begin_day()
	for k in flags:
		Game.set_flag(k, flags[k])


## Runs one conversation, skipping lines and picking `picks` in order. Returns
## {end, lines: [[speaker, text]], speakers, labels (every label shown)}.
func _talk(id: String, picks: Array) -> Dictionary:
	var out := {"end": "", "lines": [], "speakers": [], "labels": []}
	var c := Conversation.new()
	add_child(c)
	c.finished.connect(func(e: String): out.end = e if e != "" else "<none>")
	c.line_started.connect(func(s: String, t: String):
		out.lines.append([s, t])
		if not s in out.speakers:
			out.speakers.append(s))
	c.choices_shown.connect(func(l: Array): out.labels.append_array(l))
	c.start(id, _player, _npc)
	var frames := 0
	var todo := picks.duplicate()
	while out.end == "" and frames < 2000:
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
				c.choose(0)
			else:
				c.choose(i)
	print("RESULT %s -> %s via %s" % [id, out.end, " / ".join(out.lines.map(func(l): return l[0]))])
	return out


func _said(r: Dictionary, bit: String) -> bool:
	return r.lines.any(func(l): return bit in str(l[1]))


func _stat(who: String) -> int:
	return int(Game.companions.get(who, {}).get("trust", 0))


func _any_hint() -> bool:
	return Game.flags.keys().any(func(k): return str(k).begins_with("hint_"))


func _check(ok: bool, what: String) -> void:
	print("RESULT %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_fails += 1


func _shot(file: String) -> void:
	await RenderingServer.frame_post_draw
	var p := _dir.path_join(file)
	get_viewport().get_texture().get_image().save_png(p)
	print("RESULT shot %s" % ProjectSettings.globalize_path(p))
