extends Node3D
## Act 8's flight (the plane route): Fletcher's biplane from a desert airstrip outside Cairo to
## Akmentar, with the artifacts and ONE companion (-f9's act8_plane picks who: plane_companion).
## STRIP -> TAKEOFF -> FLIGHT -> STORM -> LANDING -> END.
## - At the strip: the talk act8_plane with Fletcher by his plane.
## - The takeoff and the flight south over the desert at dusk; the camera rides behind the plane.
## - The guardian comes after the amulet: a sandstorm wall rises behind and catches up. Its gusts
##   roll the plane: hold it level with A / D. Let it roll too far and it drops: the plane takes
##   damage and the companion is thrown about (hurt; twice and they're injured).
## - A rough landing in the ruins at Akmentar (AkmentarSurface): the plane won't fly again.
## When it's over `finished` gets the result and Enter goes to `next_scene` (set by act8.gd).
## Test args (after --): --auto[=steady|sloppy] (a bot holds the plane level, or doesn't),
## --companion=<id>, --seconds=N, --shots=t1,t2, --shot-dir=path.

signal finished(result: Dictionary)

static var next_scene := "res://act8.tscn"

enum Step { STRIP, TAKEOFF, FLIGHT, STORM, LANDING, END }

const CRUISE := 45.0          # m/s
const ALTITUDE := 85.0
const CALM_SECS := 12.0
const STORM_SECS := 32.0
const LIMIT := 0.6            # rad of roll before it drops
const LIMIT_SECS := 0.5       # held that long
const STEER := 1.5            # rad/s of correction at full A / D
const LANDING_SPOT := Vector3(24, 0, 128)  # at Akmentar, west of our camp

var level: Level
var plane: Biplane
var player: Player
var hud: Hud
var args := {}
var step := Step.STRIP
var result := {"drops": 0, "gusts": 0, "plane_damage": 0.0, "companion": "none", "hurt": 0}
var companion := "none"
var _cam: Camera3D
var _fade: ColorRect
var _bodies: Array[Node3D] = []     # seated: [front, rear]
var _storm: MeshInstance3D
var _storm_mat: StandardMaterial3D
var _roll_rate := 0.0
var _over_t := 0.0
var _gust_t := 2.0
var _gust := 0.0                    # rad/s pushing the roll now
var _gust_left := 0.0
var _phase_t := 0.0
var _storm_z := 0.0
var _look_back_t := 0.0             # s left of a look back at the storm
var _looked_mid := false
var _t := 0.0
var _shots: Array[float] = []
var _done := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	child_entered_tree.connect(func(n: Node):
		if n.process_mode == Node.PROCESS_MODE_INHERIT:
			n.process_mode = Node.PROCESS_MODE_PAUSABLE)
	Controls.setup()
	args = TestDriver.parse_args()
	if args.size() > 0:
		get_window().set_flag(Window.FLAG_NO_FOCUS, true)
	if args.has("auto") and Game.party().is_empty():
		for id in ["eleanor", "mahmoud"]:
			Game.companion(id)["recruited"] = true
	Game.act = 8
	level = FlightRange.new()
	add_child(level)
	Ambience.play(self, "desert")
	plane = Biplane.new()
	add_child(plane)
	plane.global_position = FlightRange.STRIP_START
	player = Player.new()
	add_child(player)
	player.global_position = level.player_spawn
	player.yaw = PI * 0.5  # looking west, at the plane
	player.set_armed(false)
	hud = Hud.new()
	hud.player = player
	add_child(hud)
	add_child(CountdownBars.new())
	_cam = Camera3D.new()
	_cam.fov = 60.0
	_cam.far = 3000.0
	add_child(_cam)
	var layer := CanvasLayer.new()
	layer.layer = 50
	add_child(layer)
	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 0)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_fade)
	for s in str(args.get("shots", "")).split(",", false):
		_shots.append(float(s))
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if args.size() > 0 else Input.MOUSE_MODE_CAPTURED
	_strip()


# ---------------------------------------------------------------- the airstrip

func _strip() -> void:
	step = Step.STRIP
	var fletcher := Npc.make(level, "fletcher", FlightRange.STRIP_START + Vector3(3.2, 0, -1.5), "", Characters.glb("fletcher"))
	fletcher.face_towards(player.global_position)
	hud.show_message("THE AIRSTRIP", "Fletcher's biplane, engine ticking as it cools. One seat to spare.")
	await get_tree().create_timer(2.5).timeout
	hud.show_message("")
	if args.has("companion"):
		Game.set_flag("plane_companion", str(args.companion))
	elif FileAccess.file_exists("res://dialogue/act8_plane.json"):
		if args.has("auto"):
			await BotTalk.run(self, "act8_plane", player, fletcher)
		else:
			var c := Conversation.new()
			add_child(c)
			c.start("act8_plane", player, fletcher)
			await c.finished
	companion = str(Game.flag("plane_companion", "none"))
	if companion != "none" and not Game.in_party(companion):
		companion = "none"
	result.companion = companion
	print("RESULT flight companion=%s" % companion)
	fletcher.queue_free()
	_takeoff()


# ---------------------------------------------------------------- the flight

func _takeoff() -> void:
	step = Step.TAKEOFF
	# Everyone aboard: the companion in front, you in the middle, Fletcher at the stick.
	_seat(1)
	if companion != "none":
		_bodies.append(_seat_body(0, Characters.glb(companion)))
	_bodies.append(_seat_body(2, Characters.glb("fletcher")))
	_cam.current = true
	hud.toast("The engine catches. Fletcher opens the throttle.", 3.0)
	plane.spin = 1.0
	# Down the strip, then up.
	var tw := create_tween()
	tw.tween_property(plane, "global_position", FlightRange.STRIP_START + Vector3(0, 0, -260), 6.0).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(plane, "pitch", 0.0, 6.0)
	tw.tween_property(plane, "pitch", 0.16, 0.8)
	tw.tween_property(plane, "global_position", FlightRange.STRIP_START + Vector3(0, ALTITUDE, -260 - CRUISE * 7.0), 7.0).set_trans(Tween.TRANS_SINE)
	tw.parallel().tween_property(plane, "pitch", 0.0, 7.0)
	await tw.finished
	step = Step.FLIGHT
	_phase_t = 0.0
	hud.toast("South over the desert. Akmentar by nightfall.", 3.5)
	Objective.set_goal("Fly south to Akmentar")


## The player rides in seat `k` (seated pose, no walking).
func _seat(k: int) -> void:
	player.set_physics_process(false)
	player.velocity = Vector3.ZERO
	if player.explorer:
		player.explorer.set_driving(true)
	player.set_meta("plane_seat", k)


func _seat_body(k: int, glb: String) -> Node3D:
	var b := Rider.RiderBody.make(glb)
	if b == null:
		return null
	plane.seats[k].add_child(b)
	b.position = Vector3.DOWN * 0.55
	b.set_driving(true)
	return b


func _process(delta: float) -> void:
	_t += delta
	if step in [Step.TAKEOFF, Step.FLIGHT, Step.STORM, Step.LANDING]:
		var seat: Marker3D = plane.seats[int(player.get_meta("plane_seat", 1))]
		player.global_position = seat.global_position - Vector3.UP * 0.55
		player.model.rotation.y = plane.global_rotation.y
		_follow_cam(delta)
	if step == Step.FLIGHT or step == Step.STORM:
		_fly(delta)
	if _shots.size() > 0 and _t >= _shots[0]:
		_shots.pop_front()
		_shot("flight_%05.1f.png" % _t)
	if args.has("seconds") and _t > float(args.seconds):
		print("RESULT flight timeout step=%d" % step)
		get_tree().quit(1)


## Behind and above the plane, swaying with it; the storm shakes it.
func _follow_cam(delta: float) -> void:
	if _look_back_t > 0.0:
		# The look back: from ahead of the plane, past it, at the wall of sand coming on.
		_look_back_t -= delta
		_cam.global_position = plane.global_transform * Vector3(6.0, 7.0, -24.0)
		_cam.look_at(plane.global_position + plane.global_basis.z * 60.0 + Vector3.UP * 25.0, Vector3.UP)
		return
	var behind := plane.global_transform * Vector3(0, 4.0, 13.0)
	var shake := Vector3.ZERO
	if step == Step.STORM:
		shake = Vector3(sin(_t * 23.0), sin(_t * 17.0 + 1.0), 0) * 0.15 * (0.5 + absf(_gust))
	_cam.global_position = _cam.global_position.lerp(behind + shake, minf(delta * 4.0, 1.0)) if step != Step.TAKEOFF or _t > 0.5 else behind
	_cam.look_at(plane.global_position + Vector3.UP * 1.5 - plane.global_basis.z * 8.0, Vector3.UP)
	_cam.rotate_object_local(Vector3.FORWARD, -plane.roll * 0.35)


func _fly(delta: float) -> void:
	_phase_t += delta
	plane.global_position += Vector3(0, 0, -CRUISE * delta)
	(level as FlightRange).set_dusk(clampf(_phase_t / (CALM_SECS + STORM_SECS), 0.0, 1.0))
	if step == Step.FLIGHT:
		plane.roll = move_toward(plane.roll, 0.0, delta * 0.4)
		if _phase_t >= CALM_SECS:
			_storm_begin()
		return
	# The storm: it gains on the plane; its gusts roll it; you hold it level.
	var p := (_phase_t - CALM_SECS) / STORM_SECS
	if p > 0.55 and not _looked_mid:
		_looked_mid = true
		_look_back_t = 3.0  # it's much closer now
	_storm_z = lerpf(plane.global_position.z + 650.0, plane.global_position.z + 4.0, p)
	_storm.scale.y = lerpf(0.35, 1.0, minf(p * 2.0, 1.0))
	_storm.global_position = Vector3(plane.global_position.x, 300.0 * _storm.scale.y, _storm_z)  # rising from the ground
	level._env.fog_density = lerpf(0.0015, 0.02, p * p)
	level._env.fog_light_color = level._env.fog_light_color.lerp(Color(0.55, 0.38, 0.22), delta)
	_gust_t -= delta
	if _gust_t <= 0.0:
		_gust_t = randf_range(2.2, 3.8) * lerpf(1.2, 0.75, p)
		_gust = (1.0 if randf() < 0.5 else -1.0) * randf_range(0.7, 1.15)
		_gust_left = randf_range(0.9, 1.5)
		result.gusts += 1
	if _gust_left > 0.0:
		_gust_left -= delta
	else:
		_gust = move_toward(_gust, 0.0, delta * 3.0)
	var steer := _steer_input()
	_roll_rate = _gust - steer * STEER - plane.roll * 0.6
	plane.roll = clampf(plane.roll + _roll_rate * delta, -1.2, 1.2)
	if absf(plane.roll) > LIMIT:
		_over_t += delta
		if _over_t > LIMIT_SECS:
			_drop()
	else:
		_over_t = 0.0
	if p >= 1.0:
		_landing()


## A / D (or the bot): positive steers the roll down from the right.
func _steer_input() -> float:
	if args.has("auto"):
		if str(args.get("auto", "")) == "sloppy":
			return 0.0
		return clampf(plane.roll * 3.0 + _gust / STEER, -1.0, 1.0)
	return Input.get_axis("move_left", "move_right")


## It rolled too far: the plane drops, the companion is thrown about.
func _drop() -> void:
	_over_t = 0.0
	result.drops += 1
	plane.damage = minf(plane.damage + 18.0, 100.0)
	plane.roll *= 0.3
	plane.global_position.y = maxf(plane.global_position.y - 8.0, 30.0)
	hud.on_damaged(10.0)
	if companion != "none":
		result.hurt += 1
		Game.apply([{"stat": [companion, "fear", 1]}])
		if result.hurt == 2:
			Game.set_flag(companion + "_injured")
	hud.toast("The plane drops like a stone, then catches. %s" % ("Hold it level! ({move_left} / {move_right})" if result.drops == 1 else
		("%s is thrown against the cockpit rim." % DayLog.person(companion) if companion != "none" else "Something in the rigging snaps.")), 3.0)
	print("RESULT flight drop %d damage=%.0f" % [result.drops, plane.damage])


func _storm_begin() -> void:
	step = Step.STORM
	_storm = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(3000, 600, 80)  # a wall of sand far taller than the plane flies
	_storm.mesh = bm
	_storm_mat = StandardMaterial3D.new()
	_storm_mat.albedo_color = Color(0.5, 0.36, 0.22, 0.85)
	_storm_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_storm_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_storm_mat.disable_fog = true  # the fog would hide it at a distance
	_storm.mesh.surface_set_material(0, _storm_mat)
	add_child(_storm)
	_storm.position = Vector3(0, 105, plane.global_position.z + 650.0)
	hud.toast("Behind you, the horizon is rising: a wall of sand, and it's gaining. {move_left} / {move_right} to hold her level.", 5.0)
	Objective.set_goal("Hold her level through the storm")
	_look_back_t = 4.5
	print("RESULT flight storm")


# ---------------------------------------------------------------- the landing

func _landing() -> void:
	step = Step.LANDING
	hud.toast("The storm swallows the sun. Fletcher puts her down wherever there's ground.", 3.5)
	var tw := create_tween()
	tw.tween_property(plane, "global_position", plane.global_position + Vector3(0, -ALTITUDE + 8.0, -CRUISE * 5.0), 5.0)
	tw.parallel().tween_property(_fade, "color:a", 1.0, 5.0)
	await tw.finished
	# At Akmentar: the ruins, the plane on its nose in the sand.
	if _storm:
		_storm.queue_free()
	level.queue_free()
	var surface := AkmentarSurface.new()
	add_child(surface)
	level = surface
	surface.set_night(0.7)
	Ambience.play(self, "night")
	plane.global_position = LANDING_SPOT
	plane.rotation = Vector3(0, -0.6, 0)
	plane.damage = maxf(plane.damage, 40.0)
	plane.wreck()
	step = Step.END  # out of the plane: nobody is held in a seat any more
	for b in _bodies:
		if is_instance_valid(b):
			b.queue_free()
	_bodies.clear()
	await get_tree().physics_frame
	# Everyone out, on their feet beside it.
	player.global_position = LANDING_SPOT + Vector3(3.0, 0, 3.0)
	player.velocity = Vector3.ZERO
	player.set_physics_process(true)
	if player.explorer:
		player.explorer.set_driving(false)
	player.camera.current = true
	player.yaw = 0.0
	var fletcher := Npc.make(level, "fletcher", LANDING_SPOT + Vector3(-2.5, 0, 2.5), "", Characters.glb("fletcher"))
	fletcher.face_towards(LANDING_SPOT)
	if companion != "none":
		var c := Gunman.make_companion(companion, player, Characters.glb(companion))
		if c:
			add_child(c)
			c.global_position = LANDING_SPOT + Vector3(4.5, 0, 1.0)
	var tw2 := create_tween()
	tw2.tween_property(_fade, "color:a", 0.0, 2.0)
	await tw2.finished
	await get_tree().create_timer(1.0).timeout
	hud.toast("Fletcher pats the cowling. \"She got us here. She'll not fly again.\"", 4.5)
	await get_tree().create_timer(4.5).timeout
	_finish()


func _finish() -> void:
	if _done:
		return
	_done = true
	step = Step.END
	result.plane_damage = plane.damage
	Game.set_flag("plane_wrecked")
	Game.set_flag("flight_done")
	Game.set_flag("flight_drops", result.drops)
	print("RESULT flight end companion=%s gusts=%d drops=%d plane_damage=%.0f hurt=%d injured=%s" % [companion, result.gusts,
		result.drops, plane.damage, result.hurt, Game.flag(companion + "_injured", false) if companion != "none" else false])
	finished.emit(result)
	hud.show_message("AKMENTAR", "The plane is finished; the ruins are a short walk away.\n\nEnter  go on")
	Objective.set_goal("")
	if args.has("auto"):
		await get_tree().create_timer(1.0).timeout
		get_tree().quit(0)


func _unhandled_input(event: InputEvent) -> void:
	if args.size() > 0:
		return
	var enter: bool = event is InputEventKey and event.pressed and event.keycode in [KEY_ENTER, KEY_KP_ENTER]
	if _done and enter:
		get_tree().change_scene_to_file(next_scene)  # Game (the flags, the companion) carries over


func _shot(file: String) -> void:
	await RenderingServer.frame_post_draw
	if DisplayServer.get_name() == "headless":
		return
	var dir: String = args.get("shot-dir", "user://shots")
	DirAccess.make_dir_recursive_absolute(dir)
	get_viewport().get_texture().get_image().save_png(dir.path_join(file))
	print("RESULT shot %s" % dir.path_join(file))
