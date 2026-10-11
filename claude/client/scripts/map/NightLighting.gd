class_name NightLighting
extends Node2D
## Ambiente nocturno de la auditoría: un CanvasModulate oscurece el mundo y cada
## personaje y cada pista lleva su propia luz para que sigan leyéndose en la penumbra.
##
## Solo afecta al mundo (capa 0 del canvas): la UI, el modal y las barras flotantes
## viven en CanvasLayers propios y no se oscurecen. Al ocultar el mapa (fase de
## asamblea) el CanvasModulate deja de aplicarse.

@export var night_color := Color("#2A3350")        # tono del ambiente (más oscuro = más noche)
@export var players_root: Node                      # Map/Players
@export var evidence_root: Node                     # Map/Evidence
@export var local_light_scale := 3.2                # radio de la linterna del jugador local
@export var player_light_scale := 1.6
## Energía de las luces de jugadores. Se suman donde se solapan: si pasan de 1 los
## cuerpos se queman a blanco (y con hdr_2d + glow, brillan).
@export var local_light_energy := 0.6
@export var player_light_energy := 0.3
@export var evidence_light_scale := 1.1
@export var evidence_light_color := Color("#E5A93C")  # UiPalette.AMBER: las pistas brillan en ámbar
## Suelo de oficina bajo el mapa (el color de fondo no lo oscurece el CanvasModulate,
## así que sin suelo las luces no tendrían dónde verse). Tamaño 0 = sin suelo.
@export var floor_rect := Rect2(-640, -384, 2560, 1536)
@export var floor_color := Color("#5A6684")
@export var floor_tile := 64.0

var modulate_node: CanvasModulate
var _local_light: PointLight2D
static var _light_texture: GradientTexture2D

func _ready() -> void:
	z_index = -10  # el suelo se dibuja debajo de jugadores y pistas
	queue_redraw()
	modulate_node = CanvasModulate.new()
	modulate_node.name = "NightModulate"
	modulate_node.color = night_color
	add_child(modulate_node)
	for root in [players_root, evidence_root]:
		if root == null:
			continue
		for child in root.get_children():
			_light_up(child)
		root.child_entered_tree.connect(_light_up)
	# Visión nocturna (búho): la linterna del jugador local alumbra más lejos.
	Abilities.ability_changed.connect(func(_skin: String, _kit: Dictionary) -> void: _scale_local_light())

## Moqueta de oficina: losetas con una junta tenue para que las luces se noten.
func _draw() -> void:
	if floor_rect.size == Vector2.ZERO:
		return
	draw_rect(floor_rect, floor_color.darkened(0.25))  # juntas
	var x := floor_rect.position.x
	while x < floor_rect.end.x:
		var y := floor_rect.position.y
		while y < floor_rect.end.y:
			draw_rect(Rect2(x + 1, y + 1, floor_tile - 2, floor_tile - 2), floor_color)
			y += floor_tile
		x += floor_tile

## Luz circular suave (degradado radial blanco → transparente), compartida.
static func light_texture() -> GradientTexture2D:
	if _light_texture == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		g.add_point(0.5, Color(1, 1, 1, 0.55))
		_light_texture = GradientTexture2D.new()
		_light_texture.gradient = g
		_light_texture.fill = GradientTexture2D.FILL_RADIAL
		_light_texture.fill_from = Vector2(0.5, 0.5)
		_light_texture.fill_to = Vector2(1.0, 0.5)
		_light_texture.width = 256
		_light_texture.height = 256
	return _light_texture

func _light_up(node: Node) -> void:
	if not node is Node2D or node.has_node("NightLight"):
		return
	var light := PointLight2D.new()
	light.name = "NightLight"
	light.texture = light_texture()
	if node is Player:
		light.texture_scale = local_light_scale if node.is_local else player_light_scale
		light.energy = local_light_energy if node.is_local else player_light_energy
		light.color = Color("#DCE6FF")
		if node.is_local:
			_local_light = light
	else:
		light.texture_scale = evidence_light_scale
		light.energy = 0.9
		light.color = evidence_light_color
	node.add_child(light)
	if light == _local_light:
		_scale_local_light()

func _scale_local_light() -> void:
	if is_instance_valid(_local_light):
		_local_light.texture_scale = local_light_scale * Abilities.flashlight_multiplier()
