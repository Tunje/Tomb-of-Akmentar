extends Node3D
## What poses Cairo's people are in (Simon saw one standing with his head thrown back, arms a
## little out, by a wall: a seat / rail / table clip with nothing there, or a body never posed).
##   survey (default)  Cairo with its crowd, sped up (--speed=3), for --seconds (60). Every half
##          second, every person: a SPOT_CLIPS clip while not at the spot claimed for it, and any
##          rigged body on screen still in its model's raw rest pose (never posed). Prints each.
##   --atlas   (windowed) a row of the crowd's stand-in, one per clip plus its raw rest pose, to
##             tell which pose that was; --shot-dir=path
## Never takes focus or captures the mouse.

var level: Node3D
var player: Player
var args := {}
var _fails := 0
var _seen := {}


func _ready() -> void:
	get_window().set_flag(Window.FLAG_NO_FOCUS, true)
	args = TestDriver.parse_args()
	Controls.setup()
	if args.has("atlas"):
		await _atlas()
		return
	level = CoastTown.new() if str(args.get("map", "")) == "coast" else Cairo.new()
	add_child(level)
	player = Player.new()
	add_child(player)
	player.global_position = level.player_spawn
	player.set_armed(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await get_tree().physics_frame
	var crowd: Crowd = level.get("crowd") as Crowd if "crowd" in level else null
	if crowd == null:
		var found := level.find_children("*", "", false, false).filter(func(n: Node) -> bool: return n is Crowd)
		crowd = found[0] if not found.is_empty() else null
	_check(crowd != null and crowd.people.size() > 10, "survey: Cairo's crowd (%d)" % (crowd.people.size() if crowd else 0))
	if crowd == null:
		_end()
		return
	Engine.time_scale = float(args.get("speed", "3"))
	var secs := float(args.get("seconds", "60"))
	var off_spot := 0
	var raw := 0
	var t := 0.0
	var clips := {}
	while t < secs:
		await get_tree().create_timer(0.5 * Engine.time_scale).timeout
		t += 0.5 * Engine.time_scale
		# Walk the player about so the culling and the people's manners both get exercised.
		if level is Cairo:
			player.global_position = Vector3(30.0 + fmod(t * 1.7, 50.0), 0.1, 50.0 + 25.0 * sin(t * 0.05))
		for p in crowd.people:
			clips[p.anim] = int(clips.get(p.anim, 0)) + 1
			if p.anim in CrowdPerson.SPOT_CLIPS and not p._at_spot():
				off_spot += 1
				_once("spot " + p.name, "RESULT off-spot %s anim %s state %s at %s spot %s" % [p.name, p.anim, p.state, p.global_position.snapped(Vector3.ONE * 0.1), str(p._spot.get("pos", "-"))])
		var cam := get_viewport().get_camera_3d()
		for n in level.find_children("*", "", true, false):
			if n is RiggedBody and (n as Node3D).is_visible_in_tree() and cam and cam.is_position_in_frustum((n as Node3D).global_position + Vector3.UP):
				if _raw(n as RiggedBody):
					raw += 1
					_once("raw " + str(n.get_path()), "RESULT raw-pose %s (%s) at %s" % [n.name, n.get_class(), (n as Node3D).global_position.snapped(Vector3.ONE * 0.1)])
	Engine.time_scale = 1.0
	if args.has("jump"):
		await _jumps(crowd)
	print("RESULT info clips seen: %s" % str(clips))
	_check(off_spot == 0, "survey: no seat/rail/table clip away from its spot (%d)" % off_spot)
	_check(raw == 0, "survey: nobody on screen in a raw rest pose (%d)" % raw)
	_end()


## As coast_town_test takes its views: the camera jumps somewhere new and the shot comes 70 frames
## later (under the crowd's 0.5 s think), vsync off, the overview first. Anyone in view then in a T
## (hands out at shoulder height), or anyone whose Transition never got a state (a rest pose)?
func _jumps(crowd: Crowd) -> void:
	var views := [[Vector3(56, 1.7, 72), Vector3(10, 1.5, 36)], [Vector3(20, 3, 20), Vector3(60, 1, 60)],
		[Vector3(90, 2, 40), Vector3(40, 1, 70)], [Vector3(10, 2, 80), Vector3(60, 1, 30)]]
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	views.push_front([Vector3(30, 200, 330), Vector3(30, 0, 110)])
	var cam := Camera3D.new()
	add_child(cam)
	cam.make_current()
	var t_bad := 0
	for v: Array in views:
		cam.global_position = v[0]
		cam.look_at(v[1], Vector3.UP)
		for i in 70:
			await get_tree().process_frame
		for n in level.find_children("*", "", true, false):
			if not n is RiggedBody:
				continue
			var p := n as RiggedBody
			if not p.is_visible_in_tree() or not cam.is_position_in_frustum(p.global_position + Vector3.UP) or p.skeleton == null:
				continue
			var hl := p.bone_point("hand_l")
			var hr := p.bone_point("hand_r")
			var sh := p.bone_point("upperarm_l")
			if absf(hl.y - sh.y) < 0.25 and hl.distance_to(hr) > 1.2:
				t_bad += 1
				var cp := p as CrowdPerson
				print("RESULT T-pose %s (%s, under %s) %s tree active %s at %s, %.0f m from the camera" % [p.name, p.get_class(), p.get_parent().name,
					("state %s anim %s lod %d" % [cp.state, cp.anim, cp.lod]) if cp else "", p._tree.active if p._tree else false,
					p.global_position.snapped(Vector3.ONE * 0.1), cam.global_position.distance_to(p.global_position)])
	_check(t_bad == 0, "jumps: nobody in a T-pose 70 frames after the camera moves (%d)" % t_bad)
	# A Transition with no state outputs nothing: the body stands in its rest pose.
	var stateless := crowd.people.filter(func(p: CrowdPerson) -> bool: return p._tree and str(p._tree.get("parameters/state/current_state")) == "")
	_check(stateless.is_empty(), "jumps: everyone's clip chosen (none stateless: %s)" % str(stateless.map(func(p: CrowdPerson) -> String: return p.name)))


## Its body's bones all still at their rest (the pose never copied onto it).
func _raw(b: RiggedBody) -> bool:
	var sk := b.skeleton
	if sk == null:
		return false
	var moved := 0
	for i in sk.get_bone_count():
		var rest := sk.get_bone_rest(i).basis.get_rotation_quaternion()
		var pose := sk.get_bone_pose_rotation(i)
		if rest.angle_to(pose) > 0.02:
			moved += 1
	return moved < 3


func _once(key: String, line: String) -> void:
	if not _seen.has(key):
		_seen[key] = true
		print(line)


func _atlas() -> void:
	var sun := DirectionalLight3D.new()
	add_child(sun)
	sun.rotation = Vector3(deg_to_rad(-50), deg_to_rad(30), 0)
	var we := WorldEnvironment.new()
	we.environment = Environment.new()
	we.environment.background_mode = Environment.BG_COLOR
	we.environment.background_color = Color(0.55, 0.6, 0.65)
	we.environment.ambient_light_color = Color(0.7, 0.7, 0.7)
	we.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	add_child(we)
	var keys: Array = ["rest"] + CrowdPerson.CLIPS.keys()
	var bodies: Array[NpcBody] = []
	for i in keys.size():
		var b := NpcBody.create(Characters.DIR + str(args.get("model", "bandits/bandit_scout.glb")))
		if b == null:
			_check(false, "atlas: the stand-in's model")
			_end()
			return
		add_child(b)
		b.position = Vector3(i * 1.3, 0, 0)
		bodies.append(b)
		var l := Label3D.new()
		l.text = str(keys[i])
		l.font_size = 40
		l.pixel_size = 0.004
		l.position = Vector3(i * 1.3, 2.15, 0)
		add_child(l)
	await get_tree().process_frame
	await get_tree().process_frame
	for i in keys.size():
		var k: String = keys[i]
		bodies[i].debug_pose("rest" if k == "rest" else str(CrowdPerson.CLIPS[k]))
	var cam := Camera3D.new()
	add_child(cam)
	var mid := (keys.size() - 1) * 1.3 * 0.5
	cam.look_at_from_position(Vector3(mid, 1.4, 9.5), Vector3(mid, 1.0, 0))
	cam.make_current()
	await get_tree().create_timer(0.5).timeout
	if DisplayServer.get_name() != "headless":
		get_window().size = Vector2i(2400, 700)
		await get_tree().create_timer(0.3).timeout
		await RenderingServer.frame_post_draw
		var dir: String = args.get("shot-dir", "user://pose_shots")
		DirAccess.make_dir_recursive_absolute(dir)
		get_viewport().get_texture().get_image().save_png(dir.path_join("crowd_poses_%s.png" % str(args.get("model", "scout")).get_file().get_basename()))
		print("RESULT shot %s" % dir.path_join("crowd_poses.png"))
	_end()


func _end() -> void:
	print("RESULT crowd_pose_test %s fails=%d" % ["PASS" if _fails == 0 else "FAIL", _fails])
	get_tree().quit(0 if _fails == 0 else 1)


func _check(ok: bool, what: String) -> void:
	print("RESULT %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_fails += 1
