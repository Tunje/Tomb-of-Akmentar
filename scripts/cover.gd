class_name Cover
extends RefCounted
## Player cover, ported from Wreck Wreckers (net/player_cover.gd, Rook) without the net code:
##   FREE ──[E near a cover face, facing it ≤60°]──► IN_COVER (snaps to the face, crouched)
##   IN_COVER: A/D slides along the face; hold aim ──► POP_OUT (stand up and shoot)
##   IN_COVER/POP_OUT ──[W + E, low and thin piece, safe landing]──► VAULT (0.6 s arc) ──► FREE
##   IN_COVER/POP_OUT ──[E, S, Space, sprint, piece gone]──► FREE
## No blind fire: crouched in cover you can't shoot, as in Wreck Wreckers.
## Cover pieces are the level's StaticBody3D boxes in group "cover" with meta "cover_size"
## (x = length, y = height, z = depth; the body's origin is the box centre).

enum State { FREE, IN_COVER, POP_OUT, VAULT }

const ENTER_RANGE := 1.0          # m from the cover face to the player's centre
const ENTER_MAX_ANGLE := 60.0     # facing the face
const HOLD_DIST := 0.45           # where the player's centre sits in cover (capsule radius + gap)
const SLIDE_SPEED := 2.5
const SNAP_SPEED := ENTER_RANGE / 0.2   # the 0.2 s snap
const VAULT_TIME := 0.6
const VAULT_CLEARANCE := 0.15     # feet pass this far above the top
const MAX_VAULT_DEPTH := 0.8
const MAX_VAULT_HEIGHT := 1.3
const MIN_EDGE_LENGTH := 1.0

var state := State.FREE
var piece: StaticBody3D
var edge_id := -1
var _vault_t := 0.0
var _vault_from := Vector3.ZERO
var _vault_to := Vector3.ZERO
var _vault_lift := 0.0


func in_cover() -> bool:
	return state == State.IN_COVER or state == State.POP_OUT


func leave() -> void:
	state = State.FREE
	piece = null
	edge_id = -1


## One physics step. Returns the XZ velocity to use while in cover (Vector3), or null when the
## normal movement code should run. VAULT moves the body directly and returns Vector3.ZERO.
## `facing` is where the player looks (camera yaw), `input` is move input (x right, y back).
func step(body: CharacterBody3D, delta: float, input: Vector2, facing: Vector3, cover_pressed: bool,
		aim_held: bool, leave_now: bool) -> Variant:
	var entered := false
	match state:
		State.FREE:
			if cover_pressed:
				var hit := find_edge(body.get_tree().get_nodes_in_group("cover"), body.global_position, facing)
				if not hit.is_empty():
					piece = hit.piece
					edge_id = hit.edge.id
					state = State.IN_COVER
					entered = true  # this press took cover; it isn't also the "E again = leave" press
			if state == State.FREE:
				return null
		State.VAULT:
			return _vault_step(body, delta)
	var e := edge(piece, edge_id) if is_instance_valid(piece) else {}
	if e.is_empty() or leave_now or input.y > 0.5:
		leave()
		return null
	if cover_pressed and not entered:
		# W + E vaults when allowed and the landing is safe; otherwise E just leaves cover.
		if input.y < -0.5 and vaultable(piece):
			var land: Variant = vault_landing(body, e)
			if land != null:
				_start_vault(body, land)
				return Vector3.ZERO
		leave()
		return null
	state = State.POP_OUT if aim_held else State.IN_COVER
	# Slide along the face (A/D, camera-relative), held HOLD_DIST off it.
	var a: Vector3 = e.a
	var b: Vector3 = e.b
	var n: Vector3 = e.normal
	var t := (b - a).normalized()
	var length := (b - a).length()
	var pos := body.global_position
	var s := (pos - a).dot(t)
	if state == State.IN_COVER:
		var right := Vector3(-facing.z, 0, facing.x).normalized()
		var along := (right * input.x).dot(t)
		if absf(along) > 0.3:
			s += signf(along) * SLIDE_SPEED * delta
	s = clampf(s, minf(HOLD_DIST, length * 0.5), maxf(length - HOLD_DIST, length * 0.5))
	var target := a + t * s + n * HOLD_DIST
	var flat := Vector3(target.x - pos.x, 0, target.z - pos.z)
	var max_step := (SNAP_SPEED + SLIDE_SPEED) * delta
	if flat.length() > max_step:
		flat = flat.normalized() * max_step
	return flat / maxf(delta, 0.0001)


## The face the player is in cover at (or {}).
func current_edge() -> Dictionary:
	return edge(piece, edge_id) if in_cover() and is_instance_valid(piece) else {}


func _start_vault(body: CharacterBody3D, land: Vector3) -> void:
	state = State.VAULT
	_vault_t = 0.0
	_vault_from = body.global_position
	_vault_to = land
	_vault_lift = maxf(top_y(piece) - maxf(_vault_from.y, _vault_to.y), 0.0) + VAULT_CLEARANCE


func _vault_step(body: CharacterBody3D, delta: float) -> Variant:
	_vault_t = minf(_vault_t + delta / VAULT_TIME, 1.0)
	var p := _vault_from.lerp(_vault_to, _vault_t)
	p.y += sin(PI * _vault_t) * _vault_lift
	body.global_position = p
	body.velocity = Vector3.ZERO
	if _vault_t >= 1.0:
		leave()
	return Vector3.ZERO


# ---------------------------------------------------------------- pieces (boxes)

static func size_of(p: Node3D) -> Vector3:
	return p.get_meta("cover_size", Vector3.ZERO)


static func vaultable(p: Node3D) -> bool:
	var s := size_of(p)
	return s.z <= MAX_VAULT_DEPTH and s.y <= MAX_VAULT_HEIGHT


static func top_y(p: Node3D) -> float:
	return p.global_position.y + size_of(p).y * 0.5


## Faces at base height: [{id, a, b, normal}]. id 0 = +Z, 1 = -Z, 2 = +X, 3 = -X; short faces skipped.
static func edges(p: Node3D) -> Array:
	var size := size_of(p)
	var out: Array = []
	var hx := size.x * 0.5
	var hz := size.z * 0.5
	var y := -size.y * 0.5
	var faces := [
		[0, Vector3(-hx, y, hz), Vector3(hx, y, hz), Vector3(0, 0, 1), size.x],
		[1, Vector3(hx, y, -hz), Vector3(-hx, y, -hz), Vector3(0, 0, -1), size.x],
		[2, Vector3(hx, y, hz), Vector3(hx, y, -hz), Vector3(1, 0, 0), size.z],
		[3, Vector3(-hx, y, -hz), Vector3(-hx, y, hz), Vector3(-1, 0, 0), size.z],
	]
	var xf := p.global_transform
	for f: Array in faces:
		if f[4] < MIN_EDGE_LENGTH:
			continue
		out.append({"id": f[0], "a": xf * (f[1] as Vector3), "b": xf * (f[2] as Vector3),
			"normal": (xf.basis * (f[3] as Vector3)).normalized()})
	return out


static func edge(p: Node3D, id: int) -> Dictionary:
	for e: Dictionary in edges(p):
		if e.id == id:
			return e
	return {}


## The cover face a player at `feet` facing `facing` may take, or {} : {piece, edge, dist}.
static func find_edge(pieces: Array, feet: Vector3, facing: Vector3, range_m := ENTER_RANGE, max_angle := ENTER_MAX_ANGLE) -> Dictionary:
	var best := {}
	var fwd := Vector3(facing.x, 0, facing.z).normalized()
	for p in pieces:
		for e: Dictionary in edges(p):
			var d := _edge_distance(e, feet, range_m)
			if d < 0.0:
				continue
			if fwd.dot(-(e.normal as Vector3)) < cos(deg_to_rad(max_angle)):
				continue
			if best.is_empty() or d < best.dist:
				best = {"piece": p, "edge": e, "dist": d}
	return best


## Distance from the face to `feet` if the player is in front of it (outer side, along its
## length, same floor level), else -1.
static func _edge_distance(e: Dictionary, feet: Vector3, range_m: float) -> float:
	var a: Vector3 = e.a
	var b: Vector3 = e.b
	var n: Vector3 = e.normal
	var rel := Vector3(feet.x - a.x, 0, feet.z - a.z)
	var d := rel.dot(n)
	var s := rel.dot((b - a).normalized())
	if d <= 0.0 or d > range_m or s < -0.2 or s > (b - a).length() + 0.2 or absf(feet.y - a.y) > 0.6:
		return -1.0
	return d


## Where a vault over this face lands (feet), or null if there's no floor there or the capsule
## wouldn't fit (stands in for Wreck Wreckers' MovementValidator.safe_landing).
static func vault_landing(body: CharacterBody3D, e: Dictionary) -> Variant:
	var a: Vector3 = e.a
	var t := ((e.b as Vector3) - a).normalized()
	var n: Vector3 = e.normal
	var feet := body.global_position
	var on_edge := a + t * Vector3(feet.x - a.x, 0, feet.z - a.z).dot(t)
	var space := body.get_world_3d().direct_space_state
	# Depth: from the face through the box along -n.
	var ray := PhysicsRayQueryParameters3D.create(on_edge - n * 3.0 + Vector3.UP * 0.3, on_edge + Vector3.UP * 0.3, 1)
	var back: Dictionary = space.intersect_ray(ray)
	var depth := on_edge.distance_to(back.position - Vector3.UP * 0.3) if back else 0.6
	var land := on_edge - n * (depth + HOLD_DIST + 0.1)
	land.y = feet.y
	var down := space.intersect_ray(PhysicsRayQueryParameters3D.create(land + Vector3.UP * 0.5, land + Vector3.DOWN * 0.6, 1))
	if down.is_empty():
		return null
	land.y = (down.position as Vector3).y
	var shape := PhysicsShapeQueryParameters3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.7
	shape.shape = cap
	shape.transform = Transform3D(Basis.IDENTITY, land + Vector3.UP * 0.9)
	shape.collision_mask = 1 | 4
	shape.exclude = [body.get_rid()]
	if not space.intersect_shape(shape, 1).is_empty():
		return null
	return land
