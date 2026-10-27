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
	var nm := Level.nav_mesh()  # (0.3 m climb was 0.25 in whole cells all along)
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
	_camp_fires()
	_dress_ruins()
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
				_broken_column(p, side, rng)


## A column that came down (Simon: the fallen ones were whole columns lying in a straight line
## beside their places): a jagged stump where it stood, and its drums thrown down every which way,
## out from the colonnade, some cracked in two. The drums are low cover.
func _broken_column(p: Vector3, side: float, rng: RandomNumberGenerator) -> void:
	var stump_h := rng.randf_range(0.5, 1.7)
	_drum(p + Vector3.UP * stump_h * 0.5, stump_h, Basis(), rng)
	var fall := Vector3(side, 0, rng.randf_range(-0.9, 0.9)).normalized()
	var at := p + fall * (1.2 + rng.randf_range(0.0, 0.6))
	for j in rng.randi_range(2, 3):
		var length := rng.randf_range(0.9, 1.5)
		var lie := Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.RIGHT, PI * 0.5)  # on its side, any heading
		var drum := _drum(at + Vector3.UP * 0.62, length, lie, rng)
		_mark_cover(drum, Vector3(1.1, 1.0, length))
		at += fall.rotated(Vector3.UP, rng.randf_range(-0.7, 0.7)) * (length + rng.randf_range(0.2, 0.9))


## One column drum: a stone cylinder (r 0.62) of `length`, at `centre`, turned by `turn`.
func _drum(centre: Vector3, length: float, turn: Basis, rng: RandomNumberGenerator) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("drum", true)
	var cs := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 0.62
	shape.height = length
	cs.shape = shape
	body.add_child(cs)
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.6 * rng.randf_range(0.9, 1.0)  # weathered, not turned on a lathe
	cm.bottom_radius = 0.62
	cm.height = length
	cm.radial_segments = 14
	mi.mesh = cm
	mi.material_override = _stone
	body.add_child(mi)
	_nav.add_child(body)
	body.global_transform = Transform3D(turn, centre)
	return body


func _site_landmark(id: String, p: Vector3) -> void:
	match id:
		"anubis", "horus", "ra":
			# image-to-3d's statue (4 m with its base, facing +Z, toward the camps) on a wider
			# plinth; the box keeps the collision, and stands in if the model is missing.
			_box(_nav, p + Vector3.UP * 0.3, Vector3(2.6, 0.6, 2.6), _stone)
			var foot: Vector2 = {"anubis": Vector2(1.12, 1.58), "horus": Vector2(1.14, 1.33), "ra": Vector2(1.39, 1.78)}[id]
			var statue := _box(_nav, p + Vector3.UP * 2.6, Vector3(foot.x, 4.0, foot.y), _floor_mat)
			statue.set_meta("statue", id)
			if _prop(self, "statue_%s.glb" % id, p + Vector3.UP * 0.6):
				(statue.get_child(1) as MeshInstance3D).visible = false
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
			# ...with a shallow ramp up onto it on every side (Simon: you couldn't get up on it).
			for dir in [Vector3.FORWARD, Vector3.BACK, Vector3.LEFT, Vector3.RIGHT]:
				var ramp := _box(_nav, Vector3.ZERO, Vector3(5.0, 0.3, 2.05), _floor_mat)
				# Its length (-Z) points out from the edge, tipped so the outer end meets the sand.
				var tilt := Basis.looking_at(dir, Vector3.UP) * Basis(Vector3.RIGHT, -atan2(0.3, 2.0))
				ramp.global_transform = Transform3D(tilt, p + dir * 5.0 + Vector3.UP * 0.15 - tilt.y * 0.15)
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


# ---------------------------------------------------------------- dressing (looks only)

const KIT := "dungeon/"
const GLYPH := Vector3(2.0, 2.5, 0.4)   # a glyph wall block; its carved face is +Z
const FRIEZE := Vector3(2.0, 0.6, 0.45)
const COLUMN_H := 5.0                    # the kit's columns, 1.5 across


## The dungeon kit over the blockout, without moving anything: carved glyph blocks on the stone
## walls (MultiMesh, stretched to each wall), friezes along the tall ones, papyrus and lotus
## columns over the standing cylinders, lying columns over the fallen ones, the obelisk as a
## square glyph pillar. Collision and cover stay the boxes they were.
func _dress_ruins() -> void:
	var designs := [_kit_mesh("wall_glyph_a"), _kit_mesh("wall_glyph_b"), _kit_mesh("wall_glyph_c")]
	var frieze := _kit_mesh("wall_glyph_frieze")
	var blocks: Array = [[], [], []]
	var tops: Array[Transform3D] = []
	var n := 0
	for body in _nav.get_children():
		if not body is StaticBody3D or body.get_child_count() < 2:
			continue
		var mi := body.get_child(1) as MeshInstance3D
		var cs := body.get_child(0) as CollisionShape3D
		if mi == null or cs == null or mi.material_override != _stone or body.has_meta("drum"):
			continue  # (a fallen column's drums and stump stay plain broken stone)
		n += 1
		if cs.shape is CylinderShape3D:
			var cyl := cs.shape as CylinderShape3D
			var foot: Vector3 = body.position - Vector3.UP * cyl.height * 0.5
			var kind := "papyrus" if n % 2 == 0 else "lotus"
			var w := cyl.radius / 0.75
			if _prop(body, KIT + "pillar_%s.glb" % kind, foot, n * 0.7, Vector3(w, cyl.height / COLUMN_H, w)):
				mi.visible = false
			continue
		if not cs.shape is BoxShape3D:
			continue
		var size: Vector3 = (cs.shape as BoxShape3D).size
		var long := maxf(size.x, size.z)
		var short := minf(size.x, size.z)
		if size.y > 4.0 and long < 1.6:
			# The obelisk: the kit's square glyph pillar, stretched to its height.
			if _prop(body, KIT + "pillar_square_glyph.glb", body.position - Vector3.UP * size.y * 0.5, 0.0,
					Vector3(long / 1.48, size.y / COLUMN_H, long / 1.48)):
				mi.visible = false
		elif short < 1.3 and size.y < 1.3 and long > 2.5 and absf(size.y - short) < 0.05 and body.is_in_group("cover"):
			# A fallen column (square in section, lying along its length): a column on its side.
			var along_z := size.z >= size.x
			var p := _prop(body, KIT + "pillar_%s.glb" % ("lotus" if n % 2 == 0 else "papyrus"), body.global_position)
			if p:
				var w := short / 1.5
				p.basis = Basis(Vector3.RIGHT if along_z else Vector3.BACK, PI * 0.5).scaled_local(Vector3(w, long / COLUMN_H, w))
				p.position = Vector3(0, 0, -long * 0.5) if along_z else Vector3(long * 0.5, 0, 0)
				mi.visible = false
		elif short <= 1.8 and long >= 2.0 and size.y >= 0.8:
			_glyph_faces(body as StaticBody3D, size, blocks, tops, designs.has(null), frieze != null)
	if not designs.has(null):
		for i in 3:
			_multimesh(designs[i], blocks[i])
	if frieze:
		_multimesh(frieze, tops)


## Glyph blocks over both long faces of a wall box, stretched so whole blocks fill it exactly,
## and a frieze along the top of the tall ones.
func _glyph_faces(body: StaticBody3D, size: Vector3, blocks: Array, tops: Array[Transform3D], no_blocks: bool, has_frieze: bool) -> void:
	var along_x := size.x >= size.z
	var long := size.x if along_x else size.z
	var short := size.z if along_x else size.x
	var cols := maxi(1, roundi(long / GLYPH.x))
	var rows := maxi(1, roundi(size.y / GLYPH.y))
	var sx := long / (cols * GLYPH.x)
	var sy := size.y / (rows * GLYPH.y)
	var xf := body.global_transform
	for side in [-1.0, 1.0]:
		# In the wall's own frame: `out` is the face's normal, `run` along the wall.
		var out := Vector3(0, 0, side) if along_x else Vector3(side, 0, 0)
		var run := Vector3(1, 0, 0) if along_x else Vector3(0, 0, 1)
		var turn := xf.basis * Basis.looking_at(-out, Vector3.UP)  # +Z = out, in the world
		for c in cols:
			for r in rows:
				if no_blocks:
					break
				var local := out * (short * 0.5 - GLYPH.z * 0.5 + 0.02) + run * ((c + 0.5) * GLYPH.x * sx - long * 0.5) \
					+ Vector3.UP * (r * GLYPH.y * sy - size.y * 0.5)
				var pick := absi(int(body.position.x) * 7 + int(body.position.z) * 13 + c * 5 + r * 3) % 3
				(blocks[pick] as Array).append(Transform3D(turn.scaled_local(Vector3(sx, sy, 1.0)), xf * local))
			if has_frieze and size.y >= 3.0:
				var top := out * (short * 0.5 - FRIEZE.z * 0.5 + 0.05) + run * ((c + 0.5) * GLYPH.x * sx - long * 0.5) \
					+ Vector3.UP * (size.y * 0.5 - FRIEZE.y)
				tops.append(Transform3D(turn.scaled_local(Vector3(sx, 1.0, 1.0)), xf * top))


## Two fire pillars at each camp, out to the sides of the ring (clear of the ways in and out).
func _camp_fires() -> void:
	for id in CAMPS:
		for side in [-1.0, 1.0]:
			var at: Vector3 = CAMPS[id] + Vector3(side * 9.0, 0, -5.5)
			var base := _box(_nav, at + Vector3.UP * 1.5, Vector3(0.9, 3.0, 0.9), _stone)
			(base.get_child(1) as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			if _prop(base, KIT + "fire_pillar_tall.glb", at):
				(base.get_child(1) as MeshInstance3D).visible = false
			var holder := Node3D.new()
			add_child(holder)
			holder.position = at
			_flame(holder, Vector3.UP * 3.25, 2.4, 11.0, false)


func _multimesh(mesh: Mesh, xforms: Array) -> void:
	if xforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	add_child(mmi)


## The mesh inside one of the kit's GLBs (they're single-mesh props), or null if missing.
func _kit_mesh(file: String) -> Mesh:
	var path := PROPS + KIT + file + ".glb"
	if not ResourceLoader.exists(path):
		return null
	var scene := (load(path) as PackedScene).instantiate()
	var found := scene.find_children("*", "MeshInstance3D", true, false)
	var mesh: Mesh = (found[0] as MeshInstance3D).mesh if not found.is_empty() else null
	scene.free()
	return mesh


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
