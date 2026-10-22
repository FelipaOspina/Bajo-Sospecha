// Halo suave (sprite aditivo con caída radial): resplandor de neones, lámparas y focos.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform vec4 color : source_color = vec4(1.0);
uniform float energy = 0.6;
uniform float flicker = 0.0;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float d = length(p);
	float a = pow(max(1.0 - d, 0.0), 2.2);
	a *= 1.0 - flicker * 0.5 * step(0.93, fract(sin(floor(TIME * 9.0)) * 43758.5));
	ALBEDO = color.rgb * energy;
	ALPHA = clamp(a * color.a, 0.0, 1.0);
}
