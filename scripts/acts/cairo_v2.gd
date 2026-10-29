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
## People talking in pairs, by district (Cairo's CHATS, re-placed).
const V2_CHATS := [
	[Vector3(122, 0, 152), Vector3(122.9, 0, 152.6)], [Vector3(117, 0, 64.6), Vector3(117.9, 0, 64.0)],
	[Vector3(150.5, 0, 133), Vector3(151.3, 0, 133.7)], [Vector3(28, 0, 52), Vector3(28.9, 0, 52.5)],
	[Vector3(214, 0, 88), Vector3(214.8, 0, 88.6)], [Vector3(60, 0, 88), Vector3(60.9, 0, 88.3)],
]
## Animals standing about (Cairo's ANIMALS, re-placed): cab horses at the station, a horse at the
## hotel's door, donkeys in the souk and at the caravanserai's gate. [where, yaw, size]
const V2_ANIMALS := [
	[Vector3(20, 0, 70), 0.0, 1.0], [Vector3(23.5, 0, 70), 0.1, 1.0], [Vector3(103, 0, 61.5), PI * 0.5, 1.0],
	[Vector3(163, 0, 137.5), PI * 0.5, 0.72], [Vector3(176.5, 0, 168), 0.3, 0.72], [Vector3(140, 0, 158), -0.4, 0.72],
]

## -f9's crowd for v2 (crowd/cairo_v2.json): on, the acts use v2 (tests can turn it off).
static var with_life := true

## Stage 2: image-to-3d's facade kit (gameplan/asset_briefs.md, Cairo). Flat-fronted boxes that
## tile; each module's front is its +Z, its origin at the bottom centre of the front's width.
const KIT := "res://assets/props/cairo/"
const OLD_GROUND := ["cai_house_shop_open", "cai_house_shop_closed"]
const OLD_UPPER := ["cai_house_upper_shutters", "cai_house_upper_bay"]
const OLD_ROOF := "cai_house_roofline"
const OLD_CORNER := "cai_house_corner"
const EURO := ["cai_euro_bay_balconies", "cai_euro_bay_arcade"]
const QUAY := "cai_quay_wall_rings"
const MOSQUE := "cai_mosque_wall"
## The landmarks' one-off pieces (image-to-3d, TRELLIS): origin on the ground at the footprint's
## centre, front +Z.
const PORTAL := "cai_mosque_portal"           # 6.9 x 2.9 m, 12 m tall: at the mosque's east door
const MINARET := "cai_minaret_mamluk"         # 40 m: the mosque's
const MINARET_2 := "cai_minaret_ottoman"      # 40 m: a second one over the old quarter's roofs
const GATE_TOWER := "cai_gate_tower"          # 22 m, 9.6 m across: either side of the south gate
const AWNING := "cai_awning_patchwork"        # 6 m span along its Z
const QUAY_STEPS := "cai_quay_wall_steps"     # every few modules along the quay
const MOSQUE_W := 6.0
const MOSQUE_H := 10.0
const STOREY := 4.0      # an old-quarter module's height (and its width)
const EURO_W := 6.0
const EURO_H := 14.0

var _kit := ""           # "old" / "euro" / "mosque" while that's being built; "" = blockout
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
		_kit = "mosque" if id == "mosque" else ""
		_moved(MOVES[id], Callable(self, "_" + id))
	_kit = ""
	_v2_blocks()
	_v2_wall()
	_v2_quay()
	_v2_landmarks()
	_v2_street_life()
	_animals(V2_ANIMALS)
	interiors = CairoInteriors.build(self)  # -f9's rooms, at the moved venues (it reads MOVES); before the bake and the merge
	_v2_skyline()
	for id: String in SPOTS:
		var s: Array = SPOTS[id]
		var at: Vector3 = QUAY_SPOTS.get(id, s[0] + MOVES.get(SPOT_OF.get(id, id), Vector3.ZERO))
		spots[id] = interiors.room_spots.get(id, at) if interiors else at
	interactables["hotel_bed"] = Interactable.make(self, spots.hotel_bed + Vector3.UP * 0.9, SPOTS.hotel_bed[2], "hotel_bed", 1.0)
	player_spawn = spots.hotel + Vector3(0, 0, 2.0)
	tavern_door = door_of("tavern")
	mooring = Transform3D(Basis.IDENTITY, Vector3(V2_RIVER_X + 9.0, WATER_Y, 90.0))
	_environment()
	set_day_time(day_time)
	_nav.bake_navigation_mesh(false)
	if with_life:
		crowd = Crowd.populate(self, "cairo_v2")
	_townsfolk(V2_CHATS)
	RenderBudget.quiet_minor(_deco)
	if not "--no-merge" in OS.get_cmdline_user_args():
		print("CAIRO v2 deco merged: %d draw calls fewer" % RenderBudget.merge_static(_deco))


## Spot `id`'s place in the street before its door, at its moved landmark.
func door_of(id: String) -> Vector3:
	return QUAY_SPOTS.get(id, SPOTS[id][0] + MOVES.get(SPOT_OF.get(id, id), Vector3.ZERO))


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
	if _kit == "mosque" and _kit_scene(MOSQUE):
		_mosque_walls(r)
		return
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
			if _kit_scene(OLD_ROOF):
				_kit_row(face, n, along, inner, h, [OLD_ROOF], STOREY, STOREY)  # the stepped parapet on top
			if corner:
				for side: float in [-1.0, 1.0]:
					_kit_piece(corner, face + along * side * (width * 0.5 - 0.75), n, Vector3(1.0, h / 9.0, 1.0))


## The mosque's block faced all round with the mosque wall (it stands in a square now), its east
## door left open (today's door, until the portal arrives).
func _mosque_walls(r: Rect2) -> void:
	var c := Vector3(r.get_center().x, 0, r.get_center().y)
	_box(_nav, c + Vector3.UP * MOSQUE_H * 0.5, Vector3(r.size.x, MOSQUE_H, r.size.y), _plaster[0])
	for f: Vector2 in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
		var n := Vector3(f.x, 0, f.y)
		var along := Vector3(absf(n.z), 0, absf(n.x))
		var width := r.size.x if n.z != 0 else r.size.y
		var depth := r.size.y if n.z != 0 else r.size.x
		var face := c + n * depth * 0.5
		var count := maxi(1, roundi(width / MOSQUE_W))
		var sx := width / (count * MOSQUE_W)
		for k in count:
			var u := (k - (count - 1) * 0.5) * MOSQUE_W * sx
			var at := face + along * u
			if n.x > 0.5 and absf(at.z - 24.0) < MOSQUE_W * sx * 0.5:
				continue  # the door (today's builder puts it at z 24 on the east face)
			_kit_piece(_kit_scene(MOSQUE), at, n, Vector3(sx, 1.0, 1.0))
	# The portal over the east door, standing out from the wall into the square.
	var portal := _kit_scene(PORTAL)
	if portal:
		_one_off(portal, Vector3(r.end.x + 1.4, 0, 24.0), PI * 0.5)


## A one-off piece on the ground at `at` (in _deco's frame), its front turned by `yaw`.
func _one_off(sc: PackedScene, at: Vector3, yaw: float) -> Node3D:
	var m: Node3D = sc.instantiate()
	_deco.add_child(m)
	m.rotation.y = yaw
	m.position = at
	return m


## The minaret: the kit's (from the ground, through the roof it stood on) where it's delivered.
func _minaret(base: Vector3, h: float) -> void:
	var sc := _kit_scene(MINARET)
	if sc == null:
		super(base, h)
		return
	_one_off(sc, Vector3(base.x, 0, base.z), 0.0)


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
	m.position = at + n * (0.03 - _front_z(m))  # its front 3 cm proud of the wall (in _deco's frame: moved holders too)


## How far a module's wall face (+Z) stands from its origin. The modules are symmetric in depth
## about their origin, so it's the back face's distance; the front's bounds include what projects
## (a mashrabiya bay, a water spout) and would push the wall out.
func _front_z(m: Node3D) -> float:
	var z := 0.0
	for mi: MeshInstance3D in m.find_children("*", "MeshInstance3D", true, false):
		z = minf(z, (mi.transform * mi.get_aabb()).position.z)
	return -z


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


## The pieces that stand on their own: the gate's towers, the second minaret, the souk's awnings.
func _v2_landmarks() -> void:
	var tower := _kit_scene(GATE_TOWER)
	if tower:
		for x: float in [91.5, 108.5]:
			_one_off(tower, Vector3(x, 0, V2_SOUTH + 1.0), PI)  # (their fronts to the north, into the city)
	var m2 := _kit_scene(MINARET_2)
	if m2:
		_one_off(m2, Vector3(41, 0, 163), 0.0)  # over the old quarter's roofs (inside a block)
	var aw := _kit_scene(AWNING)
	if aw:
		for x: float in [162.0, 186.0, 199.0]:
			_one_off(aw, Vector3(x, 0, 135.0), 0.0)  # across the souk lane (its span along Z)
		for z: float in [142.0, 172.0, 190.0]:
			_one_off(aw, Vector3(100.0, 0, z), PI * 0.5)  # across the Old Street


## Beyond the walls (seen, never reached, so no collision): the rest of the city low on every side
## but the river, two far minarets, and the citadel on its hill to the south-south-west (Simon,
## 28 Oct: "a citadel on a hill as the skyline landmark"). Blockout until image-to-3d's citadel.
const CITADEL_AT := Vector3(0, 0, 300)
const CITADEL_HILL := 45.0  # high enough to stand over the old town's roofs from its squares

func _v2_skyline() -> void:
	for i in 90:
		var side := i % 3
		var t := _rng.randf()
		var out := _rng.randf_range(10, 60)
		var p: Vector3
		match side:
			0: p = Vector3(-RING - out, 0, lerpf(-RING - 60, V2_SOUTH + RING + 60, t))
			1: p = Vector3(lerpf(-RING - 60, V2_RIVER_X - 30, t), 0, -RING - out)
			_: p = Vector3(lerpf(-RING - 60, V2_RIVER_X - 30, t), 0, V2_SOUTH + RING + out)
		if side == 2 and absf(p.x - 100.0) < 18.0:
			continue  # the road south from the gate stays open
		var h := _rng.randf_range(6, 16)
		_mesh(p + Vector3.UP * h * 0.5, Vector3(_rng.randf_range(10, 20), h, _rng.randf_range(10, 20)),
			_plaster[_rng.randi() % _plaster.size()])
	var minaret := _kit_scene(MINARET_2)
	for p: Vector3 in [Vector3(-60, 0, 120), Vector3(70, 0, -55)]:
		if minaret:
			_one_off(minaret, p, 0.0)
		else:
			_minaret(p, 26.0)
	_citadel()


## The citadel: a rocky hill, crenellated walls with round towers round its top, and a great
## domed mosque with two pencil minarets (Muhammad Ali's, seen from the old city).
func _citadel() -> void:
	var c := CITADEL_AT
	var hill := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 100.0
	sm.height = 100.0
	hill.mesh = sm
	hill.material_override = _sand
	_deco.add_child(hill)
	hill.position = c + Vector3.UP * (CITADEL_HILL - 50.0)
	hill.scale = Vector3(1.0, 1.0, 0.8)
	var top := c + Vector3.UP * CITADEL_HILL
	var stone: StandardMaterial3D = _plaster[4]
	var w := 110.0
	var d := 80.0
	for side: Array in [[Vector3(0, 0, -d * 0.5), Vector3(w, 0, 3)], [Vector3(0, 0, d * 0.5), Vector3(w, 0, 3)],
			[Vector3(-w * 0.5, 0, 0), Vector3(3, 0, d)], [Vector3(w * 0.5, 0, 0), Vector3(3, 0, d)]]:
		var sz: Vector3 = side[1]
		_mesh(top + side[0] + Vector3.UP * 6.0, Vector3(sz.x, 12.0, sz.z), stone)
		for k in int(maxf(sz.x, sz.z) / 6.0):  # crenellations
			var u := -maxf(sz.x, sz.z) * 0.5 + 3.0 + k * 6.0
			var along := Vector3(u, 0, 0) if sz.x > sz.z else Vector3(0, 0, u)
			_mesh(top + side[0] + along + Vector3.UP * 12.8, Vector3(2.0 if sz.x > sz.z else 3.2, 1.6, 3.2 if sz.x > sz.z else 2.0), stone)
	for corner: Vector3 in [Vector3(-w, 0, -d), Vector3(w, 0, -d), Vector3(-w, 0, d), Vector3(w, 0, d), Vector3(0, 0, d)]:
		var tower := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 6.0
		cm.bottom_radius = 7.0
		cm.height = 16.0
		tower.mesh = cm
		tower.material_override = stone
		_deco.add_child(tower)
		tower.position = top + corner * 0.5 + Vector3.UP * 8.0
	# The mosque: a block, a great dome and half-domes, two pencil minarets.
	var m := top + Vector3(-10, 0, -8)
	_mesh(m + Vector3.UP * 9.0, Vector3(36, 18, 36), _plaster[0])
	var dome := MeshInstance3D.new()
	var ds := SphereMesh.new()
	ds.radius = 13.0
	ds.height = 22.0
	dome.mesh = ds
	dome.material_override = _plaster[0]
	_deco.add_child(dome)
	dome.position = m + Vector3.UP * 22.0
	for k in 4:
		var hd := MeshInstance3D.new()
		var hs := SphereMesh.new()
		hs.radius = 7.0
		hs.height = 9.0
		hd.mesh = hs
		hd.material_override = _plaster[0]
		_deco.add_child(hd)
		hd.position = m + Vector3(cos(k * PI * 0.5), 0, sin(k * PI * 0.5)) * 14.0 + Vector3.UP * 18.5
	var mn := _kit_scene(MINARET_2)
	for x: float in [-19.0, 19.0]:
		var at := m + Vector3(x, 0, 19.0)
		if mn:
			var mi := _one_off(mn, at, 0.0)
			mi.scale = Vector3.ONE * 1.3  # (taller and slimmer than the old city's)
		else:
			_minaret(at, 50.0)


## Lamps along the Boulevard and the Old Street, a truck parked on the Boulevard, carts in the
## station square and the souk, and crates to duck behind (Cairo's street life, re-placed).
func _v2_street_life() -> void:
	for x in range(44, 205, 16):
		_street_lamp(Vector3(x, 0, 58.6))
		_street_lamp(Vector3(x + 8, 0, 65.4))
	for z in range(80, 200, 18):  # (not 74: that row put a lamp post in the tavern's doorway at z 128)
		_street_lamp(Vector3(96.6, 0, z))
		_street_lamp(Vector3(103.4, 0, z + 9))
	var truck := _box(_nav, Vector3(88, 1.1, 64.2), Vector3(2.1, 2.2, 5.0), _wood)
	truck.rotation.y = PI * 0.5
	_dress_native(truck, "vehicle_truck.glb")
	_cart(Vector3(34, 0, 46), 0.2)
	_cart(Vector3(171, 0, 137.6), PI * 0.5)
	for p: Array in [[Vector3(98, 0, 112), Vector3(0.9, 1.0, 2.4)], [Vector3(102.5, 0, 150), Vector3(0.9, 1.0, 2.0)],
			[Vector3(158, 0, 132.5), Vector3(2.0, 1.0, 0.9)], [Vector3(36, 0, 60), Vector3(2.4, 1.0, 0.8)],
			[Vector3(126, 0, 106.5), Vector3(2.0, 1.0, 0.9)]]:
		var crate := _box(_nav, p[0] + Vector3.UP * p[1].y * 0.5, p[1], _wood)
		_mark_cover(crate, p[1])
		_dress(crate, "prop_crate_large.glb", Vector3(1.0, 0.52, 0.49))


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
		var steps := _kit_scene(QUAY_STEPS)
		for z in range(3, int(V2_SOUTH), 6):
			var m: Node3D = (steps if steps and z % 30 == 9 else qw).instantiate()
			_deco.add_child(m)
			m.rotation.y = PI * 0.5  # its front (+Z) to the river (+X)
			m.global_position = Vector3(V2_RIVER_X + 0.03 - _front_z(m), -3.0, float(z))
	# The landing stage where the steamer ties up.
	_box(_nav, Vector3(V2_RIVER_X + 4.0, -0.25, 90.0), Vector3(8.0, 0.5, 4.0), _wood)
	for z in [100.0, 107.0, 114.0]:
		_street_lamp(Vector3(V2_RIVER_X - 2.0, 0, z))
