class_name NavCache
extends RefCounted
## A big map's navmesh baked once and kept: the next load of the same geometry reads it back
## (tens of ms) instead of baking it again (seconds). The cache is keyed by a signature of what the
## bake would read (every collision shape the region parses: its kind, size and place; and the
## navmesh's own settings), so any change to the map bakes afresh.
##   NavCache.bake(_nav, "valley")          # in place of _nav.bake_navigation_mesh(false)
##   NavCache.bake(_nav, "valley", true)    # cold: baked on a thread (the map is walkable later)
## Read from res://nav/<key>.res (shipped with the game, written by `NavCache.ship = true`, e.g.
## tests/nature_test --ship) or user://navcache/<key>.res (written after any cold bake); each holds
## its signature in its metadata, so a stale one is passed over (and replaced).

const SHIP_DIR := "res://nav/"
const USER_DIR := "user://navcache/"

static var ship := false        # also write res://nav/<key>.res (from a dev run, to commit)
static var last := {}           # key -> {"from": "res"|"user"|"baked", "ms": int, "sig": String}
static var _tile_sig := {}      # key -> the signature tiles() worked out (save_tiles() keeps it)


## Gives `region` its navmesh: from the cache when the geometry's the same, else baked (and saved).
## Returns true if it came from the cache.
static func bake(region: NavigationRegion3D, key: String, threaded := false) -> bool:
	var t0 := Time.get_ticks_msec()
	var sig := signature(region)
	for dir: String in [SHIP_DIR, USER_DIR]:
		var path := dir + key + ".res"
		if not ResourceLoader.exists(path):
			continue
		var nm := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as NavigationMesh
		if nm and str(nm.get_meta("sig", "")) == sig:
			region.navigation_mesh = nm
			last[key] = {"from": "res" if dir == SHIP_DIR else "user", "ms": Time.get_ticks_msec() - t0, "sig": sig}
			return true
	if threaded:
		region.bake_finished.connect(_save.bind(region, key, sig, t0), CONNECT_ONE_SHOT)
		region.bake_navigation_mesh(true)
	else:
		region.bake_navigation_mesh(false)
		_save(region, key, sig, t0)
	return false


## A map baked in tiles (a region per tile, as RoadV2 does): its cached tiles {name: NavigationMesh}
## for the geometry under `region` (`extra`: anything else the tiling depends on, e.g. the tile
## size), or {} when there's none or it's stale: bake them, then hand them to save_tiles().
static func tiles(region: NavigationRegion3D, key: String, extra := "") -> Dictionary:
	var t0 := Time.get_ticks_msec()
	var sig := signature(region) + "_" + extra
	_tile_sig[key] = sig
	for dir: String in [SHIP_DIR, USER_DIR]:
		var path := dir + key + ".res"
		if not ResourceLoader.exists(path):
			continue
		var pack := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
		if pack and str(pack.get_meta("sig", "")) == sig:
			var out := {}
			var names: Array = pack.get_meta("names", [])
			var meshes: Array = pack.get_meta("tiles", [])
			for i in mini(names.size(), meshes.size()):
				out[names[i]] = meshes[i]
			last[key] = {"from": "res" if dir == SHIP_DIR else "user", "ms": Time.get_ticks_msec() - t0, "sig": sig}
			return out
	return {}


## Keeps a tiled bake (after tiles() came back empty): {name: NavigationMesh}.
static func save_tiles(key: String, made: Dictionary) -> void:
	var pack := Resource.new()
	pack.set_meta("sig", str(_tile_sig.get(key, "")))
	pack.set_meta("names", made.keys())
	pack.set_meta("tiles", made.values())
	last[key] = {"from": "baked", "ms": -1, "sig": str(_tile_sig.get(key, ""))}
	_write(pack, key)


static func _save(region: NavigationRegion3D, key: String, sig: String, t0: int) -> void:
	last[key] = {"from": "baked", "ms": Time.get_ticks_msec() - t0, "sig": sig}
	if not is_instance_valid(region) or region.navigation_mesh == null:
		return
	var nm := region.navigation_mesh
	nm.set_meta("sig", sig)
	_write(nm, key)


static func _write(res: Resource, key: String) -> void:
	var dirs: Array[String] = [USER_DIR]
	if ship:
		dirs.append(SHIP_DIR)
	for dir in dirs:
		DirAccess.make_dir_recursive_absolute(dir)
		var err := ResourceSaver.save(res, dir + key + ".res", ResourceSaver.FLAG_COMPRESS)
		if err != OK:
			push_warning("NavCache: couldn't save %s%s.res (%s)" % [dir, key, error_string(err)])


## What the bake would read, as a short hash: the navmesh's settings, then every collision shape
## the region parses (under it, or in its source group), in tree order.
static func signature(region: NavigationRegion3D) -> String:
	var nm := region.navigation_mesh
	var parts := PackedStringArray()
	for p: String in ["cell_size", "cell_height", "agent_radius", "agent_height", "agent_max_climb", "agent_max_slope",
			"region_min_size", "region_merge_size", "edge_max_length", "edge_max_error", "detail_sample_distance",
			"detail_sample_max_error", "geometry_parsed_geometry_type", "geometry_collision_mask", "geometry_source_geometry_mode",
			"filter_low_hanging_obstacles", "filter_ledge_spans", "filter_walkable_low_height_spans", "border_size",
			"filter_baking_aabb", "filter_baking_aabb_offset"]:
		parts.append(str(nm.get(p)))
	var roots: Array[Node] = []
	if nm.geometry_source_geometry_mode == NavigationMesh.SOURCE_GEOMETRY_ROOT_NODE_CHILDREN:
		roots.append(region)
	else:
		roots.append_array(region.get_tree().get_nodes_in_group(nm.geometry_source_group_name))
	for r in roots:
		_shapes(r, nm, parts, nm.geometry_source_geometry_mode != NavigationMesh.SOURCE_GEOMETRY_GROUPS_EXPLICIT)
	return str(hash(parts)) + "_" + str(parts.size())


static func _shapes(n: Node, nm: NavigationMesh, parts: PackedStringArray, deep: bool) -> void:
	if n is CollisionObject3D and nm.geometry_parsed_geometry_type != NavigationMesh.PARSED_GEOMETRY_MESH_INSTANCES:
		if (n as CollisionObject3D).collision_layer & nm.geometry_collision_mask:
			for c in n.get_children():
				if c is CollisionShape3D and not (c as CollisionShape3D).disabled and (c as CollisionShape3D).shape:
					parts.append(_shape(c as CollisionShape3D))
	if n is MeshInstance3D and nm.geometry_parsed_geometry_type != NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS:
		var mi := n as MeshInstance3D
		if mi.mesh:
			parts.append("M%s%s%s" % [mi.mesh.get_aabb(), mi.mesh.resource_path, mi.global_transform])
	if n is MultiMeshInstance3D and nm.geometry_parsed_geometry_type != NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS:
		var mm := (n as MultiMeshInstance3D).multimesh
		if mm:
			parts.append("MM%d%s%s" % [mm.instance_count, mm.get_aabb(), (n as Node3D).global_transform])
	if not deep:
		return
	for c in n.get_children():
		_shapes(c, nm, parts, true)


static func _shape(cs: CollisionShape3D) -> String:
	var s := cs.shape
	var at := str(cs.global_transform)
	if s is BoxShape3D:
		return "B%s%s" % [(s as BoxShape3D).size, at]
	if s is CylinderShape3D:
		return "C%s,%s%s" % [(s as CylinderShape3D).radius, (s as CylinderShape3D).height, at]
	if s is CapsuleShape3D:
		return "K%s,%s%s" % [(s as CapsuleShape3D).radius, (s as CapsuleShape3D).height, at]
	if s is SphereShape3D:
		return "S%s%s" % [(s as SphereShape3D).radius, at]
	if s is ConvexPolygonShape3D:
		return "V%d%s" % [hash((s as ConvexPolygonShape3D).points), at]
	if s is ConcavePolygonShape3D:
		return "F%d%s" % [hash((s as ConcavePolygonShape3D).get_faces()), at]
	if s is HeightMapShape3D:
		var hm := s as HeightMapShape3D
		return "H%d,%d,%d%s" % [hm.map_width, hm.map_depth, hash(hm.map_data), at]
	if s is WorldBoundaryShape3D:
		return "W%s%s" % [(s as WorldBoundaryShape3D).plane, at]
	return "%s%s" % [s.get_class(), at]
