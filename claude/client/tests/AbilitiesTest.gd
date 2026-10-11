extends Node2D
## Prueba sin servidor: godot --headless res://tests/AbilitiesTest.tscn
## Diccionario de habilidades de los 12 animales, enfriamiento, señales para el HUD y
## el botón de la habilidad.

var _failures := 0
var _now := 1_000_000.0
var _sent: Array = []
var _signals := {}

class FakeNet extends Node:
	var sent: Array = []
	var seq := 0
	func send_intent(type: String, payload: Dictionary = {}) -> int:
		seq += 1
		sent.append({"t": type, "seq": seq, "payload": payload})
		return seq

func _snap(phase: String, skin: String, ability: Dictionary, speed := 1.0) -> Dictionary:
	var you := {"roleId": "ROLE_CEO", "inventory": [], "knownTeammates": [], "objectives": [], "speedMultiplier": speed}
	if not ability.is_empty():
		you["ability"] = ability
	return {"version": 1, "phase": phase, "interactables": [{"id": "cajon", "type": "evidence_spot", "position": {"x": 50, "y": 60}, "radius": 40, "contents": []}],
		"players": [{"id": "me", "name": "Ana", "skinId": skin, "position": {"x": 0, "y": 0}},
			{"id": "p2", "name": "Beto", "skinId": "leon", "position": {"x": 90, "y": 0}}],
		"you": you}

func _record(name: String) -> Callable:
	return func(a = null, b = null, c = null) -> void:
		_signals[name] = [a, b, c]

func _ready() -> void:
	Network.player_id = "me"
	var net := FakeNet.new()
	add_child(net)
	Abilities.net = net
	Abilities.clock = func() -> float: return _now
	for s in ["ability_changed", "cooldown_changed", "ability_ready", "ability_activated", "ability_ended", "ability_failed", "scent_marked", "ability_seen"]:
		Abilities.connect(s, _record(s))

	# 1. Diccionario: los 12 animales, con pasiva y activa basadas en rasgos reales.
	var animals := AnimalAbilities.animals()
	animals.sort()
	var skins := SkinCatalog.ids().duplicate()
	skins.sort()
	_check(animals == skins and animals.size() == 12, "los 12 animales del catálogo tienen habilidades")
	var complete := true
	for a in animals:
		var p := AnimalAbilities.passive_of(a)
		var act := AnimalAbilities.active_of(a)
		complete = complete and p.get("name", "") != "" and p.get("trait", "") != "" and act.get("name", "") != "" and float(act.get("cooldown", 0)) > 0.0
	_check(complete, "cada uno con pasiva y activa (nombre, rasgo real y enfriamiento)")
	_check(AnimalAbilities.active_of("leon")["id"] == "rugido" and AnimalAbilities.passive_effect("buho", "flashlight") == 1.35, "rugido del león y visión nocturna del búho")
	_check(not JSON.stringify(AnimalAbilities.all()).contains("ROLE_"), "ninguna habilidad nombra roles")
	_check(AnimalAbilities.timing_text(AnimalAbilities.active_of("oso")) == "Cada 35 s · dura 2,5 s", "texto de enfriamiento y duración")

	# 2. En el lobby no se puede.
	GameState._replace(_snap("lobby", "conejo", {}))
	_check(Abilities.skin_id == "conejo" and _signals.has("ability_changed"), "ability_changed al conocer tu animal")
	_check(Abilities.use() == -1 and _signals["ability_failed"][0] == "wrong_phase", "fuera de la investigación avisa y no envía nada")

	# 3. Investigación: lista, se usa, el servidor la confirma y empieza el enfriamiento.
	GameState._replace(_snap("investigation", "conejo", {"id": "salto", "readyAt": 0, "activeUntil": null, "cooldownMs": 18000}, 1.0))
	_check(Abilities.can_use() and Abilities.cooldown_left() == 0.0, "lista al empezar la investigación")
	var seq := Abilities.use()
	_check(seq > 0 and net.sent.back()["t"] == Protocol.I_USE_ABILITY, "use() envía use_ability al servidor")
	EventBus.ability_used.emit("me", "salto", int(_now + 1200), [], [])
	_check(_signals.has("ability_activated") and is_equal_approx(_signals["ability_activated"][1], 1.2), "ability_activated con la duración (1,2 s)")
	_check(is_equal_approx(Abilities.cooldown_left(), 18.0), "enfriamiento de 18 s")
	GameState._replace(_snap("investigation", "conejo", {"id": "salto", "readyAt": _now + 18000, "activeUntil": _now + 1200, "cooldownMs": 18000}, 1.9))
	_check(Abilities.speed_multiplier() == 1.9, "la velocidad del salto llega del servidor (Player la usa)")
	_check(Abilities.use() == -1 and _signals["ability_failed"][0] == "on_cooldown", "durante el enfriamiento no se puede")
	await get_tree().process_frame   # process_frame llega antes de los _process: un frame más
	await get_tree().process_frame
	_check(_signals.has("cooldown_changed") and is_equal_approx(_signals["cooldown_changed"][1], 18.0), "cooldown_changed para el HUD")
	_now += 2000
	await get_tree().process_frame
	_check(_signals.has("ability_ended"), "ability_ended al acabar el efecto")
	_now += 16_100
	await get_tree().process_frame
	_check(_signals.has("ability_ready") and Abilities.can_use(), "ability_ready al terminar el enfriamiento")
	# Rechazo del servidor → aviso con el motivo.
	seq = Abilities.use()
	Abilities._on_message({"t": Protocol.M_REJECTED, "seq": seq, "reason": "not_alive"})
	_check(_signals["ability_failed"][1] == AnimalAbilities.ERRORS["not_alive"], "un rechazo del servidor llega como ability_failed con texto")

	# 4. Olfato (marcas solo tuyas) y habilidades de otros.
	GameState._replace(_snap("investigation", "perro", {"id": "olfato", "readyAt": 0, "activeUntil": null, "cooldownMs": 40000}))
	var markers := ScentMarkers.new()
	add_child(markers)
	EventBus.ability_used.emit("me", "olfato", int(_now + 6000), ["cajon"], [])
	_check(_signals.has("scent_marked") and _signals["scent_marked"][0] == ["cajon"] and markers.marked_count() == 1, "olfato: marca los escondites en el mapa")
	EventBus.ability_used.emit("p2", "rugido", -1, [], ["me"])
	_check(_signals["ability_seen"] == ["p2", "rugido", true], "ability_seen: Beto rugió y te alcanzó")

	# 5. Botón del HUD.
	var hud_button := AbilityButton.new()
	add_child(hud_button)
	_check(hud_button.visible and hud_button.name_label.text == "Olfato" and hud_button.passive_label.text == "Pasiva: Trote", "el botón muestra la activa y la pasiva de tu animal")
	EventBus.ability_used.emit("p2", "rugido", -1, [], [])
	_check(hud_button.notice.text == "Beto usó Rugido", "aviso cuando otro usa una habilidad pública")
	hud_button.button.pressed.emit()
	_check(net.sent.back()["t"] == Protocol.I_USE_ABILITY, "pulsar el botón (o la tecla Q) usa la habilidad")
	_check(InputMap.has_action(AnimalAbilities.ACTION), "acción de teclado use_ability definida")
	GameState._replace(_snap("investigation", "buho", {"id": "vuelo_silencioso", "readyAt": 0, "activeUntil": null, "cooldownMs": 45000}))
	_check(Abilities.flashlight_multiplier() == 1.35 and hud_button.name_label.text == "Vuelo silencioso", "al cambiar de animal cambian el botón y la linterna")

	print("AbilitiesTest: ", "OK" if _failures == 0 else "%d fallos" % _failures)
	get_tree().quit(1 if _failures > 0 else 0)

func _check(cond: bool, label: String) -> void:
	if cond:
		print("  ok   ", label)
	else:
		_failures += 1
		print("  FAIL ", label)
