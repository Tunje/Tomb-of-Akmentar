extends Node3D
## Act 2 map test: builds Cairo, checks every named spot is reachable on the navmesh from the
## spawn and that no spot or person stands inside something solid, then (with a window) takes
## day and dusk screenshots round the quarter. Prints RESULT lines; exits 0 when every check
## passed. Args after "--":
##   --shot-dir=C:/path   where PNGs go (default user://cairo_shots)
##   --no-shots           checks only (headless)
## Never takes focus or captures the mouse (Simon plays while we test).

const VIEWS := [
	["avenue_west", Vector3(4, 3.0, 50), Vector3(60, 2, 50)],
	["hotel", Vector3(47, 2.2, 58), Vector3(47, 4, 44)],
	["museum", Vector3(92, 2.5, 45), Vector3(92, 4, 26)],
	["bazaar", Vector3(70, 2.0, 77), Vector3(36, 1.6, 77)],
	["caravanserai", Vector3(100, 3.0, 96), Vector3(84, 1.0, 64)],
	["docks", Vector3(96, 4.0, 40), Vector3(122, 0, 54)],
	["tavern", Vector3(36, 2.0, 74), Vector3(26, 2, 64)],
	["station", Vector3(22, 2.5, 50), Vector3(0, 5, 50)],
	["road_gate", Vector3(29, 2.2, 84), Vector3(29, 2, 104)],
	["overview", Vector3(-6, 45, 120), Vector3(56, 0, 46)],
]

var _dir := "user://cairo_shots"
var _shots := true
var _level: Cairo
var _cam: Camera3D
var _fails := 0


func _ready() -> void:
	get_window().set_flag(Window.FLAG_NO_FOCUS, true)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot-dir="):
			_dir = a.substr(11)
		elif a == "--no-shots":
			_shots = false
	if DisplayServer.get_name() == "headless":
		_shots = false
	DirAccess.make_dir_recursive_absolute(_dir)
	var t0 := Time.get_ticks_msec()
	_level = Cairo.new()
	add_child(_level)
	print("RESULT build_ms %d" % (Time.get_ticks_msec() - t0))
	_level.place_people()
	_level.place_people({}, Cairo.LATER_PEOPLE)  # Act 7's, so their stand points are checked too
	_cam = Camera3D.new()
	_cam.fov = 62.0
	_cam.far = 900.0
	add_child(_cam)
	_cam.current = true
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print("RESULT %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_fails += 1


func _run() -> void:
	for i in 4:
		await get_tree().physics_frame
	var map := get_world_3d().navigation_map
	for i in 120:  # until the server has synced the baked region into the map
		if NavigationServer3D.map_get_iteration_id(map) > 0 and NavigationServer3D.map_get_closest_point(map, _level.player_spawn) != Vector3.ZERO:
			break
		await get_tree().physics_frame
	var space := get_world_3d().direct_space_state
	var from := NavigationServer3D.map_get_closest_point(map, _level.player_spawn)
	var nm: NavigationMesh = _level._nav.navigation_mesh
	print("RESULT navmesh %d polys, closest to spawn %s, map regions %d" % [nm.get_polygon_count(), from, NavigationServer3D.map_get_regions(map).size()])
	_check(from.distance_to(_level.player_spawn) < 0.6, "spawn is on the navmesh")
	for id in _level.spots:
		var to: Vector3 = _level.spots[id]
		if id == "museum":
			to.y = 0.15
		var path := NavigationServer3D.map_get_path(map, from, to, true)
		var end := path[path.size() - 1] if path.size() > 0 else from
		_check(path.size() > 0 and Vector2(end.x, end.z).distance_to(Vector2(to.x, to.z)) < 0.9, "reach %s (path end %.1f m off at %s)" % [id, Vector2(end.x, end.z).distance_to(Vector2(to.x, to.z)), end])
		_check(not _inside(space, to + Vector3.UP * 1.0), "%s spot is clear" % id)
	for id in _level.npcs:
		var p: Vector3 = (_level.npcs[id] as Node3D).global_position
		_check(not _inside(space, p + Vector3.UP * 1.0), "%s stands clear" % id)
	_check(_level.interactables.has("hotel_bed"), "the hotel bed is usable")
	_audit_act("act2", "res://actions/act2_plan.json", space)
	_audit_act("act7", "res://actions/act7_plan.json", space)
	# Act 1 stands people by its doors (Cairo.near_spot): those points must be open ground.
	for p in [["club", 1.4, 0.0], ["club", 0.0, 4.0], ["club", -1.5, 5.0], ["tavern", -1.4, 0.3]]:
		var at := _level.near_spot(p[0], p[1], p[2])
		_check(not _blocked(space, at), "act1 stand by %s (%.1f, %.1f) is open" % p)
	# open_point pulls a point inside a building out onto the street.
	var inside := Vector3(63, 0, 58)  # in the officers' club
	_check(not _blocked(space, _level.open_point(inside)), "open_point gets out of the club (%s)" % _level.open_point(inside).snapped(Vector3.ONE * 0.1))
	# Townsfolk walk without collision: their routes must not cross anything solid.
	for w in Cairo.WALKS:
		var blocked := ""
		for k in w.size():
			var a: Vector3 = w[k]
			var b: Vector3 = w[(k + 1) % w.size()]
			var steps := int(a.distance_to(b) / 0.4) + 1
			for s in steps + 1:
				var p := a.lerp(b, float(s) / steps)
				for y in [0.4, 1.2]:
					if blocked == "" and _inside(space, p + Vector3.UP * y):
						blocked = "%s" % p
		_check(blocked == "", "walk %s..%s is clear%s" % [w[0], w[1], "" if blocked == "" else " (blocked at %s)" % blocked])
	_check(_level.townsfolk.size() == Cairo.WALKS.size() + Cairo.CHATS.size() * 2, "townsfolk about (%d)" % _level.townsfolk.size())
	_check(is_equal_approx(Cairo.day_time_for(3, 3), 0.0) and is_equal_approx(Cairo.day_time_for(0, 3), 1.0), "day_time_for: morning to dusk")
	if _shots:
		for t in [0.15, 0.5, 1.0]:
			_level.set_day_time(t)
			var label: String = {0.15: "morning", 0.5: "noon", 1.0: "dusk"}[t]
			for v in VIEWS:
				if t != 0.5 and not v[0] in ["avenue_west", "bazaar", "museum", "overview"]:
					continue
				_cam.look_at_from_position(v[1], v[2])
				for i in 8:
					await get_tree().process_frame
				var img := get_viewport().get_texture().get_image()
				var path := _dir.path_join("cairo_%s_%s.png" % [v[0], label])
				img.save_png(path)
				print("SHOT ", ProjectSettings.globalize_path(path))
	print("RESULT %s (%d failed)" % ["PASS" if _fails == 0 else "FAIL", _fails])
	get_tree().quit(0 if _fails == 0 else 1)


## An act's layout as the act builds it (an ActionSpot per plan spot, the hotel bed): no two
## prompts close enough to hide each other, each one picked when you walk up to its door and
## face it, and nobody the act stands about on a prompt or against a wall.
func _audit_act(act: String, plan_path: String, space: PhysicsDirectSpaceState3D) -> void:
	var plan: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(plan_path))
	var made: Array[ActionSpot] = []
	for id in plan.get("spots", {}):
		made.append(ActionSpot.make(_level, str(plan.spots[id]), _level.spots[id]))
	var prompts := {}  # spot id -> Interactable
	for i in made.size():
		prompts[str((plan.spots as Dictionary).keys()[i])] = made[i].interactable
	prompts["hotel_bed"] = _level.interactables.hotel_bed
	var ids := prompts.keys()
	for a in ids.size():
		for b in range(a + 1, ids.size()):
			var pa: Vector3 = prompts[ids[a]].global_position
			var pb: Vector3 = prompts[ids[b]].global_position
			var d := Vector2(pa.x - pb.x, pa.z - pb.z).length()
			if d < 2.5:
				_check(d >= 1.8, "%s: %s and %s prompts %.1f m apart" % [act, ids[a], ids[b], d])
	for id in ids:
		var it: Interactable = prompts[id]
		var f: Vector2 = Cairo.SPOTS.get(id, [Vector3.ZERO, Vector2(0, 1)])[1]
		var n := Vector3(f.x, 0, f.y) if f != Vector2.ZERO else (_level.player_spawn - it.global_position).normalized()
		n.y = 0.0
		var stand := it.global_position + n.normalized() * 1.0
		var got := Interactable.pick(get_tree(), stand, -n)
		_check(got == it, "%s: walking up to %s picks it (got %s)" % [act, id, got.id if got else "nothing"])
	var people: Array = plan.get("hosts", {}).values() if act == "act7" else \
		Cairo.NPC_POINTS.keys().filter(func(k): return not k in Cairo.LATER_PEOPLE)
	for who in people:
		var at: Vector3 = Cairo.NPC_POINTS[who][0]
		var nearest := INF
		for id in ids:
			var p: Vector3 = prompts[id].global_position
			nearest = minf(nearest, Vector2(p.x - at.x, p.z - at.z).length())
		_check(nearest >= 0.9, "%s: %s isn't standing on a prompt (%.1f m)" % [act, who, nearest])
		_check(not _blocked(space, at), "%s: %s has room to stand (not in a wall or doorway)" % [act, who])
	for s in made:
		s.free()  # now, not at the frame's end: the next act's audit must not see them


## Would a person (a 0.3 m capsule) at `p` overlap anything solid?
func _blocked(space: PhysicsDirectSpaceState3D, p: Vector3) -> bool:
	var q := PhysicsShapeQueryParameters3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.6
	q.shape = cap
	q.transform = Transform3D(Basis.IDENTITY, p + Vector3.UP * 0.95)
	q.collision_mask = 1
	return not space.intersect_shape(q, 1).is_empty()


## Is `p` inside a solid (anything on layer 1)?
func _inside(space: PhysicsDirectSpaceState3D, p: Vector3) -> bool:
	var q := PhysicsPointQueryParameters3D.new()
	q.position = p
	q.collision_mask = 1
	return not space.intersect_point(q, 1).is_empty()
