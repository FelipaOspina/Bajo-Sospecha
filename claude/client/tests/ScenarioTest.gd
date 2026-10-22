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
	_check(sm.current.roles.size() == 9, "9 roles")
	_check(rm.all_roles().size() == 9, "RoleManager recibe los roles")
	_check(root.get_child_count() == 16, "16 pistas instanciadas")
	_check(sm.current.player_count == {"min": 4, "max": 12}, "de 4 a 12 jugadores")
	var logs := sm.get_spawned("CLUE_SERVER_LOGS")
	_check(logs != null and logs.interactable_id == "spawn_CLUE_SERVER_LOGS", "id igual al del servidor")
	_check(logs.position == Vector2(460, 120), "posición {x,y}")
	_check(sm.get_spawned("CLUE_UNLOCKED_LAPTOP").position == Vector2(1080, 60), "posición [x,y]")
	_check(sm.current.get_spawn("CLUE_SERVER_LOGS").type == EvidenceSpawnData.Type.TEXT, "tipo text")
	_check(sm.current.spawns_affecting("ROLE_CEO", -1).size() == 16, "todo perjudica al CEO")
	_check_new_content(sm.current)
	var acc := rm.get_role("ROLE_ACCOMPLICE")
	_check(acc != null and acc.min_players == 6 and acc.powers == ["silence"] and acc.knows_teammates, "RoleDefinition: min_players/powers del Cómplice")
	_check(rm.get_role("ROLE_CEO").motive_targets == ["ROLE_LEAKER"], "RoleDefinition: motive_targets del CEO")
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
	_check(d.player_count == {"min": 4, "max": 12}, "player_count de 4 a 12 (plazas de rol: %s)" % [d.player_count])
	_check(d.roles.size() == 9, "9 roles en el caso libre")
	_check_new_content(d)
	var emp := d.get_role("ROLE_EMPLOYEE")
	_check(emp.count == {"min": 0, "max": 4} and emp.weight == 1, "count del Empleado (0..4) y peso de relleno")
	var logs := d.get_spawn("CLUE_SERVER_LOGS")
	_check(logs.position == Vector2(460, 120) and not logs.pocketable, "logs: posición del caso y no transportables")
	_check("ROLE_CTO" in logs.benefits and "ROLE_CEO" in logs.harms, "beneficia/perjudica desde backup/deletion")
	var types := ["CLUE_SERVER_LOGS", "CLUE_UNLOCKED_LAPTOP", "CLUE_TORN_CONTRACT", "CLUE_ENCRYPTED_PENDRIVE"].map(func(id): return d.get_spawn(id).type_name)
	_check(types == ["text", "photo", "item", "item"], "tipo libre → text/photo/item (%s)" % [types])
	_check(d.get_role("ROLE_CEO").team == "culpables", "team explícito")
	_check(d.get_role("ROLE_INVESTOR").team == "inocentes", "team explícito (antes salía de alignment)")
	_check(LegacyCaseNormalizer.normalize({"roles": [{"role_id": "X", "alignment": "Culpable / Encubridor"}]})["scenario"]["roles"][0]["team"] == "culpable", "sin team: equipo desde alignment")

## Roles y pistas nuevos (partidas de 4 a 12): mismo contenido en el caso nativo y en el libre.
func _check_new_content(d: ScenarioData) -> void:
	var expected := {
		"CLUE_LAWYER_NDA": Vector2(2900, -80), "CLUE_HR_DISMISSAL": Vector2(3380, 0), "CLUE_BLACKOUT_LOG": Vector2(3820, -160),
		"CLUE_GYM_LOCKER": Vector2(2960, 1000), "CLUE_BURNER_PHONE": Vector2(3700, 1080),
	}
	_check(d.evidence_spawns.size() == 16, "16 pistas (%d)" % d.evidence_spawns.size())
	for id in expected:
		var s := d.get_spawn(id)
		_check(s != null and s.position == expected[id], "%s en su posición fija" % id)
	_check(d.get_spawn("CLUE_GYM_LOCKER").pocketable and d.get_spawn("CLUE_BURNER_PHONE").pocketable, "taquilla y móvil se pueden llevar")
	_check(d.get_spawn("CLUE_LAWYER_NDA").incriminates == ["ROLE_ACCOMPLICE", "ROLE_CEO"], "incriminates del NDA")
	_check("ROLE_CFO" in d.get_spawn("CLUE_FAKE_INVOICES").incriminates, "las facturas incriminan a la Directora Financiera")
	var acc := d.get_role("ROLE_ACCOMPLICE")
	_check(acc != null and acc.team == "culpables" and acc.count == {"min": 0, "max": 1} and acc.min_players == 6, "Cómplice: culpables, 0..1, desde 6")
	_check(acc.powers == ["silence"] and acc.knows_teammates, "Cómplice: silence y conoce al CEO")
	_check(acc.to_role_dict()["minPlayers"] == 6 and acc.to_role_dict()["powers"] == ["silence"], "to_role_dict lleva minPlayers y powers")
	var sec := d.get_role("ROLE_SECURITY")
	_check(sec != null and sec.min_players == 5 and sec.powers == ["escort"] and sec.team == "inocentes", "Seguridad: escort, desde 5")
	_check(d.get_role("ROLE_JOURNALIST").min_players == 9 and d.get_role("ROLE_JOURNALIST").team == "mercenario", "Periodista desde 9")
	var cfo := d.get_role("ROLE_CFO")
	_check(cfo.min_players == 10 and cfo.powers == ["silence"] and cfo.motive_targets == ["ROLE_INVESTOR"], "Directora Financiera desde 10")
	_check(d.get_role("ROLE_CEO").powers == ["silence"] and d.get_role("ROLE_CEO").motive_targets == ["ROLE_LEAKER"], "CEO: silence y móvil contra el Filtrador")

func _check(cond: bool, label: String) -> void:
	if cond:
		print("  ok   ", label)
	else:
		_failures += 1
		print("  FAIL ", label)
