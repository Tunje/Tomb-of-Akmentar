extends Node3D
## The Builders' Way (scripts/sites/builders_way.gd; the valley plan's hidden path), headless:
##   the trail: one clue isn't enough, any two of the three are (journal entry, flag), the seal's
##     clue doesn't count toward it;
##   the tomb (AkmentarBelow) with its doors open: a navmesh path from the stair's top (level 2,
##     behind the shrine) down to the forecourt, and into the Scarab Mother's shrine;
##   with them shut: the forecourt can't reach it (the secret stays one);
##   the shrine's seal: refused without the clue, forced on a second push (loud: forced signal and
##     flag), opened quietly with it;
##   the valley's cleft: no prompt until the trail is put together.

var _fails := 0


func _ready() -> void:
	Controls.setup()
	_trail()
	await _tomb(false)
	await _tomb(true)
	await _seal()
	await _cleft()
	print("RESULT builders_way_test %s fails=%d" % ["PASS" if _fails == 0 else "FAIL", _fails])
	get_tree().quit(0 if _fails == 0 else 1)


func _trail() -> void:
	Game.reset()
	Game.set_flag("clue_builders_seal")
	_check(not BuildersWay.check(), "trail: the seal's clue alone isn't the way")
	Game.set_flag("clue_builders_stair")
	_check(not BuildersWay.check() and not Game.flag(BuildersWay.FOUND), "trail: one of the three isn't enough")
	Game.set_flag("clue_builders_plan")
	_check(BuildersWay.check() and Game.flag(BuildersWay.FOUND) and Journal.has("builders_way"), "trail: two of three, the journal entry and the flag")
	_check(not BuildersWay.check(), "trail: written once")


## The tomb, its Builders' Way doors (and the shrine's) open or shut.
func _tomb(open: bool) -> void:
	Game.reset()
	if open:
		for id in ["secret_2_58_26", "secret_2_58_27", "secret_4_40_30", "secret_4_40_31", "secret_2_51_26", "secret_2_51_27"]:
			Game.set_flag("door_%s_open" % id)
	var map := get_world_3d().navigation_map
	var before := NavigationServer3D.map_get_iteration_id(map)
	var level := AkmentarBelow.new()
	add_child(level)
	var w := 0
	var top: Vector3 = level.points["builders_way"]
	# (A map that has synced since this tomb went in, not the last one's still: two iterations on.)
	while (NavigationServer3D.map_get_iteration_id(map) < before + 2 or NavigationServer3D.map_get_closest_point(map, top) == Vector3.ZERO) and w < 600:
		await get_tree().physics_frame
		w += 1
	var forecourt: Vector3 = level.points["forecourt"]
	var shrine := level.dcell(2, 25, 53)   # (a corner: its centre holds the shrine's marker)
	var down := _path(map, top, forecourt)
	var into := _path(map, top, shrine)
	var tag := "open" if open else "shut"
	if open:
		_check(down > 0.0, "tomb (%s): the stair's top to the forecourt, %.0f m" % [tag, down])
		_check(into > 0.0, "tomb (%s): the stair's top into the shrine, %.0f m" % [tag, into])
	else:
		_check(down < 0.0, "tomb (%s): the forecourt can't reach the stair (%s)" % [tag, "no path" if down < 0.0 else "%.0f m" % down])
	remove_child(level)
	level.free()
	for i in 4:
		await get_tree().physics_frame


## A path's length on the navmesh, or -1 if it doesn't get there (within 1 m).
func _path(map: RID, a: Vector3, b: Vector3) -> float:
	var from := NavigationServer3D.map_get_closest_point(map, a)
	var to := NavigationServer3D.map_get_closest_point(map, b)
	if from.distance_to(a) > 1.5 or to.distance_to(b) > 1.5:
		return -1.0
	var p := NavigationServer3D.map_get_path(map, from, to, true)
	if p.size() < 2 or p[-1].distance_to(to) > 1.0:
		return -1.0
	var len := 0.0
	for i in p.size() - 1:
		len += p[i].distance_to(p[i + 1])
	return len


func _seal() -> void:
	Game.reset()
	var d := ClueDoor.make(self, "test_seal", Vector3.ZERO, Vector3(2, 3, 0.4), "clue_builders_seal")
	d.can_force = true
	var heard := [false]
	d.forced.connect(func() -> void: heard[0] = true)
	await get_tree().process_frame
	_check(not d.try_open() and not d.is_open, "seal: refused without the clue")
	_check(d.try_open() and d.is_open and heard[0] and Game.flag("door_test_seal_forced"), "seal: forced on the second push (loud)")
	d.queue_free()
	Game.reset()
	Game.set_flag("clue_builders_seal")
	var q := ClueDoor.make(self, "test_seal2", Vector3.ZERO, Vector3(2, 3, 0.4), "clue_builders_seal")
	q.can_force = true
	await get_tree().process_frame
	_check(q.try_open() and not Game.flag("door_test_seal2_forced"), "seal: with the clue, quietly")
	q.queue_free()


func _cleft() -> void:
	Game.reset()
	var v := AkmentarValley.new()
	add_child(v)
	var cleft: Interactable = null
	for n in v.find_children("*", "", true, false):
		if n is Interactable and (n as Interactable).id == "builders_cleft":
			cleft = n
	_check(cleft != null and v.builders_cleft != Vector3.ZERO, "cleft: in the ravine at %s" % v.builders_cleft)
	if cleft:
		_check(not cleft.available(), "cleft: no prompt before the trail")
		Game.set_flag(BuildersWay.FOUND)
		_check(cleft.available(), "cleft: the prompt once the trail is put together")
	remove_child(v)
	v.free()


func _check(ok: bool, what: String) -> void:
	print("RESULT %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_fails += 1
