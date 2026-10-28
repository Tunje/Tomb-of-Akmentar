class_name RoadV2
extends TownV2
## Stage 1 of gameplan/route_stops_plan.md: the desert road at about 3x, 1 km from the start to the
## caravan town's south gate, with its stops, as blockout. No act uses it yet: DesertRoute stays the
## game's until Simon approves (tests/road_v2_test walks and times it). North is -z; the convoy
## starts in the south (z 1210) and drives north to the gate (z 220); TownV2 stands at the north
## end where it is on its own map, and the night camp (DesertCamp) is off the road east, between the
## canyon and the town. The stops, south to north:
##   the start: a well with a milestone, where the convoy forms up      START_Z
##   the dead camel and a milestone                                     CAMEL_Z
##   the ruined watch-tower on a rise east of the road (Youssef's)      TOWER_Z
##   the sandstorm blows up just past it                                STORM_Z
##   the wadi canyon: cliffs both sides, a shelf on each for the ambush CANYON (ambush at AMBUSH_Z)
##   the night camp, 70 m east by a track                               CAMP_Z
##   the fork: a track west to the temple, by a toppled statue          FORK_Z
##   the town gate                                                      TownV2.SPOTS.south_gate
## The navmesh is baked in tiles (TILE m, one geometry parse, each tile cut clean at its edges so
## they join): one bake of the whole 460 x 1300 m at 0.25 m cells is too much at once.
## Placeholders (blockout until models come): the canyon's cliffs and shelves, the rise and the
## tower's broken walls, the well, the milestones, the dead camel (boxes), the boulders and the
## buttes on the skyline, the banks round the map's sides and the dune mounds at their feet, the
## temple track; the toppled statue is statue_horus.glb laid down. The town's people are crowd
## stand-ins (crowd/town_v2.json, the camels big HorseRigs), the vultures AmbientLife's birds.

const START_Z := 1210.0
const CAMEL_Z := 1080.0
const TOWER_Z := 930.0
const STORM_Z := 860.0
const CANYON := Vector2(560, 640)    # z, north end to south end
const AMBUSH_Z := 600.0
const CAMP_Z := 480.0
const FORK_Z := 430.0
const GATE_Z := 220.0
const ROAD_W := 6.0
const SHELF := Vector2(4.0, 9.5)     # the canyon's shelves: from this far off the road's middle to this
const SHELF_H := 4.5
const CLIFF_H := 11.0
const TILE := 64.0
const GROUND := Rect2(-80, -40, 460, 1300)

## Where the bandits lie in wait on the shelves (as DesertRoute.bandit_posts).
var bandit_posts: Array[Vector3] = []
var camp: DesertCamp
var bake_ms := 0
var tiles := 0
var _road_mat: StandardMaterial3D


static func road_x(z: float) -> float:
	return 180.0 + 25.0 * sin((z - GATE_Z) / 140.0) + 8.0 * sin((z - GATE_Z) / 53.0)


static func road_point(z: float) -> Vector3:
	return Vector3(road_x(z), 0.0, z)


## The road's length from z0 south to z1 north, along its line.
static func road_length(z0: float, z1: float) -> float:
	var l := 0.0
	var z := z0
	while z > z1:
		l += road_point(z).distance_to(road_point(maxf(z - 2.0, z1)))
		z -= 2.0
	return l


func _ready() -> void:
	_rng.seed = 1924
	_make_materials()
	_town_materials()
	_road_mat = _floor_mat.duplicate() as StandardMaterial3D
	_road_mat.albedo_texture = _noise_tex(Color(0.5, 0.4, 0.27), Color(0.64, 0.52, 0.36), 0.04, false)
	_nav = NavigationRegion3D.new()
	_nav.navigation_mesh = Level.nav_mesh()
	add_child(_nav)
	_deco = Node3D.new()
	_deco.name = "Deco"
	add_child(_deco)
	_box(_nav, Vector3(GROUND.get_center().x, -0.5, GROUND.get_center().y), Vector3(GROUND.size.x, 1.0, GROUND.size.y), _sand)
	_town()
	_road()
	_start()
	_dead_camel()
	_tower()
	_canyon()
	_fork()
	camp = DesertCamp.build(self, road_point(CAMP_Z) + Vector3(70, 0, 0), -PI * 0.5)
	_track(road_point(CAMP_Z) + Vector3(ROAD_W * 0.5, 0, 0), camp.spots.gate)
	_scatter()
	_edges()
	spots.start = road_point(START_Z - 10.0)
	spots.storm = road_point(STORM_Z)
	spots.ambush = road_point(AMBUSH_Z)
	spots.camp = camp.anchor
	spots.camp_lookout = camp.spots.lookout
	player_spawn = spots.start
	_environment()
	_sun.rotation = Vector3(deg_to_rad(-30), deg_to_rad(-120), 0)
	_env.fog_density = 0.0024           # the haze: the far road and the buttes fade into it
	_env.fog_aerial_perspective = 0.35
	_env.fog_light_color = Color(0.8, 0.66, 0.48)
	_bake_tiles()
	RenderBudget.quiet_minor(_deco)
	RenderBudget.quiet_minor(_nav)
	if not "--no-merge" in OS.get_cmdline_user_args():
		# The long views: the dressing and the solids' meshes merged by area (the solids' in 64 m
		# cells: 1 km of road in 24 m ones was still ~500 draw calls looking down it).
		print("ROAD v2 merged: deco %d, solids %d draw calls fewer" % [RenderBudget.merge_static(_deco),
			RenderBudget.merge_static(_nav, 64.0)])
	if not "--no-crowd" in OS.get_cmdline_user_args():
		Crowd.populate(self, "town_v2")
		# Vultures over the canyon.
		AmbientLife.add(self, {"birds": {"count": 5, "center": [road_x(AMBUSH_Z), AMBUSH_Z], "radius": 35, "height": 38, "span": 2.8},
			"critters": 6})


## The navmesh in tiles from one parse of the solids under _nav.
func _bake_tiles() -> void:
	var t0 := Time.get_ticks_msec()
	# From -f9's NavCache when the geometry's the same (the signature covers every shape under _nav).
	var cached := NavCache.tiles(_nav, "road_v2", "%s_%s" % [TILE, GROUND])
	if not cached.is_empty():
		for n: String in cached:
			_tile(n, cached[n])
	else:
		var made := {}
		var src := NavigationMeshSourceGeometryData3D.new()
		NavigationServer3D.parse_source_geometry_data(_nav.navigation_mesh, src, _nav)
		var b := src.get_bounds()
		var border := 2.0
		var x := GROUND.position.x
		while x < GROUND.end.x:
			var z := GROUND.position.y
			while z < GROUND.end.y:
				var nm := Level.nav_mesh()
				nm.border_size = border
				# (Clipped to the ground: the banks' top edges past it would bake as islands.)
				var size := Vector2(minf(TILE, GROUND.end.x - x), minf(TILE, GROUND.end.y - z))
				nm.filter_baking_aabb = AABB(Vector3(x - border, b.position.y - 1.0, z - border),
					Vector3(size.x + border * 2.0, b.size.y + 2.0, size.y + border * 2.0))
				NavigationServer3D.bake_from_source_geometry_data(nm, src)
				if nm.get_polygon_count() > 0:
					var n := "Tile_%d_%d" % [int(x), int(z)]
					_tile(n, nm)
					made[n] = nm
				z += TILE
			x += TILE
		NavCache.save_tiles("road_v2", made)
	_nav.enabled = false  # (it only holds the solids; the tiles are the navmesh)
	bake_ms = Time.get_ticks_msec() - t0
	print("ROAD v2 navmesh: %d tiles in %d ms%s" % [tiles, bake_ms, " (cached)" if not cached.is_empty() else ""])


func _tile(n: String, nm: NavigationMesh) -> void:
	var r := NavigationRegion3D.new()
	r.name = n
	r.navigation_mesh = nm
	add_child(r)
	tiles += 1


# ---------------------------------------------------------------- the road

## A packed-earth band from outside the gate to past the start, milestones every 100 m.
func _road() -> void:
	var z := GATE_Z
	while z < GROUND.end.y - 10.0:
		_band(road_point(z), road_point(z + 8.0), ROAD_W, _road_mat)
		z += 8.0
	var k := 1
	while GATE_Z + k * 100.0 < START_Z:
		_milestone(road_point(GATE_Z + k * 100.0) + Vector3(ROAD_W * 0.5 + 1.0, 0, 0))
		k += 1


func _band(a: Vector3, b: Vector3, w: float, mat: Material) -> void:
	var bm := BoxMesh.new()
	bm.size = Vector3(w, 0.04, a.distance_to(b) + 0.4)
	var seg := _mesh(bm, (a + b) * 0.5 + Vector3.UP * 0.02, mat)
	seg.look_at_from_position(seg.position, b + Vector3.UP * 0.02, Vector3.UP)
	seg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## A side track (narrower, in 8 m pieces) from `a` to `b`.
func _track(a: Vector3, b: Vector3) -> void:
	var n := maxi(int(a.distance_to(b) / 8.0), 1)
	for i in n:
		_band(a.lerp(b, float(i) / n), a.lerp(b, float(i + 1) / n), 3.5, _road_mat)


func _milestone(p: Vector3) -> void:
	_box(_nav, p + Vector3.UP * 0.45, Vector3(0.45, 0.9, 0.3), _stone)


## The start: a well beside the road, a trough, a milestone; the convoy forms up here.
func _start() -> void:
	var p := road_point(START_Z)
	_cylinder(_nav, p + Vector3(-9.0, 0.45, 0), 1.4, 0.9)
	_box(_nav, p + Vector3(-9.0, 0.3, 3.5), Vector3(4.0, 0.6, 0.9), _stone)
	_milestone(p + Vector3(ROAD_W * 0.5 + 1.0, 0, -3.0))
	_palm(p + Vector3(-14.0, 0, -2.0), 7.0)
	_palm(p + Vector3(-12.5, 0, 3.0), 6.0)
	spots.start_well = p + Vector3(-6.5, 0, 0)


## A dead camel by the road (a hump, a neck, legs), and a milestone.
func _dead_camel() -> void:
	var p := road_point(CAMEL_Z) + Vector3(-7.0, 0, 0)
	var hide := StandardMaterial3D.new()
	hide.albedo_color = Color(0.55, 0.42, 0.28)
	var body := _box(_nav, p + Vector3(0, 0.45, 0), Vector3(1.0, 0.9, 2.2), hide)
	body.rotation.y = 0.4
	var neck := BoxMesh.new()
	neck.size = Vector3(0.3, 0.3, 1.6)
	_mesh(neck, p + Vector3(0.5, 0.2, -1.8), hide, Vector3(0, 0.9, 0))
	for k in 4:
		var leg := BoxMesh.new()
		leg.size = Vector3(0.15, 0.15, 1.1)
		_mesh(leg, p + Vector3(0.9, 0.12, -0.6 + k * 0.45), hide, Vector3(0, 1.3 + k * 0.15, 0))
	_milestone(road_point(CAMEL_Z + 6.0) + Vector3(ROAD_W * 0.5 + 1.0, 0, 0))
	spots.dead_camel = road_point(CAMEL_Z) + Vector3(-3.6, 0, 0)


## The watch-tower: a rise east of the road with a ramp up its west face, the tower's broken walls
## on top round a room with a doorway (Youssef's lookout down the road).
func _tower() -> void:
	var c := road_point(TOWER_Z) + Vector3(34.0, 0, 0)
	var h := 2.6
	var top := 22.0
	_box(_nav, c + Vector3(0, h * 0.5, 0), Vector3(top, h, top), _stone)
	var run := 11.0
	var ramp := _box(_nav, Vector3(c.x - top * 0.5 - run * 0.5, h * 0.5 - 0.2, c.z), Vector3(Vector2(run, h).length(), 0.4, 4.0), _stone)
	ramp.rotation.z = atan2(h, run)
	var y := h
	var inner := 7.0
	var t := 1.0
	var walls := [
		[Vector3(0, 0, -inner * 0.5 - t * 0.5), Vector3(inner + t * 2.0, 7.5, t)],     # north, the tall corner
		[Vector3(inner * 0.5 + t * 0.5, 0, 0), Vector3(t, 4.5, inner)],                  # east
		[Vector3(0, 0, inner * 0.5 + t * 0.5), Vector3(inner + t * 2.0, 2.2, t)],       # south, broken low
		[Vector3(-inner * 0.5 - t * 0.5, 0, -2.4), Vector3(t, 5.5, 2.2)],                # west either side of the doorway
		[Vector3(-inner * 0.5 - t * 0.5, 0, 2.4), Vector3(t, 3.0, 2.2)],
	]
	for w: Array in walls:
		var s: Vector3 = w[1]
		_box(_nav, c + w[0] + Vector3(0, y + s.y * 0.5, 0), s, _mud[2])
	for k in 5:  # fallen blocks
		var b := _box(_nav, c + Vector3(_rng.randf_range(-9, 9), y + 0.35, _rng.randf_range(6, 9.5)), Vector3(1.2, 0.7, 0.9), _mud[2])
		b.rotation.y = _rng.randf() * PI
		_mark_cover(b, Vector3(1.2, 0.7, 0.9))
	spots.tower = c + Vector3(0, y, 0)
	spots.tower_view = c + Vector3(-top * 0.5 + 2.0, y, -6.0)


## The wadi canyon: cliffs either side of the road, each with a shelf 4.5 m up on the road side
## (rocks along its lip for cover), reached by a ramp off its north end: the bandits come from
## the town. Boulders in the bed.
func _canyon() -> void:
	var z := CANYON.x
	var step := 10.0
	while z < CANYON.y:
		var mid := (z + step * 0.5)
		var x := road_x(mid)
		for s: float in [-1.0, 1.0]:
			var shelf_w := SHELF.y - SHELF.x
			_box(_nav, Vector3(x + s * (SHELF.x + shelf_w * 0.5), SHELF_H * 0.5, mid), Vector3(shelf_w, SHELF_H, step + 0.2), _stone)
			# The cliff runs out to the map's side: the canyon is the only way through.
			var inner := x + s * SHELF.y
			var outer := GROUND.position.x if s < 0.0 else GROUND.end.x
			_box(_nav, Vector3((inner + outer) * 0.5, CLIFF_H * 0.5, mid), Vector3(absf(outer - inner), CLIFF_H, step + 0.2), _stone)
			if int(z) % 20 == 0:
				var rock := _box(_nav, Vector3(x + s * (SHELF.x + 0.9), SHELF_H + 0.55, mid), Vector3(1.4, 1.1, 2.2), _stone)
				_mark_cover(rock, Vector3(1.4, 1.1, 2.2))
				bandit_posts.append(Vector3(x + s * (SHELF.x + 2.6), SHELF_H, mid))
		z += step
	# The ramps up to the shelves, off their north ends.
	var run := 20.0
	for s: float in [-1.0, 1.0]:
		var x := road_x(CANYON.x) + s * (SHELF.x + SHELF.y) * 0.5
		var ramp := _box(_nav, Vector3(x, SHELF_H * 0.5 - 0.2, CANYON.x - run * 0.5), Vector3(SHELF.y - SHELF.x, 0.4, Vector2(run, SHELF_H).length()), _stone)
		ramp.rotation.x = -atan2(SHELF_H, run)
	for k in 6:
		var bz := _rng.randf_range(CANYON.x + 5.0, CANYON.y - 5.0)
		var side := -1.0 if k % 2 == 0 else 1.0
		var b := _box(_nav, road_point(bz) + Vector3(side * _rng.randf_range(3.6, 3.9), 0.5, 0), Vector3(0.9, 1.0, 1.6), _stone)
		_mark_cover(b, Vector3(0.9, 1.0, 1.6))
	spots.shelf_west = bandit_posts[0]
	spots.shelf_east = bandit_posts[1]


## The fork: a track west toward the temple (act3_temple), a toppled statue half in the sand.
func _fork() -> void:
	var p := road_point(FORK_Z)
	var end := Vector3(GROUND.position.x + 10.0, 0, FORK_Z - 70.0)
	_track(p + Vector3(-ROAD_W * 0.5, 0, 0), end)
	var at := p + Vector3(-9.0, -0.5, 6.0)
	var statue := _prop(_deco, "statue_horus.glb", at, 0.7)
	if statue:
		statue.rotation = Vector3(-PI * 0.5 + 0.12, 0.7, 0.1)
	var lying := Vector3(-sin(0.7), 0, -cos(0.7))  # which way it fell (its head)
	var body := _box(_nav, at + lying * 1.6 + Vector3(0, 0.6, 0), Vector3(1.6, 1.4, 3.6), null)
	body.rotation.y = 0.7
	(body.get_child(1) as MeshInstance3D).visible = false
	_box(_nav, p + Vector3(-13.0, 0.3, 9.5), Vector3(2.2, 0.6, 2.2), _stone)   # its plinth, tipped
	spots.fork = p + Vector3(-5.0, 0, -3.0)
	spots.temple_track = end


## Boulders off the road and buttes on the skyline.
func _scatter() -> void:
	for k in 60:
		var z := _rng.randf_range(GATE_Z + 40.0, GROUND.end.y - 20.0)
		if z > CANYON.x - 25.0 and z < CANYON.y + 5.0:
			continue
		var side := -1.0 if _rng.randf() < 0.5 else 1.0
		var p := road_point(z) + Vector3(side * _rng.randf_range(9.0, 70.0), 0, 0)
		if p.distance_to(camp.anchor) < 35.0 or absf(z - TOWER_Z) < 20.0 or absf(z - FORK_Z) < 25.0:
			continue
		var s := Vector3(_rng.randf_range(1.0, 3.5), _rng.randf_range(0.8, 2.2), _rng.randf_range(1.0, 3.0))
		var b := _box(_nav, p + Vector3(0, s.y * 0.5 - 0.05, 0), s, _stone)
		b.rotation.y = _rng.randf() * PI
		_mark_cover(b, s)
	# Buttes on the skyline, out past the banks either side and beyond both ends.
	var butte := _stone.duplicate() as StandardMaterial3D
	butte.albedo_texture = _noise_tex(Color(0.5, 0.36, 0.24), Color(0.66, 0.5, 0.34), 0.03, false)
	for k in 22:
		var bm := BoxMesh.new()
		bm.size = Vector3(_rng.randf_range(40, 110), _rng.randf_range(30, 70), _rng.randf_range(40, 100))
		var at: Vector3
		if k < 16:
			var side := -1.0 if k % 2 == 0 else 1.0
			at = Vector3(180.0 + side * _rng.randf_range(340, 560), 0, _rng.randf_range(-150, 1400))
		else:
			at = Vector3(_rng.randf_range(-200, 560), 0, -260.0 if k % 2 == 0 else 1500.0)
		_mesh(bm, at + Vector3(0, bm.size.y * 0.5 - 2.0, 0), butte, Vector3(0, _rng.randf() * PI, 0))


## The map's sides: banks of sand too steep to climb (48-58 degrees) all round the ground, in
## 40 m lengths of different heights so the skyline rolls, dune mounds along their feet.
func _edges() -> void:
	var seg := 40.0
	for side: float in [-1.0, 1.0]:
		var ex := GROUND.position.x if side < 0.0 else GROUND.end.x
		var z := GROUND.position.y
		while z < GROUND.end.y:
			_bank(Vector3(ex, 0, z + seg * 0.5), Vector3(side, 0, 0), seg)
			z += seg
		var ez := GROUND.position.y if side < 0.0 else GROUND.end.y
		var x := GROUND.position.x
		while x < GROUND.end.x:
			_bank(Vector3(x + seg * 0.5, 0, ez), Vector3(0, 0, side), seg)
			x += seg


## One length of bank at `at` on the edge, rising outward (`out`).
func _bank(at: Vector3, out: Vector3, seg: float) -> void:
	var tilt := deg_to_rad(_rng.randf_range(48.0, 58.0))
	var l := _rng.randf_range(22.0, 44.0)
	var u := out * cos(tilt) + Vector3.UP * sin(tilt)      # up the slope
	var w := Vector3(-out.z, 0, out.x)                      # along the edge
	var n := w.cross(u)                                     # the slab's face normal (inward and up)
	var body := _box(_nav, Vector3.ZERO, Vector3(l, 2.0, seg + 4.0), _sand)
	body.basis = Basis(u, n, w)
	body.position = at + u * (l * 0.5) - n * 1.0 + out * 0.5
	var sm := SphereMesh.new()
	var r := _rng.randf_range(12.0, 22.0)
	sm.radius = r
	sm.height = r * 2.0
	var mound := _mesh(sm, at + out * (r * 1.1) + Vector3(w.x, 0, w.z) * _rng.randf_range(-15, 15) + Vector3(0, -r * 0.62, 0), _sand)
	mound.scale = Vector3(1.4, 1.0, 1.4)
