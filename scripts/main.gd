extends Node3D
## Game loop: start topside, go down into the tomb, mummies wake when they see
## or hear you, a sarcophagus wave in the burial chamber, every mummy dead = win.
## Test runs: pass args after "--", see TestDriver.

const WAVE_WHEN_LEFT := 1
const WAKE_RADIUS := 18.0  # gunfire
const SIGHT := 13.0

var level: Level
var player: Player
var hud: Hud
var mummies: Array[Mummy] = []  # live nodes only; corpses leave when they sink
var spawned := 0
var truck: Truck
var tourer: Truck
var boat: RiverBoat
var river_bank_z := INF
var brawlers: Array[Node] = []
var bandits: Array[Gunman] = []
var npcs := {}  # id -> Npc standing in the world
var companions := {}  # id -> Gunman on our side
const BANDIT_SIGHT := 28.0
var started := false
var over := false
var wave_done := false
var elapsed := 0.0
var _entered_burial := false
var _sight_t := 0.0


func _ready() -> void:
	# Main keeps listening while paused; everything it spawns pauses.
	process_mode = Node.PROCESS_MODE_ALWAYS
	child_entered_tree.connect(func(n: Node):
		if n.process_mode == Node.PROCESS_MODE_INHERIT:
			n.process_mode = Node.PROCESS_MODE_PAUSABLE)
	_setup_input()
	var args := TestDriver.parse_args()
	if args.has("chain") and not args.has("act"):  # the whole campaign from a new game (tests/soak_test)
		Game.reset()
		get_tree().change_scene_to_file.call_deferred("res://act1.tscn")
		return
	if args.get("act", "") in ["1", "2", "3", "4", "5", "6", "7", "8", "9"]:
		get_tree().change_scene_to_file.call_deferred("res://act%s.tscn" % args.act)
		return
	# Started as the game (no test args): the title screen, unless the title sent us here (its
	# Chapters > Playtest range, or Continue from a rest made in the range).
	var title_request := TitleScreen.take_request() if args.is_empty() else ""
	if args.is_empty() and title_request == "":
		get_tree().change_scene_to_file.call_deferred("res://title.tscn")
		return
	if args.has("explorer-glb"):
		ExplorerBody.glb_path = args["explorer-glb"]
	if args.has("mummy-glb"):
		MummyBody.glb_path = args["mummy-glb"]
	level = Level.new()
	add_child(level)
	player = Player.new()
	add_child(player)
	player.global_position = level.player_spawn
	player.yaw = 0.0  # look north, toward the tomb doorway
	hud = Hud.new()
	hud.player = player
	add_child(hud)
	add_child(CountdownBars.new())
	player.hit_confirmed.connect(hud.on_hit)
	player.damaged.connect(hud.on_damaged)
	player.died.connect(_on_player_died)
	player.fired.connect(_on_fired)
	for i in level.mummy_spawns.size():
		var p := level.mummy_spawns[i]
		var m := _spawn_mummy(i % 3 == 2)  # every third is a High Priest
		m.global_position = p
		m.rotation.y = randf() * TAU
	level.interactables["camp_fire"].used.connect(func(_by): _save_at("camp_fire"))
	level.interactables["camp_bed"].used.connect(func(_by): _sleep_at("camp_bed"))
	# A bandit ambush among the west ruins (Proving Ground step 6): they engage when you
	# come close or shoot near them.
	for i in 4:
		var g := Gunman.new()
		add_child(g)
		g.global_position = Vector3(9.0 + (i % 2) * 5.0, 0.0, 74.0 + i * 5.0)
		bandits.append(g)
	# Talking and actions (Proving Ground steps 3-4, -f9's systems): Eleanor by the camp,
	# a Cairo street stall (3 actions a day) and the camp's companion talks.
	var camp: Vector3 = level.interactables["camp_fire"].global_position
	Game.changed.connect(_on_game_changed)
	npcs["eleanor"] = Npc.make(level, "eleanor", camp + Vector3(-1.5, 0.0, -3.0), "eleanor_meet", Characters.glb("eleanor"))
	ActionSpot.make(level, "cairo_corner", level.player_spawn + Vector3(-3.0, 0.0, -6.0))
	ActionSpot.make(level, "camp", camp + Vector3(1.2, 0.0, -1.6))
	# Investigation (step 11): three statues near the tomb doorway, and a sealed slab that only
	# opens once the Statue of Anubis has been read. Stand-in pillars until real statues exist.
	var door_z: float = level.player_spawn.z - 12.0
	for s in [["anubis", Vector3(32.0, 0.0, door_z)], ["horus", Vector3(48.0, 0.0, door_z)], ["ra", Vector3(26.0, 0.0, door_z + 6.0)]]:
		level._box(level._nav, s[1] + Vector3.UP * 1.2, Vector3(0.9, 2.4, 0.9), level._stone)
		SiteSpot.make(level, "akmentar_surface", s[0], s[1] + Vector3(0.0, 0.0, 1.0))
	ClueDoor.make(level._nav, "anubis_door", Vector3(54.0, 1.25, door_z + 6.0), Vector3(2.4, 2.5, 0.5), "clue_anubis",
		"The slab won't move. Something carved on it matches a statue nearby.", "Pressed in the right order, the slab sinks into the sand.")
	# The river south of the camp (step 10): a pier from the bank and -f9's riverboat docked at it,
	# sailing west down a gentle S-bend. "Ring the bell" on board casts off.
	var bank: float = level.player_spawn.z + Level.SOUTH_EXTENT * 0.45  # = the tomb footprint + SOUTH_EXTENT
	level._box(level._nav, Vector3(40.0, -0.3, bank + 5.0), Vector3(4.0, 0.6, 10.0), level._floor_mat)
	RiverWater.make(level, Vector2(500.0, Level.RIVER_W), RiverBoat.WATER_Y, Vector3(40.0, RiverBoat.WATER_Y, bank + Level.RIVER_W * 0.5))
	var river := Path3D.new()
	river.curve = Curve3D.new()
	var cz := bank + 10.0 + RiverBoat.BEAM * 0.5 + 3.1  # the plank's end meets the pier's end
	for p in [Vector3(42.5, 0.0, cz), Vector3(10.0, 0.0, cz + 2.0), Vector3(-40.0, 0.0, cz + 8.0),
			Vector3(-90.0, 0.0, cz + 4.0), Vector3(-150.0, 0.0, cz + 10.0)]:
		river.curve.add_point(p)
	level.add_child(river)
	boat = RiverBoat.make(level, river, "steamer")
	# Falling in = back on deck, but only over the river: the tomb is below y = -1 too
	# (RiverBoat.watch checks height alone, which put tomb visitors on the boat).
	river_bank_z = bank
	# Horses by the camp (step 8, -f9's Horse): E "Ride"; W climbs walk, trot, gallop.
	Horse.make(level, "bay", camp + Vector3(-4.0, 0.0, 5.0))
	Horse.make(level, "grey", camp + Vector3(-6.5, 0.0, 5.5))
	# A brawl to try (step 7): three toughs loiter east of the camp; "Pick a fight" starts it.
	var brawl_at: Vector3 = camp + Vector3(14.0, 0.0, -2.0)  # east: well away from the bandit ruins
	var fight := Interactable.make(level, brawl_at + Vector3(0.0, 0.0, 3.0), "Pick a fight (brawl)", "brawl_start", 1.5)
	fight.used.connect(func(_by): _start_brawl(brawl_at))
	Game.event.connect(_on_game_event)
	# Props added above are inside the level's nav region: rebake so paths go round them.
	level._nav.bake_navigation_mesh(false)
	# A truck by the camp (Proving Ground step 9).
	truck = Truck.new()
	add_child(truck)
	truck.global_position = level.player_spawn + Vector3(-7.0, 0.6, 1.0)
	# The Cairo touring car beside it (image-to-3d's tourer, same driving code; right-hand drive).
	tourer = Truck.make_tourer()
	add_child(tourer)
	tourer.global_position = level.player_spawn + Vector3(-12.0, 0.6, 1.0)

	if args.size() > 0:
		# Test windows must never take Simon's keyboard or mouse while he plays.
		get_window().set_flag(Window.FLAG_NO_FOCUS, true)
		set_process_unhandled_input(false)
		player.set_process_unhandled_input(false)
		var d := TestDriver.new()
		d.args = args
		d.game = self
		add_child(d)
		_start(false)
	else:
		# From the title (TitleScreen): the range afresh, or a last rest made here.
		if title_request == "continue":
			_continue()
		else:
			Game.reset()
			DayLog.begin_day()
			_start()


## Rest at a campfire: save here.
func _save_at(spot: String) -> void:
	Game.place = spot
	Game.set_flag("player_health", player.health)
	Game.set_flag("ammo", player.ammo)
	if Game.save_game():
		SavePrompt.after_rest(self, hud)  # "Game saved", and a copy in a numbered slot if wanted


## Sleep: the next day starts, then save.
func _sleep_at(spot: String) -> void:
	# The day summary ends the day itself (-f9's DaySummary), then we save.
	DaySummary.open(self, player).closed.connect(func() -> void:
		hud.toast("Day %d" % Game.day)
		_save_at(spot))


func _continue() -> void:
	if not Game.load_game():
		return
	# A save made in an act goes back to that act (the end of one, into the next).
	var scene := SaveRoute.scene_for(Game.place)  # the one table of where each save resumes
	if scene != "":
		get_tree().change_scene_to_file(scene)
		return
	DayLog.ensure()  # the log is saved; begin_day would wipe it
	var spot: Node3D = level.interactables.get(Game.place)
	if spot:
		player.global_position = spot.global_position + Vector3(0, 0, 1.5)
	player.health = float(Game.flag("player_health", player.max_health))
	var saved_ammo: Variant = Game.flag("ammo", null)
	if saved_ammo is Array and saved_ammo.size() == player.ammo.size():
		for i in saved_ammo.size():
			player.ammo[i] = int(saved_ammo[i])
	_spawn_party()
	_start()
	hud.toast("Day %d" % Game.day)


func _spawn_mummy(priest := false) -> Mummy:
	var m := Mummy.new()
	m.priest = priest
	add_child(m)
	m.target = player
	m.killed.connect(_on_mummy_killed)
	m.tree_exiting.connect(func(): mummies.erase(m))
	mummies.append(m)
	spawned += 1
	return m


func _start(capture_mouse := true) -> void:
	started = true
	player.controls_enabled = true
	hud.allow_options = false  # in play: O works from the pause screen
	hud.show_message("")
	if capture_mouse:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if OptionsScreen.is_open() or LoadScreen.is_open() or SavePrompt.is_open():
		return  # its own keys (a number would start an act behind it)
	if event is InputEventMouseButton and event.pressed:
		if not started:
			Game.reset()
			DayLog.begin_day()
			_start()
		elif Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not over:
			get_tree().paused = false
			if not ActionMenu.ui_open():  # talking, menus and the day screen keep the mouse
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			hud.show_message("")
	elif event.is_action_pressed("party_order") and started and not over:
		var order: String = Gunman.toggle_party_order(get_tree())
		hud.toast("Companions: " + order)
	elif event.is_action_pressed("journal") and started and not over:
		JournalScreen.toggle(self, player)
	elif event is InputEventKey and event.pressed:
		# (Esc or Start: the pause menu, which Hud opens in every scene.)
		if event.keycode == KEY_Q and (not started or over):
			get_tree().quit()
		# Proving Ground: try the board screens (route map, site draft, epilogue).
		elif event.keycode == KEY_F2 and started and not over:
			RouteBoard.open(self, "act3_route", player)
		elif event.keycode == KEY_F3 and started and not over:
			SiteDraft.open(self, "akmentar_surface", player)
		elif event.keycode == KEY_F4 and started and not over:
			EpilogueShow.open(self, "akmentar", player)
		elif event.keycode in [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9] and not started:
			Game.reset()
			Game.set_flag("quickstart_act")  # started from the menu: the act fills in a default party
			get_tree().change_scene_to_file("res://act%d.tscn" % {KEY_1: 1, KEY_2: 2, KEY_3: 3, KEY_4: 4, KEY_5: 5, KEY_6: 6, KEY_7: 7, KEY_8: 8, KEY_9: 9}[event.keycode])
		elif event.keycode == KEY_C and not started and Game.has_save():
			_continue()
		elif event.keycode == KEY_ENTER and over:
			get_tree().paused = false
			get_tree().reload_current_scene()


func _process(delta: float) -> void:
	if boat and player.global_position.z > river_bank_z and player.global_position.y < RiverBoat.FALL_Y and player.vehicle == null:
		player.global_position = boat.to_global(boat.deck_spawn)  # fell in the river: back aboard
		player.velocity = Vector3.ZERO
	level.set_indoor(level.indoor_amount(player.camera.global_position))
	if not started or over or get_tree().paused:
		return
	elapsed += delta
	_sight_t -= delta
	if _sight_t <= 0.0:
		_sight_t = 0.25
		_wake_by_sight()
	if level.is_in_burial(player.global_position):
		_entered_burial = true
	var alive := alive_count()
	hud.remaining = alive + (0 if wave_done else level.sarcophagi.size())
	if _entered_burial and not wave_done and _alive_in_burial() <= WAVE_WHEN_LEFT:
		wave_done = true
		_sarcophagus_wave()
	if wave_done and alive == 0 and not over:
		_win()


func _alive_in_burial() -> int:
	var n := 0
	for m in mummies:
		if m.is_active() and level.is_in_burial(m.global_position):
			n += 1
	return n


## Bandits engage within BANDIT_SIGHT (or `any_range`, e.g. a shot nearby).
func _alert_bandits(any_range := 0.0) -> void:
	for g in bandits:
		if is_instance_valid(g) and g.target == null \
				and g.global_position.distance_to(player.global_position) < maxf(BANDIT_SIGHT, any_range):
			g.target = player


func _wake_by_sight() -> void:
	_alert_bandits()
	var eye := player.global_position + Vector3.UP * 1.5
	var space := get_world_3d().direct_space_state
	for m in mummies:
		if m.state != Mummy.State.DORMANT:
			continue
		var head := m.global_position + Vector3.UP * 1.5
		if head.distance_to(eye) > SIGHT:
			continue
		if space.intersect_ray(PhysicsRayQueryParameters3D.create(head, eye, 1)).is_empty():
			_wake_later(m, randf_range(0.0, 0.8))


func alive_count() -> int:
	var n := 0
	for m in mummies:
		if is_instance_valid(m) and m.is_active():
			n += 1
	return n


func _wake_later(m: Mummy, secs: float) -> void:
	get_tree().create_timer(secs).timeout.connect(func():
		if is_instance_valid(m):
			m.wake())


func _on_fired() -> void:
	_alert_bandits(45.0)
	# Gunfire carries in a tomb.
	for m in mummies:
		if is_instance_valid(m) and m.state == Mummy.State.DORMANT \
				and m.global_position.distance_to(player.global_position) < WAKE_RADIUS:
			_wake_later(m, randf_range(0.2, 1.0))


func _sarcophagus_wave() -> void:
	var i := 0
	for s in level.sarcophagi:
		var delay := 0.6 + i * 1.1
		i += 1
		get_tree().create_timer(delay).timeout.connect(func():
			if over:
				return
			var lid: Node3D = s.get_meta("lid")
			var dir: Vector3 = s.get_meta("open_dir")
			var tw := s.create_tween()
			tw.tween_property(lid, "position", lid.position + dir * 1.1 + Vector3.DOWN * 0.35, 0.6).set_trans(Tween.TRANS_QUAD)
			tw.parallel().tween_property(lid, "rotation", Vector3(dir.z * 0.4, 0, -dir.x * 0.4), 0.6)
			var m := _spawn_mummy(true)  # priests rise from the sarcophagi
			m.rise(s.global_position + Vector3.DOWN * 0.45, s.get_meta("exit")))


func _on_mummy_killed(_m: Mummy) -> void:
	pass


func _win() -> void:
	# Risers may still be on their way out of the sarcophagi.
	for m in mummies:
		if is_instance_valid(m) and m.state == Mummy.State.RISING:
			return
	if spawned < level.mummy_spawns.size() + level.sarcophagi.size():
		return
	over = true
	player.controls_enabled = false
	hud.show_message("TOMB CLEARED","Time %d:%02d · Health %d\n\nEnter to play again · Q to quit" % [int(elapsed) / 60, int(elapsed) % 60, int(player.health)])
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _on_player_died() -> void:
	over = true
	hud.show_message("YOU DIED", "Enter to try again · Q to quit")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _setup_input() -> void:
	Controls.setup()


# ---------------------------------------------------------------- companions

## Companion models until each has their own (image-to-3d makes one per person).
const COMPANION_GLB := {"eleanor": NpcBody.SCOUT}


## Everyone in the party fights at our side (on continue, and when someone is recruited).
func _spawn_party() -> void:
	var i := 0
	for id in Game.party():
		_spawn_companion(id, player.global_position + Vector3(i * 1.2 - 0.6, 0.0, 2.5))
		i += 1


func _spawn_companion(id: String, at: Vector3) -> void:
	if companions.has(id) and is_instance_valid(companions[id]):
		return
	var c := Gunman.make_companion(id, player, Characters.glb(id))
	if c == null:
		return
	add_child(c)
	c.global_position = at
	companions[id] = c
	# The standing NPC steps into the party: one Eleanor, not two.
	if npcs.has(id) and is_instance_valid(npcs[id]):
		npcs[id].queue_free()
		npcs.erase(id)


## Game.changed "companion:<id>": a recruit joins once their conversation has finished.
func _on_game_changed(what: String) -> void:
	if not what.begins_with("companion:"):
		return
	var id := what.trim_prefix("companion:")
	if not Game.in_party(id) or companions.has(id):
		return
	var at: Vector3 = npcs[id].global_position if npcs.has(id) and is_instance_valid(npcs[id]) else player.global_position + Vector3(0, 0, 2.5)
	if Conversation.current:
		await Conversation.current.finished
	_spawn_companion(id, at)


# ---------------------------------------------------------------- brawls

## Fists only: holster, raise the guard, three unarmed toughs (-bf's Brawler) close in.
func _start_brawl(at: Vector3) -> void:
	if player.melee.enabled:
		return
	player.set_armed(false)
	player.melee.enabled = true
	for i in 3:
		var b := Brawler.new()
		b.glb = GunmanBody.BANDITS[i]
		b.skill = 0.5
		b.max_hp = 70.0
		add_child(b)
		b.global_position = at + Vector3(cos(i * TAU / 3.0), 0.0, sin(i * TAU / 3.0)) * 3.0
		brawlers.append(b)
	hud.toast("Brawl! Left mouse punch · right mouse block · {shove} shove")


## Game events: the end of a brawl hands the fists back.
func _on_game_event(name: String) -> void:
	if name == "brawl_won" or name == "brawl_lost":
		player.melee.enabled = false
		player.melee.revive()
		hud.toast("You won the brawl" if name == "brawl_won" else "You were knocked out")
		# The fight is over either way: the toughs walk off (no beating a man who's down).
		for b in brawlers:
			if is_instance_valid(b):
				b.queue_free()
		brawlers.clear()
