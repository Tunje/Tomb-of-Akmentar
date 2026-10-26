extends Node
## The whole campaign in one process: Acts 1 to 9 with each act's --auto bot, chained the way the
## game chains them, with NO Game.reset between acts, and a check that what each act needs from the
## earlier ones actually arrives.
##   godot --headless --path . res://tests/campaign_test.tscn -- --auto [--act-seconds=900]
## A Runner node on the root outlives the scene changes. It watches each act:
## - Game.place turning "actN_end" (every act sets it as it saves at its end): the act is done; the
##   runner snapshots Game and changes to act N+1 itself, before the act's own --auto quit fires;
## - a set piece (act3_desert, act8_temple, ...) emitting `finished`: on to its `next_scene`, as Enter
##   does in the game;
## - an act taking longer than --act-seconds: FAIL, and on to the next act anyway.
## Then it prints a table (act, PASS/FAIL, seconds), the broken hand-offs (what an act needed and
## didn't get, whose file it is) and the flags each act injected itself (quickstarts that hide a
## broken hand-off). Exits 0 when every act passed and no hand-off broke.
##
## HOW TO RUN IT (for Simon)
##   From the project folder, in a terminal (Git Bash or PowerShell), with the console build of Godot:
##     "C:\Users\simon\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe" ^
##       --headless --path . res://tests/campaign_test.tscn -- --auto > campaign.txt
##   (all on one line; it needs no window, so it's fine to run while playing). A green run takes about
##   6-10 minutes (a stuck act waits out --act-seconds); its saves go to the test slot, never yours.
##   Then look at the end of campaign.txt, or just the lines starting with CAMPAIGN:
##     CAMPAIGN act | result | seconds | note      one row per act, PASS or FAIL (and why)
##     CAMPAIGN broken hand-offs: N                 what an act needed from an earlier one and
##                                                  didn't get, with whose file it is [in brackets]
##     CAMPAIGN start-up injections: N              an act overwriting what it was handed
##     CAMPAIGN album {...}                          who got which ending card
##     RESULT campaign PASS / FAIL                  the verdict
##   --act-seconds=N gives each act longer (default 900) before it counts as stuck.
##   Each act's bot plays it on its own terms, so a run isn't always the same: a companion can die
##   in one run and live in the next. Run it twice before believing a single failure.

const ACTS := ["res://act1.tscn", "res://act2.tscn", "res://act3.tscn", "res://act4.tscn", "res://act5.tscn",
	"res://act6.tscn", "res://act7.tscn", "res://act8.tscn", "res://act9.tscn"]
## Whose file each act's flow is (for routing what breaks).
const OWNER := {1: "act1.gd (-99)", 2: "act2.gd (-99)", 3: "act3.gd (-99) / act3_desert.gd (-2d)", 4: "act4.gd (-99)",
	5: "act5.gd (-99)", 6: "act6.gd (-99)", 7: "act7.gd (-99)", 8: "act8.gd (-99)", 9: "act9.gd (-f9)"}


class Runner extends Node:
	var act := 0                  # 1..9, the act running now
	var act_seconds := 900.0
	var t := 0.0                  # in this act
	var total := 0.0
	var results := {}             # act -> {"ok", "secs", "end_place", "note"}
	var handoff := {}             # act -> the Game snapshot when it ended (what the next act gets)
	var started := {}             # act -> the snapshot right after its scene was ready
	var problems: Array[String] = []
	var injected: Array[String] = []
	var _scene: Node
	var _changing := false
	var _hooked := {}

	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--act-seconds="):
				act_seconds = float(a.substr(14))
		_go(1)

	func _go(n: int) -> void:
		if n > ACTS.size():
			_finish()
			return
		act = n
		t = 0.0
		_changing = true
		print("CAMPAIGN start act %d (day %d, money %d, party %s)" % [n, Game.day, Game.money, Game.party()])
		get_tree().change_scene_to_file.call_deferred(ACTS[n - 1])

	func _process(delta: float) -> void:
		t += delta
		total += delta
		var cur := get_tree().current_scene
		if cur != _scene and cur != null:
			_scene = cur
			_changing = false
			_on_scene(cur)
		if _changing:
			return
		_unstick_talk(delta)
		var place := str(Game.place)
		if place == "act%d_end" % act:
			_act_done(true, "")
		elif t > act_seconds:
			_act_done(false, "timed out after %.0f s in %s (step place=%s)" % [t, _scene.scene_file_path if _scene else "?", place])

	## An act's bot that leaves a talk's wheel waiting (no auto picker): after 3 s the runner picks the
	## first choice, as a player would, and logs it as a finding against that act.
	var _wheel_t := 0.0
	var _stuck_logged := {}

	func _unstick_talk(delta: float) -> void:
		var c := Conversation.current
		if c == null or c.state != Conversation.State.CHOICES:
			_wheel_t = 0.0
			return
		_wheel_t += delta
		if _wheel_t < 3.0:
			return
		_wheel_t = 0.0
		var key := "%d:%s" % [act, c.id]
		if not _stuck_logged.has(key):
			_stuck_logged[key] = true
			problems.append("Act %d: under --auto the talk %s waits on its wheel with no bot to choose (the runner picked for it)  [%s]" % [act, c.id, OWNER.get(act, "?")])
		print("CAMPAIGN picked '%s' in %s (act %d)" % [c.visible_choices[0].label, c.id, act])
		c.choose(0)

	## A new scene: hook a set piece's `finished`; snapshot an act's start.
	func _on_scene(s: Node) -> void:
		print("CAMPAIGN scene %s (act %d, t=%.0f)" % [s.scene_file_path, act, t])
		if s.has_signal("finished") and not _hooked.has(s):
			_hooked[s] = true
			s.connect("finished", func(_r: Variant = null) -> void: _set_piece_done(s))
		if s.scene_file_path == ACTS[act - 1] and not started.has(act):
			started[act] = _snapshot()
			_injected_check(act)

	func _set_piece_done(s: Node) -> void:
		var next := ""
		if "next_scene" in s:
			next = str(s.get("next_scene"))
		elif s.get_script() and "next_scene" in s.get_script():
			next = str(s.get_script().get("next_scene"))
		print("CAMPAIGN set piece %s finished -> %s" % [s.scene_file_path, next])
		if next != "":
			_changing = true
			await get_tree().create_timer(0.2).timeout
			get_tree().change_scene_to_file(next)

	func _act_done(ok: bool, note: String) -> void:
		results[act] = {"ok": ok, "secs": t, "note": note, "place": str(Game.place)}
		handoff[act] = _snapshot()
		print("CAMPAIGN act %d %s in %.0f s %s" % [act, "done" if ok else "FAILED", t, note])
		_check_after(act)
		if act == ACTS.size():
			_finish()
		else:
			_go(act + 1)

	func _snapshot() -> Dictionary:
		return {"flags": Game.flags.duplicate(true), "money": Game.money, "day": Game.day, "party": Game.party().duplicate(),
			"countdowns": Game.countdowns.duplicate(), "transport": Game.transport.duplicate(true)}

	# ------------------------------------------------------------ the checks

	func _f(snap: Dictionary, name: String) -> Variant:
		return (snap.get("flags", {}) as Dictionary).get(name, null)

	## A flag as a truth value (missing = false; bool(null) would be an error).
	func _b(snap: Dictionary, name: String) -> bool:
		var v: Variant = _f(snap, name)
		return true if v else false

	func _need(n: int, ok: bool, what: String) -> void:
		if not ok:
			problems.append("after Act %d: %s  [%s]" % [n, what, OWNER.get(n, "?")])

	## What act n must leave for the acts after it.
	func _check_after(n: int) -> void:
		var s: Dictionary = handoff[n]
		match n:
			1:
				_need(n, _b(s, "act1_offer_accepted"), "act1_offer_accepted not set (the offer)")
				_need(n, _b(s, "act1_gunfight_won") or _b(s, "act1_gunfight_avoided"),
					"neither act1_gunfight_won nor act1_gunfight_avoided (Isabelle's proof in Act 2)")
				_need(n, int(s.money) > 0, "no money after the offer (%d)" % int(s.money))
			2:
				_need(n, not (s.party as Array).is_empty(), "nobody recruited")
				_need(n, _b(s, "hired_eleanor") or _b(s, "hired_pembroke") or _b(s, "hired_hassan"),
					"no Egyptologist hired (the Hassan fallback should guarantee one)")
				for id in s.party:
					_need(n, _b(s, "hired_" + str(id)), "%s is in the party without hired_%s (the album will call them never-joined)" % [id, id])
				if handoff.has(1):
					_need(n, int(s.money) <= int(handoff[1].money) + 300, "money grew past Act 1's + the 300 fund (%d -> %d)" % [int(handoff[1].money), int(s.money)])
			3:
				_need(n, int(_f(s, "race_step") if _f(s, "race_step") != null else 0) in [3, 4, 5], "race_step not 3/4/5 (%s)" % _f(s, "race_step"))
				_need(n, _f(s, "route_act3_route") != null, "route_act3_route not set (the board)")
				if handoff.has(2):
					for id in s.party:
						_need(n, id in handoff[2].party, "%s in the party after Act 3 but not hired in Act 2" % id)
			4:
				_need(n, _f(s, "night_choice") != null, "night_choice not set")
				_need(n, _f(s, "ally") != null, "ally not set (Act 5's ally / thieves)")
				var claims := 0
				for k in s.flags:
					if str(k).begins_with("claimed_") and str(k).count("_") == 1:
						claims += 1
				_need(n, claims > 0, "no claimed_<site> flags (the draft)")
				if handoff.has(3):
					_need(n, _f(s, "race_step") == _f(handoff[3], "race_step"), "race_step changed in Act 4 (%s -> %s)" % [_f(handoff[3], "race_step"), _f(s, "race_step")])
			5:
				var th := str(_f(s, "thieves") if _f(s, "thieves") != null else "")
				_need(n, th in ["americans", "germans", "italians"], "thieves not set (%s)" % th)
				_need(n, th == "" or _b(s, "thieves_" + th), "thieves_%s plain flag not set" % th)
				_need(n, str(_f(s, "new_objective")) == "recover_amulet", "new_objective != recover_amulet (%s): the revelation talk didn't run" % _f(s, "new_objective"))
				# The escape under the bot shouldn't cost companions (it's god mode for the player, and
				# the companions run with him); a loss here usually means one was cut off by a slab.
				var lost: Array = _f(s, "act5_casualties") if _f(s, "act5_casualties") is Array else []
				_need(n, lost.is_empty(), "companions lost in the escape under the bot: %s (party before %s, after %s)" % [lost,
					handoff[4].party if handoff.has(4) else "?", s.party])
				if handoff.has(4) and str(_f(handoff[4], "ally")) != "":
					_need(n, th == str(_f(handoff[4], "ally")), "thieves (%s) != Act 4's ally (%s)" % [th, _f(handoff[4], "ally")])
			6:
				_need(n, s.countdowns.has("thieves") and s.countdowns.has("mummy"), "countdowns missing (%s)" % [s.countdowns])
				_need(n, int(s.countdowns.get("thieves", 0)) > 0, "thieves countdown already 0 on arrival (%s)" % [s.countdowns])
				_need(n, _f(s, "return_route") != null, "return_route not set (the board)")
			7:
				_need(n, _b(s, "artifacts_recovered") or _b(s, "thieves_escaped"), "neither artifacts_recovered nor thieves_escaped")
				_need(n, not _b(s, "artifacts_recovered") or str(_f(s, "new_objective")) == "return_artifacts", "recovered but new_objective != return_artifacts (act7_recovered didn't run)")
				if handoff.has(6):
					_need(n, int(s.countdowns.get("mummy", 99)) <= int(handoff[6].countdowns.get("mummy", 0)), "mummy countdown went up in Act 7 (%s -> %s)" % [handoff[6].countdowns, s.countdowns])
			8:
				_need(n, _f(s, "act8_route") != null, "act8_route not set (the board)")
				_need(n, str(_f(s, "act8_choice")) == "descend" or _b(s, "player_sacrificed"), "neither act8_choice=descend nor player_sacrificed")
			9:
				_need(n, _b(s, "barrier_restored") or _b(s, "ritual_failed"), "neither barrier_restored nor ritual_failed")
				var cards := EpilogueShow.pick_cards("akmentar")
				var v := {}
				for c: Dictionary in cards:
					v[c.who] = c.variant
				print("CAMPAIGN album %s" % [v])
				for id in ["eleanor", "pembroke", "hassan", "hargreaves", "idris", "isabelle", "saleh", "youssef", "farid", "mahmoud", "khalil", "naguib"]:
					if _b(s, "hired_" + id):
						_need(n, str(v.get(id, "")) != "never", "%s was hired but the album says never joined" % id)
				_need(n, (_b(s, "barrier_restored") and v.get("keepers", "") == "restored") or (not _b(s, "barrier_restored") and v.get("keepers", "") == "broken"),
					"the Keepers' card (%s) disagrees with barrier_restored" % v.get("keepers", ""))

	## Did act n's own start-up paper over what it was handed? (quickstarts: test parties, thieves)
	func _injected_check(n: int) -> void:
		if n <= 1 or not handoff.has(n - 1):
			return
		var before: Dictionary = handoff[n - 1]
		var now: Dictionary = started[n]
		for id in now.party:
			if not id in before.party:
				injected.append("Act %d added %s to the party at its start (it wasn't in Act %d's party %s)  [%s]" % [n, id, n - 1, before.party, OWNER.get(n, "?")])
		for k in ["thieves_americans", "thieves_germans", "thieves_italians", "ally", "race_step", "artifacts_recovered", "act8_choice"]:
			if now.flags.get(k, null) != before.flags.get(k, null):
				injected.append("Act %d changed %s at its start (%s -> %s)  [%s]" % [n, k, before.flags.get(k, null), now.flags.get(k, null), OWNER.get(n, "?")])
		for k in ["thieves", "mummy"]:
			if n == 7 and int(now.countdowns.get(k, -1)) != int(before.countdowns.get(k, -1)):
				injected.append("Act 7 changed the %s countdown at its start (%s -> %s)  [%s]" % [k, before.countdowns.get(k, null), now.countdowns.get(k, null), OWNER.get(n, "?")])

	func _finish() -> void:
		set_process(false)
		var failed := 0
		print("CAMPAIGN ================================================================")
		print("CAMPAIGN act | result | seconds | note")
		for n in range(1, ACTS.size() + 1):
			var r: Dictionary = results.get(n, {"ok": false, "secs": 0.0, "note": "never reached"})
			if not r.ok:
				failed += 1
			print("CAMPAIGN %3d | %s | %6.0f | %s" % [n, "PASS" if r.ok else "FAIL", float(r.secs), r.note])
		print("CAMPAIGN broken hand-offs: %d" % problems.size())
		for p in problems:
			print("CAMPAIGN   " + p)
		print("CAMPAIGN start-up injections: %d" % injected.size())
		for p in injected:
			print("CAMPAIGN   " + p)
		var ok := failed == 0 and problems.is_empty()
		print("RESULT campaign %s acts_failed=%d handoffs_broken=%d injected=%d total=%.0f s" % ["PASS" if ok else "FAIL", failed,
			problems.size(), injected.size(), total])
		get_tree().quit(0 if ok else 1)


func _ready() -> void:
	get_window().set_flag(Window.FLAG_NO_FOCUS, true)
	if DisplayServer.get_name() == "headless":
		get_window().size = Vector2i(1600, 900)  # the boards lay out from the screen size
	Game.reset()
	var r := Runner.new()
	r.name = "CampaignRunner"
	get_tree().root.add_child.call_deferred(r)
