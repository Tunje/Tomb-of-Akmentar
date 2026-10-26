extends Node3D
## Act 8: the artifacts go back to Akmentar, with the guardian after them. -f9's data
## (routes/act8_plan.json, routes/act8_route.json, actions/act8_*.json, dialogue/act8_*.json).
##   Cairo (the Cairo map): buy horses and trucks, book a passage, wire Fletcher, restock (ActionSpots,
##   money only), then "Set out" (the hotel bed): transport counted, who carries the amulet
##   (act8_carrier), the route board ──► the road (the desert road map): the route's talk and its
##   fight (the guardian's servants come for the amulet; none by plane), the last night
##   (act8_last_night, not after the plane), the final choice (act8_final):
##     end_descend ──► Act 9 (res://act9.tscn)        end_sacrifice ──► the epilogue
## Test args (after --): --auto (buys what the bot can, picks --route=..., default the first open;
## talks skipped; the fight is won), --seconds=N.

const PREP_SPOTS := ["caravanserai", "docks", "telegraph", "gunsmith", "outfitter"]
const FIGHT_EVENTS := {"boat_battle": "act8_boat", "temple_battle": "act8_temple", "chariot_chase": "act8_chase", "flight": "act8_plane"}
const MINIONS := 6

var level: Level
var player: Player
var hud: Hud
var args := {}
var companions := {}
var _events: Array[String] = []
var _route_event := ""
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
	Game.act = 8
	if args.has("auto") and Game.party().is_empty():
		for id in ["mahmoud", "khalil", "eleanor"]:
			Game.companion(id)["recruited"] = true
			Game.set_flag("hired_" + id)
		Game.money = maxi(Game.money, 200)
		Game.set_flag("artifacts_recovered")
	var cairo := Cairo.new()
	level = cairo
	add_child(cairo)
	cairo.set_day_time(0.2)
	cairo.place_people({}, ["abdel", "hamdi", "nabil", "zaki", "samira", "clara"])
	for id in PREP_SPOTS:
		if cairo.spots.has(id) and FileAccess.file_exists("res://actions/act8_%s.json" % id):
			ActionSpot.make(cairo, "act8_" + id, cairo.spots[id])
	var bed: Interactable = cairo.interactables.get("hotel_bed")
	if bed:
		bed.prompt = "Set out for Akmentar"
		bed.used.connect(func(_by): _set_out())
	player = Player.new()
	add_child(player)
	player.global_position = cairo.player_spawn
	player.set_armed(false)
	hud = Hud.new()
	hud.player = player
	add_child(hud)
	add_child(CountdownBars.new())
	player.hit_confirmed.connect(hud.on_hit)
	player.damaged.connect(hud.on_damaged)
	player.died.connect(func(): hud.show_message("YOU DIED", "Enter to try again"))
	_spawn_party()
	Game.event.connect(func(name: String): _events.append(name))
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if args.size() > 0 else Input.MOUSE_MODE_CAPTURED
	hud.show_message("THE WAY BACK", "The jars and the amulet must go home to Akmentar, and the guardian is coming for them.\nGet ready in Cairo, then set out from the hotel.")
	await get_tree().create_timer(3.5).timeout
	hud.show_message("")
	if args.has("auto"):
		Game.apply([{"item": ["horse", 4]}, {"item": ["truck", 1]}, {"set_flag": "act8_boat_booked"}])
		_set_out()


func _spawn_party() -> void:
	var i := 0
	for id in Game.party():
		var c := Gunman.make_companion(id, player, Characters.glb(id))
		if c:
			add_child(c)
			c.global_position = player.global_position + Vector3(i * 1.4 - 1.4, 0, 2.5)
			companions[id] = c
			i += 1


# ---------------------------------------------------------------- setting out

func _set_out() -> void:
	if Game.flag("act8_set_out", false):
		return
	Game.set_flag("act8_set_out")
	_count_transport()
	await _talk("act8_carrier")
	var b := RouteBoard.open(self, "act8_route", player)
	var closed := [false]
	b.finished.connect(func(_p): closed[0] = true)
	if args.has("auto"):
		await get_tree().create_timer(0.4).timeout
		var want := str(args.get("route", ""))
		for i in b.options().size():
			if (want == "" and b.reason(i) == "") or str(b.options()[i].get("id", "")) == want:
				b.choose(i)
				break
	while not closed[0]:
		await get_tree().process_frame
	for e in _events:
		if FIGHT_EVENTS.has(e):
			_route_event = e
	_events.clear()
	_to_the_road()


## Horses and trucks: what Game.transport has plus what was bought in Cairo, against the party.
func _count_transport() -> void:
	var people := Game.party().size() + 1
	var horses: int = (Game.transport.horses as Array).size() + int(Game.inventory.get("horse", 0))
	var trucks := 0
	for t in Game.transport.trucks:
		trucks += int(float((t as Dictionary).get("health", 100.0)) > 0.0 or Game.flag("trucks_repaired", false))
	trucks += int(Game.inventory.get("truck", 0))
	Game.set_flag("enough_horses", horses >= people)
	Game.set_flag("enough_trucks", trucks * 4 >= people)


# ---------------------------------------------------------------- the road

## Cairo gives way to the road (the desert road map, whatever the route: a stand-in for each
## route's own set piece), the party about you.
func _to_the_road() -> void:
	hud.toast("Days on the road. The guardian's servants are never far behind.", 3.5)
	await get_tree().create_timer(1.0).timeout
	level.queue_free()
	var road := DesertRoute.new()
	add_child(road)
	level = road
	await get_tree().physics_frame
	player.global_position = DesertRoute.road_point(DesertRoute.START_Z - 40.0)
	var i := 0
	for c in companions.values():
		if is_instance_valid(c):
			(c as Node3D).global_position = player.global_position + Vector3(i * 1.4 - 1.4, 0, 2.5)
			i += 1
	await _talk(FIGHT_EVENTS.get(_route_event, ""))
	if _route_event != "flight":
		await _fight()
		await _talk("act8_last_night")
	await _final()


## The guardian's servants come for the amulet: a wave of mummies down the road at you.
func _fight() -> void:
	player.set_armed(true)
	hud.toast("They're coming for the amulet!", 3.0)
	var ms: Array[Mummy] = []
	for k in MINIONS:
		var m := Mummy.new()
		add_child(m)
		m.global_position = player.global_position + Vector3(randf_range(-10, 10), 0, -18.0 - k * 2.0)
		m.target = player
		m.wake()
		ms.append(m)
	if args.has("auto"):
		for m in ms:
			m.take_hit("head", 10000.0, Vector3.FORWARD, m.global_position, 1.0, 0.0)
	while true:
		await get_tree().create_timer(0.5).timeout
		if not player.alive:
			return
		var up := 0
		for m in ms:
			up += int(is_instance_valid(m) and m.is_active())
		if up == 0:
			break
	hud.toast("The road is quiet again. For now.", 3.0)
	await get_tree().create_timer(1.5).timeout


func _final() -> void:
	var end := ""
	if args.has("auto"):
		end = "end_sacrifice" if args.get("final", "descend") == "sacrifice" else "end_descend"
		Game.set_flag("act8_choice", "sacrifice" if end == "end_sacrifice" else "descend")
		if end == "end_sacrifice":
			Game.apply([{"set_flag": "player_sacrificed"}, {"set_flag": "barrier_restored"}])
	else:
		end = await _talk("act8_final")
	_done = true
	Game.place = "act8_end"
	Game.save_game()
	print("RESULT act8 end route=%s choice=%s carrier=%s party=%s" % [Game.flag("route_act8_route", ""), Game.flag("act8_choice", ""),
		Game.flag("carrier", ""), Game.party()])
	if end == "end_sacrifice" or Game.flag("player_sacrificed", false):
		hud.show_message("")
		EpilogueShow.open(self, "akmentar", player)
	else:
		hud.show_message("THE LAST DOOR", "The guardian waits below. Two of its keepers still live.\n\nEnter  go down into Akmentar (Act 9)")
	if args.has("auto"):
		await get_tree().create_timer(1.0).timeout
		get_tree().quit(0)


## A talk with the first companion standing (or the road); its end id. Skipped in bot runs.
func _talk(id: String) -> String:
	if id == "" or args.has("auto") or not FileAccess.file_exists("res://dialogue/%s.json" % id):
		return ""
	var who: Node3D = player
	for c in companions.values():
		if is_instance_valid(c):
			who = c
			break
	var c := Conversation.new()
	add_child(c)
	c.start(id, player, who)
	return await c.finished


func _unhandled_input(event: InputEvent) -> void:
	if args.size() > 0:
		return
	if _done and not Game.flag("player_sacrificed", false) and event is InputEventKey and event.pressed \
			and event.keycode in [KEY_ENTER, KEY_KP_ENTER]:
		if ResourceLoader.exists("res://act9.tscn"):
			get_tree().change_scene_to_file("res://act9.tscn")
		else:
			hud.toast("Act 9 isn't built yet.", 3.0)
	elif not player.alive and event is InputEventKey and event.pressed and event.keycode in [KEY_ENTER, KEY_KP_ENTER]:
		get_tree().reload_current_scene()
	elif event.is_action_pressed("journal"):
		JournalScreen.toggle(self, player)


func _process(delta: float) -> void:
	_t += delta
	if args.has("seconds") and _t > float(args.seconds):
		print("RESULT act8 timeout")
		get_tree().quit(1)
