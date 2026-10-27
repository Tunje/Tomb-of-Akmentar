extends Node3D
## Act 8's chariot chase (the coast route): the party in trucks on the coast road (CoastRoad,
## about 1.4 km at dusk), the guardian's chariots of the dead coming up behind. You drive the
## lead truck; the drover drives the second; the companions aboard shoot at any chariot in reach
## (you can't fire and steer at once). Chariots draw alongside and slash at a truck; swerve into
## them to ram. A truck wrecked kills everyone aboard (Game kill). Reach the fort at the end of
## the road and it's over. The talk act8_chase plays first.
## When it's over `finished` gets the result and Enter goes to `next_scene` (set by the act that
## sends you here). Test args (after --): --auto (the bot drives, the party shoots), --gunner (with
## --auto: a companion drives (GunnerSeat) and the bot shoots from the back),
## --party=a,b, --trucks=1|2, --seconds=N, --shots=t1,t2, --shot-dir=path.

signal finished(result: Dictionary)

static var next_scene := "res://act8.tscn"

const CHARIOTS := [8, 14]             # in all, for one truck / two
const AT_ONCE := 5
const SHOT_RANGE := 25.0
const HIT_CHANCE := 0.35
const SHOT_DAMAGE := 9.0
const DROVER_GLB := "res://assets/characters/explorer/explorer.glb"  # crew stand-in

var level: CoastRoad
var player: Player
var hud: Hud
var args := {}
var trucks: Array[Truck] = []
var crews := {}                      # Truck -> Array of [companion id ("" = the drover), Rider]
var chariots: Array[Chariot] = []
var result := {"destroyed": 0, "trucks_lost": 0, "dead": []}
var _spawned := 0
var _spawn_t := 6.0
var _gun_t := {}                     # Rider -> seconds to its next shot
var _running := false
var _done := false
var _autopilot: Rider
var _chase_cam: Camera3D           # bot runs: a camera behind the convoy (the hidden player's sits in the cab)
var _t := 0.0
var _shots: Array[float] = []


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
	if args.has("party") or (args.has("auto") and Game.party().is_empty()):
		for id in str(args.get("party", "mahmoud,eleanor,khalil,hargreaves")).split(",", false):
			Game.companion(id)["recruited"] = true
	level = CoastRoad.new()
	add_child(level)
	Ambience.play(self, "river")  # the surf along the coast road
	level.set_dusk(0.8)
	player = Player.new()
	add_child(player)
	player.global_position = level.player_spawn
	player.set_armed(false)
	hud = Hud.new()
	hud.player = player
	add_child(hud)
	add_child(CountdownBars.new())
	player.hit_confirmed.connect(hud.on_hit)
	player.damaged.connect(hud.on_damaged)
	player.seat_swapped.connect(func(text: String): hud.toast(text, 3.0))
	player.died.connect(func():
		_running = false
		hud.show_message("YOU DIED", "Enter to try again"))
	for s in str(args.get("shots", "")).split(",", false):
		_shots.append(float(s))
	_convoy()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if args.size() > 0 else Input.MOUSE_MODE_CAPTURED
	_start()


## How many trucks the expedition still has running (Game.transport), 1 or 2 on the road.
func _truck_count() -> int:
	if args.has("trucks"):
		return clampi(int(args.trucks), 1, 2)
	var n := 0
	for t: Dictionary in Game.transport.get("trucks", []):
		n += int(float(t.get("health", 0)) > 0.0)
	return clampi(n if n > 0 else 2, 1, 2)


## The trucks nose to tail at the start, the player at the first one's wheel, everyone aboard.
func _convoy() -> void:
	var n := _truck_count()
	for i in n:
		var t := Truck.new()
		t.id = "truck_%d" % i
		var z := CoastRoad.START_Z - 8.0 + i * 9.0
		t.position = CoastRoad.road_point(z) + Vector3.UP * 0.6
		add_child(t)
		t.look_at(t.global_position + CoastRoad.road_dir(z), Vector3.UP)
		t.wrecked.connect(_on_wrecked)
		trucks.append(t)
		crews[t] = []
	if args.has("auto") and not args.has("gunner"):
		_autopilot = Rider.mount(self, trucks[0], DROVER_GLB)  # the bot's hands on the wheel
		player.visible = false
		player.set_physics_process(false)
		_chase_cam = Camera3D.new()
		_chase_cam.fov = 65.0
		add_child(_chase_cam)
		_chase_cam.current = true
	else:
		player.enter_vehicle(trucks[0])
	if trucks.size() > 1:
		crews[trucks[1]].append(["", Rider.mount(self, trucks[1], DROVER_GLB)])
	# The party: three behind the player, the rest on the second truck.
	var party := Game.party()
	for k in party.size():
		var t: Truck = trucks[0] if k < 3 or trucks.size() == 1 else trucks[1]
		var seat: int = (k + 1) if t == trucks[0] else (k - 2)
		if seat >= t.seats.size():
			continue  # no room: they stay behind at the camp
		var r := Rider.mount(self, t, Characters.glb(party[k]), seat)
		crews[t].append([str(party[k]), r])
		_gun_t[r] = randf_range(0.5, 1.5)
		if r.body:  # riding, they still talk (Barks finds the "party" group)
			r.body.add_to_group("party")
			r.body.set_meta("bark_id", str(party[k]))


func _start() -> void:
	hud.show_message("THE COAST ROAD", "Dusk. Behind you, on the sand, wheels that make no sound.")
	await get_tree().create_timer(2.5).timeout
	hud.show_message("")
	if not args.has("auto") and FileAccess.file_exists("res://dialogue/act8_chase.json"):
		var c := Conversation.new()
		add_child(c)
		var who: Node3D = player
		for e in crews.get(trucks[0], []):
			if e[0] != "" and (e[1] as Rider).body:
				who = (e[1] as Rider).body
				break
		c.start("act8_chase", player, who)
		await c.finished
	hud.toast("Drive! They're coming up behind. ({crouch}: look back · {swap_seat}: hand a companion the wheel and take the gun.)", 4.0)
	_running = true
	_road_ahead()
	Barks.say_any(get_tree(), "truck_ride")
	if args.has("gunner"):
		# The gunner bot: a companion takes the wheel (GunnerSeat), the player shoots from the back.
		var note := GunnerSeat.swap(player)
		print("RESULT chase gunner swap '%s' seat=%d driver_is_rider=%s armed=%s" % [note, player.gunner_seat,
			trucks[0].driver != player, player.armed])


## The drover (and the bot) follow the road: points every 25 m to the fort.
func _road_ahead() -> void:
	for t in trucks:
		for e in crews[t]:
			if e[0] == "":
				_set_route(e[1], t)
	if _autopilot:
		_set_route(_autopilot, trucks[0])


func _set_route(r: Rider, t: Truck) -> void:
	r.want_speed = t.spec.get("max_speed", 12.5)
	var z := t.global_position.z - 20.0
	var pts: Array[Vector3] = []
	while z > CoastRoad.FINISH_Z - 30.0:
		pts.append(CoastRoad.road_point(z))
		z -= 25.0
	r.path = pts
	r.goal = CoastRoad.road_point(CoastRoad.FINISH_Z - 40.0)


# ---------------------------------------------------------------- the chase

func _physics_process(delta: float) -> void:
	if not _running or _done:
		return
	if args.has("gunner"):
		_gunner_bot()
	var lead := _lead()
	if lead == null:
		return
	# The chariots come up from behind, a few at a time.
	_spawn_t -= delta
	var live := chariots.filter(func(c): return is_instance_valid(c) and c.alive).size()
	if _spawned < _total() and live < AT_ONCE and _spawn_t <= 0.0:
		_spawn_t = randf_range(4.0, 8.0)
		var z := minf(lead.global_position.z + randf_range(55.0, 80.0), CoastRoad.START_Z + 30.0)  # inside the map
		var c := Chariot.make(self, CoastRoad.road_point(z) + Vector3(randf_range(-6, 6), 0, 0), _pick_truck())
		c.destroyed.connect(_on_chariot_down)
		chariots.append(c)
		_spawned += 1
		print("RESULT chase chariot %d at z %.0f (lead z %.0f)" % [_spawned, z, lead.global_position.z])
		if _spawned == 1:
			hud.toast("Chariots! Keep them off the trucks.", 3.0)
	# Retarget chariots whose truck is gone; any left far behind (caught on a rock) come up again.
	for c in chariots:
		if is_instance_valid(c) and c.alive and c.global_position.z - lead.global_position.z > 140.0:
			var z := lead.global_position.z + 60.0
			c.global_position = CoastRoad.road_point(z)
			c.look_at(c.global_position + CoastRoad.road_dir(z), Vector3.UP)
	for c in chariots:
		if is_instance_valid(c) and c.alive and (not is_instance_valid(c.target) or c.target.health <= 0.0):
			c.target = _pick_truck()
	# The companions shoot from the trucks.
	for t in trucks:
		if t.health <= 0.0:
			continue
		for e in crews[t]:
			if e[0] == "" or (e[1] as Rider).seat == 0:
				continue  # the drover, or a companion who has the wheel (the gunner seat)
			var r: Rider = e[1]
			_gun_t[r] = float(_gun_t.get(r, 1.0)) - delta
			if _gun_t[r] > 0.0:
				continue
			_gun_t[r] = randf_range(0.8, 1.5)
			_fire_from(t, r)
	# Into the fort: the chase is won.
	if player.alive and _player_truck_z() < CoastRoad.FINISH_Z:
		_finish()


## How many chariots come in all (fewer against a lone truck).
func _total() -> int:
	return CHARIOTS[mini(trucks.size(), 2) - 1]


var _gunner_t := 0.0
var _swapped_back := false
var _gunner_hits := 0


## --gunner: the player in the back with the gun, aiming at the nearest chariot and firing in
## bursts; halfway down the road it takes the wheel and hands it back again (the swap both ways).
func _gunner_bot() -> void:
	if player.vehicle == null or player.gunner_seat < 0:
		return
	if _gunner_t == 0.0:
		player.hit_confirmed.connect(func(_k: bool, _h: bool): _gunner_hits += 1)
	_gunner_t += get_physics_process_delta_time()
	var best: Chariot = null
	var best_d := 35.0
	for c in chariots:
		if is_instance_valid(c) and c.alive:
			var dist := player.global_position.distance_to(c.global_position)
			if dist < best_d:
				best_d = dist
				best = c
	if best:
		var d := best.global_position + Vector3.UP * 1.3 - (player.global_position + Vector3.UP * 1.6)
		player.yaw = atan2(-d.x, -d.z)
		player.pitch = clampf(atan2(d.y, Vector2(d.x, d.z).length()), -1.0, 1.0)
	_hold("aim", best != null)
	_hold("fire", best != null and fmod(_gunner_t, 0.35) < 0.15)
	if player.ammo[player.current] <= 0:
		player.start_reload()
	if not _swapped_back and trucks[0].global_position.z < -700.0:
		_swapped_back = true
		var a := GunnerSeat.swap(player)
		var at_wheel := player.gunner_seat == -1 and trucks[0].driver == player
		var b := GunnerSeat.swap(player)
		print("RESULT chase gunner swap back '%s' at_wheel=%s, and out again '%s' gunner=%s" % [a, at_wheel, b, player.gunner_seat >= 0])


func _hold(action: String, on: bool) -> void:
	if on:
		Input.action_press(action)
	else:
		Input.action_release(action)


func _lead() -> Truck:
	for t in trucks:
		if t.health > 0.0:
			return t
	return null


func _player_truck_z() -> float:
	return trucks[0].global_position.z if trucks[0].health > 0.0 else INF


## A chariot's quarry: a running truck, most often the player's.
func _pick_truck() -> Truck:
	var live := trucks.filter(func(t): return t.health > 0.0)
	if live.is_empty():
		return null
	return live[0] if randf() < 0.6 or live.size() == 1 else live[1]


func _fire_from(t: Truck, r: Rider) -> void:
	var from: Vector3 = r.body.global_position + Vector3.UP * 1.3 if r.body else t.global_position + Vector3.UP * 2.0
	var best: Chariot = null
	var best_d := SHOT_RANGE
	for c in chariots:
		if is_instance_valid(c) and c.alive:
			var d := from.distance_to(c.global_position)
			if d < best_d:
				best_d = d
				best = c
	if best == null:
		return
	var aim := best.global_position + Vector3(randf_range(-1, 1), 1.4 + randf_range(-0.5, 0.5), randf_range(-1, 1))
	Fx.muzzle_flash(self, from, (aim - from).normalized())
	Fx.tracer(self, from, aim)
	Sfx.play_at(self, Sfx.gunshot(randf_range(0.9, 1.1)), from, -4.0)
	if randf() < HIT_CHANCE:
		best.take_damage(SHOT_DAMAGE)


func _on_chariot_down(_c: Chariot) -> void:
	result.destroyed += 1
	print("RESULT chase chariot down (%d/%d)" % [result.destroyed, _total()])
	hud.toast("One down! (%d of %d)" % [result.destroyed, _total()], 2.0)


## A truck goes: everyone aboard dies with it (the player too, if it's theirs).
func _on_wrecked(t: Truck) -> void:
	result.trucks_lost += 1
	for e in crews.get(t, []):
		var r: Rider = e[1]
		if is_instance_valid(r):
			if r.body:
				r.body.remove_from_group("party")
			r.kill()
		if e[0] != "":
			Game.apply([{"kill": e[0]}])
			(result.dead as Array).append(e[0])
	var who: Array = crews.get(t, []).filter(func(e): return e[0] != "").map(func(e): return str(e[0]).capitalize())
	print("RESULT chase truck lost %s dead=%s" % [t.id, who])
	hud.toast("The truck goes over in a ball of fire.%s" % ("" if who.is_empty() else " %s with it." % ", ".join(who)), 4.0)
	for i in Game.transport.get("trucks", []).size():
		var e: Dictionary = Game.transport.trucks[i]
		if float(e.get("health", 0)) > 0.0:
			e["health"] = 0.0  # the first one still on the books is the one lost
			break
	if player.vehicle == t and player.gunner_seat >= 0:
		player.take_damage(1000.0, t.global_position)  # in the back of it with the gun: no way out
	if t == trucks[0] and args.has("auto"):
		_running = false
		print("RESULT chase lost (the player's truck)")
		await get_tree().create_timer(1.0).timeout
		get_tree().quit(0)


func _finish() -> void:
	if _done:
		return
	_done = true
	_running = false
	result["escaped"] = true
	Game.set_flag("chase_survived")
	Game.set_flag("chase_chariots_destroyed", result.destroyed)
	print("RESULT chase end t=%.0fs destroyed=%d trucks_lost=%d health=%s dead=%s party=%s" % [_t, result.destroyed, result.trucks_lost,
		trucks.map(func(t): return roundi(t.health)), result.dead, Game.party()])
	if args.has("gunner"):
		print("RESULT chase gunner hits=%d (the player's rounds on chariots)" % _gunner_hits)
	finished.emit(result)
	hud.show_message("THE FORT GATE", "%d chariots down. %s\n\nEnter  go on" % [result.destroyed,
		"Everyone made it." if (result.dead as Array).is_empty() else "Lost: %s." % ", ".join((result.dead as Array).map(func(i): return str(i).capitalize()))])
	if args.has("auto"):
		await get_tree().create_timer(1.0).timeout
		get_tree().quit(0)


func _unhandled_input(event: InputEvent) -> void:
	if args.size() > 0:
		return
	var enter: bool = event is InputEventKey and event.pressed and event.keycode in [KEY_ENTER, KEY_KP_ENTER]
	if _done and enter:
		get_tree().change_scene_to_file(next_scene)  # Game (the flags, the dead) carries over
	elif enter and not player.alive:
		Checkpoint.retry(self)  # Game as it was on entry, then the scene from its start
	elif event.is_action_pressed("ui_cancel") and not ActionMenu.ui_open():
		get_tree().paused = not get_tree().paused
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if get_tree().paused else Input.MOUSE_MODE_CAPTURED
		hud.show_message("PAUSED" if get_tree().paused else "", "Click to resume · Q to quit" if get_tree().paused else "")
	elif event is InputEventKey and event.pressed and event.keycode == KEY_Q and get_tree().paused:
		get_tree().quit()


var _looking_back := false
var _warn_t := 0.0


## Driving, you only see a chariot once it's level with you: C (held) looks over your shoulder,
## and one closing from behind gets a word, which side it's on.
func _look_back(delta: float) -> void:
	var t := player.vehicle as Truck
	if t == null or player.gunner_seat >= 0:
		_looking_back = false
		return
	var ahead := -t.global_basis.z
	ahead.y = 0.0
	ahead = ahead.normalized()
	var want := Input.is_action_pressed("crouch")
	if want:
		player.yaw = atan2(ahead.x, ahead.z)  # facing back down the road
	elif _looking_back:
		player.yaw = atan2(-ahead.x, -ahead.z)  # and forward again
	_looking_back = want
	_warn_t -= delta
	if _warn_t > 0.0 or not _running:
		return
	for c in chariots:
		if not is_instance_valid(c) or not c.alive:
			continue
		var rel := c.global_position - t.global_position
		rel.y = 0.0
		if rel.length() < 35.0 and rel.length() > 7.0 and ahead.dot(rel.normalized()) < -0.5:
			var right := ahead.cross(Vector3.UP)
			hud.toast("A chariot behind you, %s! (hold {crouch} to look back)" % ("right" if rel.dot(right) > 0.0 else "left"), 2.5)
			_warn_t = 7.0
			break


func _process(delta: float) -> void:
	_t += delta
	_look_back(delta)
	if _autopilot and trucks[0].health > 0.0:
		player.global_position = trucks[0].global_position  # the hidden bot rides along (HUD)
		var back := trucks[0].global_basis.z
		back.y = 0.0
		_chase_cam.global_position = trucks[0].global_position + back.normalized() * 15.0 + Vector3.UP * 6.0
		_chase_cam.look_at(trucks[0].global_position - back.normalized() * 6.0 + Vector3.UP * 1.5, Vector3.UP)
	if _shots.size() > 0 and _t >= _shots[0]:
		_shots.pop_front()
		_shot("chase_%05.1f.png" % _t)
	if args.has("seconds") and _t > float(args.seconds):
		print("RESULT chase timeout z=%.0f destroyed=%d" % [trucks[0].global_position.z, result.destroyed])
		get_tree().quit(1)


func _shot(file: String) -> void:
	await RenderingServer.frame_post_draw
	if DisplayServer.get_name() == "headless":
		return
	var dir: String = args.get("shot-dir", "user://shots")
	DirAccess.make_dir_recursive_absolute(dir)
	get_viewport().get_texture().get_image().save_png(dir.path_join(file))
	print("RESULT shot %s" % dir.path_join(file))
