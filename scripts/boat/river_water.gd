class_name RiverWater
extends MeshInstance3D
## The river: one big subdivided plane with a moving shader (slow swell, ripples drifting with the
## current, a muddy Nile green, glints). No physics: anything that falls through is the boat's
## problem (RiverBoat.watch puts people back on deck).
##   RiverWater.make(self, Vector2(400, 400), 0.0)

const SHADER := """
shader_type spatial;
render_mode cull_disabled;

uniform vec4 deep : source_color = vec4(0.10, 0.20, 0.18, 1.0);
uniform vec4 shallow : source_color = vec4(0.30, 0.38, 0.27, 1.0);
uniform vec2 flow = vec2(0.0, 0.6);
uniform float swell = 0.06;

varying vec3 wpos;

float waves(vec2 p, float t) {
	return sin(p.x * 0.35 + t * 1.3) * 0.5 + sin(p.y * 0.27 - t * 1.1) * 0.5
		+ sin((p.x + p.y) * 0.9 + t * 2.1) * 0.25;
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX.y += waves(wpos.xz, TIME) * swell;
}

void fragment() {
	vec2 p = wpos.xz - flow * TIME;
	float r = sin(p.x * 1.7 + sin(p.y * 0.6) * 2.0) * sin(p.y * 1.3 + TIME * 0.8)
		+ 0.5 * sin(p.x * 3.9 - p.y * 2.7 + TIME * 1.7);
	float e = 0.05;
	float dx = (sin((p.x + e) * 1.7 + sin(p.y * 0.6) * 2.0) * sin(p.y * 1.3 + TIME * 0.8)) - (sin(p.x * 1.7 + sin(p.y * 0.6) * 2.0) * sin(p.y * 1.3 + TIME * 0.8));
	float dz = (sin(p.x * 1.7 + sin((p.y + e) * 0.6) * 2.0) * sin((p.y + e) * 1.3 + TIME * 0.8)) - (sin(p.x * 1.7 + sin(p.y * 0.6) * 2.0) * sin(p.y * 1.3 + TIME * 0.8));
	vec3 n = normalize(vec3(-dx / e * 0.08, 1.0, -dz / e * 0.08));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	ALBEDO = mix(deep.rgb, shallow.rgb, clamp(0.5 + r * 0.18, 0.0, 1.0));
	ROUGHNESS = 0.12;
	SPECULAR = 0.6;
	METALLIC = 0.0;
}
"""


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
	return w
