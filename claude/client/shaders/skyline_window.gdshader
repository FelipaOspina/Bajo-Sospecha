// Ventanal de la oficina: cielo nocturno y siluetas de rascacielos con ventanas
// encendidas, en coordenadas del mundo. Sin texturas.
shader_type spatial;

uniform float base_y = 0.55;   // altura del alféizar (m)
uniform float glass_h = 2.2;   // alto del cristal (m)

varying vec3 wpos;

float hash(float x) {
	return fract(sin(x * 91.7) * 43758.5453);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float t = clamp((wpos.y - base_y) / glass_h, 0.0, 1.0);
	vec3 sky = mix(vec3(0.03, 0.04, 0.1), vec3(0.11, 0.07, 0.2), t);
	float col_id = floor(wpos.x * 2.5);
	float top = 0.25 + 0.6 * hash(col_id);
	float building = step(t, top);
	vec2 w = vec2(fract(wpos.x * 10.0), fract(wpos.y * 9.0));
	float win = building * step(0.3, w.x) * step(w.x, 0.7) * step(0.3, w.y) * step(w.y, 0.7)
		* step(0.62, hash(floor(wpos.x * 10.0) * 3.7 + floor(wpos.y * 9.0) * 11.3));
	ALBEDO = vec3(0.0);
	ROUGHNESS = 0.08;
	METALLIC = 0.0;
	SPECULAR = 0.6;
	EMISSION = mix(sky, vec3(0.025, 0.03, 0.05), building) + win * vec3(1.0, 0.78, 0.45) * 0.9;
}
