extends Node2D
class_name ProceduralChibiAvatar
## Chibi "de vinilo" hecho con código y un shader, sin PNG: es la figura del avatar
## mientras no existan las imágenes de su skin (ver PlayerAvatar.apply_skin).
##
## Se dibuja como UN rectángulo con res://shaders/chibi_sdf.gdshader, que pinta el animal
## entero con campos de distancia: silueta continua (cabeza con mofletes y orejas fundidas,
## cuerpo con capucha y brazos, zapatillas), volumen inflado tipo muñeco de vinilo, luz de
## estudio satinada, pliegues y oclusión suave entre piezas, y bordes con antialias a
## cualquier escala. Una llamada de dibujo por chibi (antes eran ~60 piezas).
##
## Anatomía (origen en los pies, unidades a escala 1, ~100 px de alto con orejas):
##   zapatillas con suela, puntera, cordones y franja de color; piernas entre la cadera y
##   el tobillo; torso en forma de pera con traje o sudadera; mochila; cola; brazos de dos
##   tramos (hombro y codo) con mano; cabeza grande con orejas, hocico, mofletes, cejas y
##   ojos con iris y dos brillos (parpadean); gorra con visera si la lleva.
##
## El aspecto sale de la skin (SkinCatalog: pelaje, orejas, ropa, zapatillas, mochila,
## cola, gorra...), nunca del rol: la skin la ven todos y el rol es secreto. La corbata
## (o la acreditación de la sudadera) lleva el acento de la skin; PlayerAvatar le pone el
## color de tu rol solo en tu propio personaje (set_accent).
##
## Llama a animate_walk(delta, velocity.length()) cada frame: rebote de juguete de
## cuerda, pasos que levantan las zapatillas, brazos que se balancean doblando el codo,
## cabeza con retraso, orejas y cola con muelle. Quieto, respira y parpadea. La pose se
## manda al shader como unos pocos parámetros por frame.

const SHADER_PATH := "res://shaders/chibi_sdf.gdshader"
const SHOE_Y := 0.0
const HEAD_Y := -64.0
const HEAD_RADIUS := Vector2(27.0, 24.5)
const TORSO_Y := -29.5
const HIP := Vector2(6.5, -14.0)
const ANKLE_UP := 7.0
const SHOULDER := Vector2(14.2, -40.5)
## Códigos que entiende el shader.
const VIEWS := {"frente": 0, "lado": 1, "espalda": 2}
const EAR_TYPES := {"round": 0, "round_stripes": 0, "pointed": 1, "tall_pointed": 2, "long": 3, "floppy": 4, "tufts": 5, "none": 6}
const TAIL_TYPES := {"none": 0, "bushy": 1, "ringed": 2, "thin": 3, "striped": 4, "puff": 5}
const PATCHES := {"": 0, "panda": 1, "mask": 2, "face": 3}
## Ancho del rectángulo que pinta el shader (la figura cabe de sobra, con mochila y cola).
const HALF_WIDTH := 52.0

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
## Dibujarlo horneado (una hoja de sprites) cuando ChibiBaker.enabled() lo permite:
## móviles y web. Ver ChibiBaker.
@export var bake := false:
	set(value):
		bake = value
		if is_node_ready():
			_request_bake()

## Gesto encima de la pose (la mascota del lobby al acariciarla o darle de comer; ver
## PetReactions). Claves opcionales: smile (0..1, ojos cerrados de gusto), mouth (0..1,
## boca abierta), head (Vector3: desplazamiento x, y y giro de la cabeza), arms (Vector4:
## sustituye a los brazos), tail_speed y tail_amp (meneo de la cola). Solo en vivo: el
## chibi horneado no lo muestra.
var emote: Dictionary = {}
## Vista actual: "frente", "lado" o "espalda" (el volteo izquierda/derecha lo hace Visuals).
var facing := "frente"
var config: Dictionary
var head_radius := HEAD_RADIUS
## Material propio de este chibi (sus colores y su pose son parámetros del shader).
var shader_material: ShaderMaterial

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
var _rect := Rect2()
var _rng := RandomNumberGenerator.new()
var _sheet: Texture2D     # hoja horneada (null = shader en vivo)
var _bake_key := ""
var _frame := -1          # paso de la hoja (-1 = quieto)
# Pose actual (la que recibe el shader).
var _lift := 0.0
var _squash := 0.0
var _body_rot := 0.0
var _feet: Array[Vector2] = [Vector2(-7.5, 0), Vector2(7.5, 0)]
var _feet_rot: Array[float] = [0.0, 0.0]
var _arms := Vector4(0.16, -0.25, -0.16, 0.25)
var _head_pos := Vector2(0, HEAD_Y)
var _head_rot := 0.0
var _tail_rot := 0.0
var _eye_open := 1.0
var _smile := 0.0
var _mouth := 0.0

static var _shader: Shader
static var _shadow: GradientTexture2D
static var _shadow_core: GradientTexture2D

func _notification(what: int) -> void:
	if what == NOTIFICATION_ENTER_TREE and shader_material:
		shader_material.set_shader_parameter("linear_output", linear_viewport(get_viewport()))

## true si el viewport pinta en espacio lineal (HDR 2D, solo en Forward+/Mobile): el
## shader convierte su color sRGB al final. Las hojas de ChibiBaker se hornean en sRGB y
## Godot las pasa a lineal al dibujarlas.
static func linear_viewport(vp: Viewport) -> bool:
	return vp != null and vp.use_hdr_2d and RenderingServer.get_rendering_device() != null

func _ready() -> void:
	_rng.randomize()
	_blink_in = _rng.randf_range(1.5, 4.5)
	generate_avatar()

func generate_avatar() -> void:
	_show_sheet(null)
	config = CosmeticCatalog.dress(SkinCatalog.skin(skin_id), look)
	if shader_material == null:
		shader_material = ShaderMaterial.new()
		shader_material.shader = shader()
		shader_material.set_shader_parameter("linear_output", linear_viewport(get_viewport()) if is_inside_tree() else false)
	var fur := Color(config.get("fur", "#D9622B"))
	var fur_light := Color(config.get("fur_light", "#F8E8DA"))
	var outfit := Color(config.get("outfit", "#1E2A4A"))
	var hoodie: bool = config.get("style", "suit") == "hoodie"
	var sb: Array = config.get("scale_body", [1.0, 1.0])
	head_radius = Vector2(HEAD_RADIUS.x * float(sb[0]), HEAD_RADIUS.y * float(sb[1]))
	var ear_kind := str(config.get("ear_type", "round"))
	var ear_color := Color(config.get("ear_color", fur.to_html()))
	var ear_outer := ear_color
	var ear_inner := fur_light
	match ear_kind:
		"pointed", "tall_pointed":
			ear_inner = fur_light.lerp(Color("#F4A6B8"), 0.35)
		"long":
			ear_inner = Color("#F7B6C8")
		"floppy":
			ear_outer = ear_color.darkened(0.28)
		"tufts":
			ear_outer = ear_color.darkened(0.25)
		_:
			ear_inner = ear_color.lightened(0.18) if config.has("ear_color") else fur_light
	var tail_kind := str(config.get("tail", "none"))
	var m := shader_material
	m.set_shader_parameter("head_r", head_radius)
	m.set_shader_parameter("body_w", (1.04 if hoodie else 0.98) * lerpf(1.0, float(sb[0]), 0.5))
	m.set_shader_parameter("ear_type", EAR_TYPES.get(ear_kind, 0))
	m.set_shader_parameter("stripes", ear_kind == "round_stripes")
	m.set_shader_parameter("patches", PATCHES.get(str(config.get("patches", "")), 0))
	m.set_shader_parameter("beak", config.get("snout", "nose") == "beak")
	m.set_shader_parameter("tail_type", TAIL_TYPES.get(tail_kind, 0))
	m.set_shader_parameter("has_mane", config.has("mane"))
	m.set_shader_parameter("has_cap", config.get("hat", "") == "cap")
	m.set_shader_parameter("hoodie", hoodie)
	_set_color("fur_color", fur)
	_set_color("fur_light", fur_light)
	_set_color("ear_outer", ear_outer)
	_set_color("ear_inner", ear_inner)
	_set_color("mane_color", Color(config.get("mane", "#A8642A")))
	_set_color("outfit_color", outfit)
	_set_color("pants_color", Color("#2B3A55") if hoodie else outfit.darkened(0.35))
	_set_color("shoe_color", Color(config.get("shoes", "#F1F5F9")))
	_set_color("bag_color", Color(config.get("bag", "#1F2937")))
	_set_color("cap_color", Color(config.get("hat_color", "#1E3A8A")))
	_set_color("eye_color", Color(config.get("eye", "#2A1A12")))
	_set_color("brow_color", fur.darkened(0.55) if fur.get_luminance() > 0.25 else fur.lightened(0.45))
	_set_color("tail_color", fur_light.darkened(0.04) if tail_kind == "puff" else fur)   # pompón claro (también el del panda)
	_set_color("tail_tip", fur_light if skin_id == "zorro" else fur.lightened(0.15))
	_set_color("tail_band", fur.darkened(0.55))
	_set_color("accent_color", _accent())
	_top = _compute_top(head_radius)
	_rect = Rect2(-HALF_WIDTH, _top - 10.0, HALF_WIDTH * 2.0, -_top + 10.0 + 8.0)
	material = shader_material
	set_facing(facing)
	_request_bake()

## Altura de la punta (orejas, gorra o cabeza) sobre los pies, en negativo: para colocar
## el nombre justo encima.
func top_y() -> float:
	return _top

## Rasgos que dibuja el shader para esta skin (para pruebas y depuración).
func features() -> Dictionary:
	if shader_material == null:
		return {}
	var keys := ["ear_type", "stripes", "patches", "beak", "tail_type", "has_mane", "has_cap", "hoodie", "view"]
	var out := {}
	for k in keys:
		out[k] = shader_material.get_shader_parameter(k)
	return out

func shader_param(param: String) -> Variant:
	return shader_material.get_shader_parameter(param) if shader_material else null

## Color del acento (corbata o cinta). Por defecto el de la skin; PlayerAvatar pone el
## color de tu rol solo en tu propio personaje.
func set_accent(c: Color) -> void:
	_accent_override = c
	if shader_material:
		_set_color("accent_color", _accent())
	if bake:
		_request_bake()

func accent_color() -> Color:
	return _accent()

## "frente": cara a la vista. "lado": mira a la derecha (Visuals voltea para la izquierda):
## la cara va de perfil, se ven la mochila y la cola y solo el brazo de delante.
## "espalda": sin cara; mochila y cola delante.
func set_facing(view: String) -> void:
	facing = view
	if shader_material == null:
		return
	if _sheet:
		queue_redraw()
	shader_material.set_shader_parameter("view", VIEWS.get(view, 0))
	var side := view == "lado"
	_feet[0].x = -2.5 if side else -7.5
	_feet[1].x = 3.0 if side else 7.5
	_push_pose()

## Altura a la que el rebote levanta el cuerpo (PlayerAvatar encoge la sombra).
func lift() -> float:
	return _lift

# Animación procedural (wobble 2.4D de juguete de cuerda).
func animate_walk(delta: float, speed: float) -> void:
	if shader_material == null:
		return
	var ratio := clampf(speed / maxf(max_speed, 1.0), 0.0, 1.5)
	var moving := ratio > 0.05
	_amp = move_toward(_amp, 1.0 if moving else 0.0, delta * 6.0)
	if moving:
		_phase += delta * TAU * (1.6 + 1.2 * ratio)   # pasos por segundo según la velocidad
	elif _amp == 0.0:
		_phase = 0.0
	_breath += delta * TAU * 0.4
	_tail_time += delta * (6.0 + 6.0 * _amp) * float(emote.get("tail_speed", 1.0))

	var step := sin(_phase)
	var side := facing == "lado"
	var lift_px := absf(step) * 3.0 * _amp                                # un saltito por paso
	_lift = lift_px
	if _sheet:
		# Horneado: solo se elige el paso de la hoja (lo demás ya está en la imagen).
		var frame := posmod(int(floor(fposmod(_phase, TAU) / TAU * ChibiBaker.WALK_FRAMES + 0.5)), ChibiBaker.WALK_FRAMES) if _amp > 0.5 else -1
		if frame != _frame:
			_frame = frame
			queue_redraw()
		return
	_squash = cos(2.0 * _phase) * 0.06 * _amp + sin(_breath) * 0.018 * (1.0 - _amp)
	_body_rot = step * 0.06 * _amp + (0.05 * _amp if side else 0.0)

	# Zapatillas: se levantan por turnos y, de lado, van adelante y atrás.
	for i in 2:
		var s := step if i == 0 else -step
		var c := cos(_phase) if i == 0 else -cos(_phase)
		_feet[i].y = SHOE_Y - maxf(0.0, s) * 4.5 * _amp
		if side:
			_feet[i].x = (-2.5 if i == 0 else 3.0) + c * 6.0 * _amp
			_feet_rot[i] = -maxf(0.0, s) * 0.35 * _amp
		else:
			_feet_rot[i] = 0.0

	# Brazos: balanceo opuesto a las piernas; el codo se dobla más al ir hacia delante.
	var swing := step * (0.65 if side else 0.45) * _amp
	var rest := 0.16 + sin(_breath) * 0.03 * (1.0 - _amp)
	_arms.x = rest + swing
	_arms.y = -(0.25 + maxf(0.0, step) * 0.6 * _amp)
	_arms.z = -rest + (-swing if not side else swing * -1.0)
	_arms.w = 0.25 + maxf(0.0, -step) * 0.6 * _amp if not side else -(0.3 + maxf(0.0, step) * 0.7 * _amp)

	# Cabeza con un poco de retraso y balanceo.
	_head_pos.x = 0.0
	_head_pos.y = HEAD_Y + lift_px * 0.35 + sin(_breath) * 0.6 * (1.0 - _amp)
	_head_rot = sin(_phase - 0.6) * 0.05 * _amp

	# Orejas y cola con muelle: el rebote las sacude y vuelven solas.
	var lift_velocity := (lift_px - _last_lift) / maxf(delta, 0.0001)
	_last_lift = lift_px
	_ear_velocity += (-_ear_angle * 120.0 - _ear_velocity * 10.0 + lift_velocity * 0.6) * delta
	_ear_angle = clampf(_ear_angle + _ear_velocity * delta, -0.35, 0.35)
	_tail_rot = sin(_tail_time) * (0.12 + 0.18 * _amp) * float(emote.get("tail_amp", 1.0))

	# Parpadeo.
	if _blink_left > 0.0:
		_blink_left -= delta
		if _blink_left <= 0.0:
			_eye_open = 1.0
	else:
		_blink_in -= delta
		if _blink_in <= 0.0:
			_blink_left = 0.12
			_blink_in = _rng.randf_range(2.0, 5.0)
			_eye_open = 0.12
	_apply_emote()
	_push_pose()

## Suma el gesto (emote) a la pose calculada.
func _apply_emote() -> void:
	_smile = clampf(float(emote.get("smile", 0.0)), 0.0, 1.0)
	_mouth = clampf(float(emote.get("mouth", 0.0)), 0.0, 1.0)
	if emote.is_empty():
		return
	var head: Vector3 = emote.get("head", Vector3.ZERO)
	_head_pos += Vector2(head.x, head.y)
	_head_rot += head.z
	if emote.has("arms"):
		_arms = emote["arms"]

## Sacude las orejas con su muelle (un empujón; vuelven solas).
func kick_ears(impulse: float) -> void:
	_ear_velocity += impulse

## Pone una pose fija del paso (fase 0..TAU, amount 0 = quieto): la usa ChibiBaker.
func pose(phase: float, amount: float) -> void:
	_amp = amount
	_phase = phase
	animate_walk(0.0, max_speed if amount > 0.0 else 0.0)

## Pose actual tal como la recibe el shader (para pruebas).
func pose_state() -> Dictionary:
	return {"lift": _lift, "squash": _squash, "body_rot": _body_rot, "feet": _feet.duplicate(), "arms": _arms, "head": _head_pos, "eye_open": _eye_open, "smile": _smile, "mouth": _mouth}

## Los colores van como Vector4 en sRGB: un Color se pasaría a lineal en los viewports con
## HDR 2D y la luz del shader se calcularía en otro espacio (se vería distinto en PC y móvil).
func _set_color(param: String, c: Color) -> void:
	shader_material.set_shader_parameter(param, Vector4(c.r, c.g, c.b, c.a))

func _push_pose() -> void:
	var m := shader_material
	m.set_shader_parameter("body_anim", Vector4(_lift, _squash, _body_rot, 0.0))
	m.set_shader_parameter("head_anim", Vector4(_head_pos.x, _head_pos.y, _head_rot, _ear_angle))
	m.set_shader_parameter("feet_pos", Vector4(_feet[0].x, _feet[0].y, _feet[1].x, _feet[1].y))
	m.set_shader_parameter("feet_rot", Vector2(_feet_rot[0], _feet_rot[1]))
	m.set_shader_parameter("arm_rot", _arms)
	m.set_shader_parameter("tail_rot", _tail_rot)
	m.set_shader_parameter("eye_open", _eye_open)
	m.set_shader_parameter("eye_smile", _smile)
	m.set_shader_parameter("mouth_open", _mouth)

func _draw() -> void:
	if _sheet:
		draw_texture_rect_region(_sheet, ChibiBaker.local_rect(), ChibiBaker.region(facing, _frame))
	elif shader_material:
		draw_rect(_rect, Color.WHITE)

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

## Con hoja: se dibuja la textura (alfa premultiplicado, como sale del SubViewport, con
## mipmaps para que no se pixele al alejarse). Sin hoja: el shader en vivo.
func _show_sheet(tex: Texture2D) -> void:
	_sheet = tex
	material = ChibiBaker.premultiplied() if tex else shader_material
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS if tex else CanvasItem.TEXTURE_FILTER_PARENT_NODE
	queue_redraw()

func _accent() -> Color:
	return _accent_override if _accent_override.a > 0.0 else Color(config.get("accent", "#FF334B"))

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

static func shader() -> Shader:
	if _shader == null:
		_shader = load(SHADER_PATH)
	return _shader

## Sombra de contacto difusa: penumbra ancha y muy suave (luz de estudio grande) con un
## núcleo más oscuro bajo los pies. La usan PlayerAvatar, las vistas previas del menú y
## la sala de espera; el shader añade la oclusión justo debajo de cada zapatilla.
static func shadow_texture() -> GradientTexture2D:
	if _shadow == null:
		_shadow = _radial([0.0, 0.3, 0.62, 1.0], [Color(0, 0, 0, 0.42), Color(0, 0, 0, 0.30), Color(0, 0, 0, 0.11), Color(0, 0, 0, 0)])
	return _shadow

static func _shadow_core_texture() -> GradientTexture2D:
	if _shadow_core == null:
		_shadow_core = _radial([0.0, 0.5, 1.0], [Color(0, 0, 0, 0.38), Color(0, 0, 0, 0.16), Color(0, 0, 0, 0)])
	return _shadow_core

static func _radial(offsets: Array, colors: Array) -> GradientTexture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array(offsets)
	g.colors = PackedColorArray(colors)
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 128
	t.height = 128
	return t

## Dibuja la sombra ovalada en un CanvasItem (centro en los pies): se encoge y se aclara
## cuando el cuerpo salta.
static func draw_contact_shadow(item: CanvasItem, feet: Vector2, k: float, lift_px := 0.0) -> void:
	var shrink := clampf(1.0 - lift_px * 0.04, 0.6, 1.0)
	var wide := Vector2(60.0, 19.0) * k * shrink
	item.draw_texture_rect(shadow_texture(), Rect2(feet + Vector2(1.5 * k, 0.5 * k) - wide / 2.0, wide), false)
	var core := Vector2(34.0, 9.0) * k * shrink
	item.draw_texture_rect(_shadow_core_texture(), Rect2(feet - core / 2.0, core), false, Color(1, 1, 1, shrink))
