class_name Hop
extends RefCounted
## Climbing over something low in the way (collapsed rubble, a fallen block) for AI bodies that
## can't use the player's Cover vault: find() says where the far side is, step() flies the arc.
##   var hop := Hop.find(self, dir, 1.3)
##   if hop: _hop = hop            # then each physics frame: if _hop.step(self, delta): _hop = null

const MASK := 1

var from := Vector3.ZERO
var to := Vector3.ZERO
var lift := 0.0
var time := 0.7
var t := 0.0


## A Hop over the obstacle right ahead along `dir` if it's no taller than `max_h` (above the
## feet) and there's floor and room on the far side; else null.
static func find(body: CharacterBody3D, dir: Vector3, max_h: float, radius := 0.35, height := 1.75, seconds := 0.7) -> Hop:
	var d := Vector3(dir.x, 0, dir.z).normalized()
	if d.length() < 0.1:
		return null
	var space := body.get_world_3d().direct_space_state
	var feet := body.global_position
	var ex: Array[RID] = [body.get_rid()]
	var low := space.intersect_ray(_q(feet + Vector3.UP * 0.4, feet + Vector3.UP * 0.4 + d * (radius + 0.8), ex))
	if low.is_empty():
		return null
	var top_probe := feet + Vector3.UP * (max_h + 0.25)
	if not space.intersect_ray(_q(top_probe, top_probe + d * (radius + 1.4), ex)).is_empty():
		return null  # a wall, not rubble
	var face: Vector3 = low.position
	# How tall: down onto the top just past the face.
	var top := space.intersect_ray(_q(face + d * 0.15 + Vector3.UP * (max_h + 1.0), face + d * 0.15 + Vector3.DOWN * 0.2, ex))
	var top_y: float = (top.position as Vector3).y if top else feet.y + max_h
	if top_y - feet.y > max_h:
		return null
	# How deep: back from beyond onto the far face.
	var beyond := face + d * 3.0
	var back := space.intersect_ray(_q(beyond, face + d * 0.05, ex))
	var far_face: Vector3 = back.position if back else face + d * 0.8
	var land := far_face + d * (radius + 0.25)
	land.y = feet.y
	var down := space.intersect_ray(_q(land + Vector3.UP * 0.6, land + Vector3.DOWN * 0.8, ex))
	if down.is_empty():
		return null
	land.y = (down.position as Vector3).y
	var shape := PhysicsShapeQueryParameters3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = radius
	cap.height = height
	shape.shape = cap
	shape.transform = Transform3D(Basis.IDENTITY, land + Vector3.UP * (height * 0.5 + 0.05))
	shape.collision_mask = MASK
	shape.exclude = ex
	if not space.intersect_shape(shape, 1).is_empty():
		return null
	var h := Hop.new()
	h.from = feet
	h.to = land
	h.lift = maxf(top_y - maxf(feet.y, land.y), 0.0) + 0.2
	h.time = seconds
	return h


## Moves `body` along the arc; true when it has landed.
func step(body: CharacterBody3D, delta: float) -> bool:
	t = minf(t + delta / time, 1.0)
	var p := from.lerp(to, t)
	p.y += sin(PI * t) * lift
	body.global_position = p
	body.velocity = Vector3.ZERO
	return t >= 1.0


static func _q(a: Vector3, b: Vector3, ex: Array[RID]) -> PhysicsRayQueryParameters3D:
	return PhysicsRayQueryParameters3D.create(a, b, MASK, ex)
