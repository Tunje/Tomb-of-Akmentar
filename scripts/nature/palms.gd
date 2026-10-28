class_name Palms
extends RefCounted
## Date palms made in code (no model): a tapering, ringed trunk with a lean and a crown of arching
## frond cards (leaflets cut by the shader, alpha scissor), swaying in the wind; four variants
## (VARIANTS: heights, frond counts, one with hanging dead fronds and dates). Drawn as MultiMeshes,
## one per variant per parent: a whole grove is a handful of draw calls.
##   Palms.add(level, at, 8.0, level._nav)   # one palm (batched; its trunk solid in the nav region)
##   Palms.place(level, points)              # many at once
## add() collects and builds once at the end of the frame (the visuals); the trunk's collision goes
## in at once, so a navmesh baked in the same _ready goes round it.

const VARIANTS := [
	{"h": 6.0, "fronds": 11, "lean": 0.35, "dead": 0, "dates": false},
	{"h": 7.5, "fronds": 13, "lean": 0.6, "dead": 3, "dates": true},
	{"h": 9.0, "fronds": 14, "lean": 0.25, "dead": 2, "dates": false},
	{"h": 10.5, "fronds": 12, "lean": 0.8, "dead": 4, "dates": true},
]
const TRUNK_R := 0.24
const FROND_LEN := 3.6
const FRONDS := """
shader_type spatial;
render_mode cull_disabled;
uniform vec4 green : source_color = vec4(0.25, 0.38, 0.14, 1.0);
uniform vec4 tip_col : source_color = vec4(0.48, 0.52, 0.22, 1.0);
uniform vec4 dead_col : source_color = vec4(0.55, 0.42, 0.24, 1.0);
uniform float sway = 1.0;
varying float dead;
void vertex() {
	dead = COLOR.r;
	vec3 base = NODE_POSITION_WORLD;
	float tip = UV.y * UV.y;
	float t = TIME * 1.3 + base.x * 0.31 + base.z * 0.23;
	VERTEX.x += sin(t) * 0.18 * tip * sway;
	VERTEX.z += sin(t * 0.8 + 1.7) * 0.12 * tip * sway;
	VERTEX.y += sin(t * 1.9 + UV.x * 3.0) * 0.05 * tip * sway;
}
void fragment() {
	// Leaflets: slanting strips either side of the midrib, the frond narrowing to its tip.
	float across = abs(UV.x - 0.5) * 2.0;
	float width = sin(clamp(UV.y, 0.0, 1.0) * 3.14159) * 0.95 + 0.05;
	float leaf = fract(UV.y * 26.0 - across * 1.6);
	float cut = step(across, width) * step(0.32, leaf);
	float rib = 1.0 - step(0.06, across);
	ALPHA = max(cut, rib * step(UV.y, 0.98));
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	vec3 c = mix(green.rgb, tip_col.rgb, UV.y * 0.7 + across * 0.2);
	ALBEDO = mix(c, dead_col.rgb, dead);
	ROUGHNESS = 0.8;
	BACKLIGHT = vec3(0.25, 0.3, 0.1);
}
"""

static var _meshes: Array[ArrayMesh] = []
static var _trunk_mat: StandardMaterial3D
static var _frond_mat: ShaderMaterial
static var _pending := {}   # parent instance id -> [parent, [Transform3D, variant]...]


## One palm at `at` (on the ground), about `height` m tall (0 = any). `nav`: where its trunk's
## collision goes (a level's _nav, so a bake goes round it); null = no collision.
static func add(parent: Node3D, at: Vector3, height := 0.0, nav: Node = null) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector3i(roundi(at.x * 10.0), roundi(at.y * 10.0), roundi(at.z * 10.0)))
	var v := _variant_for(height, rng)
	var h: float = height if height > 0.0 else float(VARIANTS[v].h) * rng.randf_range(0.9, 1.1)
	var s := h / float(VARIANTS[v].h)
	var xf := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s, s)), at)
	var id := parent.get_instance_id()
	if not _pending.has(id):
		_pending[id] = [parent, []]
		_flush.bind(id).call_deferred()
	(_pending[id][1] as Array).append([xf, v])
	if nav:
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		var cs := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = TRUNK_R * s * 1.1
		cyl.height = h * 0.9
		cs.shape = cyl
		body.add_child(cs)
		nav.add_child(body)
		body.global_position = at + Vector3.UP * h * 0.45


## Many at once (built now): `points` are ground positions; heights vary by variant.
static func place(parent: Node3D, points: Array, nav: Node = null) -> void:
	for p: Vector3 in points:
		add(parent, p, 0.0, nav)
	_flush(parent.get_instance_id())


## Build what add() collected for a parent: a MultiMeshInstance3D per variant.
static func _flush(id: int) -> void:
	if not _pending.has(id):
		return
	var entry: Array = _pending[id]
	_pending.erase(id)
	if not is_instance_valid(entry[0]):
		return   # (freed before the end of its frame)
	var parent: Node3D = entry[0]
	_ensure()
	var by: Array = [[], [], [], []]
	for e: Array in entry[1]:
		(by[int(e[1])] as Array).append(e[0])
	for v in VARIANTS.size():
		var xs: Array = by[v]
		if xs.is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = _meshes[v]
		mm.instance_count = xs.size()
		for i in xs.size():
			mm.set_instance_transform(i, xs[i])
		var mi := MultiMeshInstance3D.new()
		mi.name = "Palms_%d" % v
		mi.multimesh = mm
		mi.visibility_range_end = 260.0
		parent.add_child(mi)
		mi.global_transform = Transform3D.IDENTITY


static func _variant_for(height: float, rng: RandomNumberGenerator) -> int:
	if height <= 0.0:
		return rng.randi_range(0, VARIANTS.size() - 1)
	var best := 0
	for v in VARIANTS.size():
		if absf(float(VARIANTS[v].h) - height) < absf(float(VARIANTS[best].h) - height):
			best = v
	return best


# ---------------------------------------------------------------- the meshes

static func _ensure() -> void:
	if not _meshes.is_empty():
		return
	_trunk_mat = StandardMaterial3D.new()
	_trunk_mat.vertex_color_use_as_albedo = true
	_trunk_mat.vertex_color_is_srgb = true
	_trunk_mat.roughness = 0.95
	var sh := Shader.new()
	sh.code = FRONDS
	_frond_mat = ShaderMaterial.new()
	_frond_mat.shader = sh
	for v in VARIANTS.size():
		_meshes.append(_build(VARIANTS[v], v))


## One variant: the trunk (a surface) and the crown (another).
static func _build(spec: Dictionary, seed_n: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 900 + seed_n
	var h := float(spec.h)
	var lean := float(spec.lean)
	var mesh := ArrayMesh.new()
	# The trunk: rings up a gentle curve, tapering, banded dark and light.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings := 14
	var sides := 8
	var top := Vector3.ZERO
	for r in rings:
		for k in sides:
			for corner in [[r, k], [r + 1, k], [r + 1, k + 1], [r, k], [r + 1, k + 1], [r, k + 1]]:
				var t: float = float(corner[0]) / rings
				var a: float = TAU * float(corner[1]) / sides
				var centre := Vector3(lean * t * t * h * 0.35, t * h, 0)
				var rad := TRUNK_R * lerpf(1.25, 0.7, t)
				var band := 0.82 + 0.18 * float(int(t * h / 0.35) % 2)
				st.set_color(Color(0.42, 0.33, 0.24) * band)
				st.add_vertex(centre + Vector3(cos(a) * rad, 0, sin(a) * rad))
		top = Vector3(lean * h * 0.35, h, 0)
	# Dates: a few clusters under the crown.
	if spec.dates:
		for c in 3:
			var a := TAU * c / 3.0 + 0.4
			var at := top + Vector3(cos(a) * 0.35, -0.6, sin(a) * 0.35)
			_blob(st, at, 0.22, Color(0.75, 0.42, 0.12))
	st.generate_normals()
	st.set_material(_trunk_mat)
	mesh = st.commit(mesh)
	# The crown: fronds arching out and down, a few dead ones hanging.
	var fr := SurfaceTool.new()
	fr.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := int(spec.fronds)
	for i in n:
		var a := TAU * i / n + rng.randf_range(-0.2, 0.2)
		var rise := rng.randf_range(0.3, 1.3)
		var droop := rng.randf_range(1.6, 2.6)
		_frond(fr, top, a, rise, droop, FROND_LEN * rng.randf_range(0.85, 1.15), 0.0)
	for i in int(spec.dead):
		var a := TAU * i / maxf(float(spec.dead), 1.0) + 0.6
		_frond(fr, top - Vector3.UP * 0.3, a, -1.2, 0.6, FROND_LEN * 0.8, 1.0)
	fr.generate_normals()
	fr.set_material(_frond_mat)
	mesh = fr.commit(mesh)
	return mesh


## A frond: a folded strip along an arch from the crown (UV.y 0 at the base, 1 at the tip).
static func _frond(st: SurfaceTool, top: Vector3, a: float, rise: float, droop: float, length: float, dead: float) -> void:
	var dir := Vector3(cos(a), 0, sin(a))
	var side := Vector3(-sin(a), 0, cos(a))
	var segs := 7
	var pts: Array[Vector3] = []
	for s in segs + 1:
		var t := float(s) / segs
		pts.append(top + dir * length * t + Vector3.UP * (rise * sin(t * PI * 0.7) - droop * t * t))
	for s in segs:
		var t0 := float(s) / segs
		var t1 := float(s + 1) / segs
		var w0 := 0.55 * sin(maxf(t0, 0.08) * PI) + 0.05
		var w1 := 0.55 * sin(maxf(t1, 0.08) * PI) + 0.05
		var fold := Vector3.DOWN * 0.12
		# Two halves either side of the midrib, folded down a little (a V): volume from the side.
		for half: float in [-1.0, 1.0]:
			var e0: Vector3 = pts[s] + side * w0 * half + fold * w0
			var e1: Vector3 = pts[s + 1] + side * w1 * half + fold * w1
			var u_e := 0.5 + 0.5 * half
			var quad := [[pts[s], 0.5, t0], [e0, u_e, t0], [e1, u_e, t1], [pts[s], 0.5, t0], [e1, u_e, t1], [pts[s + 1], 0.5, t1]]
			for q: Array in quad:
				st.set_color(Color(dead, 0, 0))
				st.set_uv(Vector2(q[1], q[2]))
				st.add_vertex(q[0])


static func _blob(st: SurfaceTool, c: Vector3, r: float, col: Color) -> void:
	var faces := [[Vector3.UP, Vector3.RIGHT, Vector3.BACK], [Vector3.DOWN, Vector3.RIGHT, Vector3.FORWARD],
		[Vector3.RIGHT, Vector3.UP, Vector3.FORWARD], [Vector3.LEFT, Vector3.UP, Vector3.BACK],
		[Vector3.BACK, Vector3.UP, Vector3.RIGHT], [Vector3.FORWARD, Vector3.UP, Vector3.LEFT]]
	for f: Array in faces:
		var n: Vector3 = f[0]
		var u: Vector3 = f[1]
		var v: Vector3 = f[2]
		var ctr := c + n * r
		var corners := [ctr - u * r - v * r, ctr + u * r - v * r, ctr + u * r + v * r, ctr - u * r + v * r]
		for idx in [0, 2, 1, 0, 3, 2]:
			st.set_color(col)
			st.add_vertex(corners[idx])
