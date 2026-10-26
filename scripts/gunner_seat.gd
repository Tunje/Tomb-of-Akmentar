class_name GunnerSeat
extends Node
## The gunner seat: in a truck with a companion aboard, V (swap_seat) hands them the wheel and puts
## the player in their seat, standing in the bed with the gun out (Player.gunner_seat); V again
## swaps back. While the companion drives, this node steers them: along the road on maps that have
## one (CoastRoad, DesertRoute: look-ahead on the road line, slowing for bends, stopping at its
## end), elsewhere on along the heading the truck had when they took over.
##   GunnerSeat.swap(player)   # from Player, on swap_seat

const LOOK_AHEAD := 18.0      # m along the road to steer at
const BEND_LOOK := 30.0       # m ahead to judge the bend
const SLOWEST := 0.45         # of top speed, in the sharpest bend

var truck: Truck
var rider: Rider              # the companion at the wheel
var player: Node3D
var _heading := Vector3.FORWARD


## Swap the player between the wheel and a passenger seat. Returns what happened, for a toast
## ("" = nothing to do: not in a truck, or nobody aboard to take the wheel).
static func swap(p: Node3D) -> String:
	var t := p.get("vehicle") as Truck
	if t == null or t.health <= 0.0:
		return ""
	var seated: int = p.get("gunner_seat")
	if seated < 0:
		# Driving: find a companion aboard to take over.
		var r: Rider = null
		for n in p.get_tree().get_nodes_in_group("riders"):
			var c := n as Rider
			if c and c.mount_node == t and c.seat > 0 and c.body:
				r = c
				break
		if r == null:
			return ""
		var s := r.seat
		t.leave(p)
		r.move_to_seat(0)
		t.board(p, s)
		p.call("take_gunner_seat", s)
		var g := GunnerSeat.new()
		g.name = "GunnerSeat"
		g.truck = t
		g.rider = r
		g.player = p
		g._heading = -t.global_basis.z
		t.add_child(g)
		var id := _id_of(r)
		return "%s takes the wheel. You've got the gun." % (DayLog.person(id) if id != "" else "Your companion")
	# Gunner: back to the wheel; the companion goes back to the seat you had.
	var g: GunnerSeat = t.get_node_or_null("GunnerSeat")
	t.leave(p)
	if g and is_instance_valid(g.rider):
		g.rider.move_to_seat(seated)
	elif t.driver:
		return ""  # someone else at the wheel we didn't put there
	if g:
		g.queue_free()
	t.board(p, 0)
	p.call("take_wheel")
	return "You take the wheel."


## The companion id behind a Rider's name ("" for the drover).
static func _id_of(r: Rider) -> String:
	var glb := r._glb.get_file().get_basename()
	return glb if Characters.MODELS.has(glb) else ""


func _physics_process(_delta: float) -> void:
	if not is_instance_valid(truck) or not is_instance_valid(rider) or truck.health <= 0.0:
		queue_free()
		return
	if not is_instance_valid(player) or player.get("vehicle") != truck:
		rider.goal = Vector3.INF  # the gunner hopped off: pull up and wait for them
		queue_free()
		return
	var top: float = truck.spec.get("max_speed", 12.5)
	var at := truck.global_position
	var road := _road()
	if road.is_empty():
		# No road: keep on along the heading the truck had.
		rider.goal = at + _heading * 40.0
		rider.want_speed = top * 0.7
		return
	var point: Callable = road.point
	var dir: Callable = road.dir
	if at.z < float(road.end) + 6.0:
		rider.goal = Vector3.INF  # the end of the road: pull up
		return
	var ahead: Vector3 = point.call(at.z - LOOK_AHEAD)
	# Back onto the line if it's drifted off: aim at the road, not just along it.
	rider.goal = ahead
	var bend := (dir.call(at.z) as Vector3).angle_to(dir.call(at.z - BEND_LOOK))
	rider.want_speed = top * clampf(1.0 - bend * 2.0, SLOWEST, 1.0)


## The map's road, as {point(z), dir(z), end z}, if the level has one running north (-Z).
func _road() -> Dictionary:
	for n in get_tree().current_scene.get_children():
		if n is CoastRoad:
			return {"point": CoastRoad.road_point, "dir": CoastRoad.road_dir, "end": CoastRoad.FINISH_Z - 30.0}
		if n is DesertRoute:
			return {"point": DesertRoute.road_point, "dir": DesertRoute.road_dir, "end": DesertRoute.TOWN_Z}
	return {}
