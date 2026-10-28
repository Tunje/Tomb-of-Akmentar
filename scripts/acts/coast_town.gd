class_name CoastTown
extends TownV2
## Stage 1 of gameplan/route_stops_plan.md: the fishing town on the coast route, about 190 x 220 m,
## the sea to the west, as blockout. No act uses it yet: Act 3's coast branch keeps the desert
## road's map with a sea plane until Simon approves (tests/coast_town_test walks it). North is -z;
## the shore road runs north-south past the town's east side (x 196-206).
##   the harbour: a stone wall out into the sea and round to the south, the lighthouse and the
##   keeper's hut on its end, boats moored in the basin, the quay along the beach
##   the beach south of the harbour: boats pulled up, net racks
##   the fish market by the quay; the coffee house (the resupply) and the trader on the harbour
##   street; a small mosque; the boatyard with a hull on stocks; palms and the well
##   whitewashed houses with blue doors (a different palette from the desert town)
## Placeholders (blockout until models come): every building and the doors, the harbour wall and
## quay, the lighthouse and hut, the boats (hulls and masts as boxes), the net racks, the market
## stalls, the hull on stocks, the well (the palms are -f9's Palms). The people are crowd stand-ins
## (crowd/coast_town.json), the gulls AmbientLife's birds in white. South of the town on the
## beach, the trucks' night camp (BeachCamp).

const SEA_X := -30.0     # the waterline (the beach runs from here to the town at x 0)
const SEA_FLOOR := -2.5
## Each district's ground.
const COAST_DISTRICTS := {
	"harbour": Rect2(-138, 24, 108, 106), "beach": Rect2(-30, 130, 30, 110), "fish_market": Rect2(4, 30, 56, 40),
	"coffee_trader": Rect2(74, 34, 68, 40), "mosque": Rect2(4, 90, 56, 52), "boatyard": Rect2(76, 90, 110, 60),
	"palms_well": Rect2(4, 166, 186, 50),
}
const COAST_SPOTS := {
	"arrival": Vector3(201, 0, 250), "road_north": Vector3(201, 0, -40), "harbour_street": Vector3(100, 0, 78),
	"quay": Vector3(-26, 0, 70), "pier": Vector3(-123, 0, 60), "keeper": Vector3(-126, 0, 124),
	"beach_boats": Vector3(-16, 0, 182), "nets": Vector3(-3, 0, 214), "fish_market": Vector3(32, 0, 50),
	"coffee_house": Vector3(94, 0, 70), "trader": Vector3(130, 0, 72), "mosque": Vector3(20, 0, 112),
	"boatyard": Vector3(100, 0, 140), "well": Vector3(90, 0, 194),
}

const CAMP_AT := Vector3(-5, 0, 330)

var camp: BeachCamp
var _blue: StandardMaterial3D
var _sea_mat: StandardMaterial3D
var _wood: StandardMaterial3D


func _ready() -> void:
	_rng.seed = 1925
	_make_materials()
	_town_materials()
	_blue = StandardMaterial3D.new()
	_blue.albedo_color = Color(0.16, 0.36, 0.62)
	_wood = StandardMaterial3D.new()
	_wood.albedo_color = Color(0.42, 0.28, 0.16)
	_sea_mat = StandardMaterial3D.new()
	_sea_mat.albedo_color = Color(0.12, 0.3, 0.36)
	_sea_mat.roughness = 0.1
	_sea_mat.metallic = 0.3
	_nav = NavigationRegion3D.new()
	_nav.navigation_mesh = Level.nav_mesh()
	add_child(_nav)
	_deco = Node3D.new()
	_deco.name = "Deco"
	add_child(_deco)
	# The land from the waterline east, the sea floor west of it under the water.
	_box(_nav, Vector3((SEA_X + 260.0) * 0.5, -0.5, 170.0), Vector3(260.0 - SEA_X, 1.0, 460.0), _sand)
	_box(_nav, Vector3(SEA_X - 115.0, SEA_FLOOR - 0.5, 170.0), Vector3(230.0, 1.0, 460.0), _floor_mat)
	var sea := PlaneMesh.new()
	sea.size = Vector2(700, 900)
	_mesh(sea, Vector3(SEA_X - 350.0, -0.6, 110.0), _sea_mat)
	_flat(Rect2(196, -60, 10, 460), _floor_mat, 0.02)    # the shore road
	_flat(Rect2(0, 74, 196, 8), _floor_mat, 0.02)        # the harbour street
	_harbour()
	_beach()
	_fish_market()
	_coffee_and_trader()
	_coast_mosque()
	_boatyard()
	_palms_and_well()
	_coast_houses()
	# The beach camp south of the town: the trucks turned off the shore road onto the sand.
	camp = BeachCamp.build(self, CAMP_AT, -PI * 0.5)
	_flat(Rect2(CAMP_AT.x + 30.0, CAMP_AT.z - 2.0, 196.0 - CAMP_AT.x - 30.0, 4.0), _floor_mat, 0.02)
	for id: String in COAST_SPOTS:
		spots[id] = COAST_SPOTS[id]
	spots.camp = camp.anchor
	spots.camp_lookout = camp.spots.lookout
	player_spawn = spots.arrival
	_environment()
	_sun.rotation = Vector3(deg_to_rad(-26), deg_to_rad(-70), 0)  # late afternoon, from over the sea
	_env.fog_density = 0.0015
	_env.fog_light_color = Color(0.75, 0.78, 0.8)
	NavCache.bake(_nav, "coast_town")
	RenderBudget.quiet_minor(_deco)
	if not "--no-merge" in OS.get_cmdline_user_args():
		print("COAST town deco merged: %d draw calls fewer" % RenderBudget.merge_static(_deco))
	if not "--no-crowd" in OS.get_cmdline_user_args():
		Crowd.populate(self, "coast_town")


## A solid from the sea floor up to the ground's level (a pier, the harbour wall's walk).
func _pier(r: Rect2) -> void:
	_solid(r, -SEA_FLOOR, _stone, SEA_FLOOR)


## A row of whitewashed houses over `r`, each lot with a blue door (and now and then a blue
## shutter) on its `face` side: "n", "s", "e" or "w".
func _row(r: Rect2, face: String, hmin := 3.5, hmax := 7.0) -> void:
	var along_x := face in ["n", "s"]
	var length := r.size.x if along_x else r.size.y
	var at := 0.0
	while at < length - 0.1:
		var w := minf(_rng.randf_range(6.0, 11.0), length - at)
		if length - at - w < 5.0:
			w = length - at
		var lot := Rect2(r.position + (Vector2(at, 0) if along_x else Vector2(0, at)), Vector2(w, r.size.y) if along_x else Vector2(r.size.x, w))
		var h := _rng.randf_range(hmin, hmax)
		_solid(lot, h, _whitewash if _rng.randf() < 0.85 else _mud[1])
		var c := lot.get_center()
		var door := BoxMesh.new()
		var out := {"n": Vector2(0, -1), "s": Vector2(0, 1), "e": Vector2(1, 0), "w": Vector2(-1, 0)}[face] as Vector2
		var edge := c + out * (Vector2(lot.size.x, lot.size.y) * 0.5 + Vector2.ONE * 0.04)
		door.size = Vector3(1.1, 2.1, 0.08) if along_x else Vector3(0.08, 2.1, 1.1)
		_mesh(door, Vector3(edge.x, 1.05, edge.y), _blue)
		if _rng.randf() < 0.6 and h > 4.0:
			var shutter := BoxMesh.new()
			shutter.size = Vector3(0.9, 0.9, 0.08) if along_x else Vector3(0.08, 0.9, 0.9)
			var side := (Vector2(1, 0) if along_x else Vector2(0, 1)) * minf(w * 0.3, 2.5)
			_mesh(shutter, Vector3(edge.x + side.x, 3.0, edge.y + side.y), _blue)
		at += w


func _boat(p: Vector3, yaw: float, length: float, solid: bool) -> void:
	var hull := Vector3(length * 0.3, 1.0, length)
	if solid:
		var b := _box(_nav, p + Vector3(0, hull.y * 0.5, 0), hull, _wood)
		b.rotation = Vector3(0, yaw, 0.12)
		_mark_cover(b, hull)
	else:
		var bm := BoxMesh.new()
		bm.size = hull
		_mesh(bm, p + Vector3(0, hull.y * 0.5 - 0.4, 0), _wood, Vector3(0, yaw, 0))
		var mast := CylinderMesh.new()
		mast.top_radius = 0.06
		mast.bottom_radius = 0.08
		mast.height = length * 1.1
		_mesh(mast, p + Vector3(0, mast.height * 0.5, 0), _wood)


# ---------------------------------------------------------------- the districts

## The harbour: the wall out west from the beach, then south, the lighthouse on a platform at its
## end with the keeper's hut; a parapet on the sea side, bollards and moored boats inside; the
## quay along the beach.
func _harbour() -> void:
	_pier(Rect2(-126, 24, 96, 6))        # the north arm
	_pier(Rect2(-126, 30, 6, 80))        # the south arm
	_pier(Rect2(-138, 108, 22, 22))      # the platform at its end
	_solid(Rect2(-126, 24, 96, 0.8), 1.1, _stone)   # the parapet on the sea side
	_solid(Rect2(-126, 24, 0.8, 84), 1.1, _stone)
	var lh := _cylinder(_nav, Vector3(-122, 8.0, 114), 3.0, 16.0)
	(lh.get_child(1) as MeshInstance3D).material_override = _whitewash
	var lamp := CylinderMesh.new()
	lamp.top_radius = 1.4
	lamp.bottom_radius = 1.6
	lamp.height = 2.0
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(1.0, 0.9, 0.6)
	glass.emission_enabled = true
	glass.emission = Color(1.0, 0.85, 0.5)
	_mesh(lamp, Vector3(-122, 17.0, 114), glass)
	_solid(Rect2(-136, 120, 7, 6), 3.2, _whitewash)   # the keeper's hut
	for k in 6:
		_cylinder(_nav, Vector3(-120.6, 0.3, 40.0 + k * 12.0), 0.25, 0.6)
		_cylinder(_nav, Vector3(-60.0 + k * 9.0, 0.3, 29.4), 0.25, 0.6)
	for k in 5:
		_boat(Vector3(-100.0 + k * 13.0, -0.6, 48.0 + (k % 2) * 30.0), 0.2 * (k % 3), 8.0, false)
	_flat(Rect2(SEA_X, 30, 8, 80), _floor_mat, 0.03)   # the quay's paving
	for k in 7:
		_cylinder(_nav, Vector3(SEA_X + 0.6, 0.3, 36.0 + k * 11.0), 0.25, 0.6)


## The beach south of the harbour: boats pulled up, net racks.
func _beach() -> void:
	for k in 6:
		_boat(Vector3(-20.0 + _rng.randf_range(-3, 3), 0, 140.0 + k * 16.0), PI * 0.5 + _rng.randf_range(-0.3, 0.3), 6.5, true)
	for k in 4:
		var z := 150.0 + k * 22.0
		for dz: float in [-3.0, 3.0]:
			_solid(Rect2(-6.1, z + dz - 0.1, 0.2, 0.2), 2.0, _wood)
		var bar := BoxMesh.new()
		bar.size = Vector3(0.1, 0.1, 6.4)
		_mesh(bar, Vector3(-6.0, 2.0, z), _wood)
		var net := QuadMesh.new()
		net.size = Vector2(6.0, 1.7)
		_mesh(net, Vector3(-6.0, 1.1, z), _cloth[1], Vector3(0, PI * 0.5, 0))


## The fish market: stalls in rows under awnings by the quay.
func _fish_market() -> void:
	for i in 3:
		for j in 3:
			var x := 10.0 + i * 16.0
			var z := 36.0 + j * 11.0
			if i == 1 and j == 1:
				continue  # the middle stays open (Farid's place)
			_solid(Rect2(x, z, 6, 1.4), 0.9, _wood)
			_awning(Rect2(x - 0.5, z - 1.5, 7, 4.0), 2.7)


## The coffee house (the resupply) with its terrace on the harbour street, the trader beside it.
func _coffee_and_trader() -> void:
	_solid(Rect2(74, 34, 40, 30), 6.5, _whitewash)
	_awning(Rect2(76, 64, 36, 7), 2.9)
	for k in 4:
		_cylinder(_nav, Vector3(80.0 + k * 9.0, 0.4, 67.5), 0.5, 0.8)   # terrace tables
	_solid(Rect2(118, 34, 24, 30), 5.5, _mud[1])
	_awning(Rect2(119, 64, 22, 4), 2.8)
	var door := BoxMesh.new()
	door.size = Vector3(1.6, 2.3, 0.08)
	_mesh(door, Vector3(130, 1.15, 64.05), _blue)


## A small mosque: a walled court, the hall west (toward the sea), a minaret on the street corner.
func _coast_mosque() -> void:
	var r: Rect2 = COAST_DISTRICTS.mosque
	var hall := Rect2(r.position.x, r.position.y + 30.0, r.size.x, r.size.y - 30.0)
	_solid(hall, 7.0, _whitewash)
	var dome := SphereMesh.new()
	dome.radius = 6.0
	dome.height = 6.5
	_mesh(dome, Vector3(hall.get_center().x, 7.0, hall.get_center().y), _whitewash)
	var w := 1.0
	_solid(Rect2(r.position.x, r.position.y, 20, w), 4.5, _whitewash)
	_solid(Rect2(r.position.x + 26.0, r.position.y, r.size.x - 26.0, w), 4.5, _whitewash)   # the gate, north
	_solid(Rect2(r.position.x, r.position.y, w, 30), 4.5, _whitewash)
	_solid(Rect2(r.end.x - w, r.position.y, w, 30), 4.5, _whitewash)
	_solid(Rect2(r.end.x - 5.0, r.position.y + 0.5, 4.5, 4.5), 18.0, _whitewash)   # the minaret


## The boatyard: a hull on stocks, timber stacks, a shed, a low wall round the yard.
func _boatyard() -> void:
	var r: Rect2 = COAST_DISTRICTS.boatyard
	for x: float in [104.0, 112.0, 120.0]:
		_solid(Rect2(x, 116, 1.2, 4.0), 0.9, _wood)                  # the stocks
	var hull := _box(_nav, Vector3(112, 1.9, 118), Vector3(3.2, 2.0, 16.0), _wood)
	hull.rotation.y = PI * 0.5
	_solid(Rect2(150, 94, 34, 18), 6.0, _mud[0])                     # the shed
	for k in 3:
		_solid(Rect2(84.0 + k * 9.0, 96, 6, 2), 1.0 + k * 0.3, _wood)  # timber stacks
	_solid(Rect2(r.position.x, r.end.y - 0.6, r.size.x - 14.0, 0.6), 1.4, _mud[0])
	_solid(Rect2(r.end.x - 0.6, r.position.y + 24.0, 0.6, r.size.y - 24.0), 1.4, _mud[0])


func _palms_and_well() -> void:
	_cylinder(_nav, Vector3(90, 0.5, 190), 1.5, 1.0)
	_solid(Rect2(84, 196, 4.5, 1), 0.6, _mud[0])
	for k in 26:
		var p := Vector2(_rng.randf_range(10, 184), _rng.randf_range(170, 212))
		if p.distance_to(Vector2(90, 192)) < 9.0:
			continue
		_palm(Vector3(p.x, 0, p.y), _rng.randf_range(6.0, 9.5))


## Houses between: north of the market and the coffee house, east along the shore road, south of
## the mosque, either side of the main street (x 64-70) and the lane at z 160-164.
func _coast_houses() -> void:
	_row(Rect2(4, 2, 58, 22), "s")
	_row(Rect2(72, 2, 118, 26), "s")
	_row(Rect2(146, 34, 44, 34), "w")
	_row(Rect2(4, 146, 56, 14), "n")
	_row(Rect2(76, 154, 110, 6), "s", 3.0, 4.5)
	_row(Rect2(186.5, 90, 4, 60), "e", 3.0, 4.5)
