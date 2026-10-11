class_name Progression
extends RefCounted
## Reglas de progresión y economía para mostrarlas en el menú (res://data/progression/
## progression.json, copia de shared/config/progression/progression.json). El servidor
## es quien cobra y reparte: aquí solo se lee para pintar precios y recompensas.
## Monedas del juego, sin pagos reales.

const DATA_PATH := "res://data/progression/progression.json"
const CURRENCIES := ["coins", "credits"]

static var _data: Dictionary

static func data() -> Dictionary:
	if _data.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH)) if FileAccess.file_exists(DATA_PATH) else null
		_data = parsed if parsed is Dictionary else {}
	return _data

static func pass_config() -> Dictionary:
	return data().get("battle_pass", {})

static func max_pass_level() -> int:
	return int(pass_config().get("max_level", 50))

static func currency_name(currency: String) -> String:
	return str(data().get("currencies", {}).get(currency, {}).get("name", currency))

static func currency_short(currency: String) -> String:
	return str(data().get("currencies", {}).get(currency, {}).get("short", currency))

## Recompensa de un nivel del Executive Pass: {kind: "cosmetic", cosmetic} o
## {kind: "coins"|"credits", amount}. Misma regla que ProfileService.rewardAt en el servidor.
static func reward_at(level: int, track: String) -> Dictionary:
	var bp := pass_config()
	for r in bp.get("cosmetic_rewards", []):
		if int(r["level"]) == level and r["track"] == track:
			return {"kind": "cosmetic", "cosmetic": str(r["cosmetic"])}
	for r in bp.get("skin_rewards", []):
		if int(r["level"]) == level and r["track"] == track:
			return {"kind": "skin", "skin": str(r["skin"])}
	for r in bp.get("credit_rewards", []):
		if int(r["level"]) == level and r["track"] == track:
			return {"kind": "credits", "amount": int(r["amount"])}
	var per_level := "free_coins_per_level" if track == "free" else "premium_coins_per_level"
	return {"kind": "coins", "amount": int(bp.get(per_level, 0))}

## Precio de un cosmético en la tienda ({"coins": 600} o {"credits": 120}); vacío si no se vende.
## Los animales no se venden: son de todos.
static func shop_price(cosmetic_id: String) -> Dictionary:
	var p = data().get("shop", {}).get("cosmetics", {}).get(cosmetic_id)
	return p if p is Dictionary else {}

static func is_starter_cosmetic(cosmetic_id: String) -> bool:
	return cosmetic_id in data().get("starter_cosmetics", [])

static func premium_price() -> Dictionary:
	return pass_config().get("premium_price", {})

static func is_starter(skin_id: String) -> bool:
	return skin_id in data().get("starter_skins", [])

## Nivel y pista del pase que regala el cosmético, o {} si no está en el pase.
static func pass_unlock(cosmetic_id: String) -> Dictionary:
	for r in pass_config().get("cosmetic_rewards", []):
		if r["cosmetic"] == cosmetic_id:
			return {"level": int(r["level"]), "track": str(r["track"])}
	return {}

## Cómo se consigue un cosmético, en una línea ("De inicio", "Pase nv. 5 · Gratis", "600 MC").
## Los animales siempre: "Gratis".
static func source_text(id: String) -> String:
	if SkinCatalog.has(id):
		return "Gratis" if is_starter(id) else "No disponible"
	if is_starter_cosmetic(id):
		return "De inicio"
	var parts: Array[String] = []
	var unlock := pass_unlock(id)
	if not unlock.is_empty():
		parts.append("Pase nv. %d · %s" % [unlock["level"], "Gratis" if unlock["track"] == "free" else "Premium"])
	var price := shop_price(id)
	if not price.is_empty():
		parts.append(price_text(price))
	return " · ".join(parts) if not parts.is_empty() else "No disponible"

static func match_rewards() -> Dictionary:
	return data().get("match_rewards", {})

## "950 MC", "200 CN".
static func price_text(price: Dictionary) -> String:
	var parts: Array[String] = []
	for c in CURRENCIES:
		if price.has(c):
			parts.append("%s %s" % [format_amount(int(price[c])), currency_short(c)])
	return " + ".join(parts)

## Separador de miles con punto, como en español: 125430 → "125.430".
static func format_amount(n: int) -> String:
	var digits := str(absi(n))
	var out := ""
	while digits.length() > 3:
		out = "." + digits.right(3) + out
		digits = digits.left(digits.length() - 3)
	return ("-" if n < 0 else "") + digits + out
