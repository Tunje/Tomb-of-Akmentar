class_name Level
extends Node3D
## Builds the tomb from a character map. One cell = CELL metres.
## '#' wall  '.' floor  'P' pillar  'B' brazier  'L' wall torch (wall cell)
## 'S' sarcophagus (a mummy rises from it later)  'M' dormant mummy  '@' player start

const CELL := 2.0
const WALL_H := 5.0
const MAP := [
	"####################",
	"#M.......SS.......M#",
	"#..P...B....B...P..#",
	"#..................#",
	"#S..P....M.....P..S#",
	"#..................#",
	"#..P...B....B...P..#",
	"#.M..............M.#",
	"########....########",
	"#########..#########",
	"########L..L########",
	"#########..#########",
	"#########..#########",
	"####.......#########",
	"####..L#############",
	"####..##############",
	"###L..L#############",
	"####..##############",
	"####.@##############",
	"####################",
]
## Rows above this are the burial chamber.
const CHAMBER_LAST_ROW := 7

var player_spawn := Vector3.ZERO
var mummy_spawns: Array[Vector3] = []
var sarcophagi: Array[Node3D] = []
var torches: Array[OmniLight3D] = []
var chamber_z_max := 0.0

var _nav: NavigationRegion3D
var _stone: StandardMaterial3D
var _floor_mat: StandardMaterial3D
var _t := 0.0


func _ready() -> void:
	_make_materials()
	_nav = NavigationRegion3D.new()
	var nm := NavigationMesh.new()
	nm.agent_radius = 0.45
	nm.agent_height = 1.8
	nm.agent_max_climb = 0.3
	nm.cell_size = 0.25
	nm.cell_height = 0.25
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_collision_mask = 1
	_nav.navigation_mesh = nm
	add_child(_nav)

	var rows := MAP.size()
	var cols: int = MAP[0].length()
	chamber_z_max = (CHAMBER_LAST_ROW + 1) * CELL
	# Floor and ceiling as single slabs.
	var size := Vector3(cols * CELL, 1.0, rows * CELL)
	var centre := Vector3(cols * CELL * 0.5, -0.5, rows * CELL * 0.5)
	_box(_nav, centre, size, _floor_mat)
	_box(self, centre + Vector3.UP * (WALL_H + 1.0), size, _stone)

	for r in rows:
		var line: String = MAP[r]
		var c := 0
		while c < cols:
			var ch := line[c]
			var p := _cell(r, c)
			match ch:
				"#", "L":
					# Merge horizontal runs of wall into one box.
					var run := 1
					while c + run < cols and line[c + run] in ["#", "L"]:
						run += 1
					var mid := (_cell(r, c) + _cell(r, c + run - 1)) * 0.5
					_box(_nav, mid + Vector3.UP * WALL_H * 0.5, Vector3(run * CELL, WALL_H, CELL), _stone)
					for k in run:
						if line[c + k] == "L":
							_wall_torch(r, c + k)
					c += run
					continue
				"P":
					_pillar(p)
				"B":
					_brazier(p)
				"S":
					_sarcophagus(p, r)
				"M":
					mummy_spawns.append(p)
				"@":
					player_spawn = p
			c += 1

	_environment()
	_nav.bake_navigation_mesh(false)


func _process(delta: float) -> void:
	_t += delta
	for i in torches.size():
		var l := torches[i]
		var base: float = l.get_meta("base")
		l.light_energy = base * (0.85 + 0.1 * sin(_t * 13.0 + i * 1.7) + 0.06 * sin(_t * 31.0 + i * 4.1))


func is_in_chamber(pos: Vector3) -> bool:
	return pos.z < chamber_z_max


func _cell(r: int, c: int) -> Vector3:
	return Vector3(c * CELL + CELL * 0.5, 0.0, r * CELL + CELL * 0.5)


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


func _pillar(p: Vector3) -> void:
	_box(_nav, p + Vector3.UP * WALL_H * 0.5, Vector3(1.3, WALL_H, 1.3), _stone)


func _flame(parent: Node3D, pos: Vector3, energy: float, light_range: float) -> void:
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.62, 0.3)
	l.light_energy = energy
	l.set_meta("base", energy)
	l.omni_range = light_range
	l.omni_attenuation = 1.3
	l.shadow_enabled = true
	parent.add_child(l)
	l.position = pos
	torches.append(l)
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
	parent.add_child(fire)
	fire.position = pos - Vector3.UP * 0.25


func _brazier(p: Vector3) -> void:
	var b := _box(_nav, p + Vector3.UP * 0.5, Vector3(0.6, 1.0, 0.6), _stone)
	_flame(b, Vector3.UP * 0.85, 3.0, 11.0)


func _wall_torch(r: int, c: int) -> void:
	# Light sits on the face that looks at the nearest floor cell.
	for d in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]:
		var rr: int = r + d.y
		var cc: int = c + d.x
		if rr < 0 or rr >= MAP.size() or cc < 0 or cc >= MAP[0].length():
			continue
		if MAP[rr][cc] in ["#", "L"]:
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
		_flame(holder, Vector3.UP * 0.4, 2.2, 8.0)
		return


func _sarcophagus(p: Vector3, r: int) -> void:
	# Long axis along x for the side ones, along z for the head-wall pair.
	var along_z: bool = r == 1
	var size := Vector3(1.0, 0.9, 2.2) if along_z else Vector3(2.2, 0.9, 1.0)
	var base := _box(_nav, p + Vector3.UP * 0.45, size, _stone)
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
	var to_c := Vector3(10.0 * CELL, 0, (CHAMBER_LAST_ROW + 1) * CELL * 0.5) - p
	var dir := Vector3(signf(to_c.x), 0, 0) if absf(to_c.x) > absf(to_c.z) else Vector3(0, 0, signf(to_c.z))
	var half := absf(dir.dot(size)) * 0.5
	base.set_meta("lid", lid)
	base.set_meta("open_dir", dir)
	base.set_meta("exit", p + dir * (half + 0.8))
	sarcophagi.append(base)


func _environment() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.01, 0.008, 0.006)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.32, 0.26, 0.2)
	env.ambient_light_energy = 0.12
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.1
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.glow_bloom = 0.05
	env.ssao_enabled = true
	env.ssao_intensity = 2.5
	env.fog_enabled = true
	env.fog_light_color = Color(0.12, 0.08, 0.05)
	env.fog_density = 0.025
	we.environment = env
	add_child(we)
