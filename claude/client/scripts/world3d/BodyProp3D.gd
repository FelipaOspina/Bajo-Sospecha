class_name BodyProp3D
extends Node3D
## Cuerpo de un jugador silenciado en la vista 3D (snapshot.bodies), en estilo cartoon:
## el mismo personaje de peluche (PlushAvatar3D) tumbado boca arriba en el suelo.
##  - noqueado (kind "knocked"): ojos cerrados, tres estrellitas girando sobre la
##    cabeza y la cuenta atrás hasta que se levanta (until, hora del servidor);
##  - fuera de juego (kind "dead"): ojos en X, sin estrellas. Se queda hasta que lo
##    reportan (reported: true) y entonces deja de dibujarse.
## Nada gore. Nunca muestra el rol: solo la skin y los cosméticos públicos.

## Personaje 3D cargado por ruta (no por class_name): funciona aunque la caché de clases
## de .godot sea vieja, p. ej. al abrir el juego con el .bat sin pasar por el editor.
const Plush3D := preload("res://scripts/world3d/HeroAvatar3D.gd")   # hero; sin su GLB cae a PlushAvatar3D / vinilo
const STAR_COUNT := 3
const STAR_ORBIT := 0.34
const STAR_SPEED := 2.6          # rad/s
const STAR_COLOR := Color("#FFD54A")

var body_id := ""
var player_id := ""
var kind := ""
var skin_id := ""
## Hora del servidor (ms) a la que se levanta (solo noqueado); -1 sin cuenta atrás.
var until_ms := -1

var model: Plush3D
var stars: Node3D
var countdown: Label3D
var _alpha := 1.0
var _star_mat: StandardMaterial3D
var _time := 0.0

## Arma el cuerpo. look: cosméticos públicos.
func build(id: String, owner_id: String, skin: String, look: Dictionary, body_kind: String) -> void:
	body_id = id
	player_id = owner_id
	skin_id = skin
	for c in get_children():
		c.queue_free()
	var lie := Node3D.new()
	lie.name = "Lying"
	# Un giro leve distinto por jugador para que no queden todos iguales.
	lie.rotation.y = (float(hash(owner_id) % 100) / 100.0 - 0.5) * 0.5
	add_child(lie)
	# Tumbado de lado, como en los dibujos: la cabeza a un lado (izquierda o derecha
	# según el jugador), la cara hacia la cámara y un poco hacia arriba.
	var side := 1.0 if hash(owner_id) % 2 == 0 else -1.0
	var tumble := Node3D.new()
	tumble.name = "Tumble"
	tumble.rotation.z = PI / 2.0 * side
	# El eje del tumbado a la altura de media cabeza: la mejilla toca el suelo.
	tumble.position = Vector3(0, Plush3D.HEAD_R * 0.95, 0)
	lie.add_child(tumble)
	model = Plush3D.new()
	model.name = "Model"
	tumble.add_child(model)
	model.build(skin, look)
	var mid := (Plush3D.BODY_Y + Plush3D.HEAD_Y) * 0.5   # entre tripa y cabeza
	model.position.y = -mid
	# Gira sobre su eje largo para que la cara mire arriba y hacia la cámara.
	model.rotation.y = 0.75 * side
	stars = Node3D.new()
	stars.name = "Stars"
	# Sobre la cabeza.
	stars.position = Vector3(-(Plush3D.HEAD_Y - mid + 0.1) * side, Plush3D.HEAD_R * 2.0 + 0.12, 0.0)
	lie.add_child(stars)
	_star_mat = StandardMaterial3D.new()
	_star_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_star_mat.albedo_color = STAR_COLOR * 1.6
	_star_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mesh := star_mesh(0.12, 0.055, 0.03)
	for i in STAR_COUNT:
		var star := MeshInstance3D.new()
		star.name = "Star%d" % i
		star.mesh = mesh
		star.material_override = _star_mat
		var a := TAU * float(i) / STAR_COUNT
		star.position = Vector3(cos(a), 0, sin(a)) * STAR_ORBIT
		stars.add_child(star)
	countdown = Label3D.new()
	countdown.name = "Countdown"
	countdown.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	countdown.no_depth_test = true
	countdown.fixed_size = false
	countdown.pixel_size = 0.006
	countdown.font_size = 56
	countdown.outline_size = 14
	countdown.modulate = STAR_COLOR
	countdown.outline_modulate = Color(0.05, 0.06, 0.12, 0.9)
	countdown.position = Vector3(0, 1.45, 0)
	if UiPalette.heading_font():
		countdown.font = UiPalette.heading_font()
	add_child(countdown)
	kind = ""
	set_kind(body_kind)

## Cambia entre noqueado y fuera de juego.
func set_kind(body_kind: String) -> void:
	if body_kind == kind:
		return
	kind = body_kind
	var knocked := kind == Protocol.BODY_KNOCKED
	stars.visible = knocked
	countdown.visible = knocked
	if model:
		model.set_knocked_face(kind)

## Segundos que faltan para que se levante (-1 si no hay cuenta atrás).
func seconds_left(now_ms: float) -> int:
	if until_ms < 0 or kind != Protocol.BODY_KNOCKED:
		return -1
	return maxi(0, ceili((float(until_ms) - now_ms) / 1000.0))

## Estrellas girando y cuenta atrás.
func tick(delta: float, now_ms: float) -> void:
	_time += delta
	if stars.visible:
		stars.rotation.y = _time * STAR_SPEED
		for s in stars.get_children():
			s.rotation.y = -_time * 4.0
			s.position.y = sin(_time * 3.0 + s.get_index()) * 0.04
	var left := seconds_left(now_ms)
	countdown.visible = left >= 0
	if left >= 0:
		countdown.text = str(left)

## Opacidad (línea de vista): 1 = sólido.
func set_alpha(a: float) -> void:
	if is_equal_approx(a, _alpha):
		return
	_alpha = a
	if model:
		model.set_alpha(a)
	_star_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if a < 0.99 else BaseMaterial3D.TRANSPARENCY_DISABLED
	_star_mat.albedo_color.a = a
	countdown.modulate.a = a
	countdown.outline_modulate.a = 0.9 * a

## Estrella de cinco puntas plana (en XZ) con un poco de grosor.
static func star_mesh(outer: float, inner: float, thick: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pts: Array[Vector3] = []
	for i in 10:
		var r := outer if i % 2 == 0 else inner
		var a := -PI / 2.0 + TAU * float(i) / 10.0
		pts.append(Vector3(cos(a) * r, 0, sin(a) * r))
	for y in [thick / 2.0, -thick / 2.0]:
		var n := Vector3.UP if y > 0 else Vector3.DOWN
		for i in 10:
			st.set_normal(n)
			st.add_vertex(Vector3(0, y, 0))
			st.set_normal(n)
			st.add_vertex(pts[i] + Vector3(0, y, 0))
			st.set_normal(n)
			st.add_vertex(pts[(i + 1) % 10] + Vector3(0, y, 0))
	return st.commit()
