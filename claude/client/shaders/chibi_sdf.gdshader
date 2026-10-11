shader_type canvas_item;
render_mode unshaded;
// Chibi "de vinilo" entero en un solo rectángulo (ProceduralChibiAvatar dibuja un rect con
// este material). Cada parte es un campo de distancia (SDF) y las que se tocan se funden
// con uniones suaves, así que la silueta es una sola línea continua: cabeza con mofletes y
// orejas, cuerpo con capucha y brazos, zapatillas. No hay esferas apiladas.
//
// Volumen: la normal sale de la distancia al borde ("inflado", como un muñeco de vinilo):
// en el borde mira de lado y hacia dentro mira a la cámara. Los brazos, el hocico, los ojos
// y la visera llevan su propio bulto encima. Entre piezas hay pliegues y oclusión suave
// (la cabeza sombrea el cuello, el brazo el costado, la visera la frente).
//
// Luz de estudio satinada: luz principal cálida arriba a la izquierda con terminador
// ancho, ambiente frío del techo y rebote cálido del suelo, brillo satinado ancho, reflejo
// de softbox solo en lo brillante (ojos, nariz, punteras) y contorno cálido por detrás.
// Las sombras guardan saturación (como el vinilo, que deja pasar algo de luz).
//
// Bordes: antialias analítico con fwidth, así que se ve nítido a cualquier escala (menú a
// 4x, mapa a 0.75x) sin texturas que se pixelen. Con output_mode = 1 pinta el mapa de
// normales en vez del color (lo usa la exportación de sprites de 512x512).
//
// Unidades: las del chibi (escala 1), con el origen en los pies y la y hacia abajo.
// Compatible con los renderizadores Compatibility (móviles/web) y Forward+.

const float EPS = 0.3;   // paso de las diferencias finitas de la normal (unidades)

// ── Forma (la pone ProceduralChibiAvatar.generate_avatar) ──
uniform int view = 0;            // 0 frente, 1 lado (mira a la derecha), 2 espalda
uniform vec2 head_r = vec2(27.0, 24.5);
uniform float body_w = 1.0;
uniform int ear_type = 0;        // 0 redondas, 1 puntiagudas, 2 altas, 3 largas, 4 caídas, 5 penachos, 6 sin orejas
uniform bool stripes = false;    // rayas de tigre en la cabeza
uniform int patches = 0;         // 0 nada, 1 manchas de panda, 2 antifaz, 3 cara clara (pingüino)
uniform bool beak = false;
uniform int tail_type = 0;       // 0 sin cola, 1 tupida, 2 anillada, 3 fina, 4 rayada, 5 pompón
uniform bool has_mane = false;
uniform bool has_cap = false;
uniform bool hoodie = false;
uniform int output_mode = 0;     // 0 color, 1 mapa de normales
// El color se calcula en sRGB; si el viewport pinta en lineal (HDR 2D en Forward+/Mobile)
// se convierte al final para que se vea igual que en Compatibility.
uniform bool linear_output = false;

// ── Colores (tal cual, en sRGB) ──
uniform vec4 fur_color = vec4(0.85, 0.38, 0.17, 1.0);
uniform vec4 fur_light = vec4(0.97, 0.91, 0.85, 1.0);
uniform vec4 ear_outer = vec4(0.85, 0.38, 0.17, 1.0);
uniform vec4 ear_inner = vec4(0.97, 0.80, 0.80, 1.0);
uniform vec4 mane_color = vec4(0.66, 0.39, 0.16, 1.0);
uniform vec4 outfit_color = vec4(0.15, 0.16, 0.22, 1.0);
uniform vec4 pants_color = vec4(0.17, 0.23, 0.33, 1.0);
uniform vec4 shoe_color = vec4(0.89, 0.91, 0.94, 1.0);
uniform vec4 bag_color = vec4(0.25, 0.25, 0.27, 1.0);
uniform vec4 cap_color = vec4(0.12, 0.23, 0.54, 1.0);
uniform vec4 accent_color = vec4(1.0, 0.2, 0.29, 1.0);
uniform vec4 eye_color = vec4(0.6, 0.2, 0.07, 1.0);
uniform vec4 brow_color = vec4(0.4, 0.17, 0.08, 1.0);
uniform vec4 tail_color = vec4(0.85, 0.38, 0.17, 1.0);
uniform vec4 tail_tip = vec4(0.97, 0.91, 0.85, 1.0);
uniform vec4 tail_band = vec4(0.38, 0.17, 0.08, 1.0);

// ── Animación (cada frame, desde animate_walk) ──
uniform vec4 body_anim = vec4(0.0);                    // x elevación, y aplastado, z giro
uniform vec4 head_anim = vec4(0.0, -64.0, 0.0, 0.0);   // xy posición en el cuerpo, z giro, w muelle de las orejas
uniform vec4 feet_pos = vec4(-7.5, 0.0, 7.5, 0.0);     // zapatilla izquierda (xy) y derecha (zw)
uniform vec2 feet_rot = vec2(0.0);
uniform vec4 arm_rot = vec4(0.16, -0.25, -0.16, 0.25); // hombro y codo, izquierdo (xy) y derecho (zw)
uniform float tail_rot = 0.0;
uniform float eye_open = 1.0;
uniform float eye_smile = 0.0;   // 0..1: ojos cerrados de gusto (^ ^), al acariciar la mascota
uniform float mouth_open = 0.0;  // 0..1: boca (o pico) abierta: ladrar, maullar, comer

// ── Luz de estudio ──
uniform vec3 key_dir = vec3(-0.55, -0.72, 0.8);
uniform vec4 key_tint = vec4(1.0, 0.95, 0.88, 1.0);
uniform vec4 sky_tint = vec4(0.70, 0.78, 1.0, 1.0);
uniform vec4 ground_tint = vec4(0.80, 0.62, 0.52, 1.0);
uniform vec4 rim_tint = vec4(1.0, 0.84, 0.62, 1.0);
uniform float exposure = 1.0;

varying vec2 lp;
varying float flip;

void vertex() {
	lp = VERTEX;
	// Volteado (Visuals.scale.x = -1): la luz no se voltea con el dibujo.
	flip = sign(MODEL_MATRIX[0].x * MODEL_MATRIX[1].y - MODEL_MATRIX[0].y * MODEL_MATRIX[1].x);
	if (flip == 0.0) {
		flip = 1.0;
	}
}

// ───── Utilidades ─────

vec2 rot(vec2 p, float a) {
	float c = cos(a);
	float s = sin(a);
	return vec2(c * p.x - s * p.y, s * p.x + c * p.y);
}

float sd_circle(vec2 p, float r) {
	return length(p) - r;
}

// Elipse aproximada (exacta en el borde, suave dentro).
float sd_ellipse(vec2 p, vec2 r) {
	float k1 = length(p / (r * r));
	if (k1 < 1e-5) {
		return -min(r.x, r.y);
	}
	float k0 = length(p / r);
	return k0 * (k0 - 1.0) / k1;
}

float sd_segment(vec2 p, vec2 a, vec2 b) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	float h = clamp(dot(pa, ba) / max(dot(ba, ba), 1e-6), 0.0, 1.0);
	return length(pa - ba * h);
}

float sd_capsule(vec2 p, vec2 a, vec2 b, float r) {
	return sd_segment(p, a, b) - r;
}

// Cápsula de radios distintos (de ra en a hasta rb en b).
float sd_cone(vec2 p, vec2 a, vec2 b, float ra, float rb) {
	vec2 pp = p - a;
	vec2 pb = b - a;
	float h = max(dot(pb, pb), 1e-4);
	vec2 q = vec2(dot(pp, vec2(pb.y, -pb.x)), dot(pp, pb)) / h;
	q.x = abs(q.x);
	float bb = ra - rb;
	vec2 c = vec2(sqrt(max(h - bb * bb, 1e-4)), bb);
	float k = c.x * q.y - c.y * q.x;
	float m = dot(c, q);
	float n = dot(q, q);
	if (k < 0.0) {
		return sqrt(h * n) - ra;
	}
	if (k > c.x) {
		return sqrt(h * (n + 1.0 - 2.0 * q.y)) - rb;
	}
	return m - ra;
}

float sd_rbox(vec2 p, vec2 b, float r) {
	vec2 q = abs(p) - b + vec2(r);
	return length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - r;
}

float sd_tri(vec2 p, vec2 p0, vec2 p1, vec2 p2) {
	vec2 e0 = p1 - p0;
	vec2 e1 = p2 - p1;
	vec2 e2 = p0 - p2;
	vec2 v0 = p - p0;
	vec2 v1 = p - p1;
	vec2 v2 = p - p2;
	vec2 pq0 = v0 - e0 * clamp(dot(v0, e0) / dot(e0, e0), 0.0, 1.0);
	vec2 pq1 = v1 - e1 * clamp(dot(v1, e1) / dot(e1, e1), 0.0, 1.0);
	vec2 pq2 = v2 - e2 * clamp(dot(v2, e2) / dot(e2, e2), 0.0, 1.0);
	float s = sign(e0.x * e2.y - e0.y * e2.x);
	vec2 d = min(min(vec2(dot(pq0, pq0), s * (v0.x * e0.y - v0.y * e0.x)),
			vec2(dot(pq1, pq1), s * (v1.x * e1.y - v1.y * e1.x))),
			vec2(dot(pq2, pq2), s * (v2.x * e2.y - v2.y * e2.x)));
	return -sqrt(d.x) * sign(d.y);
}

float sq(float x) {
	return x * x;
}

float smin(float a, float b, float k) {
	float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
	return mix(b, a, h) - k * h * (1.0 - h);
}

float smax(float a, float b, float k) {
	return -smin(-a, -b, k);
}

// Cobertura con antialias (d en unidades, px = unidades por píxel).
float cov(float d, float px) {
	return clamp(0.5 - d / px, 0.0, 1.0);
}

// Trazo de medio ancho w que no parpadea cuando es más fino que un píxel.
float stroke(float d, float w, float px) {
	float we = max(w, px * 0.6);
	return cov(d - we, px) * min(w / we, 1.0);
}

// Normal de un bulto inflado: de lado en el borde y de cara a la cámara a profundidad T.
vec3 pillow(float d, vec2 g, float T) {
	vec2 dir = g / max(length(g), 1e-5);
	float s = pow(1.0 - clamp(-d / T, 0.0, 1.0), 1.15);
	vec2 xy = dir * s;
	return vec3(xy, sqrt(max(1.0 - dot(xy, xy), 0.0)));
}

vec3 bump(vec3 n, float d, vec2 g, float T, float w) {
	return normalize(mix(n, pillow(d, g, T), clamp(w, 0.0, 1.0)));
}

vec3 darken(vec3 c, float k) {
	return c * (1.0 - k);
}

vec3 lighten(vec3 c, float k) {
	return c + (vec3(1.0) - c) * k;
}

// Luz de estudio satinada. ao = oclusión (1 = nada).
vec3 shade(vec3 albedo, vec3 n, float gloss, float ao) {
	if (output_mode == 1) {
		return vec3(n.x * flip, -n.y, n.z) * 0.5 + 0.5;
	}
	vec3 L = normalize(vec3(key_dir.x * flip, key_dir.y, key_dir.z));
	float ndl = dot(n, L);
	float diff = smoothstep(-0.42, 0.98, ndl);
	float up = clamp(0.5 - 0.5 * n.y, 0.0, 1.0);
	vec3 amb = mix(ground_tint.rgb, sky_tint.rgb, up);
	float lum = dot(albedo, vec3(0.299, 0.587, 0.114));
	vec3 rich = clamp(mix(vec3(lum), albedo, 1.35), 0.0, 1.0);
	vec3 base = mix(rich * 0.94, albedo, diff);
	vec3 col = base * (amb * 0.46 + key_tint.rgb * diff * 0.64) * exposure;
	vec3 H = normalize(L + vec3(0.0, 0.0, 1.0));
	float ndh = max(dot(n, H), 0.0);
	float satin = pow(ndh, 8.0) * (0.035 + 0.10 * gloss);
	float softbox = smoothstep(0.94, 0.99, ndh) * (0.012 + 0.6 * gloss);
	float fres = pow(1.0 - clamp(n.z, 0.0, 1.0), 2.4);
	vec2 nd = n.xy / max(length(n.xy), 1e-4);
	float back_side = smoothstep(-0.15, 0.75, dot(nd, normalize(vec2(0.78 * flip, -0.62))));
	col *= 1.0 - 0.20 * fres * (1.0 - back_side);
	col *= ao;
	col += vec3(satin + softbox) * mix(0.35, 1.0, ao);
	col += rim_tint.rgb * fres * back_side * 0.34 * ao;
	return col;
}

vec3 to_linear(vec3 c) {
	vec3 cc = clamp(c, 0.0, 1.0);
	return mix(cc / 12.92, pow((cc + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), cc));
}

void over(inout vec4 acc, vec3 col, float a) {
	acc.rgb = col * a + acc.rgb * (1.0 - a);
	acc.a = a + acc.a * (1.0 - a);
}

// ───── Marcos: pies (mundo) → cuerpo (rebota) → cabeza ─────

vec2 to_body(vec2 p) {
	vec2 s = rot(p + vec2(0.0, body_anim.x), -body_anim.z);
	return s / vec2(1.0 + body_anim.y, 1.0 - body_anim.y);
}

vec2 from_body(vec2 q) {
	return rot(q * vec2(1.0 + body_anim.y, 1.0 - body_anim.y), body_anim.z) - vec2(0.0, body_anim.x);
}

vec2 to_head(vec2 q) {
	return rot(q - head_anim.xy, -head_anim.z);
}

// ───── Piernas y zapatillas ─────

float legs_d(vec2 p) {
	float d = 1e3;
	for (int i = 0; i < 2; i++) {
		float s = i == 0 ? -1.0 : 1.0;
		vec2 hip = from_body(vec2(6.5 * s * (view == 1 ? 0.4 : 1.0), -15.0));
		vec2 ank = (i == 0 ? feet_pos.xy : feet_pos.zw) + vec2(0.0, -7.0);
		d = min(d, sd_capsule(p, hip, ank, 4.5));
	}
	return d;
}

vec2 shoe_frame(vec2 p, int i) {
	vec2 pos = i == 0 ? feet_pos.xy : feet_pos.zw;
	float r = i == 0 ? feet_rot.x : feet_rot.y;
	return rot(p - pos, -r);
}

float shoe_d(vec2 f, float s) {
	float sole;
	float upper;
	if (view == 1) {
		sole = sd_rbox(f - vec2(1.0, -2.3), vec2(9.4, 2.3), 2.2);
		upper = smin(sd_ellipse(f - vec2(-1.2, -6.3), vec2(6.8, 4.7)), sd_ellipse(f - vec2(3.8, -4.4), vec2(5.6, 3.4)), 2.5);
	} else {
		sole = sd_rbox(f - vec2(0.5 * s, -2.3), vec2(8.6, 2.3), 2.3);
		upper = sd_ellipse(f - vec2(0.0, -6.1), vec2(7.2, 4.9));
	}
	return smin(sole, upper, 1.4);
}

// ───── Cuerpo: torso, capucha, brazos ─────

vec2 shoulder(int i) {
	if (view == 1) {
		return vec2(1.5, -40.5);
	}
	return vec2(i == 0 ? -14.2 : 14.2, -40.5);
}

// Articulaciones de un brazo: codo, muñeca, centro de la mano y ángulo del antebrazo.
void arm_joints(int i, out vec2 el, out vec2 wr, out vec2 hc, out float a2) {
	vec2 sh = shoulder(i);
	float a1 = i == 0 ? arm_rot.x : arm_rot.z;
	a2 = a1 + (i == 0 ? arm_rot.y : arm_rot.w);
	el = sh + rot(vec2(0.0, 9.5), a1);
	wr = el + rot(vec2(0.0, 7.4), a2);
	hc = el + rot(vec2(0.0, 11.0), a2);
}

float hand_d(vec2 q, vec2 hc, float a2, float s) {
	vec2 k = rot(q - hc, -a2);
	float palm = sd_ellipse(k, vec2(4.5, 4.4));
	float thumb = sd_circle(k - vec2(-3.4 * s, -1.0), 1.9);
	return smin(palm, thumb, 1.2);
}

float arm_d(vec2 q, int i) {
	vec2 el;
	vec2 wr;
	vec2 hc;
	float a2;
	arm_joints(i, el, wr, hc, a2);
	float s = i == 0 ? -1.0 : 1.0;
	float sleeve = smin(sd_cone(q, shoulder(i), el, 4.8, 4.4), sd_cone(q, el, wr, 4.4, 4.1), 1.2);
	return smin(sleeve, hand_d(q, hc, a2, view == 1 ? -1.0 : s), 0.8);
}

float arms_d(vec2 q) {
	float d = 1e3;
	for (int i = 0; i < 2; i++) {
		if (view == 1 && i == 0) {
			continue;
		}
		d = min(d, arm_d(q, i));
	}
	return d;
}

float collar_d(vec2 q) {
	if (!hoodie) {
		return 1e3;
	}
	if (view == 1) {
		return sd_ellipse(q - vec2(-2.0, -42.5), vec2(13.5, 7.6));
	}
	if (view == 2) {
		return sd_ellipse(q - vec2(0.0, -43.5), vec2(18.5, 9.5));
	}
	return sd_ellipse(q - vec2(0.0, -42.0), vec2(20.5, 7.8));
}

float torso_d(vec2 q) {
	float w = body_w * (view == 1 ? 0.86 : 1.0);
	float a = sd_ellipse(q - vec2(0.0, -31.5), vec2(14.8 * w, 13.6));
	float b = sd_ellipse(q - vec2(0.0, -21.0), vec2(16.8 * w, 10.2));
	return smin(smin(a, b, 6.0), collar_d(q), 3.0);
}

float body_d(vec2 q) {
	return smin(torso_d(q), arms_d(q), 2.2);
}

// ───── Mochila y cola ─────

float bag_d(vec2 q) {
	if (view == 1) {
		float b = sd_rbox(q - vec2(-13.0, -31.0), vec2(5.6, 12.5), 5.0);
		return smin(b, sd_ellipse(q - vec2(-17.2, -24.5), vec2(3.0, 5.6)), 1.5);
	}
	float b = sd_rbox(q - vec2(0.0, -31.0), vec2(12.6, 13.0), 7.0);
	float handle = abs(sd_ellipse(q - vec2(0.0, -45.5), vec2(4.6, 2.8))) - 1.1;
	return min(b, handle);
}

vec2 tail_frame(vec2 q) {
	vec2 pos = view == 1 ? vec2(-13.0, -16.0) : vec2(0.0, -15.0);
	return rot(q - pos, -tail_rot);
}

float tail_d(vec2 t) {
	if (tail_type == 1 || tail_type == 2) {
		float brush = sd_ellipse(rot(t - vec2(-4.0, -9.0), 0.6), vec2(6.5, 11.5));
		return smin(brush, sd_circle(t - vec2(-9.5, -17.0), 4.6), 3.0);
	}
	if (tail_type == 3 || tail_type == 4) {
		vec2 a = vec2(-1.0, -1.0);
		vec2 b = vec2(-5.1, -7.5);
		vec2 c = vec2(-7.4, -12.8);
		vec2 d = vec2(-9.6, -18.0);
		float tl = smin(smin(sd_cone(t, a, b, 2.5, 2.3), sd_cone(t, b, c, 2.3, 2.1), 1.0), sd_cone(t, c, d, 2.1, 2.0), 1.0);
		if (has_mane) {
			tl = smin(tl, sd_ellipse(t - vec2(-11.5, -20.5), vec2(3.8, 4.4)), 1.5);
		}
		return tl;
	}
	if (tail_type == 5) {
		vec2 u = t - vec2(0.0, -2.0);
		return length(u) - 5.6;
	}
	return 1e3;
}

// ───── Cabeza ─────

float ear_one(vec2 h, float s) {
	float ea = head_anim.w * s;
	vec2 r = head_r;
	if (ear_type == 0) {
		vec2 c = has_cap ? vec2(0.86 * r.x * s, -0.62 * r.y) : vec2(0.72 * r.x * s, -0.78 * r.y);
		return sd_circle(h - c, 8.8);
	}
	if (ear_type == 1 || ear_type == 2) {
		float H = ear_type == 2 ? 23.0 : 17.0;
		vec2 e = rot(h - vec2(0.55 * r.x * s, -0.70 * r.y), -(0.18 * s + ea));
		return sd_tri(e, vec2(-6.6, 1.2), vec2(2.2 * s, -H + 1.8), vec2(6.6, 1.2)) - 1.7;
	}
	if (ear_type == 3) {
		vec2 e = rot(h - vec2(8.5 * s, -r.y - 2.0), -(0.14 * s + ea));
		return sd_ellipse(e - vec2(0.0, -12.0), vec2(5.8, 15.5));
	}
	if (ear_type == 5) {
		vec2 e = rot(h - vec2(0.6 * r.x * s, -0.72 * r.y), -ea);
		return sd_tri(e, vec2(-4.0, 1.4), vec2(4.2 * s, -10.8), vec2(4.0, 1.4)) - 1.0;
	}
	return 1e3;
}

float ears_d(vec2 h) {
	return min(ear_one(h, -1.0), ear_one(h, 1.0));
}

float floppy_d(vec2 h) {
	if (ear_type != 4) {
		return 1e3;
	}
	float d = 1e3;
	for (int i = 0; i < 2; i++) {
		float s = i == 0 ? -1.0 : 1.0;
		if (view == 1 && i == 0) {
			continue;
		}
		vec2 base = view == 1 ? vec2(-2.0, -0.5 * head_r.y) : vec2((head_r.x - 3.0) * s, -0.45 * head_r.y);
		vec2 e = rot(h - base, -(-0.3 * s + head_anim.w * s));
		d = min(d, sd_ellipse(e - vec2(0.0, 10.0), vec2(7.5, 14.5)));
	}
	return d;
}

// Cabeza en forma de huevo ancho abajo (mofletes) sin uniones: el sombreado no hace surcos.
float head_core(vec2 h) {
	float wide = 1.0 + 0.08 * smoothstep(-0.7 * head_r.y, 0.55 * head_r.y, h.y);
	return sd_ellipse(h, vec2(head_r.x * wide, head_r.y));
}

float head_d(vec2 h) {
	vec2 r = head_r;
	float d = head_core(h);
	float cr = 0.5 * r.x;
	if (view == 1) {
		d = smin(d, sd_circle(h - vec2(0.42 * r.x, 0.38 * r.y), cr), 8.0);
		if (!beak) {
			d = smin(d, sd_ellipse(h - vec2(0.80 * r.x, 0.33 * r.y), vec2(8.2, 6.8)), 4.0);
		}
	}
	float k = ear_type == 5 ? 1.5 : (ear_type == 0 || ear_type == 3 ? 2.6 : 2.0);
	return smin(d, ears_d(h), k);
}

float mane_d(vec2 h) {
	vec2 m = h - vec2(view == 1 ? -3.0 : 0.0, -1.0);
	float ang = atan(m.y, m.x);
	float below = max(sin(ang), 0.0);
	vec2 R = head_r * vec2(1.16 - 0.10 * below, 1.10 - 0.24 * below);
	float sc = 0.5 + 0.5 * cos(14.0 * ang);
	return sd_ellipse(m, R + 2.0) - 4.0 * sc + 1.0;
}

// ───── Gorra ─────

float crown_d(vec2 h) {
	vec2 r = head_r;
	vec2 c = vec2(view == 1 ? -1.0 : 0.0, -0.62 * r.y);
	float d = sd_ellipse(h - c, vec2(1.0 * r.x, 0.66 * r.y));
	return smax(d, h.y + 0.40 * r.y, 1.2);
}

float brim_d(vec2 h) {
	vec2 r = head_r;
	if (view == 2) {
		return 1e3;
	}
	if (view == 1) {
		return sd_ellipse(rot(h - vec2(0.86 * r.x, -0.42 * r.y), -0.10), vec2(0.40 * r.x, 2.7));
	}
	return sd_ellipse(h - vec2(0.0, -0.37 * r.y), vec2(0.72 * r.x, 4.2));
}

// ───── Cara (pintada sobre la cabeza) ─────

void paint_face(vec2 h, float px, inout vec3 col, inout float gloss, inout vec3 n, inout float ao) {
	vec2 r = head_r;
	float kx = r.x / 27.0;
	bool side = view == 1;
	// Marco de la cara: de lado se desplaza hacia delante y se estrecha.
	vec2 f = side ? vec2((h.x - 0.36 * r.x) / 0.78, h.y) : h;
	vec3 fl = fur_light.rgb;

	// Rayas de tigre.
	if (stripes) {
		float d = 1e3;
		for (int i = 0; i < 3; i++) {
			float x = (float(i) - 1.0) * 9.0 * kx;
			float y0 = -r.y + 1.0 + abs(x) * 0.3;
			d = min(d, sd_tri(f, vec2(x - 2.6, y0), vec2(x + 2.6, y0), vec2(x, y0 + 9.5)));
		}
		for (int i = 0; i < 2; i++) {
			float s = i == 0 ? -1.0 : 1.0;
			vec2 c = vec2((r.x - 1.0) * s, -2.0);
			d = min(d, sd_tri(h, c + vec2(0.0, -3.2), c + vec2(-8.0 * s, 0.0), c + vec2(0.0, 3.2)));
			d = min(d, sd_tri(h, c + vec2(0.0, 3.6), c + vec2(-6.0 * s, 6.2), c + vec2(0.0, 8.4)));
		}
		col = mix(col, darken(fur_color.rgb, 0.6), cov(d - 0.3, max(px, 0.5)));
	}
	if (view == 2) {
		return;
	}
	// Manchas, antifaz, cara clara o discos faciales.
	if (patches == 1) {
		for (int i = 0; i < 2; i++) {
			float s = i == 0 ? -1.0 : 1.0;
			if (side && i == 0) {
				continue;
			}
			float d = sd_ellipse(rot(f - vec2(10.5 * kx * s, 0.8), -0.45 * s), vec2(8.0, 9.8));
			col = mix(col, vec3(0.10, 0.10, 0.13), cov(d, max(px, 0.5)));
		}
	} else if (patches == 2) {
		float d = sd_ellipse(f - vec2(0.0, -0.5), vec2(22.5 * kx, 7.6));
		d = smax(d, -sd_ellipse(f - vec2(0.0, 9.0), vec2(9.0, 5.5)), 2.0);
		col = mix(col, vec3(0.16, 0.17, 0.21), cov(d, max(px, 0.5)));
		float brows = min(sd_ellipse(f - vec2(-10.5 * kx, -10.0), vec2(6.0, 2.6)), sd_ellipse(f - vec2(10.5 * kx, -10.0), vec2(6.0, 2.6)));
		col = mix(col, fl, cov(brows, max(px, 0.8)) * 0.85);
	} else if (patches == 3) {
		float d = smin(min(sd_ellipse(f - vec2(-8.6 * kx, 1.0), vec2(12.0, 13.0)), sd_ellipse(f - vec2(8.6 * kx, 1.0), vec2(12.0, 13.0))), sd_ellipse(f - vec2(0.0, 9.5), vec2(16.0, 10.0)), 3.0);
		col = mix(col, fl, cov(d, max(px, 0.5)));
	}
	if (beak && patches != 3) {
		float d = min(sd_circle(f - vec2(-10.0 * kx, 0.5), 10.8), sd_circle(f - vec2(10.0 * kx, 0.5), 10.8));
		if (side) {
			d = sd_circle(f - vec2(10.0 * kx, 0.5), 10.8);
		}
		col = mix(col, fl, cov(d, max(px, 0.6)));
		ao *= 1.0 - 0.12 * exp(-sq(max(d, 0.0) / 1.2)) * step(0.0, d);
	}
	// Hocico claro con bulto.
	if (!beak) {
		vec2 mc = side ? vec2(0.80 * r.x, 0.33 * r.y) : vec2(0.0, 9.5);
		vec2 mr = side ? vec2(8.2, 6.8) : vec2(11.5, 7.6);
		vec2 mp = side ? h : f;
		float d = sd_ellipse(mp - mc, mr);
		vec2 g = vec2(sd_ellipse(mp + vec2(EPS, 0.0) - mc, mr) - d, sd_ellipse(mp + vec2(0.0, EPS) - mc, mr) - d);
		col = mix(col, fl, cov(d, max(px, 0.7)));
		if (!side) {
			n = bump(n, d, g, 5.5, cov(d, 2.5) * 0.85);
		}
	}
	// Coloretes.
	for (int i = 0; i < 2; i++) {
		float s = i == 0 ? -1.0 : 1.0;
		if (side && i == 0) {
			continue;
		}
		vec2 u = (f - vec2(17.0 * kx * s, 8.5)) / vec2(5.4, 3.2);
		col = mix(col, vec3(1.0, 0.52, 0.60), (0.42 + 0.25 * eye_smile) * exp(-dot(u, u) * 1.4));
	}
	// Ojos grandes y brillantes: base oscura, iris, pupila y dos brillos. Parpadean.
	// Con eye_smile se cierran de gusto en un arco hacia arriba (^ ^).
	float smile = clamp(eye_smile, 0.0, 1.0);
	float shut = eye_open * (1.0 - smile);
	float open = max(shut, 0.12);
	for (int i = 0; i < 2; i++) {
		float s = i == 0 ? -1.0 : 1.0;
		if (side && i == 0) {
			continue;
		}
		vec2 ec = vec2(10.5 * kx * s, -0.5);
		if (smile > 0.6) {
			vec2 u = f - ec - vec2(0.0, 2.4);
			float arc = u.y <= 0.0 ? abs(length(u) - 4.8) : length(vec2(abs(u.x) - 4.8, u.y));
			vec3 lid = (patches == 1 || patches == 2) ? vec3(0.95, 0.93, 0.90) : vec3(0.16, 0.09, 0.08);
			col = mix(col, lid, stroke(arc, 1.0, px));
		} else {
			vec2 e = f - ec;
			e.y /= open;
			vec2 er = vec2(6.0, 7.2);
			float d = sd_ellipse(e, er);
			float a = cov(d * open, px);
			if (a > 0.0) {
				vec3 iris = eye_color.rgb;
				vec3 ec_col = darken(iris, 0.72);
				ec_col = mix(ec_col, lighten(iris, 0.12), 0.85 * cov(sd_ellipse(e - vec2(0.0, 2.8), vec2(4.6, 3.4)), px / open));
				ec_col = mix(ec_col, vec3(0.02, 0.02, 0.04), cov(sd_ellipse(e - vec2(0.0, -0.4), vec2(3.3, 4.3)), px / open));
				ec_col = mix(ec_col, vec3(1.0), cov(sd_ellipse(e - vec2(-1.9, -2.6), vec2(2.3, 2.6)), px / open));
				ec_col = mix(ec_col, vec3(1.0), 0.9 * cov(sd_circle(e - vec2(2.3, 2.8), 1.0), px / open));
				if (shut < 0.3) {
					ec_col = darken(fur_color.rgb, 0.7);
				}
				col = mix(col, ec_col, a);
				gloss = mix(gloss, 1.0, a);
				vec2 g = vec2(sd_ellipse(e + vec2(EPS, 0.0), er) - d, sd_ellipse(e + vec2(0.0, EPS), er) - d);
				n = bump(n, d, g, 4.0, a * 0.75);
			}
			ao *= 1.0 - 0.18 * exp(-sq(max(d * open, 0.0) / 0.9)) * step(0.0, d);
		}
		// Ceja.
		vec2 b = rot(f - vec2(10.5 * kx * s, -11.0), 0.12 * s);
		float bd = min(sd_segment(b, vec2(-4.0, 0.9), vec2(0.0, -0.7)), sd_segment(b, vec2(0.0, -0.7), vec2(4.0, 0.9)));
		col = mix(col, brow_color.rgb, stroke(bd, 0.75, px));
	}
	// Nariz y boca, o pico.
	if (beak) {
		vec2 bp = side ? vec2((h.x - 0.92 * r.x) / 1.0, h.y) : f;
		float up;
		float lo;
		float drop = 3.0 * clamp(mouth_open, 0.0, 1.0);
		float gap = 1e3;
		if (side) {
			up = sd_tri(bp, vec2(-3.5, 3.6), vec2(6.0, 7.4), vec2(-3.5, 9.4)) - 1.2;
			lo = mouth_open > 0.02 ? sd_tri(bp, vec2(-3.5, 9.0), vec2(4.5, 9.0 + drop), vec2(-3.5, 10.8 + 0.6 * drop)) - 0.8 : 1e3;
			gap = mouth_open > 0.02 ? sd_tri(bp, vec2(-3.5, 7.4), vec2(5.0, 8.0 + 0.8 * drop), vec2(-3.5, 9.6 + 0.6 * drop)) : 1e3;
		} else {
			up = sd_tri(bp, vec2(-4.4, 5.2), vec2(4.4, 5.2), vec2(0.0, 10.4)) - 1.3;
			lo = sd_ellipse(bp - vec2(0.0, 10.4 + drop), vec2(3.0, 1.6 + 0.3 * drop));
			gap = mouth_open > 0.02 ? sd_ellipse(bp - vec2(0.0, 9.6 + 0.5 * drop), vec2(3.4, 0.4 + 0.6 * drop)) : 1e3;
		}
		col = mix(col, vec3(0.36, 0.10, 0.12), cov(gap, px));
		vec2 gu = vec2(0.0);
		if (side) {
			gu = vec2(sd_tri(bp + vec2(EPS, 0.0), vec2(-3.5, 3.6), vec2(6.0, 7.4), vec2(-3.5, 9.4)) - 1.2 - up, sd_tri(bp + vec2(0.0, EPS), vec2(-3.5, 3.6), vec2(6.0, 7.4), vec2(-3.5, 9.4)) - 1.2 - up);
		} else {
			gu = vec2(sd_tri(bp + vec2(EPS, 0.0), vec2(-4.4, 5.2), vec2(4.4, 5.2), vec2(0.0, 10.4)) - 1.3 - up, sd_tri(bp + vec2(0.0, EPS), vec2(-4.4, 5.2), vec2(4.4, 5.2), vec2(0.0, 10.4)) - 1.3 - up);
		}
		float al = cov(lo, px);
		col = mix(col, vec3(0.85, 0.42, 0.04), al);
		float au = cov(up, px);
		col = mix(col, vec3(0.98, 0.64, 0.10), au);
		gloss = mix(gloss, 0.55, max(au, al));
		n = bump(n, up, gu, 2.8, au);
		ao *= 1.0 - 0.25 * exp(-sq(max(up, 0.0) / 1.0)) * step(0.0, up) * step(-0.5, h.y - 6.0);
	} else {
		vec2 np = side ? vec2(h.x - (0.80 * r.x + 6.2), h.y - 5.4) : f - vec2(0.0, 5.6);
		float nd = sd_tri(np, vec2(-3.0, -1.6), vec2(3.0, -1.6), vec2(0.0, 1.6)) - 1.0;
		vec2 ng = vec2(sd_tri(np + vec2(EPS, 0.0), vec2(-3.0, -1.6), vec2(3.0, -1.6), vec2(0.0, 1.6)) - 1.0 - nd, sd_tri(np + vec2(0.0, EPS), vec2(-3.0, -1.6), vec2(3.0, -1.6), vec2(0.0, 1.6)) - 1.0 - nd);
		float na = cov(nd, px);
		col = mix(col, vec3(0.10, 0.08, 0.09), na);
		gloss = mix(gloss, 0.9, na);
		n = bump(n, nd, ng, 2.2, na);
		// Boca en "w".
		vec2 m = side ? vec2(h.x - (0.80 * r.x + 3.0), h.y - 10.2) : f - vec2(0.0, 10.0);
		float md = 1e3;
		for (int i = 0; i < 2; i++) {
			float s = i == 0 ? -1.0 : 1.0;
			if (side && i == 0) {
				continue;
			}
			vec2 c = vec2(1.8 * s, 0.0);
			vec2 u = m - c;
			float arc = u.y >= 0.0 ? abs(length(u) - 1.8) : min(length(u - vec2(-1.8, 0.0)), length(u - vec2(1.8, 0.0)));
			md = min(md, arc);
		}
		if (!side) {
			md = min(md, sd_segment(m, vec2(0.0, -2.6), vec2(0.0, 0.0)));
		}
		col = mix(col, vec3(0.23, 0.12, 0.10), stroke(md, 0.5, px));
		// Boca abierta (con lengua) colgando del centro de la "w".
		if (mouth_open > 0.02) {
			float k = clamp(mouth_open, 0.0, 1.0);
			vec2 mr = vec2((side ? 2.8 : 3.8) * (0.6 + 0.4 * k), max(4.0 * k, 0.4));
			vec2 mo = m - vec2(side ? 0.6 : 0.0, 1.2 + mr.y);
			float od = sd_ellipse(mo, mr);
			vec3 inside = vec3(0.36, 0.10, 0.12);
			float td = sd_ellipse(mo - vec2(0.0, mr.y * 0.75), vec2(mr.x * 0.72, mr.y * 0.55));
			inside = mix(inside, vec3(0.96, 0.47, 0.54), cov(td, px));
			col = mix(col, inside, cov(od, px));
			col = mix(col, vec3(0.23, 0.12, 0.10), stroke(abs(od), 0.35, px) * min(k * 3.0, 1.0));
		}
	}
}

// ───── Programa principal: capas de atrás hacia delante ─────

void fragment() {
	vec2 p = lp;
	float px = max(length(fwidth(p)) * 0.7071, 1e-4);
	vec4 acc = vec4(0.0);
	vec2 q = to_body(p);
	bool side = view == 1;
	bool back = view == 2;
	vec3 outfit = outfit_color.rgb;

	// 0. Oclusión de contacto bajo cada zapatilla (la sombra ancha la pinta quien lo contiene).
	if (output_mode == 0 && p.y > -6.0) {
		for (int i = 0; i < 2; i++) {
			vec2 fp = i == 0 ? feet_pos.xy : feet_pos.zw;
			float up = max(-fp.y, 0.0);
			vec2 u = (p - vec2(fp.x + (side ? 1.0 : 0.0), 0.3)) / (vec2(10.5, 2.6) * (1.0 + up * 0.06));
			over(acc, vec3(0.0), 0.42 * exp(-2.4 * dot(u, u)) * clamp(1.0 - up / 7.0, 0.0, 1.0));
		}
	}

	// 1. De lado: cola y mochila por detrás del cuerpo.
	if (side && tail_type != 0) {
		vec2 t = tail_frame(q);
		float d = tail_d(t);
		if (d < 3.0) {
			vec2 g = vec2(tail_d(tail_frame(q + vec2(EPS, 0.0))) - d, tail_d(tail_frame(q + vec2(0.0, EPS))) - d);
			vec3 c = tail_color.rgb;
			if (tail_type == 1) {
				c = mix(c, tail_tip.rgb, cov(sd_circle(t - vec2(-9.8, -17.5), 4.4), 1.5));
			}
			if (tail_type == 2) {
				float rings = min(sd_ellipse(rot(t - vec2(-4.5, -6.0), 0.6), vec2(7.0, 1.9)), sd_ellipse(rot(t - vec2(-8.1, -12.0), 0.6), vec2(7.0, 1.9)));
				c = mix(c, tail_band.rgb, cov(rings, px));
			}
			if (tail_type == 4) {
				float bands = min(sd_segment(t, vec2(-2.0, -5.3), vec2(-6.5, -3.5)), sd_segment(t, vec2(-5.4, -11.6), vec2(-9.6, -9.6)));
				c = mix(c, tail_band.rgb, stroke(bands, 1.0, px));
			}
			if (has_mane && (tail_type == 3 || tail_type == 4)) {
				c = mix(c, mane_color.rgb, cov(sd_ellipse(t - vec2(-11.5, -20.5), vec2(3.8, 4.4)), 1.2));
			}
			over(acc, shade(c, pillow(d, g / EPS, tail_type == 5 ? 5.0 : 3.6), 0.0, 1.0), cov(d / max(length(g / EPS), 0.5), px));
		}
	}
	if (side) {
		float d = bag_d(q);
		if (d < 3.0) {
			vec2 g = vec2(bag_d(q + vec2(EPS, 0.0)) - d, bag_d(q + vec2(0.0, EPS)) - d) / EPS;
			vec3 c = bag_color.rgb;
			float pocket = sd_ellipse(q - vec2(-17.2, -24.5), vec2(3.0, 5.6));
			c = mix(c, lighten(c, 0.12), cov(pocket, px));
			over(acc, shade(c, pillow(d, g, 5.0), 0.05, 1.0 - 0.2 * smoothstep(-6.0, -12.0, q.x)), cov(d, px));
		}
	}

	// 2. Piernas.
	if (p.y > -24.0) {
		float d = legs_d(p);
		if (d < 3.0) {
			vec2 g = vec2(legs_d(p + vec2(EPS, 0.0)) - d, legs_d(p + vec2(0.0, EPS)) - d) / EPS;
			float ao = 1.0 - 0.35 * smoothstep(-6.0, -13.0, p.y);
			over(acc, shade(pants_color.rgb, pillow(d, g, 4.0), 0.0, ao), cov(d, px));
		}
	}

	// 3. Zapatillas (la derecha delante).
	if (p.y > -16.0) {
		for (int i = 0; i < 2; i++) {
			float s = i == 0 ? -1.0 : 1.0;
			vec2 f = shoe_frame(p, i);
			float d = shoe_d(f, s);
			if (d > 3.0) {
				continue;
			}
			vec2 g = vec2(shoe_d(shoe_frame(p + vec2(EPS, 0.0), i), s) - d, shoe_d(shoe_frame(p + vec2(0.0, EPS), i), s) - d) / EPS;
			vec3 n = pillow(d, g, 4.2);
			float gloss = 0.15;
			float ao = 1.0;
			vec3 c = shoe_color.rgb;
			// Suela de goma con su pliegue.
			float sole_line = f.y + 3.2;
			c = mix(c, vec3(0.89, 0.91, 0.94), cov(-sole_line, px));
			c = mix(c, vec3(0.74, 0.78, 0.84), cov(-(f.y + 0.9), px));
			ao *= 1.0 - 0.28 * exp(-sq(sole_line / 0.6));
			// Puntera brillante.
			if (!back) {
				vec2 tc = side ? vec2(4.4, -3.9) : vec2(0.0, -3.9);
				vec2 tr = side ? vec2(4.2, 2.3) : vec2(4.9, 2.4);
				float td = sd_ellipse(f - tc, tr);
				vec2 tg = vec2(sd_ellipse(f + vec2(EPS, 0.0) - tc, tr) - td, sd_ellipse(f + vec2(0.0, EPS) - tc, tr) - td) / EPS;
				float ta = cov(td, px);
				c = mix(c, vec3(0.97, 0.98, 0.99), ta);
				gloss = mix(gloss, 0.7, ta);
				n = bump(n, td, tg, 2.0, ta * 0.8);
				// Cordones.
				vec2 lc = side ? vec2(0.6, -9.2) : vec2(0.0, -8.4);
				float laces = 1e3;
				for (int k = 0; k < 2; k++) {
					vec2 o = lc + vec2(side ? float(k) * 2.2 : 0.0, side ? float(k) * 0.9 : float(k) * 1.8);
					laces = min(laces, sd_segment(f, o - vec2(side ? 1.4 : 2.6, 0.0), o + vec2(side ? 1.4 : 2.6, 0.0)));
				}
				c = mix(c, vec3(1.0), 0.8 * stroke(laces, 0.42, px));
			} else {
				float heel = sd_rbox(f - vec2(0.0, -8.0), vec2(1.7, 2.2), 1.2);
				c = mix(c, darken(c, 0.25), cov(heel, px));
			}
			// Franja de color (acento) en el lado de fuera.
			vec2 sa = side ? vec2(-4.6, -4.2) : vec2(1.4 * s, -4.3);
			vec2 sb = side ? vec2(0.6, -7.6) : vec2(5.4 * s, -7.4);
			c = mix(c, accent_color.rgb, stroke(sd_segment(f, sa, sb), 0.8, px) * step(sole_line, 0.0));
			over(acc, shade(c, n, gloss, ao), cov(d, px));
		}
	}

	// 4. Cuerpo: torso, capucha y brazos en una sola silueta suave.
	if (q.y > -64.0 && q.y < -4.0 && abs(q.x) < 42.0) {
		float d = body_d(q);
		if (d < 3.0) {
			vec2 g = vec2(body_d(q + vec2(EPS, 0.0)) - d, body_d(q + vec2(0.0, EPS)) - d) / EPS;
			vec3 n = pillow(d, g, 11.0);
			float gloss = 0.05;
			float ao = 1.0;
			vec3 c = outfit;
			float dt = torso_d(q);
			// Brazos: su propio bulto y un pliegue donde pasan por delante del torso.
			float da = arms_d(q);
			float near_sh = min(length(q - shoulder(0)), length(q - shoulder(1)));
			if (side) {
				near_sh = length(q - shoulder(1));
			}
			float fade = smoothstep(2.0, 8.0, near_sh);
			float wa = cov(da, max(px, 1.4)) * fade;
			if (da < 6.0) {
				vec2 ga = vec2(arms_d(q + vec2(EPS, 0.0)) - da, arms_d(q + vec2(0.0, EPS)) - da) / EPS;
				n = bump(n, da, ga, 4.4, wa);
			}
			float in_torso = cov(dt, 1.5);
			ao *= 1.0 - 0.36 * in_torso * fade * exp(-max(da, 0.0) / 1.8) * step(0.0, da);
			ao *= 1.0 - 0.16 * in_torso * fade * exp(-sq(da / 0.7));
			// Capucha (cuello vuelto) un poco más clara, con su pliegue.
			if (hoodie) {
				float dc = collar_d(q);
				c = mix(c, lighten(outfit, 0.08), cov(dc, max(px, 1.0)) * (1.0 - wa));
				ao *= 1.0 - 0.22 * exp(-sq(dc / 0.9)) * cov(dt - 0.5, 1.0) * step(-42.0, q.y) * (1.0 - wa);
			}
			// Manos con su color de pelaje y puños.
			float arm_px = cov(da, px);
			for (int i = 0; i < 2; i++) {
				if (side && i == 0) {
					continue;
				}
				float s = i == 0 ? -1.0 : 1.0;
				vec2 el;
				vec2 wr;
				vec2 hc;
				float a2;
				arm_joints(i, el, wr, hc, a2);
				float hd = hand_d(q, hc, a2, side ? -1.0 : s);
				float band = cov(sd_segment(q, wr - rot(vec2(0.0, 1.6), a2), wr), px) * cov(sd_cone(q, el, wr, 4.4, 4.1), px);
				c = mix(c, darken(outfit, 0.22), band * arm_px);
				c = mix(c, fur_color.rgb, cov(hd, px) * arm_px);
				gloss = mix(gloss, 0.12, cov(hd, px) * arm_px);
				ao *= 1.0 - 0.18 * exp(-sq(hd / 0.6)) * arm_px;
			}
			// Detalles del pecho (no se ven de espaldas ni sobre los brazos).
			float front_k = (1.0 - arm_px) * (back ? 0.0 : 1.0);
			if (front_k > 0.0) {
				vec2 u = side ? vec2((q.x - 5.0) / 0.7, q.y) : q;
				if (!hoodie) {
					float shirt = sd_tri(u, vec2(-7.0, -44.0), vec2(7.0, -44.0), vec2(0.0, -30.0));
					c = mix(c, vec3(0.95, 0.96, 0.98), cov(shirt, px) * front_k);
					float lapel = 1e3;
					for (int i = 0; i < 2; i++) {
						float s = i == 0 ? -1.0 : 1.0;
						lapel = min(lapel, min(sd_tri(u, vec2(7.5 * s, -44.0), vec2(1.0 * s, -30.0), vec2(4.0 * s, -28.0)), sd_tri(u, vec2(7.5 * s, -44.0), vec2(4.0 * s, -28.0), vec2(11.0 * s, -40.0))));
					}
					c = mix(c, darken(outfit, 0.25), cov(lapel, px) * front_k);
					ao *= 1.0 - 0.2 * exp(-sq(lapel / 0.6)) * front_k * step(0.0, lapel);
					float knot = sd_rbox(u - vec2(0.0, -41.2), vec2(2.3, 1.6), 1.0);
					float blade = min(min(sd_tri(u, vec2(-1.7, -39.6), vec2(1.7, -39.6), vec2(3.6, -30.0)), sd_tri(u, vec2(-1.7, -39.6), vec2(3.6, -30.0), vec2(-3.6, -30.0))), sd_tri(u, vec2(-3.6, -30.0), vec2(3.6, -30.0), vec2(0.0, -26.0)));
					float tie = min(knot, blade - 0.25);
					float ta = cov(tie, px) * front_k;
					c = mix(c, accent_color.rgb, ta);
					gloss = mix(gloss, 0.35, ta);
					ao *= 1.0 - 0.25 * exp(-sq(max(tie, 0.0) / 0.7)) * step(0.0, tie) * front_k;
					for (int k = 0; k < 2; k++) {
						float bd = sd_circle(u - vec2(4.6, -24.0 + float(k) * 6.0), 1.15);
						c = mix(c, darken(outfit, 0.5), cov(bd, px) * front_k);
					}
				} else {
					float pocket = sd_rbox(u - vec2(0.0, -19.5), vec2(10.5, 4.8), 3.2);
					c = mix(c, darken(outfit, 0.12), cov(pocket, px) * front_k);
					ao *= 1.0 - 0.3 * exp(-sq(pocket / 0.6)) * front_k * step(-24.4, -u.y);
					float cords = min(sd_segment(u, vec2(-3.2, -41.5), vec2(-3.2, -33.5)), sd_segment(u, vec2(3.2, -41.5), vec2(3.2, -33.5)));
					c = mix(c, vec3(0.9, 0.92, 0.95), stroke(cords, 0.55, px) * front_k);
					float tips = min(sd_ellipse(u - vec2(-3.2, -32.6), vec2(1.2, 1.6)), sd_ellipse(u - vec2(3.2, -32.6), vec2(1.2, 1.6)));
					c = mix(c, vec3(0.92, 0.94, 0.97), cov(tips, px) * front_k);
					gloss = mix(gloss, 0.6, cov(tips, px) * front_k);
					// Acreditación colgada: la cinta lleva el acento.
					float strap = min(sd_segment(u, vec2(-5.3, -42.5), vec2(0.0, -30.6)), sd_segment(u, vec2(5.3, -42.5), vec2(0.0, -30.6)));
					c = mix(c, accent_color.rgb, stroke(strap, 0.85, px) * front_k);
					float card = sd_rbox(u - vec2(0.0, -26.4), vec2(3.6, 3.3), 0.7);
					c = mix(c, vec3(0.97, 0.98, 0.99), cov(card, px) * front_k);
					c = mix(c, accent_color.rgb, cov(max(card, u.y + 28.0), px) * front_k);
					c = mix(c, vec3(0.55, 0.6, 0.68), stroke(sd_segment(u, vec2(-2.0, -26.0), vec2(2.0, -26.0)), 0.3, px) * front_k * cov(card, px));
					gloss = mix(gloss, 0.4, cov(card, px) * front_k);
					ao *= 1.0 - 0.25 * exp(-sq(max(card, 0.0) / 0.6)) * step(0.0, card) * front_k;
				}
				// Correas de la mochila.
				float straps = 1e3;
				for (int i = 0; i < 2; i++) {
					float s = i == 0 ? -1.0 : 1.0;
					if (side && i == 0) {
						continue;
					}
					vec2 a = side ? vec2(3.0, -42.0) : vec2(10.6 * s, -42.5);
					vec2 b = side ? vec2(5.4, -25.0) : vec2(12.8 * s, -25.0);
					straps = min(straps, sd_segment(side ? q : u, a, b) - 1.7);
				}
				c = mix(c, darken(bag_color.rgb, 0.18), cov(straps, px) * front_k);
				ao *= 1.0 - 0.22 * exp(-sq(max(straps, 0.0) / 0.6)) * step(0.0, straps) * front_k;
			}
			if (back && !hoodie) {
				c = mix(c, darken(outfit, 0.3), stroke(sd_segment(q, vec2(0.0, -19.0), vec2(0.0, -11.0)), 0.4, px));
			}
			// Sombra de la cabeza (y la melena) sobre el cuello y los hombros.
			vec2 so = vec2(2.0 * flip, 6.0);
			float hs = sd_ellipse(q - head_anim.xy - so, head_r * (has_mane ? 1.12 : 0.98));
			ao *= 1.0 - 0.42 * (1.0 - smoothstep(-4.0, 6.0, hs));
			// Parte baja del cuerpo, más en sombra (oclusión del suelo).
			ao *= 1.0 - 0.18 * smoothstep(-20.0, -10.0, q.y) * (1.0 - wa);
			over(acc, shade(c, n, gloss, ao), cov(d / max(length(g), 0.5), px));
		}
	}

	// 5. De espaldas: mochila y cola delante del cuerpo.
	if (back) {
		float d = bag_d(q);
		if (d < 3.0) {
			vec2 g = vec2(bag_d(q + vec2(EPS, 0.0)) - d, bag_d(q + vec2(0.0, EPS)) - d) / EPS;
			vec3 n = pillow(d, g, 7.0);
			vec3 c = bag_color.rgb;
			float ao = 1.0;
			float pocket = sd_rbox(q - vec2(0.0, -23.5), vec2(8.6, 5.6), 3.6);
			vec2 pg = vec2(sd_rbox(q + vec2(EPS, 0.0) - vec2(0.0, -23.5), vec2(8.6, 5.6), 3.6) - pocket, sd_rbox(q + vec2(0.0, EPS) - vec2(0.0, -23.5), vec2(8.6, 5.6), 3.6) - pocket) / EPS;
			float pa = cov(pocket, px);
			c = mix(c, lighten(c, 0.12), pa);
			n = bump(n, pocket, pg, 2.5, pa * 0.8);
			ao *= 1.0 - 0.3 * exp(-sq(max(pocket, 0.0) / 0.8)) * step(0.0, pocket);
			float zips = min(sd_segment(q, vec2(-6.4, -27.4), vec2(6.4, -27.4)), abs(sd_ellipse(q - vec2(0.0, -31.0), vec2(10.4, 10.6))) + step(-33.0, q.y) * 10.0);
			c = mix(c, vec3(1.0), 0.32 * stroke(zips, 0.35, px));
			float hd = abs(sd_ellipse(q - vec2(0.0, -45.5), vec2(4.6, 2.8))) - 1.1;
			c = mix(c, darken(c, 0.25), cov(hd, px));
			ao *= 1.0 - 0.2 * smoothstep(-28.0, -18.0, q.y);
			over(acc, shade(c, n, 0.08, ao), cov(d, px));
		}
		if (tail_type != 0) {
			vec2 t = tail_frame(q);
			float td = tail_d(t);
			if (td < 3.0) {
				vec2 g = vec2(tail_d(tail_frame(q + vec2(EPS, 0.0))) - td, tail_d(tail_frame(q + vec2(0.0, EPS))) - td) / EPS;
				vec3 c = tail_color.rgb;
				if (tail_type == 1) {
					c = mix(c, tail_tip.rgb, cov(sd_circle(t - vec2(-9.8, -17.5), 4.4), 1.5));
				}
				if (tail_type == 2) {
					float rings = min(sd_ellipse(rot(t - vec2(-4.5, -6.0), 0.6), vec2(7.0, 1.9)), sd_ellipse(rot(t - vec2(-8.1, -12.0), 0.6), vec2(7.0, 1.9)));
					c = mix(c, tail_band.rgb, cov(rings, px));
				}
				if (tail_type == 4) {
					float bands = min(sd_segment(t, vec2(-2.0, -5.3), vec2(-6.5, -3.5)), sd_segment(t, vec2(-5.4, -11.6), vec2(-9.6, -9.6)));
					c = mix(c, tail_band.rgb, stroke(bands, 1.0, px));
				}
				if (has_mane && (tail_type == 3 || tail_type == 4)) {
					c = mix(c, mane_color.rgb, cov(sd_ellipse(t - vec2(-11.5, -20.5), vec2(3.8, 4.4)), 1.2));
				}
				over(acc, shade(c, pillow(td, g, tail_type == 5 ? 5.0 : 3.6), 0.0, 1.0), cov(td / max(length(g), 0.5), px));
			}
		}
	}

	vec2 h = to_head(q);
	if (length(h) < 80.0) {
		// 6. Melena por detrás de la cabeza.
		if (has_mane) {
			float d = mane_d(h);
			if (d < 3.0) {
				vec2 g = vec2(mane_d(h + vec2(EPS, 0.0)) - d, mane_d(h + vec2(0.0, EPS)) - d) / EPS;
				vec2 m = h - vec2(0.0, -1.0);
				float ang = atan(m.y, m.x);
				vec3 c = mane_color.rgb;
				float hc = head_core(h);
				float ao = 1.0 - 0.35 * exp(-max(hc, 0.0) / 3.0);
				ao *= 0.9 + 0.1 * cos(14.0 * ang);
				over(acc, shade(c, pillow(d, g, 7.0), 0.0, ao), cov(d / max(length(g), 0.5), px));
			}
		}

		// 7. Cabeza con mofletes y orejas fundidas.
		float d = head_d(h);
		if (d < 3.0) {
			vec2 g = vec2(head_d(h + vec2(EPS, 0.0)) - d, head_d(h + vec2(0.0, EPS)) - d) / EPS;
			float de = ears_d(h);
			float hc = head_core(h);
			float ear_zone = smoothstep(-1.5, 1.5, hc) * cov(de, 1.5);
			vec3 n = pillow(d, g, mix(19.0, 5.5, ear_zone));
			float gloss = 0.1;
			float ao = 1.0;
			vec3 c = fur_color.rgb;
			if (back && has_mane) {
				c = darken(mane_color.rgb, 0.04);
			}
			c = mix(c, ear_outer.rgb, ear_zone);
			// Interior de las orejas (solo por delante).
			if (!back && ear_zone > 0.0) {
				float inner = 1e3;
				for (int i = 0; i < 2; i++) {
					float s = i == 0 ? -1.0 : 1.0;
					float ea = head_anim.w * s;
					vec2 r = head_r;
					if (ear_type == 0) {
						vec2 cc = has_cap ? vec2(0.86 * r.x * s, -0.62 * r.y) : vec2(0.72 * r.x * s, -0.78 * r.y);
						inner = min(inner, sd_circle(h - cc - vec2(0.0, 0.5), 4.8));
					} else if (ear_type == 1 || ear_type == 2) {
						float H = ear_type == 2 ? 23.0 : 17.0;
						vec2 e = rot(h - vec2(0.55 * r.x * s, -0.70 * r.y), -(0.18 * s + ea));
						inner = min(inner, sd_tri(e, vec2(-3.4, 0.0), vec2(1.4 * s, -H * 0.66), vec2(3.4, 0.0)) - 0.8);
					} else if (ear_type == 3) {
						vec2 e = rot(h - vec2(8.5 * s, -r.y - 2.0), -(0.14 * s + ea));
						inner = min(inner, sd_ellipse(e - vec2(0.0, -12.5), vec2(2.9, 11.0)));
					}
				}
				float ia = cov(inner, px) * smoothstep(-0.5, 1.5, hc);
				c = mix(c, ear_inner.rgb, ia);
				ao *= 1.0 - 0.22 * ia * smoothstep(-2.5, 0.0, inner);
			}
			// Pliegue donde la oreja nace de la cabeza.
			ao *= 1.0 - 0.22 * exp(-sq(hc / 1.3)) * cov(de, 1.0);
			paint_face(h, px, c, gloss, n, ao);
			// Sombra de la visera en la frente.
			if (has_cap && !back) {
				float bs = brim_d(h - vec2(1.5 * flip, 3.6));
				ao *= 1.0 - 0.4 * (1.0 - smoothstep(-1.0, 4.0, bs));
				float cs = crown_d(h - vec2(1.0 * flip, 2.5));
				ao *= 1.0 - 0.3 * (1.0 - smoothstep(-1.0, 3.0, cs));
			}
			// Sombra de las orejas caídas sobre la cabeza.
			float fd = floppy_d(h);
			ao *= 1.0 - 0.32 * exp(-max(fd, 0.0) / 2.0) * step(0.0, fd);
			// Sombra suave del cuello bajo la barbilla.
			ao *= 1.0 - 0.12 * smoothstep(0.55, 1.0, h.y / head_r.y);
			over(acc, shade(c, n, gloss, ao), cov(d / max(length(g), 0.5), px));
		}

		// 7b. Orejas caídas (perro) por delante.
		if (ear_type == 4) {
			float fd = floppy_d(h);
			if (fd < 3.0) {
				vec2 g = vec2(floppy_d(h + vec2(EPS, 0.0)) - fd, floppy_d(h + vec2(0.0, EPS)) - fd) / EPS;
				over(acc, shade(ear_outer.rgb, pillow(fd, g, 4.5), 0.05, 1.0 - 0.15 * smoothstep(0.0, 22.0, h.y)), cov(fd, px));
			}
		}

		// 8. Gorra: copa, cinta, botón, logo (acento) y visera.
		if (has_cap) {
			float cd = crown_d(h);
			if (cd < 3.0) {
				vec2 g = vec2(crown_d(h + vec2(EPS, 0.0)) - cd, crown_d(h + vec2(0.0, EPS)) - cd) / EPS;
				vec3 n = pillow(cd, g, 10.0);
				vec3 c = cap_color.rgb;
				float gloss = 0.08;
				float ao = 1.0;
				vec2 r = head_r;
				float band = h.y + 0.49 * r.y;
				c = mix(c, darken(cap_color.rgb, 0.28), cov(-band, px));
				ao *= 1.0 - 0.2 * exp(-sq(band / 0.6));
				vec2 bc = vec2(view == 1 ? -1.0 : 0.0, -1.27 * r.y);
				float btn = sd_circle(h - bc, 2.3);
				vec2 bg = vec2(sd_circle(h + vec2(EPS, 0.0) - bc, 2.3) - btn, sd_circle(h + vec2(0.0, EPS) - bc, 2.3) - btn) / EPS;
				float ba = cov(btn, px);
				c = mix(c, lighten(cap_color.rgb, 0.18), ba);
				n = bump(n, btn, bg, 1.6, ba);
				// Costuras de los paneles.
				if (!side) {
					float seams = min(abs(h.x - 0.36 * r.x * smoothstep(-1.27 * r.y, -0.5 * r.y, h.y)), abs(h.x + 0.36 * r.x * smoothstep(-1.27 * r.y, -0.5 * r.y, h.y)));
					c = mix(c, darken(cap_color.rgb, 0.18), stroke(seams, 0.3, px) * step(0.0, -band) * 0.8);
				}
				if (back) {
					float gap = sd_rbox(h - vec2(0.0, -0.47 * r.y), vec2(5.0, 2.6), 2.2);
					c = mix(c, darken(cap_color.rgb, 0.6), cov(gap, px));
				} else {
					vec2 lc = side ? vec2(0.46 * r.x, -0.78 * r.y) : vec2(0.0, -0.80 * r.y);
					vec2 lr = side ? vec2(3.0, 3.0) : vec2(5.4, 3.4);
					float logo = sd_rbox(h - lc, lr, 2.2);
					float la = cov(logo, px);
					c = mix(c, accent_color.rgb, la);
					gloss = mix(gloss, 0.5, la);
					vec2 lg = vec2(sd_rbox(h + vec2(EPS, 0.0) - lc, lr, 2.2) - logo, sd_rbox(h + vec2(0.0, EPS) - lc, lr, 2.2) - logo) / EPS;
					n = bump(n, logo, lg, 1.5, la * 0.7);
				}
				over(acc, shade(c, n, gloss, ao), cov(cd / max(length(g), 0.5), px));
			}
			float bd = brim_d(h);
			if (bd < 3.0) {
				vec2 g = vec2(brim_d(h + vec2(EPS, 0.0)) - bd, brim_d(h + vec2(0.0, EPS)) - bd) / EPS;
				vec3 c = darken(cap_color.rgb, 0.08);
				float under = side ? 0.0 : smoothstep(-1.0, 3.0, h.y + 0.37 * head_r.y);
				float ao = 1.0 - 0.35 * under;
				over(acc, shade(c, pillow(bd, g, 2.6), 0.1, ao), cov(bd, px));
			}
		}
	}

	if (acc.a <= 0.002) {
		discard;
	}
	vec3 rgb = acc.rgb / acc.a;
	if (linear_output && output_mode == 0) {
		rgb = to_linear(rgb);
	}
	COLOR = vec4(rgb, acc.a) * COLOR;
}
