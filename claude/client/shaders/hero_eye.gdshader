// Ojo "hero": globo con iris pintado (textura propia, A = brillos pintados), córnea con
// clearcoat y un poco de paralaje (el iris parece estar bajo una lente). look mueve la
// mirada (desplaza el iris), ko dibuja los ojos en X de dibujo animado.
shader_type spatial;
render_mode cull_back;

uniform sampler2D eye_tex : source_color, filter_linear_mipmap, repeat_disable;
uniform vec2 look = vec2(0.0);
uniform float parallax = 0.06;
uniform float highlight = 1.35;
uniform float ko = 0.0;
uniform float alpha : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	vec3 vt = vec3(dot(VIEW, TANGENT), dot(VIEW, BINORMAL), dot(VIEW, NORMAL));
	vec2 uv = UV - look * vec2(0.18, -0.14);
	vec2 puv = uv + vt.xy * parallax * vec2(1.0, -1.0);
	vec4 iris = texture(eye_tex, (puv - 0.5) * 1.0 + 0.5);
	vec4 hl = texture(eye_tex, UV);
	vec3 col = iris.rgb;
	if (ko > 0.5) {
		vec2 q = (UV - 0.5) * 2.0;
		float d = min(abs(q.x - q.y), abs(q.x + q.y)) / 1.4142;
		float x = (1.0 - smoothstep(0.10, 0.16, d)) * step(length(q), 0.62);
		col = mix(vec3(0.85, 0.86, 0.9), vec3(0.02, 0.02, 0.04), x);
	}
	ALBEDO = col;
	ROUGHNESS = 0.25;
	SPECULAR = 0.6;
	CLEARCOAT = 1.0;
	CLEARCOAT_ROUGHNESS = 0.04;
	EMISSION = vec3(1.0) * hl.a * highlight * (1.0 - ko);
	//ALPHA
}
