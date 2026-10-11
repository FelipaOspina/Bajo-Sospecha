class_name LobbyStage
extends Control
## Sala de espera en 2.4D: alfombra, un sofá bajo pegado a la pared, mesa de centro con
## la carpeta de evidencias y los animales de los jugadores alrededor (los chibis del
## mapa). Cada asiento lleva el nombre en una píldora, la corona del anfitrión y la
## etiqueta LISTO. Nunca el rol.
## El sofá es pequeño y está al fondo para no tapar el ventanal, el tablero de casos ni
## el lema de la pared. Asientos y mesa van en un mismo nodo con orden por Y (Y-Sort):
## quien está más abajo en la pantalla tapa a quien está detrás, y todos quedan encima
## de la alfombra. Luz de estudio suave: charco cálido sobre la alfombra, degradados y
## sombras de contacto difusas.
## Se diseña sobre un lienzo de 760×430 centrado y escalado al control.
##
## Tu animal es además tu mascota (Alter Ego): tócalo (clic o toque) y reacciona a su
## manera (el león sacude la melena, el panda da una voltereta...); arrastra el dedo o el
## ratón por encima para acariciarlo (cierra los ojos de gusto y salen corazones). La
## sala emite pet_touched para que suene su sonido; comer y beber los pide LobbyView con
## pet_react. Tu animal se dibuja siempre en vivo para poder poner esas caras; los de los
## demás, horneados en móvil (ChibiBaker).

signal pet_touched(gesture: String, skin_id: String)

const DESIGN := Vector2(760, 430)
## Asientos en orden de llegada (relativos al centro): dos delante del sofá, dos en los
## pufs de delante, los extremos y los laterales. Solo los dos primeros quedan detrás de
## la mesa.
const SLOTS := [
	{"pos": Vector2(-78, 10), "row": "back"}, {"pos": Vector2(78, 10), "row": "back"},
	{"pos": Vector2(-212, 152), "row": "front"}, {"pos": Vector2(212, 152), "row": "front"},
	{"pos": Vector2(-272, 34), "row": "corner"}, {"pos": Vector2(272, 34), "row": "corner"},
	{"pos": Vector2(-336, 108), "row": "side"}, {"pos": Vector2(336, 108), "row": "side"},
]
const SOLO_SLOT := {"pos": Vector2(0, 150), "row": "front"}
const ROW_SCALE := {"back": 1.0, "corner": 1.05, "side": 1.15, "front": 1.25}
const BACK_ROWS := ["back", "corner"]
const GREEN := Color("#4ADE80")
## Centro de la mesa y de la alfombra (relativos al centro del lienzo).
const TABLE_POS := Vector2(0, 66)
const RUG_POS := Vector2(0, 76)
## Sofá: caja del respaldo (el asiento y los brazos salen de ella).
const SOFA := Rect2(-150, -58, 300, 40)
## Gestos sobre tu mascota (en píxeles del lienzo de diseño y milisegundos).
const TAP_SLOP := 14.0
const TAP_MS := 450
const STROKE_PX := 90.0
const STROKE_GAP_MS := 700

var _floor: Node2D       # asientos, plazas libres y mesa, ordenados por Y
var _table: Node2D
var _seats := {}   # player_id -> Seat
var _empty: Array[Node2D] = []
var _signature := ""
var _scale := 1.0
var _center := Vector2.ZERO
var _local_id := ""
var _press := false
var _press_pos := Vector2.ZERO
var _press_ms := 0
var _stroke := 0.0
var _stroked := false
var _last_stroke_ms := -100000

static var _soft: GradientTexture2D

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS   # para tocar y acariciar a tu mascota
	_floor = Node2D.new()
	_floor.name = "Floor"
	_floor.y_sort_enabled = true
	add_child(_floor)
	_table = _Table.new()
	_table.name = "Table"
	_floor.add_child(_table)
	resized.connect(_relayout)
	_relayout()

## players: [{id, name, skinId, ready}] en orden de llegada. solo = sin sala (solo tú, delante).
func set_players(players: Array, host_id: String, max_players: int, local_id: String, solo := false) -> void:
	var signature := JSON.stringify([players, host_id, max_players, local_id, solo])
	if signature == _signature:
		return
	_signature = signature
	_local_id = local_id
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
			_floor.add_child(seat)
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
			var marker := _EmptySeat.new()
			marker.slot = SLOTS[i]
			_floor.add_child(marker)
			_empty.append(marker)
	_relayout()

func seat_for(player_id: String) -> Seat:
	return _seats.get(player_id)

func local_seat() -> Seat:
	return _seats.get(_local_id)

## Reacción de tu mascota (ver PetReactions) con una lluvia opcional de iconos:
## "hearts", "notes" o "food:<icono>" (la comida va hacia su boca). false si está ocupada
## con otra reacción (force la interrumpe: comer y beber, que piden los botones).
func pet_react(kind: String, burst := "", force := false) -> bool:
	var seat := local_seat()
	if seat == null or not seat.react(kind, force):
		return false
	if burst != "":
		seat.burst(burst)
	return true

## Bocadillo de "tengo hambre / sed" sobre tu mascota ("" = ninguno).
func set_pet_need(icon: String) -> void:
	var seat := local_seat()
	if seat:
		seat.set_need(icon)

## true si el punto (coordenadas del control) cae sobre tu mascota.
func pet_hit(point: Vector2) -> bool:
	var seat := local_seat()
	if seat == null:
		return false
	var local := seat.transform.affine_inverse() * point
	return seat.hit_rect().has_point(local)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and pet_hit(event.position):
			_press = true
			_press_pos = event.position
			_press_ms = Time.get_ticks_msec()
			_stroke = 0.0
			_stroked = false
			accept_event()
		elif not event.pressed and _press:
			_press = false
			accept_event()
			var quick := Time.get_ticks_msec() - _press_ms <= TAP_MS
			if not _stroked and quick and event.position.distance_to(_press_pos) <= TAP_SLOP * _scale:
				_gesture("tap")
	elif event is InputEventMouseMotion:
		var over := pet_hit(event.position)
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if over or _press else Control.CURSOR_ARROW
		if _press and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
			accept_event()
			if over:
				_stroke += event.relative.length()
			var now := Time.get_ticks_msec()
			if _stroke >= STROKE_PX * _scale and now - _last_stroke_ms >= STROKE_GAP_MS:
				_stroke = 0.0
				_stroked = true
				_last_stroke_ms = now
				_gesture("stroke")

## Tocar: la reacción propia del animal. Acariciar: ojos de gusto y corazones.
func _gesture(gesture: String) -> void:
	var seat := local_seat()
	if seat == null:
		return
	var skin := seat.chibi.skin_id
	var ok := pet_react(PetCare.tap_reaction(skin), "notes") if gesture == "tap" else pet_react("cuddle", "hearts")
	if ok:
		pet_touched.emit(gesture, skin)

func seat_count() -> int:
	return _seats.size()

func empty_seat_count() -> int:
	return _empty.size()

## Rectángulo del sofá en coordenadas del control (para comprobar que no tapa el fondo).
func sofa_rect() -> Rect2:
	return Rect2(_center + SOFA.position * _scale, SOFA.size * _scale)

func _relayout() -> void:
	_scale = minf(size.x / DESIGN.x, size.y / DESIGN.y)
	_center = Vector2(size.x / 2.0, size.y * 0.47)
	if _floor == null:
		return
	for seat in _floor.get_children():
		if seat == _table:
			continue
		seat.position = _center + seat.slot["pos"] * _scale
		seat.scale = Vector2.ONE * _scale * ROW_SCALE[seat.slot["row"]]
	_table.position = _center + TABLE_POS * _scale
	_table.scale = Vector2.ONE * _scale
	queue_redraw()

func _draw() -> void:
	draw_set_transform(_center, 0.0, Vector2(_scale, _scale))
	# Alfombra redonda con un charco de luz cálida de estudio encima.
	_ellipse(RUG_POS + Vector2(0, 6), Vector2(352, 120), Color(0, 0, 0, 0.28))
	_ellipse(RUG_POS, Vector2(346, 116), Color("#1E2440"))
	_ellipse(RUG_POS, Vector2(318, 104), Color("#283052"))
	_ellipse_outline(RUG_POS, Vector2(292, 93), Color("#E5A93C", 0.24), 2.0)
	_ellipse_outline(RUG_POS, Vector2(204, 64), Color("#E5A93C", 0.12), 1.5)
	_soft_blob(RUG_POS + Vector2(-30, -14), Vector2(300, 100), Color("#FFC88A", 0.16))
	# Sofá bajo contra la pared (no tapa el ventanal ni el tablero).
	_soft_blob(Vector2(0, SOFA.end.y + 26), Vector2(196, 22), Color(0, 0, 0, 0.5))
	_soft_round_rect(SOFA, Color("#3A4168"), Color("#262B45"), 14)
	draw_line(SOFA.position + Vector2(16, 3), Vector2(SOFA.end.x - 16, SOFA.position.y + 3), Color(1, 1, 1, 0.10), 2.0, true)
	for i in 2:
		_soft_round_rect(Rect2(SOFA.position.x + 10 + i * 141, SOFA.position.y + 8, 139, 30), Color("#3C446E"), Color("#2C3252"), 11)
	_soft_round_rect(Rect2(SOFA.position.x - 6, SOFA.end.y - 6, SOFA.size.x + 12, 22), Color("#3F4774"), Color("#2A3050"), 10)
	draw_line(Vector2(SOFA.position.x + 6, SOFA.end.y - 4), Vector2(SOFA.end.x - 6, SOFA.end.y - 4), Color(1, 1, 1, 0.09), 1.5, true)
	for side in [-1, 1]:
		var arm := Rect2(SOFA.position.x - 24 if side < 0 else SOFA.end.x - 4, SOFA.position.y + 10, 28, 46)
		_soft_round_rect(arm, Color("#353C62"), Color("#22273E"), 12)
	# Sombra difusa de la mesa sobre la alfombra (la mesa se dibuja en el suelo ordenado).
	_soft_blob(TABLE_POS + Vector2(0, 30), Vector2(170, 52), Color(0, 0, 0, 0.55))
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

## Mancha difusa (sombra de contacto o charco de luz): degradado radial estirado.
func _soft_blob(c: Vector2, r: Vector2, col: Color) -> void:
	draw_texture_rect(soft_texture(), Rect2(c - r, r * 2.0), false, col)

## Rectángulo redondeado con degradado vertical (luz de arriba).
func _soft_round_rect(r: Rect2, top: Color, bottom: Color, radius: float) -> void:
	draw_polygon(round_rect_points(r, radius), _vertical_colors(round_rect_points(r, radius), r, top, bottom))

static func round_rect_points(r: Rect2, radius: float, steps := 6) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var rad := minf(radius, minf(r.size.x, r.size.y) / 2.0)
	var corners := [[r.end - Vector2(rad, rad), 0.0], [Vector2(r.position.x + rad, r.end.y - rad), PI / 2.0],
		[r.position + Vector2(rad, rad), PI], [Vector2(r.end.x - rad, r.position.y + rad), PI * 1.5]]
	for c in corners:
		for i in steps + 1:
			var a: float = c[1] + PI / 2.0 * i / steps
			pts.append(c[0] + Vector2(cos(a), sin(a)) * rad)
	return pts

static func _vertical_colors(pts: PackedVector2Array, r: Rect2, top: Color, bottom: Color) -> PackedColorArray:
	var cols := PackedColorArray()
	for p in pts:
		cols.append(top.lerp(bottom, clampf((p.y - r.position.y) / maxf(r.size.y, 1.0), 0.0, 1.0)))
	return cols

static func soft_texture() -> GradientTexture2D:
	if _soft == null:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
		g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.45), Color(1, 1, 1, 0)])
		_soft = GradientTexture2D.new()
		_soft.gradient = g
		_soft.fill = GradientTexture2D.FILL_RADIAL
		_soft.fill_from = Vector2(0.5, 0.5)
		_soft.fill_to = Vector2(1.0, 0.5)
		_soft.width = 128
		_soft.height = 128
	return _soft

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
	var reaction := ""
	var _hop := 0.0
	var _react_t := 0.0
	var _lift_px := 0.0
	var _need: _NeedBubble

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
		_need = _NeedBubble.new()
		_need.name = "NeedBubble"
		_need.visible = false
		add_child(_need)

	func configure(display_name: String, skin_id: String, player_ready: bool, host: bool, local: bool, seat_row: String, look := {}) -> void:
		if player_ready and not is_ready:
			_hop = 1.0
		is_ready = player_ready
		is_host = host
		is_local = local
		row = seat_row
		if chibi.skin_id != skin_id:
			chibi.skin_id = skin_id
		# Tu mascota, siempre en vivo (pone caras al tocarla); las demás, horneadas en móvil.
		if chibi.bake == local:
			chibi.bake = not local
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
		_need.position = Vector2(34, chibi.top_y() + 26)
		if row in LobbyStage.BACK_ROWS:
			# Detrás de la mesa los pies quedan tapados: LISTO va junto al nombre.
			ready_badge.position = Vector2(pill.position.x + pill.size.x + 4, pill.position.y + (pill.size.y - ready_badge.size.y) / 2.0)
		else:
			ready_badge.position = Vector2(-ready_badge.size.x / 2.0, 10)

	## Empieza una reacción de mascota. false si ya está con otra (las caricias seguidas
	## alargan la que está en marcha).
	func react(kind: String, force := false) -> bool:
		if not PetReactions.has_kind(kind):
			return false
		if reaction == kind and kind == "cuddle":
			_react_t = minf(_react_t, PetReactions.duration(kind) * 0.3)
			return true
		if reaction != "" and reaction != "cuddle" and not force:
			return false
		reaction = kind
		_react_t = 0.0
		chibi.kick_ears(5.0)
		return true

	## Zona que cuenta como "tocar a la mascota" (coordenadas del asiento).
	func hit_rect() -> Rect2:
		var top := chibi.top_y()
		return Rect2(-36, top, 72, -top + 6)

	func burst(kind: String) -> void:
		var b := _Burst.new()
		b.setup(kind, chibi.top_y())
		add_child(b)

	func set_need(icon: String) -> void:
		_need.icon = icon
		_need.visible = icon != "" and reaction == ""

	func _process(delta: float) -> void:
		var s := PetReactions.rest()
		if reaction != "":
			_react_t += delta
			if _react_t >= PetReactions.duration(reaction):
				reaction = ""
				_need.visible = _need.icon != ""
			else:
				s = PetReactions.sample(reaction, _react_t)
				_need.visible = false
		chibi.emote = s["emote"]
		chibi.animate_walk(delta, 0.0)
		var hop_y := 0.0
		if _hop > 0.0:
			_hop = maxf(0.0, _hop - delta * 2.2)
			hop_y = -sin(_hop * PI) * 14.0
		var offset: Vector2 = s["offset"] + Vector2(0, hop_y)
		var pivot: Vector2 = s["pivot"]
		var basis := Transform2D(float(s["rot"]), s["scale"], 0.0, Vector2.ZERO)
		var t := Transform2D(float(s["rot"]), s["scale"], 0.0, pivot + offset - basis.basis_xform(pivot))
		if t != chibi.transform:
			chibi.transform = t
			_lift_px = -offset.y
			queue_redraw()

	func _draw() -> void:
		if row != "back":
			# Puf con sombra difusa y luz de arriba.
			draw_texture_rect(LobbyStage.soft_texture(), Rect2(Vector2(-50, -10), Vector2(100, 30)), false, Color(0, 0, 0, 0.5))
			draw_set_transform(Vector2(0, 4), 0.0, Vector2(1.0, 0.42))
			draw_circle(Vector2(0, -6), 40, Color("#2B3150"))
			draw_circle(Vector2(-4, -12), 34, Color("#343B62"))
			draw_circle(Vector2(-10, -18), 22, Color("#3E4673"))
			draw_set_transform(Vector2.ZERO)
		ProceduralChibiAvatar.draw_contact_shadow(self, Vector2(0, -1), 1.0, _lift_px)
		if is_local:
			draw_set_transform(Vector2(0, 2), 0.0, Vector2(1.0, 0.35))
			draw_arc(Vector2.ZERO, 34, 0, TAU, 40, Color(UiPalette.AMBER, 0.75), 3.0, true)
			draw_set_transform(Vector2.ZERO)

## Iconos que salen de tu mascota al reaccionar: corazones o notas que suben, o su comida
## (o una gota de agua) que va hacia la boca y suelta unos brillos.
class _Burst extends Node2D:
	var _parts: Array = []   # {icon, from, to, t, life, size, delay, sway}
	var _rng := RandomNumberGenerator.new()

	func setup(kind: String, top: float) -> void:
		_rng.randomize()
		var head := Vector2(0, top * 0.82)   # a la altura de las orejas: no tapan la cara
		if kind.begins_with("food:"):
			var icon := kind.trim_prefix("food:")
			_parts.append({"icon": icon, "from": Vector2(40, top - 8), "to": Vector2(0, -52), "t": 0.0, "life": 0.6, "size": 30.0, "delay": 0.0, "sway": 0.0, "shrink": true})
			for i in 4:
				_parts.append({"icon": "sparkle", "from": Vector2(0, -52), "to": Vector2(_rng.randf_range(-30, 30), -52 + _rng.randf_range(-34, -14)), "t": 0.0, "life": 0.55, "size": 12.0, "delay": 0.55 + i * 0.05, "sway": 0.0, "shrink": false})
			return
		var icon := "heart" if kind == "hearts" else "note"
		for i in (5 if kind == "hearts" else 3):
			var from := head + Vector2(_rng.randf_range(24, 34) * (1 if i % 2 == 0 else -1), _rng.randf_range(-6, 6))
			_parts.append({"icon": icon, "from": from, "to": from + Vector2(signf(from.x) * _rng.randf_range(4, 22), _rng.randf_range(-70, -46)), "t": 0.0, "life": 1.1, "size": _rng.randf_range(13, 19), "delay": i * 0.09, "sway": _rng.randf_range(2.0, 5.0), "shrink": false})

	func _process(delta: float) -> void:
		var alive := false
		for p in _parts:
			p["t"] += delta
			if p["t"] < p["delay"] + p["life"]:
				alive = true
		queue_redraw()
		if not alive:
			queue_free()

	func _draw() -> void:
		for p in _parts:
			var k := clampf((p["t"] - p["delay"]) / p["life"], 0.0, 1.0)
			if p["t"] < p["delay"] or k >= 1.0:
				continue
			var eased := 1.0 - (1.0 - k) * (1.0 - k)
			var pos: Vector2 = p["from"].lerp(p["to"], eased) + Vector2(sin(k * TAU) * p["sway"], 0)
			var size: float = p["size"] * (1.0 - 0.6 * k if p["shrink"] else 0.7 + 0.3 * minf(k * 4.0, 1.0))
			var alpha := 1.0 if p["shrink"] else 1.0 - smoothstep(0.6, 1.0, k)
			PetIcons.draw(self, p["icon"], pos, size, alpha)

## Bocadillo de pensamiento con lo que necesita (su comida o una gota de agua).
class _NeedBubble extends Node2D:
	var icon := "":
		set(v):
			icon = v
			queue_redraw()
	var _t := 0.0

	func _process(delta: float) -> void:
		if visible:
			_t += delta
			queue_redraw()

	func _draw() -> void:
		if icon == "":
			return
		var bob := Vector2(0, sin(_t * 3.0) * 2.0)
		draw_circle(Vector2(-14, 16) + bob * 0.5, 3.0, Color(1, 1, 1, 0.85))
		draw_circle(Vector2(-8, 10) + bob * 0.7, 4.5, Color(1, 1, 1, 0.9))
		draw_circle(Vector2(6, -6) + bob, 16.0, Color(0, 0, 0, 0.25))
		draw_circle(Vector2(5, -8) + bob, 16.0, Color(1, 1, 1, 0.95))
		PetIcons.draw(self, icon, Vector2(5, -8) + bob, 22.0)

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
		draw_rect(Rect2(-20, 0, 40, 26), Color("#1A120E"))
		draw_set_transform(Vector2(0, 4), 0.0, Vector2(1.0, 0.36))
		draw_circle(Vector2.ZERO, 132, Color("#24170F"))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.36))
		draw_circle(Vector2.ZERO, 130, Color("#4A3426"))
		draw_circle(Vector2(-10, -10), 112, Color("#523B2C"))
		draw_texture_rect(LobbyStage.soft_texture(), Rect2(Vector2(-110, -100), Vector2(170, 150)), false, Color("#FFD9A8", 0.22))
		draw_arc(Vector2.ZERO, 124, PI * 1.05, PI * 1.75, 32, Color(1, 1, 1, 0.12), 3, true)
		draw_arc(Vector2.ZERO, 128, 0, TAU, 64, Color(0, 0, 0, 0.25), 2, true)
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
