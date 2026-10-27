extends Node3D
## Act 3, the riverboat (Route B; gameplan/primaryact.md: "Riverboat: boat is attacked and
## destroyed; expedition is stranded in the desert", starting position Step 5).
## ABOARD -> ATTACK -> BURNING -> STRANDED -> END.
## The steamer sails upriver with your party and the Americans aboard. Whitfield and his $500
## wager first (-f9's dialogue/act3_riverboat.json). Then the Keepers of the Veil strike: riflemen
## on the west bank open up as you pass, and skiffs row out and come alongside to port, two waves
## of boarders fighting along the deck (crates are cover; the two American gunmen fight beside
## you). In the second wave a firebomb sets the steamer alight: once the boarders are dealt with
## the boat is lost, and everyone wades ashore to the west bank (act3_stranded.json, with
## Whitfield). Sets race_step 5, recognized_bandits, boat_attacked, riverboat_lost.
## The talks are skipped in --auto runs unless --talk is given, and when their files are missing.
## Test args after "--": --auto  --party=mahmoud,khalil  --shots=t1,t2  --shot-dir=path
## --cam=chase (shots from beside the boat)  --seconds=N  --seed=N.

## Hand-over for act3.gd: where Enter goes at the end (set before changing to this scene), and
## a signal when the summary is up (the flags are all set by then).
signal finished(result: Dictionary)

enum Step { ABOARD, ATTACK, BURNING, STRANDED, END }

static var next_scene := "res://act4.tscn"

const AMERICANS := "americans"
const ATTACK_AFTER := 14.0         # s after the talk (or the start, without it)
const WAVES := [4, 5]              # boarders per wave (two skiffs each)
const NEXT_WAVE_WHEN := 1
const NEXT_WAVE_AFTER := 40.0
const BANK_RIFLES := 3
const ROW_TIME := 9.0              # s from the bank to alongside
const WITHDRAW_AFTER := 75.0       # after the last wave boards, whoever's left jumps overboard
const KEEPER_GLB := ["res://assets/characters/bandits/bandit_scout.glb",
	"res://assets/characters/bandits/bandit_raider.glb"]
## Where boarders come over the port rail (boat-local): foredeck, the passage, afterdeck.
const BOARD_AT := [Vector3(-3.6, 0, -12.0), Vector3(-3.6, 0, -4.0), Vector3(-3.6, 0, 6.0), Vector3(-3.6, 0, 13.0)]

var level: RiverRoute
var boat: RiverBoat
var player: Player
var hud: Hud
var step := Step.ABOARD
var args := {}
var companions := {}               # id -> Gunman
var americans: Array[Gunman] = []
var whitfield: Npc
var keepers: Array[Gunman] = []
var result := {}
var _t := 0.0
var _shots: Array[float] = []
var _chase: Camera3D
var _fight_bot: FightBot
var _wave := 0
var _wave_t := 0.0
var _wave_members: Array[Gunman] = []
var _skiffs: Array[Node3D] = []
var _killed := 0
var _withdrew := 0
var _party_start: Array[String] = []
var _fire: Array[Node3D] = []
var _attack_at := -1.0


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
	if args.has("seed"):
		seed(int(args.seed))
	Game.act = 3
	Game.set_flag("route", "riverboat")
	level = RiverRoute.new()
	add_child(level)
	Ambience.play(self, "river")
	boat = RiverBoat.make(level, level.path, "act3_steamer", 30.0)
	boat.add_folk()  # passengers and crew, who go below at the first shots (-f9)
	player = Player.new()
	add_child(player)
	player.global_position = boat.to_global(Vector3(2.4, RiverBoat.DECK_Y + 0.1, 13.0))
	player.yaw = boat.global_rotation.y
	player.set_armed(false)
	boat.watch(player)
	hud = Hud.new()
	hud.player = player
	add_child(hud)
	player.hit_confirmed.connect(hud.on_hit)
	player.damaged.connect(hud.on_damaged)
	player.died.connect(_on_died)
	for s in str(args.get("shots", "")).split(",", false):
		_shots.append(float(s))
	if args.has("party") or (args.has("auto") and Game.party().is_empty()):
		for id in str(args.get("party", "mahmoud,khalil")).split(",", false):
			Game.companion(id)["recruited"] = true  # test runs: who comes along
	_aboard_people()
	_settle_aboard.call_deferred()
	if args.get("cam", "") == "chase":
		_chase = Camera3D.new()
		add_child(_chase)
		_chase.fov = 60.0
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if args.size() > 0 else Input.MOUSE_MODE_CAPTURED
	boat.sail()
	_aboard()


func _unhandled_input(event: InputEvent) -> void:
	if args.size() > 0:
		return
	if step == Step.END and event is InputEventKey and event.pressed and event.keycode in [KEY_ENTER, KEY_KP_ENTER]:
		Loader.go(get_tree(), next_scene)
	elif event is InputEventKey and event.pressed and event.keycode in [KEY_ENTER, KEY_KP_ENTER] and not player.alive:
		Checkpoint.retry(self)  # Game as it was on entry, then the scene from its start
	elif event.is_action_pressed("party_order"):
		hud.toast("Companions: " + str(Gunman.toggle_party_order(get_tree())))


# ---------------------------------------------------------------- aboard

## The party on the afterdeck; Whitfield and Maggie by the cabin (they ride the deck as its
## children); two American gunmen who'll fight beside you.
func _aboard_people() -> void:
	var i := 0
	for id in Game.party():
		var c := Gunman.make_companion(id, player, Characters.glb(id))
		if c == null:
			continue
		add_child(c)
		c.global_position = boat.to_global(Vector3(-1.0 + i * 1.3, RiverBoat.DECK_Y + 0.1, 15.0))
		boat.watch(c)
		companions[id] = c
		_party_start.append(id)
		i += 1
	whitfield = Npc.make(boat, "whitfield", boat.to_global(Vector3(2.6, RiverBoat.DECK_Y, 10.6)), "act3_riverboat", Characters.glb("whitfield"))
	Npc.make(boat, "maggie", boat.to_global(Vector3(-2.6, RiverBoat.DECK_Y, 10.8)), "", Characters.glb("maggie"))
	Gunman.set_allies(Gunman.PARTY, AMERICANS)
	for k in 2:
		var g := Gunman.new()
		g.team = AMERICANS
		g.name = "American_%d" % (k + 1)
		g.glb = Characters.glb("callahan") if k == 0 else Characters.DIR + Characters.CREW_STAND_IN
		g.can_surrender = false
		g.foe_player = player
		add_child(g)
		g.global_position = boat.to_global([Vector3(2.4, RiverBoat.DECK_Y + 0.1, -9.0), Vector3(-2.4, RiverBoat.DECK_Y + 0.1, -9.5)][k])
		boat.watch(g)
		americans.append(g)


## The boat takes its place on the river in its first physics step; until then its deck isn't
## under anyone. Put everyone back where they belong once it's there.
func _settle_aboard() -> void:
	var where := {player: Vector3(2.4, RiverBoat.DECK_Y + 0.1, 13.0)}
	var i := 0
	for c in companions.values():
		where[c] = Vector3(-1.0 + i * 1.3, RiverBoat.DECK_Y + 0.1, 15.0)
		i += 1
	where[americans[0]] = Vector3(2.4, RiverBoat.DECK_Y + 0.1, -9.0)
	where[americans[1]] = Vector3(-2.4, RiverBoat.DECK_Y + 0.1, -9.5)
	for n in 3:
		await get_tree().physics_frame
		for who: Node3D in where:
			if is_instance_valid(who):
				who.global_position = boat.to_global(where[who])
				if who is CharacterBody3D:
					(who as CharacterBody3D).velocity = Vector3.ZERO
	player.yaw = boat.global_rotation.y


func _aboard() -> void:
	step = Step.ABOARD
	hud.show_message("THE RIVERBOAT", "Upriver toward Akmentar. The Americans booked the same passage.")
	Objective.set_goal("Upriver to Akmentar on the steamer")
	await get_tree().create_timer(2.5).timeout
	hud.show_message("")
	await get_tree().create_timer(1.5).timeout
	if is_instance_valid(whitfield):
		await _talk("act3_riverboat", whitfield)
	_attack_at = _t + (6.0 if args.has("auto") else ATTACK_AFTER)


# ---------------------------------------------------------------- the attack

func _attack() -> void:
	step = Step.ATTACK
	print("RESULT act3_riverboat attack t=%.1f progress=%.0f" % [_t, boat.progress])
	hud.toast("Riflemen on the west bank! Boats putting out!", 4.0)
	Objective.set_goal("Defend the steamer")
	player.set_armed(true)
	# The riflemen: ahead on the port (west) bank, in the palms; they shoot as the boat passes.
	for i in BANK_RIFLES:
		var at := level.bank_point(boat.progress + 40.0 + i * 9.0, -1.0, 4.0 + i * 2.0)
		var g := _keeper("Rifle_%d" % (i + 1), at, false)
		g.guard_at = at
	_next_wave()


func _keeper(n: String, at: Vector3, aboard: bool) -> Gunman:
	var g := Gunman.new()
	g.name = n
	g.glb = KEEPER_GLB[keepers.size() % KEEPER_GLB.size()]
	g.foe_player = player
	g.surrender_chance = 0.15
	add_child(g)
	g.global_position = at
	g.target = player
	g.killed.connect(func(_g): _killed += 1)
	if aboard:
		boat.watch(g)
	keepers.append(g)
	return g


## Two skiffs row out from the west bank and come alongside to port.
func _next_wave() -> void:
	var count: int = WAVES[_wave]
	_wave += 1
	_wave_t = 0.0
	_wave_members.clear()
	var halves := [count / 2, count - count / 2]
	for k in 2:
		var slots := [BOARD_AT[k * 2 if _wave == 1 else k * 2 + 1], BOARD_AT[(k * 2 + 2) % BOARD_AT.size()]]
		_skiffs.append(Skiff.launch(self, boat, slots[0] + Vector3(-1.6, 0, 0), halves[k], KEEPER_GLB, ROW_TIME + k * 2.0,
			func(sk: Skiff): _board(sk, slots)))
	hud.toast("Skiffs coming alongside to port!" if _wave == 1 else "More boats! They're throwing fire!", 3.0)
	print("RESULT act3_riverboat wave %d (%d boarders) t=%.1f" % [_wave, count, _t])


func _board(sk: Skiff, slots: Array) -> void:
	for i in sk.crew:
		var local: Vector3 = slots[i % slots.size()] + Vector3(0.4 * (i / slots.size()), RiverBoat.DECK_Y + 0.15, 0.8 * (i / slots.size()))
		var g := _keeper("Keeper_%d_%d" % [_wave, keepers.size() + 1], boat.to_global(local), true)
		_wave_members.append(g)
	sk.empty()
	if _wave == WAVES.size() and _fire.is_empty():
		_set_alight()


## The firebomb: the cabin burns from the stern (fire and smoke on the deck, a red glow).
func _set_alight() -> void:
	for local in [Vector3(0.0, RiverBoat.UPPER_Y + 0.4, 8.0), Vector3(1.2, RiverBoat.DECK_Y + 0.4, 10.2), Vector3(-1.0, RiverBoat.UPPER_Y + 0.4, 3.0)]:
		var f := _flames()
		boat.add_child(f)
		f.position = local
		_fire.append(f)
	print("RESULT act3_riverboat alight t=%.1f" % _t)


func _flames() -> Node3D:
	var root := Node3D.new()
	for spec in [[Color(1.0, 0.5, 0.12, 0.9), 0.5, 0.9, 1.6, 40], [Color(0.18, 0.17, 0.16, 0.65), 1.1, 3.5, 2.5, 30]]:
		var p := CPUParticles3D.new()
		p.amount = spec[4]
		p.lifetime = spec[2]
		p.direction = Vector3.UP
		p.spread = 15.0
		p.gravity = Vector3(0, spec[3], 0)
		p.initial_velocity_min = 0.5
		p.initial_velocity_max = 1.5
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		p.emission_sphere_radius = 0.6
		var qm := QuadMesh.new()
		qm.size = Vector2.ONE * float(spec[1])
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color = spec[0]
		m.albedo_texture = Fx.soft_dot()
		qm.material = m
		p.mesh = qm
		root.add_child(p)
	var glow := OmniLight3D.new()
	glow.light_color = Color(1.0, 0.5, 0.2)
	glow.light_energy = 2.5
	glow.omni_range = 7.0
	root.add_child(glow)
	glow.position = Vector3.UP * 0.6
	return root


func _fighting(list: Array[Gunman]) -> int:
	var n := 0
	for g in list:
		if is_instance_valid(g) and g.is_active() and not g.surrendered:
			n += 1
	return n


func _boarders() -> Array[Gunman]:
	var out: Array[Gunman] = []
	for g in keepers:
		if is_instance_valid(g) and not g.name.begins_with("Rifle"):
			out.append(g)
	return out


func _attack_step(delta: float) -> void:
	_wave_t += delta
	var boarding := false
	for sk in _skiffs:
		boarding = boarding or (is_instance_valid(sk) and (sk as Skiff).crew > 0)
	if _wave < WAVES.size() and not boarding and (_fighting(_wave_members) <= NEXT_WAVE_WHEN or _wave_t > NEXT_WAVE_AFTER):
		_next_wave()
	# The riflemen fall behind as the boat sails on: out of range, they're out of the fight.
	for g in keepers.duplicate():
		if is_instance_valid(g) and g.is_active() and g.name.begins_with("Rifle") and g.global_position.distance_to(boat.global_position) > 70.0:
			keepers.erase(g)
			FightBot.remove_gunman(g)
	if _wave < WAVES.size() or boarding:
		return
	# After the last wave: stragglers go over the side when time's up.
	if _wave_t > WITHDRAW_AFTER:
		for g in _boarders():
			if g.is_active() and not g.surrendered:
				_withdrew += 1
				print("RESULT act3_riverboat %s jumps overboard" % g.name)
				keepers.erase(g)
				FightBot.remove_gunman(g)
	if _fighting(_boarders()) == 0:
		_burning()


# ---------------------------------------------------------------- the boat is lost

func _burning() -> void:
	step = Step.BURNING
	print("RESULT act3_riverboat cleared t=%.1f killed=%d" % [_t, _killed])
	hud.toast("The fire's in the engine room. She's lost. Over the side and make for the west bank!", 5.0)
	Objective.set_goal("Over the side: make for the west bank")
	boat.cruise = 0.0  # the engine dies; she drifts to a stop
	for k in 3:
		var f := _flames()
		boat.add_child(f)
		f.position = Vector3(randf_range(-2.0, 2.0), RiverBoat.DECK_Y + 0.4, randf_range(-6.0, 12.0))
		_fire.append(f)
	await get_tree().create_timer(6.0).timeout
	_stranded()


func _stranded() -> void:
	step = Step.STRANDED
	# Everyone wades ashore: the party and the Americans on the west bank, beside the wreck.
	var ashore := level.bank_point(boat.progress, -1.0, 6.0)
	var toward := (boat.global_position - ashore)
	toward.y = 0
	toward = toward.normalized()
	var side := toward.cross(Vector3.UP)
	player.global_position = ashore
	player.yaw = atan2(-toward.x, -toward.z)
	var i := 1
	for c in companions.values():
		if is_instance_valid(c) and (c as Gunman).is_active():
			(c as Node3D).global_position = ashore + side * (1.5 * i) - toward * 1.0
			i += 1
	for g in americans:
		if is_instance_valid(g) and g.is_active():
			g.global_position = ashore - side * (1.5 * i) - toward * 1.5
			i += 1
	for g in keepers:
		if is_instance_valid(g) and g.surrendered:
			FightBot.remove_gunman(g)  # left on the burning boat; the Americans' story, not ours
	var blackened := StandardMaterial3D.new()
	blackened.albedo_color = Color(0.1, 0.08, 0.07)
	for mi in boat.find_children("*", "MeshInstance3D", true, false):
		if not (mi as Node).get_parent() is CPUParticles3D:
			(mi as MeshInstance3D).material_override = blackened
	if is_instance_valid(whitfield):
		whitfield.reparent(level)
		whitfield.global_position = ashore - side * 2.0 + toward * 1.5
	var lost: Array[String] = []
	for id in _party_start:
		if not Game.in_party(id):
			lost.append(id)
	result = {"result": "boat_lost", "keepers_killed": _killed, "withdrew": _withdrew, "party_losses": lost,
		"americans_standing": _fighting(americans), "t": snappedf(_t, 0.1)}
	Game.set_flag("boat_attacked", true)
	Game.set_flag("riverboat_lost", true)
	Game.set_flag("recognized_bandits", true)
	Game.set_flag("race_step", 5)
	hud.show_message("STRANDED", "The steamer burns in the river. On foot from here, with the Americans.")
	await get_tree().create_timer(3.0).timeout
	hud.show_message("")
	await _talk("act3_stranded", whitfield if is_instance_valid(whitfield) else player)
	_end()


func _end() -> void:
	step = Step.END
	var lost: Array = result.get("party_losses", [])
	var lines := [
		"The Keepers boarded the steamer and burned her.",
		"Attackers killed: %d, fled: %d." % [result.get("keepers_killed", 0), result.get("withdrew", 0)],
		"Companions lost: %s." % (", ".join(lost.map(func(id): return str(id).capitalize())) if not lost.is_empty() else "none"),
		"The wager: %s." % ("accepted" if Game.flag("wager_accepted", false) else ("declined" if Game.flag("wager_offered", false) else "not made")),
	]
	hud.show_message("STRANDED ON THE NILE", "\n".join(lines) + "\n\nThe race to Akmentar: you start last.\nEnter  on to Akmentar (Act 4)")
	Objective.set_goal("")
	print("RESULT act3_riverboat end result=%s killed=%d withdrew=%d party_losses=%s americans_standing=%d player_health=%.0f t=%.1f" % [
		result.get("result", ""), result.get("keepers_killed", 0), result.get("withdrew", 0), lost,
		result.get("americans_standing", 0), player.health, _t])
	finished.emit(result)
	if args.has("auto"):
		TestDriver.auto_end(self, next_scene, 1.5)  # --chain: on, as Enter would


func _on_died() -> void:
	hud.show_message("YOU DIED", "Enter to try again")
	print("RESULT act3_riverboat died step=%s t=%.1f" % [Step.keys()[step], _t])
	if args.has("auto"):
		get_tree().quit(1)


## A conversation, when its file exists (and not in bot runs unless --talk).
func _talk(id: String, speaker: Node3D) -> void:
	if not FileAccess.file_exists("res://dialogue/%s.json" % id) or (args.has("auto") and not args.has("talk")):
		return
	var c := Conversation.new()
	add_child(c)
	if c.start(id, player, speaker):
		await c.finished


# ---------------------------------------------------------------- tick and test bot

func _physics_process(delta: float) -> void:
	_t += delta
	if step == Step.ABOARD and _attack_at >= 0.0 and _t >= _attack_at:
		_attack()
	elif step == Step.ATTACK:
		_attack_step(delta)
	if args.has("auto"):
		player.max_health = 100000.0
		player.health = 100000.0
		if _fight_bot == null:
			_fight_bot = FightBot.new(player)
		if step == Step.ATTACK:
			_fight_bot.fight(delta)
		else:
			FightBot.release_moves()
			Input.action_release("fire")
			Input.action_release("aim")


func _process(_delta: float) -> void:
	if _chase:
		_chase.global_position = boat.to_global(Vector3(-22.0, 9.0, 10.0))
		_chase.look_at(boat.to_global(Vector3(0, 2.0, -2.0)), Vector3.UP)
	if _shots.size() > 0 and _t >= _shots[0]:
		_shots.pop_front()
		_shot("act3_riverboat_%05.1f.png" % _t)
	if args.has("seconds") and _t > float(args.seconds):
		print("RESULT act3_riverboat timeout step=%s" % Step.keys()[step])
		get_tree().quit(1)


func _shot(file: String) -> void:
	if _chase:
		_chase.make_current()
	await RenderingServer.frame_post_draw
	var dir: String = args.get("shot-dir", "user://shots")
	DirAccess.make_dir_recursive_absolute(dir)
	get_viewport().get_texture().get_image().save_png(dir.path_join(file))
	print("RESULT shot %s" % dir.path_join(file))


## A Keepers' rowing boat: a hull and its crew (riding bodies, seated) that rows from the west
## bank to a point alongside the steamer (in the steamer's frame, so it keeps pace), then calls
## `on_alongside` and drifts astern once empty.
class Skiff extends Node3D:
	var boat: RiverBoat
	var alongside := Vector3.ZERO   # boat-local
	var crew := 0
	var row_time := 9.0
	var on_alongside: Callable
	var _from := Vector3.ZERO       # boat-local, where it started
	var _t := 0.0
	var _done := false
	var _bodies: Array[Node3D] = []

	static func launch(parent: Node, b: RiverBoat, local_at: Vector3, n: int, looks: Array, seconds: float, then: Callable) -> Skiff:
		var s := Skiff.new()
		s.boat = b
		s.alongside = local_at
		s.crew = n
		s.row_time = seconds
		s.on_alongside = then
		s._from = local_at + Vector3(-17.0, 0, -14.0)
		parent.add_child(s)
		var wood := StandardMaterial3D.new()
		wood.albedo_color = Color(0.3, 0.2, 0.12)
		var hull := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(1.5, 0.5, 4.6)
		hull.mesh = bm
		hull.material_override = wood
		s.add_child(hull)
		hull.position = Vector3.UP * 0.1
		for i in n:
			var body := Rider.RiderBody.make(looks[i % looks.size()])
			if body == null:
				continue
			s.add_child(body)
			body.position = Vector3(0, -0.1, -1.4 + i * 1.0)
			body.set_driving(true)  # seated at the oars
			s._bodies.append(body)
		s._place()
		return s

	func _physics_process(delta: float) -> void:
		_t += delta
		if _done:
			alongside += Vector3(-0.5, 0, 3.0) * delta  # falls astern, empty
		_place()
		if not _done and _t >= row_time:
			_done = true
			on_alongside.call(self)
		if _done and _t > row_time + 20.0:
			queue_free()

	func _place() -> void:
		if not is_instance_valid(boat):
			return
		var k := clampf(_t / row_time, 0.0, 1.0)
		var local := _from.lerp(alongside, 1.0 - pow(1.0 - k, 2.0)) if not _done else alongside
		var p := boat.to_global(local)
		global_position = Vector3(p.x, 0.05, p.z)
		global_rotation = Vector3(0, boat.global_rotation.y, 0)

	func empty() -> void:
		crew = 0
		for b in _bodies:
			b.queue_free()
		_bodies.clear()
