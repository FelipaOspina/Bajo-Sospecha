class_name BodyContainers
extends Node
## Contenedores "body" que crea el servidor al silenciar a alguien: todo su inventario
## cae al suelo en ese sitio ("Objetos caídos de <nombre>"). No vienen en el caso, así
## que se crean y se quitan aquí según snapshot.interactables (type "body"). Son
## InteractableEvidence normales: se examinan y se recogen como cualquier otro.

## Donde cuelgan (Main/Map/Evidence, el mismo sitio que las pistas del caso).
@export var root: Node2D

var _nodes := {}   # interactable id -> BodyBag

func _ready() -> void:
	GameState.snapshot_applied.connect(sync)

func get_container(id: String) -> BodyBag:
	var n = _nodes.get(id)
	return n if is_instance_valid(n) else null

func containers() -> Array:
	return _nodes.values().filter(func(n): return is_instance_valid(n))

func sync(s: Dictionary) -> void:
	if root == null:
		return
	var seen := {}
	for v in s.get("interactables", []):
		if str(v.get("type", "")) != Protocol.INTERACTABLE_BODY:
			continue
		var id := str(v.get("id", ""))
		seen[id] = true
		var node: BodyBag = get_container(id)
		if node == null:
			node = BodyBag.new()
			node.name = "Body_" + id.replace(":", "_").replace("#", "_")
			node.interactable_id = id
			node.radius = float(v.get("radius", 40.0))
			node.owner_id = str(v.get("ownerId", ""))
			root.add_child(node)
			_nodes[id] = node
			node._sync_from_state(s)
		node.position = Protocol.vec2_from(v.get("position", {}))
		node.prompt_text = str(v.get("label", "")) if str(v.get("label", "")) != "" else "Objetos caídos de %s" % GameState.player_name(node.owner_id)
	for id in _nodes.keys():
		if not seen.has(id):
			if is_instance_valid(_nodes[id]):
				_nodes[id].queue_free()
			_nodes.erase(id)

## Bolsa de objetos caídos: la dibuja World3DView con la línea de vista.
class BodyBag extends InteractableEvidence:
	var owner_id := ""
