extends Node
## Prueba sin servidor: godot --headless res://tests/TrialTest.tscn
## Simula los snapshots del servidor y comprueba la pantalla de juicio y la final.

const FakeNetwork := preload("res://tests/FakeNetwork.gd")

var _failures := 0

func _ready() -> void:
	Network.player_id = "me"
	var net := FakeNetwork.new()
	add_child(net)
	var trial := TrialSystem.new()
	trial.network = net
	add_child(trial)
	var screen: AssemblyBoardUI = preload("res://scenes/ui/AssemblyBoardUI.tscn").instantiate()
	screen.trial = trial
	add_child(screen)
	var map := Node2D.new()
	add_child(map)
	var views := PhaseViewController.new()
	views.exploration_view = map
	views.board = screen
	add_child(views)
	var asked := []
	screen.evidence_presented.connect(func(e: EvidenceData, pid: String) -> void:
		asked.append([e.instance_id, pid])
		screen.assembly.present(e.instance_id))
	var final_screen := ResolutionScreen.new()
	final_screen.trial = trial
	add_child(final_screen)

	var knife := {"instanceId": "ev_1", "visibility": "full", "name": "Cuchillo", "description": "Con iniciales."}
	var logs := {"instanceId": "ev_2", "visibility": "full", "name": "Logs", "description": "SSH.", "content": {"text": "02:03 cto"},
		"medium": "digital/critica", "pocketable": true, "isCopy": true}
	var base := {
		"version": 1, "phase": "discussion", "phaseEndsAt": null,
		"players": [{"id": "me", "name": "Ana"}, {"id": "p2", "name": "Beto"}],
		"interactables": [],
		"you": {"roleId": "ROLE_CTO", "team": "inocentes", "objectives": [], "inventory": [knife, logs], "knownTeammates": []},
		"trial": {"deck": [], "options": [{"id": "despedir_ceo", "label": "Despedir al CEO", "accusesRole": "ROLE_CEO"},
				{"id": "despedir_cto", "label": "Despedir al CTO", "accusesRole": "ROLE_CTO"}, {"id": "abstain", "label": "No acusar a nadie"}],
			"voted": [], "myVote": null, "maxPresentedPerPlayer": 1, "resolution": null},
	}

	var assembly := screen.assembly
	var presented := []
	assembly.evidence_presented.connect(func(e, by): presented.append([e.display_name, by]))

	# 1. Debate: la pantalla aparece y ofrece el inventario (copias incluidas).
	var lobby := base.duplicate(true)
	lobby["phase"] = "investigation"
	GameState._replace(lobby)
	_check(not screen.visible and map.visible and views.view == "exploration", "en la investigación se ve el mapa, no la mesa")
	GameState._replace(base.duplicate(true))
	_check(screen.visible, "la mesa de asamblea se despliega en el debate")
	_check(not map.visible and map.process_mode == Node.PROCESS_MODE_DISABLED, "la exploración se oculta y se pausa")
	_check(assembly.player_inventory().size() == 2, "el inventario incluye la copia de los logs")
	_check(not trial.can_vote(), "en el debate aún no se vota")
	_check(screen._hand_box.get_child_count() == 2, "una carta por prueba en la mano")
	_check(screen._orbit.get_child_count() == 2 and _has_text(screen, "Ana (tú)"), "un asiento por jugador")
	_check(_has_text(screen, "ASAMBLEA EXTRAORDINARIA DEL DIRECTORIO"), "título de la asamblea")
	assembly.select("ev_2")
	_check(assembly.selected.instance_id == "ev_2" and _has_text(screen, "Colocar «Logs» en la mesa"), "clic selecciona la prueba")
	_check(assembly.can_drop(TrialAssemblyManager.drag_data(assembly.selected)), "la mesa acepta soltarla")
	_check(not assembly.can_drop({"type": "otra_cosa"}), "la mesa rechaza otros arrastres")
	screen._drop_zone.on_drop.call(TrialAssemblyManager.drag_data(assembly.selected))
	_check(asked == [["ev_2", "me"]], "soltarla emite evidence_presented(evidence_data, player_id)")
	_check(net.sent[-1]["t"] == "present_evidence" and net.sent[-1]["evidenceInstanceId"] == "ev_2", "y se envía al servidor")
	var before := net.sent.size()
	assembly.accuse("despedir_ceo")
	_check(net.sent.size() == before and _has_text(screen, "Ahora no se puede"), "Acusar no funciona en el debate")

	# 2. El servidor la pone en la mesa: aparece para todos y se agota el cupo.
	var s := base.duplicate(true)
	s["trial"]["deck"] = [{"instanceId": "ev_2", "presentedBy": "me", "at": 0, "evidence": logs}]
	GameState._replace(s)
	_check(trial.deck.size() == 1 and trial.deck[0]["evidence"].display_name == "Logs", "la mesa pública muestra la prueba")
	_check(presented == [["Logs", "me"]], "emite evidence_presented(evidence_data, player_id)")
	_check(assembly.player_inventory().size() == 1, "lo ya expuesto no se ofrece otra vez")
	_check(not trial.can_present(), "cupo de exposición agotado")
	_check(not assembly.can_present("ev_1") and not assembly.present("ev_1"), "el cupo se comprueba antes de enviar")
	_check(screen.center_frame.frame_id() == "terminal" and screen.center_frame.visible_text().contains("02:03 cto"), "el centro de la mesa la muestra en su marco")
	_check(_has_text(screen, "expuesta por Ana"), "dice quién la expuso")
	_check(screen.find_child("SlotEvidence_1", true, false) != null, "la carta ocupa un hueco de la mesa")
	_check(_has_text(screen, "1 prueba"), "el asiento cuenta las pruebas expuestas")
	GameState._replace(s.duplicate(true))
	_check(presented.size() == 1, "no se anuncia dos veces")

	# 3. Votación: se vota una decisión narrativa.
	s["phase"] = "voting"
	GameState._replace(s.duplicate(true))
	_check(trial.can_vote(), "se abre la votación")
	var selector: OptionButton = screen._vote_selector
	_check(selector.item_count == 2 and not selector.disabled, "el selector lista a quién expulsar (sin la abstención)")
	_check(screen._skip_btn.visible and not screen._skip_btn.disabled, "botón Abstenerse")
	selector.select(0)
	screen._accuse_btn.pressed.emit()
	_check(net.sent[-1]["t"] == "vote" and net.sent[-1]["optionId"] == "despedir_ceo", "Confirmar Voto de Expulsión envía el voto")
	s["trial"]["myVote"] = "despedir_ceo"
	s["trial"]["voted"] = ["me", "p2"]
	s["trial"]["tally"] = {"despedir_ceo": 1, "despedir_cto": 1, "abstain": 0}
	GameState._replace(s.duplicate(true))
	_check(selector.get_item_text(selector.selected).begins_with("● Despedir al CEO"), "se marca tu voto")
	_check(screen._accuse_btn.text == "Retirar mi voto", "el botón permite retirarlo")
	_check(_has_text(screen, "votó"), "los asientos muestran quién ha votado, no a quién")
	_check(_has_text(screen, "Han votado 2 de 2"), "muestra cuántos han votado")
	_check(assembly.votes_by_role() == {"ROLE_CEO": 1, "ROLE_CTO": 1}, "votos recibidos por cada rol")
	_check(selector.get_item_text(0).ends_with("·  1"), "muestra los votos de cada opción")
	screen._skip_btn.pressed.emit()
	_check(net.sent[-1]["optionId"] == "abstain", "Abstenerse vota la abstención")
	assembly.accuse("despedir_ceo")
	_check(net.sent[-1]["t"] == "vote" and net.sent[-1]["optionId"] == null, "pulsar tu opción otra vez retira el voto")
	_check(assembly.accuse_role("ROLE_CTO") and net.sent[-1]["optionId"] == "despedir_cto", "acusar por rol")

	# 4. Rechazo del servidor.
	trial.present("ev_1")
	EventBus.intent_rejected.emit(net.sent.size(), "present_limit")
	_check(_has_text(screen, "Ya has expuesto todas"), "explica el rechazo")

	# 5. Resolución.
	s["phase"] = "results"
	s["trial"]["resolution"] = {
		"verdict": {"optionId": "despedir_ceo", "label": "Despedir al CEO", "tally": {"despedir_ceo": 2}, "accused": ["p2"]},
		"endings": [{"id": "cto_gana", "title": "El CTO limpia su nombre", "description": "..."}],
		"winners": ["me"],
		"players": [
			{"id": "me", "name": "Ana", "roleId": "ROLE_CTO", "roleName": "El CTO", "team": "inocentes", "won": true,
				"objectives": [{"id": "o1", "description": "Probar la IP", "completed": true}]},
			{"id": "p2", "name": "Beto", "roleId": "ROLE_CEO", "roleName": "El CEO", "team": "culpables", "won": false, "objectives": []},
		],
		"revealedEvidence": ["CLUE_SERVER_LOGS"],
	}
	GameState._replace(s)
	_check(not screen.visible and views.view == "results", "el juicio se cierra en resultados")
	_check(final_screen.visible, "aparece la pantalla final")
	await get_tree().process_frame
	_check(_has_text(final_screen, "El CTO limpia su nombre"), "muestra el final")
	_check(_has_text(final_screen, "Has ganado."), "dice si has ganado")
	_check(_has_text(final_screen, "Beto — El CEO"), "revela los roles")

	# 6. Un delta del servidor que cambia el inventario llega a InventoryManager
	#    (p. ej. la copia que deja un backup_action completado).
	var inv := InventoryManager.new()
	add_child(inv)
	var lobby2 := base.duplicate(true)
	lobby2["phase"] = "investigation"
	lobby2["you"]["inventory"] = []
	GameState._replace(lobby2)
	_check(inv.size() == 0, "inventario vacío al empezar")
	GameState._apply_delta({"to": 99, "ops": [{"op": "set", "path": ["you", "inventory"], "value": [logs]}]})
	_check(inv.size() == 1 and inv.items()[0].is_copy, "la copia del backup entra en InventoryManager por delta")

	print("TrialTest: ", "OK" if _failures == 0 else "%d fallos" % _failures)
	get_tree().quit(1 if _failures > 0 else 0)

func _has_text(root: Node, text: String) -> bool:
	for n in root.find_children("*", "", true, false):
		if (n is Label or n is Button) and not n.is_queued_for_deletion() and n.is_visible_in_tree() and n.text.contains(text):
			return true
	return false

func _check(cond: bool, label: String) -> void:
	if cond:
		print("  ok   ", label)
	else:
		_failures += 1
		print("  FAIL ", label)
