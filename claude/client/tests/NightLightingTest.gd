extends Node
## Prueba sin servidor: godot --headless res://tests/NightLightingTest.tscn
## La noche de auditoría ahora la pinta la vista 3D (World3DView).

var _failures := 0

func _ready() -> void:
	var main: Node = load("res://scenes/main/Main.tscn").instantiate()
	main.scenario_id = "caso_fraude_tech_startup"
	add_child(main)
	await get_tree().process_frame
	var view: World3DView = main.get_node("World3D")
	_check(view.layer < 0, "la vista 3D va detrás del juego 2D")
	_check(view.office != null and view.office.get_child_count() > 50, "la oficina 3D está construida")
	var env: Environment = view.viewport.get_node("WorldEnvironment").environment
	_check(env.background_color.get_luminance() < 0.1, "ambiente nocturno")
	view._sync_evidence()   # fuera de la exploración la vista no se actualiza sola
	_check(view._markers.size() == main.get_node("Map/Evidence").get_child_count(), "cada pista tiene su aro y su luz en 3D")
	var p: PlayerAvatar = load("res://scenes/player/PlayerAvatar.tscn").instantiate()
	p.is_local = true
	main.get_node("Map/Players").add_child(p)
	await get_tree().process_frame
	view._sync_avatars(0.016)
	_check(view.actors.get_children().any(func(n): return n is PlushAvatar3D), "los jugadores que entran tienen su personaje 3D")
	_check(view._local_light.visible, "el jugador local lleva linterna")
	var modal: CanvasLayer = main.get_node("UI/EvidenceInspectionModal")
	_check(modal.layer > 0, "el modal vive en su propia capa")

	print("NightLightingTest: ", "OK" if _failures == 0 else "%d fallos" % _failures)
	get_tree().quit(1 if _failures > 0 else 0)

func _check(cond: bool, label: String) -> void:
	if cond:
		print("  ok   ", label)
	else:
		_failures += 1
		print("  FAIL ", label)
