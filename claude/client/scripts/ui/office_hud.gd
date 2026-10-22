class_name OfficeHUD
extends CanvasLayer
## HUD de exploración estilo oficina (escena scenes/ui/OfficeHUD.tscn):
##  - Panel de Tareas arriba a la izquierda (con diseño glassmorphism y tareas corporativas de referencia)
##  - Minimapa circular arriba a la derecha con silueta de oficina y botón de ajustes ⚙️
##  - Joystick virtual abajo a la izquierda para control táctil/ratón
##  - Botón de carrera con icono de zapatilla 👟 abajo a la derecha
##  - Se oculta fuera de la exploración (asamblea, resultados)

signal in_game_menu_requested

const VISIBLE_PHASES := ["briefing", "investigation"]

@export var players: PlayerSpawner

@onready var tasks_panel: PanelContainer = $TasksPanel
@onready var title: Label = %TasksTitle
@onready var task_list: VBoxContainer = %TaskList
@onready var minimap: CircularMinimap = %Minimap
@onready var joystick: VirtualJoystick = $VirtualJoystick
@onready var sprint_button: SprintButton = $SprintButton
@onready var settings_btn: Button = $SettingsButton

var ability_button: AbilityButton
## Botón de emergencia (call_meeting) junto al de ajustes; lo envía SocialHUD.
var meeting_button: Button
var _signature := ""
var _tasks: Array = []
var _ghost := false

func _ready() -> void:
	# Estilo del panel de tareas (cristal oscuro translúcido con esquinas redondeadas)
	var card := StyleBoxFlat.new()
	card.bg_color = Color(0.08, 0.12, 0.20, 0.76)
	card.border_color = Color(1.0, 1.0, 1.0, 0.18)
	card.set_border_width_all(1)
	card.set_corner_radius_all(16)
	card.shadow_color = Color(0, 0, 0, 0.45)
	card.shadow_size = 6
	card.content_margin_left = 18
	card.content_margin_right = 18
	card.content_margin_top = 16
	card.content_margin_bottom = 18
	tasks_panel.add_theme_stylebox_override("panel", card)

	title.add_theme_font_override("font", UiPalette.heading_font())
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color.WHITE)

	minimap.players = players

	# Botón de ajustes ⚙️ (esquina superior derecha para abrir el menú en partida)
	var gear_style := StyleBoxFlat.new()
	gear_style.bg_color = Color(0.08, 0.12, 0.20, 0.8)
	gear_style.border_color = Color(1.0, 1.0, 1.0, 0.25)
	gear_style.set_border_width_all(1)
	gear_style.set_corner_radius_all(20)
	gear_style.shadow_color = Color(0, 0, 0, 0.4)
	gear_style.shadow_size = 4
	settings_btn.add_theme_stylebox_override("normal", gear_style)
	settings_btn.add_theme_stylebox_override("hover", gear_style)
	settings_btn.add_theme_stylebox_override("pressed", gear_style)
	settings_btn.visible = true
	settings_btn.pressed.connect(func() -> void: in_game_menu_requested.emit())

	# Botón de emergencia 🚨 (junto al botón de ajustes): abre la asamblea de EMERGENCIA
	# (no el juicio final). Una vez por jugador y partida; no para fantasmas ni noqueados.
	var meeting_btn := Button.new()
	meeting_btn.name = "CallMeetingButton"
	meeting_btn.text = SocialHUD.MEETING_TEXT
	meeting_btn.focus_mode = Control.FOCUS_NONE
	meeting_btn.anchors_preset = Control.PRESET_TOP_RIGHT
	meeting_btn.anchor_left = 1.0
	meeting_btn.anchor_right = 1.0
	meeting_btn.grow_horizontal = Control.GROW_DIRECTION_BEGIN   # el texto largo crece hacia la izquierda
	meeting_btn.offset_left = -540.0
	meeting_btn.offset_right = -255.0
	meeting_btn.offset_top = 20.0
	meeting_btn.offset_bottom = 56.0
	UiPalette.style_button(meeting_btn, UiPalette.CRIMSON)
	meeting_btn.pressed.connect(func() -> void: EventBus.emergency_meeting_requested.emit())
	add_child(meeting_btn)
	meeting_button = meeting_btn

	_update_touch_controls_visibility()
	_add_ability_button()
	GameState.snapshot_applied.connect(_on_snapshot)
	_on_snapshot(GameState.snapshot)
	_rebuild()

## Habilidad activa del animal (tecla Q) abajo a la derecha; en móvil, encima del botón de correr.
func _add_ability_button() -> void:
	ability_button = AbilityButton.new()
	ability_button.name = "AbilityButton"
	ability_button.anchor_left = 1.0
	ability_button.anchor_right = 1.0
	ability_button.anchor_top = 1.0
	ability_button.anchor_bottom = 1.0
	var lift := 150.0 if sprint_button and sprint_button.visible else 0.0
	ability_button.offset_left = -AbilityButton.WIDTH - 20.0
	ability_button.offset_right = -20.0
	ability_button.offset_top = -AbilityButton.SIZE - 66.0 - lift
	ability_button.offset_bottom = -20.0 - lift
	add_child(ability_button)

func _update_touch_controls_visibility() -> void:
	# En PC los botones táctiles desaparecen; en móviles o pantallas táctiles aparecen
	var is_mobile: bool = OS.has_feature("mobile") or OS.has_feature("android") or OS.has_feature("ios") or DisplayServer.is_touchscreen_available()
	if joystick:
		joystick.visible = is_mobile
	if sprint_button:
		sprint_button.visible = is_mobile

func tasks() -> Array:
	return _tasks


func _on_snapshot(s: Dictionary) -> void:
	visible = s.get("phase", "lobby") in VISIBLE_PHASES
	SocialHUD.apply_meeting_button(meeting_button)
	# Los fantasmas no usan la activa de su animal.
	var ghost := GameState.is_ghost()
	if ghost != _ghost and ability_button:
		_ghost = ghost
		ability_button.visible = not ghost and not AnimalAbilities.kit(Abilities.skin_id).get("active", {}).is_empty()
	var objectives: Array = GameState.my_private_state().get("objectives", [])
	var signature := JSON.stringify(objectives)
	if signature == _signature:
		return
	_signature = signature
	_tasks.clear()
	var active_found := false
	for o in objectives:
		var state := "done"
		if not o.get("completed", false):
			state = "pending" if active_found else "active"
			active_found = true
		_tasks.append({"text": str(o.get("description", "")), "state": state})
	_rebuild()

func _rebuild() -> void:
	for c in task_list.get_children():
		task_list.remove_child(c)
		c.queue_free()

	if _tasks.is_empty():
		var waiting := Label.new()
		waiting.text = "Esperando el reparto de roles…"
		waiting.add_theme_color_override("font_color", UiPalette.TEXT_DIM)
		task_list.add_child(waiting)
		return
	for t in _tasks:
		task_list.add_child(_row(t["text"], t["state"]))

func _row(text: String, state: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)

	# Viñeta circular de estado (blanco/hollow, amarillo brillante o gris)
	var dot := Panel.new()
	dot.name = "StatusDot"
	dot.custom_minimum_size = Vector2(14, 14)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	var dot_style := StyleBoxFlat.new()
	dot_style.set_corner_radius_all(7)
	if state == "active":
		dot_style.bg_color = UiPalette.AMBER
		dot_style.border_color = Color("#FEF08A")
		dot_style.set_border_width_all(1)
		dot_style.shadow_color = Color(0.96, 0.62, 0.05, 0.5)
		dot_style.shadow_size = 4
	elif state == "done":
		dot_style.bg_color = Color("#475569")
		dot_style.border_color = Color("#64748B")
		dot_style.set_border_width_all(1)
	else:
		# pending: blanco pizarra
		dot_style.bg_color = Color("#E2E8F0")
		dot_style.border_color = Color(1, 1, 1, 0.65)
		dot_style.set_border_width_all(1)

	dot.add_theme_stylebox_override("panel", dot_style)
	row.add_child(dot)

	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = 210
	label.add_theme_font_size_override("font_size", 15)
	if state == "active":
		label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))
	elif state == "done":
		label.add_theme_color_override("font_color", Color("#64748B"))
	else:
		label.add_theme_color_override("font_color", Color(0.9, 0.92, 0.95, 0.95))

	row.add_child(label)
	return row
