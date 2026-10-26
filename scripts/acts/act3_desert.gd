extends Node3D
## Act 3, the desert route to the town (gameplan/primaryact.md, Act 3: "Desert -> Town: ambushed
## by a mysterious group", starting position Step 4). ROAD -> AMBUSH -> AFTER -> TOWN -> END.
## The convoy rides north up the desert road: the player on a horse, the companions on theirs,
## the hired drover with the supply truck behind. Where the road dips through the wadi the
## ambush springs (RoadAmbush): fight from the rocks, or stay in the saddle and ride through.
## Afterwards a talk with a companion (-f9's dialogue/act3_after_ambush.json: who were they?), then
## on to the town and its elder, Rashid Amin (act3_town.json). The talks are skipped in --auto runs
## unless --talk is given, and when their files are missing.
## Test args after "--": --auto (a bot plays it)  --plan=fight|ride (the bot's choice, default
## fight)  --party=mahmoud,khalil  --shots=t1,t2  --shot-dir=path  --cam=overview (shots from
## above the wadi)  --seconds=N  --seed=N.

## Hand-over for act3.gd: where Enter goes at the end (set before changing to this scene), and
## a signal when the summary is up (the flags are all set by then).
signal finished(result: Dictionary)

enum Step { ROAD, AMBUSH, AFTER, TOWN, END }

static var next_scene := "res://act4.tscn"

const DROVER_GLB := "res://assets/characters/explorer/explorer.glb"  # crew stand-in

var level: DesertRoute
var player: Player
var hud: Hud
var step := Step.ROAD
var args := {}
var ambush: RoadAmbush
var horse: Horse                  # the player's
var truck: Truck
var drover: Rider
var riders := {}                  # companion id -> Rider, while they ride
var result := {}
var elder: Npc
var _t := 0.0
var _shots: Array[float] = []
var _overview: Camera3D
var _bot_unseen := 0.0
var _bot_path := PackedVector3Array()
var _bot_repath := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
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
	Game.set_flag("route", "desert")
	Game.set_flag("route_branch", "town")
	level = DesertRoute.new()
	add_child(level)
	player = Player.new()
	add_child(player)
	player.global_position = level.start_point
	player.yaw = 0.0  # north, up the road
	player.set_armed(false)
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
	_convoy()
	if args.get("cam", "") == "overview":
		_overview = Camera3D.new()
		add_child(_overview)
		_overview.global_position = level.ambush_centre + Vector3(-34, 30, 22)
		_overview.look_at(level.ambush_centre + Vector3(4, 0, -6), Vector3.UP)
		_overview.fov = 60.0
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if args.size() > 0 else Input.MOUSE_MODE_CAPTURED
	_road()


func _unhandled_input(event: InputEvent) -> void:
	if args.size() > 0:
		return
	if step == Step.END and event is InputEventKey and event.pressed and event.keycode in [KEY_ENTER, KEY_KP_ENTER]:
		get_tree().change_scene_to_file(next_scene)  # Game (race_step, the party) carries over
	elif event is InputEventKey and event.pressed and event.keycode in [KEY_ENTER, KEY_KP_ENTER] and not player.alive:
		get_tree().reload_current_scene()
	elif event.is_action_pressed("party_order"):
		hud.toast("Companions: " + str(Gunman.toggle_party_order(get_tree())))
	elif event.is_action_pressed("ui_cancel"):
		get_tree().paused = not get_tree().paused
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if get_tree().paused else Input.MOUSE_MODE_CAPTURED
		hud.show_message("PAUSED" if get_tree().paused else "", "Click to resume · Q to quit" if get_tree().paused else "")
	elif event is InputEventKey and event.pressed and event.keycode == KEY_Q and get_tree().paused:
		get_tree().quit()
	elif event is InputEventMouseButton and event.pressed and get_tree().paused:
		get_tree().paused = false
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		hud.show_message("")


# ---------------------------------------------------------------- the convoy

## The player in the saddle at the head, each companion on a horse behind, the truck at the back.
func _convoy() -> void:
	var z := DesertRoute.START_Z
	horse = Horse.make(level, "bay", level.start_point)
	player.enter_vehicle(horse)
	var i := 0
	for id in Game.party():
		var slot := _slot(z, i)
		var h := Horse.make(level, "horse_" + str(id), slot)
		riders[id] = Rider.mount(self, h, Characters.glb(id))
		i += 1
	truck = Truck.new()
	truck.name = "SupplyTruck"
	level.add_child(truck)
	truck.global_position = DesertRoute.road_point(z + _truck_gap()) + Vector3.UP * 0.3
	drover = Rider.mount(self, truck, DROVER_GLB)


## Where companion `i` rides: behind the player, alternating sides of the road.
func _slot(z: float, i: int) -> Vector3:
	var p := DesertRoute.road_point(z + 5.0 + 3.5 * i)
	var side := DesertRoute.road_dir(p.z).cross(Vector3.UP)
	return p + side * (1.6 if i % 2 == 0 else -1.6)


func _truck_gap() -> float:
	return 8.0 + 3.5 * riders.size()


## While the convoy rides: everyone keeps their place behind the player.
func _keep_formation() -> void:
	var z := player.global_position.z
	var lead_speed := horse.speed if is_instance_valid(horse) else 0.0
	var i := 0
	for id in riders:
		var r: Rider = riders[id]
		if not is_instance_valid(r):
			continue
		var slot := _slot(z, i)
		var behind := slot.distance_to(r.mount_node.global_position)
		r.goal = slot
		r.want_speed = clampf(maxf(lead_speed, 1.7) + (behind - 1.0) * 0.6, 1.7, Horse.GALLOP)
		i += 1
	if drover and is_instance_valid(drover) and drover.body:
		var slot := DesertRoute.road_point(z + _truck_gap())
		drover.goal = slot
		drover.want_speed = clampf(maxf(lead_speed, 1.5) + (slot.distance_to(truck.global_position) - 1.0) * 0.5, 0.0, 9.0)


# ---------------------------------------------------------------- the act

func _road() -> void:
	step = Step.ROAD
	hud.show_message("THE DESERT ROAD", "Three days across the sand to the town. Akmentar lies beyond.")
	await get_tree().create_timer(2.5).timeout
	hud.show_message("")
	hud.toast("W / S speed up and slow down · A / D steer · E get down", 4.0)


func _ambush() -> void:
	step = Step.AMBUSH
	print("RESULT act3_desert ambush t=%.1f at z=%.0f" % [_t, player.global_position.z])
	var all_riders := riders.duplicate()
	riders.clear()  # RoadAmbush takes them down off their horses
	ambush = RoadAmbush.start(level, player, {
		"centre": level.ambush_centre, "posts": level.bandit_posts,
		"rider_from": level.rider_from, "rider_to": level.rider_to,
		"finish_z": DesertRoute.FINISH_Z,
	}, {"truck": truck, "drover": drover, "riders": all_riders, "player_horse": horse},
		int(args.get("seed", "-1")))
	ambush.riders_coming.connect(func(): hud.toast("Riders! Coming down the wadi from the east!", 3.0))
	hud.toast("Ambush! Get down into cover (E) or ride on through!", 4.0)
	result = await ambush.finished
	_after()


func _after() -> void:
	step = Step.AFTER
	var rode := str(result.get("result", "")) == "drove_through"
	Game.set_flag("ambush_town", true)
	Game.set_flag("ambush_result", result.get("result", ""))
	Game.set_flag("supplies_lost", rode)  # the stalled truck is left behind on the road
	Game.set_flag("race_step", 4)
	Game.set_flag("ambush_prisoners", int(result.get("surrendered", 0)))
	# The Keepers' horses aren't ours (Horse records every horse in Game.transport).
	Game.transport["horses"] = (Game.transport.get("horses", []) as Array).filter(func(e):
		return not (e is Dictionary and str(e.get("id", "")).begins_with("keeper_")))
	hud.toast("You broke through. The truck and its supplies stay behind in the wadi." if rode
		else "The attackers are gone. Whoever sent them wanted you off this road.", 4.0)
	await get_tree().create_timer(3.0).timeout
	await _talk("act3_after_ambush", _nearest_companion())
	_on_to_town()


## Who the after-ambush talk is with: the nearest companion still standing, else the truck.
func _nearest_companion() -> Node3D:
	var best: Node3D = truck if is_instance_valid(truck) else player
	var bd := INF
	for c in ambush.companions.values():
		if is_instance_valid(c) and (c as Gunman).is_active():
			var d := player.global_position.distance_to((c as Node3D).global_position)
			if d < bd:
				bd = d
				best = c
	return best


func _on_to_town() -> void:
	step = Step.TOWN
	var at := DesertRoute.road_point(DesertRoute.TOWN_Z + 6.0)
	elder = Npc.make(level, "rashid", at + DesertRoute.road_dir(at.z).cross(Vector3.UP) * 3.0, "act3_town", Characters.glb("rashid"))
	hud.toast("On to the town: north up the road.", 4.0)
	if args.has("auto"):
		# The bot skips the ride: the party is at the edge of town.
		if player.vehicle:
			player.exit_vehicle()
		player.global_position = DesertRoute.road_point(DesertRoute.TOWN_Z + 18.0)
		var i := 0
		for c in ambush.companions.values():
			if is_instance_valid(c) and (c as Gunman).is_active():
				(c as Node3D).global_position = _slot(DesertRoute.TOWN_Z + 16.0, i)
				i += 1


func _town() -> void:
	step = Step.END  # the talk runs first; _end shows the summary
	print("RESULT act3_desert town t=%.1f" % _t)
	await _talk("act3_town", elder)
	_end()


## A conversation, when its file exists (and not in bot runs unless --talk).
func _talk(id: String, speaker: Node3D) -> void:
	if not FileAccess.file_exists("res://dialogue/%s.json" % id) or (args.has("auto") and not args.has("talk")):
		return
	var c := Conversation.new()
	add_child(c)
	if c.start(id, player, speaker):
		await c.finished


func _end() -> void:
	step = Step.END
	var lost: Array = result.get("party_losses", [])
	var lines := [
		"You %s." % ("rode through the ambush" if result.get("result", "") == "drove_through" else "fought off the ambush"),
		"Attackers killed: %d, gave up: %d, fled: %d." % [result.get("bandits_killed", 0), result.get("surrendered", 0), result.get("withdrew", 0)],
		"Companions lost: %s." % (", ".join(lost.map(func(id): return str(id).capitalize())) if not lost.is_empty() else "none"),
		"Horses lost: %d." % (result.get("horses_lost", []) as Array).size(),
	]
	hud.show_message("THE ROAD TO THE TOWN", "\n".join(lines) + "\n\nThe race to Akmentar: you start fourth.\nEnter  on to Akmentar (Act 4)")
	print("RESULT act3_desert end result=%s killed=%d surrendered=%d withdrew=%d party_losses=%s horses_lost=%s truck=%.0f player_health=%.0f t=%.1f" % [
		result.get("result", ""), result.get("bandits_killed", 0), result.get("surrendered", 0), result.get("withdrew", 0),
		lost, result.get("horses_lost", []), float(result.get("truck_health", 0.0)), player.health, _t])
	finished.emit(result)
	if args.has("auto"):
		await get_tree().create_timer(1.5).timeout
		get_tree().quit(0)


func _on_died() -> void:
	hud.show_message("YOU DIED", "Enter to try again")
	print("RESULT act3_desert died step=%s t=%.1f" % [Step.keys()[step], _t])
	if args.has("auto"):
		get_tree().quit(1)


# ---------------------------------------------------------------- tick and test bot

func _physics_process(delta: float) -> void:
	_t += delta
	if step == Step.ROAD:
		_keep_formation()
		if player.global_position.z < DesertRoute.AMBUSH_Z:
			_ambush()
	elif step == Step.TOWN and player.global_position.z < DesertRoute.TOWN_Z + 14.0:
		_town()
	if args.has("auto"):
		_bot(delta)


func _process(_delta: float) -> void:
	if _shots.size() > 0 and _t >= _shots[0]:
		_shots.pop_front()
		_shot("act3_desert_%05.1f.png" % _t)
	if args.has("seconds") and _t > float(args.seconds):
		print("RESULT act3_desert timeout step=%s" % Step.keys()[step])
		get_tree().quit(1)


func _shot(file: String) -> void:
	if _overview:
		_overview.make_current()
	await RenderingServer.frame_post_draw
	var dir: String = args.get("shot-dir", "user://shots")
	DirAccess.make_dir_recursive_absolute(dir)
	get_viewport().get_texture().get_image().save_png(dir.path_join(file))
	print("RESULT shot %s" % dir.path_join(file))


func _bot(delta: float) -> void:
	player.max_health = 100000.0
	player.health = 100000.0
	var plan: String = args.get("plan", "fight")
	if player.vehicle:
		if step == Step.AMBUSH and plan == "fight":
			_release_moves()
			player.exit_vehicle()
			player.set_armed(true)
			return
		_bot_ride(step == Step.AMBUSH)
	elif step == Step.AMBUSH:
		_bot_fight(delta)
	elif step == Step.TOWN:
		_bot_walk(DesertRoute.road_point(DesertRoute.TOWN_Z), delta)
	else:
		_release_moves()
		Input.action_release("fire")
		Input.action_release("aim")


## In the saddle: up the road at a trot (a gallop once the shooting starts).
func _bot_ride(gallop: bool) -> void:
	var z := player.global_position.z
	var ahead := DesertRoute.road_point(z - 12.0)
	var d := ahead - player.global_position
	var fwd := -horse.global_basis.z
	var err := Vector3(fwd.x, 0, fwd.z).normalized().signed_angle_to(Vector3(d.x, 0, d.z).normalized(), Vector3.UP)
	_press("move_left", err > 0.06)
	_press("move_right", err < -0.06)
	_press("move_forward", gallop or horse.speed < 3.4)
	if args.has("trace") and fmod(_t, 1.0) < get_physics_process_delta_time():
		print("TRACE ride z=%.1f x=%.1f road_x=%.1f speed=%.1f target=%.1f wall=%s err=%.2f" % [z, player.global_position.x,
			DesertRoute.road_x(z), horse.speed, horse.target_speed, horse.is_on_wall(), err])


## On foot: shoot the nearest bandit in sight; with none in sight for a while, walk toward the
## nearest one (the navmesh path).
func _bot_fight(delta: float) -> void:
	var space := get_world_3d().direct_space_state
	var best: Gunman = null
	var nearest: Gunman = null
	var bd := 60.0
	var nd := INF
	for n in get_tree().get_nodes_in_group("gunmen"):
		var g := n as Gunman
		if g == null or g.team != Gunman.BANDITS or not g.alive or g.surrendered:
			continue
		var d := player.global_position.distance_to(g.global_position)
		if d < nd:
			nd = d
			nearest = g
		var ray := PhysicsRayQueryParameters3D.create(player.camera.global_position, g.global_position + Vector3.UP * 1.3, 1)
		if d < bd and space.intersect_ray(ray).is_empty():
			bd = d
			best = g
	if best == null:
		Input.action_release("fire")
		Input.action_release("aim")
		_bot_unseen += delta
		if nearest and _bot_unseen > 3.0:
			_bot_walk(nearest.global_position, delta)
		else:
			_release_moves()
		return
	_bot_unseen = 0.0
	_release_moves()
	var aim := best.global_position + Vector3.UP * 1.3 - player.camera.global_position
	var want_yaw := atan2(-aim.x, -aim.z)
	var want_pitch := asin(clampf(aim.normalized().y, -1, 1))
	player.yaw = lerp_angle(player.yaw, want_yaw, minf(delta * 10.0, 1.0))
	player.pitch = lerpf(player.pitch, want_pitch, minf(delta * 10.0, 1.0))
	Input.action_press("aim")
	_press("fire", absf(angle_difference(player.yaw, want_yaw)) < deg_to_rad(2.5) and fmod(_t, 0.4) < delta)


func _bot_walk(to: Vector3, delta: float) -> void:
	_bot_repath -= delta
	if _bot_repath <= 0.0 or _bot_path.is_empty():
		_bot_repath = 1.0
		_bot_path = NavigationServer3D.map_get_path(get_world_3d().navigation_map, player.global_position, to, true)
	while _bot_path.size() > 1 and Vector2(_bot_path[0].x - player.global_position.x, _bot_path[0].z - player.global_position.z).length() < 1.0:
		_bot_path.remove_at(0)
	if _bot_path.is_empty():
		_release_moves()
		return
	var d := _bot_path[0] - player.global_position
	player.yaw = lerp_angle(player.yaw, atan2(-d.x, -d.z), minf(delta * 8.0, 1.0))
	player.pitch = lerpf(player.pitch, 0.0, minf(delta * 4.0, 1.0))
	_press("move_forward", true)


func _press(action: String, on: bool) -> void:
	if on:
		Input.action_press(action)
	else:
		Input.action_release(action)


func _release_moves() -> void:
	for a in ["move_forward", "move_back", "move_left", "move_right"]:
		Input.action_release(a)
