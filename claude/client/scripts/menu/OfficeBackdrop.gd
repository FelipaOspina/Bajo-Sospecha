class_name OfficeBackdrop
extends Control
## Fondo del menú: oficina de detectives de noche, dibujada con código (sin imágenes):
## ventanal con la ciudad, tablero de corcho "CASOS" con hilo rojo, lista de tipos de
## caso, lema en la pared, lámparas cálidas y suelo de madera. Se diseña sobre un
## lienzo virtual de 1280×720 que se escala para cubrir la pantalla.
## dim > 0 lo oscurece (para las pestañas que no son la sala).

const VIRTUAL := Vector2(1280, 720)
const WALL_TOP := Color("#0F1528")
const WALL_BOTTOM := Color("#1D2541")
const FLOOR_NEAR := Color("#120E0C")
const FLOOR_FAR := Color("#2C2119")
const NEON := Color("#5EE7FF")
const WARM := Color("#FFB45E")
## Línea entre pared y suelo (en el lienzo virtual).
const HORIZON := 470.0

@export_range(0.0, 1.0) var dim := 0.0:
	set(value):
		dim = value
		queue_redraw()

var _buildings: Array = []     # [{rect, color, windows: [Rect2]}]
var _cork_notes: Array = []    # [{rect, color, rotation, photo}]
var _glow_tex: GradientTexture2D
var _vignette_tex: GradientTexture2D

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_glow_tex = _radial(Color(1, 1, 1, 1), Color(1, 1, 1, 0))
	_vignette_tex = _radial(Color(0, 0, 0, 0), Color(0, 0, 0, 0.75), 0.45)
	_generate()
	resized.connect(queue_redraw)

func _generate() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1914
	var window := _window_rect()
	for layer in 2:
		var x := window.position.x - 10.0
		while x < window.end.x + 10.0:
			var w := rng.randf_range(16, 38)
			var h := rng.randf_range(50, 120) if layer == 0 else rng.randf_range(30, 175)
			var r := Rect2(x, window.end.y - h, w, h)
			var windows: Array = []
			if layer == 1:
				var wy := r.position.y + 6.0
				while wy < r.end.y - 8.0:
					var wx := r.position.x + 4.0
					while wx < r.end.x - 5.0:
						if rng.randf() < 0.32:
							windows.append(Rect2(wx, wy, 3, 4))
						wx += 7.0
					wy += 9.0
			_buildings.append({"rect": r, "layer": layer, "windows": windows})
			x += w + (rng.randf_range(2, 10) if layer == 1 else rng.randf_range(-4, 6))
	for i in 9:
		var photo := rng.randf() < 0.45
		var size_v := Vector2(rng.randf_range(30, 46), rng.randf_range(26, 40)) if photo else Vector2(rng.randf_range(30, 44), rng.randf_range(24, 34))
		_cork_notes.append({
			"rect": Rect2(Vector2(246 + (i % 3) * 62 + rng.randf_range(-4, 6), 276 + (i / 3) * 38 + rng.randf_range(-3, 4)), size_v * 0.85),
			"rotation": rng.randf_range(-0.12, 0.12),
			"photo": photo,
			"color": [Color("#F1E3A0"), Color("#E9E5DA"), Color("#F5C2A8")][rng.randi() % 3],
		})

func _window_rect() -> Rect2:
	return Rect2(842, 204, 178, 210)

func _draw() -> void:
	var k := maxf(size.x / VIRTUAL.x, size.y / VIRTUAL.y)
	var offset := (size - VIRTUAL * k) / 2.0
	draw_rect(Rect2(Vector2.ZERO, size), WALL_TOP)
	draw_set_transform(offset, 0.0, Vector2(k, k))
	_draw_room()
	draw_set_transform(Vector2.ZERO)
	draw_texture_rect(_vignette_tex, Rect2(Vector2.ZERO, size), false)
	if dim > 0.0:
		draw_rect(Rect2(Vector2.ZERO, size), Color(UiPalette.NAVY, dim))

func _draw_room() -> void:
	# Pared y suelo.
	_gradient_rect(Rect2(0, 0, 1280, HORIZON), WALL_TOP, WALL_BOTTOM)
	for x in range(80, 1280, 160):
		draw_line(Vector2(x, HORIZON - 110), Vector2(x, HORIZON - 5), Color(1, 1, 1, 0.025), 2)
	draw_rect(Rect2(0, HORIZON - 114, 1280, 3), Color(1, 1, 1, 0.03))
	_gradient_rect(Rect2(0, HORIZON, 1280, 720 - HORIZON), FLOOR_FAR, FLOOR_NEAR)
	draw_rect(Rect2(0, HORIZON - 8, 1280, 9), Color("#0A0D17"))
	var vanish := Vector2(640, 200)
	for x in range(-600, 1900, 95):
		var bottom := Vector2(x, 720)
		var top := bottom.lerp(vanish, (720.0 - HORIZON - 1.0) / (720.0 - vanish.y))
		draw_line(top, bottom, Color(0, 0, 0, 0.22), 2)
	var y := HORIZON + 7.0
	var step := 10.0
	while y < 720:
		draw_line(Vector2(0, y), Vector2(1280, y), Color(0, 0, 0, 0.12), 1)
		step *= 1.32
		y += step

	_draw_window()
	_draw_corkboard()
	_draw_checklist()
	_draw_slogan()
	_draw_lamps()
	_draw_plants()

func _draw_window() -> void:
	var r := _window_rect()
	# Luz de la ciudad que entra por el ventanal y cae en el suelo.
	draw_colored_polygon(PackedVector2Array([Vector2(r.position.x + 10, r.end.y + 12), Vector2(r.end.x - 10, r.end.y + 12),
		Vector2(r.end.x + 90, 720), Vector2(r.position.x - 120, 720)]), Color(0.55, 0.45, 0.95, 0.045))
	draw_rect(r.grow(12), Color("#070A12"))
	_gradient_rect(Rect2(r.position, Vector2(r.size.x, r.size.y * 0.55)), Color("#120E33"), Color("#3A2A66"))
	_gradient_rect(Rect2(r.position + Vector2(0, r.size.y * 0.55), Vector2(r.size.x, r.size.y * 0.45)), Color("#3A2A66"), Color("#B8607A"))
	draw_circle(r.position + Vector2(52, 40), 11, Color("#F6EBC8"))
	draw_circle(r.position + Vector2(57, 37), 10, Color("#1C1640"))
	for b in _buildings:
		var br: Rect2 = b["rect"].intersection(r)
		if br.size.x <= 0:
			continue
		draw_rect(br, Color("#2A2550") if b["layer"] == 0 else Color("#0B0F1D"))
		for wnd in b["windows"]:
			if r.encloses(wnd):
				draw_rect(wnd, Color("#FFD38A", 0.85))
	_glow(r.position + Vector2(r.size.x * 0.5, r.end.y), 160, Color("#D9708A", 0.18))
	# Marco y travesaños.
	for i in range(1, 3):
		var x := r.position.x + r.size.x * i / 3.0
		draw_line(Vector2(x, r.position.y), Vector2(x, r.end.y), Color("#070A12"), 6)
	draw_line(Vector2(r.position.x, r.position.y + 70), Vector2(r.end.x, r.position.y + 70), Color("#070A12"), 5)
	draw_rect(Rect2(r.position.x - 18, r.end.y + 10, r.size.x + 36, 8), Color("#161B2C"))
	draw_colored_polygon(PackedVector2Array([r.position + Vector2(30, 0), r.position + Vector2(70, 0), r.position + Vector2(20, r.size.y), r.position + Vector2(-0, r.size.y)]), Color(1, 1, 1, 0.035))

func _draw_corkboard() -> void:
	var board := Rect2(232, 266, 200, 128)
	_glow(board.get_center() + Vector2(0, -20), 190, Color(WARM, 0.13))
	draw_rect(board.grow(9), Color("#3A2716"))
	draw_rect(board, Color("#7A5533"))
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	for i in 140:
		draw_rect(Rect2(board.position + Vector2(rng.randf() * board.size.x, rng.randf() * board.size.y), Vector2(2, 2)), Color(0, 0, 0, 0.12))
	var pins: Array[Vector2] = []
	for n in _cork_notes:
		var rect: Rect2 = n["rect"]
		draw_set_transform_matrix(_base_transform() * Transform2D(n["rotation"], rect.get_center()))
		var local := Rect2(-rect.size / 2.0, rect.size)
		draw_rect(local.grow(1), Color(0, 0, 0, 0.3))
		if n["photo"]:
			draw_rect(local, Color("#E8E4DA"))
			draw_rect(local.grow(-3), Color("#3B4152"))
			draw_circle(local.get_center() + Vector2(0, -3), 5, Color("#8C93A6"))
			draw_rect(Rect2(local.get_center() + Vector2(-8, 3), Vector2(16, 8)), Color("#8C93A6"))
		else:
			draw_rect(local, n["color"])
			for l in 3:
				draw_line(local.position + Vector2(4, 8 + l * 6), local.position + Vector2(local.size.x - 5, 8 + l * 6), Color(0, 0, 0, 0.25), 1)
		draw_set_transform_matrix(_base_transform())
		pins.append(rect.get_center() + Vector2(0, -rect.size.y / 2.0 + 3))
	for i in range(pins.size() - 1):
		if i % 3 != 2:
			draw_line(pins[i], pins[i + 1], Color("#D23A3A", 0.85), 1.5, true)
	draw_line(pins[1], pins[4], Color("#D23A3A", 0.85), 1.5, true)
	draw_line(pins[4], pins[8], Color("#D23A3A", 0.85), 1.5, true)
	for p in pins:
		draw_circle(p, 3, Color("#E23B3B"))
		draw_circle(p + Vector2(-1, -1), 1, Color(1, 1, 1, 0.6))
	# Neón "CASOS".
	var font := UiPalette.heading_font()
	var pos := Vector2(256, 248)
	for g in [[14, 0.06], [9, 0.10], [5, 0.18]]:
		draw_string_outline(font, pos, "CASOS", HORIZONTAL_ALIGNMENT_LEFT, -1, 40, g[0], Color(NEON, g[1]))
	draw_string(font, pos, "CASOS", HORIZONTAL_ALIGNMENT_LEFT, -1, 40, Color("#CFFAFF"))
	_glow(Vector2(318, 236), 110, Color(NEON, 0.10))

func _draw_checklist() -> void:
	var paper := Rect2(448, 196, 112, 96)
	draw_rect(paper.grow(2), Color(0, 0, 0, 0.35))
	draw_rect(paper, Color("#E4DFD2"))
	var font := UiPalette.body_font()
	var items := ["Investigación", "Secuestro", "Infidelidades", "Robos", "Fraudes", "Otros"]
	for i in items.size():
		var y := paper.position.y + 16 + i * 14
		var box := Rect2(paper.position.x + 8, y - 8, 8, 8)
		draw_rect(box, Color("#2B2B2B"), false, 1.2)
		if i in [0, 1, 4]:
			draw_polyline(PackedVector2Array([box.position + Vector2(1, 4), box.position + Vector2(3, 7), box.position + Vector2(9, -1)]), Color("#C62828"), 2, true)
		draw_string(font, Vector2(box.end.x + 5, y), items[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#2B2B2B"))

func _draw_slogan() -> void:
	var font := UiPalette.heading_font()
	draw_set_transform_matrix(_base_transform() * Transform2D(-0.07, Vector2(612, 224)))
	var lines := ["LA VERDAD", "SIEMPRE", "APARECE"]
	for i in lines.size():
		draw_string(font, Vector2(i * 8, i * 27), lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 25, Color("#DCE3F2", 0.72))
	draw_arc(Vector2(136, 46), 10, 0, TAU, 24, Color("#DCE3F2", 0.72), 3, true)
	draw_line(Vector2(143, 54), Vector2(152, 63), Color("#DCE3F2", 0.72), 4, true)
	draw_set_transform_matrix(_base_transform())

func _draw_lamps() -> void:
	_glow(Vector2(640, 240), 300, Color(WARM, 0.12))
	_glow(Vector2(640, 560), 440, Color(WARM, 0.10))
	_glow(Vector2(930, 320), 190, Color("#9B7BFF", 0.08))

func _draw_plants() -> void:
	for plant in [[Vector2(1032, HORIZON - 30), 0.85], [Vector2(212, HORIZON - 30), 0.85]]:
		var base: Vector2 = plant[0]
		var s: float = plant[1]
		draw_colored_polygon(PackedVector2Array([base + Vector2(-22, 0) * s, base + Vector2(22, 0) * s, base + Vector2(16, 40) * s, base + Vector2(-16, 40) * s]), Color("#2A2F3E"))
		for i in 7:
			var a := -PI / 2 + (i - 3) * 0.38
			var tip := base + Vector2(cos(a), sin(a)) * 70.0 * s
			var mid := base.lerp(tip, 0.5) + Vector2(cos(a + PI / 2), sin(a + PI / 2)) * 9.0 * s
			var mid2 := base.lerp(tip, 0.5) - Vector2(cos(a + PI / 2), sin(a + PI / 2)) * 9.0 * s
			draw_colored_polygon(PackedVector2Array([base, mid, tip, mid2]), Color("#1F4A33") if i % 2 == 0 else Color("#2E6544"))

func _base_transform() -> Transform2D:
	var k := maxf(size.x / VIRTUAL.x, size.y / VIRTUAL.y)
	return Transform2D(0.0, Vector2(k, k), 0.0, (size - VIRTUAL * k) / 2.0)

func _glow(center: Vector2, radius: float, c: Color) -> void:
	draw_texture_rect(_glow_tex, Rect2(center - Vector2(radius, radius), Vector2(radius, radius) * 2.0), false, c)

func _gradient_rect(r: Rect2, top: Color, bottom: Color) -> void:
	draw_polygon(PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]),
		PackedColorArray([top, top, bottom, bottom]))

static func _radial(inner: Color, outer: Color, start := 0.0) -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, inner)
	g.set_color(1, outer)
	g.set_offset(0, start)
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 128
	t.height = 128
	return t
