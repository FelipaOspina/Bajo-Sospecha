class_name Protocol
## Espejo de shared/protocol/protocol.ts. Mantener sincronizado.

const VERSION := 1

# Cliente → Servidor
const I_JOIN := "join"                 # entrada directa (bots y pruebas): {"name", "protocol", "roomCode"?}
const I_READY := "ready"
const I_CHOOSE_SKIN := "choose_skin"   # lobby: {"skinId": "panda"}
# Menú: perfil, salas y matchmaking
const I_HELLO := "hello"               # {"name", "protocol", "profileId"?} → llega "profile"
const I_CREATE_ROOM := "create_room"   # sala privada con código de 6 → llega "welcome"
const I_JOIN_ROOM := "join_room"       # {"roomCode"}
const I_QUEUE_MATCH := "queue_match"   # cola pública de 4 → llegan "queued" y, al llenarse, "welcome"
const I_LEAVE_QUEUE := "leave_queue"
# Mismos mensajes con los nombres del diseño del menú (botones Crear sala y Jugar).
const CREATE_PRIVATE_ROOM := I_CREATE_ROOM
const QUEUE_MATCH := I_QUEUE_MATCH
const JOIN_ROOM := I_JOIN_ROOM
const I_LEAVE_ROOM := "leave_room"
const I_CHAT := "chat"                 # {"text"} solo en el lobby
# Executive Pass y tienda (monedas del juego; sin pagos reales)
const I_CLAIM_PASS_REWARD := "claim_pass_reward"   # {"level", "track": "free"|"premium"}
const I_BUY_SKIN := "buy_skin"         # {"skinId"} (antiguo: los animales son gratis)
const I_BUY_COSMETIC := "buy_cosmetic" # {"cosmeticId"} ropa, gorra, zapatillas o mochila
const I_EQUIP_COSMETIC := "equip_cosmetic"   # {"slot": "outfit"|"hat"|"shoes"|"bag", "cosmeticId": id o null}
const I_BUY_PREMIUM := "buy_premium_pass"
const I_SELECT_SKIN := "select_skin"   # skin preferida del perfil {"skinId"}
const I_MOVE := "move"
const I_INTERACT := "interact"
const I_CHANNEL_START := "channel_start"
const I_CHANNEL_CANCEL := "channel_cancel"
const I_DROP := "drop_evidence"
const I_DESTROY := "destroy_evidence"
const I_PRESENT := "present_evidence"
const I_VOTE := "vote"
const I_USE_ABILITY := "use_ability"   # activa del animal (solo en la investigación)

# Servidor → Cliente
const M_WELCOME := "welcome"
const M_SNAPSHOT := "snapshot"
const M_DELTA := "delta"
const M_EVENT := "event"
const M_ACK := "ack"
const M_REJECTED := "rejected"
const M_PROFILE := "profile"           # perfil completo tras hello y tras cada cambio
const M_QUEUED := "queued"             # {"position" (0 = fuera), "waiting", "matchSize"}
const M_REWARDS := "rewards"           # {"rewards": {xp, coins, won, levelsGained, passLevelsGained}}

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
const E_CHAT := "chat"                 # {"by", "name", "text", "at"}
const E_ABILITY_USED := "ability_used" # {"by", "abilityId", "endsAt", "marks"? (olfato, solo tú), "affected"?}

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
