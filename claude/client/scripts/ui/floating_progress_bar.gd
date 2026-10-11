class_name FloatingProgressBar
extends Node2D
## Barra de canalización flotante sobre la cabeza del personaje ("Purgando logs...").
##
## La barra se dibuja en un CanvasLayer propio con follow_viewport_enabled: sigue a la
## cámara (posición y zoom del mundo) pero NO hereda la escala ni el volteo del
## personaje (scale.x = -1), así que no se deforma. Este Node2D solo marca el punto
## de anclaje; cada frame se recoloca BarAnchor encima.
##
## Color dinámico: #ff334b para acciones hostiles (borrar logs, triturar) y #00e5ff
## para respaldos pacíficos (descargar, fotografiar). Ver UiPalette.
##
## Uso:
##   var bar := FloatingProgressBar.attach(player, "Tomando foto...", 3.0, 0.0, "backup")
##   bar.completed.connect(...)
##   bar.interrupted.connect(func(reason): ...)
## Dos modos:
##  - auto_complete = true: se completa sola al acabar el tiempo (uso local / offline).
##  - auto_complete = false: llena hasta el 100 % y espera a server_finished(ok, reason).
##    Así todos los jugadores cercanos ven el mismo resultado que decide el servidor.
## Con watch_movement, si el personaje se mueve emite interrupted("moved").

signal completed
signal interrupted(reason: String)

const SCENE_PATH := "res://scenes/ui/FloatingProgressBar.tscn"
const COLOR_FAILED := Color("#64748B")

@export var vertical_offset := -44.0  # por encima del nombre del jugador
@export var move_tolerance := 6.0
@export var watch_movement := false
@export var auto_complete := true

var action_label := ""
var duration := 1.0
var elapsed := 0.0
var finished := false
var is_hostile := false

var _origin := Vector2.ZERO
@onready var layer: CanvasLayer = $CanvasLayer
@onready var anchor: Control = $CanvasLayer/BarAnchor
@onready var label: Label = $CanvasLayer/BarAnchor/Layout/ActionLabel
@onready var progress_bar: ProgressBar = $CanvasLayer/BarAnchor/Layout/ChannelingBar

## Crea la barra sobre `target` (normalmente el Player) y la arranca.
## kind: "delete" (hostil, rojo) o "backup" (pacífica, cian).
static func attach(target: Node2D, text: String, duration_s: float, already_elapsed := 0.0, kind := "backup") -> FloatingProgressBar:
	var bar: FloatingProgressBar = load(SCENE_PATH).instantiate()
	target.add_child(bar)
	bar.start(text, duration_s, already_elapsed, UiPalette.is_hostile(kind))
	return bar

func _ready() -> void:
	position = Vector2(0, vertical_offset)
	layer.follow_viewport_enabled = true
	# Un CanvasLayer no hereda la visibilidad: si se oculta el mapa, se oculta la barra.
	visibility_changed.connect(func() -> void: layer.visible = is_visible_in_tree())
	label.add_theme_font_override("font", UiPalette.heading_font())
	label.add_theme_color_override("font_color", UiPalette.TEXT)
	var under := UiPalette.flat(Color(UiPalette.NAVY, 0.8), Color(0, 0, 0, 0.6), 1, 3, 0)
	progress_bar.add_theme_stylebox_override("background", under)

func start(text: String, duration_s: float, already_elapsed := 0.0, hostile := false) -> void:
	action_label = text
	duration = maxf(duration_s, 0.001)
	elapsed = clampf(already_elapsed, 0.0, duration)
	finished = false
	_origin = _owner_position()
	label.text = text
	set_hostile(hostile)
	_update_bar()
	_follow()

## Nombres de la especificación de diseño.
func start_channeling(text: String, duration_s: float, hostile := false) -> void:
	start(text, duration_s, 0.0, hostile)

func cancel_channeling(reason := "moved") -> void:
	interrupt(reason)

## Rojo (#ff334b) si es hostil, cian (#00e5ff) si es un respaldo.
func set_hostile(hostile: bool) -> void:
	is_hostile = hostile
	_set_color(UiPalette.CRIMSON if hostile else UiPalette.CYAN)

func bar_color() -> Color:
	var s := progress_bar.get_theme_stylebox("fill") as StyleBoxFlat
	return s.bg_color if s else Color.WHITE

func progress() -> float:
	return elapsed / duration

func _process(delta: float) -> void:
	_follow()
	if finished:
		return
	if watch_movement and _owner_position().distance_to(_origin) > move_tolerance:
		interrupt("moved")
		return
	elapsed = minf(elapsed + delta, duration)
	_update_bar()
	if elapsed >= duration and auto_complete:
		_finish(true, "")

## Confirmación del servidor (modo auto_complete = false).
func server_finished(ok: bool, reason: String) -> void:
	if finished:
		return
	if ok:
		elapsed = duration
		_update_bar()
	_finish(ok, reason)

func interrupt(reason := "interrupted") -> void:
	if not finished:
		_finish(false, reason)

func _finish(ok: bool, reason: String) -> void:
	finished = true
	if not ok:
		_set_color(COLOR_FAILED)
	label.text = action_label.trim_suffix("...") + (" ✓" if ok else " ✗")
	if ok:
		completed.emit()
	else:
		interrupted.emit(reason)
	# El CanvasLayer no hereda modulate: se desvanece el ancla.
	var tween := create_tween()
	tween.tween_interval(0.6)
	tween.tween_property(anchor, "modulate:a", 0.0, 0.3)
	tween.tween_callback(queue_free)

## Coloca la barra centrada sobre el punto de anclaje, en coordenadas del mundo.
func _follow() -> void:
	anchor.position = global_position - Vector2(anchor.size.x / 2.0, anchor.size.y)

func _update_bar() -> void:
	progress_bar.value = progress() * 100.0

func _set_color(c: Color) -> void:
	progress_bar.add_theme_stylebox_override("fill", UiPalette.flat(c, Color.TRANSPARENT, 0, 3, 0))

func _owner_position() -> Vector2:
	var p := get_parent()
	return p.global_position if p is Node2D else Vector2.ZERO
