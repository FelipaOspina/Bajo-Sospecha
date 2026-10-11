class_name PetReactions
extends RefCounted
## Reacciones de la mascota del lobby: una propia de cada animal al tocarla y las
## comunes (caricia, comer, beber, "ya estoy lleno"). Son animación procedural: cada
## una es una función del tiempo que devuelve cómo mover el chibi entero (salto, giro,
## estirón) y el gesto que pinta el shader (ojos de gusto, boca abierta, cabeza, brazos
## y cola; ver ProceduralChibiAvatar.emote).
##
## sample(kind, t) → {offset: Vector2, rot: float, pivot: Vector2, scale: Vector2, emote: {}}
## en unidades del chibi (origen en los pies, ~100 de alto). El giro es alrededor de pivot.

const DURATION := {
	"mane_shake": 1.4, "howl": 1.8, "chuff": 1.3, "pounce": 1.3, "meow": 1.5, "wag": 1.6,
	"sway": 2.0, "roll": 1.6, "binky": 1.5, "rub_hands": 1.6, "head_turn": 1.8, "flap": 1.6,
	"cuddle": 1.2, "eat": 1.5, "drink": 1.4, "refuse": 0.9,
}
## Una por animal (pets.json "tap"); el resto son comunes.
const TAP_KINDS := ["mane_shake", "howl", "chuff", "pounce", "meow", "wag", "sway", "roll", "binky", "rub_hands", "head_turn", "flap"]
const CENTER := Vector2(0, -45)
## Brazos en reposo (hombro y codo, izquierdo y derecho).
const ARMS_REST := Vector4(0.16, -0.25, -0.16, 0.25)

static func duration(kind: String) -> float:
	return float(DURATION.get(kind, 1.2))

static func has_kind(kind: String) -> bool:
	return DURATION.has(kind)

static func rest() -> Dictionary:
	return {"offset": Vector2.ZERO, "rot": 0.0, "pivot": CENTER, "scale": Vector2.ONE, "emote": {}}

static func sample(kind: String, t: float) -> Dictionary:
	var d := duration(kind)
	var u := clampf(t / d, 0.0, 1.0)
	var r := rest()
	var e := {}
	var fade := _fade(u)   # entra y sale suave
	match kind:
		"mane_shake":   # león: sacude la melena con un rugido corto y acaba sonriendo
			var shake := sin(t * 26.0) * 0.24 * (1.0 - u) * fade
			e["head"] = Vector3(sin(t * 26.0) * 1.5 * (1.0 - u), 0.0, shake)
			e["mouth"] = _window(u, 0.0, 0.45) * 0.8
			e["smile"] = _window(u, 0.55, 1.0)
			r["scale"] = Vector2(1.0 + 0.04 * fade, 1.0 - 0.02 * fade)
		"howl":   # lobo: se estira, cierra los ojos y aúlla bajito
			var up := _window(u, 0.15, 0.9)
			r["scale"] = Vector2(1.0 - 0.04 * up, 1.0 + 0.08 * up) if u > 0.15 else Vector2(1.04, 0.94 + 0.06 * (1.0 - _window(u, 0.0, 0.15)))
			e["head"] = Vector3(0.0, -4.0 * up, 0.0)
			e["mouth"] = up * 0.9
			e["smile"] = up
			e["tail_amp"] = 1.6
		"chuff":   # tigre: tres resoplidos amistosos con la cabeza
			var beat := absf(sin(u * PI * 3.0))
			e["head"] = Vector3(0.0, 2.2 * beat, sin(u * PI * 3.0) * 0.05)
			e["mouth"] = beat * 0.45 * fade
			e["smile"] = _window(u, 0.6, 1.0)
			r["rot"] = sin(u * TAU) * 0.05 * fade
			r["scale"] = Vector2(1.0 + 0.02 * beat, 1.0 - 0.03 * beat)
		"pounce":   # zorro: se agacha y salta en arco como cuando caza en la nieve
			if u < 0.27:
				var k := _ease(u / 0.27)
				r["scale"] = Vector2(1.0 + 0.1 * k, 1.0 - 0.14 * k)
			elif u < 0.75:
				var k := (u - 0.27) / 0.48
				r["offset"] = Vector2(0.0, -46.0 * sin(k * PI))
				r["rot"] = sin(k * PI) * -0.18
				r["scale"] = Vector2(0.94, 1.08)
				e["smile"] = 1.0
				e["tail_amp"] = 2.0
			else:
				var k := (u - 0.75) / 0.25
				var land := sin(k * PI) * (1.0 - k)
				r["scale"] = Vector2(1.0 + 0.12 * land, 1.0 - 0.14 * land)
				e["smile"] = 1.0 - k
		"meow":   # gato: ladea la cabeza, maúlla y barre el aire con la cola
			e["head"] = Vector3(0.0, 0.0, 0.22 * fade)
			e["mouth"] = _window(u, 0.18, 0.62) * 0.75
			e["tail_speed"] = 0.45
			e["tail_amp"] = 2.4
			e["smile"] = _window(u, 0.66, 1.0)
			r["offset"] = Vector2(0.0, -6.0 * _bump(u, 0.05, 0.3))
		"wag":   # perro: dos saltitos, la lengua fuera y la cola a toda velocidad
			var hop := maxf(_bump(u, 0.05, 0.42), _bump(u, 0.5, 0.87))
			r["offset"] = Vector2(0.0, -16.0 * hop)
			r["scale"] = Vector2(1.0 - 0.04 * hop, 1.0 + 0.05 * hop)
			e["tail_speed"] = 4.5
			e["tail_amp"] = 2.2
			e["mouth"] = 0.65 * fade
			e["smile"] = fade
		"sway":   # oso: se mece de un pie al otro con los brazos abiertos
			r["pivot"] = Vector2.ZERO
			r["rot"] = sin(u * TAU * 2.0) * 0.13 * fade
			e["arms"] = ARMS_REST.lerp(Vector4(1.55, -0.65, -1.55, 0.65), fade)
			e["smile"] = fade
			e["mouth"] = 0.3 * fade
		"roll":   # panda: una voltereta entera y un pelín de mareo
			if u < 0.12:
				r["scale"] = Vector2(1.06, 1.0 - 0.1 * _ease(u / 0.12))
			elif u < 0.72:
				var k := _ease((u - 0.12) / 0.6)
				r["rot"] = k * TAU
				r["offset"] = Vector2(0.0, -22.0 * sin(k * PI))
				r["scale"] = Vector2(0.92, 0.92)
				e["smile"] = 1.0
			else:
				var k := (u - 0.72) / 0.28
				e["head"] = Vector3(0.0, 0.0, sin(k * TAU * 1.5) * 0.16 * (1.0 - k))
				e["smile"] = 1.0 - k
		"binky":   # conejo: dos saltos con giro en el aire (binky)
			var j1 := _bump(u, 0.06, 0.48)
			var j2 := _bump(u, 0.56, 0.86)
			r["offset"] = Vector2(0.0, -34.0 * j1 - 16.0 * j2)
			var twist := sin(clampf((u - 0.06) / 0.42, 0.0, 1.0) * TAU)
			r["scale"] = Vector2(1.0 - 0.35 * absf(twist) * (1.0 if j1 > 0.0 else 0.0), 1.0 + 0.04 * (j1 + j2))
			r["rot"] = 0.12 * j2
			e["smile"] = maxf(j1, j2)
		"rub_hands":   # mapache: se frota las manitas delante del pecho
			var rub := sin(t * 22.0) * 0.18
			e["arms"] = ARMS_REST.lerp(Vector4(-0.3 + rub, -1.3, 0.3 + rub, 1.3), fade)
			e["head"] = Vector3(0.0, 1.0 * fade, sin(t * 5.0) * 0.06 * fade)
			e["smile"] = fade
			r["scale"] = Vector2(1.0, 1.0 - 0.025 * absf(sin(t * 11.0)) * fade)
		"head_turn":   # búho: gira la cabeza a un lado, al otro, y ahueca las plumas
			var turn := sin(u * TAU) * 0.55 * fade
			e["head"] = Vector3(0.0, 0.0, turn)
			var fluff := _window(u, 0.7, 1.0)
			r["scale"] = Vector2(1.0 + 0.07 * fluff, 1.0 + 0.02 * fluff)
			e["smile"] = fluff
		"flap":   # pingüino: aletea, se bambolea y abre el pico para cantar
			var f := sin(t * 20.0)
			e["arms"] = ARMS_REST.lerp(Vector4(0.7 + 0.5 * f, 0.0, -0.7 - 0.5 * f, 0.0), fade)
			r["pivot"] = Vector2.ZERO
			r["rot"] = sin(t * 9.0) * 0.08 * fade
			e["head"] = Vector3(0.0, -2.0 * fade, 0.0)
			e["mouth"] = _window(u, 0.2, 0.8) * 0.85
			e["smile"] = _window(u, 0.25, 0.85)
		"cuddle":   # caricia (común): se arrima a la mano, ojos de gusto y cola lenta
			r["pivot"] = Vector2.ZERO
			r["rot"] = sin(t * 4.0) * 0.06 * fade
			r["scale"] = Vector2(1.0 + 0.04 * fade, 1.0 - 0.035 * fade)
			e["smile"] = fade
			e["head"] = Vector3(0.0, 1.0 * fade, 0.12 * fade)
			e["tail_speed"] = 0.5
			e["tail_amp"] = 1.8
		"eat":   # comer: mira la comida, mastica tres veces y queda contento
			var chew := absf(sin((u - 0.15) * PI * 4.0)) if u > 0.15 and u < 0.8 else 0.0
			e["head"] = Vector3(0.0, 2.5 * fade, 0.0)
			e["mouth"] = chew * 0.7
			e["smile"] = _window(u, 0.8, 1.0)
			r["scale"] = Vector2(1.0 + 0.02 * chew, 1.0 - 0.025 * chew)
			e["tail_speed"] = 2.0
		"drink":   # beber: cabeza abajo y lengüetazos rápidos
			var lap := absf(sin(t * 24.0)) if u > 0.1 and u < 0.8 else 0.0
			e["head"] = Vector3(0.0, 3.0 * fade, 0.0)
			e["mouth"] = lap * 0.4
			e["smile"] = _window(u, 0.8, 1.0)
		"refuse":   # ya está lleno: niega con la cabeza
			e["head"] = Vector3(0.0, 0.0, sin(u * TAU * 2.0) * 0.2 * (1.0 - u))
	r["emote"] = e
	return r

## 0 → 1 → 0 a lo largo de la reacción, con entrada y salida suaves (15 %).
static func _fade(u: float) -> float:
	return smoothstep(0.0, 0.15, u) * (1.0 - smoothstep(0.85, 1.0, u))

## 1 dentro de [a, b] con bordes suaves.
static func _window(u: float, a: float, b: float) -> float:
	var edge := minf(0.08, (b - a) / 3.0)
	return smoothstep(a, a + edge, u) * (1.0 - smoothstep(b - edge, b, u))

## Arco de salto (0 fuera de [a, b], 1 en el medio).
static func _bump(u: float, a: float, b: float) -> float:
	if u <= a or u >= b:
		return 0.0
	return sin((u - a) / (b - a) * PI)

static func _ease(x: float) -> float:
	return x * x * (3.0 - 2.0 * x)
