class_name Player
extends CharacterBody2D
## Jugador. Si es local: lee input, se mueve con predicción y envía su posición
## a 20 Hz. Si es remoto: interpola hacia la posición autoritativa del servidor.

const SEND_INTERVAL := 1.0 / 20.0
const SNAP_DISTANCE := 48.0
## Teclas de movimiento (también las usa ChannelPresenter para cancelar canalizaciones).
const MOVE_ACTIONS := ["ui_left", "ui_right", "ui_up", "ui_down"]   # si el servidor nos corrige más que esto, teletransporte

@export var speed := 240.0    # < maxSpeedPxPerSec del servidor (260)
## Opacidad de un fantasma (solo lo ven otros fantasmas; él se ve a sí mismo así).
const GHOST_ALPHA := 0.42

var player_id := ""
var is_local := false
var _send_timer := 0.0
var _server_position := Vector2.ZERO
var _input_locked := false
## Fuera de la partida (silenciado dos veces o expulsado): translúcido y sin colisiones.
var ghost := false
## Noqueado (30 s en el suelo): no se dibuja de pie (lo dibuja el cuerpo) ni se mueve.
var knocked := false
## El servidor lo manda oculto (un fantasma visto por un vivo): no se dibuja.
var server_hidden := false
var _connected := true
var _base_mask := -1

func _ready() -> void:
	_base_mask = collision_mask
	GameState.snapshot_applied.connect(_on_snapshot)
	EventBus.ui_modal_changed.connect(func(open: bool): _input_locked = open)

## Conectado o no (semitransparente si se cayó). PlayerAvatar también atenúa el nombre.
func set_connected(on: bool) -> void:
	_connected = on
	modulate.a = (1.0 if on else 0.35) * (GHOST_ALPHA if ghost else 1.0)

## Estado público del jugador (PublicPlayerState): fantasma, noqueado u oculto.
## Lo llama PlayerSpawner con cada snapshot, antes de set_connected.
func apply_status(p: Dictionary) -> void:
	ghost = bool(p.get("ghost", false))
	knocked = bool(p.get("knocked", false))
	server_hidden = bool(p.get("hidden", false))
	# El fantasma atraviesa las paredes (el servidor ya no valida su posición contra muros).
	if _base_mask < 0:
		_base_mask = collision_mask
	collision_mask = 0 if ghost else _base_mask
	visible = not server_hidden and not knocked
	set_connected(_connected)

## Barra de canalización sobre el personaje. PlayerAvatar la coloca encima del nombre.
func attach_progress_bar(text: String, duration_s: float, already_elapsed := 0.0, kind := "backup") -> FloatingProgressBar:
	return FloatingProgressBar.attach(self, text, duration_s, already_elapsed, kind)

## Coloca al personaje sin interpolar (al aparecer o al reconectar).
func teleport(pos: Vector2) -> void:
	position = pos
	_server_position = pos

func _physics_process(delta: float) -> void:
	if is_local:
		var dir := Vector2.ZERO if _input_locked or knocked else Input.get_vector(MOVE_ACTIONS[0], MOVE_ACTIONS[1], MOVE_ACTIONS[2], MOVE_ACTIONS[3])
		velocity = dir * speed * Abilities.speed_multiplier()   # pasiva y acelerones del animal (los valida el servidor)
		move_and_slide()
		_send_timer += delta
		if _send_timer >= SEND_INTERVAL and not knocked:
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
