class_name CoastRoad
extends Level
## Act 8's coast road for the chariot chase: a long, gently winding track north along the shore,
## about 1.4 km. The sea lies west past a strip of beach, rocks and dunes rise to the east; the
## road runs from START (z 0) north (-Z) to a coastguard fort's gate at FINISH. Room to drive
## flat out, swerve and ram. Reuses Level's helpers (_box, materials, sky). Blockout shapes.
##   road_x(z)      the road's centre line
##   road_point(z)  a point on the road
##   road_dir(z)    the way north along it

const LENGTH := 1400.0
const START_Z := 0.0
const FINISH_Z := -LENGTH + 40.0
const ROAD_W := 8.0
const SEA_X := -46.0        # the waterline
const EAST_X := 70.0        # the inland edge

var _road_mat: StandardMaterial3D
var _water: StandardMaterial3D


static func road_x(z: float) -> float:
	return 10.0 * sin(z / 110.0) + 4.0 * sin(z / 37.0)


static func road_point(z: float) -> Vector3:
	return Vector3(road_x(z), 0.0, z)


static func road_dir(z: float) -> Vector3:
	return (road_point(z - 2.0) - road_point(z + 2.0)).normalized()


func _ready() -> void:
	_make_materials()
	_road_mat = _floor_mat.duplicate()
	_road_mat.albedo_texture = _noise_tex(Color(0.5, 0.42, 0.3), Color(0.62, 0.52, 0.38), 0.05, false)
	_water = StandardMaterial3D.new()
	_water.albedo_color = Color(0.12, 0.3, 0.36)
	_water.roughness = 0.1
	_water.metallic = 0.3
	_nav = NavigationRegion3D.new()  # nothing walks here: the navmesh is never baked
	add_child(_nav)
	var z0 := START_Z + 40.0
	var z1 := -LENGTH - 40.0
	_box(_nav, Vector3((SEA_X + EAST_X) * 0.5, -0.5, (z0 + z1) * 0.5), Vector3(EAST_X - SEA_X, 1.0, z0 - z1), _sand)
	_sea(z0, z1)
	_road(z0, z1)
	_rocks()
	_fort()
	_edges(z0, z1)
	player_spawn = road_point(START_Z - 6.0)
	_environment()


func _sea(z0: float, z1: float) -> void:
	var sea := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(600, z0 - z1 + 600)
	sea.mesh = pm
	sea.material_override = _water
	add_child(sea)
	sea.position = Vector3(SEA_X - 300.0, -0.6, (z0 + z1) * 0.5)
	# The wet sand at the waterline, and the dune ridge inland beyond the edge.
	var wet := MeshInstance3D.new()
	var wm := PlaneMesh.new()
	wm.size = Vector2(6, z0 - z1)
	wet.mesh = wm
	var wmat := _sand.duplicate() as StandardMaterial3D
	wmat.albedo_texture = _noise_tex(Color(0.5, 0.42, 0.3), Color(0.6, 0.5, 0.36), 0.02, false)
	wet.material_override = wmat
	add_child(wet)
	wet.position = Vector3(SEA_X + 3.0, 0.01, (z0 + z1) * 0.5)
	var rng := RandomNumberGenerator.new()
	rng.seed = 707
	for i in 40:
		var z := lerpf(z0, z1, (i + rng.randf()) / 40.0)
		var radius := rng.randf_range(10, 22)
		var dune := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = radius
		sm.height = radius * 2.0
		dune.mesh = sm
		dune.material_override = _sand
		add_child(dune)
		dune.position = Vector3(EAST_X + radius * 1.2 + rng.randf_range(0, 20), -radius * 0.2, z)
		dune.scale = Vector3(1.4, 0.45, 1.6)


## The road: a packed-earth band (meshes, every 8 m) with marker stones every 100 m.
func _road(z0: float, z1: float) -> void:
	var z := z0
	while z > z1:
		var a := road_point(z)
		var b := road_point(z - 8.0)
		var seg := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(ROAD_W, 0.04, a.distance_to(b) + 0.4)
		seg.mesh = bm
		seg.material_override = _road_mat
		add_child(seg)
		seg.position = (a + b) * 0.5 + Vector3.UP * 0.01
		seg.look_at(b + Vector3.UP * 0.01, Vector3.UP)
		seg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		z -= 8.0
	for k in int(LENGTH / 100.0):
		var p := road_point(START_Z - k * 100.0) + Vector3(ROAD_W * 0.5 + 1.2, 0, 0)
		_box(_nav, p + Vector3.UP * 0.4, Vector3(0.4, 0.8, 0.4), _stone)


## Rocks and ruined walls inland, a few on the beach; never on the road.
func _rocks() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1931
	for i in 160:
		var z := rng.randf_range(START_Z - 10.0, -LENGTH)
		var inland := rng.randf() < 0.75
		var off := rng.randf_range(ROAD_W * 0.5 + 4.0, 55.0) if inland else -rng.randf_range(ROAD_W * 0.5 + 5.0, 32.0)
		var p := road_point(z) + Vector3(off, 0, 0)
		if p.x < SEA_X + 4.0 or p.x > EAST_X - 3.0:
			continue
		var size := Vector3(rng.randf_range(1.5, 5.0), rng.randf_range(0.8, 3.5), rng.randf_range(1.5, 5.0))
		var rock := _box(_nav, p + Vector3.UP * size.y * 0.45, size, _stone)
		rock.rotation = Vector3(rng.randf_range(-0.15, 0.15), rng.randf() * TAU, rng.randf_range(-0.15, 0.15))
	# Palms by the beach now and then.
	for i in 24:
		var z := rng.randf_range(START_Z, -LENGTH)
		var p := road_point(z) + Vector3(-rng.randf_range(8.0, 20.0), 0, 0)
		var trunk := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.16
		cm.bottom_radius = 0.25
		cm.height = 7.0
		trunk.mesh = cm
		var wood := StandardMaterial3D.new()
		wood.albedo_color = Color(0.33, 0.22, 0.13)
		trunk.material_override = wood
		add_child(trunk)
		trunk.position = p + Vector3.UP * 3.5
		trunk.rotation.z = rng.randf_range(-0.12, 0.12)
		var leaf := StandardMaterial3D.new()
		leaf.albedo_color = Color(0.22, 0.36, 0.14)
		leaf.cull_mode = BaseMaterial3D.CULL_DISABLED
		for k in 8:
			var a := TAU * k / 8.0
			var frond := MeshInstance3D.new()
			var fm := BoxMesh.new()
			fm.size = Vector3(0.45, 0.02, 2.8)
			frond.mesh = fm
			frond.material_override = leaf
			add_child(frond)
			frond.rotation_order = EULER_ORDER_YXZ
			frond.rotation = Vector3(-0.45, a, 0)
			frond.position = p + Vector3(sin(a) * 1.2, 6.7, cos(a) * 1.2)


## The coastguard fort at the end of the road: walls either side and the open gate.
func _fort() -> void:
	var p := road_point(FINISH_Z - 20.0)
	for side in [-1.0, 1.0]:
		_box(_nav, p + Vector3(side * 14.0, 3.5, 0), Vector3(20.0, 7.0, 3.0), _stone)
		_box(_nav, p + Vector3(side * 5.5, 5.0, 0), Vector3(3.0, 10.0, 4.0), _stone)
	_box(_nav, p + Vector3(0, 8.8, 0), Vector3(8.0, 2.4, 3.6), _floor_mat)
	var flag := MeshInstance3D.new()
	var fm := BoxMesh.new()
	fm.size = Vector3(1.6, 1.0, 0.04)
	flag.mesh = fm
	var red := StandardMaterial3D.new()
	red.albedo_color = Color(0.6, 0.15, 0.12)
	flag.material_override = red
	add_child(flag)
	flag.position = p + Vector3(-5.5, 11.5, 0)


func _edges(z0: float, z1: float) -> void:
	for e in [
		[Vector3(SEA_X + 1.0, 5, (z0 + z1) * 0.5), Vector3(1, 10, z0 - z1)],
		[Vector3(EAST_X, 5, (z0 + z1) * 0.5), Vector3(1, 10, z0 - z1)],
		[Vector3((SEA_X + EAST_X) * 0.5, 5, z0), Vector3(EAST_X - SEA_X, 10, 1)],
		[Vector3((SEA_X + EAST_X) * 0.5, 5, z1), Vector3(EAST_X - SEA_X, 10, 1)],
	]:
		var b := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = e[1]
		cs.shape = bs
		b.add_child(cs)
		add_child(b)
		b.position = e[0]


## 0 = day, 1 = dusk: the chase runs in the evening, the sun low over the sea.
func set_dusk(f: float) -> void:
	_sun.light_energy = lerpf(1.6, 0.9, f)
	_sun.light_color = Color(1.0, 0.9, 0.75).lerp(Color(1.0, 0.55, 0.3), f)
	_sun.rotation = Vector3(deg_to_rad(lerpf(-38, -10, f)), deg_to_rad(lerpf(-140, -80, f)), 0)  # low in the west
	var sky := _env.sky.sky_material as ProceduralSkyMaterial
	sky.sky_top_color = Color(0.32, 0.5, 0.75).lerp(Color(0.25, 0.25, 0.45), f)
	sky.sky_horizon_color = Color(0.85, 0.75, 0.6).lerp(Color(0.95, 0.55, 0.35), f)
