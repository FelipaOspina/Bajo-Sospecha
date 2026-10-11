class_name CosmeticCatalog
extends RefCounted
## Cosméticos del avatar (res://data/cosmetics/cosmetics.json, copia de
## shared/config/cosmetics/cosmetics.json): ropa, gorras, zapatillas y mochilas.
## Es lo único que se compra (con monedas del juego) o se gana en el pase; no cambia
## nada del juego. dress() los aplica sobre los colores de la skin para el chibi.

const DATA_PATH := "res://data/cosmetics/cosmetics.json"
const SLOTS := ["outfit", "hat", "shoes", "bag"]
const RARITY_COLORS := {"rare": Color("#38BDF8"), "epic": Color("#F5B800")}

static var _data: Dictionary

static func data() -> Dictionary:
	if _data.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH)) if FileAccess.file_exists(DATA_PATH) else null
		_data = parsed if parsed is Dictionary else {"slots": {}, "items": []}
	return _data

static func items() -> Array:
	return data().get("items", [])

static func item(id: String) -> Dictionary:
	for i in items():
		if i["id"] == id:
			return i
	return {}

static func has(id: String) -> bool:
	return not item(id).is_empty()

static func by_slot(slot: String) -> Array:
	return items().filter(func(i): return i["slot"] == slot)

## Nombre del hueco en español ("Ropa", "Gorra"...).
static func slot_name(slot: String) -> String:
	return str(data().get("slots", {}).get(slot, slot))

static func rarity_color(id: String) -> Color:
	return RARITY_COLORS.get(str(item(id).get("rarity", "")), Color("#94A3B8"))

## Datos de la skin con los cosméticos puestos encima (para ProceduralChibiAvatar).
## look = {"outfit": id, "hat": id, "shoes": id, "bag": id}; los huecos vacíos dejan
## lo que trae el animal. Nunca toca la corbata (en tu pantalla lleva el color de tu rol).
static func dress(skin: Dictionary, look: Dictionary) -> Dictionary:
	if look.is_empty():
		return skin
	var out := skin.duplicate()
	for slot in SLOTS:
		var it := item(str(look.get(slot, "")))
		if it.is_empty() or it.get("slot") != slot:
			continue
		match slot:
			"outfit":
				out["outfit"] = it["color"]
				out["style"] = it.get("style", out.get("style", "suit"))
			"hat":
				out["hat"] = "cap"
				out["hat_color"] = it["color"]
			"shoes":
				out["shoes"] = it["color"]
			"bag":
				out["bag"] = it["color"]
	return out

## Clave estable de un look (para cachés, como el chibi horneado).
static func look_key(look: Dictionary) -> String:
	var parts: Array[String] = []
	for slot in SLOTS:
		if look.has(slot):
			parts.append("%s=%s" % [slot, look[slot]])
	return ",".join(parts)
