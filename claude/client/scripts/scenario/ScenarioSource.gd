class_name ScenarioSource
extends RefCounted
## Origen de escenarios. Sustituible (disco, descarga desde el servidor, tests).

func load_raw(_scenario_id: String) -> Variant:
	push_error("ScenarioSource.load_raw no implementado")
	return null


## Lee <directory>/<id>.json. Acepta también una ruta completa a un .json.
class FileSource extends ScenarioSource:
	var directory: String

	func _init(dir: String = "res://data/scenarios") -> void:
		directory = dir

	func load_raw(scenario_id: String) -> Variant:
		var path := scenario_id if scenario_id.ends_with(".json") else "%s/%s.json" % [directory, scenario_id]
		if not FileAccess.file_exists(path):
			push_error("No existe el escenario: %s" % path)
			return null
		var json := JSON.new()
		if json.parse(FileAccess.get_file_as_string(path)) != OK:
			push_error("JSON inválido en %s (línea %d): %s" % [path, json.get_error_line(), json.get_error_message()])
			return null
		return json.data


class MemorySource extends ScenarioSource:
	var scenarios: Dictionary

	func _init(by_id: Dictionary) -> void:
		scenarios = by_id

	func load_raw(scenario_id: String) -> Variant:
		return scenarios.get(scenario_id, {}).duplicate(true)
