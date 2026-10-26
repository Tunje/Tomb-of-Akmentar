extends Node3D
## DeckNav on the RiverBoat: bakes the deck navmesh and checks which parts of the decks join up
## (foredeck, both side passages, afterdeck, upper deck): a path between each pair, and whether a
## body (r 0.35) fits past the crates in the side passages. Then the boat sails and a gunman walks
## the foredeck to the afterdeck along it. Args after "--": --sail=no (stays docked).
## RESULT lines: polygons, each route reachable / how far off, the walk.

const POINTS := {
	"foredeck": Vector3(0.0, 0, -13.0),
	"port_fwd": Vector3(-3.4, 0, -4.0),
	"port_aft": Vector3(-3.4, 0, 6.0),
	"stbd_fwd": Vector3(3.4, 0, -2.0),
	"stbd_mid": Vector3(3.4, 0, 2.0),
	"afterdeck": Vector3(0.0, 0, 14.0),
	"upper": Vector3(0.0, 2.8, 4.0),
}

var boat: RiverBoat


func _ready() -> void:
	get_window().set_flag(Window.FLAG_NO_FOCUS, true)
	var args := TestDriver.parse_args()
	var path := Path3D.new()
	var c := Curve3D.new()
	for k in 30:
		c.add_point(Vector3(0, 0, -k * 20.0))
	path.curve = c
	add_child(path)
	boat = RiverBoat.make(self, path, "deck_test", 20.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var region := DeckNav.attach(boat)
	var map := get_world_3d().navigation_map
	var it := NavigationServer3D.map_get_iteration_id(map)
	for k in 120:  # the map syncs on its own schedule (async iterations): wait for the deck to be in it
		await get_tree().physics_frame
		if NavigationServer3D.map_get_iteration_id(map) > it + 1:
			break
	print("RESULT decknav polygons=%d map iteration %d -> %d" % [region.navigation_mesh.get_polygon_count(), it,
		NavigationServer3D.map_get_iteration_id(map)])
	var names := POINTS.keys()
	for i in names.size():
		for j in range(i + 1, names.size()):
			var a := _deck(POINTS[names[i]])
			var b := _deck(POINTS[names[j]])
			var p := NavigationServer3D.map_get_path(map, a, b, true)
			var off := p[p.size() - 1].distance_to(b) if p.size() > 0 else INF
			var start_off := p[0].distance_to(a) if p.size() > 0 else INF
			print("RESULT route %s -> %s reachable=%s (end %.1f m off, start %.1f m off, %d points)" % [names[i], names[j],
				off < 0.8 and start_off < 0.8, off, start_off, p.size()])
	# The crates in the side passages: does a body get past each, between it and the cabin wall
	# (x 2.3)? Probed at 2.75 (0.1 m off the wall: the boat rolls a little), upright in her frame.
	var space := get_world_3d().direct_space_state
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.75
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = cap
	q.collision_mask = 1
	for z in [-6.0, 2.0, 7.5]:
		var side := -1.0 if z == 2.0 else 1.0
		q.transform = Transform3D(boat.global_basis, _deck(Vector3(side * 2.75, 0.95, z)))
		print("RESULT passage crate at z=%.1f (%s): a body %s" % [z, "port" if side < 0.0 else "starboard",
			"gets past" if space.intersect_shape(q, 1).is_empty() else "is blocked"])
	if args.get("sail", "yes") == "yes":
		boat.sail()
	# A companion told to hold on the afterdeck walks there (his hold point rides the deck).
	var g := Gunman.new()
	g.team = Gunman.PARTY
	add_child(g)
	g.global_position = _deck(POINTS.foredeck) + Vector3.UP * 0.1
	await get_tree().physics_frame
	var goal_local := Vector3.ZERO
	goal_local = POINTS[args.get("to", "afterdeck")]
	g.order = "hold"
	g.hold_at = _deck(goal_local)
	var t := 0.0
	var best := INF
	while t < 30.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		var goal := _deck(goal_local)
		var d := Vector2(goal.x - g.global_position.x, goal.z - g.global_position.z).length()
		best = minf(best, d)
		if d < 1.0:
			break
	print("RESULT walk foredeck -> afterdeck sailing=%s arrived=%s t=%.1f closest=%.1f at=%s" % [boat.state == RiverBoat.State.SAILING,
		best < 1.0, t, best, boat.to_local(g.global_position).snapped(Vector3.ONE * 0.1)])
	get_tree().quit(0)


func _deck(local: Vector3) -> Vector3:
	return boat.to_global(local + Vector3(0, RiverBoat.DECK_Y + 0.1, 0))
