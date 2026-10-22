// Ojo de PlushAvatar3D (prototipo): cúpula brillante con iris marrón oscuro, pupila negra
// grande, borde claro y dos brillos; párpado del color del pelo para parpadear, rayita
// ∩ de gusto / ∪ de dormido y ojos en X. UV de cada ojo = disco 0..1 (centro 0,5).
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec4 iris_color : source_color = vec4(0.35, 0.18, 0.08, 1.0);
uniform vec4 lid_color : source_color = vec4(0.9, 0.5, 0.2, 1.0);
uniform vec4 line_color : source_color = vec4(0.12, 0.06, 0.04, 1.0);
uniform vec4 white_color : source_color = vec4(0.97, 0.95, 0.92, 1.0);
uniform float lid = 0.0;
uniform float arch = 1.0;
uniform float xeyes = 0.0;
uniform vec2 look = vec2(0.0);
uniform float alpha_v = 1.0;

float band(float d, float w, float aa) {
	return 1.0 - smoothstep(w - aa, w + aa, d);
}

void fragment() {
	vec2 p = vec2(UV.x * 2.0 - 1.0, 1.0 - UV.y * 2.0);
	float r = length(p);
	vec2 c = look + vec2(0.0, 0.04);
	float ri = length((p - c) * vec2(1.0, 0.98));
	// ojo de peluche: todo iris marrón casi negro (sin anillo blanco), algo más cálido
	// abajo, pupila grande y dos brillos grandes como en la referencia
	float lower = smoothstep(0.1, -0.85, p.y - c.y);
	vec3 col = mix(iris_color.rgb * 0.22, iris_color.rgb * 0.95, lower * smoothstep(0.95, 0.35, ri) );
	float pupil = 1.0 - smoothstep(0.5, 0.56, length((p - c * 1.1) * vec2(1.0, 0.93)));
	col = mix(col, vec3(0.012, 0.008, 0.01), pupil);
	// borde oscuro fino (sin esclerótica)
	col = mix(col, line_color.rgb * 0.5, smoothstep(0.88, 0.98, r));
	// esclerótica: solo una rayita clara abajo hacia fuera
	vec2 ws = p - vec2(-0.42, -0.78);
	float white = (1.0 - smoothstep(0.0, 0.02, abs(r - 0.9) - 0.035)) * smoothstep(0.5, 0.15, length(ws));
	col = mix(col, white_color.rgb * 0.92, white * 0.85);
	vec2 hc = p - c * 0.6;
	float hl = 1.0 - smoothstep(0.24, 0.27, length((hc - vec2(0.3, 0.33)) * vec2(1.0, 0.92)));
	float hl2 = 1.0 - smoothstep(0.1, 0.125, length(hc - vec2(-0.3, -0.3)));
	float h = max(hl, hl2 * 0.95);
	col = mix(col, vec3(1.0), h);
	float emit = h;
	float l = clamp(lid, 0.0, 1.0);
	float edge = 1.05 - 2.2 * l + 0.25 * p.x * p.x;
	float cover = smoothstep(edge - 0.03, edge + 0.03, p.y);
	emit *= 1.0 - cover;
	col = mix(col, lid_color.rgb, cover);
	float closed = smoothstep(0.82, 0.97, l);
	if (closed > 0.0) {
		col = mix(col, lid_color.rgb, closed);
		float ya = -0.1 + arch * 0.4 * (1.0 - p.x * p.x / 0.7);
		col = mix(col, line_color.rgb, band(abs(p.y - ya), 0.12, 0.03) * step(abs(p.x), 0.78) * closed);
		emit *= 1.0 - closed;
	}
	if (xeyes > 0.0) {
		col = mix(col, lid_color.rgb, xeyes);
		float x = max(band(abs(p.x - p.y) * 0.707, 0.11, 0.03), band(abs(p.x + p.y) * 0.707, 0.11, 0.03)) * step(r, 0.75);
		col = mix(col, line_color.rgb, x * xeyes);
		emit *= 1.0 - xeyes;
	}
	ALBEDO = col;
	EMISSION = vec3(emit * 0.6);
	float matte = max(cover, max(closed, xeyes));
	ROUGHNESS = mix(0.08, 0.85, matte);
	SPECULAR = mix(0.75, 0.2, matte);
	CLEARCOAT = 1.0 - matte;
	CLEARCOAT_ROUGHNESS = 0.06;
	//ALPHA
}
