extends Node
## Formato de precios por región (StorePrices): USD por defecto y COP en es_CO.

var _failed := 0

func _ready() -> void:
	_check(StorePrices.region_of("es_CO") == "CO", "es_CO es la región CO")
	_check(StorePrices.region_of("es-co") == "CO", "también con guion y en minúsculas")
	_check(StorePrices.region_of("en") == "", "sin región: vacío")
	_check(StorePrices.currency_for("es_CO") == "COP", "es_CO usa pesos colombianos")
	_check(StorePrices.currency_for("en_US") == "USD", "en_US usa dólares")
	_check(StorePrices.currency_for("es_ES") == "USD", "una región sin tabla vuelve a USD")
	_check(StorePrices.format(4.99, "USD") == "$4.99 USD", "USD: $4.99 USD (%s)" % StorePrices.format(4.99, "USD"))
	_check(StorePrices.format(19900, "COP") == "$19.900 COP", "COP: $19.900 COP (%s)" % StorePrices.format(19900, "COP"))
	_check(StorePrices.format(1234.5, "USD") == "$1,234.50 USD", "USD con miles y dos decimales")
	_check(StorePrices.format(1299900, "COP") == "$1.299.900 COP", "COP con millones")
	var pack: Dictionary = StorePrices.packs()[1]
	_check(StorePrices.price_text(pack, "es_CO") == "$19.900 COP", "paquete de 500 CN en Colombia: %s" % StorePrices.price_text(pack, "es_CO"))
	_check(StorePrices.price_text(pack, "en_US") == "$4.99 USD", "el mismo paquete en EE. UU.: %s" % StorePrices.price_text(pack, "en_US"))
	_check(StorePrices.price_text({"price": {"USD": 2.0}}, "es_CO") == "$2.00 USD", "sin precio local: en USD")
	StorePrices.locale_override = "es_CO"
	_check(StorePrices.currency_for() == "COP", "locale forzado (pruebas) se respeta")
	StorePrices.locale_override = ""
	print("StorePricesTest: ", "OK" if _failed == 0 else "%d FALLOS" % _failed)
	get_tree().quit(1 if _failed > 0 else 0)

func _check(ok: bool, text: String) -> void:
	print("  ", "ok  " if ok else "FAIL", " ", text)
	if not ok:
		_failed += 1
