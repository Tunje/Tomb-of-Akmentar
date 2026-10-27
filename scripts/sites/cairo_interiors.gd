class_name CairoInteriors
extends Node3D
## Real rooms behind Cairo's doors (Simon: "I don't want all negotiations happening outside in
## corridors"). Each venue's solid blockout box is swapped for a shell carved from it: walls 0.3 m
## thick on the old faces, a doorway where its entrance was, a roof over a ceiling, inner walls
## between rooms. The rooms are furnished (tables and chairs, a bar counter, shelves, rugs, lamps,
## daylight in the windows), lit warm by a few lights that never cast shadows and fade out with
## distance, and their furniture blocks the navmesh. The facades and signs stay -7f's.
##   interiors = CairoInteriors.build(self)   # Cairo._ready, after the buildings, before the bake
## Cost: one merged mesh per building's shell, one per room (vertex colours) and one for its glows;
## 1-3 lights a room; everything past FAR m isn't drawn.
## Chairs: seat_at(p) finds one (Npc sits on it when it's put there); crowd_groups() gives Crowd the
## seated patrons of the bar and café (an indoor group: the street crowd never comes in).
## ROOM_SPOTS: where each talk's spot and host go inside (for SPOTS / NPC_POINTS, cairo.gd).

const WALL := 0.3
const FAR := 45.0
const WARM := Color(1.0, 0.72, 0.42)

## The venues: the building's rect and height (as cairo.gd builds it), its rooms (inside rects,
## floor and ceiling heights, the kind of furnishing) and its doors (on the ground at the facade's
## face, outward normal, width, height).
const VENUES := [
	{"id": "tavern", "rect": Rect2(14, 60, 12, 12), "h": 8.0,
		"rooms": [{"id": "bar", "rect": Rect2(14.3, 60.3, 11.4, 11.4), "floor": 0.0, "ceil": 3.8, "kind": "bar"}],
		"doors": [[Vector3(26, 0, 66), Vector2(1, 0), 2.0, 2.8]]},
	{"id": "hotel", "rect": Rect2(38, 30, 18, 16), "h": 16.0,
		"rooms": [{"id": "lobby", "rect": Rect2(39.5, 37.0, 15.2, 8.7), "floor": 0.0, "ceil": 5.0, "kind": "lobby"}],
		"doors": [[Vector3(47.5, 0, 46), Vector2(0, 1), 2.6, 3.0]]},
	{"id": "museum", "rect": Rect2(80, 0, 24, 26), "h": 13.0,
		"rooms": [{"id": "museum_hall", "rect": Rect2(84.3, 12.3, 15.4, 13.4), "floor": 0.45, "ceil": 7.0, "kind": "hall"},
			{"id": "museum_office", "rect": Rect2(88.3, 6.3, 7.4, 5.7), "floor": 0.45, "ceil": 3.6, "kind": "study"}],
		"doors": [[Vector3(92, 0.45, 26), Vector2(0, 1), 2.6, 3.6], [Vector3(92, 0.45, 12.15), Vector2(0, 1), 1.4, 2.4]]},
	{"id": "outfitter", "rect": Rect2(40, 54, 10, 8), "h": 7.5,
		"rooms": [{"id": "outfitter", "rect": Rect2(40.3, 54.3, 9.4, 7.4), "floor": 0.0, "ceil": 3.6, "kind": "outfitter"}],
		"doors": [[Vector3(45, 0, 54), Vector2(0, -1), 1.8, 2.8]]},
	{"id": "telegraph", "rect": Rect2(64, 4, 8, 10), "h": 7.0,
		"rooms": [{"id": "telegraph", "rect": Rect2(64.3, 4.3, 7.4, 9.4), "floor": 0.0, "ceil": 3.6, "kind": "telegraph"}],
		"doors": [[Vector3(72, 0, 9), Vector2(1, 0), 1.6, 2.6]]},
	{"id": "club", "rect": Rect2(56, 54, 14, 10), "h": 9.0,
		"rooms": [{"id": "club", "rect": Rect2(60.3, 54.3, 9.4, 9.4), "floor": 0.0, "ceil": 4.0, "kind": "club"},
			{"id": "freddie_office", "rect": Rect2(56.3, 54.3, 3.7, 9.4), "floor": 0.0, "ceil": 3.4, "kind": "office"}],
		"doors": [[Vector3(63, 0, 54), Vector2(0, -1), 2.0, 3.0], [Vector3(58.15, 0, 54), Vector2(0, -1), 1.4, 2.4]]},
	{"id": "gunsmith", "rect": Rect2(32, 56, 8, 10), "h": 7.0,
		"rooms": [{"id": "gunsmith", "rect": Rect2(32.3, 56.3, 7.4, 9.4), "floor": 0.0, "ceil": 3.4, "kind": "gunsmith"}],
		"doors": [[Vector3(32, 0, 61), Vector2(-1, 0), 1.6, 2.7]]},
	{"id": "dealer", "rect": Rect2(36, 80, 8, 8), "h": 8.0,
		"rooms": [{"id": "dealer", "rect": Rect2(36.3, 80.3, 7.4, 7.4), "floor": 0.0, "ceil": 3.6, "kind": "dealer"}],
		"doors": [[Vector3(40, 0, 80), Vector2(0, -1), 1.5, 2.6]]},
]
## Where the talks happen inside: SPOTS ids (where you stand to use it) and NPC_POINTS ids (where
## the person is, and the point they face). Seated hosts are put on a chair's point and sit.
const ROOM_SPOTS := {
	"tavern": Vector3(18.6, 0, 64.5),          # at the bar, before McKenna
	"cafe": Vector3(21.0, 0, 67.6),            # (new) the café side: Karim's table
	"hotel": Vector3(47.0, 0, 39.6),           # the reception desk
	"hotel_bed": Vector3(41.4, 0, 44.4),       # the foot of the stairs
	"museum": Vector3(92, 0.45, 14.4),         # the hall, by the office door
	"outfitter": Vector3(45, 0, 58.6),
	"telegraph": Vector3(68.6, 0, 9),
	"club": Vector3(63, 0, 56.6),
	"freddie": Vector3(58.15, 0, 56.0),        # (new) Freddie's office, Act 1
	"gunsmith": Vector3(34.4, 0, 61),
	"dealer": Vector3(40, 0, 83.2),
}
const ROOM_PEOPLE := {
	"mckenna": [Vector3(15.4, 0, 64.5), Vector3(19, 0, 64.5)],      # behind the bar
	"isabelle": [Vector3(17.3, 0, 66.4), Vector3(14, 0, 66.4)],     # on a stool at the bar (sits)
	"idris": [Vector3(21.0, 0, 61.65), Vector3(21, 0, 70)],         # at a table (sits)
	"karim": [Vector3(21.0, 0, 68.95), Vector3(21, 0, 74)],         # the café table (sits)
	"clara": [Vector3(52.6, 0, 41.2), Vector3(47, 0, 41.2)],        # a lobby armchair (sits)
	"archivist": [Vector3(92, 0.45, 7.9), Vector3(92, 0.45, 14)],   # at his desk (sits)
	"eleanor": [Vector3(88.0, 0.45, 18.2), Vector3(86, 0.45, 18.2)],
	"pembroke": [Vector3(96.4, 0.45, 19.6), Vector3(98, 0.45, 19.6)],
	"samira": [Vector3(45.0, 0, 61.0), Vector3(45, 0, 56)],         # behind the counter
	"nabil": [Vector3(65.6, 0, 9.0), Vector3(70, 0, 9)],            # behind the counter
	"hargreaves": [Vector3(67.4, 0, 60.6), Vector3(63, 0, 60.6)],   # a club armchair (sits)
	"zaki": [Vector3(37.4, 0, 61.0), Vector3(33, 0, 61)],
	"yacoub": [Vector3(40.0, 0, 86.0), Vector3(40, 0, 82)],
	"hassan": [Vector3(42.3, 0, 82.2), Vector3(43.5, 0, 82.2)],
}
## Act 1's (not for place_people: she's only there the once): Umm Sayed in Freddie's office.
const UMM_SAYED := [Vector3(57.3, 0, 58.0), Vector3(58.15, 0, 56)]

var level: Node3D
var rooms: Array = []            # {id, rect, floor, ceil, kind}
var seats: Array = []            # {pos, yaw, host}
var _lights: Array[OmniLight3D] = []
var _pane_mat: StandardMaterial3D
var _glow_mat: StandardMaterial3D
var _solid_mat: StandardMaterial3D
var _t := 0.0


## Tests: no interiors at all (the "before" of a frame-rate run).
static var disabled := false


static func build(cairo: Node3D) -> CairoInteriors:
	if disabled:
		return null
	var ci := CairoInteriors.new()
	ci.name = "Interiors"
	ci.level = cairo
	cairo.add_child(ci)
	ci._materials()
	for v: Dictionary in VENUES:
		ci._venue(v)
	print("INTERIORS %d rooms, %d chairs, %d lights" % [ci.rooms.size(), ci.seats.size(), ci._lights.size()])
	return ci


## The chair whose sitting point is at `p` (within 0.45 m), as {pos, yaw}; {} if none.
func seat_at(p: Vector3) -> Dictionary:
	for s: Dictionary in seats:
		var q: Vector3 = s.pos
		if Vector2(q.x - p.x, q.z - p.z).length() < 0.45 and absf(q.y - p.y) < 0.6:
			return s
	return {}


## The room `p` is in (its id), "" outdoors.
func room_at(p: Vector3) -> String:
	for r: Dictionary in rooms:
		if (r.rect as Rect2).has_point(Vector2(p.x, p.z)) and p.y < float(r.ceil):
			return r.id
	return ""


## The patrons of the bar and the café for Crowd: seated, on the chairs nobody else has; an
## indoor group (the street crowd's refuges and strolls never use it).
func crowd_groups() -> Array:
	var bar: Dictionary = {}
	for r: Dictionary in rooms:
		if r.id == "bar":
			bar = r
	if bar.is_empty():
		return []
	var rect: Rect2 = bar.rect
	var free := seats.filter(func(s: Dictionary) -> bool: return not s.host and rect.has_point(Vector2(s.pos.x, s.pos.z)))
	return [{"name": "patrons", "indoor": true, "share": 0.1, "roles": {"sit": 1.0},
		"waypoints": [[20.0, 63.4], [23.6, 66.6], [18.4, 69.6], [24.2, 61.2]],
		"seats": free.map(func(s: Dictionary) -> Array: return [s.pos.x, s.pos.z, s.yaw])}]


# ---------------------------------------------------------------- the shells

func _materials() -> void:
	_solid_mat = StandardMaterial3D.new()
	_solid_mat.vertex_color_use_as_albedo = true
	_solid_mat.vertex_color_is_srgb = true
	_solid_mat.roughness = 0.85
	_glow_mat = StandardMaterial3D.new()
	_glow_mat.vertex_color_use_as_albedo = true
	_glow_mat.vertex_color_is_srgb = true
	_glow_mat.emission_enabled = true
	_glow_mat.emission = WARM
	_glow_mat.emission_energy_multiplier = 1.6
	_pane_mat = StandardMaterial3D.new()
	_pane_mat.albedo_color = Color(0.75, 0.82, 0.9)
	_pane_mat.emission_enabled = true
	_pane_mat.emission = Color(0.9, 0.92, 0.95)
	_pane_mat.emission_energy_multiplier = 1.0
	_pane_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED


func _venue(v: Dictionary) -> void:
	var r: Rect2 = v.rect
	var h := float(v.h)
	var nav: Node = level.get("_nav")
	var centre := Vector3(r.get_center().x, h * 0.5, r.get_center().y)
	var old: StaticBody3D = null
	for c in nav.get_children():
		if c is StaticBody3D and (c as StaticBody3D).position.distance_to(centre) < 0.05:
			old = c
			break
	if old == null:
		push_warning("INTERIORS: no blockout box for %s at %s" % [v.id, centre])
		return
	var mi: MeshInstance3D = old.get_child(1) as MeshInstance3D if old.get_child_count() > 1 else null
	var wall_mat: Material = mi.material_override if mi else null
	nav.remove_child(old)
	old.queue_free()
	_open_doors(v)
	# The shell: a grid on every room edge; cells outside the rooms are solid to the roof, cells in
	# one are solid above its ceiling (and below a raised floor). Then each door is cut through.
	var xs := [r.position.x, r.end.x]
	var zs := [r.position.y, r.end.y]
	for room: Dictionary in v.rooms:
		var rr: Rect2 = room.rect
		for x in [rr.position.x, rr.end.x]:
			if not xs.has(x):
				xs.append(x)
		for z in [rr.position.y, rr.end.y]:
			if not zs.has(z):
				zs.append(z)
		rooms.append({"id": room.id, "rect": rr, "floor": float(room.floor), "ceil": float(room.ceil), "kind": room.kind})
	xs.sort()
	zs.sort()
	var boxes: Array[AABB] = []
	for i in xs.size() - 1:
		for j in zs.size() - 1:
			var x0: float = xs[i]
			var x1: float = xs[i + 1]
			var z0: float = zs[j]
			var z1: float = zs[j + 1]
			var mid := Vector2((x0 + x1) * 0.5, (z0 + z1) * 0.5)
			var inside: Dictionary = {}
			for room: Dictionary in v.rooms:
				if (room.rect as Rect2).has_point(mid):
					inside = room
			if inside.is_empty():
				boxes.append(AABB(Vector3(x0, 0, z0), Vector3(x1 - x0, h, z1 - z0)))
			else:
				var fl := float(inside.floor)
				var ce := float(inside.ceil)
				boxes.append(AABB(Vector3(x0, fl + ce, z0), Vector3(x1 - x0, h - fl - ce, z1 - z0)))
				if fl > 0.0:
					boxes.append(AABB(Vector3(x0, 0, z0), Vector3(x1 - x0, fl, z1 - z0)))
	for d: Array in v.doors:
		var at: Vector3 = d[0]
		var n := Vector3((d[1] as Vector2).x, 0, (d[1] as Vector2).y)
		var along := Vector3(absf(n.z), 0, absf(n.x))
		var w := float(d[2])
		var size := along * w + n.abs() * 1.2 + Vector3.UP * float(d[3])
		var cut := AABB(at - along * w * 0.5 - n.abs() * 0.6, size)
		var next: Array[AABB] = []
		for b in boxes:
			next.append_array(_subtract(b, cut))
		boxes = next
	_shell(boxes, wall_mat, nav)
	for room: Dictionary in v.rooms:
		_furnish(room, v.doors)


## `a` minus `b`: up to six boxes.
static func _subtract(a: AABB, b: AABB) -> Array[AABB]:
	if not a.intersects(b):
		return [a]
	var out: Array[AABB] = []
	var rest := a
	for axis in 3:
		var lo: float = rest.position[axis]
		var hi: float = rest.end[axis]
		var blo: float = b.position[axis]
		var bhi: float = b.end[axis]
		if blo > lo:
			var p := rest
			p.size[axis] = blo - lo
			out.append(p)
		if bhi < hi:
			var q := rest
			q.position[axis] = bhi
			q.size[axis] = hi - bhi
			out.append(q)
		var mlo := maxf(lo, blo)
		var mhi := minf(hi, bhi)
		rest.position[axis] = mlo
		rest.size[axis] = mhi - mlo
	var kept: Array[AABB] = []
	for x in out:
		if x.size.x > 0.01 and x.size.y > 0.01 and x.size.z > 0.01:
			kept.append(x)
	return kept


## The shell's boxes as one mesh in the building's own plaster, and their collision (in the nav
## region, so the bake sees the rooms).
func _shell(boxes: Array[AABB], mat: Material, nav: Node) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	for b in boxes:
		_box_faces(st, b.get_center(), b.size, Basis(), Color.WHITE, true)
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = b.size
		cs.shape = bs
		body.add_child(cs)
		cs.position = b.get_center()
	st.generate_normals()
	var m := MeshInstance3D.new()
	m.name = "Shell"
	m.mesh = st.commit()
	m.material_override = mat
	add_child(m)
	nav.add_child(body)


## The entrance's dark door panel (cairo.gd's _entrance) out of the opening.
func _open_doors(v: Dictionary) -> void:
	var deco: Node = level.get("_deco")
	var dark: Material = level.get("_dark")
	for d: Array in v.doors:
		var at: Vector3 = d[0]
		var n := Vector3((d[1] as Vector2).x, 0, (d[1] as Vector2).y)
		var panel := at + Vector3.UP * float(d[3]) * 0.5 + n * 0.05
		for c in deco.get_children():
			if c is MeshInstance3D and (c as MeshInstance3D).material_override == dark and (c as MeshInstance3D).position.distance_to(panel) < 0.6:
				c.queue_free()


# ---------------------------------------------------------------- furnishing

## A room's kit: boxes and cylinders gathered into one mesh (vertex colours), glows into another;
## solid pieces into the nav region's collision.
class Kit:
	var st := SurfaceTool.new()
	var glow := SurfaceTool.new()
	var solids: Array[AABB] = []
	var any_glow := false

	func _init() -> void:
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		glow.begin(Mesh.PRIMITIVE_TRIANGLES)

	func box(c: Vector3, size: Vector3, col: Color, solid := false, yaw := 0.0) -> void:
		CairoInteriors._box_faces(st, c, size, Basis(Vector3.UP, yaw), col, false)
		if solid:
			var b := Basis(Vector3.UP, yaw)
			var ext := (b * size).abs()
			solids.append(AABB(c - ext * 0.5, ext))

	func cyl(c: Vector3, r: float, h: float, col: Color, solid := false, sides := 10) -> void:
		CairoInteriors._cyl_faces(st, c, r, r, h, col, sides)
		if solid:
			solids.append(AABB(c - Vector3(r, h * 0.5, r), Vector3(r * 2.0, h, r * 2.0)))

	func lit(c: Vector3, size: Vector3, col: Color) -> void:
		any_glow = true
		CairoInteriors._box_faces(glow, c, size, Basis(), col, false)


const WOOD := Color(0.36, 0.22, 0.12)
const DARK_WOOD := Color(0.22, 0.13, 0.08)
const BRASS := Color(0.72, 0.56, 0.26)
const LEATHER := Color(0.36, 0.17, 0.1)
const RUGS := [Color(0.55, 0.14, 0.12), Color(0.18, 0.24, 0.42), Color(0.5, 0.34, 0.12)]
const PLASTER_IN := Color(0.86, 0.78, 0.62)


func _furnish(room: Dictionary, doors: Array) -> void:
	var k := Kit.new()
	var r: Rect2 = room.rect
	var fl := float(room.floor)
	var ce := float(room.ceil)
	var c := Vector3(r.get_center().x, fl, r.get_center().y)
	# Floor boards, a dado and skirting round the walls (not over the doors), ceiling beams.
	k.box(c + Vector3.UP * 0.01, Vector3(r.size.x, 0.02, r.size.y), Color(0.42, 0.3, 0.2))
	for wall in _walls(r, fl, doors):
		var a: Vector3 = wall[0]
		var b: Vector3 = wall[1]
		var nrm: Vector3 = wall[2]
		var mid := (a + b) * 0.5
		var seg_len := a.distance_to(b)
		var size := Vector3(seg_len, 1.0, 0.03) if absf(nrm.z) > 0.5 else Vector3(0.03, 1.0, seg_len)
		k.box(mid + Vector3.UP * 0.5 + nrm * 0.015, size, DARK_WOOD.lerp(PLASTER_IN, 0.25))
		k.box(mid + Vector3.UP * 1.02 + nrm * 0.03, size * Vector3(1, 0.05, 1) + nrm.abs() * 0.03, DARK_WOOD)
	var beams := int(r.size.x / 1.8)
	for i in beams:
		var x := r.position.x + (i + 0.5) * r.size.x / beams
		k.box(Vector3(x, fl + ce - 0.12, c.z), Vector3(0.18, 0.24, r.size.y), DARK_WOOD)
	_windows(r, fl, doors)
	match str(room.kind):
		"bar":
			_bar(k, r)
		"lobby":
			_lobby(k, r)
		"hall":
			_hall(k, r, fl)
		"study":
			_study(k, r, fl)
		"outfitter":
			_outfitter(k, r)
		"telegraph":
			_telegraph(k, r)
		"club":
			_club(k, r)
		"office":
			_office(k, r)
		"gunsmith":
			_gunsmith(k, r)
		"dealer":
			_dealer(k, r)
	_commit(k, str(room.id))


## Each wall of `r` as [a, b, inward normal] segments, with the doors' gaps left out.
func _walls(r: Rect2, fl: float, doors: Array) -> Array:
	var out := []
	var edges := [
		[Vector3(r.position.x, fl, r.position.y), Vector3(r.end.x, fl, r.position.y), Vector3(0, 0, 1)],
		[Vector3(r.position.x, fl, r.end.y), Vector3(r.end.x, fl, r.end.y), Vector3(0, 0, -1)],
		[Vector3(r.position.x, fl, r.position.y), Vector3(r.position.x, fl, r.end.y), Vector3(1, 0, 0)],
		[Vector3(r.end.x, fl, r.position.y), Vector3(r.end.x, fl, r.end.y), Vector3(-1, 0, 0)],
	]
	for e: Array in edges:
		var a: Vector3 = e[0]
		var b: Vector3 = e[1]
		var nrm: Vector3 = e[2]
		var along := (b - a).normalized()
		var cuts: Array = []
		for d: Array in doors:
			var at: Vector3 = d[0]
			# A door on this wall: within the wall's thickness (plus a bit) of its line.
			var off := (at - a) - along * (at - a).dot(along)
			if Vector2(off.x, off.z).length() < WALL + 0.35:
				var t := (at - a).dot(along)
				cuts.append([t - float(d[2]) * 0.5, t + float(d[2]) * 0.5])
		cuts.sort_custom(func(x: Array, y: Array) -> bool: return float(x[0]) < float(y[0]))
		var s := 0.0
		var total := a.distance_to(b)
		for cut: Array in cuts:
			var c0 := clampf(float(cut[0]), 0.0, total)
			var c1 := clampf(float(cut[1]), 0.0, total)
			if c1 <= c0:
				continue  # a door on this line, but past this wall's ends
			if c0 > s + 0.05:
				out.append([a + along * s, a + along * c0, nrm])
			s = maxf(s, c1)
		if total > s + 0.05:
			out.append([a + along * s, b, nrm])
	return out


## Daylight in the windows on the walls that are the building's faces (not over a door).
func _windows(r: Rect2, fl: float, doors: Array) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 0
	for wall in _walls(r, fl, doors):
		var a: Vector3 = wall[0]
		var b: Vector3 = wall[1]
		var nrm: Vector3 = wall[2]
		if not _on_face(a, b):
			continue
		var seg_len := a.distance_to(b)
		var count := int((seg_len - 0.6) / 2.6)
		for i in count:
			var p := a.lerp(b, (i + 0.5) / count) + Vector3.UP * 1.75 + nrm * 0.02
			var size := Vector3(0.9, 1.3, 0.02) if absf(nrm.z) > 0.5 else Vector3(0.02, 1.3, 0.9)
			_box_faces(st, p, size, Basis(), Color.WHITE, false)
			n += 1
	if n == 0:
		return
	st.generate_normals()
	var m := MeshInstance3D.new()
	m.mesh = st.commit()
	m.material_override = _pane_mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	m.visibility_range_end = FAR
	add_child(m)


## A wall segment that lies on its building's outside face (within the wall's thickness).
func _on_face(a: Vector3, b: Vector3) -> bool:
	var mid := (a + b) * 0.5
	for v: Dictionary in VENUES:
		var r: Rect2 = v.rect
		if r.grow(0.5).has_point(Vector2(mid.x, mid.z)):
			return absf(mid.x - r.position.x) < WALL + 0.05 or absf(mid.x - r.end.x) < WALL + 0.05 \
				or absf(mid.z - r.position.y) < WALL + 0.05 or absf(mid.z - r.end.y) < WALL + 0.05
	return false


func _commit(k: Kit, id: String) -> void:
	k.st.generate_normals()
	var m := MeshInstance3D.new()
	m.name = "Room_" + id
	m.mesh = k.st.commit()
	m.material_override = _solid_mat
	m.visibility_range_end = FAR
	m.visibility_range_end_margin = 4.0
	m.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	add_child(m)
	if k.any_glow:
		k.glow.generate_normals()
		var g := MeshInstance3D.new()
		g.mesh = k.glow.commit()
		g.material_override = _glow_mat
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		g.visibility_range_end = FAR
		add_child(g)
	if not k.solids.is_empty():
		var body := StaticBody3D.new()
		body.name = "Furniture_" + id
		body.collision_layer = 1
		body.collision_mask = 0
		for b in k.solids:
			var cs := CollisionShape3D.new()
			var bs := BoxShape3D.new()
			bs.size = b.size
			cs.shape = bs
			body.add_child(cs)
			cs.position = b.get_center()
		(level.get("_nav") as Node).add_child(body)


## A lamp: its glow, and a light that never casts a shadow and fades out past 22 m.
func _lamp(k: Kit, at: Vector3, range_m := 6.0, energy := 1.2, hanging := true) -> void:
	if hanging:
		k.box(at + Vector3.UP * 0.5, Vector3(0.02, 1.0, 0.02), DARK_WOOD)
	k.lit(at, Vector3(0.28, 0.3, 0.28), WARM)
	var l := OmniLight3D.new()
	l.light_color = WARM
	l.omni_range = range_m
	l.omni_attenuation = 1.2
	l.light_energy = energy
	l.shadow_enabled = false
	l.distance_fade_enabled = true
	l.distance_fade_begin = 22.0
	l.distance_fade_length = 8.0
	add_child(l)
	l.position = at + Vector3.DOWN * 0.2
	_lights.append(l)


## A chair: its sitting point `at` (the floor where the sitter stands before sitting), facing
## `yaw`; the seat 0.12 m behind it, 0.45 up (like Crowd's stools). `host`: kept for an Npc.
func _chair(k: Kit, at: Vector3, yaw: float, host := false, col := WOOD, arm := false) -> void:
	var b := Basis(Vector3.UP, yaw)
	var seat := at + b * Vector3(0, 0, 0.12)
	k.box(seat + Vector3.UP * 0.42, Vector3(0.46, 0.06, 0.46), col, true, yaw)
	k.box(seat + b * Vector3(0, 0, 0.21) + Vector3.UP * 0.75, Vector3(0.46, 0.6, 0.05), col, false, yaw)
	for sx in [-0.2, 0.2]:
		for sz in [-0.2, 0.2]:
			k.box(seat + b * Vector3(sx, 0, sz) + Vector3.UP * 0.2, Vector3(0.04, 0.4, 0.04), DARK_WOOD, false, yaw)
	if arm:
		for sx in [-0.26, 0.26]:
			k.box(seat + b * Vector3(sx, 0, 0) + Vector3.UP * 0.6, Vector3(0.08, 0.3, 0.46), col, false, yaw)
	seats.append({"pos": at, "yaw": yaw, "host": host})


## A bar stool (sitting point `at`, facing `yaw`): taller, at the counter.
func _stool(k: Kit, at: Vector3, yaw: float, host := false) -> void:
	var seat := at + Basis(Vector3.UP, yaw) * Vector3(0, 0, 0.12)
	k.cyl(seat + Vector3.UP * 0.225, 0.19, 0.45, WOOD, true)
	seats.append({"pos": at, "yaw": yaw, "host": host})


func _table(k: Kit, at: Vector3, r := 0.45, h := 0.75, cloth := Color(0, 0, 0, 0)) -> void:
	k.cyl(at + Vector3.UP * (h - 0.02), r, 0.04, cloth if cloth.a > 0.0 else WOOD, true, 12)
	k.cyl(at + Vector3.UP * (h * 0.5), 0.06, h, DARK_WOOD)


func _rug(k: Kit, at: Vector3, size: Vector2, i: int) -> void:
	var col: Color = RUGS[i % RUGS.size()]
	k.box(at + Vector3.UP * 0.025, Vector3(size.x, 0.01, size.y), col)
	k.box(at + Vector3.UP * 0.027, Vector3(size.x - 0.3, 0.01, size.y - 0.3), col.lerp(Color(0.85, 0.75, 0.5), 0.3))


func _shelves(k: Kit, toward: Vector3, a: Vector3, length: float, along_x: bool, h := 2.2, stuff := Color(0.5, 0.4, 0.3)) -> void:
	# Against a wall, open to the room (`toward`, its middle): a back, five boards, goods on them.
	var dir := Vector3(1, 0, 0) if along_x else Vector3(0, 0, 1)
	var side := Vector3(0, 0, 1) if along_x else Vector3(1, 0, 0)
	var out := side * signf((toward - a).dot(side))
	var size := Vector3(length, h, 0.35) if along_x else Vector3(0.35, h, length)
	k.solids.append(AABB(a - Vector3(size.x, 0, size.z) * 0.5, size))
	var thin := (Vector3(length, h, 0.04) if along_x else Vector3(0.04, h, length))
	k.box(a - out * 0.155 + Vector3.UP * h * 0.5, thin, DARK_WOOD)
	for e in [-1.0, 1.0]:
		k.box(a + dir * e * (length * 0.5 - 0.02) + Vector3.UP * h * 0.5, Vector3(0.04, h, 0.35) if along_x else Vector3(0.35, h, 0.04), DARK_WOOD)
	for shelf in 5:
		var y := 0.06 + shelf * (h - 0.1) / 4.0
		k.box(a + Vector3.UP * y, Vector3(length, 0.03, 0.34) if along_x else Vector3(0.34, 0.03, length), WOOD)
		if shelf == 4:
			continue
		for i in int((length - 0.2) / 0.3):
			var p := a + dir * (-length * 0.5 + 0.25 + i * 0.3) + out * 0.02 + Vector3.UP * (y + 0.13)
			var tone := stuff.lerp(Color(0.85, 0.75, 0.55), fmod(i * 0.37 + shelf * 0.21, 1.0) * 0.6)
			k.box(p, Vector3(0.2, 0.22 - fmod(i * 0.13, 0.1), 0.2), tone)


func _mid(r: Rect2) -> Vector3:
	return Vector3(r.get_center().x, 0, r.get_center().y)


## The Crocodile Bar: the bar counter along the back wall, bottles behind, stools; tables in the
## middle; the café side to the south (low tables, a hookah, the coffee counter, rugs).
func _bar(k: Kit, r: Rect2) -> void:
	var x0 := r.position.x
	k.box(Vector3(x0 + 2.4, 0.52, 64.5), Vector3(0.6, 1.04, 6.2), WOOD, true)
	k.box(Vector3(x0 + 2.4, 1.06, 64.5), Vector3(0.75, 0.05, 6.4), DARK_WOOD)
	_shelves(k, _mid(r), Vector3(x0 + 0.2, 0, 64.5), 6.0, false, 2.4, Color(0.25, 0.4, 0.2))
	for z in [62.2, 63.6, 65.0, 66.4]:
		_stool(k, Vector3(x0 + 3.0, 0, z), PI * 0.5, is_equal_approx(z, 66.4))
	_lamp(k, Vector3(x0 + 2.4, 2.9, 63.0), 5.0, 1.0)
	_lamp(k, Vector3(x0 + 2.4, 2.9, 66.2), 5.0, 1.0)
	# The bar's tables.
	for t: Array in [[Vector3(21.0, 0, 62.4), true], [Vector3(23.8, 0, 64.4), false]]:
		var at: Vector3 = t[0]
		_table(k, at)
		_chair(k, at + Vector3(0, 0, -0.75), PI, t[1])     # its north side, facing the table
		_chair(k, at + Vector3(0, 0, 0.75), 0.0)
		_chair(k, at + Vector3(0.75, 0, 0), PI * 0.5)
	_lamp(k, Vector3(22.4, 3.0, 63.4), 6.5, 1.3)
	_rug(k, Vector3(22.2, 0, 63.4), Vector2(4.2, 3.0), 0)
	# The café side: brass-topped low tables, a hookah, the coffee counter with its pots.
	for t: Array in [[Vector3(21.0, 0, 69.7), true], [Vector3(24.0, 0, 69.9), false], [Vector3(18.2, 0, 69.6), false]]:
		var at: Vector3 = t[0]
		_table(k, at, 0.42, 0.62, BRASS)
		_chair(k, at + Vector3(0, 0, -0.75), PI, t[1])
		_chair(k, at + Vector3(0.75, 0, 0), PI * 0.5)
	k.cyl(Vector3(22.6, 0.3, 70.9), 0.12, 0.6, Color(0.3, 0.45, 0.5))
	k.cyl(Vector3(22.6, 0.75, 70.9), 0.04, 0.3, BRASS)
	k.box(Vector3(16.6, 0.5, 71.3), Vector3(3.2, 1.0, 0.6), WOOD, true)
	for i in 4:
		k.cyl(Vector3(15.6 + i * 0.6, 1.12, 71.3), 0.1, 0.22, BRASS)
	_rug(k, Vector3(21.2, 0, 69.8), Vector2(6.4, 2.8), 2)
	_lamp(k, Vector3(19.6, 2.9, 69.8), 6.0, 1.1)
	_lamp(k, Vector3(23.6, 2.9, 69.8), 6.0, 1.1)


## The Khedivial's lobby: the reception desk and the pigeonholes for keys, sofas and armchairs,
## potted palms, a rug, the stairs up to the rooms.
func _lobby(k: Kit, r: Rect2) -> void:
	k.box(Vector3(47.0, 0.55, 38.3), Vector3(5.0, 1.1, 0.7), WOOD, true)
	k.box(Vector3(47.0, 1.12, 38.3), Vector3(5.2, 0.05, 0.85), Color(0.55, 0.45, 0.35))
	for i in 10:
		for j in 3:
			k.box(Vector3(45.0 + i * 0.42, 1.8 + j * 0.38, 37.12), Vector3(0.36, 0.32, 0.18), DARK_WOOD.lerp(BRASS, 0.15 if (i + j) % 3 == 0 else 0.0))
	k.lit(Vector3(48.9, 1.26, 38.25), Vector3(0.16, 0.2, 0.16), WARM)     # the desk lamp
	# The stairs up the west wall, to a landing under the ceiling.
	for s in 10:
		k.box(Vector3(40.4, 0.15 + s * 0.3, 44.6 - s * 0.32), Vector3(1.4, 0.3, 0.34), WOOD.lerp(Color(0.6, 0.15, 0.12), 0.4), true)
	k.box(Vector3(41.15, 1.6, 42.0), Vector3(0.06, 1.0, 3.6), DARK_WOOD)
	# Seating: a sofa, armchairs round low tables.
	k.box(Vector3(43.6, 0.25, 41.4), Vector3(0.8, 0.5, 2.2), LEATHER, true)
	k.box(Vector3(43.25, 0.65, 41.4), Vector3(0.18, 0.5, 2.2), LEATHER)
	_table(k, Vector3(45.0, 0, 41.4), 0.4, 0.5)
	_chair(k, Vector3(52.6, 0, 41.2), PI * 0.5, true, LEATHER, true)
	_chair(k, Vector3(52.6, 0, 42.6), PI * 0.5, false, LEATHER, true)
	_table(k, Vector3(51.4, 0, 41.9), 0.4, 0.5)
	_chair(k, Vector3(50.2, 0, 41.9), -PI * 0.5, false, LEATHER, true)
	for p in [Vector3(40.4, 0, 38.0), Vector3(54.0, 0, 38.0), Vector3(45.0, 0, 45.0), Vector3(50.0, 0, 45.0)]:
		k.cyl(p + Vector3.UP * 0.3, 0.28, 0.6, Color(0.55, 0.32, 0.2), true)
		k.box(p + Vector3.UP * 1.3, Vector3(0.9, 1.0, 0.9), Color(0.2, 0.36, 0.16))
	_rug(k, Vector3(47.5, 0, 42.0), Vector2(6.0, 4.0), 1)
	for x in [43.0, 47.5, 52.0]:
		_lamp(k, Vector3(x, 4.2, 41.6), 7.0, 1.2)


## The museum's front hall: columns, cases, a seated king, a sarcophagus on its plinth.
func _hall(k: Kit, r: Rect2, fl: float) -> void:
	var y := fl
	for x in [87.5, 96.5]:
		for z in [16.0, 22.0]:
			k.cyl(Vector3(x, y + 3.5, z), 0.4, 7.0, Color(0.78, 0.7, 0.58), true, 12)
	for c: Array in [[Vector3(88.0, y, 17.0)], [Vector3(96.4, y, 18.4)], [Vector3(88.0, y, 21.5)], [Vector3(96.4, y, 22.6)]]:
		var at: Vector3 = c[0]
		k.box(at + Vector3.UP * 0.45, Vector3(1.4, 0.9, 0.8), DARK_WOOD, true)
		k.lit(at + Vector3.UP * 1.25, Vector3(1.3, 0.7, 0.7), Color(0.4, 0.42, 0.38))   # lit glass
		k.box(at + Vector3.UP * 1.1, Vector3(0.3, 0.3, 0.2), Color(0.65, 0.5, 0.2))
	# The king on his throne, against the back wall (clear of the office door).
	k.box(Vector3(86.6, y + 0.5, 13.4), Vector3(2.0, 1.0, 1.4), Color(0.6, 0.55, 0.45), true)
	k.box(Vector3(86.6, y + 1.7, 13.3), Vector3(0.9, 1.6, 0.8), Color(0.45, 0.42, 0.36))
	k.box(Vector3(86.6, y + 2.8, 13.3), Vector3(0.5, 0.6, 0.5), Color(0.45, 0.42, 0.36))
	# The sarcophagus.
	k.box(Vector3(92, y + 0.35, 19.5), Vector3(1.4, 0.7, 3.0), Color(0.6, 0.55, 0.45), true)
	k.box(Vector3(92, y + 0.95, 19.5), Vector3(0.8, 0.5, 2.3), Color(0.55, 0.42, 0.2))
	_rug(k, Vector3(92, y, 23.5), Vector2(3.0, 3.2), 0)
	for p in [Vector3(89, y + 5.2, 17), Vector3(95, y + 5.2, 17), Vector3(92, y + 5.2, 22.5)]:
		_lamp(k, p, 10.0, 1.4)


## The archivist's office: his desk and chair, books to the ceiling, the drawers, a green lamp.
func _study(k: Kit, r: Rect2, fl: float) -> void:
	var y := fl
	k.box(Vector3(92, y + 0.38, 9.2), Vector3(1.8, 0.76, 0.85), WOOD, true)
	_chair(k, Vector3(92, y, 7.9), PI, true, LEATHER, true)
	_chair(k, Vector3(92.7, y, 10.5), 0.0)
	_shelves(k, _mid(r), Vector3(89.0, y, 9.2), 5.0, false, 3.2)
	_shelves(k, _mid(r), Vector3(95.0, y, 8.8), 4.0, false, 3.2)
	k.box(Vector3(93.6, y + 0.6, 6.7), Vector3(0.8, 1.2, 0.6), Color(0.3, 0.3, 0.28), true)
	for i in 6:
		k.box(Vector3(91.6 + i * 0.12, y + 0.8, 9.1 + fmod(i * 0.31, 0.3)), Vector3(0.3, 0.02, 0.22), Color(0.9, 0.86, 0.74))
	k.lit(Vector3(92.6, y + 0.95, 9.0), Vector3(0.24, 0.12, 0.24), Color(0.4, 0.8, 0.5))
	_rug(k, Vector3(92, y, 9.6), Vector2(3.0, 2.4), 1)
	_lamp(k, Vector3(92, y + 3.1, 9.4), 5.5, 1.2)


## The outfitters: the counter across the shop, shelves of tins behind, crates and rolled tents,
## coils of rope, saddles, hurricane lamps hung up.
func _outfitter(k: Kit, r: Rect2) -> void:
	k.box(Vector3(45, 0.5, 60.1), Vector3(6.0, 1.0, 0.7), WOOD, true)
	_shelves(k, _mid(r), Vector3(45, 0, 61.5), 8.6, true, 2.6, Color(0.55, 0.45, 0.3))
	for p in [Vector3(41.3, 0, 55.4), Vector3(41.3, 0, 56.4), Vector3(48.7, 0, 55.6)]:
		k.box(p + Vector3.UP * 0.35, Vector3(0.8, 0.7, 0.7), WOOD.lerp(Color(0.6, 0.5, 0.35), 0.4), true)
	for i in 3:
		k.box(Vector3(48.6, 0.18 + i * 0.34, 57.6), Vector3(0.34, 0.32, 1.6), Color(0.7, 0.64, 0.5), i == 0)   # rolled tents
	k.cyl(Vector3(41.4, 0.1, 58.4), 0.4, 0.2, Color(0.6, 0.5, 0.3))
	k.box(Vector3(48.6, 0.55, 59.2), Vector3(0.5, 0.5, 0.8), LEATHER, true)
	for x in [42.5, 47.5]:
		_lamp(k, Vector3(x, 2.9, 57.5), 5.5, 1.1)
	_rug(k, Vector3(45, 0, 57.0), Vector2(3.0, 2.2), 2)


## The telegraph office: the counter with its grille, the clerk's key and sounder, a bench for
## those waiting, the clock.
func _telegraph(k: Kit, r: Rect2) -> void:
	k.box(Vector3(67.0, 0.55, 9.0), Vector3(0.7, 1.1, 7.0), WOOD, true)
	for i in 8:
		k.box(Vector3(67.0, 1.7, 5.9 + i * 0.9), Vector3(0.04, 1.1, 0.04), BRASS)
	k.box(Vector3(67.0, 2.25, 9.0), Vector3(0.1, 0.06, 7.0), BRASS)
	k.box(Vector3(65.3, 0.4, 7.0), Vector3(0.9, 0.8, 1.6), DARK_WOOD, true)
	k.box(Vector3(65.3, 0.85, 7.0), Vector3(0.25, 0.1, 0.18), BRASS)
	k.box(Vector3(68.8, 0.25, 4.8), Vector3(3.0, 0.5, 0.45), WOOD, true)   # the bench, by the south wall
	k.cyl(Vector3(64.5, 2.6, 9.0), 0.3, 0.06, Color(0.92, 0.9, 0.82))
	_shelves(k, _mid(r), Vector3(64.5, 0, 11.6), 2.0, false, 2.0, Color(0.85, 0.82, 0.72))
	_lamp(k, Vector3(67.5, 3.0, 9.0), 6.0, 1.2)


## The officers' club: leather armchairs round low tables, the billiard table, bookcases, the
## drinks cabinet, a long rug.
func _club(k: Kit, r: Rect2) -> void:
	k.box(Vector3(64.6, 0.4, 61.0), Vector3(2.6, 0.8, 1.4), DARK_WOOD, true)
	k.box(Vector3(64.6, 0.82, 61.0), Vector3(2.3, 0.04, 1.1), Color(0.12, 0.35, 0.2))
	_table(k, Vector3(66.6, 0, 57.4), 0.4, 0.5)
	_chair(k, Vector3(67.4, 0, 60.6), PI * 0.5, true, LEATHER, true)
	_chair(k, Vector3(67.6, 0, 57.4), PI * 0.5, false, LEATHER, true)
	_chair(k, Vector3(66.6, 0, 56.4), PI, false, LEATHER, true)
	_shelves(k, _mid(r), Vector3(69.4, 0, 59.0), 6.0, false, 2.8)
	_shelves(k, _mid(r), Vector3(64.6, 0, 63.5), 5.0, true, 2.8)
	k.box(Vector3(61.0, 0.55, 62.6), Vector3(1.0, 1.1, 0.6), DARK_WOOD, true)
	for i in 4:
		k.cyl(Vector3(60.7 + i * 0.2, 1.25, 62.6), 0.05, 0.28, Color(0.4, 0.25, 0.1))
	_rug(k, Vector3(64.8, 0, 58.6), Vector2(6.0, 4.4), 0)
	for x in [62.4, 66.6]:
		_lamp(k, Vector3(x, 3.2, 59.0), 6.5, 1.2)


## Freddie's office: his desk under papers, the chair pushed back, the filing cabinet left open,
## shelves of ledgers, papers on the floor.
func _office(k: Kit, r: Rect2) -> void:
	k.box(Vector3(58.15, 0.38, 60.4), Vector3(1.6, 0.76, 0.8), WOOD, true)
	_chair(k, Vector3(58.15, 0, 61.7), 0.0, false, LEATHER, true)
	k.box(Vector3(56.75, 0.65, 62.9), Vector3(0.6, 1.3, 0.6), Color(0.32, 0.32, 0.3), true)
	k.box(Vector3(56.75, 0.9, 62.45), Vector3(0.54, 0.3, 0.5), Color(0.38, 0.38, 0.36))
	_shelves(k, _mid(r), Vector3(59.75, 0, 59.0), 4.0, false, 2.6, Color(0.4, 0.3, 0.2))
	for i in 9:
		k.box(Vector3(57.0 + fmod(i * 0.73, 2.4), 0.03, 57.0 + fmod(i * 1.37, 5.0)), Vector3(0.3, 0.01, 0.22), Color(0.9, 0.86, 0.74), false, i * 0.7)
	k.lit(Vector3(58.7, 0.9, 60.2), Vector3(0.2, 0.12, 0.2), WARM)
	_lamp(k, Vector3(58.15, 2.9, 58.6), 5.0, 1.1)


## The gunsmith: the counter, rifles racked on the back wall, the workbench and its vice.
func _gunsmith(k: Kit, r: Rect2) -> void:
	k.box(Vector3(35.6, 0.5, 61.0), Vector3(0.7, 1.0, 5.6), WOOD, true)
	k.box(Vector3(39.5, 1.4, 61.0), Vector3(0.2, 1.6, 6.0), DARK_WOOD, true)
	for i in 12:
		k.box(Vector3(39.3, 1.45, 58.4 + i * 0.47), Vector3(0.06, 1.3, 0.08), Color(0.3, 0.2, 0.12))
	k.box(Vector3(37.6, 0.45, 65.2), Vector3(2.2, 0.9, 0.7), WOOD, true)
	k.box(Vector3(38.2, 1.0, 65.2), Vector3(0.2, 0.2, 0.2), Color(0.25, 0.25, 0.25))
	_lamp(k, Vector3(36.0, 2.8, 61.0), 6.0, 1.1)


## The antiquities dealer: shelves of jars and figures, the counter, a rug, a lamp.
func _dealer(k: Kit, r: Rect2) -> void:
	k.box(Vector3(40.0, 0.5, 85.2), Vector3(3.4, 1.0, 0.7), WOOD, true)
	_shelves(k, _mid(r), Vector3(40.0, 0, 87.5), 7.0, true, 2.6, Color(0.6, 0.45, 0.25))
	_shelves(k, _mid(r), Vector3(36.5, 0, 83.5), 5.0, false, 2.6, Color(0.5, 0.5, 0.42))
	for p in [Vector3(43.0, 0, 81.4), Vector3(43.2, 0, 82.9)]:
		k.cyl(p + Vector3.UP * 0.35, 0.25, 0.7, Color(0.62, 0.42, 0.25), true)
	_rug(k, Vector3(40.0, 0, 83.0), Vector2(3.0, 2.4), 1)
	_lamp(k, Vector3(40.0, 2.9, 83.6), 6.0, 1.1)


# ---------------------------------------------------------------- daylight

## The windows bright by day, dim at dusk (the city's day_time).
func _process(delta: float) -> void:
	_t -= delta
	if _t > 0.0:
		return
	_t = 1.0
	var dt: float = float(level.get("day_time")) if "day_time" in level else 0.5
	var gloom: float = float(level.get("gloom")) if "gloom" in level else 0.0
	var day := (1.0 - smoothstep(0.8, 0.98, dt)) * (1.0 - 0.7 * gloom)
	_pane_mat.emission_energy_multiplier = lerpf(0.05, 1.1, day)
	_pane_mat.emission = Color(0.9, 0.92, 0.95).lerp(Color(0.95, 0.6, 0.35), smoothstep(0.7, 0.95, dt))


# ---------------------------------------------------------------- geometry

## A box's six faces into `st` (`world_uv`: planar UVs at a plaster's scale, for the shells).
static func _box_faces(st: SurfaceTool, c: Vector3, size: Vector3, b: Basis, col: Color, world_uv: bool) -> void:
	var h := size * 0.5
	var faces := [
		[Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0)], [Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 0)],
		[Vector3(0, 1, 0), Vector3(1, 0, 0), Vector3(0, 0, -1)], [Vector3(0, -1, 0), Vector3(1, 0, 0), Vector3(0, 0, 1)],
		[Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, 1, 0)], [Vector3(0, 0, -1), Vector3(-1, 0, 0), Vector3(0, 1, 0)],
	]
	for f: Array in faces:
		var n: Vector3 = f[0]
		var u: Vector3 = f[1]
		var v: Vector3 = f[2]
		var ctr := n * h
		var du := u * h
		var dv := v * h
		var corners := [ctr - du - dv, ctr + du - dv, ctr + du + dv, ctr - du + dv]
		var pts: Array[Vector3] = []
		for p: Vector3 in corners:
			pts.append(c + b * p)
		for idx in [0, 2, 1, 0, 3, 2]:
			st.set_color(col)
			if world_uv:
				var wp: Vector3 = pts[idx]
				var uu := wp.dot(u) if absf(n.y) < 0.5 else wp.x
				var vv := wp.y if absf(n.y) < 0.5 else wp.z
				st.set_uv(Vector2(uu, -vv) * 0.18)
			st.add_vertex(pts[idx])


static func _cyl_faces(st: SurfaceTool, c: Vector3, r_top: float, r_bot: float, h: float, col: Color, sides: int) -> void:
	for i in sides:
		var a0 := TAU * i / sides
		var a1 := TAU * (i + 1) / sides
		var p0 := Vector3(cos(a0), 0, sin(a0))
		var p1 := Vector3(cos(a1), 0, sin(a1))
		var b0 := c + p0 * r_bot - Vector3.UP * h * 0.5
		var b1 := c + p1 * r_bot - Vector3.UP * h * 0.5
		var t0 := c + p0 * r_top + Vector3.UP * h * 0.5
		var t1 := c + p1 * r_top + Vector3.UP * h * 0.5
		var top := c + Vector3.UP * h * 0.5
		var bot := c - Vector3.UP * h * 0.5
		for v in [b0, b1, t1, b0, t1, t0, top, t0, t1, bot, b1, b0]:
			st.set_color(col)
			st.add_vertex(v)
