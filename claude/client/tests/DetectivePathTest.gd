extends Node
## Prueba sin servidor: godot --headless res://tests/DetectivePathTest.tscn
## Ruta del Detective en el cliente: la curva de niveles igual que el servidor, la pestaña
## con el camino (nodos bloqueados / alcanzados / actual, tarjetas de lección y retos), la
## celebración de subida de nivel, la recompensa pendiente de la práctica y los consejos
## de las primeras partidas (sin delatar roles).

const Path := preload("res://scripts/menu/DetectivePath.gd")
const FakeNetwork := preload("res://tests/FakeNetwork.gd")

var _failures := 0
var _saved := {}

func _profile(level: int, done: Array, progress := {}) -> Dictionary:
	return {"id": "perfil-test-0001", "name": "Ana", "xp": Path.xp_to_reach(level) + 10, "level": level, "xpIntoLevel": 10, "xpForLevel": Path.xp_for_level(level),
		"coins": 500, "credits": 50, "skins": ["panda"], "selectedSkin": "panda", "cosmetics": [], "equipped": {},
		"path": {"tutorialDone": "tutorial" in done, "done": done, "progress": progress, "rewarded": range(1, level + 1)}}

func _ready() -> void:
	_saved = {"profile": Account.profile, "hints": Account.hints_enabled, "pending": Account.tutorial_reward_pending, "seen": Account.seen_lessons.duplicate(), "net": Account.net, "online": Account.online}
	_curve()
	await _view()
	_popup()
	_account()
	await _hints()
	_finish()

func _curve() -> void:
	_check([1, 2, 3, 4, 5].map(func(l): return Path.xp_for_level(l)) == [300, 450, 600, 750, 900], "curva creciente igual que el servidor")
	_check(Path.xp_for_level(60) == 3000, "tope por nivel")
	_check(Path.xp_to_reach(5) == 2100, "XP para el nivel 5: 2.100")
	_check(Path.progress_for(2100) == {"level": 5, "into": 0, "need": 900}, "XP → nivel")
	_check(Path.progress_for(2099)["level"] == 4, "un punto antes, nivel 4")
	_check(Path.max_level() == 15, "15 niveles en la ruta")
	for l in Path.levels():
		var lesson: Dictionary = l.get("lesson", {})
		if lesson.get("title", "") == "" or lesson.get("body", []).is_empty() or l.get("challenge", {}).is_empty():
			_check(false, "nivel %d completo" % int(l["level"]))
	var stats := Path.levels().map(func(l): return str(l["challenge"]["stat"]))
	_check(not stats.any(func(s): return s in ["silenced", "silences", "kills", "destroyed", "deleted", "escorts"]), "ningún reto de silenciar, borrar ni escoltar")

func _view() -> void:
	Account.profile = _profile(5, ["tutorial", "jugar_1", "recoger_2"], {"copia_1": 0})
	var v: Control = (load("res://scripts/menu/detective_path_view.gd") as GDScript).new()
	v.size = Vector2(1040, 600)
	add_child(v)
	v.show()
	await get_tree().process_frame
	v.refresh()
	await get_tree().process_frame
	_check(v.node_buttons.size() == 15, "15 nodos en el camino")
	_check(v.level_label.text == "Nv. 5", "nivel en la cabecera de la ruta")
	_check(v.selected == 5, "se abre en tu nivel")
	_check(Path.state_of(1, 5, Account.profile) == Path.DONE and Path.state_of(4, 5, Account.profile) == Path.REACHED, "hecho y alcanzado con reto pendiente")
	_check(Path.state_of(5, 5, Account.profile) == Path.CURRENT and Path.state_of(6, 5, Account.profile) == Path.LOCKED, "actual y bloqueado")
	var a: Vector2 = v.node_center(1)
	var b: Vector2 = v.node_center(6)
	_check(a.y < b.y and v.node_center(5).x > a.x, "zigzag: 5 por fila")
	v.node_buttons[4].pressed.emit()
	await get_tree().process_frame
	var card: Control = v.lesson_card()
	_check(card != null and (card.find_child("LessonTitle", true, false) as Label).text == "Copias de seguridad", "pulsar el nodo 4 abre su lección")
	_check(card.find_child("LessonArt", true, false) != null and card.find_child("LessonBody", true, false) != null, "lección ilustrada con explicación")
	_check(card.find_child("LessonControls", true, false) != null, "con controles")
	var status := (card.find_child("ChallengeStatus", true, false) as Label).text
	_check("0 de 1" in status, "reto acumulado en curso (%s)" % status)
	_check(Account.is_lesson_seen(4), "la lección queda vista (sin la marca NUEVA)")
	v.select_level(9)
	await get_tree().process_frame
	card = v.lesson_card()
	_check(card.find_child("LessonBody", true, false) == null, "lección bloqueada: sin explicación")
	_check("nivel 9" in (card.find_child("ChallengeStatus", true, false) as Label).text, "reto bloqueado hasta el nivel 9")
	v.select_level(3)
	await get_tree().process_frame
	_check("Cumplido" in (v.lesson_card().find_child("ChallengeStatus", true, false) as Label).text, "reto cumplido")
	v.select_level(1)
	await get_tree().process_frame
	var asked := [false]
	v.tutorial_requested.connect(func() -> void: asked[0] = true)
	var practice: Button = v.lesson_card().find_child("PracticeButton", true, false)
	_check(practice != null and "Repetir" in practice.text, "nivel 1: repetir la práctica")
	practice.pressed.emit()
	_check(asked[0], "el botón pide la práctica a MainMenu")
	v.select_level(10)
	await get_tree().process_frame
	_check(v.lesson_card().find_child("LevelReward", true, false) != null, "nivel 10: recompensa cosmética visible")
	# Al subir de nivel la ruta vuelve a tu nivel (si no has elegido otro).
	Account.profile = _profile(6, ["tutorial", "jugar_1", "recoger_2"])
	v.refresh()
	_check(v.selected == 6, "tras subir, se abre el nivel nuevo")
	v.queue_free()

func _popup() -> void:
	var p: Control = load("res://scripts/menu/LevelUpPopup.gd").show_for(self, {"source": "match", "xp": 570, "matchXp": 420, "coins": 100, "levelsGained": 1, "levelBefore": 3, "level": 4,
		"challenges": [{"id": "recoger_2", "text": "Recoge 2 pruebas en una misma partida", "level": 3, "xp": 150, "coins": 0}], "levelRewards": [{"level": 4, "coins": 50}]})
	_check((p.find_child("BigLevel", true, false) as Label).text == "NIVEL 4", "celebración: nivel nuevo")
	_check((p.find_child("Ribbon", true, false) as Label).text == "¡SUBES DE NIVEL!", "cinta de subida")
	var rows: Node = p.find_child("Rows", true, false)
	_check(rows.get_child_count() == 4, "partida, reto, recompensa de nivel y monedas (%d filas)" % rows.get_child_count())
	_check(p.find_child("Unlocked", true, false) != null, "anuncia la lección desbloqueada")
	var got := [0]
	p.lesson_requested.connect(func(l: int) -> void: got[0] = l)
	(p.find_child("LessonButton", true, false) as Button).pressed.emit()
	_check(got[0] == 4 and p.is_queued_for_deletion(), "«Ver la lección» lleva al nivel 4 y cierra")

func _account() -> void:
	var net := FakeNetwork.new()
	add_child(net)
	Account.net = net
	Account.online = true
	Account.profile = _profile(1, [])
	Account.tutorial_reward_pending = true
	_check(Account.flush_tutorial_reward() > 0 and net.sent[-1]["t"] == Protocol.I_CLAIM_TUTORIAL, "conectado: pide la XP de la práctica")
	var seq: int = net.sent[-1]["seq"]
	Account._on_message({"t": Protocol.M_REJECTED, "seq": seq, "reason": "already_claimed"})
	_check(not Account.tutorial_reward_pending, "ya reclamada: deja de estar pendiente sin avisar")
	Account.tutorial_reward_pending = true
	Account._on_message({"t": Protocol.M_PROFILE, "profile": _profile(2, ["tutorial"])})
	_check(not Account.tutorial_reward_pending, "un perfil con la práctica hecha limpia lo pendiente")
	Account.pending_celebration = {}
	Account._on_message({"t": Protocol.M_REWARDS, "rewards": {"source": "match", "xp": 120, "coins": 40, "levelsGained": 0, "challenges": []}})
	_check(Account.pending_celebration.is_empty(), "partida sin subida ni retos: sin celebración")
	Account._on_message({"t": Protocol.M_REWARDS, "rewards": {"source": "match", "xp": 420, "coins": 40, "levelsGained": 1, "level": 3, "challenges": []}})
	_check(Account.take_celebration().get("level") == 3 and Account.pending_celebration.is_empty(), "subida: celebración pendiente hasta volver al menú")

func _hints() -> void:
	var h: CanvasLayer = (load("res://scripts/ui/MatchHints.gd") as GDScript).new()
	add_child(h)
	Network.player_id = "me"
	Account.hints_enabled = true
	Account.profile = _profile(2, ["tutorial"])
	GameState._replace({"version": 1, "phase": "investigation", "lobby": {"code": "ABCDEF"}, "players": [{"id": "me", "name": "Ana", "position": {"x": 0, "y": 0}}],
		"you": {"roleId": "ROLE_CEO", "inventory": []}, "bodies": [], "trial": {}, "interactables": []})
	_check(h.enabled(), "consejos activos por debajo del nivel %d" % Path.hint_max_level())
	_check(h.hint("explore") and not h.hint("explore"), "cada consejo una vez por partida")
	h._process(0.1)
	_check(h.panel.visible and h.label.text == h.HINTS["explore"], "se muestra el consejo")
	_check(not h.HINTS.values().any(func(t): return "CEO" in t or "culpable" in t.to_lower() or "silenciar a" in t.to_lower()), "los consejos no hablan de roles ni invitan a silenciar")
	GameState.snapshot["bodies"] = [{"id": "body:x", "playerId": "x", "position": {"x": 100, "y": 0}, "reported": false}]
	h._scan_bodies()
	_check(h.shown.has("body"), "cuerpo cerca: consejo de reportar")
	Account.profile = _profile(Path.hint_max_level(), ["tutorial"])
	_check(not h.enabled(), "desde el nivel %d ya no salen" % Path.hint_max_level())
	Account.profile = _profile(2, ["tutorial"])
	Account.hints_enabled = false
	_check(not h.enabled(), "desactivados en Configuración")
	Account.hints_enabled = true
	Network.local_server = self
	_check(not h.enabled(), "en la práctica local no salen")
	Network.local_server = null
	GameState.reset()
	_check(h.shown.is_empty() and not h.panel.visible, "al salir de la sala se reinician")
	h.queue_free()

func _check(ok: bool, text: String) -> void:
	print("  ", "ok  " if ok else "FAIL", " ", text)
	if not ok:
		_failures += 1

func _finish() -> void:
	Account.profile = _saved["profile"]
	Account.hints_enabled = _saved["hints"]
	Account.tutorial_reward_pending = _saved["pending"]
	Account.seen_lessons = _saved["seen"]
	Account.net = _saved["net"]
	Account.online = _saved["online"]
	Account._save()
	print("DetectivePathTest: ", "OK" if _failures == 0 else "%d fallos" % _failures)
	get_tree().quit(1 if _failures > 0 else 0)
