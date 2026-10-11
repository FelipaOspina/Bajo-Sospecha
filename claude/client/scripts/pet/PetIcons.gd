class_name PetIcons
extends RefCounted
## Iconos de la mascota dibujados con código (sin PNG): la comida de cada especie, el
## agua, corazones y notas para las reacciones. draw(item, icon, centro, tamaño) pinta
## en cualquier CanvasItem; PetIcons.Rect es un Control que muestra uno.

const ICONS := ["meat", "bone", "berries", "fish", "kibble", "honey", "bamboo", "carrot", "grapes", "cricket", "water", "heart", "note", "sparkle"]

static func draw(ci: CanvasItem, icon: String, c: Vector2, s: float, alpha := 1.0) -> void:
	var k := s / 32.0   # se diseñan en una caja de 32
	var a := alpha
	match icon:
		"meat":
			_blob(ci, c + Vector2(-3, -1) * k, Vector2(11, 9) * k, -0.5, Color("#C2453A", a), Color("#E5786A", a))
			_blob(ci, c + Vector2(-4, -2) * k, Vector2(6, 4.5) * k, -0.5, Color("#F2C6B0", a), Color("#FBE3D6", a))
			_bone(ci, c + Vector2(6, 6) * k, c + Vector2(12, 12) * k, 2.6 * k, Color("#F4EBDD", a))
		"bone":
			_bone(ci, c + Vector2(-9, 7) * k, c + Vector2(9, -7) * k, 3.4 * k, Color("#F4EBDD", a))
			_blob(ci, c + Vector2(-1, 1) * k, Vector2(6, 4) * k, -0.66, Color("#C2453A", a), Color("#E5786A", a))
		"berries":
			for p in [Vector2(-6, 3), Vector2(5, 4), Vector2(-1, -5)]:
				_ball(ci, c + p * k, 6.5 * k, Color("#7C3AED", a) if p.y < 0 else Color("#C0264B", a))
			_leaf(ci, c + Vector2(4, -11) * k, 6 * k, 0.6, Color("#3FAE5A", a))
		"fish":
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(8, 0) * k, c + Vector2(15, -7) * k, c + Vector2(15, 7) * k]), Color("#3B82C4", a))
			_blob(ci, c + Vector2(-2, 0) * k, Vector2(11, 7) * k, 0.0, Color("#4F9BE0", a), Color("#A9D4F5", a))
			ci.draw_circle(c + Vector2(-8, -1.5) * k, 1.6 * k, Color("#0F172A", a))
			ci.draw_arc(c + Vector2(-4, 0) * k, 4.0 * k, -0.9, 0.9, 8, Color("#2563A0", a), 1.2 * k, true)
		"kibble":
			_blob(ci, c + Vector2(0, 5) * k, Vector2(14, 6) * k, 0.0, Color("#B91C1C", a), Color("#EF4444", a))
			for p in [Vector2(-6, 0), Vector2(0, -2), Vector2(6, 0), Vector2(-3, -6), Vector2(3, -6)]:
				_ball(ci, c + p * k, 3.6 * k, Color("#9A5B2B", a))
		"honey":
			_blob(ci, c + Vector2(0, 3) * k, Vector2(11, 11) * k, 0.0, Color("#D98E04", a), Color("#FBBF24", a))
			ci.draw_rect(Rect2(c + Vector2(-9, -12) * k, Vector2(18, 6) * k), Color("#9A3412", a))
			_blob(ci, c + Vector2(0, 3) * k, Vector2(5, 3) * k, 0.0, Color("#FDE68A", a * 0.8), Color("#FEF3C7", a * 0.8))
		"bamboo":
			for i in 3:
				var top := c + Vector2(-2 + i * 0.8, 14 - i * 9.5) * k
				_capsule(ci, top, top + Vector2(0.8, -8.0) * k, 3.4 * k, Color("#4CAF50", a))
				ci.draw_line(top + Vector2(-3.4, 0) * k, top + Vector2(3.4, 0) * k, Color("#2E7D32", a), 1.4 * k, true)
			_leaf(ci, c + Vector2(7, -8) * k, 7 * k, 0.4, Color("#66BB6A", a))
			_leaf(ci, c + Vector2(-7, 2) * k, 6 * k, -2.6, Color("#66BB6A", a))
		"carrot":
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-6, -6) * k, c + Vector2(6, -6) * k, c + Vector2(1, 14) * k, c + Vector2(-1, 14) * k]), Color("#F97316", a))
			ci.draw_circle(c + Vector2(0, -6) * k, 6 * k, Color("#F97316", a))
			ci.draw_line(c + Vector2(-3, 0) * k, c + Vector2(1, 0) * k, Color("#C2410C", a), 1.2 * k, true)
			ci.draw_line(c + Vector2(0, 5) * k, c + Vector2(3, 5) * k, Color("#C2410C", a), 1.2 * k, true)
			_leaf(ci, c + Vector2(-3, -14) * k, 6 * k, -1.9, Color("#22A34A", a))
			_leaf(ci, c + Vector2(3, -14) * k, 6 * k, -1.2, Color("#22A34A", a))
		"grapes":
			for p in [Vector2(-6, -4), Vector2(0, -4), Vector2(6, -4), Vector2(-3, 2), Vector2(3, 2), Vector2(0, 8)]:
				_ball(ci, c + p * k, 4.4 * k, Color("#7E3FB5", a))
			ci.draw_line(c + Vector2(0, -9) * k, c + Vector2(2, -14) * k, Color("#7C5A3A", a), 1.6 * k, true)
			_leaf(ci, c + Vector2(6, -12) * k, 5 * k, 0.3, Color("#4CAF50", a))
		"cricket":
			_blob(ci, c + Vector2(0, 2) * k, Vector2(11, 5.5) * k, 0.0, Color("#4D7C0F", a), Color("#84CC16", a))
			ci.draw_circle(c + Vector2(-10, 0) * k, 4 * k, Color("#3F6212", a))
			ci.draw_line(c + Vector2(4, 2) * k, c + Vector2(10, -8) * k, Color("#3F6212", a), 2.0 * k, true)
			ci.draw_line(c + Vector2(10, -8) * k, c + Vector2(13, 6) * k, Color("#3F6212", a), 1.6 * k, true)
			ci.draw_line(c + Vector2(-12, -2) * k, c + Vector2(-16, -12) * k, Color("#3F6212", a), 1.0 * k, true)
			ci.draw_circle(c + Vector2(-11, -1) * k, 1.0 * k, Color("#0F172A", a))
		"water":
			var pts := PackedVector2Array([c + Vector2(0, -13) * k])
			for i in 21:
				var ang := deg_to_rad(-25.0 + 230.0 * i / 20.0)
				pts.append(c + (Vector2(0, 4) + Vector2(cos(ang), sin(ang)) * 9.0) * k)
			ci.draw_colored_polygon(pts, Color("#38BDF8", a))
			_blob(ci, c + Vector2(-3, 4) * k, Vector2(2.4, 4) * k, 0.3, Color("#E0F7FF", a * 0.85), Color("#FFFFFF", a * 0.85))
		"heart":
			heart(ci, c, s * 0.5, Color("#FF5C8A", a))
		"note":
			ci.draw_line(c + Vector2(4, 8) * k, c + Vector2(4, -12) * k, Color("#FDE68A", a), 2.4 * k, true)
			ci.draw_line(c + Vector2(4, -12) * k, c + Vector2(12, -8) * k, Color("#FDE68A", a), 2.4 * k, true)
			_blob(ci, c + Vector2(-1, 9) * k, Vector2(6, 4.5) * k, -0.4, Color("#FDE68A", a), Color("#FFF7D1", a))
		"sparkle":
			var star := PackedVector2Array()
			for i in 8:
				var ang := TAU * i / 8.0 - PI / 2.0
				star.append(c + Vector2(cos(ang), sin(ang)) * (14.0 if i % 2 == 0 else 4.0) * k)
			ci.draw_colored_polygon(star, Color("#FFF3B0", a))

## Corazón relleno de radio r (dos círculos y un triángulo).
static func heart(ci: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	ci.draw_circle(c + Vector2(-r * 0.5, -r * 0.2), r * 0.55, col)
	ci.draw_circle(c + Vector2(r * 0.5, -r * 0.2), r * 0.55, col)
	ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 1.02, 0.05 * r), c + Vector2(r * 1.02, 0.05 * r), c + Vector2(0, r * 1.05)]), col)
	ci.draw_circle(c + Vector2(-r * 0.62, -r * 0.36), r * 0.16, Color(1, 1, 1, col.a * 0.7))

static func _blob(ci: CanvasItem, c: Vector2, r: Vector2, ang: float, base: Color, light: Color) -> void:
	ci.draw_set_transform(c, ang, Vector2(1.0, r.y / maxf(r.x, 0.001)))
	ci.draw_circle(Vector2.ZERO, r.x, base)
	ci.draw_circle(Vector2(-r.x * 0.22, -r.x * 0.28), r.x * 0.55, light)
	ci.draw_circle(Vector2(-r.x * 0.12, -r.x * 0.16), r.x * 0.62, Color(base, base.a * 0.55))
	ci.draw_set_transform(Vector2.ZERO)

static func _ball(ci: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	ci.draw_circle(c, r, col.darkened(0.15))
	ci.draw_circle(c + Vector2(-r, -r) * 0.15, r * 0.82, col)
	ci.draw_circle(c + Vector2(-r, -r) * 0.38, r * 0.28, Color(1, 1, 1, col.a * 0.55))

static func _bone(ci: CanvasItem, a: Vector2, b: Vector2, w: float, col: Color) -> void:
	ci.draw_line(a, b, col, w * 1.6, true)
	var n := (b - a).normalized().orthogonal() * w * 0.75
	for p in [a, b]:
		ci.draw_circle(p + n, w, col)
		ci.draw_circle(p - n, w, col)

static func _capsule(ci: CanvasItem, a: Vector2, b: Vector2, r: float, col: Color) -> void:
	ci.draw_line(a, b, col, r * 2.0, true)
	ci.draw_circle(a, r, col)
	ci.draw_circle(b, r, col)
	ci.draw_line(a + Vector2(-r * 0.4, 0), b + Vector2(-r * 0.4, 0), Color(1, 1, 1, col.a * 0.35), r * 0.5, true)

static func _leaf(ci: CanvasItem, c: Vector2, len: float, ang: float, col: Color) -> void:
	ci.draw_set_transform(c, ang, Vector2.ONE)
	ci.draw_colored_polygon(PackedVector2Array([Vector2(-len, 0), Vector2(-len * 0.2, -len * 0.42), Vector2(len, 0), Vector2(-len * 0.2, len * 0.42)]), col)
	ci.draw_set_transform(Vector2.ZERO)

## Control que muestra un icono centrado.
class Rect extends Control:
	var icon := "heart":
		set(value):
			icon = value
			queue_redraw()

	func _init(icon_name := "heart", side := 28.0) -> void:
		icon = icon_name
		custom_minimum_size = Vector2(side, side)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		PetIcons.draw(self, icon, size / 2.0, minf(size.x, size.y) * 0.92)
