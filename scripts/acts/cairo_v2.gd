class_name CairoV2
extends Cairo
## Stage 1 of gameplan/cairo_plan.md: Cairo at about 4x the ground (230 x 205 m of streets, the
## Nile front along the east), in districts, as blockout. No act uses it yet: today's Cairo stays
## the game's until Simon approves (tests/cairo_v2_test walks it). The landmarks are today's
## builders, each built shifted to its new place (MOVES); the blocks between them are new.
## -f9's interiors are built at the moved venues; their crowd comes with `with_life`. Not here yet:
## the townsfolk's chatting pairs, the street life and animals.

const V2_RIVER_X := 232.0   # the quay edge
const V2_SOUTH := 205.0     # the city wall
## Each landmark's builder and how far it moves from today's place (its spots move with it).
const MOVES := {
	"hotel": Vector3(68, 0, 12), "bank": Vector3(68, 0, 12), "consulate": Vector3(80, 0, 0),
	"telegraph": Vector3(133, 0, 66), "club": Vector3(100, 0, 12), "outfitter": Vector3(66, 0, 12),
	"gunsmith": Vector3(30, 0, 49), "tavern": Vector3(70, 0, 62), "police": Vector3(26, 0, 12),
	"station": Vector3(14, 0, 0), "mosque": Vector3(108, 0, 105), "museum": Vector3(90, 0, 0),
	"dealer": Vector3(114, 0, 81), "bazaar": Vector3(121, 0, 58), "caravanserai": Vector3(100, 0, 86),
	"road_gate": Vector3(71, 0, 105),
}
## Which landmark carries each spot (the rest are on the new quay).
const SPOT_OF := {"hotel_bed": "hotel", "freddie": "club", "cafe": "tavern"}
const QUAY_SPOTS := {"docks": Vector3(220, 0, 110), "labour": Vector3(220, 0, 135)}

## -f9's crowd for v2 (crowd/cairo_v2.json): off until the acts use v2 (cairo_v2_test --with-life).
static var with_life := false

## Stage 2: image-to-3d's facade kit (gameplan/asset_briefs.md, Cairo). Flat-fronted boxes that
## tile; each module's front is its +Z, its origin at the bottom centre of the front's width.
const KIT := "res://assets/props/cairo/"
const OLD_GROUND := ["cai_house_shop_open", "cai_house_shop_closed"]
const OLD_UPPER := ["cai_house_upper_shutters"]
const OLD_CORNER := "cai_house_corner"
const EURO := ["cai_euro_bay_balconies", "cai_euro_bay_arcade"]
const QUAY := "cai_quay_wall_rings"
const STOREY := 4.0      # an old-quarter module's height (and its width)
const EURO_W := 6.0
const EURO_H := 14.0

var _kit := ""           # "old" / "euro" while _v2_blocks builds that district; "" = blockout
var _kit_scenes := {}    # id -> PackedScene


func _ready() -> void:
	_rng.seed = 1922
	_make_materials()
	_cairo_materials()
	_nav = NavigationRegion3D.new()
	_nav.navigation_mesh = Level.nav_mesh()
	add_child(_nav)
	_deco = Node3D.new()
	_deco.name = "Deco"
	add_child(_deco)
	# The ground: the city, its ring and the quay, up to the river.
	_box(_nav, Vector3((-RING + V2_RIVER_X) * 0.5, -0.5, (-RING + V2_SOUTH + RING) * 0.5),
		Vector3(V2_RIVER_X + RING, 1.0, V2_SOUTH + RING * 2.0), _street)
	_v2_river()
	for id: String in MOVES:
		_moved(MOVES[id], Callable(self, "_" + id))
	_v2_blocks()
	_v2_wall()
	_v2_quay()
	interiors = CairoInteriors.build(self)  # -f9's rooms, at the moved venues (it reads MOVES); before the bake and the merge
	_moved(Vector3(60, 0, 52), _skyline)
	for id: String in SPOTS:
		var s: Array = SPOTS[id]
		var at: Vector3 = QUAY_SPOTS.get(id, s[0] + MOVES.get(SPOT_OF.get(id, id), Vector3.ZERO))
		spots[id] = interiors.room_spots.get(id, at) if interiors else at
	interactables["hotel_bed"] = Interactable.make(self, spots.hotel_bed + Vector3.UP * 0.9, SPOTS.hotel_bed[2], "hotel_bed", 1.0)
	player_spawn = spots.hotel + Vector3(0, 0, 2.0)
	mooring = Transform3D(Basis.IDENTITY, Vector3(V2_RIVER_X + 9.0, WATER_Y, 90.0))
	_environment()
	set_day_time(day_time)
	_nav.bake_navigation_mesh(false)
	if with_life:
		crowd = Crowd.populate(self, "cairo_v2")
	RenderBudget.quiet_minor(_deco)
	if not "--no-merge" in OS.get_cmdline_user_args():
		print("CAIRO v2 deco merged: %d draw calls fewer" % RenderBudget.merge_static(_deco))


## A kit piece's scene, or null when it hasn't been delivered (the blockout stands in).
func _kit_scene(id: String) -> PackedScene:
	if not _kit_scenes.has(id):
		var path := KIT + id + ".glb"
		_kit_scenes[id] = load(path) if ResourceLoader.exists(path) else null
	return _kit_scenes[id]


## A building: in a kit district, a plain block (its collision and roof) faced on the street with
## the kit's modules, tiled to fill each face exactly; elsewhere Cairo's blockout building.
func _building(r: Rect2, h: float, mat: Material, faces: Array, door := true) -> void:
	var euro := _kit == "euro" and _kit_scene(EURO[0]) != null
	var old := _kit == "old" and _kit_scene(OLD_GROUND[0]) != null and _kit_scene(OLD_UPPER[0]) != null
	if not (euro or old):
		super(r, h, mat, faces, door)
		return
	h = EURO_H if euro else STOREY * clampf(roundf(h / STOREY), 2.0, 3.0)
	var c := Vector3(r.get_center().x, 0, r.get_center().y)
	_box(_nav, c + Vector3.UP * h * 0.5, Vector3(r.size.x, h, r.size.y), mat)
	_mesh(c + Vector3.UP * (h + 0.15), Vector3(r.size.x + 0.2, 0.3, r.size.y + 0.2), _trim)  # the roof's lip
	for f in faces:
		var n := Vector3(f.x, 0, f.y)
		var along := Vector3(absf(n.z), 0, absf(n.x))
		var width := r.size.x if n.z != 0 else r.size.y
		var depth := r.size.y if n.z != 0 else r.size.x
		var face := c + n * depth * 0.5
		if euro:
			_kit_row(face, n, along, width, 0.0, EURO, EURO_W, EURO_H)
		else:
			var corner := _kit_scene(OLD_CORNER)
			var inner := width - (3.0 if corner else 0.0)
			_kit_row(face, n, along, inner, 0.0, OLD_GROUND, STOREY, STOREY)
			for fl in range(1, int(h / STOREY)):
				_kit_row(face, n, along, inner, fl * STOREY, OLD_UPPER, STOREY, STOREY)
			if corner:
				for side: float in [-1.0, 1.0]:
					_kit_piece(corner, face + along * side * (width * 0.5 - 0.75), n, Vector3(1.0, h / 9.0, 1.0))


## One row of modules along a face, `width` wide, its foot at `y`: as many as fit, stretched (or
## squeezed) a little so the row fills the face edge to edge.
func _kit_row(face: Vector3, n: Vector3, along: Vector3, width: float, y: float, ids: Array, w: float, h: float) -> void:
	var count := maxi(1, roundi(width / w))
	var sx := width / (count * w)
	for k in count:
		var u := (k - (count - 1) * 0.5) * w * sx
		var id: String = ids[_rng.randi() % ids.size()]
		var sc := _kit_scene(id)
		if sc:
			_kit_piece(sc, face + along * u + Vector3.UP * y, n, Vector3(sx, 1.0, 1.0))


## A module standing against a face: its front just proud of the wall, turned to face `n`.
func _kit_piece(sc: PackedScene, at: Vector3, n: Vector3, scale_by: Vector3) -> void:
	var m: Node3D = sc.instantiate()
	_deco.add_child(m)
	m.rotation.y = atan2(n.x, n.z)
	m.scale = scale_by
	m.global_position = at + n * (0.03 - _front_z(m))  # its front 3 cm proud of the wall, the rest inside


## How far a module's front (+Z) stands from its origin, from its meshes' bounds.
func _front_z(m: Node3D) -> float:
	var z := 0.0
	for mi: MeshInstance3D in m.find_children("*", "MeshInstance3D", true, false):
		z = maxf(z, (mi.transform * mi.get_aabb()).end.z)
	return z


## Build with today's builder, shifted by `off`: its solids and its dressing go under offset
## holders, so it stands at its new place whole; the solids then move into _nav for the bake.
func _moved(off: Vector3, build: Callable) -> void:
	var nav_keep := _nav
	var deco_keep := _deco
	var n := NavigationRegion3D.new()  # (only a holder while it builds: emptied into _nav after)
	n.enabled = false  # never on the navigation map (a region freed mid-build stalled the map's updates)
	n.position = off
	nav_keep.add_child(n)
	var d := Node3D.new()
	d.position = off
	deco_keep.add_child(d)
	_nav = n
	_deco = d
	build.call()
	_nav = nav_keep
	_deco = deco_keep
	# Into the outer region itself, where they are now (the bake doesn't read nested regions).
	for c in n.get_children():
		c.reparent(_nav, true)
	n.queue_free()


## The landmarks' footprints at their new places (holes the blocks leave).
func _holes() -> Array:
	return [Rect2(106, 42, 18, 16), Rect2(126, 46, 14, 12), Rect2(142, 18, 10, 16), Rect2(197, 70, 8, 10),
		Rect2(156, 66, 14, 10), Rect2(106, 66, 10, 8), Rect2(62, 105, 8, 10), Rect2(84, 122, 12, 12),
		Rect2(28, 66, 10, 10), Rect2(150, 161, 8, 8), Rect2(0, 40, 14, 20), Rect2(180, 140, 24, 46)]


## The districts' blocks between the streets (the streets are what's left open):
## the Boulevard z 58-66; the Old Street x 96-104; the souk lane z 131-139; the corniche x 205+;
## the station square, the museum square and the mosque square stay open.
func _v2_blocks() -> void:
	var holes := _holes()
	var blocks := [
		# The north: behind the station square, and the European quarter either side of x 76-84.
		[Rect2(0, 0, 40, 38), 8.0, 14.0], [Rect2(40, 0, 36, 58), 9.0, 16.0], [Rect2(84, 0, 68, 42), 10.0, 18.0],
		[Rect2(84, 42, 22, 16), 10.0, 16.0], [Rect2(140, 34, 12, 24), 10.0, 16.0],
		# South of the Boulevard: the European blocks and the souk's north side.
		[Rect2(104, 66, 44, 40), 9.0, 15.0], [Rect2(156, 66, 41, 40), 9.0, 15.0], [Rect2(150, 110, 55, 21), 7.0, 12.0],
		# The old quarter: lanes x 22-26 and 56-62 north-south, z 86-90 / 116-120 / 146-150 / 176-180 east-west.
		[Rect2(26, 76, 30, 10), 5.0, 11.0], [Rect2(0, 66, 22, 20), 5.0, 11.0], [Rect2(62, 66, 34, 20), 5.0, 11.0],
	]
	for z: Array in [[90.0, 116.0], [120.0, 146.0], [150.0, 176.0], [180.0, 205.0]]:
		for x: Array in [[0.0, 22.0], [26.0, 56.0], [62.0, 96.0]]:
			blocks.append([Rect2(x[0], z[0], x[1] - x[0], z[1] - z[0]), 5.0, 11.0])
	# The souk: narrow blocks either side of its lanes (z 157-161, 181-185; x 176-180), and the
	# old blocks south of the mosque square.
	blocks.append_array([[Rect2(150, 139, 26, 18), 5.0, 9.0], [Rect2(150, 161, 26, 20), 5.0, 9.0],
		[Rect2(150, 185, 26, 20), 5.0, 9.0], [Rect2(180, 186, 25, 19), 5.0, 9.0],
		[Rect2(104, 164, 46, 16), 5.0, 10.0], [Rect2(104, 184, 46, 21), 5.0, 10.0]])
	for b: Array in blocks:
		var r: Rect2 = b[0]
		var inside := holes.filter(func(h: Rect2) -> bool: return r.intersects(h))
		_kit = _district(r)
		_block(r, inside, b[1], b[2])
	_kit = ""
	# The ring outside, so the city's edges end in facades.
	_block(Rect2(-RING, -RING, RING, V2_SOUTH + RING), [], 8.0, 16.0)
	_block(Rect2(0, -RING, V2_RIVER_X - 27.0, RING), [], 8.0, 16.0)


## Which kit faces a block: the European quarter's bays north of the Boulevard, and south of it
## east of the Old Street down to z 106; the old houses everywhere else inside the walls.
func _district(r: Rect2) -> String:
	var c := r.get_center()
	if (c.y < 58.0 and c.x > 40.0) or (c.x > 104.0 and c.y < 106.0):
		return "euro"
	return "old"


## The city wall along the south, with the gate (today's, moved) at the Old Street's end.
func _v2_wall() -> void:
	for seg: Array in [[0.0, 97.0], [103.0, 205.0]]:
		_building(Rect2(seg[0], V2_SOUTH, seg[1] - seg[0], 2.0), 9.0, _plaster[1], [Vector2(0, -1)], false)
	# The road south out of the gate, past low houses either side.
	_mesh(Vector3(100, 0.02, V2_SOUTH + 60.0), Vector3(6.0, 0.02, 110.0), _sand)
	_block(Rect2(0, V2_SOUTH + 2.0, 97, RING - 2.0), [], 4.0, 7.0)
	_block(Rect2(103, V2_SOUTH + 2.0, 102, RING - 2.0), [], 4.0, 7.0)


## The Nile: the quay wall, the water and the far bank, along the whole city.
func _v2_river() -> void:
	var len := V2_SOUTH + RING * 2.0 + 200.0
	var mid := V2_SOUTH * 0.5
	_box(_nav, Vector3(V2_RIVER_X - 0.3, -1.6, mid), Vector3(0.6, 3.2, len), _trim)
	var water := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(120, len)
	water.mesh = pm
	water.material_override = _water
	add_child(water)
	water.position = Vector3(V2_RIVER_X + 60, WATER_Y, mid)
	_mesh(Vector3(V2_RIVER_X + 60, WATER_Y - 2.0, mid), Vector3(120, 0.2, len), _dark)
	var bank := MeshInstance3D.new()
	var bm := PlaneMesh.new()
	bm.size = Vector2(300, len)
	bank.mesh = bm
	bank.material_override = _sand
	add_child(bank)
	bank.position = Vector3(V2_RIVER_X + 120 + 150, -0.6, mid)
	for i in 22:
		_palm(Vector3(V2_RIVER_X + 122 + _rng.randf_range(0, 18), -0.6, -60 + i * 16 + _rng.randf_range(-4, 4)), _rng.randf_range(7, 10), false)


## The corniche and the quay: bollards along the edge, palms, the docks' crates and the steamer
## landing (the old quay's pieces stay with the old Cairo).
func _v2_quay() -> void:
	for z in range(4, int(V2_SOUTH), 8):
		var b := _cylinder(_nav, Vector3(V2_RIVER_X - 0.6, 0.35, z), 0.22, 0.7)
		(b.get_child(1) as MeshInstance3D).material_override = _iron
	for z: float in [10.0, 30.0, 52.0, 74.0, 160.0, 184.0]:
		_palm(Vector3(V2_RIVER_X - 3.0, 0, z), 8.0 + _rng.randf_range(-1, 1))
	# The docks: crates and sacks in stacks between z 100 and 145 (cover, and something to see).
	for i in 10:
		var at := Vector3(_rng.randf_range(208, 216), 0, 100.0 + i * 4.6)
		var crate := _box(_nav, at + Vector3.UP * 0.6, Vector3(1.4, 1.2, 1.4), _wood)
		_mark_cover(crate, Vector3(1.4, 1.2, 1.4))
	# The quay wall's face on the river: the kit's stone with its mooring rings, the length of the city.
	var qw := _kit_scene(QUAY)
	if qw:
		for z in range(3, int(V2_SOUTH), 6):
			var m: Node3D = qw.instantiate()
			_deco.add_child(m)
			m.rotation.y = PI * 0.5  # its front (+Z) to the river (+X)
			m.global_position = Vector3(V2_RIVER_X + 0.03 - _front_z(m), -3.0, float(z))
	# The landing stage where the steamer ties up.
	_box(_nav, Vector3(V2_RIVER_X + 4.0, -0.25, 90.0), Vector3(8.0, 0.5, 4.0), _wood)
	for z in [100.0, 107.0, 114.0]:
		_street_lamp(Vector3(V2_RIVER_X - 2.0, 0, z))
