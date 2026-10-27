extends Node
## Resume sweep: for one place in SaveRoute.SCENES (--place=<id>), writes a test-slot save as the
## act would have left it, loads it the way Continue does (Game.load_game, SaveRoute.scene_for),
## changes to that scene, and after 3 s of play checks: the player exists, is alive and has ground
## under them (not falling; tombs sit lower, so no fixed height), the act hasn't already ended (act9_end: that one
## opens the album), and every companion stands clear of walls. Prints
## "RESULT resume <place> ok|FAIL <why>" and exits 0 / 1. One place per run (a shell loop runs
## them all, one Godot at a time):
##   for p in $(godot --headless --path . res://tests/resume_test.tscn -- --list | grep ^PLACE | cut -d' ' -f2); do
##     godot --headless --path . res://tests/resume_test.tscn -- --place=$p; done

const WAIT := 3.0
const PARTY := ["mahmoud", "eleanor"]
## What the act had set by each place (the minimum it checks on resume).
const FLAGS := {
	"act6_keepers": {"act6_started": true, "keeper_horses": 2, "thieves_americans": true},
	"act6_end": {"act6_started": true, "act6_done": true, "thieves_americans": true, "return_route": "coast"},
	"act7_hotel_bed": {"act7_started": true, "thieves_americans": true},
	"act7_recovered": {"act7_started": true, "thieves_americans": true, "artifacts_recovered": true,
		"act7_done": true, "new_objective": "return_artifacts"},
	"act7_end": {"act7_started": true, "artifacts_recovered": true, "act7_done": true, "new_objective": "return_artifacts"},
	"act8_back": {"act8_back_from": "boat_battle", "route_act8_route": "river", "artifacts_recovered": true},
	"act8_end": {"act8_choice": "descend", "artifacts_recovered": true},
	"act9_start": {"act8_choice": "descend"},
	"act9_end": {"act8_choice": "descend", "barrier_restored": true},
}
const COUNTDOWNS := {
	"act6_keepers": {"thieves": 7, "mummy": 9}, "act6_end": {"thieves": 1, "mummy": 3},
	"act7_hotel_bed": {"thieves": 4, "mummy": 6}, "act7_recovered": {"thieves": 3, "mummy": 5},
	"act7_end": {"thieves": 3, "mummy": 5},
}


func _ready() -> void:
	get_window().set_flag(Window.FLAG_NO_FOCUS, true)
	var args := TestDriver.parse_args()
	if args.has("list"):
		for p in SaveRoute.SCENES:
			print("PLACE %s" % p)
		get_tree().quit(0)
		return
	var place := str(args.get("place", ""))
	if not SaveRoute.SCENES.has(place):
		print("RESULT resume %s FAIL not in SaveRoute.SCENES" % place)
		get_tree().quit(1)
		return
	# The save the act would have made at `place` (always the test slot: there are args).
	Game.reset()
	Game.place = place
	Game.act = int(place.substr(3, 1))
	Game.money = 200
	for id in PARTY:
		Game.companion(id)["recruited"] = true
	for f in FLAGS.get(place, {}):
		Game.set_flag(f, FLAGS[place][f])
	for c in COUNTDOWNS.get(place, {}):
		Game.countdowns[c] = COUNTDOWNS[place][c]
	if not Game.save_game():
		print("RESULT resume %s FAIL couldn't write the test save" % place)
		get_tree().quit(1)
		return
	# Continue's way in.
	Game.reset()
	if not Game.load_game():
		print("RESULT resume %s FAIL couldn't load the test save" % place)
		get_tree().quit(1)
		return
	var scene := SaveRoute.scene_for(Game.place)
	var checker := Checker.new()
	checker.place = place
	checker.scene = scene
	get_tree().root.add_child.call_deferred(checker)  # outlives the scene change
	get_tree().change_scene_to_file.call_deferred(scene)


class Checker extends Node:
	var place := ""
	var scene := ""

	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS
		_check.call_deferred()

	func _check() -> void:
		await get_tree().create_timer(WAIT - 1.0, true, false, true).timeout
		var p := _player()
		var y1 := p.global_position.y if p else 0.0
		await get_tree().create_timer(1.0, true, false, true).timeout
		var why := _why(p, y1)
		print("RESULT resume %s %s" % [place, "ok" if why == "" else "FAIL " + why])
		get_tree().quit(0 if why == "" else 1)

	func _why(p: Player, y1: float) -> String:
		var cs := get_tree().current_scene
		if cs == null or cs.scene_file_path != scene:
			return "wrong scene (%s, wanted %s)" % [cs.scene_file_path if cs else "none", scene]
		if p == null or not is_instance_valid(p):
			return "no player"
		if not p.alive:
			return "the player is dead"
		var y := p.global_position.y
		var space0 := p.get_world_3d().direct_space_state
		var down := PhysicsRayQueryParameters3D.create(p.global_position + Vector3.UP * 0.5, p.global_position + Vector3.DOWN * 2.5, 1, [p.get_rid()])
		if y < -40.0 or (p.vehicle == null and space0.intersect_ray(down).is_empty()):
			return "the player fell through (y %.1f, no ground under the player)" % y  # (tombs are lower: Act 5's floor is y -6)
		if p.vehicle == null and p.is_physics_processing() and y1 - y > 1.0:
			return "the player is falling (%.1f m in 1 s, at %s)" % [y1 - y, p.global_position.snapped(Vector3.ONE * 0.1)]
		for prop in ["_done", "_over"]:
			if prop in cs and bool(cs.get(prop)) and place != "act9_end":
				return "the act is already over (%s)" % prop
		var space := p.get_world_3d().direct_space_state
		for n in get_tree().get_nodes_in_group("party"):
			var g := n as Node3D
			if g == null or not g.is_visible_in_tree():
				continue
			var q := PhysicsShapeQueryParameters3D.new()
			var cap := CapsuleShape3D.new()
			cap.radius = 0.28
			cap.height = 1.5
			q.shape = cap
			q.transform = Transform3D(Basis.IDENTITY, g.global_position + Vector3.UP * 0.95)
			q.collision_mask = 1
			q.exclude = [(g as CollisionObject3D).get_rid()] if g is CollisionObject3D else []
			if not space.intersect_shape(q, 1).is_empty():
				return "%s stands in a wall at %s" % [g.name, g.global_position.snapped(Vector3.ONE * 0.1)]
		return ""

	func _player() -> Player:
		var cs := get_tree().current_scene
		if cs == null:
			return null
		for n in cs.find_children("*", "", true, false):
			if n is Player:
				return n
		return null
