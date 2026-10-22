// Anillo de luz suave en el suelo (plataformas de la sala de espera): aro nítido con
// halo, relleno tenue hacia el centro, discontinuo opcional y latido. Aditivo y sin
// luces (se ve igual en gl_compatibility, sin depender del glow).
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform vec4 color : source_color = vec4(1.0, 0.8, 0.4, 1.0);
uniform float energy = 1.2;
uniform float radius = 0.78;
uniform float width = 0.035;
uniform float halo = 0.16;
uniform float fill = 0.10;
uniform float dashes = 0.0;
uniform float spin = 0.0;
uniform float pulse = 0.0;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float d = length(p);
	float e = abs(d - radius);
	float ring = 1.0 - smoothstep(width * 0.5, width, e);
	float glow = exp(-(e * e) / (halo * halo)) * 0.45;
	float inner = fill * (1.0 - smoothstep(0.0, radius, d)) ;
	float a = ring + glow + inner;
	if (dashes > 0.0) {
		float ang = atan(p.y, p.x) / 6.2831853 + TIME * spin;
		a *= smoothstep(0.3, 0.42, fract(ang * dashes)) * (1.0 - smoothstep(0.78, 0.9, fract(ang * dashes)));
	}
	a *= 1.0 + pulse * sin(TIME * 2.6);
	a *= 1.0 - smoothstep(0.92, 1.0, d);
	ALBEDO = color.rgb * energy;
	ALPHA = clamp(a * color.a, 0.0, 1.0);
}
