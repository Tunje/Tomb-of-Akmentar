extends Node3D
## Act 5: the awakening of Akmentar (gameplan/act5_build.md).
## DESCEND -> LEVEL2 (investigate) -> ROYAL_DOOR -> TOMB (investigate, interrupted) -> AWAKENING ->
## ESCAPE (run to the stairs) -> REVELATION -> END.
## -f9's data/talk and -bf's Guardian / ScarabSwarm plug in when present (load by path), so the act
## runs end to end without them. Test args after "--": --auto, --ally=americans|germans|none,
## --seconds=N, --shots=..., --shot-dir=...

enum Step { DESCEND, LEVEL2, ROYAL_DOOR, TOMB, AWAKENING, ESCAPE, REVELATION, END }

const GUARDIAN := "res://scripts/guardian.gd"
const SCARABS := "res://scripts/scarabs.gd"
const LEVEL2_SITES := "res://sites/akmentar_below.json"
const TOMB_SITES := "res://sites/royal_tomb.json"
## The slab across the main stairs' neck comes down on its own this long into the escape: slower
## than that and it's one of the side shafts.
const NECK_SLAB_AFTER := 150.0  # five levels up: the neck closes on the slow, not the steady
const WAIT_AT_TOP := 8.0  # how long the survivors at the top wait once someone stops coming
const WAIT_MAX := 150.0   # (those left studying on the deepest level have five to climb on their own)
## The allied expedition (the thieves) running out ahead of you: its leader and two of its people.
const ALLY_TEAMS := {"americans": ["whitfield", "maggie", "callahan"], "germans": ["adler", "kruger", "vogel"]}
## The party in the tomb: whom you leave to study where, and their own runs at the awakening.
const PARTY := preload("res://scripts/acts/act5_party.gd")

var level: AkmentarBelow
var player: Player
var hud: Hud
var step := Step.DESCEND
var args := {}
var companions := {}
var guardian: Node3D
var _t := 0.0
var _shots: Array[float] = []
var _door_spot: Interactable
var _tomb_done := 0
var _ally_npc: Npc
var _rashad: Node3D
var _tomb_spots := {}
var _sleepers: Array[Mummy] = []
var _told_vault := false
var _ally_team := {}  # id -> Gunman, the allied expedition during the escape
var party: Node  # act5_party.gd: who's left studying where, and their runs out
var _builders_out := false  # up the Builders' Way (-f9's): the workmen's stair to the ravine
var _level_spots: Array[SiteSpot] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	child_entered_tree.connect(func(n: Node):
		if n.process_mode == Node.PROCESS_MODE_INHERIT:
			n.process_mode = Node.PROCESS_MODE_PAUSABLE)
	Controls.setup()
	args = TestDriver.parse_args()
	if args.size() > 0:
		get_window().set_flag(Window.FLAG_NO_FOCUS, true)
	if args.has("ally"):
		Game.set_flag("ally", "" if args.ally == "none" else args.ally)
	if str(Game.flag("ally", "")) != "":
		Game.set_flag("ally_is_" + str(Game.flag("ally", "")))  # the talks branch on these
	Game.act = 5
	level = AkmentarBelow.new()
	add_child(level)
	level.builders_stair_used.connect(func(_by: Node) -> void: _builders_out = true)
	level.builders_seal_forced.connect(_seal_forced)
	Warmup.start(self, Warmup.MUMMIES)  # what spawns mid-fight, loaded now (tests/perf_test)
	Ambience.play(self, "tomb")
	player = Player.new()
	add_child(player)
	player.global_position = level.player_spawn
	player.yaw = 0.0  # facing north, into the tomb
	# Her lantern: the maze between the torches is black without it.
	player.add_lantern()
	TombDust.add(self, player)  # motes in the lantern light, grit from the ceiling (-f9)
	hud = Hud.new()
	hud.player = player
	add_child(hud)
	add_child(CountdownBars.new())
	player.hit_confirmed.connect(hud.on_hit)
	player.damaged.connect(hud.on_damaged)
	player.died.connect(func(): hud.show_message("YOU DIED", "Enter  load the last save"))
	for s in str(args.get("shots", "")).split(",", false):
		_shots.append(float(s))
	# A test or menu start brings a crew, but only a fresh one: after a real Act 4 (night_choice) an empty
	# party is a wipe and stays one (-f9's campaign test).
	if args.has("party") or ((args.has("auto") or Game.flag("quickstart_act", false)) and Game.party().is_empty() and not Game.flags.has("night_choice")):
		for id in str(args.get("party", "mahmoud,khalil")).split(",", false):
			Game.companion(id)["recruited"] = true  # test runs: who comes along
			Game.set_flag("hired_" + id)  # the epilogue needs it to tell "died" from "never joined"
	_spawn_party()
	party = PARTY.new()
	add_child(party)
	party.setup(self)
	party.escape_steps = [Step.AWAKENING, Step.ESCAPE]
	if FileAccess.file_exists(TOMB_SITES):
		SiteBudget.begin("akmentar_below", SiteSpot.load_area("akmentar_below"), true)
	Game.event.connect(func(name: String):
		if name == "royal_tomb_interrupted" and step == Step.TOMB:
			_tomb_done = int(SiteBudget.state("royal_tomb").get("used", 0))
			_awaken())
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if args.size() > 0 else Input.MOUSE_MODE_CAPTURED
	# Saves: the start, the royal door, the escape. A death loads the last (SaveRoute), and a load
	# at a milestone starts there.
	var resume_at := Game.place
	if not resume_at.begins_with("act5_"):
		Game.place = "act5_start"
		Game.save_game()
	if resume_at == "act5_royal_door":
		_resume_at_door()
	elif resume_at == "act5_escape":
		_resume_escape()
	else:
		_descend()
	if args.has("view"):
		_view(str(args.view))
	if args.has("holes"):
		_scan_holes()
	if args.has("reach"):
		_scan_reach()


func _unhandled_input(event: InputEvent) -> void:
	if args.size() > 0:
		return
	if step == Step.END and event is InputEventKey and event.pressed and event.keycode in [KEY_ENTER, KEY_KP_ENTER]:
		Loader.go(get_tree(), "res://act6.tscn")  # the Keepers' send-off; Game carries over
	elif event.is_action_pressed("journal"):
		JournalScreen.toggle(self, player)
	elif event.is_action_pressed("party_order"):
		hud.toast("Companions: " + str(Gunman.toggle_party_order(get_tree())))
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ENTER and not player.alive:
		SaveRoute.resume(get_tree())  # the last save: the act's start or a later milestone


# ---------------------------------------------------------------- the act

## Loaded at the royal door's save: before it, the level's studies done (their flags kept).
func _resume_at_door() -> void:
	step = Step.LEVEL2
	var door := level.royal_door.global_position
	player.global_position = Vector3(door.x, AkmentarBelow.deck_y(AkmentarBelow.DECKS - 1), door.z + 3.0)
	player.yaw = 0.0  # facing the door
	_bring_party()
	party.restore()  # those left studying on the way down: back at their sites
	var ally: String = Game.flag("ally", "")
	if ally != "":
		var who := "whitfield" if ally == "americans" else "adler"
		_ally_npc = Npc.make(level, who, player.global_position + Vector3(1.6, 0, 0.5), "", Characters.glb(who))
	_door_spot = Interactable.make(level, door + Vector3(0, -1.0, 1.6), "Open the royal door", "royal_door", 1.6)
	_door_spot.used.connect(func(_by): _royal_door())
	hud.show_message("THE ROYAL DOOR", "Where you stood before.")
	await get_tree().create_timer(2.0).timeout
	hud.show_message("")
	if args.has("auto"):
		_royal_door()


## Loaded at the escape's save: in the tomb as it wakes, and the run again.
func _resume_escape() -> void:
	level.open_royal_door()
	NavCache.bake(level._nav, "akmentar_below_resume")
	var door := level.royal_door.global_position
	var at := door.lerp(level.guardian_spawn, 0.5)
	at.y = AkmentarBelow.deck_y(AkmentarBelow.DECKS - 1)
	player.global_position = at
	var d := door - at
	player.yaw = atan2(-d.x, -d.z)  # facing the way out
	_bring_party()
	party.restore()  # those left studying: where they were when it woke
	_awaken()


## The companions to the player (a load at a milestone puts them at the act's start).
func _bring_party() -> void:
	var i := 0
	for c in companions.values():
		if is_instance_valid(c):
			c.global_position = player.global_position + Vector3(i * 1.2 - 0.6, 0, 1.5)
			i += 1


func _descend() -> void:
	step = Step.DESCEND
	hud.show_message("BELOW AKMENTAR", "The air is cold and old. Somewhere far below, the royal tomb.")
	Objective.set_goal("Find the way down to the royal tomb")
	await get_tree().create_timer(2.5).timeout
	hud.show_message("")
	# The ally's leader comes down with you: the morning talk (what they found, what they hide).
	var ally: String = Game.flag("ally", "")
	if ally != "":
		var who := "whitfield" if ally == "americans" else "adler"
		_ally_npc = Npc.make(level, who, player.global_position + Vector3(1.6, 0, -2.0), "act5_morning", Characters.glb(who))
		if not args.has("auto"):
			await get_tree().create_timer(0.3).timeout
			var c := _ally_npc.talk(player, "act5_morning")
			if c:
				await c.finished
	_level2()


func _level2() -> void:
	step = Step.LEVEL2
	var ally: String = Game.flag("ally", "")
	var budget := 5 if ally != "" else 3
	Game.set_flag("level2_budget", budget)
	if FileAccess.file_exists(LEVEL2_SITES):
		for id in level.pois:
			var s := SiteSpot.make(level, "akmentar_below", AkmentarBelow.SITE_IDS[id], level.pois[id])
			party.hook(s)  # E: who stays to study it
			_level_spots.append(s)
	hud.toast("On the way down you can study %d places before the royal door (%s). Leave someone at each to study it." % [budget,
		"your allies insist on two of them" if ally != "" else "choose well"], 4.5)
	Objective.set_goal("Study what you can on the way down, then open the royal door at the bottom")
	# Sleepers in the maze's dead ends: they wake when you come close or shoot near them.
	for p in level.mummy_spawns:
		var m := Mummy.new()
		m.priest = randf() < 0.3
		add_child(m)
		m.global_position = p
		m.rotation.y = randf() * TAU
		m.target = player
		_sleepers.append(m)
	player.fired.connect(func():
		for m in _sleepers:
			if is_instance_valid(m) and m.global_position.distance_to(player.global_position) < 16.0:
				m.wake())
	_door_spot = Interactable.make(level, level.royal_door.global_position + Vector3(0, -1.0, 1.6), "Open the royal door", "royal_door", 1.6)
	_door_spot.used.connect(func(_by): _royal_door())
	if args.has("auto"):
		_auto_level2()


func _royal_door() -> void:
	if step != Step.LEVEL2:
		return
	step = Step.ROYAL_DOOR
	Game.place = "act5_royal_door"  # a death from here on comes back to the door
	Game.save_game()
	_door_spot.queue_free()
	if FileAccess.file_exists("res://dialogue/act5_royal_door.json") and not args.has("auto"):
		var c := Conversation.new()
		add_child(c)
		c.start("act5_royal_door", player, _ally_npc if _ally_npc else level.royal_door)
		await c.finished
	elif args.has("auto"):
		# No talk in the test: the doc's defaults.
		var ally: String = Game.flag("ally", "")
		Game.set_flag("door_forced", ally == "americans" and not Game.flag("found_warning", false))
		Game.set_flag("german_delay", ally == "germans" and not Game.flag("found_ritual", false))
	if Game.flag("door_forced", false):
		# A beat to get out from under it: the traps cover the space before the door.
		hud.toast("Callahan's men set their bars to the door. Stand clear!", 3.0)
		if args.has("auto"):
			_auto_step_back()
		await get_tree().create_timer(3.0).timeout
		hud.toast("They force the door. The tomb answers.", 3.0)
		_door_traps()
	level.open_royal_door()
	await get_tree().create_timer(3.2).timeout
	NavCache.bake(level._nav, "akmentar_below_open")   # (5 s baked, a few ms from the cache)
	_tomb()


func _door_traps() -> void:
	# -bf's TombTrap: darts from the side walls, then ceiling blocks, in front of the door.
	var ts := _ready_script("res://scripts/tomb_trap.gd", "spring")
	if ts:
		var at := Vector3(level.royal_door.global_position.x, AkmentarBelow.deck_y(AkmentarBelow.DECKS - 1), level.royal_door.global_position.z + 0.5)
		ts.spring(self, Transform3D(Basis(Vector3.UP, PI), at), [])
		return
	for i in 6:
		var at := level.royal_door.global_position + Vector3(randf_range(-3, 3), 3.5, randf_range(0.5, 3.0))
		Fx.impact(self, at - Vector3.UP * 3.4, Vector3.UP, Fx.Kind.STONE)
		Sfx.play_at(self, Sfx.impact(), at, 6.0)
		await get_tree().create_timer(0.25).timeout


func _tomb() -> void:
	step = Step.TOMB
	Barks.say_any(get_tree(), "entering_tomb")
	var allowed := 1 if Game.flag("german_delay", false) else 2
	Game.set_flag("tomb_allowed", allowed)
	hud.toast("The royal tomb of Akmentar", 3.0)
	Objective.set_goal("Study the royal tomb")
	if FileAccess.file_exists(TOMB_SITES):
		# Rebuilt now: the door (german_delay) changes the tomb's slots and its cut.
		SiteBudget.begin("royal_tomb", SiteSpot.load_area("royal_tomb"), true)
		for id in level.royal_pois:
			_tomb_spots[id] = SiteSpot.make(level, "royal_tomb", AkmentarBelow.SITE_IDS[id], level.royal_pois[id])
			party.hook(_tomb_spots[id])
	if args.has("auto"):
		_auto_tomb()


## The interruption: after the 2nd study (the 1st with the German delay) the tomb wakes.
func _tomb_studied() -> void:
	_tomb_done += 1
	if _tomb_done >= int(Game.flag("tomb_allowed", 2)) and step == Step.TOMB:
		await get_tree().create_timer(1.5).timeout
		_awaken()


func _awaken() -> void:
	step = Step.AWAKENING
	Game.place = "act5_escape"  # a death in the escape comes back to the waking
	Game.save_game()
	Game.set_flag("awakened", true)
	hud.show_message("", "")
	hud.toast("The sarcophagus lid grinds. Something breathes.", 3.0)
	level.open_sarcophagus()
	player.set_armed(true)
	for lamp in level.torches:
		lamp.light_energy *= 0.6
	await get_tree().create_timer(1.5).timeout
	var gs := _ready_script(GUARDIAN, "spawn")
	if gs:
		guardian = gs.spawn(self, level.guardian_spawn, player)
		guardian.set("commander", true)
		if guardian.has_signal("commanded"):
			guardian.connect("commanded", _summon)
	else:
		var m := Mummy.new()
		m.priest = true
		add_child(m)
		m.global_position = level.guardian_spawn
		m.target = player
		m.wake()
		guardian = m
	var ss := _ready_script(SCARABS, "burst")
	if ss:
		for v in level.vents:
			ss.burst(self, v, player)
	# Only the dead down here rise with him; the rest wait in the levels above until he calls them.
	for p in level.minion_spawns:
		if AkmentarBelow.deck_of(p.y) == AkmentarBelow.DECKS - 1:
			_raise(p)
		else:
			_dormant.append(p)
	_escape()


## His call (Guardian.commanded): the dead nearest `at` and ahead of it (the levels above you, the
## way you're going) rise and come for you. A few at a time; at most MAX_RAISED walking at once.
const PER_CALL := 2
const MAX_RAISED := 9
var _dormant: Array[Vector3] = []


func _summon(at: Vector3) -> void:
	if step != Step.ESCAPE:
		return
	var walking := 0
	for m in get_tree().get_nodes_in_group("mummies"):
		if m != guardian and is_instance_valid(m) and (m as Node).has_method("is_active") and m.call("is_active"):
			walking += 1
	var here := AkmentarBelow.deck_of(at.y)
	_dormant.sort_custom(func(a: Vector3, b: Vector3) -> bool: return _call_rank(a, at, here) < _call_rank(b, at, here))
	var n := 0
	while n < PER_CALL and walking + n < MAX_RAISED and not _dormant.is_empty():
		var p: Vector3 = _dormant[0]
		if _call_rank(p, at, here) > 200.0:
			break
		_dormant.remove_at(0)
		_raise(p)
		n += 1
	# And one near someone making their own way out, when there's room: they're hunted too.
	var solos: Array = party.solo_points() if party else []
	if not solos.is_empty() and walking + n < MAX_RAISED and not _dormant.is_empty():
		var near: Vector3 = solos[randi() % solos.size()]
		var lvl := AkmentarBelow.deck_of(near.y)
		_dormant.sort_custom(func(a: Vector3, b: Vector3) -> bool: return _call_rank(a, near, lvl) < _call_rank(b, near, lvl))
		if _call_rank(_dormant[0], near, lvl) <= 200.0:
			_raise(_dormant.pop_front())
			n += 1
	if n > 0:
		hud.toast("Somewhere ahead, stone scrapes on stone. He's calling them up.", 3.0)
	if args.has("auto"):
		print("RESULT summon raised=%d walking=%d left=%d level=%d solos=%d t=%.1f" % [n, walking, _dormant.size(), here, solos.size(), _t])


## Lower = called first: on your level or the next one up (where you're heading), 8-40 m off.
func _call_rank(p: Vector3, at: Vector3, here: int) -> float:
	var lvl := AkmentarBelow.deck_of(p.y)
	var d := Vector2(p.x - at.x, p.z - at.z).length()
	if lvl > here or lvl < here - 1 or d < 8.0:
		return 999.0
	return d + (0.0 if lvl == here else 10.0)


## The shrine's seal forced (no clue_builders_seal): the crack carries; a couple wake nearby.
func _seal_forced(at: Vector3) -> void:
	hud.toast("The crack rolls away through the rock. Something below heard it.", 3.0)
	var near := level.minion_spawns.duplicate()
	near.sort_custom(func(a: Vector3, b: Vector3) -> bool: return a.distance_to(at) < b.distance_to(at))
	for p: Vector3 in near.slice(0, 2):
		_raise(p)


func _raise(p: Vector3) -> void:
	var mm := Mummy.new()
	add_child(mm)
	mm.global_position = p
	mm.target = player
	mm.wake()


func _escape() -> void:
	step = Step.ESCAPE
	Barks.say_any(get_tree(), "act5_escape")
	hud.toast("RUN. Back to the stairs!", 3.0)
	Objective.set_goal("Get out of the tomb: back to the stairs")
	# Those you left studying each make their own run for the nearest way out (Simon: everyone is
	# somewhere in the tomb when it wakes); the rest run with you (-bf's escape mode), and one of
	# them goes down partway (help or leave).
	var solo: Array = party.escape_start()
	var i := 0
	var with_you: Array[Gunman] = []
	for id in companions:
		var c: Gunman = companions[id]
		if is_instance_valid(c) and not id in solo:
			c.escape = true
			with_you.append(c)
			if args.has("auto"):  # the bot teleported through the tomb: bring them along
				c.global_position = player.global_position + Vector3(i * 1.2 - 0.6, 0, 1.5)
				i += 1
	if not solo.is_empty():
		hud.toast("%s %s still down there somewhere. They'll make for the stairs." % [
			", ".join(solo.map(func(id): return Hud._first_name(companions[id]))), "is" if solo.size() == 1 else "are"], 4.0)
	_ally_run()
	if not with_you.is_empty():
		get_tree().create_timer(14.0).timeout.connect(func():
			var c: Gunman = with_you[0]
			if is_instance_valid(c) and c.alive and step == Step.ESCAPE:
				c.stumble())
	# Collapsed sections along the way: a heap across part of the passage, never all of it (Simon:
	# a chest-high wall sealed the way out). Run round the gap, or vault it (E, then W+E).
	var k := 0
	for c in level.collapse_points:
		var size := Vector3(2.4, 1.0, 0.8)
		var side := 0.8 if k % 2 == 0 else -0.8
		var rubble := level._box(level._nav, c + Vector3(side, 0.5, 0), size, level._stone)
		level._mark_cover(rubble, size)
		k += 1
		_rubble_hint(rubble)
	_rebake()  # paths round the rubble (or vault it)
	_arm_slabs()
	if args.has("auto"):
		_auto_escape()
	var out := -1
	while out < 0:
		if not player.alive:
			return
		await get_tree().create_timer(0.2).timeout
		out = _exit_reached(player)
		if _builders_out:
			out = 3  # up the workmen's stair to the ravine
	# The revelation happens where you came up (the Builders' Way's top is still below ground: the
	# surface's main exit instead).
	level.stair_top = level.exits[out] if out < level.exits.size() else level.exits[0]
	if out == 3:
		# Placeholder until the ravine has its own spot: up and out by the main stairs' top, with
		# whoever was on the stair with you.
		hud.show_message("THE BUILDERS' WAY", "Up the workmen's stair, and out into the ravine.")
		var top: Vector3 = level.points.get("builders_way", player.global_position)
		var n := 0
		for c in companions.values():
			if is_instance_valid(c) and c.alive and (c as Node3D).global_position.distance_to(top) < 10.0:
				(c as Node3D).global_position = level.stair_top + Vector3(n * 1.2 - 1.2, 0.1, 3.5)
				n += 1
		player.global_position = level.stair_top + Vector3(0, 0.1, 2.0)
		get_tree().create_timer(2.5).timeout.connect(func() -> void: hud.show_message(""))
	_guardian_turns_back()
	Game.set_flag("escaped", true)
	Game.set_flag("escape_exit", ["main", "west", "east", "builders"][out])
	await _wait_for_companions()
	_revelation()


## The allied expedition are the thieves: at the awakening they bolt for the nearest way out with
## what they took, ahead of you, and don't wait for anyone. They follow a runner that takes the
## navmesh path to the exit (round any shut slab); at the top they're gone. Simon: "those allies
## should leave before you as they are the thieves".
func _ally_run() -> void:
	var ally: String = Game.flag("ally", "")
	if not ALLY_TEAMS.has(ally):
		return
	var from := _ally_npc.global_position if _ally_npc else player.global_position + Vector3(0, 0, 3.0)
	if _ally_npc:
		_ally_npc.queue_free()
		_ally_npc = null
	var runner := Node3D.new()
	runner.name = "AllyRunner"
	add_child(runner)
	runner.global_position = from
	var i := 0
	for id in ALLY_TEAMS[ally]:
		var g := Gunman.new()
		g.name = str(id).capitalize()
		g.team = Gunman.PARTY
		g.leader = runner
		g.glb = Characters.glb(id)
		g.max_health = 120.0
		g.health = 120.0
		add_child(g)
		g.global_position = from + Vector3(i * 1.1 - 1.1, 0, 0.8 * i)
		g.escape = true
		_ally_team[id] = g
		i += 1
	if level.amulet:
		level.amulet.visible = false  # it's in their sacking
	var who: String = ALLY_TEAMS[ally][0]
	hud.toast("%s's people are running for it, and they've got something wrapped in sacking." % who.capitalize(), 4.0)
	_ally_flee(runner)


func _ally_flee(runner: Node3D) -> void:
	const SPEED := 6.0
	var map := get_world_3d().navigation_map
	var path := PackedVector3Array()
	var best := INF
	var replan := 0.0
	while step == Step.ESCAPE or step == Step.AWAKENING:
		# Planned twice a second, not every frame: three paths up five levels each frame cost ~40 ms
		# (-7f's perf sweep: the escape fell to 21 fps).
		replan -= get_physics_process_delta_time()
		if replan <= 0.0 or path.size() < 2:
			replan = 0.5
			path = PackedVector3Array()
			best = INF
			for e in level.exits:
				var p := NavigationServer3D.map_get_path(map, runner.global_position, e + Vector3(0, 0, 1.0), true)
				var len := 0.0
				for k in range(1, p.size()):
					len += p[k].distance_to(p[k - 1])
				if p.size() > 1 and len < best:
					best = len
					path = p
		while path.size() > 1 and runner.global_position.distance_to(path[1]) < 0.3:
			path.remove_at(0)
		if path.size() < 2 or (best < 1.5 and path.size() <= 2):
			break  # out
		var step_len := SPEED * get_physics_process_delta_time()
		var to := path[1] - runner.global_position
		runner.global_position += to.normalized() * minf(step_len, to.length())
		# Don't leave the slow ones too far behind: the runner waits for the pack.
		var lag := 0.0
		for g in _ally_team.values():
			if is_instance_valid(g) and g.alive:
				lag = maxf(lag, g.global_position.distance_to(runner.global_position))
		if lag > 6.0:
			runner.global_position -= to.normalized() * minf(step_len, to.length())
		await get_tree().physics_frame
	# Up and away: gone before you get there.
	for g in _ally_team.values():
		if is_instance_valid(g):
			g.queue_free()
	runner.queue_free()
	Game.set_flag("thieves_fled", true)


## The first time you come up to a rubble heap: how to get over it.
func _rubble_hint(rubble: Node3D) -> void:
	while step == Step.ESCAPE and is_instance_valid(rubble):
		if player.global_position.distance_to(rubble.global_position) < 4.0:
			if not _told_vault:
				_told_vault = true
				hud.toast("Fallen stone: run round the gap, or {cover} to take cover against it, then {move_forward}+{cover} to vault.", 4.0)
			return
		await get_tree().create_timer(0.3).timeout


## Drop-slabs: each sinks when you run at it; the stairs' neck on a timer. A shut slab changes the
## maze, so the navmesh is rebaked: companions and the guardian path round (or are cut off).
func _arm_slabs() -> void:
	var people: Array = [player]
	if guardian:
		people.append(guardian)
	var told := [false]
	for s in level.slab_doors:
		s.target = player
		s.people = people
		s.armed = true
		s.shut.connect(_rebake)
		if args.has("auto"):
			s.started.connect(func(): print("RESULT slab start at=%s t=%.1f" % [s._floor, _t]))
			s.shut.connect(func():
				var near := []
				for id in companions:
					var c: Node3D = companions[id]
					if is_instance_valid(c):
						near.append("%s:%.0fm" % [id, c.global_position.distance_to(s._floor)])
				print("RESULT slab shut at=%s player=%.0fm %s" % [s._floor, player.global_position.distance_to(s._floor), near]))
		s.started.connect(func():
			if not told[0]:
				told[0] = true
				hud.toast("Stone grinds overhead: the slab is coming down. Get under it!", 3.0))
	if level.neck_slab:
		level.neck_slab.drop_after = NECK_SLAB_AFTER
		level.neck_slab.target = null  # only its timer brings it down: running at it mustn't cut off the companions behind you
		level.neck_slab.started.connect(func():
			hud.toast("Far off, a deep grinding: the way to the main stairs is closing.", 3.5))
	# Scarab vents in the corridor walls: each pours once as you pass.
	var ss := _ready_script(SCARABS, "pour")
	if ss == null:
		return
	for v in level.scarab_vents:
		_vent_watch(ss, v)


func _vent_watch(ss: GDScript, v: Dictionary) -> void:
	while step == Step.ESCAPE and player.global_position.distance_to(v.point) > 5.0:
		await get_tree().create_timer(0.25).timeout
	if step == Step.ESCAPE:
		ss.pour(self, v.point, v.normal)


## Out in the daylight, the hunt is over for now (Simon: the mummy could still kill him after he got
## out): the guardian is after the amulet, not you, and won't follow into the sun. It stops, turns
## back into the dark and is gone; its minions with it.
func _guardian_turns_back() -> void:
	if guardian and is_instance_valid(guardian):
		if guardian.has_method("pause"):
			guardian.call("pause")
		var g := guardian
		get_tree().create_timer(1.5).timeout.connect(func():
			if is_instance_valid(g):
				g.queue_free())
	# His minions near the way out go with him; deeper in, those after someone still making their
	# own way out keep at it (going back for them means facing those), until they reach the light.
	var inside: Array = party.solo_points() if party else []
	for m in get_tree().get_nodes_in_group("mummies"):
		if is_instance_valid(m) and m != guardian:
			var mm := m as Node3D
			if inside.is_empty() or _in_sun(mm.global_position) or not inside.any(func(p: Vector3) -> bool: return p.distance_to(mm.global_position) < 30.0):
				mm.queue_free()
	if not inside.is_empty():
		_sun_watch()


## The dead don't follow into the sun: near an exit and up the last stairs, they're gone.
func _in_sun(p: Vector3) -> bool:
	for e: Vector3 in level.exits:
		if p.y > -4.0 and Vector2(p.x - e.x, p.z - e.z).length() < 12.0:
			return true
	return false


func _sun_watch() -> void:
	while step == Step.ESCAPE:
		for m in get_tree().get_nodes_in_group("mummies"):
			if is_instance_valid(m) and m != guardian and _in_sun((m as Node3D).global_position):
				(m as Node).queue_free()
		await get_tree().create_timer(0.5).timeout


## Which exit `who` is out of (index into level.exits), or -1.
func _exit_reached(who: Node3D) -> int:
	for i in level.exits.size():
		var e: Vector3 = level.exits[i]
		var p := who.global_position
		if p.y > -1.0 and absf(p.x - e.x) < 4.0 and p.z > e.z - 2.0:
			return i
	return -1


## A companion is out once at the top, or on the last of the stairs close behind you.
func _out(c: Node3D) -> bool:
	if party and c is Gunman and party.runs.has((c as Gunman).companion_id) and party.runs[(c as Gunman).companion_id].out:
		return true  # made it up on their own
	return _exit_reached(c) >= 0 or (c.global_position.y > -3.0 and c.global_position.distance_to(player.global_position) < 8.0) \
		or (_builders_out and level.points.has("builders_way") and c.global_position.distance_to(level.points["builders_way"]) < 10.0)


## At the top: a few seconds for the companions still coming; whoever isn't out by then (cut off
## behind a slab, caught, lost in the dark) is a casualty.
func _wait_for_companions() -> void:
	# Five levels is a long climb: you wait as long as someone is still coming (getting nearer the
	# way out), and give up on whoever has stopped coming for WAIT_AT_TOP s (cut off, caught, down).
	var t := 0.0
	var since_progress := 0.0
	var best := {}
	var waiting := true
	while waiting and since_progress < WAIT_AT_TOP and t < WAIT_MAX:
		waiting = false
		var closer := false
		for id in companions:
			var c: Node3D = companions[id]
			if is_instance_valid(c) and c.alive and not _out(c):
				waiting = true
				var d := c.global_position.distance_to(level.stair_top)
				if d < float(best.get(id, INF)) - 0.5:
					best[id] = d
					closer = true
		if waiting:
			if t == 0.0:
				hud.toast("You wait at the top, listening for footsteps...", 3.0)
			await get_tree().create_timer(0.5).timeout
			t += 0.5
			since_progress = 0.0 if closer else since_progress + 0.5
	var lost: Array = []
	var why := {}
	for id in companions:
		var c: Gunman = companions[id]
		if not is_instance_valid(c) or not c.alive or not _out(c):
			lost.append(id)
			why[id] = party.reason(id)
	Game.set_flag("act5_casualties", lost)
	Game.set_flag("act5_casualty_reasons", why)  # id -> cut off behind a slab, caught, down and left, lost in the dark
	var made := companions.size() - lost.size()
	if not lost.is_empty():
		hud.toast("%d of %d came out. %s." % [made, companions.size(), "; ".join(lost.map(func(id): return "%s: %s" % [
			DayLog.person(str(id)), why[id]]))], 6.0)
	elif not companions.is_empty():
		hud.toast("All %d of them came out." % companions.size(), 3.5)


func _revelation() -> void:
	step = Step.REVELATION
	for c in companions.values():
		if is_instance_valid(c) and (c as Node).has_meta("left_behind"):
			(c as Node).remove_meta("left_behind")  # no more arrows down into the dark
	var ally: String = Game.flag("ally", "")
	var thieves: String = ally if ally != "" else "italians"
	Game.set_flag("thieves", thieves)
	Game.set_flag("thieves_" + thieves)  # plain flag the revelation talk can test
	hud.toast("Daylight, and men in indigo all around you.", 3.0)
	_rashad = Npc.make(self, "rashad", level.stair_top + Vector3(0, 0, 3.0), "act5_revelation", Characters.glb("rashad"))
	await get_tree().create_timer(2.0).timeout
	if args.has("auto"):
		await BotTalk.run(self, "act5_revelation", player, _rashad)  # its flags (new_objective...) carry on
	elif FileAccess.file_exists("res://dialogue/act5_revelation.json"):
		var c := Conversation.new()
		add_child(c)
		c.start("act5_revelation", player, _rashad if _rashad else player)
		await c.finished
	_end()


func _end() -> void:
	step = Step.END
	Game.place = "act5_end"
	Objective.set_goal("")
	Game.save_game()
	var lines := ["The guardian is awake.", "The amulet is gone: the %s took it." % str(Game.flag("thieves", "")).capitalize(),
		"The Keepers want it back, and so must you."]
	hud.show_message("THE AWAKENING", "\n".join(lines) + "\n\nEnter  hear the Keepers out (Act 6)")
	print("RESULT act5 end ally=%s forced=%s delay=%s studied_tomb=%d escaped=%s exit=%s lost=%s fled=%s thieves=%s t=%.0f" % [
		Game.flag("ally", ""), Game.flag("door_forced", false), Game.flag("german_delay", false), _tomb_done,
		Game.flag("escaped", false), Game.flag("escape_exit", ""), Game.flag("act5_casualties", []), Game.flag("thieves_fled", false),
		Game.flag("thieves", ""), _t])
	if party:
		var solo := {}
		for id in party.runs:
			var r: Dictionary = party.runs[id]
			solo[id] = "joined you" if r.joined else ("out on their own" if r.out else str(Game.flag("act5_casualty_reasons", {}).get(id, "?")))
		print("RESULT act5 party out=%d of %d left_at_sites=%s runs=%s why=%s" % [companions.size() - (Game.flag("act5_casualties", []) as Array).size(),
			companions.size(), party.left.keys(), solo, Game.flag("act5_casualty_reasons", {})])
	if args.has("auto"):
		TestDriver.auto_end(self, "res://act6.tscn", 1.5)  # --chain: on, as Enter would


func _spawn_party() -> void:
	var i := 0
	for id in Game.party():
		var c := Gunman.make_companion(id, player, Characters.glb(id))
		if c:
			add_child(c)
			c.global_position = player.global_position + Vector3((2.4 + i * 1.2) * (1 if i % 2 == 0 else -1), 0, -1.0)  # to the sides, not in the lens
			companions[id] = c
			i += 1


# ---------------------------------------------------------------- test bot

var _rebake_again := false


## Mid-escape rebakes run on a thread (a synchronous one stalled ~220 ms when the rubble fell,
## -7f's perf sweep); one asked for while another is baking runs once that one finishes.
func _rebake() -> void:
	if level._nav.is_baking():
		if not _rebake_again:
			_rebake_again = true
			level._nav.bake_finished.connect(func():
				_rebake_again = false
				_rebake(), CONNECT_ONE_SHOT)
		return
	level._nav.bake_navigation_mesh(true)


var _death_logged := false
var _still := 0


func _process(delta: float) -> void:
	_t += delta
	if _shots.size() > 0 and _t >= _shots[0]:
		_shots.pop_front()
		_shot("act5_%05.1f.png" % _t)
	if args.has("auto") and step in [Step.AWAKENING, Step.ESCAPE]:
		player.max_health = 1.0e9
		player.health = 1.0e9
	if args.has("auto") and not player.alive and not _death_logged:
		_death_logged = true
		print("RESULT act5 died step=%s at=%s t=%.1f" % [Step.keys()[step], player.global_position, _t])
	if args.has("party-trace") and step == Step.ESCAPE and int(_t * 10) % 40 == 0:
		var line := []
		for id in companions:
			var c: Gunman = companions[id]
			if is_instance_valid(c):
				line.append("%s %s %s" % [id, c.global_position.snapped(Vector3.ONE * 0.5), Gunman.State.keys()[c.state]])
		print("PARTY t=%.1f player=%s %s" % [_t, player.global_position.snapped(Vector3.ONE * 0.5), line])
	if args.has("seconds") and _t > float(args.seconds):
		print("RESULT act5 timeout step=%s player=%s" % [Step.keys()[step], player.global_position])
		get_tree().quit(1)


func _shot(file: String) -> void:
	await RenderingServer.frame_post_draw
	var dir: String = args.get("shot-dir", "user://shots")
	DirAccess.make_dir_recursive_absolute(dir)
	get_viewport().get_texture().get_image().save_png(dir.path_join(file))
	print("RESULT shot %s" % dir.path_join(file))


func _auto_level2() -> void:
	await get_tree().create_timer(1.0).timeout
	if int(args.get("leave", 0)) > 0:
		await _auto_leave(int(args.leave))
	player.global_position = _door_spot.global_position + Vector3(0, 0, 1.0)
	player.yaw = 0.0
	await get_tree().create_timer(0.5).timeout
	_door_spot.use(player)


## Test: --leave=N. On the way down, one companion left at each of N sites on different levels
## (spread from the top level to the bottom), as the menu would; the bot waits for their clues.
func _auto_leave(n: int) -> void:
	var by_deck := {}
	for s in _level_spots:
		if is_instance_valid(s) and s.refusal() == "":
			var k := AkmentarBelow.deck_of(s.global_position.y)
			if not by_deck.has(k):
				by_deck[k] = s
	var decks: Array = by_deck.keys()
	decks.sort()
	var picks: Array = []
	for i in mini(n, decks.size()):
		picks.append(by_deck[decks[roundi(float(i) * (decks.size() - 1) / maxf(n - 1, 1))]])
	for s: SiteSpot in picks:
		var free: Array = party.following()
		if free.is_empty() or s.refusal() != "":
			break
		var g: Gunman = free[0]
		player.global_position = s.global_position + Vector3(0, 0, 2.5)
		g.global_position = s.global_position + Vector3(1.5, 0.05, 1.5)
		await get_tree().create_timer(0.3).timeout
		party.leave(s, [g.companion_id])
		await get_tree().create_timer(0.5).timeout
	var t := 0.0
	while t < 20.0 and party.left.values().any(func(e: Dictionary) -> bool: return not e.done):
		await get_tree().create_timer(0.5).timeout
		t += 0.5
	print("RESULT act5 auto left=%s studied=%s t=%.1f" % [party.left.keys(), party.left.values().map(func(e: Dictionary) -> bool: return e.done), _t])


func _auto_tomb() -> void:
	await get_tree().create_timer(1.0).timeout
	for id in ["1", "2", "3"]:
		player.global_position = level.royal_pois[id] + Vector3(0, 0, 2.0)
		await get_tree().create_timer(0.6).timeout
		if _tomb_spots.has(id):
			(_tomb_spots[id] as SiteSpot).inspect(player)  # (its E asks who stays: the bot studies it itself)
			await get_tree().create_timer(0.8).timeout
			for n in get_tree().root.find_children("*", "", true, false):
				if n is ModalScreen:
					n.close()  # the clue card; closing it lets the interruption fire
			await get_tree().create_timer(1.0).timeout
		else:
			_tomb_studied()  # no data: count it here
		if step != Step.TOMB:
			return


## Escape: walk the navmesh path to the stairs' top at a sprint (god mode in the test).
## Test views of the maze: --view=<name> --shot-dir=... stands the player there and takes one shot.
## Test views of the tomb: --view=<name> --shot-dir=... stands the player there and takes one shot.
## [level, row, col, yaw, pitch]
const VIEWS := {"shaft": [0, 19, 38, PI * 0.75, -0.7], "stair": [2, 32, 25, 0.0, 0.15], "bridge1": [1, 25, 31, -PI / 2, -0.1],
	"bridge3": [3, 26, 31, 0.0, -0.2], "forecourt": [4, 30, 31, 0.0, 0.75], "royal": [4, 7, 31, 0.0, -0.1],
	"hall2": [2, 50, 30, -PI / 2, -0.05], "secret": [2, 26, 49, -PI / 2, -0.05], "rails": [0, 20, 37, PI * 0.75, -0.25],
	"west1": [1, 33, 9, 0.0, -0.05], "south": [0, 42, 31, 0.0, 0.0]}


func _view(name: String) -> void:
	await get_tree().create_timer(4.0).timeout
	var v: Array = VIEWS.get(name, VIEWS.shaft)
	player.global_position = level.dcell(v[0], v[1], v[2]) + Vector3.UP * 0.3
	player.yaw = v[3]
	player.pitch = v[4]
	var i := 0
	for c in companions.values():
		(c as Node3D).global_position = player.global_position + Basis(Vector3.UP, v[3]) * Vector3(i * 0.9 - 0.45, 0, 2.0)
		i += 1
	await get_tree().create_timer(2.5).timeout
	await _shot("act5_view_%s.png" % name)
	get_tree().quit(0)


## Test: --holes. Every walkable cell on every level, at its centre and near its corners: floor
## within 3 m below (the well's open cells and the stairwells' holes are skipped). Prints each hole.
func _scan_holes() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	var space := get_world_3d().direct_space_state
	var holes := 0
	for k in AkmentarBelow.DECKS:
		for r in AkmentarBelow.H:
			for c in AkmentarBelow.W:
				var ch := level.dch(k, r, c)
				if ch in ["#", "L", "D", "?", "O", "s"]:
					continue
				var p := level.dcell(k, r, c)
				for off in [Vector2.ZERO, Vector2(0.8, 0.8), Vector2(-0.8, 0.8), Vector2(0.8, -0.8), Vector2(-0.8, -0.8)]:
					var from := Vector3(p.x + off.x, p.y + 1.5, p.z + off.y)
					var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 3.0, 1))
					if hit.is_empty():
						holes += 1
						print("RESULT hole level=%d r=%d c=%d ch=%s at=%s" % [k, r, c, ch, from])
	print("RESULT holes=%d" % holes)
	get_tree().quit(0)


## Test: --reach. From every walkable cell on every level (every 3rd, for speed), a navmesh path to
## the main stairs' top must arrive. Prints each cell that can't get out (walls in the way, a gap).
func _scan_reach() -> void:
	await get_tree().create_timer(1.0).timeout
	var map := get_world_3d().navigation_map
	var bad := 0
	var n := 0
	for k in AkmentarBelow.DECKS:
		for r in range(0, AkmentarBelow.H, 3):
			for c in range(0, AkmentarBelow.W, 3):
				var ch := level.dch(k, r, c)
				if ch in ["#", "L", "D", "?", "O", "s", "|"]:
					continue
				var p := level.dcell(k, r, c)
				var from := NavigationServer3D.map_get_closest_point(map, p)
				if from.distance_to(p) > 1.2:
					bad += 1
					print("RESULT reach nonav level=%d r=%d c=%d ch=%s" % [k, r, c, ch])
					continue
				n += 1
				var way := NavigationServer3D.map_get_path(map, from, level.stair_top, true)
				if way.size() < 2 or way[way.size() - 1].distance_to(level.stair_top) > 3.0:
					bad += 1
					print("RESULT reach stuck level=%d r=%d c=%d ch=%s ends=%s" % [k, r, c, ch, way[way.size() - 1] if way.size() > 0 else Vector3.ZERO])
	print("RESULT reach checked=%d bad=%d" % [n, bad])
	get_tree().quit(0)


func _auto_step_back() -> void:
	var away := player.global_position - level.royal_door.global_position
	player.yaw = atan2(-away.x, -away.z)
	Input.action_press("move_forward")
	await get_tree().create_timer(2.4).timeout
	Input.action_release("move_forward")


## Test: --help. When a companion goes down, the bot goes back, faces him and presses E as a player
## would; logs whether the prompt was there, whether he's up, and whether he runs on.
var _helping: Gunman


func _auto_help_watch() -> void:
	for c in companions.values():
		(c as Gunman).stumbled_down.connect(func(g: Gunman): _helping = g)


func _auto_help(g: Gunman) -> void:
	var to := g.global_position - player.global_position
	to.y = 0
	player.global_position = g.global_position - to.normalized() * 1.3
	player.yaw = atan2(-to.x, -to.z)
	for i in 6:
		await get_tree().physics_frame
	var prompt := player.focus.prompt if player.focus and "prompt" in player.focus else str(player.focus)
	print("RESULT help prompt=%s stumbled=%s dist=%.1f" % [prompt, g.stumbled, player.global_position.distance_to(g.global_position)])
	Input.action_press("cover")
	await get_tree().physics_frame
	await get_tree().physics_frame
	Input.action_release("cover")
	await get_tree().create_timer(0.3).timeout
	var at := g.global_position
	await get_tree().create_timer(2.0).timeout
	print("RESULT help after_e stumbled=%s alive=%s moved=%.1f state=%s" % [g.stumbled, g.alive, g.global_position.distance_to(at), Gunman.State.keys()[g.state]])


var _fetch_id := ""
var _fetched := false


## --fetch: the one left behind the bot goes back for (the nearest when it starts), until they've
## joined you, are out, or are gone.
func _fetch_target() -> Gunman:
	if not args.has("fetch") or _fetched or party == null:
		return null
	if _fetch_id == "":
		var bd := INF
		for id in party.runs:
			var g := companions.get(id) as Gunman
			var r: Dictionary = party.runs[id]
			if is_instance_valid(g) and g.state != Gunman.State.DEAD and not r.joined and not r.out:
				var d := g.global_position.distance_to(player.global_position)
				if d < bd:
					bd = d
					_fetch_id = id
		if _fetch_id == "":
			_fetched = true
			return null
		print("RESULT act5 bot goes back for %s (%.0f m) t=%.1f" % [_fetch_id, bd, _t])
	var g := companions.get(_fetch_id) as Gunman
	var r: Dictionary = party.runs.get(_fetch_id, {})
	if not is_instance_valid(g) or g.state == Gunman.State.DEAD or r.get("joined", false) or r.get("out", false):
		_fetched = true
		print("RESULT act5 fetch %s done: %s t=%.1f" % [_fetch_id, "joined" if r.get("joined", false) else ("out" if r.get("out", false) else "lost"), _t])
		return null
	if g.stumbled and player.global_position.distance_to(g.global_position) < 2.0:
		_helping = g  # down: help them up (the --help routine), then on
	return g


func _auto_escape() -> void:
	if args.has("help"):  # (not with --fetch alone: _auto_help steps the bot to them, wherever they fell)
		_auto_help_watch()
	while step == Step.ESCAPE and player.alive:
		if _helping:
			var g := _helping
			_helping = null
			Input.action_release("move_forward")
			Input.action_release("sprint")
			await _auto_help(g)
			continue
		var path := PackedVector3Array()
		var best := INF
		for e in level.exits:
			var p := NavigationServer3D.map_get_path(get_world_3d().navigation_map, player.global_position,
				e + Vector3(0, 0, -1.0), true)
			var len := 0.0
			for i in range(1, p.size()):
				len += p[i].distance_to(p[i - 1])
			if p.size() > 1 and p[p.size() - 1].distance_to(e + Vector3(0, 0, -1.0)) > 2.0:
				len = INF  # the path ends short: that way is shut
			if len < best:
				best = len
				path = p
		# --fetch: first, back for the nearest one left behind (till they're with you).
		var fetch := _fetch_target()
		if fetch:
			path = NavigationServer3D.map_get_path(get_world_3d().navigation_map, player.global_position, fetch.global_position, true)
		var next: Vector3 = path[1] if path.size() > 1 else level.stair_top
		var d := next - player.global_position
		# A minion in the way: stop and shoot it.
		var block: Mummy = null
		for m in get_tree().get_nodes_in_group("mummies"):
			var mm := m as Mummy
			if mm and mm.is_active() and mm.global_position.distance_to(player.global_position) < 7.0 and mm != guardian:
				var seen := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(
					player.camera.global_position, mm.aim_point(player.camera.global_position), 1)).is_empty()
				if seen:
					block = mm
					break
		if block:
			var aim := block.aim_point(player.camera.global_position) - player.camera.global_position  # a limb: they're shot apart, never killed
			player.yaw = atan2(-aim.x, -aim.z)
			player.pitch = asin(clampf(aim.normalized().y, -1, 1))
			Input.action_release("sprint")
			Input.action_release("move_forward")
			Input.action_press("aim")
			Input.action_press("fire")
			await get_tree().create_timer(0.25).timeout
			Input.action_release("fire")
			continue
		Input.action_release("aim")
		player.yaw = atan2(-d.x, -d.z)
		Input.action_press("move_forward")
		Input.action_press("sprint")
		var was := player.global_position
		await get_tree().create_timer(0.25).timeout
		_still = _still + 1 if player.global_position.distance_to(was) < 0.1 else 0
		if _still >= 4:
			# Blocked by a fallen block or rubble: into cover on it (E), then over (W+E).
			_still = 0
			Input.action_release("sprint")
			Input.action_release("move_forward")
			for tap in 2:
				if tap == 1:
					Input.action_press("move_forward")
				Input.action_press("cover")
				await get_tree().physics_frame
				await get_tree().physics_frame
				Input.action_release("cover")
				await get_tree().create_timer(0.4).timeout
			await get_tree().create_timer(0.8).timeout
	Input.action_release("move_forward")
	Input.action_release("sprint")


## A helper's script, only once it exists, compiles and has `entry` (else null: the fallback runs).
func _ready_script(path: String, entry: String) -> GDScript:
	if not ResourceLoader.exists(path):
		return null
	var s := load(path) as GDScript
	if s == null or not s.can_instantiate():
		return null
	for m in s.get_script_method_list():
		if m.name == entry:
			return s
	return null
