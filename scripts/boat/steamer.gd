class_name Steamer
extends Node3D
## Stage 1 of the riverboat in gameplan/route_stops_plan.md (Simon: a 52 m Cook's steamer, its
## saloon and cabins walk-in, the same boat for Act 3 and Act 8's night): three decks as blockout,
## built static into a level so its navmesh bakes with it. No act uses it yet: RiverBoat (36 m,
## two decks, moving) stays the game's.
##   var boat := Steamer.build(level, at, yaw)   # `at` on the waterline, midships; before the bake
## Local frame as RiverBoat's: -Z the bow, +X starboard. The decks:
##   the hold (its floor 1 m under the waterline): cargo, down a stair from the aft deck
##   the main deck (1.25 m up): the foredeck with the loads and a gangway gap each side; the deck
##     house, walk-in: the saloon forward (dining tables, the piano, the bar), then six cabins on a
##     corridor; the galley aft; side walkways round it; the stern wheel behind the aft deck
##   the sun deck (the house's roof, 4.25 m up), by a stair from the foredeck: the wheelhouse
##     forward, the funnel, deckchairs under an awning aft (the Americans' corner); its rails and
##     the saloon roof are the fight's high ground
## spots: foredeck, gangway_port, gangway_starboard, saloon, piano, bar, corridor, cabin_1..6,
## galley, aft_deck, hold, stair_up, sun_deck, wheelhouse, deckchairs, stern. interactables:
## steamer_bed (your cabin's bunk: sleep and save).
## Placeholders (blockout until models come): the hull, the house and its rooms, the wheel and its
## housing, the funnel, the wheelhouse, the furniture (tables, chairs, piano, bar, bunks, the
## galley's stove), the awning and deckchairs; the crates are the kit's.

const LENGTH := 52.0
const BEAM := 11.0
## A real steamer's freeboard: the river's surface is kept out of the hull (-f9's
## RiverWater.mask_hull), so the hold can sit under the waterline without the water showing in it.
## Every floor is on the navmesh's 0.25 m grid (with `at` on it too): off it, the navmesh rode half
## a metre over the decks and the stairs' joins came apart.
const DECK := 1.25         # the main deck's surface over the waterline
const SUN := 4.25          # the sun deck's
const HOLD := -1.0         # the hold's floor (2.25 m under the deck: the navmesh wants headroom)
const HOUSE := Rect2(-3.8, -10, 7.6, 22)    # the deck house (x, z): saloon z -10..2, cabins 2..12
const SALOON_END := 2.0
const CABINS_END := 12.0
const CORRIDOR := 0.8      # half its width
const GALLEY := Rect2(-3.8, 12, 2.8, 4)
const HOLD_RECT := Rect2(-4.0, 10, 8.0, 10)
const HOLD_STAIR := Rect2(2.3, 16.7, 1.6, 3.3)  # down toward the bow, from z 20 to 17
const SUN_STAIR := Rect2(2.4, -14.5, 1.5, 4.5)  # up toward the stern, to the sun deck at z -10
const GANGWAY := Vector2(-16, -13)          # the rail's gap each side (z)

var level: Level
var yaw := 0.0
var spots := {}
var _xf := Transform3D.IDENTITY
var _white: StandardMaterial3D
var _hull: StandardMaterial3D
var _deck: StandardMaterial3D
var _wood: StandardMaterial3D
var _dark: StandardMaterial3D
var _cloth: StandardMaterial3D
var _glass: StandardMaterial3D


static func build(lvl: Level, at: Vector3, facing := 0.0) -> Steamer:
	var s := Steamer.new()
	s.name = "Steamer"
	s.level = lvl
	s.yaw = facing
	s._xf = Transform3D(Basis(Vector3.UP, facing), at)
	lvl.add_child(s)
	s.global_transform = s._xf
	RiverWater.mask_hull(s, Vector2(BEAM * 0.5 - 0.15, 21.8), 4.0)   # no river inside the hull
	s._materials()
	s._hull_and_hold()
	s._main_deck()
	s._saloon()
	s._cabins()
	s._galley()
	s._sun_deck()
	s._wheel()
	s._loads()
	for k: String in s.spots:
		s.spots[k] = s._w(s.spots[k])
	s.level.interactables["steamer_bed"] = Interactable.make(lvl, s.spots.cabin_1 + Vector3.UP * 0.9, "Sleep in your cabin (save)", "steamer_bed", 1.0)
	return s


func _w(p: Vector3) -> Vector3:
	return _xf * p


func _materials() -> void:
	_white = level._floor_mat.duplicate() as StandardMaterial3D
	_white.albedo_texture = level._noise_tex(Color(0.86, 0.84, 0.78), Color(0.95, 0.94, 0.9), 0.04, false)
	_hull = level._floor_mat.duplicate() as StandardMaterial3D
	_hull.albedo_texture = level._noise_tex(Color(0.12, 0.12, 0.13), Color(0.2, 0.2, 0.21), 0.05, false)
	_deck = level._floor_mat.duplicate() as StandardMaterial3D
	_deck.albedo_texture = level._noise_tex(Color(0.55, 0.42, 0.28), Color(0.68, 0.54, 0.38), 0.08, false)
	_wood = StandardMaterial3D.new()
	_wood.albedo_color = Color(0.36, 0.22, 0.12)
	_dark = StandardMaterial3D.new()
	_dark.albedo_color = Color(0.08, 0.07, 0.06)
	_cloth = StandardMaterial3D.new()
	_cloth.albedo_color = Color(0.86, 0.8, 0.66)
	_cloth.cull_mode = BaseMaterial3D.CULL_DISABLED
	_glass = StandardMaterial3D.new()
	_glass.albedo_color = Color(0.3, 0.38, 0.42, 0.35)
	_glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA


# ---------------------------------------------------------------- pieces (in the boat's frame)

## A solid from (x0, y0, z0) to (x1, y1, z1), into the level's _nav.
func _solid(x0: float, y0: float, z0: float, x1: float, y1: float, z1: float, mat: Material) -> StaticBody3D:
	var size := Vector3(absf(x1 - x0), absf(y1 - y0), absf(z1 - z0))
	var b := level._box(level._nav, _w(Vector3((x0 + x1) * 0.5, (y0 + y1) * 0.5, (z0 + z1) * 0.5)), size, mat)
	b.rotation.y = yaw
	return b


## A mesh only, nothing walks into it.
func _mesh(m: Mesh, p: Vector3, mat: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = mat
	add_child(mi)
	mi.position = p
	mi.rotation = rot
	return mi


func _box_mesh(x0: float, y0: float, z0: float, x1: float, y1: float, z1: float, mat: Material) -> void:
	var bm := BoxMesh.new()
	bm.size = Vector3(absf(x1 - x0), absf(y1 - y0), absf(z1 - z0))
	_mesh(bm, Vector3((x0 + x1) * 0.5, (y0 + y1) * 0.5, (z0 + z1) * 0.5), mat)


## A wall along x (at z) or along z (at x) from a to b, from y0 to y1, with gaps [from, to] cut.
func _wall_x(z: float, a: float, b: float, y0: float, y1: float, gaps: Array, mat: Material, t := 0.15) -> void:
	for seg: Vector2 in _cut(minf(a, b), maxf(a, b), gaps):
		_solid(seg.x, y0, z - t * 0.5, seg.y, y1, z + t * 0.5, mat)


func _wall_z(x: float, a: float, b: float, y0: float, y1: float, gaps: Array, mat: Material, t := 0.15) -> void:
	for seg: Vector2 in _cut(minf(a, b), maxf(a, b), gaps):
		_solid(x - t * 0.5, y0, seg.x, x + t * 0.5, y1, seg.y, mat)


## [a, b] minus the gaps, as segments.
static func _cut(a: float, b: float, gaps: Array) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var at := a
	var sorted := gaps.duplicate()
	sorted.sort_custom(func(p: Vector2, q: Vector2) -> bool: return p.x < q.x)
	for g: Vector2 in sorted:
		if g.x > at + 0.01:
			out.append(Vector2(at, minf(g.x, b)))
		at = maxf(at, g.y)
	if at < b - 0.01:
		out.append(Vector2(at, b))
	return out


## A wall with windows: solid to 1 m, open to 2.1 m (posts every 2 m), solid again to the top.
func _windowed_z(x: float, a: float, b: float, doors: Array) -> void:
	_wall_z(x, a, b, DECK, DECK + 1.0, doors, _white)
	_wall_z(x, a, b, DECK + 2.1, SUN - 0.2, [], _white)
	for seg: Vector2 in _cut(a, b, doors):
		var z := seg.x
		while z <= seg.y:
			_solid(x - 0.08, DECK + 1.0, z - 0.1, x + 0.08, DECK + 2.1, z + 0.1, _white)
			z += 2.0


# ---------------------------------------------------------------- the hull and the hold

func _hull_and_hold() -> void:
	var hx := BEAM * 0.5
	var z0 := -22.0
	var z1 := 22.0
	_solid(-hx, -1.6, z0, hx, HOLD, z1, _hull)                       # the bottom (the hold's floor on it)
	for s: float in [-1.0, 1.0]:
		_solid(s * (hx - 0.3), -1.6, z0, s * hx, DECK - 0.2, z1, _hull)   # the sides
		_box_mesh(s * hx, 0.0, z0, s * (hx + 0.02), DECK, z1, _white)    # the white band above the water
	# Under the main deck: solid, but for the hold.
	var h := HOLD_RECT
	var fill := [Rect2(-hx + 0.3, z0, BEAM - 0.6, h.position.y - z0), Rect2(-hx + 0.3, h.end.y, BEAM - 0.6, z1 - h.end.y),
		Rect2(-hx + 0.3, h.position.y, h.position.x + hx - 0.3, h.size.y), Rect2(h.end.x, h.position.y, hx - 0.3 - h.end.x, h.size.y)]
	for r: Rect2 in fill:
		_solid(r.position.x, HOLD, r.position.y, r.end.x, DECK - 0.2, r.end.y, _hull)
	# The bow: a wedge of deck narrowing to the stem.
	for k in 5:
		var w := hx * (1.0 - (k + 1) / 5.5)
		_solid(-w, -1.6, z0 - k - 1.0, w, DECK, z0 - k, _hull)
	spots.hold = Vector3(-1.5, HOLD, 13.0)
	# The hold's loads.
	for c: Array in [[Vector3(-2.6, HOLD + 0.5, 11.5), Vector3(2.0, 1.0, 1.0)], [Vector3(-2.6, HOLD + 0.5, 18.0), Vector3(2.0, 1.0, 1.0)], [Vector3(1.0, HOLD + 0.4, 11.4), Vector3(1.0, 0.8, 1.0)]]:
		var b := _solid(c[0].x - c[1].x * 0.5, c[0].y - c[1].y * 0.5, c[0].z - c[1].z * 0.5, c[0].x + c[1].x * 0.5, c[0].y + c[1].y * 0.5, c[0].z + c[1].z * 0.5, _wood)
		level._dress(b, "prop_crate_large.glb", Vector3(1.0, 0.8, 1.0))
		level._mark_cover(b, c[1])
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.75, 0.45)
	l.light_energy = 0.8
	l.omni_range = 7.0
	add_child(l)
	l.position = Vector3(0, HOLD + 1.6, 15.0)


# ---------------------------------------------------------------- the main deck

func _main_deck() -> void:
	var hx := BEAM * 0.5
	var st := HOLD_STAIR
	# The deck, with the hold stair's well cut out.
	_solid(-hx, DECK - 0.2, -22.0, hx, DECK, st.position.y, _deck)
	_solid(-hx, DECK - 0.2, st.end.y, hx, DECK, 22.0, _deck)
	_solid(-hx, DECK - 0.2, st.position.y, st.position.x, DECK, st.end.y, _deck)
	_solid(st.end.x, DECK - 0.2, st.position.y, hx, DECK, st.end.y, _deck)
	# The stair down: eleven steps toward the bow, the first flush with the deck (a step just under
	# the deck's edge shares its navmesh cell with the deck slab: no headroom, the stair cut off).
	var n := 11
	for k in n:
		var top := DECK - k * (DECK - HOLD) / n
		var z := st.end.y - (k + 1) * st.size.y / n
		_solid(st.position.x, HOLD, z, st.end.x, top, z + st.size.y / n, _wood)
	# The bow's deck planks over the wedge.
	for k in 5:
		var w := hx * (1.0 - (k + 1) / 5.5)
		_box_mesh(-w, DECK, -22.0 - k - 1.0, w, DECK + 0.01, -22.0 - k, _deck)
	# The rails: round the sides (a gap each side at the gangway), across the stern, along the bow.
	for s: float in [-1.0, 1.0]:
		_wall_z(s * (hx - 0.1), -22.0, 22.0, DECK, DECK + 1.0, [GANGWAY], _wood, 0.12)
		var a := Vector3(s * hx * 0.82, 0, -22.0)
		var b := Vector3(0, 0, -27.0)
		var r := _solid(0, DECK, 0, 0.12, DECK + 1.0, a.distance_to(b), _wood)
		r.global_position = _w((a + b) * 0.5 + Vector3.UP * (DECK + 0.5))
		r.rotation.y = yaw + atan2(a.x - b.x, a.z - b.z)
	_wall_x(22.0, -hx, hx, DECK, DECK + 1.0, [], _wood, 0.12)
	spots.foredeck = Vector3(0, DECK, -18.0)
	spots.gangway_port = Vector3(-hx + 0.8, DECK, (GANGWAY.x + GANGWAY.y) * 0.5)
	spots.gangway_starboard = Vector3(hx - 0.8, DECK, (GANGWAY.x + GANGWAY.y) * 0.5)
	spots.aft_deck = Vector3(1.0, DECK, 20.5)
	spots.stern = Vector3(-3.0, DECK, 21.0)


# ---------------------------------------------------------------- the saloon

func _saloon() -> void:
	var h := HOUSE
	var z0 := h.position.y
	# Fore wall: the door in the middle, windows either side.
	_wall_x(z0, h.position.x, h.end.x, DECK, DECK + 1.0, [Vector2(-0.75, 0.75)], _white)
	_wall_x(z0, h.position.x, h.end.x, DECK + 2.1, SUN - 0.2, [], _white)
	for x: float in [-3.0, -1.6, 1.6, 3.0]:
		_solid(x - 0.1, DECK + 1.0, z0 - 0.08, x + 0.1, DECK + 2.1, z0 + 0.08, _white)
	_solid(-0.85, DECK + 1.0, z0 - 0.08, -0.75, DECK + 2.1, z0 + 0.08, _white)
	_solid(0.75, DECK + 1.0, z0 - 0.08, 0.85, DECK + 2.1, z0 + 0.08, _white)
	# Sides: windows down both, a door each side midway.
	for s: float in [-1.0, 1.0]:
		_windowed_z(s * h.end.x, z0, SALOON_END, [Vector2(-5.75, -4.25)])
	# Aft wall to the cabins: the corridor's opening.
	_wall_x(SALOON_END, h.position.x, h.end.x, DECK, SUN - 0.2, [Vector2(-CORRIDOR, CORRIDOR)], _white)
	# The furniture: four dining tables with chairs, the piano, the bar along the aft wall.
	var chair := CylinderMesh.new()
	chair.top_radius = 0.22
	chair.bottom_radius = 0.22
	chair.height = 0.45
	for x: float in [-2.1, 2.1]:
		for z: float in [-7.6, -3.4]:
			_solid(x - 0.5, DECK, z - 0.8, x + 0.5, DECK + 0.75, z + 0.8, _wood)
			for side: float in [-1.0, 1.0]:
				for dz: float in [-0.4, 0.4]:
					_mesh(chair, Vector3(x + side * 0.85, DECK + 0.22, z + dz), _wood)
	_solid(-3.6, DECK, -9.8, -2.2, DECK + 1.25, -9.1, _dark)              # the piano, port forward corner
	_solid(1.0, DECK, SALOON_END - 0.9, 3.6, DECK + 1.1, SALOON_END - 0.3, _wood)   # the bar
	_box_mesh(1.0, DECK + 1.6, SALOON_END - 0.2, 3.6, DECK + 2.4, SALOON_END - 0.12, _dark)  # bottles behind it
	_lights([Vector3(0, SUN - 0.5, -7.0), Vector3(0, SUN - 0.5, -2.0)], 1.1, 7.0)
	spots.saloon = Vector3(0, DECK, -5.5)
	spots.piano = Vector3(-1.0, DECK, -9.1)
	spots.bar = Vector3(2.3, DECK, SALOON_END - 1.6)


func _lights(points: Array, energy: float, r: float) -> void:
	for p: Vector3 in points:
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.8, 0.55)
		l.light_energy = energy
		l.omni_range = r
		l.omni_attenuation = 1.4
		add_child(l)
		l.position = p


# ---------------------------------------------------------------- the cabins

func _cabins() -> void:
	var h := HOUSE
	var n := 3
	var length := (CABINS_END - SALOON_END) / n
	# The outer walls (a window each, glass in it), the corridor's walls with a door to each cabin.
	for s: float in [-1.0, 1.0]:
		_wall_z(s * h.end.x, SALOON_END, CABINS_END, DECK, SUN - 0.2, [], _white)
		var doors: Array = []
		for k in n:
			var mid := SALOON_END + (k + 0.5) * length
			doors.append(Vector2(mid - 0.75, mid + 0.75))
			_box_mesh(s * (h.end.x + 0.09), DECK + 1.2, mid - 0.5, s * (h.end.x + 0.1), DECK + 2.0, mid + 0.5, _glass)
		_wall_z(s * CORRIDOR, SALOON_END, CABINS_END, DECK, SUN - 0.2, doors, _white, 0.1)
		for k in range(1, n):
			_wall_x(SALOON_END + k * length, s * CORRIDOR, s * h.end.x, DECK, SUN - 0.2, [], _white, 0.1)
		for k in n:
			var mid := SALOON_END + (k + 0.5) * length
			var x0 := s * (h.end.x - 0.15)
			var x1 := s * (h.end.x - 1.05)
			_solid(minf(x0, x1), DECK, mid - 1.0, maxf(x0, x1), DECK + 0.5, mid + 1.0, _wood)   # the bunk
			_box_mesh(minf(x0, x1), DECK + 0.5, mid - 1.0, maxf(x0, x1), DECK + 0.62, mid + 1.0, _cloth)
			var id := "cabin_%d" % (k + 1 + (0 if s > 0.0 else n))
			spots[id] = Vector3(s * (CORRIDOR + 1.0), DECK, mid)
			_lights([Vector3(s * 2.2, SUN - 0.6, mid)], 0.5, 3.5)
	# The corridor's aft end opens onto the aft deck.
	_wall_x(CABINS_END, h.position.x, h.end.x, DECK, SUN - 0.2, [Vector2(-CORRIDOR, CORRIDOR)], _white)
	_lights([Vector3(0, SUN - 0.5, (SALOON_END + CABINS_END) * 0.5)], 0.6, 6.0)
	spots.corridor = Vector3(0, DECK, (SALOON_END + CABINS_END) * 0.5)


# ---------------------------------------------------------------- the galley

func _galley() -> void:
	var g := GALLEY
	_wall_x(g.end.y, g.position.x, g.end.x, DECK, SUN - 0.2, [], _white)
	_wall_z(g.position.x, g.position.y, g.end.y, DECK, SUN - 0.2, [], _white)
	_wall_z(g.end.x, g.position.y, g.end.y, DECK, SUN - 0.2, [Vector2(13.25, 14.75)], _white)
	_solid(g.position.x + 0.1, DECK, g.position.y + 0.1, g.position.x + 0.9, DECK + 0.9, g.position.y + 2.2, _dark)   # the stove
	_solid(g.position.x + 1.4, DECK, g.end.y - 1.0, g.end.x - 0.2, DECK + 0.85, g.end.y - 0.3, _wood)  # the table
	_lights([Vector3(g.get_center().x, SUN - 0.6, g.get_center().y)], 0.6, 4.0)
	spots.galley = Vector3(g.get_center().x + 0.2, DECK, g.get_center().y - 0.4)


# ---------------------------------------------------------------- the sun deck

func _sun_deck() -> void:
	var hx := BEAM * 0.5
	var z0 := HOUSE.position.y
	var z1 := GALLEY.end.y
	_solid(-hx + 0.3, SUN - 0.2, z0, hx - 0.3, SUN, z1, _deck)
	# Its rails (the stair's top left open), posts down to the main deck's rail at the corners.
	var st := SUN_STAIR
	_wall_x(z0, -hx + 0.3, hx - 0.3, SUN, SUN + 1.0, [Vector2(st.position.x, st.end.x)], _wood, 0.1)
	_wall_x(z1, -hx + 0.3, hx - 0.3, SUN, SUN + 1.0, [], _wood, 0.1)
	for s: float in [-1.0, 1.0]:
		_wall_z(s * (hx - 0.35), z0, z1, SUN, SUN + 1.0, [], _wood, 0.1)
		for z: float in [z0, -2.0, 6.0, z1]:
			_box_mesh(s * (hx - 0.4), DECK + 1.0, z - 0.06, s * (hx - 0.28), SUN - 0.2, z + 0.06, _white)
	# The stair up from the foredeck: fifteen steps toward the stern.
	var n := 15
	for k in n:
		var top := DECK + (k + 1) * (SUN - DECK) / n
		var z := st.position.y + k * st.size.y / n
		_solid(st.position.x, DECK, z, st.end.x, top, z + st.size.y / n, _wood)
	# The wheelhouse forward (walk-in: the door aft), the wheel, glass all round.
	var w := Rect2(-2.0, z0 + 0.3, 4.0, 3.2)
	_wall_x(w.position.y, w.position.x, w.end.x, SUN, SUN + 1.1, [], _white)
	_wall_x(w.end.y, w.position.x, w.end.x, SUN, SUN + 2.5, [Vector2(-0.75, 0.75)], _white)
	_wall_z(w.position.x, w.position.y, w.end.y, SUN, SUN + 1.1, [], _white)
	_wall_z(w.end.x, w.position.y, w.end.y, SUN, SUN + 1.1, [], _white)
	_box_mesh(w.position.x, SUN + 1.1, w.position.y - 0.05, w.end.x, SUN + 2.3, w.position.y + 0.05, _glass)
	_solid(w.position.x - 0.1, SUN + 2.4, w.position.y - 0.1, w.end.x + 0.1, SUN + 2.6, w.end.y + 0.1, _white)   # its roof
	for c: Vector2 in [Vector2(w.position.x, w.position.y), Vector2(w.end.x, w.position.y), Vector2(w.position.x, w.end.y), Vector2(w.end.x, w.end.y)]:
		_solid(c.x - 0.08, SUN + 1.1, c.y - 0.08, c.x + 0.08, SUN + 2.4, c.y + 0.08, _white)
	var wheel := TorusMesh.new()
	wheel.inner_radius = 0.38
	wheel.outer_radius = 0.45
	_mesh(wheel, Vector3(0, SUN + 1.2, w.position.y + 0.6), _wood, Vector3(PI * 0.5, 0, 0))
	# The funnel, black with a band; deckchairs under an awning aft.
	var funnel := level._cylinder(level._nav, _w(Vector3(0, SUN + 3.0, -1.5)), 0.75, 6.0)
	(funnel.get_child(1) as MeshInstance3D).material_override = _dark
	var band := CylinderMesh.new()
	band.top_radius = 0.78
	band.bottom_radius = 0.78
	band.height = 0.5
	_mesh(band, Vector3(0, SUN + 5.0, -1.5), _white)
	for k in 6:
		var x := -3.2 + (k % 3) * 2.4
		var z := 8.0 + floorf(k / 3.0) * 3.0
		_solid(x - 0.3, SUN, z - 0.7, x + 0.3, SUN + 0.4, z + 0.7, _cloth)
	_box_mesh(-hx + 0.4, SUN + 2.5, 6.0, hx - 0.4, SUN + 2.56, z1, _cloth)   # the awning
	for c: Vector2 in [Vector2(-hx + 0.6, 6.0), Vector2(hx - 0.6, 6.0), Vector2(-hx + 0.6, z1 - 0.2), Vector2(hx - 0.6, z1 - 0.2)]:
		_box_mesh(c.x - 0.05, SUN, c.y - 0.05, c.x + 0.05, SUN + 2.5, c.y + 0.05, _wood)
	spots.stair_up = Vector3(st.get_center().x, DECK, st.position.y - 2.0)
	spots.sun_deck = Vector3(-2.5, SUN, 2.0)
	spots.wheelhouse = Vector3(0, SUN, w.get_center().y + 0.2)
	spots.deckchairs = Vector3(-2.0, SUN, 13.0)


# ---------------------------------------------------------------- the wheel and the loads

## The stern wheel in its housing, behind the aft rail (dressing; the rail stops anyone going over).
func _wheel() -> void:
	var paddles := CylinderMesh.new()
	paddles.top_radius = 2.4
	paddles.bottom_radius = 2.4
	paddles.height = BEAM - 1.6
	_mesh(paddles, Vector3(0, DECK - 0.3, 24.4), _wood, Vector3(0, 0, PI * 0.5))
	for s: float in [-1.0, 1.0]:
		_box_mesh(s * (BEAM * 0.5 - 0.6), -0.4, 22.0, s * (BEAM * 0.5 - 0.3), DECK + 2.4, 26.0, _white)
	_box_mesh(-BEAM * 0.5 + 0.3, DECK + 2.2, 22.0, BEAM * 0.5 - 0.3, DECK + 2.4, 26.0, _white)


## The foredeck's loads: crates and the capstan (cover for the deck fights).
func _loads() -> void:
	for c: Array in [[Vector3(-2.6, DECK + 0.4, -19.0), Vector3(2.0, 0.8, 1.0)], [Vector3(2.4, DECK + 0.4, -20.5), Vector3(1.0, 0.8, 1.0)], [Vector3(-3.0, DECK + 0.4, -12.0), Vector3(1.0, 0.8, 2.0)]]:
		var b := _solid(c[0].x - c[1].x * 0.5, c[0].y - c[1].y * 0.5, c[0].z - c[1].z * 0.5, c[0].x + c[1].x * 0.5, c[0].y + c[1].y * 0.5, c[0].z + c[1].z * 0.5, _wood)
		level._dress(b, "prop_crate_large.glb", Vector3(1.0, 0.8, 1.0))
		level._mark_cover(b, c[1])
	var cap := level._cylinder(level._nav, _w(Vector3(0, DECK + 0.4, -23.0)), 0.45, 0.8)
	(cap.get_child(1) as MeshInstance3D).material_override = _dark
