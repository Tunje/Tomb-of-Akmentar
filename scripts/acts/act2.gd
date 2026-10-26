extends Node3D
## Act 2: Cairo. Two days of actions (Game.ACTIONS_PER_DAY each) to recruit the expedition, buy
## its kit and learn what you can, on -7f's Cairo map (scripts/acts/cairo.gd) with -f9's data
## (actions/act2_plan.json, actions/act2_<spot>.json, dialogue/act2_*.json).
## Each named place is an ActionSpot (E: a menu of actions, each costing actions and money); the
## spot's host and the recruits stand at their places. Hired people join and follow you. The hotel
## room saves and ends the day (DaySummary). After the last day you leave Cairo: if no Egyptologist
## was hired Hassan offers to come for free (act2_hassan_fallback), then the summary and on to Act 3.
## Events from the talks: fight_bounty_hunters (Isabelle's trouble, three gunmen at the tavern) and
## fight_museum_guards (threatening the archivist).
## Test args (after --): --auto (the bot sleeps through the days; RESULT lines), --seconds=N, --shots=..

const PLAN := "res://actions/act2_plan.json"
const NEXT_ACT := ["res://act3_desert.tscn", "res://act4.tscn"]  # the first that exists

var level: Cairo
var player: Player
var hud: Hud
var args := {}
var plan := {}
var companions := {}
var _start_day := 1
var _leaving := false
var _done := false
var _t := 0.0
var _shots: Array[float] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	child_entered_tree.connect(func(n: Node):
		if n.process_mode == Node.PROCESS_MODE_INHERIT:
			n.process_mode = Node.PROCESS_MODE_PAUSABLE)
	Controls.setup()
	args = TestDriver.parse_args()
	if args.size() > 0:
		get_window().set_flag(Window.FLAG_NO_FOCUS, true)
	plan = JSON.parse_string(FileAccess.get_file_as_string(PLAN)) if FileAccess.file_exists(PLAN) else {}
	Game.act = 2
	if not Game.flag("act2_started", false):
		Game.set_flag("act2_started")
		Game.set_flag("act2_start_day", Game.day)
		Game.apply(plan.get("start", []))
	_start_day = int(Game.flag("act2_start_day", Game.day))
	level = Cairo.new()
	add_child(level)
	level.set_night(0.0)
	level.place_people()
	_place_spots()
	player = Player.new()
	add_child(player)
	player.global_position = level.player_spawn
	player.set_armed(false)  # a city: the gun stays holstered until there's trouble
	hud = Hud.new()
	hud.player = player
	add_child(hud)
	add_child(CountdownBars.new())
	player.hit_confirmed.connect(hud.on_hit)
	player.damaged.connect(hud.on_damaged)
	player.died.connect(func(): hud.show_message("YOU DIED", "Enter to try again"))
	for s in str(args.get("shots", "")).split(",", false):
		_shots.append(float(s))
	DayLog.begin_day()
	_sync_party()
	Game.changed.connect(_on_changed)
	Game.event.connect(_on_event)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if args.size() > 0 else Input.MOUSE_MODE_CAPTURED
	hud.show_message("CAIRO, 1926", "%d days to raise an expedition. Money: £%d" % [int(plan.get("days", 2)), Game.money])
	await get_tree().create_timer(3.0).timeout
	hud.show_message("")
	if args.has("auto"):
		_auto()


## Every place in the plan becomes an ActionSpot where Cairo put it (its own plain prompt goes),
## and the hotel room saves and ends the day.
func _place_spots() -> void:
	var spots: Dictionary = plan.get("spots", {})
	for id in spots:
		if not level.spots.has(id):
			push_warning("act2: no place for spot %s on the map" % id)
			continue
		var old: Node = level.interactables.get(id)
		if old:
			old.queue_free()
		ActionSpot.make(level, str(spots[id]), level.spots[id])
	var bed: Interactable = level.interactables.get("hotel_bed")
	if bed:
		bed.used.connect(func(_by): _sleep())


func _sleep() -> void:
	if DaySummary.current or _leaving:
		return
	_save("hotel_bed")
	DaySummary.open(self, player)


func _on_changed(what: String) -> void:
	if what == "day" and Game.day >= _start_day + int(plan.get("days", 2)):
		_leave()
	elif what.begins_with("flag:hired_") or what == "party":
		_sync_party()


## Hired people join: a companion following the player for everyone in the party.
func _sync_party() -> void:
	for id in Game.party():
		if companions.has(id):
			continue
		var c := Gunman.make_companion(id, player, Characters.glb(id))
		if c == null:
			continue
		add_child(c)
		var npc: Node3D = level.npcs.get(id)
		c.global_position = npc.global_position if npc else player.global_position + Vector3(1.5, 0, 2.0)
		if npc:
			npc.queue_free()  # the standing figure becomes the follower
			level.npcs.erase(id)
		companions[id] = c


func _on_event(name: String) -> void:
	match name:
		"fight_bounty_hunters":
			_bounty_hunters()
		"fight_museum_guards":
			Game.set_flag("archivist_hostile")
			hud.toast("The museum guards throw you out into the street.", 3.0)


## Isabelle's trouble: three bounty men come for her at the tavern. Win, and she hears you out.
func _bounty_hunters() -> void:
	player.set_armed(true)
	hud.toast("Three men push into the tavern, guns out.", 3.0)
	var at: Vector3 = level.spots.get("tavern", player.global_position)
	var men: Array[Gunman] = []
	for i in 3:
		var g := Gunman.new()
		g.team = Gunman.BANDITS
		g.glb = Characters.glb("callahan" if i == 0 else "vogel")
		add_child(g)
		g.global_position = at + Vector3(-3.0 + i * 3.0, 0, 9.0)
		g.target = player
		men.append(g)
	while true:
		await get_tree().create_timer(0.5).timeout
		var standing := 0
		for g in men:
			standing += int(is_instance_valid(g) and g.is_active() and not g.surrendered)
		if standing == 0 or not player.alive:
			break
	if not player.alive:
		return
	Game.set_flag("isabelle_trouble_settled")
	player.set_armed(false)
	var isabelle: Node3D = level.npcs.get("isabelle")
	if FileAccess.file_exists("res://dialogue/act2_isabelle.json") and not args.has("auto"):
		var c := Conversation.new()
		add_child(c)
		c.start("act2_isabelle", player, isabelle if isabelle else player)


## The days are spent: Hassan's offer if no Egyptologist is coming, the tally, and on.
func _leave() -> void:
	if _leaving:
		return
	_leaving = true
	var egypt := false
	for f in ["hired_eleanor", "hired_pembroke", "hired_hassan"]:
		egypt = egypt or Game.flag(f, false)
	if not egypt and FileAccess.file_exists("res://dialogue/act2_hassan_fallback.json"):
		if args.has("auto"):
			Game.apply([{"recruit": "hassan"}, {"set_flag": "hired_hassan"}])
		else:
			var c := Conversation.new()
			add_child(c)
			c.start("act2_hassan_fallback", player, level.npcs.get("hassan", player))
			await c.finished
	_done = true
	Game.place = "act2_end"
	Game.save_game()
	var names: Array = Game.party().map(func(id): return str(id).capitalize())
	hud.show_message("LEAVING CAIRO", "With you: %s.\nMoney left: £%d.\n\nEnter  set out for Akmentar (Act 3)" % [
		", ".join(names) if not names.is_empty() else "nobody", Game.money])
	print("RESULT act2 end day=%d party=%s money=%d" % [Game.day, Game.party(), Game.money])
	if args.has("auto"):
		await get_tree().create_timer(1.0).timeout
		get_tree().quit(0)


func _unhandled_input(event: InputEvent) -> void:
	if args.size() > 0:
		return
	if _done and event is InputEventKey and event.pressed and event.keycode in [KEY_ENTER, KEY_KP_ENTER]:
		for s in NEXT_ACT:
			if ResourceLoader.exists(s):
				get_tree().change_scene_to_file(s)
				return
	elif event.is_action_pressed("journal"):
		JournalScreen.toggle(self, player)
	elif event.is_action_pressed("party_order"):
		hud.toast("Companions: " + str(Gunman.toggle_party_order(get_tree())))
	elif event.is_action_pressed("ui_cancel") and not ActionMenu.ui_open():
		get_tree().paused = not get_tree().paused
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if get_tree().paused else Input.MOUSE_MODE_CAPTURED
		hud.show_message("PAUSED" if get_tree().paused else "", "Click to resume · Q to quit" if get_tree().paused else "")
	elif event is InputEventKey and event.pressed and event.keycode == KEY_Q and get_tree().paused:
		get_tree().quit()


func _save(where: String) -> void:
	Game.place = "act2_" + where
	Game.set_flag("player_health", player.health)
	if Game.save_game():
		hud.toast("Game saved")


# ---------------------------------------------------------------- test bot

func _process(delta: float) -> void:
	_t += delta
	if _shots.size() > 0 and _t >= _shots[0]:
		_shots.pop_front()
		_shot("act2_%05.1f.png" % _t)
	if args.has("seconds") and _t > float(args.seconds):
		print("RESULT act2 timeout day=%d" % Game.day)
		get_tree().quit(1)


func _shot(file: String) -> void:
	await RenderingServer.frame_post_draw
	if DisplayServer.get_name() == "headless":
		return
	var dir: String = args.get("shot-dir", "user://shots")
	DirAccess.make_dir_recursive_absolute(dir)
	get_viewport().get_texture().get_image().save_png(dir.path_join(file))
	print("RESULT shot %s" % dir.path_join(file))


## Hire one recruit through his spot's talk effects directly, then sleep through the days.
func _auto() -> void:
	print("RESULT act2 start money=%d spots=%d npcs=%d" % [Game.money, get_tree().get_nodes_in_group("interactable").size(), level.npcs.size()])
	Game.apply([{"recruit": "mahmoud"}, {"set_flag": "hired_mahmoud"}])
	await get_tree().create_timer(1.0).timeout
	print("RESULT act2 party=%s followers=%d" % [Game.party(), companions.size()])
	for d in int(plan.get("days", 2)):
		_sleep()
		await get_tree().create_timer(0.5).timeout
		if DaySummary.current:
			DaySummary.current._close()
		await get_tree().create_timer(0.5).timeout
