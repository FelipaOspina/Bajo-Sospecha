class_name LobbyStage
extends Control
## Sala de espera en 3D, con el mismo estilo de juguete de vinilo que la oficina: la sala
## de reuniones de la agencia de detectives, de noche. Al fondo, la pared con el ventanal
## a la ciudad, el tablero de CASOS con fotos e hilo rojo y el neón "BAJO SOSPECHA";
## delante, una grada en semicírculo de tres escalones (con tiras de luz en el borde) en
## la que cada jugador tiene su plataforma redonda con un aro de luz.
## Luz de cine: foco cálido cenital con su haz "volumétrico", contraluces de color (cian
## a un lado, violeta al otro) que perfilan el vinilo, la ciudad por el ventanal, motas de
## polvo flotando en el haz y una cámara que deriva muy despacio (paralaje).
##
## Cada jugador es su personaje 3D (PlushAvatar3D) en una plaza, en orden de llegada,
## respirando y mirando alrededor. Las plazas están al tresbolillo (delante 4, en medio 4
## y arriba 4) para que ningún nombre tape a otro. Encima van en 2D (proyectados desde
## la cabeza con la cámara) el nombre en una píldora (con la marca de LISTO dentro), la
## corona del anfitrión, el bocadillo de hambre o sed y los corazones. Nunca el rol:
## solo colores de la skin y del cosmético; el aro es neutro, ámbar el tuyo y verde si
## estás listo (lo mismo para todos).
##
## La sala 3D ocupa todo el control; la cámara encuadra las plazas dentro de
## focus_margins (el hueco que dejan los paneles de LobbyView).
##
## Tu animal es además tu mascota (Alter Ego): tócalo (clic o toque) y reacciona a su
## manera (el león sacude la melena, el panda da una voltereta...); arrastra el dedo o el
## ratón por encima para acariciarlo (se aplasta de gusto, entorna los ojos y salen
## corazones). La sala emite pet_touched para que suene su sonido; comer y beber los pide
## LobbyView con pet_react.
##
## Rendimiento (móvil): un solo SubViewport para toda la sala (nada de un viewport por
## plaza), MSAA 2x, sin sombras dinámicas y a 30 fps; si la sala no se ve, no se dibuja.
## Los haces, aros y halos son shaders aditivos sin luz (baratos y sin depender del glow).

signal pet_touched(gesture: String, skin_id: String)

## Personaje 3D cargado por ruta (no por class_name): funciona aunque la caché de clases
## de .godot sea vieja, p. ej. al abrir el juego con el .bat sin pasar por el editor.
const Plush3D := preload("res://scripts/world3d/HeroAvatar3D.gd")   # hero; sin su GLB cae a PlushAvatar3D / vinilo
const DESIGN := Vector2(760, 430)
## Centro de la grada (elipses de los escalones) y alturas de cada escalón.
const STAGE_C := Vector3(0, 0, -2.6)
const TIERS := [
	{"h": 0.42, "a": 5.05, "b": 3.0},
	{"h": 0.88, "a": 3.9, "b": 1.75},
]
## Plazas en orden de llegada (metros; y = altura del escalón; la cara mira a +Z, hacia
## la cámara). Al tresbolillo: delante 4 en el suelo, en medio 4 en el primer escalón
## (entre los de delante) y arriba 4 en el segundo (detrás de los de delante).
const SLOTS := [
	{"pos": Vector3(-0.85, 0, 1.15), "row": "front"}, {"pos": Vector3(0.85, 0, 1.15), "row": "front"},
	{"pos": Vector3(-2.55, 0, 0.72), "row": "front"}, {"pos": Vector3(2.55, 0, 0.72), "row": "front"},
	{"pos": Vector3(-1.7, 0.42, -0.3), "row": "mid"}, {"pos": Vector3(1.7, 0.42, -0.3), "row": "mid"},
	{"pos": Vector3(-3.35, 0.42, -0.85), "row": "mid"}, {"pos": Vector3(3.35, 0.42, -0.85), "row": "mid"},
	{"pos": Vector3(-0.85, 0.88, -1.45), "row": "back"}, {"pos": Vector3(0.85, 0.88, -1.45), "row": "back"},
	{"pos": Vector3(-2.55, 0.88, -1.75), "row": "back"}, {"pos": Vector3(2.55, 0.88, -1.75), "row": "back"},
]
const SOLO_SLOT := {"pos": Vector3(0, 0, 1.0), "row": "solo"}
## Filas de atrás (compatibilidad: antes LISTO iba junto al nombre en ellas).
const BACK_ROWS := ["back"]
## Altura de la plataforma redonda de cada plaza.
const PLATFORM_H := 0.07
## Compatibilidad: antes había pufs.
const POUF_ROWS := []
const POUF_H := PLATFORM_H
const GREEN := Color("#4ADE80")
## Lo que debe caber en el encuadre sin sala (tú solo, en el centro).
const FRAME_SOLO := AABB(Vector3(-3.1, 0.0, -3.0), Vector3(6.2, 3.5, 4.6))
## Márgenes alrededor de las plazas usadas (x, arriba para el nombre, z).
const FRAME_PAD := Vector3(0.62, 1.95, 0.5)
const CAM_PITCH := -15.0
## Proporción máxima del hueco de encuadre (ancho / alto).
const MAX_FOCUS_ASPECT := 1.95
const CAM_FOV := 30.0
const WALL_Z := -3.0
## Deriva de cámara (paralaje): amplitud en metros y grados.
const DRIFT_M := Vector2(0.10, 0.04)
const DRIFT_DEG := 0.55
## Reacción de mascota (PetReactions) → movimiento del personaje 3D (Plush3D.react).
const MOTIONS := {
	"mane_shake": "wiggle", "howl": "stretch", "chuff": "nod", "pounce": "pounce", "meow": "tilt",
	"wag": "double_hop", "sway": "sway", "roll": "flip", "binky": "spin", "rub_hands": "rub",
	"head_turn": "look", "flap": "flap", "cuddle": "squish", "eat": "nod", "drink": "nod", "refuse": "shake",
}
## Gestos sobre tu mascota (en píxeles del lienzo de diseño y milisegundos).
const TAP_SLOP := 14.0
const TAP_MS := 450
const STROKE_PX := 90.0
const STROKE_GAP_MS := 700

const RING_SHADER := preload("res://shaders/lobby_glow_ring.gdshader")
const BEAM_SHADER := preload("res://shaders/lobby_beam.gdshader")
const EMISSIVE_SHADER := preload("res://shaders/lobby_emissive.gdshader")
const GLOW_SHADER := preload("res://shaders/lobby_soft_glow.gdshader")
const GlassBox := preload("res://scripts/ui/GlassBox.gd")

## Márgenes (izq., arriba, der., abajo) en px del hueco donde se encuadran las plazas.
@export var focus_margins := Vector4.ZERO:
	set(v):
		focus_margins = v
		_relayout()

var mobile := false
var _vp: SubViewport
var _cam: Camera3D
var _cam_base := Transform3D.IDENTITY
var _room: Node3D          # muebles y decorado (fijo)
var _actors: Node3D        # plazas: plataformas, aros y personajes
var _overlay: Node2D       # nombres, coronas, bocadillos y corazones
var _seats := {}   # player_id -> Seat
var _empty: Array = []     # _EmptySeat
var _signature := ""
var _frame_box := FRAME_SOLO
var _scale := 1.0
var _local_id := ""
var _press := false
var _press_pos := Vector2.ZERO
var _press_ms := 0
var _stroke := 0.0
var _stroked := false
var _last_stroke_ms := -100000
var _frame := 0
var _time := 0.0
var _mats := {}
var _rng := RandomNumberGenerator.new()

static var _soft: GradientTexture2D

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS   # para tocar y acariciar a tu mascota
	mobile = OS.has_feature("mobile") or OS.has_feature("web")
	_rng.seed = 2207
	_vp = SubViewport.new()
	_vp.name = "Lounge3D"
	_vp.own_world_3d = true
	_vp.msaa_3d = Viewport.MSAA_2X if mobile else Viewport.MSAA_4X
	_vp.positional_shadow_atlas_size = 0 if mobile else 2048
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_vp)
	_build_environment()
	_room = Node3D.new()
	_room.name = "Room"
	_vp.add_child(_room)
	_build_room()
	_actors = Node3D.new()
	_actors.name = "Actors"
	_vp.add_child(_actors)
	_cam = Camera3D.new()
	_cam.fov = CAM_FOV
	_cam.near = 0.1
	_cam.far = 60.0
	_cam.current = true
	_vp.add_child(_cam)
	_overlay = Node2D.new()
	_overlay.name = "Overlay"
	add_child(_overlay)
	resized.connect(_relayout)
	visibility_changed.connect(_refresh_updates)
	_relayout()

## players: [{id, name, skinId, ready, look, connected}] en orden de llegada.
## solo = sin sala (solo tú, en el centro).
func set_players(players: Array, host_id: String, max_players: int, local_id: String, solo := false) -> void:
	var signature := JSON.stringify([players, host_id, max_players, local_id, solo])
	if signature == _signature:
		return
	_signature = signature
	_local_id = local_id
	_frame_box = FRAME_SOLO if solo else _frame_for(clampi(maxi(max_players, players.size()), 1, SLOTS.size()))
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
			_overlay.add_child(seat)
			_actors.add_child(seat.anchor)
		seat.set_slot(slot, _platform_mats())
		seat.configure(str(p.get("name", "?")), str(p.get("skinId", SkinCatalog.fallback_for(id))), bool(p.get("ready", false)),
			id == host_id, id == local_id, slot["row"], p.get("look", {}) if p.get("look") is Dictionary else {})
		seat.set_connected(solo or bool(p.get("connected", true)))
		seat.set_ring(_ring_mat("ready") if bool(p.get("ready", false)) else (_ring_mat("local") if id == local_id else _ring_mat("idle")))
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
			marker.ring = _empty_platform(SLOTS[i]["pos"])
			_actors.add_child(marker.ring)
			_overlay.add_child(marker)
			_empty.append(marker)
	_relayout()

## Caja de encuadre: las n primeras plazas con sitio para los nombres encima.
func _frame_for(n: int) -> AABB:
	var box := AABB(SLOTS[0]["pos"], Vector3.ZERO)
	for i in n:
		box = box.expand(SLOTS[i]["pos"])
	box.position -= Vector3(FRAME_PAD.x, 0.0, FRAME_PAD.z)
	box.size += Vector3(FRAME_PAD.x * 2.0, 0.0, FRAME_PAD.z * 2.0)
	box.position.y = 0.0
	box.size.y = box.size.y + FRAME_PAD.y
	return box

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

## true si el punto (coordenadas del control) cae sobre tu mascota (su modelo proyectado).
func pet_hit(point: Vector2) -> bool:
	var seat := local_seat()
	return seat != null and seat.hit_rect().has_point(point)

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
	var skin := seat.skin_id
	var ok := pet_react(PetCare.tap_reaction(skin), "notes") if gesture == "tap" else pet_react("cuddle", "hearts")
	if ok:
		pet_touched.emit(gesture, skin)

func seat_count() -> int:
	return _seats.size()

func empty_seat_count() -> int:
	return _empty.size()

## Rectángulo de la grada en coordenadas del control (lo que antes era el sofá).
func sofa_rect() -> Rect2:
	return project_box(AABB(Vector3(-3.9, 0.0, WALL_Z + 0.2), Vector3(7.8, 0.5, 1.6)))

## Hueco del control donde se encuadran las plazas.
func focus_rect() -> Rect2:
	var r := Rect2(Vector2(focus_margins.x, focus_margins.y), size - Vector2(focus_margins.x + focus_margins.z, focus_margins.y + focus_margins.w))
	if r.size.x < 80.0 or r.size.y < 80.0:
		return Rect2(Vector2.ZERO, size)
	return r

## Punto 3D de la sala → coordenadas del control.
func project(p: Vector3) -> Vector2:
	if _cam == null or _vp == null or _vp.size.x <= 0:
		return Vector2.ZERO
	return _cam.unproject_position(p) * (size / Vector2(_vp.size))

## Caja 3D → rectángulo que ocupa en el control.
func project_box(box: AABB) -> Rect2:
	var r := Rect2(project(box.position), Vector2.ZERO)
	for i in 8:
		r = r.expand(project(box.get_endpoint(i)))
	return r

func _relayout() -> void:
	if _vp == null:
		return
	var k := get_viewport().get_final_transform().get_scale().y if get_viewport() else 1.0
	var px := (size * clampf(k, 1.0, 1.5 if mobile else 2.0)).ceil()
	_vp.size = Vector2i(maxi(int(px.x), 16), maxi(int(px.y), 16))
	var focus := focus_rect()
	_scale = maxf(minf(focus.size.x / DESIGN.x, focus.size.y / DESIGN.y), 0.1)
	_fit_camera(focus)
	_cam_base = _cam.transform
	_apply_drift()
	_place_overlays()
	_refresh_updates()
	queue_redraw()

func _place_overlays() -> void:
	var order: Array = []
	for seat in _seats.values():
		seat.place(self, _scale)
		order.append(seat)
	for e in _empty:
		e.position = project(e.slot["pos"] + Vector3(0, PLATFORM_H, 0))
		e.scale = Vector2.ONE * _scale
	# Los de delante tapan a los de detrás.
	order.sort_custom(func(a, b): return a.anchor.position.z < b.anchor.position.z)
	for i in order.size():
		_overlay.move_child(order[i], -1)

## Encuadra la caja dentro del hueco: ajusta la distancia (tamaño) y desplaza la cámara
## en su plano (centro). Converge en pocas vueltas porque el tamaño va como 1/distancia.
## En pantallas muy anchas no se acerca más: se ve más pared a los lados.
func _fit_camera(focus: Rect2) -> void:
	var max_w := focus.size.y * MAX_FOCUS_ASPECT
	if focus.size.x > max_w:
		focus = Rect2(focus.position.x + (focus.size.x - max_w) / 2.0, focus.position.y, max_w, focus.size.y)
	var basis := Basis.from_euler(Vector3(deg_to_rad(CAM_PITCH), 0.0, 0.0))
	var look := _frame_box.get_center()
	var dist := 10.0
	var shift := Vector2.ZERO
	for i in 10:
		_cam.transform = Transform3D(basis, look + basis.z * dist + basis.x * shift.x + basis.y * shift.y)
		var r := project_box(_frame_box)
		if r.size.x <= 1.0 or r.size.y <= 1.0:
			return
		dist *= maxf(r.size.x / focus.size.x, r.size.y / focus.size.y)
		var m_per_px := 2.0 * dist * tan(deg_to_rad(CAM_FOV) / 2.0) / maxf(size.y, 1.0)
		var d := focus.get_center() - r.get_center()
		shift += Vector2(-d.x, d.y) * m_per_px
	_cam.transform = Transform3D(basis, look + basis.z * dist + basis.x * shift.x + basis.y * shift.y)

## Deriva lenta de la cámara alrededor de su encuadre (paralaje suave).
func _apply_drift() -> void:
	var t := _time
	var off := Vector3(sin(t * 0.23) * DRIFT_M.x, sin(t * 0.31 + 1.3) * DRIFT_M.y, 0.0)
	var yaw := deg_to_rad(sin(t * 0.19 + 0.4) * DRIFT_DEG)
	var pitch := deg_to_rad(sin(t * 0.27) * DRIFT_DEG * 0.4)
	_cam.transform = _cam_base * Transform3D(Basis.from_euler(Vector3(pitch, yaw, 0.0)), off)

## Solo se dibuja mientras se ve; en móvil, a 30 fps (un frame sí y otro no).
func _refresh_updates() -> void:
	if _vp == null:
		return
	var on := is_visible_in_tree()
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if on and not mobile else SubViewport.UPDATE_ONCE if on else SubViewport.UPDATE_DISABLED
	set_process(on)

func _process(delta: float) -> void:
	_time += delta
	if mobile:
		_frame += 1
		if _frame % 2 != 0:
			return
		_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	_apply_drift()
	_place_overlays()

func _draw() -> void:
	if _vp:
		draw_texture_rect(_vp.get_texture(), Rect2(Vector2.ZERO, size), false)
	# Viñeta de cine: oscurece suave los bordes (y deja leer mejor los paneles).
	var w := size.x
	var h := size.y
	var dark := Color(0.01, 0.015, 0.04, 0.55)
	var clear := Color(dark, 0.0)
	var band := minf(w, h) * 0.28
	for q in [[Vector2(0, 0), Vector2(w, 0), Vector2(w, band), Vector2(0, band), dark, dark, clear, clear],
			[Vector2(0, h - band * 1.2), Vector2(w, h - band * 1.2), Vector2(w, h), Vector2(0, h), clear, clear, dark, dark],
			[Vector2(0, 0), Vector2(band, 0), Vector2(band, h), Vector2(0, h), dark, clear, clear, dark],
			[Vector2(w - band, 0), Vector2(w, 0), Vector2(w, h), Vector2(w - band, h), clear, dark, dark, clear]]:
		draw_polygon(PackedVector2Array([q[0], q[1], q[2], q[3]]), PackedColorArray([q[4], q[5], q[6], q[7]]))

# ── luz y entorno ───────────────────────────────────────────────────────────

func _build_environment() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("#070A16")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("#7D8BC4")
	e.ambient_light_energy = 0.42
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	e.tonemap_exposure = 1.12
	e.tonemap_white = 6.0
	e.glow_enabled = not mobile
	e.glow_intensity = 0.7
	e.glow_strength = 1.05
	e.glow_bloom = 0.03
	e.glow_hdr_threshold = 1.0
	e.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	e.adjustment_enabled = true
	e.adjustment_contrast = 1.06
	e.adjustment_saturation = 1.08
	env.environment = e
	_vp.add_child(env)
	# Luz principal de estudio, cálida y suave, desde delante a la izquierda.
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-42, -28, 0)
	key.light_energy = 0.62
	key.light_color = Color("#FFE6C7")
	key.shadow_enabled = not mobile
	key.shadow_blur = 2.5
	key.directional_shadow_max_distance = 22.0
	_vp.add_child(key)
	# Relleno frío muy suave desde la derecha.
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-18, 38, 0)
	fill.light_energy = 0.22
	fill.light_color = Color("#9DB4FF")
	_vp.add_child(fill)
	# Contraluces de color desde detrás: cian a la izquierda, violeta a la derecha.
	_rim(Vector3(-5.2, 3.6, -2.2), Color("#3DD8FF"), 5.5)
	_rim(Vector3(5.2, 3.6, -2.2), Color("#B26BFF"), 5.5)
	# Foco cenital cálido sobre la grada (el "charco" de luz del escenario).
	var pool := SpotLight3D.new()
	pool.position = Vector3(0, 6.2, 0.4)
	pool.rotation_degrees = Vector3(-90, 0, 0)
	pool.spot_angle = 34.0
	pool.spot_angle_attenuation = 1.4
	pool.spot_range = 9.0
	pool.light_energy = 3.2
	pool.light_color = Color("#FFD2A1")
	pool.shadow_enabled = not mobile
	_vp.add_child(pool)

func _rim(pos: Vector3, col: Color, energy: float) -> void:
	var s := SpotLight3D.new()
	s.position = pos
	s.light_color = col
	s.light_energy = energy
	s.spot_range = 11.0
	s.spot_angle = 40.0
	s.spot_angle_attenuation = 1.2
	_vp.add_child(s)
	s.look_at_from_position(pos, Vector3(0, 0.7, 0.2), Vector3.UP)

func _omni(pos: Vector3, col: Color, energy: float, reach: float) -> void:
	var o := OmniLight3D.new()
	o.position = pos
	o.light_color = col
	o.light_energy = energy
	o.omni_range = reach
	o.omni_attenuation = 1.4
	_room.add_child(o)

# ── decorado ────────────────────────────────────────────────────────────────

func _build_room() -> void:
	_floor_and_wall()
	_window(Vector3(3.75, 1.95, WALL_Z), Vector2(2.9, 2.0))
	_case_board(Vector3(-3.7, 1.55, WALL_Z), Vector2(2.1, 1.2))
	_neon_sign(Vector3(0.0, 2.85, WALL_Z + 0.06))
	_stage()
	_floor_lamp(Vector3(5.9, 0, WALL_Z + 0.55))
	_plant(Vector3(-6.0, 0, WALL_Z + 0.55), 1.2)
	_plant(Vector3(6.6, 0, WALL_Z + 0.6), 1.05)
	_shelf(Vector3(-6.4, 0, WALL_Z + 0.25))
	_cabinet(Vector3(-5.05, 0, WALL_Z + 0.32))
	_beams()
	_dust()
	# Focos de galería que bañan la pared (tablero, neón y ventanal).
	for x in [-3.7, 3.75]:
		var wash := SpotLight3D.new()
		wash.position = Vector3(x, 4.4, WALL_Z + 1.4)
		wash.rotation_degrees = Vector3(-64, 0, 0)
		wash.spot_angle = 30.0
		wash.spot_angle_attenuation = 1.5
		wash.spot_range = 5.5
		wash.light_energy = 2.6
		wash.light_color = Color("#FFD9A8")
		_room.add_child(wash)

func _floor_and_wall() -> void:
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_texture = _tex_planks(Color("#3B2A20"))
	floor_mat.roughness = 0.32
	floor_mat.metallic_specular = 0.6
	floor_mat.uv1_triplanar = true
	floor_mat.uv1_world_triplanar = true
	floor_mat.uv1_scale = Vector3.ONE * 0.45
	_box(Vector3(0, -0.05, 4.0), Vector3(30, 0.1, 14.0), floor_mat)
	# Pared: azul noche con paneles verticales y zócalo oscuro con moldura.
	_box(Vector3(0, 4.0, WALL_Z - 0.1), Vector3(30, 8.0, 0.2), _mat("wall", Color("#1E2644"), 0.85))
	for i in 25:
		var x := -12.0 + i * 1.0
		_box(Vector3(x, 2.3, WALL_Z + 0.01), Vector3(0.03, 2.6, 0.02), _mat("wall_line", Color("#18203A"), 0.8))
	_box(Vector3(0, 0.5, WALL_Z + 0.02), Vector3(30, 1.0, 0.04), _mat("wainscot", Color("#121731"), 0.55))
	_box(Vector3(0, 1.01, WALL_Z + 0.05), Vector3(30, 0.05, 0.06), _mat("rail", Color("#2A3356"), 0.4))
	_box(Vector3(0, 0.06, WALL_Z + 0.05), Vector3(30, 0.12, 0.06), _mat("base", Color("#0B0E1C"), 0.5))
	_box(Vector3(0, 3.62, WALL_Z + 0.04), Vector3(30, 0.08, 0.06), _mat("rail_top", Color("#232C4C"), 0.5))

## Grada en semicírculo: alfombra base con su borde de luz y dos escalones con tira LED.
func _stage() -> void:
	var c := STAGE_C
	var base_mat := _mat("stage_rug", Color("#161C34"), 0.92)
	_disc(c + Vector3(0, 0.006, 0), 1.0, 0.012, base_mat, Vector3(6.0, 1, 4.55))
	_ellipse_band(c, 5.85, 4.4, 0.0145, 0.05, _glow_line(Color("#E5A93C"), 0.9), false)
	var riser := _mat("riser", Color("#10142A"), 0.5)
	var carpet := _mat("tier_top", Color("#1C2343"), 0.95)
	for t in TIERS:
		var h: float = t["h"]
		var a: float = t["a"]
		var b: float = t["b"]
		_disc(c + Vector3(0, h / 2.0, 0), 1.0, h, riser, Vector3(a, 1, b))
		_disc(c + Vector3(0, h + 0.003, 0), 1.0, 0.006, carpet, Vector3(a - 0.1, 1, b - 0.08))
		# Tira LED en la arista del escalón y reflejo tenue en la contrahuella.
		_ellipse_band(c, a + 0.004, b + 0.004, h - 0.035, 0.022, _glow_line(Color("#FFC46B"), 1.6), true)
		_ellipse_band(c, a + 0.006, b + 0.006, h * 0.5 - 0.06, h - 0.07, _glow_line(Color("#FFB347"), 0.08), true)
	# Plataforma de "héroe" en el centro (donde estás tú sin sala).
	var hero := _ring_quad(SOLO_SLOT["pos"] + Vector3(0, 0.02, 0), 2.6, _hero_ring())
	hero.name = "HeroRing"

## Banda fina siguiendo media elipse (la mitad que mira a la cámara). vertical = en la
## contrahuella (de y a y + w); si no, tumbada en el suelo (anchura w hacia dentro).
func _ellipse_band(c: Vector3, a: float, b: float, y: float, w: float, mat: Material, vertical: bool) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 72
	for i in n:
		var t0 := PI * i / n - 0.12
		var t1 := PI * (i + 1) / n - 0.12
		var quad: Array[Vector3] = []
		for t in [t0, t1]:
			var p := Vector3(cos(t) * a, y, sin(t) * b)
			if vertical:
				quad.append(p)
				quad.append(p + Vector3(0, w, 0))
			else:
				var k := (a - w) / a
				var kb := (b - w) / b
				quad.append(p)
				quad.append(Vector3(cos(t) * a * k, y, sin(t) * b * kb))
		var u0 := float(i) / n
		var u1 := float(i + 1) / n
		for v in [[quad[0], Vector2(u0, 1)], [quad[1], Vector2(u0, 0)], [quad[2], Vector2(u1, 1)], [quad[2], Vector2(u1, 1)], [quad[1], Vector2(u0, 0)], [quad[3], Vector2(u1, 0)]]:
			st.set_uv(v[1])
			st.add_vertex(v[0])
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.position = c
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_room.add_child(mi)
	return mi

func _glow_line(col: Color, energy: float) -> Material:
	var k := "line" + col.to_html() + str(energy)
	if not _mats.has(k):
		_mats[k] = _line_mat(col, energy)
	return _mats[k]

## Material de tira de luz: emisivo plano, con un poco de caída en los bordes.
func _line_mat(col: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(col.r * energy, col.g * energy, col.b * energy)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if energy < 0.5:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.albedo_color = Color(col, energy)
	return m

func _ring_quad(pos: Vector3, size_m: float, mat: Material, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(size_m, size_m)
	mi.mesh = plane
	mi.material_override = mat
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	(parent if parent else _room).add_child(mi)
	return mi

func _ring_shader(col: Color, energy: float, radius := 0.62, width := 0.05, halo := 0.14, fill := 0.12, dashes := 0.0, spin := 0.0, pulse := 0.0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = RING_SHADER
	m.set_shader_parameter("color", col)
	m.set_shader_parameter("energy", energy)
	m.set_shader_parameter("radius", radius)
	m.set_shader_parameter("width", width)
	m.set_shader_parameter("halo", halo)
	m.set_shader_parameter("fill", fill)
	m.set_shader_parameter("dashes", dashes)
	m.set_shader_parameter("spin", spin)
	m.set_shader_parameter("pulse", pulse)
	return m

func _hero_ring() -> ShaderMaterial:
	return _ring_shader(Color("#FFC46B"), 0.9, 0.5, 0.025, 0.2, 0.08, 0.0, 0.0, 0.0)

## Aro de cada plataforma: neutro, el tuyo (ámbar) o listo (verde). Iguales para todos.
func _ring_mat(kind: String) -> ShaderMaterial:
	var k := "ring_" + kind
	if not _mats.has(k):
		match kind:
			"ready":
				_mats[k] = _ring_shader(GREEN, 1.6, 0.62, 0.07, 0.16, 0.22, 0.0, 0.0, 0.18)
			"local":
				_mats[k] = _ring_shader(Color("#FFB938"), 1.5, 0.62, 0.07, 0.16, 0.18, 0.0, 0.0, 0.1)
			"empty":
				_mats[k] = _ring_shader(Color("#9FB4FF"), 0.7, 0.6, 0.06, 0.05, 0.03, 18.0, 0.015, 0.0)
			_:
				_mats[k] = _ring_shader(Color("#AFC3FF"), 0.75, 0.62, 0.05, 0.12, 0.07)
	return _mats[k]

func _platform_mats() -> Dictionary:
	if not _mats.has("platform"):
		var body := StandardMaterial3D.new()
		body.albedo_color = Color("#151A30")
		body.roughness = 0.25
		body.metallic = 0.35
		var top := StandardMaterial3D.new()
		top.albedo_color = Color("#232B4F")
		top.roughness = 0.6
		var rim := StandardMaterial3D.new()
		rim.albedo_color = Color("#3A4470")
		rim.roughness = 0.2
		rim.metallic = 0.7
		_mats["platform"] = {"body": body, "top": top, "rim": rim}
	return _mats["platform"]

## Plaza libre: la plataforma apagada con un aro discontinuo que gira despacio.
func _empty_platform(pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	Seat.build_platform(n, _platform_mats())
	_ring_quad(Vector3(0, PLATFORM_H + 0.012, 0), 1.25, _ring_mat("empty"), n)
	return n

## Haces de luz falsos (volumétricos): el foco cenital y los dos contraluces.
func _beams() -> void:
	_beam(Vector3(0, 6.0, 0.4), Vector3(0, 0, 0.0), 0.25, 2.7, Color("#FFD9A8"), 0.07)
	_beam(Vector3(-5.2, 3.6, -2.2), Vector3(-1.2, 0.3, 0.2), 0.12, 1.4, Color("#3DD8FF"), 0.05)
	_beam(Vector3(5.2, 3.6, -2.2), Vector3(1.2, 0.3, 0.2), 0.12, 1.4, Color("#B26BFF"), 0.05)

func _beam(from: Vector3, to: Vector3, r0: float, r1: float, col: Color, intensity: float) -> void:
	var mi := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	var length := from.distance_to(to)
	cone.top_radius = r0
	cone.bottom_radius = r1
	cone.height = length
	cone.cap_top = false
	cone.cap_bottom = false
	cone.radial_segments = 32
	cone.rings = 1
	mi.mesh = cone
	var m := ShaderMaterial.new()
	m.shader = BEAM_SHADER
	m.set_shader_parameter("color", col)
	m.set_shader_parameter("intensity", intensity)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_room.add_child(mi)
	var dir := (to - from).normalized()
	var up := dir.cross(Vector3.RIGHT if absf(dir.x) < 0.9 else Vector3.FORWARD).normalized()
	var x := up.cross(-dir).normalized()
	mi.basis = Basis(x, -dir, up.normalized()).orthonormalized()
	mi.position = (from + to) / 2.0

## Halo suave (quad aditivo) para neones, lámparas y la ventana.
func _glow_quad(pos: Vector3, size_m: float, col: Color, energy: float, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(size_m, size_m)
	mi.mesh = q
	var m := ShaderMaterial.new()
	m.shader = GLOW_SHADER
	m.set_shader_parameter("color", col)
	m.set_shader_parameter("energy", energy)
	mi.material_override = m
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	(parent if parent else _room).add_child(mi)
	return mi

## Motas de polvo que flotan en la luz (CPU: funcionan en gl_compatibility).
func _dust() -> void:
	var p := CPUParticles3D.new()
	p.name = "Dust"
	p.amount = 36 if mobile else 80
	p.lifetime = 9.0
	p.preprocess = 9.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(5.0, 1.6, 2.2)
	p.position = Vector3(0, 1.7, -0.4)
	p.direction = Vector3(0, 1, 0)
	p.spread = 180.0
	p.gravity = Vector3(0, 0.015, 0)
	p.initial_velocity_min = 0.02
	p.initial_velocity_max = 0.08
	p.scale_amount_min = 0.4
	p.scale_amount_max = 1.0
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.2, 0.8, 1.0])
	ramp.colors = PackedColorArray([Color(1, 0.9, 0.75, 0.0), Color(1, 0.9, 0.75, 0.75), Color(1, 0.9, 0.75, 0.6), Color(1, 0.9, 0.75, 0.0)])
	p.color_ramp = ramp
	var q := QuadMesh.new()
	q.size = Vector2(0.035, 0.035)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = soft_texture()
	m.albedo_color = Color(1.6, 1.4, 1.1)
	q.material = m
	p.mesh = q
	_room.add_child(p)

func _window(c: Vector3, s: Vector2) -> void:
	var dark := _mat("frame", Color("#090C18"), 0.35, 0.3)
	_box(c + Vector3(0, 0, 0.02), Vector3(s.x + 0.26, s.y + 0.26, 0.1), dark)
	var sky := ShaderMaterial.new()
	sky.shader = EMISSIVE_SHADER
	sky.set_shader_parameter("tex", _tex_skyline())
	sky.set_shader_parameter("energy", 1.25)
	_quad(c + Vector3(0, 0, 0.075), s, sky)
	# Travesaños, alféizar y un reflejo en el cristal.
	for i in range(1, 3):
		_box(c + Vector3(-s.x / 2.0 + s.x * i / 3.0, 0, 0.09), Vector3(0.06, s.y, 0.04), dark)
	_box(c + Vector3(0, s.y * 0.5 - 0.62, 0.09), Vector3(s.x, 0.05, 0.04), dark)
	_box(c + Vector3(0, -s.y / 2.0 - 0.16, 0.14), Vector3(s.x + 0.5, 0.06, 0.26), _mat("sill", Color("#20294A"), 0.35))
	var shine := StandardMaterial3D.new()
	shine.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shine.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shine.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	shine.albedo_color = Color(0.7, 0.75, 1.0, 0.07)
	for k in [[-0.28, 0.32], [-0.12, 0.1]]:
		var streak := _quad(c + Vector3(s.x * k[0], 0, 0.1), Vector2(k[1], s.y * 1.05), shine)
		streak.rotation.z = -0.35
	# Resplandor de la ciudad en el cristal y su luz violeta en la sala.
	_glow_quad(c + Vector3(0, -0.1, 0.12), s.x * 1.5, Color("#8A6BFF"), 0.18)
	_omni(c + Vector3(-0.5, -0.2, 0.9), Color("#9C86FF"), 1.1, 4.2)

func _case_board(c: Vector3, s: Vector2) -> void:
	_box(c + Vector3(0, 0, 0.03), Vector3(s.x + 0.14, s.y + 0.14, 0.06), _mat("board_frame", Color("#3A2716"), 0.5))
	var cork := StandardMaterial3D.new()
	cork.albedo_texture = _tex_cork()
	cork.roughness = 0.95
	_quad(c + Vector3(0, 0, 0.065), s, cork)
	# Fotos de sospechosos (siluetas), notas y recortes clavados, unidos con hilo rojo.
	var pins: Array[Vector3] = []
	var colors := [Color("#F3E5AB"), Color("#F4B6A8"), Color("#E8E4DA")]
	var mug := StandardMaterial3D.new()
	mug.albedo_texture = _tex_suspect()
	mug.roughness = 0.5
	for i in 9:
		var col := i % 3
		var row := i / 3
		var p := c + Vector3(-s.x * 0.34 + col * s.x * 0.34 + _rng.randf_range(-0.08, 0.08), s.y * 0.3 - row * s.y * 0.3 + _rng.randf_range(-0.05, 0.05), 0.075)
		var photo := i in [0, 2, 4, 6, 8]
		var size := Vector2(_rng.randf_range(0.28, 0.34), _rng.randf_range(0.24, 0.3)) if photo else Vector2(_rng.randf_range(0.24, 0.3), _rng.randf_range(0.18, 0.22))
		var note := _box(p, Vector3(size.x, size.y, 0.008), _mat("note%d" % (3 if photo else i % 3), Color("#ECE8DE") if photo else colors[i % 3], 0.8))
		note.rotation.z = _rng.randf_range(-0.14, 0.14)
		if photo:
			var pic := _quad(Vector3(0, 0.018, 0.0045), Vector2(size.x * 0.84, size.y * 0.68), mug, note)
			pic.name = "Suspect"
		else:
			for li in 3:
				_box(Vector3(-size.x * 0.05, size.y * 0.22 - li * size.y * 0.2, 0.0045), Vector3(size.x * 0.7, 0.012, 0.002), _mat("ink", Color("#5B5B66"), 0.8), note)
		var pin := p + Vector3(0, size.y * 0.4, 0.02)
		_ball(pin, 0.024, _mat("pin", Color("#E23B3B"), 0.25))
		pins.append(pin)
	var thread := _mat("thread", Color("#E0302F"), 0.5)
	for pair in [[0, 1], [1, 2], [0, 4], [4, 2], [3, 4], [4, 5], [4, 8], [6, 7], [7, 8], [3, 6]]:
		_bar(pins[pair[0]], pins[pair[1]], 0.009, thread)
	# Rótulo "CASOS" en neón cian encima.
	var neon := _label("CASOS", 110, 0.0042, Color(0.55, 2.3, 2.8))
	neon.position = c + Vector3(0, s.y / 2.0 + 0.28, 0.06)
	neon.outline_size = 18
	neon.outline_modulate = Color(0.2, 0.9, 1.0, 0.22)
	_room.add_child(neon)
	_glow_quad(c + Vector3(0, s.y / 2.0 + 0.28, 0.04), 1.8, Color("#3DD8FF"), 0.35)
	_omni(c + Vector3(0, s.y / 2.0 + 0.4, 0.7), Color("#5EE7FF"), 0.8, 2.8)

## Neón principal en la pared: "BAJO SOSPECHA" con una lupa, tubo rosa y halo.
func _neon_sign(c: Vector3) -> void:
	var back := _box(c + Vector3(0, 0, -0.03), Vector3(3.1, 0.8, 0.03), _mat("sign_back", Color("#0E1020"), 0.3, 0.4))
	back.name = "SignBack"
	var tube := Color(2.6, 0.75, 1.35)
	for line in [["BAJO", 0.17, 104], ["SOSPECHA", -0.17, 104]]:
		var l := _label(line[0], line[2], 0.0034, tube)
		l.position = c + Vector3(0.0, line[1], 0.0)
		l.outline_size = 22
		l.outline_modulate = Color(1.0, 0.25, 0.55, 0.28)
		_room.add_child(l)
	# Lupa en neón ámbar.
	var lens := MeshInstance3D.new()
	var ring := TorusMesh.new()
	ring.inner_radius = 0.105
	ring.outer_radius = 0.13
	ring.rings = 32
	lens.mesh = ring
	lens.material_override = _line_mat(Color("#FFC46B"), 2.2)
	lens.rotation.x = PI / 2.0
	lens.position = c + Vector3(1.22, 0.1, 0.02)
	_room.add_child(lens)
	_bar(lens.position + Vector3(0.09, -0.09, 0), lens.position + Vector3(0.24, -0.24, 0), 0.03, lens.material_override)
	_glow_quad(c + Vector3(0.05, 0, 0.02), 4.2, Color("#FF4F8B"), 0.32).scale = Vector3(1.0, 0.45, 1.0)
	_glow_quad(lens.position + Vector3(0, 0, 0.01), 0.9, Color("#FFC46B"), 0.35)
	_omni(c + Vector3(0, -0.1, 0.8), Color("#FF5C9A"), 0.9, 3.4)

func _floor_lamp(p: Vector3) -> void:
	var metal := _mat("brass", Color("#B08D57"), 0.3, 0.8)
	_disc(p + Vector3(0, 0.02, 0), 0.16, 0.04, metal)
	_disc(p + Vector3(0, 0.8, 0), 0.015, 1.6, metal)
	var shade := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.14
	cone.bottom_radius = 0.24
	cone.height = 0.32
	shade.mesh = cone
	shade.material_override = _line_mat(Color(1.0, 0.78, 0.5), 1.4)
	shade.position = p + Vector3(0, 1.7, 0)
	_room.add_child(shade)
	_glow_quad(p + Vector3(0, 1.62, 0.25), 1.3, Color("#FFC27A"), 0.4)
	_omni(p + Vector3(0, 1.55, 0.2), Color("#FFC27A"), 1.4, 3.4)

func _plant(p: Vector3, h: float) -> void:
	var pot := _disc(p + Vector3(0, 0.22 * h, 0), 0.2 * h, 0.44 * h, _mat("pot", Color("#2A2F3E"), 0.4))
	pot.mesh.top_radius = 0.22 * h
	pot.mesh.bottom_radius = 0.16 * h
	for i in 9:
		var ang := TAU * i / 9.0 + _rng.randf() * 0.3
		var lean := 0.45 + _rng.randf() * 0.4
		var leaf := MeshInstance3D.new()
		var m := SphereMesh.new()
		m.radius = 0.09 * h
		m.height = 0.62 * h
		m.radial_segments = 12
		m.rings = 6
		leaf.mesh = m
		leaf.material_override = _mat("leaf%d" % (i % 3), Color("#2F7D4A").lightened(0.07 * (i % 3)) if i % 2 == 0 else Color("#1F5A36"), 0.55)
		var base := p + Vector3(0, 0.44 * h, 0)
		leaf.position = base + Vector3(cos(ang) * sin(lean), cos(lean), sin(ang) * sin(lean)) * 0.3 * h
		leaf.basis = Basis(Vector3(-sin(ang), 0, cos(ang)), -lean) * Basis.from_scale(Vector3(1.0, 1.0, 0.45))
		_room.add_child(leaf)

func _shelf(p: Vector3) -> void:
	var wood := _mat("shelf", Color("#3A2A20"), 0.5)
	for i in 3:
		_box(p + Vector3(0, 0.9 + i * 0.55, 0.1), Vector3(1.3, 0.04, 0.3), wood)
		for j in 5:
			if _rng.randf() < 0.75:
				var bh := _rng.randf_range(0.25, 0.38)
				var col: Color = [Color("#7F1D1D"), Color("#1E3A5F"), Color("#3F4D3A"), Color("#6B5B3E"), Color("#2E2A4F")][_rng.randi() % 5]
				_box(p + Vector3(-0.5 + j * 0.2 + _rng.randf_range(-0.04, 0.04), 0.92 + i * 0.55 + bh / 2.0, 0.1), Vector3(0.09, bh, 0.24), _mat("book%d" % j, col, 0.7))

## Archivador metálico con un cajón entreabierto y expedientes.
func _cabinet(p: Vector3) -> void:
	var steel := _mat("cabinet", Color("#2B3452"), 0.35, 0.5)
	_box(p + Vector3(0, 0.62, 0), Vector3(0.62, 1.24, 0.55), steel)
	for i in 3:
		var y := 0.24 + i * 0.4
		var open := i == 1
		_box(p + Vector3(0, y, 0.29 + (0.14 if open else 0.0)), Vector3(0.56, 0.34, 0.03), _mat("drawer", Color("#34406A"), 0.3, 0.5))
		_box(p + Vector3(0, y + 0.08, 0.32 + (0.14 if open else 0.0)), Vector3(0.16, 0.025, 0.03), _mat("handle", Color("#B08D57"), 0.3, 0.8))
		if open:
			for f in 4:
				_box(p + Vector3(-0.18 + f * 0.11, y + 0.2, 0.2), Vector3(0.02, 0.18, 0.3), _mat("file%d" % (f % 2), Color("#D9A35B") if f % 2 == 0 else Color("#E4DFD2"), 0.8))
	# Lámpara de banquero encima con su luz verde.
	_box(p + Vector3(0, 1.26, 0.05), Vector3(0.3, 0.03, 0.18), _mat("lamp_base", Color("#B08D57"), 0.3, 0.8))
	var shade := _box(p + Vector3(0, 1.48, 0.05), Vector3(0.36, 0.08, 0.14), _line_mat(Color(1.0, 0.72, 0.4), 1.2))
	shade.rotation.x = 0.2
	_glow_quad(p + Vector3(0, 1.42, 0.25), 0.8, Color("#FFB347"), 0.25)

# ── piezas y materiales ─────────────────────────────────────────────────────

func _box(pos: Vector3, s: Vector3, mat: Material, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = s
	mi.mesh = m
	mi.material_override = mat
	mi.position = pos
	(parent if parent else _room).add_child(mi)
	return mi

func _disc(pos: Vector3, r: float, h: float, mat: Material, scl := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := CylinderMesh.new()
	m.top_radius = r
	m.bottom_radius = r
	m.height = h
	m.radial_segments = 48
	mi.mesh = m
	mi.material_override = mat
	mi.position = pos
	mi.scale = scl
	_room.add_child(mi)
	return mi

func _ball(pos: Vector3, r: float, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	m.radial_segments = 12
	m.rings = 6
	mi.mesh = m
	mi.material_override = mat
	mi.position = pos
	_room.add_child(mi)
	return mi

func _capsule(pos: Vector3, r: float, h: float, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := CapsuleMesh.new()
	m.radius = r
	m.height = h
	mi.mesh = m
	mi.material_override = mat
	mi.position = pos
	_room.add_child(mi)
	return mi

func _quad(pos: Vector3, s: Vector2, mat: Material, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := QuadMesh.new()
	m.size = s
	mi.mesh = m
	mi.material_override = mat
	mi.position = pos
	(parent if parent else _room).add_child(mi)
	return mi

## Barra fina de a a b (hilo rojo, mango de la lupa).
func _bar(a: Vector3, b: Vector3, thick: float, mat: Material) -> MeshInstance3D:
	var mi := _box((a + b) / 2.0, Vector3(thick, thick, a.distance_to(b)), mat)
	mi.basis = Basis.looking_at(b - a, Vector3(0, 0, 1) if absf((b - a).normalized().z) < 0.9 else Vector3.UP)
	return mi

func _label(text: String, font_size: int, pixel: float, col: Color, font: Font = null) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font = font if font else UiPalette.heading_font()
	l.font_size = font_size
	l.pixel_size = pixel
	l.modulate = col
	l.outline_size = 0
	l.shaded = false
	l.double_sided = false
	return l

func _mat(key: String, col: Color, rough := 0.5, metal := 0.0) -> StandardMaterial3D:
	var k := key + col.to_html() + str(rough) + str(metal)
	if not _mats.has(k):
		var m := StandardMaterial3D.new()
		m.albedo_color = col
		m.roughness = rough
		m.metallic = metal
		_mats[k] = m
	return _mats[k]

func _emit(key: String, col: Color) -> StandardMaterial3D:
	var k := "emit_" + key + str(col)
	if not _mats.has(k):
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(col.r, col.g, col.b).clamp() * 0.4
		m.emission_enabled = true
		m.emission = Color(minf(col.r, 1.0), minf(col.g, 1.0), minf(col.b, 1.0))
		m.emission_energy_multiplier = maxf(maxf(col.r, col.g), col.b) * 0.9
		_mats[k] = m
	return _mats[k]

func _tex_planks(base: Color) -> ImageTexture:
	var n := 128
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	var plank_h := 16
	var tones := []
	var offsets := []
	for i in n / plank_h:
		tones.append(_rng.randf_range(-0.08, 0.08))
		offsets.append(_rng.randi() % n)
	for y in n:
		var row := y / plank_h
		for x in n:
			var t: float = tones[row]
			var c := base.lightened(t) if t > 0 else base.darkened(-t)
			c = c.darkened(0.06 * (0.5 + 0.5 * sin(x * 0.35 + y * 1.7 + row * 4.0)))
			if y % plank_h == 0 or (x + offsets[row]) % n == 0:
				c = base.darkened(0.45)
			img.set_pixel(x, y, c)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

func _tex_cork() -> ImageTexture:
	var n := 64
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	var base := Color("#7A5533")
	for y in n:
		for x in n:
			img.set_pixel(x, y, base.darkened(_rng.randf() * 0.22) if _rng.randf() < 0.5 else base.lightened(_rng.randf() * 0.06))
	return ImageTexture.create_from_image(img)

## Ciudad de noche: cielo violeta que se enciende en rosa abajo, luna y edificios con
## ventanas encendidas en dos capas.
func _tex_skyline() -> ImageTexture:
	var w := 256
	var h := 192
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	for y in h:
		var t := float(y) / h
		var col := Color("#120E33").lerp(Color("#3A2A66"), clampf(t / 0.55, 0.0, 1.0)) if t < 0.55 else Color("#3A2A66").lerp(Color("#B8607A"), (t - 0.55) / 0.45)
		img.fill_rect(Rect2i(0, y, w, 1), col * 0.85)
	for yy in range(-9, 10):
		for xx in range(-9, 10):
			if xx * xx + yy * yy <= 81 and (xx - 4) * (xx - 4) + (yy + 3) * (yy + 3) > 64:
				img.set_pixel(46 + xx, 34 + yy, Color("#F6EBC8"))
	for layer in 2:
		var x := -4
		while x < w:
			var bw := 12 + _rng.randi() % 26
			var bh := (40 + _rng.randi() % 50) if layer == 0 else (30 + _rng.randi() % 110)
			img.fill_rect(Rect2i(x, h - bh, bw, bh), Color("#2A2550") if layer == 0 else Color("#0B0F1D"))
			if layer == 1:
				for wy in range(h - bh + 5, h - 3, 7):
					for wx in range(x + 3, x + bw - 3, 5):
						if _rng.randf() < 0.33:
							img.fill_rect(Rect2i(wx, wy, 2, 3), Color(1.0, 0.82, 0.5) if _rng.randf() < 0.85 else Color(0.55, 0.85, 1.0))
			x += bw + (_rng.randi() % 8 if layer == 1 else -2 + _rng.randi() % 6)
	return ImageTexture.create_from_image(img)

## Foto de sospechoso para el tablero: silueta de cabeza y hombros sobre gris, con la
## regla de alturas detrás y una interrogación.
func _tex_suspect() -> ImageTexture:
	var w := 48
	var h := 40
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	img.fill(Color("#7C8396"))
	for y in range(4, h, 6):
		img.fill_rect(Rect2i(0, y, w, 1), Color("#8E95A8"))
	for y in h:
		for x in w:
			var dx := (x - 24.0) / 7.5
			var dy := (y - 15.0) / 8.5
			var head := dx * dx + dy * dy <= 1.0
			var sx := (x - 24.0) / 17.0
			var sy := (y - 42.0) / 15.0
			var body := sx * sx + sy * sy <= 1.0 and y > 24
			if head or body:
				img.set_pixel(x, y, Color("#262A38"))
	# "?" sencillo en blanco sobre la cabeza.
	for q in [[22, 11], [23, 10], [24, 10], [25, 10], [26, 11], [26, 12], [25, 13], [24, 14], [24, 15], [24, 18]]:
		img.set_pixel(q[0], q[1], Color("#E8E4DA"))
	return ImageTexture.create_from_image(img)

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

static var _shadow_mat: StandardMaterial3D

## Sombra de contacto suave bajo cada personaje (también sin sombras dinámicas).
static func shadow_material() -> StandardMaterial3D:
	if _shadow_mat == null:
		_shadow_mat = StandardMaterial3D.new()
		_shadow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_shadow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_shadow_mat.albedo_texture = soft_texture()
		_shadow_mat.albedo_color = Color(0, 0, 0, 0.6)
	return _shadow_mat

## Un jugador en la sala: su personaje 3D en su plataforma con el aro de luz y, encima en
## 2D, la píldora del nombre (con la marca de LISTO), la corona, el bocadillo y los
## corazones. El nodo 2D se coloca en los pies proyectados; anchor es la parte 3D.
class Seat extends Node2D:
	var slot: Dictionary = {}
	var anchor: Node3D
	var model: Plush3D
	## Compatibilidad: antes era el chibi 2D; el personaje 3D también expone skin_id.
	var chibi: Plush3D:
		get:
			return model
	var skin_id := ""
	var pill: PanelContainer
	var name_label: Label
	var crown: MenuIcon
	## Marca de LISTO: círculo verde con un check, dentro de la píldora.
	var ready_badge: PanelContainer
	var is_host := false
	var is_ready := false
	var is_local := false
	var connected := true
	var row := "back"
	var reaction := ""
	var _react_t := 0.0
	var _need: _NeedBubble
	var _built := ""
	var _pop := false
	var _ring: MeshInstance3D
	var _platform: Node3D
	var _lift := 0.0
	var _hit := Rect2()
	var _top := -100.0      # cabeza (y local, hacia arriba es negativo)
	var _mouth := -50.0
	var _half_w := 34.0
	var _yaw := 0.0
	var _t := 0.0
	var _phase := 0.0
	var _style_key := ""
	## Alto real del modelo (m, punta de las orejas incluida); se mide al construirlo.
	var _height := Plush3D.HEIGHT

	func _init() -> void:
		anchor = Node3D.new()
		anchor.name = "Seat3D"
		model = Plush3D.new()
		model.name = "Avatar"
		anchor.add_child(model)
		var shadow := MeshInstance3D.new()
		var plane := PlaneMesh.new()
		plane.size = Vector2(0.95, 0.95)
		shadow.mesh = plane
		shadow.material_override = LobbyStage.shadow_material()
		shadow.position.y = 0.004
		shadow.name = "Shadow"
		anchor.add_child(shadow)
		pill = PanelContainer.new()
		pill.name = "NamePill"
		pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var row_box := HBoxContainer.new()
		row_box.name = "Row"
		row_box.add_theme_constant_override("separation", 5)
		row_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pill.add_child(row_box)
		name_label = Label.new()
		name_label.add_theme_font_size_override("font_size", 12)
		name_label.add_theme_font_override("font", UiPalette.bold_font())
		name_label.add_theme_constant_override("outline_size", 0)
		name_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row_box.add_child(name_label)
		ready_badge = PanelContainer.new()
		ready_badge.name = "ReadyBadge"
		ready_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ready_badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var badge_style := UiPalette.flat(LobbyStage.GREEN, Color.TRANSPARENT, 0, 8, 1)
		badge_style.shadow_color = Color(LobbyStage.GREEN, 0.55)
		badge_style.shadow_size = 4
		ready_badge.add_theme_stylebox_override("panel", badge_style)
		ready_badge.tooltip_text = "LISTO"
		var check := MenuIcon.make("check", Color("#052E16"), 12)
		ready_badge.add_child(check)
		row_box.add_child(ready_badge)
		add_child(pill)
		crown = MenuIcon.make("crown", Color("#FFC94A"), 20)
		crown.name = "Crown"
		add_child(crown)
		_need = _NeedBubble.new()
		_need.name = "NeedBubble"
		_need.visible = false
		add_child(_need)
		_phase = randf() * TAU

	func _notification(what: int) -> void:
		if what == NOTIFICATION_PREDELETE and is_instance_valid(anchor):
			anchor.queue_free()

	## Plataforma redonda: cuerpo oscuro brillante, canto metálico y tapa enmoquetada.
	static func build_platform(parent: Node3D, mats: Dictionary) -> Node3D:
		var root := Node3D.new()
		root.name = "Platform"
		var h := LobbyStage.PLATFORM_H
		var body := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.43
		cyl.bottom_radius = 0.46
		cyl.height = h
		cyl.radial_segments = 40
		body.mesh = cyl
		body.material_override = mats["body"]
		body.position.y = h / 2.0
		root.add_child(body)
		var lip := MeshInstance3D.new()
		var t := TorusMesh.new()
		t.inner_radius = 0.41
		t.outer_radius = 0.44
		t.rings = 40
		lip.mesh = t
		lip.material_override = mats["rim"]
		lip.scale = Vector3(1, 0.5, 1)
		lip.position.y = h
		root.add_child(lip)
		var top := MeshInstance3D.new()
		var disc := CylinderMesh.new()
		disc.top_radius = 0.41
		disc.bottom_radius = 0.41
		disc.height = 0.006
		disc.radial_segments = 40
		top.mesh = disc
		top.material_override = mats["top"]
		top.position.y = h + 0.003
		root.add_child(top)
		parent.add_child(root)
		return root

	## Coloca la parte 3D en su plaza: plataforma, aro de luz y orientación.
	func set_slot(new_slot: Dictionary, mats: Dictionary) -> void:
		if new_slot == slot:
			return
		slot = new_slot
		var p: Vector3 = slot["pos"]
		anchor.position = p
		_lift = LobbyStage.PLATFORM_H
		model.position.y = _lift
		# Mira a la cámara, un poco hacia el centro.
		_yaw = atan2(-p.x * 0.9, 10.0 - p.z) * 0.8
		model.face(_yaw)
		if _platform == null:
			_platform = Seat.build_platform(anchor, mats)
		if _ring == null:
			_ring = MeshInstance3D.new()
			var plane := PlaneMesh.new()
			plane.size = Vector2(1.45, 1.45)
			_ring.mesh = plane
			_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_ring.name = "GlowRing"
			anchor.add_child(_ring)
		_ring.position.y = _lift + 0.012
		var shadow := anchor.get_node("Shadow") as Node3D
		shadow.position.y = _lift + 0.008
		shadow.scale = Vector3.ONE * 0.85

	func set_ring(mat: Material) -> void:
		if _ring:
			_ring.material_override = mat

	func set_connected(on: bool) -> void:
		connected = on
		model.set_alpha(1.0 if on else 0.45)
		pill.modulate.a = 1.0 if on else 0.6

	func configure(display_name: String, new_skin: String, player_ready: bool, host: bool, local: bool, seat_row: String, look := {}) -> void:
		var key := new_skin + JSON.stringify(look)
		if key != _built:
			_built = key
			skin_id = new_skin
			model.build(new_skin, look)   # cosméticos: ropa, gorra, zapatillas, mochila
			model.face(_yaw)
			model.animate(0.0, Vector3.ZERO, 0.0)
			_height = _measure_height()
		if _pop:
			_pop = false
			model.react("pop")
		elif player_ready and not is_ready and reaction == "":
			model.react("hop")
		is_ready = player_ready
		is_host = host
		is_local = local
		row = seat_row
		# Tu píldora es ámbar y lleva la flechita: sin "(tú)" para que no tape a nadie.
		name_label.text = display_name
		var style_key := "%s%s" % [local, player_ready]
		if style_key != _style_key:
			_style_key = style_key
			var st
			if local:
				st = GlassBox.make(Color("#FFD567"), Color("#F0A92A"), 10.0, 0.0)
				st.border_top = Color("#FFF1B8")
				st.border_bottom = Color("#B9781A")
				st.glow_color = Color(1.0, 0.75, 0.25, 0.35)
				st.glow_size = 6
			else:
				st = GlassBox.make(Color(0.10, 0.13, 0.24, 0.9), Color(0.04, 0.06, 0.12, 0.92), 10.0, 0.0)
				st.border_top = Color(1, 1, 1, 0.28)
				st.border_bottom = Color(1, 1, 1, 0.06)
			st.shadow_size = 6
			st.shadow_offset = Vector2(0, 2)
			st.shadow_color = Color(0, 0, 0, 0.45)
			st.content_margin_left = 9
			st.content_margin_right = 9 if not player_ready else 4
			st.content_margin_top = 3
			st.content_margin_bottom = 3
			pill.add_theme_stylebox_override("panel", st)
			name_label.add_theme_color_override("font_color", Color("#2A1A02") if local else Color("#F1F5F9"))
		crown.visible = host
		ready_badge.visible = player_ready
		_place_labels.call_deferred()

	## Punto más alto de las mallas del modelo (en su espacio), para poner el nombre justo
	## encima de la cabeza o de las orejas de cada animal.
	func _measure_height() -> float:
		if not model.is_inside_tree():
			return Plush3D.HEIGHT
		var inv := model.global_transform.affine_inverse()
		var top := 0.0
		for mi in model.find_children("*", "MeshInstance3D", true, false):
			if not (mi as MeshInstance3D).visible or mi.is_queued_for_deletion():
				continue      # la mochila / la gorra ocultas no cuentan
			var box: AABB = (inv * (mi as MeshInstance3D).global_transform) * (mi as MeshInstance3D).get_aabb()
			top = maxf(top, box.end.y)
		return clampf(top, 0.6, Plush3D.HEIGHT + 0.4) if top > 0.0 else Plush3D.HEIGHT

	func pop_in() -> void:
		_pop = true

	## Proyecta la plaza con la cámara de la sala: el nodo 2D va a los pies y se guardan
	## la altura de la cabeza, la boca y la zona que cuenta como "tocar a la mascota".
	func place(stage: LobbyStage, k: float) -> void:
		var base := anchor.position + Vector3(0, _lift, 0)
		var feet := stage.project(base)
		position = feet
		# Los de delante se ven algo más grandes (perspectiva), sin pasarse.
		var head := stage.project(base + Vector3(0, Plush3D.HEIGHT, 0))
		var px_per_m := (feet.y - head.y) / Plush3D.HEIGHT
		var s := clampf(px_per_m / maxf(150.0 * k, 1.0), 0.85, 1.25) * k
		scale = Vector2.ONE * s
		_top = (stage.project(base + Vector3(0, _height + 0.05, 0)).y - feet.y) / s
		_mouth = (stage.project(base + Vector3(0, Plush3D.MOUTH_Y, 0)).y - feet.y) / s
		_half_w = (stage.project(base + Vector3(Plush3D.HEAD_R, Plush3D.HEAD_Y, 0)).x - feet.x) / s
		var hw := Plush3D.HEAD_R + 0.02
		_hit = stage.project_box(AABB(base + Vector3(-hw, 0.0, -0.3), Vector3(hw * 2.0, _height + 0.05, 0.6)))
		_place_labels()

	func _place_labels() -> void:
		pill.reset_size()
		pill.position = Vector2(-pill.size.x / 2.0, _top - 4.0 - pill.size.y)
		crown.position = Vector2(-10, pill.position.y - 17)
		_need.position = Vector2(_half_w + 4.0, _top + 22.0)
		queue_redraw()

	## Tu plaza: una flechita ámbar bajo la píldora que apunta a tu animal.
	func _draw() -> void:
		if not is_local:
			return
		var y := pill.position.y + pill.size.y + 1.0
		var bob := sin(_t * 3.0) * 1.5
		draw_colored_polygon(PackedVector2Array([Vector2(-5, y + bob), Vector2(5, y + bob), Vector2(0, y + 5 + bob)]), Color("#F0A92A"))

	## Empieza una reacción de mascota. false si ya está con otra (las caricias seguidas
	## alargan la que está en marcha).
	func react(kind: String, force := false) -> bool:
		if not PetReactions.has_kind(kind):
			return false
		if reaction == kind and kind == "cuddle":
			_react_t = minf(_react_t, PetReactions.duration(kind) * 0.3)
			model.react(LobbyStage.MOTIONS[kind], PetReactions.duration(kind))
			return true
		if reaction != "" and reaction != "cuddle" and not force:
			return false
		reaction = kind
		_react_t = 0.0
		model.react(LobbyStage.MOTIONS.get(kind, "hop"), PetReactions.duration(kind))
		return true

	## Zona que cuenta como "tocar a la mascota" (coordenadas de la sala).
	func hit_rect() -> Rect2:
		return _hit

	func burst(kind: String) -> void:
		var b := _Burst.new()
		b.setup(kind, _top, _mouth, _half_w)
		add_child(b)

	func set_need(icon: String) -> void:
		_need.icon = icon
		_need.visible = icon != "" and reaction == ""

	func _process(delta: float) -> void:
		_t += delta
		if reaction != "":
			_react_t += delta
			if _react_t >= PetReactions.duration(reaction):
				reaction = ""
				_need.visible = _need.icon != ""
			else:
				_need.visible = false
		# Respiración en reposo y, de vez en cuando, mira a un lado y al otro.
		if is_visible_in_tree():
			if reaction == "" and not model.is_reacting():
				var look := sin(_t * 0.45 + _phase) * 0.22 * smoothstep(0.2, 0.8, absf(sin(_t * 0.17 + _phase * 0.5)))
				model.face(_yaw + look)
			model.animate(delta, Vector3.ZERO, 0.0)
			if is_local:
				queue_redraw()

## Iconos que salen de tu mascota al reaccionar: corazones o notas que suben, o su comida
## (o una gota de agua) que va hacia la boca y suelta unos brillos.
class _Burst extends Node2D:
	var _parts: Array = []   # {icon, from, to, t, life, size, delay, sway}
	var _rng := RandomNumberGenerator.new()

	func setup(kind: String, top: float, mouth: float, half_w: float) -> void:
		_rng.randomize()
		var head := Vector2(0, top * 0.78)   # a la altura de las orejas: no tapan la cara
		var lips := Vector2(0, mouth)
		if kind.begins_with("food:"):
			var icon := kind.trim_prefix("food:")
			_parts.append({"icon": icon, "from": Vector2(half_w + 12, top - 8), "to": lips, "t": 0.0, "life": 0.6, "size": 30.0, "delay": 0.0, "sway": 0.0, "shrink": true})
			for i in 4:
				_parts.append({"icon": "sparkle", "from": lips, "to": lips + Vector2(_rng.randf_range(-30, 30), _rng.randf_range(-34, -14)), "t": 0.0, "life": 0.55, "size": 12.0, "delay": 0.55 + i * 0.05, "sway": 0.0, "shrink": false})
			return
		var icon := "heart" if kind == "hearts" else "note"
		for i in (5 if kind == "hearts" else 3):
			var from := head + Vector2((half_w * 0.75 + _rng.randf_range(0, 10)) * (1 if i % 2 == 0 else -1), _rng.randf_range(-6, 6))
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

## Plaza libre: solo marca su sitio (la plataforma apagada y el aro discontinuo están en
## 3D, en ring); la lista de jugadores ya dice "Esperando…".
class _EmptySeat extends Node2D:
	var slot: Dictionary = {}
	var ring: Node3D

	func _notification(what: int) -> void:
		if what == NOTIFICATION_PREDELETE and is_instance_valid(ring):
			ring.queue_free()
