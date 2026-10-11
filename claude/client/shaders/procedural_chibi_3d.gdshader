shader_type canvas_item;
// Volumen "de vinilo satinado" para las piezas del chibi procedural (ProceduralChibiAvatar).
// Cada pieza es una elipse plana y el shader le inventa una normal de esfera para darle:
//  - difusa envolvente (wrap): sombras suaves, como plástico satinado y no como una bola dura;
//  - luz ambiental de oficina: fría desde arriba (fluorescentes) y cálida rebotada desde el suelo;
//  - oclusión en la parte de abajo de cada pieza: separa cabeza, cuerpo y brazos;
//  - brillo especular limpio (mancha de borde nítido) y un brillo ancho y tenue;
//  - luz de contorno sutil desde arriba a la derecha.
// Hay tres materiales con este shader (pelaje, tela y brillante); el color va en el Polygon2D.
//
// La pieza debe traer UV de 0 a 1 sobre su caja (un Polygon2D solo pasa UV al shader
// si tiene textura: el script le pone una blanca de 1×1 y su array uv).
// Compatible con los renderizadores Compatibility (móviles/web) y Forward+.

uniform vec4 base_color : source_color = vec4(1.0);              // tinte extra (blanco = el color de la pieza)
uniform vec3 light_direction = vec3(-0.45, -0.65, 0.75);         // arriba a la izquierda, hacia la cámara
uniform vec4 sky_color : source_color = vec4(0.80, 0.87, 1.0, 1.0);    // ambiente frío (techo de oficina)
uniform vec4 ground_color : source_color = vec4(0.62, 0.50, 0.44, 1.0); // rebote cálido del suelo
uniform float ambient : hint_range(0.0, 1.0) = 0.42;
uniform float diffuse_strength : hint_range(0.0, 1.5) = 0.70;
uniform float wrap : hint_range(0.0, 1.0) = 0.45;
uniform float occlusion : hint_range(0.0, 1.0) = 0.25;
uniform float glossiness : hint_range(1.0, 128.0) = 32.0;
uniform float specular : hint_range(0.0, 2.0) = 0.30;
uniform float sheen : hint_range(0.0, 1.0) = 0.10;
uniform vec4 rim_color : source_color = vec4(0.62, 0.86, 1.0, 1.0);
uniform float rim_strength : hint_range(0.0, 2.0) = 0.28;

void fragment() {
	vec2 uv = UV * 2.0 - 1.0;
	float dist = length(uv);

	// Recorte elíptico, con un píxel de suavizado en el borde.
	float aa = max(fwidth(dist), 0.001);
	float coverage = 1.0 - smoothstep(1.0 - aa, 1.0, dist);
	if (coverage <= 0.0) {
		discard;
	}

	// Normal de esfera (la y de pantalla crece hacia abajo).
	float z = sqrt(max(1.0 - dist * dist, 0.0));
	vec3 n = normalize(vec3(uv.x, uv.y, z));
	vec3 l = normalize(light_direction);
	vec3 albedo = COLOR.rgb * base_color.rgb;

	// Difusa envolvente suavizada.
	float diff = clamp((dot(n, l) + wrap) / (1.0 + wrap), 0.0, 1.0);
	diff = diff * diff * (3.0 - 2.0 * diff);
	// Ambiente: cielo arriba, suelo abajo.
	vec3 amb = mix(sky_color.rgb, ground_color.rgb, clamp(n.y * 0.5 + 0.5, 0.0, 1.0));
	// Oclusión: el borde inferior de cada pieza se oscurece un poco.
	float ao = 1.0 - occlusion * smoothstep(0.15, 1.0, uv.y) * (1.0 - 0.5 * z);
	vec3 col = albedo * (amb * ambient + vec3(diff * diffuse_strength)) * ao;

	// Brillos: mancha nítida (vinilo) + brillo ancho (satinado).
	vec3 h = normalize(l + vec3(0.0, 0.0, 1.0));
	float ndh = max(dot(n, h), 0.0);
	float spot = smoothstep(0.30, 0.65, pow(ndh, glossiness)) * specular;
	float broad = pow(ndh, 5.0) * sheen;

	// Contorno: fresnel, más fuerte en el lado de arriba a la derecha.
	float fres = pow(1.0 - z, 2.5);
	vec2 side = uv / max(dist, 0.0001);
	float rim = fres * rim_strength * smoothstep(-0.2, 0.7, dot(side, normalize(vec2(0.75, -0.45))));

	col += vec3(spot + broad) + rim_color.rgb * rim;
	COLOR = vec4(col, COLOR.a * base_color.a * coverage);
}
