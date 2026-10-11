extends Node
## Composition root del cliente: crea y conecta los sistemas.

## Caso a cargar: id en data/scenarios/ (también casos en formato libre, p. ej.
## "caso_fraude_tech_startup"). El servidor debe usar el mismo SCENARIO.
@export var scenario_id := "nexuscore_fraude"
## Se usa solo si scenario_id está vacío.
@export var role_set_id := "mansion_clasica"
@export var player_name := "Jugador"
## Vacío = sala pública. Los jugadores con el mismo código juegan juntos.
@export var room_code := ""

@onready var role_manager: RoleManager = $RoleManager
@onready var evidence_system: EvidenceSystem = $EvidenceSystem
@onready var scenario_manager: ScenarioManager = $ScenarioManager
@onready var player_spawner: PlayerSpawner = $Map/Players
@onready var assembly: TrialAssemblyManager = $TrialAssemblyManager
@onready var board: AssemblyBoardUI = $UI/AssemblyBoardUI

func _ready() -> void:
	if scenario_id.is_empty():
		role_manager.load_role_set(role_set_id)
	elif not scenario_manager.load_scenario(scenario_id):
		return
	evidence_system.role_manager = role_manager
	player_spawner.local_player_spawned.connect(evidence_system.set_detector)
	# La mesa pide exponer una carta de la mano → la lógica del juicio la envía al servidor.
	board.evidence_presented.connect(func(e: EvidenceData, _player_id: String) -> void: assembly.present(e.instance_id))
	EventBus.connected_to_server.connect(_on_connected)
	await Network.connect_to_server(player_name, room_code)

func _on_connected(player_id: String) -> void:
	print("Conectado como ", player_id, " en la sala ", Network.room_code)
	Network.send_intent(Protocol.I_READY, {"ready": true})
