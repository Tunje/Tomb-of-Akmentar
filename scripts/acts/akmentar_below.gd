class_name AkmentarBelow
extends Level
## Act 5's map: Akmentar's second level and the royal tomb, one connected underground map built
## with Level's tile builder. The text map is generated from a room list (no hand-counted rows).
## Stairs at the south come down from the surface; the royal tomb is at the north behind a sealed
## double door. Letters: a-i the nine Level 2 points, 1-5 the royal tomb's points, R the royal door,
## G the guardian's sarcophagus spot, X scarab vents, Z minion spawns, C collapse points (escape).

const W := 40
const H := 34
## [x0, y0, x1, y1] in cells, inclusive.
const ROOMS := {
	"royal": [13, 1, 28, 6], "ante": [17, 8, 24, 10], "hall": [18, 11, 23, 22],
	"w1": [3, 9, 11, 13], "w2": [3, 16, 11, 20], "e1": [30, 9, 37, 13], "e2": [30, 16, 37, 20],
	"south": [14, 23, 27, 26],
	# Corridors.
	"cw1": [12, 11, 17, 11], "cw2": [12, 18, 17, 18], "ce1": [24, 11, 29, 11], "ce2": [24, 18, 29, 18],
}
const MARKS := {
	# Level 2 points of interest, two per side chamber and one in the antechamber.
	Vector2i(5, 10): "a", Vector2i(9, 12): "b", Vector2i(5, 17): "c", Vector2i(9, 19): "d",
	Vector2i(32, 10): "e", Vector2i(36, 12): "f", Vector2i(32, 17): "g", Vector2i(36, 19): "h",
	Vector2i(18, 9): "i",
	# The royal tomb's five, the sarcophagus and the guardian.
	Vector2i(15, 2): "1", Vector2i(26, 2): "2", Vector2i(14, 4): "3", Vector2i(27, 4): "4", Vector2i(16, 6): "5",
	Vector2i(20, 3): "S", Vector2i(20, 4): "G",
	Vector2i(20, 7): "R", Vector2i(21, 7): "R",
	# Scarab vents, minion spawns, collapse points along the escape.
	Vector2i(14, 1): "X", Vector2i(27, 1): "X", Vector2i(18, 15): "X", Vector2i(23, 19): "X",
	Vector2i(4, 13): "Z", Vector2i(37, 13): "Z", Vector2i(4, 20): "Z", Vector2i(37, 20): "Z",
	Vector2i(20, 14): "C", Vector2i(21, 20): "C",
	# Light and pillars.
	Vector2i(19, 13): "P", Vector2i(22, 13): "P", Vector2i(19, 17): "P", Vector2i(22, 17): "P", Vector2i(19, 21): "P", Vector2i(22, 21): "P",
	Vector2i(7, 11): "B", Vector2i(7, 18): "B", Vector2i(34, 11): "B", Vector2i(34, 18): "B",
	Vector2i(17, 25): "B", Vector2i(24, 25): "B", Vector2i(23, 6): "B",
}

var pois := {}  # "a".."i" -> floor position
var royal_pois := {}  # "1".."5" -> floor position
var vents: Array[Vector3] = []
var minion_spawns: Array[Vector3] = []
var collapse_points: Array[Vector3] = []
var guardian_spawn := Vector3.ZERO
var royal_door: StaticBody3D
var stair_top := Vector3.ZERO
var _door_cells: Array[Vector3] = []


func map_rows() -> Array:
	var grid: Array = []
	for y in H:
		grid.append("#".repeat(W).split(""))
	for r in ROOMS.values():
		for y in range(r[1], r[3] + 1):
			for x in range(r[0], r[2] + 1):
				grid[y][x] = "."
	for p in MARKS:
		grid[p.y][p.x] = MARKS[p]
	# Stairs down from the surface at the south, two cells wide, with torches either side.
	for y in range(27, H - 1):
		grid[y][20] = "D"
		grid[y][21] = "D"
	for y in [28, 31]:
		grid[y][19] = "L"
		grid[y][22] = "L"
	# Wall torches beside each room's long sides.
	for name in ["w1", "w2", "e1", "e2", "hall", "royal", "south"]:
		var r: Array = ROOMS[name]
		var mid: int = (r[1] + r[3]) / 2
		for x in [r[0] - 1, r[2] + 1]:
			if grid[mid][x] == "#":
				grid[mid][x] = "L"
	var rows: Array = []
	for row in grid:
		rows.append("".join(row))
	return rows


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
	var south: Array = ROOMS.south
	player_spawn = _cell((south[1] + south[3]) / 2 + 1, 20) + Vector3(CELL * 0.5, 0, 0)
	stair_top = _cell(H - 1, 20) + Vector3(CELL * 0.5, -FLOOR_Y, 0)
	_box(self, stair_top + Vector3(0, -0.5, 4.0), Vector3(8.0, 1.0, 10.0), _sand)  # a patch of surface
	# The sealed royal door across the R cells.
	if _door_cells.size() == 2:
		var mid := (_door_cells[0] + _door_cells[1]) * 0.5
		royal_door = _box(_nav, mid + Vector3.UP * 2.0, Vector3(CELL * 2.0, 4.0, 0.8), _floor_mat)
		royal_door.set_meta("royal_door", true)


func _environment() -> void:
	super._environment()
	set_indoor(1.0)


## The royal door slides down into the floor (the escape and the act open it).
func open_royal_door(secs := 3.0) -> void:
	if royal_door == null:
		return
	var tw := royal_door.create_tween()
	tw.tween_property(royal_door, "position:y", royal_door.position.y - 4.2, secs).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(func(): (royal_door.get_child(0) as CollisionShape3D).disabled = true)
