class_name SteamerV2
extends TownV2
## The steamer on the open river (stage 1, gameplan/route_stops_plan.md): Steamer anchored
## mid-stream, the Nile over a bed 4.5 m down (its depth tint and foam), low banks with palms both
## sides. A map to walk the boat's three decks and its rooms; no act uses it yet.
## Placeholders: the steamer's (see Steamer), the banks (boxes), the palms are -f9's Palms.

var boat: Steamer
var water: RiverWater


func _ready() -> void:
	_rng.seed = 1927
	_make_materials()
	_town_materials()
	_nav = NavigationRegion3D.new()
	_nav.navigation_mesh = Level.nav_mesh()
	add_child(_nav)
	_deco = Node3D.new()
	_deco.name = "Deco"
	add_child(_deco)
	_box(_nav, Vector3(0, -5.0, 0), Vector3(400, 1.0, 500), _floor_mat)       # the river's bed
	for s: float in [-1.0, 1.0]:
		_box(_nav, Vector3(s * 110.0, -2.0, 0), Vector3(80, 5.0, 500), _sand)   # the banks, 0.5 m over the water
		for k in 18:
			_palm(Vector3(s * _rng.randf_range(76.0, 140.0), 0.5, _rng.randf_range(-220.0, 220.0)), _rng.randf_range(6.0, 10.0))
	water = RiverWater.make(self, Vector2(400, 500), 0.0, Vector3.ZERO)
	RiverWater.depth(water, 3.0, 0.3)
	boat = Steamer.build(self, Vector3.ZERO, 0.0)
	spots = boat.spots.duplicate()
	player_spawn = spots.foredeck
	_environment()
	_sun.rotation = Vector3(deg_to_rad(-34), deg_to_rad(-60), 0)
	_env.fog_density = 0.003
	NavCache.bake(_nav, "steamer_v2")
	RenderBudget.quiet_minor(_deco)
	if not "--no-merge" in OS.get_cmdline_user_args():
		print("STEAMER v2 merged: deco %d, boat %d draw calls fewer" % [RenderBudget.merge_static(_deco), RenderBudget.merge_static(boat, 24.0, [boat.wheel])])
