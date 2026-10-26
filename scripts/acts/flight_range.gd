class_name FlightRange
extends Level
## Act 8's flight: a desert airstrip outside Cairo and the open desert south of it, for flying over
## (about 5 km of it along -Z, dunes and rock outcrops, no collision beyond the strip). Cairo's
## minarets stand on the northern horizon behind the strip. Blockout shapes.
##   STRIP_START / STRIP_END   the runway, north to south
##   set_dusk(f)               0 late afternoon .. 1 dusk

const STRIP_START := Vector3(0, 0, 0)
const STRIP_END := Vector3(0, 0, -420)
const LENGTH := 5200.0

var _strip_mat: StandardMaterial3D


func _ready() -> void:
	_make_materials()
	_nav = NavigationRegion3D.new()  # nobody walks far here: never baked
	add_child(_nav)
	# Solid ground round the strip (people stand here), sand to the horizon beyond.
	_box(_nav, Vector3(0, -0.5, -150), Vector3(300, 1.0, 600), _sand)
	var far := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(4000, LENGTH + 2000)
	far.mesh = pm
	far.material_override = _sand
	add_child(far)
	far.position = Vector3(0, -0.02, -LENGTH * 0.5)
	_strip()
	_dunes()
	_cairo_horizon()
	player_spawn = STRIP_START + Vector3(4, 0, 6)
	_environment()
	set_dusk(0.0)


func _strip() -> void:
	_strip_mat = _floor_mat.duplicate()
	_strip_mat.albedo_texture = _noise_tex(Color(0.52, 0.43, 0.3), Color(0.62, 0.52, 0.37), 0.04, false)
	var strip := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(18, 0.04, STRIP_START.z - STRIP_END.z)
	strip.mesh = bm
	strip.material_override = _strip_mat
	add_child(strip)
	strip.position = (STRIP_START + STRIP_END) * 0.5 + Vector3.UP * 0.02
	# Whitewashed stones along both edges, every 30 m.
	var white := StandardMaterial3D.new()
	white.albedo_color = Color(0.92, 0.9, 0.84)
	var z := STRIP_START.z
	while z > STRIP_END.z:
		for s in [-1.0, 1.0]:
			_box(_nav, Vector3(s * 10.0, 0.15, z), Vector3(0.6, 0.3, 0.5), white)
		z -= 30.0
	# A canvas hangar, fuel drums, the windsock on its pole.
	var tent := _box(_nav, Vector3(-22, 2.0, 8), Vector3(10, 4.0, 8), _floor_mat)
	_dress(tent, "prop_tent.glb", Vector3(2.5, 1.17, 1.53))
	var drum := StandardMaterial3D.new()
	drum.albedo_color = Color(0.3, 0.32, 0.25)
	for k in 5:
		var d := _cylinder(_nav, Vector3(-14.0 + (k % 3) * 0.8, 0.45, 12.0 + (k / 3) * 0.8), 0.32, 0.9)
		(d.get_child(1) as MeshInstance3D).material_override = drum
	var pole := _cylinder(_nav, Vector3(14, 3.0, -6), 0.06, 6.0)
	(pole.get_child(1) as MeshInstance3D).material_override = drum
	var sock := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.12
	cm.bottom_radius = 0.3
	cm.height = 1.6
	sock.mesh = cm
	var orange := StandardMaterial3D.new()
	orange.albedo_color = Color(0.9, 0.45, 0.15)
	sock.material_override = orange
	add_child(sock)
	sock.position = Vector3(14.7, 5.7, -6)
	sock.rotation = Vector3(0, 0, PI * 0.5 - 0.25)


## Dunes and the odd rock outcrop along the way (meshes only).
func _dunes() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1927
	for i in 220:
		var p := Vector3(rng.randf_range(-1500, 1500), 0, rng.randf_range(-LENGTH, 400))
		if absf(p.x) < 60 and p.z > STRIP_END.z - 40:
			continue  # not on the strip
		var r := rng.randf_range(20, 70)
		var dune := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = r
		sm.height = r * 2.0
		dune.mesh = sm
		dune.material_override = _sand
		add_child(dune)
		dune.position = p + Vector3.DOWN * r * 0.75
		dune.scale = Vector3(1.6, 0.6, 1.0)
		dune.rotation.y = rng.randf() * TAU
		if i % 9 == 0:
			var rock := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(rng.randf_range(10, 30), rng.randf_range(8, 25), rng.randf_range(10, 30))
			rock.mesh = bm
			rock.material_override = _stone
			add_child(rock)
			rock.position = p + Vector3(r * 0.8, bm.size.y * 0.4, 0)
			rock.rotation = Vector3(rng.randf_range(-0.1, 0.1), rng.randf() * TAU, rng.randf_range(-0.1, 0.1))


## Cairo on the northern horizon: low blocks and a few minarets.
func _cairo_horizon() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 30
	var plaster := StandardMaterial3D.new()
	plaster.albedo_color = Color(0.78, 0.7, 0.56)
	for i in 40:
		var p := Vector3(rng.randf_range(-700, 700), 0, rng.randf_range(600, 900))
		var h := rng.randf_range(8, 25)
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(rng.randf_range(20, 60), h, rng.randf_range(20, 50))
		mi.mesh = bm
		mi.material_override = plaster
		add_child(mi)
		mi.position = p + Vector3.UP * h * 0.5
	for i in 6:
		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 1.2
		cm.bottom_radius = 2.0
		cm.height = rng.randf_range(35, 55)
		mi.mesh = cm
		mi.material_override = plaster
		add_child(mi)
		mi.position = Vector3(rng.randf_range(-500, 500), cm.height * 0.5, rng.randf_range(620, 820))


## 0 = late afternoon, 1 = dusk: the sun low ahead to the west, the sky reddening.
func set_dusk(f: float) -> void:
	if _sun == null:
		return
	_sun.light_energy = lerpf(1.5, 0.75, f)
	_sun.light_color = Color(1.0, 0.85, 0.65).lerp(Color(1.0, 0.5, 0.28), f)
	_sun.rotation = Vector3(deg_to_rad(lerpf(-30, -7, f)), deg_to_rad(-60), 0)
	_env.ambient_light_energy = lerpf(0.55, 0.38, f)
	var sky := _env.sky.sky_material as ProceduralSkyMaterial
	sky.sky_top_color = Color(0.34, 0.5, 0.75).lerp(Color(0.24, 0.24, 0.45), f)
	sky.sky_horizon_color = Color(0.88, 0.76, 0.6).lerp(Color(0.95, 0.52, 0.32), f)
	sky.ground_horizon_color = Color(0.8, 0.68, 0.5).lerp(Color(0.55, 0.38, 0.28), f)
	_env.fog_light_color = Color(0.8, 0.68, 0.5).lerp(Color(0.7, 0.45, 0.32), f)
	_env.fog_density = 0.0015
