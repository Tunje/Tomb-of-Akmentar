extends Node3D
## Act 9: the last guardian (gameplan/primaryact.md, Act 9), on Act 5's map (AkmentarBelow) with
## -f9's data (actions/act9_plan.json, dialogue/act9_*.json, epilogue/akmentar.json).
## ARRIVAL -> SURFACE -> HALLS -> ROYAL -> RITUAL -> END -> EPILOGUE.
## - Noura al-Khatib and Omar Saqr, the last two guardians, come down with you as party fighters
##   (Gunman, team PARTY). Each death clears noura_alive / omar_alive; both gone and the rite fails.
## - Three threats, one per level: at the top of the stairs (act9_surface; the fight comes up out
##   of the south hall), in the low hall (act9_halls) and before the royal door (act9_royal). Each
##   is a talk: a clue from Acts 4-5 gets you past (end_safe), otherwise its fight (end_fight /
##   event act9_<level>_fight): mummies wake round you and the next level waits until they're down.
## - The burial chamber: the rite at the altar (act9_ritual, event ritual_defence). The singers hold
##   there while minions rise in waves, scarabs pour from the vents, and partway through the
##   guardian wakes and comes for you (lead him off the altar; shooting slows him, nothing kills
##   him). One voice takes longer. Both singers dead: the rite fails.
## - act9_end, then the ending album (EpilogueShow "akmentar").
## Test args (after --): --auto (a bot plays it; RESULT lines), --party=eleanor,hargreaves (who
## comes, quickstart), --clues=clue_greetings,clue_hieroglyphs (known before the descent),
## --voices=1 (Omar falls as the rite starts) | --voices=0 (both do: the rite fails),
## --ritual=N (seconds of chant, for quick runs), --place=act9_end (as if continued from the save
## at the end: straight to the album), --seconds=N, --shots=t1,t2, --shot-dir=path.

enum Step { ARRIVAL, SURFACE, HALLS, ROYAL, RITUAL, END, EPILOGUE }

const RITUAL_TIME := {2: 60.0, 1: 95.0}   # seconds of chant, two voices / one
const WAVE_EVERY := 10.0                   # a wave of minions this often during the rite
const WAVE_SIZE := 2
const SCARABS_EVERY := 3                   # a scarab burst every this many waves
const RITUAL_SLAMS := 2                      # grabs that slam before one kills (Act 5's: 1)
const GUARDIAN_AT := 0.45                  # the guardian wakes this far through the rite
const FIGHT := {"surface": 9, "halls": 13, "royal": 13}  # minions in each level's fight
const TRIGGER := 5.0                       # how close to a level's point its threat starts
const SINGER_HEALTH := 220.0
const AVOID := ["Mock their beliefs"]      # the bot never picks these
const DEFAULT_PARTY := "eleanor,hargreaves"

var level: AkmentarBelow
var player: Player
var hud: Hud
var step := Step.ARRIVAL
var args := {}
var companions := {}
var singers := {}             # "noura" / "omar" -> Gunman
var guardian: Node3D
var points := {}              # "surface" / "halls" / "royal" / "altar" -> Vector3
var _foes: Array[Mummy] = []
var _ritual_t := 0.0
var _ritual_len := 60.0
var _t := 0.0
var _shots: Array[float] = []
var _album: EpilogueShow


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
	Game.act = 9
	if args.has("place"):
		Game.place = str(args.place)  # tests: as if continued from this save
	var finished := str(Game.place) == "act9_end"  # a Continue after the end: the album, not the act again
	if not finished:
		_quickstart()
	level = AkmentarBelow.new()
	add_child(level)
	_light_the_surface()
	Ambience.play(self, "tomb")
	_points()
	player = Player.new()
	add_child(player)
	player.global_position = points.surface + Vector3(0, 0, 2.0)
	player.yaw = 0.0  # north, down the stairs
	player.set_armed(true)
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
	player.hit_confirmed.connect(hud.on_hit)
	player.damaged.connect(hud.on_damaged)
	player.died.connect(func(): hud.show_message("YOU DIED", "Enter to try again"))
	for s in str(args.get("shots", "")).split(",", false):
		_shots.append(float(s))
	if finished:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		print("RESULT act9 continued at act9_end: the album")
		_show_album()
		return
	_spawn_party()
	_spawn_singers()
	Game.event.connect(_on_event)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if args.size() > 0 else Input.MOUSE_MODE_CAPTURED
	Game.place = "act9_start"
	Game.save_game(_slot())
	_arrival()


## Test and start-screen runs: who comes along (hired_<id> too, so the album knows they joined),
## and what you learned before (clue flags).
func _quickstart() -> void:
	# A party that died on the way stays dead: only a start here (no Act 8 behind it) gets a test party.
	var fresh := not Game.flags.has("act8_route")
	if args.has("party") or ((args.has("auto") or Game.flag("quickstart_act", false)) and Game.party().is_empty() and fresh):
		for id in str(args.get("party", DEFAULT_PARTY)).split(",", false):
			Game.apply([{"recruit": id}])
			Game.set_flag("hired_" + id)
	for f in str(args.get("clues", "")).split(",", false):
		Game.set_flag(f)
	if not Game.flags.has("act8_route"):  # started here, not from Act 8: what Act 8 would have left
		Game.set_flag("artifacts_recovered")
		Game.set_flag("act8_choice", "descend")


## The level points on Act 5's map: the stairs' top, the low hall, the antechamber, the altar.
func _points() -> void:
	points.surface = level.stair_top
	var low: Rect2i = AkmentarBelow.CHAMBERS["low"]
	points.halls = level._cell(low.position.y + low.size.y / 2, low.position.x + low.size.x / 2)
	var ante: Rect2i = AkmentarBelow.ANTE
	points.royal = level._cell(ante.position.y + 1, ante.position.x + ante.size.x / 2)
	points.altar = level.royal_pois.get("4", level.guardian_spawn)


func _on_event(name: String) -> void:
	if name == "ritual_defence":
		_ritual()


# ---------------------------------------------------------------- the act

func _arrival() -> void:
	step = Step.ARRIVAL
	hud.show_message("THE LAST GUARDIAN", "Akmentar is overrun. Two of the Keepers are still alive.")
	await get_tree().create_timer(2.5).timeout
	hud.show_message("")
	await _talk("act9_arrival", _speaker())
	Barks.say_any(get_tree(), "entering_tomb")
	await _level("surface", "act9_surface", "The stair down. Something waits at the bottom.")
	hud.toast("Down into the halls.", 3.0)
	await _reach(points.halls)
	await _level("halls", "act9_halls", "The halls. The way down is sealed again.")
	hud.toast("On to the king's door.", 3.0)
	await _reach(points.royal)
	await _level("royal", "act9_royal", "The king's door.")
	level.open_royal_door()
	await get_tree().create_timer(3.2).timeout
	level._nav.bake_navigation_mesh(false)
	hud.toast("Into the burial chamber. To the altar.", 3.0)
	await _reach(points.altar)
	_to_altar()
	match str(args.get("voices", "")):  # tests: who has fallen by the time you reach the altar
		"1": _fell("omar")
		"0":
			_fell("omar")
			_fell("noura")
	await _talk("act9_ritual", _speaker())
	if step != Step.RITUAL:  # end_failed: nobody left to sing
		_end()


## One level's threat: its talk, then (end_fight) its fight, until the minions are down.
func _level(id: String, talk_id: String, line: String) -> void:
	step = {"surface": Step.SURFACE, "halls": Step.HALLS, "royal": Step.ROYAL}[id]
	hud.toast(line, 3.0)
	var end := await _talk(talk_id, _speaker())
	print("RESULT act9 %s -> %s" % [id, end])
	if end != "end_fight":
		return
	var around: Vector3 = points.halls if id == "surface" else points[id]  # the surface's fight comes up the stairs
	_wake_foes(around, int(FIGHT[id]))
	Hints.once("aim_fire", self)
	Hints.once("orders", self)
	hud.toast("They're coming!", 2.5)
	Barks.say_any(get_tree(), "mummy_seen", player.global_position)
	while _active_foes() > 0 and player.alive:
		await get_tree().create_timer(0.3).timeout
	print("RESULT act9 %s cleared t=%.1f" % [id, _t])


func _to_altar() -> void:
	var i := 0
	for id in ["noura", "omar"]:
		var g: Gunman = singers.get(id)
		if g and g.alive:
			g.global_position = points.altar + Vector3(-1.4 if i == 0 else 1.4, 0, 1.2)
			g.set_order("hold")
		i += 1


## The rite: hold out for its length while the singers live.
func _ritual() -> void:
	step = Step.RITUAL
	while Conversation.current != null:  # the chant starts once its talk is over
		await get_tree().process_frame
	var voices := int(Game.flag("noura_alive", false)) + int(Game.flag("omar_alive", false))
	_ritual_len = float(args.get("ritual", RITUAL_TIME.get(voices, 60.0)))
	_ritual_t = 0.0
	hud.toast("The chant begins. Keep them alive!", 3.0)
	var wave := 0
	var next_wave := 1.0
	var guardian_woken := false
	var told := 0
	while _ritual_t < _ritual_len:
		if not player.alive:
			return
		if not _singing():
			break
		await get_tree().create_timer(0.25).timeout
		_ritual_t += 0.25
		if _ritual_t >= next_wave:
			next_wave += WAVE_EVERY
			wave += 1
			_wave(wave)
		if not guardian_woken and _ritual_t >= _ritual_len * GUARDIAN_AT:
			guardian_woken = true
			_wake_guardian()
		var pct := int(_ritual_t / _ritual_len * 100.0)
		if pct >= told + 25 and pct < 100:
			told = pct - pct % 25
			hud.toast("The rite: %d%%" % told, 2.0)
	var done := _singing() and _ritual_t >= _ritual_len
	Game.set_flag("ritual_done", done)
	if not done:
		Game.set_flag("ritual_failed")
	print("RESULT act9 ritual done=%s voices=%d t=%.1f noura=%s omar=%s" % [done, voices, _ritual_t,
		Game.flag("noura_alive", false), Game.flag("omar_alive", false)])
	_settle(done)
	_end()


func _singing() -> bool:
	return Game.flag("noura_alive", false) or Game.flag("omar_alive", false)


## A wave: minions rise round the chamber and go for whoever is nearest (a singer, often).
func _wave(n: int) -> void:
	var at: Array = [level.royal_pois.get("1"), level.royal_pois.get("3"), level.royal_pois.get("5"), level.guardian_spawn]
	for k in WAVE_SIZE:
		var p: Variant = at[(n * WAVE_SIZE + k) % at.size()]
		if p is Vector3:
			_spawn_minion(p + Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)))
	if n % SCARABS_EVERY == 0 and not level.vents.is_empty():
		var ss := _ready_script("res://scripts/scarabs.gd", "burst")
		if ss:
			ss.burst(self, level.vents[n % level.vents.size()], player)
			Barks.say_any(get_tree(), "scarabs", points.altar)
			Hints.once("scarabs", self)


## Partway: the guardian himself, out of his sarcophagus and after you, the one who carried the
## amulet away. Keep him off the altar; shooting him slows him; he can't be killed.
func _wake_guardian() -> void:
	level.open_sarcophagus()
	var gs := _ready_script("res://scripts/guardian.gd", "spawn")
	if gs == null:
		return
	guardian = gs.spawn(self, level.guardian_spawn, player)
	if "slams_left" in guardian:
		guardian.set("slams_left", RITUAL_SLAMS)  # you can't run from the altar: more grace than the escape
	hud.toast("The sarcophagus opens. He's coming for you. Lead him away from the altar!", 3.5)
	Barks.say_any(get_tree(), "guardian_seen", level.guardian_spawn)
	Hints.once("guardian", self)


## The rite's end: done, everything dead falls; failed, the guardian takes the amulet.
func _settle(done: bool) -> void:
	if guardian and is_instance_valid(guardian):
		if guardian.has_method("pause"):
			guardian.call("pause")
		if done:
			guardian.queue_free()
	if done:
		# They fall where they stand (killed, not freed: companions may still be aiming at them).
		for m in get_tree().get_nodes_in_group("mummies"):
			var mm := m as Mummy
			if mm and mm.is_active():
				mm.take_hit("torso", 100000.0, Vector3.DOWN, mm.global_position, 0.0, 0.0)


func _end() -> void:
	if step == Step.END or step == Step.EPILOGUE:
		return
	step = Step.END
	await _talk("act9_end", _speaker())
	print("RESULT act9 end restored=%s failed=%s died_in_tomb=%s party=%s t=%.0f" % [Game.flag("barrier_restored", false),
		Game.flag("ritual_failed", false), Game.flag("player_died_in_tomb", false), Game.party(), _t])
	Game.place = "act9_end"
	Game.save_game(_slot())
	_show_album()


## The ending album, then THE END (also straight from a save made at the end).
func _show_album() -> void:
	step = Step.EPILOGUE
	_album = EpilogueShow.open(self, "akmentar", player)
	print("RESULT act9 album %s" % [EpilogueShow.pick_cards("akmentar").map(func(c: Dictionary) -> String: return "%s:%s" % [c.who, c.variant])])
	_album.closed.connect(func():
		hud.show_message("THE END", "Thank you for playing Tombs of Akmentar."))
	if args.has("auto"):
		for i in 40:
			await get_tree().create_timer(0.1).timeout
			if not is_instance_valid(_album) or _album.is_queued_for_deletion():
				break
			_album.next()
		print("RESULT act9 done t=%.0f" % _t)
		get_tree().quit(0)


# ---------------------------------------------------------------- people

func _spawn_party() -> void:
	var i := 0
	for id in Game.party():
		var c := Gunman.make_companion(id, player, Characters.glb(id))
		if c:
			add_child(c)
			c.global_position = player.global_position + _beside(i)
			companions[id] = c
			i += 1


## The i-th place out to the side of the player and a step ahead, alternating left and right, so
## nobody stands between the camera and the view (x ±(2.4 + k·1.2), z −1 in the player's frame).
func _beside(i: int) -> Vector3:
	var side := -1.0 if i % 2 == 0 else 1.0
	var local := Vector3(side * (2.4 + (i / 2) * 1.2), 0, -1.0)
	return Basis(Vector3.UP, player.yaw) * local


## At the stairs' top the low sun stood behind the Keepers and the party were black shapes against
## it: light them from behind the camera instead (the player starts facing north), with more fill.
func _light_the_surface() -> void:
	if level._sun:
		level._sun.rotation = Vector3(deg_to_rad(-48), 0.0, 0.0)  # pointing north and down
		level._sun.light_energy = maxf(level._sun.light_energy, 1.3)
	if level._env:
		level._env.ambient_light_energy = maxf(level._env.ambient_light_energy, 0.7)


## The last two guardians: party fighters who follow you down, and whose lives are the rite's.
func _spawn_singers() -> void:
	var i := 0
	for id in ["noura", "omar"]:
		var g := Gunman.new()
		g.name = id.capitalize()
		g.team = Gunman.PARTY
		g.companion_id = id
		g.leader = player
		g.glb = Characters.glb(id)
		g.max_health = SINGER_HEALTH
		g.health = SINGER_HEALTH
		g.can_surrender = false
		add_child(g)
		g.global_position = player.global_position + Basis(Vector3.UP, player.yaw) * Vector3(1.6 if i == 0 else -1.6, 0, -2.4)
		g.killed.connect(func(_g: Gunman): _fell(id))
		singers[id] = g
		Game.set_flag(id + "_alive")
		i += 1


## Who the camera talks to: a living singer, else yourself.
func _speaker() -> Node3D:
	for id in ["noura", "omar"]:
		var g: Gunman = singers.get(id)
		if g and is_instance_valid(g) and g.alive:
			return g
	return player


func _fell(id: String) -> void:
	if not Game.flag(id + "_alive", false):
		return
	Game.set_flag(id + "_alive", false)
	print("RESULT act9 fell %s step=%s t=%.1f" % [id, Step.keys()[step], _t])
	var g: Gunman = singers.get(id)
	if g and g.alive:
		g.take_damage(100000.0, g.global_position)  # a test's --voices: they fall now
	if step != Step.END and step != Step.EPILOGUE:
		hud.toast("%s is down!" % id.capitalize(), 3.0)
		var other: Gunman = singers.get("omar" if id == "noura" else "noura")
		if other and is_instance_valid(other) and other.alive:
			Barks.say(other, "ally_down")


func _wake_foes(around: Vector3, n: int) -> void:
	var spots: Array = level.mummy_spawns.duplicate()
	spots.append_array(level.minion_spawns)
	spots.sort_custom(func(a: Vector3, b: Vector3) -> bool: return a.distance_to(around) < b.distance_to(around))
	for k in mini(n, spots.size()):
		_spawn_minion(spots[k])


func _spawn_minion(at: Vector3) -> void:
	var m := Mummy.new()
	m.priest = randf() < 0.25
	add_child(m)
	m.global_position = at
	m.target = player
	m.wake()
	m.killed.connect(func(dead: Mummy) -> void: Barks.say_any(get_tree(), "enemy_down", dead.global_position))
	_foes.append(m)


func _active_foes() -> int:
	var n := 0
	for m in _foes:
		if is_instance_valid(m) and m.is_active():
			n += 1
	return n


# ---------------------------------------------------------------- helpers

## Waits until the player is near `p` (the bot walks there: it takes everyone along).
func _reach(p: Vector3) -> void:
	if args.has("auto"):
		player.global_position = p + Vector3(0, 0.2, 1.5)
		var i := 0
		for g in companions.values() + singers.values():
			if is_instance_valid(g) and g.alive:
				g.global_position = p + Vector3(i * 1.2 - 1.2, 0.2, 3.0)
				i += 1
		await get_tree().create_timer(0.6).timeout
		return
	while player.global_position.distance_to(p) > TRIGGER:
		await get_tree().create_timer(0.25).timeout


## A talk; its end node id. The bot picks the first choice it doesn't avoid (the clue options come
## first in the threat talks, the fight last).
func _talk(id: String, with: Node3D) -> String:
	if not FileAccess.file_exists("res://dialogue/%s.json" % id):
		return ""
	var c := Conversation.new()
	add_child(c)
	var out := [""]
	c.finished.connect(func(e: String) -> void: out[0] = e if e != "" else "<none>")
	c.start(id, player, with if with else player)
	if args.has("auto"):
		while out[0] == "" and is_instance_valid(c):
			await get_tree().process_frame
			if not is_instance_valid(c):
				break
			if c.state == Conversation.State.LINE or c.state == Conversation.State.PLAYER_LINE:
				c.wheel.advance.emit()
			elif c.state == Conversation.State.CHOICES:
				var pick := 0
				for k in c.visible_choices.size():
					if not str(c.visible_choices[k].label) in AVOID:
						pick = k
						break
				c.choose(pick)
	while out[0] == "":
		await get_tree().process_frame
	return out[0]


func _unhandled_input(event: InputEvent) -> void:
	if args.size() > 0:
		return
	if event.is_action_pressed("journal"):
		JournalScreen.toggle(self, player)
	elif event.is_action_pressed("party_order"):
		hud.toast("Companions: " + str(Gunman.toggle_party_order(get_tree())))
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ENTER and not player.alive:
		Checkpoint.retry(self)  # Game as it was on entry, then the scene from its start


func _slot() -> String:
	return "test" if args.size() > 0 else "main"


## A helper's script, only once it exists, compiles and has `entry` (else null).
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


# ---------------------------------------------------------------- test bot

func _process(delta: float) -> void:
	_t += delta
	_idle_bark(delta)
	if _shots.size() > 0 and _t >= _shots[0]:
		_shots.pop_front()
		_shot("act9_%05.1f.png" % _t)
	if args.has("seconds") and _t > float(args.seconds):
		print("RESULT act9 timeout step=%s" % Step.keys()[step])
		get_tree().quit(1)


var _bot_t := 0.0
var _idle_t := 0.0


## Between fights on the way down, someone remarks on the place now and then.
func _idle_bark(delta: float) -> void:
	if not step in [Step.SURFACE, Step.HALLS, Step.ROYAL] or _active_foes() > 0:
		_idle_t = 0.0
		return
	_idle_t += delta
	if _idle_t > 35.0:
		_idle_t = 0.0
		Barks.say_any(get_tree(), "idle_explore", player.global_position)


func _physics_process(delta: float) -> void:
	if not args.has("auto") or not player.alive or Conversation.current != null:
		return
	player.max_health = 1.0e9
	player.health = 1.0e9
	_bot_t -= delta
	if _bot_t > 0.0:
		return
	_bot_t = 0.2
	# Shoot what's nearest a singer (the guardian first, when he's close to one), else nearest you.
	var aim_at: Node3D = null
	var best := INF
	var space := get_world_3d().direct_space_state
	var cands: Array = get_tree().get_nodes_in_group("mummies")
	if guardian and is_instance_valid(guardian):
		cands.append(guardian)
	for m in cands:
		var n := m as Node3D
		if n == null or not is_instance_valid(n) or (n is Mummy and not (n as Mummy).is_active()):
			continue
		if (n as Mummy) and (n as Mummy).state == Mummy.State.DORMANT:
			continue
		var d := n.global_position.distance_to(player.global_position)
		for s in singers.values():
			if is_instance_valid(s) and s.alive:
				d = minf(d, n.global_position.distance_to(s.global_position) * 0.8)
		if n == guardian:
			d *= 0.5
		if d < best and d < 30.0:
			var seen := space.intersect_ray(PhysicsRayQueryParameters3D.create(player.camera.global_position,
				n.global_position + Vector3.UP * 1.2, 1)).is_empty()
			if seen:
				best = d
				aim_at = n
	if aim_at == null:
		Input.action_release("fire")
		Input.action_release("aim")
		return
	var aim := aim_at.global_position + Vector3.UP * 1.3 - player.camera.global_position
	player.yaw = atan2(-aim.x, -aim.z)
	player.pitch = asin(clampf(aim.normalized().y, -1, 1))
	Input.action_press("aim")
	if Input.is_action_pressed("fire"):
		Input.action_release("fire")
	else:
		Input.action_press("fire")


func _shot(file: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var dir: String = args.get("shot-dir", "user://shots")
	DirAccess.make_dir_recursive_absolute(dir)
	get_viewport().get_texture().get_image().save_png(dir.path_join(file))
	print("RESULT shot %s" % dir.path_join(file))
