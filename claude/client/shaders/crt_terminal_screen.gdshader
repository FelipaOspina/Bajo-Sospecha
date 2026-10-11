shader_type canvas_item;

// Overlay CRT Shader para UI / Terminales en Godot 4
// Colocar este shader en un ColorRect sobre la vista de la terminal (Mouse Filter: IGNORE)
// Curvatura, recorte y viñeta se calculan sobre el propio rectángulo (UV), no sobre la ventana;
// TerminalFrame pasa rect_size para traducir la distorsión a coordenadas de pantalla.

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform vec2 rect_size = vec2(0.0);

group_uniforms Curvatura_Distorsion;
uniform float curvature : hint_range(0.0, 0.2, 0.005) = 0.035;
uniform float corner_softness : hint_range(0.0, 0.5, 0.01) = 0.05;

group_uniforms Lineas_Escaneo;
uniform float scanline_density : hint_range(100.0, 800.0, 10.0) = 320.0;
uniform float scanline_intensity : hint_range(0.0, 0.5, 0.01) = 0.18;
uniform float scanline_speed : hint_range(0.0, 5.0, 0.1) = 0.4;

group_uniforms Aberracion_Cromatica;
uniform float aberration_amount : hint_range(0.0, 0.02, 0.0005) = 0.0025;

group_uniforms Iluminacion_Vignette;
uniform float vignette_intensity : hint_range(0.0, 1.5, 0.05) = 0.55;
uniform float vignette_opacity : hint_range(0.0, 1.0, 0.05) = 0.65;
uniform float screen_brightness : hint_range(0.8, 1.5, 0.05) = 1.08;
uniform float flicker_intensity : hint_range(0.0, 0.05, 0.002) = 0.012;

group_uniforms Tinte_Fosforo;
uniform vec4 phosphor_tint : source_color = vec4(0.0, 0.95, 0.85, 1.0); // Cyan Neon Terminal
uniform float tint_mix : hint_range(0.0, 0.3, 0.01) = 0.08;

// Función de distorsión de barril (curvatura de cristal CRT)
vec2 curve_uv(vec2 uv) {
	vec2 delta = uv - 0.5;
	float delta2 = dot(delta, delta);
	vec2 curved = uv + delta * delta2 * curvature;
	return curved;
}

// Borde oscurecido simulando el bisel interno
float rounded_box(vec2 uv, vec2 size, float radius) {
	vec2 d = abs(uv - 0.5) - size + vec2(radius);
	return min(max(d.x, d.y), 0.0) + length(max(d, 0.0)) - radius;
}

void fragment() {
	vec2 uv = curve_uv(UV);
	vec2 to_screen = rect_size * SCREEN_PIXEL_SIZE; // 1 unidad de UV local en unidades de SCREEN_UV
	vec2 screen_uv = SCREEN_UV + (uv - UV) * to_screen;
	
	// Máscara para recortar fuera de los bordes curvados de la pantalla
	float box_dist = rounded_box(uv, vec2(0.495), corner_softness);
	float edge_cut = smoothstep(0.0, 0.005, -box_dist);

	// Aberración cromática (desfase RGB en los bordes)
	vec2 dir = normalize(uv - 0.5);
	float dist_center = length(uv - 0.5);
	vec2 offset = dir * (dist_center * aberration_amount) * to_screen;
	
	float r = texture(screen_texture, screen_uv + offset).r;
	float g = texture(screen_texture, screen_uv).g;
	float b = texture(screen_texture, screen_uv - offset).b;
	vec3 color = vec3(r, g, b);

	// Líneas de escaneo horizontales (Scanlines)
	float scanline = sin((screen_uv.y + TIME * scanline_speed * 0.05) * scanline_density * 3.14159);
	scanline = (scanline + 1.0) * 0.5;
	color -= scanline * scanline_intensity;

	// Parpadeo sutil de tubo de rayos catódicos (Flicker)
	float flicker = sin(TIME * 60.0) * cos(TIME * 30.0) * flicker_intensity;
	color += flicker;

	// Viñeta perimetral suave
	float vignette = uv.x * uv.y * (1.0 - uv.x) * (1.0 - uv.y);
	vignette = clamp(pow(16.0 * vignette, vignette_intensity), 0.0, 1.0);
	color = mix(color * vignette, color, 1.0 - vignette_opacity);

	// Tinte fosforescente corporativo
	color = mix(color, color * phosphor_tint.rgb, tint_mix);

	// Brillo global
	color *= screen_brightness;

	// Fuera del cristal curvado, negro (esquinas del tubo) en vez de dejar ver la imagen sin efecto
	COLOR = vec4(color * edge_cut, 1.0);
}
