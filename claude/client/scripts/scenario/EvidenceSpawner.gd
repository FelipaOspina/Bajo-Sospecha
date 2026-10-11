class_name EvidenceSpawner
extends RefCounted
## Fábrica de nodos de pista por tipo (Abierto/Cerrado): cada tipo tiene un
## constructor registrable. Por defecto crea un EvidenceSpot con un indicador
## visual; se puede registrar una escena propia por tipo con register_scene().

const TYPE_COLORS := {
	EvidenceSpawnData.Type.TEXT: Color(0.85, 0.85, 0.7),
	EvidenceSpawnData.Type.AUDIO: Color(0.4, 0.75, 1.0),
	EvidenceSpawnData.Type.PHOTO: Color(0.9, 0.55, 0.9),
	EvidenceSpawnData.Type.ITEM: Color(1.0, 0.8, 0.3),
}

var _builders := {}  # Type -> Callable(spawn: EvidenceSpawnData) -> InteractableEvidence

func _init() -> void:
	for t in EvidenceSpawnData.Type.values():
		_builders[t] = _build_default

func register(type: EvidenceSpawnData.Type, builder: Callable) -> EvidenceSpawner:
	_builders[type] = builder
	return self

## La raíz de la escena debe extender InteractableEvidence. Si tiene setup(spawn), se llama.
func register_scene(type: EvidenceSpawnData.Type, scene: PackedScene) -> EvidenceSpawner:
	return register(type, func(_spawn: EvidenceSpawnData) -> InteractableEvidence:
		var node := scene.instantiate() as InteractableEvidence
		assert(node != null, "La escena de pista debe extender InteractableEvidence")
		return node)

func spawn(data: EvidenceSpawnData, parent: Node) -> InteractableEvidence:
	var node: InteractableEvidence = _builders[data.type].call(data)
	node.name = data.interactable_id()
	node.interactable_id = data.interactable_id()
	node.radius = data.radius
	node.position = data.position
	node.prompt_text = "Examinar" if not data.pocketable else "Buscar"
	node.set_meta("evidence_spawn_id", data.id)
	if node.has_method("setup"):
		node.setup(data)
	parent.add_child(node)
	return node

func _build_default(data: EvidenceSpawnData) -> InteractableEvidence:
	var spot := EvidenceSpot.new()
	var marker := Polygon2D.new()
	marker.name = "Marker"
	marker.color = TYPE_COLORS[data.type]
	marker.polygon = PackedVector2Array([Vector2(-10, -10), Vector2(10, -10), Vector2(10, 10), Vector2(-10, 10)])
	spot.add_child(marker)

	match data.type:
		EvidenceSpawnData.Type.AUDIO:
			var player := AudioStreamPlayer2D.new()
			player.name = "Audio"
			var path := str(data.content.get("audio", ""))
			if ResourceLoader.exists(path):
				player.stream = load(path)
			spot.add_child(player)
		EvidenceSpawnData.Type.PHOTO:
			var path := str(data.content.get("image", ""))
			if ResourceLoader.exists(path):
				var sprite := Sprite2D.new()
				sprite.name = "Photo"
				sprite.texture = load(path)
				sprite.scale = Vector2(0.25, 0.25)
				spot.add_child(sprite)
	return spot
