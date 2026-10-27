extends Node3D
## CampJobs (scripts/sites/camp_jobs.gd) on the Akmentar surface, with the whole cast:
##   day      Act 4's day: each companion at their own job (a different place each), holding,
##            playing its clip, gun put away unless on watch; the talks at the jobs; crews working
##            the claimed sites (ours as many as were hired, the rivals' a crew each)
##   talk     talking to one at their job starts their camp talk, and the day's flag is set (the
##            camp fire's menu then has no second rung for them)
##   fight    a bandit walks in: they drop their jobs and fight; once he's down, back to work
##   night    round the fire, Hargreaves on watch, Hassan under the stars
##   release  breaking camp: they follow again
## --perf[=off]  instead: a frame rate at the camp by day (windowed), with the jobs and crews, or
##               the party simply following; --seconds=N --shots=t1,.. --cam=camp|sites|fire --night
## Never takes focus or captures the mouse.

const CAST := ["eleanor", "pembroke", "hargreaves", "saleh", "naguib", "mahmoud", "khalil", "isabelle", "hassan", "youssef"]
const CAMS := {
	"camp": [Vector3(78, 6.0, 128), Vector3(70, 0.5, 117)],
	"fire": [Vector3(73.5, 2.0, 122.5), Vector3(70, 0.6, 117.5)],
	"sites": [Vector3(70, 9.0, 52), Vector3(70, 0, 40)],
}

var level: Node3D
var player: Player
var companions := {}
var args := {}
var _fails := 0
var _t := 0.0
var _frames: Array[float] = []
var _shots: Array[float] = []
var _perf := false
var _sites := {}


func _ready() -> void:
	get_window().set_flag(Window.FLAG_NO_FOCUS, true)
	args = TestDriver.parse_args()
	Controls.setup()
	Settings.ensure(get_tree())
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.max_fps = 0
	for s in str(args.get("shots", "")).split(",", false):
		_shots.append(float(s))
	var cast: Array = CAST.duplicate()
	if str(args.get("what", "")) == "crewless":
		cast = cast.filter(func(x: String) -> bool: return not x in ["mahmoud", "khalil", "naguib"])
	for id in cast:
		Game.apply([{"recruit": id}])
	var what := str(args.get("what", ""))
	level = DesertRoute.new() if what == "road" else (Cairo.new() if what == "cairo" else AkmentarSurface.new())
	add_child(level)
	if level is DesertRoute:
		level.player_spawn = DesertRoute.road_point(DesertRoute.START_Z - 30.0)
	player = Player.new()
	add_child(player)
	player.global_position = level.player_spawn
	player.set_armed(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var i := 0
	for id in cast:
		var c := Gunman.make_companion(id, player, Characters.glb(id))
		if c:
			add_child(c)
			c.global_position = player.global_position + Vector3(i % 5 * 1.4 - 2.8, 0, 2.5 + int(i / 5) * 1.4)
			companions[id] = c
			i += 1
	# Three sites ours, two each the rivals'.
	var claims := {"horus": "party", "souls": "party", "anubis": "party", "scarabs": "americans", "obelisk": "americans", "hieroglyphs": "germans", "offering": "germans"}
	for k in claims:
		_sites[k] = {"at": AkmentarSurface.SITES[k], "team": claims[k]}
	await get_tree().physics_frame
	await get_tree().physics_frame
	if args.has("cam"):
		var c: Array = CAMS.get(str(args.cam), CAMS.camp)
		var cam := Camera3D.new()
		add_child(cam)
		cam.look_at_from_position(c[0], c[1])
		cam.make_current()
	if str(args.get("what", "")) == "road":
		await _road()
	elif str(args.get("what", "")) == "cairo":
		await _cairo()
	elif str(args.get("what", "")) == "crewless":
		await _crewless()
	elif args.has("perf") or args.has("look"):
		_perf = true
		if str(args.get("perf", "")) != "off":
			CampJobs.assign(level, companions, "act4_night" if args.has("night") else "act4_day", args.has("night"), {"sites": _sites})
			if not args.has("night"):
				CampJobs.staff_sites(level, _sites)
		await get_tree().create_timer(float(args.get("seconds", "25"))).timeout
	else:
		await _day()
		await _talk()
		await _fight()
		await _night()
		_release()
	print("RESULT camp_jobs_test %s fails=%d" % ["PASS" if _fails == 0 else "FAIL", _fails])
	get_tree().quit(0 if _fails == 0 else 1)


## Act 3's night on the road: a camp made where there's none, everyone placed round it.
func _road() -> void:
	var camp := CampJobs.make_camp(level, player.global_position + Vector3(9.0, 0, 0))
	var h := CampJobs.assign(level, companions, "act3_camp", true, {"anchor": camp})
	var w := 0.0
	while h.jobs.is_empty() and w < 12.0:
		await get_tree().create_timer(0.25).timeout
		w += 0.25
	_check(h.jobs.size() == CAST.size() and level.get_node_or_null("RoadCamp") != null, "road: a camp made, %d of %d at their places round it" % [h.jobs.size(), CAST.size()])
	player.global_position = camp + Vector3(-14, 0.1, 0)
	var secs := 0.0
	while secs < 40.0 and _settled(h).size() < h.jobs.size():
		await get_tree().create_timer(1.0).timeout
		secs += 1.0
	_check(_settled(h).size() == h.jobs.size(), "road: all settled in %.0f s" % secs)
	CampJobs.release(level)


## Act 8's prep in Cairo: each at their place in town (the lobby, the outfitters, the hotel door,
## the caravanserai's animals, the docks).
func _cairo() -> void:
	var h := CampJobs.assign(level, companions, "act8_prep")
	var w := 0.0
	while h.jobs.is_empty() and w < 12.0:
		await get_tree().create_timer(0.25).timeout
		w += 0.25
	_check(h.jobs.size() == CAST.size(), "cairo: %d of %d given a place in town" % [h.jobs.size(), CAST.size()])
	player.global_position = Vector3(60, 0.1, 50)
	var secs := 0.0
	while secs < 50.0 and _settled(h).size() < h.jobs.size():
		await get_tree().create_timer(1.0).timeout
		secs += 1.0
	var not_yet: Array = h.jobs.keys().filter(func(id: String) -> bool: return not id in _settled(h))
	for id in not_yet:
		var j: Dictionary = h.jobs[id]
		var g := j.g as Gunman
		print("RESULT info %s in cairo: at %s, spot %s (%.2f m), state %s vel %s" % [id, g.global_position.snapped(Vector3.ONE * 0.1), (j.spot as Vector3).snapped(Vector3.ONE * 0.1),
			Vector2(g.global_position.x - j.spot.x, g.global_position.z - j.spot.z).length(), g.state, g.velocity.snapped(Vector3.ONE * 0.1)])
	_check(not_yet.is_empty(), "cairo: all there in %.0f s (not: %s)" % [secs, str(not_yet)])
	CampJobs.release(level)


## No crews hired: each of our claimed sites still has someone working it by day (a scholar).
func _crewless() -> void:
	var h := CampJobs.assign(level, companions, "act4_day", false, {"sites": _sites})
	var w := 0.0
	while h.jobs.is_empty() and w < 12.0:
		await get_tree().create_timer(0.25).timeout
		w += 0.25
	var crews := CampJobs.staff_sites(level, _sites, {})
	var ours: Array = _sites.keys().filter(func(k: String) -> bool: return _sites[k].team == "party")
	var manned := 0
	for k in ours:
		var at: Vector3 = _sites[k].at
		if h.jobs.values().any(func(j: Dictionary) -> bool: return (j.spot as Vector3).distance_to(at) < 6.0):
			manned += 1
	_check(manned == ours.size(), "crewless: each of our %d sites has a scholar working it (%d)" % [ours.size(), manned])
	_check(crews.filter(func(c: Crowd) -> bool: return c.name.ends_with("party")).is_empty(), "crewless: and no crew of ours (none hired)")


func _jobs() -> CampJobs:
	return level.get_node_or_null("CampJobs") as CampJobs


## The player out of everyone's way (stood still on a path, he stops them: they won't push past).
func _step_aside() -> void:
	player.global_position = level.camps.party + Vector3(-12.0, 0.1, 6.0)


func _settled(h: CampJobs) -> Array:
	var out := []
	for id in h.jobs:
		var j: Dictionary = h.jobs[id]
		var g := j.g as Gunman
		if Vector2(g.global_position.x - j.spot.x, g.global_position.z - j.spot.z).length() < 0.4:
			out.append(id)
	return out


func _blend_of(g: Gunman) -> float:
	var v: Variant = g.rig._tree.get("parameters/job_mix/blend_amount") if g.rig and g.rig._tree else null
	return float(v) if v != null else 0.0


func _day() -> void:
	var h := CampJobs.assign(level, companions, "act4_day", false, {"sites": _sites})
	var w := 0.0
	while h.jobs.is_empty() and w < 12.0:
		await get_tree().create_timer(0.25).timeout
		w += 0.25
	print("RESULT info assigned after %.2f s (the navmesh)" % w)
	_step_aside()
	_check(h.jobs.size() == CAST.size(), "day: %d of %d companions given a job" % [h.jobs.size(), CAST.size()])
	var kinds := {}
	for id in h.jobs:
		kinds[h.jobs[id].kind] = int(kinds.get(h.jobs[id].kind, 0)) + 1
	print("RESULT info day jobs: %s" % str(kinds))
	var spots: Array = h.jobs.values().map(func(j: Dictionary) -> Vector3: return j.spot)
	var close := 0
	for a in spots.size():
		for b in range(a + 1, spots.size()):
			if (spots[a] as Vector3).distance_to(spots[b]) < 1.2:
				close += 1
	_check(close == 0, "day: each at their own place (%d too close)" % close)
	var secs := 0.0
	while secs < 40.0 and _settled(h).size() < h.jobs.size():
		await get_tree().create_timer(1.0).timeout
		secs += 1.0
		if args.has("trace"):
			var k := companions.khalil as Gunman
			print("TRACE %2.0f khalil at %s vel %s state %s finished %s next %s" % [secs, k.global_position.snapped(Vector3.ONE * 0.1), k.velocity.snapped(Vector3.ONE * 0.1), k.state, k._agent.is_navigation_finished(), k._agent.get_next_path_position().snapped(Vector3.ONE * 0.1)])
	await get_tree().create_timer(1.5).timeout
	var settled := _settled(h)
	for id in h.jobs:
		if not id in settled:
			var j: Dictionary = h.jobs[id]
			var g := j.g as Gunman
			var path := NavigationServer3D.map_get_path(get_world_3d().navigation_map, g.global_position, j.spot, true)
			print("RESULT info %s: %.2f m off its spot %s at %s, state %s, order %s, hold_at %s, path %d pts ending %.2f m off" % [id, Vector2(g.global_position.x - j.spot.x, g.global_position.z - j.spot.z).length(),
				str(j.spot.snapped(Vector3.ONE * 0.1)), str(g.global_position.snapped(Vector3.ONE * 0.1)), g.state, g.order, str(g.hold_at.snapped(Vector3.ONE * 0.1)), path.size(), path[-1].distance_to(j.spot) if path.size() > 0 else -1.0])
	_check(settled.size() == h.jobs.size(), "day: all at their jobs in %.0f s (%d of %d; not: %s)" % [secs, settled.size(), h.jobs.size(), str(CAST.filter(func(x: String) -> bool: return not x in settled))])
	var playing := 0
	var with_clip := 0
	for id in h.jobs:
		var j: Dictionary = h.jobs[id]
		if str(j.clip) != "":
			with_clip += 1
			if _blend_of(j.g) > 0.9:
				playing += 1
	_check(playing == with_clip, "day: %d of %d playing their job's clip" % [playing, with_clip])
	var hg := companions.hargreaves as Gunman
	var el := companions.eleanor as Gunman
	_check(hg.rig.gun_holder.visible and not el.rig.gun_holder.visible, "day: Hargreaves on watch with his gun, Eleanor's put away")
	_check(h.jobs.values().all(func(j: Dictionary) -> bool: return (j.g as Gunman).order == "hold"), "day: all holding (none trailing the player)")
	var talks := h.jobs.values().filter(func(j: Dictionary) -> bool: return j.get("talk") is Interactable and (j.talk as Interactable).is_in_group("interactable")).size()
	_check(talks >= 8, "day: %d 'Talk to' at their jobs" % talks)
	var crews := CampJobs.staff_sites(level, _sites)
	await get_tree().create_timer(1.0).timeout
	var ours := 0
	var theirs := 0
	for c in crews:
		if c.name.ends_with("party"):
			ours += c.people.size()
		else:
			theirs += c.people.size()
	_check(ours == 12 and theirs == 12, "day: crews at the sites, ours %d (30 men hired, 12 shown on high), the rivals' %d" % [ours, theirs])
	await get_tree().create_timer(6.0).timeout
	var digging := 0
	for c in crews:
		digging += c.people.filter(func(p: CrowdPerson) -> bool: return p.state == "dig").size()
	_check(digging >= 12, "day: %d of them digging" % digging)


func _talk() -> void:
	var h := _jobs()
	var j: Dictionary = h.jobs.eleanor
	h._on_talk(player, "eleanor")
	await get_tree().process_frame
	var started := Conversation.current != null
	_check(started, "talk: talking to Eleanor at her job starts her camp talk")
	if started:
		Conversation.current._finish("")
	await get_tree().create_timer(0.6).timeout
	var a := h._camp_action("eleanor")
	_check(h._camp_spot._done(a), "talk: the day's flag set (the fire's menu has no second rung)")
	_check(not (j.talk as Interactable).is_in_group("interactable"), "talk: no more 'Talk to Eleanor' today")


func _fight() -> void:
	var h := _jobs()
	var g := Gunman.new()
	g.name = "Bandit"
	g.team = "bandits"
	g.glb = GunmanBody.BANDITS[0]
	g.foe_player = player
	add_child(g)
	g.global_position = level.camps.party + Vector3(0, 0, 22)
	g.target = player
	await get_tree().create_timer(2.0).timeout
	var dropped := h.jobs.values().filter(func(j: Dictionary) -> bool: return _blend_of(j.g) < 0.1).size()
	_check(Gunman.fight_on(get_tree()) and dropped == h.jobs.size(), "fight: a bandit, and all %d drop their jobs (%d)" % [h.jobs.size(), dropped])
	await get_tree().create_timer(4.0).timeout
	var shot := 0
	for id in h.jobs:
		shot += (h.jobs[id].g as Gunman).shots_fired
	_check(shot > 0, "fight: they fight from where they are (%d shots)" % shot)
	if is_instance_valid(g):
		g.take_damage(100000.0, player.global_position) if g.has_method("take_damage") else g.queue_free()
	await get_tree().create_timer(1.0).timeout
	if is_instance_valid(g) and g.is_active():
		g.queue_free()
	_step_aside()
	var secs := 0.0
	while secs < 40.0 and _settled(h).size() < h.jobs.size():
		await get_tree().create_timer(1.0).timeout
		secs += 1.0
	await get_tree().create_timer(CampJobs.QUIET + 1.0).timeout
	var back := h.jobs.values().filter(func(j: Dictionary) -> bool: return str(j.clip) == "" or _blend_of(j.g) > 0.9).size()
	_check(back == h.jobs.size(), "fight: over, all back at work (%d of %d)" % [back, h.jobs.size()])


func _night() -> void:
	CampJobs.clear_sites(level)
	var h := CampJobs.assign(level, companions, "act4_night", true)
	_step_aside()
	var at_fire := h.jobs.values().filter(func(j: Dictionary) -> bool: return j.kind == "fire").size()
	_check(at_fire >= 5 and h.jobs.hargreaves.kind == "watch" and h.jobs.hassan.kind == "stars", "night: %d round the fire, Hargreaves on watch, Hassan under the stars" % at_fire)
	var near := h.jobs.values().filter(func(j: Dictionary) -> bool: return j.kind == "fire" and (j.spot as Vector3).distance_to(h.anchor) < 4.0).size()
	_check(near == at_fire, "night: the fire's seats close round it (%d)" % near)
	var secs := 0.0
	while secs < 40.0 and _settled(h).size() < h.jobs.size():
		await get_tree().create_timer(1.0).timeout
		secs += 1.0
	var not_yet: Array = h.jobs.keys().filter(func(id: String) -> bool: return not id in _settled(h))
	for id in not_yet:
		var j: Dictionary = h.jobs[id]
		var g := j.g as Gunman
		var cam := get_viewport().get_camera_3d()
		print("RESULT info %s at night: at %s, spot %s (%.2f m), cam %.0f m, in view %s" % [id, g.global_position.snapped(Vector3.ONE * 0.1), (j.spot as Vector3).snapped(Vector3.ONE * 0.1),
			Vector2(g.global_position.x - j.spot.x, g.global_position.z - j.spot.z).length(), cam.global_position.distance_to(g.global_position), cam.is_position_in_frustum(g.global_position + Vector3.UP)])
		print("RESULT info   state %s target %s order %s hold_at %s vel %s downed %s" % [g.state, g.target, g.order, g.hold_at.snapped(Vector3.ONE * 0.1), g.velocity.snapped(Vector3.ONE * 0.1), g.downed])
	_check(not_yet.is_empty(), "night: all in their places in %.0f s (not: %s)" % [secs, str(not_yet)])


func _release() -> void:
	CampJobs.release(level)
	_check(companions.values().all(func(g: Gunman) -> bool: return g.order == "follow"), "release: they follow again")


func _process(delta: float) -> void:
	_t += delta
	if _perf and _t > 8.0:
		_frames.append(delta * 1000.0)
	if _shots.size() > 0 and _t >= _shots[0]:
		_shots.pop_front()
		_shot("campjobs_%s_%s_%s_%04.1f.png" % [str(args.get("cam", "player")), "night" if args.has("night") else "day", str(args.get("perf", "on")), _t])


func _exit_tree() -> void:
	if _frames.size() > 10:
		var s := _frames.duplicate()
		s.sort()
		var mean := 0.0
		for f in s:
			mean += f
		mean /= s.size()
		print("PERFSUM frames=%d mean_ms=%.2f (%.0f fps) p95_ms=%.1f" % [s.size(), mean, 1000.0 / mean, s[int(s.size() * 0.95)]])


func _shot(file: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var dir: String = args.get("shot-dir", "user://campjobs_shots")
	DirAccess.make_dir_recursive_absolute(dir)
	get_viewport().get_texture().get_image().save_png(dir.path_join(file))
	print("RESULT shot %s" % dir.path_join(file))


func _check(ok: bool, what: String) -> void:
	print("RESULT %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_fails += 1
