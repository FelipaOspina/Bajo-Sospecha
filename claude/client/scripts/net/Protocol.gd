class_name Protocol
## Espejo de shared/protocol/protocol.ts. Mantener sincronizado.

const VERSION := 1

# Cliente → Servidor
const I_JOIN := "join"
const I_READY := "ready"
const I_MOVE := "move"
const I_INTERACT := "interact"
const I_CHANNEL_START := "channel_start"
const I_CHANNEL_CANCEL := "channel_cancel"
const I_DROP := "drop_evidence"
const I_DESTROY := "destroy_evidence"
const I_PRESENT := "present_evidence"
const I_VOTE := "vote"

# Servidor → Cliente
const M_WELCOME := "welcome"
const M_SNAPSHOT := "snapshot"
const M_DELTA := "delta"
const M_EVENT := "event"
const M_ACK := "ack"
const M_REJECTED := "rejected"

# Eventos de juego
const E_PLAYER_JOINED := "player_joined"
const E_PLAYER_LEFT := "player_left"
const E_PHASE_CHANGED := "phase_changed"
const E_EVIDENCE_COLLECTED := "evidence_collected"
const E_EVIDENCE_DROPPED := "evidence_dropped"
const E_EVIDENCE_DESTROYED := "evidence_destroyed"
const E_EVIDENCE_PRESENTED := "evidence_presented"
const E_VOTE_CAST := "vote_cast"
const E_CHANNEL_STARTED := "channel_started"
const E_CHANNEL_FINISHED := "channel_finished"
const E_GAME_OVER := "game_over"

# Fases
const PHASE_LABELS := {
	"lobby": "Sala de espera",
	"briefing": "Reparto de roles",
	"investigation": "Investigación",
	"discussion": "Juicio: debate",
	"voting": "Juicio: votación",
	"results": "Resolución",
}

# Visibilidad
const VIS_HIDDEN := "hidden"
const VIS_PARTIAL := "partial"
const VIS_FULL := "full"

static func vec2_from(d: Dictionary) -> Vector2:
	return Vector2(d.get("x", 0.0), d.get("y", 0.0))

static func vec2_to(v: Vector2) -> Dictionary:
	return {"x": v.x, "y": v.y}
