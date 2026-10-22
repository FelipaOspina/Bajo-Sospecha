extends Node
## Prueba sin servidor: godot --headless res://tests/ElevatorTest.tscn
## Ascensor de carga: al empezar la partida (lobby → briefing) aparece con un personaje
## por jugador (12 caben en pantalla), el tuyo con el aro neutro; el indicador cuenta
## PB → 14; llega antes de que acabe el briefing y devuelve la pantalla y el teclado al
## juego; si la partida empieza antes, llega enseguida; y nunca muestra nada del rol.

const Ride := preload("res://scripts/world3d/ElevatorRide.gd")
const SKINS := ["pinguino", "zorro", "gato", "panda", "leon", "conejo", "oso", "perro", "lobo", "tigre", "mapache", "buho"]
const NAMES := ["Felipe", "Ana", "Beto", "Carla", "Dani", "Eva", "Fede", "Gala", "Hugo", "Irene", "Javi", "Lola"]

var _failures := 0
var main: Node
var ride: Node
var view: World3DView
var _modal: Array = []

func _ready() -> void:
	get_tree().root.size = Vector2i(1280, 720)   # sin ventana (--headless) mide 64×64
	Network.player_id = "p0"
	EventBus.ui_modal_changed.connect(func(open: bool) -> void: _modal.append(open))
	main = load("res://scenes/main/Main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	ride = main.get_node_or_null("ElevatorRide")
	view = main.get_node("World3D")
	_check(ride != null and ride.get_script() == Ride, "Main tiene el ascensor (cargado por ruta)")
	if ride == null:
		_finish()
		return
	_check(not ride.is_active() and not ride.visible, "en el menú no se ve")
	await _full_ride()
	await _second_match_same_layout()
	await _hurry()
	await _short_or_late()
	_layouts()
	_finish()

func _finish() -> void:
	print("ElevatorTest: ", "OK" if _failures == 0 else "%d fallos" % _failures)
	get_tree().quit(1 if _failures > 0 else 0)

func _check(cond: bool, label: String) -> void:
	if cond:
		print("  ok   ", label)
	else:
		_failures += 1
		print("  FAIL ", label)

# ───────────── Estado falso ─────────────

func _now() -> float:
	return Network.server_time_ms()

func _players(n: int) -> Array:
	var out := []
	for i in n:
		out.append({"id": "p%d" % i, "name": NAMES[i], "skinId": SKINS[i], "position": {"x": 900 + i * 40, "y": 700},
			"connected": true, "ready": true, "alive": true, "inventoryCount": 0})
	return out

func _snap(phase: String, n: int, role_id := "", ends = null) -> Dictionary:
	var you := {}
	if role_id != "":
		you = {"roleId": role_id, "team": _role_team(role_id), "objectives": [], "inventory": [], "knownTeammates": [], "ghost": false}
	return {"version": 1, "phase": phase, "phaseEndsAt": ends,
		"lobby": {"code": "ELEV14", "visibility": "private", "hostId": "p0", "minPlayers": 4, "maxPlayers": 12, "startsAt": null},
		"players": _players(n), "interactables": [], "you": you if role_id != "" else null, "bodies": [], "emergency": null,
		"trial": {"deck": [], "options": [], "voted": [], "myVote": null, "maxPresentedPerPlayer": 1, "resolution": null}}

func _roles() -> Array:
	return main.get_node("RoleManager").all_roles()

func _role_team(id: String) -> String:
	var r = main.get_node("RoleManager").get_role(id)
	return r.team if r else "?"

func _frames(n := 2) -> void:
	for i in n:
		await get_tree().process_frame

## Espera a que termine (o a que pasen max_s segundos).
func _wait_finish(max_s: float) -> float:
	var t0 := Time.get_ticks_msec()
	while ride.is_active() and (Time.get_ticks_msec() - t0) < max_s * 1000.0:
		await get_tree().process_frame
	return (Time.get_ticks_msec() - t0) / 1000.0

## Lo que muestra el ascensor no puede mencionar ningún rol ni equipo.
func _no_role_text(where: String) -> void:
	var texts: Array = ride.visible_texts()
	var bad := []
	for r in _roles():
		for word in [r.id, r.display_name, r.team]:
			var w := str(word).strip_edges().to_lower()
			if w.length() < 3:
				continue
			for t in texts:
				if str(t).to_lower().contains(w):
					bad.append("%s ⊂ %s" % [w, t])
	for t in texts:
		var low := str(t).to_lower()
		if low.contains("rol") or low.contains("culpable") or low.contains("inocente") or low.contains("asesin"):
			bad.append(t)
	_check(bad.is_empty() and texts.size() > 0, "%s: ningún texto habla del rol (%d textos) %s" % [where, texts.size(), str(bad)])

# ───────────── 1. Viaje completo ─────────────

func _full_ride() -> void:
	var roles := _roles()
	_check(roles.size() >= 2, "hay roles en el caso para comprobar que no se filtran (%d)" % roles.size())
	GameState._replace(_snap("lobby", 12))
	await _frames(3)
	_check(not ride.is_active(), "en la sala de espera no aparece")
	_modal.clear()
	var briefing_ms := 6500.0
	var ends := _now() + briefing_ms
	GameState._replace(_snap("briefing", 12, roles[0].id, ends))
	await _frames(1)
	_check(ride.is_active() and ride.visible, "al empezar la partida aparece el ascensor")
	_check(ride.avatar_count() == 12, "un personaje por jugador: %d de 12" % ride.avatar_count())
	_check(ride.avatar_ids() == _players(12).map(func(p): return p["id"]), "en el orden de llegada a la sala")
	_check(ride.local_avatar_id() == "p0", "el tuyo lleva el aro (%s)" % ride.local_avatar_id())
	var all_hero := true
	for id in ride.avatar_ids():
		var m = ride.avatar_model(id)
		all_hero = all_hero and m is PlushAvatar3D and m.skin_id == SKINS[int(id.substr(1))]
	_check(all_hero, "cada uno es su personaje 3D con su skin")
	_check(ride.floors_seen.size() >= 1 and ride.floors_seen[0] == "PB", "el indicador empieza en PB (%s)" % str(ride.floors_seen))
	_check(_modal == [true], "el teclado del jugador queda en pausa mientras sube (%s)" % str(_modal))
	_check(view.covered, "la vista 3D del mapa no se dibuja debajo")
	var timing: Dictionary = ride.timing()
	_check(timing["total"] <= briefing_ms / 1000.0 and timing["total"] >= Ride.MIN_TOTAL_S, "dura lo que el briefing, sin pasarse (%.2f s)" % timing["total"])
	_check(timing["ride"] >= 2.0, "el viaje en sí dura %.2f s" % timing["ride"])
	await _frames(4)
	# Los 12 caben en pantalla.
	var cam: Camera3D = ride.camera()
	var vs := Vector2(ride.viewport_3d().size)
	var inside := 0
	for id in ride.avatar_ids():
		var m: Node3D = ride.avatar_model(id)
		var feet := cam.unproject_position(m.global_position)
		var head := cam.unproject_position(m.global_position + Vector3(0, Ride.Hero3D.HEIGHT, 0))
		if Rect2(Vector2.ZERO, vs).has_point(feet) and Rect2(Vector2.ZERO, vs).has_point(head) and not cam.is_position_behind(m.global_position):
			inside += 1
	_check(inside == 12, "los 12 caben en el encuadre (%d)" % inside)
	_check(cam.position.z < Ride.FRONT_Z and cam.position.y < Ride.H, "la cámara está dentro de la cabina")
	_no_role_text("subiendo")
	await get_tree().create_timer(timing["ride"] * 0.5).timeout
	_check(ride.stage == "ride" and ride.floors_seen.size() > 3 and ride.floors_seen.size() < 15, "a medio viaje va por la planta %s" % ride.floor_text())
	var arrived := [false]
	ride.arrived.connect(func() -> void: arrived[0] = true, CONNECT_ONE_SHOT)
	var waited := await _wait_finish(12.0)
	var expected: Array[String] = ["PB"]
	for i in range(1, 15):
		expected.append(str(i))
	_check(arrived[0], "llega a la planta 14 (ding)")
	_check(ride.floors_seen == expected, "cuenta las plantas de una en una: %s" % str(ride.floors_seen))
	_check(not ride.is_active() and ride.handed_over and not ride.visible, "termina y devuelve la pantalla al juego")
	_check(_now() <= ends + 250.0, "antes de que empiece la investigación (%.0f ms de margen)" % (ends - _now()))
	_check(not view.covered, "la vista 3D del mapa vuelve a dibujarse")
	_check(_modal.size() >= 2 and _modal[-1] == false, "y el teclado vuelve al jugador (%s)" % str(_modal))
	_check(ride.viewport_3d().render_target_update_mode == SubViewport.UPDATE_DISABLED, "el ascensor deja de dibujarse")
	_check(ride.avatar_count() == 0, "y suelta sus personajes")
	GameState._replace(_snap("briefing", 12, roles[0].id, ends))
	await _frames(2)
	_check(not ride.is_active(), "no se repite en el mismo briefing")
	GameState._replace(_snap("investigation", 12, roles[0].id, _now() + 300000))
	await _frames(2)
	_check(not ride.is_active() and main.get_node("Map").visible, "la investigación sigue normal")
	print("  (viaje completo en %.2f s)" % waited)

# ───────────── 2. Otra partida con otro rol: mismo ascensor ─────────────

func _second_match_same_layout() -> void:
	var roles := _roles()
	GameState._replace(_snap("lobby", 12))
	await _frames(2)
	GameState._replace(_snap("briefing", 12, roles[0].id, _now() + 9000))
	await _frames(2)
	var first: Dictionary = ride.slot_positions()
	var texts_a: Array = ride.visible_texts()
	ride.arrive_now()
	await _wait_finish(3.0)
	GameState._replace(_snap("lobby", 12))
	await _frames(2)
	GameState._replace(_snap("briefing", 12, roles[-1].id, _now() + 9000))
	await _frames(2)
	_check(ride.is_active(), "la siguiente partida vuelve a subir en ascensor")
	var second: Dictionary = ride.slot_positions()
	var same := first.size() == 12 and second.size() == 12
	for id in first:
		same = same and second.has(id) and (first[id] as Vector3).is_equal_approx(second[id])
	_check(same, "con otro rol (%s → %s) todos quedan en el mismo sitio" % [roles[0].id, roles[-1].id])
	var texts_b: Array = ride.visible_texts()
	texts_a.sort()
	texts_b.sort()
	_check(texts_a == texts_b, "y se ven exactamente los mismos textos")
	_no_role_text("con otro rol")
	ride.arrive_now()
	await _wait_finish(3.0)

# ───────────── 3. La partida empieza antes: llega enseguida ─────────────

func _hurry() -> void:
	GameState._replace(_snap("lobby", 8))
	await _frames(2)
	_modal.clear()
	GameState._replace(_snap("briefing", 8, _roles()[0].id, _now() + 9000))
	await get_tree().create_timer(1.2).timeout
	_check(ride.is_active() and ride.avatar_count() == 8, "con 8 jugadores, 8 personajes")
	GameState._on_message({"t": "event", "version": 2, "event": {"e": "phase_changed", "phase": "investigation", "endsAt": int(_now() + 300000)}})
	await _frames(1)
	_check(ride.hurried and _modal.size() >= 2 and _modal[-1] == false, "si la investigación ya empezó, el teclado se suelta al momento (%s)" % str(_modal))
	var waited := await _wait_finish(4.0)
	_check(not ride.is_active() and waited <= OUTRO_FAST + 0.4, "y llega y abre las puertas sin hacer esperar (%.2f s)" % waited)
	_check(ride.floors_seen[-1] == "14", "el indicador acaba en 14 (%s)" % str(ride.floors_seen))
	_check(not view.covered, "la vista del mapa vuelve")

const OUTRO_FAST := Ride.OUTRO_S * Ride.HURRY_SCALE

# ───────────── 4. Briefing ya casi acabado (reconexión) ─────────────

func _short_or_late() -> void:
	GameState._replace(_snap("lobby", 4))
	await _frames(2)
	GameState._replace(_snap("briefing", 4, _roles()[0].id, _now() + 1500))
	await _frames(2)
	_check(not ride.is_active(), "si quedaba muy poco briefing no se muestra")
	GameState._replace(_snap("investigation", 4, _roles()[0].id, _now() + 300000))
	await _frames(1)
	GameState._replace(_snap("lobby", 4))
	await _frames(1)
	GameState._replace(_snap("briefing", 4, _roles()[0].id, _now() + 5000))
	await _frames(2)
	_check(ride.is_active() and ride.avatar_count() == 4, "con 4 jugadores, 4 personajes")
	_check(ride.timing()["total"] >= Ride.MIN_TOTAL_S and ride.timing()["total"] <= 5.0, "dura al menos %.1f s (%.2f s)" % [Ride.MIN_TOTAL_S, ride.timing()["total"]])
	GameState._replace(_snap("investigation", 4, _roles()[0].id, _now() + 300000))
	await _wait_finish(3.0)
	_check(not ride.is_active(), "y termina al empezar la investigación")

# ───────────── 5. Plazas ─────────────

func _layouts() -> void:
	var ok := true
	for n in range(1, 13):
		var slots: Array = Ride.layout(n)
		ok = ok and slots.size() == n
		for i in slots.size():
			var p: Vector3 = slots[i]
			ok = ok and absf(p.x) < Ride.W / 2.0 - 0.45 and p.z > Ride.BACK_Z + 0.3 and p.z < Ride.FRONT_Z - 1.0
			for j in range(i + 1, slots.size()):
				ok = ok and Vector2(p.x, p.z).distance_to(Vector2(slots[j].x, slots[j].z)) > 0.9
	_check(ok, "de 1 a 12 jugadores: todos dentro de la cabina y sin pisarse")
