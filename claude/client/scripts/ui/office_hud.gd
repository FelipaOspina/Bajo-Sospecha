class_name OfficeHUD
extends CanvasLayer
## HUD de exploración estilo oficina (escena scenes/ui/OfficeHUD.tscn):
##  - Panel de Tareas arriba a la izquierda: los objetivos secretos de tu rol, con un
##    punto de estado (blanco pendiente, ámbar el activo, gris hecho). Solo los ves tú:
##    vienen de "you" en el snapshot, que el servidor solo te envía a ti.
##  - Minimapa circular arriba a la derecha (CircularMinimap).
##  - Habilidad activa de tu animal abajo a la derecha (AbilityButton, tecla Q).
## Se oculta fuera de la exploración (asamblea, resultados). Usa el Theme global
## (corporate_theme.tres): el PanelContainer toma el panel de cristal.

const VISIBLE_PHASES := ["briefing", "investigation"]
const DOT_COLORS := {"pending": Color("#E2E8F0"), "active": UiPalette.AMBER, "done": Color("#64748B")}

@export var players: PlayerSpawner

@onready var title: Label = %TasksTitle
@onready var task_list: VBoxContainer = %TaskList
@onready var minimap: CircularMinimap = %Minimap
var ability_button: AbilityButton

var _signature := ""
var _tasks: Array = []   # [{text, state}]

func _ready() -> void:
	title.add_theme_font_override("font", UiPalette.heading_font())
	minimap.players = players
	ability_button = AbilityButton.new()
	ability_button.name = "AbilityButton"
	ability_button.anchor_left = 1.0
	ability_button.anchor_right = 1.0
	ability_button.anchor_top = 1.0
	ability_button.anchor_bottom = 1.0
	ability_button.offset_left = -AbilityButton.WIDTH - 20.0
	ability_button.offset_right = -20.0
	ability_button.offset_top = -AbilityButton.SIZE - 66.0
	ability_button.offset_bottom = -20.0
	add_child(ability_button)
	GameState.snapshot_applied.connect(_on_snapshot)
	_on_snapshot(GameState.snapshot)

## Tareas mostradas: [{text, state: "pending" | "active" | "done"}].
func tasks() -> Array:
	return _tasks

func _on_snapshot(s: Dictionary) -> void:
	visible = s.get("phase", "lobby") in VISIBLE_PHASES
	var objectives: Array = GameState.my_private_state().get("objectives", [])
	var signature := JSON.stringify(objectives)
	if signature == _signature:
		return   # los deltas llegan a 20 Hz: solo se reconstruye si cambian
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
	row.add_theme_constant_override("separation", 10)
	var dot := Panel.new()
	dot.name = "StatusDot"
	dot.custom_minimum_size = Vector2(10, 10)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dot.add_theme_stylebox_override("panel", UiPalette.flat(DOT_COLORS[state], Color(0, 0, 0, 0.4), 1, 5, 0))
	row.add_child(dot)
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = 210
	label.add_theme_font_size_override("font_size", 14)
	if state == "done":
		label.add_theme_color_override("font_color", UiPalette.TEXT_DIM)
	row.add_child(label)
	return row
