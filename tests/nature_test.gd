extends Node3D
## The reusable nature pieces (scripts/nature/, scripts/boat/river_water.gd):
##   default (headless is fine)
##     NavCache: the Akmentar valley built cold (its cache cleared: baked, then saved), again warm
##       (read back: the same polygons, much faster), and with one box moved (stale: baked again);
##     Waterfall: one built (sheet, churn, spray, mist, its roar looping); SoundLife's "falls"
##       loop: loud enough, no click at its seam;
##     Palms: 40 batched into one MultiMesh per variant, their trunks solid.
##     RiverWater.mask_hull: a boat's waterline kept dry (--look --cam=hull: a hollow hull afloat,
##     its hold under the waterline; --no-mask for the before).
##   --look  (windowed) a showcase: a cliff with a waterfall into a pool dug into the ground (its
##           bed sloping from the shore to 3 m), palms round it, a lake beyond; --cam=fall|pool|grove|
##           lake|wide, --shots=t1,.. --shot-dir=path; PERFSUM over --seconds (default 12), the camera
##           sweeping round. --quality=low|medium|high
##   --bakes  the acts' big maps (AkmentarSurface, AkmentarBelow) built twice: navmesh times
##   --ship  also write res://nav/akmentar_valley.res (to commit: the game then loads it at once)
## Never takes focus or captures the mouse.

const CAMS := {
	"fall": [Vector3(26, 6, 30), Vector3(0, 12, 4)],
	"pool": [Vector3(14, 3.5, 22), Vector3(2, 0, 8)],
	"grove": [Vector3(-30, 2.0, 40), Vector3(-6, 6, 18)],
	"lake": [Vector3(30, 2.5, 70), Vector3(10, 0, 40)],
	"wide": [Vector3(60, 22, 80), Vector3(0, 8, 20)],
	"hull": [Vector3(26, 6, 58), Vector3(20, -0.4, 50)],
}

var args := {}
var _fails := 0
var _t := 0.0
var _frames: Array[float] = []
var _shots: Array[float] = []
var _cam: Camera3D
var _look := false


func _ready() -> void:
	get_window().set_flag(Window.FLAG_NO_FOCUS, true)
	args = TestDriver.parse_args()
	Controls.setup()
	Settings.ensure(get_tree())
	if args.has("quality"):
		Settings.set_value("quality", str(args.quality), get_tree())
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if args.has("bakes"):
		await _bakes()
		_end()
		return
	if args.has("look"):
		_look = true
		await _showcase()
		return
	await _navcache()
	_falls_sound()
	await _waterfall()
	await _palms()
	await _hull_mask()
	_end()


# ---------------------------------------------------------------- NavCache

func _navcache() -> void:
	NavCache.ship = args.has("ship")
	for dir: String in [NavCache.USER_DIR]:
		if FileAccess.file_exists(dir + "akmentar_valley.res"):
			DirAccess.remove_absolute(dir + "akmentar_valley.res")
	var shipped := ResourceLoader.exists(NavCache.SHIP_DIR + "akmentar_valley.res") and not args.has("ship")
	var polys: Array[int] = []
	for run: String in ["cold", "warm"]:
		var t0 := Time.get_ticks_msec()
		var v := AkmentarValley.new()
		add_child(v)
		var ms := Time.get_ticks_msec() - t0
		var info: Dictionary = NavCache.last.get("akmentar_valley", {})
		polys.append((v.get("_nav") as NavigationRegion3D).navigation_mesh.get_polygon_count())
		print("RESULT info valley %s: built in %d ms, its navmesh %s in %d ms, %d polygons" % [run, ms, info.get("from", "?"), int(info.get("ms", -1)), polys[-1]])
		if run == "cold":
			_check(info.get("from", "") == ("res" if shipped else "baked"), "navcache: cold, %s" % ("from the shipped res://nav (its signature matches)" if shipped else "baked (no cache)"))
			_check(FileAccess.file_exists(NavCache.USER_DIR + "akmentar_valley.res") or shipped, "navcache: saved to user://navcache")
		else:
			_check(info.get("from", "") in ["res", "user"], "navcache: warm, read back from the cache (%s, %d ms)" % [info.get("from", "?"), int(info.get("ms", -1))])
			_check(polys[0] == polys[1] and polys[1] > 100, "navcache: the same navmesh both times (%d / %d polygons)" % [polys[0], polys[1]])
			# One box moved: the signature changes, so the cache is passed over.
			var nav: NavigationRegion3D = v.get("_nav")
			var sig := NavCache.signature(nav)
			var body := nav.find_children("*", "StaticBody3D", true, false)[3] as Node3D
			body.position.x += 1.0
			_check(NavCache.signature(nav) != sig, "navcache: a moved box changes the signature (a stale cache is rebaked)")
			body.position.x -= 1.0
		remove_child(v)
		v.free()
		await get_tree().process_frame


## --bakes: the acts' big maps built twice each (the first may bake, the second should read the
## cache), with their navmesh times.
func _bakes() -> void:
	for make: Callable in [func() -> Node3D: return AkmentarSurface.new(), func() -> Node3D: return AkmentarBelow.new()]:
		for run: String in ["first", "second"]:
			var t0 := Time.get_ticks_msec()
			var lvl: Node3D = make.call()
			add_child(lvl)
			var nav: NavigationRegion3D = lvl.get("_nav")
			var key := (lvl.get_script() as Script).resource_path.get_file().get_basename()
			var info: Dictionary = NavCache.last.get(key, {})
			print("RESULT info %s %s: built in %d ms, navmesh %s in %d ms, %d polygons" % [key, run, Time.get_ticks_msec() - t0,
				info.get("from", "(no NavCache)"), int(info.get("ms", -1)), nav.navigation_mesh.get_polygon_count()])
			if run == "second" and not info.is_empty():
				_check(info.get("from", "") in ["res", "user"], "bakes: %s read back from the cache" % key)
			remove_child(lvl)
			lvl.free()
			await get_tree().process_frame


# ---------------------------------------------------------------- the waterfall

func _falls_sound() -> void:
	var s := SoundLife.stream("falls", true) as AudioStreamWAV
	_check(s != null and s.loop_mode == AudioStreamWAV.LOOP_FORWARD, "falls: a looping stream")
	if s == null:
		return
	var n := s.data.size() / 2
	var sum := 0.0
	var peak := 0.0
	for i in range(0, n, 7):
		var v := s.data.decode_s16(i * 2) / 32000.0
		sum += v * v
		peak = maxf(peak, absf(v))
	var rms := sqrt(sum / (n / 7.0))
	var seam := absf(s.data.decode_s16((n - 1) * 2) - s.data.decode_s16(0)) / 32000.0
	_check(rms > 0.05 and peak < 0.99, "falls: a roar (rms %.2f, peak %.2f, %.1f s)" % [rms, peak, n / float(SoundLife.RATE)])
	_check(seam < 0.15, "falls: the loop's seam doesn't click (jump %.3f)" % seam)


func _waterfall() -> void:
	var f := Waterfall.make(self, Vector3(0, 20, 0), 6.0, 18.0, Vector3.BACK)
	await get_tree().process_frame
	var kinds := {}
	for c in f.get_children():
		kinds[c.name] = c.get_class()
	_check(kinds.has("Sheet") and kinds.has("Churn") and kinds.get("Spray", "") == "GPUParticles3D" and kinds.get("Mist", "") == "GPUParticles3D",
		"waterfall: sheet, churn, spray and mist (%s)" % str(kinds.keys()))
	_check(f.sound != null and f.sound.stream != null, "waterfall: its roar looping")
	var b := f.base()
	_check(absf(b.y - 2.0) < 0.01 and b.z > 2.0, "waterfall: lands below the lip, thrown out %.1f m" % b.z)
	f.queue_free()


# ---------------------------------------------------------------- palms

func _palms() -> void:
	var grove := Node3D.new()
	add_child(grove)
	var nav := Node3D.new()
	add_child(nav)
	for k in 40:
		Palms.add(grove, Vector3(fmod(k * 7.3, 40.0), 0, k * 1.9), 0.0, nav)
	_check(nav.get_child_count() == 40, "palms: 40 trunks solid at once (%d bodies)" % nav.get_child_count())
	await get_tree().process_frame
	var mms := grove.find_children("*", "MultiMeshInstance3D", false, false)
	var total := 0
	for m in mms:
		total += (m as MultiMeshInstance3D).multimesh.instance_count
	_check(mms.size() >= 3 and mms.size() <= 4 and total == 40, "palms: batched, %d MultiMeshes for %d palms" % [mms.size(), total])
	var tall := Palms.VARIANTS.map(func(v: Dictionary) -> float: return v.h)
	print("RESULT info palm variants: heights %s" % str(tall))


## RiverWater.mask_hull: a boat's footprint goes to the water's shader, and leaves when it's freed.
func _hull_mask() -> void:
	var w := RiverWater.make(self, Vector2(40, 40), 0.0)
	var boat := Node3D.new()
	add_child(boat)
	RiverWater.mask_hull(boat, Vector2(2, 6))
	await get_tree().process_frame
	await get_tree().process_frame
	var m := w.material_override as ShaderMaterial
	_check(int(m.get_shader_parameter("hull_count")) == 1, "hull mask: a boat's waterline in the water's shader")
	boat.free()
	await get_tree().process_frame
	await get_tree().process_frame
	_check(int(m.get_shader_parameter("hull_count")) == 0, "hull mask: gone with the boat")
	w.queue_free()


# ---------------------------------------------------------------- the showcase

func _showcase() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	for s in str(args.get("shots", "")).split(",", false):
		_shots.append(float(s))
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.shadow_enabled = true
	sun.rotation = Vector3(deg_to_rad(-38), deg_to_rad(28), 0)
	sun.light_color = Color(1.0, 0.95, 0.85)
	add_child(sun)
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = Sky.new()
	env.sky.sky_material = ProceduralSkyMaterial.new()
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_density = 0.002
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sand := StandardMaterial3D.new()
	sand.albedo_color = Color(0.78, 0.66, 0.48)
	var rock := StandardMaterial3D.new()
	rock.albedo_color = Color(0.6, 0.45, 0.32)
	var mud := StandardMaterial3D.new()
	mud.albedo_color = Color(0.45, 0.4, 0.3)
	var nav := Node3D.new()
	add_child(nav)
	# Ground round a pool (x -12..12, z 2..22) and a lake (x -10..40, z 34..70): slabs around them.
	_box(nav, Vector3(0, -0.5, -40), Vector3(200, 1, 84), sand)
	_box(nav, Vector3(-56, -0.5, 36), Vector3(88, 1, 72), sand)
	_box(nav, Vector3(66, -0.5, 36), Vector3(68, 1, 72), sand)
	_box(nav, Vector3(14, -0.5, 28), Vector3(52, 1, 12), sand)
	_box(nav, Vector3(26, -0.5, 12), Vector3(28, 1, 20), sand)
	_box(nav, Vector3(0, -0.5, 100), Vector3(200, 1, 60), sand)
	# The pool's bed: a ramp from the shore down to 3 m, and the lake's floor at 2.5 m.
	var bed := _box(nav, Vector3(0, -1.7, 12), Vector3(24, 0.4, 22), mud)
	bed.rotation.x = deg_to_rad(-7)
	_box(nav, Vector3(0, -3.5, 12), Vector3(24, 1, 22), mud)
	_box(nav, Vector3(15, -3.0, 52), Vector3(50, 1, 36), mud)
	for b: Array in [[Vector3(-12.5, -1.5, 12), Vector3(1, 3, 22)], [Vector3(12.5, -1.5, 12), Vector3(1, 3, 22)],
			[Vector3(0, -1.5, 22.5), Vector3(26, 3, 1)], [Vector3(-10.5, -1.5, 52), Vector3(1, 3, 36)],
			[Vector3(40.5, -1.5, 52), Vector3(1, 3, 36)], [Vector3(15, -1.5, 34.5), Vector3(52, 3, 1)], [Vector3(15, -1.5, 70.5), Vector3(52, 3, 1)]]:
		_box(nav, b[0], b[1], sand)
	# The cliff, the fall off it into the pool, rocks at the pool's edge.
	_box(nav, Vector3(0, 12, -6), Vector3(60, 24, 12), rock)
	var f := Waterfall.make(self, Vector3(0, 24, 0.1), 8.0, 24.2, Vector3.BACK)
	for r: Vector3 in [Vector3(-9, 0.2, 18), Vector3(8, 0.0, 20), Vector3(10.5, 0.4, 6)]:
		var rk := _box(nav, r, Vector3(2.2, 1.6, 1.8), rock)
		rk.rotation = Vector3(0.3, r.x, 0.2)
	var pool := RiverWater.make(self, Vector2(24, 21), -0.25, Vector3(0, 0, 12.5))
	RiverWater.depth(pool, 0.4, 0.6)
	(pool.material_override as ShaderMaterial).set_shader_parameter("flow", Vector2(0, 0.25))
	var lake := RiverWater.make(self, Vector2(50, 36), -0.3, Vector3(15, 0, 52))
	RiverWater.depth(lake, 0.5, 0.6)
	(lake.material_override as ShaderMaterial).set_shader_parameter("flow", Vector2(0.05, 0.05))
	# A hollow hull afloat on the lake, its hold's floor under the waterline (RiverWater.mask_hull
	# keeps the river out of it; --no-mask for the before).
	var hull := Node3D.new()
	hull.name = "Hull"
	add_child(hull)
	hull.position = Vector3(20, -0.3, 50)
	hull.rotation.y = 0.4
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.42, 0.3, 0.2)
	_box(hull, Vector3(0, -0.5, 0), Vector3(4.0, 0.2, 11.0), wood)            # the hold's floor, 0.5 m under
	for side: float in [-1.0, 1.0]:
		_box(hull, Vector3(side * 1.95, 0.15, 0), Vector3(0.1, 1.5, 11.0), wood)  # the sides, 0.9 m freeboard
		_box(hull, Vector3(0, 0.15, side * 5.45), Vector3(4.0, 1.5, 0.1), wood)  # bow and stern
	if not "--no-mask" in OS.get_cmdline_user_args():
		RiverWater.mask_hull(hull, Vector2(1.85, 5.35), 8.0)
	# Palms: round the pool and the lake, a grove to the west.
	var pts: Array = []
	for k in 30:
		pts.append(Vector3(-30 + fmod(k * 9.7, 18.0), 0, 6 + fmod(k * 13.1, 40.0)))
	for z in [4.0, 10.0, 17.0, 24.0]:
		pts.append(Vector3(16.0 + fmod(z, 3.0), 0, z))
	for x in [-6.0, 4.0, 14.0, 24.0, 34.0]:
		pts.append(Vector3(x, 0, 74.0 + fmod(x * 0.7, 3.0)))
	Palms.place(self, pts, nav)
	_cam = Camera3D.new()
	_cam.far = 1500.0
	add_child(_cam)
	_cam.make_current()
	var c: Array = CAMS.get(str(args.get("cam", "wide")), CAMS.wide)
	_cam.look_at_from_position(c[0], c[1])
	print("RESULT info showcase: waterfall lands at %s, %d palms" % [f.base().snapped(Vector3.ONE * 0.1), pts.size()])
	await get_tree().create_timer(float(args.get("seconds", "12"))).timeout
	_end()


func _box(parent: Node, at: Vector3, size: Vector3, mat: Material) -> StaticBody3D:
	var b := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	b.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	b.add_child(mi)
	parent.add_child(b)
	b.position = at
	return b


func _process(delta: float) -> void:
	if not _look:
		return
	_t += delta
	if _t > 2.0:
		_frames.append(delta * 1000.0)
	if not args.has("cam") and _cam:
		# A slow sweep round the scene: the frame rate from every side.
		var a := _t * 0.25
		_cam.look_at_from_position(Vector3(8 + sin(a) * 45.0, 9, 30 + cos(a) * 45.0), Vector3(4, 4, 24))
	if _shots.size() > 0 and _t >= _shots[0]:
		_shots.pop_front()
		_shot("nature_%s_%04.1f.png" % [str(args.get("cam", "sweep")), _t])


func _shot(file: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var dir: String = args.get("shot-dir", "user://nature_shots")
	DirAccess.make_dir_recursive_absolute(dir)
	get_viewport().get_texture().get_image().save_png(dir.path_join(file))
	print("RESULT shot %s" % dir.path_join(file))


func _end() -> void:
	if _frames.size() > 10:
		var s := _frames.duplicate()
		s.sort()
		var mean := 0.0
		for f in s:
			mean += f
		mean /= s.size()
		print("PERFSUM frames=%d mean_ms=%.2f (%.0f fps) p95_ms=%.1f draws=%d" % [s.size(), mean, 1000.0 / mean, s[int(s.size() * 0.95)],
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)])
	print("RESULT nature_test %s fails=%d" % ["PASS" if _fails == 0 else "FAIL", _fails])
	get_tree().quit(0 if _fails == 0 else 1)


func _check(ok: bool, what: String) -> void:
	print("RESULT %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_fails += 1
