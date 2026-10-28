class_name AkmentarValley
extends AkmentarSurface
## Stage 1 of gameplan/akmentar_valley_plan.md: the Golden Pharaoh valley in blockout, beside
## today's surface (AkmentarSurface). No act uses it yet: today's surface stays Act 4's until Simon
## answers the plan's questions (tests/akmentar_valley_test walks it).
## The valley: about 470 x 560 m, cliffs on three sides, the gorge and the desert to the south;
## x east, z south, the Golden Facade's foot at z 0. Its areas are numbered as Simon's map:
##   1 the desert approach  2 the royal causeway over the gorge  3 the outer gate (first pylon)
##   4 the processional avenue  5 the colossal guardians  6 the ceremonial plaza  7 the obelisk court
##   8 the second pylon  9 the great stairway (+18 m)  10 the terrace of kings  11 the Golden Facade
##   (its door: a tunnel down to the stair into the tomb, a placeholder)  12 the solar disc
##   13 the side temples  14 the cliff terraces  15 the valley of statues  16 the sacred lake
##   17 the waterfall gardens  18 the watchers' ledges (+35 m)  19 the hidden path
## Boxes and today's kit only (the dungeon columns, the statues, the camp props); PLACEHOLDERS lists
## what each stands in for.

const TERRACE_Y := 18.0
const LEDGE_Y := 35.0
const GORGE := Vector2(405, 445)      # z, the gorge's north and south edges
const GORGE_Y := -8.0
const LAKE := Rect2(60, 180, 75, 120)
## Act 4's study sites in the valley (the plan's table), at their ground's height.
const VALLEY_SITES := {
	"greetings": Vector3(12, 0, 385), "horus": Vector3(-14, 0, 241), "offering": Vector3(22, 0, 205),
	"obelisk": Vector3(-20, 0, 150), "hieroglyphs": Vector3(16, 0, 137), "ra": Vector3(-30, TERRACE_Y, 56),
	"mummification": Vector3(-80, TERRACE_Y, 62), "storeroom": Vector3(80, TERRACE_Y, 62),
	"souls": Vector3(105, 0, 240), "anubis": Vector3(185, 0, 300), "scarabs": Vector3(-165, 0, 235),
	"astronomer": Vector3(210, LEDGE_Y, 85),
}
## The camps: ours on the approach outside the gorge, the rivals inside the valley.
const VALLEY_CAMPS := {"party": Vector3(40, 0, 492), "americans": Vector3(190, 0, 388), "germans": Vector3(-160, 0, 388)}
## Blockout stand-ins and what they wait for (gameplan/asset_briefs.md, section 1, and the plan's gaps).
const PLACEHOLDERS := {
	"cliffs (boxes)": "akm_cliff_face", "pylons (boxes)": "akm_pylon_face, akm_pylon_cornice, akm_flagpole_pennant",
	"sphinxes (boxes)": "akm_ram_sphinx", "colossi (boxes)": "akm_colossus_seated",
	"plaza columns (dungeon pillar_lotus/papyrus)": "akm_column_base/_shaft/_capital",
	"obelisks (boxes)": "akm_obelisk", "great stair (a ramp)": "akm_grand_stair",
	"terrace pillars (dungeon pillar_square_glyph)": "akm_osiride_pillar",
	"facade walls (boxes)": "akm_facade_wall, akm_facade_door, akm_facade_portico",
	"golden door (a gold box)": "akm_golden_door_frame, akm_golden_door_leaf", "solar disc (a cylinder)": "akm_solar_disc",
	"causeway (boxes)": "akm_causeway_section, akm_terrace_balustrade", "lake walls (boxes)": "akm_lake_edge",
	"lake shrine (boxes)": "akm_lake_shrine", "statue valley (boxes, today's statues)": "akm_colossus_seated (weathered), akm_osiride_pillar, akm_rubble",
	"waterfall (a box)": "a waterfall shader in Godot", "palms (meshes)": "palms (Cairo's builder for now)",
	"the stair down (a dark pit)": "the hypostyle hall and Act 5's tomb", "airstrip (a strip)": "airstrip windsock and hut",
}

var horse_spot := Vector3.ZERO
var stair_down := Vector3.ZERO    # the placeholder at the tunnel's foot (Act 5's tomb, later)
var boat_landing := Vector3.ZERO
var airstrip := Vector3.ZERO
var _gold: StandardMaterial3D
var _rock: StandardMaterial3D
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 1923
	_make_materials()
	_valley_materials()
	camps = VALLEY_CAMPS
	_nav = NavigationRegion3D.new()
	_nav.navigation_mesh = Level.nav_mesh()  # (the map's own 0.25 m cells: the world map shares one cell size)
	add_child(_nav)
	_ground()
	_cliffs()
	_gorge_and_causeway()
	_axis()
	_terrace_and_facade()
	_sides()
	for id: String in VALLEY_SITES:
		_site_landmark(id, VALLEY_SITES[id])
	for id: String in VALLEY_CAMPS:
		_expedition_camp(id, VALLEY_CAMPS[id])
	horse_spot = VALLEY_CAMPS.party + Vector3(7, 0, -7)
	_box(_nav, horse_spot + Vector3(0, 0.55, -1.0), Vector3(3.0, 1.1, 0.2), _floor_mat)  # the hitching rail
	player_spawn = VALLEY_CAMPS.party + Vector3(0, 0, 4)
	tomb_door = Vector3(0, TERRACE_Y, 0)
	_environment()
	_sun.directional_shadow_max_distance = 140.0
	_sun.rotation = Vector3(deg_to_rad(-42), deg_to_rad(18), 0)  # from the south: the facade (facing south) in the light
	_env.fog_density = 0.0012
	var t0 := Time.get_ticks_msec()
	var cached := NavCache.bake(_nav, "akmentar_valley")
	print("VALLEY navmesh %s in %d ms" % ["from the cache" if cached else "baked", Time.get_ticks_msec() - t0])


## Act 4's SiteSpots at the valley's sites (main calls this, as for the surface).
func place_sites() -> void:
	for id: String in VALLEY_SITES:
		site_spots[id] = SiteSpot.make(self, "akmentar_surface", id, site_spot(id))


## Where you stand at a site: beside its landmark on the side toward our camp if that's clear,
## else the first clear side round it (a long wall's end, a plinth's side). Needs the tree.
func site_spot(id: String) -> Vector3:
	var p: Vector3 = VALLEY_SITES[id]
	var toward := VALLEY_CAMPS.party - p
	toward.y = 0
	var start := atan2(toward.z, toward.x)
	var space := get_world_3d().direct_space_state
	var q := PhysicsShapeQueryParameters3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.45
	q.shape = sphere
	q.collision_mask = 1
	for r: float in [1.6, 2.6, 3.6, 5.0]:
		for k in 8:
			var a := start + (k / 2) * 0.785 * (1.0 if k % 2 == 0 else -1.0)
			var at := p + Vector3(cos(a), 0, sin(a)) * r
			q.transform = Transform3D(Basis(), at + Vector3.UP * 1.0)
			if space.intersect_shape(q, 1).is_empty():
				return at
	return p + toward.normalized() * 1.6


func _valley_materials() -> void:
	_gold = StandardMaterial3D.new()
	_gold.albedo_color = Color(0.85, 0.66, 0.24)
	_gold.metallic = 0.6
	_gold.roughness = 0.35
	_rock = _stone.duplicate() as StandardMaterial3D
	_rock.albedo_color = Color(0.62, 0.46, 0.32)


# ---------------------------------------------------------------- the ground

## The valley floor (y 0) in pieces round the gorge and the sacred lake's basin, the desert south.
func _ground() -> void:
	var x0 := -260.0
	var x1 := 280.0
	_slab(Rect2(x0, -10, x1 - x0, LAKE.position.y + 10), 0.0)                     # north of the lake
	_slab(Rect2(x0, LAKE.position.y, LAKE.position.x - x0, LAKE.size.y), 0.0)       # west of it
	_slab(Rect2(LAKE.end.x, LAKE.position.y, x1 - LAKE.end.x, LAKE.size.y), 0.0)    # east of it
	_slab(Rect2(x0, LAKE.end.y, x1 - x0, GORGE.x - LAKE.end.y), 0.0)                # down to the gorge
	_slab(Rect2(x0, GORGE.y, x1 - x0, 300), 0.0)                                    # the approach and the desert
	_box(_nav, Vector3(LAKE.get_center().x, -3.0, LAKE.get_center().y), Vector3(LAKE.size.x, 1.0, LAKE.size.y), _floor_mat)
	_water(Rect2(LAKE.position + Vector2(0.5, 0.5), LAKE.size - Vector2.ONE), -0.6)
	airstrip = Vector3(195, 0, 590)
	_flat(Vector3(195, 0.03, 590), Vector3(110, 0.02, 20), Color(0.78, 0.7, 0.55))


func _slab(r: Rect2, top: float) -> void:
	_box(_nav, Vector3(r.get_center().x, top - 0.5, r.get_center().y), Vector3(r.size.x, 1.0, r.size.y), _sand)


## Water over `r` at height `y`: `murk` how fast its bed fades (clear 0.3 .. muddy 1.2), `foam_w`
## how far out from its edges the foam reaches (in m of depth: small for a shallow pool).
func _water(r: Rect2, y: float, murk := 0.45, foam_w := 0.6) -> void:
	var w := RiverWater.make(self, r.size, y, Vector3(r.get_center().x, y, r.get_center().y))
	w.name = "Water"
	RiverWater.depth(w, murk, foam_w)
	var m := w.material_override as ShaderMaterial
	m.set_shader_parameter("deep", Color(0.08, 0.2, 0.22))
	m.set_shader_parameter("shallow", Color(0.3, 0.45, 0.4))


## A mesh with no collision (paving, markings).
func _flat(at: Vector3, size: Vector3, c: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.9
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.position = at
	return mi


## A walkable ramp from `a` to `b` (both on its top surface), `width` across.
func _ramp(a: Vector3, b: Vector3, width: float, mat: Material = null) -> StaticBody3D:
	var d := b - a
	var body := _box(_nav, Vector3.ZERO, Vector3(width, 0.6, d.length()), mat if mat else _floor_mat)
	var basis := Basis.looking_at(d.normalized(), Vector3.UP)
	body.global_transform = Transform3D(basis, (a + b) * 0.5 - basis.y * 0.3)
	return body


## A solid block from y0 up `h` over the x/z rect.
func _block(r: Rect2, y0: float, h: float, mat: Material) -> StaticBody3D:
	return _box(_nav, Vector3(r.get_center().x, y0 + h * 0.5, r.get_center().y), Vector3(r.size.x, h, r.size.y), mat)


# ---------------------------------------------------------------- the cliffs

## The valley's walls: north behind the facade (split for its door's tunnel and the hidden path's
## ravine), west and east, and the lower rock shelves inside them.
func _cliffs() -> void:
	# North, 100 m: west of the door, between the door and the ravine, east of the ravine.
	_block(Rect2(-260, -80, 257, 80), 0, 100, _rock)
	_block(Rect2(3, -80, 116, 80), 0, 100, _rock)
	_block(Rect2(129, -80, 151, 80), 0, 100, _rock)
	_block(Rect2(-3, -80, 6, 80), 27, 73, _rock)        # over the door's tunnel
	_block(Rect2(-3, -80, 6, 25), 0, 8, _rock)          # under the tunnel's far end
	# West and east walls.
	_block(Rect2(-260, 0, 45, 405), 0, 60, _rock)
	_block(Rect2(235, 0, 45, 405), 0, 70, _rock)
	# The rock shelves within: west by the gardens, east under the ledges, the north corners.
	_block(Rect2(-215, 0, 105, 40), 0, 30, _rock)
	_block(Rect2(110, 0, 9, 40), 0, 30, _rock)          # (the ravine of the hidden path between)
	_block(Rect2(129, 0, 106, 40), 0, 30, _rock)
	_block(Rect2(-215, 40, 65, 110), 0, 20, _rock)
	_block(Rect2(150, 135, 85, 115), 0, 20, _rock)


# ---------------------------------------------------------------- the gorge, the causeway

func _gorge_and_causeway() -> void:
	var z0 := GORGE.x
	var z1 := GORGE.y
	_box(_nav, Vector3(10, GORGE_Y - 0.5, (z0 + z1) * 0.5), Vector3(540, 1.0, z1 - z0), _rock)
	_water(Rect2(-260, z0 + 6, 540, z1 - z0 - 12), GORGE_Y + 0.4, 0.6, 0.15)   # (0.4 m deep: a shallow stream)
	# 2: the causeway, 16 m wide, level with the ground, on piers, with balustrades.
	_box(_nav, Vector3(0, -0.5, (z0 + z1) * 0.5), Vector3(16, 1.0, z1 - z0 + 2), _floor_mat)
	for sx in [-8.2, 8.2]:
		_box(_nav, Vector3(sx, 0.5, (z0 + z1) * 0.5), Vector3(0.4, 1.0, z1 - z0 + 2), _stone)
	for z in range(int(z0) + 8, int(z1), 12):
		_box(_nav, Vector3(0, (GORGE_Y + 0.0) * 0.5 - 0.5, z), Vector3(12, -GORGE_Y - 1.0, 3), _stone)
	# The boat landing, under the causeway's west side, with a stair up onto the approach.
	boat_landing = Vector3(-60, GORGE_Y + 0.6, z1 - 5.5)
	_box(_nav, boat_landing - Vector3.UP * 0.3, Vector3(16, 0.6, 11), _floor_mat)
	# The stair up runs west along the gorge's south wall to the approach's edge.
	_ramp(Vector3(-56, GORGE_Y + 0.6, z1 - 2), Vector3(-96, 0, z1 - 2), 4.0, _stone)


# ---------------------------------------------------------------- the axis

func _axis() -> void:
	# 3 and 8: the pylons, each a pair of towers either side of a gate 8 m wide.
	for p: Array in [[372.0, 24.0], [124.0, 20.0]]:
		for sx in [-1.0, 1.0]:
			_block(Rect2(-36.0 if sx < 0 else 4.0, float(p[0]) - 8.0, 32, 16), 0, p[1], _stone)
		_box(_nav, Vector3(0, float(p[1]) - 2.0, p[0]), Vector3(8, 4, 16), _stone)  # the lintel over the gate
	# 4: the avenue, paved, a ram sphinx (box) every 8 m a side.
	_flat(Vector3(0, 0.02, 307), Vector3(20, 0.02, 114), Color(0.86, 0.78, 0.62))
	for z in range(256, 362, 8):
		for sx in [-13.0, 13.0]:
			_block(Rect2(sx - 1.2, z - 2.6, 2.4, 5.2), 0, 3.0, _stone)
	# 5: the colossal guardians (seated: a base and a body).
	for sx in [-22.0, 22.0]:
		_block(Rect2(sx - 4.0, 236, 8, 11), 0, 6, _stone)
		_block(Rect2(sx - 3.0, 239, 6, 6), 6, 12, _stone)
	# 6: the ceremonial plaza: paving, colonnades of the dungeon kit's columns either side.
	_flat(Vector3(0, 0.02, 201), Vector3(90, 0.02, 62), Color(0.86, 0.78, 0.62))
	var k := 0
	for z in range(176, 230, 9):
		for sx in [-42.0, 42.0]:
			var col := _cylinder(_nav, Vector3(sx, 3.5, z), 0.9, 7.0)
			if _prop(col, KIT + "pillar_%s.glb" % ("lotus" if k % 2 == 0 else "papyrus"), Vector3(sx, 0, z), 0.0, Vector3(1.2, 1.4, 1.2)):
				(col.get_child(1) as MeshInstance3D).visible = false
			k += 1
	# 7: the obelisk court: four, one fallen and broken.
	for c in [Vector2(-20, 140), Vector2(20, 140), Vector2(20, 160)]:
		_block(Rect2(c.x - 1.0, c.y - 1.0, 2, 2), 0, 20, _gold)
	_block(Rect2(-31, 159, 20, 2), 0, 2, _gold)
	# 9: the great stairway, 30 m wide, up 18 m to the terrace.
	_ramp(Vector3(0, 0, 118), Vector3(0, TERRACE_Y, 70), 30.0, _floor_mat)
	for sx in [-16.0, 16.0]:
		_ramp(Vector3(sx, 1.0, 118), Vector3(sx, TERRACE_Y + 1.0, 70), 2.0, _stone)  # its side walls


# ---------------------------------------------------------------- the terrace, the facade

func _terrace_and_facade() -> void:
	# 10: the terrace of kings, x -100..100, z 0..70, at +18, its front lined with Osiride pillars.
	_block(Rect2(-100, 0, 200, 70), 0, TERRACE_Y, _stone)
	for x in range(-50, 51, 10):
		if absi(x) < 18:
			continue  # (the stair's head)
		var p := _box(_nav, Vector3(x, TERRACE_Y + 3.5, 66), Vector3(1.6, 7, 1.6), _floor_mat)
		if _prop(p, KIT + "pillar_square_glyph.glb", Vector3(x, TERRACE_Y, 66), 0.0, Vector3(1.0, 1.4, 1.0)):
			(p.get_child(1) as MeshInstance3D).visible = false
	# 13: the side temples on the terrace, west and east, each with a portico of four columns.
	for sx in [-80.0, 80.0]:
		_block(Rect2(sx - 18, 10, 36, 30), TERRACE_Y, 12, _stone)
		for k in 4:
			var cx: float = sx - 9.0 + k * 6.0
			var col := _cylinder(_nav, Vector3(cx, TERRACE_Y + 3.5, 44), 0.8, 7.0)
			if _prop(col, KIT + "pillar_lotus.glb", Vector3(cx, TERRACE_Y, 44), 0.0, Vector3(1.1, 1.4, 1.1)):
				(col.get_child(1) as MeshInstance3D).visible = false
	# 11: the Golden Facade on the cliff at z 0: four seated colossi either side of the door.
	for sx in [-30.0, -18.0, 18.0, 30.0]:
		_block(Rect2(sx - 4.0, 1, 8, 10), TERRACE_Y, 6, _stone)
		_block(Rect2(sx - 3.0, 3, 6, 6), TERRACE_Y + 6, 12, _stone)
	_box(_nav, Vector3(-4.5, TERRACE_Y + 6, 0.5), Vector3(3, 12, 1), _gold)   # the door's frame
	_box(_nav, Vector3(4.5, TERRACE_Y + 6, 0.5), Vector3(3, 12, 1), _gold)
	_box(_nav, Vector3(0, TERRACE_Y + 10, 0.5), Vector3(6, 4, 1), _gold)
	var glow := OmniLight3D.new()
	glow.light_color = Color(1.0, 0.78, 0.4)
	glow.light_energy = 2.0
	glow.omni_range = 9.0
	add_child(glow)
	glow.position = Vector3(0, TERRACE_Y + 4, -2)
	# The door's tunnel: down from the terrace into the cliff, to the stair down (a placeholder).
	_ramp(Vector3(0, TERRACE_Y, 0), Vector3(0, 8.0, -40), 6.0, _floor_mat)
	stair_down = Vector3(0, 8.0, -48)
	_box(_nav, Vector3(0, 7.5, -48), Vector3(6, 1, 16), _floor_mat)
	_flat(Vector3(0, 8.03, -52), Vector3(4, 0.02, 4), Color(0.05, 0.04, 0.03))   # the dark of the stair down
	interactables["stair_down"] = Interactable.make(self, stair_down + Vector3.UP * 1.0, "The stair down (Act 5's tomb: a placeholder)", "stair_down", 1.4)
	# 12: the solar disc, 50 m up the cliff.
	var disc := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 7.0
	cm.bottom_radius = 7.0
	cm.height = 0.6
	disc.mesh = cm
	disc.material_override = _gold
	add_child(disc)
	disc.position = Vector3(0, 68, 0.2)
	disc.rotation.x = PI * 0.5


# ---------------------------------------------------------------- the sides

func _sides() -> void:
	# 14: the cliff terraces, raised 8 m along both sides, each with a ramp.
	for tz in [60.0, 110.0, 160.0, 210.0]:
		_block(Rect2(-150, tz, 25, 30), 0, 8, _stone)
	_block(Rect2(125, 60, 25, 30), 0, 8, _stone)                # (the east side's one: the lake and the ledges' stair)
	_ramp(Vector3(-118, 0, 268), Vector3(-131, 8, 239), 4.0)    # up onto a west terrace
	_ramp(Vector3(118, 0, 110), Vector3(131, 8, 89), 4.0)       # and the east one
	# 18: the watchers' ledges on the east rock at +35, a rock-cut stair up the shelf's west face.
	_block(Rect2(150, 40, 85, 95), 0, LEDGE_Y, _rock)
	_ramp(Vector3(144, 0, 255), Vector3(144, LEDGE_Y, 132), 8.0, _rock)
	_box(_nav, Vector3(146, LEDGE_Y - 0.15, 129), Vector3(12, 0.3, 6), _rock)   # the stair's head (from where it ends, z 132), onto the ledge
	# 19: the hidden path: up the ravine behind the east side temple to the rear cliffs (+25).
	_ramp(Vector3(124, 0, 4), Vector3(124, 25, -80), 6.0, _rock)
	_block(Rect2(100, -180, 180, 100), 0, 25, _rock)            # the rear plateau
	# 15: the valley of statues: weathered colossi and pillars, half sunk.
	for c in [Vector3(165, 0, 270), Vector3(215, 0, 285), Vector3(170, 0, 340), Vector3(222, 0, 350), Vector3(198, 0, 365)]:
		_block(Rect2(c.x - 3, c.z - 4, 6, 8), -1.0, 4, _stone)
		_block(Rect2(c.x - 2.2, c.z - 2.2, 4.4, 4.4), 3.0, 8 + _rng.randf() * 4.0, _stone)
	for c in [Vector2(160, 300), Vector2(205, 320), Vector2(226, 260)]:
		var p := _box(_nav, Vector3(c.x, 3.5, c.y), Vector3(1.6, 7, 1.6), _floor_mat)
		p.rotation.z = _rng.randf_range(-0.25, 0.25)
	# 16: the sacred lake's walls (low, round the basin) and the shrine on its causeway.
	for e in [Rect2(LAKE.position.x, LAKE.position.y - 1, LAKE.size.x, 1), Rect2(LAKE.position.x, LAKE.end.y, LAKE.size.x, 1),
			Rect2(LAKE.end.x, LAKE.position.y, 1, LAKE.size.y)]:
		_block(e, 0, 0.8, _stone)
	_block(Rect2(LAKE.position.x - 1, LAKE.position.y, 1, 56), 0, 0.8, _stone)
	_block(Rect2(LAKE.position.x - 1, LAKE.position.y + 64, 1, 56), 0, 0.8, _stone)
	_box(_nav, Vector3(82.5, -0.5, 240), Vector3(45, 1, 6), _floor_mat)          # the walk out to the shrine
	_box(_nav, Vector3(105, -0.5, 240), Vector3(12, 1, 12), _floor_mat)          # its island
	_block(Rect2(109, 236, 2, 8), 0, 4, _gold)
	# 17: the waterfall gardens: the fall off the west cliff, pools, palms.
	# The fall pours east off the west cliff (its face at x -215) into a walled pool at its foot.
	Waterfall.make(self, Vector3(-215, 40, 200), 14.0, 39.2, Vector3.RIGHT)
	for e in [Rect2(-215, 185, 30, 1), Rect2(-215, 215, 30, 1), Rect2(-186, 186, 1, 29)]:
		_block(e, 0, 0.9, _stone)
	_water(Rect2(-215, 186, 29, 29), 0.75, 0.35, 0.25)
	for k in 18:
		var at := Vector3(_rng.randf_range(-210, -115), 0, _rng.randf_range(155, 325))
		if Rect2(-217, 183, 34, 34).has_point(Vector2(at.x, at.z)):
			at.x += 34.0   # not in the pool
		_palm(at)
	for k in 10:
		var x := _rng.randf_range(-100, 140)
		_palm(Vector3(x, 0, _rng.randf_range(452, 470)))


## A palm (Palms: a date palm, its trunk solid in the navmesh); the height drawn from the
## level's own dice as before, so the rest of the layout doesn't shift.
func _palm(at: Vector3) -> void:
	Palms.add(self, at, _rng.randf_range(6.0, 9.0), _nav)
