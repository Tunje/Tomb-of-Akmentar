class_name RiverWater
extends MeshInstance3D
## The river: one big subdivided plane with a moving shader. A slow swell; ripples at two scales
## drifting with the current at two speeds; a muddy Nile green that takes the sky's colour at a
## low angle; sun glints twinkling where the ripples catch the sun (they follow the level's sun,
## and fade as it goes down). No physics: anything that falls through is the boat's problem
## (RiverBoat.watch puts people back on deck).
##   RiverWater.make(self, Vector2(400, 400), 0.0)
## On a RiverRoute it also lays reed beds along both banks (one MultiMesh, swaying in the wind).

const SHADER := """
shader_type spatial;
render_mode cull_disabled;

uniform vec4 deep : source_color = vec4(0.10, 0.20, 0.18, 1.0);
uniform vec4 shallow : source_color = vec4(0.30, 0.38, 0.27, 1.0);
uniform vec4 sky : source_color = vec4(0.62, 0.70, 0.74, 1.0);
uniform vec2 flow = vec2(0.0, 0.6);
uniform float swell = 0.06;
uniform vec3 sun_dir = vec3(0.4, 0.6, 0.3);   // toward the sun, world space
uniform vec4 sun_col : source_color = vec4(1.0, 0.92, 0.75, 1.0);
uniform float glint = 1.0;

varying vec3 wpos;

float waves(vec2 p, float t) {
	return sin(p.x * 0.35 + t * 1.3) * 0.5 + sin(p.y * 0.27 - t * 1.1) * 0.5
		+ sin((p.x + p.y) * 0.9 + t * 2.1) * 0.25;
}

float rip(vec2 p, float t) {
	return sin(p.x * 1.7 + sin(p.y * 0.6) * 2.0) * sin(p.y * 1.3 + t * 0.8)
		+ 0.5 * sin(p.x * 3.9 - p.y * 2.7 + t * 1.7);
}

vec2 slope(vec2 p, float t) {
	float e = 0.05;
	float h = rip(p, t);
	return vec2(rip(p + vec2(e, 0.0), t) - h, rip(p + vec2(0.0, e), t) - h) / e;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX.y += waves(wpos.xz, TIME) * swell;
}

void fragment() {
	// Broad ripples with the current, finer ones faster across them.
	vec2 p1 = wpos.xz - flow * TIME;
	vec2 p2 = wpos.xz * 2.6 - flow * TIME * 2.2 + vec2(13.0, 7.0);
	vec2 s = slope(p1, TIME) * 0.08 + slope(p2, TIME * 1.3) * 0.035;
	vec3 n = normalize(vec3(-s.x, 1.0, -s.y));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	vec3 v = normalize(CAMERA_POSITION_WORLD - wpos);
	float r = rip(p1, TIME);
	vec3 base = mix(deep.rgb, shallow.rgb, clamp(0.5 + r * 0.18, 0.0, 1.0));
	float fres = pow(1.0 - clamp(dot(n, v), 0.0, 1.0), 4.0);
	ALBEDO = mix(base, sky.rgb * 0.8, fres * 0.55);
	// Glints: the sun's reflection, broken into twinkling points on the ripples.
	vec3 refl = reflect(-v, n);
	float sun = pow(max(dot(refl, normalize(sun_dir)), 0.0), 700.0);
	vec2 cell = floor(wpos.xz * 5.0 + flow * TIME * 5.0);
	float tw = step(0.72, hash(cell)) * (0.5 + 0.5 * sin(TIME * 9.0 + hash(cell + 3.1) * 40.0));
	EMISSION = sun_col.rgb * sun * tw * glint * 7.0;
	ROUGHNESS = 0.12;
	SPECULAR = 0.6;
	METALLIC = 0.0;
}
"""
const REEDS := """
shader_type spatial;
render_mode cull_disabled;
uniform vec4 tip : source_color = vec4(0.62, 0.6, 0.32, 1.0);
uniform vec4 root : source_color = vec4(0.22, 0.3, 0.12, 1.0);
void vertex() {
	// Sway in the wind, more toward the tips, out of step from clump to clump.
	vec3 w = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float k = VERTEX.y * VERTEX.y;
	VERTEX.x += sin(TIME * 1.4 + w.x * 0.7 + w.z * 0.4) * 0.07 * k;
	VERTEX.z += sin(TIME * 1.1 + w.z * 0.6) * 0.04 * k;
}
void fragment() {
	ALBEDO = mix(root.rgb, tip.rgb, clamp(UV.y, 0.0, 1.0));
	ROUGHNESS = 0.85;
}
"""
const REED_EVERY := 1.0       # m along each bank between clumps (some skipped: the beds come and go)

var _sun: DirectionalLight3D
var _sun_t := 0.0


static func make(parent: Node3D, size: Vector2, y := 0.0, centre := Vector3.ZERO) -> RiverWater:
	var w := RiverWater.new()
	w.name = "RiverWater"
	var pm := PlaneMesh.new()
	pm.size = size
	pm.subdivide_width = int(size.x / 2.0)
	pm.subdivide_depth = int(size.y / 2.0)
	w.mesh = pm
	var sh := Shader.new()
	sh.code = SHADER
	var m := ShaderMaterial.new()
	m.shader = sh
	w.material_override = m
	w.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(w)
	w.global_position = Vector3(centre.x, y, centre.z)
	if parent is RiverRoute and (parent as RiverRoute).path:
		reed_beds(parent, (parent as RiverRoute).path, RiverRoute.HALF_W, y)
	return w


## The sun's direction and height into the glints, twice a second (the level sets its sun after).
func _process(delta: float) -> void:
	_sun_t -= delta
	if _sun_t > 0.0:
		return
	_sun_t = 0.5
	if not is_instance_valid(_sun):
		var s: Variant = get_parent().get("_sun")
		_sun = s if s is DirectionalLight3D else null
		if _sun == null:
			return
	var m := material_override as ShaderMaterial
	var to_sun := _sun.global_basis.z
	m.set_shader_parameter("sun_dir", to_sun)
	m.set_shader_parameter("sun_col", _sun.light_color)
	m.set_shader_parameter("glint", smoothstep(0.03, 0.3, to_sun.y) * (1.0 if _sun.visible else 0.0))


## Reed beds along both banks of `path` (`half_w` from its middle to the water's edge): clumps of
## blades in one MultiMesh, standing in the shallows and up the bank's foot.
static func reed_beds(parent: Node3D, path: Path3D, half_w: float, water_y := 0.0) -> MultiMeshInstance3D:
	var c := path.curve
	var length := c.get_baked_length()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7311
	var xforms: Array[Transform3D] = []
	var s := 0.0
	while s < length:
		var p := c.sample_baked(s)
		var q := c.sample_baked(minf(s + 1.0, length))
		var f := (q - p).normalized()
		var right := f.cross(Vector3.UP).normalized()
		var bed := 0.5 + 0.5 * sin(s * 0.045) * sin(s * 0.11 + 1.3)   # thick here, thin there
		for side in [-1.0, 1.0]:
			if rng.randf() > 0.45 + 0.55 * bed:
				continue
			for k in rng.randi_range(6, 12):
				var at: Vector3 = p + right * side * (half_w + rng.randf_range(-1.6, 1.2)) + f * rng.randf_range(-0.8, 0.8)
				var h := rng.randf_range(1.1, 2.4) * (0.7 + 0.5 * bed)
				var b := Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.RIGHT, rng.randf_range(-0.15, 0.15))
				xforms.append(Transform3D(b.scaled(Vector3(1.0, h, 1.0)), path.global_transform * at + Vector3.UP * (water_y - 0.25)))
		s += REED_EVERY
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _blades()
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mi := MultiMeshInstance3D.new()
	mi.name = "ReedBeds"
	mi.multimesh = mm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var sh := Shader.new()
	sh.code = REEDS
	var m := ShaderMaterial.new()
	m.shader = sh
	mi.material_override = m
	parent.add_child(mi)
	return mi


## One clump: eight blades leaning out from a point, 1 m tall (scaled per clump).
static func _blades() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in 8:
		var a := TAU * k / 8.0 + fmod(k * 0.9, 0.5)
		var lean := Vector3(cos(a), 0, sin(a)) * (0.12 + 0.1 * fmod(k * 0.37, 1.0))
		var side := Vector3(-sin(a), 0, cos(a)) * 0.05
		var top := lean + Vector3.UP
		for v: Array in [[-side, 0.0], [side, 0.0], [top, 1.0]]:
			st.set_uv(Vector2(0.5, v[1]))
			st.add_vertex(v[0])
	st.generate_normals()
	return st.commit()
