class_name PetSfx
extends Node
## Sonidos de la mascota del lobby: para cada animal uno al tocarla (<animal>_feliz) y
## otro al acariciarla (<animal>_caricia), y los comunes comer, beber y lleno.
## Son WAV de res://assets/audio/pets/ sintetizados por tools/gen_pet_sfx.py: obra propia
## del proyecto, sin grabaciones de terceros (ver assets/audio/pets/LICENCIA.md). Para
## cambiarlos por grabaciones reales basta con dejar otro WAV con el mismo nombre.
## Si falta un archivo, simplemente no suena.

const DIR := "res://assets/audio/pets/"
const COMMON := ["comer", "beber", "lleno"]
const VOICES := 3

## Volumen de 0 a 1 (Configuración → Sonidos de la mascota). 0 = en silencio.
static var volume := 0.8

var last_played := ""
var _players: Array[AudioStreamPlayer] = []
var _cache := {}
var _next := 0

func _ready() -> void:
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		p.name = "Voice%d" % i
		add_child(p)
		_players.append(p)

static func path_for(key: String) -> String:
	return DIR + key + ".wav"

## Sonido de un gesto: "tap" (tocarla) o "stroke" (acariciarla).
static func key_for(skin_id: String, gesture: String) -> String:
	return skin_id + ("_caricia" if gesture == "stroke" else "_feliz")

## Todos los sonidos que deberían existir (12 animales × 2 + los comunes).
static func all_keys() -> Array:
	var keys: Array = []
	for id in SkinCatalog.ids():
		keys.append(key_for(id, "tap"))
		keys.append(key_for(id, "stroke"))
	keys.append_array(COMMON)
	return keys

## Reproduce un sonido. false si está en silencio o falta el archivo. Si ese mismo
## sonido ya está sonando (caricias seguidas) no lo vuelve a empezar.
func play(key: String, pitch_jitter := 0.04) -> bool:
	if volume <= 0.0 or _players.is_empty():
		return false
	var stream := _stream(key)
	if stream == null:
		return false
	for p in _players:
		if p.playing and p.stream == stream:
			return true
	var player := _players[_next]
	_next = (_next + 1) % _players.size()
	player.stream = stream
	player.volume_db = linear_to_db(volume)
	player.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
	player.play()
	last_played = key
	return true

func _stream(key: String) -> AudioStream:
	if not _cache.has(key):
		var path := path_for(key)
		_cache[key] = load(path) if ResourceLoader.exists(path) else null
	return _cache[key]
