class_name Level
extends Node3D
## Desert topside above a tomb built from a character map. One cell = CELL metres.
## Tomb floor is at FLOOR_Y; the ground (and tomb ceiling slab) top is at y = 0.
## '#' wall  '.' floor  'P' pillar  'B' brazier  'L' wall torch (wall cell)
## 'S' sarcophagus (a mummy rises from it later)  'M' dormant mummy
## 'D' stairwell (ramp up to the surface; the high end is the south end)
## 'W' waist-high broken wall: cover you can vault (see Cover)

const CELL := 2.0
const FLOOR_Y := -6.0
const WALL_H := 5.0
const MAP := [
	"########################################",
	"#........###.......SS.......###........#",
	"#.M......###..P..B....B..P..###......M.#",
	"#........###................###........#",
	"#..B..B..###...P...M....P...###..B..B..#",
	"#........###...W........W...###........#",
	"#......M.###..P..B....B..P..###.M......#",
	"#........###S..............S###........#",
	"#........###....M......M....###........#",
	"#........###................###........#",
	"####..#############..#############..####",
	"###L..L###########L..L###########L..L###",
	"####..#############..#############..####",
	"#......................................#",
	"#...P....P....P......P....P....P....P..#",
	"#.....M..........B..........M..........#",
	"#.....W.......W..........W.......W.....#",
	"#..........B.........M..........B......#",
	"#...P....P....P......P....P....P....P..#",
	"#..........W..........W...........W....#",
	"#.......M..............................#",
	"###################..###################",
	"#############..............#############",
	"#############..B........B..#############",
	"#############..W...M....W..#############",
	"#############..B........B..#############",
	"#############..............#############",
	"###################DD###################",
	"##################LDDL##################",
	"###################DD###################",
	"###################DD###################",
	"##################LDDL##################",
	"###################DD###################",
	"########################################",
]
## Burial chamber, in cells (inclusive): the sarcophagus wave happens here.
const BURIAL := Rect2i(12, 1, 16, 9)
## How far the desert reaches south of the tomb footprint (m).
const SOUTH_EXTENT := 34.0
## The river south of the desert (m wide), with a pier from the bank at x 38-42.
const RIVER_W := 40.0

var player_spawn := Vector3.ZERO
var mummy_spawns: Array[Vector3] = []
var sarcophagi: Array[Node3D] = []
var torches: Array[OmniLight3D] = []
## Save points and other usable things the game wires up (Interactable.id -> node).
var interactables := {}
var _map: Array = []

var _nav: NavigationRegion3D
var _stone: StandardMaterial3D
var _floor_mat: StandardMaterial3D
var _sand: StandardMaterial3D
var _env: Environment
var _sun: DirectionalLight3D
var _rows := 0
var _cols := 0
var _t := 0.0


func _ready() -> void:
	_map = map_rows()
	_rows = _map.size()
	_cols = 0
	for line in _map:
		_cols = maxi(_cols, (line as String).length())
	_make_materials()
	_nav = NavigationRegion3D.new()
	var nm := NavigationMesh.new()
	nm.agent_radius = 0.5
	nm.agent_height = 1.75
	nm.agent_max_climb = 0.25
	nm.agent_max_slope = 40.0
	nm.cell_size = 0.25
	nm.cell_height = 0.25
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_collision_mask = 1
	_nav.navigation_mesh = nm
	add_child(_nav)

	_build_tomb()
	_build_surface()
	_environment()
	_nav.bake_navigation_mesh(false)


func _process(delta: float) -> void:
	_t += delta
	for i in torches.size():
		var l := torches[i]
		var base: float = l.get_meta("base")
		l.light_energy = base * (0.85 + 0.1 * sin(_t * 13.0 + i * 1.7) + 0.06 * sin(_t * 31.0 + i * 4.1))


func _ch(r: int, c: int) -> String:
	var line: String = _map[r]
	return line[c] if c < line.length() else "#"


func _cell(r: int, c: int) -> Vector3:
	return Vector3(c * CELL + CELL * 0.5, FLOOR_Y, r * CELL + CELL * 0.5)


func is_in_burial(pos: Vector3) -> bool:
	var c := int(pos.x / CELL)
	var r := int(pos.z / CELL)
	return pos.y < FLOOR_Y + 3.0 and BURIAL.has_point(Vector2i(c, r))


## 0 out in the sun, 1 deep in the tomb; blends along the stairwell.
func indoor_amount(pos: Vector3) -> float:
	return clampf(-(pos.y + 0.5) / 4.0, 0.0, 1.0)


func set_indoor(f: float) -> void:
	_sun.light_energy = lerpf(1.6, 0.0, f)
	_env.ambient_light_energy = lerpf(0.55, 0.2, f)
	_env.ambient_light_sky_contribution = lerpf(1.0, 0.0, f)
	_env.fog_light_color = Color(0.75, 0.62, 0.45).lerp(Color(0.12, 0.08, 0.05), f)
	_env.fog_density = lerpf(0.004, 0.025, f)
	_env.tonemap_exposure = lerpf(0.9, 1.1, f)


# ---------------------------------------------------------------- tomb

func _build_tomb() -> void:
	# Tomb floor in one slab.
	var size := Vector3(_cols * CELL, 1.0, _rows * CELL)
	var centre := Vector3(_cols * CELL * 0.5, FLOOR_Y - 0.5, _rows * CELL * 0.5)
	_box(_nav, centre, size, _floor_mat)

	var stair := Rect2i()
	for r in _rows:
		var c := 0
		while c < _cols:
			var ch := _ch(r, c)
			var p := _cell(r, c)
			match ch:
				"#", "L":
					# Merge horizontal runs of wall into one box.
					var run := 1
					while c + run < _cols and _ch(r, c + run) in ["#", "L"]:
						run += 1
					var mid := (_cell(r, c) + _cell(r, c + run - 1)) * 0.5
					_box(_nav, mid + Vector3.UP * WALL_H * 0.5, Vector3(run * CELL, WALL_H, CELL), _stone)
					for k in run:
						if _ch(r, c + k) == "L":
							_wall_torch(r, c + k)
					c += run
					continue
				"D":
					stair = Rect2i(c, r, 1, 1) if stair.size == Vector2i.ZERO else stair.expand(Vector2i(c, r))
				"P":
					_box(_nav, p + Vector3.UP * WALL_H * 0.5, Vector3(1.3, WALL_H, 1.3), _stone)
				"B":
					_brazier(p)
				"S":
					_sarcophagus(p, r, c)
				"W":
					var wall_size := Vector3(1.9, 1.1, 0.6)
					_mark_cover(_box(_nav, p + Vector3.UP * wall_size.y * 0.5, wall_size, _stone), wall_size)
				"M":
					mummy_spawns.append(p)
				_:
					if ch != ".":
						_marker(ch, p, r, c)
			c += 1

	# Ceiling slab (= the desert ground) with a hole over the stairwell.
	for r in _rows:
		var c := 0
		while c < _cols:
			if _ch(r, c) == "D":
				c += 1
				continue
			var run := 1
			while c + run < _cols and _ch(r, c + run) != "D":
				run += 1
			var a := _cell(r, c)
			var b := _cell(r, c + run - 1)
			_box(_nav, Vector3((a.x + b.x) * 0.5, -0.5, a.z), Vector3(run * CELL, 1.0, CELL), _sand)
			c += run
	if stair.size != Vector2i.ZERO:
		stair.size += Vector2i.ONE
		_stairs(stair)


func _stairs(cells: Rect2i) -> void:
	# A ramp to walk on, with step meshes over it so it reads as stairs.
	var x0 := cells.position.x * CELL
	var x1 := (cells.position.x + cells.size.x) * CELL
	var z_low := cells.position.y * CELL  # north end, tomb floor
	var z_high := (cells.position.y + cells.size.y) * CELL  # south end, surface
	var run := z_high - z_low
	var rise := -FLOOR_Y
	var slope := atan2(rise, run)
	var len := sqrt(run * run + rise * rise)
	var ramp := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(x1 - x0, 0.4, len)
	cs.shape = bs
	ramp.add_child(cs)
	_nav.add_child(ramp)
	ramp.position = Vector3((x0 + x1) * 0.5, FLOOR_Y + rise * 0.5 - 0.2 / cos(slope), (z_low + z_high) * 0.5)
	ramp.rotation.x = -slope  # high end to the south (+Z)
	var steps := int(rise / 0.3)
	for i in steps:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(x1 - x0, 0.3, run / steps)
		mi.mesh = bm
		mi.material_override = _stone
		add_child(mi)
		mi.position = Vector3((x0 + x1) * 0.5, FLOOR_Y + (i + 0.5) * 0.3, z_low + (i + 0.5) * run / steps)
	# Doorway on the surface: posts, lintel, low side walls.
	var mx := (x0 + x1) * 0.5
	for side in [-1.0, 1.0]:
		_box(_nav, Vector3(mx + side * ((x1 - x0) * 0.5 + 0.6), 2.5, z_high - 0.6), Vector3(1.2, 5.0, 1.2), _stone)
		_box(_nav, Vector3(mx + side * ((x1 - x0) * 0.5 + 0.35), 0.5, (z_low + z_high) * 0.5), Vector3(0.7, 1.0, run), _stone)
	_box(_nav, Vector3(mx, 5.4, z_high - 0.6), Vector3(x1 - x0 + 3.2, 0.8, 1.6), _stone)
	_box(_nav, Vector3(mx, 0.75, z_low - 0.35), Vector3(x1 - x0 + 1.4, 1.5, 0.7), _stone)


# ---------------------------------------------------------------- surface

func _build_surface() -> void:
	var w := _cols * CELL
	var d := _rows * CELL
	# Ground south of the tomb footprint, where you arrive.
	_box(_nav, Vector3(w * 0.5, -0.5, d + SOUTH_EXTENT * 0.5), Vector3(w, 1.0, SOUTH_EXTENT), _sand)
	player_spawn = Vector3(w * 0.5, 0.0, d + SOUTH_EXTENT * 0.55)
	_camp(player_spawn + Vector3(6.0, 0.0, 2.0))

	# Invisible edges, with dunes beyond so it doesn't look like a wall.
	var total_d := d + SOUTH_EXTENT
	for e in [
		[Vector3(-0.5, 5, total_d * 0.5), Vector3(1, 10, total_d)],
		[Vector3(w + 0.5, 5, total_d * 0.5), Vector3(1, 10, total_d)],
		[Vector3(w * 0.5, 5, -0.5), Vector3(w, 10, 1)],
		# South: the riverbank, open only at the pier (x 38-42); the river is crossed by boat.
		[Vector3(19.0, 5, total_d + 0.5), Vector3(38.0, 10, 1)],
		[Vector3(61.0, 5, total_d + 0.5), Vector3(38.0, 10, 1)],
		[Vector3(w * 0.5, 5, total_d + RIVER_W + 0.5), Vector3(w + 400.0, 10, 1)],
	]:
		var b := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = e[1]
		cs.shape = bs
		b.add_child(cs)
		add_child(b)
		b.position = e[0]
	var rng := RandomNumberGenerator.new()
	rng.seed = 1923
	# Far sand only OUTSIDE the play area, so it never covers the stairwell.
	const FAR := 300.0
	for r in [
		Rect2(-FAR, -FAR, w + FAR * 2.0, FAR),  # north
		Rect2(-FAR, total_d + RIVER_W, w + FAR * 2.0, FAR),  # south, past the river
		Rect2(-FAR, 0, FAR, total_d),  # west
		Rect2(w, 0, FAR, total_d),  # east
	]:
		var far := MeshInstance3D.new()
		var plane := PlaneMesh.new()
		plane.size = r.size
		far.mesh = plane
		far.material_override = _sand
		add_child(far)
		far.position = Vector3(r.position.x + r.size.x * 0.5, 0.0, r.position.y + r.size.y * 0.5)
	# Low dunes ringing the edges, kept fully outside the walkable area.
	for i in 48:
		var radius := rng.randf_range(8, 18)
		var reach := radius * 1.6 + 1.0  # widest half-extent after scaling
		var side := i % 4
		var t := rng.randf()
		var out := reach + rng.randf_range(0, 12)
		var pos: Vector3
		match side:
			0: pos = Vector3(lerpf(-20, w + 20, t), 0, -out)
			1: pos = Vector3(lerpf(-20, w + 20, t), 0, total_d + RIVER_W + out)
			2: pos = Vector3(-out, 0, lerpf(-20, total_d + 20, t))
			_: pos = Vector3(w + out, 0, lerpf(-20, total_d + 20, t))
		var dune := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = radius
		sm.height = radius * 2.0
		dune.mesh = sm
		dune.material_override = _sand
		add_child(dune)
		dune.position = pos + Vector3.DOWN * radius * 0.15
		dune.scale = Vector3(1.6, 0.4, 1.6)

	# Ruins: broken columns and wall stubs to move between and hide behind.
	var stair_x := w * 0.5
	var stair_z0 := 27.0 * CELL - 4.0
	var stair_z1 := 33.0 * CELL + 4.0
	var placed := 0
	var tries := 0
	while placed < 34 and tries < 400:
		tries += 1
		var p := Vector3(rng.randf_range(4, w - 4), 0, rng.randf_range(4, total_d - 4))
		if absf(p.x - stair_x) < 7.0 and p.z > stair_z0 and p.z < stair_z1:
			continue
		if p.distance_to(player_spawn) < 6.0:
			continue
		placed += 1
		if rng.randf() < 0.6:
			var h := rng.randf_range(1.0, 5.5)
			var col := _cylinder(_nav, p + Vector3.UP * h * 0.5, 0.65, h)
			col.rotation.z = rng.randf_range(-0.06, 0.06)
		else:
			var len := rng.randf_range(3.0, 7.0)
			# Most stubs are waist-high cover; some stand tall.
			var low := rng.randf() < 0.7
			var h := rng.randf_range(0.95, 1.25) if low else rng.randf_range(1.8, 2.6)
			var size := Vector3(len, h, 0.7 if low else 0.9)
			var wall := _box(_nav, p + Vector3.UP * h * 0.5, size, _stone)
			wall.rotation.y = rng.randf() * PI
			if low:
				_mark_cover(wall, size)
	# An obelisk to steer by.
	_box(_nav, Vector3(w * 0.5, 0.4, d + SOUTH_EXTENT - 8.0), Vector3(3, 0.8, 3), _stone)
	var ob := _box(_nav, Vector3(w * 0.5, 6.5, d + SOUTH_EXTENT - 8.0), Vector3(1.6, 11.5, 1.6), _stone)
	ob.scale = Vector3(1, 1, 1)


## Expedition camp: a campfire (rest = save) and a bedroll (sleep = next day + save).
## Stand-in shapes until image-to-3d's camp props arrive.
func _camp(at: Vector3) -> void:
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.25, 0.22, 0.2)
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.3, 0.18, 0.09)
	for i in 8:
		var a := TAU * i / 8.0
		var stone := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.16
		sm.height = 0.22
		stone.mesh = sm
		stone.material_override = dark
		add_child(stone)
		stone.position = at + Vector3(cos(a), 0.06, sin(a)) * Vector3(0.55, 1, 0.55)
	for i in 3:
		var log := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.06
		cm.bottom_radius = 0.06
		cm.height = 0.8
		log.mesh = cm
		log.material_override = wood
		add_child(log)
		log.position = at + Vector3.UP * 0.1
		log.rotation = Vector3(PI * 0.5, TAU * i / 3.0, 0)
	var fire := Node3D.new()
	add_child(fire)
	fire.position = at
	_flame(fire, Vector3.UP * 0.45, 2.5, 9.0, true)
	interactables["camp_fire"] = Interactable.make(self, at, "Rest by the fire (save)", "camp_fire", 1.2)

	var bed_at := at + Vector3(2.2, 0, 0.8)
	var cloth := StandardMaterial3D.new()
	cloth.albedo_color = Color(0.45, 0.38, 0.26)
	var bed := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.8, 0.12, 1.9)
	bed.mesh = bm
	bed.material_override = cloth
	add_child(bed)
	bed.position = bed_at + Vector3.UP * 0.06
	interactables["camp_bed"] = Interactable.make(self, bed_at, "Sleep (next day, save)", "camp_bed", 1.0)


## A box the player can take cover at (Cover reads the size; the body's origin is its centre).
func _mark_cover(body: StaticBody3D, size: Vector3) -> void:
	body.set_meta("cover_size", size)
	body.add_to_group("cover")
	# Simon: "why does the world go dark if you crouch or take cover?": in the tomb the braziers
	# burn just above these, so their shadow swallowed anyone crouched behind them.
	if body.position.y < FLOOR_Y + 3.0:
		for mi in body.find_children("*", "MeshInstance3D", true, false):
			(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _cylinder(parent: Node, pos: Vector3, radius: float, h: float) -> StaticBody3D:
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = h
	cs.shape = shape
	body.add_child(cs)
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius * 0.9
	cm.bottom_radius = radius
	cm.height = h
	mi.mesh = cm
	mi.material_override = _stone
	body.add_child(mi)
	parent.add_child(body)
	body.position = pos
	return body


# ---------------------------------------------------------------- pieces

func _make_materials() -> void:
	_stone = StandardMaterial3D.new()
	_stone.albedo_texture = _noise_tex(Color(0.36, 0.28, 0.19), Color(0.62, 0.5, 0.34), 0.05, false)
	_stone.normal_enabled = true
	_stone.normal_texture = _noise_tex(Color.BLACK, Color.WHITE, 0.09, true)
	_stone.roughness = 0.95
	_stone.uv1_triplanar = true
	_stone.uv1_scale = Vector3.ONE * 0.25
	_floor_mat = _stone.duplicate()
	_floor_mat.albedo_texture = _noise_tex(Color(0.3, 0.24, 0.16), Color(0.5, 0.41, 0.28), 0.03, false)
	_sand = _stone.duplicate()
	_sand.albedo_texture = _noise_tex(Color(0.7, 0.55, 0.36), Color(0.86, 0.72, 0.5), 0.02, false)
	_sand.uv1_scale = Vector3.ONE * 0.1


func _noise_tex(a: Color, b: Color, freq: float, normal: bool) -> NoiseTexture2D:
	var n := FastNoiseLite.new()
	n.frequency = freq
	n.fractal_octaves = 5
	var t := NoiseTexture2D.new()
	t.noise = n
	t.seamless = true
	t.width = 512
	t.height = 512
	if normal:
		t.as_normal_map = true
		t.bump_strength = 6.0
	else:
		var g := Gradient.new()
		g.set_color(0, a)
		g.set_color(1, b)
		t.color_ramp = g
	return t


func _box(parent: Node, pos: Vector3, size: Vector3, mat: Material) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	shape.shape = bs
	body.add_child(shape)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	body.add_child(mi)
	parent.add_child(body)
	body.position = pos
	return body


func _flame(parent: Node3D, pos: Vector3, energy: float, light_range: float, shadows: bool) -> void:
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.62, 0.3)
	l.light_energy = energy
	l.set_meta("base", energy)
	l.omni_range = light_range
	l.omni_attenuation = 1.3
	parent.add_child(l)
	if shadows:
		RenderBudget.want_shadows(l)  # only the few nearest the camera cast them
	l.position = pos
	torches.append(l)
	# Scarabs keep out of firelight (scarabs.gd reads group "fire"): a wall torch guards a little,
	# a brazier or fire pillar a whole corner. Ambience gives each a crackle too.
	l.add_to_group("fire")
	l.set_meta("fire_radius", 1.2 if light_range < 9.0 else 3.2)
	var fire := CPUParticles3D.new()
	fire.amount = 40
	fire.lifetime = 0.5
	fire.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	fire.emission_sphere_radius = 0.08
	fire.direction = Vector3.UP
	fire.spread = 15.0
	fire.gravity = Vector3(0, 1.5, 0)
	fire.initial_velocity_min = 0.3
	fire.initial_velocity_max = 0.7
	fire.scale_amount_min = 0.6
	fire.scale_amount_max = 1.0
	var curve := Curve.new()
	curve.add_point(Vector2(0, 1))
	curve.add_point(Vector2(1, 0))
	fire.scale_amount_curve = curve
	var qm := QuadMesh.new()
	qm.size = Vector2(0.18, 0.18)
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	fm.albedo_color = Color(1.0, 0.55, 0.15)
	fm.emission_enabled = true
	fm.emission = Color(1.0, 0.5, 0.1)
	fm.emission_energy_multiplier = 4.0
	fm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fm.albedo_texture = Fx.soft_dot()
	fm.emission_texture = Fx.soft_dot()
	fm.vertex_color_use_as_albedo = true
	qm.material = fm
	fire.mesh = qm
	RenderBudget.quiet(fire, 35.0)  # its glow sprites cast no shadows, and stop past 35 m
	parent.add_child(fire)
	fire.position = pos - Vector3.UP * 0.25


func _brazier(p: Vector3) -> void:
	var b := _box(_nav, p + Vector3.UP * 0.5, Vector3(0.6, 1.0, 0.6), _stone)
	# Its own flame sits on top: casting, the base threw a black square around itself.
	(b.get_child(1) as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_flame(b, Vector3.UP * 0.85, 3.0, 11.0, true)


func _wall_torch(r: int, c: int) -> void:
	# Light sits on the face that looks at the nearest floor cell.
	for d in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]:
		var rr: int = r + d.y
		var cc: int = c + d.x
		if rr < 0 or rr >= _rows or cc < 0 or cc >= _cols:
			continue
		if _ch(rr, cc) in ["#", "L"]:
			continue
		var holder := Node3D.new()
		add_child(holder)
		var face := _cell(r, c) + Vector3(d.x, 0, d.y) * (CELL * 0.5 + 0.15)
		holder.position = face + Vector3.UP * 2.4
		var stick := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.04
		cm.bottom_radius = 0.03
		cm.height = 0.45
		stick.mesh = cm
		var wood := StandardMaterial3D.new()
		wood.albedo_color = Color(0.2, 0.12, 0.06)
		stick.material_override = wood
		holder.add_child(stick)
		# The iron bracket (dungeon kit), its cup under the flame, its back plate on the rock.
		var sconce := _prop(holder, "dungeon/wall_sconce.glb", holder.global_position, atan2(float(d.x), float(d.y)))
		if sconce:
			sconce.position = Vector3(d.x, 0, d.y) * -0.12 + Vector3.UP * -0.15
			RenderBudget.quiet(sconce, 30.0)  # 24k tris beside its own flame: no shadow, not drawn far off
			stick.visible = false
		_flame(holder, Vector3.UP * 0.4, 2.2, 8.0, false)
		return


func _sarcophagus(p: Vector3, r: int, c: int) -> void:
	# Lie along a wall: long axis along z if there's wall north of it.
	var along_z: bool = _ch(r - 1, c) in ["#", "L"]
	var size := Vector3(1.0, 0.9, 2.2) if along_z else Vector3(2.2, 0.9, 1.0)
	var base := _box(_nav, p + Vector3.UP * 0.45, size, _stone)
	_mark_cover(base, size)
	var lid := MeshInstance3D.new()
	var lm := BoxMesh.new()
	lm.size = Vector3(size.x + 0.1, 0.18, size.z + 0.1)
	lid.mesh = lm
	var gold := StandardMaterial3D.new()
	gold.albedo_color = Color(0.55, 0.4, 0.15)
	gold.metallic = 0.7
	gold.roughness = 0.45
	lid.material_override = gold
	base.add_child(lid)
	lid.position = Vector3.UP * 0.54
	# Open and climb out on the side that faces the room centre.
	var centre := _cell(BURIAL.position.y + BURIAL.size.y / 2, BURIAL.position.x + BURIAL.size.x / 2)
	var to_c := centre - p
	var dir := Vector3(signf(to_c.x), 0, 0) if absf(to_c.x) > absf(to_c.z) else Vector3(0, 0, signf(to_c.z))
	var half := absf(dir.dot(size)) * 0.5
	base.set_meta("lid", lid)
	base.set_meta("open_dir", dir)
	base.set_meta("exit", p + dir * (half + 0.8))
	sarcophagi.append(base)


func _environment() -> void:
	var we := WorldEnvironment.new()
	_env = Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.32, 0.5, 0.75)
	sm.sky_horizon_color = Color(0.85, 0.75, 0.6)
	sm.ground_horizon_color = Color(0.8, 0.68, 0.5)
	sm.ground_bottom_color = Color(0.5, 0.4, 0.28)
	sm.sun_angle_max = 20.0
	sky.sky_material = sm
	_env.sky = sky
	_env.background_mode = Environment.BG_SKY
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	_env.ambient_light_color = Color(0.32, 0.26, 0.2)
	_env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	_env.tonemap_mode = Environment.TONE_MAPPER_AGX
	_env.glow_enabled = true
	_env.glow_intensity = 0.6
	_env.glow_bloom = 0.05
	_env.ssao_enabled = not OS.get_cmdline_user_args().has("--no-ssao")
	_env.ssao_intensity = 2.5
	_env.fog_enabled = true
	_env.fog_sky_affect = 0.3
	we.environment = _env
	add_child(we)
	_sun = DirectionalLight3D.new()
	_sun.light_color = Color(1.0, 0.9, 0.75)
	_sun.shadow_enabled = true
	_sun.directional_shadow_max_distance = 90.0
	add_child(_sun)
	_sun.rotation = Vector3(deg_to_rad(-38), deg_to_rad(-140), 0)
	set_indoor(0.0)


# ---------------------------------------------------------------- image-to-3d props

const PROPS := "res://assets/props/"


## A static prop GLB (real metres, origin on the ground) at `pos`, or null if it's missing.
func _prop(parent: Node, file: String, pos: Vector3, rot_y := 0.0, scale_by := Vector3.ONE) -> Node3D:
	if not ResourceLoader.exists(PROPS + file):
		return null
	var p: Node3D = (load(PROPS + file) as PackedScene).instantiate()
	parent.add_child(p)
	p.global_position = pos
	p.rotation.y = rot_y
	p.scale = scale_by
	return p


## Swap a stand-in box's look for a prop fitted to the box (its collision stays).
## `native` is the prop's own size in metres.
func _dress(body: StaticBody3D, file: String, native: Vector3) -> void:
	if not ResourceLoader.exists(PROPS + file):
		return
	var size: Vector3 = (body.get_child(0) as CollisionShape3D).shape.size
	var p: Node3D = (load(PROPS + file) as PackedScene).instantiate()
	body.add_child(p)
	p.position = Vector3(0, -size.y * 0.5, 0)
	p.scale = Vector3(size.x / native.x, size.y / native.y, size.z / native.z)
	(body.get_child(1) as MeshInstance3D).visible = false


## The tomb's layout (subclasses return their own map, same legend).
func map_rows() -> Array:
	return MAP


## Any other map letter (subclasses use them for points of interest, spawns, etc.).
func _marker(_ch: String, _p: Vector3, _r: int, _c: int) -> void:
	pass
