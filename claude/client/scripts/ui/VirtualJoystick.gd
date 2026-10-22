class_name VirtualJoystick
extends Control
## Joystick virtual translúcido para controles táctiles y ratón (esquina inferior izquierda)
## Replica fielmente el control de la imagen de referencia:
##  - Aro exterior de cristal con 4 flechas de dirección (arriba, abajo, izquierda, derecha)
##  - Pomo central blanco que sigue el arrastre y vuelve al centro con amortiguación
##  - Emula las acciones ui_left, ui_right, ui_up, ui_down para mover al personaje

signal direction_changed(vector: Vector2)

const RADIUS := 70.0
const THUMB_RADIUS := 24.0
const DEADZONE := 0.12

var _touch_id := -1
var _touch_pos := Vector2.ZERO
var _current_vector := Vector2.ZERO
var _is_pressed := false

func _ready() -> void:
	custom_minimum_size = Vector2(RADIUS * 2 + 10, RADIUS * 2 + 10)
	mouse_filter = Control.MOUSE_FILTER_PASS

func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed and _touch_id == -1:
			_touch_id = event.index
			_update_input(event.position)
		elif not event.pressed and event.index == _touch_id:
			_reset_input()

	elif event is InputEventScreenDrag and event.index == _touch_id:
		_update_input(event.position)

	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_is_pressed = true
				_update_input(event.position)
			else:
				_is_pressed = false
				_reset_input()

	elif event is InputEventMouseMotion and _is_pressed:
		_update_input(event.position)

func _update_input(local_pos: Vector2) -> void:
	var center := size / 2.0
	var diff := local_pos - center
	var dist := diff.length()
	if dist > RADIUS:
		diff = diff.normalized() * RADIUS
	_touch_pos = diff

	var raw_vec := diff / RADIUS
	if raw_vec.length() < DEADZONE:
		_current_vector = Vector2.ZERO
	else:
		_current_vector = raw_vec

	_simulate_actions(_current_vector)
	direction_changed.emit(_current_vector)
	queue_redraw()

func _reset_input() -> void:
	_touch_id = -1
	_touch_pos = Vector2.ZERO
	_current_vector = Vector2.ZERO
	_simulate_actions(Vector2.ZERO)
	direction_changed.emit(Vector2.ZERO)
	queue_redraw()

func _simulate_actions(vec: Vector2) -> void:
	_set_action("ui_left", vec.x < -0.3)
	_set_action("ui_right", vec.x > 0.3)
	_set_action("ui_up", vec.y < -0.3)
	_set_action("ui_down", vec.y > 0.3)

func _set_action(action: String, pressed: bool) -> void:
	if pressed:
		if not Input.is_action_pressed(action):
			Input.action_press(action)
	else:
		if Input.is_action_pressed(action):
			Input.action_release(action)

func _draw() -> void:
	var center := size / 2.0

	# 1. Base exterior translúcida de cristal
	draw_circle(center, RADIUS, Color(0.06, 0.10, 0.18, 0.52))
	# Borde suave blanco/cristal
	draw_arc(center, RADIUS, 0.0, TAU, 64, Color(1, 1, 1, 0.32), 2.0, true)
	draw_arc(center, RADIUS - 4, 0.0, TAU, 64, Color(1, 1, 1, 0.10), 1.0, true)

	# 2. Flechas indicadoras de dirección (Arriba, Abajo, Izquierda, Derecha)
	var arrow_dist := RADIUS * 0.72
	var arrow_size := 7.0
	var arrow_col := Color(1, 1, 1, 0.45)

	# Arriba
	_draw_arrow(center + Vector2(0, -arrow_dist), Vector2(0, -arrow_size), arrow_col)
	# Abajo
	_draw_arrow(center + Vector2(0, arrow_dist), Vector2(0, arrow_size), arrow_col)
	# Izquierda
	_draw_arrow(center + Vector2(-arrow_dist, 0), Vector2(-arrow_size, 0), arrow_col)
	# Derecha
	_draw_arrow(center + Vector2(arrow_dist, 0), Vector2(arrow_size, 0), arrow_col)

	# 3. Pomo interior blanco con relieve
	var knob_pos := center + _touch_pos
	# Sombra del pomo
	draw_circle(knob_pos + Vector2(0, 3), THUMB_RADIUS + 2, Color(0, 0, 0, 0.35))
	# Pomo blanco satinado
	draw_circle(knob_pos, THUMB_RADIUS, Color(0.96, 0.97, 1.0, 0.95))
	# Anillo interior tenue
	draw_arc(knob_pos, THUMB_RADIUS * 0.55, 0.0, TAU, 32, Color(0.8, 0.85, 0.95, 0.6), 1.5, true)
	draw_circle(knob_pos, 4.0, Color(0.85, 0.9, 1.0, 0.8))

func _draw_arrow(tip: Vector2, dir: Vector2, color: Color) -> void:
	var side := dir.orthogonal() * 0.6
	var pts := PackedVector2Array([
		tip,
		tip - dir + side,
		tip - dir - side
	])
	draw_colored_polygon(pts, color)
