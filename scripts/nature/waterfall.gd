class_name Waterfall
extends Node3D
## A waterfall made in code (no model): a sheet of water leaving a lip and falling on a curve
## (streaks of foam running down it, faster as it falls, whiter at the bottom), a churning ring of
## foam where it lands, spray thrown up off the pool, mist drifting from the base, and its roar
## (SoundLife's "falls" loop, carrying far).
##   Waterfall.make(level, Vector3(0, 30, 0), 8.0, 25.0, Vector3.BACK)   # lip's middle, width,
##                                                                      # drop, the way it pours
## No collision: water. Particles thin out on the low quality setting.

const SHEET := """
shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;
uniform vec4 water_col : source_color = vec4(0.44, 0.56, 0.58, 1.0);
uniform vec4 foam_col : source_color = vec4(0.93, 0.95, 0.94, 1.0);
uniform float width_m = 8.0;
uniform float height_m = 25.0;
uniform float speed = 1.0;
float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}
void fragment() {
	float y = UV.y;
	// Streaks: noise drawn out along the fall, scrolling down; sqrt(y) as the water speeds up.
	float along = sqrt(y) * height_m * 0.5 - TIME * speed * 2.4;
	vec2 q = vec2(UV.x * width_m * 2.2, along);
	float n = noise(q * vec2(1.0, 0.18)) * 0.6 + noise(q * vec2(2.7, 0.45) + 7.3) * 0.4;
	float streak = smoothstep(0.38, 0.85, n);
	float fine = noise(vec2(UV.x * width_m * 9.0, along * 3.0 + 11.0));
	float edge = smoothstep(0.0, 0.07, UV.x) * smoothstep(0.0, 0.07, 1.0 - UV.x);
	float white = clamp(streak * 0.75 + y * 0.45 + fine * 0.15, 0.0, 1.0);
	ALBEDO = mix(water_col.rgb, foam_col.rgb, white);
	ALPHA = edge * clamp(0.5 + streak * 0.4 + y * 0.3 - (1.0 - fine) * 0.15 * (1.0 - y), 0.0, 1.0);
	ROUGHNESS = mix(0.15, 0.6, white);
	SPECULAR = 0.5;
	BACKLIGHT = vec3(0.25, 0.3, 0.3);
}
"""
const POOL := """
shader_type spatial;
render_mode cull_disabled, depth_draw_never;
uniform vec4 foam_col : source_color = vec4(0.93, 0.95, 0.94, 1.0);
float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}
void fragment() {
	// Churn spreading out from where the sheet lands (an oval, along the lip): thick at the
	// middle, broken into drifting patches toward the edge.
	vec2 c = (UV - 0.5) * 2.0;
	float r = length(c);
	float a = atan(c.y, c.x);
	float n = noise(vec2(a * 3.0, r * 6.0 - TIME * 1.4)) * 0.6 + noise(vec2(a * 7.0 + 3.0, r * 14.0 - TIME * 2.3)) * 0.4;
	float body = 1.0 - smoothstep(0.15, 1.0, r);
	ALBEDO = foam_col.rgb;
	ALPHA = clamp(body * (0.35 + n * 0.9) - (1.0 - body) * 0.2, 0.0, 1.0) * 0.95;
	ROUGHNESS = 0.7;
}
"""
const LIP_SPEED := 1.6      # m/s the water leaves the lip at (how far out the curve throws it)
const GRAVITY := 9.8

var width := 8.0
var height := 25.0
var sound: AudioStreamPlayer3D


## A waterfall whose lip's middle is `top`, `width` m across, dropping `height` m, pouring toward
## `out` (flat; it falls on a curve from there).
static func make(parent: Node3D, top: Vector3, w: float, h: float, out := Vector3.BACK) -> Waterfall:
	var f := Waterfall.new()
	f.name = "Waterfall"
	f.width = w
	f.height = h
	parent.add_child(f)
	var fwd := Vector3(out.x, 0.0, out.z).normalized()
	f.global_transform = Transform3D(Basis(fwd.cross(Vector3.UP).normalized() * -1.0, Vector3.UP, fwd), top)
	f._build()
	return f


## Where the water lands (world): the middle of the pool's churn.
func base() -> Vector3:
	return global_transform * Vector3(0.0, -height, _throw())


func _throw() -> float:
	return LIP_SPEED * sqrt(2.0 * height / GRAVITY)


func _build() -> void:
	var low := str(Settings.value("quality")) == "low"
	var sh := Shader.new()
	sh.code = SHEET
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("width_m", width)
	m.set_shader_parameter("height_m", height)
	var sheet := MeshInstance3D.new()
	sheet.name = "Sheet"
	sheet.mesh = _sheet_mesh()
	sheet.material_override = m
	sheet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(sheet)
	var at := Vector3(0.0, -height, _throw())
	# The churn: a flat oval of foam on the pool, a little above the water.
	var ps := Shader.new()
	ps.code = POOL
	var pm := ShaderMaterial.new()
	pm.shader = ps
	var ring := MeshInstance3D.new()
	ring.name = "Churn"
	var plane := PlaneMesh.new()
	plane.size = Vector2(width * 1.7, width * 0.9 + 4.0)
	ring.mesh = plane
	pm.render_priority = 1       # over the pool's water (both transparent)
	ring.material_override = pm
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)
	ring.position = at + Vector3(0, 0.08, 0.6)
	# Spray: white blobs thrown up and out off the landing, falling back.
	var spray := _particles("Spray", int(width * (6.0 if low else 14.0)), 1.3, Vector2(0.8, 2.0), 0.6)
	var sm := spray.process_material as ParticleProcessMaterial
	sm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	sm.emission_box_extents = Vector3(width * 0.45, 0.2, 0.6)
	sm.direction = Vector3(0, 1, 0.4)
	sm.spread = 35.0
	sm.initial_velocity_min = 1.5
	sm.initial_velocity_max = 4.0
	sm.gravity = Vector3(0, -6.0, 0)
	spray.position = at
	add_child(spray)
	# Mist: big faint puffs rising and drifting off the pool, out toward `out`.
	var mist := _particles("Mist", int(width * (1.5 if low else 3.5)), 5.0, Vector2(4.0, 9.0), 0.28)
	var mm := mist.process_material as ParticleProcessMaterial
	mm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mm.emission_box_extents = Vector3(width * 0.55, 0.5, 1.2)
	mm.direction = Vector3(0, 0.6, 1)
	mm.spread = 25.0
	mm.initial_velocity_min = 0.4
	mm.initial_velocity_max = 1.4
	mm.gravity = Vector3(0, 0.15, 0)
	mm.damping_min = 0.1
	mm.damping_max = 0.3
	mist.position = at + Vector3(0, 0.5, 0)
	mist.visibility_aabb = AABB(Vector3(-width, -2, -4), Vector3(width * 2.0, 14, 20))
	add_child(mist)
	# The roar, from the landing (where it's loudest).
	var ear := Node3D.new()
	ear.name = "Roar"
	add_child(ear)
	ear.position = at
	sound = SoundLife.loop(ear, "falls", clampf(linear_to_db(width / 8.0) * 0.5, -6.0, 4.0))


## The sheet: rows down the fall (UV.y 0 at the lip .. 1 landing), columns across, spreading a
## little as it falls; the throw curve x = v t, y = -g t² / 2.
func _sheet_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rows := clampi(int(height / 1.2), 8, 40)
	var cols := clampi(int(width / 1.0), 4, 24)
	var t_end := sqrt(2.0 * height / GRAVITY)
	var pts := []
	for j in rows + 1:
		var v := float(j) / rows
		var t := t_end * sqrt(v)    # rows even in drop, not time (it's long at the bottom)
		var row := []
		for i in cols + 1:
			var u := float(i) / cols
			var spread := 1.0 + 0.15 * v
			var bow := sin(u * PI) * 0.25 * (1.0 - v)    # the lip's water bulges out in the middle
			row.append([Vector3((u - 0.5) * width * spread, -0.5 * GRAVITY * t * t, LIP_SPEED * t + bow), Vector2(u, v)])
		pts.append(row)
	for j in rows:
		for i in cols:
			for c: Array in [[j, i], [j, i + 1], [j + 1, i + 1], [j, i], [j + 1, i + 1], [j + 1, i]]:
				var e: Array = pts[c[0]][c[1]]
				st.set_uv(e[1])
				st.add_vertex(e[0])
	st.generate_normals()
	return st.commit()


func _particles(n: String, amount: int, life: float, size: Vector2, alpha: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = n
	p.amount = maxi(amount, 4)
	p.lifetime = life
	p.preprocess = life
	p.randomness = 0.6
	p.visibility_range_end = 220.0
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	pm.scale_min = size.x
	pm.scale_max = size.y
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.2, 0.7, 1.0])
	fade.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, alpha), Color(1, 1, 1, alpha * 0.7), Color(1, 1, 1, 0)])
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	pm.color_ramp = ramp
	pm.angle_min = 0.0
	pm.angle_max = 360.0
	p.process_material = pm
	p.sorting_offset = 1.0
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color(0.92, 0.94, 0.95)
	mat.albedo_texture = Fx.soft_dot()
	mat.proximity_fade_enabled = true
	mat.proximity_fade_distance = 0.8
	mat.render_priority = 2
	quad.material = mat
	p.draw_pass_1 = quad
	return p
