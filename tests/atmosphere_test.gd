extends Node3D
## The air and light of the places, one map per run (--what=...):
##   desert   DesertRoute by day + Weather (Ambience's desert bed): sand on the wind, wisps off
##            the crests, the heat shimmer (and none on the low preset)
##   storm    the same, and a 20 s sandstorm: fog thick and brown-orange, the veil, streaks,
##            visibility() low; after it, the road's own fog back
##   river    RiverRoute: the reed beds along both banks, the sun's glints on the water
##   night    Cairo at dusk: the bazaar's lantern strings and the tavern's glow on, no more lights
##            than the budget (none on low); by day all off
##   curse    Cairo under the curse: flies about, the crowd's robes darkened
## Checks (headless is fine), then a frame rate (PERFSUM, windowed) and screenshots.
##   --mode=off   without it (the before)   --look   no checks, just --seconds   --cam=<preset>
##   --seconds=N  --shots=t1,t2  --shot-dir=path
## Never takes focus or captures the mouse.

const CAMS := {
	"dunes": [Vector3(0, 3.0, 0), Vector3(40, 1.0, 80)],
	"bazaar": [Vector3(34.5, 1.7, 77.0), Vector3(60, 3.0, 77.0)],
	"tavern": [Vector3(31.0, 1.7, 75.0), Vector3(27.0, 1.5, 64.0)],
	"street": [Vector3(29.0, 1.7, 52.0), Vector3(29.0, 1.4, 70.0)],
	"banks": [Vector3(0, 3.0, -40), Vector3(-22, 0.5, -90)],
}

var level: Node3D
var player: Player
var args := {}
var what := "desert"
var _fails := 0
var _t := 0.0
var _shots: Array[float] = []
var _frames: Array[float] = []
var _cam: Camera3D


func _ready() -> void:
	get_window().set_flag(Window.FLAG_NO_FOCUS, true)
	args = TestDriver.parse_args()
	Controls.setup()
	Settings.ensure(get_tree())
	what = str(args.get("what", "desert"))
	var off := str(args.get("mode", "")) == "off"
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.max_fps = 0
	for s in str(args.get("shots", "")).split(",", false):
		_shots.append(float(s))
	match what:
		"river":
			level = RiverRoute.new()
		"night", "curse":
			level = Cairo.new()
		_:
			level = DesertRoute.new()
	add_child(level)
	player = Player.new()
	add_child(player)
	player.global_position = level.player_spawn
	if level is DesertRoute:
		player.global_position = DesertRoute.road_point(60.0) + Vector3.UP * 0.1
	player.set_armed(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await get_tree().physics_frame
	await get_tree().physics_frame
	match what:
		"desert", "storm":
			if not off:
				Weather.on_bed(level, "desert")
		"night":
			level.call("set_day_time", 1.0)
		"curse":
			level.call("set_day_time", 0.55)
			if not off:
				level.call("set_curse", 1.0, 1.0)
	if off and what == "river" and level.get_node_or_null("ReedBeds"):
		level.get_node("ReedBeds").queue_free()  # (the shader can't be had the old way: reeds only)
	if off and level.get("crowd"):
		var c: Crowd = level.get("crowd")
		if what == "night" and c.lights:
			c.lights.queue_free()
			c.lights = null
	if args.has("cam"):
		var c: Array = CAMS.get(str(args.cam), CAMS.dunes)
		_cam = Camera3D.new()
		add_child(_cam)
		var from: Vector3 = c[0]
		var to: Vector3 = c[1]
		if level is DesertRoute:
			from += player.global_position
			to += player.global_position
		_cam.look_at_from_position(from, to)
		_cam.make_current()
		if args.has("label"):
			# A world marker in the shimmer's band (it should stay straight: the shimmer bends
			# only the opaque world).
			var l := Label3D.new()
			l.text = "Rest by the fire (save)"
			l.font_size = 64
			l.pixel_size = 0.02
			l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			l.no_depth_test = true
			add_child(l)
			l.global_position = from + (to - from).normalized() * 20.0
	if off or args.has("look"):
		if what == "storm" and not off:
			Weather.sandstorm(level, float(args.get("seconds", "30")))
		await get_tree().create_timer(float(args.get("seconds", "25"))).timeout
	else:
		match what:
			"desert":
				await _desert()
			"storm":
				await _storm()
			"river":
				await _river()
			"night":
				await _night()
			"curse":
				await _curse()
	print("RESULT atmosphere_test %s %s fails=%d" % [what, "PASS" if _fails == 0 else "FAIL", _fails])
	get_tree().quit(0 if _fails == 0 else 1)


func _weather() -> Weather:
	for n in find_children("Weather", "", true, false):
		if n is Weather and not n.is_queued_for_deletion():
			return n
	return null


func _desert() -> void:
	await get_tree().create_timer(4.0).timeout
	var w := _weather()
	_check(w != null, "desert: the desert's air on its bed")
	if w == null:
		return
	_check(w._grains.emitting and w._grains.amount_ratio > 0.9, "desert: sand on the wind")
	var wisps := w._wisps.filter(func(p: GPUParticles3D) -> bool: return p.emitting).size()
	_check(wisps >= 1, "desert: %d wisps off the crests" % wisps)
	_check(w._shimmer.visible, "desert: the heat shimmer by day (sun %.2f)" % w._sun_up())
	Settings.set_value("quality", "low", get_tree())
	await get_tree().process_frame
	await get_tree().process_frame
	_check(not w._shimmer.visible, "desert: no shimmer on the low preset")
	Settings.set_value("quality", "high", get_tree())
	Weather.on_bed(level, "cairo")
	await get_tree().process_frame
	await get_tree().process_frame
	_check(_weather() == null, "desert: another bed takes it away")


func _storm() -> void:
	await get_tree().create_timer(1.0).timeout
	var w := _weather()
	if w == null:
		_check(false, "storm: weather")
		return
	var env: Environment = level.get("_env")
	var fog0 := env.fog_density
	Weather.sandstorm(level, 20.0)
	var shake := 0.0
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 9000:
		await get_tree().process_frame
		shake = maxf(shake, player.trauma)
	_check(w.storm_f > 0.95 and env.fog_density > 0.045, "storm: at its height, fog %.4f (was %.4f)" % [env.fog_density, fog0])
	_check(w._veil.visible and w._streaks.emitting and not w._shimmer.visible, "storm: the veil and the streaks, no shimmer")
	_check(Weather.visibility() < 0.2, "storm: visibility %.2f" % Weather.visibility())
	_check(shake > 0.1, "storm: buffeting (camera trauma up to %.2f)" % shake)
	await get_tree().create_timer(12.5).timeout
	_check(w.storm_f == 0.0 and is_equal_approx(env.fog_density, fog0) and Weather.visibility() == 1.0,
		"storm: over, the road's fog back (%.4f)" % env.fog_density)


func _river() -> void:
	await get_tree().create_timer(1.5).timeout
	var reeds := level.get_node_or_null("ReedBeds") as MultiMeshInstance3D
	_check(reeds != null and reeds.multimesh.instance_count > 400, "river: reed beds, %d clumps" % (reeds.multimesh.instance_count if reeds else 0))
	var water := level.get_node_or_null("RiverWater") as RiverWater
	var g: float = (water.material_override as ShaderMaterial).get_shader_parameter("glint") if water else 0.0
	_check(water != null and g > 0.3, "river: the sun's glints on the water (%.2f)" % g)


func _night() -> void:
	await get_tree().create_timer(1.5).timeout
	var c: Crowd = level.get("crowd")
	var cl := c.lights if c else null
	_check(cl != null, "night: the crowd's lights")
	if cl == null:
		return
	player.global_position = Vector3(40, 0.1, 77)  # in the bazaar lane
	await get_tree().create_timer(1.2).timeout
	_check(cl.on > 0.95 and cl.lit() >= 1 and cl.lit() <= CrowdLights.MAX_LIGHTS.high, "night: lanterns on, %d lights lit (budget %d)" % [cl.lit(), CrowdLights.MAX_LIGHTS.high])
	_check(cl._lights.all(func(l: OmniLight3D) -> bool: return not l.shadow_enabled), "night: none cast shadows")
	Settings.set_value("quality", "low", get_tree())
	await get_tree().create_timer(0.7).timeout
	_check(cl.lit() == 0 and cl._bulb_mat.emission_energy_multiplier > 2.0, "night: low preset, no lights (the lanterns still glow)")
	Settings.set_value("quality", "high", get_tree())
	level.call("set_day_time", 0.4)
	await get_tree().create_timer(0.7).timeout
	_check(cl.lit() == 0 and cl.on < 0.01, "night: by day all off")


func _curse() -> void:
	await get_tree().create_timer(2.5).timeout
	var c: Crowd = level.get("crowd")
	_check(c != null and c.life != null, "curse: the crowd and its ambient life")
	if c == null or c.life == null:
		return
	_check(c.life.flies > 0.95 and c.life._fly_mm.multimesh.visible_instance_count == AmbientLife.FLIES, "curse: flies about (%d)" % c.life._fly_mm.multimesh.visible_instance_count)
	var dressed := c.people.filter(func(p: CrowdPerson) -> bool: return not p._looks.is_empty())
	var dark := dressed.filter(func(p: CrowdPerson) -> bool: return float(p._looks[0].get_shader_parameter("mourn")) > 0.8)
	_check(not dressed.is_empty() and dark.size() == dressed.size(), "curse: %d of %d robes darkened" % [dark.size(), dressed.size()])
	level.call("set_curse", 0.0, 0.0)
	await get_tree().create_timer(1.0).timeout
	_check(c.life._fly_mm.multimesh.visible_instance_count == 0 and float(dressed[0]._looks[0].get_shader_parameter("mourn")) == 0.0,
		"curse: lifted, no flies, robes back")


func _process(delta: float) -> void:
	_t += delta
	if _t > 4.0:
		_frames.append(delta * 1000.0)
	if _shots.size() > 0 and _t >= _shots[0]:
		_shots.pop_front()
		_shot("atmos_%s_%s_%s_%04.1f.png" % [what, str(args.get("mode", "on")), str(args.get("cam", "player")), _t])


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
	var dir: String = args.get("shot-dir", "user://atmos_shots")
	DirAccess.make_dir_recursive_absolute(dir)
	get_viewport().get_texture().get_image().save_png(dir.path_join(file))
	print("RESULT shot %s" % dir.path_join(file))


func _check(ok: bool, what_: String) -> void:
	print("RESULT %s %s" % ["ok  " if ok else "FAIL", what_])
	if not ok:
		_fails += 1
