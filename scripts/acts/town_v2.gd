class_name TownV2
extends Level
## Stage 1 of gameplan/route_stops_plan.md: the caravan town at the end of the desert road, about
## 300 x 220 m inside its wall, in districts, as blockout. No act uses it yet: today's town (the
## houses at DesertRoute's north end) stays the game's until Simon approves (tests/town_v2_test
## walks it). North is -z; the convoy comes in at the south gate.
##   the caravanserai (NW): a courtyard 72 x 46 m in a ring of rooms, its gate east on the lane
##   the well square (N): the well, a dovecote, a sycamore, a few stalls
##   the souk (NE): blocks of shops on narrow lanes under awnings
##   the mosque (middle): a walled court, the prayer hall east under a dome, the minaret
##   Mariam's store and the inn (SE): the store on the gate street, the inn round its own court
##   the palm grove and gardens (SW): walled plots, palms, a channel
##   houses between, the cross street (z 90-104) and the gate street (x 174-186)
## Placeholders (blockout until models come): every building (boxes in mud-brick and plaster), the
## wall and gate towers, the well, the dovecote, the dome and minaret, palms and the sycamore (a
## trunk and a crown), stalls and awnings (cloth boxes), the garden beds and the channel.

const SIZE := Vector2(300, 220)
const TOWN_WALL_H := 5.0
const GATE := Vector2(174, 186)       # the south gate's opening (x)
## Each district's ground (for the test's overview and anyone placing things in it).
const DISTRICTS := {
	"caravanserai": Rect2(10, 24, 88, 64), "well_square": Rect2(112, 18, 78, 72), "souk": Rect2(190, 2, 108, 88),
	"mosque": Rect2(112, 106, 60, 54), "store_inn": Rect2(188, 106, 110, 54), "grove": Rect2(6, 106, 96, 110),
	"houses_south": Rect2(112, 164, 186, 52),
}
const SPOTS := {
	"arrival": Vector3(180, 0, 238), "south_gate": Vector3(180, 0, 210), "caravanserai": Vector3(36, 0, 46),
	"caravanserai_gate": Vector3(104, 0, 56), "well": Vector3(150, 0, 60), "dovecote": Vector3(174, 0, 38),
	"souk": Vector3(228, 0, 30), "souk_east": Vector3(282, 0, 58), "mosque": Vector3(126, 0, 122),
	"store": Vector3(184, 0, 115), "inn": Vector3(246, 0, 124), "grove": Vector3(54, 0, 160),
	"cross_street": Vector3(150, 0, 97), "back_lane": Vector3(156, 0, 190),
}

var spots := {}
var _deco: Node3D
var _rng := RandomNumberGenerator.new()
var _mud: Array[StandardMaterial3D] = []
var _whitewash: StandardMaterial3D
var _cloth: Array[StandardMaterial3D] = []
var _green: StandardMaterial3D
var _bark: StandardMaterial3D
var _water: StandardMaterial3D


func _ready() -> void:
	_rng.seed = 1923
	_make_materials()
	_town_materials()
	_nav = NavigationRegion3D.new()
	_nav.navigation_mesh = Level.nav_mesh()
	add_child(_nav)
	_deco = Node3D.new()
	_deco.name = "Deco"
	add_child(_deco)
	# The ground: the town and 40 m of desert round it, the road south from the gate.
	_box(_nav, Vector3(SIZE.x * 0.5, -0.5, SIZE.y * 0.5 + 20.0), Vector3(SIZE.x + 80.0, 1.0, SIZE.y + 120.0), _sand)
	_flat(Rect2(GATE.x + 2.0, SIZE.y, GATE.y - GATE.x - 4.0, 60.0), _floor_mat, 0.02)
	_town()
	player_spawn = spots.arrival
	_environment()
	_sun.rotation = Vector3(deg_to_rad(-34), deg_to_rad(-130), 0)
	_env.fog_density = 0.002
	_env.fog_light_color = Color(0.8, 0.66, 0.48)
	_nav.bake_navigation_mesh(false)
	RenderBudget.quiet_minor(_deco)
	if not "--no-merge" in OS.get_cmdline_user_args():
		print("TOWN v2 deco merged: %d draw calls fewer" % RenderBudget.merge_static(_deco))


## The town itself (on ground that's already there; RoadV2 builds it at the road's north end).
func _town() -> void:
	_wall()
	_caravanserai()
	_well_square()
	_souk()
	_mosque()
	_store_and_inn()
	_grove()
	_houses()
	for id: String in SPOTS:
		spots[id] = SPOTS[id]


func _town_materials() -> void:
	for c in [[Color(0.58, 0.45, 0.32), Color(0.72, 0.6, 0.44)], [Color(0.64, 0.5, 0.36), Color(0.78, 0.66, 0.5)],
			[Color(0.52, 0.42, 0.3), Color(0.66, 0.55, 0.4)]]:
		var m := _floor_mat.duplicate() as StandardMaterial3D
		m.albedo_texture = _noise_tex(c[0], c[1], 0.06, false)
		_mud.append(m)
	_whitewash = _floor_mat.duplicate() as StandardMaterial3D
	_whitewash.albedo_texture = _noise_tex(Color(0.82, 0.78, 0.7), Color(0.95, 0.92, 0.85), 0.05, false)
	for c: Color in [Color(0.62, 0.22, 0.16), Color(0.82, 0.72, 0.5), Color(0.25, 0.35, 0.5), Color(0.5, 0.42, 0.2)]:
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		_cloth.append(m)
	_green = StandardMaterial3D.new()
	_green.albedo_color = Color(0.3, 0.42, 0.18)
	_bark = StandardMaterial3D.new()
	_bark.albedo_color = Color(0.4, 0.3, 0.2)
	_water = StandardMaterial3D.new()
	_water.albedo_color = Color(0.2, 0.32, 0.34)
	_water.roughness = 0.05
	_water.metallic = 0.3


# ---------------------------------------------------------------- pieces

## A solid standing on the ground over `r` (x, z), `h` tall.
func _solid(r: Rect2, h: float, mat: Material, y0 := 0.0) -> StaticBody3D:
	return _box(_nav, Vector3(r.get_center().x, y0 + h * 0.5, r.get_center().y), Vector3(r.size.x, h, r.size.y), mat)


## A mesh only, nothing walks into it.
func _mesh(m: Mesh, p: Vector3, mat: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = mat
	_deco.add_child(mi)
	mi.position = p
	mi.rotation = rot
	return mi


## A flat mesh just over the ground (a road, a bed, a channel).
func _flat(r: Rect2, mat: Material, y := 0.03) -> void:
	var pm := PlaneMesh.new()
	pm.size = r.size
	_mesh(pm, Vector3(r.get_center().x, y, r.get_center().y), mat)


## A row of houses filling `r`: cut along its long side into lots 7-14 m, each its own height
## (and now and then plaster), so the skyline steps.
func _block(r: Rect2, hmin := 4.0, hmax := 8.0) -> void:
	var along_x := r.size.x >= r.size.y
	var length := r.size.x if along_x else r.size.y
	var at := 0.0
	while at < length - 0.1:
		var w := minf(_rng.randf_range(7.0, 14.0), length - at)
		if length - at - w < 5.0:
			w = length - at
		var lot := Rect2(r.position + (Vector2(at, 0) if along_x else Vector2(0, at)), Vector2(w, r.size.y) if along_x else Vector2(r.size.x, w))
		var mat: Material = _whitewash if _rng.randf() < 0.15 else _mud[_rng.randi() % _mud.size()]
		_solid(lot, _rng.randf_range(hmin, hmax), mat)
		at += w


func _awning(r: Rect2, y := 3.2) -> void:
	var bm := BoxMesh.new()
	bm.size = Vector3(r.size.x, 0.06, r.size.y)
	_mesh(bm, Vector3(r.get_center().x, y, r.get_center().y), _cloth[_rng.randi() % _cloth.size()],
		Vector3(_rng.randf_range(-0.06, 0.06), 0, 0))


func _tree(p: Vector3, h: float, crown: float, trunk := 0.22) -> void:
	var t := _cylinder(_nav, p + Vector3(0, h * 0.5, 0), trunk, h)
	(t.get_child(1) as MeshInstance3D).material_override = _bark
	var sm := SphereMesh.new()
	sm.radius = crown
	sm.height = crown * 0.65
	_mesh(sm, p + Vector3(0, h + crown * 0.15, 0), _green)


# ---------------------------------------------------------------- the districts

## The town wall, the south gate between two towers.
func _wall() -> void:
	var t := 1.5
	_solid(Rect2(0, 0, SIZE.x, t), TOWN_WALL_H, _mud[0])
	_solid(Rect2(0, 0, t, SIZE.y), TOWN_WALL_H, _mud[0])
	_solid(Rect2(SIZE.x - t, 0, t, SIZE.y), TOWN_WALL_H, _mud[0])
	_solid(Rect2(0, SIZE.y - t, GATE.x - 4.0, t), TOWN_WALL_H, _mud[0])
	_solid(Rect2(GATE.y + 4.0, SIZE.y - t, SIZE.x - GATE.y - 4.0, t), TOWN_WALL_H, _mud[0])
	for x: float in [GATE.x - 4.0, GATE.y]:
		_solid(Rect2(x, SIZE.y - 3.0, 4.0, 5.0), 8.0, _mud[1])
	var arch := BoxMesh.new()
	arch.size = Vector3(GATE.y - GATE.x, 1.6, 2.0)
	_mesh(arch, Vector3((GATE.x + GATE.y) * 0.5, 6.4, SIZE.y - 0.5), _mud[1])
	# The towers at the corners.
	for c: Vector2 in [Vector2(0, 0), Vector2(SIZE.x - 5.0, 0), Vector2(0, SIZE.y - 5.0), Vector2(SIZE.x - 5.0, SIZE.y - 5.0)]:
		_solid(Rect2(c, Vector2(5, 5)), 7.5, _mud[1])


## The caravanserai: a ring of rooms two storeys high round an open court, its gate east.
func _caravanserai() -> void:
	var r: Rect2 = DISTRICTS.caravanserai
	var d := 8.0
	var h := 7.5
	var m := _mud[2]
	_solid(Rect2(r.position.x, r.position.y, r.size.x, d), h, m)
	_solid(Rect2(r.position.x, r.end.y - d, r.size.x, d), h, m)
	_solid(Rect2(r.position.x, r.position.y + d, d, r.size.y - d * 2.0), h, m)
	var gz := Vector2(52, 60)  # the gate's opening (z)
	_solid(Rect2(r.end.x - d, r.position.y + d, d, gz.x - r.position.y - d), h, m)
	_solid(Rect2(r.end.x - d, gz.y, d, r.end.y - d - gz.y), h, m)
	_solid(Rect2(r.end.x - d, gz.x, d, gz.y - gz.x), 2.0, m, h - 2.0)  # the gateway's lintel, over the way in
	# The gallery: a shade roof round the court on posts (dressing; the rooms behind are solid).
	for side: Rect2 in [Rect2(r.position.x + d, r.position.y + d, r.size.x - d * 2.0, 3.0),
			Rect2(r.position.x + d, r.end.y - d - 3.0, r.size.x - d * 2.0, 3.0)]:
		_awning(side, 3.4)
	# In the court: a fountain, troughs, the loads, stalls for the animals along the west.
	_cylinder(_nav, Vector3(54, 0.4, 56), 1.8, 0.8)
	for z: float in [40.0, 70.0]:
		_solid(Rect2(60, z, 6, 1), 0.7, _mud[0])
	for k in 5:
		_solid(Rect2(r.position.x + d, 36.0 + k * 7.0, 5.0, 0.3), 1.3, _mud[0])
	for c: Vector3 in [Vector3(80, 0.4, 38), Vector3(82, 0.4, 72), Vector3(72, 0.4, 74)]:
		var b := _box(_nav, c, Vector3(2.0, 0.8, 1.0), _floor_mat)
		_dress(b, "prop_crate_large.glb", Vector3(1.0, 0.8, 1.0))
		_mark_cover(b, Vector3(2.0, 0.8, 1.0))
	_prop(_deco, "vehicle_truck.glb", Vector3(70, 0, 60), PI * 0.5)
	var tb := _box(_nav, Vector3(70, 1.3, 60), Vector3(6.4, 2.6, 2.4), null)
	(tb.get_child(1) as MeshInstance3D).visible = false


## The well square: open ground, the well in the middle, a dovecote, a sycamore, a few stalls.
func _well_square() -> void:
	_cylinder(_nav, Vector3(150, 0.5, 55), 1.6, 1.0)
	_solid(Rect2(146, 50, 0.3, 10), 2.6, _bark)       # the well's frame (two posts and a beam)
	_solid(Rect2(153.7, 50, 0.3, 10), 2.6, _bark)
	_solid(Rect2(141, 62, 5, 1), 0.6, _mud[0])        # a trough
	var dove := _cylinder(_nav, Vector3(180, 5.0, 30), 3.4, 10.0)
	(dove.get_child(1) as MeshInstance3D).material_override = _whitewash
	_tree(Vector3(124, 0, 76), 6.5, 6.0, 0.6)
	for k in 4:
		var x := 120.0 + k * 9.0
		_solid(Rect2(x, 24, 3, 1.4), 1.0, _bark)
		_awning(Rect2(x - 0.5, 23, 4, 3.2), 2.6)


## The souk: blocks of shops on lanes 4 m wide (east-west at z 28-32 and 56-60, north-south at
## x 226-230 and 262-266), awnings over the lanes, opening west onto the well square.
func _souk() -> void:
	var xs := [[194.0, 226.0], [230.0, 262.0], [266.0, 298.5]]
	var zs := [[1.5, 28.0], [32.0, 56.0], [60.0, 90.0]]
	for x: Array in xs:
		for z: Array in zs:
			_block(Rect2(x[0], z[0], x[1] - x[0], z[1] - z[0]), 4.0, 6.5)
	for z: float in [28.0, 56.0]:
		var x := 194.0
		while x < 296.0:
			_awning(Rect2(x, z, 6.0, 4.0))
			x += 7.5
	for x: float in [226.0, 262.0]:
		var z := 2.0
		while z < 88.0:
			_awning(Rect2(x, z, 4.0, 6.0))
			z += 7.5


## The mosque: a walled court, the prayer hall along the east under a dome, the minaret at the
## north-west corner; the gate north onto the cross street.
func _mosque() -> void:
	var r: Rect2 = DISTRICTS.mosque
	var hall := Rect2(r.end.x - 22.0, r.position.y, 22.0, r.size.y)
	_solid(hall, 8.0, _whitewash)
	var dome := SphereMesh.new()
	dome.radius = 8.0
	dome.height = 9.0
	_mesh(dome, Vector3(hall.get_center().x, 8.0, hall.get_center().y), _whitewash)
	var w := 1.0
	var gx := Vector2(130, 138)
	_solid(Rect2(r.position.x, r.position.y, gx.x - r.position.x, w), 5.0, _whitewash)
	_solid(Rect2(gx.y, r.position.y, hall.position.x - gx.y, w), 5.0, _whitewash)
	_solid(Rect2(r.position.x, r.position.y, w, r.size.y), 5.0, _whitewash)
	_solid(Rect2(r.position.x, r.end.y - w, hall.position.x - r.position.x, w), 5.0, _whitewash)
	_solid(Rect2(r.position.x + 1.0, r.position.y + 1.0, 4.5, 4.5), 22.0, _whitewash)  # the minaret
	_cylinder(_nav, Vector3(131, 0.4, 136), 1.5, 0.8)   # the ablution fountain


## Mariam's store on the gate street, the inn round its court behind it, houses between.
func _store_and_inn() -> void:
	_solid(Rect2(188, 106, 24, 16), 5.5, _whitewash)   # Mariam's store
	_awning(Rect2(186, 108, 3, 12), 2.8)
	for c: Vector3 in [Vector3(187.2, 0.4, 111), Vector3(187.2, 0.4, 118)]:
		var b := _box(_nav, c, Vector3(1.0, 0.8, 2.0), _floor_mat)
		_dress(b, "prop_crate_large.glb", Vector3(1.0, 0.8, 1.0))
	_block(Rect2(188, 126, 24, 34), 4.0, 7.0)
	# The inn: rooms round a court 32 x 34, its gate west on the lane at x 212-216.
	var r := Rect2(216, 106, 62, 54)
	var d := 7.0
	var h := 7.0
	var m := _mud[1]
	_solid(Rect2(r.position.x, r.position.y, r.size.x, d), h, m)
	_solid(Rect2(r.position.x, r.end.y - d, r.size.x, d), h, m)
	_solid(Rect2(r.end.x - d, r.position.y + d, d, r.size.y - d * 2.0), h, m)
	var gz := Vector2(120, 128)
	_solid(Rect2(r.position.x, r.position.y + d, d, gz.x - r.position.y - d), h, m)
	_solid(Rect2(r.position.x, gz.y, d, r.end.y - d - gz.y), h, m)
	_solid(Rect2(r.position.x, gz.x, d, gz.y - gz.x), 2.0, m, h - 2.0)
	_tree(Vector3(254, 0, 134), 5.0, 4.0, 0.4)
	_block(Rect2(282, 106, 16.5, 54), 4.0, 6.5)


## The palm grove and its gardens: four walled plots with gaps, palms, beds, a channel.
func _grove() -> void:
	var r: Rect2 = DISTRICTS.grove
	var channel := Rect2(r.position.x, 158, r.size.x, 1.6)
	_flat(channel, _water, 0.05)
	for plot: Rect2 in [Rect2(10, 110, 40, 44), Rect2(58, 110, 40, 44), Rect2(10, 164, 40, 48), Rect2(58, 164, 40, 48)]:
		var t := 0.6
		var gap := 4.0
		var mid := plot.get_center()
		# Each side in two halves round a gap.
		_solid(Rect2(plot.position.x, plot.position.y, mid.x - gap * 0.5 - plot.position.x, t), 1.3, _mud[0])
		_solid(Rect2(mid.x + gap * 0.5, plot.position.y, plot.end.x - mid.x - gap * 0.5, t), 1.3, _mud[0])
		_solid(Rect2(plot.position.x, plot.end.y - t, mid.x - gap * 0.5 - plot.position.x, t), 1.3, _mud[0])
		_solid(Rect2(mid.x + gap * 0.5, plot.end.y - t, plot.end.x - mid.x - gap * 0.5, t), 1.3, _mud[0])
		_solid(Rect2(plot.position.x, plot.position.y, t, mid.y - gap * 0.5 - plot.position.y), 1.3, _mud[0])
		_solid(Rect2(plot.position.x, mid.y + gap * 0.5, t, plot.end.y - mid.y - gap * 0.5), 1.3, _mud[0])
		_solid(Rect2(plot.end.x - t, plot.position.y, t, mid.y - gap * 0.5 - plot.position.y), 1.3, _mud[0])
		_solid(Rect2(plot.end.x - t, mid.y + gap * 0.5, t, plot.end.y - mid.y - gap * 0.5), 1.3, _mud[0])
		# Beds either side of the plot's cross paths, palms in rows between them.
		for q: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
			var c := mid + q * Vector2(plot.size.x * 0.25 + 0.5, plot.size.y * 0.25 + 0.5)
			_flat(Rect2(c - Vector2(5, 4), Vector2(10, 8)), _green, 0.04)
		for i in 4:
			for j in 4:
				if i in [1, 2] and j in [1, 2]:
					continue  # the paths through the middle stay open
				var p := plot.position + Vector2(3.5 + i * (plot.size.x - 7.0) / 3.0, 3.5 + j * (plot.size.y - 7.0) / 3.0)
				p += Vector2(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1))
				_tree(Vector3(p.x, 0, p.y), _rng.randf_range(6.0, 9.0), 2.4)


## Houses: north of the caravanserai and the square, along the west lane, south of the mosque.
func _houses() -> void:
	_block(Rect2(1.5, 1.5, 96.5, 16.5), 4.0, 7.0)
	_block(Rect2(112, 1.5, 78, 14.5), 4.0, 7.5)
	_block(Rect2(1.5, 24, 6, 64), 3.5, 5.0)
	# South of the mosque and the inn: two rows each side of a lane at z 188-192, a lane at x 140-144.
	for x: Array in [[112.0, 140.0], [144.0, 172.0], [188.0, 240.0], [244.0, 298.5]]:
		_block(Rect2(x[0], 164, x[1] - x[0], 24), 4.0, 7.0)
		_block(Rect2(x[0], 192, x[1] - x[0], 20), 3.5, 6.5)
