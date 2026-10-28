class_name AkmentarBelow
extends Level
## Act 5's map: the tomb under Akmentar, five levels deep (Simon: "the tomb needs to feel massive,
## huge, and definitely not all on one plain... at least 5 levels with his tomb at the very bottom of
## a massive stair").
## - THE GREAT SHAFT: a 32 m square well through every level, 39 m from the forecourt at the bottom to
##   its roof. The Weeping Stair winds down its walls, one flight per level (a landing on each, a
##   gallery opening off it into that level), to the forecourt at the bottom; the royal door is on
##   the forecourt's north side. Two bridges cross the well (level 1 east-west, level 3 north-south),
##   and every edge onto the drop has a real stone balustrade.
## - Each level: large chambers (7 m ceilings) joined by 4 m passages and two long corridors round
##   the well, so there's always more than one way; narrower side stairs between the levels make the
##   other ways up (Simon: "many large chambers with interconnected paths"); secret walls; blind
##   passages the minions come out of at the awakening (nothing moves down here before then).
## - Three ways out at the top: the main stairs and a long stair up at each side.
## Each level is a character map like Level's (one cell = 2 m), plus:
##   "O" open (the well, or a stairwell's hole), "s" a side stair's ramp, "=" bridge, "?" secret wall,
##   a-i points of interest, 1-5 royal tomb points, R royal door, G guardian, Z minions,
##   "|" drop-slab (a run of them is one slab across the passage), V scarab vent.

const W := 64
const H := 56
const SEED := 1926
const DECKS := 5
const DECK_H := 8.0            # floor to floor
const ROOM_H := 7.0            # floor to ceiling (the floor above is 1 m thick)
const TOP := -8.0              # level 0's floor
## The well (cells), and the Weeping Stair: each level's landing in a corner of it, and the flight
## from it down one wall to the next level's landing (lane: [x0, z0, x1, z1] cell edges, from the
## top end to the bottom end). Level 4's "landing" is the whole well floor: the forecourt.
const SHAFT := Rect2i(24, 18, 16, 16)
const LANDINGS := [Rect2i(37, 18, 3, 3), Rect2i(37, 31, 3, 3), Rect2i(24, 31, 3, 3), Rect2i(24, 18, 3, 3)]
const FLIGHTS := [  # [lane rect, top end, bottom end] in cell coordinates
	[Rect2(38, 21, 2, 10), Vector2(39, 21), Vector2(39, 31)],   # 0 -> 1, down the east wall
	[Rect2(27, 32, 10, 2), Vector2(37, 33), Vector2(27, 33)],   # 1 -> 2, along the south wall
	[Rect2(24, 21, 2, 10), Vector2(25, 31), Vector2(25, 21)],   # 2 -> 3, up the west wall
	[Rect2(27, 18, 10, 2), Vector2(27, 19), Vector2(37, 19)],   # 3 -> 4, along the north wall
]
const BRIDGES := {1: Rect2i(24, 25, 16, 2), 3: Rect2i(31, 18, 2, 16)}
## Side stairs: [upper level, the cells (2 wide, running south), descending toward +z].
const STAIRS := [[0, Rect2i(12, 20, 2, 7)], [0, Rect2i(50, 20, 2, 7)], [1, Rect2i(8, 39, 2, 7)],
	[1, Rect2i(54, 39, 2, 7)], [2, Rect2i(8, 16, 2, 7)], [2, Rect2i(56, 16, 2, 7)], [3, Rect2i(8, 35, 2, 7)],
	[2, BUILDERS_STAIRS[0]], [3, BUILDERS_STAIRS[1]]]
## The Builders' Way (gameplan/akmentar_valley_plan.md, the hidden path): the workmen's own stair
## from the valley's ravine comes in at level 2's east edge (BUILDERS_TOP), behind the Scarab
## Mother's shrine; its east wall is a seal (forced, or opened with clue_builders_seal). From there
## two narrow stairs go down inside the rock, past level 3, to level 4 and a low secret door into
## the forecourt's east side (opened with found_builders_way).
const BUILDERS_TOP := Vector2i(62, 26)
const BUILDERS_STAIRS := [Rect2i(61, 28, 2, 7), Rect2i(61, 37, 2, 7)]
const BUILDERS_PASSAGES := [[2, Rect2i(59, 26, 4, 2)], [3, Rect2i(61, 35, 2, 2)], [4, Rect2i(61, 44, 2, 2)],
	[4, Rect2i(43, 44, 18, 2)], [4, Rect2i(41, 30, 2, 16)]]
const ROYAL := Rect2i(24, 1, 16, 8)
const ANTE := Rect2i(26, 10, 12, 6)
## The chambers per level. A one-letter key is a point of interest at its centre.
const ROOMS := [
	{"south": Rect2i(26, 40, 12, 6), "north0": Rect2i(26, 3, 12, 9), "a": Rect2i(4, 32, 12, 10),
		"westhall": Rect2i(4, 6, 12, 14), "easthall": Rect2i(48, 6, 12, 14), "eastlow": Rect2i(48, 32, 12, 10)},
	{"b": Rect2i(4, 6, 12, 10), "c": Rect2i(48, 6, 12, 10), "west1": Rect2i(4, 27, 12, 12),
		"east1": Rect2i(48, 27, 12, 12), "north1": Rect2i(24, 3, 16, 9), "low": Rect2i(22, 38, 20, 9)},
	{"d": Rect2i(4, 4, 12, 12), "e": Rect2i(48, 4, 12, 12), "west2": Rect2i(4, 24, 12, 12),
		"hall2": Rect2i(4, 46, 56, 8), "east2": Rect2i(44, 35, 8, 9), "north2": Rect2i(24, 3, 16, 10),
		"h": Rect2i(52, 24, 6, 6)},
	{"f": Rect2i(4, 23, 12, 12), "g": Rect2i(48, 23, 12, 12), "north3": Rect2i(22, 5, 20, 8),
		"south3": Rect2i(22, 39, 20, 8)},
	{"royal": ROYAL, "ante": ANTE, "workers": Rect2i(4, 42, 12, 8)},
]
const PASSAGES := [
	[Rect2i(20, 5, 2, 41), Rect2i(42, 5, 2, 41), Rect2i(22, 42, 4, 2), Rect2i(38, 42, 4, 2), Rect2i(22, 6, 4, 2),
		Rect2i(38, 6, 4, 2), Rect2i(16, 10, 4, 2), Rect2i(44, 10, 4, 2), Rect2i(16, 36, 4, 2), Rect2i(44, 36, 4, 2),
		Rect2i(8, 20, 2, 12), Rect2i(54, 20, 2, 12), Rect2i(40, 18, 2, 2)],
	[Rect2i(18, 5, 2, 42), Rect2i(44, 5, 2, 42), Rect2i(16, 9, 2, 2), Rect2i(46, 9, 2, 2), Rect2i(16, 32, 2, 2),
		Rect2i(46, 32, 2, 2), Rect2i(20, 6, 4, 2), Rect2i(40, 6, 4, 2), Rect2i(20, 42, 2, 2), Rect2i(42, 42, 2, 2),
		Rect2i(20, 25, 4, 2), Rect2i(40, 25, 4, 2), Rect2i(38, 34, 2, 4), Rect2i(8, 17, 2, 10)],
	[Rect2i(18, 5, 2, 41), Rect2i(44, 5, 2, 30), Rect2i(16, 8, 2, 2), Rect2i(46, 8, 2, 2), Rect2i(16, 28, 2, 2),
		Rect2i(20, 31, 4, 2), Rect2i(46, 44, 2, 2), Rect2i(20, 6, 4, 2), Rect2i(40, 6, 4, 2), Rect2i(46, 26, 5, 2)],
	[Rect2i(18, 5, 2, 40), Rect2i(44, 5, 2, 40), Rect2i(20, 7, 2, 2), Rect2i(42, 7, 2, 2), Rect2i(20, 41, 2, 2),
		Rect2i(42, 41, 2, 2), Rect2i(16, 28, 2, 2), Rect2i(46, 28, 2, 2), Rect2i(24, 13, 2, 5), Rect2i(31, 13, 2, 5),
		Rect2i(31, 34, 2, 5)],
	[Rect2i(30, 16, 4, 2), Rect2i(16, 44, 4, 2), Rect2i(18, 26, 2, 20), Rect2i(20, 26, 4, 2)],
]
## Blind passages, [level, rect, the minion cell at the far end].
const BLIND := [[0, Rect2i(30, 12, 2, 3), Vector2i(30, 14)], [1, Rect2i(26, 12, 2, 3), Vector2i(26, 14)],
	[2, Rect2i(12, 36, 2, 3), Vector2i(12, 38)], [2, Rect2i(36, 13, 2, 3), Vector2i(36, 15)],
	[3, Rect2i(36, 13, 2, 4), Vector2i(36, 16)], [3, Rect2i(54, 35, 2, 4), Vector2i(54, 38)],
	[4, Rect2i(10, 50, 2, 3), Vector2i(10, 52)]]
## Secret walls: [level, cell, the clue flag that reveals the trick]. The shrine of the Scarab
## Mother ("h", level 2) is sealed; the other is a shortcut from the Builders (b) down to level 1's west hall.
const SECRETS := [[2, Vector2i(51, 26), "found_builders"], [2, Vector2i(51, 27), "found_builders"],
	[1, Vector2i(8, 16), "found_symbols"], [1, Vector2i(9, 16), "found_symbols"],
	[2, Vector2i(58, 26), "clue_builders_seal"], [2, Vector2i(58, 27), "clue_builders_seal"],
	[4, Vector2i(40, 30), "found_builders_way"], [4, Vector2i(40, 31), "found_builders_way"]]
## The point of interest at the Weeping Stair's foot (level 4, the forecourt).
const STAIR_FOOT := Vector2i(35, 22)
const SLABS := 7
const SLAB_H := 3.0  # the drop-slab gateways' opening (the slab hides in the lintel above)
const SCARAB_VENTS := 9
## Map letters -> -f9's site ids (sites/akmentar_below.json, sites/royal_tomb.json).
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
var scarab_vents: Array[Dictionary] = []  # {point, normal, level}
var secret_doors: Array[Node] = []
var amulet: Node3D  # on the royal tomb's plinth "2" until the thieves take it
var sarc_lid: Node3D  # the royal sarcophagus's lid (it slides off at the awakening)
## Named places for the acts (act9's fights, the views): world positions.
var points := {}
signal builders_stair_used(by: Node)    # the Builders' Way's stair up to the valley, from its top
signal builders_seal_forced(at: Vector3)  # the shrine's seal broken without the trick: loud
## Per level: its rows (Array of Array of one-char Strings while laying out, then Strings).
var decks: Array = []
var _door_cells: Array[Vector3] = []
var _rng := RandomNumberGenerator.new()


static func deck_y(k: int) -> float:
	return TOP - k * DECK_H


## Which level a world height is on (the nearest floor at or below it).
static func deck_of(y: float) -> int:
	return clampi(int(floor((TOP - y + 1.5) / DECK_H)), 0, DECKS - 1)


func dch(k: int, r: int, c: int) -> String:
	if k < 0 or k >= DECKS or r < 0 or r >= H or c < 0 or c >= W:
		return "#"
	return (decks[k][r] as String)[c]


func dcell(k: int, r: int, c: int) -> Vector3:
	return Vector3(c * CELL + CELL * 0.5, deck_y(k), r * CELL + CELL * 0.5)


## The floor height under a world point (the level it's on), for spawns and tests.
func floor_at(p: Vector3) -> float:
	return deck_y(deck_of(p.y))


# ---------------------------------------------------------------- the layout

func map_rows() -> Array:
	_rng.seed = SEED
	var g: Array = []
	for k in DECKS:
		var d: Array = []
		for y in H:
			d.append("#".repeat(W).split(""))
		g.append(d)
	for k in DECKS:
		var d: Array = g[k]
		for key in ROOMS[k]:
			_stamp(d, ROOMS[k][key], ".")
		for r: Rect2i in PASSAGES[k]:
			_stamp(d, r, ".")
		for b: Array in BUILDERS_PASSAGES:
			if b[0] == k:
				_stamp(d, b[1], ".")
		# The well: open on every level but the bottom (the forecourt); each level's landing.
		if k < DECKS - 1:
			_stamp(d, SHAFT, "O")
			_stamp(d, LANDINGS[k], ".")
		else:
			_stamp(d, SHAFT, ".")
		if BRIDGES.has(k):
			_stamp(d, BRIDGES[k], "=")
	for b in BLIND:
		_stamp(g[b[0]], b[1], ".")
		var tip: Vector2i = b[2]
		g[b[0]][tip.y][tip.x] = "Z"
	for s in STAIRS:
		_stamp(g[s[0]], s[1], "O")
		_stamp(g[s[0] + 1], s[1], "s")
	_dress_rooms(g)
	_secret_room(g)
	_royal(g[DECKS - 1])
	_exits(g[0])
	_slabs_and_vents(g)
	for k in DECKS:
		_torches(g[k])
	decks = []
	for k in DECKS:
		var rows: Array = []
		for row in g[k]:
			rows.append("".join(row))
		decks.append(rows)
	return decks[0]  # Level's _map: level 0 (the tests' ascii, _ch)


func _stamp(d: Array, r: Rect2i, ch: String) -> void:
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			d[y][x] = ch


## Points of interest at the chambers' centres; columns inset from the big ones' corners, fire
## pillars halfway along their sides; a few minions waiting in corners.
func _dress_rooms(g: Array) -> void:
	for k in DECKS:
		var d: Array = g[k]
		for key: String in ROOMS[k]:
			var r: Rect2i = ROOMS[k][key]
			if key in ["royal", "ante"]:
				continue
			var cx := r.position.x + r.size.x / 2
			var cy := r.position.y + r.size.y / 2
			if key.length() == 1:
				d[cy][cx] = key
			if key == "h":
				continue
			if r.size.x >= 8 and r.size.y >= 6:
				var step := 4 if r.size.x >= 16 else r.size.x - 3
				for x in range(r.position.x + 1, r.end.x - 1, maxi(step, 1)):
					for y in [r.position.y + 1, r.end.y - 2]:
						if d[y][x] == "." and _clear_round(d, x, y):
							d[y][x] = "P"
			for p in [Vector2i(r.position.x, cy), Vector2i(r.end.x - 1, cy)]:
				if d[p.y][p.x] == "." and _walled_beside(d, p):
					d[p.y][p.x] = "B"
			if r.size.x * r.size.y >= 96 and k > 0:
				var corner := Vector2i(r.end.x - 1, r.position.y) if (k + cx) % 2 == 0 else Vector2i(r.position.x, r.end.y - 1)
				if d[corner.y][corner.x] == ".":
					d[corner.y][corner.x] = "Z"
	# Fire bowls round the forecourt (the well's light from below). None on the landings: there one
	# narrowed the gallery doorway beside it and the dead piled up against it.
	var f: Array = g[DECKS - 1]
	for p in [Vector2i(26, 22), Vector2i(37, 29), Vector2i(26, 29), Vector2i(31, 31)]:
		f[p.y][p.x] = "B"
	for p in [Vector2i(28, 24), Vector2i(35, 24), Vector2i(28, 28), Vector2i(35, 28)]:
		f[p.y][p.x] = "P"
	f[STAIR_FOOT.y][STAIR_FOOT.x] = "i"


## A column wants open floor all round it (not a doorway's mouth).
func _clear_round(d: Array, x: int, y: int) -> bool:
	for dy in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			if d[y + dy][x + dx] != ".":
				return false
	return true


## `p` has rock on at least one side (a fire pillar there stands against a wall, not in a doorway).
func _walled_beside(d: Array, p: Vector2i) -> bool:
	for dx in [1, -1]:
		if d[p.y][p.x + dx] == "#":
			return true
	return false


## The shrine is sealed: a ring of rock round it with the secret wall; the other secret seals the
## shortcut from the Builders.
func _secret_room(g: Array) -> void:
	var ring: Rect2i = (ROOMS[2]["h"] as Rect2i).grow(1)
	var d: Array = g[2]
	for y in range(ring.position.y, ring.end.y):
		for x in range(ring.position.x, ring.end.x):
			if x == ring.position.x or x == ring.end.x - 1 or y == ring.position.y or y == ring.end.y - 1:
				d[y][x] = "#"
	for s in SECRETS:
		var c: Vector2i = s[1]
		g[s[0]][c.y][c.x] = "?"


## The royal tomb at the bottom, north of the forecourt: antechamber, door, the tomb itself.
func _royal(d: Array) -> void:
	var rx := ROYAL.position.x
	for p in [[rx + 2, 2, "1"], [rx + 13, 2, "2"], [rx + 1, 4, "3"], [rx + 14, 4, "4"], [rx + 3, 6, "5"],
			[rx + 7, 3, "S"], [rx + 7, 4, "G"], [rx + 1, 1, "X"], [rx + 14, 1, "X"], [rx + 10, 6, "B"], [rx + 5, 6, "B"]]:
		d[p[1]][p[0]] = p[2]
	for p in [[rx + 4, 2], [rx + 11, 2], [rx + 4, 5], [rx + 11, 5]]:
		d[p[1]][p[0]] = "P"
	d[ROYAL.end.y][31] = "R"
	d[ROYAL.end.y][32] = "R"
	d[ANTE.position.y + 1][ANTE.position.x + 1] = "B"
	d[ANTE.position.y + 1][ANTE.end.x - 2] = "B"


## The ways out at the top: the main stairs (4 wide) south of the south hall, and a long stair up
## at each side; torches on the stair walls; the neck slab across the main stairs' way in.
func _exits(d: Array) -> void:
	for y in range(46, H):
		for x in range(30, 34):
			d[y][x] = "D"
	for x in [4, 58]:
		for y in range(42, H):
			d[y][x] = "D"
			d[y][x + 1] = "D"
	for y in [48, 53]:
		for x in [29, 34, 3, 6, 57, 60]:
			if d[y][x] == "#":
				d[y][x] = "L"
	for x in range(30, 34):
		d[45][x] = "|"


## Drop-slabs across 4 m passages (two cells, "|") and scarab vents in passage walls, on every level,
## those on the ways out from the royal tomb first. A slab only goes where a way round remains.
func _slabs_and_vents(g: Array) -> void:
	var pairs: Array = []  # [level, cell, its twin]
	var walls: Array = []  # [level, cell]
	for k in DECKS:
		var d: Array = g[k]
		for y in range(2, H - 3):
			for x in range(2, W - 3):
				if d[y][x] != "." or (k == 0 and y >= 40):  # not on the main stairs' last approach
					continue
				if d[y][x + 1] == "." and _rock(d[y][x - 1]) and _rock(d[y][x + 2]) \
						and _open(d[y - 1][x]) and _open(d[y - 1][x + 1]) and _open(d[y + 1][x]) and _open(d[y + 1][x + 1]):
					pairs.append([k, Vector2i(x, y), Vector2i(x + 1, y)])
				if d[y + 1][x] == "." and _rock(d[y - 1][x]) and _rock(d[y + 2][x]) \
						and _open(d[y][x - 1]) and _open(d[y + 1][x - 1]) and _open(d[y][x + 1]) and _open(d[y + 1][x + 1]):
					pairs.append([k, Vector2i(x, y), Vector2i(x, y + 1)])
				for dv in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					if d[y + dv.y][x + dv.x] == "#":
						walls.append([k, Vector2i(x, y)])
						break
	for i in pairs.size():
		var j := _rng.randi_range(i, pairs.size() - 1)
		var t: Array = pairs[i]
		pairs[i] = pairs[j]
		pairs[j] = t
	var route := _route(g)
	pairs.sort_custom(func(a, b): return route.has(_key(a[0], a[1])) and not route.has(_key(b[0], b[1])))
	var placed: Array = []  # [level, cell]
	var reach := _reach(g)
	var per := {}
	for pr in pairs:
		if placed.size() >= SLABS:
			break
		var k: int = pr[0]
		var c: Vector2i = pr[1]
		if per.get(k, 0) >= 2:
			continue
		var near := false
		for o in placed:
			near = near or (o[0] == k and Vector2(o[1] - c).length() < 8.0)
		if near:
			continue
		for q: Vector2i in [pr[1], pr[2]]:
			g[k][q.y][q.x] = "|"
		var r := _reach(g)
		if r.size() < reach.size() - 2:  # it sealed somewhere off from every exit: not here
			for q: Vector2i in [pr[1], pr[2]]:
				g[k][q.y][q.x] = "."
			continue
		reach = r
		placed.append([k, c])
		per[k] = per.get(k, 0) + 1
	var n := 0
	for i in walls.size():
		var w: Array = walls[(i * 37) % walls.size()]
		var k: int = w[0]
		var c: Vector2i = w[1]
		if n >= SCARAB_VENTS or g[k][c.y][c.x] != "." or k == 0:
			continue
		var near := false
		for o in placed:
			near = near or (o[0] == k and Vector2(o[1] - c).length() < 6.0)
		if near:
			continue
		g[k][c.y][c.x] = "V"
		placed.append([k, c])
		n += 1


static func _rock(ch: String) -> bool:
	return ch in ["#", "L"]


static func _open(ch: String) -> bool:
	return not ch in ["#", "L", "?", "|", "=", "O", "s"]


static func _walk(ch: String) -> bool:
	return not ch in ["#", "L", "?", "|", "O", "s"]


static func _key(k: int, c: Vector2i) -> int:
	return k * 100000 + c.y * 1000 + c.x


## The links between levels: [level, cell] pairs that join (side stairs' ends, the Weeping Stair's
## landings), for the walks below.
func _links() -> Array:
	var out: Array = []
	for s in STAIRS:
		var r: Rect2i = s[1]
		out.append([[s[0], Vector2i(r.position.x, r.position.y - 1)], [s[0] + 1, Vector2i(r.position.x, r.end.y)]])
	for k in DECKS - 1:
		var lo: Vector2i = (LANDINGS[k + 1] as Rect2i).position if k + 1 < DECKS - 1 else Vector2i(SHAFT.end.x - 2, SHAFT.position.y + 1)
		out.append([[k, (LANDINGS[k] as Rect2i).position], [k + 1, lo]])
	return out


func _neighbours(g: Array, k: int, c: Vector2i, links: Dictionary, blocked: Array) -> Array:
	var out: Array = []
	for dv in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var n: Vector2i = c + dv
		if n.x < 0 or n.y < 0 or n.x >= W or n.y >= H:
			continue
		if g[k][n.y][n.x] in blocked:
			continue
		out.append([k, n])
	for l in links.get(_key(k, c), []):
		out.append(l)
	return out


func _link_map() -> Dictionary:
	var m := {}
	for l in _links():
		var a: Array = l[0]
		var b: Array = l[1]
		m[_key(a[0], a[1])] = m.get(_key(a[0], a[1]), []) + [b]
		m[_key(b[0], b[1])] = m.get(_key(b[0], b[1]), []) + [a]
	return m


## Every [level, cell] that can walk to a way out (the top's stairs) with the slabs shut.
func _reach(g: Array) -> Dictionary:
	var links := _link_map()
	var seen := {}
	var queue: Array = []
	for y in H:
		for x in W:
			if g[0][y][x] == "D":
				seen[_key(0, Vector2i(x, y))] = true
				queue.append([0, Vector2i(x, y)])
	while not queue.is_empty():
		var cur: Array = queue.pop_front()
		for n in _neighbours(g, cur[0], cur[1], links, ["#", "L", "?", "|", "O", "s"]):
			var key := _key(n[0], n[1])
			if seen.has(key):
				continue
			seen[key] = true
			queue.append(n)
	return seen


## The cells on the shortest walks from the royal antechamber up to each way out.
func _route(g: Array) -> Dictionary:
	var links := _link_map()
	var from := [DECKS - 1, Vector2i(ANTE.position.x + 4, ANTE.end.y - 1)]
	var parent := {_key(from[0], from[1]): from}
	var queue: Array = [from]
	var goals: Array = []
	while not queue.is_empty():
		var cur: Array = queue.pop_front()
		if cur[0] == 0 and g[0][cur[1].y][cur[1].x] == "D":
			goals.append(cur)
			continue
		for n in _neighbours(g, cur[0], cur[1], links, ["#", "L", "?", "O", "s"]):
			var key := _key(n[0], n[1])
			if parent.has(key):
				continue
			parent[key] = cur
			queue.append(n)
	var on := {}
	for goal: Array in goals:
		var c: Array = goal
		while _key(c[0], c[1]) != _key(from[0], from[1]):
			on[_key(c[0], c[1])] = true
			c = parent[_key(c[0], c[1])]
	return on


## Wall torches every few metres along the corridors (on rock that faces a floor cell).
func _torches(d: Array) -> void:
	for y in range(1, H - 1):
		for x in range(1, W - 1):
			if d[y][x] != "." or (x * 7 + y * 11) % 9 != 0:
				continue
			for dv in [Vector2i(0, -1), Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, 1)]:
				if d[y + dv.y][x + dv.x] == "#":
					d[y + dv.y][x + dv.x] = "L"
					break


# ---------------------------------------------------------------- building

func _build_tomb() -> void:
	for k in DECKS:
		_build_deck(k)
	for f in FLIGHTS.size():
		_flight(f)
	for k in DECKS - 1:
		_landing(k)
	for k in BRIDGES:
		_bridge(k, BRIDGES[k])
	for s in STAIRS:
		_side_stair(s[0], s[1])
	_main_stairs()
	_builders_way()
	_glyph_walls()
	# Every still piece of the five levels as a few meshes per 24 m (2525 meshes were ~5800 draw
	# calls with their shadows); the doors (scripted), the amulet and the lid stay their own.
	if not "--no-merge" in OS.get_cmdline_user_args():  # (tests: the before, to compare)
		var inst := _instance_kit(96.0, [amulet, sarc_lid])
		print("TOMB merged: %d draw calls fewer (%d kit props instanced)" % [RenderBudget.merge_static(self, 24.0, [amulet, sarc_lid]), inst])
	if TombPaint.enabled():
		TombPaint.ceilings(self)   # star ceilings over the halls (after the merge: their own meshes)


## One level: its rock (only what faces something: the inside of the mass is never seen or
## touched), its floors in runs, and what stands on them.
func _build_deck(k: int) -> void:
	var y := deck_y(k)
	for r in H:
		var c := 0
		while c < W:
			var ch := dch(k, r, c)
			if _rock(ch):
				var run := 1
				while c + run < W and _rock(dch(k, r, c + run)):
					run += 1
				_rock_run(k, r, c, run)
				c += run
				continue
			if ch in ["O", "s", "D", "="]:
				c += 1
				continue
			if ch == "?":
				_secret(k, r, c)
				c += 1
				continue
			# A run of plain floor in one slab.
			var run := 1
			while c + run < W and not (dch(k, r, c + run) in ["#", "L", "O", "s", "D", "=", "?"]):
				run += 1
			var a := dcell(k, r, c)
			var b := dcell(k, r, c + run - 1)
			_box(_nav, Vector3((a.x + b.x) * 0.5, y - 0.5, a.z), Vector3(run * CELL, 1.0, CELL), _floor_mat)
			for i in run:
				var cc := c + i
				var at := dcell(k, r, cc)
				match dch(k, r, cc):
					"P":
						_column(at, r, cc)
					"B":
						_brazier(at)
					"S":
						_sarcophagus(at, r, cc)
					".":
						pass
					var m:
						_marker(m, at, r, cc)
			c += run
	# Level 0's roof is the desert (the stairs' cells open to the sky).
	if k == 0:
		for r in H:
			var c := 0
			while c < W:
				if dch(0, r, c) == "D":
					c += 1
					continue
				var run := 1
				while c + run < W and dch(0, r, c + run) != "D":
					run += 1
				var a := dcell(0, r, c)
				var b := dcell(0, r, c + run - 1)
				_box(_nav, Vector3((a.x + b.x) * 0.5, -0.5, a.z), Vector3(run * CELL, 1.0, CELL), _sand)
				c += run


## A run of rock cells on level k: a full-height block where it faces something on this level, else
## just the 1 m slab that is the ceiling of the level below (when there's anything under it).
func _rock_run(k: int, r: int, c: int, run: int) -> void:
	var y := deck_y(k)
	var i := 0
	while i < run:
		var faces := _faces_open(k, r, c + i)
		var j := 1
		while i + j < run and _faces_open(k, r, c + i + j) == faces:
			j += 1
		var a := dcell(k, r, c + i)
		var b := dcell(k, r, c + i + j - 1)
		var mid_x := (a.x + b.x) * 0.5
		if faces:
			_box(_nav, Vector3(mid_x, y - 1.0 + (ROOM_H + 1.0) * 0.5, a.z), Vector3(j * CELL, ROOM_H + 1.0, CELL), _stone)
		else:
			var below := false
			for q in j:
				below = below or (k + 1 < DECKS and not _rock(dch(k + 1, r, c + i + q)))
			if below:
				_box(_nav, Vector3(mid_x, y - 0.5, a.z), Vector3(j * CELL, 1.0, CELL), _stone)
		for q in j:
			if dch(k, r, c + i + q) == "L":
				_torch(k, r, c + i + q)
		i += j


func _faces_open(k: int, r: int, c: int) -> bool:
	for dv in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if not _rock(dch(k, r + dv.y, c + dv.x)):
			return true
	return false


## A wall torch on rock cell (r, c) of level k, on its face toward the floor beside it.
func _torch(k: int, r: int, c: int) -> void:
	for dv in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]:
		if _rock(dch(k, r + dv.y, c + dv.x)) or dch(k, r + dv.y, c + dv.x) == "O":
			continue
		var holder := Node3D.new()
		add_child(holder)
		holder.position = dcell(k, r, c) + Vector3(dv.x, 0, dv.y) * (CELL * 0.5 + 0.15) + Vector3.UP * 2.6
		var sconce := _prop(holder, "dungeon/wall_sconce.glb", holder.global_position, atan2(float(dv.x), float(dv.y)))
		if sconce:
			sconce.position = Vector3(dv.x, 0, dv.y) * -0.12 + Vector3.UP * -0.15
			RenderBudget.quiet(sconce, 30.0)
		_flame(holder, Vector3.UP * 0.4, 2.2, 8.0, false)
		return


# ---------------------------------------------------------------- the Weeping Stair, bridges, side stairs

const RAIL_H := 1.1

## A flight down one wall of the well: a thick sloped stone run (stepped on top) hung on the wall,
## its open side railed.
func _flight(f: int) -> void:
	var lane: Rect2 = FLIGHTS[f][0]
	var top_c: Vector2 = FLIGHTS[f][1]
	var bot_c: Vector2 = FLIGHTS[f][2]
	var hi := Vector3(top_c.x * CELL, deck_y(f), top_c.y * CELL)
	var lo := Vector3(bot_c.x * CELL, deck_y(f + 1), bot_c.y * CELL)
	var along_x := lane.size.x > lane.size.y
	var width := (lane.size.y if along_x else lane.size.x) * CELL
	_steps(hi, lo, width, 1.6)
	# The rail on its open side: the lane's edge away from the well's wall.
	var inner := _inner_edge(lane)
	var a := hi
	var b := lo
	if along_x:
		a.z = inner
		b.z = inner
	else:
		a.x = inner
		b.x = inner
	# Stopped short of the stair's foot: run to its end, a companion caught on the rail's corner
	# there and never got onto the flight (tests: --party-trace).
	var down := b - a
	_balustrade(a + down * (0.4 / down.length()), b - down * (1.4 / down.length()))


## The lane's edge on the well's open side (world metres): the wall is whichever side of the well
## the lane hugs.
func _inner_edge(lane: Rect2) -> float:
	if lane.size.x > lane.size.y:  # along a north or south wall
		return lane.end.y * CELL if lane.position.y == SHAFT.position.y else lane.position.y * CELL
	return lane.end.x * CELL if lane.position.x == SHAFT.position.x else lane.position.x * CELL


## A sloped run from `hi` to `lo` (centres of its top and bottom edges), `width` across, `thick`
## deep below its walking surface; the walking surface is a smooth ramp (people and the navmesh), the
## look is steps.
func _steps(hi: Vector3, lo: Vector3, width: float, thick: float) -> void:
	var flat := Vector3(lo.x - hi.x, 0, lo.z - hi.z)
	var run := flat.length()
	var rise := hi.y - lo.y
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(width, 0.4, sqrt(run * run + rise * rise))
	cs.shape = bs
	body.add_child(cs)
	_nav.add_child(body)
	var bas := Basis.looking_at(lo - hi, Vector3.UP)
	body.global_transform = Transform3D(bas, (hi + lo) * 0.5 - bas.y * 0.2)
	# The stone under it, as a deep slab following the slope.
	var under := MeshInstance3D.new()
	var um := BoxMesh.new()
	um.size = Vector3(width, thick, bs.size.z)
	under.mesh = um
	under.material_override = _stone
	add_child(under)
	under.global_transform = Transform3D(bas, (hi + lo) * 0.5 - bas.y * (thick * 0.5 + 0.05))
	# Steps on top.
	var n := maxi(int(rise / 0.25), 1)
	var dir := flat / run
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var step := BoxMesh.new()
	step.size = Vector3(width, 0.25, run / n + 0.02)
	mm.mesh = step
	mm.instance_count = n
	var face := Basis.looking_at(dir, Vector3.UP)
	for i in n:
		var t := (i + 0.5) / n
		var at := hi + dir * run * t
		at.y = hi.y - rise * (float(i + 1) / n) + 0.125 - 0.02
		mm.set_instance_transform(i, Transform3D(face, at))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = _floor_mat
	add_child(mmi)


## A stone balustrade from `a` to `b` (walking-surface points; it can slope): a plinth, balusters,
## posts every 3 m with caps, a broad top rail at 1.1 m; one solid collider so nobody goes over.
func _balustrade(a: Vector3, b: Vector3) -> void:
	var span := a.distance_to(b)
	if span < 0.3:
		return
	var bas := Basis.looking_at(b - a, Vector3.UP)
	var mid := (a + b) * 0.5
	var wall := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(0.3, RAIL_H, span)
	cs.shape = bs
	wall.add_child(cs)
	wall.set_meta("parapet", true)
	_nav.add_child(wall)
	wall.global_transform = Transform3D(bas.orthonormalized(), mid + Vector3.UP * RAIL_H * 0.5)
	# Upright pieces stand plumb even on a slope: build them in a level frame along the run.
	var flat := Vector3(b.x - a.x, 0, b.z - a.z).normalized()
	var turn := Basis.looking_at(flat, Vector3.UP)
	var parts := {"plinth": [], "rail": [], "post": [], "cap": [], "baluster": []}
	parts.plinth.append(Transform3D(bas, mid + Vector3.UP * 0.1))
	parts.rail.append(Transform3D(bas, mid + Vector3.UP * (RAIL_H - 0.06)))
	var posts := maxi(int(span / 3.0), 1)
	for i in posts + 1:
		var p := a.lerp(b, float(i) / posts)
		parts.post.append(Transform3D(turn, p + Vector3.UP * RAIL_H * 0.5))
		parts.cap.append(Transform3D(turn, p + Vector3.UP * (RAIL_H + 0.08)))
	var n := int(span / 0.32)
	for i in n:
		var p := a.lerp(b, (i + 0.5) / n)
		parts.baluster.append(Transform3D(turn, p + Vector3.UP * (0.2 + (RAIL_H - 0.32) * 0.5)))
	var sizes := {"plinth": Vector3(0.34, 0.2, span), "rail": Vector3(0.32, 0.12, span),
		"post": Vector3(0.3, RAIL_H, 0.3), "cap": Vector3(0.38, 0.16, 0.38), "baluster": Vector3(0.12, RAIL_H - 0.32, 0.12)}
	for key: String in parts:
		var mesh: Mesh
		if key == "baluster":
			var cyl := CylinderMesh.new()
			cyl.top_radius = 0.05
			cyl.bottom_radius = 0.07
			cyl.height = sizes.baluster.y
			cyl.radial_segments = 8
			mesh = cyl
		else:
			var bm := BoxMesh.new()
			bm.size = sizes[key]
			mesh = bm
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = parts[key].size()
		for i in parts[key].size():
			mm.set_instance_transform(i, parts[key][i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = _stone if key != "baluster" else _floor_mat
		add_child(mmi)


## A landing: a thick slab in its corner of the well at its level's height, railed along every
## edge that drops away (not where the flights leave or arrive).
func _landing(k: int) -> void:
	var l: Rect2i = LANDINGS[k]
	var y := deck_y(k)
	var centre := Vector3((l.position.x + l.size.x * 0.5) * CELL, y, (l.position.y + l.size.y * 0.5) * CELL)
	var slab := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(l.size.x * CELL, 1.6, l.size.y * CELL)
	slab.mesh = bm
	slab.material_override = _stone
	add_child(slab)
	slab.global_position = centre - Vector3.UP * 0.8
	var lanes: Array[Rect2] = []
	for i in [k - 1, k]:  # the flight arriving here and the one leaving
		if i >= 0 and i < FLIGHTS.size():
			lanes.append(FLIGHTS[i][0])
	# Each edge, cell by cell: rail where the next cell over is the open well and no flight.
	for side in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var run_from := Vector3.ZERO
		var run_on := false
		var count := l.size.y if side.x != 0 else l.size.x
		for i in count + 1:
			var open := false
			if i < count:
				var cell := Vector2i(l.end.x if side.x > 0 else l.position.x - 1, l.position.y + i) if side.x != 0 \
					else Vector2i(l.position.x + i, l.end.y if side.y > 0 else l.position.y - 1)
				open = SHAFT.has_point(cell)
				for ln in lanes:
					open = open and not ln.has_point(Vector2(cell) + Vector2(0.5, 0.5))
			var edge := Vector3.ZERO
			if side.x != 0:
				edge = Vector3((l.end.x if side.x > 0 else l.position.x) * CELL, y, (l.position.y + i) * CELL)
			else:
				edge = Vector3((l.position.x + i) * CELL, y, (l.end.y if side.y > 0 else l.position.y) * CELL)
			if open and not run_on:
				run_from = edge
				run_on = true
			elif not open and run_on:
				_balustrade(run_from, edge)
				run_on = false


## A bridge across the well: a deck of stone on two deep beams, balustrades both sides.
func _bridge(k: int, r: Rect2i) -> void:
	var y := deck_y(k)
	var along_x := r.size.x > r.size.y
	var x0 := r.position.x * CELL
	var x1 := r.end.x * CELL
	var z0 := r.position.y * CELL
	var z1 := r.end.y * CELL
	var centre := Vector3((x0 + x1) * 0.5, y, (z0 + z1) * 0.5)
	var size := Vector3(x1 - x0, 0.6, z1 - z0)
	var deck := _box(_nav, centre - Vector3.UP * 0.3, size, _floor_mat)
	deck.set_meta("bridge", true)
	var beam := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(size.x * (1.0 if along_x else 0.6), 1.2, size.z * (0.6 if along_x else 1.0))
	beam.mesh = bm
	beam.material_override = _stone
	add_child(beam)
	beam.global_position = centre - Vector3.UP * 1.2
	if along_x:
		_balustrade(Vector3(x0, y, z0 + 0.15), Vector3(x1, y, z0 + 0.15))
		_balustrade(Vector3(x0, y, z1 - 0.15), Vector3(x1, y, z1 - 0.15))
	else:
		_balustrade(Vector3(x0 + 0.15, y, z0), Vector3(x0 + 0.15, y, z1))
		_balustrade(Vector3(x1 - 0.15, y, z0), Vector3(x1 - 0.15, y, z1))


## A side stair between level k and k + 1: down from its north end to its south end.
func _side_stair(k: int, r: Rect2i) -> void:
	var x := (r.position.x + r.size.x * 0.5) * CELL
	_steps(Vector3(x, deck_y(k), r.position.y * CELL), Vector3(x, deck_y(k + 1), r.end.y * CELL), r.size.x * CELL, 1.0)


## The main stairs up to the desert (4 wide), and the side ways out: from level 0 up to the sand.
func _main_stairs() -> void:
	for run in [[30, 4], [4, 2], [58, 2]]:
		var x: float = (run[0] + run[1] * 0.5) * CELL
		var first: int = 46 if run[0] == 30 else 42
		_steps(Vector3(x, 0.0, H * CELL), Vector3(x, deck_y(0), first * CELL), run[1] * CELL, 1.0)


## A secret wall: a ClueDoor (it sinks once its clue flag is set) that sounds hollow when tried,
## with floor behind it for when it opens.
func _secret(k: int, r: int, c: int) -> void:
	var p := dcell(k, r, c)
	_box(_nav, Vector3(p.x, p.y - 0.5, p.z), Vector3(CELL, 1.0, CELL), _floor_mat)
	var flag := "found_builders"
	for s in SECRETS:
		if s[0] == k and s[1] == Vector2i(c, r):
			flag = s[2]
	var texts: Array = BUILDERS_TEXTS.get(flag, ["The stone here sounds hollow. Fine cracks run round a block the size of a door, but it won't move.",
		"You press where the builders marked it. The block grinds back into the dark."])
	var d := ClueDoor.make(_nav, "secret_%d_%d_%d" % [k, c, r], p, Vector3(CELL, ROOM_H, CELL), flag, texts[0], texts[1])
	secret_doors.append(d)
	if flag == "clue_builders_seal":
		d.can_force = true
		d.forced.connect(func() -> void: builders_seal_forced.emit(p))
	var block := _kit_mesh("wall_glyph_b")
	if block == null:
		return
	for dir in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if _rock(dch(k, r + dir.y, c + dir.x)) or dch(k, r + dir.y, c + dir.x) == "?":
			continue
		var out := Vector3(dir.x, 0, dir.y)
		for h in 2:
			var mi := MeshInstance3D.new()
			mi.mesh = block
			d.add_child(mi)
			mi.global_transform = Transform3D(Basis.looking_at(-out, Vector3.UP),
				p + out * (CELL * 0.5 - BLOCK.z * 0.5 + 0.02) + Vector3.UP * h * BLOCK.y)


## (Story placeholders, like the clue texts: Simon will rewrite the story.)
const BUILDERS_TEXTS := {
	"clue_builders_seal": ["Plaster seals this wall, stamped over and over with a scarab. Behind it, the rock sounds hollow.",
		"You press the one scarab that faces east. The plaster cracks along a line, and the seal swings in."],
	"found_builders_way": ["A low block, a hand's width proud of the wall. It doesn't move from this side.",
		"You lift where the workmen's tally said. The low door scrapes open onto the forecourt."],
}


## The Builders' Way: where its stair comes in (points.builders_way, an arrival for the acts) and
## the way back up it to the valley (E there: builders_stair_used; the act does the loading card).
func _builders_way() -> void:
	var top := dcell(2, BUILDERS_TOP.y, BUILDERS_TOP.x)
	points["builders_way"] = top - Vector3(CELL, 0, 0)
	points["builders_door"] = dcell(4, 30, 41)
	var up := Interactable.make(self, top + Vector3.UP, "Climb the builders' stair", "builders_stair", 1.6)
	up.used.connect(func(by: Node) -> void: builders_stair_used.emit(by))


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
		"|":
			# One slab across a passage: built by the run's first cell (west or north).
			var k := deck_of(p.y)
			if dch(k, _r, _c - 1) == "|" or dch(k, _r - 1, _c) == "|":
				return
			var across_x := dch(k, _r, _c + 1) == "|"
			var wide := 1
			while across_x and dch(k, _r, _c + wide) == "|":
				wide += 1
			while not across_x and dch(k, _r + wide, _c) == "|":
				wide += 1
			var at := p + (Vector3(CELL, 0, 0) if across_x else Vector3(0, 0, CELL)) * (wide - 1) * 0.5
			# A low gateway: the slab hangs hidden in a deep stone lintel (3 m up to the 7 m ceiling).
			# A slab as tall as the room had no slot to hide in: it hung down into the corridor, and its
			# top came up through the floor of the level above as a block (Simon's screenshots).
			var lintel_h := ROOM_H - SLAB_H
			var span := Vector3(CELL * wide, lintel_h, 0.9) if across_x else Vector3(0.9, lintel_h, CELL * wide)
			_box(_nav, at + Vector3.UP * (SLAB_H + lintel_h * 0.5), span, _stone)
			var slab := SlabDoor.make(_nav, at, Vector3(CELL * wide, SLAB_H, 0.5), 0.0 if across_x else PI * 0.5, _stone)
			slab_doors.append(slab)
			if k == 0 and _r == 45:
				neck_slab = slab
		"V":
			var k := deck_of(p.y)
			for dv in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				if _rock(dch(k, _r + dv.y, _c + dv.x)):
					var n := Vector3(-dv.x, 0, -dv.y)
					scarab_vents.append({"point": p - n * CELL * 0.5 + Vector3.UP * 0.3, "normal": n, "level": k})
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
const CHUNK := 16  # glyph walls are drawn per 16 x 16 cell patch per level, so the camera culls them
const KIT_INSTANCE_VERTS := 2000   # a kit prop this heavy is instanced, not merged (_instance_kit)
const WALL_SEEN := 70.0  # m: wall carving further off than this isn't drawn (the dark hides it)


## Every rock face that looks onto a floor (or the well) gets carved, painted blocks stacked to the
## ceiling, the frieze along the top. One MultiMesh per design per patch.
func _glyph_walls() -> void:
	var designs := ["wall_glyph_a", "wall_glyph_b", "wall_glyph_c"]
	var meshes: Array[Mesh] = []
	for d in designs:
		meshes.append(_kit_mesh(d))
	var frieze := _kit_mesh("wall_glyph_frieze")
	if meshes.has(null):
		return
	var patches := {}  # key -> [[a], [b], [c], [frieze]]
	for k in DECKS:
		var top_y := deck_y(k) + ROOM_H
		for r in H:
			for c in W:
				var ch := dch(k, r, c)
				if _rock(ch) or ch == "D":
					continue
				for dv in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					if not _rock(dch(k, r + dv.y, c + dv.x)):
						continue
					var out := Vector3(-dv.x, 0, -dv.y)
					var face := dcell(k, r, c) - out * CELL * 0.5
					var turn := Basis.looking_at(-out, Vector3.UP)
					# The well's faces run from the floor slab's underside; rooms' from the floor.
					var base := deck_y(k) - (1.0 if ch == "O" else 0.0)
					var key := "%d_%d_%d" % [k, c / CHUNK, r / CHUNK]
					if not patches.has(key):
						patches[key] = [[], [], [], []]
					var h := 0
					while base + h * BLOCK.y < top_y - 0.5:
						var at := Vector3(face.x, base + h * BLOCK.y, face.z) - out * (BLOCK.z * 0.5 - 0.02)
						var pick := absi(k * 17 + r * 7 + c * 13 + h * 5 + dv.x * 3 + dv.y * 11) % 3
						patches[key][pick].append(Transform3D(turn, at))
						h += 1
					if frieze:
						patches[key][3].append(Transform3D(turn, Vector3(face.x, top_y - FRIEZE.y, face.z) - out * (FRIEZE.z * 0.5 - 0.05)))
	if TombPaint.enabled():   # (the carving painted: gameplan/reference/tomb_look)
		for i in 3:
			meshes[i] = TombPaint.painted(meshes[i], "wall")
		if frieze:
			frieze = TombPaint.painted(frieze, "frieze")
	for key in patches:
		for i in 3:
			_multimesh(meshes[i], patches[key][i])
		if frieze:
			_multimesh(frieze, patches[key][3])


## The kit's heavy props (a wall sconce is ~30k vertices, a pillar ~20k) as one MultiMesh per mesh
## per `cell` m instead of merged: merging copied ~11M vertices into new meshes (4 s of the tomb's
## load, and the memory) for the same few draw calls. What the merge would take, nothing else: not
## under `keep` or a scripted node, not animated, no surface overrides. Returns how many.
func _instance_kit(cell: float, keep: Array) -> int:
	var groups := {}
	var anim_cache := {}
	var to_local := global_transform.affine_inverse()
	for m: MeshInstance3D in find_children("*", "MeshInstance3D", true, false):
		if m.mesh == null or not ".glb::" in m.mesh.resource_path or not m.is_visible_in_tree() or m.get_child_count() > 0:
			continue
		var verts := 0
		var overridden := false
		for i in m.mesh.get_surface_count():
			verts += (m.mesh as ArrayMesh).surface_get_array_len(i) if m.mesh is ArrayMesh else 0
			overridden = overridden or m.get_surface_override_material(i) != null
		if verts < KIT_INSTANCE_VERTS or overridden or m.get_node_or_null(m.skeleton) is Skeleton3D:
			continue
		if (m.mesh as ArrayMesh).get_blend_shape_count() > 0 or RenderBudget._going(m, self) or RenderBudget._kept(m, self, keep) or RenderBudget._animated(m, self, anim_cache):
			continue
		var xf := to_local * m.global_transform
		var c := Vector2i(floori(xf.origin.x / cell), floori(xf.origin.z / cell))
		var key := "%s|%d|%d|%d|%.1f" % [c, m.mesh.get_instance_id(), m.material_override.get_instance_id() if m.material_override else 0,
			m.cast_shadow, m.visibility_range_end]
		if not groups.has(key):
			groups[key] = {"from": m, "xforms": [], "nodes": []}
		(groups[key].xforms as Array).append(xf)
		(groups[key].nodes as Array).append(m)
	var n := 0
	for key: String in groups:
		var g: Dictionary = groups[key]
		var from: MeshInstance3D = g.from
		var xforms: Array = g.xforms
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = from.mesh
		if from.material_override == null and "pillar" in from.mesh.resource_path and TombPaint.enabled():
			mm.mesh = TombPaint.painted(from.mesh, "pillar")   # (painted bands up the columns)
		mm.instance_count = xforms.size()
		for i in xforms.size():
			mm.set_instance_transform(i, xforms[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Kit"
		mmi.multimesh = mm
		mmi.material_override = from.material_override
		mmi.cast_shadow = from.cast_shadow
		mmi.visibility_range_end = from.visibility_range_end
		mmi.visibility_range_end_margin = from.visibility_range_end_margin
		mmi.visibility_range_fade_mode = from.visibility_range_fade_mode
		add_child(mmi)
		n += xforms.size()
	for key: String in groups:
		for m: MeshInstance3D in groups[key].nodes:
			m.get_parent().remove_child(m)
			m.queue_free()
	return n


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
	mmi.visibility_range_end = WALL_SEEN
	mmi.visibility_range_end_margin = 6.0
	mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
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


## A real column (lotus, papyrus or square with carved figures) on a column cell's stone core,
## stretched to the 7 m ceilings.
func _column(at: Vector3, r: int, c: int) -> void:
	var body := _box(_nav, at + Vector3.UP * ROOM_H * 0.5, Vector3(1.2, ROOM_H, 1.2), _stone)
	var kinds := ["pillar_lotus", "pillar_papyrus", "pillar_square_glyph"]
	var prop := _prop(self, KIT + kinds[(r + c) % 3] + ".glb", at, PI * 0.5 * ((r * 3 + c) % 4), Vector3(1.0, ROOM_H / WALL_H, 1.0))
	if prop:
		(body.get_child(1) as MeshInstance3D).visible = false


## Fire pillars: the tall ones in the royal tomb and round the forecourt.
func _brazier(p: Vector3) -> void:
	var c := int(p.x / CELL)
	var r := int(p.z / CELL)
	var deep := deck_of(p.y) == DECKS - 1
	var tall := deep and (ROYAL.has_point(Vector2i(c, r)) or SHAFT.has_point(Vector2i(c, r)))
	var h := 3.0 if tall else 1.8
	var b := _box(_nav, p + Vector3.UP * h * 0.5, Vector3(0.7, h, 0.7), _stone)
	var prop := _prop(self, KIT + ("fire_pillar_tall.glb" if tall else "fire_pillar.glb"), p)
	var reach := 16.0 if tall else 11.0
	if prop == null:
		(b.get_child(1) as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_flame(b, Vector3.UP * (h * 0.5 + 0.35), 3.0, reach, true)
		return
	(b.get_child(1) as MeshInstance3D).visible = false
	for g in prop.find_children("*", "GeometryInstance3D", true, false):
		(g as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_flame(b, Vector3.UP * (h * 0.5 - 0.1), 3.0 if not tall else 4.0, reach, true)


## The royal sarcophagus (image-to-3d: 2.7 x 1.35 x 1.22 m, long along X, its lid a child "lid").
func _sarcophagus(p: Vector3, r: int, c: int) -> void:
	var k := deck_of(p.y)
	var along_z: bool = _rock(dch(k, r - 1, c))
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


## A waist-high stone block a point of interest sits on.
func _plinth(p: Vector3, h: float) -> void:
	var b := _box(_nav, p + Vector3.UP * h * 0.5, Vector3(1.1, h, 1.1), _floor_mat)
	_mark_cover(b, Vector3(1.1, h, 1.1))


func _build_surface() -> void:
	# No desert down here: the stairs' tops are the ways out.
	player_spawn = dcell(0, 43, 31) + Vector3(CELL * 0.5, 0, 0)
	stair_top = Vector3(32 * CELL, 0.0, H * CELL)
	exits = [stair_top, Vector3(5 * CELL, 0.0, H * CELL), Vector3(59 * CELL, 0.0, H * CELL)]
	for e in exits:
		_box(self, e + Vector3(0, -0.5, 5.0), Vector3(10.0, 1.0, 10.0), _sand)
	if _door_cells.size() == 2:
		var mid := (_door_cells[0] + _door_cells[1]) * 0.5
		royal_door = _box(_nav, mid + Vector3.UP * 2.5, Vector3(CELL * 2.0, 5.0, 0.8), _floor_mat)
		royal_door.set_meta("royal_door", true)
	# Rubble on the way out: the gallery off level 2's landing, and level 0's east corridor.
	collapse_points.append(dcell(2, 31, 21) + Vector3(0, 0, CELL * 0.5))
	collapse_points.append(dcell(0, 30, 42) + Vector3(CELL * 0.5, 0, 0))
	points.merge({  # (merged: the Builders' Way's went in with the tomb)
		"surface": stair_top,
		"south": dcell(0, 42, 31),
		"halls": dcell(1, 42, 31),  # level 1's low hall, under the landing
		"forecourt": dcell(4, 26, 31),
		"royal": dcell(4, ANTE.position.y + 2, ANTE.position.x + ANTE.size.x / 2),
		"stair_foot": dcell(4, STAIR_FOOT.y, STAIR_FOOT.x),
	}, true)
	for k in DECKS - 1:
		var l: Rect2i = LANDINGS[k]
		points["landing%d" % k] = dcell(k, l.position.y + 1, l.position.x + 1)


func _environment() -> void:
	super._environment()
	set_indoor(1.0)
	_env.ambient_light_energy = TOMB_FILL
	_env.ambient_light_color = Color(0.36, 0.28, 0.2)
	_env.fog_light_color = Color(0.16, 0.11, 0.07)
	# Thin enough to see down the well to the forecourt's fires, thick enough that it's a gulf.
	_env.fog_density = 0.018


const TOMB_FILL := 0.75


## The royal door slides down into the floor (the act opens it).
func open_royal_door(secs := 3.0) -> void:
	if royal_door == null:
		return
	var tw := royal_door.create_tween()
	tw.tween_property(royal_door, "position:y", royal_door.position.y - 5.2, secs).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(func(): (royal_door.get_child(0) as CollisionShape3D).disabled = true)


## Every level's map for tests: one character per cell, levels one under another.
func ascii() -> String:
	var out: Array[String] = []
	for k in DECKS:
		out.append("-- level %d (floor %.0f m)" % [k, deck_y(k)])
		out.append("\n".join(decks[k]))
	return "\n".join(out)
