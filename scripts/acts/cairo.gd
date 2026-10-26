class_name Cairo
extends Level
## Act 2's map: a quarter of 1920s Cairo, about 112 x 100 m, the Nile along its east side.
## Streets: the avenue (east-west, z 46-54) from the old quarter to the docks; Sharia west
## (north-south, x 26-32); Sharia east (x 72-80) past the museum plaza; the bazaar lane (z 74-80)
## between them, under arches and awnings; and the quay road along the river (x 104-112).
## Flat-roofed plaster blocks fill the rest. The named places (SPOTS) are Interactables in
## `interactables`; recruits and hosts stand at NPC_POINTS (place_people); townsfolk walk WALKS.
## set_day_time(t): 0 morning, 0.5 noon, 1 dusk.
## Blockout boxes until image-to-3d's building pieces arrive.

const RIVER_X := 112.0      # the quay edge; the Nile is east of it
const WATER_Y := -1.2
const SOUTH := 100.0
const RING := 14.0          # the outer ring of buildings that closes the streets off

## The named places: where the player stands to use them, the facade's outward normal (x, z),
## and the E prompt. act2.gd hangs its ActionSpots / talks on these ids.
const SPOTS := {
	"hotel": [Vector3(44, 0, 47.3), Vector2(0, 1), "The hotel"],
	"hotel_bed": [Vector3(51, 0, 47.3), Vector2(0, 1), "Go up to your room (sleep: save, end the day)"],
	"museum": [Vector3(92, 0, 29.6), Vector2(0, 1), "The Museum of Antiquities"],
	"consulate": [Vector3(73.3, 0, 26), Vector2(1, 0), "The consulate"],
	"bank": [Vector3(65, 0, 47.3), Vector2(0, 1), "The bank"],
	"telegraph": [Vector3(73.3, 0, 9), Vector2(1, 0), "The telegraph office"],
	"club": [Vector3(63, 0, 52.7), Vector2(0, -1), "The officers' club"],
	"outfitter": [Vector3(45, 0, 52.7), Vector2(0, -1), "The outfitters"],
	"gunsmith": [Vector3(30.7, 0, 61), Vector2(-1, 0), "The gunsmith"],
	"tavern": [Vector3(27.3, 0, 66), Vector2(1, 0), "The tavern"],
	"bazaar": [Vector3(54, 0, 77.4), Vector2(0, 0), "The bazaar"],
	"dealer": [Vector3(40, 0, 78.7), Vector2(0, -1), "The antiquities dealer"],
	"caravanserai": [Vector3(78.6, 0, 77), Vector2(-1, 0), "The caravanserai"],
	"labour": [Vector3(107, 0, 62), Vector2(0, 0), "The labour market"],
	"docks": [Vector3(110, 0, 50), Vector2(0, 0), "The docks"],
	# Act 7's.
	"station": [Vector3(1.4, 0, 50), Vector2(1, 0), "The railway station"],
	"police": [Vector3(7, 0, 52.7), Vector2(0, -1), "Police headquarters"],
	"road_gate": [Vector3(29, 0, 97.5), Vector2(0, 0), "The south gate"],
}
## Where each recruit and each spot's host stands (Characters / people.json ids), and the point
## they face. Hosts are -f9's: the person an action spot's talk is with.
const NPC_POINTS := {
	"eleanor": [Vector3(89.2, 0, 30.4), Vector3(91, 0, 40)],
	"pembroke": [Vector3(95, 0, 30.6), Vector3(93, 0, 40)],
	"hassan": [Vector3(42.4, 0, 78.9), Vector3(42, 0, 74)],
	"hargreaves": [Vector3(60.5, 0, 52.6), Vector3(61, 0, 48)],
	"idris": [Vector3(27.5, 0, 63.2), Vector3(31, 0, 64)],
	"isabelle": [Vector3(27.8, 0, 69), Vector3(31, 0, 67)],
	"saleh": [Vector3(85, 0, 72.5), Vector3(80, 0, 77)],
	"youssef": [Vector3(86, 0, 81.5), Vector3(80, 0, 77)],
	"farid": [Vector3(89, 0, 77), Vector3(80, 0, 77)],
	"mahmoud": [Vector3(105.5, 0, 64.5), Vector3(108, 0, 62)],
	"khalil": [Vector3(107.5, 0, 66.5), Vector3(108, 0, 62)],
	"naguib": [Vector3(109.6, 0, 64.8), Vector3(108, 0, 62)],
	# Hosts.
	"archivist": [Vector3(92, 0.45, 26.9), Vector3(92, 0, 32)],
	"yacoub": [Vector3(38.5, 0, 79.4), Vector3(40, 0, 77)],
	"mckenna": [Vector3(26.5, 0, 64.8), Vector3(30, 0, 66)],
	"abdel": [Vector3(82.8, 0, 75.2), Vector3(78, 0, 77)],
	"fatima": [Vector3(107.6, 0, 60.4), Vector3(106, 0, 63)],
	"zaki": [Vector3(31.4, 0, 59.5), Vector3(28, 0, 61)],
	"samira": [Vector3(46.7, 0, 53.4), Vector3(45, 0, 50)],
	"rafiq": [Vector3(54, 0, 75.4), Vector3(54, 0, 78)],
	"nabil": [Vector3(72.6, 0, 7.5), Vector3(76, 0, 9)],
	"karim": [Vector3(66.2, 0, 46.9), Vector3(65, 0, 50)],
	"clara": [Vector3(46.2, 0, 46.9), Vector3(45, 0, 50)],
	"hamdi": [Vector3(116, 0, 51), Vector3(110, 0, 50)],
	# Act 7's.
	"watkins": [Vector3(0.9, 0, 47.9), Vector3(6, 0, 50)],
	"khalaf": [Vector3(8.9, 0, 53.4), Vector3(7, 0, 49)],
	"salim": [Vector3(48.8, 0, 78.4), Vector3(50, 0, 76)],
	"blackwood": [Vector3(63.4, 0, 47.2), Vector3(65, 0, 50)],
}
## People who only appear when the city is under the countdown (Act 7 lists them in `only`).
const LATER_PEOPLE := ["watkins", "khalaf", "salim", "blackwood"]
## Hitching places in the caravanserai yard (the act puts the expedition's horses here).
const HORSE_POINTS := [Vector3(86, 0, 58.6), Vector3(90, 0, 58.6), Vector3(94, 0, 58.6), Vector3(98, 0, 58.6)]
## Where the riverboat ties up: alongside the pier's south face, bow to the east (+X).
const MOORING := Vector3(121, WATER_Y, 57.5)
## Townsfolk walking loops (each a list of points, walked in order and back to the first),
## kept to the open middle of the streets, clear of lamps, crates and the named people.
const WALKS := [
	[Vector3(4, 0, 49), Vector3(34, 0, 49)],
	[Vector3(60, 0, 51), Vector3(100, 0, 51)],
	[Vector3(40, 0, 50.5), Vector3(72, 0, 50.5)],
	[Vector3(30.5, 0, 4), Vector3(30.5, 0, 44)],
	[Vector3(30.3, 0, 56), Vector3(30.3, 0, 96)],
	[Vector3(77, 0, 2), Vector3(77, 0, 44)],
	[Vector3(75, 0, 58), Vector3(75, 0, 98)],
	[Vector3(35, 0, 76.3), Vector3(69, 0, 76.3)],
	[Vector3(106, 0, 4), Vector3(106, 0, 44)],
	[Vector3(106.5, 0, 76), Vector3(106.5, 0, 98)],
	[Vector3(88, 0, 34), Vector3(96, 0, 34), Vector3(96, 0, 43), Vector3(88, 0, 43)],
	[Vector3(86, 0, 66), Vector3(98, 0, 66)],
]
## Townsfolk standing about in twos, talking.
const CHATS := [
	[Vector3(18, 0, 52.4), Vector3(18.9, 0, 52.9)], [Vector3(100, 0, 47.8), Vector3(100.9, 0, 48.4)],
	[Vector3(35, 0, 44.6), Vector3(35.8, 0, 44.0)], [Vector3(66, 0, 77.4), Vector3(66.9, 0, 77.0)],
]
## Animals about the place: where, facing (yaw), and size (1 horse, 0.72 donkey).
const ANIMALS := [
	[Vector3(88, 0, 90), 0.4, 0.72], [Vector3(92.5, 0, 92), -0.3, 0.72], [Vector3(98, 0, 63.5), PI * 0.5, 1.0],
	[Vector3(59.6, 0, 77.6), PI * 0.5, 0.72],   # the bazaar cart's donkey
]
## Stand-in looks for townsfolk until image-to-3d's civilians exist.
const TOWNSFOLK_MODELS := ["bandits/bandit_scout.glb", "bandits/bandit_raider.glb"]

var spots := {}             # id -> Vector3 (the SPOTS positions)
var npcs := {}              # id -> Npc (place_people)
var mooring := Transform3D(Basis.IDENTITY, MOORING)
var day_time := 0.5         # 0 morning .. 0.5 noon .. 1 dusk (set_day_time)
var dust := 0.0             # the curse (set_curse): ochre dust in the air
var gloom := 0.0            # the curse: the sky darkening by day
var townsfolk: Array[Node3D] = []
var _day_tween: Tween
var _rng := RandomNumberGenerator.new()
var _deco: Node3D
var _plaster: Array[StandardMaterial3D] = []
var _trim: StandardMaterial3D
var _street: StandardMaterial3D
var _paving: StandardMaterial3D
var _dark: StandardMaterial3D
var _win: StandardMaterial3D
var _win_lit: StandardMaterial3D
var _lamp_glass: StandardMaterial3D
var _wood: StandardMaterial3D
var _iron: StandardMaterial3D
var _water: StandardMaterial3D
var _leaf: StandardMaterial3D
var _cloths: Array[StandardMaterial3D] = []
var _lamps: Array[OmniLight3D] = []
var _animals_idle: Array[HorseRig] = []


func _ready() -> void:
	_rng.seed = 1922
	_make_materials()
	_cairo_materials()
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
	_deco = Node3D.new()
	_deco.name = "Deco"
	add_child(_deco)

	# The ground: the whole quarter plus the ring, up to the quay edge.
	var x0 := -RING
	var z0 := -RING
	var z1 := SOUTH + RING
	_box(_nav, Vector3((x0 + RIVER_X) * 0.5, -0.5, (z0 + z1) * 0.5), Vector3(RIVER_X - x0, 1.0, z1 - z0), _street)
	_river()
	_blocks()
	_hotel()
	_museum()
	_consulate()
	_bank()
	_telegraph()
	_club()
	_outfitter()
	_gunsmith()
	_tavern()
	_mosque()
	_bazaar()
	_dealer()
	_station()
	_police()
	_road_gate()
	_caravanserai()
	_quay()
	_street_life()
	_animals()
	_skyline()
	# Each act puts its own ActionSpots (actions/act<N>_<id>.json) on these positions; only the
	# hotel bed is a plain Interactable here (the act wires it to save and end the day).
	for id in SPOTS:
		var s: Array = SPOTS[id]
		spots[id] = s[0]
	interactables["hotel_bed"] = Interactable.make(self, spots.hotel_bed + Vector3.UP * 0.9, SPOTS.hotel_bed[2], "hotel_bed", 1.0)
	player_spawn = Vector3(47.5, 0, 50)
	_environment()
	set_day_time(day_time)
	_nav.bake_navigation_mesh(false)
	_townsfolk()


## The recruits and hosts at their places. `conversations`: Characters id -> dialogue id (none =
## no Talk). `only`: just these ids (Act 7 names its own); empty = everyone but LATER_PEOPLE.
func place_people(conversations := {}, only: Array = []) -> Dictionary:
	for id in NPC_POINTS:
		if (only.is_empty() and id in LATER_PEOPLE) or (not only.is_empty() and not id in only):
			continue
		var p: Array = NPC_POINTS[id]
		var n := Npc.make(self, id, p[0], conversations.get(id, ""), Characters.glb(id))
		n.face_towards(p[1])
		n.rotation.y = atan2(-(p[1] - p[0]).x, -(p[1] - p[0]).z)
		npcs[id] = n
	return npcs


# ---------------------------------------------------------------- materials

func _cairo_materials() -> void:
	for c in [[Color(0.78, 0.68, 0.52), Color(0.9, 0.82, 0.66)],   # sand plaster
			[Color(0.82, 0.78, 0.7), Color(0.95, 0.92, 0.85)],      # whitewash
			[Color(0.72, 0.55, 0.38), Color(0.84, 0.68, 0.5)],      # ochre
			[Color(0.74, 0.58, 0.5), Color(0.86, 0.7, 0.6)],        # dusty pink
			[Color(0.66, 0.6, 0.5), Color(0.8, 0.74, 0.62)]]:       # grey stone
		var m := _stone.duplicate() as StandardMaterial3D
		m.albedo_texture = _noise_tex(c[0], c[1], 0.04, false)
		m.uv1_scale = Vector3.ONE * 0.18
		_plaster.append(m)
	_trim = _stone.duplicate()
	_trim.albedo_texture = _noise_tex(Color(0.55, 0.45, 0.33), Color(0.68, 0.57, 0.42), 0.05, false)
	_street = _sand.duplicate()
	_street.albedo_texture = _noise_tex(Color(0.55, 0.46, 0.34), Color(0.7, 0.6, 0.45), 0.03, false)
	_paving = _stone.duplicate()
	_paving.albedo_texture = _noise_tex(Color(0.62, 0.56, 0.46), Color(0.78, 0.7, 0.58), 0.08, false)
	_paving.uv1_scale = Vector3.ONE * 0.4
	_dark = _flat(Color(0.12, 0.09, 0.07))
	_win = _flat(Color(0.1, 0.11, 0.13))
	_win.roughness = 0.3
	_win_lit = _win.duplicate()
	_win_lit.emission_enabled = true
	_win_lit.emission = Color(1.0, 0.7, 0.35)
	_win_lit.emission_energy_multiplier = 0.0
	_lamp_glass = _flat(Color(0.85, 0.8, 0.62))
	_lamp_glass.roughness = 0.2
	_lamp_glass.emission_enabled = true
	_lamp_glass.emission = Color(1.0, 0.75, 0.4)
	_lamp_glass.emission_energy_multiplier = 0.0
	_wood = _flat(Color(0.33, 0.21, 0.12))
	_iron = _flat(Color(0.12, 0.12, 0.12))
	_iron.metallic = 0.6
	_water = _flat(Color(0.18, 0.3, 0.28))
	_water.roughness = 0.08
	_water.metallic = 0.3
	_leaf = _flat(Color(0.22, 0.36, 0.14))
	_leaf.cull_mode = BaseMaterial3D.CULL_DISABLED
	for c in [Color(0.62, 0.18, 0.14), Color(0.2, 0.4, 0.3), Color(0.85, 0.78, 0.6), Color(0.25, 0.3, 0.5), Color(0.75, 0.5, 0.15)]:
		var m := _flat(c)
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		_cloths.append(m)


func _flat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.9
	return m


# ---------------------------------------------------------------- building pieces

## A mesh with no collision (trim, windows, awnings, far skyline).
func _mesh(pos: Vector3, size: Vector3, mat: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	_deco.add_child(mi)
	mi.position = pos
	mi.rotation = rot
	return mi


## A flat-roofed building on `r` (x, z rect), `h` tall: walls, a cornice and parapet, windows on
## the faces listed in `faces` (outward normals), and maybe a door and some roof clutter.
func _building(r: Rect2, h: float, mat: Material, faces: Array, door := true) -> void:
	var c := Vector3(r.get_center().x, 0, r.get_center().y)
	_box(_nav, c + Vector3.UP * h * 0.5, Vector3(r.size.x, h, r.size.y), mat)
	# Cornice band and a parapet lip round the flat roof.
	_mesh(c + Vector3.UP * (h - 0.25), Vector3(r.size.x + 0.3, 0.3, r.size.y + 0.3), _trim)
	for e in [[Vector3(0, 0, -0.5), r.size.x, true], [Vector3(0, 0, 0.5), r.size.x, true],
			[Vector3(-0.5, 0, 0), r.size.y, false], [Vector3(0.5, 0, 0), r.size.y, false]]:
		var off: Vector3 = e[0] * Vector3(r.size.x - 0.2, 0, r.size.y - 0.2)
		var sz := Vector3(e[1], 0.6, 0.2) if e[2] else Vector3(0.2, 0.6, e[1])
		_mesh(c + off + Vector3.UP * (h + 0.3), sz, mat)
	var floors := int((h - 0.5) / 3.2)
	for f in faces:
		var n := Vector3(f.x, 0, f.y)
		var along := Vector3(absf(n.z), 0, absf(n.x))  # the facade's own x direction
		var width := r.size.x if n.z != 0 else r.size.y
		var depth := r.size.y if n.z != 0 else r.size.x
		var face := c + n * depth * 0.5
		var count := int((width - 1.5) / 2.6)
		var door_at := _rng.randi_range(0, maxi(count - 1, 0)) if door else -1
		for k in count:
			var u := (k - (count - 1) * 0.5) * 2.6
			for fl in floors:
				var y := 1.6 + fl * 3.2
				if fl == 0 and k == door_at:
					_mesh(face + along * u + Vector3.UP * 1.15 + n * 0.04, _rot_size(Vector3(1.3, 2.3, 0.12), n), _dark)
					_mesh(face + along * u + Vector3.UP * 2.45 + n * 0.08, _rot_size(Vector3(1.7, 0.25, 0.2), n), _trim)
					continue
				if fl == 0 and _rng.randf() < 0.35:
					continue
				var lit := _rng.randf() < 0.3
				_mesh(face + along * u + Vector3.UP * y + n * 0.04, _rot_size(Vector3(0.9, 1.4, 0.1), n), _win_lit if lit else _win)
				_mesh(face + along * u + Vector3.UP * (y - 0.78) + n * 0.1, _rot_size(Vector3(1.15, 0.12, 0.22), n), _trim)
				if fl > 0 and _rng.randf() < 0.12:
					_balcony(face + along * u + Vector3.UP * (y - 0.8), n)
	# Roof clutter: a water tank or a little roof room.
	var roll := _rng.randf()
	if roll < 0.3:
		var tank := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.6
		cm.bottom_radius = 0.6
		cm.height = 1.2
		tank.mesh = cm
		tank.material_override = _iron
		_deco.add_child(tank)
		tank.position = c + Vector3(r.size.x * 0.2, h + 0.6, -r.size.y * 0.2)
	elif roll < 0.55 and r.size.x > 6 and r.size.y > 6:
		_mesh(c + Vector3(-r.size.x * 0.15, h + 1.2, r.size.y * 0.1), Vector3(3.0, 2.4, 2.6), mat)


## A size given for a facade facing +Z, turned to face `n`.
func _rot_size(s: Vector3, n: Vector3) -> Vector3:
	return s if n.z != 0 else Vector3(s.z, s.y, s.x)


func _balcony(at: Vector3, n: Vector3) -> void:
	_mesh(at + n * 0.45, _rot_size(Vector3(1.6, 0.12, 0.9), n), _trim)
	_mesh(at + n * 0.88 + Vector3.UP * 0.45, _rot_size(Vector3(1.6, 0.8, 0.04), n), _iron)


## Fill a block (x, z rect) with buildings of mixed heights, skipping the landmark rects
## (they build themselves). Windows go on the faces on the block's edge.
func _block(r: Rect2, landmarks: Array, low := 6.0, high := 13.0) -> void:
	var xs := _cuts(r.position.x, r.end.x, landmarks.map(func(l: Rect2): return [l.position.x, l.end.x]))
	var zs := _cuts(r.position.y, r.end.y, landmarks.map(func(l: Rect2): return [l.position.y, l.end.y]))
	for i in xs.size() - 1:
		for j in zs.size() - 1:
			var lot := Rect2(xs[i], zs[j], xs[i + 1] - xs[i], zs[j + 1] - zs[j])
			var skip := false
			for l in landmarks:
				skip = skip or (l as Rect2).has_point(lot.get_center())
			if skip:
				continue
			var faces := []
			if is_equal_approx(lot.position.y, r.position.y): faces.append(Vector2(0, -1))
			if is_equal_approx(lot.end.y, r.end.y): faces.append(Vector2(0, 1))
			if is_equal_approx(lot.position.x, r.position.x): faces.append(Vector2(-1, 0))
			if is_equal_approx(lot.end.x, r.end.x): faces.append(Vector2(1, 0))
			var h := snappedf(_rng.randf_range(low, high), 0.5)
			_building(lot, h, _plaster[_rng.randi() % _plaster.size()], faces)


## Cut points from a to b: the landmark edges, then lots of about 9-12 m between them.
func _cuts(a: float, b: float, edges: Array) -> Array:
	var fixed := [a, b]
	for e in edges:
		for v in e:
			if v > a + 0.01 and v < b - 0.01 and not fixed.has(v):
				fixed.append(v)
	fixed.sort()
	var out := []
	for i in fixed.size() - 1:
		var lo: float = fixed[i]
		var hi: float = fixed[i + 1]
		var n := maxi(1, int(round((hi - lo) / 10.5)))
		for k in n:
			var t := lo + (hi - lo) * k / n
			if k > 0:
				t += _rng.randf_range(-1.2, 1.2)
			out.append(t)
	out.append(b)
	return out


## The streets' blocks, and the ring outside them that closes every street off.
func _blocks() -> void:
	_block(Rect2(0, 0, 26, 46), [Rect2(4, 10, 18, 22)])                          # NW (the mosque)
	_block(Rect2(32, 0, 40, 46), [Rect2(38, 30, 18, 16), Rect2(58, 34, 14, 12),   # N-mid: hotel, bank,
		Rect2(62, 18, 10, 16), Rect2(64, 4, 8, 10)])                             # consulate, telegraph
	_block(Rect2(0, 54, 26, 46), [Rect2(14, 60, 12, 12), Rect2(2, 54, 10, 10)])   # SW: tavern, police
	_block(Rect2(32, 54, 40, 20), [Rect2(56, 54, 14, 10), Rect2(40, 54, 10, 8),   # S-mid north: club,
		Rect2(32, 56, 8, 10)], 5.0, 10.0)                                        # outfitter, gunsmith
	_block(Rect2(32, 80, 40, 20), [Rect2(36, 80, 8, 8)], 5.0, 10.0)              # S-mid south (dealer)
	# The ring: low and high blocks round the outside, so the streets end in facades.
	_block(Rect2(-RING, -RING, RING, SOUTH + RING * 2.0), [Rect2(-RING, 40, RING, 20)], 8.0, 16.0)  # (the station)
	_block(Rect2(0, -RING, RIVER_X - 8.0, RING), [], 8.0, 16.0)
	_block(Rect2(0, SOUTH, RIVER_X - 8.0, RING), [Rect2(26, SOUTH, 6, RING)], 8.0, 16.0)  # (the south gate)
	_block(Rect2(RIVER_X - 8.0, -RING, 8.0, RING), [], 6.0, 8.0)
	_block(Rect2(RIVER_X - 8.0, SOUTH, 8.0, RING), [], 6.0, 8.0)


## A sign board over a door: a board on the wall and its painted name.
func _sign(at: Vector3, n: Vector3, text: String, width := 4.0, board := Color(0.18, 0.22, 0.16)) -> void:
	var m := _flat(board)
	_mesh(at + n * 0.08, _rot_size(Vector3(width, 0.75, 0.12), n), m)
	var l := Label3D.new()
	l.text = text
	l.font_size = 56
	l.pixel_size = 0.007
	l.outline_size = 0
	l.modulate = Color(0.95, 0.85, 0.55)
	l.width = width / l.pixel_size
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	_deco.add_child(l)
	l.position = at + n * 0.16
	l.rotation.y = atan2(n.x, n.z)


## A shop awning: canvas sloping out from the wall at `at` (centre of its top edge).
func _awning(at: Vector3, n: Vector3, width: float, cloth: Material, reach := 1.8) -> void:
	var a := _mesh(at + n * reach * 0.5 + Vector3.DOWN * 0.3, Vector3(width, 0.05, reach), cloth)
	a.rotation = Vector3(0.32, atan2(n.x, n.z), 0)
	a.rotation_order = EULER_ORDER_YXZ
	# The front valance.
	_mesh(at + n * (reach * 0.95) + Vector3.DOWN * 0.78, _rot_size(Vector3(width, 0.3, 0.04), n), cloth)


## The door of a named building: dark doorway, steps, sign, maybe an awning.
func _entrance(at: Vector3, n: Vector3, text: String, door_w := 1.8, door_h := 2.8, sign_w := 4.0) -> void:
	_mesh(at + Vector3.UP * door_h * 0.5 + n * 0.05, _rot_size(Vector3(door_w, door_h, 0.12), n), _dark)
	_mesh(at + Vector3.UP * (door_h + 0.15) + n * 0.1, _rot_size(Vector3(door_w + 0.6, 0.3, 0.22), n), _trim)
	_mesh(at + Vector3.UP * 0.07 + n * 0.45, _rot_size(Vector3(door_w + 1.2, 0.14, 0.9), n), _trim)
	if text != "":
		_sign(at + Vector3.UP * (door_h + 0.9), n, text, sign_w)


## An arch across a street: two piers, the curve (a ring of stones) and the band over it.
## `at` is the middle of the opening on the ground; `along` is the way through it.
func _arch(at: Vector3, along: Vector3, span: float, rise := 3.4, solid := true, mat: Material = null) -> void:
	var m: Material = mat if mat else _plaster[0]
	var across := Vector3(absf(along.z), 0, absf(along.x))
	var depth := 0.9
	for s in [-1.0, 1.0]:
		var p: Vector3 = at + across * s * (span * 0.5 + 0.35) + Vector3.UP * rise * 0.5
		if solid:
			_box(_nav, p, _rot_size(Vector3(0.7, rise, depth), along), m)
		else:
			_mesh(p, _rot_size(Vector3(0.7, rise, depth), along), m)
	var radius := span * 0.5
	var top := at + Vector3.UP * rise
	var steps := 9
	for k in steps:
		var a := PI * (k + 0.5) / steps
		var p := top + across * cos(a) * radius + Vector3.UP * sin(a) * radius * 0.7
		# Each stone lies along the curve's tangent.
		var stone := _mesh(p, _rot_size(Vector3(radius * PI / steps + 0.1, 0.45, depth), along), _trim)
		if along.z != 0:
			stone.rotation.z = a - PI * 0.5
		else:
			stone.rotation.x = PI * 0.5 - a
	var crown := radius * 0.7
	_mesh(top + Vector3.UP * (crown + 0.7), _rot_size(Vector3(span + 1.4, 1.2, depth), along), m)
	# Fill the spandrels (between the curve and the band) in steps that follow the curve.
	for s in [-1.0, 1.0]:
		var x0 := radius * 0.45
		var x_end := radius + 0.7
		var slices := 6
		for k in slices:
			var xa := lerpf(x0, x_end, float(k) / slices)
			var xb := lerpf(x0, x_end, float(k + 1) / slices)
			var under := crown * sqrt(maxf(0.0, 1.0 - pow(xa / radius, 2))) + 0.15 if xa < radius else 0.0
			var h := crown + 0.1 - under
			if h > 0.05:
				var p: Vector3 = top + across * s * (xa + xb) * 0.5 + Vector3.UP * (under + h * 0.5)
				_mesh(p, _rot_size(Vector3(xb - xa, h, depth * 0.9), along), m)


# ---------------------------------------------------------------- the named places

func _hotel() -> void:
	var r := Rect2(38, 30, 18, 16)
	var mat := _plaster[1]
	_building(r, 16.0, mat, [Vector2(0, 1), Vector2(0, -1), Vector2(-1, 0)], false)
	var n := Vector3(0, 0, 1)
	var front := 46.0
	_entrance(Vector3(47.5, 0, front), n, "HOTEL KHEDIVIAL", 2.6, 3.0, 6.0)
	# The veranda along the front: posts and a roof over the pavement.
	for k in 6:
		_cylinder_post(Vector3(39.5 + k * 3.2, 0, front + 2.6), 0.12, 3.6, _plaster[1])
	_mesh(Vector3(47, 3.7, front + 1.35), Vector3(17.4, 0.25, 2.9), _trim)
	_mesh(Vector3(47, 4.0, front + 2.75), Vector3(17.4, 0.4, 0.15), _plaster[1])
	# Potted palms by the door.
	for x in [45.2, 49.8]:
		_pot_palm(Vector3(x, 0, front + 0.6))
	# The bed is upstairs: a little brass plate by the side door.
	_mesh(Vector3(51, 1.15, front + 0.05), Vector3(1.2, 2.3, 0.12), _dark)
	_sign(Vector3(51, 2.7, front), n, "ROOMS", 1.4, Color(0.25, 0.15, 0.08))


func _museum() -> void:
	# The Museum of Antiquities: a long pink building on its plaza, a portico of columns.
	var r := Rect2(80, 0, 24, 26)
	var mat := _plaster[3]
	_building(r, 13.0, mat, [Vector2(0, 1), Vector2(-1, 0), Vector2(1, 0)], false)
	var front := 26.0
	var n := Vector3(0, 0, 1)
	# A raised portico (0.45 up) on three 0.15 steps, six columns, the pediment band.
	for k in 3:
		var d := 3.4 - k * 0.4
		_box(_nav, Vector3(92, 0.075 * (k + 1), front + d * 0.5), Vector3(14.4 - k * 0.6, 0.15 * (k + 1), d), _paving)
	for k in 6:
		var x := 86.0 + k * 2.4
		var col := _cylinder(_nav, Vector3(x, 0.45 + 3.2, front + 1.4), 0.38, 6.4)
		if _prop(col, "dungeon/pillar_lotus.glb", Vector3(x, 0.45, front + 1.4), 0.0, Vector3(1.1, 1.0, 1.1)):
			(col.get_child(1) as MeshInstance3D).visible = false
	_mesh(Vector3(92, 7.1, front + 1.3), Vector3(14.4, 0.7, 3.0), _trim)
	_mesh(Vector3(92, 8.0, front + 0.5), Vector3(10.0, 1.2, 1.2), mat)
	_entrance(Vector3(92, 0.45, front), n, "", 2.6, 3.6)
	_sign(Vector3(92, 7.1, front + 2.8), n, "MUSEUM OF EGYPTIAN ANTIQUITIES", 9.0, Color(0.5, 0.4, 0.28))
	# The plaza: paving, palms, a fountain basin (cover), benches.
	var pave := _mesh(Vector3(92, 0.01, 36), Vector3(24, 0.02, 20), _paving)
	pave.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var basin := _cylinder(_nav, Vector3(92, 0.35, 38.5), 2.4, 0.7)
	(basin.get_child(1) as MeshInstance3D).material_override = _trim
	var pool := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 2.1
	cm.bottom_radius = 2.1
	cm.height = 0.05
	pool.mesh = cm
	pool.material_override = _water
	_deco.add_child(pool)
	pool.position = Vector3(92, 0.68, 38.5)
	_cylinder(_nav, Vector3(92, 1.2, 38.5), 0.3, 1.0)
	for p in [Vector3(83, 0, 31), Vector3(101, 0, 31), Vector3(83, 0, 43), Vector3(101, 0, 43)]:
		_palm(p, 7.5)
	for p in [Vector3(86, 0, 38.5), Vector3(98, 0, 38.5)]:
		var bench := _box(_nav, p + Vector3.UP * 0.25, Vector3(0.6, 0.5, 2.2), _wood)
		_mark_cover(bench, Vector3(0.6, 0.5, 2.2))


func _consulate() -> void:
	var r := Rect2(62, 18, 10, 16)
	_building(r, 12.0, _plaster[1], [Vector2(1, 0)], false)
	var n := Vector3(1, 0, 0)
	_entrance(Vector3(72, 0, 26), n, "CONSULATE", 2.0, 3.2, 3.6)
	# Railings and a flag over the door.
	for z in [21.0, 31.0]:
		_mesh(Vector3(73.2, 0.55, z), Vector3(0.08, 1.1, 6.0), _iron)
	var pole := MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = 0.05
	pm.bottom_radius = 0.06
	pm.height = 3.0
	pole.mesh = pm
	pole.material_override = _iron
	_deco.add_child(pole)
	pole.rotation = Vector3(0, 0, -0.9)
	pole.position = Vector3(73.2, 6.0, 26)
	_mesh(Vector3(74.3, 6.4, 26), Vector3(0.03, 0.9, 1.4), _cloths[3])


func _bank() -> void:
	_building(Rect2(58, 34, 14, 12), 11.0, _plaster[4], [Vector2(0, 1), Vector2(1, 0)], false)
	var front := 46.0
	_entrance(Vector3(65, 0, front), Vector3(0, 0, 1), "BANK OF EGYPT", 2.2, 3.4, 4.6)
	for x in [60.5, 62.5, 67.5, 69.5]:
		_mesh(Vector3(x, 3.5, front + 0.3), Vector3(0.7, 7.0, 0.6), _trim)


func _telegraph() -> void:
	_building(Rect2(64, 4, 8, 10), 7.0, _plaster[2], [Vector2(1, 0)], false)
	_entrance(Vector3(72, 0, 9), Vector3(1, 0, 0), "TELEGRAPH", 1.6, 2.6, 3.4)
	# Wires off the roof to a pole by the street.
	_cylinder_post(Vector3(75, 0, 5), 0.12, 8.0, _wood)
	_mesh(Vector3(75, 7.7, 5), Vector3(0.1, 0.1, 1.6), _wood)


func _club() -> void:
	_building(Rect2(56, 54, 14, 10), 9.0, _plaster[0], [Vector2(0, -1)], false)
	var n := Vector3(0, 0, -1)
	_entrance(Vector3(63, 0, 54), n, "OFFICERS' CLUB", 2.0, 3.0, 5.0)
	_awning(Vector3(63, 3.6, 54), n, 8.0, _cloths[1], 2.2)


func _outfitter() -> void:
	_building(Rect2(40, 54, 10, 8), 7.5, _plaster[2], [Vector2(0, -1)], false)
	var n := Vector3(0, 0, -1)
	_entrance(Vector3(45, 0, 54), n, "OUTFITTERS", 1.8, 2.8, 4.0)
	_awning(Vector3(45, 3.4, 54), n, 6.0, _cloths[2], 2.0)
	# Goods out front: crates, a tent bundle, coiled rope.
	for p in [Vector3(41.6, 0, 52.9), Vector3(48.4, 0, 52.9)]:
		var crate := _box(_nav, p + Vector3.UP * 0.4, Vector3(1.2, 0.8, 0.8), _wood)
		_dress(crate, "prop_crate_small.glb", Vector3(0.6, 0.4, 0.4))
	_prop(self, "prop_bedroll.glb", Vector3(48.4, 0.8, 52.9), 0.2)


func _gunsmith() -> void:
	_building(Rect2(32, 56, 8, 10), 7.0, _plaster[4], [Vector2(-1, 0)], false)
	var n := Vector3(-1, 0, 0)
	_entrance(Vector3(32, 0, 61), n, "GUNSMITH", 1.6, 2.7, 3.4)
	_awning(Vector3(32, 3.3, 61), n, 5.0, _cloths[0], 1.6)


func _tavern() -> void:
	_building(Rect2(14, 60, 12, 12), 8.0, _plaster[2], [Vector2(1, 0)], false)
	var n := Vector3(1, 0, 0)
	_entrance(Vector3(26, 0, 66), n, "THE CROCODILE BAR", 2.0, 2.8, 5.0)
	_awning(Vector3(26, 3.4, 66), n, 9.0, _cloths[0], 2.4)
	# Tables out front, a lantern at the door.
	for z in [62.0, 70.0]:
		var t := _cylinder(_nav, Vector3(28.2, 0.4, z), 0.5, 0.8)
		(t.get_child(1) as MeshInstance3D).material_override = _wood
	_lantern(Vector3(26.3, 2.6, 64.3))


func _mosque() -> void:
	# A mosque in the old quarter: a block, a dome, and a minaret to steer by.
	var r := Rect2(4, 10, 18, 22)
	_building(r, 9.0, _plaster[0], [Vector2(1, 0), Vector2(0, 1)], false)
	var dome := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 5.0
	sm.height = 7.0
	dome.mesh = sm
	dome.material_override = _plaster[4]
	_deco.add_child(dome)
	dome.position = Vector3(13, 9.0, 21)
	_mesh(Vector3(13, 9.3, 21), Vector3(10.4, 0.6, 10.4), _trim)
	_minaret(Vector3(20, 9.0, 12), 18.0)
	_mesh(Vector3(22.05, 2.0, 24), Vector3(0.12, 4.0, 2.4), _dark)
	_mesh(Vector3(22.1, 4.2, 24), Vector3(0.22, 0.4, 3.0), _trim)


func _minaret(base: Vector3, h: float) -> void:
	var parts := [[2.2, 0.0, h * 0.45, true], [1.6, h * 0.45, h * 0.35, false], [1.1, h * 0.8, h * 0.2, false]]
	for p in parts:
		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = p[0] * 0.5
		cm.bottom_radius = p[0] * 0.5
		cm.height = p[2]
		cm.radial_segments = 8 if p[3] else 16
		mi.mesh = cm
		mi.material_override = _plaster[0]
		_deco.add_child(mi)
		mi.position = base + Vector3.UP * (p[1] + p[2] * 0.5)
		var ring := MeshInstance3D.new()
		var rm := CylinderMesh.new()
		rm.top_radius = p[0] * 0.5 + 0.35
		rm.bottom_radius = p[0] * 0.5 + 0.1
		rm.height = 0.35
		ring.mesh = rm
		ring.material_override = _trim
		_deco.add_child(ring)
		ring.position = base + Vector3.UP * (p[1] + p[2])
	var cap := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.65
	cone.height = 1.8
	cap.mesh = cone
	cap.material_override = _plaster[4]
	_deco.add_child(cap)
	cap.position = base + Vector3.UP * (h + 0.9)


## The bazaar lane (z 74-80, x 32-72): arches at both ends and in the middle, stalls under
## awnings along both walls, a donkey cart.
func _bazaar() -> void:
	var lane_z := 77.0
	for x in [33.0, 52.0, 71.0]:
		_arch(Vector3(x, 0, lane_z), Vector3(1, 0, 0), 5.0, 3.4, true, _plaster[2])
	var stalls := [36.0, 46.0, 50.0, 57.0, 62.0, 66.0]
	for i in stalls.size():
		var x: float = stalls[i]
		var side := -1.0 if i % 2 == 0 else 1.0
		var wall_z := 74.0 if side < 0 else 80.0
		var n := Vector3(0, 0, -side)
		if absf(x - 40.0) < 3.0 and side > 0:
			continue  # the dealer's door
		var cloth := _cloths[i % _cloths.size()]
		_awning(Vector3(x, 3.0, wall_z), n, 3.4, cloth, 1.7)
		var table := _box(_nav, Vector3(x, 0.45, wall_z + n.z * 0.75), Vector3(2.4, 0.9, 0.9), _wood)
		_mark_cover(table, Vector3(2.4, 0.9, 0.9))
		# Goods: jars and baskets on the table, a crate beside it.
		for k in 3:
			var jar := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.12
			cm.bottom_radius = 0.18
			cm.height = 0.35
			jar.mesh = cm
			jar.material_override = _cloths[(i + k + 2) % _cloths.size()] if k == 1 else _trim
			_deco.add_child(jar)
			jar.position = Vector3(x - 0.7 + k * 0.7, 1.08, wall_z + n.z * 0.75)
		var crate := _box(_nav, Vector3(x + 1.7, 0.3, wall_z + n.z * 0.5), Vector3(0.7, 0.6, 0.6), _wood)
		_dress(crate, "prop_crate_small.glb", Vector3(0.6, 0.4, 0.4))
	# Lanterns strung along the lane.
	for x in [42.0, 60.0]:
		_lantern(Vector3(x, 3.6, 74.4))


func _dealer() -> void:
	_building(Rect2(36, 80, 8, 8), 8.0, _plaster[3], [Vector2(0, -1)], false)
	_entrance(Vector3(40, 0, 80), Vector3(0, 0, -1), "ANTIQUITIES", 1.5, 2.6, 3.4)


## The railway station closes the avenue's west end: a tall hall, a clock over the doors.
func _station() -> void:
	var n := Vector3(1, 0, 0)
	_building(Rect2(-RING, 40, RING, 20), 13.0, _plaster[1], [Vector2(1, 0)], false)
	_entrance(Vector3(0, 0, 50), n, "", 3.4, 4.2)
	_sign(Vector3(0, 6.0, 50), n, "CAIRO CENTRAL STATION", 7.0, Color(0.2, 0.25, 0.32))
	# The clock: a white face in an iron ring, hands at ten past ten.
	var face := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 1.0
	cm.bottom_radius = 1.0
	cm.height = 0.12
	face.mesh = cm
	face.material_override = _flat(Color(0.92, 0.9, 0.82))
	_deco.add_child(face)
	face.position = Vector3(0.1, 9.0, 50)
	face.rotation.z = PI * 0.5
	for hand in [[0.75, 0.5], [0.55, -0.5]]:
		var h := _mesh(Vector3(0.2, 9.0, 50), Vector3(0.03, hand[0], 0.07), _iron)
		h.rotation.x = hand[1]
		h.position += Vector3(0, cos(hand[1]), -sin(hand[1])) * hand[0] * 0.5
	# Twin towers either side.
	for z in [44.4, 55.6]:
		_box(_nav, Vector3(0.8, 8.5, z), Vector3(3.2, 17.0, 3.2), _plaster[1])
		_mesh(Vector3(0.8, 17.2, z), Vector3(3.8, 0.4, 3.8), _trim)
		_mesh(Vector3(0.8, 18.4, z), Vector3(2.0, 2.0, 2.0), _plaster[4])
	_lantern(Vector3(0.35, 3.4, 47.8))
	_lantern(Vector3(0.35, 3.4, 52.2))


## Police headquarters on the avenue's south side.
func _police() -> void:
	var n := Vector3(0, 0, -1)
	_building(Rect2(2, 54, 10, 10), 10.0, _plaster[4], [Vector2(0, -1)], false)
	_entrance(Vector3(7, 0, 54), n, "POLICE", 1.8, 3.0, 3.0)
	_lantern(Vector3(5.6, 2.9, 53.7))
	_lantern(Vector3(8.4, 2.9, 53.7))
	for x in [4.0, 10.0]:
		_mesh(Vector3(x, 0.55, 53.0), Vector3(2.4, 1.1, 0.08), _iron)


## The south road out of the city: Sharia west runs through an arch in the outer ring to a
## checkpoint barrier (the act's lockdown happens here). Beyond it the road is only seen.
func _road_gate() -> void:
	_arch(Vector3(29, 0, SOUTH + 0.6), Vector3(0, 0, 1), 5.0, 3.8, true, _plaster[4])
	_mesh(Vector3(29, 1.0, SOUTH + 3.0), Vector3(6.0, 0.14, 0.14), _cloths[0])
	for x in [26.4, 31.6]:
		_mesh(Vector3(x, 0.55, SOUTH + 3.0), Vector3(0.2, 1.1, 0.2), _iron)
	var b := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(6.0, 6.0, 0.5)
	cs.shape = bs
	b.add_child(cs)
	add_child(b)
	b.position = Vector3(29, 3.0, SOUTH + 3.3)
	# The sentry box just inside, and the road on south.
	var hut := _box(_nav, Vector3(31.0, 1.25, 98.6), Vector3(1.2, 2.5, 1.2), _wood)
	_mark_cover(hut, Vector3(1.2, 2.5, 1.2))
	_mesh(Vector3(29, -0.01, SOUTH + RING + 40.0), Vector3(6.0, 0.02, 80.0), _street)
	var far := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(160, 80)
	far.mesh = pm
	far.material_override = _sand
	add_child(far)
	far.position = Vector3(29, -0.05, SOUTH + RING + 40.0)


## The caravanserai: a walled yard (x 80-104, z 54-100) with an arched gate on Sharia east,
## stables in an arcade along the north wall, troughs, hay, a hitching rail.
func _caravanserai() -> void:
	var x0 := 80.0
	var x1 := 104.0
	var z0 := 54.0
	var z1 := SOUTH
	var h := 6.0
	var mat := _plaster[2]
	var gate_z := 77.0
	var gate_w := 5.0
	var t := 1.2
	# West wall either side of the gate, with windows on the street.
	_building(Rect2(x0, z0, t, gate_z - gate_w * 0.5 - z0), h, mat, [Vector2(-1, 0)], false)
	_building(Rect2(x0, gate_z + gate_w * 0.5, t, z1 - gate_z - gate_w * 0.5), h, mat, [Vector2(-1, 0)], false)
	_building(Rect2(x0, z0, x1 - x0, t), h, mat, [Vector2(0, -1)], false)
	_building(Rect2(x0, z1 - t, x1 - x0, t), h, mat, [], false)
	_building(Rect2(x1 - t, z0, t, z1 - z0), h, mat, [Vector2(1, 0)], false)
	# The gate: an arch through the wall, its band carrying the name.
	_mesh(Vector3(x0 + t * 0.5, h - 0.8, gate_z), Vector3(t, 1.6, gate_w + 0.2), mat)
	_arch(Vector3(x0 + t * 0.5, 0, gate_z), Vector3(1, 0, 0), gate_w - 0.4, 2.8, false, mat)
	_sign(Vector3(x0, h - 0.6, gate_z), Vector3(-1, 0, 0), "CARAVANSERAI", 4.6, Color(0.3, 0.18, 0.1))
	# Packed earth in the yard.
	var yard := _mesh(Vector3((x0 + x1) * 0.5, 0.01, (z0 + z1) * 0.5), Vector3(x1 - x0 - 2.4, 0.02, z1 - z0 - 2.4), _sand)
	yard.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Stables: an arcade roof on posts along the north wall, stall dividers.
	for k in 7:
		_cylinder_post(Vector3(x0 + 3.0 + k * 3.0, 0, z0 + 4.2), 0.16, 3.4, _wood)
	_mesh(Vector3((x0 + x1) * 0.5, 3.5, z0 + 2.6), Vector3(x1 - x0 - 2.4, 0.2, 3.6), _wood)
	for k in 6:
		_box(_nav, Vector3(x0 + 4.5 + k * 3.0, 0.7, z0 + 2.4), Vector3(0.12, 1.4, 2.2), _wood)
	# The hitching rail in front of the stables.
	_box(_nav, Vector3(92, 1.0, z0 + 3.4), Vector3(14.0, 0.1, 0.1), _wood)
	for x in [85.0, 92.0, 99.0]:
		_box(_nav, Vector3(x, 0.5, z0 + 3.4), Vector3(0.14, 1.0, 0.14), _wood)
	# Troughs, hay, sacks: cover in the yard.
	for p in [[Vector3(96, 0, 70), Vector3(3.0, 0.7, 0.9)], [Vector3(96, 0, 84), Vector3(3.0, 0.7, 0.9)]]:
		var trough := _box(_nav, p[0] + Vector3.UP * p[1].y * 0.5, p[1], _wood)
		_mark_cover(trough, p[1])
	var hay := _flat(Color(0.78, 0.66, 0.35))
	for p in [Vector3(101, 0, 90), Vector3(101, 0, 92.4), Vector3(99.4, 0, 91.2)]:
		var bale := _box(_nav, p + Vector3.UP * 0.45, Vector3(1.4, 0.9, 1.0), hay)
		_mark_cover(bale, Vector3(1.4, 0.9, 1.0))
	for p in [Vector3(84, 0, 92), Vector3(86, 0, 94)]:
		var crate := _box(_nav, p + Vector3.UP * 0.5, Vector3(1.6, 1.0, 1.0), _wood)
		_mark_cover(crate, Vector3(1.6, 1.0, 1.0))
		_dress(crate, "prop_crate_large.glb", Vector3(1.0, 0.52, 0.49))
	# A well in the middle.
	var well := _cylinder(_nav, Vector3(92, 0.45, 77), 1.0, 0.9)
	(well.get_child(1) as MeshInstance3D).material_override = _trim
	_lantern(Vector3(x0 + 1.4, 3.0, gate_z - 3.2))
	_lantern(Vector3(x0 + 1.4, 3.0, gate_z + 3.2))


## The quay road along the Nile, the pier (the docks), the labour market's crates and sacks.
func _quay() -> void:
	# Bollards along the edge.
	for z in range(4, 100, 8):
		if z > 44 and z < 56:
			continue
		var b := _cylinder(_nav, Vector3(RIVER_X - 0.6, 0.35, z), 0.22, 0.7)
		(b.get_child(1) as MeshInstance3D).material_override = _iron
	for z in [8.0, 30.0, 70.0, 92.0]:
		_palm(Vector3(RIVER_X - 2.4, 0, z), 8.0 + _rng.randf_range(-1, 1))
	# The labour market: men wait by sacks and crates for a day's hire.
	var sack := _flat(Color(0.7, 0.62, 0.45))
	# Kept to the river edge: the quay road (x 104-112) stays open the whole way.
	for p in [Vector3(110.5, 0, 66.8), Vector3(110.3, 0, 68.2), Vector3(110.6, 0, 73)]:
		var s := _box(_nav, p + Vector3.UP * 0.35, Vector3(1.0, 0.7, 0.7), sack)
		s.rotation.y = _rng.randf() * PI
	for p in [Vector3(110.4, 0, 57.4), Vector3(110.4, 0, 58.8)]:
		var crate := _box(_nav, p + Vector3.UP * 0.5, Vector3(1.6, 1.0, 1.0), _wood)
		_mark_cover(crate, Vector3(1.6, 1.0, 1.0))
		_dress(crate, "prop_crate_large.glb", Vector3(1.0, 0.52, 0.49))
	_sign(Vector3(104.05, 3.0, 62), Vector3(1, 0, 0), "LABOUR EXCHANGE", 4.4, Color(0.3, 0.18, 0.1))
	# The pier: a timber deck on posts out into the river, where the riverboat ties up.
	var deck := _box(_nav, Vector3((RIVER_X + 126) * 0.5, -0.15, 50), Vector3(126 - RIVER_X, 0.3, 6.0), _wood)
	deck.name = "Pier"
	for x in range(int(RIVER_X) + 2, 127, 3):
		for z in [47.2, 52.8]:
			var post := _cylinder(_nav, Vector3(x, -1.2, z), 0.16, 2.4)
			(post.get_child(1) as MeshInstance3D).material_override = _wood
	for p in [Vector3(116, 0, 52.4), Vector3(122, 0, 52.4)]:
		var c := _cylinder(_nav, p + Vector3.UP * 0.25, 0.18, 0.5)
		(c.get_child(1) as MeshInstance3D).material_override = _iron
	var stack := _box(_nav, Vector3(115, 0.5, 48.2), Vector3(1.6, 1.0, 1.0), _wood)
	_mark_cover(stack, Vector3(1.6, 1.0, 1.0))
	_dress(stack, "prop_crate_large.glb", Vector3(1.0, 0.52, 0.49))
	_arch(Vector3(RIVER_X + 0.3, 0, 50), Vector3(1, 0, 0), 5.2, 3.6, true, _plaster[4])
	_lantern(Vector3(125.6, 1.8, 52.6))
	# Invisible edges: the quay (open only onto the pier) and round the pier.
	for e in [[Vector3(RIVER_X + 0.5, 4, (-RING + 47.0) * 0.5), Vector3(1, 8, 47.0 + RING)],
			[Vector3(RIVER_X + 0.5, 4, (53.0 + SOUTH + RING) * 0.5), Vector3(1, 8, SOUTH + RING - 53.0)],
			[Vector3(119, 4, 46.5), Vector3(14, 8, 1)], [Vector3(119, 4, 53.5), Vector3(14, 8, 1)],
			[Vector3(126.5, 4, 50), Vector3(1, 8, 8)]]:
		var b := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = e[1]
		cs.shape = bs
		b.add_child(cs)
		add_child(b)
		b.position = e[0]


func _river() -> void:
	# The quay wall, the water, and the far bank with palms.
	_box(_nav, Vector3(RIVER_X - 0.3, -1.6, (SOUTH) * 0.5), Vector3(0.6, 3.2, SOUTH + RING * 2.0), _trim)
	var water := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(90, 400)
	water.mesh = pm
	water.material_override = _water
	add_child(water)
	water.position = Vector3(RIVER_X + 45, WATER_Y, 50)
	var bank := MeshInstance3D.new()
	var bm := PlaneMesh.new()
	bm.size = Vector2(300, 400)
	bank.mesh = bm
	bank.material_override = _sand
	add_child(bank)
	bank.position = Vector3(RIVER_X + 90 + 150, -0.6, 50)
	for i in 14:
		_palm(Vector3(RIVER_X + 92 + _rng.randf_range(0, 14), -0.6, -80 + i * 16 + _rng.randf_range(-4, 4)), _rng.randf_range(7, 10), false)
	# The ground below the quay wall, so the water has a bottom.
	_mesh(Vector3(RIVER_X + 45, WATER_Y - 2.0, 50), Vector3(90, 0.2, 400), _dark)


# ---------------------------------------------------------------- dressing

func _cylinder_post(at: Vector3, radius: float, h: float, mat: Material) -> StaticBody3D:
	var c := _cylinder(_nav, at + Vector3.UP * h * 0.5, radius, h)
	(c.get_child(1) as MeshInstance3D).material_override = mat
	return c


## A date palm: a leaning trunk and a crown of fronds. `solid`: the trunk blocks.
func _palm(at: Vector3, h: float, solid := true) -> void:
	var lean := Vector3(_rng.randf_range(-0.08, 0.08), 0, _rng.randf_range(-0.08, 0.08))
	var trunk := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.16
	cm.bottom_radius = 0.26
	cm.height = h
	trunk.mesh = cm
	trunk.material_override = _wood
	_deco.add_child(trunk)
	trunk.position = at + Vector3.UP * h * 0.5
	trunk.rotation = lean
	if solid:
		var b := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var shape := CylinderShape3D.new()
		shape.radius = 0.28
		shape.height = 2.0
		cs.shape = shape
		b.add_child(cs)
		_nav.add_child(b)
		b.position = at + Vector3.UP
	var top := at + (trunk.transform.basis * Vector3.UP) * h
	for k in 9:
		var a := TAU * k / 9.0 + _rng.randf() * 0.3
		var frond := MeshInstance3D.new()
		var qm := BoxMesh.new()
		qm.size = Vector3(0.5, 0.02, 3.0)
		frond.mesh = qm
		frond.material_override = _leaf
		_deco.add_child(frond)
		frond.rotation_order = EULER_ORDER_YXZ
		frond.rotation = Vector3(-0.45 + _rng.randf_range(-0.1, 0.2), a, 0)
		frond.position = top + Vector3(sin(a), -0.35, cos(a)) * 1.3


func _pot_palm(at: Vector3) -> void:
	var pot := _cylinder(_nav, at + Vector3.UP * 0.35, 0.35, 0.7)
	(pot.get_child(1) as MeshInstance3D).material_override = _trim
	for k in 6:
		var a := TAU * k / 6.0
		var frond := _mesh(at + Vector3(sin(a) * 0.45, 1.2, cos(a) * 0.45), Vector3(0.25, 0.02, 1.0), _leaf)
		frond.rotation_order = EULER_ORDER_YXZ
		frond.rotation = Vector3(-0.6, a, 0)


## A hanging / wall lantern that lights up at dusk.
func _lantern(at: Vector3) -> void:
	var lamp := _prop(_deco, "prop_lantern.glb", at)
	if lamp == null:
		_mesh(at + Vector3.UP * 0.15, Vector3(0.22, 0.3, 0.22), _lamp_glass)
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.7, 0.38)
	l.omni_range = 7.0
	l.light_energy = 0.0
	l.shadow_enabled = false
	_deco.add_child(l)
	l.position = at + Vector3.UP * 0.25
	_lamps.append(l)


## An iron street lamp on a post.
func _street_lamp(at: Vector3) -> void:
	_cylinder_post(at, 0.09, 3.8, _iron)
	_mesh(at + Vector3.UP * 3.98, Vector3(0.24, 0.34, 0.24), _lamp_glass)
	_mesh(at + Vector3.UP * 4.19, Vector3(0.34, 0.08, 0.34), _iron)
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.75, 0.45)
	l.omni_range = 11.0
	l.light_energy = 0.0
	_deco.add_child(l)
	l.position = at + Vector3.UP * 3.8
	_lamps.append(l)


func _cart(at: Vector3, yaw: float) -> void:
	var cart := _box(_nav, at + Vector3.UP * 0.75, Vector3(1.4, 0.5, 2.4), _wood)
	cart.rotation.y = yaw
	_mark_cover(cart, Vector3(1.4, 0.5, 2.4))
	for s in [-1.0, 1.0]:
		var wheel := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.55
		cm.bottom_radius = 0.55
		cm.height = 0.1
		wheel.mesh = cm
		wheel.material_override = _wood
		cart.add_child(wheel)
		wheel.position = Vector3(s * 0.78, -0.2, 0.1)
		wheel.rotation.z = PI * 0.5
	for s in [-0.4, 0.4]:
		var shaft := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.08, 0.08, 1.8)
		shaft.mesh = bm
		shaft.material_override = _wood
		cart.add_child(shaft)
		shaft.position = Vector3(s, -0.25, -2.0)


## Street lamps, a parked truck, awnings over ordinary shops, cover along the avenue.
func _street_life() -> void:
	for x in [8.0, 24.0, 36.0, 58.0, 84.0, 100.0]:
		_street_lamp(Vector3(x, 0, 46.8))
	for x in [16.0, 52.0, 76.0, 104.0]:
		_street_lamp(Vector3(x, 0, 53.2))
	for z in [12.0, 32.0, 68.0, 90.0]:
		_street_lamp(Vector3(26.8, 0, z))
		_street_lamp(Vector3(79.2, 0, z + 6.0))
	# A truck parked on the avenue (image-to-3d's, its collision a box).
	var truck := _box(_nav, Vector3(30, 1.1, 51.8), Vector3(2.1, 2.2, 5.0), _wood)
	truck.rotation.y = PI * 0.5
	_dress_native(truck, "vehicle_truck.glb")
	_cart(Vector3(12, 0, 52.5), PI * 0.5 + 0.15)
	# Shop awnings along the avenue and the streets (ordinary shops, no spot).
	var shops := [[Vector3(10, 3.2, 46), Vector3(0, 0, 1)], [Vector3(18, 3.2, 54), Vector3(0, 0, -1)],
		[Vector3(34, 3.2, 54), Vector3(0, 0, -1)], [Vector3(90, 3.2, 54), Vector3(0, 0, -1)],
		[Vector3(26, 3.2, 20), Vector3(1, 0, 0)], [Vector3(32, 3.2, 14), Vector3(-1, 0, 0)],
		[Vector3(32, 3.2, 36), Vector3(-1, 0, 0)], [Vector3(26, 3.2, 86), Vector3(1, 0, 0)],
		[Vector3(72, 3.2, 90), Vector3(1, 0, 0)], [Vector3(72, 3.2, 60), Vector3(1, 0, 0)]]
	for i in shops.size():
		_awning(shops[i][0], shops[i][1], 4.0, _cloths[(i + 1) % _cloths.size()], 1.7)
	# Low walls and stacked goods to duck behind (the act may hold a street fight).
	for p in [[Vector3(20, 0, 47.5), Vector3(2.4, 1.0, 0.8)], [Vector3(70, 0, 52.4), Vector3(2.0, 1.0, 0.9)],
			[Vector3(29, 0, 40), Vector3(0.9, 1.0, 2.4)], [Vector3(77, 0, 64), Vector3(0.9, 1.0, 2.0)],
			[Vector3(29, 0, 86), Vector3(0.9, 1.0, 2.0)]]:
		var crate := _box(_nav, p[0] + Vector3.UP * p[1].y * 0.5, p[1], _wood)
		_mark_cover(crate, p[1])
		_dress(crate, "prop_crate_large.glb", Vector3(1.0, 0.52, 0.49))


## Dress a box with a prop at its own size (centred on the box, standing on its floor).
func _dress_native(body: StaticBody3D, file: String) -> void:
	if not ResourceLoader.exists(PROPS + file):
		return
	var size: Vector3 = (body.get_child(0) as CollisionShape3D).shape.size
	var p: Node3D = (load(PROPS + file) as PackedScene).instantiate()
	body.add_child(p)
	p.position = Vector3(0, -size.y * 0.5, 0)
	(body.get_child(1) as MeshInstance3D).visible = false


## Rooftops beyond the ring, domes and minarets: the rest of the city.
func _skyline() -> void:
	for i in 70:
		var side := i % 3
		var t := _rng.randf()
		var out := _rng.randf_range(4, 40)
		var p: Vector3
		match side:
			0: p = Vector3(-RING - out, 0, lerpf(-RING - 40, SOUTH + RING + 40, t))
			1: p = Vector3(lerpf(-RING - 40, RIVER_X, t), 0, -RING - out)
			_: p = Vector3(lerpf(-RING - 40, RIVER_X, t), 0, SOUTH + RING + out)
		var h := _rng.randf_range(7, 18)
		if side == 2 and absf(p.x - 29.0) < 15.0:
			continue  # keep the south road's view open
		var size := Vector3(_rng.randf_range(8, 16), h, _rng.randf_range(8, 16))
		_mesh(p + Vector3.UP * h * 0.5, size, _plaster[_rng.randi() % _plaster.size()])
	for p in [Vector3(-40, 0, 70), Vector3(40, 0, -45), Vector3(80, 0, 140), Vector3(-30, 0, -20)]:
		_minaret(p, _rng.randf_range(22, 30))
	# The citadel's domes far off to the south-east.
	for p in [Vector3(20, 0, 160), Vector3(40, 0, 170)]:
		var dome := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 9.0
		sm.height = 12.0
		dome.mesh = sm
		dome.material_override = _plaster[4]
		_deco.add_child(dome)
		dome.position = p + Vector3.UP * 14.0
		_mesh(p + Vector3.UP * 7.0, Vector3(22, 14, 22), _plaster[4])


# ---------------------------------------------------------------- light

## The time of day: 0 morning (sun low in the east, over the Nile), 0.5 noon (high, south),
## 1 dusk (low and red in the west; the lamps and some windows come on). act2.gd moves it as the
## day's actions are spent; ease_day_time slides it there.
func set_day_time(t: float) -> void:
	day_time = clampf(t, 0.0, 1.0)
	if _sun == null:
		return
	var high := sin(PI * day_time)            # 0 at the ends of the day, 1 at noon
	var dusk := smoothstep(0.7, 1.0, day_time)
	var dawn := 1.0 - smoothstep(0.0, 0.25, day_time)
	var elevation := lerpf(10.0, 3.0, day_time) + 55.0 * high
	_sun.rotation = Vector3(deg_to_rad(-elevation), deg_to_rad(lerpf(90.0, -90.0, day_time)), 0)
	_sun.light_energy = lerpf(0.8, 1.7, high) * (1.0 - 0.35 * dusk)
	_sun.light_color = Color(1.0, 0.92, 0.78).lerp(Color(1.0, 0.82, 0.62), dawn).lerp(Color(1.0, 0.5, 0.28), dusk)
	_env.ambient_light_energy = lerpf(0.45, 0.6, high) * (1.0 - 0.4 * dusk)
	_env.ambient_light_sky_contribution = lerpf(1.0, 0.6, dusk)
	_env.fog_light_color = Color(0.82, 0.7, 0.52).lerp(Color(0.75, 0.68, 0.62), dawn).lerp(Color(0.6, 0.38, 0.32), dusk)
	_env.fog_density = lerpf(0.003, 0.0055, maxf(dawn, dusk))
	_env.tonemap_exposure = lerpf(0.92, 1.1, dusk)
	var sky := _env.sky.sky_material as ProceduralSkyMaterial
	sky.sky_top_color = Color(0.36, 0.55, 0.8).lerp(Color(0.42, 0.55, 0.75), dawn).lerp(Color(0.18, 0.18, 0.38), dusk)
	sky.sky_horizon_color = Color(0.9, 0.8, 0.62).lerp(Color(0.95, 0.78, 0.65), dawn).lerp(Color(0.95, 0.55, 0.35), dusk)
	sky.ground_horizon_color = Color(0.82, 0.7, 0.52).lerp(Color(0.5, 0.32, 0.25), dusk)
	# The curse: dust thickens the air, the gloom drains the sun and sky toward a bruised brown.
	if dust > 0.0 or gloom > 0.0:
		_sun.light_energy *= 1.0 - 0.25 * dust - 0.6 * gloom
		_sun.light_color = _sun.light_color.lerp(Color(0.9, 0.55, 0.35), gloom * 0.6)
		_env.ambient_light_energy *= 1.0 - 0.45 * gloom
		_env.fog_light_color = _env.fog_light_color.lerp(Color(0.72, 0.56, 0.34), dust * 0.7).lerp(Color(0.2, 0.14, 0.12), gloom)
		_env.fog_density += 0.008 * dust + 0.01 * gloom
		sky.sky_top_color = sky.sky_top_color.lerp(Color(0.62, 0.5, 0.36), dust * 0.5).lerp(Color(0.1, 0.07, 0.08), gloom)
		sky.sky_horizon_color = sky.sky_horizon_color.lerp(Color(0.85, 0.65, 0.4), dust * 0.6).lerp(Color(0.35, 0.18, 0.12), gloom)
		sky.ground_horizon_color = sky.ground_horizon_color.lerp(Color(0.25, 0.15, 0.12), gloom)
	var lamps_on := maxf(smoothstep(0.82, 0.97, day_time), gloom)
	for l in _lamps:
		l.light_energy = 1.6 * lamps_on
	_win_lit.emission_energy_multiplier = 0.9 * lamps_on
	_lamp_glass.emission_energy_multiplier = 3.0 * lamps_on


## Slide the time of day to `t` over `seconds` (0 = at once).
func ease_day_time(t: float, seconds := 3.0) -> void:
	if _day_tween:
		_day_tween.kill()
	if seconds <= 0.0:
		set_day_time(t)
		return
	_day_tween = create_tween()
	_day_tween.tween_method(set_day_time, day_time, clampf(t, 0.0, 1.0), seconds).set_trans(Tween.TRANS_SINE)


## The day's time for `actions_left` of `per_day` actions: each action spent moves it on; the
## last one spent brings dusk.
static func day_time_for(actions_left: int, per_day: int) -> float:
	return clampf(1.0 - float(actions_left) / maxf(per_day, 1), 0.0, 1.0)


## The curse over the city (Act 7): `dust_f` 0..1 hangs ochre dust in the air, `gloom_f` 0..1
## darkens the sky by day (the lamps come on). Lies over the time of day; eased by the act.
func set_curse(dust_f: float, gloom_f: float) -> void:
	dust = clampf(dust_f, 0.0, 1.0)
	gloom = clampf(gloom_f, 0.0, 1.0)
	set_day_time(day_time)


## How full the streets are: 1 every townsperson about, 0 nobody (the sickness).
func set_crowd(f: float) -> void:
	Ambience.set_crowd(f)  # the street murmur thins with them
	var keep := roundi(clampf(f, 0.0, 1.0) * townsfolk.size())
	for i in townsfolk.size():
		var t := townsfolk[i]
		if is_instance_valid(t):
			t.visible = i < keep
			t.process_mode = Node.PROCESS_MODE_INHERIT if i < keep else Node.PROCESS_MODE_DISABLED


## Kept for the older callers: 0 = the afternoon, 1 = dusk.
func set_night(f: float) -> void:
	set_day_time(lerpf(0.55, 1.0, f))


func set_indoor(_f: float) -> void:
	pass  # all outdoors: the time of day is set_day_time's job


# ---------------------------------------------------------------- people and animals

func _townsfolk() -> void:
	var k := 0
	for w in WALKS:
		var t := Townsperson.make(self, w, Characters.DIR + TOWNSFOLK_MODELS[k % TOWNSFOLK_MODELS.size()])
		k += 1
		if t:
			townsfolk.append(t)
	for pair in CHATS:
		for i in 2:
			var p: Vector3 = pair[i]
			var n := Npc.make(self, "townsfolk_%d" % k, p, "", Characters.DIR + TOWNSFOLK_MODELS[k % TOWNSFOLK_MODELS.size()])
			n.face_towards(pair[1 - i])
			n.rotation.y = atan2(-(pair[1 - i] - p).x, -(pair[1 - i] - p).z)
			if n.body:
				n.body.talk = 0.6
			k += 1
			townsfolk.append(n)


## Horses and donkeys standing about (HorseRig only, idling: no Ride prompt and not in the
## expedition's transport). Each stands in a box the navmesh goes round.
func _animals() -> void:
	for a in ANIMALS:
		var at: Vector3 = a[0]
		var size: float = a[2]
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(0.6, 1.5, 2.3) * size
		cs.shape = bs
		cs.position = Vector3(0, 0.75 * size, -0.3 * size)
		body.add_child(cs)
		_nav.add_child(body)
		body.position = at
		body.rotation.y = a[1]
		var rig := HorseRig.create()
		rig.scale = Vector3.ONE * size
		body.add_child(rig)
		_animals_idle.append(rig)
	_cart(Vector3(62.4, 0, 77.6), PI * 0.5)


func _process(delta: float) -> void:
	super(delta)
	for rig in _animals_idle:
		rig.animate(delta, 0.0, 0.0)


## "The thieves leave in 2 days. He reaches the city in 1 day." from Game.countdowns.
static func countdown_line() -> String:
	var t := int(Game.countdowns.get("thieves", 0))
	var m := int(Game.countdowns.get("mummy", 0))
	return "The thieves leave in %d day%s. He reaches the city in %d day%s." % [t, "" if t == 1 else "s", m, "" if m == 1 else "s"]


## A point by spot `id`'s door for an act to stand someone: `along` metres along the facade (+ =
## to the right as you face the door from the street) and `out` metres further out into the
## street than the spot itself. Spots with no facade (bazaar, labour, docks, road_gate) use +Z.
func near_spot(id: String, along: float, out := 0.0) -> Vector3:
	var s: Array = SPOTS[id]
	var f: Vector2 = s[1]
	var n := Vector3(f.x, 0, f.y) if f != Vector2.ZERO else Vector3(0, 0, 1)
	var right := Vector3(n.z, 0, -n.x)  # facing the door (-n), +X of that view
	return (s[0] as Vector3) + right * along + n * out


## The nearest open ground to `want` where a person fits: for acts that put people round the
## player or a door, so nobody stands inside a building. Rings outward, 1 m apart, up to 15 m.
## (Not the navmesh: baked from collision triangles, it also has unreachable islands on the
## ground inside every building.)
func open_point(want: Vector3) -> Vector3:
	var space := get_world_3d().direct_space_state
	var q := PhysicsShapeQueryParameters3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.7
	q.shape = cap
	q.collision_mask = 1
	for r in 16:
		var steps := 1 if r == 0 else 8 + r * 4
		for k in steps:
			var a := TAU * k / steps
			var p := want + Vector3(cos(a), 0, sin(a)) * r
			q.transform = Transform3D(Basis.IDENTITY, Vector3(p.x, 1.0, p.z))
			if space.intersect_shape(q, 1).is_empty():
				return Vector3(p.x, want.y, p.z)
	return want
