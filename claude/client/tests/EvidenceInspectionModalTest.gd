extends Node
## Prueba sin servidor: godot --headless res://tests/EvidenceInspectionModalTest.tscn

const FakeNetwork := preload("res://tests/FakeNetwork.gd")

var _failures := 0
var _modal_open := false

func _ready() -> void:
	EventBus.ui_modal_changed.connect(func(open: bool): _modal_open = open)

	var net := FakeNetwork.new()
	add_child(net)
	var inv := InventoryManager.new()
	add_child(inv)
	var evidence := EvidenceSystem.new()
	evidence.network = net
	evidence.inventory = inv
	add_child(evidence)
	var modal: EvidenceInspectionModal = preload("res://scenes/ui/EvidenceInspectionModal.tscn").instantiate()
	modal.evidence_system = evidence
	modal.inventory = inv
	add_child(modal)

	var spot := EvidenceContainer.new()
	spot.interactable_id = "estudio_mesa"
	add_child(spot)
	var locked_view := {"instanceId": "ev_1", "visibility": "partial", "locked": "view", "requiredItems": ["Llave del estudio"]}
	var open_view := {"instanceId": "ev_2", "visibility": "full", "definitionId": "carta", "name": "Carta rota",
		"description": "Una amenaza.", "tags": ["documento"], "medium": "documental/fisico", "pocketable": true, "content": {"text": "Paga o hablo."}}
	var fixed_view := {"instanceId": "ev_3", "visibility": "full", "definitionId": "pantalla", "name": "Pantalla",
		"description": "Un chat abierto.", "medium": "digital/testimonial", "pocketable": false}
	spot.set_contents(_views([locked_view, open_view, fixed_view]))

	# 1. Pulsar E sobre el objeto abre el visor y bloquea el movimiento.
	spot.interact()
	_check(modal.visible and _modal_open, "E abre el visor y bloquea el movimiento")

	# 2. Pista con candado: sin detalles, sin Guardar, dice qué llave falta.
	_check(modal._title.text == "Algo que no logras distinguir", "sin permiso de ver no hay detalles")
	_check(modal.frame_id() == "item" and modal.frame.visible_text().contains("no consigues saber"), "sin aspecto conocido: marco de objeto, sin contenido")
	_check(modal._lock.text.contains("Llave del estudio"), "indica la llave que falta")
	_check(modal._save.disabled, "Guardar desactivado con candado")

	# 3. Pista visible: texto completo y se puede guardar la pieza concreta.
	modal.show_page(1)
	_check(modal.frame_id() == "paper", "Documental / Físico se ve en una hoja de papel")
	_check(modal.frame.visible_text().contains("Paga o hablo."), "muestra el texto de la pista")
	_check(modal.action_buttons().is_empty(), "sin acciones autorizadas no hay botones")
	_check(not modal._save.disabled, "Guardar activo")
	modal.save_current()
	var last: Dictionary = net.sent[-1]
	_check(last["t"] == "interact" and last["evidenceInstanceId"] == "ev_2", "pide al servidor esa pieza concreta")
	_check(modal._save.disabled, "no se puede pulsar dos veces")

	# 4. El servidor confirma: llega al inventario y desaparece del objeto.
	var added := []
	inv.item_added.connect(func(e): added.append(e.instance_id))
	spot.set_contents(_views([locked_view, fixed_view]))
	inv.replace_from_views([open_view])
	_check(added == ["ev_2"] and inv.has_definition("carta"), "InventoryManager la recibe")
	_check(modal._status.text.contains("Guardada"), "el visor confirma el guardado")

	# 5. Pista que no se puede llevar.
	modal.show_page(1)
	_check(modal.frame_id() == "phone", "Digital / Testimonial se ve en un marco de celular")
	_check(modal._save.disabled and modal._lock.text.contains("solo examinarla"), "las fijas solo se examinan")

	# 6. Un rechazo del servidor se muestra en el visor.
	modal.show_page(0)
	modal._awaiting = "ev_1"
	evidence.collect("estudio_mesa", "ev_1")
	EventBus.intent_rejected.emit(net.sent.size(), "requires_item")
	_check(modal._status.text == "Te falta algo para poder llevártela.", "muestra el motivo del rechazo")

	# 7. Cerrar devuelve el control.
	modal.close()
	_check(not modal.visible and not _modal_open, "cerrar devuelve el control")

	# 8. Terminal con acciones del rol: el botón arranca la acción canalizada.
	Network.player_id = "me"
	var server := EvidenceContainer.new()
	server.interactable_id = "spawn_CLUE_SERVER_LOGS"
	add_child(server)
	var logs_view := {"instanceId": "ev_9", "visibility": "full", "definitionId": "CLUE_SERVER_LOGS", "name": "Logs de Auditoría",
		"description": "Conexiones SSH.", "tags": ["digital", "critica"], "medium": "digital/critica", "pocketable": false,
		"actions": [{"kind": "backup", "label": "Descargar dump forense a dispositivo móvil", "seconds": 6}]}
	server.set_contents(_views([logs_view]))
	server.interact()
	_check(modal.frame_id() == "terminal", "Digital / Crítica se ve en una terminal de código")
	_check(modal.frame.visible_text().contains("root@srv"), "la terminal muestra el prompt")
	_check(modal.action_buttons().size() == 1 and modal.action_buttons()[0].name == "BackupEvidenceBtn" and modal.action_buttons()[0].text.contains("(6 s)"), "footer: solo BackupEvidenceBtn, con su tiempo")
	_check(modal.frame.name == "TerminalView" and modal.frame.get_parent().name == "ContentSlot", "la vista se inyecta en el ContentSlot")
	_check(modal._bezel.visible and modal._bezel.texture != null and modal._bezel.patch_margin_left == 40, "bisel de monitor como 9-slice detrás de la vista")
	_check(modal._lock.text.contains("copiarla"), "explica que se puede sacar copia")
	var crt: ColorRect = modal.frame.crt_overlay
	_check(crt != null and crt.mouse_filter == Control.MOUSE_FILTER_IGNORE and (crt.material as ShaderMaterial).shader.resource_path.ends_with("crt_terminal_screen.gdshader"), "la pantalla lleva el shader CRT sin bloquear el ratón")
	var requested := []
	modal.action_requested.connect(func(e, kind): requested.append([e.instance_id, kind]))
	modal.action_buttons()[0].pressed.emit()
	last = net.sent[-1]
	_check(last["t"] == "channel_start" and last["evidenceInstanceId"] == "ev_9" and last["action"] == "backup", "el botón pide la acción canalizada")
	_check(requested == [["ev_9", "backup"]], "emite action_requested")
	_check(modal.action_buttons()[0].disabled, "no se puede pulsar dos veces")
	EventBus.channel_started.emit("me", {"kind": "backup", "label": "x", "startedAt": 0, "durationMs": 6000})
	_check(not modal.visible, "se cierra cuando el servidor arranca la barra")

	# 9. Vista parcial de una terminal: se ve la carcasa, no el contenido; un rechazo vuelve a habilitar.
	var partial_view := {"instanceId": "ev_10", "visibility": "partial", "medium": "digital/critica",
		"actions": [{"kind": "delete", "label": "Purgar partición /var/log/audit.log", "seconds": 10}]}
	server.set_contents(_views([partial_view]))
	server.interact()
	_check(modal.frame_id() == "terminal" and modal.frame.visible_text().contains("Permiso denegado"), "parcial: terminal sin contenido")
	_check(modal.action_buttons().size() == 1 and modal.action_buttons()[0].name == "DeleteEvidenceBtn", "el culpable ve DeleteEvidenceBtn")
	modal.start_action("delete")
	EventBus.intent_rejected.emit(net.sent.size(), "moved")
	_check(modal.visible and modal._status.text.contains("interrumpida") and not modal.action_buttons()[0].disabled, "un rechazo se explica y reactiva el botón")
	modal.close()

	# 10. Abrir una prueba suelta (inventario / mesa) sin botón Guardar.
	modal.open_evidence(EvidenceData.from_view(open_view))
	_check(modal.visible and not modal._save.visible and modal.frame_id() == "paper", "abre una prueba del inventario")
	modal.close()

	# 11. setup_inspection con la pista tal como viene en el JSON del caso.
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/scenarios/caso_fraude_tech_startup.json"))
	var logs_clue: Dictionary = raw["clues_and_evidence"][0]
	modal.setup_inspection(logs_clue, "ROLE_CEO")
	_check(modal.frame_id() == "terminal" and modal.action_buttons().map(func(b): return str(b.name)) == ["DeleteEvidenceBtn"], "CEO: solo deletion_action")
	_check(modal._delete_btn.text.contains("Purgar partición") and modal._delete_btn.text.contains("(10 s)"), "con el nombre y tiempo del caso")
	modal.close()
	modal.setup_inspection(logs_clue, "ROLE_CTO")
	_check(modal.action_buttons().map(func(b): return str(b.name)) == ["BackupEvidenceBtn"] and modal._backup_btn.text.contains("(6 s)"), "CTO: solo backup_action")
	modal.close()
	modal.setup_inspection(logs_clue, "ROLE_INVESTOR")
	_check(modal.action_buttons().is_empty(), "un rol sin permiso no ve botones")
	modal.close()

	print("EvidenceInspectionModalTest: ", "OK" if _failures == 0 else "%d fallos" % _failures)
	get_tree().quit(1 if _failures > 0 else 0)

func _views(list: Array) -> Array[EvidenceData]:
	var out: Array[EvidenceData] = []
	for v in list:
		out.append(EvidenceData.from_view(v))
	return out

func _check(cond: bool, label: String) -> void:
	if cond:
		print("  ok   ", label)
	else:
		_failures += 1
		print("  FAIL ", label)
