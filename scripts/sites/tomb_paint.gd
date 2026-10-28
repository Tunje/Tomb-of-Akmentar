class_name TombPaint
extends RefCounted
## The tomb's paint (gameplan/reference/tomb_look ref_1, ref_6: painted reliefs, not bare sandstone),
## all in shaders on the kit that's there, no new geometry but the ceilings' quads:
## - Carved walls, friezes and pillars: the carving's detail (where the texture strays from its
##   own blurred self, and the normal map's edges) painted lapis, ochre red, malachite and gold,
##   glyph by glyph on the walls (each block its own mix), in bands on the friezes and up the
##   columns; faded and flaking with age, dustier low on the walls.
## - Star ceilings, deep blue with gold stars, over the halls (cells inside a 3 x 3 of open floor:
##   not the corridors, not the shaft) and the royal tomb.
## Each level is richer than the one above (RICH): the royal tomb at the bottom the brightest.
##   TombPaint.painted(mesh, "wall" | "frieze" | "pillar")  -> the kit mesh with its carved face painted
##   TombPaint.ceilings(level)                             -> adds the star ceilings
## Off with --no-paint (the before, to compare).

## Per level (0 at the top .. 4 the royal tomb): how much of the paint has lasted.
const RICH := [0.35, 0.5, 0.62, 0.78, 1.0]

const CARVED := """
shader_type spatial;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float has_normal = 1.0;
uniform float roughness = 0.9;
uniform float metallic = 0.0;
uniform sampler2D rough_tex : hint_roughness_g, filter_linear_mipmap, repeat_enable;
uniform sampler2D metal_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec4 rough_ch = vec4(0.0);       // which channel (all 0: no texture, the value alone)
uniform vec4 metal_ch = vec4(0.0);
uniform float rich[5];
uniform float top = -8.0;
uniform float deck_h = 8.0;
uniform vec2 cells = vec2(10.0, 14.0);   // glyph-sized cells across the texture (walls)
uniform int mode = 0;                    // 0 wall (glyph by glyph), 1 frieze (bands), 2 pillar (bands up it)
uniform float on = 1.0;
varying vec3 wpos;
varying float seed;

const vec3 LAPIS = vec3(0.09, 0.2, 0.5);
const vec3 OCHRE = vec3(0.6, 0.19, 0.09);
const vec3 MALACHITE = vec3(0.1, 0.4, 0.28);
const vec3 GOLD = vec3(0.82, 0.6, 0.16);
const vec3 DUST = vec3(0.5, 0.42, 0.32);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}
// A palette pick: lapis most, then ochre, malachite, and gold the rarest.
vec3 pal(float h, out float gold) {
	gold = 0.0;
	if (h < 0.36) return LAPIS;
	if (h < 0.62) return OCHRE;
	if (h < 0.86) return MALACHITE;
	gold = 1.0;
	return GOLD;
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 o = MODEL_MATRIX[3].xyz;   // each block / column its own mix
	seed = hash(o.xz * 0.37 + vec2(o.y * 0.11, 0.0));
}

void fragment() {
	vec3 tex = texture(albedo_tex, UV).rgb;
	vec3 nrm = texture(normal_tex, UV).rgb;
	float lum = dot(tex, vec3(0.3, 0.59, 0.11));
	// The carving: where the texture strays from its blurred self, and the normal map's edges.
	vec3 blur = textureLod(albedo_tex, UV, 5.0).rgb;
	float stray = smoothstep(0.08, 0.22, length(tex - blur));
	float edge = has_normal * smoothstep(0.12, 0.35, length(nrm.xy * 2.0 - 1.0));
	float carved = clamp(max(stray, edge * 0.8), 0.0, 1.0);
	// Which colour: per glyph cell on a wall, per band on a frieze or up a column.
	float h;
	if (mode == 0) {
		h = hash(floor(UV * cells) + seed * 17.0);
	} else if (mode == 1) {
		h = fract(floor(UV.y * 5.0) * 0.27 + floor(UV.x * 12.0) * 0.5 * step(0.5, fract(UV.y * 2.5)) + seed * 0.3);
	} else {
		h = fract(floor(wpos.y / 0.55) * 0.31 + seed * 0.5);
	}
	float gold;
	vec3 colour = pal(h, gold);
	int deck = int(clamp(floor((top - wpos.y + deck_h - 0.1) / deck_h), 0.0, 4.0));   // (anywhere floor to ceiling)
	float r = rich[deck];
	float floor_y = top - float(deck) * deck_h;
	// Age: flaked in patches, dust settled low on the walls.
	float flake = smoothstep(0.25, 0.7, noise(UV * vec2(24.0, 30.0) + seed * 9.0)) * 0.6 + 0.4;
	float low = 1.0 - smoothstep(0.2, 2.0, wpos.y - floor_y);
	// Already painted in the texture (its hue off the stone's): boosted below, not painted over (a
	// blue laid on a red glyph only made mud).
	float blum = dot(blur, vec3(0.3, 0.59, 0.11));
	float own = smoothstep(0.04, 0.12, length((tex - vec3(lum)) - (blur - vec3(blum)) * (lum / max(blum, 0.01))));
	// Only the figures (darker than the stone round them: the carved glyphs), not the pale ground
	// between them, which lapis under torchlight could only darken.
	float figure = smoothstep(0.01, 0.08, blum - lum);
	float paint = carved * figure * (1.0 - own) * r * flake * (1.0 - low * 0.6) * on;
	// The texture's own paint (faint, faded) brought up, then the palette laid on at the stone's own
	// brightness: the relief's shading reads through, and the walls don't go darker for it (lapis
	// under torchlight would read as black at its true value).
	// (How the glyphs differ from the stone round them, boosted: their paint and lines, not the
	// stone's own tan, which only went redder and darker under the torches.)
	vec3 base = clamp(blur + (tex - blur) * (1.0 + 2.0 * r * flake * (1.0 - low * 0.6) * on), 0.0, 1.0);
	// (Matched under warm light, as the torches see it: a lapis glyph as bright as the stone round
	// it in their orange light, or it reads black.)
	vec3 warm = vec3(0.62, 0.33, 0.05);
	vec3 painted = colour * clamp(dot(tex, warm) * 1.35 / dot(colour, warm), 0.0, 3.0);
	painted = painted / max(1.0, max(painted.r, max(painted.g, painted.b)));
	vec3 a = mix(base, painted, paint * 0.85);
	a = mix(a, DUST * (0.7 + lum * 0.6), low * 0.45 * on);
	ALBEDO = a;
	if (has_normal > 0.5) {
		NORMAL_MAP = nrm;
	}
	float leaf = gold * paint;
	float rough = roughness * (dot(rough_ch, vec4(1.0)) > 0.0 ? dot(texture(rough_tex, UV), rough_ch) : 1.0);
	float metal = metallic * (dot(metal_ch, vec4(1.0)) > 0.0 ? dot(texture(metal_tex, UV), metal_ch) : 1.0);
	// (Paint isn't metal: where it's on, the stone's own sheen gives way, but for the gold leaf.)
	METALLIC = mix(metal, leaf * 0.55, clamp(paint * 1.5, 0.0, 1.0));
	ROUGHNESS = mix(mix(rough, 0.85, clamp(paint * 1.5, 0.0, 1.0)), 0.42, leaf);
	SPECULAR = 0.5;
}
"""

const STARS := """
shader_type spatial;
render_mode cull_disabled;
uniform float rich[5];
uniform float top = -8.0;
uniform float deck_h = 8.0;
const vec3 LAPIS = vec3(0.05, 0.11, 0.3);
const vec3 GOLD = vec3(0.85, 0.63, 0.2);
const vec3 STONE = vec3(0.42, 0.34, 0.24);
varying vec3 wpos;
float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	int deck = int(clamp(floor((top - wpos.y + 7.5) / deck_h), 0.0, 4.0));
	float r = rich[deck];
	// Stars on a staggered grid, five-pointed, each a little off its place.
	vec2 p = wpos.xz / 0.55;
	p.x += 0.5 * step(1.0, mod(floor(p.y), 2.0));
	vec2 cell = floor(p);
	vec2 q = fract(p) - 0.5 + (vec2(hash(cell), hash(cell + 7.1)) - 0.5) * 0.25;
	float a = atan(q.y, q.x) + hash(cell + 3.3) * 6.283;
	float star = 1.0 - smoothstep(0.0, 0.02, length(q) - 0.17 * (0.5 + 0.5 * cos(a * 5.0)) - 0.02);
	// Age: the blue flaked off to the stone in patches (more of it on the upper levels).
	float worn = smoothstep(0.2, 0.55, noise(wpos.xz * 0.35) * 0.7 + noise(wpos.xz * 2.3) * 0.3 + (r - 0.6) * 0.8);
	vec3 blue = LAPIS * (0.85 + 0.3 * noise(wpos.xz * 1.3));
	vec3 col = mix(blue, GOLD, star);
	float kept = worn * (0.45 + 0.55 * r);
	ALBEDO = mix(STONE * (0.8 + 0.3 * noise(wpos.xz * 3.0)), col, kept);
	METALLIC = star * kept * 0.5;
	ROUGHNESS = mix(0.9, 0.45, star * kept);
}
"""

static var _mats := {}


static func enabled() -> bool:
	return not "--no-paint" in OS.get_cmdline_user_args()


## The kit mesh with its textured (carved) surface painted: a copy, shared per mesh (the plain
## sides keep their own material). Null when it has no textured surface (then leave it be).
static func painted(mesh: Mesh, kind := "wall") -> Mesh:
	if not mesh is ArrayMesh:
		return mesh
	var key := "%d_%s" % [mesh.get_instance_id(), kind]
	if _mats.has(key):
		return _mats[key]
	var out := (mesh as ArrayMesh).duplicate() as ArrayMesh
	var done := false
	for i in out.get_surface_count():
		var src := out.surface_get_material(i) as BaseMaterial3D
		if src and src.albedo_texture:
			out.surface_set_material(i, _material(src, kind))
			done = true
	_mats[key] = out if done else mesh
	return _mats[key]


static func _material(src: BaseMaterial3D, kind: String) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = CARVED
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("albedo_tex", src.albedo_texture)
	if src.normal_enabled and src.normal_texture:
		m.set_shader_parameter("normal_tex", src.normal_texture)
	else:
		m.set_shader_parameter("has_normal", 0.0)
	m.set_shader_parameter("roughness", src.roughness)
	m.set_shader_parameter("metallic", src.metallic)
	if src.roughness_texture:
		m.set_shader_parameter("rough_tex", src.roughness_texture)
		m.set_shader_parameter("rough_ch", _channel(src.roughness_texture_channel))
	if src.metallic_texture:
		m.set_shader_parameter("metal_tex", src.metallic_texture)
		m.set_shader_parameter("metal_ch", _channel(src.metallic_texture_channel))
	m.set_shader_parameter("rich", PackedFloat32Array(RICH))
	m.set_shader_parameter("top", AkmentarBelow.TOP)
	m.set_shader_parameter("deck_h", AkmentarBelow.DECK_H)
	m.set_shader_parameter("mode", {"wall": 0, "frieze": 1, "pillar": 2}.get(kind, 0))
	return m


static func _channel(c: int) -> Vector4:
	match c:
		BaseMaterial3D.TEXTURE_CHANNEL_RED:
			return Vector4(1, 0, 0, 0)
		BaseMaterial3D.TEXTURE_CHANNEL_GREEN:
			return Vector4(0, 1, 0, 0)
		BaseMaterial3D.TEXTURE_CHANNEL_BLUE:
			return Vector4(0, 0, 1, 0)
		BaseMaterial3D.TEXTURE_CHANNEL_ALPHA:
			return Vector4(0, 0, 0, 1)
	return Vector4(0.333, 0.333, 0.333, 0)


## The star ceilings: per level, a quad per hall cell just under the ceiling, in one mesh.
static func ceilings(level: AkmentarBelow) -> int:
	var sh := Shader.new()
	sh.code = STARS
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("rich", PackedFloat32Array(RICH))
	m.set_shader_parameter("top", AkmentarBelow.TOP)
	m.set_shader_parameter("deck_h", AkmentarBelow.DECK_H)
	var n := 0
	var half := Level.CELL * 0.5
	for k in AkmentarBelow.DECKS:
		var hall := {}
		for r in AkmentarBelow.H - 2:
			for c in AkmentarBelow.W - 2:
				var open := true
				for dr in 3:
					for dc in 3:
						open = open and _under_roof(level.dch(k, r + dr, c + dc)) and (k == 0 or level.dch(k - 1, r + dr, c + dc) != "O")
				if open:
					for dr in 3:
						for dc in 3:
							hall[Vector2i(c + dc, r + dr)] = true
		if hall.is_empty():
			continue
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		st.set_normal(Vector3.DOWN)
		var y := AkmentarBelow.deck_y(k) + AkmentarBelow.ROOM_H - 0.02
		for cell: Vector2i in hall:
			var at := level.dcell(k, cell.y, cell.x)
			var a := Vector3(at.x - half, y, at.z - half)
			var b := Vector3(at.x + half, y, at.z - half)
			var c2 := Vector3(at.x + half, y, at.z + half)
			var d := Vector3(at.x - half, y, at.z + half)
			for v: Vector3 in [a, c2, b, a, d, c2]:
				st.add_vertex(v)
			n += 1
		var mi := MeshInstance3D.new()
		mi.name = "StarCeiling_%d" % k
		mi.mesh = st.commit()
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		level.add_child(mi)
	return n


## A cell whose ceiling is a painted one: open floor of a room (not rock, the shaft, the open
## stairwells or the sky over level 0's stairs); and the level above has no hole over it.
static func _under_roof(ch: String) -> bool:
	return not AkmentarBelow._rock(ch) and not ch in ["O", "D", "s", "="]
