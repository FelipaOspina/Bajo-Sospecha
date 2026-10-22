class_name SprintButton
extends Control
## Botón circular de carrera/sprint con icono de zapatilla (esquina inferior derecha)
## Replica fielmente el botón de acción de la imagen de referencia

signal sprint_pressed(active: bool)

const RADIUS := 52.0
var _is_pressed := false
var _scale_anim := 1.0

func _ready() -> void:
	custom_minimum_size = Vector2(RADIUS * 2 + 10, RADIUS * 2 + 10)
	mouse_filter = Control.MOUSE_FILTER_PASS

func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			_set_pressed(true)
		else:
			_set_pressed(false)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_set_pressed(true)
		else:
			_set_pressed(false)

func _set_pressed(pressed: bool) -> void:
	_is_pressed = pressed
	_scale_anim = 0.92 if pressed else 1.0
	sprint_pressed.emit(pressed)
	# Si Abilities tiene acelerón disponible, lo activa
	if pressed:
		Abilities.trigger_active()
	queue_redraw()

func _draw() -> void:
	var center := size / 2.0
	var r := RADIUS * _scale_anim

	# 1. Resplandor / sombra exterior
	draw_circle(center + Vector2(0, 4), r + 2, Color(0, 0, 0, 0.4))

	# 2. Base circular azul acero / navy translúcida
	var base_color := Color("#2563EB", 0.9) if _is_pressed else Color("#1E293B", 0.85)
	draw_circle(center, r, base_color)

	# 3. Anillos concéntricos de cristal
	draw_arc(center, r, 0.0, TAU, 64, Color(1, 1, 1, 0.45), 2.2, true)
	draw_arc(center, r - 4, 0.0, TAU, 64, Color(1, 1, 1, 0.15), 1.2, true)

	# 4. ICONO DE ZAPATILLA DEPORTIVA (Sneaker) estilizada en blanco y cian
	var shoe_center := center + Vector2(-2, 2)
	_draw_sneaker(shoe_center, _scale_anim)

func _draw_sneaker(c: Vector2, s: float) -> void:
	# Silueta y suela de zapatilla deportiva inclinada hacia arriba-derecha
	var angle := -0.32
	var transform_mat := Transform2D().rotated(angle)

	# Puntos locales de la zapatilla (origen en el centro)
	var sole := PackedVector2Array([
		c + (transform_mat * (Vector2(-24, 12) * s)),
		c + (transform_mat * (Vector2(24, 10) * s)),
		c + (transform_mat * (Vector2(26, 17) * s)),
		c + (transform_mat * (Vector2(-22, 18) * s))
	])
	# Suela blanca
	draw_colored_polygon(sole, Color.WHITE)

	# Cuerpo de la zapatilla (azul cian claro y blanco)
	var upper := PackedVector2Array([
		c + (transform_mat * (Vector2(-22, 12) * s)),
		c + (transform_mat * (Vector2(-18, -6) * s)),
		c + (transform_mat * (Vector2(-8, -12) * s)),
		c + (transform_mat * (Vector2(2, -4) * s)),
		c + (transform_mat * (Vector2(16, 2) * s)),
		c + (transform_mat * (Vector2(24, 10) * s))
	])
	draw_colored_polygon(upper, Color("#38BDF8"))
	draw_polyline(upper, Color.WHITE, 2.0 * s)

	# Franja blanca deportiva y puntera
	var toe_cap := PackedVector2Array([
		c + (transform_mat * (Vector2(14, 3) * s)),
		c + (transform_mat * (Vector2(24, 10) * s)),
		c + (transform_mat * (Vector2(18, 12) * s))
	])
	draw_colored_polygon(toe_cap, Color.WHITE)

	# Cordones blancos
	for i in 3:
		var lx := -8.0 + i * 6.0
		var ly := -6.0 + i * 3.0
		draw_line(
			c + (transform_mat * (Vector2(lx, ly) * s)),
			c + (transform_mat * (Vector2(lx + 4, ly - 3) * s)),
			Color.WHITE, 2.0 * s
		)
