extends Node
## Prueba sin servidor: godot --headless res://tests/FloatingProgressBarTest.tscn

var _failures := 0

func _ready() -> void:
	var player := Node2D.new()
	add_child(player)

	# 1. Modo local: se llena y emite completed.
	var done := []
	var bar := FloatingProgressBar.attach(player, "Tomando foto...", 0.3)
	bar.completed.connect(func(): done.append(true))
	_check(bar.get_parent() == player and bar.position.y < 0, "aparece sobre el personaje")
	_check(bar.label.text == "Tomando foto...", "muestra el nombre de la acción")
	_check(bar.layer.follow_viewport_enabled and bar.anchor.get_parent() == bar.layer, "se dibuja en un CanvasLayer que sigue a la cámara")
	_check(bar.bar_color() == Color("#00e5ff") and not bar.is_hostile, "respaldo pacífico en cian #00e5ff")
	player.scale = Vector2(-1, 1)
	await get_tree().process_frame
	_check(bar.anchor.get_global_transform().get_scale() == Vector2.ONE, "no se voltea con el personaje")
	_check(absf(bar.anchor.position.x + bar.anchor.size.x / 2.0 - player.global_position.x) < 1.0, "sigue centrada sobre el personaje")
	player.scale = Vector2.ONE
	await get_tree().create_timer(0.15).timeout
	_check(bar.progress() > 0.2 and bar.progress() < 1.0, "se llena en tiempo real")
	await get_tree().create_timer(0.3).timeout
	_check(done == [true], "emite completed al terminar")

	# 2. Moverse antes de tiempo la interrumpe.
	var reasons := []
	var bar2 := FloatingProgressBar.attach(player, "Borrando logs...", 5.0, 0.0, "delete")
	_check(bar2.bar_color() == Color("#ff334b") and bar2.is_hostile, "acción hostil en rojo #ff334b")
	bar2.watch_movement = true
	bar2.interrupted.connect(func(r): reasons.append(r))
	await get_tree().process_frame
	player.position += Vector2(40, 0)
	await get_tree().process_frame
	_check(reasons == ["moved"] and bar2.finished, "emite interrupted si el jugador se mueve")

	# 3. Modo servidor: retoma lo ya transcurrido, espera la confirmación.
	var server_done := []
	var bar3 := FloatingProgressBar.attach(player, "Purgando...", 0.2, 0.1)
	bar3.auto_complete = false
	bar3.completed.connect(func(): server_done.append("ok"))
	bar3.interrupted.connect(func(r): server_done.append(r))
	_check(is_equal_approx(bar3.progress(), 0.5), "un jugador que llega tarde la ve a mitad")
	await get_tree().create_timer(0.3).timeout
	_check(server_done.is_empty() and not bar3.finished, "llena y espera al servidor")
	bar3.server_finished(true, "")
	_check(server_done == ["ok"], "el servidor la completa")

	var bar4 := FloatingProgressBar.attach(player, "Triturando...", 1.0)
	bar4.auto_complete = false
	var fail := []
	bar4.interrupted.connect(func(r): fail.append(r))
	bar4.server_finished(false, "target_gone")
	_check(fail == ["target_gone"], "el servidor la interrumpe con su motivo")

	# 5. Teclas de movimiento durante tu canalización: cancela y avisa al servidor.
	const FakeNetwork := preload("res://tests/FakeNetwork.gd")
	Network.player_id = "me"
	var net := FakeNetwork.new()
	add_child(net)
	var ev := EvidenceSystem.new()
	ev.network = net
	add_child(ev)
	var presenter := ChannelPresenter.new()
	presenter.evidence_system = ev
	add_child(presenter)
	var mine := FloatingProgressBar.attach(player, "Purgando...", 10.0, 0.0, "delete")
	mine.auto_complete = false
	mine.interrupted.connect(presenter._on_local_interrupted)
	presenter._bars["me"] = {"bar": mine, "startedAt": 0}
	var key := InputEventAction.new()
	key.action = "ui_left"
	key.pressed = true
	presenter._unhandled_input(key)
	_check(mine.finished and net.sent.size() > 0 and net.sent[-1]["t"] == "channel_cancel", "pulsar una tecla de movimiento cancela y notifica al servidor")

	print("FloatingProgressBarTest: ", "OK" if _failures == 0 else "%d fallos" % _failures)
	get_tree().quit(1 if _failures > 0 else 0)

func _check(cond: bool, label: String) -> void:
	if cond:
		print("  ok   ", label)
	else:
		_failures += 1
		print("  FAIL ", label)
