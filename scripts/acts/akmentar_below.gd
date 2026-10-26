class_name AkmentarBelow
extends Level
## Act 5's map: Akmentar's second level and the royal tomb, a labyrinthine complex (Simon: "many
## large chambers with interconnected paths, LIKE a labyrinth complex, not a literal labyrinth"):
## - large chambers (columns, fire pillars, a point of interest in most) joined by 4 m passages that
##   branch and loop, so there's always more than one way through, laid out by hand;
## - the antechamber and the royal tomb at the far north, the south hall with the stairs up;
## - deep halls 5 m lower with walkways crossing over them at the upper level (Simon: "walkways
##   over chambers"): the Great Pit with its stone bridge, and the chariot hall, whose walkway is
##   the direct way east; a ramp leads down into each (points of interest on both floors);
## - secret walls ("?"): hollow-sounding cracked stone that opens once you know the trick (a clue
##   flag), one sealing the Scarab Mother's shrine, one a shortcut into the south hall;
## - short blind passages; at the awakening minions come out of them and the chamber corners.
## Map letters as Level's, plus: "," pit floor, "=" bridge, "/" ramp, "?" secret wall,
## a-i points of interest, 1-5 royal tomb points, R royal door, G guardian, X vents, Z minions, C collapse,
## "|" a drop-slab door (pairs: one slab across a 4 m passage), V a scarab vent in a wall.
## Three ways out: the main stairs south of the south hall, and a long shaft up at each side.

const W := 48
const H := 44
const PIT_DROP := 5.0
const SEED := 1926
const ROYAL := Rect2i(16, 1, 16, 7)  # x, y, w, h (cells)
const ANTE := Rect2i(19, 9, 10, 3)
const SOUTH := Rect2i(18, 33, 12, 4)
const PIT := Rect2i(8, 16, 12, 9)
const BRIDGE_ROW := 20
const RAMP := Rect2i(20, 23, 5, 1)  # high end east (x 24), descends west into the pit
## The second deep hall (the chariots, "g"): a walkway along DEEP_WALK at the upper level, a ramp
## (DEEP_RAMP, high end north) down into it from the middle chamber.
const DEEP := Rect2i(27, 26, 8, 5)
const DEEP_WALK := 27
const DEEP_RAMP := Rect2i(31, 24, 2, 4)
## The side shafts: their west columns (two wide), from the complex's last row up to the surface.
const SHAFTS := [4, 42]
const SLABS := 5  # drop-slabs across passages, plus one at the main stairs' neck
const SCARAB_VENTS := 4
## The chambers. A letter key is a point of interest at its centre ("h", the shrine, is sealed).
const CHAMBERS := {
	"a": Rect2i(1, 13, 6, 6), "b": Rect2i(36, 13, 8, 6), "c": Rect2i(1, 25, 6, 6), "d": Rect2i(37, 25, 8, 6),
	"f": Rect2i(27, 14, 7, 6), "g": Rect2i(27, 26, 8, 5), "h": Rect2i(38, 20, 4, 3),
	"hub": Rect2i(22, 14, 4, 6), "low": Rect2i(21, 26, 4, 5), "west": Rect2i(9, 27, 8, 4), "mid": Rect2i(29, 21, 5, 3),
}
## The passages between them (4 m: two cells wide), as the rects they open.
const PASSAGES := [
	Rect2i(23, 12, 2, 2),   # antechamber -> hub
	Rect2i(7, 13, 15, 2),   # hub -> the opening chapel (a), along the top of the pit
	Rect2i(5, 19, 2, 2),    # a -> the bridge's west end
	Rect2i(21, 19, 2, 2),   # the bridge's east end -> hub
	Rect2i(24, 20, 2, 2),   # hub -> the ramp's top
	Rect2i(25, 22, 2, 5),   # the ramp's top -> the low hall and the chariots (g)
	Rect2i(26, 16, 1, 2),   # hub -> the erased king (f)
	Rect2i(34, 15, 2, 2),   # f -> the builders (b)
	Rect2i(43, 19, 2, 6),   # b -> the embalmers (d), down the east side
	Rect2i(30, 20, 2, 1),   # f -> mid
	Rect2i(34, 21, 3, 2),   # mid -> the shrine's secret wall (a blind end until it opens)
	Rect2i(35, 27, 2, 2),   # the walkway -> d
	Rect2i(25, 27, 2, 2),   # low -> the chariot hall's walkway
	Rect2i(17, 28, 4, 2),   # west -> low
	Rect2i(7, 28, 2, 2),    # the wards (c) -> west
	Rect2i(1, 19, 2, 6),    # a -> c, down the west side
	Rect2i(23, 31, 2, 2),   # low -> the south hall's neck
	Rect2i(4, 31, 2, 1),    # c -> the west shaft
	Rect2i(42, 31, 2, 1),   # d -> the east shaft
	Rect2i(15, 31, 2, 4),   # west -> the shortcut's secret wall into the south hall
]
## Blind passages; at the awakening a minion comes out of the far end of each ("Z"). Nothing moves
## down here before then (Simon: no mummies before the awakening).
const BLIND := [[Rect2i(30, 11, 2, 3), Vector2i(30, 11), "Z"], [Rect2i(40, 10, 2, 3), Vector2i(40, 10), "Z"],
	[Rect2i(12, 31, 2, 3), Vector2i(12, 33), "Z"], [Rect2i(39, 31, 2, 2), Vector2i(39, 32), "Z"]]
## More minions waiting in chamber corners.
const MINIONS := [Vector2i(1, 25), Vector2i(43, 13), Vector2i(9, 27), Vector2i(34, 30)]
## The point of interest on the pit's floor, and the one in the antechamber.
const PIT_POI := Vector2i(11, 22)
const ANTE_POI := Vector2i(20, 10)
## Secret walls: cell -> the clue flag that reveals the trick.
const SECRETS := {Vector2i(37, 21): "found_builders", Vector2i(17, 34): "found_symbols"}
## Map letters -> -f9's site ids (sites/akmentar_below.json, sites/royal_tomb.json). The Builders' Wall
## reveals the sealed room (the Scarab Mother's shrine); the Gallery of Wards the shortcut.
const SITE_IDS := {"a": "opening_chapel", "b": "builders", "c": "wards", "d": "embalmers", "e": "treasury",
	"f": "erased_king", "g": "chariots", "h": "scarab_shrine", "i": "weeping_stair",
	"1": "canopic", "2": "amulet", "3": "treasure", "4": "altar", "5": "sarcophagus"}

var pois := {}  # "a".."i" -> floor position
var royal_pois := {}  # "1".."5"
var vents: Array[Vector3] = []
var minion_spawns: Array[Vector3] = []
var collapse_points: Array[Vector3] = []
var guardian_spawn := Vector3.ZERO
var royal_door: StaticBody3D
var stair_top := Vector3.ZERO  # the main stairs' top
var exits: Array[Vector3] = []  # every stair top, the main one first
var slab_doors: Array[SlabDoor] = []
var neck_slab: SlabDoor  # the one across the main stairs' way in
var scarab_vents: Array[Dictionary] = []  # {point, normal}
var secret_doors: Array[Node] = []
var amulet: Node3D  # on the royal tomb's plinth "2" until the thieves take it
var sarc_lid: Node3D  # the royal sarcophagus's lid (it slides off at the awakening)
var _door_cells: Array[Vector3] = []
var _pit := {}  # Vector2i -> true for cells at the lower level (pit floor, bridge, ramp foot)
var _rng := RandomNumberGenerator.new()


# ---------------------------------------------------------------- the layout

func map_rows() -> Array:
	_rng.seed = SEED
	var g: Array = []
	for y in H:
		g.append("#".repeat(W).split(""))
	_stamp(g, ROYAL, ".")
	_stamp(g, ANTE, ".")
	_stamp(g, SOUTH, ".")
	for k in CHAMBERS:
		_stamp(g, CHAMBERS[k], ".")
	for r: Rect2i in PASSAGES:
		_stamp(g, r, ".")
	_pit_hall(g)
	_deep_hall(g)
	for b in BLIND:
		_stamp(g, b[0], ".")
		var tip: Vector2i = b[1]
		g[tip.y][tip.x] = b[2]
	for m: Vector2i in MINIONS:
		g[m.y][m.x] = "Z"
	_secret_room(g)
	_dress_chambers(g)
	# Royal tomb dressing.
	var rx := ROYAL.position.x
	for p in [[rx + 2, 2, "1"], [rx + 13, 2, "2"], [rx + 1, 4, "3"], [rx + 14, 4, "4"], [rx + 3, 6, "5"],
			[rx + 7, 3, "S"], [rx + 7, 4, "G"], [rx + 1, 1, "X"], [rx + 14, 1, "X"], [rx + 10, 6, "B"], [rx + 5, 6, "B"]]:
		g[p[1]][p[0]] = p[2]
	for p in [[rx + 4, 2], [rx + 11, 2], [rx + 4, 5], [rx + 11, 5]]:
		g[p[1]][p[0]] = "P"  # columns down the royal tomb
	g[ROYAL.end.y][23] = "R"
	g[ROYAL.end.y][24] = "R"
	g[ANTE_POI.y][ANTE_POI.x] = "i"
	g[ANTE.position.y + 1][ANTE.end.x - 2] = "B"
	# Stairs up at the south, torches on the stair walls.
	for y in range(SOUTH.end.y, H - 1):
		g[y][23] = "D"
		g[y][24] = "D"
	for y in [SOUTH.end.y + 1, H - 3]:
		g[y][22] = "L"
		g[y][25] = "L"
	g[SOUTH.position.y + 1][SOUTH.position.x + 1] = "B"
	g[SOUTH.position.y + 1][SOUTH.end.x - 2] = "B"
	for x in [SOUTH.position.x + 3, SOUTH.end.x - 4]:
		g[SOUTH.position.y][x] = "P"
		g[SOUTH.end.y - 1][x] = "P"
	# The side shafts: long stairs up from the complex's bottom row at each side.
	for x in SHAFTS:
		for y in range(SOUTH.position.y - 1, H - 1):
			g[y][x] = "D"
			g[y][x + 1] = "D"
		for y in [SOUTH.position.y + 1, H - 3]:
			g[y][x - 1] = "L"
			g[y][x + 2] = "L"
	g[SOUTH.position.y - 1][23] = "|"  # the main stairs' neck: one slab across both cells
	g[SOUTH.position.y - 1][24] = "|"
	_slabs_and_vents(g)
	_torches(g)
	var rows: Array = []
	for row in g:
		rows.append("".join(row))
	return rows


func _stamp(g: Array, r: Rect2i, ch: String) -> void:
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			g[y][x] = ch


## The Great Pit: a lower chamber ringed by rock, a bridge across it at the upper level (joining
## the passages on both sides), and a ramp from the east down to its floor.
func _pit_hall(g: Array) -> void:
	_stamp(g, PIT.grow(1), "#")
	_stamp(g, PIT, ",")
	for y in range(PIT.position.y, PIT.end.y):
		for x in range(PIT.position.x, PIT.end.x):
			_pit[Vector2i(x, y)] = true
	for x in range(PIT.position.x - 1, PIT.end.x + 1):
		g[BRIDGE_ROW][x] = "="
	g[BRIDGE_ROW][PIT.position.x - 2] = "."
	g[BRIDGE_ROW][PIT.end.x + 1] = "."
	g[BRIDGE_ROW][PIT.position.x - 1] = "."  # the bridge's ends sit on solid ground
	g[BRIDGE_ROW][PIT.end.x] = "."
	# Ramp: a walled run from the east at its top down to the pit floor.
	_stamp(g, Rect2i(RAMP.position.x, RAMP.position.y - 1, RAMP.size.x, 3), "#")
	for x in range(RAMP.position.x, RAMP.end.x):
		g[RAMP.position.y][x] = "/"
	g[RAMP.position.y][RAMP.end.x] = "."
	g[RAMP.position.y][RAMP.end.x + 1] = "."
	g[PIT_POI.y][PIT_POI.x] = "e"
	g[PIT.position.y + 1][PIT.position.x + 1] = "B"
	g[PIT.end.y - 2][PIT.end.x - 2] = "B"
	g[PIT.position.y + 3][PIT.end.x - 1] = "X"  # scarabs well up from the pit at the awakening


## The chariot hall: sunk 5 m behind a ring of rock, a walkway across it at the upper level from
## the low hall to the embalmers, and a ramp down into it from the middle chamber.
func _deep_hall(g: Array) -> void:
	var ring := DEEP.grow(1)
	for y in range(ring.position.y, ring.end.y):
		for x in range(ring.position.x, ring.end.x):
			if not DEEP.has_point(Vector2i(x, y)):
				g[y][x] = "#"
	for y in range(DEEP.position.y, DEEP.end.y):
		for x in range(DEEP.position.x, DEEP.end.x):
			_pit[Vector2i(x, y)] = true
	for x in range(DEEP.position.x, DEEP.end.x):
		g[DEEP_WALK][x] = "="
	g[DEEP_WALK][DEEP.position.x - 1] = "."  # the walkway's ends on solid ground
	g[DEEP_WALK][DEEP.end.x] = "."
	for y in range(DEEP_RAMP.position.y, DEEP_RAMP.end.y):
		for x in range(DEEP_RAMP.position.x, DEEP_RAMP.end.x):
			if g[y][x] != "=":
				g[y][x] = "/"
			_pit[Vector2i(x, y)] = true


## The shrine ("h") is sealed: a ring of rock round it with one secret wall, at the end of the
## passage from the middle chamber. The other secret is the shortcut into the south hall.
func _secret_room(g: Array) -> void:
	var ring: Rect2i = (CHAMBERS.h as Rect2i).grow(1)
	for y in range(ring.position.y, ring.end.y):
		for x in range(ring.position.x, ring.end.x):
			if x == ring.position.x or x == ring.end.x - 1 or y == ring.position.y or y == ring.end.y - 1:
				g[y][x] = "#"
	for s in SECRETS:
		g[s.y][s.x] = "?"


## Each chamber's point of interest at its centre; columns inset from the corners of the big ones,
## fire pillars halfway along the sides.
func _dress_chambers(g: Array) -> void:
	for k in CHAMBERS:
		var r: Rect2i = CHAMBERS[k]
		var cx := r.position.x + r.size.x / 2
		var cy := r.position.y + r.size.y / 2
		if k.length() == 1:
			g[cy][cx] = k
		if k == "h":
			continue
		if r.size.x >= 6 and r.size.y >= 5:
			for p in [Vector2i(r.position.x + 1, r.position.y + 1), Vector2i(r.end.x - 2, r.position.y + 1),
					Vector2i(r.position.x + 1, r.end.y - 2), Vector2i(r.end.x - 2, r.end.y - 2)]:
				if g[p.y][p.x] == ".":
					g[p.y][p.x] = "P"
		for p in [Vector2i(r.position.x, cy), Vector2i(r.end.x - 1, cy)]:
			if g[p.y][p.x] == "." and _walled_beside(g, p):
				g[p.y][p.x] = "B"


## `p` has rock on at least one side (a fire pillar there stands against a wall, not in a doorway).
func _walled_beside(g: Array, p: Vector2i) -> bool:
	for d in [Vector2i(1, 0), Vector2i(-1, 0)]:
		if g[p.y + d.y][p.x + d.x] == "#":
			return true
	return false


## Drop-slabs across passages (one slab spans a 4 m passage: two cells marked "|") and scarab
## vents in passage walls. Passages on the ways from the antechamber to the exits go first, so every
## escape meets some; a slab only goes where a way round remains.
func _slabs_and_vents(g: Array) -> void:
	var pairs: Array = []  # [cell, its twin across the passage]
	var walls: Array[Vector2i] = []
	for y in range(ANTE.end.y + 1, SOUTH.position.y - 2):  # not on the exits' last approach
		for x in range(2, W - 3):
			if g[y][x] != ".":
				continue
			# Across a north-south passage: rock either side, open above and below.
			if g[y][x + 1] == "." and _rock(g[y][x - 1]) and _rock(g[y][x + 2]) 					and _open(g[y - 1][x]) and _open(g[y - 1][x + 1]) and _open(g[y + 1][x]) and _open(g[y + 1][x + 1]):
				pairs.append([Vector2i(x, y), Vector2i(x + 1, y)])
			# Across an east-west passage.
			if g[y + 1][x] == "." and _rock(g[y - 1][x]) and _rock(g[y + 2][x]) 					and _open(g[y][x - 1]) and _open(g[y + 1][x - 1]) and _open(g[y][x + 1]) and _open(g[y + 1][x + 1]):
				pairs.append([Vector2i(x, y), Vector2i(x, y + 1)])
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				if g[y + d.y][x + d.x] == "#":
					walls.append(Vector2i(x, y))
					break
	for i in pairs.size():
		var j := _rng.randi_range(i, pairs.size() - 1)
		var t: Array = pairs[i]
		pairs[i] = pairs[j]
		pairs[j] = t
	var route := _routes(g, Vector2i(23, ANTE.end.y + 1),
		[Vector2i(23, SOUTH.position.y - 2), Vector2i(SHAFTS[0], SOUTH.position.y - 2), Vector2i(SHAFTS[1], SOUTH.position.y - 2)])
	pairs.sort_custom(func(a, b): return route.has(a[0]) and not route.has(b[0]))
	var placed: Array[Vector2i] = []
	var reach := _reach(g)
	for pr in pairs:
		if placed.size() >= SLABS:
			break
		var c: Vector2i = pr[0]
		var near := false
		for o in placed:
			near = near or Vector2(o - c).length() < 6.0
		if near:
			continue
		# Only where a way round remains: with every slab shut, nobody can be sealed off from
		# all the exits (a slab coming down in your face means a detour, never a dead end).
		for q: Vector2i in pr:
			g[q.y][q.x] = "|"
		var r := _reach(g)
		if r.size() < reach.size() - 2:
			for q: Vector2i in pr:
				g[q.y][q.x] = "."
			continue
		reach = r
		placed.append(c)
	var vents := 0
	for i in walls.size():
		var c: Vector2i = walls[(i * 37) % walls.size()]
		if vents >= SCARAB_VENTS or g[c.y][c.x] != ".":
			continue
		var near := false
		for o in placed:
			near = near or Vector2(o - c).length() < 5.0
		if near:
			continue
		g[c.y][c.x] = "V"
		placed.append(c)
		vents += 1


static func _rock(ch: String) -> bool:
	return ch in ["#", "L"]


static func _open(ch: String) -> bool:
	return not ch in ["#", "L", "?", "|", "=", "/", ","]


## The cells that can walk to a way out (any stair cell), with the slabs ("|") shut.
func _reach(g: Array) -> Dictionary:
	var seen := {}
	var queue: Array[Vector2i] = []
	for y in H:
		for x in W:
			if g[y][x] == "D":
				seen[Vector2i(x, y)] = true
				queue.append(Vector2i(x, y))
	while not queue.is_empty():
		var cur: Vector2i = queue.pop_front()
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = cur + d
			if n.x < 0 or n.y < 0 or n.x >= W or n.y >= H or seen.has(n) or g[n.y][n.x] in ["#", "L", "?", "|"]:
				continue
			seen[n] = true
			queue.append(n)
	return seen


## Every cell on the shortest grid path from `from` to each of `goals` (a set: Vector2i -> true).
func _routes(g: Array, from: Vector2i, goals: Array) -> Dictionary:
	var parent := {from: from}
	var queue: Array[Vector2i] = [from]
	while not queue.is_empty():
		var cur: Vector2i = queue.pop_front()
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = cur + d
			if n.x < 0 or n.y < 0 or n.x >= W or n.y >= H or parent.has(n) or g[n.y][n.x] in ["#", "L", "?"]:
				continue
			parent[n] = cur
			queue.append(n)
	var on := {}
	for goal in goals:
		var c: Vector2i = goal
		while parent.has(c) and c != from:
			on[c] = true
			c = parent[c]
	return on


## Wall torches every few metres along the corridors (on rock that faces a floor cell).
func _torches(g: Array) -> void:
	for y in range(1, H - 1):
		for x in range(1, W - 1):
			if g[y][x] != "." or (x * 7 + y * 11) % 9 != 0:
				continue
			for d in [Vector2i(0, -1), Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, 1)]:
				if g[y + d.y][x + d.x] == "#":
					g[y + d.y][x + d.x] = "L"
					break


# ---------------------------------------------------------------- building

func _floor_y(r: int, c: int) -> float:
	return FLOOR_Y - PIT_DROP if _pit.has(Vector2i(c, r)) and _ch(r, c) != "=" else FLOOR_Y


func _build_tomb() -> void:
	var pit_y := FLOOR_Y - PIT_DROP
	var wall_h := WALL_H + PIT_DROP
	var stairs := {}
	for r in _rows:
		var c := 0
		while c < _cols:
			var ch := _ch(r, c)
			var p := _cell(r, c)
			if ch in ["#", "L"]:
				var run := 1
				while c + run < _cols and _ch(r, c + run) in ["#", "L"]:
					run += 1
				var mid := (_cell(r, c) + _cell(r, c + run - 1)) * 0.5
				_box(_nav, Vector3(mid.x, pit_y + wall_h * 0.5, mid.z), Vector3(run * CELL, wall_h, CELL), _stone)
				for k in run:
					if _ch(r, c + k) == "L":
						_wall_torch(r, c + k)
				c += run
				continue
			if ch == "?":
				_secret(r, c)
			elif ch == "D":
				var k := c if _ch(r, c - 1) != "D" else c - 1  # each stairwell keyed by its west column
				stairs[k] = Rect2i(c, r, 1, 1) if not stairs.has(k) else (stairs[k] as Rect2i).expand(Vector2i(c, r))
			elif ch == "/":
				pass  # the ramp is built as one piece below
			elif ch == "=":
				_bridge_cell(r, c)
			else:
				var fy := _floor_y(r, c)
				_box(_nav, Vector3(p.x, fy - 0.5, p.z), Vector3(CELL, 1.0, CELL), _floor_mat)
				var at := Vector3(p.x, fy, p.z)
				match ch:
					"P":
						_column(at, r, c)
					"B":
						_brazier(at)
					"S":
						_sarcophagus(at, r, c)
					"M":
						mummy_spawns.append(at)
					".", ",":
						pass
					_:
						_marker(ch, at, r, c)
			c += 1
	_ramp()
	# Ceiling over everything except the stairwell.
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
	for k in stairs:
		var st: Rect2i = stairs[k]
		st.size += Vector2i.ONE
		_stairs(st)
	_glyph_walls()


## A bridge cell: a narrow stone span at the upper level with low parapets, the pit floor below.
func _bridge_cell(r: int, c: int) -> void:
	var p := _cell(r, c)
	var pit_y := FLOOR_Y - PIT_DROP
	_box(_nav, Vector3(p.x, pit_y - 0.5, p.z), Vector3(CELL, 1.0, CELL), _floor_mat)
	_box(_nav, Vector3(p.x, FLOOR_Y - 0.4, p.z), Vector3(CELL, 0.8, 1.6), _stone)
	for side in [-1.0, 1.0]:
		var rail := _box(_nav, Vector3(p.x, FLOOR_Y + 0.35, p.z + side * 0.72), Vector3(CELL, 0.7, 0.16), _stone)
		rail.set_meta("parapet", true)


## The ramps down into the deep halls: into the pit (high end east, down to the west) and into the
## chariot hall (high end north, down to the south). Each is one sloped slab.
func _ramp() -> void:
	var pit_hi := _cell(RAMP.position.y, RAMP.end.x - 1) + Vector3(CELL * 0.5, 0, 0)
	var pit_lo := _cell(RAMP.position.y, RAMP.position.x) - Vector3(CELL * 0.5, PIT_DROP, 0)
	_slope(pit_hi, pit_lo, CELL)
	for x in range(RAMP.position.x, RAMP.end.x):
		_pit[Vector2i(x, RAMP.position.y)] = true  # the pit floor continues under the ramp's foot
	var mid_x := (_cell(0, DEEP_RAMP.position.x).x + _cell(0, DEEP_RAMP.end.x - 1).x) * 0.5
	var deep_hi := Vector3(mid_x, FLOOR_Y, _cell(DEEP_RAMP.position.y, 0).z - CELL * 0.5)
	var deep_lo := Vector3(mid_x, FLOOR_Y - PIT_DROP, _cell(DEEP_RAMP.end.y - 1, 0).z + CELL * 0.5)
	_slope(deep_hi, deep_lo, CELL * DEEP_RAMP.size.x)


func _slope(hi: Vector3, lo: Vector3, width: float) -> void:
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(width, 0.4, hi.distance_to(lo))
	cs.shape = bs
	body.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = bs.size
	mi.mesh = bm
	mi.material_override = _floor_mat
	body.add_child(mi)
	_nav.add_child(body)
	var b := Basis.looking_at(hi - lo, Vector3.UP)  # its long side (Z) runs down the slope
	body.global_transform = Transform3D(b, (hi + lo) * 0.5 - b.y * 0.2)


## A secret wall: a ClueDoor (it sinks once its clue flag is set) that sounds hollow when tried,
## with solid rock below it down to the pit level, and floor behind it for when it opens.
func _secret(r: int, c: int) -> void:
	var p := _cell(r, c)
	_box(_nav, Vector3(p.x, FLOOR_Y - 0.5, p.z), Vector3(CELL, 1.0, CELL), _floor_mat)
	_box(_nav, Vector3(p.x, FLOOR_Y - 1.0 - PIT_DROP * 0.5, p.z), Vector3(CELL, PIT_DROP, CELL), _stone)
	var flag: String = SECRETS.get(Vector2i(c, r), "found_builders")
	var d := ClueDoor.make(_nav, "secret_%d_%d" % [c, r], p, Vector3(CELL, WALL_H, CELL), flag,
		"The stone here sounds hollow. Fine cracks run round a block the size of a door, but it won't move.",
		"You press where the builders marked it. The block grinds back into the dark.")
	secret_doors.append(d)
	# Painted like every other wall (on the door, so it sinks with it): only the cracks give it away.
	var block := _kit_mesh("wall_glyph_b")
	if block == null:
		return
	for dir in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if _ch(r + dir.y, c + dir.x) in ["#", "L", "?"]:
			continue
		var out := Vector3(dir.x, 0, dir.y)  # from the door toward that floor
		for k in 2:
			var mi := MeshInstance3D.new()
			mi.mesh = block
			d.add_child(mi)
			mi.global_transform = Transform3D(Basis.looking_at(-out, Vector3.UP),
				p + out * (CELL * 0.5 - BLOCK.z * 0.5 + 0.02) + Vector3.UP * k * BLOCK.y)


func _marker(ch: String, p: Vector3, _r: int, _c: int) -> void:
	match ch:
		"a", "b", "c", "d", "e", "f", "g", "h", "i":
			pois[ch] = p
			_plinth(p, 0.9)
		"1", "2", "3", "4", "5":
			royal_pois[ch] = p
			_plinth(p, 1.1)
			var top := p + Vector3.UP * 1.1
			# The jars and the amulet are already gone when you get here (the thieves found them
			# while you were busy): what's left is the evidence. Simon: "you will see no one walked
			# over and stole them".
			if ch == "1":  # four clean rings in the dust and broken seals where the jars stood
				for k in 4:
					var at := top + Vector3((k % 2) * 0.34 - 0.17, 0.005, (k / 2) * 0.34 - 0.17)
					_disc(at, 0.1, Color(0.62, 0.55, 0.42))
					for j in 3:
						_chip(at + Vector3(randf_range(-0.16, 0.16), 0.0, randf_range(-0.16, 0.16)))
			elif ch == "2":  # the empty cradle: a stone saddle with a clean oval in its dust
				_box(self, top + Vector3.UP * 0.07, Vector3(0.34, 0.14, 0.26), _stone)
				_disc(top + Vector3.UP * 0.145, 0.06, Color(0.66, 0.6, 0.48))
			if ch in ["1", "2"]:  # light on the empty places, so you notice what's missing
				var glint := OmniLight3D.new()
				glint.light_color = Color(1.0, 0.8, 0.5)
				glint.light_energy = 1.2
				glint.omni_range = 2.2
				add_child(glint)
				glint.global_position = top + Vector3(0, 0.7, 0.5)
		"G":
			guardian_spawn = p
		"R":
			_door_cells.append(p)
		"X":
			vents.append(p)
		"Z":
			minion_spawns.append(p)
		"C":
			collapse_points.append(p)
		"|":
			# One slab across a 4 m passage: built by the first cell of the pair (west or north).
			if _ch(_r, _c - 1) == "|" or _ch(_r - 1, _c) == "|":
				return
			var across_x := _ch(_r, _c + 1) == "|"  # the pair lies east-west: the passage runs north-south
			var wide := 2.0 if across_x or _ch(_r + 1, _c) == "|" else 1.0
			var at := p + (Vector3(CELL * 0.5, 0, 0) if across_x else Vector3(0, 0, CELL * 0.5)) * (wide - 1.0)
			var slab := SlabDoor.make(_nav, at, Vector3(CELL * wide, WALL_H, 0.5), 0.0 if across_x else PI * 0.5, _stone)
			slab_doors.append(slab)
			if _r == SOUTH.position.y - 1 and _c == 23:
				neck_slab = slab
		"V":
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				if _ch(_r + d.y, _c + d.x) in ["#", "L"]:
					var n := Vector3(-d.x, 0, -d.y)
					scarab_vents.append({"point": p - n * CELL * 0.5 + Vector3.UP * 0.3, "normal": n})
					_vent_slot(p - n * CELL * 0.5, n)
					break


## A flat ring of lighter dust (what stood here kept the dust off).
func _disc(at: Vector3, radius: float, colour: Color) -> void:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = 0.01
	mi.mesh = cm
	var m := StandardMaterial3D.new()
	m.albedo_color = colour
	m.roughness = 1.0
	mi.material_override = m
	add_child(mi)
	mi.global_position = at


## A chip of broken plaster seal.
func _chip(at: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(randf_range(0.03, 0.06), 0.015, randf_range(0.02, 0.05))
	mi.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.78, 0.7, 0.58)
	mi.material_override = m
	add_child(mi)
	mi.global_position = at + Vector3.UP * 0.01
	mi.rotation.y = randf() * TAU


## A scarab vent you can spot: a black slot low in the wall under a carved stone lip, with a
## few dark holes beside it. `at` is on the wall's face at floor level, `n` faces out of the wall.
func _vent_slot(at: Vector3, n: Vector3) -> void:
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.02, 0.015, 0.01)
	dark.roughness = 1.0
	var face := Basis.looking_at(-n, Vector3.UP)
	var parts := [[Vector3(0, 0.36, 0.0), Vector3(1.2, 0.46, 0.05), dark],
		[Vector3(0, 0.66, 0.06), Vector3(1.5, 0.16, 0.14), _floor_mat],
		[Vector3(-0.7, 0.36, 0.04), Vector3(0.14, 0.62, 0.1), _floor_mat],
		[Vector3(0.7, 0.36, 0.04), Vector3(0.14, 0.62, 0.1), _floor_mat],
		[Vector3(-0.95, 0.55, 0.0), Vector3(0.12, 0.12, 0.04), dark],
		[Vector3(0.92, 0.2, 0.0), Vector3(0.1, 0.1, 0.04), dark],
		[Vector3(1.05, 0.72, 0.0), Vector3(0.08, 0.08, 0.04), dark]]
	for part in parts:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = part[1]
		mi.mesh = bm
		mi.material_override = part[2]
		add_child(mi)
		mi.global_transform = Transform3D(face, at + face * part[0] + n * 0.01)


# ---------------------------------------------------------------- the dungeon kit (image-to-3d)

const KIT := "dungeon/"
const BLOCK := Vector3(2.0, 2.5, 0.4)  # a glyph wall block; its carved face is +Z
const FRIEZE := Vector3(2.0, 0.6, 0.45)


## Every rock face that looks onto a floor gets carved, painted blocks, set into the rock so the
## corridors stay 2 m wide, stacked to the ceiling (four high down in the pit), with the frieze
## along the top. Drawn as one MultiMesh per design: thousands of blocks, a handful of draw calls.
func _glyph_walls() -> void:
	var designs := ["wall_glyph_a", "wall_glyph_b", "wall_glyph_c"]
	var meshes: Array[Mesh] = []
	for d in designs:
		meshes.append(_kit_mesh(d))
	var frieze := _kit_mesh("wall_glyph_frieze")
	if meshes.has(null):
		return
	var xforms: Array = [[], [], []]
	var tops: Array[Transform3D] = []
	var top_y := FLOOR_Y + WALL_H
	for r in _rows:
		for c in _cols:
			var ch := _ch(r, c)
			if ch in ["#", "L", "D"]:
				continue
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				if not _ch(r + d.y, c + d.x) in ["#", "L"]:
					continue
				var out := Vector3(-d.x, 0, -d.y)  # from the rock toward the floor
				var face := _cell(r, c) - out * CELL * 0.5
				var turn := Basis.looking_at(-out, Vector3.UP)  # +Z = out
				var base := _floor_y(r, c)
				var k := 0
				while base + k * BLOCK.y < top_y - 0.5:
					var at := Vector3(face.x, base + k * BLOCK.y, face.z) - out * (BLOCK.z * 0.5 - 0.02)
					var pick := absi(r * 7 + c * 13 + k * 5 + d.x * 3 + d.y * 11) % 3
					xforms[pick].append(Transform3D(turn, at))
					k += 1
				if frieze:
					tops.append(Transform3D(turn, Vector3(face.x, top_y - FRIEZE.y, face.z) - out * (FRIEZE.z * 0.5 - 0.05)))
	for i in 3:
		_multimesh(meshes[i], xforms[i])
	if frieze:
		_multimesh(frieze, tops)


func _multimesh(mesh: Mesh, xforms: Array) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	add_child(mmi)


## The mesh inside one of the kit's GLBs (they're single-mesh props).
func _kit_mesh(file: String) -> Mesh:
	var path := PROPS + KIT + file + ".glb"
	if not ResourceLoader.exists(path):
		return null
	var scene := (load(path) as PackedScene).instantiate()
	var found := scene.find_children("*", "MeshInstance3D", true, false)
	var mesh: Mesh = (found[0] as MeshInstance3D).mesh if not found.is_empty() else null
	scene.free()
	return mesh


## A real column (lotus, papyrus or square with carved figures) on a column cell's stone core.
func _column(at: Vector3, r: int, c: int) -> void:
	var body := _box(_nav, at + Vector3.UP * WALL_H * 0.5, Vector3(1.2, WALL_H, 1.2), _stone)
	var kinds := ["pillar_lotus", "pillar_papyrus", "pillar_square_glyph"]
	var prop := _prop(self, KIT + kinds[(r + c) % 3] + ".glb", at, PI * 0.5 * ((r * 3 + c) % 4))
	if prop:
		(body.get_child(1) as MeshInstance3D).visible = false


## Fire pillars in place of the blockout braziers: the tall ones in the royal tomb. The bowl doesn't
## cast shadows, or the flame's own light would be boxed in by it.
func _brazier(p: Vector3) -> void:
	var tall := ROYAL.has_point(Vector2i(int(p.x / CELL), int(p.z / CELL)))
	var h := 3.0 if tall else 1.8
	var b := _box(_nav, p + Vector3.UP * h * 0.5, Vector3(0.7, h, 0.7), _stone)
	var prop := _prop(self, KIT + ("fire_pillar_tall.glb" if tall else "fire_pillar.glb"), p)
	if prop == null:
		(b.get_child(1) as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_flame(b, Vector3.UP * (h * 0.5 + 0.35), 3.0, 11.0, true)
		return
	(b.get_child(1) as MeshInstance3D).visible = false
	for g in prop.find_children("*", "GeometryInstance3D", true, false):
		(g as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_flame(b, Vector3.UP * (h * 0.5 - 0.1), 3.0, 11.0, true)


## The royal sarcophagus (image-to-3d: 2.7 x 1.35 x 1.22 m, long along X, its lid a child "lid").
func _sarcophagus(p: Vector3, r: int, c: int) -> void:
	var along_z: bool = _ch(r - 1, c) in ["#", "L"]
	var size := Vector3(1.22, 1.35, 2.7) if along_z else Vector3(2.7, 1.35, 1.22)
	var base := _box(_nav, p + Vector3.UP * size.y * 0.5, size, _stone)
	_mark_cover(base, size)
	var prop := _prop(self, "act5/sarcophagus_royal.glb", p, PI * 0.5 if along_z else 0.0)
	if prop:
		(base.get_child(1) as MeshInstance3D).visible = false
		sarc_lid = prop.find_child("lid", true, false) as Node3D


## Slide the lid off (the awakening): it grinds aside and tips onto the floor.
func open_sarcophagus(secs := 1.8) -> void:
	if sarc_lid == null:
		return
	var tw := sarc_lid.create_tween()
	tw.tween_property(sarc_lid, "position:z", sarc_lid.position.z + 0.9, secs).set_trans(Tween.TRANS_SINE)
	tw.tween_property(sarc_lid, "rotation:x", 0.35, 0.35).set_ease(Tween.EASE_IN)


## A waist-high stone block a point of interest sits on (blockout).
func _plinth(p: Vector3, h: float) -> void:
	var b := _box(_nav, p + Vector3.UP * h * 0.5, Vector3(1.1, h, 1.1), _floor_mat)
	_mark_cover(b, Vector3(1.1, h, 1.1))


func _build_surface() -> void:
	# No desert down here: the stairs' top is the way out.
	player_spawn = _cell(SOUTH.position.y + 2, 23) + Vector3(CELL * 0.5, 0, 0)
	stair_top = _cell(H - 1, 23) + Vector3(CELL * 0.5, -FLOOR_Y, 0)
	exits = [stair_top]
	for x in SHAFTS:
		exits.append(_cell(H - 1, x) + Vector3(CELL * 0.5, -FLOOR_Y, 0))
	for e in exits:
		_box(self, e + Vector3(0, -0.5, 4.0), Vector3(8.0, 1.0, 10.0), _sand)
	if _door_cells.size() == 2:
		var mid := (_door_cells[0] + _door_cells[1]) * 0.5
		royal_door = _box(_nav, mid + Vector3.UP * 2.0, Vector3(CELL * 2.0, 4.0, 0.8), _floor_mat)
		royal_door.set_meta("royal_door", true)
	_pick_collapse_points()


## Two rubble points on the way out: across the antechamber's neck and the south hall's neck.
func _pick_collapse_points() -> void:
	for r in [ANTE.end.y + 1, SOUTH.position.y - 2]:
		collapse_points.append(_cell(r, 23) + Vector3(CELL * 0.5, 0, 0))


func _environment() -> void:
	super._environment()
	set_indoor(1.0)


## The royal door slides down into the floor (the act opens it).
func open_royal_door(secs := 3.0) -> void:
	if royal_door == null:
		return
	var tw := royal_door.create_tween()
	tw.tween_property(royal_door, "position:y", royal_door.position.y - 4.2, secs).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(func(): (royal_door.get_child(0) as CollisionShape3D).disabled = true)


## Floor-level maze picture for tests: one character per cell.
func ascii() -> String:
	return "\n".join(_map)
