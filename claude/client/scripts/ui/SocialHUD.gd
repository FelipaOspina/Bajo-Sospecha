class_name SocialHUD
extends CanvasLayer
## HUD de "Silenciar al testigo", solo en TU pantalla (nunca revela roles a los demás:
## los botones de poder solo los ves tú, y solo si tu rol los tiene):
##  - SILENCIAR [F] (power "silence"): activo con un jugador en pie a ≤ 90 px que esté en
##    you.motiveTargets; muestra a quién y por qué ("Te vio"), la recarga y "Aún no"
##    durante el primer minuto. Sin motivo no hay objetivo.
##  - ESCOLTAR [G] (power "escort"): protege a un jugador en pie a ≤ 160 px; muestra a
##    quién proteges y cuánto le queda.
##  - REPORTAR [R]: aparece junto a un cuerpo sin reportar (≤ 160 px) y abre la asamblea
##    de emergencia.
##  - Botón de emergencia (call_meeting): lo pintan OfficeHUD y el menú en partida
##    (meeting_button_state); al pulsarlo emiten EventBus.emergency_meeting_requested y
##    aquí se envía, con aviso si el servidor lo rechaza. Una vez por jugador y partida.
##  - Fantasma: PING FANTASMA [T] (luego clic o toque en el mapa) y el panel de misiones
##    fantasma, con MISIÓN [E] a ≤ 80 px (canalización de 6 s, como las de las pistas).
##  - Avisos: banner "¡CUERPO ENCONTRADO!", pantalla de noqueado ("Te han noqueado por la
##    espalda", sin decir quién) y de fantasma, confirmación al asesino, escolta, pings, y
##    el registro persistente de lo que has visto ("Viste a Beto silenciar a Carla").
## Solo pide: el servidor valida (alcance, motivo, recarga) y responde.

const VISIBLE_PHASES := ["briefing", "investigation"]
const BUTTON_SIZE := Vector2(118, 92)
const TOAST_SECONDS := 4.5
const BANNER_SECONDS := 3.2
const GHOST_INTRO_SECONDS := 7.0
const SILENCE_COLOR := Color("#FF334B")
const ESCORT_COLOR := Color("#38BDF8")
const REPORT_COLOR := Color("#E5A93C")
const GHOST_COLOR := Color("#C084FC")
const PING_COLOR := Color("#7DF9FF")

## Por qué tienes motivo para silenciar a alguien (you.motiveTargets[].reason).
const MOTIVE_TEXT := {
	"evidence": "Lleva una prueba contra ti",
	"witness": "Te vio",
	"backup": "Sacó copia de una prueba contra ti",
	"story": "Te está chantajeando",
}

const REASON_TEXT := {
	"wrong_phase": "Ahora no puedes hacer eso.",
	"not_alive": "Ya no estás en la partida.",
	"no_power": "Tu rol no puede hacer eso.",
	"too_early": "Aún no: espera al primer minuto de la investigación.",
	"on_cooldown": "Aún se está recargando.",
	"too_far": "Está demasiado lejos.",
	"target_not_alive": "Esa persona ya no está en pie.",
	"target_protected": "Está escoltado: tu intento ha fallado.",
	"unknown_body": "Ese cuerpo ya no está.",
	"no_motive": "No tienes ningún motivo para silenciar a esa persona.",
	"knocked": "Estás noqueado: no puedes moverte ni actuar.",
	"not_ghost": "Solo los fantasmas pueden hacer eso.",
	"unknown_task": "Esa misión ya no existe.",
	"task_done": "Esa misión ya está hecha.",
	"already_channeling": "Ya estás haciendo otra cosa.",
	"moved": "Te has movido: misión interrumpida.",
	"meeting_used": "Ya usaste tu reunión de emergencia en esta partida.",
	"no_meetings_left": "Ya no quedan reuniones de emergencia en esta partida.",
}

const MEETING_TEXT := "Convocar reunión de emergencia"
const MEETING_USED_TEXT := "Reunión ya convocada"

@export var players: PlayerSpawner
var network: Node              # Network o un doble en las pruebas

var root: Control
var actions: HBoxContainer
var silence_button: Button
var escort_button: Button
var report_button: Button
var ping_button: Button
var task_button: Button
var ghost_panel: PanelContainer
var ghost_tasks_box: VBoxContainer
var witness_panel: PanelContainer
var witness_box: VBoxContainer
var toasts: VBoxContainer
var banner: Control
var banner_title: Label
var banner_sub: Label
var knocked_overlay: Control
var knocked_title: Label
var knocked_timer: Label
var ghost_overlay: Control
var ghost_title: Label
var ghost_text: Label
var aim_hint: Label

## Objetivos que mostraría cada botón ahora mismo (para pruebas): ids o "".
var silence_target := ""
var escort_target := ""
var report_body := ""
var task_target := ""
## Esperando clic/toque en el mapa para el ping fantasma.
var aiming_ping := false

var _pending := {}             # seq -> acción
var _silence_used := false     # tras el primer intento ya no es "Aún no", es recarga
var _was_ghost := false
var _was_knocked := false
var _knocked_until := -1
var _banner_left := 0.0
var _ghost_left := 0.0
var _witness_count := -1
var _task_signature := ""

func _ready() -> void:
	layer = 9
	if network == null:
		network = Network
	_build()
	EventBus.intent_rejected.connect(_on_rejected)
	EventBus.silenced.connect(_on_silenced)
	EventBus.witnessed.connect(_on_witnessed)
	EventBus.escort_blocked.connect(_on_escort_blocked)
	EventBus.body_reported.connect(_on_body_reported)
	EventBus.meeting_called.connect(_on_meeting_called)
	EventBus.emergency_meeting_requested.connect(call_meeting)
	EventBus.emergency_result.connect(_on_emergency_result)
	EventBus.ghost_ping.connect(func(_by: String, _p: Vector2, _u: int) -> void:
		if not GameState.is_ghost():
			toast("Un fantasma te señala un sitio: búscalo en el mapa.", PING_COLOR))
	EventBus.ghost_reveal.connect(func(_id: String, _p: Vector2, _u: int) -> void:
		if not GameState.is_ghost():
			toast("Una pista brilla desde el más allá durante 20 s.", GHOST_COLOR))
	GameState.snapshot_applied.connect(func(_s: Dictionary) -> void: refresh())
	refresh()

# ───────────── Construcción ─────────────

func _build() -> void:
	root = Control.new()
	root.name = "Root"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	actions = HBoxContainer.new()
	actions.name = "Actions"
	actions.alignment = BoxContainer.ALIGNMENT_END
	actions.add_theme_constant_override("separation", 10)
	actions.anchor_left = 1.0
	actions.anchor_right = 1.0
	actions.anchor_top = 1.0
	actions.anchor_bottom = 1.0
	actions.offset_left = -900.0
	actions.offset_right = -270.0      # a la izquierda de la activa del animal
	actions.offset_top = -BUTTON_SIZE.y - 30.0
	actions.offset_bottom = -30.0
	actions.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(actions)
	task_button = _action_button("TaskButton", "MISIÓN", "[E]", GHOST_COLOR, _on_task_pressed)
	ping_button = _action_button("PingButton", "PING FANTASMA", "[T]", PING_COLOR, _on_ping_pressed)
	report_button = _action_button("ReportButton", "REPORTAR", "[R]", REPORT_COLOR, _on_report_pressed)
	escort_button = _action_button("EscortButton", "ESCOLTAR", "[G]", ESCORT_COLOR, _on_escort_pressed)
	silence_button = _action_button("SilenceButton", "SILENCIAR", "[F]", SILENCE_COLOR, _on_silence_pressed)

	# Panel de fantasma (izquierda, bajo las tareas).
	ghost_panel = _side_panel("GhostPanel", GHOST_COLOR, 236.0)
	var gbox := ghost_panel.get_child(0) as VBoxContainer
	gbox.add_child(_text("MODO FANTASMA", 17, GHOST_COLOR, UiPalette.heading_font()))
	var hint := _text("Nadie te ve. Atraviesas paredes y lo ves todo. Haz misiones para que aparezcan pruebas y marca sitios a tu equipo con PING.", 12, UiPalette.TEXT_DIM)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size.x = 240
	gbox.add_child(hint)
	gbox.add_child(_text("Misiones fantasma", 14, Color.WHITE, UiPalette.bold_font()))
	ghost_tasks_box = VBoxContainer.new()
	ghost_tasks_box.name = "GhostTasks"
	ghost_tasks_box.add_theme_constant_override("separation", 3)
	gbox.add_child(ghost_tasks_box)

	# Registro de lo que has visto (persistente toda la partida).
	witness_panel = _side_panel("WitnessPanel", SILENCE_COLOR, 236.0)
	var wbox := witness_panel.get_child(0) as VBoxContainer
	wbox.add_child(_text("LO QUE HAS VISTO", 14, Color("#FCA5A5"), UiPalette.heading_font()))
	witness_box = VBoxContainer.new()
	witness_box.name = "WitnessLog"
	witness_box.add_theme_constant_override("separation", 2)
	wbox.add_child(witness_box)

	toasts = VBoxContainer.new()
	toasts.name = "Toasts"
	toasts.anchor_left = 0.5
	toasts.anchor_right = 0.5
	toasts.offset_left = -260
	toasts.offset_right = 260
	toasts.offset_top = 86
	toasts.offset_bottom = 300
	toasts.add_theme_constant_override("separation", 6)
	toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(toasts)

	aim_hint = _text("Toca el mapa para marcar un sitio · Esc para cancelar", 16, PING_COLOR, UiPalette.bold_font())
	aim_hint.name = "AimHint"
	aim_hint.anchor_left = 0.5
	aim_hint.anchor_right = 0.5
	aim_hint.anchor_top = 1.0
	aim_hint.anchor_bottom = 1.0
	aim_hint.offset_left = -300
	aim_hint.offset_right = 300
	aim_hint.offset_top = -170
	aim_hint.offset_bottom = -140
	aim_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	aim_hint.visible = false
	root.add_child(aim_hint)

	_build_knocked_overlay()
	_build_ghost_overlay()
	# El banner va encima de todo: mientras dura, tapa las pantallas de noqueo y fantasma.
	_build_banner()

func _action_button(node_name: String, title: String, key: String, accent: Color, on_press: Callable) -> Button:
	var b := Button.new()
	b.name = node_name
	b.custom_minimum_size = BUTTON_SIZE
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_stylebox_override("normal", UiPalette.flat(Color(0.05, 0.08, 0.14, 0.9), Color(accent, 0.85), 2, 18, 6))
	b.add_theme_stylebox_override("hover", UiPalette.flat(Color(accent, 0.28), accent, 2, 18, 6))
	b.add_theme_stylebox_override("pressed", UiPalette.flat(Color(accent, 0.45), accent, 2, 18, 6))
	b.add_theme_stylebox_override("disabled", UiPalette.flat(Color(0.05, 0.08, 0.14, 0.7), Color(accent, 0.25), 2, 18, 6))
	b.pressed.connect(on_press)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 0)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(box)
	var k := _text(key, 11, Color(accent, 0.9))
	k.name = "Key"
	k.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(k)
	var t := _text(title, 16 if title.length() < 11 else 13, Color.WHITE, UiPalette.heading_font())
	t.name = "Title"
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(t)
	var sub := _text("", 11, UiPalette.TEXT)
	sub.name = "Sub"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.custom_minimum_size.x = BUTTON_SIZE.x - 12
	box.add_child(sub)
	b.visible = false
	actions.add_child(b)
	return b

func _side_panel(node_name: String, accent: Color, top: float) -> PanelContainer:
	var p := PanelContainer.new()
	p.name = node_name
	p.add_theme_stylebox_override("panel", UiPalette.flat(Color(0.06, 0.08, 0.16, 0.82), Color(accent, 0.45), 1, 14, 12))
	p.offset_left = 24
	p.offset_top = top
	p.offset_right = 296
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 5)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(box)
	p.visible = false
	root.add_child(p)
	return p

func _build_banner() -> void:
	banner = Control.new()
	banner.name = "Banner"
	banner.set_anchors_preset(Control.PRESET_FULL_RECT)
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.visible = false
	root.add_child(banner)
	var scrim := ColorRect.new()
	scrim.color = Color(0.03, 0.02, 0.05, 0.78)
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.add_child(scrim)
	var band := ColorRect.new()
	band.color = Color(0.45, 0.02, 0.07, 0.92)
	band.anchor_right = 1.0
	band.anchor_top = 0.5
	band.anchor_bottom = 0.5
	band.offset_top = -78
	band.offset_bottom = 78
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.add_child(band)
	for edge in [-78.0, 74.0]:
		var stripe := ColorRect.new()
		stripe.color = Color(SILENCE_COLOR, 0.95)
		stripe.anchor_right = 1.0
		stripe.anchor_top = 0.5
		stripe.anchor_bottom = 0.5
		stripe.offset_top = edge
		stripe.offset_bottom = edge + 4.0
		stripe.mouse_filter = Control.MOUSE_FILTER_IGNORE
		banner.add_child(stripe)
	banner_title = _text("¡CUERPO ENCONTRADO!", 54, Color.WHITE, UiPalette.heading_font())
	banner_title.name = "BannerTitle"
	banner_title.add_theme_constant_override("outline_size", 10)
	banner_title.add_theme_color_override("font_outline_color", Color(0.2, 0, 0.02, 0.9))
	banner_title.anchor_right = 1.0
	banner_title.anchor_top = 0.5
	banner_title.anchor_bottom = 0.5
	banner_title.offset_top = -64
	banner_title.offset_bottom = 10
	banner_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.add_child(banner_title)
	banner_sub = _text("", 19, Color("#FECACA"), UiPalette.bold_font())
	banner_sub.name = "BannerSub"
	banner_sub.anchor_right = 1.0
	banner_sub.anchor_top = 0.5
	banner_sub.anchor_bottom = 0.5
	banner_sub.offset_top = 14
	banner_sub.offset_bottom = 60
	banner_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.add_child(banner_sub)

func _full_overlay(node_name: String, tint: Color) -> Control:
	var c := Control.new()
	c.name = node_name
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.visible = false
	root.add_child(c)
	var dim := ColorRect.new()
	dim.color = tint
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(dim)
	var box := VBoxContainer.new()
	box.name = "Box"
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 10)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(box)
	return c

func _build_knocked_overlay() -> void:
	knocked_overlay = _full_overlay("KnockedOverlay", Color(0.04, 0.03, 0.10, 0.55))
	var box := knocked_overlay.get_node("Box")
	var stars := _text("★  ★  ★", 30, Color("#FFD54A"), UiPalette.heading_font())
	stars.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(stars)
	knocked_title = _text("Te han noqueado por la espalda", 40, Color.WHITE, UiPalette.heading_font())
	knocked_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	knocked_title.add_theme_constant_override("outline_size", 8)
	box.add_child(knocked_title)
	knocked_timer = _text("", 22, Color("#FFD54A"), UiPalette.bold_font())
	knocked_timer.name = "KnockedTimer"
	knocked_timer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(knocked_timer)
	var info := _text("Has soltado todo lo que llevabas. Al levantarte podrás votar, pero ya no podrás presentar pruebas en el juicio final.", 16, UiPalette.TEXT)
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.custom_minimum_size.x = 560
	info.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(info)

func _build_ghost_overlay() -> void:
	ghost_overlay = _full_overlay("GhostOverlay", Color(0.08, 0.03, 0.16, 0.62))
	var box := ghost_overlay.get_node("Box")
	ghost_title = _text("Te han silenciado", 42, Color("#E9D5FF"), UiPalette.heading_font())
	ghost_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ghost_title.add_theme_constant_override("outline_size", 8)
	box.add_child(ghost_title)
	ghost_text = _text("Ahora eres un fantasma: nadie te ve, no puedes tocar pruebas ni votar. Ayuda a tu equipo con las misiones fantasma y el PING.", 17, UiPalette.TEXT)
	ghost_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ghost_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ghost_text.custom_minimum_size.x = 600
	ghost_text.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(ghost_text)

func _text(t: String, font_size: int, color: Color, font: Font = null) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_constant_override("outline_size", 4)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
	if font:
		l.add_theme_font_override("font", font)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

# ───────────── Estado ─────────────

func _now() -> float:
	return Network.server_time_ms()

func _me() -> String:
	return GameState.local_player_id()

func _powers() -> Dictionary:
	var p = GameState.my_private_state().get("powers")
	return p if p is Dictionary else {}

func has_power(id: String) -> bool:
	return _powers().get(id) is Dictionary

## Posición de un jugador: la de su personaje (interpolada) o la del snapshot.
func _pos(id: String) -> Vector2:
	var node: Player = players.get_player(id) if players else null
	if node:
		return node.global_position
	return Protocol.vec2_from(GameState.public_player(id).get("position", {}))

## En pie y en juego: vivo, ni fantasma, ni oculto, ni noqueado.
static func standing(p: Dictionary) -> bool:
	return p.get("alive", true) != false and not p.get("ghost", false) and not p.get("hidden", false) and not p.get("knocked", false)

## Puedo actuar (botones de vivo): fase de investigación, en pie.
func can_act() -> bool:
	return GameState.phase() == "investigation" and not GameState.is_ghost() and not GameState.is_knocked() \
		and GameState.public_player(_me()).get("alive", true) != false

## Jugadores en pie más cercanos que `max_d`, de más cerca a más lejos (sin ti).
func _near_players(max_d: float, only: Dictionary = {}, use_filter := false) -> Array:
	var me := _pos(_me())
	var out := []
	for p in GameState.players():
		var id := str(p.get("id", ""))
		if id == _me() or not standing(p) or (use_filter and not only.has(id)):
			continue
		var d := me.distance_to(_pos(id))
		if d <= max_d:
			out.append({"id": id, "d": d})
	out.sort_custom(func(a, b): return a["d"] < b["d"])
	return out

## {playerId: reason} de you.motiveTargets.
func motives() -> Dictionary:
	var out := {}
	var list = GameState.my_private_state().get("motiveTargets")
	if list is Array:
		for m in list:
			if m is Dictionary:
				out[str(m.get("playerId", ""))] = m
	return out

static func motive_text(m: Dictionary) -> String:
	if str(m.get("label", "")) != "":
		return str(m["label"])
	# Con el nombre de la prueba (evidence) si el servidor lo manda.
	var ev := str(m.get("evidence", "")) if m.get("evidence") != null else ""
	match str(m.get("reason", "")):
		"evidence":
			if ev != "":
				return "Lleva «%s» contra ti" % ev
		"backup":
			if ev != "":
				return "Sacó copia de «%s»" % ev
	return MOTIVE_TEXT.get(str(m.get("reason", "")), "Tienes un motivo")

func _seconds_until(ready_at) -> int:
	if ready_at == null:
		return 0
	return maxi(0, ceili((float(ready_at) - _now()) / 1000.0))

func _nearest_body() -> Dictionary:
	var me := _pos(_me())
	var best := {}
	var best_d := Protocol.REPORT_RANGE
	for b in GameState.bodies():
		if bool(b.get("reported", false)):
			continue
		var d := me.distance_to(Protocol.vec2_from(b.get("position", {})))
		if d <= best_d:
			best = b
			best_d = d
	return best

func _nearest_task() -> Dictionary:
	var me := _pos(_me())
	var best := {}
	var best_d := Protocol.GHOST_TASK_RANGE
	for t in GameState.ghost_tasks():
		if bool(t.get("done", false)):
			continue
		var d := me.distance_to(Protocol.vec2_from(t.get("position", {})))
		if d <= best_d:
			best = t
			best_d = d
	return best

func _channeling() -> bool:
	return GameState.public_player(_me()).get("channel") is Dictionary

# ───────────── Refresco ─────────────

func refresh() -> void:
	var phase := GameState.phase()
	var exploring := phase in VISIBLE_PHASES
	var ghost := GameState.is_ghost()
	var knocked := GameState.is_knocked()
	actions.visible = exploring
	_refresh_silence(exploring and not ghost and not knocked)
	_refresh_escort(exploring and not ghost and not knocked)
	_refresh_report(exploring and not ghost and not knocked)
	_refresh_ghost(exploring and ghost)
	_refresh_witness(exploring)
	_refresh_overlays(ghost, knocked)

func _set_button(b: Button, show: bool, enabled: bool, sub: String) -> void:
	b.visible = show
	b.disabled = not enabled
	_sub_label(b).text = sub

func _sub_label(b: Button) -> Label:
	return b.get_child(0).get_node("Sub")

func button_sub(b: Button) -> String:
	return _sub_label(b).text

func _refresh_silence(allowed: bool) -> void:
	silence_target = ""
	var power = _powers().get("silence")
	if not allowed or not power is Dictionary:
		_set_button(silence_button, false, false, "")
		return
	var left := _seconds_until(power.get("readyAt"))
	var m := motives()
	var near := _near_players(Protocol.SILENCE_RANGE, m, true)
	if not near.is_empty():
		silence_target = near[0]["id"]
	if GameState.phase() != "investigation":
		_set_button(silence_button, true, false, "Durante la investigación")
	elif left > 0:
		_set_button(silence_button, true, false, ("Recarga · %d s" if _silence_used else "Aún no · %d s") % left)
	elif silence_target == "":
		_set_button(silence_button, true, false, "Nadie a tu alcance con motivo")
	else:
		_set_button(silence_button, true, true, "%s · %s" % [GameState.player_name(silence_target), motive_text(m[silence_target])])

func _refresh_escort(allowed: bool) -> void:
	escort_target = ""
	var power = _powers().get("escort")
	if not allowed or not power is Dictionary:
		_set_button(escort_button, false, false, "")
		return
	var protecting := str(power.get("protecting", "")) if power.get("protecting") != null else ""
	var guard_left := _seconds_until(power.get("until"))
	var left := _seconds_until(power.get("readyAt"))
	var near := _near_players(Protocol.ESCORT_RANGE)
	if not near.is_empty():
		escort_target = near[0]["id"]
	if protecting != "" and guard_left > 0:
		_set_button(escort_button, true, false, "Proteges a %s · %d s" % [GameState.player_name(protecting), guard_left])
	elif GameState.phase() != "investigation":
		_set_button(escort_button, true, false, "Durante la investigación")
	elif left > 0:
		_set_button(escort_button, true, false, "Recarga · %d s" % left)
	elif escort_target == "":
		_set_button(escort_button, true, false, "Nadie cerca")
	else:
		_set_button(escort_button, true, true, "Proteger a %s" % GameState.player_name(escort_target))

func _refresh_report(allowed: bool) -> void:
	report_body = ""
	if not allowed or GameState.phase() != "investigation":
		_set_button(report_button, false, false, "")
		return
	var b := _nearest_body()
	if b.is_empty():
		_set_button(report_button, false, false, "")
		return
	report_body = str(b.get("id", ""))
	var who := GameState.player_name(str(b.get("playerId", "")))
	_set_button(report_button, true, true, ("%s, noqueado" if str(b.get("kind", "")) == Protocol.BODY_KNOCKED else "Cuerpo de %s") % who)

func _refresh_ghost(ghost_mode: bool) -> void:
	ghost_panel.visible = ghost_mode
	task_target = ""
	if not ghost_mode:
		_set_button(ping_button, false, false, "")
		_set_button(task_button, false, false, "")
		if aiming_ping:
			_set_aiming(false)
		return
	var left := _seconds_until(GameState.my_private_state().get("ghostPingReadyAt"))
	_set_button(ping_button, true, left <= 0 and GameState.phase() == "investigation", ("Recarga · %d s" % left) if left > 0 else ("Apuntando…" if aiming_ping else "Marca un sitio"))
	var t := _nearest_task()
	task_target = str(t.get("id", ""))
	var busy := _channeling()
	_set_button(task_button, task_target != "", task_target != "" and not busy and GameState.phase() == "investigation",
		"En curso…" if busy else str(t.get("label", "")))
	# Lista de misiones con la distancia a cada una.
	var me := _pos(_me())
	var rows := []
	for task in GameState.ghost_tasks():
		var d := me.distance_to(Protocol.vec2_from(task.get("position", {})))
		rows.append([str(task.get("label", "")), bool(task.get("done", false)), int(d / 10.0) * 10])
	var signature := JSON.stringify(rows)
	if signature == _task_signature:
		return
	_task_signature = signature
	for c in ghost_tasks_box.get_children():
		ghost_tasks_box.remove_child(c)
		c.queue_free()
	if rows.is_empty():
		ghost_tasks_box.add_child(_text("Esperando misiones…", 12, UiPalette.TEXT_DIM))
	for r in rows:
		var l := _text(("✓ " if r[1] else "◆ ") + r[0] + ("" if r[1] else "  ·  %d m" % maxi(1, int(r[2] / 100.0 + 0.5))), 13,
			Color("#64748B") if r[1] else Color("#E9D5FF"))
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = 240
		ghost_tasks_box.add_child(l)

func _refresh_witness(exploring: bool) -> void:
	var entries := GameState.witness_log
	witness_panel.visible = exploring and not entries.is_empty()
	# Debajo del panel de fantasma si se ven los dos.
	witness_panel.offset_top = 236.0 if not ghost_panel.visible else 236.0 + ghost_panel.size.y + 10.0
	if entries.size() == _witness_count:
		return
	_witness_count = entries.size()
	for c in witness_box.get_children():
		witness_box.remove_child(c)
		c.queue_free()
	for w in entries:
		var l := _text(witness_line(w), 13, Color("#FECACA"))
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = 240
		witness_box.add_child(l)

static func witness_line(w: Dictionary) -> String:
	return "Viste a %s silenciar a %s" % [GameState.player_name(str(w.get("killer", ""))), GameState.player_name(str(w.get("victim", "")))]

func _refresh_overlays(ghost: bool, knocked: bool) -> void:
	var me := GameState.public_player(_me())
	if knocked:
		var until = me.get("knockedUntil")
		if until != null:
			_knocked_until = int(until)
	knocked_overlay.visible = knocked and GameState.phase() in VISIBLE_PHASES
	if knocked and not _was_knocked:
		_show_ghost_intro(false)
	_was_knocked = knocked
	# Pasar a fantasma sin evento silenced: expulsado en la asamblea.
	if ghost and not _was_ghost and _ghost_left <= 0.0:
		_show_ghost_intro(true, "Te han expulsado" if GameState.emergency().get("result") is Dictionary else "Te han silenciado")
	_was_ghost = ghost

func _show_ghost_intro(show: bool, title := "Te han silenciado") -> void:
	if show:
		ghost_title.text = title
		_ghost_left = GHOST_INTRO_SECONDS
	else:
		_ghost_left = 0.0
	ghost_overlay.visible = show

func _process(delta: float) -> void:
	if knocked_overlay.visible:
		var left := maxi(0, ceili((float(_knocked_until) - _now()) / 1000.0)) if _knocked_until > 0 else -1
		knocked_timer.text = "Te levantarás en %d s" % left if left >= 0 else "Te levantarás en unos segundos"
	if _ghost_left > 0.0:
		_ghost_left -= delta
		ghost_overlay.modulate.a = clampf(_ghost_left / 0.6, 0.0, 1.0)
		if _ghost_left <= 0.0:
			ghost_overlay.visible = false
	if _banner_left > 0.0:
		_banner_left -= delta
		var t := BANNER_SECONDS - _banner_left
		banner.modulate.a = clampf(minf(t / 0.15, _banner_left / 0.4), 0.0, 1.0)
		banner_title.scale = Vector2.ONE * (1.0 + 0.25 * maxf(0.0, 1.0 - t / 0.25))
		banner_title.pivot_offset = banner_title.size / 2.0
		if _banner_left <= 0.0:
			banner.visible = false
	for c in toasts.get_children():
		var left: float = c.get_meta("left", 0.0) - delta
		c.set_meta("left", left)
		c.modulate.a = clampf(left / 0.5, 0.0, 1.0)
		if left <= 0.0:
			c.queue_free()
	# Recargas y distancias cambian sin snapshot nuevo.
	refresh()

# ───────────── Acciones ─────────────

## Estado del botón de emergencia: visible en la investigación salvo para fantasmas;
## deshabilitado si estás noqueado o ya la usaste (el máximo por partida lo dice el servidor).
static func meeting_button_state() -> Dictionary:
	var used := GameState.meeting_used()
	var knocked := GameState.is_knocked()
	var tip := "Pausa la investigación y reúne a todos para votar a quién expulsar. Solo una vez por partida."
	if used:
		tip = REASON_TEXT["meeting_used"]
	elif knocked:
		tip = "Estás noqueado: no puedes convocar una reunión."
	return {
		"visible": GameState.phase() == "investigation" and not GameState.is_ghost(),
		"disabled": used or knocked,
		"text": MEETING_USED_TEXT if used else MEETING_TEXT,
		"tooltip": tip,
	}

static func apply_meeting_button(b: Button) -> void:
	if b == null:
		return
	var st := meeting_button_state()
	b.visible = st["visible"]
	b.disabled = st["disabled"]
	b.text = st["text"]
	b.tooltip_text = st["tooltip"]

## Pulsa tu botón de emergencia (abre la asamblea de emergencia).
func call_meeting() -> void:
	var st := meeting_button_state()
	if st["visible"] and not st["disabled"]:
		_send(Protocol.I_CALL_MEETING, {}, "meeting")

func _send(type: String, payload: Dictionary, action: String) -> void:
	var seq: int = network.send_intent(type, payload)
	if seq >= 0:
		_pending[seq] = action

func _on_silence_pressed() -> void:
	if silence_target != "" and not silence_button.disabled:
		_silence_used = true
		_send(Protocol.I_SILENCE, {"targetId": silence_target}, "silence")

func _on_escort_pressed() -> void:
	if escort_target != "" and not escort_button.disabled:
		_send(Protocol.I_ESCORT, {"targetId": escort_target}, "escort")

func _on_report_pressed() -> void:
	if report_body != "":
		_send(Protocol.I_REPORT_BODY, {"bodyId": report_body}, "report")

func _on_task_pressed() -> void:
	if task_target != "" and not task_button.disabled:
		var me := players.get_player(_me()) if players else null
		if me:   # la posición exacta antes de canalizar (como al sacar copia de una pista)
			network.send_intent(Protocol.I_MOVE, {"position": Protocol.vec2_to(me.global_position)})
		_send(Protocol.I_GHOST_TASK, {"taskId": task_target}, "ghost_task")

func _on_ping_pressed() -> void:
	if not ping_button.disabled:
		_set_aiming(not aiming_ping)

func _set_aiming(on: bool) -> void:
	aiming_ping = on
	aim_hint.visible = on

## Ping en un punto del mundo (px del mapa 2D).
func send_ping(world_pos: Vector2) -> void:
	_set_aiming(false)
	_send(Protocol.I_GHOST_PING, {"position": Protocol.vec2_to(world_pos)}, "ping")
	toast("Has marcado un sitio para tu equipo.", PING_COLOR)

## Pantalla → mundo con la cámara del mapa.
func screen_to_world(p: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform().affine_inverse() * p

func _unhandled_input(event: InputEvent) -> void:
	if aiming_ping:
		var tap: bool = (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed) or (event is InputEventScreenTouch and event.pressed)
		if tap:
			get_viewport().set_input_as_handled()
			send_ping(screen_to_world(event.position))
			return
		if event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			_set_aiming(false)
			return
	if not (event is InputEventKey and event.pressed and not event.echo) or not actions.visible:
		return
	var buttons := {KEY_F: silence_button, KEY_G: escort_button, KEY_R: report_button, KEY_T: ping_button, KEY_E: task_button}
	var b: Button = buttons.get(event.physical_keycode)
	if b and b.visible and not b.disabled:
		get_viewport().set_input_as_handled()
		b.pressed.emit()

# ───────────── Respuestas y eventos ─────────────

func _on_rejected(seq: int, reason: String) -> void:
	var action = _pending.get(seq)
	if action == null:
		return
	_pending.erase(seq)
	if action == "silence" and reason in ["too_early", "on_cooldown"]:
		_silence_used = reason == "on_cooldown"
	toast(REASON_TEXT.get(reason, reason), Color("#FCA5A5"))

## Aviso corto arriba en el centro.
func toast(text: String, accent := Color("#E2E8F0")) -> Label:
	var l := _text(text, 15, Color.WHITE, UiPalette.bold_font())
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiPalette.flat(Color(0.05, 0.07, 0.13, 0.9), Color(accent, 0.8), 1, 10, 9))
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.set_meta("left", TOAST_SECONDS)
	panel.add_child(l)
	toasts.add_child(panel)
	while toasts.get_child_count() > 4:
		var old := toasts.get_child(0)
		toasts.remove_child(old)
		old.queue_free()
	return l

func toast_texts() -> Array:
	return toasts.get_children().filter(func(c): return not c.is_queued_for_deletion()).map(func(c): return (c.get_child(0) as Label).text)

func _on_silenced(killer: String, victim: String, knocked: bool, until_ms: int) -> void:
	if victim == _me():
		if knocked:
			_knocked_until = until_ms
			_was_knocked = true
			knocked_overlay.visible = true
		else:
			_was_ghost = true
			_show_ghost_intro(true, "Te han silenciado")
	elif killer == _me():
		_silence_used = true
		var who := GameState.player_name(victim)
		if knocked:
			toast("Has noqueado a %s: se levantará en 30 s y no sabrá que fuiste tú." % who, SILENCE_COLOR)
		else:
			toast("%s ya no volverá: ahora es un fantasma." % who, SILENCE_COLOR)

func _on_witnessed(killer: String, victim: String, _at: int) -> void:
	toast(witness_line({"killer": killer, "victim": victim}) + ". Queda en tu registro.", SILENCE_COLOR)
	_witness_count = -1

func _on_escort_blocked(target: String) -> void:
	var who := GameState.player_name(target)
	if target == _me():
		toast("¡Tu escolta te ha protegido de un ataque!", ESCORT_COLOR)
	elif has_power("escort"):
		toast("Has frenado un ataque contra %s." % who, ESCORT_COLOR)
	else:
		_silence_used = true
		toast("%s estaba escoltado: tu intento ha fallado." % who, SILENCE_COLOR)

func _on_body_reported(by: String, body_id: String, victim: String) -> void:
	if victim == "":
		victim = body_id.trim_prefix("body:").get_slice("#", 0)
	show_banner("¡CUERPO ENCONTRADO!", "%s ha encontrado a %s" % [GameState.player_name(by), GameState.player_name(victim)])

func _on_meeting_called(by: String) -> void:
	show_banner("¡REUNIÓN DE EMERGENCIA!", "%s ha pulsado el botón de emergencia" % GameState.player_name(by))

func show_banner(title: String, sub: String) -> void:
	banner_title.text = title
	banner_sub.text = sub
	banner.visible = true
	banner.modulate.a = 0.0
	_banner_left = BANNER_SECONDS

func _on_emergency_result(expelled: String, _tally: Dictionary) -> void:
	toast(EmergencyPanel.result_text(expelled), SILENCE_COLOR if expelled != "" else UiPalette.AMBER)
