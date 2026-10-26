extends Node3D
## Lighting check for the darkest places a player fights in: Act 5's halls (the cells farthest
## from any torch), Act 4's night at Akmentar, Act 6's night road, Act 8's night on the boat. Each
## level is lit the way its act lights it; two stand-in figures stand 10 m ahead (a dark bandit,
## a pale mummy). For each view it saves a shot and logs the floor's brightness and how far each
## figure stands out from what's around it (luma 0..1). Windowed only.
## Args after "--": --shot-dir=C:/path, --tag=before|after (in the file names).

const EYE := 1.7
const AHEAD := 10.0

var _dir := "user://lighting_shots"
var _tag := "now"
var _cam: Camera3D
var _figs: Array[MeshInstance3D] = []


func _ready() -> void:
	get_window().set_flag(Window.FLAG_NO_FOCUS, true)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot-dir="):
			_dir = a.substr(11)
		elif a.begins_with("--tag="):
			_tag = a.substr(6)
	DirAccess.make_dir_recursive_absolute(_dir)
	_cam = Camera3D.new()
	_cam.fov = 62.0
	_cam.far = 600.0
	add_child(_cam)
	_cam.current = true
	for c in [Color(0.2, 0.17, 0.14), Color(0.62, 0.56, 0.44)]:
		var mi := MeshInstance3D.new()
		var cap := CapsuleMesh.new()
		cap.radius = 0.3
		cap.height = 1.8
		mi.mesh = cap
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = 0.9
		mi.material_override = m
		add_child(mi)
		_figs.append(mi)
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		print("RESULT lighting_shots: headless, no shots")
		get_tree().quit(0)
		return
	# Act 5: the halls between torches.
	var below := AkmentarBelow.new()
	add_child(below)
	if _tag == "before":  # the tomb as it was before its fill (AkmentarBelow.TOMB_FILL)
		below._env.ambient_light_energy = 0.2
		below._env.ambient_light_color = Color(0.32, 0.26, 0.2)
		below._env.fog_light_color = Color(0.12, 0.08, 0.05)
	for v in _dark_cells(below, 2):
		await _view("act5_hall_%d" % v[2], v[0], v[1])
	below.queue_free()
	await get_tree().process_frame
	# Act 4: night at Akmentar (the surface's own night).
	var surface := AkmentarSurface.new()
	add_child(surface)
	surface.set_night(1.0)
	await _view("act4_camp_north", Vector3(70, 0, 110), Vector3(0, 0, -1))
	await _view("act4_court", Vector3(52, 0, 70), Vector3(1, 0, 0))
	surface.queue_free()
	await get_tree().process_frame
	# Act 6: the night road (act6's darken).
	var road := DesertRoute.new()
	add_child(road)
	(load("res://scripts/acts/act6.gd") as GDScript).call("darken", road, 0.85)
	var p := DesertRoute.road_point(DesertRoute.START_Z - 40.0)
	await _view("act6_road", p, DesertRoute.road_dir(DesertRoute.START_Z - 40.0))
	road.queue_free()
	await get_tree().process_frame
	# Act 8: the boat at night (act8_boat's night and lanterns).
	var river := RiverRoute.new()
	add_child(river)
	var boat_script := load("res://scripts/acts/act8_boat.gd") as GDScript
	boat_script.call("night", river)
	var boat := RiverBoat.make(river, river.path, "lighting", 120.0)
	boat_script.call("lanterns", boat)
	await get_tree().process_frame
	var fwd := -boat.global_basis.z
	# (the cabin fills x ±2.3, z -8..10: down the starboard passage, and across the foredeck)
	await _view("act8_passage", boat.to_global(Vector3(3.4, RiverBoat.DECK_Y, 9.0)), fwd)
	await _view("act8_foredeck", boat.to_global(Vector3(0.0, RiverBoat.DECK_Y, -9.5)), fwd, 6.5)
	get_tree().quit(0)


## Floor cells farthest from any torch with 10 m of open floor straight ahead: [pos, dir, n].
func _dark_cells(level: AkmentarBelow, count: int) -> Array:
	var lights: Array[Vector3] = []
	for l in level.torches:
		lights.append(l.global_position)
	var best: Array = []
	for r in level._rows:
		for c in level._cols:
			if level._ch(r, c) != ".":
				continue
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var open := true
				for k in range(-1, 6):  # (the cell behind too: the camera stands there)
					open = open and level._ch(r + d.y * k, c + d.x * k) == "."
				if not open:
					continue
				var at := level._cell(r, c)
				var near := INF
				for lp in lights:
					near = minf(near, lp.distance_to(at))
				best.append([near, at, Vector3(d.x, 0, d.y)])
	best.sort_custom(func(a, b): return a[0] > b[0])
	var out: Array = []
	for b in best:
		if out.size() >= count:
			break
		if out.any(func(o): return (o[0] as Vector3).distance_to(b[1]) < 16.0):
			continue
		print("RESULT dark cell at %s, %.1f m from the nearest flame" % [b[1], b[0]])
		out.append([b[1], b[2], out.size() + 1])
	return out


func _view(name: String, feet: Vector3, dir: Vector3, ahead := AHEAD) -> void:
	dir = Vector3(dir.x, 0, dir.z).normalized()
	var side := dir.cross(Vector3.UP)
	var target := feet + dir * ahead
	_figs[0].global_position = target - side * 0.8 + Vector3.UP * 0.9
	_figs[1].global_position = target + side * 0.8 + Vector3.UP * 0.9
	_cam.look_at_from_position(feet - dir * 1.5 + Vector3.UP * EYE, target + Vector3.UP * 1.0)
	for i in 10:
		await get_tree().process_frame
	var space := get_world_3d().direct_space_state
	var pq := PhysicsPointQueryParameters3D.new()
	pq.position = _cam.global_position
	var ray := space.intersect_ray(PhysicsRayQueryParameters3D.create(_cam.global_position, target + Vector3.UP))
	print("RESULT view %s: camera inside a solid=%s, first hit toward the figures %s" % [name,
		not space.intersect_point(pq, 1).is_empty(), "%.1f m" % _cam.global_position.distance_to(ray.position) if ray else "none"])
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := _dir.path_join("light_%s_%s.png" % [name, _tag])
	img.save_png(path)
	var w := img.get_width()
	var h := img.get_height()
	var floor_l := _mean(img, Rect2i(int(w * 0.3), int(h * 0.78), int(w * 0.4), int(h * 0.2)))
	var figs: Array[String] = []
	for f in _figs:
		var top := _cam.unproject_position(f.global_position + Vector3.UP * 0.9)
		var bot := _cam.unproject_position(f.global_position - Vector3.UP * 0.9)
		var fh := maxi(int(bot.y - top.y), 4)
		var box := Rect2i(int(top.x) - fh / 8, int(top.y), maxi(fh / 4, 2), fh)
		var ring := box.grow(fh / 4)
		var inside := _mean(img, box)
		var around := (_mean(img, ring) * ring.get_area() - inside * box.get_area()) / maxf(ring.get_area() - box.get_area(), 1.0)
		figs.append("%.3f vs %.3f (contrast %.3f)" % [inside, around, absf(inside - around)])
	print("RESULT light %-16s floor %.3f  bandit %s  mummy %s  -> %s" % [name, floor_l, figs[0], figs[1], ProjectSettings.globalize_path(path)])


func _mean(img: Image, r: Rect2i) -> float:
	r = r.intersection(Rect2i(0, 0, img.get_width(), img.get_height()))
	if r.get_area() <= 0:
		return 0.0
	var s := 0.0
	var n := 0
	for y in range(r.position.y, r.end.y, 2):
		for x in range(r.position.x, r.end.x, 2):
			s += img.get_pixel(x, y).get_luminance()
			n += 1
	return s / maxf(n, 1)
