extends CanvasLayer
## Consejos contextuales en las primeras partidas (Ruta del Detective): mientras el perfil
## está por debajo de detective_path.hint_max_level y no se han desactivado en
## Configuración, enseña cada consejo una vez por partida cuando pasa lo que explica
## (empieza la investigación, te acercas a una pista, hay un cuerpo cerca, asamblea...).
## Solo reacciona a lo que el jugador ya ve en su pantalla y los textos son iguales para
## todos los roles: un consejo nunca delata el rol de nadie. Durante la práctica local
## («Primer día en NexusCore») no sale: allí guía su propio panel.
## MainMenu lo crea (sin tocar Main): un nodo hermano suyo.

const SHOW_SECONDS := 7.0
const GAP_SECONDS := 1.2
const BODY_NEAR := 260.0

## id → texto. Los ids son los que se marcan como ya vistos en la partida.
const HINTS := {
	"briefing": "Lee tu rol y tus objetivos. Es tu secreto: no se lo digas a nadie.",
	"explore": "Explora con WASD o el joystick. Solo ves lo que tienes a la vista; los objetos que brillan esconden pruebas.",
	"focus": "Pulsa E o haz clic para examinar lo que tienes delante.",
	"collected": "Prueba guardada. En el juicio podrás exponer hasta 2: guarda las que se confirmen entre sí.",
	"channel": "Quédate quieto hasta que se llene la barra: moverte interrumpe la acción.",
	"body": "Hay alguien en el suelo cerca: acércate y pulsa REPORTAR [R] para convocar una asamblea.",
	"witness": "Lo has visto con tus ojos. Cuéntalo en la próxima asamblea: es tu testimonio.",
	"knocked": "Estás noqueado unos segundos. Ya no podrás exponer pruebas en el juicio, pero sí votar.",
	"ghost": "Eres un fantasma: atraviesas paredes y tus misiones fantasma ayudan a tu equipo.",
	"emergency": "Asamblea de emergencia: escucha, habla y vota a un jugador o «Saltar». Hace falta mayoría.",
	"discussion": "Juicio final: arrastra tus mejores pruebas a la mesa (máx. 2) y explica qué demuestran.",
	"voting": "Vota la decisión final según las pruebas de la mesa. El voto es secreto hasta el final.",
}

var panel: PanelContainer
var label: Label
var queue: Array[String] = []
var shown := {}
var current := ""
var _left := 0.0
var _gap := 0.0
var _scan := 0.0

func _ready() -> void:
	layer = 45
	name = "MatchHints"
	_build()
	EventBus.phase_changed.connect(func(phase: String, _e: int) -> void: _on_phase(phase))
	GameState.snapshot_applied.connect(_on_snapshot)
	EventBus.interactable_focused.connect(func(_i) -> void: hint("focus"))
	EventBus.evidence_collected.connect(func(by: String, _i: String, _e: Dictionary) -> void:
		if by == GameState.local_player_id():
			hint("collected"))
	EventBus.channel_started.connect(func(by: String, _c: Dictionary) -> void:
		if by == GameState.local_player_id():
			hint("channel"))
	EventBus.witnessed.connect(func(_k: String, _v: String, _a: int) -> void: hint("witness"))
	EventBus.silenced.connect(func(_k: String, victim: String, knocked: bool, _u: int) -> void:
		if victim == GameState.local_player_id():
			hint("knocked" if knocked else "ghost"))

## Se pueden enseñar ahora (ajuste, nivel y fuera de la práctica).
func enabled() -> bool:
	return Account.wants_hints() and Network.local_server == null and GameState.in_room()

## Pone en cola un consejo si no ha salido ya en esta partida.
func hint(id: String) -> bool:
	if not enabled() or shown.has(id) or not HINTS.has(id):
		return false
	shown[id] = true
	queue.append(id)
	return true

func _on_phase(phase: String) -> void:
	match phase:
		"lobby", "":
			shown.clear()
			queue.clear()
			_hide()
		"briefing":
			hint("briefing")
		"investigation":
			hint("explore")
		"emergency", "discussion", "voting":
			queue.clear()
			_hide()
			hint(phase)

func _on_snapshot(s: Dictionary) -> void:
	if s.is_empty():
		shown.clear()
		queue.clear()
		_hide()
		return
	if GameState.is_ghost():
		hint("ghost")

func _process(delta: float) -> void:
	_scan -= delta
	if _scan <= 0.0:
		_scan = 0.5
		_scan_bodies()
	if _left > 0.0:
		_left -= delta
		if _left <= 0.0:
			_hide()
		return
	if _gap > 0.0:
		_gap -= delta
		return
	if not queue.is_empty():
		_show(queue.pop_front())

func _scan_bodies() -> void:
	if shown.has("body") or GameState.phase() != "investigation" or GameState.is_ghost():
		return
	var me := GameState.public_player(GameState.local_player_id())
	if me.is_empty():
		return
	var at := Protocol.vec2_from(me.get("position", {}))
	for b in GameState.bodies():
		if not b.get("reported", false) and Protocol.vec2_from(b.get("position", {})).distance_to(at) <= BODY_NEAR:
			hint("body")
			return

func _show(id: String) -> void:
	current = id
	label.text = HINTS[id]
	panel.show()
	_left = SHOW_SECONDS
	panel.modulate.a = 0.0
	create_tween().tween_property(panel, "modulate:a", 1.0, 0.2)

func _hide() -> void:
	if panel.visible:
		_gap = GAP_SECONDS
	panel.hide()
	current = ""
	_left = 0.0

func _build() -> void:
	var anchor := Control.new()
	anchor.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(anchor)
	panel = PanelContainer.new()
	panel.name = "HintPanel"
	panel.add_theme_stylebox_override("panel", UiPalette.flat(Color(UiPalette.NAVY, 0.92), Color(UiPalette.AMBER, 0.8), 1, 12, 12))
	panel.custom_minimum_size = Vector2(520, 0)
	panel.position = Vector2(-260, 96)
	anchor.add_child(panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	panel.add_child(row)
	var icon := MenuIcon.make("star", UiPalette.AMBER, 20)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(icon)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(col)
	var title := Label.new()
	title.text = "CONSEJO DE LA RUTA DEL DETECTIVE"
	title.add_theme_font_override("font", UiPalette.bold_font())
	title.add_theme_font_size_override("font_size", 10)
	title.add_theme_color_override("font_color", UiPalette.AMBER)
	col.add_child(title)
	label = Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", UiPalette.TEXT)
	col.add_child(label)
	var close := Button.new()
	close.name = "CloseHint"
	close.text = "✕"
	close.flat = true
	close.focus_mode = Control.FOCUS_NONE
	close.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	close.pressed.connect(_hide)
	row.add_child(close)
	panel.hide()
