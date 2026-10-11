class_name RoleConfigSource
extends RefCounted
## "Interfaz" de origen de configuración de roles. Subclases: disco, red, tests.

func load_role_set(_role_set_id: String) -> Dictionary:
	push_error("RoleConfigSource.load_role_set no implementado")
	return {}


## Lee res://data/roles/<id>.json (copiado desde shared/config con tools/sync-config.sh).
class FileSource extends RoleConfigSource:
	var directory: String

	func _init(dir: String = "res://data/roles") -> void:
		directory = dir

	func load_role_set(role_set_id: String) -> Dictionary:
		var path := "%s/%s.json" % [directory, role_set_id]
		var text := FileAccess.get_file_as_string(path)
		if text.is_empty():
			push_error("No se pudo leer %s" % path)
			return {}
		var parsed = JSON.parse_string(text)
		return parsed if parsed is Dictionary else {}


## Config ya en memoria (p. ej. enviada por el servidor para mods/escenarios custom).
class MemorySource extends RoleConfigSource:
	var sets: Dictionary

	func _init(role_sets: Dictionary) -> void:
		sets = role_sets

	func load_role_set(role_set_id: String) -> Dictionary:
		return sets.get(role_set_id, {}).duplicate(true)
