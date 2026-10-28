class_name DesertCamp
extends Node3D
## The desert night camp (gameplan/route_stops_plan.md, stage 1): a rock shelter by a spring, one
## piece a desert map puts down where its road stops for the night (Act 3's night on the road, Act
## 6's night back). No act uses it yet. Its front (+z, turned by `yaw`) is the open desert, the rock
## behind: an overhang to sleep under, the spring and its palms at the west end, the cook fire in
## the middle (the anchor CampJobs rings round), two tents, the truck as a windbreak on the west,
## the picket line east, the loads, and a knoll out to the north-east for the lookout (CampJobs'
## crest). The rings round the fire are left open at CampJobs' distances, so every job finds its
## place: fire 2.1, pistol 3.4, read 4.4, catalogue 5.2, loads 6.2, dig 6.8, camels 8 (by the
## picket line), watch 10.5, stars 11.5, the crest 14-26 m (tests/desert_camp_test checks each).
##   var camp := DesertCamp.build(level, at, yaw)   # before the level bakes its navmesh
##   CampJobs.assign(level, companions, "act3_camp", true, {"anchor": camp.anchor})
## The solids go into the level's _nav (its bake reads them); the dressing stays under this node.
## The ground is the level's: put it down on flat ground (`at.y` its height).
## Placeholders (blockout until models come): the rock shelter and the knoll (boxes), the spring's
## pool and rim, the picket posts and rope (the palms are -f9's Palms). The animals are the
## act's own (tie them at `picket`).

## The camp's places, in its own frame (x east, z toward the open desert; the fire at the origin).
const FIRE := Vector3.ZERO
const SPRING := Vector3(-10.5, 0, -3.5)
const TENTS := [[Vector3(6.8, 0, -1.2), -1.9], [Vector3(-4.6, 0, 6.2), 2.5]]
const TRUCK := [Vector3(-11.5, 0, 7.5), 0.0]
const PICKET := [Vector3(11.5, 0, -0.5), Vector3(11.5, 0, 9.5)]
const KNOLL := Rect2(15, -21, 10, 9)     # the lookout's top, 1.8 m up; its ramp runs south off it
const KNOLL_H := 1.8

var level: Level
var anchor := Vector3.ZERO
var yaw := 0.0
## Where things are, in the world: fire, spring, shelter (under the overhang), truck, lookout, gate
## (the way in from the road), and the lists beds, tents, picket (where animals are tied).
var spots := {}
var _xf := Transform3D.IDENTITY
var _rock: StandardMaterial3D
var _water: StandardMaterial3D
var _bark: StandardMaterial3D


static func build(lvl: Level, at: Vector3, facing := 0.0) -> DesertCamp:
	var c := DesertCamp.new()
	c.name = "DesertCamp"
	c.level = lvl
	c.yaw = facing
	c._xf = Transform3D(Basis(Vector3.UP, facing), at)
	lvl.add_child(c)
	c._materials()
	c._shelter()
	c._spring()
	c._fire()
	c._tents_and_beds()
	c._truck()
	c._picket()
	c._loads()
	c._knoll()
	return c


func _w(p: Vector3) -> Vector3:
	return _xf * p


func _materials() -> void:
	_rock = level._stone.duplicate() as StandardMaterial3D
	_rock.albedo_texture = level._noise_tex(Color(0.48, 0.36, 0.25), Color(0.7, 0.55, 0.38), 0.04, false)
	_water = StandardMaterial3D.new()
	_water.albedo_color = Color(0.2, 0.32, 0.34)
	_water.roughness = 0.05
	_water.metallic = 0.3
	_bark = StandardMaterial3D.new()
	_bark.albedo_color = Color(0.4, 0.3, 0.2)


## A solid in the camp's frame: into the level's _nav, turned with the camp (and `tilt` about its x).
func _solid(p: Vector3, size: Vector3, mat: Material, turn := 0.0, tilt := 0.0) -> StaticBody3D:
	var b := level._box(level._nav, _w(p), size, mat)
	b.rotation = Vector3(tilt, yaw + turn, 0)
	return b


## A collision box only (round a prop that has none).
func _block(p: Vector3, size: Vector3, turn := 0.0) -> void:
	var b := _solid(p, size, null, turn)
	(b.get_child(1) as MeshInstance3D).visible = false


## A mesh only (dressing nothing walks into).
func _mesh(m: Mesh, p: Vector3, mat: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = mat
	add_child(mi)
	mi.global_position = _w(p)
	mi.rotation = rot + Vector3(0, yaw, 0)
	return mi


## The rock behind the camp: a back wall, an overhang to sleep under, an arm either end.
func _shelter() -> void:
	_solid(Vector3(0, 3.0, -9.6), Vector3(28, 6.0, 3.2), _rock)
	_solid(Vector3(-3, 2.2, -11.8), Vector3(20, 4.4, 2.5), _rock, 0.08)
	_solid(Vector3(2.0, 4.2, -6.2), Vector3(16, 1.2, 5.2), _rock)       # the overhang, 3.6 m clear under it
	_solid(Vector3(-15.0, 2.0, -6.5), Vector3(4.2, 4.0, 7.0), _rock, 0.25)  # the west arm, over the spring
	_solid(Vector3(13.2, 1.5, -6.8), Vector3(5.0, 3.0, 5.5), _rock, -0.3)   # the east arm
	for b: Array in [[Vector3(-7.8, 0.5, -7.0), 1.4], [Vector3(10.4, 0.45, -3.6), 1.2], [Vector3(-16.5, 0.6, 1.5), 1.6]]:
		var s: float = b[1]
		level._mark_cover(_solid(b[0], Vector3(s, s * 0.75, s * 0.9), _rock, float(b[1])), Vector3(s, s * 0.75, s * 0.9))
	spots.shelter = _w(Vector3(2.0, 0, -6.0))
	spots.gate = _w(Vector3(0, 0, 16.0))


## The spring under the west arm: a pool in a stone rim, three palms.
func _spring() -> void:
	var c := SPRING
	_solid(c + Vector3(0, 0.18, -1.8), Vector3(3.8, 0.36, 0.4), _rock)
	_solid(c + Vector3(0, 0.18, 1.8), Vector3(3.8, 0.36, 0.4), _rock)
	_solid(c + Vector3(-1.7, 0.18, 0), Vector3(0.4, 0.36, 3.2), _rock)
	_solid(c + Vector3(1.7, 0.18, 0), Vector3(0.4, 0.36, 3.2), _rock)
	var pool := PlaneMesh.new()
	pool.size = Vector2(3.0, 3.2)
	_mesh(pool, c + Vector3(0, 0.12, 0), _water)
	for p: Vector3 in [Vector3(-13.6, 0, 0.6), Vector3(-12.4, 0, 3.6), Vector3(-7.4, 0, -1.8)]:
		_palm_tree(p, 6.5 + absf(p.x) * 0.12)
	spots.spring = _w(c + Vector3(2.4, 0, 0))


## A date palm (-f9's Palms: batched, swaying; its trunk solid in the level's _nav for the bake).
func _palm_tree(p: Vector3, h: float) -> void:
	Palms.add(self, _w(p), h, level._nav)


## The cook fire: the camp's middle, its light, the stools round it are CampJobs' props.
func _fire() -> void:
	anchor = _w(FIRE)
	level._prop(self, "prop_campfire.glb", anchor)
	var f := Node3D.new()
	f.name = "Fire"
	add_child(f)
	f.global_position = anchor
	level._flame(f, Vector3.UP * 0.45, 2.6, 12.0, true)
	spots.fire = anchor


## Two tents off the fire (facing it), bedrolls under the overhang and by the tents.
func _tents_and_beds() -> void:
	var tents: Array[Vector3] = []
	for t: Array in TENTS:
		var p: Vector3 = t[0]
		level._prop(self, "prop_tent.glb", _w(p), yaw + float(t[1]))
		_block(p + Vector3(0, 0.9, 0), Vector3(2.2, 1.8, 2.6), float(t[1]))
		tents.append(_w(p))
	spots.tents = tents
	var beds: Array[Vector3] = []
	for k in 6:
		var p := Vector3(-3.4 + k * 2.0, 0, -6.6)
		level._prop(self, "prop_bedroll.glb", _w(p), yaw + PI * 0.5)
		beds.append(_w(p))
	for p: Vector3 in [Vector3(8.6, 0, 1.4), Vector3(-6.9, 0, 7.6)]:
		level._prop(self, "prop_bedroll.glb", _w(p), yaw)
		beds.append(_w(p))
	spots.beds = beds
	# Lanterns: at the overhang's lip and on the loads.
	for p: Vector3 in [Vector3(-2.0, 0, -4.2), Vector3(6.0, 0, -4.2)]:
		_lantern(p)


func _lantern(p: Vector3) -> void:
	level._prop(self, "prop_lantern.glb", _w(p), yaw)
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.7, 0.4)
	l.light_energy = 0.9
	l.omni_range = 5.5
	add_child(l)
	l.global_position = _w(p + Vector3(0, 0.45, 0))


## The truck on the west, side-on to the wind: the camp's windbreak.
func _truck() -> void:
	var p: Vector3 = TRUCK[0]
	level._prop(self, "vehicle_truck.glb", _w(p), yaw + float(TRUCK[1]))
	_block(p + Vector3(0, 1.3, 0), Vector3(2.4, 2.6, 6.4), float(TRUCK[1]))
	spots.truck = _w(p)


## The picket line east: two posts and a rope; the animals are tied along it.
func _picket() -> void:
	var a: Vector3 = PICKET[0]
	var b: Vector3 = PICKET[1]
	for p: Vector3 in [a, b]:
		var post := level._cylinder(level._nav, _w(p + Vector3(0, 0.7, 0)), 0.09, 1.4)
		(post.get_child(1) as MeshInstance3D).material_override = _bark
	var rope := BoxMesh.new()
	rope.size = Vector3(0.03, 0.03, a.distance_to(b))
	_mesh(rope, (a + b) * 0.5 + Vector3(0, 1.25, 0), _bark)
	var ties: Array[Vector3] = []
	for k in 4:
		ties.append(_w(a.lerp(b, (k + 0.5) / 4.0) + Vector3(1.0, 0, 0)))
	spots.picket = ties


## The loads: crates under the overhang, by the lanterns.
func _loads() -> void:
	for c: Array in [[Vector3(5.4, 0.4, -5.0), Vector3(2.0, 0.8, 1.0)], [Vector3(-3.0, 0.4, -4.9), Vector3(1.0, 0.8, 1.0)]]:
		var b := _solid(c[0], c[1], _rock)
		level._dress(b, "prop_crate_large.glb", Vector3(1.0, 0.8, 1.0))
		level._mark_cover(b, c[1])


## The knoll out north-east: a flat top 1.8 m up, a ramp down its south face toward the camp.
func _knoll() -> void:
	var r := KNOLL
	var mid := Vector3(r.get_center().x, 0, r.get_center().y)
	_solid(mid + Vector3(0, KNOLL_H * 0.5, 0), Vector3(r.size.x, KNOLL_H, r.size.y), _rock)
	var run := 7.0
	var tilt := atan2(KNOLL_H, run)
	var length := Vector2(run, KNOLL_H).length()
	_solid(Vector3(mid.x, KNOLL_H * 0.5 - 0.2, r.end.y + run * 0.5), Vector3(3.0, 0.4, length), _rock, 0.0, tilt)
	spots.lookout = _w(mid + Vector3(0, KNOLL_H, 0))
