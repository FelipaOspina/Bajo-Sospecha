extends Node
## Réplica local del estado que el servidor nos permite ver (RoomSnapshot).
## Aplica snapshots y deltas, y traduce eventos de red a señales de EventBus.
## Nunca modifica el estado por iniciativa propia: el servidor es la verdad.

signal snapshot_applied(snapshot: Dictionary)

var snapshot: Dictionary = {}
var version := -1

func _ready() -> void:
	Network.message_received.connect(_on_message)

func _on_message(msg: Dictionary) -> void:
	match msg.get("t"):
		Protocol.M_WELCOME, Protocol.M_SNAPSHOT:
			_replace(msg["snapshot"])
		Protocol.M_DELTA:
			_apply_delta(msg)
		Protocol.M_EVENT:
			_route_event(msg["event"])

## Sin sala (vuelta al menú): todo lo que dependa del estado se vacía.
func reset() -> void:
	snapshot = {}
	version = -1
	snapshot_applied.emit(snapshot)

func _replace(s: Dictionary) -> void:
	var previous_role = snapshot.get("you", {}) if snapshot.get("you") else {}
	snapshot = s
	version = int(s.get("version", 0))
	_after_change(previous_role)

func _apply_delta(msg: Dictionary) -> void:
	# Copia: los ops modifican snapshot en el sitio y, sin copiar, "antes" y "después"
	# serían el mismo diccionario (nunca se detectaría el cambio de inventario o rol).
	var previous_role: Dictionary = snapshot.get("you").duplicate(true) if snapshot.get("you") is Dictionary else {}
	for op in msg["ops"]:
		_apply_op(snapshot, op["path"], op.get("value"), op["op"] == "remove")
	version = int(msg["to"])
	snapshot["version"] = version
	_after_change(previous_role)

## Aplica una operación set/remove en una ruta tipo ["players", 2, "position"].
static func _apply_op(root, path: Array, value, remove: bool) -> void:
	var node = root
	for i in range(path.size() - 1):
		node = node[_key(node, path[i])]
	var last = _key(node, path[-1])
	if remove:
		if node is Dictionary:
			node.erase(last)
	else:
		node[last] = value

static func _key(container, k):
	return int(k) if container is Array else k

func _after_change(previous_you: Dictionary) -> void:
	var you = snapshot.get("you")
	if you is Dictionary:
		if previous_you.get("roleId") != you.get("roleId"):
			EventBus.role_revealed.emit(you["roleId"])
		if previous_you.get("inventory") != you.get("inventory"):
			EventBus.inventory_changed.emit(you["inventory"])
	snapshot_applied.emit(snapshot)

func _route_event(e: Dictionary) -> void:
	match e.get("e"):
		Protocol.E_PHASE_CHANGED:
			snapshot["phase"] = e["phase"]
			EventBus.phase_changed.emit(e["phase"], int(e["endsAt"]) if e["endsAt"] != null else -1)
		Protocol.E_EVIDENCE_COLLECTED:
			EventBus.evidence_collected.emit(e["by"], e["interactableId"], e.get("evidence", {}) if e.get("evidence") else {})
		Protocol.E_EVIDENCE_DROPPED:
			EventBus.evidence_dropped.emit(e["by"], e["interactableId"])
		Protocol.E_EVIDENCE_DESTROYED:
			EventBus.evidence_destroyed.emit(e["by"])
		Protocol.E_EVIDENCE_PRESENTED:
			EventBus.evidence_presented.emit(e["by"], e["evidence"])
		Protocol.E_CHANNEL_STARTED:
			EventBus.channel_started.emit(e["by"], e["channel"])
		Protocol.E_CHANNEL_FINISHED:
			EventBus.channel_finished.emit(e["by"], e["ok"], str(e.get("reason", "")))
		Protocol.E_GAME_OVER:
			EventBus.game_over.emit(e["resolution"])
		Protocol.E_CHAT:
			EventBus.chat_received.emit(str(e.get("by", "")), str(e.get("name", "")), str(e.get("text", "")), int(e.get("at", 0)))
		Protocol.E_ABILITY_USED:
			var ends = e.get("endsAt")
			EventBus.ability_used.emit(str(e.get("by", "")), str(e.get("abilityId", "")), int(ends) if ends != null else -1,
				e.get("marks", []) if e.get("marks") is Array else [], e.get("affected", []) if e.get("affected") is Array else [])

# ───── Consultas de conveniencia ─────

func local_player_id() -> String:
	return Network.player_id

## Estamos dentro de una sala (en el lobby o en partida).
func in_room() -> bool:
	return snapshot.get("lobby") is Dictionary

func phase() -> String:
	return str(snapshot.get("phase", ""))

## Datos de la sala: código, visibilidad, anfitrión, plazas y cuenta atrás.
func lobby() -> Dictionary:
	var l = snapshot.get("lobby")
	return l if l is Dictionary else {}

func my_private_state() -> Dictionary:
	var you = snapshot.get("you")
	return you if you is Dictionary else {}

func players() -> Array:
	return snapshot.get("players", [])

func interactable_view(id: String) -> Dictionary:
	for i in snapshot.get("interactables", []):
		if i["id"] == id:
			return i
	return {}
