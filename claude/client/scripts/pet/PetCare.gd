class_name PetCare
extends RefCounted
## Mascota del lobby (Alter Ego): hambre e hidratación de cada animal del jugador.
## Las dos barras van de 0 a 100 (llena = bien comido o bien hidratado) y bajan solas
## con el tiempo, también con el juego cerrado: cada animal guarda la hora de su última
## cuenta. Se rellenan con la comida de su especie (bambú para el panda, pescado para el
## gato... ver data/pets/pets.json) y con agua.
## La comida y el agua son gratis, no se venden y no cambian nada en la partida.
## Se guarda en este dispositivo (user://pet.cfg), aparte para cada perfil.
## Los tiempos van en segundos Unix; las pruebas pasan su propio "now".

const DATA_PATH := "res://data/pets/pets.json"
const SAVE_PATH := "user://pet.cfg"
const STATS := ["hunger", "hydration"]

static var _data: Dictionary

var save_path := SAVE_PATH
var profile_key := "local"
var _state := {}   # skin_id -> {hunger, hydration, t}

static func data() -> Dictionary:
	if _data.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
		_data = parsed if parsed is Dictionary else {}
	return _data

## Ficha de la especie: comida, dato de biología y reacción al tocarla.
static func species(skin_id: String) -> Dictionary:
	return data().get("species", {}).get(skin_id, {})

static func food(skin_id: String) -> Dictionary:
	return species(skin_id).get("food", {"id": "comida", "name": "Comida", "icon": "kibble"})

static func water() -> Dictionary:
	return data().get("water", {"id": "agua", "name": "Agua", "icon": "water"})

## Reacción al tocarla (una distinta por animal; ver PetReactions).
static func tap_reaction(skin_id: String) -> String:
	return str(species(skin_id).get("tap", "wag"))

static func max_level() -> float:
	return float(data().get("max", 100))

## Puntos que pierde por segundo.
static func rate(stat: String) -> float:
	var hours := float(data().get("hours_to_empty", {}).get(stat, 10))
	return max_level() / maxf(hours * 3600.0, 1.0)

static func now_s() -> float:
	return Time.get_unix_time_from_system()

## Carga el estado guardado de un perfil (key vacía = "local").
func load_state(key: String = "") -> void:
	profile_key = key if key != "" else "local"
	_state.clear()
	var cfg := ConfigFile.new()
	if cfg.load(save_path) != OK or not cfg.has_section(profile_key):
		return
	for skin in cfg.get_section_keys(profile_key):
		var v = cfg.get_value(profile_key, skin)
		if v is Dictionary:
			_state[skin] = {"hunger": float(v.get("hunger", 0)), "hydration": float(v.get("hydration", 0)), "t": float(v.get("t", now_s()))}

func save_state() -> void:
	var cfg := ConfigFile.new()
	cfg.load(save_path)   # conserva los demás perfiles
	if cfg.has_section(profile_key):
		cfg.erase_section(profile_key)
	for skin in _state:
		cfg.set_value(profile_key, skin, _state[skin])
	cfg.save(save_path)

## Nivel actual (0..100) de "hunger" o "hydration".
func level(skin_id: String, stat: String, now := -1.0) -> float:
	return float(_settle(skin_id, now)[stat])

func levels(skin_id: String, now := -1.0) -> Dictionary:
	var e := _settle(skin_id, now)
	return {"hunger": e["hunger"], "hydration": e["hydration"]}

func is_low(skin_id: String, stat: String, now := -1.0) -> bool:
	return level(skin_id, stat, now) < float(data().get("low_at", 30))

## Lo que más necesita: "hydration", "hunger" o "" si está bien (la sed va primero).
func need(skin_id: String, now := -1.0) -> String:
	var l := levels(skin_id, now)
	var low := float(data().get("low_at", 30))
	if l["hydration"] < low and l["hydration"] <= l["hunger"]:
		return "hydration"
	if l["hunger"] < low:
		return "hunger"
	if l["hydration"] < low:
		return "hydration"
	return ""

## Le da su comida. {ok, reason ("full" si ya está lleno), level}.
func feed(skin_id: String, now := -1.0) -> Dictionary:
	return _refill(skin_id, "hunger", float(data().get("feed_amount", 35)), now)

## Le da agua. {ok, reason ("full" si no tiene sed), level}.
func drink(skin_id: String, now := -1.0) -> Dictionary:
	return _refill(skin_id, "hydration", float(data().get("drink_amount", 40)), now)

func _refill(skin_id: String, stat: String, amount: float, now: float) -> Dictionary:
	var e := _settle(skin_id, now)
	if e[stat] >= float(data().get("full_at", 95)):
		return {"ok": false, "reason": "full", "level": e[stat]}
	e[stat] = minf(max_level(), e[stat] + amount)
	save_state()
	return {"ok": true, "reason": "", "level": e[stat]}

## Aplica lo que ha bajado desde la última cuenta y devuelve la entrada del animal.
func _settle(skin_id: String, now: float) -> Dictionary:
	var t := now if now >= 0.0 else now_s()
	if not _state.has(skin_id):
		var start := float(data().get("start", 80))
		_state[skin_id] = {"hunger": start, "hydration": start, "t": t}
	var e: Dictionary = _state[skin_id]
	# Si el reloj del sistema va hacia atrás no baja, y la cuenta sigue desde la hora más
	# tardía vista (al volver a la hora buena no se descuenta dos veces).
	var elapsed := maxf(0.0, t - float(e["t"]))
	for stat in STATS:
		e[stat] = maxf(0.0, float(e[stat]) - rate(stat) * elapsed)
	e["t"] = maxf(t, float(e["t"]))
	return e
