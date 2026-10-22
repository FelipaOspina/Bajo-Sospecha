// La calle vista desde el piso 14: manzanas, asfalto, aceras, raya amarilla
// discontinua y farolas, todo en coordenadas del mundo. Sin texturas.
shader_type spatial;

uniform float block = 34.0;   // manzana + calle (m)
uniform float road = 9.0;     // ancho de la calle (m)
uniform vec2 origin = vec2(0.0);

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 q = mod(wpos.xz - origin - vec2(block * 0.5) + vec2(road * 0.5), vec2(block));
	float on_road_x = step(q.x, road);
	float on_road_z = step(q.y, road);
	float on_road = max(on_road_x, on_road_z);
	vec3 col = vec3(0.1, 0.15, 0.11);                       // patios y jardines
	vec3 asphalt = vec3(0.13, 0.135, 0.15);
	float walk = (1.0 - on_road) * (1.0 - step(1.6, q.x - road) * step(1.6, q.y - road)
		* step(q.x, block - 1.6) * step(q.y, block - 1.6));
	col = mix(col, vec3(0.32, 0.33, 0.36), walk);           // aceras
	col = mix(col, asphalt, on_road);
	// Raya amarilla discontinua en el centro de cada calle.
	float dash_x = on_road_x * (1.0 - on_road_z) * step(abs(q.x - road * 0.5), 0.12) * step(0.5, fract(wpos.z / 4.0));
	float dash_z = on_road_z * (1.0 - on_road_x) * step(abs(q.y - road * 0.5), 0.12) * step(0.5, fract(wpos.x / 4.0));
	col = mix(col, vec3(0.75, 0.6, 0.18), max(dash_x, dash_z));
	ALBEDO = col;
	ROUGHNESS = 0.8;
	// Farolas: charcos de luz cálida en el borde de la acera, cada 8 m.
	float lx = (1.0 - on_road_z) * smoothstep(1.4, 0.0, length(vec2(q.x - road - 0.6, mod(wpos.z, 8.0) - 4.0)));
	float lz = (1.0 - on_road_x) * smoothstep(1.4, 0.0, length(vec2(q.y - road - 0.6, mod(wpos.x, 8.0) - 4.0)));
	EMISSION = vec3(1.0, 0.68, 0.32) * max(lx, lz) * 2.0;
}
