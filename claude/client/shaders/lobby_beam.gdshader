// Haz de luz "volumétrico" falso: cono abierto aditivo, más denso en el centro (según
// se mira) y que se desvanece arriba y abajo, con un leve ondular de polvo.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform vec4 color : source_color = vec4(1.0, 0.85, 0.6, 1.0);
uniform float intensity = 0.22;
uniform float fade_top = 0.12;
uniform float fade_bottom = 0.75;

void fragment() {
	float f = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float h = UV.y;
	float a = pow(f, 1.6) * intensity;
	a *= smoothstep(0.0, fade_top, h) * (1.0 - smoothstep(fade_bottom, 1.0, h));
	a *= 0.88 + 0.12 * sin(TIME * 0.9 + h * 7.0 + UV.x * 18.0);
	ALBEDO = color.rgb;
	ALPHA = clamp(a, 0.0, 1.0);
}
