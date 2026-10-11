class_name EvidenceSystem
extends Node
## Fachada de pruebas en el cliente.
##  - E sobre un objeto enfocado → interact() del objeto (las pistas abren el visor).
##  - Traduce acciones del jugador en INTENCIONES de red (recoger, soltar...).
##  - Expone señales listas para la UI (errores, eventos ajenos).
##
## Depende de abstracciones inyectables (network, role_manager, detector,
## inventory) para poder probarlo con dobles sin abrir sockets.

signal action_failed(reason: String)
signal evidence_gained(evidence: EvidenceData)
signal someone_collected(player_id: String, interactable_id: String)

const REASON_TEXT := {
	"out_of_range": "Estás demasiado lejos.",
	"inventory_full": "No te cabe nada más.",
	"wrong_phase": "Ahora no puedes hacer eso.",
	"nothing_found": "Ya no está aquí.",
	"cannot_destroy": "No puedes destruir esta prueba.",
	"not_alive": "Ya no puedes interactuar.",
	"not_pocketable": "No puedes llevártela; solo examinarla aquí.",
	"requires_role": "Tu rol no te permite llevártela.",
	"requires_item": "Te falta algo para poder llevártela.",
	"action_not_allowed": "Tu rol no puede hacer eso.",
	"already_channeling": "Ya estás haciendo otra cosa.",
	"moved": "Te has movido: acción interrumpida.",
}

@export var detector_path: NodePath
@export var inventory: InventoryManager

var network: Node            # por defecto el autoload Network
var role_manager: RoleManager

var _detector: InteractionDetector
var _pending_actions := {}   # seq -> acción, para mensajes de error

func _ready() -> void:
	if network == null:
		network = Network
	if detector_path:
		_detector = get_node(detector_path)
	EventBus.intent_rejected.connect(_on_rejected)
	EventBus.evidence_collected.connect(_on_collected)
	network.message_received.connect(_on_message)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact") and _detector and _detector.focused:
		get_viewport().set_input_as_handled()
		_detector.focused.interact()

## El detector vive en el personaje local, que aparece cuando llega el estado.
func set_detector(player: Node) -> void:
	_detector = player.get_node_or_null("InteractionDetector")

# ───── Acciones (solo piden; el servidor responde) ─────

## Empieza una acción canalizada ("delete" o "backup"). El jugador debe quedarse
## quieto; la barra de progreso la pinta ChannelPresenter con el estado del servidor.
func start_channel(instance_id: String, kind: String) -> void:
	# La posición se envía a 20 Hz: mandamos la actual antes, para que el servidor
	# no tome como "moverse" el último tramo recorrido justo antes de pulsar.
	var me = _detector.get_parent() if _detector else null
	if me is Node2D:
		network.send_intent(Protocol.I_MOVE, {"position": Protocol.vec2_to(me.global_position)})
	_track(network.send_intent(Protocol.I_CHANNEL_START, {"evidenceInstanceId": instance_id, "action": kind}), "channel")

func cancel_channel() -> void:
	network.send_intent(Protocol.I_CHANNEL_CANCEL, {})

## Guardar en el inventario. instance_id elige la pieza concreta del visor.
func collect(interactable_id: String, instance_id: String = "") -> void:
	var payload := {"interactableId": interactable_id}
	if instance_id != "":
		payload["evidenceInstanceId"] = instance_id
	_track(network.send_intent(Protocol.I_INTERACT, payload), "collect")

func drop(instance_id: String) -> void:
	_track(network.send_intent(Protocol.I_DROP, {"evidenceInstanceId": instance_id}), "drop")

func destroy(instance_id: String) -> void:
	var e := inventory.get_item(instance_id) if inventory else null
	if e and role_manager and not role_manager.can_destroy(e.tags):
		action_failed.emit(REASON_TEXT["cannot_destroy"])  # feedback inmediato; el servidor valida igual
		return
	_track(network.send_intent(Protocol.I_DESTROY, {"evidenceInstanceId": instance_id}), "destroy")

func present(instance_id: String) -> void:
	_track(network.send_intent(Protocol.I_PRESENT, {"evidenceInstanceId": instance_id}), "present")

# ───── Respuestas del servidor ─────

func _on_message(msg: Dictionary) -> void:
	if msg.get("t") == Protocol.M_ACK:
		_pending_actions.erase(int(msg["seq"]))

func _on_rejected(seq: int, reason: String) -> void:
	if _pending_actions.erase(seq):
		action_failed.emit(REASON_TEXT.get(reason, reason))

func _on_collected(by: String, interactable_id: String, evidence: Dictionary) -> void:
	if by == GameState.local_player_id() and not evidence.is_empty():
		evidence_gained.emit(EvidenceData.from_view(evidence))
	else:
		someone_collected.emit(by, interactable_id)

func _track(seq: int, action: String) -> void:
	if seq >= 0:
		_pending_actions[seq] = action
