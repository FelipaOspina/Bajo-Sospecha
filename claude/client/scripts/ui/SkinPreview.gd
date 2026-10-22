class_name SkinPreview
extends Control
## Vista previa de una skin de animal para el menú, la tienda y los retratos: el mismo
## personaje 3D de peluche del mapa (PlushAvatar3D), dibujado en un SubViewport
## transparente y centrado en el control. Camina en el sitio o se queda quieto;
## bloqueada se ve como silueta.
##
## Rendimiento: quieta se dibuja una sola vez (UPDATE_ONCE) y luego es una textura
## fija; solo las vistas que caminan se redibujan cada frame.

## Personaje 3D cargado por ruta (no por class_name): funciona aunque la caché de clases
## de .godot sea vieja, p. ej. al abrir el juego con el .bat sin pasar por el editor.
const Plush3D := preload("res://scripts/world3d/HeroAvatar3D.gd")   # hero; sin su GLB cae a PlushAvatar3D / vinilo
const SILHOUETTE := Color(0.13, 0.16, 0.24, 1.0)
const YAW := {"frente": 0.38, "lado": PI / 2.0, "espalda": PI}

@export var skin_id := "zorro":
	set(value):
		skin_id = value
		_rebuild()
## Cosméticos puestos (CosmeticCatalog); vacío = la ropa de serie del animal.
@export var look: Dictionary = {}:
	set(value):
		look = value
		_rebuild()
@export var walking := false:
	set(value):
		walking = value
		if model and not walking:
			model.animate(1.0, Vector3.ZERO, 0.0)   # vuelve a la pose quieta
		_refresh()
@export var locked := false:
	set(value):
		locked = value
		queue_redraw()
## Solo la cabeza (para retratos redondos de la lista de jugadores o la cabecera).
@export var head_only := false:
	set(value):
		head_only = value
		_layout()
@export var facing := "frente":
	set(value):
		facing = value
		if model:
			model.face(YAW.get(value, 0.0))
		_refresh()
## Margen inferior en píxeles (sombra y pies).
@export var foot_margin := 6.0

var model: Plush3D
var _viewport: SubViewport
var _camera: Camera3D
var _built_key := ""

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mobile := OS.has_feature("mobile") or OS.has_feature("web")
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.transparent_bg = true
	_viewport.msaa_3d = Viewport.MSAA_2X if mobile else Viewport.MSAA_4X
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(_viewport)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_CLEAR_COLOR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("#B8C4E0")
	e.ambient_light_energy = 0.75
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	e.tonemap_exposure = 1.05
	env.environment = e
	_viewport.add_child(env)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-38, -32, 0)
	key.light_energy = 1.25
	key.light_color = Color("#FFF4E6")
	_viewport.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-20, 150, 0)
	rim.light_energy = 0.9
	rim.light_color = Color("#9DB8FF")
	_viewport.add_child(rim)

	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.rotation_degrees = Vector3(-10, 0, 0)
	_camera.current = true
	_viewport.add_child(_camera)

	model = Plush3D.new()
	_viewport.add_child(model)
	resized.connect(_layout)
	visibility_changed.connect(_refresh)
	_rebuild()

func _rebuild() -> void:
	if model == null:
		return
	var k := skin_id + JSON.stringify(look)
	if k != _built_key:
		_built_key = k
		model.build(skin_id, look)
		model.face(YAW.get(facing, 0.0))
	_layout()

func _layout() -> void:
	if _viewport == null:
		return
	var scale_px := get_viewport().get_final_transform().get_scale().y if get_viewport() else 1.0
	var px := Vector2i((size * clampf(scale_px, 1.0, 2.0)).ceil())
	_viewport.size = Vector2i(maxi(px.x, 8), maxi(px.y, 8))
	var aspect := size.x / maxf(size.y, 1.0)
	if head_only:
		# La cara: de la barbilla a la punta de las orejas.
		_camera.size = 1.0 / minf(aspect, 1.0)
		_aim(Vector3(0, Plush3D.HEAD_Y + 0.1, 0))
	else:
		# Entero, con melenas y orejas largas; los pies quedan a foot_margin del borde.
		var tall := Plush3D.HEIGHT + 0.42
		var h := maxf(tall, 1.3 / maxf(aspect, 0.1))
		_camera.size = h
		var margin_m := foot_margin / maxf(size.y, 1.0) * h
		_aim(Vector3(0, h / 2.0 - 0.06 - margin_m, 0))
	_refresh()
	queue_redraw()

## La cámara (inclinada) mira al punto dado desde 6 m.
func _aim(target: Vector3) -> void:
	_camera.position = target + _camera.transform.basis.z * 6.0

## Quieta: se dibuja una vez. Caminando: cada frame mientras se vea.
func _refresh() -> void:
	if _viewport == null:
		return
	if walking and is_visible_in_tree():
		_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	else:
		_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	set_process(walking)
	queue_redraw()

func _draw() -> void:
	if _viewport == null:
		return
	if not head_only:
		var k := size.y / 140.0
		ProceduralChibiAvatar.draw_contact_shadow(self, Vector2(size.x / 2.0, size.y - foot_margin - 1.0), k, 0.0)
	draw_texture_rect(_viewport.get_texture(), Rect2(Vector2.ZERO, size), false, SILHOUETTE if locked else Color.WHITE)

func _process(delta: float) -> void:
	if model and walking and is_visible_in_tree():
		var yaw: float = YAW.get(facing, 0.0)
		model.animate(delta, Vector3(sin(yaw), 0.0, cos(yaw)), 0.6)
		queue_redraw()
