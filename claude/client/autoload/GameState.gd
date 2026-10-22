extends Node
## Réplica local del estado que el servidor nos permite ver (RoomSnapshot).
## Aplica snapshots y deltas, y traduce eventos de red a señales de EventBus.
## Nunca modifica el estado por iniciativa propia: el servidor es la verdad.

signal snapshot_applied(snapshot: Dictionary)

var snapshot: Dictionary = {}
var version := -1
## Marcas efímeras de los fantasmas que te han llegado (las dibujan la vista 3D y el minimapa):
## pings [{by, position, until}] y pistas que brillan {interactableId: {position, until}}.
var ghost_pings: Array = []
var ghost_reveals: Dictionary = {}
## Silenciamientos que has visto con tus ojos (evento witnessed): [{killer, victim, at}].
## Se guardan toda la partida: son tu testimonio en la asamblea.
var witness_log: Array = []

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
	ghost_pings.clear()
	ghost_reveals.clear()
	witness_log.clear()
	snapshot_applied.emit(snapshot)

func _replace(s: Dictionary) -> void:
	if str(s.get("phase", "")) == "lobby":
		ghost_pings.clear()
		ghost_reveals.clear()
		witness_log.clear()
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
		Protocol.E_SILENCED:
			EventBus.silenced.emit(_str(e.get("killer")), _str(e.get("victim")), bool(e.get("knocked", false)), _ms(e.get("until")))
		Protocol.E_WITNESSED:
			witness_log.append({"killer": _str(e.get("killer")), "victim": _str(e.get("victim")), "at": _ms(e.get("at"))})
			EventBus.witnessed.emit(_str(e.get("killer")), _str(e.get("victim")), _ms(e.get("at")))
		Protocol.E_BODY_REPORTED:
			EventBus.body_reported.emit(_str(e.get("by")), _str(e.get("bodyId")), _str(e.get("victim")))
		Protocol.E_MEETING_CALLED:
			EventBus.meeting_called.emit(_str(e.get("by")))
		Protocol.E_EMERGENCY_RESULT:
			EventBus.emergency_result.emit(_str(e.get("expelled")), e.get("tally") if e.get("tally") is Dictionary else {})
		Protocol.E_ESCORT_BLOCKED:
			EventBus.escort_blocked.emit(_str(e.get("target")))
		Protocol.E_GHOST_PING:
			var until := _ms(e.get("until"))
			if until < 0:
				until = int(Network.server_time_ms() + Protocol.GHOST_PING_SECONDS * 1000.0)
			var pos := Protocol.vec2_from(e.get("position", {}) if e.get("position") is Dictionary else {})
			ghost_pings.append({"by": _str(e.get("by")), "position": pos, "until": until})
			EventBus.ghost_ping.emit(_str(e.get("by")), pos, until)
		Protocol.E_GHOST_REVEAL:
			var until := _ms(e.get("until"))
			if until < 0:
				until = int(Network.server_time_ms() + Protocol.GHOST_REVEAL_SECONDS * 1000.0)
			var pos := Protocol.vec2_from(e.get("position", {}) if e.get("position") is Dictionary else {})
			ghost_reveals[_str(e.get("interactableId"))] = {"position": pos, "until": until}
			EventBus.ghost_reveal.emit(_str(e.get("interactableId")), pos, until)

## null / ausente → "" (los ids opcionales del protocolo).
static func _str(v) -> String:
	return "" if v == null else str(v)

## Hora del servidor (ms) o -1 si no viene.
static func _ms(v) -> int:
	return -1 if v == null else int(v)

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

func public_player(id: String) -> Dictionary:
	for p in players():
		if p.get("id") == id:
			return p
	return {}

func player_name(id: String) -> String:
	var p := public_player(id)
	return str(p.get("name", "?")) if not p.is_empty() else "?"

## Fuera de la partida para siempre (silenciado dos veces o expulsado): ves todo, no actúas.
func is_ghost() -> bool:
	if bool(my_private_state().get("ghost", false)):
		return true
	return bool(public_player(local_player_id()).get("ghost", false))

## Noqueado ahora mismo (30 s en el suelo): no puedes moverte ni actuar.
func is_knocked() -> bool:
	return bool(public_player(local_player_id()).get("knocked", false))

## Ya usaste tu botón de emergencia (call_meeting) en esta partida.
func meeting_used() -> bool:
	return bool(my_private_state().get("meetingUsed", false))

## Te noquearon alguna vez: no podrás presentar pruebas en el juicio final.
func was_knocked() -> bool:
	return bool(my_private_state().get("wasKnocked", false))

## Cuerpos en el suelo: [{id, playerId, position, reported, kind, until?}].
func bodies() -> Array:
	var b = snapshot.get("bodies")
	return b if b is Array else []

## Asamblea de emergencia en curso (o {}): {calledBy, bodyId, voted, myVote, endsAt, remaining, result}.
func emergency() -> Dictionary:
	var e = snapshot.get("emergency")
	return e if e is Dictionary else {}

## Pings de fantasma aún vigentes (caducan solos).
func active_pings() -> Array:
	var now := Network.server_time_ms()
	ghost_pings = ghost_pings.filter(func(p): return float(p["until"]) > now)
	return ghost_pings

## Pistas que brillan por una misión fantasma: {interactableId: {position, until}}.
func active_reveals() -> Dictionary:
	var now := Network.server_time_ms()
	for id in ghost_reveals.keys():
		if float(ghost_reveals[id]["until"]) <= now:
			ghost_reveals.erase(id)
	return ghost_reveals

## Misiones fantasma pendientes: [{id, label, position, done}].
func ghost_tasks() -> Array:
	var t = my_private_state().get("ghostTasks")
	return t if t is Array else []
