extends Node
## Death-and-retry sweep: one set piece per run (--piece=<id>). Starts the piece's scene with its own
## test flow (the act's --auto and friends, plus --skill-bot so the acts don't instakill), waits for
## the fight, lets it run 4 s, then (as playtest_shots --die-at does) clears the act's test args so it
## acts as for a player, spoils the try (+£777, a flag, empty guns), kills the player and presses a
## real Enter: the act's own retry runs (Checkpoint.retry or SaveRoute.resume). Twice: the second
## retry catches what only goes wrong the second time. On each new start it checks: the same scene;
## the player alive at full health; ammo, money and Game (flags, party, countdowns, inventory,
## transport) back to the checkpoint's (the state on the scene's first entry, or the last save for
## acts that load it); Gunman's alliances back; nothing left on the root by the failed try (toasts,
## slabs, rubble); and once the fight is on again: no more enemies than the first time (no
## duplicates) and the same companions, standing. Prints "RESULT retry <piece> ok|FAIL <why>".
##   godot --headless --path . res://tests/retry_test.tscn -- --list        (PIECE <id> <args>)
##   for a in "$(... --list | grep ^PIECE | cut -d' ' -f3-)" ...; one Godot at a time:
##   godot --headless --path . --fixed-fps 60 res://tests/retry_test.tscn -- <args from the PIECE line>

const RUN := 4.0          # s of fight before the death
const START_LIMIT := 420.0  # s to wait for the fight to start
const TRIES := 3          # the first try and two retries
const KEYS := ["money", "flags", "companions", "countdowns", "inventory", "transport", "day"]

## Nodes that live on the root for good, made once (Subtitles' line, Hints' pump): never a leftover.
const KEEPERS := ["Subtitles", "HintsPump"]

## Every set piece with a death in it. scene, its args, how to tell the fight's on (as in
## tests/difficulty_test; prop:<name> = the act's var is set;
## step:<NAME> = the act's step), setup: positioning for fights the act's own test flow doesn't reach,
## retry: "checkpoint" (Checkpoint.take on entry) or "save" (SaveRoute.resume: the last save);
## mid: the checkpoint is taken mid-scene (retries are compared with each other, not the first entry);
## saved: the save the game would have made before the scene (Act 7's fight comes before its first).
const PIECES := {
	"act1_brawl": {"scene": "res://act1.tscn", "args": ["--auto"], "start": "brawlers", "retry": "save"},
	"act1_armed": {"scene": "res://act1.tscn", "args": ["--auto"], "start": "gunmen", "retry": "save"},
	"act2_street": {"scene": "res://act2.tscn", "args": [], "setup": "_street", "start": "gunmen", "retry": "save"},
	"act2_guards": {"scene": "res://act2.tscn", "args": [], "setup": "_guards", "start": "brawlers", "retry": "save"},
	"act3_desert": {"scene": "res://act3_desert.tscn", "args": ["--auto", "--plan=fight"], "start": "gunmen", "retry": "checkpoint"},
	"act3_coast": {"scene": "res://act3_coast.tscn", "args": ["--auto", "--plan=fight"], "start": "gunmen", "retry": "checkpoint"},
	"act3_riverboat": {"scene": "res://act3_riverboat.tscn", "args": ["--auto"], "start": "gunmen", "retry": "checkpoint"},
	"act4_raid": {"scene": "res://act4.tscn", "args": ["--auto", "--choice=barricade"], "recruit": ["eleanor", "mahmoud"],
		"start": "gunmen", "retry": "save"},
	"act5_escape": {"scene": "res://act5.tscn", "args": ["--auto"], "start": "guardian", "retry": "save"},
	"act6_camp": {"scene": "res://act6.tscn", "args": ["--auto", "--plan=hold"], "start": "mummies", "retry": "save"},
	"act7_thieves": {"scene": "res://act7.tscn", "args": ["--auto", "--plan=fight"], "recruit": ["mahmoud", "khalil"],
		"start": "gunmen", "retry": "save", "saved": {"place": "act6_end", "act": 7, "money": 200,
		"flags": {"act6_started": true, "act6_done": true, "thieves_americans": true, "return_route": "coast"},
		"countdowns": {"thieves": 4, "mummy": 6}}},
	"act8_boat": {"scene": "res://act8_boat.tscn", "args": ["--auto"], "start": "mummies", "retry": "checkpoint"},
	"act8_temple": {"scene": "res://act8_temple.tscn", "args": ["--auto"], "start": "mummies", "retry": "checkpoint"},
	"act8_chase": {"scene": "res://act8_chase.tscn", "args": ["--auto", "--gunner"], "start": "chariots", "retry": "checkpoint"},
	"act8_flight": {"scene": "res://act8_flight.tscn", "args": ["--auto"], "start": "prop:_storm", "retry": "checkpoint"},
	"act9_surface": {"scene": "res://act9.tscn", "args": ["--auto"], "start": "event:act9_surface_fight", "retry": "checkpoint"},
	"act9_ritual": {"scene": "res://act9.tscn", "args": ["--auto"], "start": "step:RITUAL", "retry": "checkpoint",
		"mid": true},
}


func _ready() -> void:
	get_window().set_flag(Window.FLAG_NO_FOCUS, true)
	var args := TestDriver.parse_args()
	if args.has("list"):
		for id: String in PIECES:
			print("PIECE %s %s" % [id, " ".join(["--piece=" + id, "--save-slot=retry_" + id, "--skill-bot"] + Array(PIECES[id].args))])
		get_tree().quit(0)
		return
	var piece := str(args.get("piece", ""))
	if not PIECES.has(piece):
		print("RESULT retry %s FAIL not a piece (--list)" % piece)
		get_tree().quit(1)
		return
	var spec: Dictionary = PIECES[piece]
	for a: String in spec.args + ["--skill-bot", "--save-slot"]:
		if not a.substr(2).split("=")[0] in args:
			print("RESULT retry %s FAIL run it with the act's args too: %s" % [piece, a])
			get_tree().quit(1)
			return
	# Its own clean save (--save-slot): a save left by another run would be where a "load the last
	# save" goes. Only ever this run's file: the shared test.json is other tests'.
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Checker._save_path()))
	Game.reset()
	for id: String in spec.get("recruit", []):
		Game.apply([{"recruit": id}])
	if spec.has("saved"):
		var sv: Dictionary = spec.saved
		Game.place = sv.place
		Game.act = sv.act
		Game.money = sv.money
		for f: String in sv.flags:
			Game.set_flag(f, sv.flags[f])
		for c: String in sv.countdowns:
			Game.countdowns[c] = sv.countdowns[c]
		Game.save_game()
	var checker := Checker.new()
	checker.piece = piece
	checker.spec = spec
	get_tree().root.add_child.call_deferred(checker)  # outlives the reloads
	get_tree().change_scene_to_file.call_deferred(spec.scene)


class Checker extends Node:
	## This run's last-rest save (Game._slot: --save-slot's name).
	static func _save_path() -> String:
		return Game.SAVE_DIR.path_join(Game._slot("main") + ".json")

	var piece := ""
	var spec := {}
	var _t := 0.0
	var _events := {}
	var _try := 0
	var _first := {}       # the first try: state on entry, ammo, root nodes
	var _first_fight := {}  # the first try: enemies and party when the fight began
	var _expect := {}      # Game as the retry should put it back
	var _last := {}        # the try before's start (a mid-scene checkpoint's retries compare with it)
	var _pre := {}         # Game as the new scene came in (before its _ready: the act's own entry
	                       # may set things again, as on the first try)
	var _scene_id := 0
	var _line := ""         # the subtitle on screen when the player died
	var _soft: Array[String] = []  # failures that don't stop the run (reported with the rest)
	var _lead_in0 := 0.0   # the first try: s from the scene's start to the fight

	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS
		Game.event.connect(func(e: String): _events[e] = _t)
		get_tree().node_added.connect(func(n: Node):
			if _pre.is_empty() and n.get_parent() == get_tree().root and n.scene_file_path == spec.scene:
				_pre = _norm(_game()))
		_run.call_deferred()

	func _process(delta: float) -> void:
		_t += delta

	func _run() -> void:
		var why := ""
		for attempt in TRIES:
			_try = attempt
			why = await _one()
			if why != "":
				break
		if why == "" and not _soft.is_empty():
			why = "; ".join(_soft)
			_try = 0
		var tag := "" if _try == 0 else " (retry %d)" % _try
		print("RESULT retry %s %s" % [piece, "ok" if why == "" else "FAIL" + tag + " " + why])
		get_tree().quit(0 if why == "" else 1)

	## One try: wait for its scene, check its start, start the fight, check it, die and retry.
	func _one() -> String:
		var cs := await _new_scene()
		if cs == null:
			return "no new scene after Enter (still %s)" % _scene_path()
		if cs.scene_file_path != spec.scene:
			return "the retry went to %s, not %s" % [cs.scene_file_path, spec.scene]
		var p := _player(cs)
		for i in 3:
			await get_tree().physics_frame
		var start := {"game": _norm(_game()), "ammo": p.ammo.duplicate(), "root": _root_nodes(cs), "allies": _alliances()}
		if _try == 0:
			_first = start
		else:
			var why := _check_start(cs, p, start)
			if why != "":
				return why
		_last = start
		var from := _t
		if spec.has("setup"):
			await call(spec.setup, cs, p)
		while not _started(cs, p, from):
			if _t - from > START_LIMIT:
				return "the fight never started (%s after %.0f s)" % [spec.start, START_LIMIT]
			if not is_instance_valid(cs) or get_tree().current_scene != cs:
				return "the scene changed before the fight (%s)" % _scene_path()
			if not p.alive:
				return "the player died before the fight started"
			await get_tree().physics_frame
		var lead_in := _t - from
		if _try == 0:
			_lead_in0 = lead_in
		elif _lead_in0 > 30.0 and lead_in > 0.6 * _lead_in0:
			_soft.append("retry %d: %.0f s of the act again before the fight (%.0f s the first time): no checkpoint at the piece"
				% [_try, lead_in, _lead_in0])
		# A second in: an event can come the frame before its enemies are spawned (Act 9's talks).
		await get_tree().create_timer(1.0, true, false, true).timeout
		var fight := {"enemies": _enemies(), "party": _party()}
		if _try == 0:
			_first_fight = fight
		else:
			var why := _check_fight(fight)
			if why != "":
				return why
		await get_tree().create_timer(RUN - 1.0, true, false, true).timeout
		if _try == TRIES - 1:
			return ""
		if not is_instance_valid(cs) or get_tree().current_scene != cs:
			return "the scene changed during the fight (%s)" % _scene_path()
		if spec.retry == "checkpoint":
			_expect = _norm(_pick(Checkpoint._snap))  # as taken: on entry, or later (Act 9's ritual)
		if spec.retry == "save":
			_expect = _saved()
			if _expect.is_empty():
				return "there's no save to load"
		return await _die_and_retry(cs, p)

	func _check_start(cs: Node, p: Player, start: Dictionary) -> String:
		if not p.alive:
			return "the player is dead on the retry"
		if p.health < p.max_health - 0.01:
			return "health %.0f of %.0f on the retry" % [p.health, p.max_health]
		var mid: bool = spec.get("mid", false)  # the checkpoint is mid-scene: the first try's entry isn't it
		if (not mid or _try > 1) and start.ammo != (_last.ammo if mid else _first.ammo):
			return "ammo %s on the retry, %s the try before" % [start.ammo, (_last.ammo if mid else _first.ammo)]
		var g: Dictionary = _pre
		if Game.flag("retry_test_mutation", false):
			return "the failed try's flag is still set"
		for k: String in KEYS:
			if str(g.get(k)) != str(_expect.get(k)):
				return "Game.%s not back to the checkpoint's: %s" % [k, _diff(_expect.get(k), g.get(k))]
		if start.allies.size() > _first.allies.size():
			return "Gunman alliances %s on the retry, %s on the first try" % [start.allies, _first.allies]
		var extra := []
		for k: String in start.root:
			if int(start.root[k]) > int(_first.root.get(k, 0)):
				extra.append(k)
		if not extra.is_empty():
			return "left on the root from the failed try: %s" % [extra]
		if _line != "" and _subtitle() == _line:
			_soft.append("retry %d: the failed try's subtitle is still up (%s)" % [_try, _line])
		if cs.get_tree().paused:
			return "the tree is paused on the retry"
		return ""

	func _check_fight(fight: Dictionary) -> String:
		var n: int = fight.enemies
		var n0: int = _first_fight.enemies
		if n > n0:
			return "%d enemies when the fight began, %d the first time (duplicates?)" % [n, n0]
		if n == 0 and n0 > 0:  # (the ritual's waves come later: none a second in, the first time too)
			return "no enemies when the fight began"
		var party: Dictionary = fight.party
		for id: String in _first_fight.party:
			if not party.has(id):
				return "%s isn't back (party %s, first %s)" % [id, party.keys(), _first_fight.party.keys()]
			if party[id] != "standing":
				return "%s is %s when the fight begins again" % [id, party[id]]
		return ""

	## Spoil the try, die, and press Enter as a player would.
	func _die_and_retry(cs: Node, p: Player) -> String:
		if "args" in cs:
			cs.set("args", {})  # as for a player: under test args the acts skip input and their bots quit on death
		Game.money += 777
		Game.set_flag("retry_test_mutation")
		for i in p.ammo.size():
			p.ammo[i] = 0
		p._dodge_t = 0.0
		p.take_damage(p.max_health * 10.0, p.global_position + Vector3.FORWARD)
		if p.alive:
			return "the player didn't die (vehicle? invulnerable?)"
		await get_tree().create_timer(1.5, true, false, true).timeout
		_line = _subtitle()
		_pre = {}
		_scene_id = cs.get_instance_id()
		for pressed: bool in [true, false]:
			var e := InputEventKey.new()
			e.keycode = KEY_ENTER
			e.physical_keycode = KEY_ENTER
			e.pressed = pressed
			Input.parse_input_event(e)
			var a := InputEventAction.new()
			a.action = "ui_accept"
			a.pressed = pressed
			Input.parse_input_event(a)
		return ""

	## The next scene to come in (a different instance from the last try's), with its player.
	func _new_scene() -> Node:
		var t0 := _t
		while _t - t0 < 15.0:
			var cs := get_tree().current_scene
			if cs != null and cs.get_instance_id() != _scene_id and cs.is_node_ready() and _player(cs) != null:
				_scene_id = cs.get_instance_id()
				return cs
			await get_tree().process_frame
		return null

	func _started(cs: Node, p: Player, from: float) -> bool:
		var what: String = spec.start
		if what.begins_with("event:"):
			return float(_events.get(what.substr(6), -1.0)) >= from
		if what.begins_with("prop:"):  # the act's own state (the flight's storm wall)
			return cs.get(what.substr(5)) != null
		if what.begins_with("step:"):  # the act's Step (a resume at Act 9's altar skips the talk's event)
			var steps: Variant = cs.get_script().get_script_constant_map().get("Step")
			return steps is Dictionary and cs.get("step") == (steps as Dictionary).get(what.substr(5))
		match what:
			"brawlers":
				return not get_tree().get_nodes_in_group("brawlers").is_empty()
			"guardian":
				for g in cs.find_children("*", "Guardian", true, false):
					if (g as Guardian).state != Guardian.State.DORMANT:
						return true
			"gunmen":
				for n in get_tree().get_nodes_in_group("gunmen"):
					var g := n as Gunman
					if g and g.is_active() and not Gunman.allied(g.team, Gunman.PARTY):
						return true
			"mummies":
				for n in get_tree().get_nodes_in_group("mummies"):
					var m := n as Mummy
					if m and not (m.state in [Mummy.State.DORMANT, Mummy.State.RISING, Mummy.State.DEAD]):
						return true
			"chariots":
				for n in get_tree().get_nodes_in_group("chariots"):
					if n.get("alive"):
						return true
		return false

	## Every enemy in the scene, whatever it's doing (dormant ones too: a duplicate is a duplicate).
	func _enemies() -> int:
		var n := 0
		for g in get_tree().get_nodes_in_group("gunmen"):
			if g is Gunman and not Gunman.allied((g as Gunman).team, Gunman.PARTY) and (g as Gunman).alive:
				n += 1
		for m in get_tree().get_nodes_in_group("mummies"):
			if m is Mummy and (m as Mummy).state != Mummy.State.DEAD:
				n += 1
		for c in get_tree().get_nodes_in_group("chariots"):
			if c.get("alive"):
				n += 1
		n += get_tree().get_nodes_in_group("brawlers").size()
		n += get_tree().current_scene.find_children("*", "Guardian", true, false).size()
		return n

	## The companions in the scene: id -> "standing" / "down" / "dead".
	func _party() -> Dictionary:
		var out := {}
		for n in get_tree().get_nodes_in_group("party"):
			if not n is Gunman:
				continue
			var g := n as Gunman
			var id := g.companion_id if g.companion_id != "" else str(g.name)
			out[id] = "dead" if not g.alive else ("down" if g.downed else "standing")
		return out

	func _game() -> Dictionary:
		var d := Game.to_dict()
		var out := {}
		for k: String in KEYS:
			out[k] = d.get(k)
		return out

	## The last save as it'd load (the test slot: there are args).
	func _saved() -> Dictionary:
		var path := _save_path()
		if not FileAccess.file_exists(path):
			return {}
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not d is Dictionary:
			return {}
		return _norm(_pick(d as Dictionary))

	func _pick(d: Dictionary) -> Dictionary:
		var out := {}
		for k: String in KEYS:
			out[k] = d.get(k)
		return out

	## Through JSON, so a save's floats and the live ints compare. Tutorial hints (hint_*) are left
	## out: one queued in the failed try can show on the retry, and what you've been told stays told.
	func _norm(d: Dictionary) -> Dictionary:
		var v: Variant = JSON.parse_string(JSON.stringify(d))
		if not v is Dictionary:
			return {}
		var flags: Variant = (v as Dictionary).get("flags")
		if flags is Dictionary:
			for k: String in (flags as Dictionary).keys():
				if k.begins_with("hint_"):
					(flags as Dictionary).erase(k)
		return v

	func _diff(a: Variant, b: Variant) -> String:
		if a is Dictionary and b is Dictionary:
			var out := []
			for k in a:
				if not (b as Dictionary).has(k):
					out.append("-%s" % k)
				elif str(a[k]) != str(b[k]):
					out.append("%s %s->%s" % [k, a[k], b[k]])
			for k in b:
				if not (a as Dictionary).has(k):
					out.append("+%s=%s" % [k, b[k]])
			return ", ".join(out)
		return "%s -> %s" % [a, b]

	## What's on the root besides the scene and this checker: script or class -> count. The one
	## subtitle line (Subtitles.current) lives there for good; _subtitle() checks what it shows.
	func _root_nodes(cs: Node) -> Dictionary:
		var out := {}
		for n in get_tree().root.get_children():
			var k := str(n.name).trim_prefix("@").get_slice("@", 0).rstrip("0123456789")
			if n == cs or n == self or k in KEEPERS or _is_subtitles(n):
				continue
			out[k] = int(out.get(k, 0)) + 1
		return out

	## The subtitle line showing now ("" if none).
	func _subtitle() -> String:
		for n in get_tree().root.get_children():
			var l: Variant = n.get("_label") if _is_subtitles(n) else null
			if l is RichTextLabel and (l as RichTextLabel).visible and (l as RichTextLabel).modulate.a > 0.05:
				return (l as RichTextLabel).get_parsed_text()
		return ""

	func _is_subtitles(n: Node) -> bool:
		var s: Script = n.get_script()
		return s != null and s.resource_path.ends_with("subtitles.gd")

	## The team pairs Gunman.allied() says are allies now (asked, not read: a stale set clears itself).
	func _alliances() -> Array:
		var out := []
		for k: String in Gunman._allies.keys():
			var ab := k.split("|")
			if ab.size() == 2 and Gunman.allied(ab[0], ab[1]):
				out.append(k)
		return out

	func _player(cs: Node) -> Player:
		var p: Variant = cs.get("player")
		if p is Player:
			return p
		for n in cs.find_children("*", "", true, false):
			if n is Player:
				return n
		return null

	func _scene_path() -> String:
		var cs := get_tree().current_scene
		return cs.scene_file_path if cs else "none"

	# ------------------------------------------------ setups (as tests/difficulty_test's)

	## Act 2's fights aren't in its test flow: stand where the tests do and raise the talk's event.
	func _street(_cs: Node, p: Player) -> void:
		await get_tree().create_timer(3.5).timeout
		p.global_position = Vector3(29.6, 0, 70.7)  # behind StreetFight's upturned table
		p.yaw = PI
		for i in 3:
			await get_tree().physics_frame
		Game.apply([{"event": "fight_bounty_hunters"}])

	func _guards(_cs: Node, p: Player) -> void:
		await get_tree().create_timer(3.5).timeout
		p.global_position = Vector3(92, 0, 31.5)  # before the museum doors
		p.yaw = 0.0
		for i in 3:
			await get_tree().physics_frame
		Game.apply([{"event": "fight_museum_guards"}])

