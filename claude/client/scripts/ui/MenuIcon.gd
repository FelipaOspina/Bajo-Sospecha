@tool
class_name MenuIcon
extends Control
## Iconos vectoriales de la interfaz (sin imágenes): se dibujan en una caja de 24×24
## que se escala al tamaño del control. Nombres: users, user, bag, clipboard, ticket,
## cart, chip, gear, mail, coin, diamond, plus, crown, copy, share, play, sliders, chat,
## wifi, lock, check, chevron, search, star, door.

@export var icon := "users":
	set(value):
		icon = value
		queue_redraw()
@export var color := Color("#E2E8F0"):
	set(value):
		color = value
		queue_redraw()
## Para wifi: barras encendidas (0-3).
@export var level := 3:
	set(value):
		level = value
		queue_redraw()

var _k := 1.0
var _o := Vector2.ZERO

static func make(icon_name: String, tint: Color, px := 20.0) -> MenuIcon:
	var m := MenuIcon.new()
	m.icon = icon_name
	m.color = tint
	m.custom_minimum_size = Vector2(px, px)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return m

func _draw() -> void:
	_k = minf(size.x, size.y) / 24.0
	_o = (size - Vector2(24, 24) * _k) / 2.0
	var w := maxf(1.5, 2.0 * _k)
	var c := color
	match icon:
		"users":
			_circle(9, 8, 3.6, c)
			_poly([[2.5, 20], [3.5, 15], [9, 13], [14.5, 15], [15.5, 20]], c)
			_circle(16.5, 8.5, 3, Color(c, 0.7))
			_poly([[16, 13.2], [20.5, 14.5], [21.5, 19], [17.2, 19], [16.5, 15]], Color(c, 0.7))
		"user":
			_circle(12, 8, 4.2, c)
			_poly([[4.5, 21], [5.5, 15.5], [12, 13.2], [18.5, 15.5], [19.5, 21]], c)
		"bag":
			_rect(3, 8, 18, 12, c, true, 2.0)
			_line_path([[9, 8], [9, 5], [15, 5], [15, 8]], Color(c, 1), w)
			_rect(3, 12.5, 18, 1.6, Color(0, 0, 0, 0.35), true)
		"clipboard":
			_rect(5, 4, 14, 18, c, false, 2.0, w)
			_rect(9, 2.5, 6, 3.5, c, true, 1.0)
			for y in [10.0, 14.0, 18.0]:
				_line(8, y, 16, y, c, w * 0.8)
		"ticket":
			_poly([[3, 6], [21, 6], [21, 10], [19.5, 12], [21, 14], [21, 18], [3, 18], [3, 14], [4.5, 12], [3, 10]], c)
			for y in [7.5, 10.5, 13.5, 16.5]:
				_line(15, y, 15, y + 1.5, Color(0, 0, 0, 0.45), w * 0.7)
		"cart":
			_line_path([[2, 4], [5, 4], [7.5, 15], [18.5, 15], [20.5, 7.5], [6, 7.5]], c, w)
			_circle(9, 19, 1.8, c)
			_circle(17, 19, 1.8, c)
		"chip":
			_rect(6, 6, 12, 12, c, false, 1.5, w)
			_rect(9.5, 9.5, 5, 5, c, true, 0.5)
			for i in [8.5, 12.0, 15.5]:
				_line(i, 2.5, i, 5.5, c, w * 0.7)
				_line(i, 18.5, i, 21.5, c, w * 0.7)
				_line(2.5, i, 5.5, i, c, w * 0.7)
				_line(18.5, i, 21.5, i, c, w * 0.7)
		"gear":
			for i in 8:
				var a := TAU * i / 8.0
				var d := Vector2(cos(a), sin(a))
				draw_line(_p(12 + d.x * 6, 12 + d.y * 6), _p(12 + d.x * 10, 12 + d.y * 10), c, 3.4 * _k)
			_circle(12, 12, 7, c)
			_circle(12, 12, 3, Color(0.04, 0.06, 0.1, 1))
		"mail":
			_rect(3, 6, 18, 13, c, true, 1.5)
			_line_path([[3.8, 7], [12, 13.5], [20.2, 7]], Color(0.04, 0.06, 0.1, 0.9), w)
		"coin":
			_circle(12, 12, 9.5, Color("#F2B529"))
			_circle(12, 12, 9.5, Color("#B87A12"), false, w * 0.6)
			_circle(12, 12, 6.3, Color("#FFD866"))
			_rect(10.6, 8, 2.8, 8, Color("#B87A12"), true, 0.8)
		"diamond":
			_poly([[6, 4.5], [18, 4.5], [22, 9.5], [12, 21], [2, 9.5]], Color("#38BDF8"))
			_poly([[6, 4.5], [18, 4.5], [22, 9.5], [2, 9.5]], Color("#7DD3FC"))
			_poly([[8.5, 9.5], [15.5, 9.5], [12, 21]], Color("#0EA5E9"))
		"plus":
			_line(12, 5, 12, 19, c, w * 1.3)
			_line(5, 12, 19, 12, c, w * 1.3)
		"crown":
			_poly([[3, 8], [8, 12], [12, 4.5], [16, 12], [21, 8], [19, 18], [5, 18]], Color("#F2B529"))
			_rect(5, 18, 14, 2.5, Color("#C98A17"), true, 0.5)
			_circle(12, 4.5, 1.4, Color("#FFE08A"))
		"copy":
			_rect(8, 8, 12, 13, c, false, 2.0, w)
			_line_path([[5, 16], [4, 16], [4, 3], [16, 3], [16, 5]], c, w)
		"share":
			_line_path([[9, 6], [5, 6], [5, 19], [18, 19], [18, 15]], c, w)
			_line(10, 14, 19.5, 4.5, c, w)
			_line_path([[13.5, 4.5], [19.5, 4.5], [19.5, 10.5]], c, w)
		"play":
			_poly([[7, 4], [20, 12], [7, 20]], c)
		"sliders":
			for row in [[6.0, 15.0], [12.0, 8.0], [18.0, 13.0]]:
				_line(3, row[0], 21, row[0], c, w * 0.8)
				_circle(row[1], row[0], 2.6, c)
		"chat":
			_rect(3, 4, 18, 13, c, true, 4.0)
			_poly([[7, 16], [12, 16], [6.5, 21]], c)
			for x in [8.0, 12.0, 16.0]:
				_circle(x, 10.5, 1.3, Color(0.04, 0.06, 0.1, 0.9))
		"wifi":
			_circle(12, 19, 1.8, c if level >= 0 else Color(c, 0.25))
			for i in 3:
				var r := 5.0 + i * 4.5
				var on := level > i
				draw_arc(_p(12, 19.5), r * _k, -PI * 0.78, -PI * 0.22, 16, c if on else Color(c, 0.25), w)
		"lock":
			_rect(5, 10.5, 14, 10.5, c, true, 2.0)
			draw_arc(_p(12, 10.5), 4.5 * _k, PI, TAU, 16, c, w * 1.1)
			_circle(12, 15, 1.6, Color(0.04, 0.06, 0.1, 0.9))
		"check":
			_line_path([[4.5, 12.5], [10, 18], [19.5, 6.5]], c, w * 1.3)
		"chevron":
			_line_path([[9, 5], [16, 12], [9, 19]], c, w * 1.1)
		"search":
			_circle(10, 10, 6, c, false, w)
			_line(14.5, 14.5, 20.5, 20.5, c, w * 1.4)
		"star":
			var pts: Array = []
			for i in 10:
				var a := -PI / 2 + TAU * i / 10.0
				var r := 10.0 if i % 2 == 0 else 4.3
				pts.append([12 + cos(a) * r, 12.5 + sin(a) * r])
			_poly(pts, c)
		"door":
			_line_path([[13, 4], [5, 4], [5, 20], [13, 20]], c, w)
			_line(10, 12, 20, 12, c, w)
			_line_path([[16.5, 8.5], [20, 12], [16.5, 15.5]], c, w)

func _p(x: float, y: float) -> Vector2:
	return _o + Vector2(x, y) * _k

func _circle(x: float, y: float, r: float, c: Color, filled := true, width := 2.0) -> void:
	if filled:
		draw_circle(_p(x, y), r * _k, c)
	else:
		draw_arc(_p(x, y), r * _k, 0, TAU, 32, c, width)

func _line(x1: float, y1: float, x2: float, y2: float, c: Color, width: float) -> void:
	draw_line(_p(x1, y1), _p(x2, y2), c, width, true)

func _line_path(points: Array, c: Color, width: float) -> void:
	var pts := PackedVector2Array()
	for q in points:
		pts.append(_p(q[0], q[1]))
	draw_polyline(pts, c, width, true)

func _poly(points: Array, c: Color) -> void:
	var pts := PackedVector2Array()
	for q in points:
		pts.append(_p(q[0], q[1]))
	draw_colored_polygon(pts, c)

func _rect(x: float, y: float, w: float, h: float, c: Color, filled := true, radius := 0.0, width := 2.0) -> void:
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(int(radius * _k))
	sb.anti_aliasing = true
	if filled:
		sb.bg_color = c
	else:
		sb.bg_color = Color.TRANSPARENT
		sb.border_color = c
		sb.set_border_width_all(maxi(1, int(round(width))))
	draw_style_box(sb, Rect2(_p(x, y), Vector2(w, h) * _k))
