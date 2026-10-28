extends Node3D
## Act 6: the race back to Cairo, with -f9's data (routes/act6_plan.json, routes/act6_return.json,
## dialogue/act6_*.json). KEEPERS -> BOARD -> ROAD -> ARRIVAL -> END.
## - Dawn at Akmentar (AkmentarSurface): Rashad and Bashir stay to hold the guardian
##   (act6_keepers), which sets the thieves and mummy countdowns.
## - enough_horses and trucks_running are worked out, then the return board (act6_return). Every
##   day travelled ticks the countdowns (RouteBoard -> Game.end_day). Desert without enough_horses:
##   the mummy catches you in the open, game over (event desert_return).
## - The road (DesertRoute as the backdrop, at night): the camp, act6_road (the thieves' trail if
##   they fled the same way), then ride on or hold: fight_mummy_servants brings the guardian's
##   servants out of the dark (Mummy enemies round the camp).
## - Arrival at Cairo's south gate in the dust (act6_arrival), then Enter goes to Act 7.
## Test args (after --): --auto[=coast|desert|nohorses] (a bot; RESULT lines), --plan=hold|ride,
## --party=a,b, --chain (the bot goes on into Act 7), --seconds=N, --shots=t1,t2, --shot-dir=path.

enum Step { KEEPERS, BOARD, ROAD, ARRIVAL, END, OVER }

const PLAN := "res://routes/act6_plan.json"
const NEXT_ACT := "res://act7.tscn"
const RIVALS := ["americans", "germans"]   # the expeditions that can lend horses (if alive)
const SERVANT_HP := 130.0                  # (mummy.gd: 100) at 100 the party shot them down unhurt (tests/difficulty_test)
const SERVANT_PACE := 1.5                  # x their walk
const CAMP_TOUGHNESS := 1.0                # companions' health x this for the camp fight (they take the first of it)
const SERVANTS := 12                       # mummies at the night camp
const SERVANTS_THEN := 2                   # after the first three, this many together every 2.5-4 s (one at a time: shot down unhurt)

var _veil: ColorRect  # black over a map change (_change_level)
var level: Level
var player: Player
var hud: Hud
var step := Step.KEEPERS
var args := {}
var plan := {}
var companions := {}
var servants: Array[Mummy] = []
var _events: Array[String] = []
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
	Game.act = 6
	if args.has("party") or (args.has("auto") and Game.party().is_empty()):
		for id in str(args.get("party", "mahmoud,eleanor")).split(",", false):
			Game.companion(id)["recruited"] = true  # test runs: who comes along
	player = Player.new()
	add_child(player)
	player.set_armed(false)
	hud = Hud.new()
	hud.player = player
	add_child(hud)
	add_child(CountdownBars.new())
	player.hit_confirmed.connect(hud.on_hit)
	player.damaged.connect(hud.on_damaged)
	player.died.connect(func(): hud.show_message("YOU DIED", "Enter  load the last save"))
	for s in str(args.get("shots", "")).split(",", false):
		_shots.append(float(s))
	Game.event.connect(func(e: String): _events.append(e))
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if args.size() > 0 else Input.MOUSE_MODE_CAPTURED
	_keepers()


# ---------------------------------------------------------------- the levels

## Swap the map under the player (the party comes along): the old one goes.
## `at_fn` (optional): where to stand, asked of the map once it's built (its spots: Cairo or Cairo
## v2 alike); otherwise `at`.
func _use_level(l: Level, at: Vector3, yaw: float, at_fn := Callable()) -> void:
	if level:
		level.queue_free()
	level = l
	add_child(level)
	if at_fn.is_valid():
		at = at_fn.call(level)
	if not has_node("Warmup"):
		Warmup.start(self, Warmup.MUMMIES)  # what spawns mid-fight, loaded now (tests/perf_test)
	player.global_position = at
	player.velocity = Vector3.ZERO
	player.yaw = yaw
	hud.toast("", 0.0)  # the last map's line doesn't fade over the next one
	var i := 0
	for id in companions:
		var c: Node3D = companions[id]
		if is_instance_valid(c):
			c.global_position = _party_spot(i, at, yaw)
		i += 1


## A map change mid-act, under a black veil: to black, the new map built, a few frames for its
## first draw (its shaders compile, its navmesh bakes: a 1.1 s stall on the road), back in.
func _change_level(l: Level, at: Vector3, yaw: float, at_fn := Callable()) -> void:
	if _veil == null:
		var layer := CanvasLayer.new()
		layer.layer = 60
		add_child(layer)
		_veil = ColorRect.new()
		_veil.color = Color(0, 0, 0, 0)
		_veil.set_anchors_preset(Control.PRESET_FULL_RECT)
		_veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layer.add_child(_veil)
	var tw := create_tween()
	tw.tween_property(_veil, "color:a", 1.0, 0.3)
	await tw.finished
	_use_level(l, at, yaw, at_fn)
	for i in 3:
		await get_tree().process_frame
	tw = create_tween()
	tw.tween_property(_veil, "color:a", 0.0, 0.6)


## Where the i-th companion stands: out to the sides, a step ahead (as act3 / act5 do), so
## nobody stands in the camera's lens behind you.
func _party_spot(i: int, at: Vector3, yaw: float) -> Vector3:
	var side := 1.0 if i % 2 == 0 else -1.0
	return at + Vector3(side * (2.4 + (i / 2) * 1.2), 0, -1.0).rotated(Vector3.UP, yaw)


func _spawn_party() -> void:
	for id in Game.party():
		if companions.has(id):
			continue
		var c := Gunman.make_companion(id, player, Characters.glb(id))
		if c:
			add_child(c)
			c.global_position = _party_spot(companions.size(), player.global_position, player.yaw)
			companions[id] = c


## Level has a sun and sky but only AkmentarSurface / Cairo know night: dim any Level's.
func _darken(f: float) -> void:
	darken(level, f)


## The night on any Level (static: tests/lighting_shots.gd shows the road the same way).
static func darken(level: Level, f: float) -> void:
	if level.has_method("set_night") and not level is Cairo:
		level.call("set_night", f)
		return
	level._sun.light_energy = lerpf(1.6, 0.15, f)
	level._sun.light_color = Color(1.0, 0.9, 0.75).lerp(Color(0.55, 0.65, 0.95), f)
	level._env.ambient_light_energy = lerpf(0.55, 0.08, f)
	level._env.ambient_light_sky_contribution = lerpf(1.0, 0.25, f)
	level._env.fog_light_color = Color(0.75, 0.62, 0.45).lerp(Color(0.05, 0.06, 0.1), f)
	level._env.tonemap_exposure = lerpf(0.9, 1.25, f)
	var sky := level._env.sky.sky_material as ProceduralSkyMaterial
	sky.sky_top_color = Color(0.32, 0.5, 0.75).lerp(Color(0.02, 0.03, 0.08), f)
	sky.sky_horizon_color = Color(0.85, 0.75, 0.6).lerp(Color(0.08, 0.08, 0.14), f)
	sky.ground_horizon_color = Color(0.8, 0.68, 0.5).lerp(Color(0.06, 0.05, 0.05), f)


# ---------------------------------------------------------------- dawn at Akmentar

func _keepers() -> void:
	step = Step.KEEPERS
	var surface := AkmentarSurface.new()
	_use_level(surface, AkmentarSurface.CAMPS.party + Vector3(2.6, 0, 3.0), 0.0)
	surface.set_night(0.35)  # first light
	Ambience.play(self, "desert")
	_spawn_party()
	var camp: Vector3 = AkmentarSurface.CAMPS.party
	var rashad := Npc.make(level, "rashad", camp + Vector3(-1.2, 0, 1.6), "", Characters.glb("rashad"))
	var bashir := Npc.make(level, "bashir", camp + Vector3(1.0, 0, 1.4), "", Characters.glb("bashir"))
	for n in [rashad, bashir]:
		n.face_towards(player.global_position)
	hud.show_message("ACT 6", "Dawn at Akmentar. The guardian is awake; the thieves are on the road.")
	Objective.set_goal("Race the thieves back to Cairo")
	await get_tree().create_timer(2.5).timeout
	hud.show_message("")
	if not Game.flag("act6_started", false):
		# The data sets the clocks by adding; start them from nothing.
		Game.countdowns.erase("thieves")
		Game.countdowns.erase("mummy")
		if _thief() == "":
			Game.set_flag("thieves_americans")
		if not await _talk("act6_keepers", rashad):  # no talk file: what it would have set
			var c: Dictionary = plan.get("countdowns", {})
			Game.apply([{"countdown": ["thieves", int(c.get("thieves", 7))]}, {"countdown": ["mummy", int(c.get("mummy", 9))]},
				{"set_flag": ["keeper_horses", 2]}, {"set_flag": "act6_started"}])
		if not Game.flag("act6_started", false):  # a talk that missed it: still set the clocks
			Game.apply([{"countdown": ["thieves", 7]}, {"countdown": ["mummy", 9]}, {"set_flag": "act6_started"}])
	print("RESULT act6 keepers thieves=%d mummy=%d keeper_horses=%d" % [int(Game.countdowns.get("thieves", 0)),
		int(Game.countdowns.get("mummy", 0)), int(Game.flag("keeper_horses", 0))])
	_save("keepers")
	_board()


## Which crew has the artifacts ("" if no flag says).
func _thief() -> String:
	for t in ["americans", "germans", "italians"]:
		if Game.flag("thieves_" + t, false):
			return t
	return ""


## horses alive + the Keepers' + 2 from each surviving rival that isn't the thieves >= party + 1.
func _count_transport() -> void:
	var horses := 0
	for h: Dictionary in Game.transport.get("horses", []):
		horses += int(float(h.get("health", 0)) > 0.0)
	horses += int(Game.flag("keeper_horses", 0))
	for r in RIVALS:
		if Game.flag(r + "_alive", false) and not Game.flag("thieves_" + r, false):
			horses += 2
	var need := Game.party().size() + 1
	Game.set_flag("enough_horses", horses >= need)
	var trucks := false
	for t: Dictionary in Game.transport.get("trucks", []):
		trucks = trucks or float(t.get("health", 0)) > 0.0
	Game.set_flag("trucks_running", trucks)
	print("RESULT act6 transport horses=%d need=%d enough=%s trucks=%s" % [horses, need, Game.flag("enough_horses"), trucks])


# ---------------------------------------------------------------- the board

func _board() -> void:
	step = Step.BOARD
	_count_transport()
	var b := RouteBoard.open(self, "act6_return", player)
	var closed := [false]
	b.finished.connect(func(_picks): closed[0] = true)
	if args.has("auto"):
		await get_tree().create_timer(0.5).timeout
		var want := "coast" if str(args.get("auto", "true")) in ["true", "coast"] else "desert"
		for i in b.options().size():
			if str(b.options()[i].get("id", "")) == want:
				b.choose(i)
				break
	while not closed[0]:
		await get_tree().process_frame
	await get_tree().create_timer(0.3).timeout
	var route := str(Game.flag("return_route", ""))
	print("RESULT act6 route=%s day=%d thieves=%d mummy=%d" % [route, Game.day,
		int(Game.countdowns.get("thieves", 0)), int(Game.countdowns.get("mummy", 0))])
	if route == "desert" and not Game.flag("enough_horses", false):
		_caught()
		return
	_road(route)


## Desert without horses for everyone: he catches you in the open.
func _caught() -> void:
	step = Step.OVER
	print("RESULT act6 game_over caught_in_desert")
	_darken(0.9)
	hud.show_message("CAUGHT IN THE OPEN", "Too few horses. Halfway across the sand, the wind drops, and he is there.\n\nEnter  load the last save")
	if args.has("auto"):
		await get_tree().create_timer(1.0).timeout
		get_tree().quit(0)


# ---------------------------------------------------------------- the road, at night

func _road(route: String) -> void:
	step = Step.ROAD
	Game.set_flag("act6_desert_pick" if route == "desert" else "act6_coast_pick")
	var road := DesertRoute.new()
	road.coast = route == "coast"
	var z := DesertRoute.START_Z - 30.0
	var camp := DesertRoute.road_point(z) + Vector3(9.0, 0, 0)
	await _change_level(road, camp + Vector3(-2.5, 0, 2.0), 0.0)
	_darken(0.85)
	Ambience.play(self, "night")
	_camp(camp)
	CampJobs.assign(level, companions, "act6_stop", true, {"anchor": camp})  # -f9's: each at their job at the stop, fighting from their posts
	hud.show_message("THE ROAD BACK", "The %s road. Night falls; you make camp." % route)
	await get_tree().create_timer(2.5).timeout
	hud.show_message("")
	_events.clear()
	var ride := str(args.get("plan", "hold")) == "ride"  # (the bot's pick at the camp)
	if not await _talk("act6_road", player, BotTalk.AVOID + (["Hold the camp"] if ride else ["Break camp and ride"])):
		if ride:
			Game.set_flag("act6_night_ride")
			for id in Game.party():  # (the talk does this itself)
				Game.apply([{"stat": [id, "fear", 1]}])
		else:
			Game.apply([{"event": "fight_mummy_servants"}])
	if _events.has("fight_mummy_servants"):
		await _servants(camp)
		if not player.alive:
			return
	elif Game.flag("act6_night_ride", false):
		hud.toast("You break camp and ride through the dark, the servants' shapes keeping pace on the dunes.", 4.0)
		await get_tree().create_timer(2.0).timeout
	Weather.sandstorm(self, 40.0)  # -f9's: the last miles to Cairo in blowing sand
	CampJobs.release(level)
	_arrival()


func _camp(at: Vector3) -> void:
	var fire := Node3D.new()
	level.add_child(fire)
	fire.position = at
	level._flame(fire, Vector3.UP * 0.45, 2.8, 14.0, true)
	level._prop(level, "prop_campfire.glb", at)
	for k in 3:
		var a := PI * 0.5 + (k - 1) * 1.1
		level._prop(level, "prop_bedroll.glb", at + Vector3(cos(a), 0, sin(a)) * 2.6, a)


## The guardian's servants come out of the dark at the camp, not all at once: three from
## different sides, then one every few seconds from wherever the dark is (about half a minute in
## all). Held when every one of them has come and is down (act6_camp_held).
func _servants(camp: Vector3) -> void:
	player.set_armed(true)
	hud.toast("Shapes in the dark, wrapped and silent. Hold the fire!", 3.0)
	Objective.set_goal("Hold the fire until dawn")
	# Nobody dies outright (Gunman.downed, the whole game): help them up (E) before a servant reaches
	# them, or the dark takes them when it's over.
	for c in companions.values():
		if is_instance_valid(c):
			# They stand between you and the dark, so they take the first of it: dug in by the fire,
			# they hold longer than in the open (restored after the fight).
			c.set_meta("camp_max_hp", c.max_health)
			c.max_health *= CAMP_TOUGHNESS
			c.health = c.max_health
			if not c.helped_up.is_connected(_on_helped_up):
				c.helped_up.connect(_on_helped_up)
				c.stumbled_down.connect(_on_downed)
				c.killed.connect(func(g: Gunman): print("RESULT act6 killed %s (stumbled=%s)" % [g.companion_id, g.stumbled]))
	var down := [0]
	var spawned := 0
	var t := 0.0
	var next_t := 0.0
	var first_a := randf() * TAU
	var t0 := Time.get_ticks_msec()
	while player.alive:
		if spawned < SERVANTS and t >= next_t:
			for k in (3 if spawned == 0 else mini(SERVANTS_THEN, SERVANTS - spawned)):
				var a := first_a + TAU * k / 3.0 if spawned < 3 else randf() * TAU
				_servant(camp, a, spawned == 0, down)
				spawned += 1
			next_t = t + randf_range(2.5, 4.0)
		if spawned >= SERVANTS and down[0] >= SERVANTS:
			break
		await get_tree().create_timer(0.25).timeout
		t += 0.25
	if not player.alive:
		return
	print("RESULT act6 servants=%d over %.0f s" % [servants.size(), (Time.get_ticks_msec() - t0) / 1000.0])
	player.set_armed(false)
	# Anyone still down gets up by themselves (Gunman.UP_AFTER); the dead are the ones left down
	# too long with servants about, or finished where they lay.
	var lost: Array[String] = []
	for c in companions.values():
		if is_instance_valid(c):
			if c.has_meta("camp_max_hp"):
				c.max_health = float(c.get_meta("camp_max_hp"))
				c.health = minf(c.health, c.max_health)
				c.remove_meta("camp_max_hp")
			if not c.alive:
				lost.append(DayLog.person(c.companion_id))
	Game.set_flag("act6_camp_held")
	print("RESULT act6 camp_held lost=%s" % [lost])
	if lost.is_empty():
		hud.toast("The last of them falls into the fire. Nobody sleeps.", 3.0)
	else:
		hud.toast("The last of them falls. The dark took %s." % " and ".join(lost), 4.5)
	await get_tree().create_timer(2.0).timeout


## Down (Gunman leaves them a few seconds' grace): say so.
func _on_downed(g: Gunman) -> void:
	print("RESULT act6 down %s" % g.companion_id)
	hud.toast("%s is down! Get to them ({cover})." % DayLog.person(g.companion_id), 3.0)


## Back on their feet (Gunman.help_up gives them back 40%).
func _on_helped_up(g: Gunman) -> void:
	print("RESULT act6 helped up %s" % g.companion_id)


## One servant out of the dark at bearing `a` from the camp.
func _servant(camp: Vector3, a: float, priest: bool, down: Array) -> void:
	var m := Mummy.new()
	m.priest = priest
	add_child(m)
	m.health = SERVANT_HP
	m.speed *= SERVANT_PACE
	m.party_margin = 5.0  # they come for you (and the amulet) unless a companion is clearly nearer
	var p := camp + Vector3(cos(a), 0, sin(a)) * randf_range(11.0, 15.0)  # out of the dark close by (16-22 m: shot down before they arrived)
	p.y = DesertRoute.ground_y(p.z)
	m.global_position = p
	m.target = player
	m.wake()
	m.killed.connect(func(_m): down[0] += 1)
	servants.append(m)
	if args.has("auto") and not args.has("skill-bot"):  # --skill-bot: tests/difficulty_test fights them
		get_tree().create_timer(1.0).timeout.connect(func():
			if is_instance_valid(m) and m.is_active():
				m._out(Vector3.FORWARD))  # out of the fight, as all four limbs gone would (mummies never die now)


# ---------------------------------------------------------------- Cairo

func _arrival() -> void:
	step = Step.ARRIVAL
	var cairo := Cairo.new()
	# Inside the south gate, looking up the street (from the map's own gate: today's Cairo or v2).
	await _change_level(cairo, Vector3.ZERO, 0.0, func(l: Level) -> Vector3: return (l as Cairo).spots.road_gate + Vector3(0, 0, -4.5))
	cairo.set_day_time(0.85)
	cairo.set_curse(1.0, 0.0)  # the dust that won't settle
	Ambience.play(self, "cairo")
	hud.show_message("CAIRO", Cairo.countdown_line())
	Objective.set_goal("Into Cairo")
	await get_tree().create_timer(2.5).timeout
	hud.show_message("")
	await _talk("act6_arrival", player)
	_finish()


func _finish() -> void:
	step = Step.END
	Game.set_flag("act6_done")
	_save("end")
	print("RESULT act6 end day=%d thieves=%d mummy=%d route=%s" % [Game.day, int(Game.countdowns.get("thieves", 0)),
		int(Game.countdowns.get("mummy", 0)), Game.flag("return_route", "")])
	hud.show_message("BACK IN CAIRO", "Enter  into the city (Act 7)")
	Objective.set_goal("")
	if args.has("auto"):
		await get_tree().create_timer(1.0).timeout
		if args.has("chain"):
			Loader.go(get_tree(), NEXT_ACT)  # --chain: on into Act 7 with these countdowns
		else:
			get_tree().quit(0)


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


func _save(where: String) -> void:
	Game.place = "act6_" + where
	Game.set_flag("player_health", player.health)
	if Game.save_game():
		SavePrompt.after_rest(self, hud)  # "Game saved", and a copy in a numbered slot if wanted


func _unhandled_input(event: InputEvent) -> void:
	if args.size() > 0:
		return
	var enter: bool = event is InputEventKey and event.pressed and event.keycode in [KEY_ENTER, KEY_KP_ENTER]
	if step == Step.END and enter:
		Loader.go(get_tree(), NEXT_ACT)  # Game (the countdowns, the party) carries over
	elif (step == Step.OVER or not player.alive) and enter:
		SaveRoute.resume(get_tree())  # the last save, wherever it resumes
	elif event.is_action_pressed("party_order"):
		hud.toast("Companions: " + str(Gunman.toggle_party_order(get_tree())))


# ---------------------------------------------------------------- frame, test runs

func _process(delta: float) -> void:
	_t += delta
	if _shots.size() > 0 and _t >= _shots[0]:
		_shots.pop_front()
		_shot("act6_%05.1f.png" % _t)
	if args.has("seconds") and _t > float(args.seconds):
		print("RESULT act6 timeout step=%d" % step)
		get_tree().quit(1)
	if args.get("auto", "") == "desert" and step == Step.KEEPERS and not Game.flag("act6_auto_horses", false):
		# The desert bot rides with horses for everyone.
		Game.set_flag("act6_auto_horses")
		Game.transport["horses"] = [{"id": "a", "health": 100}, {"id": "b", "health": 100}, {"id": "c", "health": 100}]


func _shot(file: String) -> void:
	await RenderingServer.frame_post_draw
	if DisplayServer.get_name() == "headless":
		return
	var dir: String = args.get("shot-dir", "user://shots")
	DirAccess.make_dir_recursive_absolute(dir)
	get_viewport().get_texture().get_image().save_png(dir.path_join(file))
	print("RESULT shot %s" % dir.path_join(file))
