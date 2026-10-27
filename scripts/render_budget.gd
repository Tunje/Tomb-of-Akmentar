class_name RenderBudget
extends Node
## Frame-time savers with no visible loss (the performance pass):
## - Shadowed lights: a light that wants shadows joins SHADOW_GROUP; only the max_shadowed nearest
##   the camera within SHADOW_RANGE actually cast them (re-picked 4 times a second). Act 5's 18
##   shadowed braziers each re-rendered the tomb six times (a cube map) every frame.
## - quiet(): no shadow casting (and optionally a draw distance) on a prop's meshes: a 24k-tri
##   sconce beside its own flame throws nothing anyone sees.
## - quiet_small(): the same for every mesh under a node whose largest side is under `max_size`.
## - merge_static(): every still mesh under a node, combined per area and material into a few
##   meshes (Cairo's 3929 decoration meshes were ~5300 draw calls with their shadows).
##   RenderBudget.want_shadows(light)      # instead of light.shadow_enabled = true
##   RenderBudget.quiet(prop, 30.0)

const SHADOW_GROUP := "budget_shadow_light"
const SHADOW_RANGE := 15.0
## How many may cast shadows at once (the options' quality: 0 low, 2 medium, 4 high).
static var max_shadowed := 4

var _t := 0.0


## Register a light for shadows under the budget (adds the scene's one RenderBudget if needed).
static func want_shadows(light: Light3D) -> void:
	light.add_to_group(SHADOW_GROUP)
	light.shadow_enabled = false  # the budget turns it on when it's near
	if light.is_inside_tree():
		_ensure(light)
	else:
		light.tree_entered.connect(func(): _ensure(light), CONNECT_ONE_SHOT)


## One per scene, on the light's top node under the root (so it goes with that scene).
static func _ensure(light: Node) -> void:
	var host := light
	while host.get_parent() and host.get_parent() != light.get_tree().root:
		host = host.get_parent()
	if host.has_meta("render_budget"):
		return
	host.set_meta("render_budget", true)
	var b := RenderBudget.new()
	b.name = "RenderBudget"
	host.add_child.call_deferred(b)


## No shadows from `node`'s meshes (itself and below); not drawn past `draw_end` m if > 0.
## Combine the still meshes under `node` into one mesh per `cell` m square, per material, per
## shadow and draw-distance setting (so culling, shadows and fades still work by area). Materials
## stay shared: changing one (dusk lighting a window) still shows on every merged copy. Skinned,
## blend-shaped and animated (under an AnimationPlayer's scene, or a moving body) meshes, any with
## children, anything under a node with a script of its own (doors, interactables: they move, hide
## or get looked up) and anything under `keep` are left alone. Returns how many draw calls it saved.
static func merge_static(node: Node3D, cell := 24.0, keep: Array = []) -> int:
	var groups := {}  # key -> {"st": SurfaceTool, "mat", "shadow", "end", ...}
	var merged: Array[MeshInstance3D] = []
	var to_local := node.global_transform.affine_inverse()
	for m: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		if m.mesh == null or not m.is_visible_in_tree() or _going(m, node) or _kept(m, node, keep) or m.get_node_or_null(m.skeleton) is Skeleton3D:
			continue
		if (m.mesh is ArrayMesh and (m.mesh as ArrayMesh).get_blend_shape_count() > 0) or m.get_child_count() > 0 or _animated(m, node):
			continue
		var ok := true
		for i in m.mesh.get_surface_count():
			ok = ok and (not m.mesh is ArrayMesh or (m.mesh as ArrayMesh).surface_get_primitive_type(i) == Mesh.PRIMITIVE_TRIANGLES)
		if not ok:
			continue
		var xf := to_local * m.global_transform
		var c := Vector2i(floori(xf.origin.x / cell), floori(xf.origin.z / cell))
		for i in m.mesh.get_surface_count():
			var mat := m.get_active_material(i)
			var key := "%s|%d|%d|%.1f" % [c, mat.get_instance_id() if mat else 0, m.cast_shadow, m.visibility_range_end]
			if not groups.has(key):
				var st := SurfaceTool.new()
				st.begin(Mesh.PRIMITIVE_TRIANGLES)
				groups[key] = {"st": st, "mat": mat, "shadow": m.cast_shadow, "end": m.visibility_range_end,
					"margin": m.visibility_range_end_margin, "fade": m.visibility_range_fade_mode}
			(groups[key].st as SurfaceTool).append_from(m.mesh, i, xf)
		merged.append(m)
	for key: String in groups:
		var g: Dictionary = groups[key]
		var mi := MeshInstance3D.new()
		mi.name = "Merged"
		mi.mesh = (g.st as SurfaceTool).commit()
		mi.material_override = g.mat
		mi.cast_shadow = g.shadow
		mi.visibility_range_end = g.end
		mi.visibility_range_end_margin = g.margin
		mi.visibility_range_fade_mode = g.fade
		node.add_child(mi)
	for m in merged:
		m.get_parent().remove_child(m)
		m.queue_free()
	return merged.size() - groups.size()


## Under one of `keep`, or under a node with its own script (below `top`, which has one).
static func _kept(m: Node, top: Node, keep: Array) -> bool:
	var n := m
	while n != null and n != top:
		if n in keep or (n != m and n.get_script() != null):
			return true
		n = n.get_parent()
	return false


## Freed this frame (queue_free: still in the tree until the frame ends), or under something that is.
static func _going(m: Node, top: Node) -> bool:
	var n := m
	while n != null and n != top:
		if n.is_queued_for_deletion():
			return true
		n = n.get_parent()
	return false


static func _animated(m: Node, top: Node) -> bool:
	var n := m.get_parent()
	while n != null and n != top:
		if n is AnimatableBody3D or n is RigidBody3D or n is CharacterBody3D:
			return true
		for c in n.get_children():
			if c is AnimationPlayer:
				return true
		n = n.get_parent()
	return false


static func quiet(node: Node, draw_end := 0.0) -> void:
	if node == null:
		return
	var all: Array = node.find_children("*", "GeometryInstance3D", true, false)
	if node is GeometryInstance3D:
		all.append(node)
	for g: GeometryInstance3D in all:
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if draw_end > 0.0:
			g.visibility_range_end = draw_end
			g.visibility_range_end_margin = 2.0
			g.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF


## quiet() for each mesh under `node` whose largest side (scaled) is under `max_size` m.
static func quiet_small(node: Node, max_size: float, draw_end := 0.0) -> int:
	var n := 0
	for m: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		if m.mesh == null:
			continue
		var s := m.mesh.get_aabb().size * m.global_basis.get_scale()
		if maxf(s.x, maxf(s.y, s.z)) < max_size:
			quiet(m, draw_end)
			n += 1
	return n


## A town's decoration: no shadows from what's small (under `small` m: jars, lantern bits; also
## not drawn past `small_end` m) or flat against a wall (thinner than `thin` and under `flat_max`
## across: windows, trims, plaques). Awnings, domes and palms keep theirs. Returns how many.
static func quiet_minor(node: Node, small := 0.6, small_end := 60.0, thin := 0.12, flat_max := 1.5) -> int:
	var n := 0
	for m: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		if m.mesh == null or m.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			continue
		var s := m.mesh.get_aabb().size * m.global_basis.get_scale()
		var big := maxf(s.x, maxf(s.y, s.z))
		var least := minf(s.x, minf(s.y, s.z))
		if big < small:
			# Lamp glass and lit windows glow at dusk: no shadow, but drawn at any distance.
			var mat := m.get_active_material(0) as BaseMaterial3D
			quiet(m, 0.0 if mat and mat.emission_enabled else small_end)
			n += 1
		elif least < thin and big < flat_max:
			quiet(m)
			n += 1
	return n


func _process(delta: float) -> void:
	_t -= delta
	if _t > 0.0:
		return
	_t = 0.25
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var at := cam.global_position
	var near: Array = []
	for n in get_tree().get_nodes_in_group(SHADOW_GROUP):
		var l := n as Light3D
		if l == null or not l.is_visible_in_tree():
			continue
		var d := l.global_position.distance_to(at)
		if d < SHADOW_RANGE:
			near.append([d, l])
		else:
			l.shadow_enabled = false
	near.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	for i in near.size():
		(near[i][1] as Light3D).shadow_enabled = i < max_shadowed
