class_name SkinPreview
extends Control
## Vista previa 2.4D de una skin de animal para el menú: el mismo chibi procedural del
## mapa (ProceduralChibiAvatar), centrado y escalado al tamaño del control. Respira
## quieto o camina en el sitio; bloqueada se ve como silueta.

## Alto de referencia del chibi a escala 1 (de los pies a la punta de las orejas); cada
## animal da el suyo con ProceduralChibiAvatar.top_y().
const CHIBI_HEIGHT := 100.0
const SILHOUETTE := Color(0.13, 0.16, 0.24, 1.0)
## Hasta este tamaño se usa el chibi horneado en móviles (ChibiBaker); las vistas grandes
## van siempre en vivo para que no se vean borrosas.
const BAKE_MAX_SCALE := 1.5

@export var skin_id := "zorro":
	set(value):
		skin_id = value
		if chibi:
			chibi.skin_id = value
			_layout()
## Cosméticos puestos (CosmeticCatalog); vacío = la ropa de serie del animal.
@export var look: Dictionary = {}:
	set(value):
		look = value
		if chibi:
			chibi.look = value
			_layout()
@export var walking := false
@export var locked := false:
	set(value):
		locked = value
		if chibi:
			chibi.modulate = SILHOUETTE if locked else Color.WHITE
## Solo la cabeza (para retratos redondos de la lista de jugadores o la cabecera).
@export var head_only := false
@export var facing := "frente":
	set(value):
		facing = value
		if chibi:
			chibi.set_facing(value)
## Margen inferior en píxeles (sombra y pies).
@export var foot_margin := 6.0

var chibi: ProceduralChibiAvatar

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = head_only
	chibi = ProceduralChibiAvatar.new()
	chibi.skin_id = skin_id
	chibi.look = look
	chibi.modulate = SILHOUETTE if locked else Color.WHITE
	add_child(chibi)
	chibi.set_facing(facing)
	resized.connect(_layout)
	_layout()

func _layout() -> void:
	if chibi == null:
		return
	if head_only:
		var k := size.y / 60.0
		chibi.scale = Vector2(k, k)
		chibi.position = Vector2(size.x / 2.0, size.y / 2.0 - (ProceduralChibiAvatar.HEAD_Y + 3.0) * k)
		chibi.bake = k <= BAKE_MAX_SCALE
	else:
		# Cabe entero (también a lo ancho: la melena del león y las orejas caídas).
		var tall := maxf(-chibi.top_y(), 80.0) + 4.0
		var k := maxf(0.1, minf((size.y - foot_margin) / tall, size.x / 78.0))
		chibi.scale = Vector2(k, k)
		chibi.position = Vector2(size.x / 2.0, size.y - foot_margin)
		chibi.bake = k <= BAKE_MAX_SCALE
	queue_redraw()

func _draw() -> void:
	if head_only:
		return
	if chibi:
		ProceduralChibiAvatar.draw_contact_shadow(self, chibi.position + Vector2(0, -1), chibi.scale.x, chibi.lift())

func _process(delta: float) -> void:
	if chibi and is_visible_in_tree():
		chibi.animate_walk(delta, chibi.max_speed * 0.55 if walking else 0.0)
		if not head_only:
			queue_redraw()   # la sombra se encoge con cada saltito
