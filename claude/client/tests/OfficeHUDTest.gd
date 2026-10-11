extends Node2D
## Prueba sin servidor: godot --headless res://tests/OfficeHUDTest.tscn

var _failures := 0

func _snap(phase: String, objectives: Array, me_pos := Vector2(100, 100)) -> Dictionary:
	return {"version": 1, "phase": phase,
		"interactables": [
			{"id": "logs", "type": "item", "position": {"x": 400, "y": 100}, "radius": 30, "contents": [{"instanceId": "e1", "visibility": "partial"}]},
			{"id": "vacio", "type": "item", "position": {"x": 100, "y": 300}, "radius": 30, "contents": []}],
		"players": [{"id": "me", "name": "Ana", "skinId": "panda", "position": {"x": me_pos.x, "y": me_pos.y}},
			{"id": "p2", "name": "Beto", "skinId": "zorro", "position": {"x": 100, "y": 400}},
			{"id": "p3", "name": "Carla", "skinId": "oso", "position": {"x": 5000, "y": 100}}],
		"you": {"roleId": "ROLE_CEO", "inventory": [], "knownTeammates": [], "objectives": objectives}}

func _ready() -> void:
	Network.player_id = "me"
	var spawner := PlayerSpawner.new()
	add_child(spawner)
	var hud: OfficeHUD = load("res://scenes/ui/OfficeHUD.tscn").instantiate()
	hud.players = spawner
	add_child(hud)
	var objectives := [
		{"id": "o1", "description": "Purgar los logs del servidor", "completed": true},
		{"id": "o2", "description": "Culpar al CTO en la asamblea", "completed": false},
		{"id": "o3", "description": "Recuperar el contrato", "completed": false}]
	GameState._replace(_snap("investigation", objectives))
	await get_tree().process_frame

	# 1. Panel de tareas.
	var panel: PanelContainer = hud.get_node("TasksPanel")
	_check(panel.get_global_rect().position.x < 40 and panel.get_global_rect().position.y < 40, "panel de tareas arriba a la izquierda")
	_check(panel.get_theme_stylebox("panel") is StyleBoxFlat, "usa el panel de cristal del Theme global")
	_check(hud.title.text == "Tareas", "título Tareas")
	_check(hud.tasks().map(func(t): return t["state"]) == ["done", "active", "pending"], "estado de cada tarea: hecha, activa, pendiente")
	var dots: Array = hud.task_list.get_children().map(func(r): return (r.get_node("StatusDot").get_theme_stylebox("panel") as StyleBoxFlat).bg_color)
	_check(dots[1] == UiPalette.AMBER and dots[2] == Color("#E2E8F0"), "punto ámbar en la activa y blanco en las pendientes")
	_check(hud.tasks()[1]["text"] == "Culpar al CTO en la asamblea", "son tus objetivos secretos (solo te llegan a ti)")

	# 2. Minimapa.
	var minimap := hud.minimap
	var frame: Control = hud.get_node("MinimapFrame")
	_check(frame.get_global_rect().end.x > get_viewport().get_visible_rect().size.x - 40 and frame.get_global_rect().position.y < 40, "minimapa arriba a la derecha")
	var m := minimap.markers()
	_check(m["me"] == minimap.size / 2.0, "tú en el centro")
	_check(m["evidence"].size() == 1, "solo las pistas en las que ves algo")
	var beto: Dictionary = m["players"].filter(func(p): return p["id"] == "p2")[0]
	_check(beto["position"].y > m["me"].y and beto["color"] == Color(SkinCatalog.skin("zorro")["fur"]), "los demás en su posición, con el color de su animal")
	var carla: Dictionary = m["players"].filter(func(p): return p["id"] == "p3")[0]
	_check(absf(carla["position"].distance_to(m["me"]) - (minimap.radius() - 6.0)) < 0.5, "quien está lejos se pega al borde circular")
	spawner.get_player("p2").global_position = Vector2(100, 250)
	_check(minimap.markers()["players"].filter(func(p): return p["id"] == "p2")[0]["position"].y < beto["position"].y, "se actualiza en tiempo real")

	# 3. Solo en exploración.
	GameState._replace(_snap("voting", objectives))
	_check(not hud.visible, "se oculta en la asamblea")
	GameState._replace(_snap("investigation", []))
	_check(hud.visible and hud.task_list.get_child_count() == 1, "sin rol aún, avisa de que espera el reparto")

	print("OfficeHUDTest: ", "OK" if _failures == 0 else "%d fallos" % _failures)
	get_tree().quit(1 if _failures > 0 else 0)

func _check(cond: bool, label: String) -> void:
	if cond:
		print("  ok   ", label)
	else:
		_failures += 1
		print("  FAIL ", label)
