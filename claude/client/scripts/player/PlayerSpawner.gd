class_name PlayerSpawner
extends Node2D
## Crea y elimina los personajes según la lista de jugadores del servidor.
## El local lleva cámara e InteractionDetector; los remotos se interpolan.

signal local_player_spawned(player: Player)

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
		node.modulate.a = 1.0 if p.get("connected", true) else 0.35
	for id in _players.keys():
		if not seen.has(id):
			_players[id].queue_free()
			_players.erase(id)

func _spawn(p: Dictionary) -> Player:
	var node := Player.new()
	node.name = "Player_" + p["id"].left(8)
	node.player_id = p["id"]
	node.is_local = p["id"] == GameState.local_player_id()
	node.teleport(Protocol.vec2_from(p["position"]))
	# Los jugadores no chocan entre sí (capa 2, solo choca con el mapa en la capa 1):
	# si se empujaran, juntarse alrededor de una pista interrumpiría las acciones canalizadas.
	node.collision_layer = 2
	node.collision_mask = 1

	var shape := CircleShape2D.new()
	shape.radius = 14
	var col := CollisionShape2D.new()
	col.shape = shape
	node.add_child(col)

	var body := Polygon2D.new()
	var pts := PackedVector2Array()
	for i in 16:
		pts.append(Vector2.from_angle(TAU * i / 16.0) * 14)
	body.polygon = pts
	body.color = Color.from_hsv(float(hash(p["id"]) % 360) / 360.0, 0.55, 0.95)
	node.add_child(body)

	var label := Label.new()
	label.text = p.get("name", "?")
	label.position = Vector2(-40, -36)
	label.size = Vector2(80, 20)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Contorno para que el nombre se lea bajo la luz nocturna (NightLighting).
	label.add_theme_constant_override("outline_size", 4)
	node.add_child(label)

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
		node.add_child(Camera2D.new())

	add_child(node)
	_players[p["id"]] = node
	if node.is_local:
		local_player_spawned.emit(node)
	return node
