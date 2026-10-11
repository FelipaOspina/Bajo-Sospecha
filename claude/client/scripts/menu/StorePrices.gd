class_name StorePrices
extends RefCounted
## Precios en dinero real de los paquetes de Créditos Nexus, SOLO para mostrarlos
## (res://data/store/store_prices.json, copia de shared/config/store/store_prices.json).
## Todavía no hay pagos: la tienda los enseña con el botón de compra desactivado.
##
## Moneda base: dólares (USD), como en la distribución internacional de la Play Store.
## Si la región del dispositivo (OS.get_locale(): "es_CO" → "CO") tiene moneda propia en
## la tabla, se muestra esa: es_CO → "$19.900 COP"; el resto → "$4.99 USD".
## Es una tabla fija, no un tipo de cambio en vivo. Con Google Play Billing integrado, el
## precio local real lo da la tienda (ProductDetails.formattedPrice) y esto queda de respaldo.

const DATA_PATH := "res://data/store/store_prices.json"

## Fuerza un locale ("es_CO", "en_US"...) para probar; vacío = el del sistema. También
## sirve la variable de entorno PRICE_LOCALE.
static var locale_override := ""
static var _data: Dictionary

static func data() -> Dictionary:
	if _data.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH)) if FileAccess.file_exists(DATA_PATH) else null
		_data = parsed if parsed is Dictionary else {"base_currency": "USD", "currencies": {}, "regions": {}, "packs": []}
	return _data

static func base_currency() -> String:
	return str(data().get("base_currency", "USD"))

static func packs() -> Array:
	return data().get("packs", [])

## Locale que se usa para los precios: el forzado, PRICE_LOCALE o el del sistema.
static func locale() -> String:
	if locale_override != "":
		return locale_override
	var env := OS.get_environment("PRICE_LOCALE")
	return env if env != "" else OS.get_locale()

## País del locale en mayúsculas ("es_CO", "es-co" → "CO"); vacío si no trae región.
static func region_of(loc: String) -> String:
	var parts := loc.replace("-", "_").split("_")
	return parts[1].left(2).to_upper() if parts.size() > 1 else ""

## Moneda para ese locale: la de su región si está en la tabla; si no, la base (USD).
static func currency_for(loc := "") -> String:
	var region := region_of(loc if loc != "" else locale())
	var cur := str(data().get("regions", {}).get(region, base_currency()))
	return cur if data().get("currencies", {}).has(cur) else base_currency()

## "$4.99 USD", "$19.900 COP": símbolo, separadores y decimales de cada moneda.
static func format(amount: float, currency: String) -> String:
	var f: Dictionary = data().get("currencies", {}).get(currency, {"symbol": "$", "decimals": 2, "thousands": ",", "decimal": "."})
	var decimals := int(f.get("decimals", 2))
	var factor := int(pow(10, decimals))
	var total := int(round(absf(amount) * factor))
	var whole := str(total / factor)
	var grouped := ""
	while whole.length() > 3:
		grouped = str(f.get("thousands", ",")) + whole.right(3) + grouped
		whole = whole.left(whole.length() - 3)
	grouped = whole + grouped
	if decimals > 0:
		grouped += str(f.get("decimal", ".")) + str(total % factor).pad_zeros(decimals)
	return "%s%s%s %s" % ["-" if amount < 0 else "", f.get("symbol", "$"), grouped, currency]

## Precio de un paquete para ese locale; si el paquete no tiene precio en la moneda local,
## el de la moneda base.
static func price_text(pack: Dictionary, loc := "") -> String:
	var prices: Dictionary = pack.get("price", {})
	var cur := currency_for(loc)
	if not prices.has(cur):
		cur = base_currency()
	return format(float(prices.get(cur, 0.0)), cur)
