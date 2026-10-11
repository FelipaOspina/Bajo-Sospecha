extends Node
## Transporte WebSocket. Solo envía intenciones y reenvía mensajes del servidor.
## No contiene lógica de juego (Responsabilidad Única).

signal message_received(msg: Dictionary)

@export var server_url := "ws://localhost:7777"

var player_id := ""
var room_code := ""
## Diferencia (ms) entre el reloj del servidor y el local, medida en el welcome.
var server_time_offset_ms := 0.0
var _socket := WebSocketPeer.new()
var _seq := 0
var _pending := {} # seq -> intent, para reconciliar/mostrar errores
var _was_open := false

## room_code vacío = sala pública. Con código, todos los que lo usen juegan juntos.
func connect_to_server(player_name: String, code: String = "", url: String = server_url) -> Error:
	var err := _socket.connect_to_url(url)
	if err != OK:
		return err
	await _wait_open()
	var payload := {"name": player_name, "protocol": Protocol.VERSION}
	if code != "":
		payload["roomCode"] = code
	send_intent(Protocol.I_JOIN, payload)
	return OK

func send_intent(type: String, payload: Dictionary = {}) -> int:
	if _socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return -1
	_seq += 1
	var intent := payload.duplicate()
	intent["t"] = type
	intent["seq"] = _seq
	_pending[_seq] = intent
	_socket.send_text(JSON.stringify(intent))
	return _seq

func _process(_delta: float) -> void:
	_socket.poll()
	var state := _socket.get_ready_state()
	if state == WebSocketPeer.STATE_OPEN:
		_was_open = true
		while _socket.get_available_packet_count() > 0:
			var parsed = JSON.parse_string(_socket.get_packet().get_string_from_utf8())
			if parsed is Dictionary:
				_dispatch(parsed)
	elif state == WebSocketPeer.STATE_CLOSED and _was_open:
		_was_open = false
		EventBus.disconnected_from_server.emit(_socket.get_close_reason())

func _dispatch(msg: Dictionary) -> void:
	match msg.get("t"):
		Protocol.M_WELCOME:
			player_id = msg["playerId"]
			room_code = msg.get("roomCode", "")
			server_time_offset_ms = float(msg.get("serverTime", local_time_ms())) - local_time_ms()
			EventBus.connected_to_server.emit(player_id)
		Protocol.M_ACK:
			_pending.erase(int(msg["seq"]))
		Protocol.M_REJECTED:
			_pending.erase(int(msg["seq"]))
			EventBus.intent_rejected.emit(int(msg["seq"]), msg["reason"])
	message_received.emit(msg)

static func local_time_ms() -> float:
	return Time.get_unix_time_from_system() * 1000.0

## Hora estimada del servidor, en ms.
func server_time_ms() -> float:
	return local_time_ms() + server_time_offset_ms

func _wait_open() -> void:
	while _socket.get_ready_state() == WebSocketPeer.STATE_CONNECTING:
		_socket.poll()
		await get_tree().process_frame
