class_name Monastery
extends Node3D
## Act 6's night stop (gameplan/act6_camp_options.md, option A, Simon's pick): a ruined Coptic
## monastery on the track where the desert and the coast returns part. One piece a map puts down
## (like DesertCamp); MonasteryNight is the stop itself. Its own frame: x east, z south (+z the gate
## and the track), the courtyard fire at the origin.
## - The enclosure: mud-brick walls 5 m high round a 60 x 48 m courtyard; the gate (south) under its
##   gatehouse, a breach in the north wall, and a breach in the east wall onto the monks' cemetery.
## - The keep (the qasr, the monks' refuge) in the north-east, its roof 5 m up behind a parapet, a
##   ramp up its west side: the lookout (CampJobs' crest) and the last stand.
## - The church (west, domed), the cells along the north wall, the refectory (south-west): solid
##   for now (their doors are dressing).
## - The well and its wheel by the fire; the picket line and the truck's place inside the gate.
## - The cemetery outside the east wall: graves, two tomb-houses, crosses. In the fight its graves
##   give up their dead: `spots.graves`.
## The servants' ways in (`spots.ways`): from out of the dark at the gate, the north breach and the
## east breach, and from the graves (act6.gd's spawn points instead of a ring round the fire);
## `spots.mouths`: one just outside each gap, close but unseen.
##   var m := Monastery.build(level, at, yaw)     # before the level bakes its navmesh
##   CampJobs.assign(level, companions, "act6_stop", true, {"anchor": m.anchor})
## The solids go into the level's _nav; the dressing stays under this node. Flat ground at `at.y`.
## Placeholders (blockout, models briefed in gameplan/act6_monastery_briefs.md): every building,
## the walls and breaches' rubble, the well's wheel, the graves, crosses and tomb-houses.

const INNER := Rect2(-30, -24, 60, 48)    # the courtyard, inside the walls
const WALL_H := 5.0
const WALL_T := 1.2
const GATE := Vector2(-2.5, 2.5)          # x span of the gate in the south wall
const BREACH_N := Vector2(8.0, 13.0)      # x span of the north breach
const BREACH_E := Vector2(-11.0, -5.0)    # z span of the east breach
const KEEP := Rect2(15, -12, 8, 8)        # its footprint; the roof at WALL_H
const RAMP_X := Vector2(12.5, 14.5)       # the ramp up the keep's west side (south to north)
const RAMP_Z := Vector2(6.0, -4.0)
const CHURCH := Rect2(-26, -16, 10, 12)
const CELLS := Rect2(-28.8, -22.8, 30, 4)
const REFECTORY := Rect2(-28.8, 10, 12, 8)
const WELL := Vector3(-6.0, 0, -3.0)
const PICKET := [Vector3(12.0, 0, 12.0), Vector3(12.0, 0, 20.0)]
const TRUCK := Vector3(-11.0, 0, 17.0)
const CEMETERY := Rect2(34, -22, 24, 36)

var level: Level
var anchor := Vector3.ZERO
var yaw := 0.0
## Where things are, in the world: fire, well, keep_roof, gate (inside), gate_out (on the track
## outside, the way in), truck, church_door, refectory_door; lists: beds, picket, graves; ways:
## {gate, north, east} -> [points out in the dark beyond each way in].
var spots := {}
var _xf := Transform3D.IDENTITY
var _brick: StandardMaterial3D
var _stone: StandardMaterial3D
var _dark: StandardMaterial3D
var _wood: StandardMaterial3D


static func build(lvl: Level, at: Vector3, facing := 0.0) -> Monastery:
	var m := Monastery.new()
	m.name = "Monastery"
	m.level = lvl
	m.yaw = facing
	m._xf = Transform3D(Basis(Vector3.UP, facing), at)
	lvl.add_child(m)
	m._materials()
	m._walls()
	m._gatehouse()
	m._keep()
	m._church()
	m._cells_and_refectory()
	m._well()
	m._fire()
	m._picket_and_loads()
	m._cemetery()
	m._ways()
	return m


func _w(p: Vector3) -> Vector3:
	return _xf * p


func _materials() -> void:
	_brick = level._stone.duplicate() as StandardMaterial3D
	_brick.albedo_texture = level._noise_tex(Color(0.55, 0.45, 0.34), Color(0.74, 0.64, 0.5), 0.05, false)
	_stone = level._stone.duplicate() as StandardMaterial3D
	_stone.albedo_texture = level._noise_tex(Color(0.5, 0.46, 0.4), Color(0.7, 0.66, 0.58), 0.06, false)
	_dark = StandardMaterial3D.new()
	_dark.albedo_color = Color(0.06, 0.05, 0.05)
	_dark.roughness = 1.0
	_wood = StandardMaterial3D.new()
	_wood.albedo_color = Color(0.36, 0.26, 0.18)


## A solid in the monastery's frame: into the level's _nav, turned with it (and `tilt` about x).
func _solid(p: Vector3, size: Vector3, mat: Material, turn := 0.0, tilt := 0.0) -> StaticBody3D:
	var b := level._box(level._nav, _w(p), size, mat)
	b.rotation = Vector3(tilt, yaw + turn, 0)
	return b


## A mesh only (dressing nothing walks into).
func _mesh(m: Mesh, p: Vector3, mat: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = mat
	add_child(mi)
	mi.global_position = _w(p)
	mi.rotation = rot + Vector3(0, yaw, 0)
	return mi


## A wall run from a to b (in x or in z), WALL_T thick, `h` high.
func _wall(a: Vector2, b: Vector2, h := WALL_H, mat: Material = null) -> void:
	var mid := (a + b) * 0.5
	var size := Vector3(absf(b.x - a.x) + WALL_T, h, absf(b.y - a.y) + WALL_T)
	if absf(b.x - a.x) < 0.01:
		size.x = WALL_T
	if absf(b.y - a.y) < 0.01:
		size.z = WALL_T
	_solid(Vector3(mid.x, h * 0.5, mid.y), size, mat if mat else _brick)


## The enclosure: four walls, the gate's gap south, the breaches north and east (their fallen brick
## heaped either side of the gap, low enough to see over, high enough to crouch behind).
func _walls() -> void:
	var r := INNER
	var n := r.position.y - WALL_T * 0.5
	var s := r.end.y + WALL_T * 0.5
	var w := r.position.x - WALL_T * 0.5
	var e := r.end.x + WALL_T * 0.5
	_wall(Vector2(w, n), Vector2(BREACH_N.x - 2.0, n))
	_wall(Vector2(BREACH_N.y + 2.0, n), Vector2(e, n))
	_wall(Vector2(w, s), Vector2(GATE.x - 1.5, s))
	_wall(Vector2(GATE.y + 1.5, s), Vector2(e, s))
	_wall(Vector2(w, n), Vector2(w, s))
	_wall(Vector2(e, n), Vector2(e, BREACH_E.x - 2.0))
	_wall(Vector2(e, BREACH_E.y + 2.0), Vector2(e, s))
	# The breaches: the wall's stumps either side, broken lower, and the rubble.
	for x: float in [BREACH_N.x - 1.0, BREACH_N.y + 1.0]:
		_solid(Vector3(x, 1.4, n), Vector3(2.0, 2.8, WALL_T + 0.2), _brick)
	for z: float in [BREACH_E.x - 1.0, BREACH_E.y + 1.0]:
		_solid(Vector3(e, 1.4, z), Vector3(WALL_T + 0.2, 2.8, 2.0), _brick)
	for p: Array in [[Vector3(BREACH_N.x + 0.6, 0.45, n - 2.0), 1.4], [Vector3(BREACH_N.y - 0.5, 0.4, n + 1.8), 1.2],
			[Vector3(e + 2.0, 0.45, BREACH_E.x + 0.6), 1.4], [Vector3(e - 1.9, 0.4, BREACH_E.y - 0.5), 1.1]]:
		var sz := Vector3(p[1], float(p[1]) * 0.65, float(p[1]) * 0.9)
		level._mark_cover(_solid(p[0], sz, _brick, float(p[1])), sz)
	spots.breach_north = _w(Vector3((BREACH_N.x + BREACH_N.y) * 0.5, 0, n))
	spots.breach_east = _w(Vector3(e, 0, (BREACH_E.x + BREACH_E.y) * 0.5))


## The gatehouse over the gate: two piers, the lintel, its dark arch, a lantern inside.
func _gatehouse() -> void:
	var s := INNER.end.y + WALL_T * 0.5
	for x: float in [GATE.x - 1.0, GATE.y + 1.0]:
		_solid(Vector3(x, 3.25, s), Vector3(2.0, 6.5, 3.0), _brick)
	_solid(Vector3(0, 5.75, s), Vector3(GATE.y - GATE.x, 1.5, 3.0), _brick)
	spots.gate = _w(Vector3(0, 0, s - 3.0))
	spots.gate_out = _w(Vector3(0, 0, s + 14.0))
	_lantern(Vector3(GATE.y + 0.4, 2.6, s - 1.8))


## The keep: a tower in the north-east, its roof 5 m up behind a parapet, the ramp up its west side
## onto a landing at its south-west corner.
func _keep() -> void:
	var k := KEEP
	var c := Vector3(k.get_center().x, 0, k.get_center().y)
	_solid(c + Vector3(0, WALL_H * 0.5, 0), Vector3(k.size.x, WALL_H, k.size.y), _brick)
	var top := WALL_H
	# The parapet, but where the landing comes in (the west edge's southern end).
	_solid(Vector3(c.x, top + 0.45, k.position.y + 0.2), Vector3(k.size.x, 0.9, 0.4), _brick)
	_solid(Vector3(c.x, top + 0.45, k.end.y - 0.2), Vector3(k.size.x, 0.9, 0.4), _brick)
	_solid(Vector3(k.end.x - 0.2, top + 0.45, c.z), Vector3(0.4, 0.9, k.size.y), _brick)
	_solid(Vector3(k.position.x + 0.2, top + 0.45, k.position.y + (k.size.y - 2.4) * 0.5), Vector3(0.4, 0.9, k.size.y - 2.4), _brick)
	# The ramp (rising north) and its landing.
	var run := RAMP_Z.x - RAMP_Z.y
	var tilt := atan2(top, run)
	var length := Vector2(run, top).length()
	var rx := (RAMP_X.x + RAMP_X.y) * 0.5
	_solid(Vector3(rx, top * 0.5 - 0.2, (RAMP_Z.x + RAMP_Z.y) * 0.5), Vector3(RAMP_X.y - RAMP_X.x, 0.4, length), _brick, 0.0, tilt)
	_solid(Vector3((RAMP_X.x + k.position.x) * 0.5, top - 0.2, RAMP_Z.y - 1.2), Vector3(k.position.x - RAMP_X.x, 0.4, 2.4), _brick)
	spots.keep_roof = _w(c + Vector3(0, top, 0))
	spots.keep_foot = _w(Vector3(rx, 0, RAMP_Z.x + 1.5))
	_lantern(Vector3(c.x - 2.5, top + 0.1, c.z + 2.5))


## The church on the west: its walls, a dome, the dark doorway in its east face (facing the fire).
func _church() -> void:
	var r := CHURCH
	var c := Vector3(r.get_center().x, 0, r.get_center().y)
	_solid(c + Vector3(0, 2.4, 0), Vector3(r.size.x, 4.8, r.size.y), _brick)
	var dome := SphereMesh.new()
	dome.radius = 3.6
	dome.height = 3.6
	dome.is_hemisphere = true
	_mesh(dome, c + Vector3(0, 4.8, 0), _brick)
	var door := BoxMesh.new()
	door.size = Vector3(0.06, 2.6, 1.6)
	_mesh(door, Vector3(r.end.x + 0.03, 1.3, c.z), _dark)
	spots.church_door = _w(Vector3(r.end.x + 1.2, 0, c.z))
	_lantern(Vector3(r.end.x + 0.5, 1.8, c.z + 1.5))


## The cells along the north wall (a low range, a dark door every 3 m) and the refectory south-west.
func _cells_and_refectory() -> void:
	var r := CELLS
	_solid(Vector3(r.get_center().x, 1.6, r.get_center().y), Vector3(r.size.x, 3.2, r.size.y), _brick)
	var door := BoxMesh.new()
	door.size = Vector3(1.0, 1.9, 0.06)
	for k in int(r.size.x / 3.0):
		_mesh(door, Vector3(r.position.x + 1.5 + k * 3.0, 0.95, r.end.y + 0.03), _dark)
	_lantern(Vector3(-12.0, 2.2, r.end.y + 0.4))
	var f := REFECTORY
	_solid(Vector3(f.get_center().x, 2.0, f.get_center().y), Vector3(f.size.x, 4.0, f.size.y), _brick)
	var d2 := BoxMesh.new()
	d2.size = Vector3(1.6, 2.4, 0.06)
	_mesh(d2, Vector3(f.get_center().x + 2.0, 1.2, f.position.y - 0.03), _dark)
	spots.refectory_door = _w(Vector3(f.get_center().x + 2.0, 0, f.position.y - 1.2))


## The well: a stone ring, waist-high, and its wheel's frame (the saqiya) over it.
func _well() -> void:
	var c := WELL
	for k in 8:
		var a := TAU * k / 8.0
		_solid(c + Vector3(cos(a) * 1.3, 0.4, sin(a) * 1.3), Vector3(0.6, 0.8, 1.05), _stone, -a)
	var water := CylinderMesh.new()
	water.top_radius = 1.05
	water.bottom_radius = 1.05
	water.height = 0.05
	_mesh(water, c + Vector3(0, 0.3, 0), _dark)
	for x: float in [-1.5, 1.5]:
		_solid(c + Vector3(x, 1.4, 0), Vector3(0.22, 2.8, 0.22), _wood)
	var beam := BoxMesh.new()
	beam.size = Vector3(3.4, 0.22, 0.22)
	_mesh(beam, c + Vector3(0, 2.75, 0), _wood)
	var wheel := CylinderMesh.new()
	wheel.top_radius = 1.0
	wheel.bottom_radius = 1.0
	wheel.height = 0.18
	_mesh(wheel, c + Vector3(0, 1.9, 0), _wood, Vector3(0, 0, PI * 0.5))
	spots.well = _w(c + Vector3(0, 0, 2.2))
	Palms.add(self, _w(c + Vector3(-3.5, 0, -2.5)), 7.0, level._nav)
	Palms.add(self, _w(c + Vector3(-4.6, 0, 1.4)), 6.0, level._nav)


## The fire in the courtyard: the middle CampJobs rings round; bedrolls round it.
func _fire() -> void:
	anchor = _w(Vector3.ZERO)
	level._prop(self, "prop_campfire.glb", anchor)
	var f := Node3D.new()
	f.name = "Fire"
	add_child(f)
	f.global_position = anchor
	level._flame(f, Vector3.UP * 0.45, 2.6, 13.0, true)
	spots.fire = anchor
	var beds: Array[Vector3] = []
	for k in 6:
		var a := PI * 0.15 + k * 0.42
		var p := Vector3(cos(a), 0, sin(a)) * 7.6
		level._prop(self, "prop_bedroll.glb", _w(p), yaw + a)
		beds.append(_w(p))
	spots.beds = beds


## The picket line inside the gate, east (the horses); the truck's place west; loads by the gate.
func _picket_and_loads() -> void:
	var a: Vector3 = PICKET[0]
	var b: Vector3 = PICKET[1]
	for p: Vector3 in [a, b]:
		var post := level._cylinder(level._nav, _w(p + Vector3(0, 0.7, 0)), 0.09, 1.4)
		(post.get_child(1) as MeshInstance3D).material_override = _wood
	var rope := BoxMesh.new()
	rope.size = Vector3(0.03, 0.03, a.distance_to(b))
	_mesh(rope, (a + b) * 0.5 + Vector3(0, 1.25, 0), _wood)
	var ties: Array[Vector3] = []
	for k in 4:
		ties.append(_w(a.lerp(b, (k + 0.5) / 4.0) + Vector3(1.0, 0, 0)))
	spots.picket = ties
	spots.truck = _w(TRUCK)
	for c: Array in [[Vector3(-6.0, 0.4, 19.5), Vector3(2.0, 0.8, 1.0)], [Vector3(6.5, 0.4, 19.0), Vector3(1.0, 0.8, 1.0)]]:
		var box := _solid(c[0], c[1], _stone)
		level._dress(box, "prop_crate_large.glb", Vector3(1.0, 0.8, 1.0))
		level._mark_cover(box, c[1])


## The monks' cemetery outside the east wall: a low wall round it (open to the breach), rows of
## graves with crosses, two tomb-houses. Each grave is a place the dead can rise from.
func _cemetery() -> void:
	var r := CEMETERY
	var low := 0.8
	_wall(Vector2(r.position.x, r.position.y), Vector2(r.end.x, r.position.y), low, _stone)
	_wall(Vector2(r.position.x, r.end.y), Vector2(r.end.x, r.end.y), low, _stone)
	_wall(Vector2(r.end.x, r.position.y), Vector2(r.end.x, r.end.y), low, _stone)
	_wall(Vector2(r.position.x, r.position.y), Vector2(r.position.x, BREACH_E.x - 2.0), low, _stone)
	_wall(Vector2(r.position.x, BREACH_E.y + 2.0), Vector2(r.position.x, r.end.y), low, _stone)
	var graves: Array[Vector3] = []
	var mound := BoxMesh.new()
	mound.size = Vector3(0.9, 0.25, 2.0)
	var upright := BoxMesh.new()
	upright.size = Vector3(0.12, 1.1, 0.12)
	var arm := BoxMesh.new()
	arm.size = Vector3(0.6, 0.12, 0.12)
	for row in 4:
		for k in 6:
			if (row * 6 + k) % 5 == 3:
				continue  # (a gap: the rows aren't perfect)
			var p := Vector3(r.position.x + 4.0 + k * 3.4, 0, r.position.y + 5.0 + row * 7.5)
			_mesh(mound, p + Vector3(0, 0.12, 0), _stone)
			var lean := 0.12 * sin(float(row * 7 + k))
			_mesh(upright, p + Vector3(0, 0.55, -1.15), _stone, Vector3(lean, 0, 0))
			_mesh(arm, p + Vector3(0, 0.78, -1.15), _stone, Vector3(lean, 0, 0))
			graves.append(_w(p + Vector3(1.3, 0, 0)))  # (beside the mound: where one stands up)
	spots.graves = graves
	for t: Vector3 in [Vector3(r.position.x + 6.0, 0, r.end.y - 4.0), Vector3(r.end.x - 4.0, 0, r.end.y - 4.0)]:  # (past the graves' rows)
		var h := _solid(t + Vector3(0, 1.2, 0), Vector3(2.4, 2.4, 3.0), _brick)
		level._mark_cover(h, Vector3(2.4, 2.4, 3.0))


## The ways in, for the servants: points out in the dark beyond the gate and the north breach
## (12-18 m out), and the east breach's (the cemetery's, past the graves).
func _ways() -> void:
	var s := INNER.end.y + WALL_T
	var n := INNER.position.y - WALL_T
	var nx := (BREACH_N.x + BREACH_N.y) * 0.5
	spots.ways = {
		"gate": [_w(Vector3(-4, 0, s + 13)), _w(Vector3(3, 0, s + 16)), _w(Vector3(9, 0, s + 12))],
		"north": [_w(Vector3(nx - 4, 0, n - 13)), _w(Vector3(nx + 3, 0, n - 16)), _w(Vector3(nx + 8, 0, n - 12))],
		"east": [_w(Vector3(CEMETERY.end.x + 6, 0, -12)), _w(Vector3(CEMETERY.end.x + 8, 0, 2)), _w(Vector3(CEMETERY.end.x + 5, 0, -20))],
	}
	# Just outside each gap, out of the light and out of sight from the fire: where one steps out
	# of the dark close enough to matter (act6's old ring was 11-15 m from the fire for that).
	var ex := INNER.end.x + WALL_T
	spots.mouths = {
		"gate": _w(Vector3(1.5, 0, s + 3.0)),
		"north": _w(Vector3(nx, 0, n - 3.0)),
		"east": _w(Vector3(ex + 1.6, 0, (BREACH_E.x + BREACH_E.y) * 0.5 + 6.0)),
	}


func _lantern(p: Vector3) -> void:
	level._prop(self, "prop_lantern.glb", _w(p), yaw)
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.7, 0.4)
	l.light_energy = 0.9
	l.omni_range = 6.0
	add_child(l)
	l.global_position = _w(p + Vector3(0, 0.45, 0))
