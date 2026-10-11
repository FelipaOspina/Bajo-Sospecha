extends Node
## Prueba sin servidor: godot --headless res://tests/NightLightingTest.tscn

var _failures := 0

func _ready() -> void:
	var main: Node = load("res://scenes/main/Main.tscn").instantiate()
	main.scenario_id = "caso_fraude_tech_startup"
	add_child(main)
	await get_tree().process_frame
	var night: NightLighting = main.get_node("Map/NightLighting")
	var mod := night.get_node_or_null("NightModulate") as CanvasModulate
	_check(mod != null and mod.color.get_luminance() < 0.3, "el mapa tiene un CanvasModulate oscuro")
	var spots: Array = main.get_node("Map/Evidence").get_children()
	_check(spots.size() > 0 and spots.all(func(s): return s.get_node_or_null("NightLight") is PointLight2D), "cada pista lleva su luz ámbar")
	var p := Player.new()
	main.get_node("Map/Players").add_child(p)
	_check(p.get_node_or_null("NightLight") is PointLight2D, "los jugadores que entran llevan su luz")
	var modal: CanvasLayer = main.get_node("UI/EvidenceInspectionModal")
	_check(modal.layer > 0, "el modal vive en su propia capa y no se oscurece")

	print("NightLightingTest: ", "OK" if _failures == 0 else "%d fallos" % _failures)
	get_tree().quit(1 if _failures > 0 else 0)

func _check(cond: bool, label: String) -> void:
	if cond:
		print("  ok   ", label)
	else:
		_failures += 1
		print("  FAIL ", label)
