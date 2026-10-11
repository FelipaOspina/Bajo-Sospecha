class_name CaseTypes
extends RefCounted
## Tipos de caso del selector de la sala (res://data/cases/case_types.json). Un tipo
## está disponible si tiene al menos un escenario; los demás se muestran deshabilitados.

const DATA_PATH := "res://data/cases/case_types.json"

static var _types: Array

static func all() -> Array:
	if _types.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH)) if FileAccess.file_exists(DATA_PATH) else null
		_types = parsed.get("types", []) if parsed is Dictionary else []
	return _types

static func is_available(type: Dictionary) -> bool:
	return not type.get("scenarios", []).is_empty()

## Tipo al que pertenece un escenario ({} si ninguno).
static func for_scenario(scenario_id: String) -> Dictionary:
	for t in all():
		if scenario_id in t.get("scenarios", []):
			return t
	return {}
