extends Node
## Prueba sin servidor: godot --headless res://tests/ScenarioTest.tscn
## Sale con código 0 si todo pasa, 1 si algo falla.

var _failures := 0

func _ready() -> void:
	_test_example_scenario()
	_test_errors_are_collected()
	_test_legacy_case()
	print("ScenarioTest: ", "OK" if _failures == 0 else "%d fallos" % _failures)
	get_tree().quit(1 if _failures > 0 else 0)

func _test_example_scenario() -> void:
	var rm := RoleManager.new()
	add_child(rm)
	var root := Node2D.new()
	add_child(root)
	var sm := ScenarioManager.new()
	sm.role_manager = rm
	sm.spawn_root = root
	add_child(sm)

	_check(sm.load_scenario("nexuscore_fraude"), "carga el escenario de ejemplo")
	_check(sm.current.roles.size() == 5, "5 roles")
	_check(rm.all_roles().size() == 5, "RoleManager recibe los roles")
	_check(root.get_child_count() == 5, "5 pistas instanciadas")
	var logs := sm.get_spawned("CLUE_SERVER_LOGS")
	_check(logs != null and logs.interactable_id == "spawn_CLUE_SERVER_LOGS", "id igual al del servidor")
	_check(logs.position == Vector2(200, 150), "posición {x,y}")
	_check(sm.get_spawned("CLUE_UNLOCKED_LAPTOP").position == Vector2(640, 120), "posición [x,y]")
	_check(sm.current.get_spawn("CLUE_SERVER_LOGS").type == EvidenceSpawnData.Type.TEXT, "tipo text")
	_check(sm.current.spawns_affecting("ROLE_CEO", -1).size() == 5, "todo perjudica al CEO")
	_check(sm.secret_objectives_for("ROLE_CTO")[0]["type"] == "narrative", "objetivo en texto = narrative")

	rm.local_role = rm.get_role("ROLE_CTO")
	rm.local_stats = rm.modifiers.compute_stats(rm.local_role)
	var tags := sm.current.get_spawn("CLUE_SERVER_LOGS").all_tags()
	_check(rm.predicted_visibility(tags) == "full", "el CTO ve completa la pista que le beneficia")
	rm.local_role = rm.get_role("ROLE_LEAKER")
	_check(rm.predicted_visibility(tags) == "partial", "el Filtrador la ve parcial")

func _test_errors_are_collected() -> void:
	var res := ScenarioParser.parse({
		"scenario_id": "x", "title": "X",
		"roles": [{"id": "A", "name": "A", "secret_objectives": []}],
		"evidence_spawns": [
			{"id": "e1", "name": "E", "type": "video", "position": {"x": 0, "y": 0}, "benefits": ["B"]},
			{"id": "e1", "name": "E", "type": "item", "position": "aquí"},
		],
	})
	_check(not res.ok(), "escenario inválido rechazado")
	_check(res.errors.size() == 4, "4 errores a la vez (hay %d: %s)" % [res.errors.size(), res.errors])

## El caso original en formato libre se carga sin tocarlo (mismas expectativas que server/test/trial.test.ts).
func _test_legacy_case() -> void:
	var res := ScenarioParser.parse(ScenarioSource.FileSource.new().load_raw("caso_fraude_tech_startup"))
	_check(res != null and res.ok(), "carga el caso en formato libre %s" % [res.errors if res else "(error de script)"])
	if res == null or not res.ok():
		return
	var d := res.data
	_check(d.scenario_id == "case_002_tech_fraud", "scenario_id derivado de case_id")
	_check(d.player_count["max"] == 4, "player_count ajustado a los roles que hay")
	var logs := d.get_spawn("CLUE_SERVER_LOGS")
	_check(logs.position == Vector2(200, 150) and not logs.pocketable, "logs: sala → posición y no transportables")
	_check("ROLE_CTO" in logs.benefits and "ROLE_CEO" in logs.harms, "beneficia/perjudica desde backup/deletion")
	var types := ["CLUE_SERVER_LOGS", "CLUE_UNLOCKED_LAPTOP", "CLUE_TORN_CONTRACT", "CLUE_ENCRYPTED_PENDRIVE"].map(func(id): return d.get_spawn(id).type_name)
	_check(types == ["text", "photo", "item", "item"], "tipo libre → text/photo/item (%s)" % [types])
	_check(d.get_role("ROLE_CEO").team == "culpable", "equipo desde alignment")

func _check(cond: bool, label: String) -> void:
	if cond:
		print("  ok   ", label)
	else:
		_failures += 1
		print("  FAIL ", label)
