extends Node3D
## Act 3: the road to Akmentar. The route map (-f9's routes/act3_route.json) and what each road
## brings (routes/act3_plan.json's events), then a night camp and the race, then Act 4:
##   desert ──► the fork (act3_fork) ──► the branch board ──► the temple (act3_temple) or the town
##              (-2d's act3_desert ambush scene: it returns here)
##   riverboat ──► -2d's act3_riverboat scene when it exists, else the talks (act3_riverboat,
##              act3_stranded) with the attack told
##   coast ──► the coast branch board ──► the quiet road (act3_coast) or the town (the ambush scene)
##   then: the night camp (act3_camp, once), the race (act3_race), Enter ──► Act 4.
## The backdrop is the desert road (DesertRoute); the party stands about you.
## Test args (after --): --auto (the bot picks --route=desert|riverboat|coast, default desert,
## and --branch=temple|town|continue, default temple; talks skipped), --seconds=N.

const SET_PIECES := {"ambush_town": "res://act3_desert.tscn", "riverboat_attack": "res://act3_riverboat.tscn",
	"temple_visit": "res://act3_temple.tscn"}
const PIECE_SCRIPTS := {"ambush_town": "res://scripts/acts/act3_desert.gd", "riverboat_attack": "res://scripts/acts/act3_riverboat.gd",
	"temple_visit": "res://scripts/acts/act8_temple.gd"}

var level: DesertRoute
var player: Player
var hud: Hud
var args := {}
var companions := {}
var _events: Array[String] = []
var _board_open := false
var _done := false
var _t := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	child_entered_tree.connect(func(n: Node):
		if n.process_mode == Node.PROCESS_MODE_INHERIT:
			n.process_mode = Node.PROCESS_MODE_PAUSABLE)
	Controls.setup()
	args = TestDriver.parse_args()
	if args.size() > 0:
		get_window().set_flag(Window.FLAG_NO_FOCUS, true)
	Game.act = 3
	if args.has("auto") and not Game.flag("act3_back_from", "") and Game.money < 100:
		Game.money = 300  # a fresh test game: what Act 2 would have left, and a crew
		for id in ["mahmoud", "khalil"]:
			Game.companion(id)["recruited"] = true
			Game.set_flag("hired_" + id)
	level = DesertRoute.new()
	add_child(level)
	Ambience.play(self, "desert")
	player = Player.new()
	add_child(player)
	player.global_position = DesertRoute.road_point(DesertRoute.START_Z) if "START_Z" in DesertRoute else level.player_spawn
	player.set_armed(false)
	hud = Hud.new()
	hud.player = player
	add_child(hud)
	add_child(CountdownBars.new())
	_spawn_party()
	Game.event.connect(func(name: String): _events.append(name))
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if args.size() > 0 else Input.MOUSE_MODE_CAPTURED
	# Back from a set piece (the ambush, the boat): on to the camp and the race.
	var back: String = Game.flag("act3_back_from", "")
	if back != "":
		Game.flags.erase("act3_back_from")
		_after_road()
		return
	hud.show_message("THE ROAD TO AKMENTAR", "Choose your way. The Americans and the Germans are already moving.")
	await get_tree().create_timer(2.5).timeout
	hud.show_message("")
	_board("act3_route")


func _spawn_party() -> void:
	var i := 0
	for id in Game.party():
		var c := Gunman.make_companion(id, player, Characters.glb(id))
		if c:
			add_child(c)
			c.global_position = player.global_position + Vector3(i * 1.4 - 1.4, 0, 2.5)
			companions[id] = c
			i += 1


## A route board; its picks raise events (queued while it's open), run once it closes.
func _board(id: String) -> void:
	_board_open = true
	var b := RouteBoard.open(self, id, player)
	var closed := [false]
	b.finished.connect(func(_picks): closed[0] = true)
	if args.has("auto"):
		await get_tree().create_timer(0.5).timeout
		var want: String = {"act3_route": str(args.get("route", "desert")),
			"act3_desert_branch": str(args.get("branch", "temple")), "act3_coast_branch": str(args.get("branch", "continue"))}.get(b.board_id, "")
		var opts: Array = b.options()
		for i in opts.size():
			if str(opts[i].get("id", "")) == want:
				b.choose(i)
				break
		# A chained board (coast -> its branch) loads in the same board: pick again.
		await get_tree().create_timer(0.3).timeout
		if not closed[0] and is_instance_valid(b) and b.board_id != id:
			for i in b.options().size():
				if str(b.options()[i].get("id", "")) == str(args.get("branch", "continue")):
					b.choose(i)
					break
	while not closed[0]:
		await get_tree().process_frame
	_board_open = false
	await get_tree().create_timer(0.3).timeout
	_run_events()


func _run_events() -> void:
	while not _events.is_empty():
		var e: String = _events.pop_front()
		match e:
			"desert_fork":
				await _talk("act3_fork")
				_board("act3_desert_branch")
				return
			"temple_visit":
				await _talk("act3_temple")
				# Stayed to study: walk round -7f's temple and read the reliefs, then back on the road.
				if Game.flag("temple_studied", false) and _set_piece(e):
					return
			"coast_road":
				await _talk("act3_coast")
			"ambush_town", "riverboat_attack":
				if e == "riverboat_attack":
					await _talk("act3_riverboat")
				if _set_piece(e):
					return  # the scene comes back here (act3_back_from)
				if e == "riverboat_attack":
					hud.toast("Riders on the bank, boats in the reeds: the steamer is shot to pieces and runs aground.", 4.0)
					Game.apply([{"set_flag": "recognized_bandits"}, {"set_flag": ["race_step", 5]}])
					await get_tree().create_timer(1.5).timeout
					await _talk("act3_stranded")
	_after_road()


## Change to a set-piece scene that returns here, if it exists.
func _set_piece(e: String) -> bool:
	var scene: String = SET_PIECES[e]
	if e == "ambush_town" and Game.flag("route_act3_route", "") == "coast" and ResourceLoader.exists("res://act3_coast.tscn"):
		scene = "res://act3_coast.tscn"  # -2d's coast ambush: the same script, with trucks
	if not ResourceLoader.exists(scene) or not ResourceLoader.exists(PIECE_SCRIPTS[e]):
		return false
	var s: GDScript = load(PIECE_SCRIPTS[e])
	if "next_scene" in s:
		s.set("next_scene", "res://act3.tscn")
	Game.set_flag("act3_back_from", e)
	get_tree().change_scene_to_file.call_deferred(scene)
	return true


func _after_road() -> void:
	if not Game.flag("act3_camp_done", false):
		Game.set_flag("act3_camp_done")
		hud.toast("Night on the road. A fire, and time to talk.", 3.0)
		await get_tree().create_timer(1.0).timeout
		await _talk("act3_camp")
	await _talk("act3_race")
	_end()


func _end() -> void:
	_done = true
	Game.place = "act3_end"
	Game.save_game()
	hud.show_message("AKMENTAR IN SIGHT", "Race position: step %d.\n\nEnter  ride into the ruins (Act 4)" % int(Game.flag("race_step", 3)))
	print("RESULT act3 end route=%s branch=%s race_step=%s party=%s day=%d" % [Game.flag("route_act3_route", ""),
		Game.flag("route_act3_desert_branch", Game.flag("route_act3_coast_branch", "")), Game.flag("race_step", 3), Game.party(), Game.day])
	if args.has("auto"):
		await get_tree().create_timer(1.0).timeout
		get_tree().quit(0)


## A talk with the first companion standing (or the road); bots play it through (BotTalk).
func _talk(id: String) -> void:
	if not FileAccess.file_exists("res://dialogue/%s.json" % id):
		return
	var who: Node3D = player
	for c in companions.values():
		if is_instance_valid(c):
			who = c
			break
	if args.has("auto"):
		await BotTalk.run(self, id, player, who)
		return
	var c := Conversation.new()
	add_child(c)
	c.start(id, player, who)
	await c.finished


func _unhandled_input(event: InputEvent) -> void:
	if args.size() > 0:
		return
	if _done and event is InputEventKey and event.pressed and event.keycode in [KEY_ENTER, KEY_KP_ENTER]:
		get_tree().change_scene_to_file("res://act4.tscn")
	elif event.is_action_pressed("journal") and not _board_open:
		JournalScreen.toggle(self, player)


func _process(delta: float) -> void:
	_t += delta
	if args.has("seconds") and _t > float(args.seconds):
		print("RESULT act3 timeout")
		get_tree().quit(1)
