class_name RiverBoat
extends AnimatableBody3D
## A 1920s Nile stern-wheel paddle steamer, 36 m (Simon: the 22 m one was "too small"), built from boxes until image-to-3d's cabin,
## funnel and wheelhouse arrive. One AnimatableBody3D (sync_to_physics) holds every solid part,
## so CharacterBody3D players and gunmen standing on it are carried by move_and_slide's platform
## support. It follows a Path3D along the river:
##   DOCKED ──[ring the bell (E) / sail() / sail_after]──► SAILING ──[end of the path]──► DOCKED
## Docked, a gangplank is down on the starboard side: E "Go ashore" on deck, "Board the riverboat"
## from the pier. Crates are cover (group "cover", meta "cover_size", like level.gd's _mark_cover).
## Anyone watched (watch()) who falls into the river is put back on deck: below the waterline with
## no floor under them (so a tomb or cellar below y = 0 doesn't count), and inside `water_rect`
## (world XZ) when that is set.
##   var boat := RiverBoat.make(self, path, "nile_steamer")
## Local frame: -Z is the bow, +X starboard, the origin on the waterline at midships.

signal sailed
signal docked
signal fell_overboard(body: Node3D)

enum State { DOCKED, SAILING }

const LENGTH := 36.0
const BEAM := 9.0
const DECK_Y := 1.2           # lower deck top, above the waterline (the pier's gangplank meets it)
const CABIN_H := 2.6
const UPPER_Y := 4.0          # upper deck top
const PASSAGE := 2.2          # the side passages round the cabin: room for the camera and a fight
const CABIN_L := 18.0
const CABIN_Z := 1.0          # the cabin's centre (a longer foredeck than afterdeck)
const UPPER_L := CABIN_L + 2.0
const RAIL_H := 1.0
const PLANK_Z := -2.5         # where the gangplank meets the starboard side
const CRUISE := 4.0           # m/s (~8 knots)
const ACCEL := 0.5            # m/s^2, both ways
const TURN_RATE := 0.6        # rad/s the heading follows the river at most
const WATER_Y := 0.0
const FALL_Y := -1.0          # below this (world) a watched body has fallen in
const BOB := 1.0              # scale of the gentle pitch / roll / heave

@export var boat_id := "steamer"
var path: Path3D
var state := State.DOCKED
var progress := 0.0           # metres along the path
var speed := 0.0
var cruise := CRUISE
var sail_after := -1.0        # >= 0: casts off by itself after this many seconds docked
var falls := 0
var deck_spawn := Vector3(0, DECK_Y + 0.05, -13.0)   # local: where fallen players come back
var water_rect := Rect2()     # world XZ of the river; empty = anywhere with no floor below

var _yaw := 0.0
var _t := 0.0
var _docked_t := 0.0
var _watched: Array[Node3D] = []
var _plank_shape: CollisionShape3D
var _plank_mesh: MeshInstance3D
var _gate_shape: CollisionShape3D
var _gate_mesh: MeshInstance3D
var _wheel: Node3D
var _mats := {}


static func make(parent: Node3D, river: Path3D, id := "steamer", start_at := 0.0) -> RiverBoat:
	var b := RiverBoat.new()
	b.boat_id = id
	b.name = "RiverBoat_" + id
	b.path = river
	b.progress = start_at
	parent.add_child(b)
	return b


func _ready() -> void:
	sync_to_physics = true
	collision_layer = 1   # world: walkable, blocks bullets and sight
	collision_mask = 0
	# Move after the people on board: their cover targets and spots then use the same deck position
	# that move_and_slide carries them from, so the deck's motion isn't counted twice.
	process_physics_priority = 10
	add_to_group("boats")
	if path and path.curve:
		smooth_curve(path.curve)
	_build()
	_place(0.0, true)
	_set_docked(true)


# ---------------------------------------------------------------- sailing

func sail() -> void:
	if state == State.SAILING:
		return
	state = State.SAILING
	_set_docked(false)
	sailed.emit()


func length_m() -> float:
	return path.curve.get_baked_length() if path and path.curve else 0.0


func _physics_process(delta: float) -> void:
	_t += delta
	if state == State.DOCKED:
		_docked_t += delta
		if sail_after >= 0.0 and _docked_t >= sail_after:
			sail()
	else:
		var left := length_m() - progress
		var stop_dist := speed * speed / (2.0 * ACCEL) + 0.5
		var want := 0.0 if left <= stop_dist else cruise
		speed = move_toward(speed, want, ACCEL * delta)
		progress = minf(progress + speed * delta, length_m())
		if left <= 0.05 or (want == 0.0 and speed <= 0.01):
			speed = 0.0
			state = State.DOCKED
			_docked_t = 0.0
			sail_after = -1.0
			_set_docked(true)
			docked.emit()
	_place(delta, false)
	_watch_falls()
	if _wheel:
		_wheel.rotate_x(-speed / 1.6 * delta)


## The transform on the path at `progress`, with the heading eased toward the river's.
func _place(delta: float, snap: bool) -> void:
	if path == null or path.curve == null:
		return
	var c := path.curve
	var p := path.global_transform * c.sample_baked(progress, true)
	var ahead := path.global_transform * c.sample_baked(minf(progress + 5.0, length_m()), true)
	var behind := path.global_transform * c.sample_baked(maxf(progress - 5.0, 0.0), true)
	var dir := ahead - behind
	var want := atan2(-dir.x, -dir.z) if Vector2(dir.x, dir.z).length() > 0.01 else _yaw
	var turn := angle_difference(_yaw, want)
	_yaw = want if snap else _yaw + clampf(turn, -TURN_RATE * delta, TURN_RATE * delta)
	var heel := clampf(turn, -0.3, 0.3) * 0.04 * (speed / CRUISE)  # leans a touch into turns
	var pitch := sin(_t * 0.9) * deg_to_rad(0.35) * BOB
	var roll := sin(_t * 0.67 + 1.0) * deg_to_rad(0.5) * BOB + heel
	var heave := sin(_t * 1.1) * 0.03 * BOB
	var b := Basis.from_euler(Vector3(pitch, _yaw, roll), EULER_ORDER_YXZ)
	global_transform = Transform3D(b, Vector3(p.x, WATER_Y + heave, p.z))


## Points without handles make a polyline with a corner at every point; the boat's velocity jumps
## there and anyone in cover jolts. Give such points smooth (Catmull-Rom) handles.
static func smooth_curve(c: Curve3D) -> void:
	var n := c.point_count
	for k in n:
		if c.get_point_in(k) != Vector3.ZERO or c.get_point_out(k) != Vector3.ZERO:
			continue
		var tan := (c.get_point_position(mini(k + 1, n - 1)) - c.get_point_position(maxi(k - 1, 0))) / 6.0
		c.set_point_in(k, -tan)
		c.set_point_out(k, tan)


## Is world point `p` on (or just above) this boat's decks?
func on_deck(p: Vector3) -> bool:
	var l := to_local(p)
	return absf(l.x) < BEAM * 0.5 + 0.2 and absf(l.z) < LENGTH * 0.5 + 0.3 and l.y > DECK_Y - 0.6 and l.y < UPPER_Y + 3.0


## The boat whose deck `p` is on, or null.
static func deck_under(tree: SceneTree, p: Vector3) -> RiverBoat:
	for b in tree.get_nodes_in_group("boats"):
		if (b as RiverBoat).on_deck(p):
			return b
	return null


# ---------------------------------------------------------------- people

## Has `body` fallen into the river? Below the waterline, over open water (no floor under it
## within 30 m), and inside water_rect if one is set.
func in_river(body: Node3D) -> bool:
	var p := body.global_position
	if p.y > FALL_Y:
		return false
	if water_rect.has_area() and not water_rect.has_point(Vector2(p.x, p.z)):
		return false
	var ex: Array[RID] = []
	if body is CollisionObject3D:
		ex.append((body as CollisionObject3D).get_rid())
	var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 0.5, p + Vector3.DOWN * 30.0, 1, ex)
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()


## Put `body` back on deck (at `spawn_local`, default deck_spawn) if it falls into the river.
func watch(body: Node3D) -> void:
	if not body in _watched:
		_watched.append(body)


func _watch_falls() -> void:
	for b in _watched:
		if not is_instance_valid(b) or not in_river(b):
			continue
		falls += 1
		print("BOAT %s fell overboard, back on deck" % b.name)
		if "cover" in b and b.cover is Cover:
			b.cover.leave()
		b.global_position = to_global(deck_spawn)
		if b is CharacterBody3D:
			(b as CharacterBody3D).velocity = Vector3.ZERO
		fell_overboard.emit(b)


func _set_docked(on: bool) -> void:
	Game.set_flag("boat_%s_docked" % boat_id, on)
	if _plank_shape:
		_plank_shape.disabled = not on
		_plank_mesh.visible = on
		_gate_shape.disabled = on
		_gate_mesh.visible = not on


func _board(by: Node) -> void:
	if by is Node3D:
		(by as Node3D).global_position = to_global(Vector3(BEAM * 0.5 - 1.1, DECK_Y + 0.05, PLANK_Z))
		if by is CharacterBody3D:
			(by as CharacterBody3D).velocity = Vector3.ZERO


func _ashore(by: Node) -> void:
	if not by is Node3D:
		return
	var at := to_global(Vector3(BEAM * 0.5 + 3.4, DECK_Y + 1.0, PLANK_Z))
	var hit := get_world_3d().direct_space_state.intersect_ray(
			PhysicsRayQueryParameters3D.create(at, at + Vector3.DOWN * 4.0, 1, [get_rid()]))
	(by as Node3D).global_position = hit.position if hit else at
	if by is CharacterBody3D:
		(by as CharacterBody3D).velocity = Vector3.ZERO


# ---------------------------------------------------------------- building

func _build() -> void:
	var hx := BEAM * 0.5
	var hz := LENGTH * 0.5
	# Hull: the deck is its top; a pointed bow and a raked stern are looks only.
	_part(Vector3(BEAM, DECK_Y + 0.5, LENGTH), Vector3(0, (DECK_Y - 0.5) * 0.5, 0), "hull")
	_part(Vector3(BEAM * 0.707, DECK_Y + 0.5, BEAM * 0.707), Vector3(0, (DECK_Y - 0.5) * 0.5, -hz), "hull", false, Vector3(0, PI * 0.25, 0))
	_part(Vector3(BEAM * 0.68, 0.06, BEAM * 0.68), Vector3(0, DECK_Y + 0.03, -hz), "deck", false, Vector3(0, PI * 0.25, 0))
	_part(Vector3(BEAM - 0.1, 0.06, LENGTH - 0.1), Vector3(0, DECK_Y + 0.03, 0), "deck", false)
	_part(Vector3(BEAM + 0.1, 0.12, LENGTH + 0.1), Vector3(0, DECK_Y - 0.1, 0), "trim", false)
	# Lower rails, with a gap (and a gate) where the gangplank goes.
	var rail := 0.08
	var gap_a := PLANK_Z - 0.75
	var gap_b := PLANK_Z + 0.75
	for side in [-1.0, 1.0]:
		if side > 0.0:
			_rail(Vector3(side * (hx - rail * 0.5), 0, (-hz + 0.4 + gap_a) * 0.5), gap_a - (-hz + 0.4), true)
			_rail(Vector3(side * (hx - rail * 0.5), 0, (gap_b + hz - 0.4) * 0.5), hz - 0.4 - gap_b, true)
		else:
			_rail(Vector3(side * (hx - rail * 0.5), 0, 0), LENGTH - 0.8, true)
	var gate := _part(Vector3(rail, RAIL_H, 1.5), Vector3(hx - rail * 0.5, DECK_Y + RAIL_H * 0.5, PLANK_Z), "rail")
	_gate_shape = gate[0]
	_gate_mesh = gate[1]
	_rail(Vector3(0, 0, -hz + 0.4), BEAM, false)
	_rail(Vector3(0, 0, hz - 0.4), BEAM, false)
	# Gangplank down to the pier (starboard), only while docked.
	var plank := _part(Vector3(3.2, 0.1, 1.1), Vector3(hx + 1.5, DECK_Y - 0.08, PLANK_Z), "deck")
	_plank_shape = plank[0]
	_plank_mesh = plank[1]
	# Cabin you walk round, its roof the upper deck (overhanging the side passages).
	var cw := BEAM - PASSAGE * 2.0
	var uw := BEAM - 0.6
	var up_bow := CABIN_Z - UPPER_L * 0.5
	var up_stern := CABIN_Z + UPPER_L * 0.5
	_part(Vector3(cw, CABIN_H, CABIN_L), Vector3(0, DECK_Y + CABIN_H * 0.5, CABIN_Z), "cabin")
	var n := int(CABIN_L / 2.4)
	for k in n:  # windows, looks only
		var z := CABIN_Z - CABIN_L * 0.5 + 1.4 + k * (CABIN_L - 2.8) / float(n - 1)
		for side in [-1.0, 1.0]:
			_part(Vector3(0.04, 0.8, 1.1), Vector3(side * (cw * 0.5 + 0.01), DECK_Y + 1.5, z), "window", false)
	_part(Vector3(uw, 0.15, UPPER_L), Vector3(0, UPPER_Y - 0.075, CABIN_Z), "roof")
	# Upper deck rails (a gap at the stern for the stairs).
	var rise := UPPER_Y - DECK_Y
	_rail(Vector3(-(uw * 0.5 - 0.05), rise, CABIN_Z), UPPER_L, true)
	_rail(Vector3(uw * 0.5 - 0.05, rise, CABIN_Z), UPPER_L, true)
	_rail(Vector3(0, rise, up_bow + 0.05), uw, false)
	var ramp_x := -1.6
	var gap_l := ramp_x - 0.65
	var gap_r := ramp_x + 0.65
	_rail(Vector3((-uw * 0.5 + gap_l) * 0.5, rise, up_stern - 0.05), gap_l + uw * 0.5, false)
	_rail(Vector3((gap_r + uw * 0.5) * 0.5, rise, up_stern - 0.05), uw * 0.5 - gap_r, false)
	# Stairs: a ramp for the feet (characters have no step-up), steps for the eye.
	var run := rise * 1.4
	var ang := atan2(rise, run)
	var ramp_len := sqrt(rise * rise + run * run)
	_part(Vector3(1.2, 0.12, ramp_len), Vector3(ramp_x, DECK_Y + rise * 0.5 - 0.06, up_stern + run * 0.5), "deck", true, Vector3(ang, 0, 0))
	for k in 14:
		var f := (k + 0.5) / 14.0
		_part(Vector3(1.2, 0.06, 0.3), Vector3(ramp_x, DECK_Y + rise * (1.0 - f) + 0.02, up_stern + run * f), "trim", false)
	for side in [-0.65, 0.65]:
		_part(Vector3(0.06, 0.9, ramp_len), Vector3(ramp_x + side, DECK_Y + rise * 0.5 + 0.45, up_stern + run * 0.5), "rail", false, Vector3(ang, 0, 0))
	# Wheelhouse (forward on the upper deck), funnel, paddle wheel.
	var wz := up_bow + 2.2
	_part(Vector3(3.2, 2.3, 2.8), Vector3(0, UPPER_Y + 1.15, wz), "cabin")
	_part(Vector3(3.6, 0.14, 3.2), Vector3(0, UPPER_Y + 2.37, wz), "roof", false)
	for side in [-1.0, 1.0]:
		_part(Vector3(0.04, 0.7, 2.0), Vector3(side * 1.61, UPPER_Y + 1.5, wz), "window", false)
	_part(Vector3(2.4, 0.7, 0.04), Vector3(0, UPPER_Y + 1.5, wz - 1.41), "window", false)
	_cylinder(0.6, 5.5, Vector3(0, UPPER_Y + 2.75, wz + 3.4), "funnel")
	_cylinder(0.66, 0.5, Vector3(0, UPPER_Y + 5.4, wz + 3.4), "funnel_top", false)
	_wheel = Node3D.new()
	_wheel.position = Vector3(0, 1.1, hz + 1.9)
	add_child(_wheel)
	for k in 10:
		var blade := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(BEAM - 0.8, 0.14, 2.0)
		blade.mesh = bm
		blade.material_override = _mat("wheel")
		blade.rotation.x = TAU * k / 10.0
		_wheel.add_child(blade)
	_part(Vector3(BEAM - 0.4, 0.22, 3.4), Vector3(0, 3.3, hz + 1.9), "roof", false)  # wheel housing roof
	# Cargo: cover crates (low ones you shoot over, tall stacks you lean round) on the foredeck, down
	# the side passages, on the afterdeck and up top.
	_crate(Vector3(-2.6, 0, -12.5), Vector3(1.6, 1.0, 1.1))   # foredeck, port
	_crate(Vector3(2.2, 0, -14.6), Vector3(1.1, 1.8, 1.1))    # foredeck, starboard (tall)
	_crate(Vector3(0.4, 0, -10.2), Vector3(1.2, 1.0, 1.0))    # foredeck, middle
	# The passage crates stand against the rail, 0.8 m across, leaving 1.25 m open by the cabin
	# (in the middle they cut the decks into islands nobody but the player could vault between).
	var rx := hx - 0.12 - 0.4
	_crate(Vector3(rx, 0, -6.0), Vector3(0.8, 1.0, 0.9))      # starboard passage
	_crate(Vector3(-rx, 0, 2.0), Vector3(0.8, 1.0, 0.9))      # port passage
	_crate(Vector3(rx, 0, 7.5), Vector3(0.8, 1.0, 0.9))       # starboard passage, aft
	_crate(Vector3(2.8, 0, 13.0), Vector3(1.2, 1.0, 1.0))     # afterdeck
	_crate(Vector3(-3.2, 0, 15.6), Vector3(1.1, 1.8, 1.0))    # afterdeck, port (tall)
	_crate(Vector3(2.0, rise, CABIN_Z + 3.0), Vector3(1.0, 1.0, 1.0))   # upper deck
	_crate(Vector3(-2.2, rise, CABIN_Z - 2.5), Vector3(1.2, 1.0, 1.0))  # upper deck
	# The bell (cast off) and the gangplank's two ends.
	_part(Vector3(0.3, 0.35, 0.3), Vector3(0.0, DECK_Y + 1.55, -hz + 2.6), "brass", false)
	_part(Vector3(0.06, 1.4, 0.06), Vector3(0.0, DECK_Y + 0.7, -hz + 2.6), "trim", false)
	_usable(Vector3(0, DECK_Y + 0.9, -hz + 3.0), "Ring the bell (cast off)", "bell", 1.0).used.connect(func(_by: Node) -> void: sail())
	_usable(Vector3(hx - 0.6, DECK_Y + 0.9, PLANK_Z), "Go ashore", "ashore", 0.9).used.connect(_ashore)
	_usable(Vector3(hx + 3.4, DECK_Y + 0.6, PLANK_Z), "Board the riverboat", "board", 1.2).used.connect(_board)


## An E prompt riding the boat at `local`, only while docked.
func _usable(local: Vector3, prompt: String, id: String, radius: float) -> Interactable:
	var it := Interactable.make(self, Vector3.ZERO, prompt, "boat_%s_%s" % [id, boat_id], radius)
	it.position = local
	it.when = {"flag": "boat_%s_docked" % boat_id}
	return it


## A rail along X (along=false) or Z, height RAIL_H on the deck at `at` (y = height above DECK_Y).
func _rail(at: Vector3, length: float, along_z: bool) -> void:
	var size := Vector3(0.08, RAIL_H, length) if along_z else Vector3(length, RAIL_H, 0.08)
	_part(size, Vector3(at.x, DECK_Y + at.y + RAIL_H * 0.5, at.z), "rail")
	var cap := Vector3(0.14, 0.06, length) if along_z else Vector3(length, 0.06, 0.14)
	_part(cap, Vector3(at.x, DECK_Y + at.y + RAIL_H, at.z), "trim", false)


## A crate: solid on the boat's body, plus a shape-less StaticBody3D marker in group "cover"
## (Cover and Gunman read its transform and meta), riding the boat as a child.
func _crate(base: Vector3, size: Vector3) -> void:
	var centre := Vector3(base.x, DECK_Y + base.y + size.y * 0.5, base.z)
	_part(size, centre, "crate")
	_part(size + Vector3(0.04, -size.y + 0.08, 0.04), centre + Vector3.UP * (size.y * 0.5 - 0.1), "trim", false)
	var marker := StaticBody3D.new()
	marker.name = "Cover"
	marker.collision_layer = 0
	marker.collision_mask = 0
	marker.position = centre
	marker.set_meta("cover_size", size)
	marker.set_meta("cover_min_edge", 0.8)  # the passage crates are 0.8 m: still cover
	marker.add_to_group("cover")
	add_child(marker)


## A box: mesh, and (when `solid`) a collision shape on the boat's body. Returns [shape, mesh].
func _part(size: Vector3, at: Vector3, mat: String, solid := true, rot := Vector3.ZERO) -> Array:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.rotation = rot
	mi.position = at
	mi.material_override = _mat(mat)
	add_child(mi)
	var cs: CollisionShape3D = null
	if solid:
		cs = CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		cs.shape = shape
		cs.position = at
		cs.rotation = rot
		add_child(cs)
	return [cs, mi]


func _cylinder(radius: float, height: float, at: Vector3, mat: String, solid := true) -> void:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = height
	mi.mesh = cm
	mi.position = at
	mi.material_override = _mat(mat)
	add_child(mi)
	if solid:
		var cs := CollisionShape3D.new()
		var shape := CylinderShape3D.new()
		shape.radius = radius
		shape.height = height
		cs.shape = shape
		cs.position = at
		add_child(cs)


func _mat(id: String) -> StandardMaterial3D:
	if _mats.has(id):
		return _mats[id]
	var colors := {
		"hull": Color(0.16, 0.14, 0.12), "deck": Color(0.52, 0.38, 0.22), "trim": Color(0.36, 0.25, 0.14),
		"rail": Color(0.82, 0.78, 0.68), "cabin": Color(0.86, 0.82, 0.72), "roof": Color(0.6, 0.55, 0.48),
		"window": Color(0.12, 0.14, 0.16), "funnel": Color(0.55, 0.16, 0.1), "funnel_top": Color(0.08, 0.08, 0.08),
		"wheel": Color(0.45, 0.14, 0.1), "crate": Color(0.6, 0.46, 0.28), "brass": Color(0.8, 0.62, 0.25),
	}
	var m := StandardMaterial3D.new()
	m.albedo_color = colors.get(id, Color.MAGENTA)
	m.roughness = 0.35 if id == "window" or id == "brass" else 0.85
	m.metallic = 0.6 if id == "brass" else 0.0
	_mats[id] = m
	return m
