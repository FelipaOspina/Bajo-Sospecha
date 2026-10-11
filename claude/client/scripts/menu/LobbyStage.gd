class_name LobbyStage
extends Control
## Sala de espera en 2.4D: alfombra, sofá, mesa de centro con la carpeta de evidencias
## y los animales de los jugadores alrededor (los chibis del mapa). Cada asiento lleva
## el nombre en una píldora, la corona del anfitrión y la etiqueta LISTO. Nunca el rol.
## Se diseña sobre un lienzo de 760×430 centrado y escalado al control.

const DESIGN := Vector2(760, 430)
## Asientos en orden de llegada (relativos al centro de la mesa): dos en el sofá, dos en
## los pufs de delante, los extremos del sofá y los laterales.
## back = en el sofá; corner, side y front = de pie junto a un puf.
const SLOTS := [
	{"pos": Vector2(-95, -40), "row": "back"}, {"pos": Vector2(95, -40), "row": "back"},
	{"pos": Vector2(-215, 150), "row": "front"}, {"pos": Vector2(215, 150), "row": "front"},
	{"pos": Vector2(-290, -20), "row": "corner"}, {"pos": Vector2(290, -20), "row": "corner"},
	{"pos": Vector2(-350, 70), "row": "side"}, {"pos": Vector2(350, 70), "row": "side"},
]
const SOLO_SLOT := {"pos": Vector2(0, 150), "row": "front"}
const ROW_SCALE := {"back": 1.0, "corner": 1.05, "side": 1.15, "front": 1.25}
const BACK_ROWS := ["back", "corner"]
const GREEN := Color("#4ADE80")

var _back: Node2D
var _table: Node2D
var _front: Node2D
var _seats := {}   # player_id -> Seat
var _empty: Array[Node2D] = []
var _signature := ""
var _scale := 1.0
var _center := Vector2.ZERO

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_back = Node2D.new()
	_back.name = "BackRow"
	add_child(_back)
	_table = _Table.new()
	_table.name = "Table"
	add_child(_table)
	_front = Node2D.new()
	_front.name = "FrontRow"
	add_child(_front)
	resized.connect(_relayout)
	_relayout()

## players: [{id, name, skinId, ready}] en orden de llegada. solo = sin sala (solo tú, delante).
func set_players(players: Array, host_id: String, max_players: int, local_id: String, solo := false) -> void:
	var signature := JSON.stringify([players, host_id, max_players, local_id, solo])
	if signature == _signature:
		return
	_signature = signature
	var keep := {}
	for i in players.size():
		var p: Dictionary = players[i]
		var id := str(p.get("id", ""))
		keep[id] = true
		var slot: Dictionary = SOLO_SLOT if solo else SLOTS[mini(i, SLOTS.size() - 1)]
		var seat: Seat = _seats.get(id)
		if seat == null:
			seat = Seat.new()
			seat.name = "Seat_" + id.left(8)
			_seats[id] = seat
			seat.pop_in()
		var row_parent := _back if slot["row"] in BACK_ROWS else _front
		if seat.get_parent() != row_parent:
			if seat.get_parent():
				seat.get_parent().remove_child(seat)
			row_parent.add_child(seat)
		seat.slot = slot
		seat.configure(str(p.get("name", "?")), str(p.get("skinId", SkinCatalog.fallback_for(id))), bool(p.get("ready", false)),
			id == host_id, id == local_id, slot["row"], p.get("look", {}) if p.get("look") is Dictionary else {})
	for id in _seats.keys():
		if not keep.has(id):
			_seats[id].queue_free()
			_seats.erase(id)
	for e in _empty:
		e.queue_free()
	_empty.clear()
	if not solo:
		for i in range(players.size(), mini(max_players, SLOTS.size())):
			var slot: Dictionary = SLOTS[i]
			var marker := _EmptySeat.new()
			marker.slot = slot
			(_back if slot["row"] in BACK_ROWS else _front).add_child(marker)
			_empty.append(marker)
	_relayout()

func seat_for(player_id: String) -> Seat:
	return _seats.get(player_id)

func seat_count() -> int:
	return _seats.size()

func empty_seat_count() -> int:
	return _empty.size()

func _relayout() -> void:
	_scale = minf(size.x / DESIGN.x, size.y / DESIGN.y)
	_center = Vector2(size.x / 2.0, size.y * 0.47)
	for row in [_back, _front]:
		if row == null:
			continue
		for seat in row.get_children():
			seat.position = _center + seat.slot["pos"] * _scale
			seat.scale = Vector2.ONE * _scale * ROW_SCALE[seat.slot["row"]]
		# Los de más abajo tapan a los de arriba.
		var children: Array = row.get_children()
		children.sort_custom(func(a, b): return a.position.y < b.position.y)
		for i in children.size():
			row.move_child(children[i], i)
	if _table:
		_table.position = _center + Vector2(0, 58) * _scale
		_table.scale = Vector2.ONE * _scale
	queue_redraw()

func _draw() -> void:
	draw_set_transform(_center, 0.0, Vector2(_scale, _scale))
	# Alfombra redonda.
	_ellipse(Vector2(0, 70), Vector2(350, 118), Color("#20263E", 0.92))
	_ellipse(Vector2(0, 70), Vector2(318, 104), Color("#2A3254"))
	_ellipse_outline(Vector2(0, 70), Vector2(290, 92), Color("#E5A93C", 0.22), 2.0)
	_ellipse_outline(Vector2(0, 70), Vector2(200, 62), Color("#E5A93C", 0.12), 1.5)
	# Sofá de dos plazas detrás de la mesa.
	var back := Rect2(-205, -128, 410, 78)
	_round_rect(back, Color("#262B42"), 22)
	_round_rect(Rect2(back.position, Vector2(back.size.x, 16)), Color("#323858"), 14)
	for i in 2:
		_round_rect(Rect2(-195 + i * 196, -116, 194, 60), Color("#2D334E"), 16)
	_round_rect(Rect2(-213, -54, 426, 34), Color("#30365A"), 12)
	_round_rect(Rect2(-232, -112, 40, 92), Color("#22273C"), 16)
	_round_rect(Rect2(192, -112, 40, 92), Color("#22273C"), 16)
	draw_set_transform(Vector2.ZERO)

func _ellipse(c: Vector2, r: Vector2, col: Color) -> void:
	draw_colored_polygon(_ellipse_points(c, r), col)

func _ellipse_outline(c: Vector2, r: Vector2, col: Color, w: float) -> void:
	var pts := _ellipse_points(c, r)
	pts.append(pts[0])
	draw_polyline(pts, col, w, true)

static func _ellipse_points(c: Vector2, r: Vector2, n := 48) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n:
		var a := TAU * i / n
		pts.append(c + Vector2(cos(a) * r.x, sin(a) * r.y))
	return pts

func _round_rect(r: Rect2, col: Color, radius: float) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(int(radius))
	sb.anti_aliasing = true
	draw_style_box(sb, r)

## Un jugador en la sala: puf (si está delante), chibi, nombre, corona y LISTO.
class Seat extends Node2D:
	var slot: Dictionary = {}
	var chibi: ProceduralChibiAvatar
	var pill: PanelContainer
	var name_label: Label
	var crown: MenuIcon
	var ready_badge: PanelContainer
	var is_host := false
	var is_ready := false
	var is_local := false
	var row := "back"
	var _hop := 0.0

	func _init() -> void:
		chibi = ProceduralChibiAvatar.new()
		chibi.name = "Chibi"
		chibi.bake = true   # en móviles y web, horneado (ChibiBaker)
		add_child(chibi)
		pill = PanelContainer.new()
		pill.name = "NamePill"
		pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		name_label = Label.new()
		name_label.add_theme_font_size_override("font_size", 13)
		name_label.add_theme_font_override("font", UiPalette.bold_font())
		name_label.add_theme_constant_override("outline_size", 3)
		pill.add_child(name_label)
		add_child(pill)
		crown = MenuIcon.make("crown", UiPalette.AMBER, 22)
		crown.name = "Crown"
		add_child(crown)
		ready_badge = PanelContainer.new()
		ready_badge.name = "ReadyBadge"
		ready_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ready_badge.add_theme_stylebox_override("panel", UiPalette.flat(Color(GREEN, 0.9), Color.TRANSPARENT, 0, 8, 3))
		var rl := Label.new()
		rl.text = "LISTO"
		rl.add_theme_font_size_override("font_size", 11)
		rl.add_theme_font_override("font", UiPalette.bold_font())
		rl.add_theme_color_override("font_color", Color("#06210F"))
		ready_badge.add_child(rl)
		add_child(ready_badge)

	func configure(display_name: String, skin_id: String, player_ready: bool, host: bool, local: bool, seat_row: String, look := {}) -> void:
		if player_ready and not is_ready:
			_hop = 1.0
		is_ready = player_ready
		is_host = host
		is_local = local
		row = seat_row
		if chibi.skin_id != skin_id:
			chibi.skin_id = skin_id
		chibi.look = look   # cosméticos: ropa, gorra, zapatillas, mochila
		name_label.text = display_name + (" (tú)" if local else "")
		var border := Color(UiPalette.AMBER, 0.9) if local else Color(1, 1, 1, 0.16)
		pill.add_theme_stylebox_override("panel", UiPalette.flat(Color(UiPalette.NAVY, 0.82), border, 1, 10, 4))
		crown.visible = host
		ready_badge.visible = player_ready
		queue_redraw()
		_place_labels.call_deferred()

	func pop_in() -> void:
		_hop = 1.0

	func _place_labels() -> void:
		pill.reset_size()
		var top := chibi.top_y() - 6.0
		pill.position = Vector2(-pill.size.x / 2.0, top - pill.size.y)
		crown.position = Vector2(-11, pill.position.y - 21)
		ready_badge.reset_size()
		ready_badge.position = Vector2(-ready_badge.size.x / 2.0, 10)

	func _process(delta: float) -> void:
		chibi.animate_walk(delta, 0.0)
		if _hop > 0.0:
			_hop = maxf(0.0, _hop - delta * 2.2)
			chibi.position.y = -sin(_hop * PI) * 14.0
			queue_redraw()
		elif chibi.position.y != 0.0:
			chibi.position.y = 0.0
			queue_redraw()

	func _draw() -> void:
		if row != "back":
			# Puf.
			draw_set_transform(Vector2(0, 4), 0.0, Vector2(1.0, 0.42))
			draw_circle(Vector2.ZERO, 44, Color(0, 0, 0, 0.35))
			draw_circle(Vector2(0, -6), 40, Color("#2F3654"))
			draw_circle(Vector2(-8, -16), 26, Color("#39416A"))
			draw_set_transform(Vector2.ZERO)
		ProceduralChibiAvatar.draw_contact_shadow(self, Vector2(0, -1), 1.0, -chibi.position.y)
		if is_local:
			draw_set_transform(Vector2(0, 2), 0.0, Vector2(1.0, 0.35))
			draw_arc(Vector2.ZERO, 34, 0, TAU, 40, Color(UiPalette.AMBER, 0.75), 3.0, true)
			draw_set_transform(Vector2.ZERO)

## Plaza libre: un círculo discontinuo en el suelo.
class _EmptySeat extends Node2D:
	var slot: Dictionary = {}

	func _draw() -> void:
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.36))
		for i in 16:
			var a := TAU * i / 16.0
			draw_arc(Vector2.ZERO, 30, a, a + TAU / 32.0, 4, Color(1, 1, 1, 0.28), 2.5, true)
		draw_set_transform(Vector2.ZERO)
		var font := UiPalette.body_font()
		draw_string(font, Vector2(-40, -14), "Plaza libre", HORIZONTAL_ALIGNMENT_CENTER, 80, 12, Color(1, 1, 1, 0.35))

## Mesa de centro con taza, carpeta de EVIDENCIA y portátil.
class _Table extends Node2D:
	func _draw() -> void:
		draw_set_transform(Vector2(0, 26), 0.0, Vector2(1.0, 0.36))
		draw_circle(Vector2.ZERO, 150, Color(0, 0, 0, 0.35))
		draw_set_transform(Vector2.ZERO)
		draw_rect(Rect2(-20, 0, 40, 26), Color("#1A120E"))
		draw_set_transform(Vector2(0, 4), 0.0, Vector2(1.0, 0.36))
		draw_circle(Vector2.ZERO, 132, Color("#24170F"))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.36))
		draw_circle(Vector2.ZERO, 130, Color("#4A3426"))
		draw_circle(Vector2(-14, -14), 104, Color("#56402F"))
		draw_arc(Vector2.ZERO, 120, 0, TAU, 48, Color(1, 1, 1, 0.06), 3, true)
		draw_set_transform(Vector2.ZERO)
		# Carpeta "EVIDENCIA".
		draw_set_transform(Vector2(26, 0), -0.18, Vector2(1.0, 0.62))
		draw_rect(Rect2(-40, -26, 80, 52), Color("#D9A35B"))
		draw_rect(Rect2(-40, -26, 80, 9), Color("#C48A45"))
		draw_rect(Rect2(-30, -6, 60, 16), Color("#C62828"), false, 2)
		draw_string(UiPalette.bold_font(), Vector2(-28, 7), "EVIDENCIA", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#C62828"))
		draw_set_transform(Vector2.ZERO)
		# Taza.
		draw_rect(Rect2(-78, -18, 14, 14), Color("#E8E4DA"))
		draw_arc(Vector2(-62, -11), 4, -PI / 2, PI / 2, 8, Color("#E8E4DA"), 2)
		draw_set_transform(Vector2(-71, -18), 0.0, Vector2(1.0, 0.4))
		draw_circle(Vector2.ZERO, 7, Color("#3B2416"))
		draw_set_transform(Vector2.ZERO)
		# Portátil.
		draw_colored_polygon(PackedVector2Array([Vector2(-48, 6), Vector2(-6, 6), Vector2(0, 16), Vector2(-56, 16)]), Color("#1C2030"))
		draw_colored_polygon(PackedVector2Array([Vector2(-46, -22), Vector2(-8, -22), Vector2(-6, 6), Vector2(-48, 6)]), Color("#12182A"))
		draw_colored_polygon(PackedVector2Array([Vector2(-43, -19), Vector2(-11, -19), Vector2(-9, 3), Vector2(-45, 3)]), Color("#00E5FF", 0.35))
		for i in 4:
			draw_line(Vector2(-40, -14 + i * 4), Vector2(-20 - (i % 2) * 8, -14 + i * 4), Color("#00E5FF", 0.7), 1)
