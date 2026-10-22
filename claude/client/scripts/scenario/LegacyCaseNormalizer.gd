class_name LegacyCaseNormalizer
extends RefCounted
## Convierte un caso en formato libre de guion (case_id, individual_objectives,
## clues_and_evidence con room y type en texto) al formato de escenario.
## Mismas reglas que server/src/domain/scenario/LegacyCaseNormalizer.ts:
## si cambias una, cambia la otra (los tests de ambos lados comprueban lo mismo).

static func is_legacy(raw: Variant) -> bool:
	return raw is Dictionary and (raw.has("case_id") or raw.has("clues_and_evidence"))

static func slug(s: String) -> String:
	var t := s.to_lower()
	for pair in [["á", "a"], ["é", "e"], ["í", "i"], ["ó", "o"], ["ú", "u"], ["ü", "u"], ["ñ", "n"]]:
		t = t.replace(pair[0], pair[1])
	var re := RegEx.create_from_string("[^a-z0-9]+")
	return re.sub(t, "_", true).trim_prefix("_").trim_suffix("_")

static func evidence_type(raw: String) -> String:
	var t := slug(raw)
	if RegEx.create_from_string("audio|grabaci|voz").search(t): return "audio"
	if RegEx.create_from_string("visual|foto|imagen|captura").search(t): return "photo"
	if RegEx.create_from_string("fisic|documental|objeto|item").search(t): return "item"
	return "text"

static func room_position(room_index: int, slot: int) -> Dictionary:
	return {"x": 200 + (room_index % 3) * 440 + slot * 70, "y": 150 + int(room_index / 3) * 400}

## Posición escrita en el caso, o {} si no la trae o no es válida.
static func explicit_position(p: Variant) -> Dictionary:
	if p is Array and p.size() == 2 and (p[0] is float or p[0] is int) and (p[1] is float or p[1] is int):
		return {"x": float(p[0]), "y": float(p[1])}
	if p is Dictionary and p.has("x") and p.has("y"):
		return {"x": float(p["x"]), "y": float(p["y"])}
	return {}

## Devuelve {scenario: Dictionary, warnings: PackedStringArray}.
static func normalize(raw: Dictionary) -> Dictionary:
	var warnings := PackedStringArray()
	var setting := _dict(raw.get("setting"))
	var rooms: Array = _list(setting.get("rooms")).duplicate()
	var slots := {}

	var roles := []
	var role_by_id := {}
	for r in _list(raw.get("roles")):
		if r.has("hidden_ability"):
			warnings.append("rol %s: hidden_ability \"%s\" aún no tiene mecánica; se ignora" % [r["role_id"], r["hidden_ability"].get("name", "")])
		# Campos opcionales (partidas de 4 a 12): team, count, min_players, powers, knows_teammates, motive_targets.
		var count := {"min": 1, "max": 1}
		var raw_count := _dict(r.get("count"))
		if raw_count.has("min") and raw_count.has("max"):
			count = {"min": int(raw_count["min"]), "max": int(raw_count["max"])}
		var role := {
			"id": r["role_id"],
			"name": r.get("display_name", r["role_id"]),
			"description": r.get("starting_knowledge", ""),
			"team": str(r["team"]) if str(r.get("team", "")) != "" else slug(str(r.get("alignment", r["role_id"])).split("/")[0]),
			"count": count,
			"secret_objectives": r.get("individual_objectives", []).duplicate(),
			"modifiers": [],
		}
		if count["min"] == 0:
			role["weight"] = 1
		if r.get("min_players") != null:
			role["min_players"] = int(r["min_players"])
		if not _list(r.get("powers")).is_empty():
			role["powers"] = _list(r["powers"]).map(func(p): return str(p))
		if r.get("knows_teammates", false):
			role["knows_teammates"] = true
		if not _list(r.get("motive_targets")).is_empty():
			role["motive_targets"] = _list(r["motive_targets"]).map(func(p): return str(p))
		roles.append(role)
		role_by_id[role["id"]] = role

	var spawns := []
	for c in _list(raw.get("clues_and_evidence")):
		var req := _dict(c.get("interaction_requirements"))
		var room_index := _find_room(rooms, str(c.get("room", "Sin sala")), warnings)
		var slot: int = slots.get(room_index, 0)
		slots[room_index] = slot + 1
		# El caso puede fijar la posición en el plano ("position": {x, y} o [x, y]).
		var pos := explicit_position(c.get("position"))
		if pos.is_empty():
			pos = room_position(room_index, slot)
		var deleters: Array = _list(_dict(req.get("deletion_action")).get("authorized_roles")) if req.get("can_be_deleted", false) else []
		var backers: Array = _list(_dict(req.get("backup_action")).get("authorized_roles"))
		# deletion_action / backup_action → acciones canalizadas (las aplica el servidor).
		var actions := []
		if req.get("can_be_deleted", false) and req.get("deletion_action") is Dictionary:
			actions.append(_action("delete", req["deletion_action"]))
		if req.get("backup_action") is Dictionary:
			actions.append(_action("backup", req["backup_action"]))
		if req.has("skill_check"):
			warnings.append("pista %s: skill_check (minijuego) aún no tiene mecánica; se ignora" % c["id"])
		var tags := []
		for part in str(c.get("type", "")).split("/"):
			var t := slug(part)
			if t != "":
				tags.append(t)
		spawns.append({
			"id": c["id"],
			"name": c["name"],
			"description": c.get("description", ""),
			"type": evidence_type(str(c.get("type", ""))),
			"tags": tags,
			"medium": "/".join(tags),
			"room": c.get("room", ""),
			"position": pos,
			"pocketable": req.get("can_be_pocketed", true),
			"weight": c.get("evidence_weight", 1),
			"benefits": backers,
			"harms": deleters,
			"actions": actions,
			"incriminates": _list(c.get("incriminates")).duplicate(),
		})

	var player_count = raw.get("player_count")
	var seats := 0
	for role in roles:
		seats += int(role["count"]["max"])
	if player_count is Dictionary and int(player_count.get("max", 0)) > seats:
		warnings.append("player_count.max (%d) se reduce a %d: solo hay %d plazas de rol" % [player_count["max"], seats, seats])
		player_count = {"min": mini(int(player_count.get("min", 0)), seats), "max": seats}

	return {
		"warnings": warnings,
		"scenario": {
			"format_version": 1,
			"scenario_id": slug(str(raw.get("case_id", "caso"))),
			"title": raw.get("title", raw.get("case_id", "")),
			"description": setting.get("crisis_summary", ""),
			"player_count": player_count,
			"roles": roles,
			"evidence_spawns": spawns,
		},
	}

## Acciones canalizadas de una pista del caso (deletion_action / backup_action), con sus roles.
static func clue_actions(c: Dictionary) -> Array:
	var req := _dict(c.get("interaction_requirements"))
	var actions := []
	if req.get("can_be_deleted", false) and req.get("deletion_action") is Dictionary:
		actions.append(_action("delete", req["deletion_action"]))
	if req.get("backup_action") is Dictionary:
		actions.append(_action("backup", req["backup_action"]))
	return actions

## Etiquetas a partir del type en texto ("Digital / Crítica" → ["digital", "critica"]).
static func type_tags(raw_type: String) -> Array:
	var tags := []
	for part in raw_type.split("/"):
		var t := slug(part)
		if t != "":
			tags.append(t)
	return tags

static func _action(kind: String, a: Dictionary) -> Dictionary:
	return {"kind": kind, "label": str(a.get("action_name", "...")), "roles": _list(a.get("authorized_roles")),
		"seconds": float(a.get("channeling_time_seconds", 0))}

## En los JSON escritos a mano, un campo puede existir con valor null.
static func _dict(v: Variant) -> Dictionary:
	return v if v is Dictionary else {}

static func _list(v: Variant) -> Array:
	return v if v is Array else []

static func _find_room(rooms: Array, name: String, warnings: PackedStringArray) -> int:
	var i := rooms.find(name)
	if i < 0:
		for j in rooms.size():
			if slug(rooms[j]).contains(slug(name)) or slug(name).contains(slug(rooms[j])):
				i = j
				break
	if i < 0:
		warnings.append("la sala \"%s\" no está en setting.rooms; se añade al final" % name)
		rooms.append(name)
		i = rooms.size() - 1
	return i
