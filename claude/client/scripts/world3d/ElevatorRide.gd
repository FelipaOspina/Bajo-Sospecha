extends CanvasLayer
## Ascensor de carga: mientras empieza la partida (fase "briefing", el reparto de roles),
## todos los jugadores de la sala suben juntos en el ascensor panorámico de la torre
## hasta la planta 14, donde está NexusCore AI.
##
## La cabina es de acero cepillado, con pasamanos, luz cálida en el techo y la pared del
## fondo de cristal: detrás se ve la ciudad de noche bajando (torres con ventanas
## encendidas, farolas, estelas de coches y los forjados de la torre pasando). El
## indicador cuenta las plantas "PB → 14" con su flecha. Al llegar suena el "ding"
## (sintetizado aquí mismo: obra propia, sin muestras), la cámara se da la vuelta y las
## puertas se abren a la recepción de la oficina; los jugadores salen y la vista se
## funde con el juego de verdad.
##
## Cada jugador es su personaje 3D (HeroAvatar3D) con su skin y sus cosméticos públicos,
## en 1–3 filas según cuántos sean (hasta 12), en orden de llegada a la sala. Respiran,
## miran alrededor y de vez en cuando reaccionan (saltito, saludo, asentir...). El tuyo
## lleva el mismo aro ámbar neutro que en la sala de espera. Nunca muestra el rol: no lee
## el estado privado ("you"), y ni colores, ni posiciones, ni textos dependen del rol.
##
## Duración: cubre el briefing (llega un poco antes de que acabe); si el servidor pasa a
## la investigación antes, llega enseguida y abre las puertas sin retrasar nada. Mientras
## se ve, el teclado del jugador queda en pausa (EventBus.ui_modal_changed), igual que
## con un modal, y la vista 3D del mapa no se dibuja (World3DView.covered).
##
## Se carga por ruta (preload), sin class_name: funciona con la caché de clases vieja.

signal arrived
signal finished

const Hero3D := preload("res://scripts/world3d/HeroAvatar3D.gd")
const RING_SHADER := preload("res://shaders/lobby_glow_ring.gdshader")
const FACADE := preload("res://shaders/elevator_facade.gdshader")

const FLOORS := 14
const FLOOR_H := 3.4          # alto de planta (m)
const W := 5.6                # interior de la cabina (m): ancho (x)
const D := 6.3                #   fondo (z)
const H := 3.3                #   alto
const BACK_Z := -2.3          # pared de cristal
const FRONT_Z := 4.0          # puertas
const CZ := (BACK_Z + FRONT_Z) / 2.0
## Cámara del viaje: dentro de la cabina, arriba junto a las puertas.
const RIDE_CAM := Vector3(0.0, 2.3, FRONT_Z - 0.2)
const GLASS_Y0 := 0.3
const GLASS_Y1 := 2.5
const DOOR_W := 2.0
const DOOR_H := 2.4
const ROW_GAP := 1.05         # separación entre jugadores de una fila
const RIDE_FOV := 56.0
const STEP_H := 0.3            # escalón mirador junto al cristal (la fila de atrás)
const STEP_Z := -1.25          # borde del escalón
const BACK_FOV := 56.0

const INTRO_S := 0.45         # fundido desde negro
const OUTRO_S := 2.7          # ding + vuelta + puertas + salida y fundido
const MIN_TOTAL_S := 3.5
const MAX_TOTAL_S := 12.0
const DEFAULT_TOTAL_S := 7.5  # sin hora de fin del briefing
const SKIP_BELOW_S := 2.5     # quedaba muy poco briefing (reconexión): no se muestra
const END_EARLY_S := 0.3      # llega un pelín antes de que empiece la investigación
const HURRY_SCALE := 0.4      # el juego ya empezó: llegada y puertas rápidas
const WALK_SPEED := 1.25

const AMBER := Color("#FFB938")
const CAPTION_RIDE := "Subiendo a la planta 14"
const CAPTION_ARRIVE := "Planta 14 · NexusCore AI"
const IDLE_MOVES := ["look", "tilt", "nod", "hop", "flap", "sway", "look", "nod"]

## Escucha a GameState y arranca solo al empezar la partida (las pruebas lo apagan).
@export var auto := true

var active := false
## idle → intro → ride → arrive → doors → out → done
var stage := "idle"
## Plantas mostradas por el indicador, en orden ("PB", "1", ..., "14").
var floors_seen: Array[String] = []
## Ya se fundió con la partida (o se cortó).
var handed_over := false
var hurried := false
var mobile := false

var _vp: SubViewport
var _world: Node3D
var _rig: Node3D
var _cam: Camera3D
var _front: Node3D
var _doors: Array[Node3D] = []
var _reception: Node3D
var _actors: Node3D
var _displays: Array[Label3D] = []
var _arrows: Array[MeshInstance3D] = []
var _beacon_mat: StandardMaterial3D
var _root: Control
var _view: TextureRect
var _fade: ColorRect
var _caption: Label
var _floor_label: Label
var _arrow2d: _Arrow
var _ding: AudioStreamPlayer
var _hum: AudioStreamPlayer
var _avatars: Array = []      # {id, local, anchor, model, label, yaw, ph, next, walk}
var _mats := {}
var _rng := RandomNumberGenerator.new()
var _t := 0.0
var _total := DEFAULT_TOTAL_S
var _ride_s := 5.0
var _outro_s := OUTRO_S
var _arrive_at := 0.0
var _floor := -1
var _reversed := false
var _ride_cam := Transform3D.IDENTITY
var _locked := false
var _covered := false
var _played := false
var _vp_px := Vector2i.ZERO
var _sfx_task := -1

static var _ding_stream: AudioStreamWAV
static var _hum_stream: AudioStreamWAV
static var _brushed: ImageTexture
static var _soft: GradientTexture2D

func _ready() -> void:
	layer = 16
	visible = false
	mobile = OS.has_feature("mobile") or OS.has_feature("web")
	_rng.seed = 1414
	_build_overlay()
	set_process(false)
	if auto:
		GameState.snapshot_applied.connect(func(s: Dictionary) -> void: _on_phase(str(s.get("phase", ""))))
		EventBus.phase_changed.connect(func(phase: String, ends_at: int) -> void: _on_phase(phase, ends_at))

# ── cuándo se ve ────────────────────────────────────────────────────────────────

func _on_phase(phase: String, ends_at := -1) -> void:
	if phase == "briefing":
		if active or _played:
			return
		_played = true
		# El tutorial (servidor local) tiene su propia presentación: ahí no hay ascensor.
		if Network.get("local_server") != null:
			return
		var ends = ends_at if ends_at > 0 else GameState.snapshot.get("phaseEndsAt")
		var total := DEFAULT_TOTAL_S
		if ends != null and float(ends) > 0.0:
			total = (float(ends) - Network.server_time_ms()) / 1000.0 - END_EARLY_S
		if total < SKIP_BELOW_S:
			return
		play(GameState.players(), GameState.local_player_id(), clampf(total, MIN_TOTAL_S, MAX_TOTAL_S))
	else:
		if active:
			arrive_now()
		if phase in ["", "lobby"]:
			_played = false

## Empieza el viaje. players: [{id, name, skinId, look, connected}] (estado público).
func play(players: Array, local_id: String, total_s := DEFAULT_TOTAL_S) -> void:
	_free_world()
	_build_world()
	active = true
	handed_over = false
	hurried = false
	stage = "intro"
	floors_seen.clear()
	_floor = -1
	_t = 0.0
	_reversed = false
	_total = maxf(total_s, 1.5)
	_outro_s = minf(OUTRO_S, _total * 0.42)
	_ride_s = maxf(_total - INTRO_S - _outro_s, 0.6)
	_arrive_at = INTRO_S + _ride_s
	_rig.position = Vector3.ZERO
	_spawn_avatars(players, local_id)
	visible = true
	_root.modulate.a = 1.0
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_fade.color.a = 1.0
	_caption.text = CAPTION_RIDE
	_sync_viewport_size(true)
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_set_covered(true)
	_set_locked(true)
	_update_floor()
	_prepare_sfx()
	_hum.volume_db = -60.0
	set_process(true)

## El juego ya está listo: llega ya y abre las puertas deprisa (no retrasa la partida).
func arrive_now() -> void:
	if not active:
		return
	hurried = true
	_set_locked(false)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if stage in ["intro", "ride"]:
		_outro_s = OUTRO_S * HURRY_SCALE
		_arrive_at = _t
		_arrive()
	else:
		# Ya en la llegada: lo que quede, a la velocidad rápida.
		var k := _outro_s / OUTRO_S
		var done := (_t - _arrive_at) / k
		_outro_s = OUTRO_S * HURRY_SCALE
		_arrive_at = _t - done * HURRY_SCALE

func is_active() -> bool:
	return active

func avatar_count() -> int:
	return _avatars.size()

func avatar_ids() -> Array:
	return _avatars.map(func(a): return a["id"])

func local_avatar_id() -> String:
	for a in _avatars:
		if a["local"]:
			return a["id"]
	return ""

## Posición de cada jugador en la cabina (metros, relativa a la cabina).
func slot_positions() -> Dictionary:
	var out := {}
	for a in _avatars:
		out[a["id"]] = (a["anchor"] as Node3D).position
	return out

func avatar_model(id: String) -> Node3D:
	for a in _avatars:
		if a["id"] == id:
			return a["model"]
	return null

func floor_text() -> String:
	return _floor_name(maxi(_floor, 0))

## Todos los textos que enseña (indicadores, nombres, rótulos y la leyenda).
func visible_texts() -> Array:
	var out: Array = []
	if _world:
		for n in _world.find_children("*", "Label3D", true, false):
			out.append((n as Label3D).text)
	for n in _root.find_children("*", "Label", true, false):
		out.append((n as Label).text)
	return out

func camera() -> Camera3D:
	return _cam

func viewport_3d() -> SubViewport:
	return _vp

## Duración prevista del viaje (s) y cuándo llega (s desde que empezó).
func timing() -> Dictionary:
	return {"total": _total, "ride": _ride_s, "arrive_at": _arrive_at, "outro": _outro_s, "t": _t}

## Para capturas: salta a un momento del viaje (s desde el principio).
func seek(t: float) -> void:
	if not active:
		return
	_t = t - 0.0001
	_process(0.0001)

# ── reloj ───────────────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	if not active:
		return
	_t += delta
	if _sfx_task >= 0 and WorkerThreadPool.is_task_completed(_sfx_task):
		WorkerThreadPool.wait_for_task_completion(_sfx_task)
		_sfx_task = -1
	_sync_viewport_size(false)
	if stage in ["intro", "ride"]:
		var u := clampf((_t - INTRO_S) / maxf(_ride_s, 0.01), 0.0, 1.0)
		_rig.position.y = FLOORS * FLOOR_H * _ride_ease(u)
		_fade.color.a = 1.0 - clampf(_t / INTRO_S, 0.0, 1.0)
		stage = "intro" if _t < INTRO_S else "ride"
		_hum.volume_db = linear_to_db(maxf(0.0001, 0.22 * clampf(_t / 0.8, 0.0, 1.0)))
		if not _hum.playing and _hum_stream and _sfx_task < 0:
			_hum.stream = _hum_stream
			_hum.play()
		if _t >= _arrive_at:
			_arrive()
	if stage in ["arrive", "doors", "out"]:
		_outro(_t - _arrive_at)
	if not active:
		return
	_update_floor()
	_tick_avatars(delta)
	_tick_camera()
	if _beacon_mat:
		_beacon_mat.emission_energy_multiplier = 0.3 + 3.2 * maxf(0.0, sin(_t * 3.4))
	for a in _arrows:
		a.visible = stage in ["intro", "ride"] and fmod(_t, 0.8) < 0.55
	if _arrow2d:
		_arrow2d.blink = 1.0 if stage not in ["intro", "ride"] else (1.0 if fmod(_t, 0.8) < 0.55 else 0.25)
		_arrow2d.queue_redraw()

## Arranca suave, va rápido y frena suave (como un ascensor de verdad).
static func _ride_ease(u: float) -> float:
	return 0.5 - 0.5 * cos(PI * u)

func _arrive() -> void:
	stage = "arrive"
	_rig.position.y = FLOORS * FLOOR_H
	_fade.color.a = 0.0
	_update_floor()
	_caption.text = CAPTION_ARRIVE
	if _ding_stream:
		_ding.stream = _ding_stream
		_ding.play()
	_hum.stop()
	if _reception:
		_reception.visible = true
	for i in _avatars.size():
		_avatars[i]["next"] = 0.08 + 0.05 * float(i % 4)
		_avatars[i]["arrive_hop"] = true
	arrived.emit()

## Tras el ding (ta = s desde la llegada; k escala todo si hay prisa).
func _outro(ta: float) -> void:
	var k := _outro_s / OUTRO_S
	var cut := 0.55 * k
	var dip := 0.16 * k
	_fade.color.a = clampf(1.0 - absf(ta - cut) / dip, 0.0, 1.0)
	if ta >= cut and not _reversed:
		_reverse()
	if _reversed:
		stage = "doors"
		var u := clampf((ta - 0.78 * k) / (0.9 * k), 0.0, 1.0)
		_set_doors(u * u * (3.0 - 2.0 * u))
	# Salen hacia las puertas: primero la fila de delante, luego las de atrás.
	for a in _avatars:
		var base: Vector3 = a["base"]
		var w := ta - (0.6 + (0.0 if base.z > 0.0 else (0.22 if base.z > STEP_Z else 0.45))) * k
		if w > 0.0:
			a["walk"] = true
			var z := base.z + WALK_SPEED * w
			(a["anchor"] as Node3D).position = Vector3(base.x, base.y if z < STEP_Z else 0.0, z)
	var fade0 := 1.85 * k
	if ta >= fade0:
		stage = "out"
		_set_covered(false)
		_set_locked(false)
		_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_root.modulate.a = 1.0 - clampf((ta - fade0) / (OUTRO_S * k - fade0), 0.0, 1.0)
	if ta >= OUTRO_S * k:
		_finish()

## Corte al contraplano: desde el cristal, mirando a las puertas por encima de todos.
func _reverse() -> void:
	_reversed = true
	_front.visible = true
	for a in _avatars:
		(a["label"] as Node3D).visible = false
		var ring = a.get("ring")
		if ring:
			(ring as Node3D).visible = false
	_cam.fov = BACK_FOV
	var pos := Vector3(0.0, 2.6, -2.0)
	_cam.transform = Transform3D(Basis.IDENTITY, pos).looking_at(Vector3(0.0, 0.95, FRONT_Z + 2.0), Vector3.UP)

func _finish() -> void:
	active = false
	stage = "done"
	handed_over = true
	set_process(false)
	_set_covered(false)
	_set_locked(false)
	_hum.stop()
	visible = false
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_free_world()
	finished.emit()

func _set_locked(on: bool) -> void:
	if on == _locked:
		return
	_locked = on
	EventBus.ui_modal_changed.emit(on)

## Mientras la cabina tapa la pantalla, la vista 3D del mapa no se dibuja.
func _set_covered(on: bool) -> void:
	_covered = on
	if not is_inside_tree():
		return
	for v in get_tree().get_nodes_in_group("world3d"):
		if "covered" in v:
			v.covered = on

func _exit_tree() -> void:
	if _sfx_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_sfx_task)
		_sfx_task = -1
	if _covered:
		_set_covered(false)
	if _locked:
		_set_locked(false)

# ── indicador de planta ─────────────────────────────────────────────────────────

static func _floor_name(f: int) -> String:
	return "PB" if f <= 0 else str(f)

func _update_floor() -> void:
	var f := clampi(roundi(_rig.position.y / FLOOR_H), 0, FLOORS)
	if stage in ["intro", "ride"]:
		f = mini(f, FLOORS - 1) if _rig.position.y < FLOORS * FLOOR_H - 0.05 else FLOORS
	if f == _floor:
		return
	# Al saltar (prisa), el indicador pasa igualmente por cada planta.
	var from := _floor + 1 if _floor >= 0 else f
	for i in range(from, f + 1):
		floors_seen.append(_floor_name(i))
	_floor = f
	var txt := _floor_name(f)
	for d in _displays:
		d.text = txt
	_floor_label.text = txt

# ── jugadores ───────────────────────────────────────────────────────────────────

## Plazas: 1 fila hasta 4, 2 hasta 8 y 3 hasta 12; las de atrás van más llenas y al
## tresbolillo para que se vean todas las caras. Solo depende del orden de llegada.
static func layout(n: int) -> Array:
	var out: Array = []
	if n <= 0:
		return out
	var rows := 1 if n <= 4 else (2 if n <= 8 else 3)
	var counts: Array[int] = []
	for r in rows:
		counts.append(n / rows)
	for r in n % rows:
		counts[r] += 1   # la fila 0 es la de atrás
	var zs: Array = [[-0.6], [-1.8, -0.4], [-1.85, -0.75, 0.3]][rows - 1]
	for r in rows:
		var c: int = counts[r]
		var stagger := 0.0 if rows == 1 else (ROW_GAP * 0.25 if r % 2 == 0 else -ROW_GAP * 0.25)
		for i in c:
			var x := (float(i) - (c - 1) / 2.0) * ROW_GAP + stagger
			var z: float = zs[r]
			out.append(Vector3(x, STEP_H if z < STEP_Z else 0.0, z))
	# Orden de llegada: primero la fila de delante (se ven mejor), luego las de atrás.
	out.sort_custom(func(a: Vector3, b: Vector3) -> bool: return a.z > b.z if absf(a.z - b.z) > 0.01 else a.x < b.x)
	return out

func _spawn_avatars(players: Array, local_id: String) -> void:
	_avatars.clear()
	var list := players.filter(func(p): return p is Dictionary).slice(0, 12)
	var slots := layout(list.size())
	for i in list.size():
		var p: Dictionary = list[i]
		var id := str(p.get("id", ""))
		var anchor := Node3D.new()
		anchor.name = "P%d" % i
		var jitter := Vector3(sin(i * 12.9898) * 0.07, 0.0, cos(i * 78.233) * 0.06)
		anchor.position = slots[i] + jitter
		_actors.add_child(anchor)
		var model := Hero3D.new()
		model.name = "Avatar"
		anchor.add_child(model)
		var skin := str(p.get("skinId", ""))
		if skin == "":
			skin = SkinCatalog.fallback_for(id)
		var look: Dictionary = p.get("look") if p.get("look") is Dictionary else {}
		model.build(skin, look)
		var yaw := atan2(-anchor.position.x * 0.5, 8.0) + sin(i * 4.1) * 0.12
		model.face(yaw)
		model.animate(0.0, Vector3.ZERO, 0.0)
		if not bool(p.get("connected", true)):
			model.set_alpha(0.45)
		var shadow := MeshInstance3D.new()
		var plane := PlaneMesh.new()
		plane.size = Vector2(0.95, 0.95)
		shadow.mesh = plane
		shadow.material_override = _shadow_mat()
		shadow.position.y = 0.006
		shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		anchor.add_child(shadow)
		var entry := {"id": id, "local": id == local_id and id != "", "anchor": anchor, "model": model, "base": anchor.position,
			"yaw": yaw, "ph": float(i) * 1.7, "next": 0.9 + fmod(float(i) * 0.61, 2.2), "walk": false, "arrive_hop": false}
		if entry["local"]:
			# El mismo aro ámbar neutro que en la sala de espera: "este eres tú".
			var ring := MeshInstance3D.new()
			var rp := PlaneMesh.new()
			rp.size = Vector2(1.35, 1.35)
			ring.mesh = rp
			ring.name = "LocalRing"
			ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			ring.material_override = _local_ring_mat()
			ring.position.y = 0.012
			anchor.add_child(ring)
			entry["ring"] = ring
		var label := Label3D.new()
		label.name = "Name"
		var nm := str(p.get("name", ""))
		label.text = nm if nm.length() <= 14 else nm.substr(0, 13) + "…"
		label.font = UiPalette.bold_font()
		label.font_size = 34
		label.pixel_size = 0.004
		label.outline_size = 12
		label.outline_modulate = Color(0.02, 0.03, 0.07, 0.85)
		label.modulate = Color(1, 1, 1, 0.92)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.render_priority = 2
		label.outline_render_priority = 1
		label.position = Vector3(0, Hero3D.HEIGHT - 0.02, 0)
		anchor.add_child(label)
		entry["label"] = label
		_avatars.append(entry)

func _tick_avatars(delta: float) -> void:
	for a in _avatars:
		var m = a["model"]
		var anchor: Node3D = a["anchor"]
		if a["walk"]:
			m.animate(delta, Vector3(0, 0, 1), 1.0)
			continue
		a["next"] -= delta
		if a["next"] <= 0.0:
			if a["arrive_hop"]:
				a["arrive_hop"] = false
				m.react("hop")
				a["next"] = 9.0
			elif stage in ["intro", "ride"]:
				m.react(IDLE_MOVES[_rng.randi() % IDLE_MOVES.size()])
				a["next"] = _rng.randf_range(1.8, 4.2)
		# Mira alrededor (la ciudad, los demás) sin moverse del sitio.
		m.face(a["yaw"] + sin(_t * 0.55 + a["ph"]) * 0.22)
		m.animate(delta, Vector3.ZERO, 0.0)

# ── cámara ──────────────────────────────────────────────────────────────────────

func _sync_viewport_size(force: bool) -> void:
	var px := Vector2i(get_window().size) if is_inside_tree() else Vector2i(1280, 720)
	if mobile:
		px = Vector2i(Vector2(px) * 0.75)
	px = Vector2i(maxi(px.x, 64), maxi(px.y, 64))
	if px != _vp_px or force:
		_vp_px = px
		_vp.size = px
		_fit_ride_camera()

## Encuadra a todos (como LobbyStage): ajusta la distancia y desplaza la cámara en su
## plano hasta que la caja de las plazas (con hueco para los nombres) llena el centro.
func _fit_ride_camera() -> void:
	if _cam == null:
		return
	var box := AABB(Vector3(-1.5, 0.0, -0.9), Vector3(3.0, 1.9, 1.4))
	for a in _avatars:
		var p: Vector3 = (a["anchor"] as Node3D).position
		box = box.merge(AABB(p + Vector3(-0.6, 0.0, -0.4), Vector3(1.2, Hero3D.HEIGHT + 0.3, 0.8)))
	var vs := Vector2(_vp.size)
	var focus := Rect2(vs.x * 0.05, vs.y * 0.17, vs.x * 0.9, vs.y * 0.68)
	var rig_xf := _rig.transform
	_rig.transform = Transform3D.IDENTITY
	# La cámara no sale de la cabina: se apunta al centro de la caja y se abre o se
	# cierra el objetivo hasta que todos caben en el hueco central.
	var target := box.get_center() + Vector3(0.0, 0.1, 0.0)
	var fov := RIDE_FOV
	for i in 12:
		_cam.fov = fov
		_cam.transform = Transform3D(Basis.IDENTITY, RIDE_CAM).looking_at(target, Vector3.UP)
		var r := _project_box(box)
		if r.size.x <= 1.0 or r.size.y <= 1.0:
			break
		var ratio := maxf(r.size.x / focus.size.x, r.size.y / focus.size.y)
		fov = clampf(rad_to_deg(2.0 * atan(tan(deg_to_rad(fov) / 2.0) * ratio)), 34.0, 84.0)
		# Desplaza el punto de mira para centrar la caja en el hueco.
		var dd := r.get_center() - focus.get_center()
		var m_per_px := 2.0 * target.distance_to(RIDE_CAM) * tan(deg_to_rad(fov) / 2.0) / maxf(vs.y, 1.0)
		target += (_cam.transform.basis.x * dd.x - _cam.transform.basis.y * dd.y) * m_per_px * 0.8
	_cam.fov = fov
	_ride_cam = Transform3D(Basis.IDENTITY, RIDE_CAM).looking_at(target, Vector3.UP)
	_rig.transform = rig_xf
	if not _reversed:
		_cam.transform = _ride_cam

func _project_box(box: AABB) -> Rect2:
	var r := Rect2()
	for i in 8:
		var p := _cam.unproject_position(box.get_endpoint(i))
		r = Rect2(p, Vector2.ZERO) if i == 0 else r.expand(p)
	return r

func _tick_camera() -> void:
	if _reversed:
		return
	# Deriva lenta y un temblor mínimo al arrancar y al frenar.
	var u := clampf((_t - INTRO_S) / maxf(_ride_s, 0.01), 0.0, 1.0)
	var jolt := (exp(-u * 18.0) + exp(-(1.0 - u) * 18.0)) * (1.0 if stage == "ride" else 0.0)
	var off := Vector3(sin(_t * 0.37) * 0.06, sin(_t * 0.29 + 1.0) * 0.03 + sin(_t * 37.0) * 0.006 * jolt, 0.0)
	var rot := Basis.from_euler(Vector3(0.0, deg_to_rad(sin(_t * 0.23) * 0.6), 0.0))
	_cam.transform = Transform3D(_ride_cam.basis * rot, _ride_cam.origin + off)

# ── escena 3D ───────────────────────────────────────────────────────────────────

func _free_world() -> void:
	_avatars.clear()
	_displays.clear()
	_arrows.clear()
	_doors.clear()
	_beacon_mat = null
	if _world:
		_world.queue_free()
		_world = null
	_reception = null

func _build_world() -> void:
	_world = Node3D.new()
	_world.name = "Elevator"
	_vp.add_child(_world)
	_environment()
	_build_city()
	_rig = Node3D.new()
	_rig.name = "Rig"
	_world.add_child(_rig)
	_build_cabin()
	_actors = Node3D.new()
	_actors.name = "Riders"
	_rig.add_child(_actors)
	_cam = Camera3D.new()
	_cam.name = "Camera"
	_cam.fov = RIDE_FOV
	_cam.near = 0.1
	_cam.far = 600.0
	_cam.current = true
	_rig.add_child(_cam)
	_build_reception()
	_set_doors(0.0)
	_front.visible = false

func _environment() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	var sky := ProceduralSkyMaterial.new()
	sky.sky_top_color = Color("#03050F")
	sky.sky_horizon_color = Color("#231D45")
	sky.sky_curve = 0.12
	sky.ground_bottom_color = Color("#04050A")
	sky.ground_horizon_color = Color("#231D45")
	sky.sun_angle_max = 1.6
	sky.sun_curve = 0.05
	var s := Sky.new()
	s.sky_material = sky
	e.background_mode = Environment.BG_SKY
	e.sky = s
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("#6E7CB0")
	e.ambient_light_energy = 0.45
	e.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	e.tonemap_exposure = 1.05
	e.tonemap_white = 6.0
	if RenderingServer.get_rendering_device() == null:   # OpenGL (compatibilidad)
		e.tonemap_exposure = 0.62
	e.glow_enabled = not mobile
	e.glow_intensity = 0.6
	e.glow_bloom = 0.02
	e.glow_hdr_threshold = 1.1
	e.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	e.fog_enabled = true
	e.fog_light_color = Color("#1A2850")
	e.fog_light_energy = 0.9
	e.fog_density = 0.0045
	e.fog_sky_affect = 0.0
	e.adjustment_enabled = true
	e.adjustment_contrast = 1.06
	e.adjustment_saturation = 1.1
	env.environment = e
	_world.add_child(env)
	# Luna: contraluz azul por el cristal (y su disco en el cielo).
	var moon := DirectionalLight3D.new()
	moon.name = "Moon"
	moon.light_color = Color("#A9BCFF")
	moon.light_energy = 0.35
	moon.shadow_enabled = false
	_world.add_child(moon)
	moon.look_at_from_position(Vector3.ZERO, Vector3(-0.35, -0.3, 1.0), Vector3.UP)

# ── la ciudad (estática: la cabina sube por delante) ────────────────────────────

func _build_city() -> void:
	var city := Node3D.new()
	city.name = "City"
	_world.add_child(city)
	var rng := RandomNumberGenerator.new()
	rng.seed = 2614
	# Suelo y calles.
	var ground := MeshInstance3D.new()
	var gp := PlaneMesh.new()
	gp.size = Vector2(900, 900)
	ground.mesh = gp
	ground.position = Vector3(0, -0.3, -300)
	ground.material_override = _mat("asphalt", Color("#0A0C13"), 0.92)
	city.add_child(ground)
	var facades: Array[ShaderMaterial] = []
	for i in 6:
		var m := ShaderMaterial.new()
		m.shader = FACADE
		m.set_shader_parameter("seed", float(i) * 13.7)
		m.set_shader_parameter("lit", 0.28 + 0.07 * float(i))
		m.set_shader_parameter("wall_color", Color("#0B0E16").lerp(Color("#1A1C2A"), float(i) / 5.0))
		m.set_shader_parameter("cell", Vector2(1.2 + 0.15 * float(i % 3), 3.0 + 0.3 * float(i % 2)))
		facades.append(m)
	_beacon_mat = StandardMaterial3D.new()
	_beacon_mat.albedo_color = Color("#300406")
	_beacon_mat.emission_enabled = true
	_beacon_mat.emission = Color("#FF2A2A")
	var block := 36.0
	var lamps: Array[Vector3] = []
	var nx := 5 if mobile else 7
	var nz := 7 if mobile else 9
	for gx in range(-nx, nx + 1):
		for gz in range(-nz, 1):
			var cx := gx * block
			var cz := gz * block - 16.0
			if gz == 0 and absi(gx) <= 0:
				continue   # el hueco delante del cristal
			var towers := 1 + int(rng.randf() < 0.45)
			for k in towers:
				var w := rng.randf_range(9.0, 18.0)
				var d := rng.randf_range(9.0, 18.0)
				var h := rng.randf_range(12.0, 46.0)
				if rng.randf() < 0.28:
					h = rng.randf_range(55.0, 125.0)
				var off := Vector2(rng.randf_range(-6.0, 6.0), rng.randf_range(-6.0, 6.0)) if towers == 1 \
					else Vector2((-7.0 if k == 0 else 7.0), rng.randf_range(-5.0, 5.0))
				var mi := MeshInstance3D.new()
				var bm := BoxMesh.new()
				bm.size = Vector3(w * (0.6 if towers == 2 else 1.0), h, d)
				mi.mesh = bm
				mi.position = Vector3(cx + off.x, h / 2.0 - 0.3, cz + off.y)
				mi.material_override = facades[rng.randi() % facades.size()]
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				city.add_child(mi)
				if h > 60.0:
					var b := MeshInstance3D.new()
					var sm := SphereMesh.new()
					sm.radius = 0.45
					sm.height = 0.9
					sm.radial_segments = 8
					sm.rings = 4
					b.mesh = sm
					b.material_override = _beacon_mat
					b.position = mi.position + Vector3(0, h / 2.0 + 0.6, 0)
					city.add_child(b)
			# Farolas a lo largo de las dos calles de esta manzana.
			for j in 4:
				lamps.append(Vector3(cx - block / 2.0 + 2.0, 0.6, cz - block / 2.0 + j * block / 4.0))
				lamps.append(Vector3(cx - block / 2.0 + j * block / 4.0, 0.6, cz - block / 2.0 + 2.0))
	_multimesh(city, lamps, Vector3(0.5, 0.5, 0.5), Color("#FFB45C"), 4.0, true)
	# Estelas de coches (rojas y blancas) en algunas calles.
	var reds: Array[Vector3] = []
	var whites: Array[Vector3] = []
	for i in 140:
		var along := rng.randf_range(-nx * block, nx * block)
		var street := rng.randi_range(-nz, 0) * block - 16.0 - block / 2.0 + 4.0
		(reds if i % 2 == 0 else whites).append(Vector3(along, 0.25, street + (0.0 if i % 2 == 0 else 2.6)))
	_multimesh(city, reds, Vector3(5.0, 0.18, 0.35), Color("#FF3B3B"), 3.0, false)
	_multimesh(city, whites, Vector3(5.0, 0.18, 0.35), Color("#FFF1D6"), 3.0, false)
	# La estructura de la torre por fuera del cristal: guías y forjados que pasan.
	var steel := _mat("tower_steel", Color("#1B1F29"), 0.45, 0.6)
	for k in FLOORS + 3:
		var slab := MeshInstance3D.new()
		var sb := BoxMesh.new()
		sb.size = Vector3(W + 3.0, 0.42, 0.9)
		slab.mesh = sb
		slab.material_override = steel
		slab.position = Vector3(0, k * FLOOR_H - 0.25, BACK_Z - 1.1)
		city.add_child(slab)
		var strip := MeshInstance3D.new()
		var stb := BoxMesh.new()
		stb.size = Vector3(W + 3.0, 0.05, 0.05)
		strip.mesh = stb
		strip.material_override = _emit("strip_cool", Color("#7FB4FF"), 2.0)
		strip.position = Vector3(0, k * FLOOR_H - 0.06, BACK_Z - 0.62)
		city.add_child(strip)
	for sx in [-1.0, 1.0]:
		var rail := MeshInstance3D.new()
		var rb := BoxMesh.new()
		rb.size = Vector3(0.28, (FLOORS + 3) * FLOOR_H, 0.28)
		rail.mesh = rb
		rail.material_override = steel
		rail.position = Vector3(sx * (W / 2.0 + 0.9), (FLOORS + 3) * FLOOR_H / 2.0 - 1.0, BACK_Z - 0.75)
		city.add_child(rail)

func _multimesh(parent: Node3D, points: Array[Vector3], size: Vector3, col: Color, energy: float, sphere: bool) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	if sphere:
		var sm := SphereMesh.new()
		sm.radius = size.x / 2.0
		sm.height = size.y
		sm.radial_segments = 6
		sm.rings = 3
		mm.mesh = sm
	else:
		var bm := BoxMesh.new()
		bm.size = size
		mm.mesh = bm
	mm.instance_count = points.size()
	for i in points.size():
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, points[i]))
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = _emit("mm_%s" % col.to_html(), col, energy)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)

# ── la cabina ───────────────────────────────────────────────────────────────────

func _build_cabin() -> void:
	var cab := Node3D.new()
	cab.name = "Cabin"
	_rig.add_child(cab)
	var metal := _metal("brushed", Color("#C9CED6"), 0.38)
	var dark_metal := _metal("dark", Color("#3A3F4A"), 0.4)
	var floor_mat := _mat("floor", Color("#3B3631"), 0.3, 0.05)
	# Suelo pulido con su tira de luz alrededor.
	_box(cab, Vector3(0, -0.06, CZ), Vector3(W + 0.2, 0.12, D + 0.2), floor_mat)
	# Escalón mirador junto al cristal, con su canto de luz.
	var step_d := STEP_Z - BACK_Z
	_box(cab, Vector3(0, STEP_H / 2.0, (BACK_Z + STEP_Z) / 2.0), Vector3(W, STEP_H, step_d), _mat("step", Color("#2E2A27"), 0.35, 0.05))
	_box(cab, Vector3(0, STEP_H - 0.012, STEP_Z - 0.02), Vector3(W - 0.1, 0.02, 0.04), _emit("led_warm", Color("#FFD9A8"), 2.2))
	var led := _emit("led_warm", Color("#FFD9A8"), 2.2)
	for sx in [-1.0, 1.0]:
		_box(cab, Vector3(sx * (W / 2.0 - 0.06), 0.005, CZ), Vector3(0.03, 0.01, D - 0.2), led)
	_box(cab, Vector3(0, 0.005, BACK_Z + 0.06), Vector3(W - 0.2, 0.01, 0.03), led)
	# Paredes laterales de acero cepillado con juntas verticales y zócalo oscuro.
	for sx in [-1.0, 1.0]:
		var x: float = sx * (W / 2.0 + 0.05)
		_box(cab, Vector3(x, H / 2.0, CZ), Vector3(0.1, H, D + 0.2), metal)
		_box(cab, Vector3(x - sx * 0.055, 0.09, CZ), Vector3(0.012, 0.18, D), dark_metal)
		for j in 3:
			var z := BACK_Z + (j + 1) * D / 4.0
			_box(cab, Vector3(x - sx * 0.052, H / 2.0, z), Vector3(0.006, H - 0.1, 0.014), dark_metal)
		# Pasamanos con sus soportes.
		var rx: float = sx * (W / 2.0 - 0.08)
		_bar(cab, Vector3(rx, 0.95, BACK_Z + 0.25), Vector3(rx, 0.95, FRONT_Z - 0.45), 0.028, _metal("rail", Color("#E4E7EC"), 0.18))
		for j in 3:
			var z2 := lerpf(BACK_Z + 0.5, FRONT_Z - 0.6, j / 2.0)
			_bar(cab, Vector3(rx, 0.95, z2), Vector3(sx * (W / 2.0), 0.95, z2), 0.014, dark_metal)
	# Fondo: zócalo, cristal de suelo a casi techo con montantes, y el dintel con el indicador.
	_box(cab, Vector3(0, GLASS_Y0 / 2.0, BACK_Z - 0.05), Vector3(W + 0.2, GLASS_Y0, 0.1), metal)
	_box(cab, Vector3(0, (GLASS_Y1 + H) / 2.0, BACK_Z - 0.05), Vector3(W + 0.2, H - GLASS_Y1, 0.1), metal)
	var glass := MeshInstance3D.new()
	var gq := QuadMesh.new()
	gq.size = Vector2(W, GLASS_Y1 - GLASS_Y0)
	glass.mesh = gq
	glass.position = Vector3(0, (GLASS_Y0 + GLASS_Y1) / 2.0, BACK_Z - 0.04)
	glass.material_override = _glass_mat()
	glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	cab.add_child(glass)
	for mx in [-W / 6.0, W / 6.0]:
		_box(cab, Vector3(mx, (GLASS_Y0 + GLASS_Y1) / 2.0, BACK_Z - 0.03), Vector3(0.05, GLASS_Y1 - GLASS_Y0, 0.06), dark_metal)
	_bar(cab, Vector3(-W / 2.0 + 0.2, 1.2, BACK_Z + 0.12), Vector3(W / 2.0 - 0.2, 1.2, BACK_Z + 0.12), 0.028, _metal("rail", Color("#E4E7EC"), 0.18))
	_display(cab, Vector3(0, (GLASS_Y1 + H) / 2.0, BACK_Z + 0.005), 0.0)
	# Techo oscuro con un gran panel de luz cálida y focos.
	_box(cab, Vector3(0, H + 0.05, CZ), Vector3(W + 0.2, 0.1, D + 0.2), dark_metal)
	_box(cab, Vector3(0, H - 0.012, CZ - 0.2), Vector3(W - 1.4, 0.024, D - 2.0), _emit("ceiling", Color("#FFE4BE"), 0.85))
	for dx in [-W / 2.0 + 0.4, W / 2.0 - 0.4]:
		for dz in [CZ - 1.8, CZ, CZ + 1.8]:
			var spot := MeshInstance3D.new()
			var cy := CylinderMesh.new()
			cy.top_radius = 0.06
			cy.bottom_radius = 0.06
			cy.height = 0.01
			cy.radial_segments = 12
			spot.mesh = cy
			spot.material_override = _emit("downlight", Color("#FFE9C9"), 3.0)
			spot.position = Vector3(dx, H - 0.006, dz)
			cab.add_child(spot)
	var key := SpotLight3D.new()
	key.name = "CeilingLight"
	key.light_color = Color("#FFD7A6")
	key.light_energy = 5.0
	key.spot_range = 7.0
	key.spot_angle = 76.0
	key.spot_angle_attenuation = 0.9
	key.shadow_enabled = not mobile
	key.shadow_blur = 2.0
	key.position = Vector3(0, H - 0.05, 0.2)
	key.rotation_degrees = Vector3(-90, 0, 0)
	cab.add_child(key)
	var fill := OmniLight3D.new()
	fill.light_color = Color("#FFE2BF")
	fill.light_energy = 0.9
	fill.omni_range = 6.5
	fill.position = Vector3(0, 2.4, FRONT_Z - 0.8)
	cab.add_child(fill)
	var rim := OmniLight3D.new()
	rim.light_color = Color("#8FB0FF")
	rim.light_energy = 0.8
	rim.omni_range = 4.5
	rim.position = Vector3(0, 1.6, BACK_Z + 0.4)
	cab.add_child(rim)
	# Frente: pared con el hueco de las puertas, dos hojas correderas e indicador encima.
	_front = Node3D.new()
	_front.name = "Front"
	cab.add_child(_front)
	var side_w := (W - DOOR_W) / 2.0
	for sx in [-1.0, 1.0]:
		_box(_front, Vector3(sx * (DOOR_W / 2.0 + side_w / 2.0), H / 2.0, FRONT_Z + 0.05), Vector3(side_w + 0.1, H, 0.1), metal)
	_box(_front, Vector3(0, (DOOR_H + H) / 2.0, FRONT_Z + 0.05), Vector3(DOOR_W, H - DOOR_H, 0.1), metal)
	_box(_front, Vector3(0, DOOR_H + 0.02, FRONT_Z - 0.03), Vector3(DOOR_W + 0.14, 0.04, 0.06), dark_metal)
	for sx in [-1.0, 1.0]:
		_box(_front, Vector3(sx * (DOOR_W / 2.0 + 0.05), DOOR_H / 2.0, FRONT_Z - 0.03), Vector3(0.06, DOOR_H, 0.06), dark_metal)
	for sx in [-1.0, 1.0]:
		var door := Node3D.new()
		door.name = "DoorL" if sx < 0 else "DoorR"
		_front.add_child(door)
		_box(door, Vector3.ZERO, Vector3(DOOR_W / 2.0, DOOR_H, 0.05), _metal("door", Color("#C9CDD4"), 0.3))
		_box(door, Vector3(-sx * (DOOR_W / 4.0 - 0.01), 0, -0.03), Vector3(0.012, DOOR_H, 0.01), dark_metal)
		door.set_meta("side", sx)
		_doors.append(door)
	_display(_front, Vector3(0, (DOOR_H + H) / 2.0 + 0.02, FRONT_Z - 0.005), PI)
	# Botonera junto a la puerta (detalle).
	var panel := _box(_front, Vector3(DOOR_W / 2.0 + 0.45, 1.25, FRONT_Z - 0.01), Vector3(0.22, 0.5, 0.02), dark_metal)
	for j in 4:
		var bt := MeshInstance3D.new()
		var cy := CylinderMesh.new()
		cy.top_radius = 0.025
		cy.bottom_radius = 0.025
		cy.height = 0.012
		bt.mesh = cy
		bt.rotation_degrees = Vector3(90, 0, 0)
		bt.position = Vector3(0, 0.15 - j * 0.1, -0.015)
		bt.material_override = _emit("button_on" if j == 0 else "button", AMBER if j == 0 else Color("#8892A6"), 2.0 if j == 0 else 0.4)
		panel.add_child(bt)

## Indicador de planta: panel negro, flecha y número ámbar (luz LED).
func _display(parent: Node3D, pos: Vector3, yaw: float) -> void:
	var root := Node3D.new()
	root.position = pos
	root.rotation.y = yaw
	parent.add_child(root)
	_box(root, Vector3(0, 0, 0.012), Vector3(0.9, 0.3, 0.02), _mat("display", Color("#05060A"), 0.2))
	var arrow := MeshInstance3D.new()
	var pm := PrismMesh.new()
	pm.size = Vector3(0.14, 0.12, 0.01)
	arrow.mesh = pm
	arrow.material_override = _emit("led_amber", AMBER, 3.0)
	arrow.position = Vector3(-0.22, 0, 0.026)
	root.add_child(arrow)
	_arrows.append(arrow)
	var label := Label3D.new()
	label.text = "PB"
	label.font = UiPalette.mono_font()
	label.font_size = 64
	label.pixel_size = 0.0034
	label.outline_size = 0
	label.modulate = Color(AMBER.r * 2.2, AMBER.g * 2.2, AMBER.b * 2.2)
	label.position = Vector3(0.08, 0, 0.026)
	label.double_sided = false
	root.add_child(label)
	_displays.append(label)

func _set_doors(u: float) -> void:
	for d in _doors:
		var sx: float = d.get_meta("side")
		var closed := sx * DOOR_W / 4.0
		var open := sx * (DOOR_W / 4.0 + DOOR_W / 2.0 - 0.06)
		d.position = Vector3(lerpf(closed, open, u), DOOR_H / 2.0, FRONT_Z - 0.085)

## La recepción de NexusCore en la planta 14, al otro lado de las puertas: pared con el
## rótulo luminoso, tiras de luz, plantas y el mostrador a un lado.
func _build_reception() -> void:
	_reception = Node3D.new()
	_reception.name = "Reception"
	_reception.position = Vector3(0, FLOORS * FLOOR_H, 0)
	_reception.visible = false
	_world.add_child(_reception)
	var z0 := FRONT_Z + 0.1
	var back := z0 + 4.2
	var wall := _mat("rec_wall", Color("#1B2236"), 0.55)
	_box(_reception, Vector3(0, -0.05, z0 + 2.5), Vector3(12, 0.1, 5.2), _mat("rec_floor", Color("#8A6A4C"), 0.5))
	_box(_reception, Vector3(0, 1.8, back), Vector3(12, 3.6, 0.2), wall)
	for sx in [-1.0, 1.0]:
		_box(_reception, Vector3(sx * 4.2, 1.8, z0 + 2.1), Vector3(0.2, 3.6, 4.4), wall)
	_box(_reception, Vector3(0, 3.0, z0 + 2.1), Vector3(8.6, 0.1, 4.6), _mat("rec_ceil", Color("#151A28"), 0.8))
	# Panel de madera detrás del rótulo, con su luz de bañado.
	_box(_reception, Vector3(0, 1.1, back - 0.13), Vector3(3.6, 2.2, 0.06), _mat("rec_wood", Color("#6B4A33"), 0.5))
	var sign := Label3D.new()
	sign.text = "NexusCore AI"
	sign.font = UiPalette.heading_font()
	sign.font_size = 96
	sign.pixel_size = 0.0055
	sign.outline_size = 0
	sign.modulate = Color(0.6, 1.6, 2.3)
	sign.position = Vector3(0, 1.4, back - 0.17)
	sign.rotation.y = PI
	_reception.add_child(sign)
	_box(_reception, Vector3(0, 1.06, back - 0.17), Vector3(2.6, 0.025, 0.02), _emit("sign_line", Color("#9B7BFF"), 3.0))
	for sx in [-1.0, 1.0]:
		_box(_reception, Vector3(sx * 1.9, 1.1, back - 0.14), Vector3(0.04, 2.2, 0.04), _emit("rec_led", Color("#FFD9A8"), 2.4))
	_box(_reception, Vector3(0, 0.02, back - 0.3), Vector3(6.0, 0.02, 0.04), _emit("rec_led", Color("#FFD9A8"), 2.4))
	# Mostrador a la izquierda y plantas.
	_box(_reception, Vector3(-2.6, 0.52, z0 + 2.6), Vector3(1.8, 1.04, 0.7), _mat("desk", Color("#D9D5CE"), 0.35))
	for px in [-3.4, 2.6, 3.4]:
		var pot := _box(_reception, Vector3(px, 0.3, back - 0.6), Vector3(0.55, 0.6, 0.55), _mat("pot", Color("#2B2F3A"), 0.5))
		var leaves := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.5
		sm.height = 1.3
		leaves.mesh = sm
		leaves.material_override = _mat("leaf", Color("#2F6B45"), 0.7)
		leaves.position = Vector3(0, 0.85, 0)
		pot.add_child(leaves)
	var lamp := OmniLight3D.new()
	lamp.light_color = Color("#FFD9AE")
	lamp.light_energy = 1.8
	lamp.omni_range = 7.0
	lamp.position = Vector3(0, 2.7, z0 + 1.6)
	_reception.add_child(lamp)
	var wash := SpotLight3D.new()
	wash.light_color = Color("#FFE0B8")
	wash.light_energy = 3.0
	wash.spot_range = 4.0
	wash.spot_angle = 40.0
	_reception.add_child(wash)
	wash.look_at_from_position(Vector3(0, 2.9, back - 1.4), Vector3(0, 1.1, back), Vector3.UP)

# ── piezas y materiales ─────────────────────────────────────────────────────────

func _box(parent: Node3D, pos: Vector3, s: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = s
	mi.mesh = bm
	mi.position = pos
	mi.material_override = mat
	parent.add_child(mi)
	return mi

func _bar(parent: Node3D, a: Vector3, b: Vector3, r: float, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var cy := CylinderMesh.new()
	cy.top_radius = r
	cy.bottom_radius = r
	cy.height = a.distance_to(b)
	cy.radial_segments = 12
	mi.mesh = cy
	mi.material_override = mat
	parent.add_child(mi)
	var dir := (b - a).normalized()
	var up := Vector3.UP
	var axis := up.cross(dir)
	var basis := Basis.IDENTITY
	if axis.length() > 0.0001:
		basis = Basis(axis.normalized(), up.angle_to(dir))
	mi.transform = Transform3D(basis, (a + b) / 2.0)

func _mat(key: String, col: Color, rough := 0.5, metal := 0.0) -> StandardMaterial3D:
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = col
		m.roughness = rough
		m.metallic = metal
		_mats[key] = m
	return _mats[key]

func _metal(key: String, col: Color, rough: float) -> StandardMaterial3D:
	var k := "metal_" + key
	if not _mats.has(k):
		var m := StandardMaterial3D.new()
		m.albedo_color = col
		m.albedo_texture = _brushed_tex()
		m.metallic = 0.6
		m.roughness = rough
		m.metallic_specular = 0.6
		m.uv1_triplanar = true
		m.uv1_scale = Vector3(0.9, 2.4, 0.9)
		_mats[k] = m
	return _mats[k]

func _emit(key: String, col: Color, energy: float) -> StandardMaterial3D:
	var k := "emit_" + key
	if not _mats.has(k):
		var m := StandardMaterial3D.new()
		m.albedo_color = col.darkened(0.6)
		m.emission_enabled = true
		m.emission = col
		m.emission_energy_multiplier = energy
		_mats[k] = m
	return _mats[k]

func _glass_mat() -> StandardMaterial3D:
	if not _mats.has("glass"):
		var m := StandardMaterial3D.new()
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color = Color(0.55, 0.7, 0.95, 0.07)
		m.roughness = 0.04
		m.metallic_specular = 0.9
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		_mats["glass"] = m
	return _mats["glass"]

func _local_ring_mat() -> ShaderMaterial:
	if not _mats.has("ring_local"):
		# Los mismos valores que el aro "local" de LobbyStage.
		var m := ShaderMaterial.new()
		m.shader = RING_SHADER
		m.set_shader_parameter("color", AMBER)
		m.set_shader_parameter("energy", 1.5)
		m.set_shader_parameter("radius", 0.62)
		m.set_shader_parameter("width", 0.07)
		m.set_shader_parameter("halo", 0.16)
		m.set_shader_parameter("fill", 0.18)
		m.set_shader_parameter("dashes", 0.0)
		m.set_shader_parameter("spin", 0.0)
		m.set_shader_parameter("pulse", 0.1)
		_mats["ring_local"] = m
	return _mats["ring_local"]

func _shadow_mat() -> StandardMaterial3D:
	if not _mats.has("shadow"):
		if _soft == null:
			var g := Gradient.new()
			g.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
			g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.45), Color(1, 1, 1, 0)])
			_soft = GradientTexture2D.new()
			_soft.gradient = g
			_soft.fill = GradientTexture2D.FILL_RADIAL
			_soft.fill_from = Vector2(0.5, 0.5)
			_soft.fill_to = Vector2(1.0, 0.5)
			_soft.width = 64
			_soft.height = 64
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_texture = _soft
		m.albedo_color = Color(0, 0, 0, 0.55)
		_mats["shadow"] = m
	return _mats["shadow"]

## Acero cepillado: vetas horizontales de ruido (textura generada, sin archivos).
static func _brushed_tex() -> ImageTexture:
	if _brushed == null:
		var img := Image.create(128, 128, false, Image.FORMAT_RGB8)
		var rng := RandomNumberGenerator.new()
		rng.seed = 77
		for y in 128:
			var row := rng.randf_range(0.8, 1.0)
			for x in 128:
				var v := clampf(row + rng.randf_range(-0.035, 0.035), 0.0, 1.0)
				img.set_pixel(x, y, Color(v, v, v))
		img.generate_mipmaps()
		_brushed = ImageTexture.create_from_image(img)
	return _brushed

# ── sonido (sintetizado: obra propia) ───────────────────────────────────────────

const SR := 22050

## Los sonidos se sintetizan en otro hilo al empezar (tarda un poco y no debe dar tirones).
func _prepare_sfx() -> void:
	if (_ding_stream and _hum_stream) or _sfx_task >= 0:
		return
	_sfx_task = WorkerThreadPool.add_task(func() -> void:
		_ding_wav()
		_hum_wav())

## "Ding-dong" de llegada: dos campanadas (Mi6 y Do6) con parciales de campana y caída
## exponencial.
static func _ding_wav() -> AudioStreamWAV:
	if _ding_stream == null:
		var n := int(SR * 2.2)
		var buf := PackedFloat32Array()
		buf.resize(n)
		for strike in [[0.0, 1318.5, 1.0], [0.36, 1046.5, 0.8]]:
			var t0: int = int(float(strike[0]) * SR)
			var f: float = strike[1]
			var amp: float = strike[2]
			var partials := [[1.0, 1.0, 1.5], [2.0, 0.32, 0.8], [2.76, 0.18, 0.5], [4.07, 0.07, 0.25]]
			for i in range(t0, n):
				var t := float(i - t0) / SR
				var attack := minf(1.0, t / 0.004)
				var s := 0.0
				for p in partials:
					s += float(p[1]) * exp(-t / float(p[2])) * sin(TAU * f * float(p[0]) * t)
				buf[i] += s * amp * attack
		var tail := int(SR * 0.6)   # cola suave: sin chasquido al final
		for i in tail:
			buf[n - tail + i] *= 1.0 - float(i) / tail
		_ding_stream = _wav(buf, 0.42, false)
	return _ding_stream

## Zumbido suave del motor durante el viaje (bucle de 1 s: 55/110/165 Hz y un soplo).
static func _hum_wav() -> AudioStreamWAV:
	if _hum_stream == null:
		var n := SR
		var buf := PackedFloat32Array()
		buf.resize(n)
		var rng := RandomNumberGenerator.new()
		rng.seed = 5
		var lp := 0.0
		for i in n:
			var t := float(i) / SR
			lp += (rng.randf_range(-1.0, 1.0) - lp) * 0.02
			buf[i] = 0.5 * sin(TAU * 55.0 * t) + 0.3 * sin(TAU * 110.0 * t) + 0.12 * sin(TAU * 165.0 * t) + 1.6 * lp
		_hum_stream = _wav(buf, 0.35, true)
	return _hum_stream

static func _wav(buf: PackedFloat32Array, gain: float, loop: bool) -> AudioStreamWAV:
	var peak := 0.0001
	for v in buf:
		peak = maxf(peak, absf(v))
	var data := PackedByteArray()
	data.resize(buf.size() * 2)
	for i in buf.size():
		data.encode_s16(i * 2, int(clampf(buf[i] / peak * gain, -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = SR
	w.stereo = false
	w.data = data
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = buf.size()
	return w

# ── capa 2D: la vista, el indicador y la leyenda ────────────────────────────────

func _build_overlay() -> void:
	_vp = SubViewport.new()
	_vp.name = "Elevator3D"
	_vp.own_world_3d = true
	_vp.msaa_3d = Viewport.MSAA_2X if mobile else Viewport.MSAA_4X
	_vp.positional_shadow_atlas_size = 0 if mobile else 2048
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_vp.size = Vector2i(1280, 720)
	add_child(_vp)
	_root = Control.new()
	_root.name = "Root"
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	var bg := ColorRect.new()
	bg.color = Color("#03040A")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(bg)
	_view = TextureRect.new()
	_view.name = "View"
	_view.texture = _vp.get_texture()
	_view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_view.stretch_mode = TextureRect.STRETCH_SCALE
	_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_view)
	var vignette := _Vignette.new()
	vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(vignette)
	# Indicador de planta arriba, en el centro.
	var panel := PanelContainer.new()
	panel.name = "FloorIndicator"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var st := UiPalette.flat(Color(0.03, 0.04, 0.08, 0.78), Color(AMBER, 0.55), 1, 14, 10)
	st.content_margin_left = 16
	st.content_margin_right = 18
	panel.add_theme_stylebox_override("panel", st)
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	panel.position = Vector2(22, 18)
	_root.add_child(panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(row)
	_arrow2d = _Arrow.new()
	_arrow2d.custom_minimum_size = Vector2(22, 22)
	_arrow2d.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_arrow2d.color = AMBER
	row.add_child(_arrow2d)
	_floor_label = Label.new()
	_floor_label.name = "Floor"
	_floor_label.text = "PB"
	_floor_label.custom_minimum_size = Vector2(52, 0)
	_floor_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_floor_label.add_theme_font_override("font", UiPalette.mono_font())
	_floor_label.add_theme_font_size_override("font_size", 38)
	_floor_label.add_theme_color_override("font_color", AMBER)
	row.add_child(_floor_label)
	var sep := ColorRect.new()
	sep.color = Color(1, 1, 1, 0.18)
	sep.custom_minimum_size = Vector2(1, 34)
	sep.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(sep)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(col)
	var brand := Label.new()
	brand.text = "NEXUSCORE AI"
	brand.add_theme_font_override("font", UiPalette.bold_font())
	brand.add_theme_font_size_override("font_size", 13)
	brand.add_theme_color_override("font_color", Color("#9FD8FF"))
	col.add_child(brand)
	var dest := Label.new()
	dest.text = "Destino: planta 14"
	dest.add_theme_font_override("font", UiPalette.body_font())
	dest.add_theme_font_size_override("font_size", 13)
	dest.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
	col.add_child(dest)
	# Leyenda abajo.
	_caption = Label.new()
	_caption.name = "Caption"
	_caption.text = CAPTION_RIDE
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.add_theme_font_override("font", UiPalette.bold_font())
	_caption.add_theme_font_size_override("font_size", 18)
	_caption.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
	_caption.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	_caption.add_theme_constant_override("outline_size", 6)
	_caption.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_caption.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_caption.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_caption.position.y -= 26
	_root.add_child(_caption)
	_fade = ColorRect.new()
	_fade.name = "Fade"
	_fade.color = Color(0.0, 0.0, 0.02, 1.0)
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_fade)
	_ding = AudioStreamPlayer.new()
	_ding.name = "Ding"
	_ding.volume_db = -6.0
	add_child(_ding)
	_hum = AudioStreamPlayer.new()
	_hum.name = "Hum"
	add_child(_hum)

class _Arrow extends Control:
	var color := Color.WHITE
	var blink := 1.0
	func _draw() -> void:
		var s := size
		draw_colored_polygon(PackedVector2Array([Vector2(s.x * 0.5, s.y * 0.1), Vector2(s.x * 0.95, s.y * 0.85), Vector2(s.x * 0.05, s.y * 0.85)]), Color(color, blink))

class _Vignette extends Control:
	func _draw() -> void:
		var w := size.x
		var h := size.y
		var dark := Color(0.0, 0.005, 0.02, 0.6)
		var clear := Color(dark, 0.0)
		var band := minf(w, h) * 0.26
		for q in [[Vector2(0, 0), Vector2(w, 0), Vector2(w, band), Vector2(0, band), dark, dark, clear, clear],
				[Vector2(0, h - band), Vector2(w, h - band), Vector2(w, h), Vector2(0, h), clear, clear, dark, dark],
				[Vector2(0, 0), Vector2(band, 0), Vector2(band, h), Vector2(0, h), dark, clear, clear, dark],
				[Vector2(w - band, 0), Vector2(w, 0), Vector2(w, h), Vector2(w - band, h), clear, dark, dark, clear]]:
			draw_polygon(PackedVector2Array([q[0], q[1], q[2], q[3]]), PackedColorArray([q[4], q[5], q[6], q[7]]))
	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED:
			queue_redraw()
