extends Node
## Cuenta del jugador y acciones del menú. Es la fachada que usan las vistas del menú:
## perfil (nivel, XP, Monedas Corporativas, Créditos Nexus, Executive Pass, animales y
## cosméticos), salas (crear, unirse por código, salir), cola pública, chat y tienda.
## Los 12 animales (y sus habilidades) son de todos; solo se compran cosméticos.
##
## El perfil vive en el servidor (mock en JSON, sin contraseñas ni pagos reales); aquí
## solo se guarda su id en user://account.cfg para recuperarlo al volver a abrir el juego.
## PROFILE_ID y PNAME en el entorno lo sustituyen (bots y pruebas con varios clientes).

signal profile_updated(profile: Dictionary)
signal rewards_granted(rewards: Dictionary)
## position 0 = fuera de la cola.
signal queue_changed(position: int, waiting: int, match_size: int)
signal online_changed(online: bool)
## Respuesta del servidor a una acción del menú (action = nombre de la intención).
signal action_done(action: String, seq: int)
signal action_failed(action: String, reason: String, message: String)

const SAVE_PATH := "user://account.cfg"
const MAX_NAME := 24
const ERRORS := {
	"room_not_found": "No hay ninguna sala con ese código.",
	"room_full": "La sala está llena.",
	"game_started": "Esa partida ya ha empezado.",
	"already_in_room": "Ya estás en una sala.",
	"not_in_room": "No estás en ninguna sala.",
	"server_full": "El servidor está lleno; prueba en un momento.",
	"not_enough_coins": "No tienes suficientes Monedas Corporativas.",
	"not_enough_credits": "No tienes suficientes Créditos Nexus.",
	"already_owned": "Ya lo tienes en tu inventario.",
	"not_for_sale": "Esto no está a la venta.",
	"unknown_skin": "Ese animal no existe.",
	"skin_locked": "Aún no tienes ese animal.",
	"unknown_cosmetic": "Ese objeto no existe.",
	"cosmetic_locked": "Aún no tienes ese objeto.",
	"wrong_slot": "Ese objeto no va en ese hueco.",
	"bad_slot": "Hueco de vestuario desconocido.",
	"skin_taken": "Otro jugador de la sala ya lleva ese animal.",
	"level_not_reached": "Todavía no has llegado a ese nivel del pase.",
	"premium_required": "Necesitas el Executive Pass Premium.",
	"already_claimed": "Ya reclamaste esa recompensa.",
	"empty_message": "El mensaje está vacío.",
	"wrong_phase": "Eso solo se puede hacer en la sala de espera.",
	"no_profile": "Sin perfil: conéctate al servidor.",
	"offline": "Sin conexión con el servidor.",
}

## Destino de las intenciones: el autoload Network o un doble en los tests.
var net: Node
var profile_id := ""
var player_name := "Jugador"
## Última vista del perfil que mandó el servidor (vacía hasta el primer "profile").
var profile: Dictionary = {}
var online := false
var queue_position := 0
var queue_waiting := 0
var match_size := 4
var last_rewards: Dictionary = {}

var _actions := {}   # seq -> nombre de la intención (para traducir acks y rechazos)
var _from_env := false

func _ready() -> void:
	net = Network
	_load()
	Network.message_received.connect(_on_message)
	EventBus.disconnected_from_server.connect(func(_reason: String) -> void: _set_online(false))

# ───── Conexión ─────

## Abre la conexión (si hace falta) y se identifica. false si el servidor no responde.
func go_online() -> bool:
	if not Network.is_open() and await Network.open() != OK:
		_set_online(false)
		return false
	_set_online(true)
	hello()
	return true

func hello() -> int:
	var payload := {"name": player_name, "protocol": Protocol.VERSION}
	if profile_id != "":
		payload["profileId"] = profile_id
	return _send(Protocol.I_HELLO, payload)

## Cambia el nombre (se guarda y se manda al servidor con un nuevo hello).
func set_player_name(new_name: String) -> void:
	var clean := new_name.strip_edges().left(MAX_NAME)
	if clean.is_empty() or clean == player_name:
		return
	player_name = clean
	_save()
	if online:
		hello()

# ───── Salas y cola ─────

func quick_match() -> int:
	return _send(Protocol.I_QUEUE_MATCH, {"name": player_name, "protocol": Protocol.VERSION})

func cancel_queue() -> int:
	return _send(Protocol.I_LEAVE_QUEUE)

func create_room() -> int:
	return _send(Protocol.I_CREATE_ROOM, {"name": player_name, "protocol": Protocol.VERSION})

func join_room(code: String) -> int:
	return _send(Protocol.I_JOIN_ROOM, {"roomCode": normalize_code(code), "name": player_name, "protocol": Protocol.VERSION})

## Sale de la sala y vuelve al menú sin cerrar la conexión.
func leave_room() -> int:
	var seq := _send(Protocol.I_LEAVE_ROOM)
	Network.forget_room()
	GameState.reset()
	return seq

func set_ready(on: bool) -> int:
	return _send(Protocol.I_READY, {"ready": on})

func send_chat(text: String) -> int:
	var clean := text.strip_edges()
	return _send(Protocol.I_CHAT, {"text": clean}) if not clean.is_empty() else -1

## Animal en la sala de espera actual (lo ven todos; no puede repetirse).
func choose_skin(skin_id: String) -> int:
	return _send(Protocol.I_CHOOSE_SKIN, {"skinId": skin_id})

func in_queue() -> bool:
	return queue_position > 0

## Mayúsculas, sin espacios ni guiones: "k7m-2qx" → "K7M2QX".
static func normalize_code(code: String) -> String:
	return code.strip_edges().to_upper().replace(" ", "").replace("-", "")

# ───── Perfil, pase y tienda ─────

## Animal preferido del perfil; si estás en una sala de espera, también lo lleva ahí.
func select_skin(skin_id: String) -> int:
	var seq := _send(Protocol.I_SELECT_SKIN, {"skinId": skin_id})
	if GameState.in_room() and GameState.phase() == "lobby":
		choose_skin(skin_id)
	return seq

func claim_reward(level: int, track: String) -> int:
	return _send(Protocol.I_CLAIM_PASS_REWARD, {"level": level, "track": track})

## Reclama todo lo pendiente del pase. Devuelve cuántas peticiones mandó.
func claim_all() -> int:
	var n := 0
	var claimable: Dictionary = pass_view().get("claimable", {})
	for track in ["free", "premium"]:
		for level in claimable.get(track, []):
			claim_reward(int(level), track)
			n += 1
	return n

## Antiguo: los animales ya son gratis (el servidor responde already_owned).
func buy_skin(skin_id: String) -> int:
	return _send(Protocol.I_BUY_SKIN, {"skinId": skin_id})

## Comprar un cosmético (ropa, gorra, zapatillas, mochila) con monedas del juego.
func buy_cosmetic(cosmetic_id: String) -> int:
	return _send(Protocol.I_BUY_COSMETIC, {"cosmeticId": cosmetic_id})

## Ponerse un cosmético en su hueco (cosmetic_id vacío = quitarse lo de ese hueco).
## En la sala de espera los demás lo ven al momento.
func equip_cosmetic(slot: String, cosmetic_id: String) -> int:
	return _send(Protocol.I_EQUIP_COSMETIC, {"slot": slot, "cosmeticId": cosmetic_id if cosmetic_id != "" else null})

func owned_cosmetics() -> Array:
	return profile.get("cosmetics", Progression.data().get("starter_cosmetics", []))

func owns_cosmetic(cosmetic_id: String) -> bool:
	return cosmetic_id in owned_cosmetics()

## Lo que llevas puesto: {"outfit": id, "hat": id, ...} (vacío = ropa de serie).
func equipped() -> Dictionary:
	var e = profile.get("equipped", {})
	return e if e is Dictionary else {}

func is_equipped(cosmetic_id: String) -> bool:
	return cosmetic_id in equipped().values()

func buy_premium() -> int:
	return _send(Protocol.I_BUY_PREMIUM)

func has_profile() -> bool:
	return not profile.is_empty()

func level() -> int:
	return int(profile.get("level", 1))

func coins() -> int:
	return int(profile.get("coins", 0))

func credits() -> int:
	return int(profile.get("credits", 0))

func balance(currency: String) -> int:
	return int(profile.get(currency, 0))

func can_afford(price: Dictionary) -> bool:
	for c in price:
		if balance(c) < int(price[c]):
			return false
	return has_profile()

func owned_skins() -> Array:
	return profile.get("skins", Progression.data().get("starter_skins", ["zorro"]))

func owns(skin_id: String) -> bool:
	return skin_id in owned_skins()

func selected_skin() -> String:
	var s := str(profile.get("selectedSkin", ""))
	return s if s != "" else str(owned_skins()[0]) if not owned_skins().is_empty() else SkinCatalog.DEFAULT_SKIN["id"]

## Executive Pass tal como lo manda el servidor (level, xpIntoLevel, premium, claimed, claimable...).
func pass_view() -> Dictionary:
	return profile.get("pass", {})

func is_premium() -> bool:
	return bool(pass_view().get("premium", false))

func is_claimed(level_n: int, track: String) -> bool:
	return float(level_n) in pass_view().get("claimed", {}).get(track, []).map(func(l): return float(l))

static func error_text(reason: String) -> String:
	return ERRORS.get(reason, "No se pudo completar (%s)." % reason)

# ───── Mensajes del servidor ─────

func _on_message(msg: Dictionary) -> void:
	match msg.get("t"):
		Protocol.M_PROFILE:
			profile = msg.get("profile", {})
			profile_id = str(profile.get("id", profile_id))
			player_name = str(profile.get("name", player_name))
			_save()
			profile_updated.emit(profile)
		Protocol.M_REWARDS:
			last_rewards = msg.get("rewards", {})
			rewards_granted.emit(last_rewards)
		Protocol.M_QUEUED:
			queue_position = int(msg.get("position", 0))
			queue_waiting = int(msg.get("waiting", 0))
			match_size = int(msg.get("matchSize", match_size))
			queue_changed.emit(queue_position, queue_waiting, match_size)
		Protocol.M_ACK:
			var seq := int(msg.get("seq", -1))
			if _actions.has(seq):
				action_done.emit(_actions[seq], seq)
				_actions.erase(seq)
		Protocol.M_REJECTED:
			var seq := int(msg.get("seq", -1))
			if _actions.has(seq):
				var reason := str(msg.get("reason", ""))
				action_failed.emit(_actions[seq], reason, error_text(reason))
				_actions.erase(seq)

func _send(type: String, payload: Dictionary = {}) -> int:
	var seq: int = net.send_intent(type, payload) if net else -1
	if seq < 0:
		action_failed.emit(type, "offline", error_text("offline"))
	else:
		_actions[seq] = type
	return seq

func _set_online(value: bool) -> void:
	if not value:
		queue_position = 0
	if online == value:
		return
	online = value
	online_changed.emit(online)

# ───── Guardado local (solo id y nombre) ─────

func _load() -> void:
	var env_id := OS.get_environment("PROFILE_ID")
	var env_name := OS.get_environment("PNAME")
	_from_env = env_id != ""
	if _from_env:
		profile_id = env_id
		player_name = env_name if env_name != "" else player_name
		return
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		profile_id = str(cfg.get_value("account", "profile_id", ""))
		player_name = str(cfg.get_value("account", "name", player_name))
		ChibiBaker.mode = str(cfg.get_value("video", "avatars", "auto"))
		PetSfx.volume = clampf(float(cfg.get_value("audio", "pet_volume", PetSfx.volume)), 0.0, 1.0)
	if env_name != "":
		player_name = env_name

func _save() -> void:
	if _from_env:
		return   # cada bot con su perfil: no pisar el del jugador
	var cfg := ConfigFile.new()
	cfg.set_value("account", "profile_id", profile_id)
	cfg.set_value("account", "name", player_name)
	cfg.set_value("video", "avatars", ChibiBaker.mode)
	cfg.set_value("audio", "pet_volume", PetSfx.volume)
	cfg.save(SAVE_PATH)

## Calidad de los avatares: "auto" (horneados en móvil y web), "off" (siempre en vivo,
## con parpadeo y orejas con muelle) u "on" (siempre horneados: más FPS). Ver ChibiBaker.
## Se aplica a los personajes que aparezcan a partir de ahora.
func set_avatar_quality(mode: String) -> void:
	ChibiBaker.mode = mode
	_save()

## Volumen de los sonidos de la mascota del lobby (0 = en silencio).
func set_pet_volume(value: float) -> void:
	PetSfx.volume = clampf(value, 0.0, 1.0)
	_save()
