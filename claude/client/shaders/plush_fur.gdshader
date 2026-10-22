// Felpa de PlushAvatar3D (prototipo): pelo y tela de los muñecos de peluche.
// Colores por máscaras de vértice horneadas en el GLB (R = pelo claro, G = marca oscura,
// B = rosa / rubor; A = oclusión ambiental horneada). La pelusa se hace con una normal
// de ruido fino en espacio local (sin texturas ni UV), brillo de terciopelo en el
// contorno (sheen) y un rim suave. PlushAvatar3D crea la variante translúcida cambiando
// la línea //ALPHA.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec4 base_color : source_color = vec4(1.0);
uniform vec4 light_color : source_color = vec4(1.0);
uniform vec4 mark_color : source_color = vec4(0.1, 0.08, 0.08, 1.0);
uniform vec4 pink_color : source_color = vec4(1.0, 0.6, 0.65, 1.0);
uniform float pink_amt = 1.0;
uniform float ao_amt = 1.0;
uniform float roughness_v = 0.92;
uniform float specular_v = 0.2;
uniform float sheen = 0.5;
uniform vec4 sheen_tint : source_color = vec4(1.0);
uniform float fuzz = 0.35;        // fuerza de la normal de pelusa
uniform float fuzz_freq = 260.0;  // frecuencia de la pelusa (1/m)
uniform float grain = 0.06;       // variación de color tipo fieltro
uniform float grain_freq = 70.0;
uniform float rim_v = 0.25;
uniform float alpha_v = 1.0;
uniform sampler2D mask_tex : hint_default_black, filter_linear_mipmap;
uniform float use_tex = 0.0;    // 1 = máscaras de color desde textura (cabeza)

varying vec3 lp;

void vertex() {
	lp = VERTEX;
}

float hash3(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.1, 0.2, 0.3));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float vnoise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash3(i), hash3(i + vec3(1, 0, 0)), f.x), mix(hash3(i + vec3(0, 1, 0)), hash3(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash3(i + vec3(0, 0, 1)), hash3(i + vec3(1, 0, 1)), f.x), mix(hash3(i + vec3(0, 1, 1)), hash3(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void fragment() {
	vec3 col = base_color.rgb;
	vec3 mk = COLOR.rgb;
	if (use_tex > 0.5) {
		mk = texture(mask_tex, UV).rgb;
	}
	col = mix(col, light_color.rgb, mk.r);
	col = mix(col, mark_color.rgb, mk.g);
	col = mix(col, pink_color.rgb, mk.b * pink_amt);
	float ao = mix(1.0, COLOR.a, ao_amt);
	// pelusa: gradiente de ruido -> normal perturbada
	vec3 q = lp * fuzz_freq;
	float n0 = vnoise(q);
	float e = 0.35;
	vec3 g = vec3(vnoise(q + vec3(e, 0, 0)) - n0, vnoise(q + vec3(0, e, 0)) - n0, vnoise(q + vec3(0, 0, e)) - n0) / e;
	float n1 = vnoise(q * 0.37 + 7.0);
	vec3 gv = (VIEW_MATRIX * (MODEL_MATRIX * vec4(g, 0.0))).xyz;
	NORMAL = normalize(NORMAL - gv * fuzz * 0.25);
	float gr = vnoise(lp * grain_freq) * 0.6 + n1 * 0.4;
	col *= 1.0 + (gr - 0.5) * 2.0 * grain;
	float fr = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.5);
	col = col * (1.0 + sheen * fr * 0.9 * sheen_tint.rgb) + sheen_tint.rgb * sheen * fr * 0.04;
	ALBEDO = col * mix(1.0, ao, 0.4);
	AO = ao;
	AO_LIGHT_AFFECT = 0.35;
	ROUGHNESS = roughness_v;
	SPECULAR = specular_v;
	RIM = rim_v;
	RIM_TINT = 0.7;
	//ALPHA
}
