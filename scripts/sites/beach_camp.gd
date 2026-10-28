class_name BeachCamp
extends Node3D
## The coast route's night camp (gameplan/route_stops_plan.md, stage 1): on the coast the trucks are
## the camp, drawn up on the beach by the dunes, a fire in their lee, the sea for sound. A piece a
## coast map puts down (CoastTown has one south of the town, by the shore road). No act uses it yet.
## Its front (+z, turned by `yaw`) faces the sea; the two trucks stand side-on behind the fire as
## the windbreak, the bedrolls between, the loads at their tailgates; a dune behind them for the
## watch (CampJobs' crest). The rings round the fire are left open at CampJobs' distances, as in
## DesertCamp (tests/coast_town_test checks every job finds its spot).
##   var camp := BeachCamp.build(level, at, yaw)   # before the level bakes its navmesh
##   CampJobs.assign(level, companions, "act6_stop", true, {"anchor": camp.anchor})
## Placeholders (blockout until models come): the dune (a box with a ramp), the driftwood.

const TRUCKS := [[Vector3(-4.8, 0, -7.0), PI * 0.5 + 0.3], [Vector3(4.8, 0, -7.0), PI * 0.5 - 0.3]]
const DUNE := Rect2(-6, -29, 12, 9)      # the watch's dune top, 2.4 m up; its ramp runs toward the camp
const DUNE_H := 2.4

var level: Level
var anchor := Vector3.ZERO
var yaw := 0.0
## fire, gate (the way in from the shore road), sea (the water's edge side), lookout, and the lists
## beds and trucks.
var spots := {}
var _xf := Transform3D.IDENTITY
var _sand: StandardMaterial3D
var _wood: StandardMaterial3D


static func build(lvl: Level, at: Vector3, facing := 0.0) -> BeachCamp:
	var c := BeachCamp.new()
	c.name = "BeachCamp"
	c.level = lvl
	c.yaw = facing
	c._xf = Transform3D(Basis(Vector3.UP, facing), at)
	lvl.add_child(c)
	c._sand = lvl._sand
	c._wood = StandardMaterial3D.new()
	c._wood.albedo_color = Color(0.5, 0.42, 0.34)
	c._fire()
	c._trucks()
	c._beds_and_loads()
	c._dune()
	return c


func _w(p: Vector3) -> Vector3:
	return _xf * p


func _solid(p: Vector3, size: Vector3, mat: Material, turn := 0.0, tilt := 0.0) -> StaticBody3D:
	var b := level._box(level._nav, _w(p), size, mat)
	b.rotation = Vector3(tilt, yaw + turn, 0)
	return b


func _fire() -> void:
	anchor = _w(Vector3.ZERO)
	level._prop(self, "prop_campfire.glb", anchor)
	var f := Node3D.new()
	f.name = "Fire"
	add_child(f)
	f.global_position = anchor
	level._flame(f, Vector3.UP * 0.45, 2.6, 12.0, true)
	# Driftwood logs to sit on, either side (low: you step over them).
	for side: float in [-1.0, 1.0]:
		var log := CylinderMesh.new()
		log.top_radius = 0.16
		log.bottom_radius = 0.18
		log.height = 2.4
		var mi := MeshInstance3D.new()
		mi.mesh = log
		mi.material_override = _wood
		add_child(mi)
		mi.global_position = _w(Vector3(side * 2.9, 0.16, 1.2))
		mi.rotation = Vector3(PI * 0.5, yaw + side * 0.4, 0)
	spots.fire = anchor
	spots.gate = _w(Vector3(0, 0, 14))
	spots.sea = _w(Vector3(0, 0, 18))


func _trucks() -> void:
	var trucks: Array[Vector3] = []
	for t: Array in TRUCKS:
		var p: Vector3 = t[0]
		level._prop(self, "vehicle_truck.glb", _w(p), yaw + float(t[1]))
		var b := _solid(p + Vector3(0, 1.3, 0), Vector3(2.4, 2.6, 6.4), null, float(t[1]))
		(b.get_child(1) as MeshInstance3D).visible = false
		trucks.append(_w(p))
	spots.trucks = trucks


func _beds_and_loads() -> void:
	var beds: Array[Vector3] = []
	for k in 5:
		var p := Vector3(-4.0 + k * 2.0, 0, -3.8)
		level._prop(self, "prop_bedroll.glb", _w(p), yaw + PI * 0.5)
		beds.append(_w(p))
	for p: Vector3 in [Vector3(-6.8, 0, -1.2), Vector3(6.8, 0, -1.2)]:
		level._prop(self, "prop_bedroll.glb", _w(p), yaw)
		beds.append(_w(p))
	spots.beds = beds
	for c: Array in [[Vector3(9.4, 0.4, -4.2), Vector3(2.0, 0.8, 1.0)], [Vector3(-9.4, 0.4, -4.2), Vector3(1.0, 0.8, 1.0)]]:
		var b := _solid(c[0], c[1], level._stone)
		level._dress(b, "prop_crate_large.glb", Vector3(1.0, 0.8, 1.0))
		level._mark_cover(b, c[1])
	level._prop(self, "prop_tent.glb", _w(Vector3(-8.8, 0, 3.4)), yaw + 2.2)
	var tb := _solid(Vector3(-8.8, 0.9, 3.4), Vector3(2.2, 1.8, 2.6), null, 2.2)
	(tb.get_child(1) as MeshInstance3D).visible = false
	for p: Vector3 in [Vector3(9.4, 0.8, -4.2), Vector3(-2.5, 0, -5.0)]:
		level._prop(self, "prop_lantern.glb", _w(p), yaw)
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.7, 0.4)
		l.light_energy = 0.9
		l.omni_range = 5.5
		add_child(l)
		l.global_position = _w(p + Vector3(0, 0.45, 0))


## The dune behind the trucks: a flat top 2.4 m up for the watch, a ramp down toward the camp.
func _dune() -> void:
	var r := DUNE
	var mid := Vector3(r.get_center().x, 0, r.get_center().y)
	_solid(mid + Vector3(0, DUNE_H * 0.5, 0), Vector3(r.size.x, DUNE_H, r.size.y), _sand)
	var run := 8.0
	_solid(Vector3(mid.x, DUNE_H * 0.5 - 0.2, r.end.y + run * 0.5), Vector3(4.0, 0.4, Vector2(run, DUNE_H).length()), _sand,
		0.0, atan2(DUNE_H, run))
	# The dune's soft shoulders (dressing round the box).
	var sm := SphereMesh.new()
	sm.radius = 9.0
	sm.height = 18.0
	var mi := MeshInstance3D.new()
	mi.mesh = sm
	mi.material_override = _sand
	add_child(mi)
	mi.global_position = _w(mid + Vector3(0, -6.8, -3.0))
	mi.scale = Vector3(1.4, 1.0, 1.0)
	mi.rotation.y = yaw
	spots.lookout = _w(mid + Vector3(0, DUNE_H, 0))
