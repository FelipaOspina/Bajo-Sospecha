extends Control
## Ilustración vectorial de una lección de la Ruta del Detective (sin imágenes): una
## escena pequeña dibujada con primitivas sobre un lienzo de 360×170 que se escala al
## tamaño del control. art = id de la lección (office, sight, evidence, backup, silence,
## body, meeting, chat, trial, verdict, ghost, roles, ability, deduction, badge).
## Los animales son siluetas neutras: ninguna ilustración asocia un animal a un rol.

const W := 360.0
const H := 170.0
const INK := Color("#E2E8F0")
const DIM := Color("#64748B")
const AMBER := Color("#E5A93C")
const CYAN := Color("#00E5FF")
const RED := Color("#FF334B")
const GREEN := Color("#4ADE80")
const PURPLE := Color("#A78BFA")
const ANIMALS := [Color("#F59E0B"), Color("#60A5FA"), Color("#F472B6"), Color("#34D399"), Color("#C084FC"), Color("#FB923C")]

@export var art := "office":
	set(value):
		art = value
		queue_redraw()

var t := 0.0
var _k := 1.0
var _o := Vector2.ZERO

static func make(art_id: String, min_size := Vector2(360, 170)) -> Control:
	var c: Control = (load("res://scripts/menu/LessonArt.gd") as GDScript).new()
	c.art = art_id
	c.custom_minimum_size = min_size
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c

func _process(delta: float) -> void:
	t += delta
	if is_visible_in_tree():
		queue_redraw()

# ───── Primitivas en coordenadas del lienzo ─────

func P(x: float, y: float) -> Vector2:
	return _o + Vector2(x, y) * _k

func _rect(x: float, y: float, w: float, h: float, c: Color, filled := true, width := 2.0) -> void:
	draw_rect(Rect2(P(x, y), Vector2(w, h) * _k), c, filled, -1.0 if filled else width * _k)

func _circle(x: float, y: float, r: float, c: Color) -> void:
	draw_circle(P(x, y), r * _k, c)

func _ring(x: float, y: float, r: float, c: Color, width := 2.0) -> void:
	draw_arc(P(x, y), r * _k, 0, TAU, 40, c, width * _k, true)

func _line(x1: float, y1: float, x2: float, y2: float, c: Color, width := 2.0) -> void:
	draw_line(P(x1, y1), P(x2, y2), c, width * _k, true)

func _dashed(x1: float, y1: float, x2: float, y2: float, c: Color, width := 2.0) -> void:
	draw_dashed_line(P(x1, y1), P(x2, y2), c, width * _k, 6.0 * _k, true)

func _text(x: float, y: float, s: String, c: Color, size := 12) -> void:
	draw_string(UiPalette.bold_font(), P(x, y), s, HORIZONTAL_ALIGNMENT_LEFT, -1, int(size * _k), c)

## Animal chibi neutro: cabeza con orejas y ojos, cuerpo.
func _animal(x: float, y: float, c: Color, s := 1.0, down := false) -> void:
	if down:
		draw_set_transform(P(x, y), PI / 2.0, Vector2.ONE)
		var save := _o
		_o = -Vector2(x, y) * _k
		_animal(x, y, c, s)
		_o = save
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		return
	_circle(x, y + 16 * s, 12 * s, c.darkened(0.25))
	_circle(x - 9 * s, y - 12 * s, 6 * s, c)
	_circle(x + 9 * s, y - 12 * s, 6 * s, c)
	_circle(x, y, 13 * s, c)
	_circle(x - 4.5 * s, y - 1 * s, 2.2 * s, Color("#0B0F19"))
	_circle(x + 4.5 * s, y - 1 * s, 2.2 * s, Color("#0B0F19"))

func _doc(x: float, y: float, c := INK, w := 30.0, h := 38.0) -> void:
	_rect(x, y, w, h, Color(c, 0.95))
	for i in 4:
		_line(x + 5, y + 8 + i * 7, x + w - 5 - (8 if i == 3 else 0), y + 8 + i * 7, Color("#475569"), 1.5)

func _laptop(x: float, y: float, screen := CYAN) -> void:
	_rect(x, y, 56, 34, Color("#1E293B"))
	_rect(x + 4, y + 4, 48, 26, Color(screen, 0.35))
	_rect(x - 6, y + 34, 68, 6, Color("#334155"))

func _glow(x: float, y: float, c := AMBER) -> void:
	var pulse := 0.5 + 0.5 * sin(t * 3.0)
	for i in 3:
		_ring(x, y, 16 + i * 8 + pulse * 4, Color(c, 0.45 - i * 0.13), 2.0)

func _bar(x: float, y: float, w: float, frac: float, c := CYAN) -> void:
	_rect(x, y, w, 7, Color(1, 1, 1, 0.12))
	_rect(x, y, w * clampf(frac, 0, 1), 7, c)

func _bubble(x: float, y: float, w: float, c := INK) -> void:
	_rect(x, y, w, 20, Color(c, 0.9))
	draw_colored_polygon(PackedVector2Array([P(x + 8, y + 20), P(x + 18, y + 20), P(x + 8, y + 28)]), Color(c, 0.9))
	for i in 3:
		_circle(x + 12 + i * 10, y + 10, 2.4, Color("#334155"))

func _key(x: float, y: float, label: String) -> void:
	var w := 14.0 + label.length() * 7.0
	_rect(x, y, w, 20, Color("#1E293B"))
	_rect(x, y, w, 20, Color(1, 1, 1, 0.35), false, 1.5)
	_text(x + 6, y + 15, label, INK, 12)

func _floor() -> void:
	_rect(0, 0, W, H, Color("#0F172A"))
	for i in range(1, 9):
		_line(i * 40, 0, i * 40, H, Color(1, 1, 1, 0.035), 1.0)
	for j in range(1, 5):
		_line(0, j * 34, W, j * 34, Color(1, 1, 1, 0.035), 1.0)

func _draw() -> void:
	_k = minf(size.x / W, size.y / H)
	_o = (size - Vector2(W, H) * _k) / 2.0
	_floor()
	match art:
		"office": _draw_office()
		"sight": _draw_sight()
		"evidence": _draw_evidence()
		"backup": _draw_backup()
		"silence": _draw_silence()
		"body": _draw_body()
		"meeting": _draw_meeting()
		"chat": _draw_chat()
		"trial": _draw_trial()
		"verdict": _draw_verdict()
		"ghost": _draw_ghost()
		"roles": _draw_roles()
		"ability": _draw_ability()
		"deduction": _draw_deduction()
		_: _draw_badge()
	_rect(0, 0, W, H, Color(1, 1, 1, 0.10), false, 1.5)

func _draw_office() -> void:
	# Torre de noche con el piso 14 iluminado y una lupa.
	_rect(40, 30, 110, 140, Color("#1E293B"))
	for r in 6:
		for c in 4:
			var lit := r == 2
			_rect(50 + c * 25, 40 + r * 21, 16, 12, Color(AMBER, 0.85) if lit else Color("#334155"))
	_text(158, 82, "14", AMBER, 16)
	for i in 4:
		_animal(210 + i * 34, 120, ANIMALS[i], 0.75)
	_ring(300, 60, 22, INK, 4)
	_line(315, 76, 334, 96, INK, 6)
	_text(196, 40, "¿Quién robó 1,8 M?", INK, 13)

func _draw_sight() -> void:
	# Cono de visión: el muro tapa a uno de los animales.
	var eye := Vector2(70, 110)
	var a := -0.55
	var b := 0.35
	var pts := PackedVector2Array([P(eye.x, eye.y)])
	for i in 13:
		var ang := lerpf(a, b, i / 12.0)
		pts.append(P(eye.x + cos(ang) * 270, eye.y + sin(ang) * 270))
	draw_colored_polygon(pts, Color(AMBER, 0.13))
	_rect(200, 40, 12, 70, Color("#475569"))
	_animal(eye.x, eye.y, ANIMALS[0])
	_animal(160, 90, ANIMALS[1], 0.8)
	_animal(260, 70, Color(ANIMALS[2], 0.25), 0.8)
	_text(232, 40, "?", DIM, 20)
	_ring(318, 132, 20, INK, 2)
	_circle(318, 132, 3, AMBER)
	_text(290, 166, "minimapa", DIM, 10)

func _draw_evidence() -> void:
	_glow(250, 80)
	_doc(235, 61, Color("#FDE68A"))
	_animal(120, 95, ANIMALS[1])
	_dashed(140, 90, 215, 82, Color(INK, 0.5))
	_key(150, 120, "E")
	_rect(30, 28, 70, 26, Color("#1E293B"))
	_text(38, 46, "Recoger", GREEN, 12)
	_rect(296, 120, 28, 24, Color("#1E293B"))
	_ring(310, 120, 7, DIM, 2)
	_text(286, 160, "candado", DIM, 10)

func _draw_backup() -> void:
	_laptop(200, 55)
	_animal(120, 100, ANIMALS[3])
	_bar(90, 140, 70, fmod(t * 0.35, 1.0), CYAN)
	_line(190, 75, 160, 90, Color(CYAN, 0.6), 2)
	_doc(285, 60, Color("#BAE6FD"), 26, 32)
	_text(282, 108, "copia", CYAN, 12)
	_text(60, 34, "¡Quieto!", AMBER, 14)

func _draw_silence() -> void:
	_animal(110, 95, ANIMALS[4])
	_animal(160, 112, ANIMALS[0], 1.0, true)
	for i in 3:
		var a := t * 2.0 + i * TAU / 3.0
		_text(150 + cos(a) * 18, 92 + sin(a) * 8, "*", AMBER, 14)
	_animal(290, 90, ANIMALS[1])
	_dashed(275, 88, 175, 100, Color(RED, 0.55))
	_ring(290, 70, 26, Color(RED, 0.6), 2)
	_text(222, 40, "Testigo", RED, 13)
	_text(40, 40, "Solo con móvil", INK, 13)

func _draw_body() -> void:
	_animal(170, 110, Color("#94A3B8"), 1.0, true)
	_animal(90, 95, ANIMALS[2])
	_rect(230, 60, 96, 34, Color(RED, 0.9))
	_text(242, 82, "REPORTAR", Color.WHITE, 13)
	_key(262, 100, "R")
	_ring(170, 110, 46 + sin(t * 3.0) * 3, Color(RED, 0.4), 2)

func _draw_meeting() -> void:
	_rect(110, 62, 140, 56, Color("#3F2A1E"))
	var seats := [Vector2(95, 60), Vector2(145, 40), Vector2(215, 40), Vector2(265, 60), Vector2(130, 140), Vector2(230, 140)]
	for i in seats.size():
		_animal(seats[i].x, seats[i].y, ANIMALS[i], 0.6)
	_circle(180, 90, 13, RED)
	_ring(180, 90, 18, Color(RED, 0.5 + 0.3 * sin(t * 4.0)), 3)
	_rect(292, 96, 56, 22, Color(AMBER, 0.85))
	_text(300, 112, "Votar", Color("#1A1405"), 12)
	_rect(292, 124, 56, 22, Color("#1E293B"))
	_text(298, 140, "Saltar", INK, 12)

func _draw_chat() -> void:
	_animal(70, 110, ANIMALS[0])
	_animal(290, 110, ANIMALS[3])
	_bubble(40, 50, 120, INK)
	_bubble(190, 30, 130, Color("#BAE6FD"))
	_text(48, 64, "Estaba en Finanzas", Color("#0B0F19"), 10)
	_text(198, 44, "¿Quién te vio?", Color("#0B0F19"), 10)

func _draw_trial() -> void:
	_rect(70, 70, 220, 70, Color("#3F2A1E"))
	_doc(130, 82, Color("#FDE68A"), 28, 34)
	_doc(200, 82, Color("#BAE6FD"), 28, 34)
	_text(250, 64, "máx. 2", AMBER, 12)
	_doc(165, 22, INK, 24, 30)
	_line(177, 55, 177, 75, Color(AMBER, 0.8), 2)
	_animal(40, 105, ANIMALS[1], 0.8)
	_animal(320, 105, ANIMALS[2], 0.8)

func _draw_verdict() -> void:
	for i in 3:
		var on := i == 1
		_rect(40 + i * 100, 50, 84, 40, Color(AMBER, 0.85) if on else Color("#1E293B"))
		_text(50 + i * 100, 75, ["Opción A", "Opción B", "Abstenerse"][i], Color("#1A1405") if on else INK, 11)
	_bar(40, 120, 284, 0.62, AMBER)
	_text(40, 150, "Voto secreto hasta el final", DIM, 12)

func _draw_ghost() -> void:
	var y := 80 + sin(t * 2.0) * 6
	_animal(120, y, Color(Color("#CBD5E1"), 0.45))
	_rect(160, 30, 10, 110, Color("#475569"))
	_circle(260, 100, 6, PURPLE)
	_ring(260, 100, 20 + fmod(t * 20, 20), Color(PURPLE, 0.6), 2)
	_text(225, 140, "misión fantasma", PURPLE, 12)
	_text(60, 40, "Atraviesas paredes", INK, 12)

func _draw_roles() -> void:
	var cols := [RED, CYAN, AMBER]
	var names := ["Culpables", "Inocentes", "Mercenarios"]
	for i in 3:
		_rect(30 + i * 110, 40, 90, 100, Color(cols[i], 0.14))
		_rect(30 + i * 110, 40, 90, 100, Color(cols[i], 0.6), false, 2)
		_text(38 + i * 110, 60, names[i], cols[i], 11)
		_text(66 + i * 110, 112, "?", INK, 30)

func _draw_ability() -> void:
	_animal(110, 100, ANIMALS[5])
	for i in 4:
		_line(70 - i * 12, 92 + i * 6, 40 - i * 12, 92 + i * 6, Color(AMBER, 0.6 - i * 0.12), 3)
	var cd := fmod(t * 0.4, 1.0)
	_circle(270, 90, 30, Color("#1E293B"))
	draw_arc(P(270, 90), 30 * _k, -PI / 2, -PI / 2 + TAU * cd, 32, AMBER, 5 * _k, true)
	_text(263, 97, "Q", INK, 18)

func _draw_deduction() -> void:
	var pts := [Vector2(70, 50), Vector2(180, 40), Vector2(290, 60), Vector2(120, 125), Vector2(250, 125)]
	for a in pts.size():
		for b in [1, 3]:
			var j: int = (a + b) % pts.size()
			_line(pts[a].x + 15, pts[a].y + 18, pts[j].x + 15, pts[j].y + 18, Color(RED, 0.5), 1.5)
	for i in pts.size():
		_doc(pts[i].x, pts[i].y, [Color("#FDE68A"), Color("#BAE6FD"), INK, Color("#FBCFE8"), Color("#BBF7D0")][i], 30, 36)
		_circle(pts[i].x + 15, pts[i].y + 2, 3.5, RED)

func _draw_badge() -> void:
	var c := Vector2(180, 85)
	var pts := PackedVector2Array()
	for i in 10:
		var r := 62.0 if i % 2 == 0 else 30.0
		var ang := -PI / 2 + i * PI / 5.0
		pts.append(P(c.x + cos(ang) * r, c.y + sin(ang) * r))
	draw_colored_polygon(pts, AMBER)
	_circle(c.x, c.y, 22, Color("#B7791F"))
	_text(c.x - 7, c.y + 7, "D", Color("#FFF7E0"), 20)
	for i in 6:
		var a := t + i * TAU / 6.0
		_circle(c.x + cos(a) * 90, c.y + sin(a) * 60, 2.5, Color(AMBER, 0.6))
