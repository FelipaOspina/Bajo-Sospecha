class_name Player
extends CharacterBody2D
## Jugador. Si es local: lee input, se mueve con predicción y envía su posición
## a 20 Hz. Si es remoto: interpola hacia la posición autoritativa del servidor.

const SEND_INTERVAL := 1.0 / 20.0
const SNAP_DISTANCE := 48.0
## Teclas de movimiento (también las usa ChannelPresenter para cancelar canalizaciones).
const MOVE_ACTIONS := ["ui_left", "ui_right", "ui_up", "ui_down"]   # si el servidor nos corrige más que esto, teletransporte

@export var speed := 240.0    # < maxSpeedPxPerSec del servidor (260)

var player_id := ""
var is_local := false
var _send_timer := 0.0
var _server_position := Vector2.ZERO
var _input_locked := false

func _ready() -> void:
	GameState.snapshot_applied.connect(_on_snapshot)
	EventBus.ui_modal_changed.connect(func(open: bool): _input_locked = open)

## Coloca al personaje sin interpolar (al aparecer o al reconectar).
func teleport(pos: Vector2) -> void:
	position = pos
	_server_position = pos

func _physics_process(delta: float) -> void:
	if is_local:
		var dir := Vector2.ZERO if _input_locked else Input.get_vector(MOVE_ACTIONS[0], MOVE_ACTIONS[1], MOVE_ACTIONS[2], MOVE_ACTIONS[3])
		velocity = dir * speed
		move_and_slide()
		_send_timer += delta
		if _send_timer >= SEND_INTERVAL:
			_send_timer = 0.0
			Network.send_intent(Protocol.I_MOVE, {"position": Protocol.vec2_to(global_position)})
	else:
		global_position = global_position.lerp(_server_position, clamp(delta * 12.0, 0.0, 1.0))

func _on_snapshot(s: Dictionary) -> void:
	for p in s.get("players", []):
		if p["id"] != player_id:
			continue
		_server_position = Protocol.vec2_from(p["position"])
		# Reconciliación simple: el local solo se corrige si se desvía demasiado.
		if is_local and global_position.distance_to(_server_position) > SNAP_DISTANCE:
			global_position = _server_position
		return
