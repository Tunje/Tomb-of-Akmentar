extends Node3D
## The Temple of the Three as a set piece (DesertTemple), in two moods:
## - Act 8's temple_battle (default): night; the talk act8_temple (he is waiting there), then
##   fight_at_temple: the guardian's servants come in two waves through the pylon, the west gap
##   and the east breach. With temple_known the slab behind the statues opens on a buried
##   passage: reach its far end and you're out (escaped). Clear both waves and you've held it.
## - Act 3's temple_visit (`visit`, act3_temple.tscn): day, no fight; walk round, study the
##   reliefs (the clue if the Egyptologist was given the day: temple_studied), ride on at the gate.
## When it's over `finished` gets the result and Enter goes to `next_scene` (set by the act
## that sends you here, like act3_desert's). Test args (after --): --auto[=fight|escape],
## --party=a,b, --seconds=N, --shots=t1,t2, --shot-dir=path.

signal finished(result: Dictionary)

static var next_scene := "res://act8.tscn"

@export var visit := false

const WAVES := [5, 6]                 # mummies per wave; the second brings a priest

var level: DesertTemple
var player: Player
var hud: Hud
var args := {}
var companions := {}
var result := {}
var servants: Array[Mummy] = []
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
	if args.has("party") or (args.has("auto") and Game.party().is_empty()):
		for id in str(args.get("party", "mahmoud,eleanor")).split(",", false):
			Game.companion(id)["recruited"] = true
	level = DesertTemple.new()
	add_child(level)
	level.set_night(0.0 if visit else 0.85)
	player = Player.new()
	add_child(player)
	player.global_position = level.player_spawn if visit else level.court_centre + Vector3(0, 0, 8)
	player.yaw = 0.0  # north, at the temple
	player.set_armed(not visit)
	hud = Hud.new()
	hud.player = player
	add_child(hud)
	if not visit:
		add_child(CountdownBars.new())
	player.hit_confirmed.connect(hud.on_hit)
	player.damaged.connect(hud.on_damaged)
	player.died.connect(func(): hud.show_message("YOU DIED", "Enter to try again"))
	for s in str(args.get("shots", "")).split(",", false):
		_shots.append(float(s))
	var i := 0
	for id in Game.party():
		var c := Gunman.make_companion(id, player, Characters.glb(id))
		if c:
			add_child(c)
			c.global_position = player.global_position + Vector3(i * 1.4 - 1.4, 0, 2.5)
			companions[id] = c
			i += 1
	level.interactables["temple_relief"].used.connect(func(_by): _relief())
	level.interactables["rear_passage"].used.connect(func(_by): _open_passage())
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if args.size() > 0 else Input.MOUSE_MODE_CAPTURED
	if visit:
		_visit()
	else:
		_battle()


# ---------------------------------------------------------------- Act 3: the visit

func _visit() -> void:
	var leave := Interactable.make(level, level.player_spawn + Vector3(3.0, 1.0, 0), "Ride on", "temple_leave", 1.2)
	leave.used.connect(func(_by): _finish())
	hud.show_message("THE TEMPLE OF THE THREE", "Half dug out, half still under the sand.")
	await get_tree().create_timer(2.5).timeout
	hud.show_message("")
	if args.has("auto"):
		_relief()
		await get_tree().create_timer(0.5).timeout
		_finish()


## The procession reliefs: the clue, if a scholar had the day to read them.
func _relief() -> void:
	if Game.flag("temple_studied", false) or Game.flag("act8_temple", false):
		Conversation.journal_from(["act3_road", "temple", "read off the reliefs"])
		hud.toast("Anubis, Horus, Ra, each with a key; behind them a figure in bronze bands, an eye in its hands. Into the journal.", 5.0)
		result["clue"] = true
	else:
		hud.toast("Gods in procession toward something. Without a scholar's day here, it's just pictures.", 4.0)


# ---------------------------------------------------------------- Act 8: the battle

func _battle() -> void:
	Game.set_flag("act8_temple")
	hud.show_message("THE TEMPLE OF THE THREE", "Night. The fire pillars are lit, and nobody lit them.")
	await get_tree().create_timer(2.5).timeout
	hud.show_message("")
	if not args.has("auto"):
		await _talk("act8_temple")
	elif args.get("auto", "") == "escape":
		Game.set_flag("temple_known")
	if Game.flag("temple_known", false):
		hud.toast("\"There's a way out behind the statues. The priests' door.\"", 4.0)
	var spawns := level.servant_spawns
	for w in WAVES.size():
		if _done or not player.alive:
			return
		hud.toast("They're coming over the walls!" if w > 0 else "Shapes at the gate. Hold the court!", 3.0)
		var wave: Array[Mummy] = []
		for k in WAVES[w]:
			var m := Mummy.new()
			m.priest = w == WAVES.size() - 1 and k == 0
			add_child(m)
			m.global_position = spawns[(k + w * 3) % spawns.size()] + Vector3(randf_range(-2, 2), 0, randf_range(-2, 2))
			m.target = player
			m.wake()
			wave.append(m)
			servants.append(m)
		print("RESULT temple wave %d mummies=%d" % [w + 1, wave.size()])
		if args.get("auto", "") == "escape":
			await get_tree().create_timer(1.0).timeout
			_open_passage()
			await get_tree().create_timer(2.5).timeout
			for k in 10:
				await get_tree().physics_frame
			var map := get_world_3d().navigation_map
			var from := NavigationServer3D.map_get_closest_point(map, level.court_centre)
			var path := NavigationServer3D.map_get_path(map, from, level.rear_exit, true)
			var gap := path[path.size() - 1].distance_to(level.rear_exit) if path.size() > 0 else INF
			print("RESULT temple passage walkable=%s (path end %.1f m off)" % [gap < 1.0, gap])
			player.global_position = level.rear_exit  # the bot walks out
		elif args.has("auto"):
			await get_tree().create_timer(1.0).timeout
			for m in wave:
				m.take_hit("head", 10000.0, Vector3.FORWARD, m.global_position, 1.0, 0.0)
		while not _done and player.alive:
			await get_tree().create_timer(0.5).timeout
			var up := 0
			for m in wave:
				up += int(is_instance_valid(m) and m.is_active())
			if up == 0:
				break
		if not _done and player.alive and w < WAVES.size() - 1:
			hud.toast("A breath. Reload.", 2.5)
			await get_tree().create_timer(4.0).timeout
	if _done or not player.alive:
		return
	result["held"] = true
	Game.set_flag("temple_held")
	print("RESULT temple held")
	_finish()


func _open_passage() -> void:
	if level.rear_open or not Game.flag("temple_known", false):
		return
	hud.toast("The slab grinds down into the floor. A passage, and torchlight.", 3.0)
	print("RESULT temple passage open")
	await level.open_rear_passage()


func _process(delta: float) -> void:
	_t += delta
	# Out through the passage: past its far end and you're away.
	if not visit and not _done and level and level.rear_open and player.alive \
			and player.global_position.distance_to(level.rear_exit) < 3.0:
		result["escaped"] = true
		Game.set_flag("temple_escaped")
		print("RESULT temple escaped")
		_finish()
	if _shots.size() > 0 and _t >= _shots[0]:
		_shots.pop_front()
		_shot("temple_%05.1f.png" % _t)
	if args.has("seconds") and _t > float(args.seconds):
		print("RESULT temple timeout")
		get_tree().quit(1)


# ---------------------------------------------------------------- the end

func _finish() -> void:
	if _done:
		return
	_done = true
	player.set_armed(false)
	print("RESULT temple end visit=%s result=%s" % [visit, result])
	finished.emit(result)
	hud.show_message("THE TEMPLE OF THE THREE", ("You ride on." if visit else
		("Out through the priests' door, into the dunes." if result.get("escaped", false) else "The court is yours. Nothing else moves."))
		+ "\n\nEnter  go on")
	if args.has("auto"):
		await get_tree().create_timer(1.0).timeout
		get_tree().quit(0)


func _talk(id: String) -> void:
	if not FileAccess.file_exists("res://dialogue/%s.json" % id):
		return
	var who: Node3D = player
	for c in companions.values():
		if is_instance_valid(c):
			who = c
			break
	var c := Conversation.new()
	add_child(c)
	c.start(id, player, who)
	await c.finished


func _unhandled_input(event: InputEvent) -> void:
	if args.size() > 0:
		return
	var enter: bool = event is InputEventKey and event.pressed and event.keycode in [KEY_ENTER, KEY_KP_ENTER]
	if _done and enter:
		get_tree().change_scene_to_file(next_scene)  # Game (the flags, the party) carries over
	elif enter and not player.alive:
		get_tree().reload_current_scene()
	elif event.is_action_pressed("party_order"):
		hud.toast("Companions: " + str(Gunman.toggle_party_order(get_tree())))
	elif event.is_action_pressed("ui_cancel") and not ActionMenu.ui_open():
		get_tree().paused = not get_tree().paused
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if get_tree().paused else Input.MOUSE_MODE_CAPTURED
		hud.show_message("PAUSED" if get_tree().paused else "", "Click to resume · Q to quit" if get_tree().paused else "")
	elif event is InputEventKey and event.pressed and event.keycode == KEY_Q and get_tree().paused:
		get_tree().quit()


func _shot(file: String) -> void:
	await RenderingServer.frame_post_draw
	if DisplayServer.get_name() == "headless":
		return
	var dir: String = args.get("shot-dir", "user://shots")
	DirAccess.make_dir_recursive_absolute(dir)
	get_viewport().get_texture().get_image().save_png(dir.path_join(file))
	print("RESULT shot %s" % dir.path_join(file))
