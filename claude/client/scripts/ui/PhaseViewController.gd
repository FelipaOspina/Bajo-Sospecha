class_name PhaseViewController
extends Node
## Cambia de vista según la fase que manda el servidor:
##  - menú (sin sala o en la sala de espera): oculta y pausa el mapa; se ve MainMenu;
##  - exploración (briefing / investigación): mapa visible y activo;
##  - asamblea (debate / votación): oculta y pausa el mapa (nadie se mueve ni manda
##    posiciones), cierra el modal de inspección y despliega AssemblyBoardUI;
##  - resultados: se cierra la mesa (la pantalla final la abre ResolutionScreen).
## Es el único sitio que decide qué vista se ve; las vistas solo exponen open/close.

signal view_changed(view: String)

const VIEW_MENU := "menu"
const VIEW_EXPLORATION := "exploration"
const VIEW_ASSEMBLY := "assembly"
const VIEW_RESULTS := "results"
const ASSEMBLY_PHASES := ["discussion", "voting"]
const MENU_PHASES := ["", "lobby"]

@export var exploration_view: CanvasItem      # normalmente Main/Map
@export var board: AssemblyBoardUI
@export var inspection_modal: EvidenceInspectionModal

var view := ""

func _ready() -> void:
	GameState.snapshot_applied.connect(func(s: Dictionary) -> void: apply_phase(str(s.get("phase", ""))))
	EventBus.phase_changed.connect(func(phase: String, _ends: int) -> void: apply_phase(phase))

static func view_for(phase: String) -> String:
	if phase in MENU_PHASES:
		return VIEW_MENU
	if phase in ASSEMBLY_PHASES:
		return VIEW_ASSEMBLY
	if phase == "results":
		return VIEW_RESULTS
	return VIEW_EXPLORATION

func apply_phase(phase: String) -> void:
	var next := view_for(phase)
	if next == view:
		return
	view = next
	var exploring := next == VIEW_EXPLORATION
	if exploration_view:
		exploration_view.visible = exploring
		exploration_view.process_mode = Node.PROCESS_MODE_INHERIT if exploring else Node.PROCESS_MODE_DISABLED
	if not exploring:
		# Las canalizaciones en curso las corta el servidor al cambiar de fase.
		if inspection_modal:
			inspection_modal.close()
	if board:
		if next == VIEW_ASSEMBLY:
			board.open_board()
		else:
			board.close_board()
	view_changed.emit(next)
