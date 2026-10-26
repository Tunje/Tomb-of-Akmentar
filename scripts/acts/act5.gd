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
const NECK_SLAB_AFTER := 45.0
const WAIT_AT_TOP := 8.0  # how long the survivors at the top wait for the rest
## The allied expedition (the thieves) running out ahead of you: its leader and two of its people.
const ALLY_TEAMS := {"americans": ["whitfield", "maggie", "callahan"], "germans": ["adler", "kruger", "vogel"]}

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
	player = Player.new()
	add_child(player)
	player.global_position = level.player_spawn
	player.yaw = 0.0  # facing north, into the tomb
	# Her lantern: the maze between the torches is black without it.
	var lantern := OmniLight3D.new()
	lantern.light_color = Color(1.0, 0.72, 0.42)
	lantern.light_energy = 0.9
	lantern.omni_range = 9.0
	lantern.omni_attenuation = 1.4
	lantern.shadow_enabled = true
	lantern.position = Vector3(0.3, 1.1, -0.2)
	player.add_child(lantern)
	hud = Hud.new()
	hud.player = player
	add_child(hud)
	add_child(CountdownBars.new())
	player.hit_confirmed.connect(hud.on_hit)
	player.damaged.connect(hud.on_damaged)
	player.died.connect(func(): hud.show_message("YOU DIED", "Enter to try again"))
	for s in str(args.get("shots", "")).split(",", false):
		_shots.append(float(s))
	if args.has("party") or ((args.has("auto") or Game.flag("quickstart_act", false)) and Game.party().is_empty()):
		for id in str(args.get("party", "mahmoud,khalil")).split(",", false):
			Game.companion(id)["recruited"] = true  # test runs: who comes along
	_spawn_party()
	if FileAccess.file_exists(TOMB_SITES):
		SiteBudget.begin("akmentar_below", SiteSpot.load_area("akmentar_below"), true)
	Game.event.connect(func(name: String):
		if name == "royal_tomb_interrupted" and step == Step.TOMB:
			_tomb_done = int(SiteBudget.state("royal_tomb").get("used", 0))
			_awaken())
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if args.size() > 0 else Input.MOUSE_MODE_CAPTURED
	_descend()
	if args.has("view"):
		_view(str(args.view))
	if args.has("holes"):
		_scan_holes()


func _unhandled_input(event: InputEvent) -> void:
	if args.size() > 0:
		return
	if event.is_action_pressed("journal"):
		JournalScreen.toggle(self, player)
	elif event.is_action_pressed("party_order"):
		hud.toast("Companions: " + str(Gunman.toggle_party_order(get_tree())))
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ENTER and not player.alive:
		get_tree().reload_current_scene()


# ---------------------------------------------------------------- the act

func _descend() -> void:
	step = Step.DESCEND
	hud.show_message("BELOW AKMENTAR", "The air is cold and old. Somewhere ahead, the royal tomb.")
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
			SiteSpot.make(level, "akmentar_below", AkmentarBelow.SITE_IDS[id], level.pois[id])
	hud.toast("Level 2: you can study %d places before the royal door (%s)" % [budget,
		"your allies insist on two of them" if ally != "" else "choose well"], 4.0)
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
	level._nav.bake_navigation_mesh(false)
	_tomb()


func _door_traps() -> void:
	# -bf's TombTrap: darts from the side walls, then ceiling blocks, in front of the door.
	var ts := _ready_script("res://scripts/tomb_trap.gd", "spring")
	if ts:
		var at := Vector3(level.royal_door.global_position.x, AkmentarBelow.FLOOR_Y, level.royal_door.global_position.z + 0.5)
		ts.spring(self, Transform3D(Basis(Vector3.UP, PI), at), [])
		return
	for i in 6:
		var at := level.royal_door.global_position + Vector3(randf_range(-3, 3), 3.5, randf_range(0.5, 3.0))
		Fx.impact(self, at - Vector3.UP * 3.4, Vector3.UP, Fx.Kind.STONE)
		Sfx.play_at(self, Sfx.impact(), at, 6.0)
		await get_tree().create_timer(0.25).timeout


func _tomb() -> void:
	step = Step.TOMB
	var allowed := 1 if Game.flag("german_delay", false) else 2
	Game.set_flag("tomb_allowed", allowed)
	hud.toast("The royal tomb of Akmentar", 3.0)
	if FileAccess.file_exists(TOMB_SITES):
		# Rebuilt now: the door (german_delay) changes the tomb's slots and its cut.
		SiteBudget.begin("royal_tomb", SiteSpot.load_area("royal_tomb"), true)
		for id in level.royal_pois:
			_tomb_spots[id] = SiteSpot.make(level, "royal_tomb", AkmentarBelow.SITE_IDS[id], level.royal_pois[id])
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
	for p in level.minion_spawns:
		var mm := Mummy.new()
		add_child(mm)
		mm.global_position = p
		mm.target = player
		mm.wake()
	_escape()


func _escape() -> void:
	step = Step.ESCAPE
	hud.toast("RUN. Back to the stairs!", 3.0)
	# Companions run with you (-bf's escape mode); one of them goes down partway (help or leave).
	var i := 0
	for c in companions.values():
		if is_instance_valid(c):
			c.escape = true
			if args.has("auto"):  # the bot teleported through the tomb: bring them along
				c.global_position = player.global_position + Vector3(i * 1.2 - 0.6, 0, 1.5)
				i += 1
	_ally_run()
	if not companions.is_empty():
		get_tree().create_timer(14.0).timeout.connect(func():
			var c: Gunman = companions.values()[0]
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
	level._nav.bake_navigation_mesh(false)  # paths round the rubble (or vault it)
	_arm_slabs()
	if args.has("auto"):
		_auto_escape()
	var out := -1
	while out < 0:
		if not player.alive:
			return
		await get_tree().create_timer(0.2).timeout
		out = _exit_reached(player)
	level.stair_top = level.exits[out]  # the revelation happens where you came up
	_guardian_turns_back()
	Game.set_flag("escaped", true)
	Game.set_flag("escape_exit", ["main", "west", "east"][out])
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
	while step == Step.ESCAPE or step == Step.AWAKENING:
		var path := PackedVector3Array()
		var best := INF
		for e in level.exits:
			var p := NavigationServer3D.map_get_path(map, runner.global_position, e + Vector3(0, 0, 1.0), true)
			var len := 0.0
			for k in range(1, p.size()):
				len += p[k].distance_to(p[k - 1])
			if p.size() > 1 and len < best:
				best = len
				path = p
		if path.size() < 2 or best < 1.5:
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
				hud.toast("Fallen stone: run round the gap, or E to take cover against it, then W+E to vault.", 4.0)
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
		s.shut.connect(func(): level._nav.bake_navigation_mesh(false))
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
	for m in get_tree().get_nodes_in_group("mummies"):
		if is_instance_valid(m) and m != guardian:
			(m as Node).queue_free()


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
	return _exit_reached(c) >= 0 or (c.global_position.y > -3.0 and c.global_position.distance_to(player.global_position) < 8.0)


## At the top: a few seconds for the companions still coming; whoever isn't out by then (cut off
## behind a slab, caught, lost in the dark) is a casualty.
func _wait_for_companions() -> void:
	var t := 0.0
	var waiting := true
	while waiting and t < WAIT_AT_TOP:
		waiting = false
		for c in companions.values():
			if is_instance_valid(c) and c.alive and not _out(c):
				waiting = true
		if waiting:
			if t == 0.0:
				hud.toast("You wait at the top, listening for footsteps...", 3.0)
			await get_tree().create_timer(0.5).timeout
			t += 0.5
	var lost: Array = []
	for id in companions:
		var c: Gunman = companions[id]
		if not is_instance_valid(c) or not c.alive or not _out(c):
			lost.append(id)
	Game.set_flag("act5_casualties", lost)
	if not lost.is_empty():
		hud.toast("%s didn't come out." % ", ".join(lost.map(func(id): return str(id).capitalize())), 4.0)


func _revelation() -> void:
	step = Step.REVELATION
	var ally: String = Game.flag("ally", "")
	var thieves: String = ally if ally != "" else "italians"
	Game.set_flag("thieves", thieves)
	Game.set_flag("thieves_" + thieves)  # plain flag the revelation talk can test
	hud.toast("Daylight, and men in indigo all around you.", 3.0)
	_rashad = Npc.make(self, "rashad", level.stair_top + Vector3(0, 0, 3.0), "act5_revelation", Characters.glb("rashad"))
	await get_tree().create_timer(2.0).timeout
	if FileAccess.file_exists("res://dialogue/act5_revelation.json") and not args.has("auto"):
		var c := Conversation.new()
		add_child(c)
		c.start("act5_revelation", player, _rashad if _rashad else player)
		await c.finished
	_end()


func _end() -> void:
	step = Step.END
	Game.place = "act5_end"
	Game.save_game()
	var lines := ["The guardian is awake.", "The amulet is gone: the %s took it." % str(Game.flag("thieves", "")).capitalize(),
		"The Keepers want it back, and so must you."]
	hud.show_message("THE AWAKENING", "\n".join(lines) + "\n\n(Act 6 comes next.)")
	print("RESULT act5 end ally=%s forced=%s delay=%s studied_tomb=%d escaped=%s exit=%s lost=%s fled=%s thieves=%s t=%.0f" % [
		Game.flag("ally", ""), Game.flag("door_forced", false), Game.flag("german_delay", false), _tomb_done,
		Game.flag("escaped", false), Game.flag("escape_exit", ""), Game.flag("act5_casualties", []), Game.flag("thieves_fled", false),
		Game.flag("thieves", ""), _t])
	if args.has("auto"):
		await get_tree().create_timer(1.5).timeout
		get_tree().quit(0)


func _spawn_party() -> void:
	var i := 0
	for id in Game.party():
		var c := Gunman.make_companion(id, player, Characters.glb(id))
		if c:
			add_child(c)
			c.global_position = player.global_position + Vector3(i * 1.4 - 0.7, 0, 2.5)
			companions[id] = c
			i += 1


# ---------------------------------------------------------------- test bot

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
	player.global_position = _door_spot.global_position + Vector3(0, 0, 1.0)
	player.yaw = 0.0
	await get_tree().create_timer(0.5).timeout
	_door_spot.use(player)


func _auto_tomb() -> void:
	await get_tree().create_timer(1.0).timeout
	for id in ["1", "2", "3"]:
		player.global_position = level.royal_pois[id] + Vector3(0, 0, 2.0)
		await get_tree().create_timer(0.6).timeout
		if _tomb_spots.has(id):
			(_tomb_spots[id] as SiteSpot).interactable.use(player)
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
const VIEWS := {"bridge": [20, 13, 0.0, -0.45], "pit": [24, 13, 0.0, 0.4], "ramp": [23, 9, -PI / 2, 0.15],
	"secret": [21, 40, PI / 2, -0.1], "secret2": [34, 21, PI / 2, -0.05], "deadend": [13, 31, 0.0, -0.1],
	"hall": [18, 40, 0.0, -0.05], "hub": [19, 24, 0.0, -0.05], "walkway": [27, 26, -PI / 2, -0.35],
	"deep": [30, 30, 0.3, 0.45], "sarc": [6, 22, -0.3, -0.25], "jars": [3, 18, 0.0, -0.5], "amulet": [3, 29, 0.0, -0.6]}


func _view(name: String) -> void:
	await get_tree().create_timer(4.0).timeout
	var v: Array = VIEWS.get(name, VIEWS.bridge)
	player.global_position = level._cell(v[0], v[1]) + Vector3.UP * 0.3
	player.yaw = v[2]
	player.pitch = v[3]
	var i := 0
	for c in companions.values():
		(c as Node3D).global_position = player.global_position + Basis(Vector3.UP, v[2]) * Vector3(i * 0.9 - 0.45, 0, 2.0)
		i += 1
	await get_tree().create_timer(2.5).timeout
	await _shot("act5_view_%s.png" % name)
	get_tree().quit(0)


## Test: --holes. Every walkable cell, at its centre and near its corners: something solid to land
## on within 7 m below the upper floor (the deep halls' floors are 5 m down). Prints each hole.
func _scan_holes() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	var space := get_world_3d().direct_space_state
	var holes := 0
	for r in AkmentarBelow.H:
		for c in AkmentarBelow.W:
			var ch := level._ch(r, c)
			if ch in ["#", "L", "D", "?"]:
				continue
			var p := level._cell(r, c)
			for off in [Vector2.ZERO, Vector2(0.8, 0.8), Vector2(-0.8, 0.8), Vector2(0.8, -0.8), Vector2(-0.8, -0.8)]:
				var from := Vector3(p.x + off.x, AkmentarBelow.FLOOR_Y + 1.5, p.z + off.y)
				var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 8.5, 1))
				if hit.is_empty():
					holes += 1
					print("RESULT hole r=%d c=%d ch=%s at=%s" % [r, c, ch, from])
	print("RESULT holes=%d" % holes)
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


func _auto_escape() -> void:
	if args.has("help"):
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
		var next: Vector3 = path[1] if path.size() > 1 else level.stair_top
		var d := next - player.global_position
		# A minion in the way: stop and shoot it.
		var block: Mummy = null
		for m in get_tree().get_nodes_in_group("mummies"):
			var mm := m as Mummy
			if mm and mm.is_active() and mm.global_position.distance_to(player.global_position) < 7.0 and mm != guardian:
				var seen := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(
					player.camera.global_position, mm.global_position + Vector3.UP * 1.2, 1)).is_empty()
				if seen:
					block = mm
					break
		if block:
			var aim := block.global_position + Vector3.UP * 1.3 - player.camera.global_position
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
