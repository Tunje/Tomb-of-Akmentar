class_name MonasteryNight
extends Level
## Act 6's night stop as a map of its own (gameplan/act6_camp_options.md, option A): the ruined
## monastery (Monastery) in a shallow wadi, at night, both return routes' stop (`coast` only
## changes what the act brings: the trucks or the horses). Sand round it, the wadi's low rock sides
## north and south, dunes beyond; the moon low, the fire and lanterns the light. Its navmesh is
## NavCache'd ("monastery_night").
##   var stop := MonasteryNight.new()   # then the act: stop.monastery.anchor, .spots, .ways
## No act uses it yet: act6.gd's hook (spawn points instead of the ring round the fire) goes to -7f.

var monastery: Monastery
var coast := false


func _ready() -> void:
	_make_materials()
	_nav = NavigationRegion3D.new()
	_nav.navigation_mesh = Level.nav_mesh()
	add_child(_nav)
	_box(_nav, Vector3(10, -0.5, 0), Vector3(320, 1.0, 300), _sand)
	# The wadi's sides: low rock ridges north and south, broken; dunes beyond them (meshes).
	var rock := _stone.duplicate() as StandardMaterial3D
	rock.albedo_texture = _noise_tex(Color(0.45, 0.36, 0.27), Color(0.66, 0.54, 0.4), 0.04, false)
	var rng := RandomNumberGenerator.new()
	rng.seed = 6061
	for side: float in [-1.0, 1.0]:
		var x := -120.0
		while x < 140.0:
			var w := rng.randf_range(14.0, 30.0)
			var h := rng.randf_range(4.0, 9.0)
			_box(_nav, Vector3(x + w * 0.5, h * 0.5, side * rng.randf_range(78.0, 92.0)), Vector3(w, h, rng.randf_range(10.0, 18.0)), rock)
			x += w + rng.randf_range(0.0, 12.0)
	for k in 10:
		var dune := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = rng.randf_range(25.0, 45.0)
		sm.height = sm.radius * 2.0
		dune.mesh = sm
		dune.material_override = _sand
		add_child(dune)
		dune.position = Vector3(rng.randf_range(-140, 160), -sm.radius * 0.7, (1.0 if k % 2 == 0 else -1.0) * rng.randf_range(115, 150))
		dune.scale = Vector3(1.6, 0.5, 1.0)
	monastery = Monastery.build(self, Vector3.ZERO, 0.0)
	player_spawn = monastery.spots.gate_out
	_environment()
	_night()
	NavCache.bake(_nav, "monastery_night")


## The moon low in the east, a dark blue sky, little ambient: the fire and lanterns carry it.
func _night() -> void:
	_sun.rotation = Vector3(deg_to_rad(-28), deg_to_rad(-70), 0)
	_sun.light_color = Color(0.55, 0.65, 0.9)
	_sun.light_energy = 0.12
	var sky := _env.sky.sky_material as ProceduralSkyMaterial
	sky.sky_top_color = Color(0.02, 0.03, 0.08)
	sky.sky_horizon_color = Color(0.08, 0.08, 0.14)
	sky.ground_horizon_color = Color(0.06, 0.05, 0.06)
	sky.ground_bottom_color = Color(0.03, 0.03, 0.03)
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.ambient_light_color = Color(0.1, 0.12, 0.2)
	_env.ambient_light_energy = 0.6
	_env.fog_enabled = false
