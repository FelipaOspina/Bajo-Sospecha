class_name InteractableEvidence
extends Interactable
## Objeto del mapa que contiene pistas (un móvil, una factura, un armario...).
## Su contenido lo rellena el estado del servidor, ya filtrado para este
## jugador: si no tienes el rol o la llave, llega en parcial y con candado.
## Al pulsar E pide abrir el visor (EvidenceInspectionModal) con lo que contiene.

signal contents_changed(contents: Array)

var contents: Array[EvidenceData] = []

func _ready() -> void:
	super()
	GameState.snapshot_applied.connect(_sync_from_state)

func interact() -> void:
	EventBus.evidence_inspect_requested.emit(self)

func has_perceivable_contents() -> bool:
	return not contents.is_empty()

func find_content(instance_id: String) -> EvidenceData:
	for e in contents:
		if e.instance_id == instance_id:
			return e
	return null

## Permite fijar el contenido sin servidor (tests, editor de casos).
func set_contents(list: Array[EvidenceData]) -> void:
	contents = list
	_on_contents_changed()
	contents_changed.emit(contents)

func _sync_from_state(_s: Dictionary) -> void:
	var view := GameState.interactable_view(interactable_id)
	if view.is_empty():
		return
	var fresh: Array[EvidenceData] = []
	for v in view.get("contents", []):
		fresh.append(EvidenceData.from_view(v))
	if _signature(fresh) != _signature(contents):
		set_contents(fresh)

func _on_contents_changed() -> void:
	pass

## Cambia si cambian las piezas o su estado (p. ej. al conseguir la llave).
static func _signature(list: Array) -> Array:
	return list.map(func(e): return "%s|%s|%s" % [e.instance_id, e.visibility, e.locked])
