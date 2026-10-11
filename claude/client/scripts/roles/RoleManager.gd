class_name RoleManager
extends Node
## Gestor de roles en el cliente.
##  - Carga dinámicamente el set de roles (JSON) para mostrar nombres, descripciones
##    y objetivos en la UI.
##  - Conoce el rol del jugador local (lo revela el servidor) y calcula sus stats
##    predichas para la UI (alcance, capacidad, qué etiquetas ve).
##  - NO decide nada: la asignación y la visibilidad real son del servidor.

signal role_set_loaded(role_set_id: String)
signal local_role_changed(role: RoleDefinition)

var source: RoleConfigSource = RoleConfigSource.FileSource.new()
var modifiers: ModifierRegistry = ModifierRegistry.create_default()

var role_set_id := ""
var _roles := {}  # id -> RoleDefinition
var local_role: RoleDefinition
var local_stats: Dictionary = ModifierRegistry.BASE_STATS.duplicate(true)

func _ready() -> void:
	EventBus.role_revealed.connect(_on_role_revealed)

func load_role_set(id: String) -> bool:
	var data := source.load_role_set(id)
	if data.is_empty() or not data.has("roles"):
		push_error("Set de roles inválido: %s" % id)
		return false
	_roles.clear()
	for raw in data["roles"]:
		var role := RoleDefinition.from_dict(raw)
		_roles[role.id] = role
	role_set_id = id
	role_set_loaded.emit(id)
	return true

func get_role(id: String) -> RoleDefinition:
	return _roles.get(id)

func all_roles() -> Array:
	return _roles.values()

## Predicción local de visibilidad (misma regla que RestrictiveVisibilityPolicy).
func predicted_visibility(tags: Array) -> String:
	if local_role == null:
		return Protocol.VIS_HIDDEN
	for t in tags:
		if t in local_stats["visibility_upgrades"]:
			return Protocol.VIS_FULL
	var result := ""
	for rule in local_role.visibility_rules:
		var matches := false
		for t in rule["tags"]:
			if t in tags:
				matches = true
				break
		if matches and (result == "" or RoleDefinition.VISIBILITY_ORDER[rule["level"]] < RoleDefinition.VISIBILITY_ORDER[result]):
			result = rule["level"]
	return result if result != "" else local_role.default_visibility

func can_destroy(tags: Array) -> bool:
	for t in tags:
		if t in local_stats["destroyable_tags"]:
			return true
	return false

func _on_role_revealed(role_id: String) -> void:
	local_role = get_role(role_id)
	if local_role == null:
		push_warning("El servidor asignó un rol que este cliente no conoce: %s" % role_id)
	local_stats = modifiers.compute_stats(local_role)
	local_role_changed.emit(local_role)
