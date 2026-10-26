class_name AkmentarBelow
extends Level
## Act 5's map: Akmentar's second level and the royal tomb. A real maze (Simon: "dead ends,
## secret passages, bridges over rooms further down"):
## - a seeded recursive-backtracker maze of 2 m corridors with dead ends, plus a few loops;
## - set-piece rooms stamped into it: nine chambers with points of interest, the antechamber and
##   the royal tomb at the far north, the south hall with the stairs up;
## - the Great Pit: a chamber 5 m lower, crossed by a stone bridge at the upper level, with a long
##   ramp down to its floor (one point of interest is down there);
## - secret walls ("?"): hollow-sounding cracked stone that opens once you know the trick (a clue
##   flag), one hiding a chamber, one a shortcut;
## - sleeping mummies in some dead ends, minion spawns in others (the awakening).
## Map letters as Level's, plus: "," pit floor, "=" bridge, "/" ramp, "?" secret wall,
## a-i points of interest, 1-5 royal tomb points, R royal door, G guardian, X vents, Z minions, C collapse.

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
## Point-of-interest rooms (3 x 3 inside), keyed by the letter at their centre.
const POI_ROOMS := {"a": Vector2i(3, 11), "b": Vector2i(41, 11), "c": Vector2i(3, 28), "d": Vector2i(41, 28),
	"f": Vector2i(29, 15), "g": Vector2i(29, 28), "h": Vector2i(34, 21)}
## The point of interest on the pit's floor, and the one in the antechamber.
const PIT_POI := Vector2i(11, 22)
const ANTE_POI := Vector2i(20, 10)
## Secret walls: cell -> the clue flag that reveals the trick. "h" is sealed inside a ring.
const SECRETS := {Vector2i(32, 21): "found_builders", Vector2i(17, 34): "found_symbols"}
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
var stair_top := Vector3.ZERO
var secret_doors: Array[Node] = []
var _door_cells: Array[Vector3] = []
var _pit := {}  # Vector2i -> true for cells at the lower level (pit floor, bridge, ramp foot)
var _rng := RandomNumberGenerator.new()


# ---------------------------------------------------------------- the layout

func map_rows() -> Array:
	_rng.seed = SEED
	var g: Array = []
	for y in H:
		g.append("#".repeat(W).split(""))
	_carve_maze(g)
	_stamp(g, ROYAL, ".")
	_stamp(g, ANTE, ".")
	_stamp(g, SOUTH, ".")
	# A short neck from the antechamber into the maze, and from the south hall.
	for y in range(ANTE.end.y, ANTE.end.y + 2):
		g[y][23] = "."
	for y in range(SOUTH.position.y - 2, SOUTH.position.y):
		g[y][23] = "."
	for k in POI_ROOMS:
		var c: Vector2i = POI_ROOMS[k]
		_stamp(g, Rect2i(c.x - 1, c.y - 1, 3, 3), ".")
		g[c.y][c.x] = k
	_pit_hall(g)
	_secret_room(g)
	# Royal tomb dressing.
	var rx := ROYAL.position.x
	for p in [[rx + 2, 2, "1"], [rx + 13, 2, "2"], [rx + 1, 4, "3"], [rx + 14, 4, "4"], [rx + 3, 6, "5"],
			[rx + 7, 3, "S"], [rx + 7, 4, "G"], [rx + 1, 1, "X"], [rx + 14, 1, "X"], [rx + 10, 6, "B"], [rx + 5, 6, "B"]]:
		g[p[1]][p[0]] = p[2]
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
	_dead_end_spawns(g)
	_torches(g)
	var rows: Array = []
	for row in g:
		rows.append("".join(row))
	return rows


## Recursive backtracker on the odd cells of the middle band (between the antechamber and the
## south hall), then a few extra openings so it isn't a pure tree.
func _carve_maze(g: Array) -> void:
	var y0 := ANTE.end.y + 1
	var y1 := SOUTH.position.y - 2
	if y0 % 2 == 0:
		y0 += 1
	var start := Vector2i(23, y0)
	var stack: Array[Vector2i] = [start]
	var seen := {start: true}
	g[start.y][start.x] = "."
	while not stack.is_empty():
		var cur: Vector2i = stack.back()
		var nexts: Array[Vector2i] = []
		for d in [Vector2i(2, 0), Vector2i(-2, 0), Vector2i(0, 2), Vector2i(0, -2)]:
			var n: Vector2i = cur + d
			if n.x >= 1 and n.x < W - 1 and n.y >= y0 and n.y <= y1 and not seen.has(n):
				nexts.append(n)
		if nexts.is_empty():
			stack.pop_back()
			continue
		var n: Vector2i = nexts[_rng.randi() % nexts.size()]
		seen[n] = true
		g[(cur.y + n.y) / 2][(cur.x + n.x) / 2] = "."
		g[n.y][n.x] = "."
		stack.append(n)
	# Loops: knock through a handful of walls between two corridors.
	var opened := 0
	var tries := 0
	while opened < 9 and tries < 400:
		tries += 1
		var x := _rng.randi_range(2, W - 3)
		var y := _rng.randi_range(y0, y1)
		if g[y][x] != "#":
			continue
		var horiz: bool = g[y][x - 1] == "." and g[y][x + 1] == "." and g[y - 1][x] == "#" and g[y + 1][x] == "#"
		var vert: bool = g[y - 1][x] == "." and g[y + 1][x] == "." and g[y][x - 1] == "#" and g[y][x + 1] == "#"
		if horiz or vert:
			g[y][x] = "."
			opened += 1


func _stamp(g: Array, r: Rect2i, ch: String) -> void:
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			g[y][x] = ch


## The Great Pit: a lower chamber ringed by rock, a bridge across it at the upper level (joining
## the maze on both sides), and a ramp from the east down to its floor.
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
	# Ramp: a walled run from the maze at its east end down to the pit floor.
	_stamp(g, Rect2i(RAMP.position.x, RAMP.position.y - 1, RAMP.size.x, 3), "#")
	for x in range(RAMP.position.x, RAMP.end.x):
		g[RAMP.position.y][x] = "/"
	g[RAMP.position.y][RAMP.end.x] = "."
	g[RAMP.position.y][RAMP.end.x + 1] = "."
	g[PIT_POI.y][PIT_POI.x] = "e"
	g[PIT.position.y + 1][PIT.position.x + 1] = "B"
	g[PIT.end.y - 2][PIT.end.x - 2] = "B"
	g[PIT.position.y + 3][PIT.end.x - 1] = "X"  # scarabs well up from the pit at the awakening


## Room "h" is sealed: a ring of rock with a single secret wall facing the maze.
func _secret_room(g: Array) -> void:
	var c: Vector2i = POI_ROOMS.h
	var ring := Rect2i(c.x - 2, c.y - 2, 5, 5)
	for y in range(ring.position.y, ring.end.y):
		for x in range(ring.position.x, ring.end.x):
			var edge := x == ring.position.x or x == ring.end.x - 1 or y == ring.position.y or y == ring.end.y - 1
			if edge:
				g[y][x] = "#"
	for s in SECRETS:
		g[s.y][s.x] = "?"
	g[c.y][c.x - 3] = "."  # the maze side of the secret wall
	g[34][16] = "."  # the shortcut's far side, west of the south hall
	g[33][16] = "."
	g[32][16] = "."  # and on up into the maze


## Dead ends: sleeping mummies in three, minion spawns (the awakening) in up to six others.
func _dead_end_spawns(g: Array) -> void:
	var ends: Array[Vector2i] = []
	for y in range(1, H - 1):
		for x in range(1, W - 1):
			if g[y][x] != ".":
				continue
			var walls := 0
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				walls += int(g[y + d.y][x + d.x] == "#")
			if walls == 3:
				ends.append(Vector2i(x, y))
	ends.sort_custom(func(a, b): return (a.x * 31 + a.y * 17) % 97 < (b.x * 31 + b.y * 17) % 97)
	for k in mini(ends.size(), 9):
		g[ends[k].y][ends[k].x] = "M" if k < 3 else "Z"


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
	var stair := Rect2i()
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
				stair = Rect2i(c, r, 1, 1) if stair.size == Vector2i.ZERO else stair.expand(Vector2i(c, r))
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
						_box(_nav, at + Vector3.UP * WALL_H * 0.5, Vector3(1.3, WALL_H, 1.3), _stone)
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
	if stair.size != Vector2i.ZERO:
		stair.size += Vector2i.ONE
		_stairs(stair)


## A bridge cell: a narrow stone span at the upper level with low parapets, the pit floor below.
func _bridge_cell(r: int, c: int) -> void:
	var p := _cell(r, c)
	var pit_y := FLOOR_Y - PIT_DROP
	_box(_nav, Vector3(p.x, pit_y - 0.5, p.z), Vector3(CELL, 1.0, CELL), _floor_mat)
	_box(_nav, Vector3(p.x, FLOOR_Y - 0.4, p.z), Vector3(CELL, 0.8, 1.6), _stone)
	for side in [-1.0, 1.0]:
		var rail := _box(_nav, Vector3(p.x, FLOOR_Y + 0.35, p.z + side * 0.72), Vector3(CELL, 0.7, 0.16), _stone)
		rail.set_meta("parapet", true)


## The ramp from the maze (east, upper level) down to the pit floor (west): one sloped slab.
func _ramp() -> void:
	var hi := _cell(RAMP.position.y, RAMP.end.x - 1) + Vector3(CELL * 0.5, 0, 0)
	var lo := _cell(RAMP.position.y, RAMP.position.x) - Vector3(CELL * 0.5, PIT_DROP, 0)
	var run := hi.x - lo.x
	var slope := atan2(PIT_DROP, run)
	var length := sqrt(run * run + PIT_DROP * PIT_DROP)
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(length, 0.4, CELL)
	cs.shape = bs
	body.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = bs.size
	mi.mesh = bm
	mi.material_override = _floor_mat
	body.add_child(mi)
	_nav.add_child(body)
	body.position = (hi + lo) * 0.5 - Vector3(0, 0.2, 0)
	body.rotation.z = slope  # rises toward +X (east)
	# The pit floor continues under the ramp's foot.
	for x in range(RAMP.position.x, RAMP.end.x):
		_pit[Vector2i(x, RAMP.position.y)] = true


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


func _marker(ch: String, p: Vector3, _r: int, _c: int) -> void:
	match ch:
		"a", "b", "c", "d", "e", "f", "g", "h", "i":
			pois[ch] = p
			_plinth(p, 0.9)
		"1", "2", "3", "4", "5":
			royal_pois[ch] = p
			_plinth(p, 1.1)
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


## A waist-high stone block a point of interest sits on (blockout).
func _plinth(p: Vector3, h: float) -> void:
	var b := _box(_nav, p + Vector3.UP * h * 0.5, Vector3(1.1, h, 1.1), _floor_mat)
	_mark_cover(b, Vector3(1.1, h, 1.1))


func _build_surface() -> void:
	# No desert down here: the stairs' top is the way out.
	player_spawn = _cell(SOUTH.position.y + 2, 23) + Vector3(CELL * 0.5, 0, 0)
	stair_top = _cell(H - 1, 23) + Vector3(CELL * 0.5, -FLOOR_Y, 0)
	_box(self, stair_top + Vector3(0, -0.5, 4.0), Vector3(8.0, 1.0, 10.0), _sand)
	if _door_cells.size() == 2:
		var mid := (_door_cells[0] + _door_cells[1]) * 0.5
		royal_door = _box(_nav, mid + Vector3.UP * 2.0, Vector3(CELL * 2.0, 4.0, 0.8), _floor_mat)
		royal_door.set_meta("royal_door", true)
	_pick_collapse_points()


## Two rubble points on the way out (the corridor cells nearest the middle of the run).
func _pick_collapse_points() -> void:
	var cands: Array[Vector3] = []
	for r in range(ANTE.end.y + 2, SOUTH.position.y - 2):
		var p := _cell(r, 23)
		if _ch(r, 23) == "." and _ch(r, 22) in ["#", "L"] and _ch(r, 24) in ["#", "L"]:
			cands.append(p)
	if cands.size() >= 2:
		collapse_points.append(cands[cands.size() / 3])
		collapse_points.append(cands[cands.size() * 2 / 3])


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
