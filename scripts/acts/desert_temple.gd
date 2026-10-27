class_name DesertTemple
extends Level
## The Temple of the Three on the desert road (Act 3's temple_visit, Act 8's temple_battle):
## about 100 x 140 m of sand with a half-buried temple on a north-south axis, found in the
## twenties and only half dug out. From the south: the pylon gate (two towers, sand drifted up
## against them), the columned court with fire pillars, the hypostyle hall, and the sanctuary
## with the statues of Anubis, Horus and Ra on their plinths. The sanctuary's east wall carries
## the procession reliefs (the clue). Behind the statues a slab in the back wall hides a buried
## passage north and out into the dunes (open_rear_passage(); the way out for those who know
## the building). Reuses Level's helpers and the dungeon kit (columns, glyph walls, fire pillars).
##   player_spawn         outside the pylon, facing north
##   court_centre         the middle of the court (the battle starts here)
##   relief_spot          where to stand to study the reliefs
##   rear_door / rear_exit   the slab, and the far end of the passage
##   servant_spawns       where the guardian's servants come from (outside the walls)
## Interactables: "temple_relief" (the act wires it), "rear_passage" (shown with temple_known).

const W := 100.0
const D := 140.0
const AXIS := 50.0
const PYLON_Z := 100.0
const COURT := Rect2(30, 58, 40, 39)       # x, z
const HALL := Rect2(34, 42, 32, 16)
const SANCTUARY := Rect2(36, 20, 28, 22)
const STATUES := {"anubis": 42.0, "horus": 50.0, "ra": 58.0}  # x, standing at z 24
const SLAB_X := 55.0                       # the hidden slab in the back wall (z 20)
const PASSAGE_END_Z := 5.0

var court_centre := Vector3(AXIS, 0, 80)
var relief_spot := Vector3(62.2, 0, 31)
var rear_door := Vector3(SLAB_X, 0, 21.5)
var rear_exit := Vector3(SLAB_X, 0, PASSAGE_END_Z - 1.5)
var servant_spawns: Array[Vector3] = [
	Vector3(46, 0, 118), Vector3(54, 0, 120), Vector3(50, 0, 126),     # out past the pylon
	Vector3(18, 0, 72), Vector3(20, 0, 80),                            # the west gap
	Vector3(82, 0, 66), Vector3(84, 0, 86),                            # the east breach
]
var rear_open := false
var _slab: StaticBody3D
var _fires: Array[Node3D] = []


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
	_box(_nav, Vector3(W * 0.5, -0.5, D * 0.5), Vector3(W, 1.0, D), _sand)
	_edges()
	_pylon()
	_court()
	_hall()
	_sanctuary()
	_passage()
	_drifts()
	player_spawn = Vector3(AXIS, 0, 125)
	interactables["temple_relief"] = Interactable.make(self, relief_spot + Vector3.UP * 1.0, "Study the reliefs", "temple_relief", 1.2)
	var rear := Interactable.make(self, rear_door + Vector3.UP * 1.0, "Push the slab behind the statues", "rear_passage", 1.2)
	rear.when = {"flag": "temple_known"}
	interactables["rear_passage"] = rear
	_environment()
	set_night(0.0)
	_nav.bake_navigation_mesh(false)


# ---------------------------------------------------------------- the temple

## A wall run from a to b (on the ground), `h` high, `t` thick.
func _wall(a: Vector3, b: Vector3, h: float, t := 1.4) -> StaticBody3D:
	var mid := (a + b) * 0.5
	var along_x := absf(b.x - a.x) > absf(b.z - a.z)
	var size := Vector3(absf(b.x - a.x) + t, h, t) if along_x else Vector3(t, h, absf(b.z - a.z) + t)
	return _box(_nav, mid + Vector3.UP * h * 0.5, size, _stone)


## A column: the dungeon kit's papyrus or lotus column (5 m) over a cylinder that keeps the
## collision (and stands in if the prop is missing).
func _column(at: Vector3, kind := "papyrus") -> void:
	var col := _cylinder(_nav, at + Vector3.UP * 3.0, 0.72, 6.0)
	if _prop(col, "dungeon/pillar_%s.glb" % kind, at, 0.0, Vector3(1.0, 1.2, 1.0)):
		(col.get_child(1) as MeshInstance3D).visible = false


func _fire_pillar(at: Vector3) -> void:
	var base := _box(_nav, at + Vector3.UP * 0.9, Vector3(0.8, 1.8, 0.8), _stone)
	if _prop(base, "dungeon/fire_pillar.glb", at):
		(base.get_child(1) as MeshInstance3D).visible = false
	(base.get_child(1) as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var holder := Node3D.new()
	add_child(holder)
	holder.position = at
	_flame(holder, Vector3.UP * 2.1, 3.0, 13.0, false)
	_fires.append(holder)


## A row of glyph panels along a wall's inner face (`n` = the way the face looks).
func _glyphs(from: Vector3, to: Vector3, n: Vector3, y := 0.0, file := "") -> void:
	var count := int(from.distance_to(to) / 2.0)
	var files := ["dungeon/wall_glyph_a.glb", "dungeon/wall_glyph_b.glb", "dungeon/wall_glyph_c.glb"]
	for k in count:
		var p := from.lerp(to, (k + 0.5) / count) + n * 0.2 + Vector3.UP * y
		_prop(self, file if file != "" else files[k % files.size()], p, atan2(n.x, n.z))


## The pylon: two tapering towers either side of the gate, a lintel, the frieze.
func _pylon() -> void:
	var gap := 5.0
	for side in [-1.0, 1.0]:
		var cx: float = AXIS + side * (gap * 0.5 + 6.0)
		_box(_nav, Vector3(cx, 4.0, PYLON_Z), Vector3(12.0, 8.0, 7.0), _stone)
		_box(_nav, Vector3(cx - side * 0.4, 10.0, PYLON_Z), Vector3(10.6, 4.0, 5.6), _stone)
		_box(_nav, Vector3(cx - side * 0.7, 12.6, PYLON_Z), Vector3(9.8, 1.2, 5.0), _floor_mat)
		_glyphs(Vector3(cx - 4.5, 0, PYLON_Z + 3.5), Vector3(cx + 4.5, 0, PYLON_Z + 3.5), Vector3(0, 0, 1), 9.2, "dungeon/wall_glyph_frieze.glb")
	_box(_nav, Vector3(AXIS, 8.6, PYLON_Z), Vector3(gap + 1.0, 1.6, 6.0), _floor_mat)  # lintel
	# Half-buried: a sand ramp drifted up against each tower's outer face.
	for side in [-1.0, 1.0]:
		var dune := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 6.0
		sm.height = 12.0
		dune.mesh = sm
		dune.material_override = _sand
		add_child(dune)
		dune.position = Vector3(AXIS + side * 14.0, -1.6, PYLON_Z + 4.0)
		dune.scale = Vector3(1.4, 0.55, 1.0)


func _court() -> void:
	var r := COURT
	var h := 6.0
	# South wall either side of the pylon, west wall with a gap (z 70-77), east wall broken low.
	_wall(Vector3(r.position.x, 0, r.end.y), Vector3(AXIS - 14.5, 0, r.end.y), h)
	_wall(Vector3(AXIS + 14.5, 0, r.end.y), Vector3(r.end.x, 0, r.end.y), h)
	_wall(Vector3(r.position.x, 0, r.position.y), Vector3(r.position.x, 0, 70.0), h)
	_wall(Vector3(r.position.x, 0, 77.0), Vector3(r.position.x, 0, r.end.y), h)
	_wall(Vector3(r.end.x, 0, r.position.y), Vector3(r.end.x, 0, 74.0), h)
	_wall(Vector3(r.end.x, 0, 82.0), Vector3(r.end.x, 0, r.end.y), h)
	var low := _wall(Vector3(r.end.x, 0, 74.6), Vector3(r.end.x, 0, 81.4), 1.1)  # the east breach: rubble you can vault
	_mark_cover(low, Vector3(1.4, 1.1, 8.2))
	# North wall with the doorway into the hall.
	_wall(Vector3(r.position.x, 0, r.position.y), Vector3(AXIS - 3.0, 0, r.position.y), h)
	_wall(Vector3(AXIS + 3.0, 0, r.position.y), Vector3(r.end.x, 0, r.position.y), h)
	# Two rows of columns; a few lie broken across the court (cover).
	var rng := RandomNumberGenerator.new()
	rng.seed = 3305
	for i in 5:
		var z := 64.0 + i * 6.0
		for x in [37.0, 63.0]:
			if (i == 1 and x < 50.0) or (i == 3 and x > 50.0):
				var size := Vector3(1.1, 1.1, 4.4)
				var fallen := _box(_nav, Vector3(x + (3.0 if x < 50.0 else -3.0), 0.55, z), size, _stone)
				fallen.rotation.y = rng.randf_range(-0.5, 0.5)
				_mark_cover(fallen, size)
			else:
				_column(Vector3(x, 0, z), "papyrus" if i % 2 == 0 else "lotus")
	for p in [Vector3(41, 0, 62), Vector3(59, 0, 62), Vector3(41, 0, 93), Vector3(59, 0, 93)]:
		_fire_pillar(p)
	# Low offering tables and sand heaps to fight from.
	for p in [[Vector3(46, 0, 72), Vector3(2.6, 1.0, 1.2)], [Vector3(54, 0, 84), Vector3(2.6, 1.0, 1.2)],
			[Vector3(44, 0, 88), Vector3(1.2, 1.0, 2.4)], [Vector3(56, 0, 66), Vector3(1.2, 1.0, 2.4)]]:
		var t := _box(_nav, p[0] + Vector3.UP * p[1].y * 0.5, p[1], _floor_mat)
		_mark_cover(t, p[1])


func _hall() -> void:
	var r := HALL
	var h := 7.0
	_wall(Vector3(r.position.x, 0, r.position.y), Vector3(r.position.x, 0, r.end.y), h)
	_wall(Vector3(r.end.x, 0, r.position.y), Vector3(r.end.x, 0, r.end.y), h)
	# The hall's north wall is the sanctuary's front, with its doorway on the axis.
	_wall(Vector3(r.position.x, 0, r.position.y), Vector3(AXIS - 2.5, 0, r.position.y), h)
	_wall(Vector3(AXIS + 2.5, 0, r.position.y), Vector3(r.end.x, 0, r.position.y), h)
	for x in [40.0, 46.0, 54.0, 60.0]:
		for z in [47.0, 53.0]:
			var col := _box(_nav, Vector3(x, 3.5, z), Vector3(1.5, 7.0, 1.5), _stone)
			if _prop(col, "dungeon/pillar_square_glyph.glb", Vector3(x, 0, z), 0.0, Vector3(1.0, 1.4, 1.0)):
				(col.get_child(1) as MeshInstance3D).visible = false
	# Half a roof: the north end of the hall is still covered (shade, and dark at night).
	_box(_nav, Vector3(AXIS, h + 0.4, r.position.y + 4.0), Vector3(r.size.x + 1.4, 0.8, 8.0), _floor_mat)
	_glyphs(Vector3(r.position.x + 0.7, 0, r.position.y + 2), Vector3(r.position.x + 0.7, 0, r.end.y - 2), Vector3(1, 0, 0))
	_glyphs(Vector3(r.end.x - 0.7, 0, r.position.y + 2), Vector3(r.end.x - 0.7, 0, r.end.y - 2), Vector3(-1, 0, 0))


func _sanctuary() -> void:
	var r := SANCTUARY
	var h := 8.0
	_wall(Vector3(r.position.x, 0, r.position.y), Vector3(r.position.x, 0, r.end.y), h)
	_wall(Vector3(r.end.x, 0, r.position.y), Vector3(r.end.x, 0, r.end.y), h)
	# Back wall, with the slab's gap.
	_wall(Vector3(r.position.x, 0, r.position.y), Vector3(SLAB_X - 2.2, 0, r.position.y), h)
	_wall(Vector3(SLAB_X + 2.2, 0, r.position.y), Vector3(r.end.x, 0, r.position.y), h)
	_box(_nav, Vector3(SLAB_X, 6.0, r.position.y), Vector3(4.4, 4.0, 1.4), _stone)  # over the slab
	_slab = _box(_nav, Vector3(SLAB_X, 2.0, r.position.y), Vector3(3.0, 4.0, 1.2), _floor_mat)
	_slab.name = "RearSlab"
	_box(_nav, Vector3(AXIS, h + 0.4, (r.position.y + r.end.y) * 0.5), Vector3(r.size.x + 1.4, 0.8, r.size.y + 1.4), _floor_mat)  # roof
	# The three gods on their plinths along the back, facing the door.
	for id in STATUES:
		var p := Vector3(STATUES[id], 0, r.position.y + 4.0)
		_box(_nav, p + Vector3.UP * 0.3, Vector3(2.6, 0.6, 2.6), _stone)
		var foot: Vector2 = {"anubis": Vector2(1.12, 1.58), "horus": Vector2(1.14, 1.33), "ra": Vector2(1.39, 1.78)}[id]
		var statue := _box(_nav, p + Vector3.UP * 2.6, Vector3(foot.x, 4.0, foot.y), _floor_mat)
		statue.set_meta("statue", id)
		if _prop(self, "statue_%s.glb" % id, p + Vector3.UP * 0.6):
			(statue.get_child(1) as MeshInstance3D).visible = false
	# The procession reliefs on the east wall (the clue), glyphs on the west.
	_glyphs(Vector3(r.end.x - 0.7, 0, r.position.y + 3), Vector3(r.end.x - 0.7, 0, r.end.y - 3), Vector3(-1, 0, 0))
	_glyphs(Vector3(r.end.x - 0.7, 0, r.position.y + 3), Vector3(r.end.x - 0.7, 0, r.end.y - 3), Vector3(-1, 0, 0), 2.6, "dungeon/wall_glyph_frieze.glb")
	_glyphs(Vector3(r.position.x + 0.7, 0, r.position.y + 3), Vector3(r.position.x + 0.7, 0, r.end.y - 3), Vector3(1, 0, 0))
	# Braziers so the sanctuary isn't black under its roof.
	for p in [Vector3(39, 0, 38), Vector3(61, 0, 38)]:
		_brazier(p)


## The buried passage behind the slab: a roofed corridor north under the sand, out into the dunes.
func _passage() -> void:
	var z0 := SANCTUARY.position.y - 0.7
	var z1 := PASSAGE_END_Z
	var mid := (z0 + z1) * 0.5
	for side in [-1.0, 1.0]:
		_box(_nav, Vector3(SLAB_X + side * 2.2, 1.75, mid), Vector3(1.0, 3.5, z0 - z1), _stone)
	_box(_nav, Vector3(SLAB_X, 3.8, mid), Vector3(5.4, 0.6, z0 - z1), _stone)
	# Sand heaped over it, and the hole it comes out of.
	var heap := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 6.0
	sm.height = 12.0
	heap.mesh = sm
	heap.material_override = _sand
	add_child(heap)
	heap.position = Vector3(SLAB_X, -1.8, mid)
	heap.scale = Vector3(0.75, 0.55, 1.5)
	for k in 3:
		var t := _wall_torch_at(Vector3(SLAB_X - 1.6, 2.2, z0 - 3.0 - k * 4.5), Vector3(1, 0, 0))
		t.visible = false  # lit when the passage opens
		t.set_meta("passage", true)


## A torch on a passage wall (unlit flame holder; open_rear_passage shows them).
func _wall_torch_at(at: Vector3, n: Vector3) -> Node3D:
	var holder := Node3D.new()
	add_child(holder)
	holder.position = at + n * 0.15
	RenderBudget.quiet(_prop(holder, "dungeon/wall_sconce.glb", holder.global_position, atan2(n.x, n.z)), 30.0)  # no shadow, not drawn far off
	_flame(holder, Vector3.UP * 0.3, 1.8, 7.0, false)
	return holder


## Sand drifted through the ruin: low mounds (meshes only) and a few dunes beyond the walls.
func _drifts() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2117
	for i in 14:
		var p := Vector3(rng.randf_range(32, 68), -0.9, rng.randf_range(60, 95))
		if absf(p.x - AXIS) < 4.0:
			continue
		var m := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = rng.randf_range(1.5, 3.0)
		sm.height = sm.radius * 2.0
		m.mesh = sm
		m.material_override = _sand
		add_child(m)
		m.position = p
		m.scale = Vector3(1.4, 0.45, 1.0)


func _edges() -> void:
	for e in [
		[Vector3(-0.5, 5, D * 0.5), Vector3(1, 10, D)], [Vector3(W + 0.5, 5, D * 0.5), Vector3(1, 10, D)],
		[Vector3(W * 0.5, 5, -0.5), Vector3(W, 10, 1)], [Vector3(W * 0.5, 5, D + 0.5), Vector3(W, 10, 1)],
	]:
		var b := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = e[1]
		cs.shape = bs
		b.add_child(cs)
		add_child(b)
		b.position = e[0]
	var far := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(700, 700)
	far.mesh = plane
	far.material_override = _sand
	add_child(far)
	far.position = Vector3(W * 0.5, -0.03, D * 0.5)
	var rng := RandomNumberGenerator.new()
	rng.seed = 909
	for i in 36:
		var a := TAU * i / 36.0
		var radius := rng.randf_range(10, 20)
		var dune := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = radius
		sm.height = radius * 2.0
		dune.mesh = sm
		dune.material_override = _sand
		add_child(dune)
		var out := maxf(W, D) * 0.5 + radius * 1.6 + rng.randf_range(4, 14)
		dune.position = Vector3(W * 0.5 + cos(a) * out * 0.8, -radius * 0.15, D * 0.5 + sin(a) * out)
		dune.scale = Vector3(1.6, 0.4, 1.6)


# ---------------------------------------------------------------- the way out

## The slab grinds down into the floor; the passage's torches catch; the navmesh opens.
func open_rear_passage() -> void:
	if rear_open:
		return
	rear_open = true
	for n in get_children():
		if n is Node3D and n.has_meta("passage"):
			(n as Node3D).visible = true
	var tw := create_tween()
	tw.tween_property(_slab, "position:y", -2.2, 2.0).set_trans(Tween.TRANS_SINE)
	await tw.finished
	(_slab.get_child(0) as CollisionShape3D).disabled = true
	_nav.bake_navigation_mesh(false)


# ---------------------------------------------------------------- light

## 0 = day, 1 = night: the sun goes, moonlight, the fire pillars and braziers carry it.
func set_night(f: float) -> void:
	if _sun == null:
		return
	_sun.light_energy = lerpf(1.6, 0.16, f)
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
	for fire in _fires:
		fire.visible = f > 0.3


func set_indoor(_f: float) -> void:
	pass  # open to the sky: day / night is set_night's job
