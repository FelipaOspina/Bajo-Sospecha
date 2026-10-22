extends Node
## Prueba sin servidor: godot --headless res://tests/TutorialTest.tscn
## Práctica «Primer día en NexusCore» de principio a fin en la escena real (Main): el
## servidor local responde por Network como uno de verdad, los pasos avanzan con lo que
## haría el jugador (moverse, examinar, guardar, copiar quieto, reportar, votar, exponer y
## votar el veredicto) y al final la XP queda pendiente para el servidor (sin conexión).

var _failures := 0
var main: Node
var menu: Node
var tut: Node
var srv: Node
var _saved := {}

func _ready() -> void:
	_saved = {"seen": Account.tutorial_seen, "pending": Account.tutorial_reward_pending, "profile": Account.profile, "online": Account.online}
	Account.profile = {}
	Account.online = false
	main = load("res://scenes/main/Main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	menu = main.get_node("MainMenu")
	tut = menu.start_tutorial()
	_check(tut != null, "MainMenu arranca la práctica")
	srv = tut.server
	_check(Network.local_server == srv, "las intenciones van al servidor local")
	_check(menu.start_tutorial() == null, "no se arrancan dos prácticas a la vez")
	await _frames(5)
	_check(GameState.phase() == "briefing" and GameState.local_player_id() == "me", "welcome local: briefing (%s)" % GameState.phase())
	_check(not menu.visible, "el menú se oculta como en una partida")
	_check(GameState.my_private_state().get("roleId") == "ROLE_INVESTOR", "rol de práctica solo para ti")
	_check(GameState.players().all(func(p): return p.get("roleId") == null), "ningún rol ajeno viaja en el estado")
	_check(tut.step == "intro" and tut.panel.visible, "paso 1: presentación")

	tut.next_pressed()
	await _frames(3)
	_check(tut.step == "move" and GameState.phase() == "investigation", "Empezar → investigación y paso «muévete»")
	_check(not GameState.active_pings().is_empty(), "una marca guía hasta la puerta")
	_move(Vector2(1180, 250))
	await _frames(3)
	_check(tut.step == "inspect", "al entrar en el despacho: «examina» (%s)" % tut.step)
	_check(GameState.active_reveals().has("spawn_CLUE_CASINO_DEBTS"), "la prueba brilla")
	var spot = main.find_child("spawn_CLUE_CASINO_DEBTS", true, false)
	_check(spot != null and not spot.contents.is_empty(), "el punto real de la oficina tiene la prueba")
	EventBus.evidence_inspect_requested.emit(spot)
	await _frames(3)
	_check(tut.step == "collect", "examinar → «guárdala»")
	var rejected := []
	EventBus.intent_rejected.connect(func(_s: int, r: String) -> void: rejected.append(r))
	_move(Vector2(1100, 130))
	await _frames(2)
	Network.send_intent(Protocol.I_INTERACT, {"interactableId": "spawn_CLUE_UNLOCKED_LAPTOP"})
	await _frames(3)
	_check("not_pocketable" in rejected, "la laptop no se puede llevar (rechazo como el servidor)")
	_move(Vector2(1220, 230))
	await _frames(2)
	Network.send_intent(Protocol.I_INTERACT, {"interactableId": "spawn_CLUE_CASINO_DEBTS"})
	await _frames(3)
	_check(GameState.my_private_state().get("inventory", []).size() == 1, "la prueba está en tu inventario")
	_check(tut.step == "backup", "guardar → «haz una copia»")

	_move(Vector2(1080, 120))
	await _frames(2)
	Network.send_intent(Protocol.I_CHANNEL_START, {"evidenceInstanceId": "ev_laptop", "action": "backup"})
	await _frames(2)
	_move(Vector2(1120, 140))
	await _frames(3)
	_check(tut.step == "backup" and tut.note_label.visible, "moverse corta la copia y se avisa")
	await _frames(15)   # la barra cortada termina de cerrarse
	_move(Vector2(1080, 120))
	await _frames(5)
	Network.send_intent(Protocol.I_CHANNEL_START, {"evidenceInstanceId": "ev_laptop", "action": "backup"})
	await get_tree().create_timer(3.3).timeout
	await _frames(3)
	_check(srv.has_copy(), "copia de la laptop en el inventario")
	_check(tut.step == "witness" and tut.next_button.disabled, "copia → escena del pasillo (botón bloqueado mientras pasa)")
	await get_tree().create_timer(3.7).timeout
	await _frames(3)
	_check(GameState.witness_log.size() == 1 and GameState.bodies().size() == 1, "lo has visto: testigo y cuerpo en el suelo")
	_check(not tut.next_button.disabled, "«Entendido» se activa")
	tut.next_pressed()
	_check(tut.step == "report", "paso «reporta»")
	Network.send_intent(Protocol.I_REPORT_BODY, {"bodyId": "body:eva"})
	await _frames(3)
	_check("too_far" in rejected, "lejos del cuerpo: too_far")
	_move(srv.body_position() + Vector2(-60, 0))
	Network.send_intent(Protocol.I_REPORT_BODY, {"bodyId": "body:eva"})
	await _frames(3)
	_check(GameState.phase() == "emergency" and tut.step == "vote", "reportar abre la asamblea")
	Network.send_intent(Protocol.I_EMERGENCY_VOTE, {"targetId": "dani"})
	await get_tree().create_timer(2.2).timeout
	await _frames(3)
	var result = GameState.emergency().get("result")
	_check(result is Dictionary and result.get("expelled") == "dani", "3 de 4 votos: Dani expulsado")
	_check(tut.step == "verdict_wait" and "no se revela" in tut.text_label.text, "el rol del expulsado no se revela")
	tut.next_pressed()
	await _frames(3)
	_check(GameState.phase() == "discussion" and tut.step == "present", "juicio final: «expón una prueba»")
	Network.send_intent(Protocol.I_PRESENT, {"evidenceInstanceId": "ev_debts"})
	await _frames(3)
	_check(tut.step == "verdict", "exponer → «vota el veredicto»")
	await get_tree().create_timer(3.3).timeout
	await _frames(3)
	_check(GameState.phase() == "voting" and GameState.snapshot.get("trial", {}).get("deck", []).size() == 3, "los bots exponen y se pasa a votar (%d en la mesa)" % GameState.snapshot.get("trial", {}).get("deck", []).size())
	Network.send_intent(Protocol.I_VOTE, {"optionId": "despedir_ceo"})
	await get_tree().create_timer(1.6).timeout
	await _frames(3)
	var res = GameState.snapshot.get("trial", {}).get("resolution")
	_check(GameState.phase() == "results" and res is Dictionary, "resultados con resolución")
	_check(res is Dictionary and "me" in res.get("winners", []), "despedir al CEO: ganas")
	_check(tut.step == "done" and tut.completed, "práctica completada")
	_check(Account.tutorial_reward_pending, "sin conexión: la XP queda pendiente para el servidor")
	_check(Account.flush_tutorial_reward() == -1, "con la práctica enganchada no se pide nada")
	_check("+%d XP" % int(load("res://scripts/menu/DetectivePath.gd").tutorial_reward().get("xp", 0)) in tut.text_label.text, "el panel final anuncia la XP")
	var g = srv.snapshot()["you"]["objectives"]
	_check(g.all(func(o): return o["completed"]), "objetivos de práctica cumplidos")

	tut.finish()
	await _frames(2)
	_check(Network.local_server == null, "al salir se desengancha de Network")
	_check(not GameState.in_room(), "sin sala al volver")
	_finish()

func _move(p: Vector2) -> void:
	var me = main.get_node("Map/Players").get_player("me")
	if me:
		me.teleport(p)
	Network.send_intent(Protocol.I_MOVE, {"position": Protocol.vec2_to(p)})

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func _check(ok: bool, text: String) -> void:
	print("  ", "ok  " if ok else "FAIL", " ", text)
	if not ok:
		_failures += 1

func _finish() -> void:
	Account.tutorial_seen = _saved["seen"]
	Account.tutorial_reward_pending = _saved["pending"]
	Account.profile = _saved["profile"]
	Account._save()
	print("TutorialTest: ", "OK" if _failures == 0 else "%d fallos" % _failures)
	get_tree().quit(1 if _failures > 0 else 0)
