extends Node
## Transporte WebSocket. Solo envía intenciones y reenvía mensajes del servidor.
## No contiene lógica de juego (Responsabilidad Única).

signal message_received(msg: Dictionary)

## Servidor de producción (Render, con SSL). Es el de por defecto, también en el editor.
const PRODUCTION_URL := "wss://bajo-sospecha.onrender.com"
## Servidor local para pruebas (en la carpeta server: npm start).
const LOCAL_URL := "ws://localhost:7777"
## Render duerme el servidor gratuito tras un rato sin uso y la primera conexión lo
## despierta: el apretón de manos puede tardar cerca de un minuto.
const REMOTE_HANDSHAKE_S := 75.0
const LOCAL_HANDSHAKE_S := 5.0

## Servidor al que se conecta. Se elige al arrancar (ver resolve_server_url):
##   godot ... -- --server=ws://localhost:7777   o   -- --local   (argumento)
##   SERVER_URL=ws://localhost:7777   o   SERVER_URL=local          (variable de entorno)
## Sin nada de eso: producción.
var server_url := PRODUCTION_URL

var player_id := ""
var room_code := ""
## Diferencia (ms) entre el reloj del servidor y el local, medida en el welcome.
var server_time_offset_ms := 0.0
var _socket := WebSocketPeer.new()
var _seq := 0
var _pending := {} # seq -> intent, para reconciliar/mostrar errores
var _was_open := false
var _sent_ms := {} # seq -> Time.get_ticks_msec() al enviar
## Ida y vuelta de la última intención confirmada (ms); -1 sin medir.
var latency_ms := -1

func _ready() -> void:
	server_url = resolve_server_url(OS.get_cmdline_user_args() + OS.get_cmdline_args(), OS.get_environment("SERVER_URL"))

## URL del servidor según los argumentos (--server=<url> o --local) y la variable
## SERVER_URL ("local" = LOCAL_URL); si no hay nada, la de producción.
static func resolve_server_url(args: PackedStringArray, env: String) -> String:
	for a in args:
		if a.begins_with("--server="):
			return a.trim_prefix("--server=")
		if a == "--local":
			return LOCAL_URL
	if env.strip_edges() != "":
		return LOCAL_URL if env.strip_edges() == "local" else env.strip_edges()
	return PRODUCTION_URL

## true si el servidor es esta misma máquina (pruebas con npm start).
static func is_local_url(url: String) -> bool:
	var host := url.trim_prefix("wss://").trim_prefix("ws://").get_slice("/", 0)
	host = host.get_slice("]", 0) + "]" if host.begins_with("[") else host.get_slice(":", 0)
	return host in ["localhost", "127.0.0.1", "[::1]"]

## Abre el socket sin entrar en ninguna sala (el menú manda luego hello, cola, salas...).
## Devuelve OK si quedó abierto (o ya lo estaba).
func open(url: String = server_url) -> Error:
	if is_open():
		return OK
	_socket = WebSocketPeer.new()
	var err := _socket.connect_to_url(url)
	if err != OK:
		return err
	await _wait_open(LOCAL_HANDSHAKE_S if is_local_url(url) else REMOTE_HANDSHAKE_S)
	return OK if is_open() else ERR_CANT_CONNECT

func is_open() -> bool:
	return _socket.get_ready_state() == WebSocketPeer.STATE_OPEN

## Al volver al menú: ya no estamos en ninguna sala (la conexión sigue abierta).
func forget_room() -> void:
	room_code = ""
	_pending.clear()
	_sent_ms.clear()

## Entrada directa a una sala, sin menú (bots y pruebas).
## room_code vacío = sala pública. Con código, todos los que lo usen juegan juntos.
func connect_to_server(player_name: String, code: String = "", url: String = server_url) -> Error:
	var err := await open(url)
	if err != OK:
		return err
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
	_sent_ms[_seq] = Time.get_ticks_msec()
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
			_settle(int(msg["seq"]))
		Protocol.M_REJECTED:
			_settle(int(msg["seq"]))
			EventBus.intent_rejected.emit(int(msg["seq"]), msg["reason"])
	message_received.emit(msg)

func _settle(seq: int) -> void:
	_pending.erase(seq)
	if _sent_ms.has(seq):
		latency_ms = Time.get_ticks_msec() - int(_sent_ms[seq])
		_sent_ms.erase(seq)

static func local_time_ms() -> float:
	return Time.get_unix_time_from_system() * 1000.0

## Hora estimada del servidor, en ms.
func server_time_ms() -> float:
	return local_time_ms() + server_time_offset_ms

## Espera a que el socket se abra o falle; si tarda más de timeout_s, lo cierra.
func _wait_open(timeout_s := REMOTE_HANDSHAKE_S) -> void:
	var deadline := Time.get_ticks_msec() + int(timeout_s * 1000.0)
	while _socket.get_ready_state() == WebSocketPeer.STATE_CONNECTING:
		if Time.get_ticks_msec() > deadline:
			_socket.close()
			_socket.poll()
			return
		_socket.poll()
		await get_tree().process_frame
