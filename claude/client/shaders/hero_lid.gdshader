// Párpado de los personajes "hero" (casquete sobre el ojo, animado con shape keys).
// UV.y: 0 = parte escondida dentro de la cabeza, 1 = canto. El canto lleva la línea de
// pestañas; el resto, el color de la piel de alrededor del ojo.
shader_type spatial;
render_mode cull_disabled;

uniform vec3 skin : source_color = vec3(0.96, 0.94, 0.91);
uniform vec3 lash : source_color = vec3(0.04, 0.05, 0.1);
uniform float lash_width = 0.16;
uniform float alpha : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	float vy = 1.0 - UV.y;   // glTF invierte la V
	float e = smoothstep(1.0 - lash_width, 1.0 - lash_width * 0.55, vy);
	float side = abs(UV.x - 0.5) * 2.0;
	e *= 1.0 - smoothstep(0.82, 1.0, side) * 0.7;
	vec3 c = mix(skin * (0.94 + 0.06 * vy), lash, e);
	ALBEDO = c;
	ROUGHNESS = mix(0.85, 0.5, e);
	SPECULAR = 0.2;
	//ALPHA
}
