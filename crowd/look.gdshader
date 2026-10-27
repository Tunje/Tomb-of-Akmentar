// A townsperson's clothes and skin (scripts/crowd_person.gd, CrowdPerson.dress): the stand-in
// bandit's baked texture recoloured by what each pixel is. Navy cloth takes the robe colour (its
// shading kept), with optional vertical stripes; the salmon skin patches take this person's skin
// tone; the red sash and the dark leather keep their own colours, a little warmed.
shader_type spatial;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap;
uniform bool has_normal = false;
uniform vec3 cloth : source_color = vec3(0.9, 0.88, 0.82);
uniform vec3 stripe : source_color = vec3(0.3, 0.35, 0.6);
uniform float stripes = 0.0;            // 0 none, 1 striped
uniform vec3 skin : source_color = vec3(0.7, 0.5, 0.38);
uniform float roughness_v = 0.85;

varying vec3 model_pos;

void vertex() {
	model_pos = VERTEX;
}

void fragment() {
	vec4 t = texture(albedo_tex, UV);
	vec3 c = t.rgb;
	float lum = dot(c, vec3(0.299, 0.587, 0.114));
	float warm = c.r - c.b;
	vec3 outc;
	if (warm > 0.12 && c.r > 0.28 && c.g > 0.14 && c.r < c.g * 2.4) {
		// Skin: this person's tone, the texture's light and shade.
		outc = skin * clamp(lum / 0.5, 0.45, 1.35);
	} else if (c.r > 0.35 && c.g < 0.2 && c.b < 0.2) {
		// The red sash: kept.
		outc = c;
	} else if (warm > 0.03 && lum < 0.22) {
		// Dark leather (belts, boots): kept, a touch warmer.
		outc = c * vec3(1.1, 1.0, 0.9);
	} else {
		// Cloth: the robe colour, shaded like the navy it replaces (its mid tone ~0.17).
		vec3 base = cloth;
		if (stripes > 0.5 && fract(model_pos.x * 9.0) < 0.28) {
			base = stripe;
		}
		outc = base * clamp(lum / 0.17, 0.35, 1.25);
	}
	ALBEDO = outc;
	ROUGHNESS = roughness_v;
	if (has_normal) {
		NORMAL_MAP = texture(normal_tex, UV).rgb;
	}
}
