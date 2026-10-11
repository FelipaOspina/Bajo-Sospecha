class_name ModifierRegistry
extends RefCounted
## Registro de modificadores (Abierto/Cerrado): cada uno es un Callable que
## altera un diccionario de stats. Espejo de server/src/domain/roles/modifiers.
## En el cliente solo se usan para PREDECIR (resaltar objetos a tu alcance);
## el servidor vuelve a validar todo.

const BASE_STATS := {
	"interact_range": 64.0,
	"inventory_capacity": 5,
	"visibility_upgrades": [],
	"destroyable_tags": [],
}

var _handlers := {}  # id -> Callable(stats: Dictionary, params: Dictionary)

func register(id: String, handler: Callable) -> ModifierRegistry:
	_handlers[id] = handler
	return self

func has(id: String) -> bool:
	return _handlers.has(id)

func compute_stats(role: RoleDefinition) -> Dictionary:
	var stats := BASE_STATS.duplicate(true)
	if role == null:
		return stats
	for mod in role.modifiers:
		var h: Callable = _handlers.get(mod["id"], Callable())
		if h.is_valid():
			h.call(stats, mod.get("params", {}))
		else:
			push_warning("Modificador sin implementación en cliente: %s" % mod["id"])
	return stats

static func create_default() -> ModifierRegistry:
	var r := ModifierRegistry.new()
	r.register("extended_reach", func(s, p): s["interact_range"] *= float(p["multiplier"]))
	r.register("inventory_capacity", func(s, p): s["inventory_capacity"] = max(0, s["inventory_capacity"] + int(p["delta"])))
	r.register("forensic_eye", func(s, p): s["visibility_upgrades"].append_array(p["tags"]))
	r.register("can_destroy_evidence", func(s, p): s["destroyable_tags"].append_array(p["tags"]))
	return r
