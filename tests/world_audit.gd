extends Node
## The world audit (gameplan/world_audit.md): for one place (--place=<id>, --list for all), opens
## it through its act's scene, waits until it's built, and measures it: the walkable area (the
## navmesh: bounds, m², the longest walk from where you arrive and its time at a walk and a sprint), the
## geometry's bounds, what's in it (meshes, and how many are primitive boxes and cylinders, i.e.
## blockout, against modelled GLB props; the distinct models; people; things to use; lights), and
## two screenshots: from above, and as the player sees it. Windowed (off-screen), and with
## --no-merge so Cairo's and the tomb's blockout boxes are counted as boxes. One Godot at a time:
##   godot --path . res://tests/world_audit.tscn -- --list
##   godot --path . res://tests/world_audit.tscn -- --place=cairo --no-merge --shot-dir=C:/path

const PLACES := {
	"cairo": {"scene": "res://act2.tscn", "args": [], "wait": 6.0, "label": "Cairo (Acts 1, 2, 7) with the interiors"},
	"desert_road": {"scene": "res://act3_desert.tscn", "args": [], "wait": 5.0, "label": "The desert road and its town (Act 3; Act 3's night camp)"},
	"coast_road": {"scene": "res://act3_coast.tscn", "args": [], "wait": 5.0, "label": "The coast road and its town (Act 3)"},
	"riverboat": {"scene": "res://act3_riverboat.tscn", "args": [], "wait": 5.0, "label": "The river and the riverboat (Act 3; Act 8's boat)"},
	"temple": {"scene": "res://act8_temple.tscn", "args": [], "wait": 5.0, "label": "The desert temple (act3_temple, act8_temple)"},
	"camp_act6": {"scene": "res://act6.tscn", "args": ["--auto", "--plan=hold"], "until": "ROAD", "wait": 3.0, "label": "Act 6's night camp on the road back"},
	"surface": {"scene": "res://act4.tscn", "args": ["--auto"], "until": "DAY", "wait": 4.0, "label": "Akmentar's surface (Acts 4, 9)"},
	"tomb": {"scene": "res://act5.tscn", "args": [], "wait": 6.0, "inside": true, "label": "The tomb, five levels (Acts 5, 9)"},
	"flight": {"scene": "res://act8_flight.tscn", "args": ["--auto"], "until": "FLIGHT", "wait": 4.0, "label": "The flight range (Act 8)"},
	"chase": {"scene": "res://act8_chase.tscn", "args": [], "wait": 5.0, "label": "The chariot-chase road (Act 8)"},
}


func _ready() -> void:
	get_window().set_flag(Window.FLAG_NO_FOCUS, true)
	var args := TestDriver.parse_args()
	if args.has("list"):
		for id: String in PLACES:
			print("PLACE %s %s" % [id, " ".join(["--place=" + id, "--save-slot=audit_" + id, "--no-merge"] + Array(PLACES[id].args))])
		get_tree().quit(0)
		return
	var id := str(args.get("place", ""))
	if not PLACES.has(id):
		print("AUDIT %s FAIL not a place (--list)" % id)
		get_tree().quit(1)
		return
	var w := get_window()
	w.size = Vector2i(1600, 900)
	w.position = Vector2i(-1800, 40)  # off-screen
	Game.reset()
	var a := Auditor.new()
	a.id = id
	a.spec = PLACES[id]
	a.dir = str(args.get("shot-dir", "user://world_audit"))
	DirAccess.make_dir_recursive_absolute(a.dir)
	get_tree().root.add_child.call_deferred(a)
	get_tree().change_scene_to_file.call_deferred(PLACES[id].scene)


class Auditor extends Node:
	var id := ""
	var spec := {}
	var dir := ""

	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS
		_run.call_deferred()

	func _run() -> void:
		var t0 := Time.get_ticks_msec()
		while get_tree().current_scene == null or get_tree().current_scene == self or _level() == null:
			await get_tree().process_frame
			if Time.get_ticks_msec() - t0 > 60000:
				return _fail("no level after 60 s")
		if spec.has("until"):
			while _step_name() != spec.until:
				await get_tree().process_frame
				if Time.get_ticks_msec() - t0 > 400000:
					return _fail("never reached step %s (at %s)" % [spec.until, _step_name()])
		await get_tree().create_timer(float(spec.get("wait", 4.0))).timeout
		var cs := get_tree().current_scene
		var lv := _level()
		var r := {"place": id, "label": spec.label, "level": lv.get_script().get_global_name() if lv.get_script() else lv.get_class()}
		r.merge(_walkable(lv))
		r.merge(_contents(cs))
		await _shot(cs, "player")
		await _overview(cs, r)
		print("AUDIT " + JSON.stringify(r))
		get_tree().quit(0)

	func _fail(why: String) -> void:
		print("AUDIT %s FAIL %s" % [id, why])
		get_tree().quit(1)

	func _level() -> Level:
		var cs := get_tree().current_scene
		if cs == null:
			return null
		var l: Variant = cs.get("level")
		if l is Level and is_instance_valid(l):
			return l
		for n in cs.get_children():
			if n is Level:
				return n
		return null

	func _step_name() -> String:
		var cs := get_tree().current_scene
		var steps: Variant = cs.get_script().get_script_constant_map().get("Step") if cs and cs.get_script() else null
		if not steps is Dictionary or cs.get("step") == null:
			return ""
		for k: String in steps:
			if steps[k] == cs.get("step"):
				return k
		return ""

	## The navmesh: where you can walk. Bounds, area, and the longest walk across it.
	func _walkable(lv: Level) -> Dictionary:
		var nav: NavigationRegion3D = lv.get("_nav")
		var nm: NavigationMesh = nav.navigation_mesh if nav else null
		if nm == null or nm.get_polygon_count() == 0:
			return {"walk_area_m2": 0, "walk_note": "no navmesh (not walked)"}
		var verts := nm.get_vertices()
		var xf := nav.global_transform
		var lo := Vector3.INF
		var hi := -Vector3.INF
		var area := 0.0
		for i in nm.get_polygon_count():
			var poly := nm.get_polygon(i)
			for k in range(1, poly.size() - 1):
				var a := xf * verts[poly[0]]
				var b := xf * verts[poly[k]]
				var c := xf * verts[poly[k + 1]]
				area += 0.5 * Vector2(b.x - a.x, b.z - a.z).cross(Vector2(c.x - a.x, c.z - a.z)) * signf(Vector2(b.x - a.x, b.z - a.z).cross(Vector2(c.x - a.x, c.z - a.z)))
		for v in verts:
			var g := xf * v
			lo = lo.min(g)
			hi = hi.max(g)
		# The longest walk from where the player stands to anywhere reachable (sampled; a path counts
		# only if it gets there: roofs and closed rooms are islands nobody walks to).
		var map := nav.get_navigation_map()
		var p: Variant = get_tree().current_scene.get("player")
		var from := NavigationServer3D.map_get_closest_point(map, (p as Node3D).global_position if p is Node3D else lo)
		var length := 0.0
		var a_end := from
		var b_end := from
		var step := maxi(1, verts.size() / 300)
		for i in range(0, verts.size(), step):
			var to := xf * verts[i]
			var path := NavigationServer3D.map_get_path(map, from, to, true)
			if path.size() < 2 or path[path.size() - 1].distance_to(to) > 1.5:
				continue
			var l := 0.0
			for k in range(1, path.size()):
				l += path[k].distance_to(path[k - 1])
			if l > length:
				length = l
				b_end = to
		var size := hi - lo
		return {"walk_x_m": snappedf(size.x, 1), "walk_z_m": snappedf(size.z, 1), "walk_y_m": snappedf(size.y, 0.5),
			"walk_area_m2": snappedf(area, 10), "cross_m": snappedf(length, 1),
			"cross_walk_s": snappedf(length / Player.WALK, 1), "cross_sprint_s": snappedf(length / Player.SPRINT, 1),
			"cross_from": a_end.snapped(Vector3.ONE), "cross_to": b_end.snapped(Vector3.ONE)}

	## What's in it, by kind; and how much is blockout (primitive meshes) against modelled props.
	func _contents(cs: Node) -> Dictionary:
		var prim := 0
		var modelled := 0
		var models := {}
		var lo := Vector3.INF
		var hi := -Vector3.INF
		var people := {}
		var uses := 0
		var lights := 0
		var bodies := 0
		for n in cs.find_children("*", "", true, false):
			if n is MeshInstance3D and (n as MeshInstance3D).is_visible_in_tree() and (n as MeshInstance3D).mesh:
				var m := n as MeshInstance3D
				if m.mesh is PrimitiveMesh:
					prim += 1
				else:
					modelled += 1
				var bb := m.global_transform * m.get_aabb()
				if maxf(bb.size.x, bb.size.z) < 600.0:  # (not the ground plane or the sky's horizon)
					lo = lo.min(bb.position)
					hi = hi.max(bb.end)
			if n is Node3D and (n as Node).scene_file_path.ends_with(".glb"):
				models[n.scene_file_path.get_file()] = int(models.get(n.scene_file_path.get_file(), 0)) + 1
			if n is OmniLight3D or n is SpotLight3D:
				lights += 1
			if n is StaticBody3D:
				bodies += 1
			if n is Interactable or n is ActionSpot:
				uses += 1
			for cls: String in ["Npc", "CrowdPerson", "Townsperson", "Gunman", "Mummy", "Rider"]:
				var sc: Script = n.get_script()
				if sc and sc.get_global_name() == cls:
					people[cls] = int(people.get(cls, 0)) + 1
		var size := hi - lo
		var top: Array = models.keys()
		top.sort_custom(func(a: String, b: String) -> bool: return int(models[a]) > int(models[b]))
		return {"geo_x_m": snappedf(size.x, 1), "geo_z_m": snappedf(size.z, 1), "geo_y_m": snappedf(size.y, 1),
			"meshes_primitive": prim, "meshes_modelled": modelled,
			"blockout_pct": snappedf(100.0 * prim / maxf(prim + modelled, 1), 1), "static_bodies": bodies,
			"models_distinct": models.size(), "models_placed": models.values().reduce(func(s: int, v: int) -> int: return s + v, 0),
			"models_top": top.slice(0, 12).map(func(k: String) -> String: return "%s x%d" % [k.get_basename(), models[k]]),
			"people": people, "things_to_use": uses, "lights": lights}

	func _shot(cs: Node, tag: String) -> void:
		for c in get_tree().root.find_children("*", "CanvasLayer", true, false):
			(c as CanvasLayer).visible = false  # the place, not the HUD, cards or talks
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(dir.path_join("%s_%s.png" % [id, tag]))

	## From above: over the walkable middle (or the geometry's), looking down at 50 degrees.
	func _overview(cs: Node, r: Dictionary) -> void:
		var w := Vector2(float(r.get("walk_x_m", 0.0)), float(r.get("walk_z_m", 0.0)))
		var use_walk := w.x > 1.0
		var span := maxf(w.x, w.y) if use_walk else maxf(float(r.geo_x_m), float(r.geo_z_m))
		var centre: Vector3
		if use_walk:
			centre = ((r.cross_from as Vector3) + (r.cross_to as Vector3)) * 0.5
		else:
			var p: Variant = cs.get("player")
			centre = (p as Node3D).global_position if p is Node3D else Vector3.ZERO
		span = clampf(span, 40.0, 900.0)
		var cam := Camera3D.new()
		cam.far = 4000.0
		cam.fov = 60.0
		cs.add_child(cam)
		if spec.get("inside", false):
			# Underground: from just under the top level's ceiling, down into the levels below.
			var top := (r.cross_from as Vector3).y + 1.0  # (the player arrives on the top level)
			cam.global_position = Vector3(centre.x, top + 3.0, centre.z + span * 0.35)
			cam.look_at(Vector3(centre.x, top - 20.0, centre.z - span * 0.1), Vector3.UP)
		else:
			cam.global_position = centre + Vector3(0, span * 0.55, span * 0.6)
			cam.look_at(centre, Vector3.UP)
		cam.make_current()
		for e in cs.find_children("*", "WorldEnvironment", true, false):  # the haze hides a view from height
			var env := (e as WorldEnvironment).environment
			if env:
				env.fog_enabled = false
				env.volumetric_fog_enabled = false
		for i in 3:
			await get_tree().process_frame
		await _shot(cs, "overview")
