extends Node
## Elección del servidor (Network.resolve_server_url): producción por defecto y local
## con --local, --server=<url> o la variable SERVER_URL.

var _failed := 0

func _ready() -> void:
	var none := PackedStringArray()
	_check(Network.resolve_server_url(none, "") == Network.PRODUCTION_URL, "sin nada: producción (%s)" % Network.PRODUCTION_URL)
	_check(Network.PRODUCTION_URL.begins_with("wss://"), "producción va cifrada (wss)")
	_check(Network.resolve_server_url(PackedStringArray(["--local"]), "") == Network.LOCAL_URL, "--local: servidor local")
	_check(Network.resolve_server_url(PackedStringArray(["--server=ws://10.0.0.5:7777"]), "") == "ws://10.0.0.5:7777", "--server=<url> manda")
	_check(Network.resolve_server_url(none, "local") == Network.LOCAL_URL, "SERVER_URL=local: servidor local")
	_check(Network.resolve_server_url(none, " ws://127.0.0.1:9000 ") == "ws://127.0.0.1:9000", "SERVER_URL con una URL (sin espacios)")
	_check(Network.resolve_server_url(PackedStringArray(["--local"]), "wss://otro.example") == Network.LOCAL_URL, "el argumento gana a la variable")
	_check(Network.is_local_url(Network.LOCAL_URL), "localhost es local")
	_check(Network.is_local_url("ws://127.0.0.1:7777/"), "127.0.0.1 es local")
	_check(Network.is_local_url("ws://[::1]:7777"), "[::1] es local")
	_check(not Network.is_local_url(Network.PRODUCTION_URL), "producción no es local")
	var err: Error = await Network.open("ws://127.0.0.1:9")
	_check(err == ERR_CANT_CONNECT and not Network.is_open(), "sin servidor, open() falla limpio (ERR_CANT_CONNECT)")
	print("ServerUrlTest: ", "OK" if _failed == 0 else "%d FALLOS" % _failed)
	get_tree().quit(1 if _failed > 0 else 0)

func _check(ok: bool, text: String) -> void:
	print("  ", "ok  " if ok else "FAIL", " ", text)
	if not ok:
		_failed += 1
