class_name AnimalAbilities
extends Node
## Habilidades tácticas por animal (autoload "Abilities").
##
## Cada uno de los 12 animales tiene una pasiva (siempre activa) y una activa con
## enfriamiento que solo funciona en la investigación. Todos los animales son gratis
## para todos: la habilidad nunca se compra; en la tienda solo hay cosméticos.
##
## El diccionario vive en res://data/abilities/abilities.json, copia de
## shared/config/abilities/abilities.json: el servidor lee el mismo archivo y es quien
## valida y aplica cada efecto (fase, enfriamiento, velocidad, quién ve qué barra...).
## Aquí solo se pide usar la activa y se avisa al HUD con señales. Estructura:
##
##   {"buho": {"passive": {id, name, description, trait, effects},
##             "active":  {id, name, description, trait, icon, cooldown, duration,
##                         effects | instant ("scent"/"roar"), radius, area, secret}}, ...}
##
## Ninguna habilidad revela roles: actúan sobre movimiento, barras de acción,
## inventario y escondites con pruebas que tú ya podrías ver. La habilidad sale del
## animal, que se elige en el lobby antes del reparto de roles.

## Cambió tu animal (o se conoce por primera vez): kit = {passive, active}.
signal ability_changed(skin_id: String, kit: Dictionary)
## Segundos que faltan para poder usarla otra vez (0 = lista) y el total.
signal cooldown_changed(remaining_s: float, total_s: float)
signal ability_ready(ability_id: String)
## El servidor la aceptó; duration_s = 0 si es instantánea (rugido).
signal ability_activated(ability_id: String, duration_s: float)
signal ability_ended(ability_id: String)
signal ability_failed(reason: String, message: String)
## Olfato: escondites marcados (ids de interactables) durante duration_s.
signal scent_marked(interactable_ids: Array, duration_s: float)
## Otro jugador usó una activa pública (rugido, aullido, acelerones). affected_me: te alcanzó.
signal ability_seen(player_id: String, ability_id: String, affected_me: bool)

const DATA_PATH := "res://data/abilities/abilities.json"
## Acción de teclado para usar la activa (Q por defecto, ver project.godot).
const ACTION := "use_ability"
const ERRORS := {
	"wrong_phase": "Las habilidades solo funcionan durante la investigación.",
	"not_alive": "Ahora no puedes usar habilidades.",
	"no_ability": "Tu animal no tiene habilidad activa.",
	"on_cooldown": "Tu habilidad aún se está recargando.",
	"offline": "Sin conexión con el servidor.",
}

static var _data: Dictionary = {}

## Destino de las intenciones (Network o un doble en las pruebas) y reloj del servidor en ms.
var net: Node
var clock: Callable
## Animal del jugador local y su estado según el servidor (you.ability).
var skin_id := ""
var state: Dictionary = {}

var _pending := {}          # seq -> true
var _was_ready := true
var _active_id := ""
var _active_until := -1.0
var _last_reported := -1.0

# ───── Diccionario de habilidades ─────

## Todo el diccionario: animal -> {passive, active}.
static func all() -> Dictionary:
	if _data.is_empty():
		var f := FileAccess.open(DATA_PATH, FileAccess.READ)
		if f:
			var parsed = JSON.parse_string(f.get_as_text())
			if parsed is Dictionary and parsed.get("abilities") is Dictionary:
				_data = parsed["abilities"]
	return _data

static func animals() -> Array:
	return all().keys()

static func kit(animal: String) -> Dictionary:
	var k = all().get(animal, {})
	return k if k is Dictionary else {}

static func passive_of(animal: String) -> Dictionary:
	var p = kit(animal).get("passive", {})
	return p if p is Dictionary else {}

static func active_of(animal: String) -> Dictionary:
	var a = kit(animal).get("active", {})
	return a if a is Dictionary else {}

## Activa por su id (para nombrar la de otro jugador: "Beto usó Rugido").
static func find_active(ability_id: String) -> Dictionary:
	for animal in all():
		var a := active_of(animal)
		if a.get("id") == ability_id:
			return a
	return {}

## Un efecto de la pasiva (p. ej. "flashlight" del búho), o default.
static func passive_effect(animal: String, key: String, default: Variant = 1.0) -> Variant:
	return passive_of(animal).get("effects", {}).get(key, default)

## Texto corto de enfriamiento y duración: "Cada 45 s · dura 6 s".
static func timing_text(active: Dictionary) -> String:
	var parts := ["Cada %s s" % _num(float(active.get("cooldown", 0)))]
	if active.has("duration"):
		parts.append("dura %s s" % _num(float(active["duration"])))
	return " · ".join(parts)

static func _num(v: float) -> String:
	return str(int(v)) if is_equal_approx(v, roundf(v)) else ("%.1f" % v).replace(".", ",")

# ───── Estado del jugador local ─────

func _ready() -> void:
	net = Network
	clock = Network.server_time_ms
	_ensure_input_action()
	Network.message_received.connect(_on_message)
	GameState.snapshot_applied.connect(_on_snapshot)
	EventBus.ability_used.connect(_on_ability_used)

func active() -> Dictionary:
	return active_of(skin_id)

func passive() -> Dictionary:
	return passive_of(skin_id)

func now_ms() -> float:
	return float(clock.call()) if clock.is_valid() else Time.get_unix_time_from_system() * 1000.0

## Segundos hasta poder usarla (0 = lista).
func cooldown_left() -> float:
	return maxf(0.0, (float(state.get("readyAt", 0)) - now_ms()) / 1000.0)

func cooldown_total() -> float:
	if state.has("cooldownMs"):
		return float(state["cooldownMs"]) / 1000.0
	return float(active().get("cooldown", 0.0))

## Segundos que le quedan al efecto en curso (0 = ninguno).
func active_left() -> float:
	var until = state.get("activeUntil")
	var end := maxf(float(until) if until != null else -1.0, _active_until)
	return maxf(0.0, (end - now_ms()) / 1000.0)

func can_use() -> bool:
	return GameState.phase() == "investigation" and not active().is_empty() and cooldown_left() <= 0.0

## Multiplicador de tu velocidad ahora (lo valida el servidor; Player lo usa para predecir).
func speed_multiplier() -> float:
	var you := GameState.my_private_state()
	if you.has("speedMultiplier"):
		return float(you["speedMultiplier"])
	return float(passive_effect(skin_id, "speed", 1.0))

## Radio de tu linterna (solo visual: visión nocturna del búho).
func flashlight_multiplier() -> float:
	return float(passive_effect(skin_id, "flashlight", 1.0))

## Pide usar la activa. -1 si no se puede ahora (y avisa con ability_failed).
func use() -> int:
	if active().is_empty():
		_fail("no_ability")
		return -1
	if GameState.phase() != "investigation":
		_fail("wrong_phase")
		return -1
	if cooldown_left() > 0.0:
		_fail("on_cooldown")
		return -1
	var seq: int = net.send_intent(Protocol.I_USE_ABILITY)
	if seq < 0:
		_fail("offline")
		return -1
	_pending[seq] = true
	return seq

func _fail(reason: String) -> void:
	ability_failed.emit(reason, ERRORS.get(reason, "No se pudo usar la habilidad (%s)." % reason))

func _on_snapshot(_s: Dictionary) -> void:
	var animal := ""
	for p in GameState.players():
		if p.get("id") == Network.player_id:
			animal = str(p.get("skinId", ""))
	if animal != skin_id:
		skin_id = animal
		ability_changed.emit(skin_id, kit(skin_id))
	var ability = GameState.my_private_state().get("ability")
	state = ability if ability is Dictionary else {}

func _on_message(msg: Dictionary) -> void:
	var t: String = msg.get("t", "")
	if t != Protocol.M_ACK and t != Protocol.M_REJECTED:
		return
	var seq := int(msg.get("seq", -1))
	if not _pending.has(seq):
		return
	_pending.erase(seq)
	if t == Protocol.M_REJECTED:
		_fail(str(msg.get("reason", "")))

func _on_ability_used(by: String, ability_id: String, ends_at_ms: int, marks: Array, affected: Array) -> void:
	if by != Network.player_id:
		ability_seen.emit(by, ability_id, affected.has(Network.player_id))
		return
	var duration := maxf(0.0, (float(ends_at_ms) - now_ms()) / 1000.0) if ends_at_ms > 0 else 0.0
	# Hasta que llegue el snapshot, el enfriamiento empieza ya.
	state["readyAt"] = now_ms() + cooldown_total() * 1000.0
	if duration > 0.0:
		_active_id = ability_id
		_active_until = float(ends_at_ms)
	ability_activated.emit(ability_id, duration)
	if not marks.is_empty():
		scent_marked.emit(marks, duration)

func _process(_delta: float) -> void:
	if active().is_empty():
		return
	var left := cooldown_left()
	if absf(left - _last_reported) >= 0.05 or (left == 0.0 and _last_reported != 0.0):
		_last_reported = left
		cooldown_changed.emit(left, cooldown_total())
	if left <= 0.0 and not _was_ready:
		_was_ready = true
		ability_ready.emit(str(active().get("id", "")))
	elif left > 0.0:
		_was_ready = false
	if _active_id != "" and now_ms() >= _active_until:
		ability_ended.emit(_active_id)
		_active_id = ""
		_active_until = -1.0

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(ACTION) and not event.is_echo() and GameState.phase() == "investigation":
		use()
		get_viewport().set_input_as_handled()

## Q por defecto si el proyecto no define la acción (pruebas, escenas sueltas).
static func _ensure_input_action() -> void:
	if InputMap.has_action(ACTION):
		return
	InputMap.add_action(ACTION)
	var key := InputEventKey.new()
	key.physical_keycode = KEY_Q
	InputMap.action_add_event(ACTION, key)
