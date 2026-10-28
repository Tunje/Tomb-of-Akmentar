extends Node3D
## Act 8's boat_battle (the riverboat route): the third night on the Nile, the steamer drifting on
## still water. The talk act8_boat (-f9's), then fight_on_boat: the guardian's servants come up
## out of the river, hand over hand up the paddle wheel and over the rails, and go for whoever
## carries the amulet (the carrier flag: a companion id or "player"); anyone in their way gets it
## first. Their weight on the wheel stops the engine dead. He stands on the water astern,
## watching, and sinks away when it's over. Two waves (the second brings a priest). If the carrier
## falls, you take the amulet from them (carrier becomes "player").
## RiverRoute, RiverBoat and the Act 3 flames are -2d's; the deck has a navmesh (DeckNav).
## When it's over `finished` gets the result and Enter goes to `next_scene` (set by the act that
## sends you here). Flags: act8_boat_held, act8_boat_losses (ids), carrier / carrier_player when
## the amulet changes hands. Test args (after --): --auto, --party=a,b, --carrier=id|player,
## --seconds=N, --shots=t1,t2, --shot-dir=path, --cam=chase.

signal finished(result: Dictionary)

static var next_scene := "res://act8.tscn"

const WAVES := [6, 8]
const SERVANT_HP := 115.0  # (mummy.gd: 100; tests/difficulty_test: at 130 the boat fell 2 runs in 5)
const NEXT_WAVE_WHEN := 1          # the next wave comes when this few are still up...
const NEXT_WAVE_AFTER := 40.0      # ...or after this long
const WAVE_GAP := 5.5               # s between the call and the next wave coming over: a beat to reload and regroup
const DRIFT := 1.5                 # m/s on the still water before they come
const GUARDIAN_ASTERN := Vector3(0, 0, 34.0)  # boat-local: where he stands on the river
const IN_THE_WAY := 2.0            # a servant goes for whoever is this close, else the carrier
## A companion carrying the amulet holds the upper deck by the wheelhouse (boat-local): they
## have to come up the stern stairs past everyone.
const ROOF_HOLD := Vector3(0.0, RiverBoat.UPPER_Y + 0.1, -3.5)
## Where they come over (boat-local): [from, outside the hull below the deck edge; to, on deck].
const CLIMBS := [
	[Vector3(-2.4, 0.4, 19.2), Vector3(-2.4, 0, 16.6)],   # up the paddle wheel
	[Vector3(0.0, 0.4, 19.2), Vector3(0.0, 0, 16.6)],
	[Vector3(2.4, 0.4, 19.2), Vector3(2.0, 0, 16.6)],
	[Vector3(-5.2, 0.3, -9.0), Vector3(-3.6, 0, -9.0)],   # over the port rail
	[Vector3(-5.2, 0.3, 5.0), Vector3(-3.4, 0, 5.0)],
	[Vector3(5.2, 0.3, -9.0), Vector3(3.6, 0, -9.0)],     # over the starboard rail
	[Vector3(5.2, 0.3, 11.0), Vector3(3.4, 0, 11.0)],
	[Vector3(0.0, 0.4, -20.5), Vector3(0.0, 0, -16.6)],   # over the bow
]
const LANTERNS := [Vector3(0, 2.4, -14.0), Vector3(-3.4, 2.6, 0.0), Vector3(3.4, 2.6, 0.0), Vector3(0, 2.4, 14.5),
	Vector3(0, RiverBoat.UPPER_Y + 1.2, 1.0)]

var level: RiverRoute
var boat: RiverBoat
var player: Player
var hud: Hud
var guardian: Guardian
var args := {}
var companions := {}
var servants: Array[Mummy] = []
var result := {}
var carrier: Node3D
var _carrier_id := "player"
var _party_start: Array[String] = []
var _wave := 0
var _wave_t := 0.0
var _gap_t := -1.0  # counting down to the next wave (< 0: none called)
var _regrouped := false  # a companion has called the breather
var _wave_members: Array[Mummy] = []
var _killed := 0
var _fighting := false
var _done := false
var _t := 0.0
var _aim_t := 0.0
var _shots: Array[float] = []
var _chase: Camera3D


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Checkpoint.take(self)  # a retry after a death starts from the state on entry
	child_entered_tree.connect(func(n: Node):
		if n.process_mode == Node.PROCESS_MODE_INHERIT:
			n.process_mode = Node.PROCESS_MODE_PAUSABLE)
	Controls.setup()
	args = TestDriver.parse_args()
	if args.size() > 0:
		get_window().set_flag(Window.FLAG_NO_FOCUS, true)
	Game.act = 8
	if args.has("party") or (args.has("auto") and Game.party().is_empty()):
		for id in str(args.get("party", "mahmoud,eleanor")).split(",", false):
			Game.companion(id)["recruited"] = true
	if args.has("carrier"):
		Game.set_flag("carrier", str(args.carrier))
		Game.set_flag("carrier_" + str(args.carrier))
	elif args.has("auto") and str(Game.flag("carrier", "")) == "":
		Game.set_flag("carrier", "eleanor" if Game.in_party("eleanor") else "player")
	level = RiverRoute.new()
	add_child(level)
	Warmup.start(self, Warmup.MUMMIES)  # the priest's 5.7 MB GLB was a 175 ms stall mid-fight (tests/perf_test)
	Ambience.play(self, "river")
	_night()
	boat = RiverBoat.make(level, level.path, "act8_steamer", 120.0)
	boat.add_folk()  # passengers and crew, who go below at the first shots (-f9)
	boat.cruise = DRIFT
	player = Player.new()
	add_child(player)
	player.global_position = boat.to_global(Vector3(1.4, RiverBoat.DECK_Y + 0.1, 12.0))
	player.yaw = boat.global_rotation.y
	player.set_armed(false)
	boat.watch(player)
	hud = Hud.new()
	hud.player = player
	add_child(hud)
	add_child(CountdownBars.new())
	player.hit_confirmed.connect(hud.on_hit)
	player.damaged.connect(hud.on_damaged)
	player.died.connect(_on_died)
	for s in str(args.get("shots", "")).split(",", false):
		_shots.append(float(s))
	if args.get("cam", "") == "chase":
		_chase = Camera3D.new()
		_chase.fov = 60.0
		add_child(_chase)
	_aboard_people()
	_settle_aboard.call_deferred()
	DeckNav.attach(boat)
	Game.event.connect(func(e: String):
		if e == "fight_on_boat":
			_fight())
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if args.size() > 0 else Input.MOUSE_MODE_CAPTURED
	boat.sail()
	_intro()


# ---------------------------------------------------------------- the night on the river

## Night: a low blue moon, dark water and sky; lanterns along the boat.
func _night() -> void:
	night(level)


## The river at night (static: tests/lighting_shots.gd shows it the same way).
static func night(level: Level) -> void:
	var sun: DirectionalLight3D = level.get("_sun")
	var env: Environment = level.get("_env")
	if sun:
		sun.light_color = Color(0.55, 0.65, 0.95)
		sun.light_energy = 0.22
		sun.rotation = Vector3(deg_to_rad(-28), deg_to_rad(140), 0)
	if env:
		env.ambient_light_energy = 0.25
		env.fog_light_color = Color(0.05, 0.07, 0.12)
		env.fog_density = 0.012
		if env.sky and env.sky.sky_material is ProceduralSkyMaterial:
			var sm := env.sky.sky_material as ProceduralSkyMaterial
			sm.sky_top_color = Color(0.01, 0.015, 0.04)
			sm.sky_horizon_color = Color(0.05, 0.06, 0.1)
			sm.ground_horizon_color = Color(0.03, 0.03, 0.05)
			sm.ground_bottom_color = Color(0.01, 0.01, 0.02)


func _lanterns() -> void:
	lanterns(boat)


## The lanterns along a boat (static: tests/lighting_shots.gd lights the deck the same way).
static func lanterns(boat: Node3D) -> void:
	for at in LANTERNS:
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.72, 0.4)
		l.light_energy = 1.6
		l.omni_range = 9.0
		l.shadow_enabled = false
		boat.add_child(l)
		l.position = at


## The party about the afterdeck; the carrier among them (or you).
func _aboard_people() -> void:
	_lanterns()
	var i := 0
	for id in Game.party():
		var c := Gunman.make_companion(id, player, Characters.glb(id))
		if c == null:
			continue
		add_child(c)
		c.global_position = boat.to_global(Vector3(-1.2 + i * 1.3, RiverBoat.DECK_Y + 0.1, 14.0))
		boat.watch(c)
		companions[id] = c
		_party_start.append(id)
		i += 1
	_set_carrier(str(Game.flag("carrier", "player")))


func _settle_aboard() -> void:
	var where := {player: Vector3(1.4, RiverBoat.DECK_Y + 0.1, 12.0)}
	var i := 0
	for c in companions.values():
		where[c] = Vector3(-1.2 + i * 1.3, RiverBoat.DECK_Y + 0.1, 14.0)
		i += 1
	if carrier is Gunman:
		where[carrier] = ROOF_HOLD  # "I'll take the wheelhouse roof. If he wants the amulet, he climbs past me."
	for n in 3:
		await get_tree().physics_frame
		for who: Node3D in where:
			if is_instance_valid(who):
				who.global_position = boat.to_global(where[who])
				if who is CharacterBody3D:
					(who as CharacterBody3D).velocity = Vector3.ZERO
	player.yaw = boat.global_rotation.y
	if carrier is Gunman:
		(carrier as Gunman).set_order("hold")
		(carrier as Gunman).hold_at = boat.to_global(ROOF_HOLD)


func _set_carrier(id: String) -> void:
	_carrier_id = id if companions.has(id) else "player"
	carrier = companions[_carrier_id] if companions.has(_carrier_id) else player


func _intro() -> void:
	hud.show_message("THE NILE, BY NIGHT", "Third night on the river. The water's gone still as glass.")
	Objective.set_goal("Guard the amulet on the river")
	await get_tree().create_timer(3.0).timeout
	hud.show_message("")
	await get_tree().create_timer(1.0).timeout
	await _talk("act8_boat")
	_fight()  # (the talk's fight_on_boat usually started it already)


# ---------------------------------------------------------------- the fight

func _fight() -> void:
	if _fighting or _done:
		return
	_fighting = true
	player.set_armed(true)
	hud.toast("They're coming up out of the water! Protect the amulet!", 4.0)
	Objective.set_goal("Protect the amulet: hold the deck")
	print("RESULT act8_boat fight t=%.1f carrier=%s" % [_t, _carrier_id])
	# He stands on the river astern, and his servants' weight on the wheel stops it dead.
	guardian = Guardian.new()
	guardian.name = "Guardian"
	level.add_child(guardian)
	guardian.target = carrier
	guardian.stand_on(boat, GUARDIAN_ASTERN, RiverBoat.WATER_Y)
	boat.cruise = 0.0
	await get_tree().create_timer(2.5).timeout
	_next_wave()


func _next_wave() -> void:
	var count: int = WAVES[_wave]
	_wave += 1
	_wave_t = 0.0
	_wave_members.clear()
	hud.toast("Up the paddle wheel and over the rails!" if _wave == 1 else "More of them! A priest among them!", 3.0)
	print("RESULT act8_boat wave %d (%d servants) t=%.1f" % [_wave, count, _t])
	for k in count:
		var climb: Array = CLIMBS[(k * 3 + _wave) % CLIMBS.size()]
		get_tree().create_timer(k * 0.6).timeout.connect(func(): _climb_aboard(climb, _wave == WAVES.size() and k == 0))


## One servant hauls itself over the side (Mummy.rise: up, then down onto the deck).
func _climb_aboard(climb: Array, priest: bool) -> void:
	if _done:
		return
	var m := Mummy.new()
	m.priest = priest
	add_child(m)
	m.health = SERVANT_HP
	var from := boat.to_global(climb[0] as Vector3)
	var to := boat.to_global((climb[1] as Vector3) + Vector3.UP * (RiverBoat.DECK_Y + 0.05))
	m.target = carrier
	m.rise(from, to)
	m.killed.connect(func(_m): _killed += 1)
	boat.watch(m)
	servants.append(m)
	_wave_members.append(m)


func _up(list: Array[Mummy]) -> int:
	var n := 0
	for m in list:
		n += int(is_instance_valid(m) and m.is_active())
	return n


## Each servant goes for the carrier, unless someone is right in its way.
func _steer_servants() -> void:
	var people: Array[Node3D] = [player]
	for c in companions.values():
		if is_instance_valid(c) and (c as Gunman).is_active() and not (c as Gunman).stumbled:
			people.append(c)  # not the downed: steering at them would finish them
	for m in servants:
		if not is_instance_valid(m) or not m.is_active():
			continue
		var pick: Node3D = carrier if is_instance_valid(carrier) and carrier.alive and not carrier.get("stumbled") else null
		var bd := IN_THE_WAY
		for p in people:
			var d := p.global_position.distance_to(m.global_position)
			if d < bd and p.alive:
				bd = d
				pick = p
		if pick:
			m.target = pick
			m.set("_retarget", 1.0)  # its own nearest-person pick would ignore the amulet


func _fight_step(delta: float) -> void:
	_wave_t += delta
	_steer_servants()
	# The carrier is down (downed or dead): the amulet passes to you.
	if _carrier_id != "player" and (not is_instance_valid(carrier) or not carrier.alive or carrier.get("stumbled")):
		var who := _carrier_id.capitalize()
		_set_carrier("player")
		Game.set_flag("carrier", "player")
		Game.set_flag("carrier_player")
		Game.set_flag("act8_carrier_fell", true)
		hud.toast("%s is down. You take the amulet." % who, 3.5)
		print("RESULT act8_boat carrier %s fell t=%.1f; the player carries it" % [who, _t])
		if is_instance_valid(guardian):
			guardian.target = player
	if _gap_t >= 0.0:
		_gap_t -= delta
		if not _regrouped:  # (Barks keeps 4 s between lines: the last one down's "Down." may hold it a moment)
			_regrouped = Barks.say_any(get_tree(), "regroup", player.global_position) != ""
		if _gap_t < 0.0:
			_next_wave()
	elif _wave < WAVES.size() and (_up(_wave_members) <= NEXT_WAVE_WHEN or _wave_t > NEXT_WAVE_AFTER) and _wave_members.size() >= WAVES[_wave - 1]:
		_gap_t = WAVE_GAP  # a breath first (limb by limb, the second wave straight on the first's heels lost the boat)
		_regrouped = false
	elif _wave == WAVES.size() and _wave_members.size() >= WAVES[_wave - 1] and _up(servants) == 0:
		_held()


func _held() -> void:
	_done = true
	print("RESULT act8_boat held t=%.1f killed=%d" % [_t, _killed])
	hud.toast("The last of them goes over the side. Astern, he sinks into the river without a ripple.", 4.0)
	if is_instance_valid(guardian):
		guardian.sink(3.0)
	boat.cruise = DRIFT
	await get_tree().create_timer(4.0).timeout
	var lost: Array[String] = []
	for id in _party_start:
		if not Game.in_party(id):
			lost.append(id)
	result = {"held": true, "servants_killed": _killed, "party_losses": lost, "carrier": _carrier_id,
		"carrier_fell": Game.flag("act8_carrier_fell", false), "t": snappedf(_t, 0.1)}
	Game.set_flag("act8_boat_held")
	Game.set_flag("act8_boat_losses", lost)
	hud.show_message("THE RIVER, AT DAWN", "\n".join([
		"The servants came over the side in the dark, and you held the boat.",
		"Companions lost: %s." % (", ".join(lost.map(func(id): return str(id).capitalize())) if not lost.is_empty() else "none"),
		"The amulet is with %s." % ("you" if _carrier_id == "player" else _carrier_id.capitalize()),
		"", "Enter  go on"]))
	Objective.set_goal("")
	print("RESULT act8_boat end held=true killed=%d party_losses=%s carrier=%s player_health=%.0f t=%.1f" % [_killed, lost,
		_carrier_id, player.health, _t])
	finished.emit(result)
	if args.has("auto"):
		TestDriver.auto_end(self, next_scene)  # --chain: on, as Enter would


func _on_died() -> void:
	_done = true
	hud.show_message("YOU DIED", "Enter to try again")
	print("RESULT act8_boat died t=%.1f" % _t)
	if args.has("auto"):
		get_tree().quit(1)


func _talk(id: String) -> void:
	if not FileAccess.file_exists("res://dialogue/%s.json" % id) or args.has("auto"):
		return
	var who: Node3D = player
	for c in companions.values():
		if is_instance_valid(c):
			who = c
			break
	var c := Conversation.new()
	add_child(c)
	if c.start(id, player, who):
		await c.finished


func _unhandled_input(event: InputEvent) -> void:
	if args.size() > 0:
		return
	var enter: bool = event is InputEventKey and event.pressed and event.keycode in [KEY_ENTER, KEY_KP_ENTER]
	if enter and not result.is_empty():
		Loader.go(get_tree(), next_scene)  # Game (the flags, the party) carries over
	elif enter and not player.alive:
		Checkpoint.retry(self)  # Game as it was on entry, then the scene from its start
	elif event.is_action_pressed("party_order"):
		hud.toast("Companions: " + str(Gunman.toggle_party_order(get_tree())))
	elif event.is_action_pressed("journal"):
		JournalScreen.toggle(self, player)


# ---------------------------------------------------------------- tick and test bot

func _physics_process(delta: float) -> void:
	_t += delta
	if _fighting and not _done:
		_fight_step(delta)
	if args.has("auto"):
		player.max_health = 100000.0
		player.health = 100000.0
		_bot(delta)


## The bot: stands its ground and shoots the nearest servant it can see (head height).
func _bot(delta: float) -> void:
	var best: Mummy = null
	var bd := 40.0
	var space := get_world_3d().direct_space_state
	for m in servants:
		if not is_instance_valid(m) or not m.is_active() or m.state == Mummy.State.RISING:
			continue
		var d := m.global_position.distance_to(player.global_position)
		if d >= bd:
			continue
		var q := PhysicsRayQueryParameters3D.create(player.camera.global_position, m.global_position + Vector3.UP * 1.2, 1)
		if space.intersect_ray(q).is_empty():
			bd = d
			best = m
	if best == null or not _fighting:
		FightBot.press("aim", false)
		FightBot.press("fire", false)
		return
	var at := best.aim_point(player.camera.global_position)  # a limb: mummies are shot apart, never killed
	var to := at - player.camera.global_position
	var want := atan2(-to.x, -to.z)
	player.yaw = lerp_angle(player.yaw, want, minf(delta * 8.0, 1.0))
	player.pitch = lerpf(player.pitch, asin(clampf(to.normalized().y, -1, 1)), minf(delta * 8.0, 1.0))
	_aim_t += delta
	FightBot.press("aim", true)
	FightBot.press("fire", absf(angle_difference(player.yaw, want)) < 0.04 and fmod(_aim_t, 0.5) < 0.1)


func _process(_delta: float) -> void:
	if _chase:
		_chase.global_position = boat.to_global(Vector3(-20.0, 10.0, 14.0))
		_chase.look_at(boat.to_global(Vector3(0, 2.0, 4.0)), Vector3.UP)
	if _shots.size() > 0 and _t >= _shots[0]:
		_shots.pop_front()
		_shot("act8_boat_%05.1f.png" % _t)
	if args.has("seconds") and _t > float(args.seconds):
		print("RESULT act8_boat timeout t=%.1f wave=%d up=%d" % [_t, _wave, _up(servants)])
		get_tree().quit(1)


func _shot(file: String) -> void:
	if _chase:
		_chase.make_current()
	await RenderingServer.frame_post_draw
	if DisplayServer.get_name() == "headless":
		return
	var dir: String = args.get("shot-dir", "user://shots")
	DirAccess.make_dir_recursive_absolute(dir)
	get_viewport().get_texture().get_image().save_png(dir.path_join(file))
	print("RESULT shot %s" % dir.path_join(file))
