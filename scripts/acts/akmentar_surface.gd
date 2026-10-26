class_name AkmentarSurface
extends Level
## Act 4's map: the surface ruins of Akmentar, about 140 x 140 m of desert. The 12 investigation
## sites stand in a ruined temple court in the middle; three expedition camps lie to the south
## (ours in the middle, the Americans west, the Germans east); the sealed tomb door is in the
## north wall. Reuses Level's building helpers (_box, _flame, _mark_cover, materials, sky).
## Blockout shapes until image-to-3d's statues and camp props arrive.

const SIZE := 140.0
const C := Vector3(70.0, 0.0, 70.0)  # the court's centre

## Where each site's landmark stands (the inspect spot is 1.4 m in front of it, toward the camps).
const SITES := {
	"anubis": Vector3(55, 0, 42), "horus": Vector3(70, 0, 38), "ra": Vector3(85, 0, 42),
	"scarabs": Vector3(42, 0, 62), "hieroglyphs": Vector3(98, 0, 62),
	"greetings": Vector3(56, 0, 80), "mummification": Vector3(84, 0, 80), "souls": Vector3(70, 0, 66),
	"obelisk": Vector3(36, 0, 44), "offering": Vector3(104, 0, 44),
	"storeroom": Vector3(40, 0, 86), "astronomer": Vector3(100, 0, 86),
}
## Camp centres: ours, then the rivals'.
const CAMPS := {"party": Vector3(70, 0, 118), "americans": Vector3(36, 0, 112), "germans": Vector3(104, 0, 112)}

var camps := CAMPS
var site_spots := {}  # site id -> SiteSpot
var tomb_door: Vector3
var _night := 0.0


func _ready() -> void:
	_make_materials()
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

	_box(_nav, Vector3(SIZE * 0.5, -0.5, SIZE * 0.5), Vector3(SIZE, 1.0, SIZE), _sand)
	_edges()
	_temple()
	for id in SITES:
		_site_landmark(id, SITES[id])
	for id in CAMPS:
		_expedition_camp(id, CAMPS[id])
	_scatter()
	player_spawn = CAMPS.party + Vector3(0, 0, 4)
	_environment()
	_nav.bake_navigation_mesh(false)


## Inspect spots go in after the map (they need the tree): main calls this.
func place_sites() -> void:
	for id in SITES:
		var p: Vector3 = SITES[id]
		var toward := (CAMPS.party - p)
		toward.y = 0
		site_spots[id] = SiteSpot.make(self, "akmentar_surface", id, p + toward.normalized() * 1.6)


# ---------------------------------------------------------------- the ruins

func _edges() -> void:
	for e in [
		[Vector3(-0.5, 5, SIZE * 0.5), Vector3(1, 10, SIZE)], [Vector3(SIZE + 0.5, 5, SIZE * 0.5), Vector3(1, 10, SIZE)],
		[Vector3(SIZE * 0.5, 5, -0.5), Vector3(SIZE, 10, 1)], [Vector3(SIZE * 0.5, 5, SIZE + 0.5), Vector3(SIZE, 10, 1)],
	]:
		var b := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = e[1]
		cs.shape = bs
		b.add_child(cs)
		add_child(b)
		b.position = e[0]
	# Far sand and dunes beyond the edges.
	var far := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(700, 700)
	far.mesh = plane
	far.material_override = _sand
	add_child(far)
	far.position = Vector3(SIZE * 0.5, -0.03, SIZE * 0.5)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4019
	for i in 40:
		var a := TAU * i / 40.0
		var radius := rng.randf_range(10, 20)
		var dune := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = radius
		sm.height = radius * 2.0
		dune.mesh = sm
		dune.material_override = _sand
		add_child(dune)
		var out := SIZE * 0.5 + radius * 1.6 + rng.randf_range(4, 14)
		dune.position = Vector3(SIZE * 0.5 + cos(a) * out * 1.05, -radius * 0.15, SIZE * 0.5 + sin(a) * out * 1.05)
		dune.scale = Vector3(1.6, 0.4, 1.6)


## The temple court: a broken enclosure wall with a gap toward the camps, the tomb door in the
## north wall, and fallen columns.
func _temple() -> void:
	var x0 := 28.0
	var x1 := 112.0
	var z0 := 28.0
	var z1 := 96.0
	var h := 4.0
	# North wall with the sealed tomb door in the middle.
	_box(_nav, Vector3((x0 + 64.0) * 0.5, h * 0.5, z0), Vector3(64.0 - x0, h, 1.4), _stone)
	_box(_nav, Vector3((76.0 + x1) * 0.5, h * 0.5, z0), Vector3(x1 - 76.0, h, 1.4), _stone)
	_box(_nav, Vector3(70, h + 0.6, z0), Vector3(14.0, 1.2, 1.8), _stone)  # lintel
	var door := _box(_nav, Vector3(70, 2.0, z0 - 0.2), Vector3(12.0, 4.0, 1.0), _floor_mat)  # the sealed slab
	door.set_meta("tomb_door", true)
	tomb_door = Vector3(70, 0, z0 + 2.0)
	# West and east walls, broken in places.
	for x in [x0, x1]:
		for seg in [[z0, 50.0], [58.0, 74.0], [80.0, z1]]:
			_box(_nav, Vector3(x, h * 0.4, (seg[0] + seg[1]) * 0.5), Vector3(1.4, h * 0.8, seg[1] - seg[0]), _stone)
	# South wall with a wide gap toward the camps.
	_box(_nav, Vector3((x0 + 60.0) * 0.5, 1.2, z1), Vector3(60.0 - x0, 2.4, 1.4), _stone)
	_box(_nav, Vector3((80.0 + x1) * 0.5, 1.2, z1), Vector3(x1 - 80.0, 2.4, 1.4), _stone)
	# Colonnade along the court: some standing, some fallen (low cover).
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	for i in 10:
		for side in [-1.0, 1.0]:
			var p := Vector3(70.0 + side * 22.0, 0, 34.0 + i * 6.0)
			if rng.randf() < 0.65:
				_cylinder(_nav, p + Vector3.UP * 2.6, 0.7, 5.2)
			else:
				var size := Vector3(0.9, 0.9, rng.randf_range(2.6, 4.2))
				var fallen := _box(_nav, p + Vector3(side * 1.5, 0.45, 0), size, _stone)
				_mark_cover(fallen, size)


func _site_landmark(id: String, p: Vector3) -> void:
	match id:
		"anubis", "horus", "ra":
			_box(_nav, p + Vector3.UP * 0.6, Vector3(2.2, 1.2, 2.2), _stone)  # plinth
			var statue := _box(_nav, p + Vector3.UP * 3.0, Vector3(1.2, 3.6, 1.4), _floor_mat)
			statue.set_meta("statue", id)
		"scarabs", "hieroglyphs":
			_box(_nav, p + Vector3.UP * 2.0, Vector3(1.0, 4.0, 9.0), _stone)
		"greetings", "mummification":
			# A small roofless hall: three walls open toward the court centre.
			var open_dir := signf(C.x - p.x)
			_box(_nav, p + Vector3(-open_dir * 4.0, 1.6, 0), Vector3(0.8, 3.2, 8.0), _stone)
			_box(_nav, p + Vector3(0, 1.6, -4.0), Vector3(8.0, 3.2, 0.8), _stone)
			_box(_nav, p + Vector3(0, 1.6, 4.0), Vector3(8.0, 3.2, 0.8), _stone)
			var table := _box(_nav, p + Vector3.UP * 0.5, Vector3(2.2, 1.0, 1.0), _floor_mat)
			_mark_cover(table, Vector3(2.2, 1.0, 1.0))
		"souls":
			_box(_nav, p + Vector3.UP * 0.15, Vector3(8.0, 0.3, 8.0), _floor_mat)  # a raised floor
			for c in [Vector3(-3, 0, -3), Vector3(3, 0, -3), Vector3(-3, 0, 3), Vector3(3, 0, 3)]:
				_cylinder(_nav, p + c + Vector3.UP * 2.0, 0.45, 4.0)
		"obelisk":
			_box(_nav, p + Vector3.UP * 2.5, Vector3(1.4, 5.0, 1.4), _stone)
			var broken := _box(_nav, p + Vector3(2.5, 0.5, 1.0), Vector3(1.2, 1.0, 5.5), _stone)
			_mark_cover(broken, Vector3(1.2, 1.0, 5.5))
		"offering":
			for k in 3:
				var altar := _box(_nav, p + Vector3((k - 1) * 3.0, 0.5, 0), Vector3(2.0, 1.0, 1.2), _stone)
				_mark_cover(altar, Vector3(2.0, 1.0, 1.2))
		"storeroom":
			_box(_nav, p + Vector3(0, 1.5, -2.0), Vector3(6.0, 3.0, 1.0), _stone)
			_box(_nav, p + Vector3(-2.5, 1.5, 0.5), Vector3(1.0, 3.0, 4.0), _stone)
			_box(_nav, p + Vector3(2.5, 1.5, 0.5), Vector3(1.0, 3.0, 4.0), _stone)
		"astronomer":
			_box(_nav, p + Vector3.UP * 0.6, Vector3(6.0, 1.2, 6.0), _stone)  # the platform
			_box(_nav, p + Vector3(0, 0.3, 4.5), Vector3(2.0, 0.6, 3.0), _stone)  # a step up


# ---------------------------------------------------------------- camps

## A camp: a fire, tents (stand-in boxes), supply crates and a cart as cover; ours has a bed.
func _expedition_camp(id: String, at: Vector3) -> void:
	var canvas := StandardMaterial3D.new()
	canvas.albedo_color = {"party": Color(0.62, 0.55, 0.4), "americans": Color(0.55, 0.5, 0.35), "germans": Color(0.5, 0.48, 0.42)}[id]
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.35, 0.22, 0.12)
	var fire := Node3D.new()
	add_child(fire)
	fire.position = at
	_flame(fire, Vector3.UP * 0.45, 2.8, 12.0, true)
	_prop(self, "prop_campfire.glb", at)
	for k in 3:
		var a := PI + (k - 1) * 0.9
		var tent_at := at + Vector3(cos(a), 0, sin(a)) * 6.0
		# image-to-3d's tent is 2.5 long (x) x 1.53 x 1.17 high: scaled up a little, its long side
		# facing the fire; the stand-in box keeps the collision.
		var tent := _box(_nav, tent_at + Vector3.UP * 0.7, Vector3(3.0, 1.4, 1.8), canvas)
		tent.look_at(at + Vector3.UP * 0.7, Vector3.UP)
		_dress(tent, "prop_tent.glb", Vector3(2.5, 1.17, 1.53))
	# Cover in a loose ring: crates and a cart.
	var ring := [[Vector3(-4.5, 0, 3.5), Vector3(1.6, 1.0, 1.0)], [Vector3(4.5, 0, 3.5), Vector3(1.6, 1.0, 1.0)],
		[Vector3(0, 0, 5.5), Vector3(3.4, 1.1, 1.2)], [Vector3(-6.5, 0, -1.0), Vector3(1.0, 1.0, 2.2)],
		[Vector3(6.5, 0, -1.0), Vector3(1.0, 1.0, 2.2)]]
	for r in ring:
		var crate := _box(_nav, at + r[0] + Vector3.UP * (r[1] as Vector3).y * 0.5, r[1], wood)
		_mark_cover(crate, r[1])
		_dress(crate, "prop_crate_large.glb", Vector3(1.0, 0.52, 0.49))
	var lamp := _prop(self, "prop_lantern.glb", at + Vector3(-4.5, 1.0, 3.5))
	if lamp:
		var glow := OmniLight3D.new()
		glow.light_color = Color(1.0, 0.75, 0.4)
		glow.light_energy = 1.4
		glow.omni_range = 6.0
		lamp.add_child(glow)
		glow.position = Vector3.UP * 0.21
	if id == "party":
		interactables["camp_fire"] = Interactable.make(self, at, "Rest by the fire (save)", "camp_fire", 1.2)
		var bed_at := at + Vector3(-2.4, 0, -2.0)
		var bed := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.8, 0.12, 1.9)
		bed.mesh = bm
		bed.material_override = canvas
		add_child(bed)
		bed.position = bed_at + Vector3.UP * 0.06
		if _prop(self, "prop_bedroll.glb", bed_at, PI * 0.5):
			bed.visible = false
		interactables["camp_bed"] = Interactable.make(self, bed_at, "Sleep (end the day)", "camp_bed", 1.0)


func _scatter() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1925
	for i in 26:
		var p := Vector3(rng.randf_range(8, SIZE - 8), 0, rng.randf_range(8, SIZE - 8))
		if p.x > 26 and p.x < 114 and p.z > 26 and p.z < 98:
			continue  # not inside the court
		var near_camp := false
		for c in CAMPS.values():
			near_camp = near_camp or p.distance_to(c) < 11.0
		if near_camp:
			continue
		var size := Vector3(rng.randf_range(2.0, 5.0), rng.randf_range(0.9, 1.2), 0.8)
		var wall := _box(_nav, p + Vector3.UP * size.y * 0.5, size, _stone)
		wall.rotation.y = rng.randf() * PI
		_mark_cover(wall, size)


# ---------------------------------------------------------------- night

## 0 = day, 1 = night: the sun sets, moonlight, fires carry the scene. (Over ~4 s from main.)
func set_night(f: float) -> void:
	_night = f
	_sun.light_energy = lerpf(1.6, 0.18, f)
	_sun.light_color = Color(1.0, 0.9, 0.75).lerp(Color(0.55, 0.65, 0.95), f)
	_env.ambient_light_energy = lerpf(0.55, 0.08, f)
	_env.ambient_light_sky_contribution = lerpf(1.0, 0.25, f)
	_env.fog_light_color = Color(0.75, 0.62, 0.45).lerp(Color(0.05, 0.06, 0.1), f)
	_env.fog_density = lerpf(0.004, 0.012, f)
	_env.tonemap_exposure = lerpf(0.9, 1.25, f)
	var sky := _env.sky.sky_material as ProceduralSkyMaterial
	sky.sky_top_color = Color(0.32, 0.5, 0.75).lerp(Color(0.02, 0.03, 0.08), f)
	sky.sky_horizon_color = Color(0.85, 0.75, 0.6).lerp(Color(0.08, 0.08, 0.14), f)
	sky.ground_horizon_color = Color(0.8, 0.68, 0.5).lerp(Color(0.06, 0.05, 0.05), f)


func set_indoor(_f: float) -> void:
	pass  # all outdoors: day / night is set_night's job
