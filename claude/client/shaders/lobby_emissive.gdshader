// Superficie que emite su textura (ventanal con la ciudad, pantallas, fotos iluminadas).
// StandardMaterial3D con emission_texture sale blanco en gl_compatibility: por eso shader.
shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled, fog_disabled;

uniform sampler2D tex : source_color, filter_linear_mipmap;
uniform vec4 tint : source_color = vec4(1.0);
uniform float energy = 1.0;
uniform float scan = 0.0;

void fragment() {
	vec3 c = texture(tex, UV).rgb * tint.rgb * energy;
	if (scan > 0.0) {
		c *= 1.0 - scan * 0.5 * (0.5 + 0.5 * sin(UV.y * 240.0 + TIME * 4.0));
	}
	ALBEDO = c;
}
