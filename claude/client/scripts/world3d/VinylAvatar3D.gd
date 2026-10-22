class_name VinylAvatar3D
extends Node3D
## Personaje 3D estilo "juguete de vinilo" (como el pingüino CEO de referencia):
## cuerpo-cabeza en forma de huevo brillante, carita clara, ojos grandes con brillos,
## mejillas sonrosadas, bracitos, zapatillas gorditas y rasgos de cada animal
## (orejas, hocico, cola, melena, antifaz...). Todo se arma con primitivas a partir de
## data/skins/skins.json, así que no hace falta ningún modelo externo.
##
## Animación procedural: mira hacia donde camina, pasos alternos con las zapatillas,
## balanceo de pingüino, braceo y respiración en reposo. La cara mira a +Z.
## Reacciones de mascota (sala de espera): react("hop" | "spin" | "wiggle" | "squish"...)
## mueven un nodo aparte (_rig) que envuelve todo el modelo, así que no chocan con el
## paso ni con el giro de animate().
## Nunca muestra el rol: solo usa colores de la skin y de los cosméticos públicos.

const HEIGHT := 1.32            # alto total aproximado (m), para colocar el nombre encima
const BODY_R := 0.42
const BODY_H := 0.96
const BODY_Y := 0.64            # centro del huevo
const SEAM_Y := BODY_Y - 0.12    # donde empieza la ropa

var skin_id := ""
var skin: Dictionary = {}

var _rig: Node3D                 # reacciones: salto, giro, estirón (envuelve todo)
var _pivot: Node3D               # balanceo y rebote
var _foot_l: Node3D
var _foot_r: Node3D
var _arm_l: Node3D
var _arm_r: Node3D
var _tail: Node3D
var _phase := 0.0
var _amp := 0.0
var _time := 0.0
var _yaw := 0.0
var _alpha := 1.0
var _materials: Array[StandardMaterial3D] = []
var _eye_pivots: Array[Node3D] = []
var _react_kind := ""
var _react_t := 0.0
var _react_len := 1.0
var _happy := 0.0

static var _mat_cache := {}

## Arma el modelo. look: cosméticos públicos (ropa, gorra, zapatillas, mochila).
func build(id: String, look: Dictionary = {}) -> void:
	for c in get_children():
		c.queue_free()
	_materials.clear()
	_eye_pivots.clear()
	_react_kind = ""
	_happy = 0.0
	skin_id = id
	skin = CosmeticCatalog.dress(SkinCatalog.skin(id), look)
	var fur := _c("fur", "#9CA3AF")
	var light := _c("fur_light", "#F8FAFC")
	var outfit := _c("outfit", "#1E293B")
	var shoes := _c("shoes", "#F1F5F9")
	var sb: Array = skin.get("scale_body", [1.0, 1.0])
	var wide := float(sb[0]) if sb.size() > 0 else 1.0
	var tall := float(sb[1]) if sb.size() > 1 else 1.0

	_rig = Node3D.new()
	_rig.name = "Rig"
	add_child(_rig)
	_pivot = Node3D.new()
	_pivot.name = "Pivot"
	_rig.add_child(_pivot)
	var body := Node3D.new()
	body.name = "Body"
	body.scale = Vector3(wide, tall, wide * 0.96)
	_pivot.add_child(body)

	var is_penguin := id == "pinguino"
	var style := str(skin.get("style", "hoodie"))
	# Cuerpo-cabeza: un solo huevo brillante. Con ropa, la mitad de abajo es la prenda
	# (sudadera o traje) y un cuello acolchado tapa la unión. El pingüino va como la referencia.
	if is_penguin:
		_sphere(body, Vector3(0, BODY_Y, 0), BODY_R, BODY_H, fur)
	else:
		_sphere(body, Vector3(0, BODY_Y, 0), BODY_R, BODY_H, fur)
		var cloth := _sphere(body, Vector3(0, SEAM_Y, 0), 0.415, 0.74, outfit, true)
		cloth.rotation.x = PI
		var collar := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.37
		tm.outer_radius = 0.445
		tm.rings = 32
		collar.mesh = tm
		collar.material_override = _mat(outfit.lightened(0.08))
		collar.position.y = SEAM_Y
		collar.scale = Vector3(1.0, 0.75, 1.0)
		body.add_child(collar)
		if style == "suit":
			_suit_details(body, light)
		else:
			_hoodie_details(body, outfit)
		_badge(body)

	# Cara clara.
	var patches := str(skin.get("patches", ""))
	if is_penguin or patches == "face":
		_penguin_face(body, light)
	else:
		_sphere(body, Vector3(0, BODY_Y + 0.06, 0.2), 0.27, 0.42, light, false, Vector3(1.15, 1.0, 0.85))
	match patches:
		"panda":
			for s in [-1, 1]:
				var p := _sphere(body, Vector3(0.115 * s, BODY_Y + 0.15, 0.36), 0.085, 0.15, Color("#18181B"))
				p.rotation.z = -0.5 * s
		"mask":
			_sphere(body, Vector3(0, BODY_Y + 0.15, 0.2), 0.28, 0.13, Color("#1F2937"), false, Vector3(1.2, 1.0, 0.76))

	_eyes(body, is_penguin)
	_cheeks(body)
	_snout(body, id, light)
	_ears(body, str(skin.get("ear_type", "none")), fur, light)
	if skin.has("mane"):
		var mane := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = 0.30
		torus.outer_radius = 0.47
		mane.mesh = torus
		mane.material_override = _mat(Color(str(skin["mane"])))
		mane.rotation.x = PI / 2.0
		mane.position = Vector3(0, BODY_Y + 0.12, 0.05)
		mane.scale = Vector3(1.0, 0.6, 1.0)
		body.add_child(mane)
	if id == "tigre":
		for i in 3:
			_box(body, Vector3((i - 1) * 0.1, BODY_Y + BODY_H * 0.47, 0.06), Vector3(0.035, 0.03, 0.2), Color("#3B2416"))
	if id == "dino":
		for i in 4:
			var spike := _cone(body, Vector3(0, BODY_Y + 0.38 - i * 0.18, -0.36 + i * 0.03), 0.06, 0.13, Color("#FACC15"))
			spike.rotation.x = -0.5 - i * 0.25
	if is_penguin:
		for i in 3:
			var tuft := _capsule(body, Vector3((i - 1) * 0.05, BODY_Y + BODY_H * 0.5 + 0.03, 0.02), 0.035, 0.16, fur)
			tuft.rotation = Vector3(-0.4, 0, (i - 1) * 0.45)
	if skin.get("hat", "") == "cap":
		_cap(body, Color(str(skin.get("hat_color", "#1E293B"))))
	if skin.has("bag") and look.has("bag"):
		_box(body, Vector3(0, BODY_Y - 0.05, -0.43), Vector3(0.36, 0.38, 0.14), Color(str(skin["bag"])))

	# Brazos (giran desde el hombro).
	var arm_color := fur if is_penguin else outfit
	_arm_l = _limb_pivot(_pivot, Vector3(-0.40 * wide, BODY_Y + 0.02, 0))
	_arm_r = _limb_pivot(_pivot, Vector3(0.40 * wide, BODY_Y + 0.02, 0))
	for arm in [_arm_l, _arm_r]:
		var s := -1.0 if arm == _arm_l else 1.0
		if is_penguin:
			var flip := _sphere(arm, Vector3(0.03 * s, -0.16, 0), 0.075, 0.34, arm_color, false, Vector3(0.55, 1.0, 1.0))
			flip.rotation.z = 0.35 * s
		else:
			var sleeve := _capsule(arm, Vector3(0.03 * s, -0.12, 0), 0.07, 0.24, arm_color)
			sleeve.rotation.z = 0.3 * s
			_sphere(arm, Vector3(0.07 * s, -0.25, 0.01), 0.06, 0.12, fur)   # manita

	# Piernas cortas y zapatillas gorditas.
	_foot_l = _limb_pivot(_rig, Vector3(-0.15 * wide, 0.0, 0))
	_foot_r = _limb_pivot(_rig, Vector3(0.15 * wide, 0.0, 0))
	for foot in [_foot_l, _foot_r]:
		_capsule(foot, Vector3(0, 0.16, -0.01), 0.065, 0.2, fur.darkened(0.25) if not is_penguin else fur)
		_shoe(foot, shoes)

	var tail_type := str(skin.get("tail", "none"))
	if tail_type != "none":
		_tail = _limb_pivot(_pivot, Vector3(0, 0.38, -0.38 * wide))
		match tail_type:
			"bushy":
				var t := _sphere(_tail, Vector3(0, 0.08, -0.14), 0.12, 0.36, fur)
				t.rotation.x = -0.9
				_sphere(_tail, Vector3(0, 0.2, -0.26), 0.08, 0.14, light)
			"puff":
				_sphere(_tail, Vector3(0, 0.0, -0.04), 0.09, 0.18, light if id != "oso" else fur)
			"ringed", "striped":
				for i in 4:
					var ring := _sphere(_tail, Vector3(0, 0.03 + i * 0.07, -0.08 - i * 0.05), 0.07, 0.11, fur if i % 2 == 0 else Color("#1F2937"))
					ring.rotation.x = -0.8
			_:
				var t2 := _capsule(_tail, Vector3(0, 0.1, -0.12), 0.04, 0.3, fur)
				t2.rotation.x = -0.9
	_apply_alpha()

## Opacidad (desconexión, camuflaje): 1 = sólido.
func set_alpha(a: float) -> void:
	if is_equal_approx(a, _alpha):
		return
	_alpha = a
	_apply_alpha()

## velocity_dir: dirección de movimiento en el mundo 3D (y = 0). speed_ratio: 0..1.5.
func animate(delta: float, velocity_dir: Vector3, speed_ratio: float) -> void:
	if _pivot == null:
		return
	_time += delta
	var moving := speed_ratio > 0.08
	_amp = move_toward(_amp, 1.0 if moving else 0.0, delta * 7.0)
	if moving:
		_phase += delta * TAU * (1.7 + 1.1 * clampf(speed_ratio, 0.0, 1.5))
		var target := atan2(velocity_dir.x, velocity_dir.z)
		_yaw = lerp_angle(_yaw, target, clampf(delta * 12.0, 0.0, 1.0))
		rotation.y = _yaw
	var s := sin(_phase)
	var c := cos(_phase)
	# Rebote y balanceo de pingüino.
	_pivot.position.y = absf(s) * 0.05 * _amp + sin(_time * 2.2) * 0.008 * (1.0 - _amp)
	_pivot.rotation.z = s * 0.09 * _amp
	_pivot.rotation.x = 0.06 * _amp
	_pivot.scale = Vector3(1.0, 1.0 + sin(_time * 2.2) * 0.012 * (1.0 - _amp), 1.0)
	# Pasos alternos: adelante/atrás y levantando el pie que avanza.
	_foot_l.position.z = s * 0.13 * _amp
	_foot_r.position.z = -s * 0.13 * _amp
	_foot_l.position.y = maxf(0.0, c) * 0.07 * _amp
	_foot_r.position.y = maxf(0.0, -c) * 0.07 * _amp
	_foot_l.rotation.x = -s * 0.35 * _amp
	_foot_r.rotation.x = s * 0.35 * _amp
	# Braceo contrario a los pies; en reposo, un saludito leve de vez en cuando.
	_arm_l.rotation.x = -s * 0.7 * _amp
	_arm_r.rotation.x = s * 0.7 * _amp
	_arm_l.rotation.z = -0.15 - 0.05 * sin(_time * 2.2) * (1.0 - _amp)
	_arm_r.rotation.z = 0.15 + 0.05 * sin(_time * 2.2) * (1.0 - _amp)
	if _tail:
		_tail.rotation.y = sin(_time * 5.0 + _phase) * (0.25 + 0.3 * _amp)
	_tick_reaction(delta)

## Mira hacia una dirección sin caminar (al aparecer o en el menú).
func face(yaw: float) -> void:
	_yaw = yaw
	rotation.y = yaw

# ── reacciones (mascota) ────────────────────────────────────────────────────

## Movimientos de reacción: duración por defecto (s). Se reproducen dentro de animate().
const REACTIONS := {
	"hop": 0.5, "double_hop": 1.6, "spin": 1.5, "flip": 1.6, "wiggle": 1.4, "squish": 1.2,
	"nod": 1.5, "shake": 0.9, "sway": 2.0, "flap": 1.6, "stretch": 1.8, "pounce": 1.3,
	"tilt": 1.5, "rub": 1.6, "look": 1.8, "pop": 0.45,
}

## Empieza una reacción (ver REACTIONS); duration <= 0 usa la de serie. Corta la anterior.
func react(kind: String, duration := 0.0) -> void:
	if not REACTIONS.has(kind):
		return
	_react_kind = kind
	_react_t = 0.0
	_react_len = duration if duration > 0.0 else float(REACTIONS[kind])

func is_reacting() -> bool:
	return _react_kind != ""

## 0..1: cuánto entorna los ojos de gusto ahora mismo.
func happy_amount() -> float:
	return _happy

## Transformación de la reacción en curso (identidad en reposo).
func rig_transform() -> Transform3D:
	return _rig.transform if _rig else Transform3D.IDENTITY

func _tick_reaction(delta: float) -> void:
	if _rig == null:
		return
	if _react_kind == "":
		if _happy > 0.0 or _rig.transform != Transform3D.IDENTITY:
			_happy = 0.0
			_rig.transform = Transform3D.IDENTITY
			_set_eyes(0.0)
		return
	_react_t += delta
	if _react_t >= _react_len:
		_react_kind = ""
		_tick_reaction(0.0)
		return
	var t := _react_t
	var u := clampf(t / _react_len, 0.0, 1.0)
	var f := _fade(u)
	var off := Vector3.ZERO
	var rot := Vector3.ZERO
	var scl := Vector3.ONE
	var center := BODY_Y   # altura del punto de giro (0 = los pies)
	var happy := 0.0
	var arms := Vector3.ZERO   # x: hacia delante (ambos), y: abrir (z), z: alternar
	match _react_kind:
		"hop":   # saltito (al ponerse LISTO)
			var j := _bump(u, 0.0, 1.0)
			off.y = 0.22 * j
			scl = Vector3(1.0 - 0.05 * j, 1.0 + 0.07 * j, 1.0 - 0.05 * j)
		"pop":   # aparece con un rebote
			var k := _ease(u)
			var s := 0.3 + 0.7 * k + sin(u * PI) * 0.18
			scl = Vector3(s, s, s)
			center = 0.0
		"double_hop":   # dos saltitos contentos meneando el cuerpo
			var h := maxf(_bump(u, 0.05, 0.42), _bump(u, 0.5, 0.87) * 0.7)
			off.y = 0.26 * h
			rot.z = sin(t * 18.0) * 0.08 * f
			scl = Vector3(1.0 - 0.04 * h, 1.0 + 0.06 * h, 1.0 - 0.04 * h)
			arms.y = 0.9 * h
			happy = f
		"spin":   # salto con una vuelta entera en el aire
			var j2 := _bump(u, 0.08, 0.7)
			off.y = 0.42 * j2
			rot.y = TAU * _ease(clampf((u - 0.08) / 0.62, 0.0, 1.0))
			var land := _bump(u, 0.7, 0.95)
			scl = Vector3(1.0 + 0.1 * land, 1.0 - 0.12 * land, 1.0 + 0.1 * land)
			arms.y = 1.1 * j2
			happy = maxf(j2, land)
		"flip":   # voltereta hacia atrás y un pelín de mareo
			if u < 0.12:
				var c := _ease(u / 0.12)
				scl = Vector3(1.0 + 0.06 * c, 1.0 - 0.1 * c, 1.0 + 0.06 * c)
			elif u < 0.72:
				var k2 := _ease((u - 0.12) / 0.6)
				rot.x = -k2 * TAU
				off.y = 0.4 * sin(k2 * PI)
				happy = 1.0
			else:
				var k3 := (u - 0.72) / 0.28
				rot.z = sin(k3 * TAU * 1.5) * 0.14 * (1.0 - k3)
				happy = 1.0 - k3
		"wiggle":   # sacude la cabeza (y la melena) y acaba sonriendo
			rot.z = sin(t * 26.0) * 0.2 * (1.0 - u) * f
			rot.y = sin(t * 13.0) * 0.15 * (1.0 - u) * f
			scl = Vector3(1.0 + 0.04 * f, 1.0 - 0.02 * f, 1.0 + 0.04 * f)
			happy = _window(u, 0.55, 1.0)
		"squish":   # caricia: se aplasta de gusto y se mece
			var w := sin(t * 9.0) * 0.025
			scl = Vector3(1.0 + 0.07 * f + w * f, 1.0 - 0.07 * f - w * f, 1.0 + 0.07 * f + w * f)
			rot.z = sin(t * 4.0) * 0.07 * f
			center = 0.0
			happy = f
		"nod":   # comer y beber: cabeceos hacia la comida
			var beat := absf(sin(u * PI * 4.0)) if u > 0.12 and u < 0.82 else 0.0
			rot.x = (0.12 + 0.16 * beat) * f
			scl = Vector3(1.0 + 0.02 * beat, 1.0 - 0.03 * beat, 1.0)
			center = 0.0
			happy = _window(u, 0.8, 1.0)
		"shake":   # ya está lleno: dice que no
			rot.y = sin(u * TAU * 2.0) * 0.45 * (1.0 - u)
		"sway":   # se mece de un pie al otro con los brazos abiertos
			rot.z = sin(u * TAU * 2.0) * 0.16 * f
			center = 0.0
			arms.y = 1.3 * f
			happy = f
		"flap":   # aletea y se bambolea
			rot.z = sin(t * 9.0) * 0.08 * f
			center = 0.0
			arms.y = (0.9 + 0.6 * sin(t * 20.0)) * f
			happy = _window(u, 0.25, 0.85)
		"stretch":   # se estira mirando arriba (aullido)
			var up := _window(u, 0.15, 0.9)
			scl = Vector3(1.0 - 0.04 * up, 1.0 + 0.1 * up, 1.0 - 0.04 * up)
			rot.x = -0.28 * up
			center = 0.0
			arms.y = 0.5 * up
			happy = up
		"pounce":   # se agacha y salta en arco hacia delante
			if u < 0.27:
				var k4 := _ease(u / 0.27)
				scl = Vector3(1.0 + 0.1 * k4, 1.0 - 0.15 * k4, 1.0 + 0.1 * k4)
				center = 0.0
			elif u < 0.75:
				var k5 := (u - 0.27) / 0.48
				off = Vector3(0.0, 0.5 * sin(k5 * PI), 0.25 * sin(k5 * PI))
				rot.x = 0.3 * sin(k5 * PI)
				scl = Vector3(0.95, 1.08, 0.95)
				arms.x = 1.2 * sin(k5 * PI)
				happy = 1.0
			else:
				var k6 := (u - 0.75) / 0.25
				var land2 := sin(k6 * PI) * (1.0 - k6)
				scl = Vector3(1.0 + 0.12 * land2, 1.0 - 0.14 * land2, 1.0 + 0.12 * land2)
				center = 0.0
				happy = 1.0 - k6
		"tilt":   # ladea la cabeza con un saltito (maullido)
			rot.z = 0.22 * f
			off.y = 0.06 * _bump(u, 0.05, 0.3)
			happy = _window(u, 0.6, 1.0)
		"rub":   # se frota las manitas delante del pecho
			arms.x = 1.1 * f
			arms.z = sin(t * 22.0) * 0.35 * f
			scl = Vector3(1.0, 1.0 - 0.025 * absf(sin(t * 11.0)) * f, 1.0)
			center = 0.0
			happy = f
		"look":   # mira a un lado y al otro y ahueca las plumas
			rot.y = sin(u * TAU) * 0.8 * f
			var fluff := _window(u, 0.7, 1.0)
			scl = Vector3(1.0 + 0.08 * fluff, 1.0 + 0.02 * fluff, 1.0 + 0.08 * fluff)
			happy = fluff
	var basis := Basis.from_euler(rot) * Basis.from_scale(scl)
	var c3 := Vector3(0.0, center, 0.0)
	_rig.transform = Transform3D(basis, off + c3 - basis * c3)
	_happy = happy
	_set_eyes(happy)
	if arms != Vector3.ZERO and _arm_l:
		_arm_l.rotation.x += -arms.x + arms.z
		_arm_r.rotation.x += -arms.x - arms.z
		_arm_l.rotation.z -= arms.y
		_arm_r.rotation.z += arms.y

## Cuerpo en el suelo (silenciado): ojos cerrados (noqueado) o ojos en X de dibujo
## animado (fuera de juego). Nada gore: solo la cara de "K.O." de los cartoons.
func set_knocked_face(kind: String) -> void:
	for p in _eye_pivots:
		for c in p.get_children():
			if c.has_meta("ko_x"):
				c.queue_free()
			elif c is MeshInstance3D:
				c.visible = kind != "dead"
	if kind == "dead":
		_set_eyes(0.0)
		var ink := Color("#0B0F19")
		for p in _eye_pivots:
			for sgn in [-1, 1]:
				var bar := _box(p, Vector3(0, 0, 0.075), Vector3(0.16, 0.04, 0.04), ink)
				bar.rotation.z = PI / 4.0 * sgn
				bar.set_meta("ko_x", true)
	else:
		_set_eyes(0.85 if kind == "knocked" else 0.0)

## Ojos de gusto: aplasta los ojos hasta una rayita.
func _set_eyes(amount: float) -> void:
	for p in _eye_pivots:
		p.scale = Vector3(1.0, lerpf(1.0, 0.2, clampf(amount, 0.0, 1.0)), 1.0)

## 0 → 1 → 0 con entrada y salida suaves (15 %).
static func _fade(u: float) -> float:
	return smoothstep(0.0, 0.15, u) * (1.0 - smoothstep(0.85, 1.0, u))

static func _window(u: float, a: float, b: float) -> float:
	var edge := minf(0.08, (b - a) / 3.0)
	return smoothstep(a, a + edge, u) * (1.0 - smoothstep(b - edge, b, u))

static func _bump(u: float, a: float, b: float) -> float:
	if u <= a or u >= b:
		return 0.0
	return sin((u - a) / (b - a) * PI)

static func _ease(x: float) -> float:
	return x * x * (3.0 - 2.0 * x)

# ── piezas ──────────────────────────────────────────────────────────────────

func _penguin_face(body: Node3D, light: Color) -> void:
	# Antifaz blanco en forma de corazón (dos lóbulos) + barriga.
	for s in [-1, 1]:
		_sphere(body, Vector3(0.1 * s, BODY_Y + 0.13, 0.21), 0.2, 0.36, light, false, Vector3(1.0, 1.0, 0.95))
	_sphere(body, Vector3(0, BODY_Y - 0.03, 0.22), 0.27, 0.5, light, false, Vector3(1.1, 1.0, 0.8))

func _eyes(body: Node3D, big: bool) -> void:
	var eye_col := _c("eye", "#0F172A").darkened(0.55)
	var r := 0.09 if big else 0.084
	for s in [-1, 1]:
		# Cada ojo cuelga de un pivote para poder entornarlo (ojos de gusto).
		var eye_pivot := _limb_pivot(body, Vector3(0.13 * s, BODY_Y + 0.15, 0.37))
		_eye_pivots.append(eye_pivot)
		var eye := _sphere(eye_pivot, Vector3.ZERO, r, r * 2.1, eye_col, false, Vector3(1.0, 1.0, 0.6))
		eye.material_override = _gloss(eye_col)
		var glint := _sphere(eye_pivot, Vector3(0.025 * s, 0.03, r * 0.55), r * 0.32, r * 0.64, Color.WHITE)
		glint.material_override = _glow(Color(1.6, 1.6, 1.6))
		var glint2 := _sphere(eye_pivot, Vector3(-0.02 * s, -0.025, r * 0.55), r * 0.14, r * 0.28, Color.WHITE)
		glint2.material_override = _glow(Color(1.3, 1.3, 1.3))

func _cheeks(body: Node3D) -> void:
	var blush := Color(1.0, 0.55, 0.6, 0.55)
	for s in [-1, 1]:
		var cheek := _sphere(body, Vector3(0.21 * s, BODY_Y + 0.03, 0.335), 0.05, 0.06, blush, false, Vector3(1.0, 0.7, 0.4))
		var m := StandardMaterial3D.new()
		m.albedo_color = blush
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.roughness = 0.6
		cheek.material_override = m

func _snout(body: Node3D, id: String, light: Color) -> void:
	if str(skin.get("snout", "")) == "beak":
		var beak := _sphere(body, Vector3(0, BODY_Y + 0.05, 0.43), 0.085, 0.1, Color("#F59E0B"), false, Vector3(1.0, 0.75, 1.0))
		beak.material_override = _gloss(Color("#F59E0B"))
		_sphere(body, Vector3(0, BODY_Y + 0.015, 0.42), 0.055, 0.05, Color("#C2410C"), false, Vector3(1.0, 0.6, 1.0))
		return
	var muzzle_size := 0.12 if id != "dino" else 0.14
	_sphere(body, Vector3(0, BODY_Y + 0.04, 0.39), muzzle_size, muzzle_size * 1.4, light.lightened(0.15), false, Vector3(1.25, 0.85, 0.8))
	var nose := _sphere(body, Vector3(0, BODY_Y + 0.08, 0.475), 0.04, 0.06, Color("#1F2937"), false, Vector3(1.3, 0.8, 0.8))
	nose.material_override = _gloss(Color("#1F2937"))
	_box(body, Vector3(0, BODY_Y + 0.0, 0.47), Vector3(0.06, 0.012, 0.012), Color("#7F1D1D"))   # sonrisa

func _ears(body: Node3D, kind: String, fur: Color, light: Color) -> void:
	if kind == "none":
		return
	var ear_col := Color(str(skin.get("ear_color", ""))) if skin.has("ear_color") else fur
	for s in [-1, 1]:
		var base := Vector3(0.2 * s, BODY_Y + BODY_H * 0.42, 0.0)
		match kind:
			"long":
				var e := _capsule(body, base + Vector3(0.02 * s, 0.2, 0), 0.07, 0.42, ear_col)
				e.rotation.z = -0.15 * s
				var inner := _capsule(body, base + Vector3(0.02 * s, 0.2, 0.045), 0.04, 0.32, Color("#F9A8D4"))
				inner.rotation.z = -0.15 * s
			"round", "round_stripes":
				var e2 := _sphere(body, base + Vector3(0.03 * s, 0.04, 0), 0.1, 0.2, ear_col, false, Vector3(1.0, 1.0, 0.55))
				e2.rotation.z = -0.3 * s
				if kind == "round":
					_sphere(body, base + Vector3(0.03 * s, 0.04, 0.03), 0.055, 0.11, light, false, Vector3(1.0, 1.0, 0.5))
			"tufts":
				var t := _cone(body, base + Vector3(0.0, 0.06, 0), 0.06, 0.16, fur.darkened(0.2))
				t.rotation.z = -0.5 * s
			_:   # pointed / tall_pointed
				var h := 0.28 if kind == "tall_pointed" else 0.22
				var e3 := _cone(body, base + Vector3(0.0, h * 0.4, 0), 0.11, h, ear_col)
				e3.rotation.z = -0.32 * s
				var e4 := _cone(body, base + Vector3(0.0, h * 0.38, 0.04), 0.06, h * 0.7, light)
				e4.rotation.z = -0.32 * s
				if skin_id == "zorro":
					var tip := _cone(body, base + Vector3(sin(0.32) * h * 0.35 * s, h * 0.78, 0), 0.04, h * 0.25, Color("#1F2937"))
					tip.rotation.z = -0.32 * s

func _suit_details(body: Node3D, light: Color) -> void:
	# Camisa (V clara) y corbata con el color de acento de la skin (nunca el del rol).
	_sphere(body, Vector3(0, BODY_Y - 0.21, 0.35), 0.085, 0.15, light, false, Vector3(1.0, 1.0, 0.45))
	var tie := _box(body, Vector3(0, BODY_Y - 0.27, 0.37), Vector3(0.055, 0.15, 0.02), _c("accent", "#DC2626"))
	tie.rotation.x = -0.35

func _hoodie_details(body: Node3D, outfit: Color) -> void:
	# Cordones de la capucha y bolsillo canguro.
	for s in [-1, 1]:
		var cord := _capsule(body, Vector3(0.06 * s, BODY_Y - 0.22, 0.38), 0.012, 0.11, Color("#F8FAFC"))
		cord.rotation.x = -0.3
	var pocket := _box(body, Vector3(0, BODY_Y - 0.38, 0.27), Vector3(0.26, 0.08, 0.03), outfit.darkened(0.15))
	pocket.rotation.x = -0.55

func _badge(body: Node3D) -> void:
	var b := _box(body, Vector3(0.16, BODY_Y - 0.25, 0.345), Vector3(0.07, 0.09, 0.012), Color("#F8FAFC"))
	b.rotation = Vector3(-0.4, 0.3, 0)

func _cap(body: Node3D, col: Color) -> void:
	var crown := _sphere(body, Vector3(0, BODY_Y + BODY_H * 0.38, 0), BODY_R * 0.86, BODY_H * 0.5, col, true)
	crown.scale = Vector3(1.0, 0.75, 1.0)
	_box(body, Vector3(0, BODY_Y + BODY_H * 0.38, 0.3), Vector3(0.36, 0.025, 0.22), col.darkened(0.15))

func _shoe(foot: Node3D, col: Color) -> void:
	var upper := _sphere(foot, Vector3(0, 0.07, 0.045), 0.1, 0.15, col, false, Vector3(0.95, 1.0, 1.45))
	upper.material_override = _gloss(col)
	_sphere(foot, Vector3(0, 0.03, 0.045), 0.1, 0.07, Color("#F8FAFC"), false, Vector3(1.0, 1.0, 1.5))
	for i in 2:
		_box(foot, Vector3(0, 0.12 - i * 0.012, 0.075 + i * 0.045), Vector3(0.1, 0.014, 0.018), Color("#F8FAFC"))

func _limb_pivot(parent: Node3D, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	parent.add_child(n)
	return n

# ── primitivas ──────────────────────────────────────────────────────────────

func _sphere(parent: Node3D, pos: Vector3, r: float, h: float, col: Color, hemi := false, scl := Vector3.ONE) -> MeshInstance3D:
	var m := SphereMesh.new()
	m.radius = r
	m.height = h if not hemi else h * 0.5
	m.is_hemisphere = hemi
	m.radial_segments = 32
	m.rings = 16
	return _add(parent, m, pos, col, scl)

func _capsule(parent: Node3D, pos: Vector3, r: float, h: float, col: Color) -> MeshInstance3D:
	var m := CapsuleMesh.new()
	m.radius = r
	m.height = maxf(h, r * 2.0)
	m.radial_segments = 16
	m.rings = 6
	return _add(parent, m, pos, col)

func _cone(parent: Node3D, pos: Vector3, r: float, h: float, col: Color) -> MeshInstance3D:
	var m := CylinderMesh.new()
	m.top_radius = 0.008
	m.bottom_radius = r
	m.height = h
	m.radial_segments = 16
	return _add(parent, m, pos, col)

func _box(parent: Node3D, pos: Vector3, size: Vector3, col: Color) -> MeshInstance3D:
	var m := BoxMesh.new()
	m.size = size
	return _add(parent, m, pos, col)

func _add(parent: Node3D, mesh: Mesh, pos: Vector3, col: Color, scl := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.scale = scl
	mi.material_override = _mat(col)
	parent.add_child(mi)
	return mi

func _c(key: String, fallback: String) -> Color:
	return Color(str(skin.get(key, fallback)))

## Vinilo: brillante con capa de barniz y un borde de luz suave.
func _mat(col: Color) -> StandardMaterial3D:
	var key := "v" + col.to_html()
	if not _mat_cache.has(key):
		var m := StandardMaterial3D.new()
		# Los blancos puros se queman con las luces de la oficina: se bajan un poco.
		m.albedo_color = col if col.get_luminance() < 0.8 else col.darkened(0.14)
		m.roughness = 0.32
		m.clearcoat_enabled = true
		m.clearcoat = 0.7
		m.clearcoat_roughness = 0.18
		m.rim_enabled = true
		m.rim = 0.25
		m.rim_tint = 0.6
		_mat_cache[key] = m
	return _track(_mat_cache[key])

func _gloss(col: Color) -> StandardMaterial3D:
	var key := "g" + col.to_html()
	if not _mat_cache.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = col
		m.roughness = 0.08
		m.metallic_specular = 0.9
		m.clearcoat_enabled = true
		m.clearcoat = 1.0
		m.clearcoat_roughness = 0.05
		_mat_cache[key] = m
	return _track(_mat_cache[key])

func _glow(col: Color) -> StandardMaterial3D:
	var key := "e" + col.to_html()
	if not _mat_cache.has(key):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = col
		_mat_cache[key] = m
	return _track(_mat_cache[key])

func _track(m: StandardMaterial3D) -> StandardMaterial3D:
	if not _materials.has(m):
		_materials.append(m)
	return m

## Con transparencia se duplican los materiales para no afectar a los demás jugadores.
func _apply_alpha() -> void:
	var translucent := _alpha < 0.99
	for mi in find_children("*", "MeshInstance3D", true, false):
		var src: StandardMaterial3D = mi.get_meta("base_mat") if mi.has_meta("base_mat") else mi.material_override
		if not mi.has_meta("base_mat"):
			mi.set_meta("base_mat", src)
		if translucent:
			var m: StandardMaterial3D = src.duplicate()
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.albedo_color.a = src.albedo_color.a * _alpha
			mi.material_override = m
		else:
			mi.material_override = src
