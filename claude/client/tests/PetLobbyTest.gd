extends Control
## Mascota en la sala de espera: la barra (hambre, hidratación, comida de su especie),
## tocar y acariciar a tu animal (con clics de verdad por la GUI), sus reacciones y
## sonidos, comer, beber, "ya estoy lleno" y el bocadillo cuando tiene hambre o sed.

const SAVE := "user://pet_lobby_test.cfg"
var _failed := 0
var _gestures: Array = []
var _toasts: Array = []

func _ready() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	get_tree().root.size = Vector2i(1280, 720)   # sin ventana (--headless) mide 64×64
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var view: LobbyView = load("res://scenes/menu/LobbyView.tscn").instantiate()
	view.pet.save_path = SAVE
	add_child(view)
	view.toast_requested.connect(func(t: String) -> void: _toasts.append(t))
	view.stage.pet_touched.connect(func(g: String, skin: String) -> void: _gestures.append([g, skin]))
	await _frames(4)
	var stage := view.stage
	var seat := stage.local_seat()
	_check(seat != null, "tu animal está en la sala")
	if seat == null:
		_finish()
		return
	var skin := seat.chibi.skin_id
	var panel := view.pet_panel
	_check(panel != null and panel.is_visible_in_tree(), "la barra de la mascota está en la sala")
	_check(panel.title.text == str(SkinCatalog.skin(skin)["name"]), "con el nombre de tu animal (%s)" % panel.title.text)
	_check(panel.feed_label.text == str(PetCare.food(skin)["name"]), "y el botón de su comida: %s" % panel.feed_label.text)
	_check(not seat.chibi.bake, "tu mascota se dibuja en vivo (pone caras)")
	_check(not panel.get_global_rect().intersects(view.chat_lines.get_parent().get_parent().get_parent().get_global_rect()), "la barra no tapa el chat")
	_check(not panel.get_global_rect().intersects(view.start_button.get_global_rect()), "ni el botón grande")

	# Tocar.
	var center := stage.get_global_transform() * (seat.transform * Vector2(0, seat.chibi.top_y() * 0.5))
	_click(center)
	await _frames(2)
	_check(_gestures == [["tap", skin]], "un toque sobre tu animal cuenta como tocarlo (%s)" % str(_gestures))
	_check(seat.reaction == PetCare.tap_reaction(skin), "y reacciona a su manera: %s" % seat.reaction)
	_check(view.pet_sfx.last_played == skin + "_feliz", "con su sonido (%s)" % view.pet_sfx.last_played)
	await _seconds(0.35)
	_check(seat.chibi.transform != Transform2D.IDENTITY or not seat.chibi.emote.is_empty(), "se mueve o pone cara")
	await _seconds(PetReactions.duration(seat.reaction) + 0.2)
	_check(seat.reaction == "" and seat.chibi.transform.is_equal_approx(Transform2D.IDENTITY), "y vuelve a su sitio")

	# Acariciar (arrastrar por encima).
	_gestures.clear()
	_press(center + Vector2(-30, 0), true)
	for i in 8:
		_move(center + Vector2(-30 + i * 9, 0), Vector2(9, 0) * 2.0)
	_press(center + Vector2(40, 0), false)
	await _frames(2)
	_check(_gestures.size() == 1 and _gestures[0] == ["stroke", skin], "arrastrar por encima es una caricia (%s)" % str(_gestures))
	_check(seat.reaction == "cuddle", "se arrima con gusto")
	_check(view.pet_sfx.last_played == skin + "_caricia", "y suena su caricia (%s)" % view.pet_sfx.last_played)
	await _seconds(0.3)
	_check(float(seat.chibi.pose_state()["smile"]) > 0.5, "cierra los ojos de gusto")
	_check(seat.get_children().any(func(c): return c.get_class() == "Node2D" and c.get_script() != null and c != seat.chibi and c.name.begins_with("@")), "salen corazones")
	await _seconds(1.3)

	# Tocar fuera no hace nada.
	_gestures.clear()
	_click(stage.get_global_transform() * (seat.transform * Vector2(-90, -20)))
	await _frames(2)
	_check(_gestures.is_empty(), "tocar el suelo no cuenta")

	# Comer y beber.
	var before := view.pet.levels(skin)
	var feed_center := view.pet_panel.feed_button.get_global_rect().get_center()
	_click(feed_center)
	await _frames(2)
	var after := view.pet.levels(skin)
	_check(before["hunger"] < 90.0 and (after["hunger"] > before["hunger"] + 30.0 or after["hunger"] >= 99.9), "el botón de comida lo alimenta (%.0f → %.0f)" % [before["hunger"], after["hunger"]])
	_check(seat.reaction == "eat" and view.pet_sfx.last_played == "comer", "come con su animación y sonido")
	_check(absf(panel.hunger_bar.value - after["hunger"] / 100.0) < 0.02, "la barra de Hambre se llena (%d %%)" % roundi(after["hunger"]))
	for i in 3:
		view.feed_pet()
	_check(seat.reaction == "refuse" and view.pet_sfx.last_played == "lleno", "lleno: niega con la cabeza")
	_check(_toasts.any(func(t): return "lleno" in t), "y lo dice (%s)" % str(_toasts.back() if not _toasts.is_empty() else ""))
	before = view.pet.levels(skin)
	_click(view.pet_panel.drink_button.get_global_rect().get_center())
	await _frames(2)
	after = view.pet.levels(skin)
	_check(after["hydration"] > before["hydration"] + 30.0 or after["hydration"] >= 99.9, "el agua lo hidrata (%.0f → %.0f)" % [before["hydration"], after["hydration"]])
	_check(seat.reaction == "drink" and view.pet_sfx.last_played == "beber", "bebe con su animación y sonido")

	# Bocadillo de hambre.
	view.pet._state[skin] = {"hunger": 10.0, "hydration": 90.0, "t": PetCare.now_s()}
	await _seconds(PetReactions.duration("drink") + 0.1)
	view.refresh_pet()
	await _frames(1)
	_check(seat._need.visible and seat._need.icon == str(PetCare.food(skin)["icon"]), "con hambre piensa en su comida (%s)" % seat._need.icon)
	_check(panel.hunger_bar.low, "y la barra avisa en rojo")
	_finish()

func _finish() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	print("PetLobbyTest: ", "OK" if _failed == 0 else "%d FALLOS" % _failed)
	get_tree().quit(1 if _failed > 0 else 0)

func _click(pos: Vector2) -> void:
	_press(pos, true)
	_press(pos, false)

func _press(pos: Vector2, down: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	e.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
	e.position = pos
	e.global_position = pos
	get_viewport().push_input(e)

func _move(pos: Vector2, rel: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = pos
	e.global_position = pos
	e.relative = rel
	e.button_mask = MOUSE_BUTTON_MASK_LEFT
	get_viewport().push_input(e)

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func _seconds(s: float) -> void:
	await get_tree().create_timer(s).timeout

func _check(ok: bool, text: String) -> void:
	print("  ", "ok  " if ok else "FAIL", " ", text)
	if not ok:
		_failed += 1
