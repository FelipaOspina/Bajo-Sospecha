extends Node2D
class_name ProceduralChibiAvatar
## Chibi "de vinilo" hecho con código y un shader, sin PNG: es la figura del avatar
## mientras no existan las imágenes de su skin (ver PlayerAvatar.apply_skin).
##
## Anatomía (origen en los pies, unidades a escala 1, ~100 px de alto con orejas):
##   zapatillas deportivas (suela, empeine brillante, puntera y franja de color),
##   piernas que se estiran entre la cadera y el tobillo, torso ovalado con traje o
##   sudadera, mochila a la espalda (correas por delante), cola, brazos de dos tramos
##   (hombro y codo) con mano, y una cabeza grande y ovalada con orejas, hocico,
##   mejillas, cejas y ojos grandes con iris y dos brillos (parpadean).
## Cada pieza es un Polygon2D con res://shaders/procedural_chibi_3d.gdshader, que le
## da volumen satinado; hay tres materiales compartidos (pelaje, tela, brillante),
## así que todos los chibis se dibujan con muy pocos cambios de estado.
##
## El aspecto sale de la skin (SkinCatalog: pelaje, orejas, ropa, zapatillas, mochila,
## cola, gorra...), nunca del rol: la skin la ven todos y el rol es secreto. La corbata
## (o la acreditación de la sudadera) lleva el acento de la skin; PlayerAvatar le pone el
## color de tu rol solo en tu propio personaje (set_accent).
##
## Llama a animate_walk(delta, velocity.length()) cada frame: rebote de juguete de
## cuerda, pasos que levantan las zapatillas, brazos que se balancean doblando el codo,
## cabeza con retraso, orejas y cola con muelle. Quieto, respira y parpadea.

const SHADER_PATH := "res://shaders/procedural_chibi_3d.gdshader"
const SHOE_Y := 0.0
const HEAD_Y := -64.0
const HEAD_RADIUS := Vector2(27.0, 24.5)
const TORSO_Y := -29.5
const HIP := Vector2(6.5, -14.0)
const ANKLE_UP := 7.0
const SHOULDER := Vector2(14.5, -40.0)
## Parámetros de cada material (mismo shader): pelaje satinado, pelo suave (melena, cola),
## tela mate y piezas brillantes (ojos, nariz, punteras).
const MATERIALS := {
	"fur": {"glossiness": 26.0, "specular": 0.22, "sheen": 0.10, "rim_strength": 0.26, "wrap": 0.5, "occlusion": 0.22},
	"soft": {"glossiness": 12.0, "specular": 0.03, "sheen": 0.10, "rim_strength": 0.22, "wrap": 0.55, "occlusion": 0.14},
	"cloth": {"glossiness": 10.0, "specular": 0.0, "sheen": 0.12, "rim_strength": 0.18, "wrap": 0.5, "occlusion": 0.18},
	"gloss": {"glossiness": 64.0, "specular": 0.85, "sheen": 0.14, "rim_strength": 0.30, "wrap": 0.3, "occlusion": 0.18},
}

@export var skin_id: String = "zorro":
	set(value):
		skin_id = value
		if is_node_ready():
			generate_avatar()
## Velocidad que cuenta como "caminar a tope" (la de Player.speed).
@export var max_speed := 240.0
## Cosméticos puestos {"outfit", "hat", "shoes", "bag" → id de CosmeticCatalog}: cambian
## ropa, gorra, zapatillas y mochila sobre los colores del animal. Nunca la corbata.
@export var look: Dictionary = {}:
	set(value):
		if value == look:
			return
		look = value.duplicate()
		if is_node_ready():
			generate_avatar()
## Dibujarlo horneado (una sola textura en vez de ~60 piezas) cuando ChibiBaker.enabled()
## lo permite: móviles y web. Ver ChibiBaker.
@export var bake := false:
	set(value):
		bake = value
		if is_node_ready():
			_request_bake()

## Vista actual: "frente", "lado" o "espalda" (el volteo izquierda/derecha lo hace Visuals).
var facing := "frente"
var config: Dictionary
var body_node: Node2D
var head: Node2D
var face: Node2D
var front: Node2D        # detalles del pecho (camisa, corbata, cordones...)
var backpack: Node2D
var tail: Node2D
var left_arm: Node2D
var right_arm: Node2D
var left_foot: Node2D    # zapatillas (en el suelo, fuera del cuerpo que rebota)
var right_foot: Node2D
var ears: Array[Node2D] = []
var eyes: Array[Node2D] = []
var brows: Array[Node2D] = []
var straps: Array[Node2D] = []
var tie: Polygon2D       # pieza principal del acento (corbata o cinta de la acreditación)
var face_parts: Array[Node2D] = []   # se ocultan de espaldas
var torso: Polygon2D
var hat: Node2D
var visor: Node2D

var _accent_parts: Array[Polygon2D] = []
var _legs: Array[Polygon2D] = []
var _accent_override := Color(0, 0, 0, 0)
var _phase := 0.0
var _breath := 0.0
var _amp := 0.0
var _ear_angle := 0.0
var _ear_velocity := 0.0
var _tail_time := 0.0
var _last_lift := 0.0
var _blink_in := 2.5
var _blink_left := 0.0
var _top := -100.0
var _rng := RandomNumberGenerator.new()
var _sheet: Texture2D     # hoja horneada (null = piezas en vivo)
var _bake_key := ""
var _frame := -1          # paso de la hoja (-1 = quieto)

static var _materials := {}
static var _white: ImageTexture
static var _shadow: GradientTexture2D

func _ready() -> void:
	_rng.randomize()
	_blink_in = _rng.randf_range(1.5, 4.5)
	generate_avatar()

func generate_avatar() -> void:
	_show_sheet(null)
	for child in get_children():
		remove_child(child)
		child.queue_free()
	ears.clear()
	eyes.clear()
	brows.clear()
	straps.clear()
	face_parts.clear()
	_accent_parts.clear()
	_legs.clear()
	hat = null
	visor = null
	config = CosmeticCatalog.dress(SkinCatalog.skin(skin_id), look)
	var fur := Color(config.get("fur", "#D9622B"))
	var fur_light := Color(config.get("fur_light", "#F8E8DA"))
	var outfit := Color(config.get("outfit", "#1E2A4A"))
	var hoodie: bool = config.get("style", "suit") == "hoodie"
	var pants := Color("#2B3A55") if hoodie else outfit.darkened(0.35)
	var sb: Array = config.get("scale_body", [1.0, 1.0])
	var head_r := Vector2(HEAD_RADIUS.x * float(sb[0]), HEAD_RADIUS.y * float(sb[1]))

	# 1. Piernas (se recolocan cada frame entre cadera y tobillo) y zapatillas en el suelo.
	for s in [-1, 1]:
		var leg := _sphere(self, "LeftLeg" if s < 0 else "RightLeg", Vector2.ZERO, Vector2(4.4, 1.0), pants, Vector2.ZERO, "cloth", 16)
		_legs.append(leg)
	left_foot = _shoe("LeftShoe", -1)
	right_foot = _shoe("RightShoe", 1)

	# Contenedor del cuerpo, con el pivote en los pies (aplastar/estirar desde el suelo).
	body_node = Node2D.new()
	body_node.name = "BodyContainer"
	add_child(body_node)

	# 2. Cola y mochila (detrás del torso de frente; se reordenan al girar).
	tail = _build_tail(fur)
	backpack = _build_backpack()

	# 3. Torso ovalado con la ropa.
	torso = _sphere(body_node, "Torso", Vector2(0, TORSO_Y), Vector2(17.5 if hoodie else 16.5, 17.5), outfit, Vector2.ZERO, "cloth")
	if hoodie:
		_sphere(body_node, "Hood", Vector2(0, -44), Vector2(19, 7.5), outfit.lightened(0.08), Vector2.ZERO, "cloth", 20)
	front = Node2D.new()
	front.name = "Front"
	body_node.add_child(front)
	if hoodie:
		_build_hoodie_front(outfit)
	else:
		_build_suit_front(outfit)
	face_parts.append(front)
	for s in [-1, 1]:
		var strap := _flat(body_node, "Strap", Vector2(10.5 * s, -42), PackedVector2Array([Vector2(-1.8, 0), Vector2(1.8, 0), Vector2(2.4 * s + 1.8, 17), Vector2(2.4 * s - 1.8, 17)]), Color(config.get("bag", "#1F2937")).darkened(0.2))
		straps.append(strap)

	# 4. Brazos de dos tramos (hombro → codo → mano).
	left_arm = _build_arm("LeftArm", -1, outfit, fur)
	right_arm = _build_arm("RightArm", 1, outfit, fur)

	# 5. Cabeza grande con orejas, cara y gorra.
	head = Node2D.new()
	head.name = "Head"
	head.position = Vector2(0, HEAD_Y)
	body_node.add_child(head)
	if config.has("mane"):
		_build_mane(Color(config["mane"]), head_r)
	_build_ears(fur, head_r)
	_sphere(head, "HeadSphere", Vector2.ZERO, head_r, fur)
	if config.get("ear_type") == "round_stripes":
		_build_stripes(fur.darkened(0.6), head_r)
	face = Node2D.new()
	face.name = "Face"
	head.add_child(face)
	_build_face(fur, fur_light, head_r)
	if config.get("hat", "") == "cap":
		_build_cap(Color(config.get("hat_color", "#1E3A8A")), head_r)
	_top = _compute_top(head_r)

	set_facing(facing)
	_request_bake()

## Altura de la punta (orejas, gorra o cabeza) sobre los pies, en negativo: para colocar
## el nombre justo encima.
func top_y() -> float:
	return _top

## Color del acento (corbata o cinta). Por defecto el de la skin; PlayerAvatar pone el
## color de tu rol solo en tu propio personaje.
func set_accent(c: Color) -> void:
	_accent_override = c
	for p in _accent_parts:
		if is_instance_valid(p):
			p.color = _accent()
	if bake:
		_request_bake()

func accent_color() -> Color:
	return tie.color if tie else _accent()

## "frente": cara a la vista. "lado": mira a la derecha (Visuals voltea para la izquierda):
## la cara se desplaza, se ven la mochila y la cola y se esconden el ojo y el brazo del
## fondo. "espalda": sin cara; mochila y cola delante.
func set_facing(view: String) -> void:
	facing = view
	if body_node == null:
		return
	if _sheet:
		queue_redraw()
	var side := view == "lado"
	var back := view == "espalda"
	face.visible = not back
	face.position.x = 8.0 if side else 0.0
	for i in eyes.size():
		eyes[i].visible = not (side and i == 0)
	for i in brows.size():
		brows[i].visible = not (side and i == 0)
	front.visible = not back
	front.position.x = 5.0 if side else 0.0
	front.scale.x = 0.7 if side else 1.0
	for i in straps.size():
		straps[i].visible = not back and not (side and i == 0)
		straps[i].position.x = (3.0 if side else 10.5 * (-1 if i == 0 else 1))
	left_arm.visible = not side
	if visor:
		visor.visible = not back
		visor.position.x = 9.0 if side else 0.0
		visor.scale.x = 0.75 if side else 1.0
	# Mochila: detrás del torso (de frente y de lado) o delante (de espaldas).
	backpack.position = Vector2(-15.0, 0.0) if side else Vector2.ZERO
	backpack.scale = Vector2(0.62, 1.0) if side else Vector2.ONE
	backpack.get_node("Pocket").visible = back or side
	if back:
		body_node.move_child(backpack, front.get_index() + 1)
	else:
		body_node.move_child(backpack, 0)
	# Cola: de lado sale por detrás; de espaldas, delante de la mochila.
	if tail:
		tail.visible = side or back
		tail.position = Vector2(-14.0, -16.0) if side else Vector2(0, -15.0)
		if back:
			body_node.move_child(tail, backpack.get_index() + 1)
		else:
			body_node.move_child(tail, 0)
	# Zapatillas: de lado, una delante de otra y la puntera hacia donde mira.
	left_foot.position.x = -2.5 if side else -7.5
	right_foot.position.x = 3.0 if side else 7.5
	for foot in [left_foot, right_foot]:
		foot.get_node("Toe").visible = not back
		foot.get_node("Toe").position.x = 4.0 if side else 0.0
	_update_legs()

## Altura a la que el rebote levanta el cuerpo (PlayerAvatar encoge la sombra).
func lift() -> float:
	return -body_node.position.y if body_node else 0.0

# Animación procedural (wobble 2.4D de juguete de cuerda).
func animate_walk(delta: float, speed: float) -> void:
	if body_node == null:
		return
	var ratio := clampf(speed / maxf(max_speed, 1.0), 0.0, 1.5)
	var moving := ratio > 0.05
	_amp = move_toward(_amp, 1.0 if moving else 0.0, delta * 6.0)
	if moving:
		_phase += delta * TAU * (1.6 + 1.2 * ratio)   # pasos por segundo según la velocidad
	elif _amp == 0.0:
		_phase = 0.0
	_breath += delta * TAU * 0.4
	_tail_time += delta * (6.0 + 6.0 * _amp)

	var step := sin(_phase)
	var side := facing == "lado"
	var lift_px := absf(step) * 3.0 * _amp                                # un saltito por paso
	body_node.position.y = -lift_px
	if _sheet:
		# Horneado: solo se elige el paso de la hoja (lo demás ya está en la imagen).
		var frame := posmod(int(floor(fposmod(_phase, TAU) / TAU * ChibiBaker.WALK_FRAMES + 0.5)), ChibiBaker.WALK_FRAMES) if _amp > 0.5 else -1
		if frame != _frame:
			_frame = frame
			queue_redraw()
		return
	var squash := cos(2.0 * _phase) * 0.06 * _amp + sin(_breath) * 0.018 * (1.0 - _amp)
	body_node.scale = Vector2(1.0 + squash, 1.0 - squash)
	body_node.rotation = step * 0.06 * _amp + (0.05 * _amp if side else 0.0)

	# Zapatillas: se levantan por turnos y, de lado, van adelante y atrás.
	var feet := [left_foot, right_foot]
	for i in 2:
		var s := step if i == 0 else -step
		var c := cos(_phase) if i == 0 else -cos(_phase)
		var foot: Node2D = feet[i]
		foot.position.y = SHOE_Y - maxf(0.0, s) * 4.5 * _amp
		if side:
			foot.position.x = (-2.5 if i == 0 else 3.0) + c * 6.0 * _amp
			foot.rotation = -maxf(0.0, s) * 0.35 * _amp
		else:
			foot.rotation = 0.0
	_update_legs()

	# Brazos: balanceo opuesto a las piernas; el codo se dobla más al ir hacia delante.
	var swing := step * (0.65 if side else 0.45) * _amp
	var rest := 0.16 + sin(_breath) * 0.03 * (1.0 - _amp)
	left_arm.rotation = rest + swing
	right_arm.rotation = -rest + (-swing if not side else swing * -1.0)
	(left_arm.get_node("Elbow") as Node2D).rotation = -(0.25 + maxf(0.0, step) * 0.6 * _amp)
	(right_arm.get_node("Elbow") as Node2D).rotation = 0.25 + maxf(0.0, -step) * 0.6 * _amp if not side else -(0.3 + maxf(0.0, step) * 0.7 * _amp)

	# Cabeza con un poco de retraso y balanceo.
	head.position.y = HEAD_Y + lift_px * 0.35 + sin(_breath) * 0.6 * (1.0 - _amp)
	head.rotation = sin(_phase - 0.6) * 0.05 * _amp

	# Orejas y cola con muelle: el rebote las sacude y vuelven solas.
	var lift_velocity := (lift_px - _last_lift) / maxf(delta, 0.0001)
	_last_lift = lift_px
	_ear_velocity += (-_ear_angle * 120.0 - _ear_velocity * 10.0 + lift_velocity * 0.6) * delta
	_ear_angle = clampf(_ear_angle + _ear_velocity * delta, -0.35, 0.35)
	for ear in ears:
		ear.rotation = ear.get_meta("base_rotation", 0.0) + _ear_angle * signf(ear.position.x)
	if tail:
		tail.rotation = sin(_tail_time) * (0.12 + 0.18 * _amp)

	# Parpadeo.
	if _blink_left > 0.0:
		_blink_left -= delta
		if _blink_left <= 0.0:
			_set_eyes_open(1.0)
	else:
		_blink_in -= delta
		if _blink_in <= 0.0:
			_blink_left = 0.12
			_blink_in = _rng.randf_range(2.0, 5.0)
			_set_eyes_open(0.12)

## Pone una pose fija del paso (fase 0..TAU, amount 0 = quieto): la usa ChibiBaker.
func pose(phase: float, amount: float) -> void:
	_amp = amount
	_phase = phase
	animate_walk(0.0, max_speed if amount > 0.0 else 0.0)

func _draw() -> void:
	if _sheet:
		draw_texture_rect_region(_sheet, ChibiBaker.local_rect(), ChibiBaker.region(facing, _frame))

func _request_bake() -> void:
	if not bake or not ChibiBaker.enabled() or not is_inside_tree():
		if _sheet:
			_show_sheet(null)
		return
	var accent := _accent()
	var k := ChibiBaker.key(skin_id, accent, look)
	if k == _bake_key and _sheet:
		return
	_bake_key = k
	var tex := ChibiBaker.cached(skin_id, accent, look)
	if tex:
		_show_sheet(tex)
	else:
		ChibiBaker.request(self, skin_id, accent, _on_baked, look)

func _on_baked(k: String, tex: Texture2D) -> void:
	if k == _bake_key and bake and tex:
		_show_sheet(tex)

## Con hoja: se esconden las piezas y se dibuja la textura (alfa premultiplicado, como
## sale del SubViewport). Sin hoja: vuelven las piezas.
func _show_sheet(tex: Texture2D) -> void:
	_sheet = tex
	material = ChibiBaker.premultiplied() if tex else null
	for child in get_children():
		if child is CanvasItem:
			child.visible = tex == null
	queue_redraw()

func _set_eyes_open(k: float) -> void:
	for e in eyes:
		e.scale.y = k

## Piernas: elipse estirada entre la cadera (en el cuerpo que rebota) y el tobillo.
func _update_legs() -> void:
	var feet := [left_foot, right_foot]
	for i in 2:
		var hip := body_node.transform * Vector2(HIP.x * (-1 if i == 0 else 1) * (0.4 if facing == "lado" else 1.0), HIP.y)
		var ankle: Vector2 = feet[i].position + Vector2(0, -ANKLE_UP)
		var leg := _legs[i]
		var d := ankle - hip
		leg.position = (hip + ankle) / 2.0
		leg.rotation = d.angle() - PI / 2.0
		leg.scale = Vector2(1.0, maxf(1.0, d.length() / 2.0 + 2.0))

func _accent() -> Color:
	return _accent_override if _accent_override.a > 0.0 else Color(config.get("accent", "#FF334B"))

# ───── Construcción ─────

func _shoe(part_name: String, s: int) -> Node2D:
	var shoe := Node2D.new()
	shoe.name = part_name
	shoe.position = Vector2(7.5 * s, SHOE_Y)
	add_child(shoe)
	var color := Color(config.get("shoes", "#F1F5F9"))
	_sphere(shoe, "Sole", Vector2(0.5, -2.2), Vector2(8.6, 2.6), Color("#E2E8F0"), Vector2.ZERO, "cloth", 18)
	_sphere(shoe, "Upper", Vector2(0, -6.0), Vector2(7.0, 4.6), color, Vector2.ZERO, "fur", 20)
	_sphere(shoe, "Toe", Vector2(0, -3.9), Vector2(4.8, 2.4), Color("#F8FAFC"), Vector2.ZERO, "gloss", 14)
	for i in 2:
		_flat(shoe, "Lace", Vector2(0, -8.6 + i * 1.8), PackedVector2Array([Vector2(-2.6, -0.4), Vector2(2.6, -0.4), Vector2(2.6, 0.4), Vector2(-2.6, 0.4)]), Color(1, 1, 1, 0.75))
	var stripe := _flat(shoe, "Stripe", Vector2(-3.6 * s, -6.0), PackedVector2Array([Vector2(-2.2, 1.6), Vector2(2.0, -2.0), Vector2(2.8, -1.0), Vector2(-1.4, 2.6)]), _accent())
	_accent_parts.append(stripe)
	return shoe

func _build_backpack() -> Node2D:
	var bag_color := Color(config.get("bag", "#1F2937"))
	var pack := Node2D.new()
	pack.name = "Backpack"
	body_node.add_child(pack)
	_sphere(pack, "Bag", Vector2(0, -31), Vector2(15, 14.5), bag_color, Vector2.ZERO, "cloth")
	_sphere(pack, "Handle", Vector2(0, -46.5), Vector2(5, 2.4), bag_color.darkened(0.25), Vector2.ZERO, "cloth", 12)
	var pocket := _sphere(pack, "Pocket", Vector2(0, -24), Vector2(9.5, 6.0), bag_color.lightened(0.12), Vector2.ZERO, "cloth", 18)
	_flat(pocket, "Zip", Vector2(0, -3.2), PackedVector2Array([Vector2(-7, -0.5), Vector2(7, -0.5), Vector2(7, 0.5), Vector2(-7, 0.5)]), Color(1, 1, 1, 0.35))
	return pack

func _build_tail(fur: Color) -> Node2D:
	var kind := str(config.get("tail", "none"))
	if kind == "none":
		return null
	var t := Node2D.new()
	t.name = "Tail"
	body_node.add_child(t)
	var light := Color(config.get("fur_light", "#F8E8DA"))
	match kind:
		"bushy", "ringed":
			var main := _sphere(t, "Brush", Vector2(-4, -9), Vector2(6.5, 11.5), fur, Vector2.ZERO, "soft", 20)
			main.rotation = -0.6
			if kind == "ringed":
				for i in 2:
					var ring := _sphere(t, "Ring", Vector2(-4.5 - i * 3.6, -6 - i * 6.0), Vector2(6.2, 2.4), fur.darkened(0.55), Vector2.ZERO, "soft", 14)
					ring.rotation = -0.6
			else:
				var tip := _sphere(t, "Tip", Vector2(-9.5, -17), Vector2(4.2, 4.6), light if skin_id == "zorro" else fur.lightened(0.15), Vector2.ZERO, "soft", 14)
				tip.rotation = -0.6
		"thin", "striped":
			for i in 4:
				var seg := _sphere(t, "Segment", Vector2(-2.5 - i * 2.6, -3 - i * 4.2 - i * i * 0.3), Vector2(2.6, 3.4), fur.darkened(0.55) if kind == "striped" and i % 2 == 1 else fur, Vector2.ZERO, "fur", 12)
				seg.rotation = -0.5
			if config.has("mane"):
				_sphere(t, "Tuft", Vector2(-13, -19), Vector2(3.8, 4.2), Color(config["mane"]), Vector2.ZERO, "soft", 14)
		"puff":
			_sphere(t, "Puff", Vector2(0, -2), Vector2(6, 5.5), Color(config.get("ear_color", fur.lightened(0.1).to_html())), Vector2.ZERO, "soft", 16)
	return t

func _build_suit_front(outfit: Color) -> void:
	_flat(front, "Shirt", Vector2(0, -43), PackedVector2Array([Vector2(-7, 0), Vector2(7, 0), Vector2(0, 13)]), Color("#F1F5F9"))
	for s in [-1, 1]:
		_flat(front, "Lapel", Vector2(0, -43), PackedVector2Array([Vector2(7.5 * s, 0), Vector2(1.0 * s, 13), Vector2(4 * s, 15), Vector2(11 * s, 3)]), outfit.darkened(0.25))
	tie = _flat(front, "Tie", Vector2(0, -42), PackedVector2Array([Vector2(-2.6, 0), Vector2(2.6, 0), Vector2(1.6, 2.6), Vector2(3.6, 12), Vector2(0, 16), Vector2(-3.6, 12), Vector2(-1.6, 2.6)]), _accent())
	_accent_parts.push_front(tie)
	for y in [-24.0, -18.0]:
		_sphere(front, "Button", Vector2(4.5, y), Vector2(1.2, 1.2), outfit.darkened(0.5), Vector2.ZERO, "gloss", 10)

func _build_hoodie_front(outfit: Color) -> void:
	_sphere(front, "Pocket", Vector2(0, -20), Vector2(11, 5), outfit.darkened(0.15), Vector2.ZERO, "cloth", 18)
	for s in [-1, 1]:
		_flat(front, "Cord", Vector2(3.2 * s, -41), PackedVector2Array([Vector2(-0.6, 0), Vector2(0.6, 0), Vector2(0.6, 8), Vector2(-0.6, 8)]), Color("#E2E8F0"))
		_sphere(front, "CordTip", Vector2(3.2 * s, -32.5), Vector2(1.2, 1.6), Color("#E2E8F0"), Vector2.ZERO, "gloss", 10)
	# Acreditación colgada (el color de la cinta es el acento).
	tie = _flat(front, "Lanyard", Vector2(0, -42), PackedVector2Array([Vector2(-6, 0), Vector2(-4.5, 0), Vector2(0.6, 10), Vector2(4.5, 0), Vector2(6, 0), Vector2(0.8, 12.5), Vector2(-0.8, 12.5)]), _accent())
	_accent_parts.push_front(tie)
	var card := _flat(front, "Badge", Vector2(0, -29.5), PackedVector2Array([Vector2(-3.6, 0), Vector2(3.6, 0), Vector2(3.6, 6.5), Vector2(-3.6, 6.5)]), Color("#F8FAFC"))
	_accent_parts.append(_flat(card, "BadgeStripe", Vector2.ZERO, PackedVector2Array([Vector2(-3.6, 0), Vector2(3.6, 0), Vector2(3.6, 1.6), Vector2(-3.6, 1.6)]), _accent()))

func _build_arm(part_name: String, s: int, outfit: Color, fur: Color) -> Node2D:
	var arm := Node2D.new()
	arm.name = part_name
	arm.position = Vector2(SHOULDER.x * s, SHOULDER.y)
	body_node.add_child(arm)
	var elbow := Node2D.new()
	elbow.name = "Elbow"
	elbow.position = Vector2(0, 9.5)
	arm.add_child(elbow)
	_sphere(elbow, "Forearm", Vector2(0, 3.6), Vector2(4.3, 6.4), outfit, Vector2.ZERO, "cloth", 18)
	_sphere(elbow, "Cuff", Vector2(0, 8.6), Vector2(4.2, 1.6), outfit.darkened(0.25), Vector2.ZERO, "cloth", 14)
	_sphere(elbow, "Hand", Vector2(0, 11.0), Vector2(4.5, 4.2), fur, Vector2.ZERO, "fur", 16)
	# El brazo de arriba se dibuja encima del codo para que la manga se vea de una pieza.
	_sphere(arm, "Upper", Vector2(0, 5.0), Vector2(4.8, 7.6), outfit, Vector2.ZERO, "cloth", 18)
	return arm

func _build_mane(col: Color, r: Vector2) -> void:
	var mane := Node2D.new()
	mane.name = "Mane"
	head.add_child(mane)
	_sphere(mane, "Back", Vector2(0, -1), Vector2(r.x * 1.18, r.y * 1.1), col.darkened(0.12), Vector2.ZERO, "soft")
	for i in 14:
		var a := TAU * i / 14.0
		# Por abajo la melena se recoge para no tapar la corbata.
		var below := maxf(sin(a), 0.0)
		_sphere(mane, "Lobe", Vector2(cos(a) * r.x * (1.0 - 0.12 * below), sin(a) * r.y * (1.0 - 0.3 * below)), Vector2(9.5, 9.0) * (1.0 - 0.15 * below), col, Vector2.ZERO, "soft", 16)

func _build_ears(fur: Color, r: Vector2) -> void:
	var ear_color := Color(config.get("ear_color", fur.to_html()))
	var inner := Color(config.get("fur_light", "#F8E8DA"))
	match config.get("ear_type", "round"):
		"pointed", "tall_pointed":
			var h := 23.0 if config.get("ear_type") == "tall_pointed" else 17.0
			for s in [-1, 1]:
				var ear := _flat(head, "Ear", Vector2(r.x * 0.55 * s, -r.y * 0.7), PackedVector2Array([Vector2(-8, 2), Vector2(2.5 * s, -h), Vector2(8, 2)]), ear_color)
				ear.rotation = 0.18 * s
				_flat(ear, "Inner", Vector2(0, -1), PackedVector2Array([Vector2(-4, 1), Vector2(1.5 * s, -h * 0.68), Vector2(4, 1)]), inner.lerp(Color("#F4A6B8"), 0.35))
				_flat(ear, "Shade", Vector2.ZERO, PackedVector2Array([Vector2(2.5 * s, -h), Vector2(8 * s, 2), Vector2(5.5 * s, 2)]), Color(0, 0, 0, 0.18))
				ears.append(ear)
		"long":
			for s in [-1, 1]:
				var ear := _sphere(head, "Ear", Vector2(8.5 * s, -r.y - 2), Vector2(5.8, 15.5), ear_color, Vector2(0, -12))
				ear.rotation = 0.14 * s
				_sphere(ear, "Inner", Vector2(0, -12), Vector2(3.0, 11), Color("#F7B6C8"), Vector2.ZERO, "fur", 16)
				ears.append(ear)
		"floppy":
			for s in [-1, 1]:
				var ear := _sphere(head, "Ear", Vector2((r.x - 3) * s, -r.y * 0.45), Vector2(7.5, 14.5), ear_color.darkened(0.28), Vector2(0, 10))
				ear.rotation = -0.3 * s
				ears.append(ear)
		"tufts":
			for s in [-1, 1]:
				var ear := _flat(head, "Ear", Vector2(r.x * 0.6 * s, -r.y * 0.72), PackedVector2Array([Vector2(-5, 2), Vector2(5 * s, -12), Vector2(5, 2)]), ear_color.darkened(0.25))
				ears.append(ear)
		"none":
			pass
		_:   # "round", "round_stripes"
			for s in [-1, 1]:
				var ear := _sphere(head, "Ear", Vector2(r.x * 0.72 * s, -r.y * 0.78), Vector2(8.8, 8.6), ear_color)
				_sphere(ear, "Inner", Vector2(0, 0.5), Vector2(4.6, 4.4), inner if not config.has("ear_color") else ear_color.lightened(0.18), Vector2.ZERO, "fur", 14)
				ears.append(ear)
	for ear in ears:
		ear.set_meta("base_rotation", ear.rotation)

func _build_stripes(col: Color, r: Vector2) -> void:
	for x in [-9.0, 0.0, 9.0]:
		_flat(head, "Stripe", Vector2(x * r.x / HEAD_RADIUS.x, -r.y + 1.5 + absf(x) * 0.3), PackedVector2Array([Vector2(-2.6, 0), Vector2(2.6, 0), Vector2(0, 9)]), col)
	for s in [-1, 1]:
		_flat(head, "Stripe", Vector2((r.x - 2) * s, -2), PackedVector2Array([Vector2(0, -3), Vector2(-7 * s, 0), Vector2(0, 3)]), col)

func _build_face(fur: Color, fur_light: Color, r: Vector2) -> void:
	var kx := r.x / HEAD_RADIUS.x
	var beak: bool = config.get("snout", "nose") == "beak"
	# Manchas (panda), antifaz (mapache), cara clara (pingüino) o disco facial (búho).
	match config.get("patches", ""):
		"panda":
			for s in [-1, 1]:
				var patch := _sphere(face, "Patch", Vector2(10.5 * kx * s, 0.5), Vector2(8.2, 9.6), Color("#1A1A22"), Vector2.ZERO, "fur", 18)
				patch.rotation = 0.45 * s
		"mask":
			_sphere(face, "Mask", Vector2(0, -0.5), Vector2(22.5 * kx, 7.8), Color("#2A2D35"), Vector2.ZERO, "fur", 20)
		"face":
			for s in [-1, 1]:
				_sphere(face, "Face", Vector2(8.5 * kx * s, 1.5), Vector2(12.5, 13.5), fur_light, Vector2.ZERO, "fur", 20)
			_sphere(face, "Face", Vector2(0, 9), Vector2(15, 10), fur_light, Vector2.ZERO, "fur", 20)
	if beak and config.get("patches", "") != "face":
		for s in [-1, 1]:
			_sphere(face, "Disc", Vector2(10 * kx * s, 0.5), Vector2(11, 11), fur_light, Vector2.ZERO, "fur", 18)
	# Hocico.
	if not beak:
		_sphere(face, "Muzzle", Vector2(0, 9.5), Vector2(11.5, 7.6), fur_light, Vector2.ZERO, "fur", 20)
	# Mejillas.
	for s in [-1, 1]:
		_flat(face, "Cheek", Vector2(17.5 * kx * s, 8.5), _ellipse(Vector2(4.6, 2.8), 12), Color("#FF8FA3", 0.5))
	# Ojos grandes: base brillante con el color del iris, pupila, reflejo de iris y dos brillos.
	var iris := Color(config.get("eye", "#2A1A12"))
	for s in [-1, 1]:
		var eye := Node2D.new()
		eye.name = "EyeLeft" if s < 0 else "EyeRight"
		eye.position = Vector2(10.5 * kx * s, -0.5)
		face.add_child(eye)
		_sphere(eye, "Ball", Vector2.ZERO, Vector2(6.0, 7.2), iris.darkened(0.6), Vector2.ZERO, "gloss", 20)
		_flat(eye, "Iris", Vector2(0, 2.6), _ellipse(Vector2(4.4, 3.4), 14), Color(iris.lightened(0.15), 0.85))
		_flat(eye, "Pupil", Vector2(0, -0.4), _ellipse(Vector2(3.4, 4.4), 14), Color("#05060A"))
		_flat(eye, "Shine", Vector2(-1.9, -2.6), _ellipse(Vector2(2.3, 2.6), 12), Color.WHITE)
		_flat(eye, "Sparkle", Vector2(2.3, 2.7), _ellipse(Vector2(1.0, 1.0), 8), Color(1, 1, 1, 0.9))
		eyes.append(eye)
		# Cejas.
		var brow := _flat(face, "Brow", Vector2(10.5 * kx * s, -10.5), PackedVector2Array([Vector2(-4.2, 0.8), Vector2(0, -0.9), Vector2(4.2, 0.8), Vector2(0, 0.6)]), fur.darkened(0.55) if fur.get_luminance() > 0.25 else fur.lightened(0.45))
		brow.rotation = -0.12 * s
		brows.append(brow)
	# Nariz y boca, o pico.
	if beak:
		_sphere(face, "Beak", Vector2(0, 7.0), Vector2(4.6, 3.4), Color("#F59E0B"), Vector2.ZERO, "gloss", 16)
		_sphere(face, "BeakLow", Vector2(0, 9.6), Vector2(3.2, 1.8), Color("#D97706"), Vector2.ZERO, "gloss", 12)
	else:
		_sphere(face, "Nose", Vector2(0, 5.6), Vector2(3.8, 2.7), Color("#1A1A1A"), Vector2.ZERO, "gloss", 14)
		var mouth := Line2D.new()
		mouth.name = "Mouth"
		mouth.points = PackedVector2Array([Vector2(-3.6, 10.2), Vector2(-1.8, 11.6), Vector2(0, 10.0), Vector2(1.8, 11.6), Vector2(3.6, 10.2)])
		mouth.width = 1.1
		mouth.default_color = Color("#3A1F1A")
		mouth.joint_mode = Line2D.LINE_JOINT_ROUND
		mouth.begin_cap_mode = Line2D.LINE_CAP_ROUND
		mouth.end_cap_mode = Line2D.LINE_CAP_ROUND
		mouth.antialiased = true
		face.add_child(mouth)
	face_parts.append(face)

func _build_cap(col: Color, r: Vector2) -> void:
	hat = Node2D.new()
	hat.name = "Cap"
	head.add_child(hat)
	_sphere(hat, "Dome", Vector2(0, -r.y * 0.8), Vector2(r.x * 0.9, r.y * 0.44), col, Vector2.ZERO, "cloth")
	_flat(hat, "Band", Vector2(0, -r.y * 0.44), PackedVector2Array([Vector2(-r.x * 0.88, -2), Vector2(r.x * 0.88, -2), Vector2(r.x * 0.82, 1.6), Vector2(-r.x * 0.82, 1.6)]), col.darkened(0.3))
	_sphere(hat, "Button", Vector2(0, -r.y * 1.22), Vector2(2.4, 1.8), col.lightened(0.2), Vector2.ZERO, "gloss", 10)
	visor = Node2D.new()
	visor.name = "Visor"
	hat.add_child(visor)
	_sphere(visor, "Brim", Vector2(0, -r.y * 0.42), Vector2(r.x * 0.64, 3.4), col.darkened(0.15), Vector2.ZERO, "cloth", 20)
	var logo := _sphere(visor, "Logo", Vector2(0, -r.y * 0.78), Vector2(4.5, 3.6), _accent(), Vector2.ZERO, "gloss", 14)
	_accent_parts.append(logo)

func _compute_top(r: Vector2) -> float:
	var top := HEAD_Y - r.y
	match config.get("ear_type", "round"):
		"pointed":
			top = HEAD_Y - r.y * 0.7 - 17.0
		"tall_pointed":
			top = HEAD_Y - r.y * 0.7 - 23.0
		"long":
			top = HEAD_Y - r.y - 2.0 - 27.5
		"floppy", "none":
			top = HEAD_Y - r.y
		"tufts":
			top = HEAD_Y - r.y * 0.72 - 12.0
		_:
			top = HEAD_Y - r.y * 0.78 - 8.6
	if config.has("mane"):
		top = minf(top, HEAD_Y - r.y - 9.0)
	if config.get("hat", "") == "cap":
		top = minf(top, HEAD_Y - r.y * 1.3)
	return minf(top, HEAD_Y - r.y)

## Pieza con volumen (shader). offset desplaza el dibujo respecto al pivote (hombro, base de la oreja).
func _sphere(parent: Node, part_name: String, pos: Vector2, radius: Vector2, col: Color, offset := Vector2.ZERO, kind := "fur", segments := 24) -> Polygon2D:
	var poly := Polygon2D.new()
	poly.name = part_name
	poly.position = pos
	poly.offset = offset
	poly.polygon = _ellipse(radius, segments)
	# El Polygon2D solo pasa UV al shader si tiene textura: una blanca de 1×1 y UV 0..1.
	var uv := PackedVector2Array()
	for p in poly.polygon:
		uv.append(Vector2(p.x / radius.x, p.y / radius.y) * 0.5 + Vector2(0.5, 0.5))
	poly.uv = uv
	poly.texture = _white_texture()
	poly.color = col
	poly.material = material_for(kind)
	parent.add_child(poly)
	return poly

## Pieza plana (corbata, orejas puntiagudas, mejillas, brillos de los ojos).
func _flat(parent: Node, part_name: String, pos: Vector2, points: PackedVector2Array, col: Color) -> Polygon2D:
	var poly := Polygon2D.new()
	poly.name = part_name
	poly.position = pos
	poly.polygon = points
	poly.color = col
	poly.antialiased = true
	parent.add_child(poly)
	return poly

static func _ellipse(radius: Vector2, segments: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in range(segments):
		var angle := (float(i) / float(segments)) * TAU
		points.append(Vector2(cos(angle) * radius.x, sin(angle) * radius.y))
	return points

## Material compartido por tipo ("fur", "cloth", "gloss"): el color va en el Polygon2D.
static func material_for(kind: String) -> ShaderMaterial:
	if not _materials.has(kind):
		var m := ShaderMaterial.new()
		m.shader = load(SHADER_PATH)
		var params: Dictionary = MATERIALS.get(kind, MATERIALS["fur"])
		for k in params:
			m.set_shader_parameter(k, params[k])
		_materials[kind] = m
	return _materials[kind]

static func _white_texture() -> ImageTexture:
	if _white == null:
		var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
		img.fill(Color.WHITE)
		_white = ImageTexture.create_from_image(img)
	return _white

## Sombra de contacto suave (degradado radial: núcleo oscuro bajo los pies que se
## difumina). La usan PlayerAvatar, las vistas previas del menú y la sala de espera.
static func shadow_texture() -> GradientTexture2D:
	if _shadow == null:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
		g.colors = PackedColorArray([Color(0, 0, 0, 0.62), Color(0, 0, 0, 0.36), Color(0, 0, 0, 0)])
		_shadow = GradientTexture2D.new()
		_shadow.gradient = g
		_shadow.fill = GradientTexture2D.FILL_RADIAL
		_shadow.fill_from = Vector2(0.5, 0.5)
		_shadow.fill_to = Vector2(1.0, 0.5)
		_shadow.width = 64
		_shadow.height = 64
	return _shadow

## Dibuja la sombra ovalada en un CanvasItem (centro en los pies).
static func draw_contact_shadow(item: CanvasItem, feet: Vector2, k: float, lift_px := 0.0) -> void:
	var shrink := clampf(1.0 - lift_px * 0.04, 0.6, 1.0)
	var size := Vector2(46.0, 15.0) * k * shrink
	item.draw_texture_rect(shadow_texture(), Rect2(feet - size / 2.0, size), false)
