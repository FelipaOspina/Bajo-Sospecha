// Fachadas de la ciudad que se ve desde el ascensor: rejilla de ventanas en coordenadas
// del mundo en las cuatro caras (x o z según la normal), encendidas al azar (cálidas y
// alguna fría); las azoteas, lisas y oscuras. Sin texturas: funciona igual en
// Forward+ y en gl_compatibility.
shader_type spatial;

uniform float lit : hint_range(0.0, 1.0) = 0.45;
uniform vec2 cell = vec2(1.3, 3.2);   // separación de ventanas (m): ancho, alto de planta
uniform float seed = 0.0;
uniform vec3 wall_color : source_color = vec3(0.06, 0.07, 0.1);
uniform float glow = 1.15;

varying vec3 wpos;
varying vec3 wnorm;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float roof = step(0.6, wnorm.y);
	float side = step(abs(wnorm.z), abs(wnorm.x));
	vec2 p = vec2(mix(wpos.x, wpos.z, side), wpos.y) / cell + seed + side * 17.0;
	vec2 id = floor(p);
	vec2 f = fract(p);
	float win = step(0.16, f.x) * step(f.x, 0.84) * step(0.24, f.y) * step(f.y, 0.8) * (1.0 - roof);
	float on = step(1.0 - lit, hash(id));
	vec3 tint = mix(vec3(1.0, 0.72, 0.4), vec3(0.55, 0.8, 1.0), step(0.84, hash(id + 7.3)));
	ALBEDO = mix(wall_color, vec3(0.03, 0.04, 0.07), win);
	ROUGHNESS = mix(0.75, 0.12, win);
	METALLIC = 0.25 * win;
	EMISSION = win * on * tint * (0.3 + 0.7 * hash(id + 3.1)) * glow;
}
