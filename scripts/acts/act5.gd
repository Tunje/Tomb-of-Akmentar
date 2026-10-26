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
	for c in companions.values():
		if is_instance_valid(c):
			c.escape = true
	if not companions.is_empty():
		get_tree().create_timer(14.0).timeout.connect(func():
			var c: Gunman = companions.values()[0]
			if is_instance_valid(c) and c.alive and step == Step.ESCAPE:
				c.stumble())
	# Collapsed sections along the way: low rubble to vault.
	for c in level.collapse_points:
		var size := Vector3(3.6, 1.0, 0.8)
		var rubble := level._box(level._nav, c + Vector3.UP * 0.5, size, level._stone)
		level._mark_cover(rubble, size)
	level._nav.bake_navigation_mesh(false)  # paths round the rubble (or vault it)
	if args.has("auto"):
		_auto_escape()
	while player.global_position.z < level.stair_top.z - 2.0 or player.global_position.y < -1.0:
		if not player.alive:
			return
		await get_tree().create_timer(0.2).timeout
	Game.set_flag("escaped", true)
	_revelation()


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
	print("RESULT act5 end ally=%s forced=%s delay=%s studied_tomb=%d escaped=%s thieves=%s health=%d" % [
		Game.flag("ally", ""), Game.flag("door_forced", false), Game.flag("german_delay", false), _tomb_done,
		Game.flag("escaped", false), Game.flag("thieves", ""), int(player.health)])
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
		print("RESULT act5 timeout step=%s" % Step.keys()[step])
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
	"secret": [21, 35, PI / 2, -0.1], "secret2": [34, 21, PI / 2, -0.05], "deadend": [19, 23, PI, -0.1]}


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


func _auto_step_back() -> void:
	var away := player.global_position - level.royal_door.global_position
	player.yaw = atan2(-away.x, -away.z)
	Input.action_press("move_forward")
	await get_tree().create_timer(2.4).timeout
	Input.action_release("move_forward")


func _auto_escape() -> void:
	while step == Step.ESCAPE and player.alive:
		var path := NavigationServer3D.map_get_path(get_world_3d().navigation_map, player.global_position,
			level.stair_top + Vector3(0, 0, -1.0), true)
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
