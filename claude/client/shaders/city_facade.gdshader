// Fachada de oficinas de noche (cara +Z): rejilla de ventanas en coordenadas del
// mundo, encendidas al azar (cálidas y alguna fría). Sin texturas.
shader_type spatial;

uniform float lit : hint_range(0.0, 1.0) = 0.45;
uniform vec2 cell = vec2(1.1, 2.4);   // separación de ventanas (m): ancho, alto de planta
uniform float seed = 0.0;
uniform vec3 wall_color : source_color = vec3(0.07, 0.08, 0.11);

varying vec3 wpos;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = vec2(wpos.x, wpos.y) / cell + seed;
	vec2 id = floor(p);
	vec2 f = fract(p);
	float win = step(0.16, f.x) * step(f.x, 0.84) * step(0.22, f.y) * step(f.y, 0.78);
	float on = step(1.0 - lit, hash(id));
	vec3 tint = mix(vec3(1.0, 0.74, 0.42), vec3(0.55, 0.8, 1.0), step(0.82, hash(id + 7.3)));
	ALBEDO = mix(wall_color, vec3(0.04, 0.05, 0.08), win);
	ROUGHNESS = mix(0.7, 0.15, win);
	METALLIC = 0.2 * win;
	EMISSION = win * on * tint * (0.3 + 0.7 * hash(id + 3.1)) * 1.1;
}
