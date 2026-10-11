extends Node
## Composition root del cliente: crea y conecta los sistemas.
## Arranca en el menú (MainMenu): perfil, sala de espera, cola pública, pase y tienda.
## Con room_code (export o variable de entorno ROOM) entra directo a esa sala y se
## marca listo, como antes (bots y pruebas rápidas); el menú muestra esa sala.

## Caso a cargar: id en data/scenarios/ (también casos en formato libre, p. ej.
## "caso_fraude_tech_startup"). El servidor debe usar el mismo SCENARIO.
@export var scenario_id := "nexuscore_fraude"
## Se usa solo si scenario_id está vacío.
@export var role_set_id := "mansion_clasica"
## Solo para la entrada directa (en el menú, el nombre es el del perfil).
@export var player_name := "Jugador"
## Entrada directa a la sala con este código. Vacío = menú.
@export var room_code := ""

@onready var role_manager: RoleManager = $RoleManager
@onready var evidence_system: EvidenceSystem = $EvidenceSystem
@onready var scenario_manager: ScenarioManager = $ScenarioManager
@onready var player_spawner: PlayerSpawner = $Map/Players
@onready var assembly: TrialAssemblyManager = $TrialAssemblyManager
@onready var board: AssemblyBoardUI = $UI/AssemblyBoardUI
@onready var resolution: ResolutionScreen = $UI/ResolutionScreen
@onready var menu: MainMenu = $MainMenu

func _ready() -> void:
	if OS.get_environment("ROOM") != "":
		room_code = OS.get_environment("ROOM")
	if scenario_id.is_empty():
		role_manager.load_role_set(role_set_id)
	elif not scenario_manager.load_scenario(scenario_id):
		return
	evidence_system.role_manager = role_manager
	player_spawner.local_player_spawned.connect(evidence_system.set_detector)
	# La mesa pide exponer una carta de la mano → la lógica del juicio la envía al servidor.
	board.evidence_presented.connect(func(e: EvidenceData, _player_id: String) -> void: assembly.present(e.instance_id))
	resolution.back_to_menu_requested.connect(back_to_menu)
	# Olfato del perro: marcas sobre los escondites (solo las ve quien la usa).
	var scent := ScentMarkers.new()
	scent.name = "ScentMarkers"
	$Map.add_child(scent)
	EventBus.disconnected_from_server.connect(_on_disconnected)
	var title := scenario_manager.current.title if scenario_manager.current else ""
	menu.set_case(title if title != "" else "Caso sin título", scenario_id)
	if room_code != "":
		EventBus.connected_to_server.connect(_on_connected_direct)
		await Network.connect_to_server(player_name, room_code)
	else:
		menu.start()

func _on_connected_direct(player_id: String) -> void:
	print("Conectado como ", player_id, " en la sala ", Network.room_code)
	Network.send_intent(Protocol.I_READY, {"ready": true})

## Tras la partida: sale de la sala y recarga la escena (mapa limpio) con el menú.
func back_to_menu() -> void:
	if GameState.in_room():
		Account.leave_room()
	get_tree().reload_current_scene()

## Si se cae la conexión a mitad de partida, de vuelta al menú (que ofrece reintentar).
func _on_disconnected(_reason: String) -> void:
	if GameState.in_room():
		Network.forget_room()
		GameState.reset()
		get_tree().reload_current_scene()
