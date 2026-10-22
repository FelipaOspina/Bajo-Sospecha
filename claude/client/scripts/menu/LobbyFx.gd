extends RefCounted
## Piezas animadas de la interfaz de la sala de espera (todo dibujado, sin imágenes ni
## emojis): brillo que barre el botón grande, radar de búsqueda, anillo de cuenta atrás,
## barra de plazas por segmentos, punto de estado que late, y las ayudas de "juice"
## (rebote al pasar el ratón o pulsar) y de entrada (fundido + deslizamiento).
## Se usa con preload: const Fx := preload("res://scripts/menu/LobbyFx.gd").

const GlassBox := preload("res://scripts/ui/GlassBox.gd")

## Rebote suave al pasar por encima y al pulsar (escala desde el centro).
static func juice(c: Control, hover := 1.035, press := 0.965) -> void:
	var state := {"over": false, "down": false, "tw": null}
	var go := func() -> void:
		if not is_instance_valid(c) or not c.is_inside_tree():
			return
		c.pivot_offset = c.size / 2.0
		var target := press if state["down"] else (hover if state["over"] else 1.0)
		if c is BaseButton and (c as BaseButton).disabled:
			target = 1.0
		if state["tw"] and (state["tw"] as Tween).is_valid():
			(state["tw"] as Tween).kill()
		var tw := c.create_tween().set_trans(Tween.TRANS_BACK if target > 1.0 else Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(c, "scale", Vector2.ONE * target, 0.16 if target != press else 0.07)
		state["tw"] = tw
	c.mouse_entered.connect(func() -> void:
		state["over"] = true
		go.call())
	c.mouse_exited.connect(func() -> void:
		state["over"] = false
		state["down"] = false
		go.call())
	if c is BaseButton:
		(c as BaseButton).button_down.connect(func() -> void:
			state["down"] = true
			go.call())
		(c as BaseButton).button_up.connect(func() -> void:
			state["down"] = false
			go.call())
	c.resized.connect(func() -> void: c.pivot_offset = c.size / 2.0)

## Entrada: aparece con un fundido y se desliza desde offset (px) hasta su sitio.
## Mueve los offsets del control anclado (no su posición), así que un cambio de tamaño
## de la ventana a mitad de la animación no lo deja descolocado.
static func enter(c: Control, offset: Vector2, delay := 0.0, duration := 0.45) -> void:
	if not is_instance_valid(c):
		return
	if c.has_meta("fx_enter"):
		var old: Tween = c.get_meta("fx_enter")
		if old and old.is_valid():
			old.custom_step(100.0)
			old.kill()
	var base := Vector4(c.offset_left, c.offset_top, c.offset_right, c.offset_bottom)
	if c.has_meta("fx_base"):
		base = c.get_meta("fx_base")
	c.set_meta("fx_base", base)
	var apply := func(k: float) -> void:
		if is_instance_valid(c):
			c.offset_left = base.x + offset.x * k
			c.offset_right = base.z + offset.x * k
			c.offset_top = base.y + offset.y * k
			c.offset_bottom = base.w + offset.y * k
	apply.call(1.0)
	c.modulate.a = 0.0
	var tw := c.create_tween().set_parallel(true)
	tw.tween_property(c, "modulate:a", 1.0, duration * 0.8).set_delay(delay)
	tw.tween_method(apply, 1.0, 0.0, duration).set_delay(delay).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	c.set_meta("fx_enter", tw)

## Brillo diagonal que cruza el botón cada pocos segundos (recortado a sus esquinas).
class Shine extends Control:
	var radius := 16.0
	var period := 3.6
	var strength := 0.45
	var inset := Vector2(0, 0)
	var _t := 0.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_preset(Control.PRESET_FULL_RECT)

	func _process(delta: float) -> void:
		if is_visible_in_tree():
			_t += delta
			queue_redraw()

	func _draw() -> void:
		var k := fmod(_t, period) / 0.9   # la pasada dura 0.9 s, el resto espera
		if k > 1.0:
			return
		var r := Rect2(inset, size - inset * 2.0)
		var shape := GlassBox.rounded(r, radius)
		var w := r.size.y * 0.55
		var x := lerpf(-w * 2.0, r.size.x + w, k * k * (3.0 - 2.0 * k))
		var slant := r.size.y * 0.6
		for band in [[w, strength * 0.35], [w * 0.45, strength]]:
			var bw: float = band[0]
			var poly := PackedVector2Array([Vector2(x + slant, r.position.y), Vector2(x + slant + bw, r.position.y),
				Vector2(x + bw, r.end.y), Vector2(x, r.end.y)])
			for piece in Geometry2D.intersect_polygons(poly, shape):
				draw_colored_polygon(piece, Color(1, 1, 1, band[1]))

## Radar de búsqueda: ondas que salen del centro y un barrido que gira.
class Radar extends Control:
	var color := Color("#00E5FF")
	var _t := 0.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(delta: float) -> void:
		if is_visible_in_tree():
			_t += delta
			queue_redraw()

	func _draw() -> void:
		var c := size / 2.0
		var r := minf(size.x, size.y) / 2.0 - 1.0
		draw_circle(c, r, Color(color, 0.08))
		draw_arc(c, r, 0, TAU, 48, Color(color, 0.35), 1.2, true)
		draw_arc(c, r * 0.62, 0, TAU, 40, Color(color, 0.18), 1.0, true)
		draw_line(c - Vector2(r, 0), c + Vector2(r, 0), Color(color, 0.12), 1.0)
		draw_line(c - Vector2(0, r), c + Vector2(0, r), Color(color, 0.12), 1.0)
		for i in 2:
			var k := fmod(_t * 0.7 + i * 0.5, 1.0)
			draw_arc(c, r * k, 0, TAU, 40, Color(color, (1.0 - k) * 0.6), 1.6, true)
		# Barrido: cuña con degradado detrás de la línea.
		var a := _t * 2.6
		for j in 10:
			var a0 := a - 0.09 * (j + 1)
			var a1 := a - 0.09 * j
			draw_colored_polygon(PackedVector2Array([c, c + Vector2(cos(a0), sin(a0)) * r, c + Vector2(cos(a1), sin(a1)) * r]),
				Color(color, 0.32 * (1.0 - j / 10.0)))
		draw_line(c, c + Vector2(cos(a), sin(a)) * r, Color(color, 0.95), 1.6, true)
		# Puntitos "encontrados" que parpadean.
		for b in [[0.6, 0.55], [2.4, 0.8], [4.1, 0.38]]:
			var blink := 0.5 + 0.5 * sin(_t * 3.0 + b[0] * 2.0)
			draw_circle(c + Vector2(cos(b[0]), sin(b[0])) * r * b[1], 2.2, Color(color, 0.35 + 0.65 * blink))
		draw_circle(c, 2.6, color)

## Anillo de cuenta atrás (progress 0..1 = lo que queda) con el número en el centro.
class Ring extends Control:
	var progress := 1.0:
		set(v):
			progress = clampf(v, 0.0, 1.0)
			queue_redraw()
	var text := "":
		set(v):
			text = v
			queue_redraw()
	var color := Color("#E5A93C")
	var thickness := 3.0
	var spin := false
	var _t := 0.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(delta: float) -> void:
		if is_visible_in_tree():
			_t += delta
			queue_redraw()

	func _draw() -> void:
		var c := size / 2.0
		var r := minf(size.x, size.y) / 2.0 - thickness
		draw_circle(c, r + thickness, Color(0, 0, 0, 0.35))
		draw_arc(c, r, 0, TAU, 48, Color(color, 0.18), thickness, true)
		if spin:
			var a := _t * 4.0
			draw_arc(c, r, a, a + 1.6, 24, color, thickness, true)
		elif progress > 0.0:
			draw_arc(c, r, -PI / 2.0, -PI / 2.0 + TAU * progress, 48, color, thickness, true)
			var tip := -PI / 2.0 + TAU * progress
			draw_circle(c + Vector2(cos(tip), sin(tip)) * r, thickness * 0.9 + 0.6 * sin(_t * 6.0), color.lightened(0.4))
		if text != "":
			var font := UiPalette.heading_font()
			var fs := int(r * 0.95)
			var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			draw_string(font, c + Vector2(-w / 2.0, fs * 0.36), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)

## Barra de plazas por segmentos: ocupadas (ámbar) y libres (huecos).
class SlotBar extends Control:
	var total := 12:
		set(v):
			total = maxi(v, 1)
			queue_redraw()
	var filled := 0:
		set(v):
			filled = v
			queue_redraw()
	var color := Color("#E5A93C")
	var gap := 3.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(60, 6)

	func _draw() -> void:
		var w := (size.x - gap * (total - 1)) / total
		for i in total:
			var r := Rect2(i * (w + gap), 0, w, size.y)
			var on := i < filled
			var sb := StyleBoxFlat.new()
			sb.set_corner_radius_all(int(size.y / 2.0))
			sb.bg_color = color if on else Color(1, 1, 1, 0.10)
			if on:
				sb.shadow_color = Color(color, 0.45)
				sb.shadow_size = 3
			draw_style_box(sb, r)

## Hueco libre en la lista: círculo discontinuo que gira despacio con un "+".
class Ghost extends Control:
	var color := Color(1, 1, 1, 0.28)
	var _t := 0.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(delta: float) -> void:
		if is_visible_in_tree():
			_t += delta
			queue_redraw()

	func _draw() -> void:
		var c := size / 2.0
		var r := minf(size.x, size.y) / 2.0 - 1.5
		var n := 12
		for i in n:
			var a := TAU * i / n + _t * 0.4
			draw_arc(c, r, a, a + TAU / n * 0.55, 6, color, 1.4, true)
		draw_line(c - Vector2(4, 0), c + Vector2(4, 0), color, 1.4, true)
		draw_line(c - Vector2(0, 4), c + Vector2(0, 4), color, 1.4, true)

## Punto de estado con un halo que late.
class PulseDot extends Control:
	var color := Color("#4ADE80"):
		set(v):
			color = v
			queue_redraw()
	var pulse := true
	var _t := 0.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(10, 10)

	func _process(delta: float) -> void:
		if pulse and is_visible_in_tree():
			_t += delta
			queue_redraw()

	func _draw() -> void:
		var c := size / 2.0
		var r := minf(size.x, size.y) / 2.0
		if pulse:
			var k := fmod(_t * 0.9, 1.0)
			draw_circle(c, r * (0.6 + k * 0.9), Color(color, 0.45 * (1.0 - k)))
		draw_circle(c, r * 0.55, color)
