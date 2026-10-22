// Material "hero" de los personajes de calidad (HeroAvatar3D): mapas horneados en Blender
// (albedo, normal, ORM = oclusión / rugosidad / pelusa) + luz propia blanda tipo peluche:
//  - difusa con "wrap" (el terminador se suaviza como en el fieltro y la arcilla),
//  - brillo de terciopelo (sheen) en los bordes donde hay pelusa o tela,
//  - especular GGX controlado (piel de zapato, botones, pico) sin reflejos duros.
// Funciona en Forward+, Mobile y Compatibility.
shader_type spatial;
render_mode cull_back, depth_draw_opaque;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D orm_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_disable;
uniform float normal_strength = 1.0;
// recolor (ropa): las prendas se pintan en gris neutro (0.5) y el alfa del albedo (0.25..1) marca
// dónde se tiñen; el color final es albedo / 0.5 * tint_color (sombras y AO se conservan)
uniform vec3 tint_color : source_color = vec3(0.5);
uniform float tint_on = 0.0;
uniform float wrap : hint_range(0.0, 1.0) = 0.35;
uniform float sheen : hint_range(0.0, 2.0) = 0.5;
uniform vec3 sheen_tint : source_color = vec3(0.85, 0.9, 1.0);
uniform float spec_amount : hint_range(0.0, 2.0) = 0.5;
uniform float rough_mul = 1.0;
uniform float rough_add = 0.0;
uniform float ao_light = 0.35;
uniform float subsurface : hint_range(0.0, 1.0) = 0.0;
uniform vec3 subsurface_tint : source_color = vec3(1.0, 0.45, 0.35);
uniform float alpha : hint_range(0.0, 1.0) = 1.0;
// realce de contorno (fresnel) para que la silueta se lea con poca luz (noche, vista cenital)
uniform float rim_amount : hint_range(0.0, 1.0) = 0.0;
uniform vec3 rim_color : source_color = vec3(0.45, 0.55, 0.95);
uniform float rim_power = 2.5;

varying float v_fuzz;

void fragment() {
	vec4 a4 = texture(albedo_tex, UV);
	vec3 orm = texture(orm_tex, UV).rgb;
	float tint_mask = clamp((a4.a - 0.25) / 0.75, 0.0, 1.0);   // alfa = 0.25 + 0.75 * máscara
	ALBEDO = mix(a4.rgb, clamp(a4.rgb * 2.0 * tint_color, 0.0, 1.0), tint_mask * tint_on);
	NORMAL_MAP = texture(normal_tex, UV).rgb;
	NORMAL_MAP_DEPTH = normal_strength;
	ROUGHNESS = clamp(orm.g * rough_mul + rough_add, 0.04, 1.0);
	AO = orm.r;
	AO_LIGHT_AFFECT = ao_light;
	SPECULAR = 0.5;
	v_fuzz = orm.b;
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), rim_power);
	EMISSION = rim_color * rim_amount * fres * (0.5 + 0.5 * orm.r);
	//ALPHA
}

float d_ggx(float ndh, float r) {
	float a = r * r;
	float a2 = a * a;
	float d = ndh * ndh * (a2 - 1.0) + 1.0;
	return a2 / (PI * d * d);
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float ndv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float w = wrap * (0.4 + 0.6 * v_fuzz);
	float diff = clamp((ndl + w) / ((1.0 + w) * (1.0 + w)), 0.0, 1.0);
	vec3 lc = LIGHT_COLOR * ATTENUATION / PI;
	DIFFUSE_LIGHT += diff * lc;
	// luz que "atraviesa" el borde (piel/pico): tono cálido en el terminador
	float sss = subsurface * clamp(1.0 - abs(ndl) * 1.6, 0.0, 1.0) * clamp(ndl + 0.4, 0.0, 1.0);
	DIFFUSE_LIGHT += sss * subsurface_tint * lc * 0.6;
	// terciopelo: brillo rasante en los bordes (pelusa y tela)
	float fr = pow(1.0 - ndv, 3.0);
	float sh = sheen * v_fuzz * fr * clamp(ndl * 0.6 + 0.4, 0.0, 1.0);
	SPECULAR_LIGHT += sh * sheen_tint * lc * 0.9;
	// especular GGX con Fresnel suave
	vec3 H = normalize(LIGHT + VIEW);
	float ndh = clamp(dot(NORMAL, H), 0.0, 1.0);
	float r = clamp(ROUGHNESS, 0.06, 1.0);
	float D = d_ggx(ndh, r);
	float k = (r + 1.0) * (r + 1.0) / 8.0;
	float nl = clamp(ndl, 0.0, 1.0);
	float vis = 1.0 / ((ndv * (1.0 - k) + k) * (nl * (1.0 - k) + k) * 4.0);
	float F = 0.04 + 0.96 * pow(1.0 - clamp(dot(H, VIEW), 0.0, 1.0), 5.0);
	SPECULAR_LIGHT += spec_amount * D * vis * F * nl * LIGHT_COLOR * ATTENUATION;
}
