class_name InventoryManager
extends Node
## Inventario personal del jugador local.
## Es un espejo de solo lectura de "you.inventory" del servidor: nunca añade
## nada por su cuenta. Para guardar una pista se pide a EvidenceSystem.collect()
## y, cuando el servidor lo confirma, aquí llega item_added.

signal changed
signal item_added(evidence: EvidenceData)
signal item_removed(evidence: EvidenceData)

var _items: Array[EvidenceData] = []

func _ready() -> void:
	EventBus.inventory_changed.connect(replace_from_views)

func replace_from_views(views: Array) -> void:
	var before := {}
	for e in _items:
		before[e.instance_id] = e
	var fresh: Array[EvidenceData] = []
	for v in views:
		fresh.append(EvidenceData.from_view(v))
	_items = fresh

	for e in fresh:
		if not before.has(e.instance_id):
			item_added.emit(e)
		before.erase(e.instance_id)
	for gone in before.values():
		item_removed.emit(gone)
	changed.emit()

func items() -> Array[EvidenceData]:
	return _items

func get_item(instance_id: String) -> EvidenceData:
	for e in _items:
		if e.instance_id == instance_id:
			return e
	return null

## ¿Llevo una pista de este tipo? (útil para mostrar llaves en la UI)
func has_definition(definition_id: String) -> bool:
	return _items.any(func(e): return e.definition_id == definition_id)

func size() -> int:
	return _items.size()
