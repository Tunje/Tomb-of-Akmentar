extends Node3D
## Act 7: Cairo under the countdown. Back in the city with the thieves about to leave and the
## mummy days behind, on -7f's Cairo map with -f9's data (actions/act7_plan.json,
## actions/act7_<spot>.json, dialogue/act7_*.json). Three actions a day at the ActionSpots; the
## hotel room saves and ends the day, which ticks both countdowns (Game.end_day).
## - The mummy countdown brings the signs (plan "signs"): dust, the sky going dark (sky_dark),
##   stones falling (stones_falling: debris drops round you), the sickness (the streets empty),
##   and at 0 mummy_in_cairo: catastrophe, game over, unless the artifacts are already yours.
## - Hassan, if he came, talks first (act7_hassan).
## - The confrontation (act7_intercept) appears once you know where to catch them: the road gate
##   under the lockdown, else where their plan takes them (docks / station / police yard by
##   thief), else their lodging (the hotel). It moves if you learn something better.
## - act7_confront either recovers the artifacts or fires fight_thieves (their guards come at you;
##   win and artifacts_recovered is set). Either way act7_recovered follows; then Blackwood waits
##   at the bank (data-gated) and the hotel bed takes you on to Act 8.
## - The thieves countdown at 0 before that: act7_too_late (thieves_escaped), then Act 8.
## Test args (after --): --auto[=intercept|late|mummy] (a bot; RESULT lines), --resume (at game over,
## load the last save the way Enter does), --chain (on into Act 8), --plan=fight|talk (the bot at
## the confrontation; talks are played by BotTalk), --thieves=americans|
## germans|italians, --seconds=N, --shots=t1,t2, --shot-dir=path.

static var _bot_resumed := false  # --resume: the bot loads the save once, then stops

const PLAN := "res://actions/act7_plan.json"
const NEXT_ACT := ["res://act8.tscn"]  # the first that exists
## If the act is started on its own (start screen, tests), the countdowns Act 6 would have left.
const THIEVES_START := 4
const MUMMY_START := 6
const THIEVES := ["americans", "germans", "italians"]
## Who guards each crew's getaway (Characters ids; anyone missing gets the stand-in).
const GUARD_HP := 130.0  # hired guns, harder to put down than Act 3's bandits (tests/difficulty_test)
const GUARDS := {"americans": ["callahan", "maggie", "callahan"], "germans": ["vogel", "kruger", "vogel"],
	"italians": ["bellini", "bellini", "bellini"]}
## How full the streets stay at each sign (the crowds thin as the curse grows).
const CROWD := {"dust": 1.0, "sky_dark": 0.5, "stones_falling": 0.25, "sickness": 0.0}

var level: Cairo
var player: Player
var hud: Hud
var args := {}
var plan := {}
var companions := {}
var intercept: ActionSpot
var guards: Array[Gunman] = []
var _intercept_at := ""
var _fighting := false
var _recovering := false
var _may_leave := false     # recovered (or too late): the hotel bed goes on to Act 8
var _over := false          # the mummy reached the city
var _done := false
var _curse_tween: Tween
var _stone_t := 2.0
var _t := 0.0
var _shots: Array[float] = []
var _city_bark := 0.0


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
	Game.act = 7
	if not Game.flag("act7_started", false):
		Game.set_flag("act7_started")
		if not Game.countdowns.has("thieves"):
			Game.apply([{"countdown": ["thieves", THIEVES_START]}])
		if not Game.countdowns.has("mummy"):
			Game.apply([{"countdown": ["mummy", MUMMY_START]}])
	if args.has("thieves"):
		for t in THIEVES:
			Game.flags.erase("thieves_" + t)
		Game.set_flag("thieves_" + str(args.thieves))
	elif _thief() == "":
		Game.set_flag("thieves_americans")  # nobody said who stole them (a test start)
	level = Cairo.new()
	add_child(level)
	Ambience.play(self, "cairo")
	level.set_day_time(Cairo.day_time_for(Game.actions_left, Game.ACTIONS_PER_DAY))
	level.place_people({}, (plan.get("hosts", {}) as Dictionary).values())
	_place_spots()
	player = Player.new()
	add_child(player)
	player.global_position = level.player_spawn
	player.set_armed(false)
	player.yaw = -PI * 0.5  # east down the avenue, under the sky the curse is darkening
	hud = Hud.new()
	hud.player = player
	add_child(hud)
	add_child(CountdownBars.new())
	player.hit_confirmed.connect(hud.on_hit)
	player.damaged.connect(hud.on_damaged)
	player.died.connect(func(): hud.show_message("YOU DIED", "Enter  load the last save"))
	for s in str(args.get("shots", "")).split(",", false):
		_shots.append(float(s))
	if str(Game.place).begins_with("act7_"):
		DayLog.ensure()  # resuming a save made here: keep the day's log
	else:
		DayLog.begin_day()
	_sync_party()
	_update_signs(true)
	_place_intercept()
	Game.changed.connect(_on_changed)
	Game.event.connect(_on_event)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if args.size() > 0 else Input.MOUSE_MODE_CAPTURED
	hud.show_message("CAIRO, UNDER THE CURSE", Cairo.countdown_line())
	await get_tree().create_timer(3.0).timeout
	hud.show_message("")
	var worst := ""  # the stage the city is at already, now the title has gone
	for s: Dictionary in plan.get("signs", []):
		if Game.flag(str(s.get("flag", "")), false) and str(s.get("flag", "")) != "mummy_in_cairo":
			worst = str(s.get("text", "")).split(": ", true, 1)[-1]
	if worst != "":
		hud.toast(worst, 5.0)
	if Game.in_party("hassan") and not Game.flag("act7_hassan_heard", false):
		Game.set_flag("act7_hassan_heard")
		print("RESULT act7 hassan_talk")
		await _talk("act7_hassan", companions.get("hassan", player))
	if args.has("auto"):
		_auto()


## Which crew has the artifacts ("" if no flag says).
func _thief() -> String:
	for t in THIEVES:
		if Game.flag("thieves_" + t, false):
			return t
	return ""


## Every place in the plan becomes an ActionSpot where Cairo put it; the hotel room ends the day.
func _place_spots() -> void:
	var spots: Dictionary = plan.get("spots", {})
	for id in spots:
		if not level.spots.has(id):
			push_warning("act7: no place for spot %s on the map" % id)
			continue
		ActionSpot.make(level, str(spots[id]), level.spots[id])
	var bed: Interactable = level.interactables.get("hotel_bed")
	if bed:
		bed.used.connect(func(_by): _sleep())


func _sleep() -> void:
	if DaySummary.current or _done or _over:
		return
	if _may_leave:
		_finish()
		return
	_save("hotel_bed")
	DaySummary.open(self, player)


func _on_changed(what: String) -> void:
	if what == "actions":
		level.ease_day_time(Cairo.day_time_for(Game.actions_left, Game.ACTIONS_PER_DAY))
	elif what == "day":
		level.set_day_time(0.0)
		_update_signs()
		_check_clocks()
	elif what.begins_with("countdown:"):
		_update_signs()
		_check_clocks()
	elif what in ["flag:lockdown", "flag:thieves_plan_known", "flag:thieves_lodging"]:
		_place_intercept()
	elif what == "flag:artifacts_recovered" and Game.flag("artifacts_recovered", false):
		_recovered()
	elif what.begins_with("companion:") or what == "party":
		_sync_party()


func _on_event(name: String) -> void:
	if name == "fight_thieves":
		_fight_thieves()


# ---------------------------------------------------------------- the curse

## Set the signs the mummy countdown has reached (each once, with its line), and show them.
func _update_signs(instant := false) -> void:
	var m := int(Game.countdowns.get("mummy", 99))
	for s: Dictionary in plan.get("signs", []):
		var f := str(s.get("flag", ""))
		if f == "" or Game.flag(f, false) or m > int(s.get("mummy_at_most", -1)):
			continue
		Game.set_flag(f)
		print("RESULT act7 sign %s (mummy %d)" % [f, m])
		if f != "mummy_in_cairo" and not instant:
			hud.toast(str(s.get("text", "")).split(": ", true, 1)[-1], 5.0)
			Barks.say_any(get_tree(), "act7_curse")  # a companion reacts to the new sign
	var crowd := 1.0
	for f in CROWD:
		if Game.flag(f, false):
			crowd = minf(crowd, CROWD[f])
	level.set_crowd(crowd)
	if Game.flag("sky_dark", false):
		Ambience.play(self, "curse", 6.0)  # the dark wind over the emptying streets
	var dust_f := 1.0 if Game.flag("dust", false) else 0.0
	var gloom_f := 0.0
	if Game.flag("sky_dark", false):
		gloom_f = 0.55
	if Game.flag("stones_falling", false):
		gloom_f = 0.75
	if Game.flag("sickness", false):
		gloom_f = 0.9
	if _curse_tween:
		_curse_tween.kill()
	if instant:
		level.set_curse(dust_f, gloom_f)
	else:
		_curse_tween = create_tween()
		_curse_tween.tween_method(func(k: float) -> void:
			level.set_curse(lerpf(level.dust, dust_f, k), lerpf(level.gloom, gloom_f, k)), 0.0, 1.0, 4.0)


## The two clocks: the mummy in the city ends it all; the thieves gone ends the hunt.
func _check_clocks() -> void:
	if _done or _over or _may_leave or Game.flag("artifacts_recovered", false):
		return
	if int(Game.countdowns.get("mummy", 99)) <= 0:
		_catastrophe()
	elif int(Game.countdowns.get("thieves", 99)) <= 0:
		_too_late()


func _catastrophe() -> void:
	_over = true
	Game.set_flag("mummy_in_cairo")
	level.set_curse(1.0, 1.0)
	level.set_crowd(0.0)
	print("RESULT act7 game_over mummy_in_cairo day=%d" % Game.day)
	hud.show_message("THE CITY OF THE DEAD", "He has reached Cairo, and the artifacts were never returned.\n\nEnter  load the last save")
	if args.has("auto"):
		await get_tree().create_timer(1.0).timeout
		if args.has("resume") and not _bot_resumed:
			_bot_resumed = true  # static: survives the scene change (a flag would go with the load)
			print("RESULT act7 resuming the last save")
			SaveRoute.resume(get_tree())
			return
		get_tree().quit(0)


func _too_late() -> void:
	_may_leave = true
	print("RESULT act7 too_late day=%d" % Game.day)
	if not await _talk("act7_too_late", player):
		Game.set_flag("thieves_escaped")  # (what the talk sets)
	_finish()


## Stones falling (stones_falling): every few seconds a stone drops near you, its shadow first.
func _drop_stone() -> void:
	var a := randf() * TAU
	var at := player.global_position + Vector3(cos(a), 0, sin(a)) * randf_range(1.5, 12.0)
	at.y = 0.0
	var shadow := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 0.7
	disc.bottom_radius = 0.7
	disc.height = 0.01
	shadow.mesh = disc
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color(0, 0, 0, 0.0)
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shadow.material_override = sm
	level.add_child(shadow)
	shadow.global_position = at + Vector3.UP * 0.03
	var tw := create_tween()
	tw.tween_property(sm, "albedo_color:a", 0.55, 0.9)
	await tw.finished
	var stone := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE * randf_range(0.35, 0.6)
	stone.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.35, 0.27, 0.2)
	stone.material_override = mat
	level.add_child(stone)
	stone.global_position = at + Vector3.UP * 22.0
	stone.rotation = Vector3(randf(), randf(), randf()) * TAU
	var fall := create_tween()
	fall.tween_property(stone, "global_position", at + Vector3.UP * bm.size.y * 0.5, 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await fall.finished
	shadow.queue_free()
	_puff(at)
	if player.alive and Vector2(player.global_position.x - at.x, player.global_position.z - at.z).length() < 1.3:
		player.take_damage(18.0, at + Vector3.UP)
		hud.toast("A stone from the sky!", 1.5)
	get_tree().create_timer(10.0).timeout.connect(stone.queue_free)


func _puff(at: Vector3) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.emitting = true
	p.amount = 24
	p.lifetime = 1.2
	p.explosiveness = 0.9
	p.direction = Vector3.UP
	p.spread = 70.0
	p.initial_velocity_min = 1.0
	p.initial_velocity_max = 3.0
	p.gravity = Vector3(0, -2.0, 0)
	p.scale_amount_min = 1.0
	p.scale_amount_max = 2.2
	var qm := QuadMesh.new()
	qm.size = Vector2(0.4, 0.4)
	var m := StandardMaterial3D.new()
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(0.6, 0.5, 0.36, 0.6)
	m.albedo_texture = Fx.soft_dot()
	qm.material = m
	p.mesh = qm
	level.add_child(p)
	p.global_position = at + Vector3.UP * 0.2
	get_tree().create_timer(2.0).timeout.connect(p.queue_free)


# ---------------------------------------------------------------- the thieves

## Where the confrontation is, from what you know (plan "intercept"); placed or moved there.
func _place_intercept() -> void:
	var at_plan: Dictionary = (plan.get("intercept", {}) as Dictionary).get("at", {})
	var where := ""
	if Game.flag("lockdown", false):
		where = str(at_plan.get("lockdown", "road_gate"))
	elif Game.flag("thieves_plan_known", false):
		where = str((at_plan.get("thieves_plan_known", {}) as Dictionary).get(_thief(), "hotel"))
	elif Game.flag("thieves_lodging", false):
		where = str(at_plan.get("thieves_lodging", "hotel"))
	if where == "" or where == _intercept_at or not level.spots.has(where):
		return
	_intercept_at = where
	var pos: Vector3 = level.spots[where]
	if (plan.get("spots", {}) as Dictionary).has(where):
		# That place has its own ActionSpot: stand this one a little along the facade.
		var n: Vector2 = Cairo.SPOTS[where][1]
		pos += Vector3(-n.y, 0, n.x) * 2.5 if n != Vector2.ZERO else Vector3(0, 0, 2.0)
	if intercept == null:
		var file := str((plan.get("intercept", {}) as Dictionary).get("file", "act7_intercept"))
		intercept = ActionSpot.make(level, file, pos)
	else:
		intercept.global_position = pos
	print("RESULT act7 intercept at %s" % where)
	hud.toast("You know where to catch the thieves: %s." % str(Cairo.SPOTS[where][2]).to_lower(), 4.0)


## A guard's spot must be a short walk from the meeting place, or nobody can get at anybody.
static func _walkable(map: RID, from: Vector3, to: Vector3) -> bool:
	var path := NavigationServer3D.map_get_path(map, NavigationServer3D.map_get_closest_point(map, from), to, true)
	if path.size() < 2 or path[path.size() - 1].distance_to(to) > 0.6:
		return false
	var length := 0.0
	for i in range(1, path.size()):
		length += path[i - 1].distance_to(path[i])
	return length < 14.0


func _in_view(from: Vector3, to: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(from + Vector3.UP * 1.4, to + Vector3.UP * 1.4, 1)
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()


## The talk turned to guns: their guards come at you round the meeting place.
func _fight_thieves() -> void:
	if _fighting:
		return
	_fighting = true
	player.set_armed(true)
	hud.toast("They go for their guns.", 2.5)
	var centre: Vector3 = intercept.global_position if intercept else player.global_position
	var map := get_world_3d().navigation_map
	var ids: Array = GUARDS.get(_thief(), GUARDS.americans)
	var placed := 0
	for k in 36:  # 12 round at 8 m, then 12 m, then 16 m: a dead end like the road gate has few spots close
		if placed >= ids.size():
			break
		var a := TAU * (k % 12) / 12.0 + (k / 12) * 0.26
		var want := centre + Vector3(cos(a), 0, sin(a)) * (8.0 + 4.0 * (k / 12))
		var on := NavigationServer3D.map_get_closest_point(map, want)
		if Vector2(on.x - want.x, on.z - want.z).length() > 0.6:
			continue  # inside a building
		if not _walkable(map, centre, on) or not _in_view(centre, on):
			continue  # behind a wall from the meeting place (the road gate: outside it; its leaf isn't in the navmesh)
		var g := Gunman.new()
		g.team = Gunman.BANDITS
		g.glb = Characters.glb(ids[placed])
		add_child(g)
		g.global_position = on
		g.max_health = GUARD_HP
		g.health = GUARD_HP
		g.target = player
		guards.append(g)
		placed += 1
	print("RESULT act7 fight guards=%d at %s" % [guards.size(), _intercept_at])
	while true:
		await get_tree().create_timer(0.5).timeout
		var standing := 0
		for g in guards:
			standing += int(is_instance_valid(g) and g.is_active() and not g.surrendered)
		if standing == 0 or not player.alive:
			break
	if not player.alive:
		return
	player.set_armed(false)
	Game.set_flag("artifacts_recovered")  # -> _recovered


## The artifacts are yours (peacefully or not): the Keepers' messenger, then Blackwood and Act 8.
func _recovered() -> void:
	if _recovering:
		return
	_recovering = true
	while Conversation.current:  # the confrontation's own end first
		await get_tree().process_frame
	if not await _talk("act7_recovered", player):  # no talk file: what it would have set
		Game.apply([{"set_flag": ["new_objective", "return_artifacts"]}, {"set_flag": "act7_done"}])
	_may_leave = true
	_save("recovered")
	print("RESULT act7 recovered peaceful=%s" % Game.flag("recovered_peacefully", false))
	hud.toast("The artifacts are yours. Sir Reginald waits at the bank; the hotel bed takes you on.", 6.0)


## A talk, played by the player or (--auto) by BotTalk, which steers clear of `avoid`. False if
## the talk file is missing (the caller then applies its effects by hand).
func _talk(id: String, with: Node3D, avoid: Array = BotTalk.AVOID) -> bool:
	if not FileAccess.file_exists("res://dialogue/%s.json" % id):
		return false
	if args.has("auto"):
		await BotTalk.run(self, id, player, with, avoid)
		return true
	var c := Conversation.new()
	add_child(c)
	c.start(id, player, with if with else player)
	await c.finished
	return true


## Out of Cairo: the tally, and Enter goes on to Act 8.
func _finish() -> void:
	if _done:
		return
	_done = true
	Game.place = "act7_end"
	Game.save_game(_slot())
	var got: bool = Game.flag("artifacts_recovered", false)
	print("RESULT act7 end day=%d recovered=%s escaped=%s done=%s objective=%s thieves=%d mummy=%d" % [Game.day, got,
		Game.flag("thieves_escaped", false), Game.flag("act7_done", false), Game.flag("new_objective", ""),
		int(Game.countdowns.get("thieves", 0)), int(Game.countdowns.get("mummy", 0))])
	hud.show_message("LEAVING CAIRO", ("You have the jars and the amulet. %d days before he reaches the city." if got
		else "The thieves are gone with the artifacts. He is %d days from the city.") % int(Game.countdowns.get("mummy", 0))
		+ "\n\nEnter  on to Act 8")
	if args.has("auto"):
		await get_tree().create_timer(1.0).timeout
		if args.has("chain") and ResourceLoader.exists(NEXT_ACT[0]):
			get_tree().change_scene_to_file(NEXT_ACT[0])  # --chain: on into Act 8
		else:
			get_tree().quit(0)


# ---------------------------------------------------------------- the party

func _sync_party() -> void:
	for id in Game.party():
		if companions.has(id):
			continue
		var c := Gunman.make_companion(id, player, Characters.glb(id))
		if c == null:
			continue
		add_child(c)
		# Out to the sides, a step ahead: never behind you in the camera's lens.
		var i := companions.size()
		c.global_position = player.global_position + Vector3((1.0 if i % 2 == 0 else -1.0) * (2.4 + (i / 2) * 1.2), 0, -1.0).rotated(Vector3.UP, player.yaw)
		companions[id] = c


func _unhandled_input(event: InputEvent) -> void:
	if args.size() > 0:
		return
	var enter: bool = event is InputEventKey and event.pressed and event.keycode in [KEY_ENTER, KEY_KP_ENTER]
	if _done and enter:
		for s in NEXT_ACT:
			if ResourceLoader.exists(s):
				get_tree().change_scene_to_file(s)
				return
		hud.show_message("THE END OF ACT 7", "Act 8 isn't built yet.")
	elif (_over or not player.alive) and enter:
		SaveRoute.resume(get_tree())  # the last save, wherever it resumes
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
	Game.place = "act7_" + where
	Game.set_flag("player_health", player.health)
	if Game.save_game(_slot()):
		hud.toast("Game saved")


# ---------------------------------------------------------------- frame, test bot

func _process(delta: float) -> void:
	_t += delta
	if _t - _city_bark > 40.0 and not _over and not _done:  # a companion's word now and then in the streets
		_city_bark = _t
		Barks.say_any(get_tree(), "idle_city", player.global_position)
	if Game.flag("stones_falling", false) and not _over and not _done and not get_tree().paused:
		_stone_t -= delta
		if _stone_t <= 0.0:
			_stone_t = randf_range(1.5, 4.0)
			_drop_stone()
	if _shots.size() > 0 and _t >= _shots[0]:
		_shots.pop_front()
		_shot("act7_%05.1f.png" % _t)
	if args.has("seconds") and _t > float(args.seconds):
		print("RESULT act7 timeout day=%d" % Game.day)
		get_tree().quit(1)


func _shot(file: String) -> void:
	await RenderingServer.frame_post_draw
	if DisplayServer.get_name() == "headless":
		return
	var dir: String = args.get("shot-dir", "user://shots")
	DirAccess.make_dir_recursive_absolute(dir)
	get_viewport().get_texture().get_image().save_png(dir.path_join(file))
	print("RESULT shot %s" % dir.path_join(file))


## --auto=intercept (default): learn their plan, then the lockdown, fight the guards, recover.
## --auto=late: sleep until the thieves are gone.  --auto=mummy: sleep until he arrives.
func _auto() -> void:
	var mode := str(args.get("auto", "true"))
	print("RESULT act7 start thief=%s thieves=%d mummy=%d spots=%d npcs=%d" % [_thief(),
		int(Game.countdowns.get("thieves", 0)), int(Game.countdowns.get("mummy", 0)),
		get_tree().get_nodes_in_group("interactable").size(), level.npcs.size()])
	if mode == "late" or mode == "mummy":
		if mode == "mummy":
			Game.countdowns["thieves"] = 9
			Game.countdowns["mummy"] = 3
		for d in 12:
			_sleep()
			await get_tree().create_timer(0.4).timeout
			if DaySummary.current:
				DaySummary.current._close()
			await get_tree().create_timer(0.6).timeout
			if _done or _over:
				return
		print("RESULT act7 FAIL the days ran on")
		get_tree().quit(1)
		return
	Game.set_flag("thieves_plan_known")
	await get_tree().create_timer(0.5).timeout
	Game.set_flag("lockdown")
	await get_tree().create_timer(0.5).timeout
	print("RESULT act7 intercept_ok=%s" % (_intercept_at == "road_gate"))
	# The confrontation as the player would have it: --plan=talk lets the bot try the peaceful ways,
	# otherwise it steers to the fight.
	var peace := ["Appeal to Sofia", "Appeal to Vogel", "Buy them back", "Pay him", "Point at the sky"]
	var avoid: Array = BotTalk.AVOID + ([] if args.get("plan", "fight") == "talk" else peace)
	if not await _talk("act7_confront", player, avoid):
		Game.apply([{"event": "fight_thieves"}])
	await get_tree().create_timer(1.0).timeout
	if args.has("skill-bot"):  # tests/difficulty_test fights them: wait it out
		while player.alive and not Game.flag("artifacts_recovered", false):
			await get_tree().create_timer(0.5).timeout
	for g in guards:
		if is_instance_valid(g):
			g.take_damage(1000.0, player.global_position)
	for i in 20:
		await get_tree().create_timer(0.5).timeout
		if _may_leave:
			break
	_sleep()  # recovered: the bed takes you on


## Test runs save to their own slot, never over the game Simon is playing.
func _slot() -> String:
	return "test" if args.size() > 0 else "main"
