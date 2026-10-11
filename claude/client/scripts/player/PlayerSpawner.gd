class_name PlayerSpawner
extends Node2D
## Crea y elimina los personajes según la lista de jugadores del servidor.
## Cada uno es un PlayerAvatar (scenes/player/PlayerAvatar.tscn). El local lleva
## cámara e InteractionDetector; los remotos se interpolan.

signal local_player_spawned(player: Player)

const AVATAR_SCENE := preload("res://scenes/player/PlayerAvatar.tscn")

@export var role_manager: RoleManager
@export var detector_radius := 220.0

var _players := {}  # player_id -> Player

func _ready() -> void:
	GameState.snapshot_applied.connect(_sync)

func get_player(id: String) -> Player:
	return _players.get(id)

func _sync(s: Dictionary) -> void:
	var seen := {}
	for p in s.get("players", []):
		seen[p["id"]] = true
		var node: Player = _players.get(p["id"])
		if node == null:
			node = _spawn(p)
		node.set_connected(p.get("connected", true))
	for id in _players.keys():
		if not seen.has(id):
			_players[id].queue_free()
			_players.erase(id)

func _spawn(p: Dictionary) -> Player:
	var node: PlayerAvatar = AVATAR_SCENE.instantiate()
	node.name = "Player_" + p["id"].left(8)
	node.player_id = p["id"]
	node.is_local = p["id"] == GameState.local_player_id()
	node.display_name = p.get("name", "?")
	# Skin de animal que reparte el servidor (pública, no depende del rol).
	node.skin_id = str(p.get("skinId", SkinCatalog.fallback_for(p["id"])))
	node.teleport(Protocol.vec2_from(p["position"]))
	# La escena ya usa la capa 2 con máscara 1: los jugadores no chocan entre sí (solo con
	# el mapa), porque si se empujaran, juntarse en una pista interrumpiría las canalizaciones.

	if node.is_local:
		var detector := InteractionDetector.new()
		detector.name = "InteractionDetector"
		detector.role_manager = role_manager
		var area := CollisionShape2D.new()
		var circle := CircleShape2D.new()
		circle.radius = detector_radius
		area.shape = circle
		detector.add_child(area)
		node.add_child(detector)
		var camera := Camera2D.new()
		camera.position = Vector2(0, -24)   # el origen está en los pies: centra el cuerpo
		node.add_child(camera)

	add_child(node)
	_players[p["id"]] = node
	if node.is_local:
		local_player_spawned.emit(node)
	return node
