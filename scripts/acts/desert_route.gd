class_name DesertRoute
extends Level
## Act 3's desert route (Route A, the town branch): a long desert road running north toward the
## town, about 160 x 340 m. The convoy starts at the south end; halfway the road dips through a
## wadi (a dry riverbed crossing the whole map east to west), the ambush spot: rocks on the north
## bank look down on the crossing, more along the flanks, a few in the bed. The town's first
## mud-brick houses stand at the north end. Reuses Level's helpers (_box, _mark_cover, materials,
## sky). Blockout shapes until image-to-3d's rocks and houses arrive.
##   ground_y(z)    height of the ground at z (the wadi's banks and bed)
##   road_x(z)      the road's centre line
##   road_point(z)  a point on the road (on the ground)

const W := 160.0
const L := 340.0
const ROAD_W := 6.0
## The wadi: the south bank slopes down from WADI_S to the bed, the north bank up to WADI_N.
const WADI_N := 188.0
const WADI_S := 214.0
const BANK := 8.0          # how long each bank's slope is (m along z)
const WADI_DEPTH := 3.0
## The convoy starts here (on the road, facing north); the ambush springs when the player reaches
## AMBUSH_Z; past FINISH_Z (mounted, with the ambush on) the convoy has driven through.
const START_Z := 300.0
const AMBUSH_Z := 218.0
const FINISH_Z := 120.0
const TOWN_Z := 30.0

## The coast road (Route C -> town): the sea beyond the west edge, a beach, the wadi running
## out into it. Set before adding to the tree.
var coast := false
var start_point := Vector3.ZERO
## Where the ambush happens: the road in the wadi bed.
var ambush_centre := Vector3.ZERO
## Behind the rocks on the north bank and the west flank: where the hired bandits lie in wait.
var bandit_posts: Array[Vector3] = []
## The Keepers' riders come down the wadi bed from the east: their start and where they get down.
var rider_from := Vector3.ZERO
var rider_to := Vector3.ZERO
var _road_mat: StandardMaterial3D
var _crest: Array[Vector3] = []


func _ready() -> void:
	_make_materials()
	_road_mat = _floor_mat.duplicate()
	_road_mat.albedo_texture = _noise_tex(Color(0.5, 0.4, 0.27), Color(0.64, 0.52, 0.36), 0.04, false)
	_nav = NavigationRegion3D.new()
	var nm := NavigationMesh.new()
	nm.agent_radius = 0.5
	nm.agent_height = 1.75
	nm.agent_max_climb = 0.3
	nm.agent_max_slope = 40.0
	nm.cell_size = 0.25
	nm.cell_height = 0.25
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_collision_mask = 1
	_nav.navigation_mesh = nm
	add_child(_nav)

	_ground()
	_edges()
	_road()
	_rocks()
	_town()
	start_point = road_point(START_Z)
	player_spawn = start_point
	var bed_z := (WADI_N + WADI_S) * 0.5
	ambush_centre = road_point(bed_z)
	rider_from = Vector3(W - 8.0, -WADI_DEPTH, bed_z)
	rider_to = Vector3(road_x(bed_z) + 30.0, -WADI_DEPTH, bed_z)
	if coast:
		_sea()
	_environment()
	_sun.rotation = Vector3(deg_to_rad(-30), deg_to_rad(-120), 0)  # late afternoon, long shadows
	_env.fog_density = 0.003
	_env.fog_light_color = Color(0.8, 0.66, 0.48)
	_nav.bake_navigation_mesh(false)
	Crowd.populate(self, "desert_town")  # villagers, goats and a donkey by the town (-f9's Crowd)


# ---------------------------------------------------------------- the coast

## The Mediterranean to the west: a pale beach falling into the sea past the edge wall.
func _sea() -> void:
	var water := RiverWater.make(self, Vector2(600, L + 600.0), -0.6, Vector3(-312.0, 0, L * 0.5))
	var m := water.material_override as ShaderMaterial
	m.set_shader_parameter("deep", Color(0.06, 0.22, 0.34))
	m.set_shader_parameter("shallow", Color(0.2, 0.46, 0.52))
	m.set_shader_parameter("flow", Vector2(0.3, 0.0))
	var beach := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(30.0, L + 600.0)
	beach.mesh = pm
	var sand := _sand.duplicate() as StandardMaterial3D
	sand.albedo_texture = _noise_tex(Color(0.8, 0.7, 0.52), Color(0.9, 0.82, 0.64), 0.03, false)
	beach.material_override = sand
	add_child(beach)
	beach.position = Vector3(-25.0, -0.9, L * 0.5)
	beach.rotation.z = deg_to_rad(4.5)  # down to the waterline, westward


# ---------------------------------------------------------------- the lie of the land

static func ground_y(z: float) -> float:
	if z <= WADI_N or z >= WADI_S:
		return 0.0
	if z < WADI_N + BANK:
		return -WADI_DEPTH * (z - WADI_N) / BANK
	if z > WADI_S - BANK:
		return -WADI_DEPTH * (WADI_S - z) / BANK
	return -WADI_DEPTH


static func road_x(z: float) -> float:
	return W * 0.5 + 9.0 * sin(z / 40.0) + 4.0 * sin(z / 17.0)


static func road_point(z: float) -> Vector3:
	return Vector3(road_x(z), ground_y(z), z)


## The road's heading at z when travelling north (-Z), flattened.
static func road_dir(z: float) -> Vector3:
	var a := road_point(z + 2.0)
	var b := road_point(z - 2.0)
	return Vector3(b.x - a.x, 0, b.z - a.z).normalized()


## One seamless sheet over the whole map, down the wadi's banks and across its bed (separate
## boxes and tilted slabs left lips at the joins that stopped a horse dead). The wadi runs on past
## the map's sides (no collision out there; the edge walls keep everyone in).
func _ground() -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	_nav.add_child(body)
	var cs := CollisionShape3D.new()
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(_sheet(0.0, W))
	shape.backface_collision = true
	cs.shape = shape
	body.add_child(cs)
	for span in ([[-12.0, 0.0], [0.0, W], [W, W + 300.0]] if coast else [[-300.0, 0.0], [0.0, W], [W, W + 300.0]]):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for v in _sheet(span[0], span[1]):
			st.set_uv(Vector2(v.x, v.z) * 0.1)
			st.add_vertex(v)
		st.generate_normals()
		var mi := MeshInstance3D.new()
		mi.mesh = st.commit()
		mi.material_override = _sand
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF  # flat ground: no self-shadow speckle
		add_child(mi)
	# The bed: grey-brown gravel, a shade darker than the sand, so the wadi reads from afar.
	var gravel := _floor_mat.duplicate() as StandardMaterial3D
	gravel.albedo_texture = _noise_tex(Color(0.3, 0.27, 0.23), Color(0.44, 0.4, 0.34), 0.08, false)
	var bed := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(W + 600.0, WADI_S - WADI_N - BANK * 2.0 + 3.0)
	bed.mesh = pm
	bed.material_override = gravel
	bed.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(bed)
	bed.position = Vector3(W * 0.5, -WADI_DEPTH + 0.02, (WADI_N + WADI_S) * 0.5)
	# Broken stone along both lips, where the flood cut the bank (looks only: nobody trips on it).
	var rng := RandomNumberGenerator.new()
	rng.seed = 88
	for lip in [WADI_N, WADI_S]:
		var x := -40.0
		while x < W + 40.0:
			x += rng.randf_range(1.0, 4.0)
			if absf(x - road_x(lip)) < ROAD_W:
				continue
			var stone := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(rng.randf_range(0.6, 1.8), rng.randf_range(0.25, 0.6), rng.randf_range(0.5, 1.2))
			stone.mesh = bm
			stone.material_override = _stone
			add_child(stone)
			var into := 0.6 if lip == WADI_N else -0.6  # just over the edge, on the slope
			stone.position = Vector3(x, ground_y(lip + into) - 0.08, lip + into + rng.randf_range(-0.3, 0.3))
			stone.rotation = Vector3(rng.randf_range(-0.3, 0.3), rng.randf() * PI, rng.randf_range(-0.2, 0.2))


## The ground's triangles between x0 and x1 (facing up), following ground_y's breaks.
func _sheet(x0: float, x1: float) -> PackedVector3Array:
	var zs := [0.0, WADI_N, WADI_N + BANK, WADI_S - BANK, WADI_S, L]
	var out := PackedVector3Array()
	for i in zs.size() - 1:
		var za: float = zs[i]
		var zb: float = zs[i + 1]
		var a0 := Vector3(x0, ground_y(za), za)
		var a1 := Vector3(x1, ground_y(za), za)
		var b0 := Vector3(x0, ground_y(zb), zb)
		var b1 := Vector3(x1, ground_y(zb), zb)
		out.append_array([a0, a1, b0, a1, b1, b0])  # clockwise from above: Godot's front face
	return out


func _edges() -> void:
	for e in [
		[Vector3(-0.5, 3, L * 0.5), Vector3(1, 12, L)], [Vector3(W + 0.5, 3, L * 0.5), Vector3(1, 12, L)],
		[Vector3(W * 0.5, 3, -0.5), Vector3(W, 12, 1)], [Vector3(W * 0.5, 3, L + 0.5), Vector3(W, 12, 1)],
	]:
		var b := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = e[1]
		cs.shape = bs
		b.add_child(cs)
		add_child(b)
		b.position = e[0]
	# Sand to the horizon and dunes beyond the edges (the wadi runs on out of sight between them).
	for z in [-200.0, L + 200.0]:
		var far := MeshInstance3D.new()
		var plane := PlaneMesh.new()
		plane.size = Vector2(W + 600.0, 400.0)
		far.mesh = plane
		far.material_override = _sand
		add_child(far)
		far.position = Vector3(W * 0.5, -0.03, z)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3301
	for side in ([1.0] if coast else [-1.0, 1.0]):  # no dunes in the sea
		for i in 22:
			var z := -60.0 + i * (L + 120.0) / 21.0 + rng.randf_range(-8, 8)
			if z > WADI_N - 14.0 and z < WADI_S + 14.0:
				continue  # leave the wadi's mouth open
			var radius := rng.randf_range(14, 26)
			var dune := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = radius
			sm.height = radius * 2.0
			dune.mesh = sm
			dune.material_override = _sand
			add_child(dune)
			var x: float = W * 0.5 + side * (W * 0.5 + radius * 1.1 + rng.randf_range(2, 20))
			dune.position = Vector3(x, -radius * 0.2, z)
			dune.scale = Vector3(1.5, rng.randf_range(0.3, 0.5), 1.9)
	# North, past the town, and south behind the start: long low dunes.
	for z in [-70.0, L + 70.0]:
		for i in 6:
			var dune := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = 30.0
			sm.height = 60.0
			dune.mesh = sm
			dune.material_override = _sand
			add_child(dune)
			dune.position = Vector3(-60.0 + i * 56.0 + rng.randf_range(-10, 10), -8.0, z + rng.randf_range(-15, 15))
			dune.scale = Vector3(1.6, 0.4, 1.0)


## The road: a packed-dirt strip on the ground (no collision of its own), down through the wadi.
func _road() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var zs: Array[float] = []
	var z := 0.0
	while z < L:
		zs.append(z)
		z += 2.0
	zs.append_array([WADI_N, WADI_N + BANK, WADI_S - BANK, WADI_S, L])
	zs.sort()
	for k in zs.size() - 1:
		if zs[k + 1] - zs[k] < 0.01:
			continue
		var quad := []
		for zz in [zs[k], zs[k + 1]]:
			var c := road_point(zz)
			var side := road_dir(zz).cross(Vector3.UP).normalized() * ROAD_W * 0.5
			for v: Vector3 in [c - side, c + side]:  # each edge on the ground under it (banks)
				quad.append(Vector3(v.x, ground_y(v.z) + 0.03, v.z))
		for i in [0, 1, 2, 1, 3, 2]:
			st.set_normal(Vector3.UP)
			st.set_uv(Vector2((quad[i] as Vector3).x, (quad[i] as Vector3).z) * 0.1)
			st.add_vertex(quad[i])
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _road_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


# ---------------------------------------------------------------- rocks (cover)

func _rocks() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1926
	# The ambush: the north bank's crest (the bandits' posts), the flanks, the bed, and the south
	# approach where the convoy is when it starts (the player's first cover).
	var bed := (WADI_N + WADI_S) * 0.5
	for spec in [
		# [count, z min, z max, x off min, x off max (from the road, either side), tall share]
		[10, WADI_N - 12.0, WADI_N - 3.0, 5.0, 30.0, 0.3],
		[6, WADI_N - 30.0, WADI_N - 12.0, 8.0, 34.0, 0.4],
		[5, bed - 2.5, bed + 2.5, 6.0, 26.0, 0.2],
		[8, WADI_S + 3.0, WADI_S + 24.0, 5.5, 18.0, 0.25],
		[14, WADI_S + 30.0, L - 10.0, 6.0, 50.0, 0.4],
		[12, TOWN_Z + 20.0, WADI_N - 32.0, 6.0, 50.0, 0.4],
	]:
		for i in int(spec[0]):
			var z := rng.randf_range(spec[1], spec[2])
			var off := rng.randf_range(spec[3], spec[4]) * (1.0 if rng.randf() < 0.5 else -1.0)
			var tall: bool = rng.randf() < float(spec[5])
			var size := Vector3(rng.randf_range(1.4, 2.4), rng.randf_range(2.2, 3.2), rng.randf_range(1.4, 2.2)) if tall \
				else Vector3(rng.randf_range(1.6, 3.6), rng.randf_range(0.95, 1.2), rng.randf_range(0.8, 1.4))
			_rock(Vector3(road_x(z) + off, 0, z), size, rng.randf() * PI, spec[2] <= WADI_N - 3.0 and spec[1] >= WADI_N - 12.0)
	# The posts: a step behind (north of) the crest rocks.
	for c in _crest:
		bandit_posts.append(Vector3(c.x, 0, c.z - 2.0))


func _rock(at: Vector3, size: Vector3, yaw: float, crest: bool) -> void:
	var y := ground_y(at.z)
	var body := _box(_nav, Vector3(at.x, y + size.y * 0.5 - 0.05, at.z), size, _stone)
	body.rotation.y = yaw
	_mark_cover(body, size)
	if crest:
		_crest.append(Vector3(at.x, y, at.z))


# ---------------------------------------------------------------- the town (the goal)

func _town() -> void:
	var brick := _floor_mat.duplicate() as StandardMaterial3D
	brick.albedo_texture = _noise_tex(Color(0.58, 0.45, 0.32), Color(0.72, 0.6, 0.44), 0.06, false)
	var rng := RandomNumberGenerator.new()
	rng.seed = 512
	for i in 9:
		var side := -1.0 if i % 2 == 0 else 1.0
		var z := TOWN_Z - 14.0 + i * 3.2 + rng.randf_range(-1, 1)
		var size := Vector3(rng.randf_range(5, 8), rng.randf_range(3, 4.5), rng.randf_range(5, 7))
		var x := road_x(z) + side * (ROAD_W * 0.5 + 2.5 + size.x * 0.5 + rng.randf_range(0, 3))
		_box(_nav, Vector3(x, size.y * 0.5, z), size, brick)
	# A well at the town's edge.
	_cylinder(_nav, road_point(TOWN_Z + 10.0) + Vector3(-7.0, 0.5, 0), 1.0, 1.0)
