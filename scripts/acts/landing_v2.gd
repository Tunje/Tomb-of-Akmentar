class_name LandingV2
extends TownV2
## The village landing on the river (stage 1, gameplan/route_stops_plan.md; Simon: a real stop, a
## story beat and a market): the steamer (Steamer) moored at a landing stage on the east bank, a
## mud-brick village up from it, about 160 x 200 m. North is -z; the river runs along the west.
##   the landing stage: a timber quay, the steamer's starboard gangway onto it
##   the riverfront: a path along the bank, shadoofs lifting water, boats pulled up
##   the market under the sycamore, stalls round it (the market)
##   the headman's house (the omda's) on the square: his bench outside, the story beat's place
##   a small mosque, houses on lanes, the fields and palms behind, a channel from the river
## No act uses it yet. Its people and animals: crowd/landing.json (villagers, the market, the
## water, the fields; water buffalo, donkeys, goats).
## Placeholders (blockout until models come): the houses, the mosque and minaret, the omda's house,
## the quay, the shadoofs (a post and a beam), the boats (boxes), the stalls and awnings, the
## sycamore (a trunk and a crown), the field beds and the channel; the palms are -f9's Palms; the
## buffalo are HorseRigs (no model); the steamer's own (see Steamer).

const WATER_Y := -1.25  # (the steamer's deck, 1.25 m over it, level with the bank)
const SPOTS_LANDING := {
	"landing_stage": Vector3(-2.0, 0, -14.5), "riverfront": Vector3(9, 0, 40), "shadoof": Vector3(9, 0, 52),
	"market": Vector3(30, 0, -26), "sycamore": Vector3(34, 0, -15), "omda": Vector3(66, 0, -21),
	"mosque": Vector3(81, 0, 6), "lane": Vector3(64, 0, 40), "fields": Vector3(140, 0, 10),
	"village_north": Vector3(64, 0, -88),
}
const MARKET := Rect2(16, -42, 44, 36)

var boat: Steamer
var _wood_mat: StandardMaterial3D


func _ready() -> void:
	_rng.seed = 1928
	_make_materials()
	_town_materials()
	_wood_mat = StandardMaterial3D.new()
	_wood_mat.albedo_color = Color(0.38, 0.26, 0.15)
	_nav = NavigationRegion3D.new()
	_nav.navigation_mesh = Level.nav_mesh()
	add_child(_nav)
	_deco = Node3D.new()
	_deco.name = "Deco"
	add_child(_deco)
	_box(_nav, Vector3(100, -2.5, 0), Vector3(200, 5.0, 320), _sand)          # the land, its bank at x 0
	_box(_nav, Vector3(-110, -5.0, 0), Vector3(220, 1.0, 320), _floor_mat)    # the river's bed
	_box(_nav, Vector3(-190, -2.5, 0), Vector3(60, 5.0, 320), _sand)          # the far bank
	var water := RiverWater.make(self, Vector2(220, 320), WATER_Y, Vector3(-110, 0, 0))
	RiverWater.depth(water, 3.0, 0.3)
	boat = Steamer.build(self, Vector3(-10.0, WATER_Y, 0), 0.0)   # its deck level with the bank
	_quay()
	_riverfront()
	_market()
	_omda()
	_village_mosque()
	_village_houses()
	_fields()
	for id: String in SPOTS_LANDING:
		spots[id] = SPOTS_LANDING[id]
	for id: String in boat.spots:
		spots["boat_" + id] = boat.spots[id]
	player_spawn = boat.spots.gangway_starboard
	_environment()
	_sun.rotation = Vector3(deg_to_rad(-30), deg_to_rad(-110), 0)   # afternoon, from over the river
	_env.fog_density = 0.0025
	NavCache.bake(_nav, "landing_v2")
	RenderBudget.quiet_minor(_deco)
	if not "--no-merge" in OS.get_cmdline_user_args():
		print("LANDING v2 merged: deco %d, boat %d draw calls fewer" % [RenderBudget.merge_static(_deco), RenderBudget.merge_static(boat)])
	if not "--no-crowd" in OS.get_cmdline_user_args():
		Crowd.populate(self, "landing")


## The landing stage: a timber quay along the bank, its deck level with the steamer's, on piles.
func _quay() -> void:
	_solid(Rect2(-4.5, -26, 4.6, 24), 0.4, _wood_mat, -0.4)
	for z in [-25, -21, -9, -5]:   # (none by the gangway, z -16..-13)
		var pile := _cylinder(_nav, Vector3(-4.2, WATER_Y - 0.5, z), 0.18, 1.4)
		(pile.get_child(1) as MeshInstance3D).material_override = _wood_mat
		_cylinder(_nav, Vector3(-3.9, 0.3, z), 0.16, 0.6)   # bollards
	spots.boat_moored = boat.spots.gangway_starboard


## The riverfront: a path along the bank, shadoofs at the water, boats pulled up on the mud.
func _riverfront() -> void:
	_flat(Rect2(0, -110, 12, 220), _floor_mat, 0.02)
	for z: float in [30.0, 52.0, -62.0]:
		var post := _cylinder(_nav, Vector3(4.0, 1.5, z), 0.15, 3.0)
		(post.get_child(1) as MeshInstance3D).material_override = _wood_mat
		var beam := BoxMesh.new()
		beam.size = Vector3(5.5, 0.12, 0.12)
		_mesh(beam, Vector3(3.2, 3.0, z), _wood_mat, Vector3(0, 0, 0.35))
		_solid(Rect2(6.0, z - 1.0, 1.2, 2.0), 0.7, _mud[0])   # its stone counterweight's stand
	for k in 3:
		var bm := BoxMesh.new()
		bm.size = Vector3(1.6, 0.7, 5.5)
		_mesh(bm, Vector3(-1.5, WATER_Y + 0.6, 66.0 + k * 9.0), _wood_mat, Vector3(0, 0.2 * k, 0.1))


## The market under the sycamore: the great tree in the middle, stalls round it under awnings.
func _market() -> void:
	_tree(Vector3(36, 0, -22), 7.5, 7.0, 0.9)
	for k in 8:
		var a := TAU * k / 8.0
		var p := Vector2(36, -22) + Vector2(cos(a), sin(a)) * 14.0
		if absf(p.y + 22.0) < 4.0 and p.x < 36.0:
			continue  # the way in from the landing stays open
		_solid(Rect2(p.x - 1.5, p.y - 0.7, 3.0, 1.4), 0.9, _wood_mat)
		_awning(Rect2(p.x - 2.0, p.y - 1.8, 4.0, 3.6), 2.6)
	_flat(Rect2(12, -16, 14, 3), _floor_mat, 0.02)   # the way up from the quay


## The headman's house (the omda's): whitewashed, two storeys, a bench by its door on the square.
func _omda() -> void:
	_solid(Rect2(70, -32, 20, 20), 7.0, _whitewash)
	var door := BoxMesh.new()
	door.size = Vector3(0.1, 2.4, 1.4)
	_mesh(door, Vector3(69.94, 1.2, -22), _wood_mat)
	var bench := BoxMesh.new()   # (dressing only: the crowd's man sits on it)
	bench.size = Vector3(0.8, 0.45, 2.6)
	_mesh(bench, Vector3(68.8, 0.22, -24.7), _wood_mat)
	interactables["omda"] = Interactable.make(self, Vector3(67.0, 0.9, -22.0), "The headman's house", "omda", 1.2)


## A small mosque: a walled court, the hall, a minaret on the lane.
func _village_mosque() -> void:
	var r := Rect2(70, 10, 24, 24)
	_solid(Rect2(r.position.x, r.position.y + 12, r.size.x, 12), 6.0, _whitewash)
	_solid(Rect2(r.position.x, r.position.y, 9, 1), 3.5, _whitewash)
	_solid(Rect2(r.position.x + 15, r.position.y, 9, 1), 3.5, _whitewash)
	_solid(Rect2(r.position.x, r.position.y, 1, 12), 3.5, _whitewash)
	_solid(Rect2(r.end.x - 1, r.position.y, 1, 12), 3.5, _whitewash)
	_solid(Rect2(r.end.x - 4, r.position.y - 0.5, 4, 4), 15.0, _whitewash)
	var dome := SphereMesh.new()
	dome.radius = 4.0
	dome.height = 4.5
	_mesh(dome, Vector3(r.get_center().x, 6.0, r.position.y + 18), _whitewash)


## Houses on lanes: the north end, round the square, and south of the mosque.
func _village_houses() -> void:
	_block(Rect2(16, -100, 44, 26), 3.5, 6.0)
	_block(Rect2(70, -100, 40, 26), 3.5, 6.0)
	_block(Rect2(16, -66, 44, 18), 3.5, 5.5)
	_block(Rect2(70, -66, 40, 28), 3.5, 6.0)
	_block(Rect2(96, -32, 14, 36), 3.5, 5.5)
	_block(Rect2(16, 4, 44, 24), 3.5, 5.5)
	_block(Rect2(16, 46, 40, 24), 3.5, 5.5)
	_block(Rect2(70, 46, 40, 26), 3.5, 6.0)
	_block(Rect2(16, 82, 40, 24), 3.0, 5.0)


## The fields behind the village: beds of green either side of a channel, palms along it.
func _fields() -> void:
	_flat(Rect2(118, -2, 70, 2), _water, 0.04)
	for z in range(-100, 100, 24):
		for x in range(122, 186, 22):
			_flat(Rect2(x, z + 2, 18, 18), _green, 0.03)
	for k in 30:
		_palm(Vector3(_rng.randf_range(116.0, 190.0), 0, _rng.randf_range(-110.0, 110.0)), _rng.randf_range(6.0, 10.0))
