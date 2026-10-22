extends Node
## Prueba sin servidor: godot --headless res://tests/SilenceUiTest.tscn
## "Silenciar al testigo" en el cliente con snapshots y eventos falsos: botones de poder
## (solo en tu pantalla y solo con motivo), cuerpos 3D con línea de vista, bolsa de
## objetos caídos, REPORTAR, noqueo, fantasma (sin colisiones, sin línea de vista, ping y
## misiones), asamblea de emergencia, juicio tras el noqueo, cola de 4 a 12 y sala de 12.

const FakeNetwork := preload("res://tests/FakeNetwork.gd")

var _failures := 0
var _occ: Array
var main: Node
var net: Node
var view: World3DView
var hud: SocialHUD
var panel: EmergencyPanel
var spawner: PlayerSpawner
var door: Array

func _ready() -> void:
	Network.player_id = "me"
	_occ = LineOfSight.occluders_from(OfficeLayout.walls())
	door = _door_points()
	_check(not door.is_empty(), "hay una sala con puerta al pasillo para probar la línea de vista")
	if door.is_empty():
		_finish()
		return
	main = load("res://scenes/main/Main.tscn").instantiate()
	main.scenario_id = "caso_fraude_tech_startup"
	add_child(main)
	await get_tree().process_frame
	net = FakeNetwork.new()
	add_child(net)
	view = main.get_node("World3D")
	view.always_on = true
	hud = main.get_node("SocialHUD")
	hud.network = net
	panel = main.get_node("EmergencyPanel")
	panel.network = net
	spawner = main.get_node("Map/Players")
	main.get_node("Map").visible = true
	main.get_node("MainMenu").visible = false

	await _powers()
	await _bodies()
	await _events()
	await _ghost()
	await _emergency()
	await _meeting()
	_trial()
	_queue()
	await _lobby12()
	_finish()

func _finish() -> void:
	print("SilenceUiTest: ", "OK" if _failures == 0 else "%d fallos" % _failures)
	get_tree().quit(1 if _failures > 0 else 0)

# ───────────── Estado falso ─────────────

func _now() -> float:
	return Network.server_time_ms()

func _v(p: Vector2) -> Dictionary:
	return {"x": p.x, "y": p.y}

func _player(id: String, name: String, skin: String, at: Vector2, extra := {}) -> Dictionary:
	var p := {"id": id, "name": name, "skinId": skin, "position": _v(at), "connected": true, "ready": true, "alive": true, "inventoryCount": 0}
	p.merge(extra, true)
	return p

func _snap(phase: String, you_extra := {}, players_extra := {}, top := {}) -> Dictionary:
	var me_at: Vector2 = door[0]
	var players := [
		_player("me", "Ana", "panda", me_at),
		_player("beto", "Beto", "zorro", me_at + Vector2(50, 0)),
		_player("carla", "Carla", "oso", me_at + Vector2(-60, 0)),
		_player("dani", "Dani", "gato", me_at + Vector2(0, 300)),
		_player("eva", "Eva", "conejo", me_at + Vector2(0, 1200), {"ghost": true, "hidden": true}),
	]
	for p in players:
		if players_extra.has(p["id"]):
			p.merge(players_extra[p["id"]], true)
	var you := {"roleId": "ROLE_CEO", "team": "culpables", "objectives": [], "inventory": [], "knownTeammates": [], "ghost": false}
	you.merge(you_extra, true)
	var s := {"version": 1, "phase": phase, "phaseEndsAt": null,
		"lobby": {"code": "ABCDEF", "visibility": "public", "hostId": "me", "minPlayers": 4, "maxPlayers": 12, "startsAt": null},
		"players": players, "interactables": [], "you": you, "bodies": [], "emergency": null,
		"trial": {"deck": [], "options": [], "voted": [], "myVote": null, "maxPresentedPerPlayer": 1, "resolution": null}}
	s.merge(top, true)
	return s

func _apply(s: Dictionary) -> void:
	GameState._replace(s)

func _event(e: Dictionary) -> void:
	GameState._on_message({"t": "event", "version": 1, "event": e})

func _frames(n := 6) -> void:
	for i in n:
		await get_tree().process_frame

# ───────────── 1. Botones de poder ─────────────

func _powers() -> void:
	var ready := {"powers": {"silence": {"readyAt": 0}}, "motiveTargets": [{"playerId": "beto", "reason": "witness"}]}
	_apply(_snap("investigation", ready))
	await _frames()
	_check(hud.silence_button.visible and not hud.silence_button.disabled, "SILENCIAR activo con un motivo a ≤ 90 px")
	_check(hud.silence_target == "beto", "apunta al jugador con motivo")
	_check(hud.button_sub(hud.silence_button).contains("Beto") and hud.button_sub(hud.silence_button).contains("Te vio"), "muestra a quién y por qué: «%s»" % hud.button_sub(hud.silence_button))
	hud.silence_button.pressed.emit()
	_check(net.sent[-1] == {"t": "silence", "targetId": "beto", "seq": net.sent.size()}, "pulsar manda {t:'silence', targetId}")

	# Carla está a 60 px pero sin motivo: no es objetivo.
	_apply(_snap("investigation", {"powers": {"silence": {"readyAt": 0}}, "motiveTargets": [{"playerId": "dani", "reason": "evidence"}]}))
	await _frames(2)
	_check(hud.silence_button.visible and hud.silence_button.disabled and hud.silence_target == "", "sin motivo cerca no hay objetivo (Dani con motivo está lejos)")
	_apply(_snap("investigation", {"powers": {"silence": {"readyAt": 0}}, "motiveTargets": [{"playerId": "carla", "reason": "story"}]}))
	await _frames(2)
	_check(hud.silence_target == "carla" and hud.button_sub(hud.silence_button).contains("Te está chantajeando"), "motivo de la historia: «Te está chantajeando»")
	_apply(_snap("investigation", {"powers": {"silence": {"readyAt": 0}}, "motiveTargets": [{"playerId": "beto", "reason": "backup", "evidence": "Logs del servidor"}]}))
	await _frames(2)
	_check(hud.button_sub(hud.silence_button).contains("Sacó copia de «Logs del servidor»"), "motivo con el nombre de la prueba: «%s»" % hud.button_sub(hud.silence_button))
	_apply(_snap("investigation", {"powers": {"silence": {"readyAt": 0}}, "motiveTargets": [{"playerId": "beto", "reason": "evidence"}]}, {"beto": {"knocked": true}}))
	await _frames(2)
	_check(hud.silence_target == "", "a un noqueado no se le puede silenciar")

	# Primer minuto: "Aún no".
	hud._silence_used = false
	_apply(_snap("investigation", {"powers": {"silence": {"readyAt": _now() + 42000}}, "motiveTargets": [{"playerId": "beto", "reason": "witness"}]}))
	await _frames(2)
	_check(hud.silence_button.disabled and hud.button_sub(hud.silence_button).begins_with("Aún no · 4"), "primer minuto: «%s»" % hud.button_sub(hud.silence_button))
	hud._silence_used = true
	await _frames(1)
	_check(hud.button_sub(hud.silence_button).begins_with("Recarga · "), "después, la recarga")

	# Sin poder (inocente): ningún botón de poder.
	_apply(_snap("investigation", {"roleId": "ROLE_CTO", "team": "inocentes"}))
	await _frames(2)
	_check(not hud.silence_button.visible and not hud.escort_button.visible, "sin poderes no hay SILENCIAR ni ESCOLTAR")

	# Escolta (Jefe de Seguridad).
	_apply(_snap("investigation", {"roleId": "ROLE_SECURITY", "powers": {"escort": {"readyAt": 0, "protecting": null, "until": null}}}))
	await _frames(2)
	_check(hud.escort_button.visible and not hud.escort_button.disabled and hud.escort_target == "beto", "ESCOLTAR activo con alguien a ≤ 160 px")
	hud.escort_button.pressed.emit()
	_check(net.sent[-1]["t"] == "escort" and net.sent[-1]["targetId"] == "beto", "pulsar manda {t:'escort', targetId}")
	_apply(_snap("investigation", {"roleId": "ROLE_SECURITY", "powers": {"escort": {"readyAt": _now() + 80000, "protecting": "beto", "until": _now() + 40000}}}))
	await _frames(2)
	_check(hud.escort_button.disabled and hud.button_sub(hud.escort_button).begins_with("Proteges a Beto"), "muestra a quién proteges: «%s»" % hud.button_sub(hud.escort_button))
	_apply(_snap("discussion", {"powers": {"silence": {"readyAt": 0}}}))
	await _frames(2)
	_check(not hud.actions.visible, "fuera de la exploración no hay botones")

# ───────────── 2. Cuerpos ─────────────

func _bodies() -> void:
	var me_at: Vector2 = door[0]
	var bag := {"id": "body:carla", "type": "body", "position": _v(me_at + Vector2(40, 30)), "radius": 40, "ownerId": "carla",
		"label": "Objetos caídos de Carla", "contents": [{"instanceId": "ev_9", "visibility": "full", "name": "USB"}]}
	var bodies := [
		{"id": "body:carla", "playerId": "carla", "position": _v(me_at + Vector2(40, 30)), "reported": false, "kind": "knocked", "until": _now() + 20500},
		{"id": "body:dani", "playerId": "dani", "position": _v(door[2]), "reported": false, "kind": "dead"},
		{"id": "body:fede", "playerId": "fede", "position": _v(door[1]), "reported": false, "kind": "dead"},
	]
	_apply(_snap("investigation", {}, {"carla": {"knocked": true, "knockedUntil": _now() + 20500}}, {"bodies": bodies, "interactables": [bag]}))
	await _frames(12)
	var carla := view.body_prop("body:carla")
	_check(carla != null and carla.visible, "el noqueado se dibuja tumbado")
	_check(carla != null and carla.stars.visible and carla.countdown.visible and carla.countdown.text in ["20", "21"], "con estrellitas y cuenta atrás (%s)" % (carla.countdown.text if carla else "-"))
	_check(carla != null and is_equal_approx(absf(carla.model.get_parent().rotation.z), PI / 2.0), "tumbado en el suelo")
	_check(not spawner.get_player("carla").visible, "su personaje de pie no se dibuja mientras está noqueado")
	var dani := view.body_prop("body:dani")
	_check(dani != null and not dani.visible, "un cuerpo tras el muro no se ve (línea de vista)")
	var fede := view.body_prop("body:fede")
	_check(fede != null and fede.visible and not fede.stars.visible, "el cuerpo definitivo a la vista se ve, sin estrellas")
	_check(fede != null and _has_ko_eyes(fede.model), "con los ojos en X")
	var bags: BodyContainers = main.get_node("BodyContainers")
	var node := bags.get_container("body:carla")
	_check(node != null and node is InteractableEvidence and node.get_prompt() == "Objetos caídos de Carla", "la bolsa de objetos caídos es interactuable")
	_check(node != null and node.has_perceivable_contents() and node.get_parent() == main.get_node("Map/Evidence"), "con lo que soltó, junto a las pistas")
	_check(hud.report_button.visible and hud.report_body == "body:carla", "REPORTAR aparece junto a un cuerpo sin reportar")
	_check(hud.button_sub(hud.report_button).contains("Carla"), "dice de quién es: «%s»" % hud.button_sub(hud.report_button))
	hud.report_button.pressed.emit()
	_check(net.sent[-1]["t"] == "report_body" and net.sent[-1]["bodyId"] == "body:carla", "pulsar manda {t:'report_body', bodyId}")
	bodies[0]["reported"] = true
	bodies.remove_at(2)
	_apply(_snap("investigation", {}, {}, {"bodies": bodies}))
	await _frames(3)
	_check(view.body_prop("body:carla") == null and view.body_prop("body:fede") == null, "reportado o levantado: deja de dibujarse")
	_check(bags.get_container("body:carla") == null, "la bolsa se quita si el servidor la quita")
	_check(not hud.report_button.visible, "sin cuerpos cerca no hay REPORTAR")

func _has_ko_eyes(model: PlushAvatar3D) -> bool:
	return model.knocked_face() == "dead"

# ───────────── 3. Eventos ─────────────

func _events() -> void:
	_apply(_snap("investigation", {"powers": {"silence": {"readyAt": 0}}}))
	await _frames(2)
	_event({"e": "body_reported", "by": "beto", "bodyId": "body:carla", "victim": "carla"})
	_check(hud.banner.visible and hud.banner_title.text == "¡CUERPO ENCONTRADO!" and hud.banner_sub.text.contains("Beto"), "banner dramático al reportar")
	_event({"e": "silenced", "killer": "me", "victim": "beto", "at": 1, "knocked": true, "until": _now() + 30000})
	_check(_toasts_contain("Has noqueado a Beto"), "al asesino: confirmación")
	_event({"e": "witnessed", "killer": "beto", "victim": "carla", "at": 2})
	_check(GameState.witness_log.size() == 1 and _toasts_contain("Viste a Beto silenciar a Carla"), "testigo: aviso «Viste a Beto silenciar a Carla»")
	await _frames(2)
	_check(hud.witness_panel.visible and (hud.witness_box.get_child(0) as Label).text == "Viste a Beto silenciar a Carla", "y queda en el registro persistente")
	_event({"e": "escort_blocked", "target": "me"})
	_check(_toasts_contain("Tu escolta te ha protegido"), "escort_blocked al protegido")
	_event({"e": "escort_blocked", "target": "dani"})
	_check(_toasts_contain("Dani estaba escoltado"), "escort_blocked al asesino")
	_event({"e": "ghost_ping", "by": "eva", "position": _v(door[0] + Vector2(100, 0)), "until": _now() + 6000})
	await _frames(2)
	_check(GameState.active_pings().size() == 1 and view.beacon_keys().any(func(k): return str(k).begins_with("ping:")), "ping fantasma: marcador brillante en el mapa")
	_check(main.get_node("UI/OfficeHUD").minimap.markers()["pings"].size() == 1, "y en el minimapa")
	_check(_toasts_contain("Un fantasma te señala") and not _toasts_contain("Eva"), "aviso del ping sin decir quién")
	_event({"e": "ghost_reveal", "interactableId": "CLUE_SERVER_LOGS", "position": _v(door[1]), "until": _now() + 20000})
	_check(GameState.active_reveals().has("CLUE_SERVER_LOGS"), "ghost_reveal: la pista brilla 20 s")
	# Noqueo: pantalla sin el nombre del asesino.
	_event({"e": "silenced", "victim": "me", "at": 3, "knocked": true, "until": _now() + 30000})
	_apply(_snap("investigation", {"wasKnocked": true}, {"me": {"knocked": true, "knockedUntil": _now() + 30000}}))
	await _frames(2)
	_check(hud.knocked_overlay.visible and hud.knocked_title.text == "Te han noqueado por la espalda", "pantalla «Te han noqueado por la espalda»")
	_check(hud.knocked_timer.text.begins_with("Te levantarás en "), "con la cuenta atrás: «%s»" % hud.knocked_timer.text)
	_check(not _tree_text(hud.knocked_overlay).contains("Beto"), "sin el nombre del asesino")
	_check(_tree_text(hud.knocked_overlay).contains("no podrás presentar pruebas"), "avisa de que no podrá presentar pruebas")
	var me: Player = spawner.get_player("me")
	_check(me.knocked and not me.visible, "noqueado: no se mueve ni se dibuja de pie")
	_check(not hud.silence_button.visible and not hud.report_button.visible, "noqueado: sin botones")

# ───────────── 4. Fantasma ─────────────

func _ghost() -> void:
	var tasks := [{"id": "t1", "label": "Encender el SAI", "position": _v(door[0] + Vector2(30, 0)), "done": false},
		{"id": "t2", "label": "Revisar la taquilla", "position": _v(door[0] + Vector2(900, 0)), "done": true}]
	_event({"e": "silenced", "victim": "me", "at": 4, "knocked": false})
	_check(hud.ghost_overlay.visible and hud.ghost_title.text == "Te han silenciado", "pantalla «Te han silenciado»")
	_apply(_snap("investigation", {"ghost": true, "ghostTasks": tasks, "ghostPingReadyAt": 0, "powers": {"silence": {"readyAt": 0}}},
		{"me": {"alive": false, "ghost": true}, "eva": {"hidden": false}},
		{"bodies": [{"id": "body:dani", "playerId": "dani", "position": _v(door[2]), "reported": false, "kind": "dead"}]}))
	await _frames(12)
	var me: Player = spawner.get_player("me")
	_check(me.ghost and me.modulate.a < 0.5, "tu avatar es translúcido")
	_check(me.collision_mask == 0, "sin colisiones: atraviesa paredes")
	_check(not view.line_of_sight.active, "sin línea de vista: lo ves todo")
	_check(view.body_prop("body:dani") != null and view.body_prop("body:dani").visible, "el cuerpo tras el muro ya se ve")
	_check(spawner.get_player("eva").visible, "los fantasmas ven a los fantasmas")
	_check(not hud.silence_button.visible and not hud.escort_button.visible and not hud.report_button.visible, "el fantasma no tiene botones de vivo")
	var det: InteractionDetector = me.get_node("InteractionDetector")
	_check(det.focused == null, "ni interactúa con pistas")
	_check(hud.ping_button.visible and not hud.ping_button.disabled, "PING FANTASMA disponible")
	_check(hud.ghost_panel.visible and _tree_text(hud.ghost_tasks_box).contains("Encender el SAI"), "panel de misiones fantasma")
	_check(hud.task_button.visible and hud.task_target == "t1", "MISIÓN a ≤ 80 px de una misión pendiente")
	hud.task_button.pressed.emit()
	_check(net.sent[-1]["t"] == "ghost_task" and net.sent[-1]["taskId"] == "t1", "pulsar manda {t:'ghost_task', taskId}")
	_check(view.beacon_keys().has("task:t1") and not view.beacon_keys().has("task:t2"), "marcador de la misión pendiente en el mapa")
	_check(main.get_node("UI/OfficeHUD").minimap.markers()["tasks"].size() == 1, "y en el minimapa")
	hud.ping_button.pressed.emit()
	_check(hud.aiming_ping and hud.aim_hint.visible, "PING: espera un clic o toque en el mapa")
	hud.send_ping(Vector2(321, 654))
	_check(net.sent[-1]["t"] == "ghost_ping" and net.sent[-1]["position"] == {"x": 321.0, "y": 654.0} and not hud.aiming_ping, "manda {t:'ghost_ping', position}")
	# Vivo: el fantasma no se ve.
	_apply(_snap("investigation"))
	await _frames(4)
	_check(not spawner.get_player("eva").visible, "los vivos no ven a los fantasmas (hidden)")
	_check(view.line_of_sight.active, "vivo de nuevo: vuelve la línea de vista")
	_check(spawner.get_player("me").collision_mask != 0, "y las colisiones")

# ───────────── 5. Asamblea de emergencia ─────────────

func _emergency() -> void:
	var em := {"calledBy": "beto", "bodyId": "body:carla", "voted": ["beto"], "myVote": null, "endsAt": _now() + 60000, "remaining": 60000, "result": null}
	_apply(_snap("emergency", {}, {}, {"emergency": em, "bodies": [{"id": "body:carla", "playerId": "carla", "position": _v(door[0]), "reported": true, "kind": "dead"}]}))
	await _frames(3)
	var views: PhaseViewController = main.get_node("PhaseViewController")
	_check(views.view == "emergency" and panel.visible, "la fase emergency abre la asamblea")
	_check(not main.get_node("Map").visible, "con el mapa en pausa")
	_check(panel.subtitle.text.contains("Beto") and panel.subtitle.text.contains("Carla"), "quién la convocó y de quién era el cuerpo")
	_check(panel.grid.get_child_count() == 4, "una tarjeta por jugador en pie (sin el fantasma): %d" % panel.grid.get_child_count())
	var all := _tree_text(panel.root)
	_check(not all.contains("ROLE_") and not all.contains("CEO") and not all.contains("culpable"), "nunca muestra roles")
	_check(panel.card("beto") != null and _tree_text(panel.card("beto")).contains("HA VOTADO"), "se ve quién ha votado")
	_check(panel.timer_label.text.begins_with("00:5") or panel.timer_label.text == "01:00", "cuenta atrás (%s)" % panel.timer_label.text)
	_check(_tree_text(panel.witness_box).contains("Viste a Beto silenciar a Carla"), "lo que has visto, a mano para votar")
	panel.card("dani").pressed.emit()
	_check(net.sent[-1] == {"t": "emergency_vote", "targetId": "dani", "seq": net.sent.size()}, "clic en una tarjeta vota a ese jugador")
	panel.skip_button.pressed.emit()
	_check(net.sent[-1]["targetId"] == "skip", "Saltar voto manda 'skip'")
	em["myVote"] = "dani"
	_apply(_snap("emergency", {}, {}, {"emergency": em}))
	await _frames(1)
	panel.card("dani").pressed.emit()
	_check(net.sent[-1].has("targetId") and net.sent[-1]["targetId"] == null, "repetir el voto lo retira (null)")
	em["result"] = {"expelled": "dani", "tally": {"dani": 3, "skip": 1}}
	_apply(_snap("emergency", {}, {"dani": {"alive": false, "ghost": true, "hidden": true}}, {"emergency": em}))
	await _frames(1)
	_check(panel.result_label.text == "Dani fue expulsado", "resultado «Dani fue expulsado»")
	_check(_tree_text(panel.card("dani")).contains("EXPULSADO") and panel.skip_button.disabled, "tarjeta del expulsado y sin más votos")
	em["result"] = {"expelled": null, "tally": {"skip": 3}}
	_apply(_snap("emergency", {}, {}, {"emergency": em}))
	await _frames(1)
	_check(panel.result_label.text == "Nadie fue expulsado", "resultado «Nadie fue expulsado»")
	_event({"e": "emergency_result", "expelled": null, "tally": {}})
	_check(_toasts_contain("Nadie fue expulsado"), "emergency_result también avisa")
	em["result"] = null
	_apply(_snap("emergency", {"ghost": true}, {"me": {"alive": false, "ghost": true}}, {"emergency": em}))
	await _frames(1)
	_check(not panel.can_vote() and panel.card("beto").disabled and panel.status_label.text.begins_with("Los fantasmas no votan"), "los fantasmas no votan")
	# 12 jugadores: 6 columnas.
	var s := _snap("emergency", {}, {}, {"emergency": em})
	for i in 7:
		s["players"].append(_player("x%d" % i, "Extra %d" % i, "lobo", Vector2.ZERO))
	_apply(s)
	await _frames(1)
	_check(panel.grid.get_child_count() == 11 and panel.grid.columns == 6, "con hasta 12 jugadores caben (6 columnas)")
	_apply(_snap("investigation"))
	await _frames(2)
	_check(not panel.visible and views.view == "exploration", "al volver a la investigación se cierra")

# ───────────── 5b. Botón de emergencia y chats (fusión con call_meeting/chat de D:) ─────────────

func _meeting() -> void:
	var office: OfficeHUD = main.get_node("UI/OfficeHUD")
	var btn: Button = office.meeting_button
	var menu_btn: Button = main.get_node("UI/InGameMenu")._call_meeting_btn
	_apply(_snap("briefing"))
	await _frames(1)
	_check(btn != null and not btn.visible, "botón de emergencia oculto en el briefing")
	_apply(_snap("investigation"))
	await _frames(1)
	_check(btn.visible and not btn.disabled and btn.text == SocialHUD.MEETING_TEXT, "«Convocar reunión de emergencia» en la investigación (%s)" % btn.text)
	_check(menu_btn != null and menu_btn.visible and menu_btn.text == SocialHUD.MEETING_TEXT, "y en el menú en partida")
	btn.pressed.emit()
	_check(net.sent[-1]["t"] == "call_meeting", "pulsarlo manda {t:'call_meeting'}")
	EventBus.intent_rejected.emit(net.sent[-1]["seq"], "no_meetings_left")
	_check(_toasts_contain("Ya no quedan reuniones"), "rechazo no_meetings_left avisado")
	_apply(_snap("investigation", {"meetingUsed": true}))
	await _frames(1)
	var before: int = net.sent.size()
	btn.pressed.emit()
	_check(btn.visible and btn.disabled and btn.text == SocialHUD.MEETING_USED_TEXT and net.sent.size() == before, "ya usada: deshabilitado y no envía")
	_check(menu_btn.disabled, "también en el menú en partida")
	_apply(_snap("investigation", {}, {"me": {"knocked": true}}))
	await _frames(1)
	_check(btn.visible and btn.disabled, "noqueado: deshabilitado")
	_apply(_snap("investigation", {"ghost": true}, {"me": {"alive": false, "ghost": true}}))
	await _frames(1)
	_check(not btn.visible and not menu_btn.visible, "fantasma: sin botón de emergencia")
	# Alguien lo pulsa: aviso a todos y asamblea "sin cuerpo".
	_apply(_snap("investigation"))
	_event({"e": "meeting_called", "by": "beto"})
	_check(hud.banner.visible and hud.banner_title.text == "¡REUNIÓN DE EMERGENCIA!" and hud.banner_sub.text.contains("Beto"), "banner «¡REUNIÓN DE EMERGENCIA!»")
	var em := {"calledBy": "beto", "bodyId": null, "voted": [], "myVote": null, "endsAt": _now() + 60000, "remaining": 60000, "result": null}
	_apply(_snap("emergency", {}, {}, {"emergency": em}))
	await _frames(2)
	_check(panel.visible and panel.subtitle.text.contains("Beto") and panel.subtitle.text.contains("botón de emergencia"), "asamblea convocada con el botón (%s)" % panel.subtitle.text)
	_check(panel.chat_panel.visible and panel.chat_input.editable and not panel.chat_send.disabled, "chat de la asamblea para los vivos")
	panel.send_chat("  Fue Dani  ")
	_check(net.sent[-1] == {"t": "chat", "text": "Fue Dani", "seq": net.sent.size()}, "Enviar manda {t:'chat', text}")
	_event({"e": "chat", "by": "beto", "name": "Beto", "text": "Yo vi a [Carla]", "at": 1})
	_check(panel.chat_texts() == ["Beto: Yo vi a [Carla]"], "el chat llega a la asamblea (%s)" % [panel.chat_texts()])
	_apply(_snap("emergency", {"ghost": true}, {"me": {"alive": false, "ghost": true}}, {"emergency": em}))
	await _frames(1)
	before = net.sent.size()
	panel.send_chat("soy un fantasma")
	_check(not panel.chat_input.editable and panel.chat_send.disabled and net.sent.size() == before, "el fantasma lee el chat pero no escribe")
	# Juicio final: el chat de debate de D: y "Pasar a votación"; el fantasma no escribe.
	_apply(_snap("discussion"))
	await _frames(2)
	var board: AssemblyBoardUI = main.get_node("UI/AssemblyBoardUI")
	_check(board.visible and board._chat_input != null and board._chat_input.editable and board._skip_to_voting_btn.visible, "debate: chat y «Pasar a votación»")
	_apply(_snap("discussion", {"ghost": true}, {"me": {"alive": false, "ghost": true}}))
	await _frames(1)
	_check(not board._chat_input.editable and board._chat_send_btn.disabled and not board._skip_to_voting_btn.visible, "fantasma en el debate: sin escribir ni adelantar la votación")
	_apply(_snap("investigation"))
	await _frames(2)

# ───────────── 6. Juicio y emparejamiento ─────────────

func _trial() -> void:
	var trial: TrialSystem = main.get_node("TrialSystem")
	var item := {"instanceId": "ev_1", "visibility": "full", "name": "Logs"}
	_apply(_snap("discussion", {"inventory": [item], "wasKnocked": true}))
	var assembly: TrialAssemblyManager = main.get_node("TrialAssemblyManager")
	_check(not trial.can_present() and assembly.why_not_present("ev_1").contains("noquearon"), "noqueado antes: no presenta pruebas en el juicio")
	_apply(_snap("voting", {"inventory": [item], "wasKnocked": true}))
	_check(trial.can_vote(), "pero sí vota")
	_apply(_snap("voting", {"ghost": true}, {"me": {"alive": false, "ghost": true}}))
	_check(not trial.can_vote(), "el fantasma no vota en el juicio")

func _queue() -> void:
	Account._on_message({"t": "queued", "position": 1, "waiting": 5, "matchSize": 12, "minSize": 4, "startsAt": _now() + 22600})
	_check(Account.match_size == 12 and Account.queue_min_size == 4, "queued: plazas 4 a 12")
	_check(Account.queue_text() == "Buscando partida 5/12 · empieza en 23 s", "«%s»" % Account.queue_text())
	Account._on_message({"t": "queued", "position": 1, "waiting": 2, "matchSize": 12, "minSize": 4, "startsAt": null})
	_check(Account.queue_text() == "Buscando partida 2/12 · faltan 2 para empezar", "«%s»" % Account.queue_text())
	Account._on_message({"t": "queued", "position": 0, "waiting": 0, "matchSize": 12, "minSize": 4, "startsAt": null})

func _lobby12() -> void:
	var stage: LobbyStage = LobbyStage.new()
	stage.size = Vector2(1100, 620)
	add_child(stage)
	await get_tree().process_frame
	var list := []
	var skins := ["pinguino", "zorro", "gato", "panda", "leon", "conejo", "oso", "perro", "lobo", "tigre", "mapache", "buho"]
	for i in 12:
		list.append({"id": "p%d" % i, "name": "Jugador %d" % i, "skinId": skins[i], "ready": i % 2 == 0, "look": {}})
	stage.set_players(list, "p0", 12, "p0")
	await get_tree().process_frame
	_check(stage.seat_count() == 12 and stage.empty_seat_count() == 0, "la sala 3D tiene 12 asientos")
	var spots := {}
	var inside := true
	for i in 12:
		var seat: LobbyStage.Seat = stage.seat_for("p%d" % i)
		spots[str(seat.slot["pos"])] = true
		inside = inside and Rect2(Vector2.ZERO, stage.size).has_point(seat.position)
	_check(spots.size() == 12, "cada uno en su sitio")
	_check(inside, "todos dentro del encuadre")
	stage.set_players(list.slice(0, 5), "p0", 12, "p0")
	_check(stage.empty_seat_count() == 7, "con 5 de 12, 7 plazas libres")
	stage.queue_free()

# ───────────── utilidades ─────────────

func _door_points() -> Array:
	var los_test := preload("res://tests/LineOfSightTest.gd").new()
	los_test._occ = _occ
	var rooms := OfficeLayout.rooms()
	var corridors := rooms.filter(func(r: Dictionary) -> bool: return los_test._is_corridor(r))
	var closed := rooms.filter(func(r: Dictionary) -> bool: return not los_test._is_corridor(r))
	var out: Array = los_test._door_view(closed, corridors)
	los_test.free()
	return out

func _toasts_contain(text: String) -> bool:
	return hud.toast_texts().any(func(t: String) -> bool: return t.contains(text))

func _tree_text(n: Node) -> String:
	var out := ""
	if n is Label:
		out += (n as Label).text + "\n"
	elif n is Button:
		out += (n as Button).text + "\n"
	for c in n.get_children():
		out += _tree_text(c)
	return out

func _check(cond: bool, label: String) -> void:
	if cond:
		print("  ok   ", label)
	else:
		_failures += 1
		print("  FAIL ", label)
