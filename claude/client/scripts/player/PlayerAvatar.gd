class_name PlayerAvatar
extends Player
## Avatar modular del jugador, preparado para 2.4D (vista cenital con profundidad).
## Escena: res://scenes/player/PlayerAvatar.tscn
##
##   PlayerAvatar (CharacterBody2D, el origen está en los pies)
##   ├── FeetCollision     cápsula plana en los pies: choca con el mapa por donde pisa
##   ├── Visuals           Node2D con Y-Sort: todo lo que se voltea, se aplasta o rebota
##   │   ├── DropShadow    óvalo oscuro en el suelo (z -1: nunca tapa a otro personaje)
##   │   └── BodySprite    AnimatedSprite2D con los PNG de la skin
##   │       └── ChibiBody ProceduralChibiAvatar: se ve mientras la skin no tenga PNG
##   ├── OverheadAnchor    punto sobre la cabeza donde se cuelga la FloatingProgressBar
##   └── OverheadLayer     CanvasLayer que sigue a la cámara, con la píldora del nombre
##
## Skins: skin_id llega del servidor (PublicPlayerState.skinId), que la reparte por
## jugador; es pública y no depende del rol. apply_skin() busca los PNG en
## res://assets/sprites/skins/<skin_id>/ y, si falta frente.png, usa el chibi procedural
## con los colores de la skin. Ver assets/sprites/README.md.
##
## El nombre y la barra viven en CanvasLayers propios: no giran ni se voltean con el
## cuerpo y el CanvasModulate nocturno no los oscurece.
##
## La corbata del chibi lleva el color de tu rol (UiPalette.role_color) solo en tu
## personaje; los demás llevan el acento de su skin. Al terminar la partida
## (game_over) todos pasan al color de su rol.

const NAME_TAG_GAP := 4.0
const SPRITE_HEIGHT := 56.0   # alto en el mapa de las skins con PNG
const OVERHEAD_MIN := 56.0    # el nombre nunca más bajo que esto
const SHADOW_SCALE := 1.3

@export var skin_id: String = "zorro"
@export var skins_root := SkinCatalog.SKINS_ROOT

@onready var visuals: Node2D = $Visuals
@onready var body_sprite: AnimatedSprite2D = $Visuals/BodySprite
@onready var chibi: ProceduralChibiAvatar = $Visuals/BodySprite/ChibiBody
@onready var drop_shadow: Polygon2D = $Visuals/DropShadow
@onready var overhead_anchor: Node2D = $OverheadAnchor
@onready var overhead_layer: CanvasLayer = $OverheadLayer
@onready var name_pill: PanelContainer = $OverheadLayer/NameTag
@onready var name_tag: Label = $OverheadLayer/NameTag/NameTagLabel

var display_name := "": set = set_display_name
## Rol que este cliente conoce del personaje: el propio, o el de todos tras game_over.
var role_id := ""
## true si la skin tiene PNG; si no, se ve el chibi procedural.
var using_sprites := false
## Vista actual: "frente", "lado" o "espalda".
var facing := "frente"

var _last_position := Vector2.ZERO
var _sprite_scale := 1.0
var _phase := 0.0
var _amp := 0.0

func _ready() -> void:
	super()
	chibi.bake = true   # en móviles y web se dibuja horneado: 1 textura (ChibiBaker)
	name_tag.add_theme_font_override("font", UiPalette.heading_font())
	# Píldora oscura translúcida: el nombre se lee sobre cualquier suelo.
	var pill := UiPalette.flat(Color(UiPalette.NAVY, 0.72), Color(1, 1, 1, 0.14), 1, 10, 0)
	pill.content_margin_left = 9
	pill.content_margin_right = 9
	pill.content_margin_top = 1
	pill.content_margin_bottom = 2
	name_pill.add_theme_stylebox_override("panel", pill)
	name_tag.text = display_name
	_soften_shadow()
	GameState.snapshot_applied.connect(_on_state)
	EventBus.game_over.connect(reveal_roles)
	visibility_changed.connect(_sync_overhead_visibility)
	_last_position = global_position
	apply_skin(skin_id)
	_on_state(GameState.snapshot)
	_sync_overhead_visibility()
	_follow_overhead()

## Sombra de contacto: el óvalo de la escena pasa a ser un degradado suave (núcleo
## oscuro bajo los pies que se difumina sobre las baldosas).
func _soften_shadow() -> void:
	var tex := ProceduralChibiAvatar.shadow_texture()
	var r := Vector2(18.0, 6.5)
	var uv := PackedVector2Array()
	for p in drop_shadow.polygon:
		uv.append(Vector2(p.x / r.x, p.y / r.y) * 0.5 + Vector2(0.5, 0.5))
	drop_shadow.texture = tex
	drop_shadow.uv = uv
	drop_shadow.color = Color.WHITE

func set_display_name(value: String) -> void:
	display_name = value
	if name_tag:
		name_tag.text = value
		name_pill.reset_size()

func set_connected(on: bool) -> void:
	super(on)
	name_pill.modulate.a = modulate.a   # el CanvasLayer no hereda el modulate

## Cambia la skin. Con PNG en res://assets/sprites/skins/<id>/ los usa; si no, dibuja
## el chibi procedural con los colores del catálogo. Nunca falla por archivos ausentes.
func apply_skin(new_skin_id: String) -> void:
	skin_id = new_skin_id
	var frames := SkinCatalog.build_frames(skin_id, skins_root)
	using_sprites = frames != null
	body_sprite.sprite_frames = frames
	chibi.visible = not using_sprites
	if using_sprites:
		var h := frames.get_frame_texture("frente", 0).get_height()
		_sprite_scale = SPRITE_HEIGHT / maxf(h, 1.0)
		body_sprite.scale = Vector2.ONE * _sprite_scale
		body_sprite.offset = Vector2(0, -h / 2.0)   # pies en el origen
		body_sprite.animation = "frente"
		body_sprite.stop()
	else:
		body_sprite.scale = Vector2.ONE
		body_sprite.offset = Vector2.ZERO
		chibi.skin_id = skin_id
	_place_overhead()
	_apply_accent()

## El nombre, justo encima de las orejas (o de la gorra) de cada animal.
func _place_overhead() -> void:
	overhead_anchor.position.y = minf(-OVERHEAD_MIN, chibi.top_y() * chibi.scale.y - 2.0) if not using_sprites else -SPRITE_HEIGHT - 6.0

## Cosméticos que lleva (públicos: ropa, gorra, zapatillas, mochila; nunca el rol).
func apply_look(new_look: Dictionary) -> void:
	if new_look == chibi.look:
		return
	chibi.look = new_look
	_place_overhead()

## La barra de canalización va encima del nombre, fuera del cuerpo.
func attach_progress_bar(text: String, duration_s: float, already_elapsed := 0.0, kind := "backup") -> FloatingProgressBar:
	var bar := FloatingProgressBar.attach(overhead_anchor, text, duration_s, already_elapsed, kind)
	bar.position = Vector2(0, -name_pill.size.y - NAME_TAG_GAP)
	return bar

## Hacia dónde mira, para el minimapa: abajo, arriba o al lado según el volteo.
func heading() -> Vector2:
	match facing:
		"espalda":
			return Vector2.UP
		"lado":
			return Vector2(signf(visuals.scale.x), 0.0)
	return Vector2.DOWN

func accent_color() -> Color:
	return chibi.accent_color()

## Pantalla final: se revelan los roles y cada corbata toma el color del suyo.
func reveal_roles(resolution: Dictionary) -> void:
	for p in resolution.get("players", []):
		if p.get("id") == player_id:
			role_id = str(p.get("roleId", ""))
	_apply_accent()

func _on_state(s: Dictionary) -> void:
	if is_local:
		role_id = str(GameState.my_private_state().get("roleId", ""))
	for p in s.get("players", []):
		if p.get("id") == player_id:
			var server_skin := str(p.get("skinId", ""))
			if server_skin != "" and server_skin != skin_id:
				apply_skin(server_skin)
			apply_look(p.get("look", {}) if p.get("look") is Dictionary else {})
	_apply_accent()

func _apply_accent() -> void:
	chibi.set_accent(UiPalette.role_color(role_id) if role_id != "" else Color(0, 0, 0, 0))

func _process(delta: float) -> void:
	var step := global_position - _last_position
	_last_position = global_position
	# velocity.length() en el jugador local; los remotos se interpolan sin velocity,
	# así que también se mide el desplazamiento.
	var speed_now := maxf(velocity.length(), step.length() / maxf(delta, 0.0001))
	_update_facing(step)
	if using_sprites:
		_animate_sprite(delta, speed_now)
	else:
		chibi.animate_walk(delta, speed_now)
	var lift := -body_sprite.position.y if using_sprites else chibi.lift()
	drop_shadow.scale = Vector2.ONE * SHADOW_SCALE * (1.0 - 0.04 * lift)   # al saltar, la sombra se encoge
	_follow_overhead()

## Abajo = frente, arriba = espalda, a los lados = lado (volteando Visuals).
func _update_facing(step: Vector2) -> void:
	if step.length() < 0.2:
		return
	var view := "lado"
	if absf(step.y) > absf(step.x):
		view = "espalda" if step.y < 0.0 else "frente"
	elif absf(step.x) > 0.1:
		visuals.scale.x = signf(step.x)
	if view != facing:
		facing = view
		chibi.set_facing(view)

## Skin con PNG: vista según la dirección y rebote de juguete de cuerda.
func _animate_sprite(delta: float, speed_now: float) -> void:
	var moving := speed_now > 20.0
	_amp = move_toward(_amp, 1.0 if moving else 0.0, delta * 6.0)
	if moving:
		_phase += delta * TAU * (1.6 + 1.2 * clampf(speed_now / speed, 0.0, 1.5))
	var squash := cos(2.0 * _phase) * 0.07 * _amp
	body_sprite.scale = Vector2(1.0 + squash, 1.0 - squash) * _sprite_scale
	body_sprite.position.y = -absf(sin(_phase)) * 3.5 * _amp
	body_sprite.rotation = sin(_phase) * 0.06 * _amp
	var anim := _animation_for(moving)
	if body_sprite.animation != anim:
		body_sprite.animation = anim
	if moving and not body_sprite.is_playing():
		body_sprite.play()
	elif not moving and body_sprite.is_playing():
		body_sprite.stop()
		body_sprite.frame = 0

func _animation_for(moving: bool) -> String:
	var frames := body_sprite.sprite_frames
	match facing:
		"espalda":
			return "espalda" if frames.has_animation("espalda") else "frente"
		"lado":
			return "lado" if frames.has_animation("lado") else "frente"
	return "caminando" if moving and frames.has_animation("caminando") else "frente"

## Centra la píldora del nombre sobre la cabeza, en coordenadas del mundo.
func _follow_overhead() -> void:
	name_pill.position = overhead_anchor.global_position - Vector2(name_pill.size.x / 2.0, name_pill.size.y)

## Un CanvasLayer no hereda la visibilidad: al ocultar el mapa (asamblea) se oculta a mano.
func _sync_overhead_visibility() -> void:
	overhead_layer.visible = is_visible_in_tree()
