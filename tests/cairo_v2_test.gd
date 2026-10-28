extends Node3D
## Cairo v2 (gameplan/cairo_plan.md, stage 1), walked: it builds, every spot stands on the navmesh
## and can be walked to from the start, and how long each walk is (at 4 m/s). Prints a walk table
## and the longest walk; windowed, it also saves an overview and street views.
##   godot --headless --path . res://tests/cairo_v2_test.tscn -- --ci [--with-life]
##   godot --path . res://tests/cairo_v2_test.tscn -- --shot-dir=C:/path

const VIEWS := {
	"overview": [Vector3(120, 230, 330), Vector3(120, 0, 100)],
	"boulevard": [Vector3(60, 2.0, 62), Vector3(200, 4.0, 62)],
	"old_street": [Vector3(100, 2.0, 70), Vector3(100, 3.0, 200)],
	"mosque_square": [Vector3(108, 2.0, 158), Vector3(126, 10.0, 126)],
	"souk_lane": [Vector3(152, 2.0, 135), Vector3(205, 3.0, 135)],
	"corniche": [Vector3(218, 2.0, 8), Vector3(218, 2.0, 200)],
	"gate": [Vector3(100, 2.0, 182), Vector3(100, 10.0, 210)],
	"mosque_portal": [Vector3(147, 2.0, 129), Vector3(131, 6.0, 129)],
}

## Spots inside a room (-f9's interiors): checked like the rest now the rooms are built in v2.
const INDOORS: Array[String] = []

var _level: CairoV2
var _fails := 0
var _dir := "user://cairo_v2"


func _ready() -> void:
	get_window().set_flag(Window.FLAG_NO_FOCUS, true)
	_dir = str(TestDriver.parse_args().get("shot-dir", _dir))
	DirAccess.make_dir_recursive_absolute(_dir)
	CairoV2.with_life = TestDriver.parse_args().has("with-life")
	var t0 := Time.get_ticks_msec()
	_level = CairoV2.new()
	add_child(_level)
	print("RESULT build_ms %d" % (Time.get_ticks_msec() - t0))
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print("RESULT %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_fails += 1


func _run() -> void:
	for i in 4:
		await get_tree().physics_frame
	var map := get_world_3d().navigation_map
	# The map syncs on a worker thread, in real time: under --fixed-fps frames run far faster than that.
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 30000:
		if NavigationServer3D.map_get_closest_point(map, _level.player_spawn) != Vector3.ZERO:
			break
		await get_tree().physics_frame
	print("RESULT the map synced in %d ms" % (Time.get_ticks_msec() - t0))
	var from := NavigationServer3D.map_get_closest_point(map, _level.player_spawn)
	print("RESULT navmesh %d polygons, map regions %d, closest to the start %s" % [_level._nav.navigation_mesh.get_polygon_count(),
		NavigationServer3D.map_get_regions(map).size(), from])
	_check(from.distance_to(_level.player_spawn) < 0.6, "the start (%s) is on the navmesh" % _level.player_spawn)
	var longest := 0.0
	var longest_id := ""
	for id: String in _level.spots:
		var to: Vector3 = _level.spots[id]
		var near := NavigationServer3D.map_get_closest_point(map, to)
		var path := NavigationServer3D.map_get_path(map, from, near, true)
		var length := 0.0
		for k in range(1, path.size()):
			length += path[k].distance_to(path[k - 1])
		var reached := path.size() > 1 and path[path.size() - 1].distance_to(near) < 1.0
		var on := Vector2(near.x - to.x, near.z - to.z).length() < 1.5
		if id in INDOORS and not (on and reached):
			print("RESULT skip %-12s indoors: needs -f9's rooms in v2 (stage 1 has none)" % id)
			continue
		_check(on and reached, "%-12s at %s: %s, walk %.0f m (%.0f s)" % [id, to.snapped(Vector3.ONE * 0.1),
			"on the navmesh" if on else "OFF the navmesh (%.1f m)" % Vector2(near.x - to.x, near.z - to.z).length(),
			length, length / Player.WALK])
		if reached and length > longest:
			longest = length
			longest_id = id
	print("RESULT longest walk from the start: %s, %.0f m (%.0f s walking, %.0f s sprinting)" % [longest_id, longest,
		longest / Player.WALK, longest / Player.SPRINT])
	for pair: Array in [["hotel", "bazaar"], ["station", "docks"], ["road_gate", "museum"], ["docks", "road_gate"]]:
		var a := NavigationServer3D.map_get_closest_point(map, _level.spots[pair[0]])
		var b := NavigationServer3D.map_get_closest_point(map, _level.spots[pair[1]])
		var p := NavigationServer3D.map_get_path(map, a, b, true)
		var l := 0.0
		for k in range(1, p.size()):
			l += p[k].distance_to(p[k - 1])
		print("RESULT walk %s -> %s: %.0f m (%.0f s)" % [pair[0], pair[1], l, l / Player.WALK])
	if DisplayServer.get_name() != "headless":
		var cam := Camera3D.new()
		cam.far = 1200.0
		add_child(cam)
		cam.make_current()
		for name: String in VIEWS:
			var v: Array = VIEWS[name]
			cam.global_position = v[0]
			cam.look_at(v[1], Vector3.UP)
			for i in 3:
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(_dir.path_join("cairo_v2_%s.png" % name))
	print("RESULT cairo_v2_test %s (%d failed)" % ["PASS" if _fails == 0 else "FAIL", _fails])
	get_tree().quit(0 if _fails == 0 else 1)
