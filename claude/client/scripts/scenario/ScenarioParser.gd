class_name ScenarioParser
extends RefCounted
## Valida un Dictionary (JSON ya parseado) y construye ScenarioData.
## Acumula TODOS los errores para que el diseñador del caso los vea de una vez.
## Las reglas coinciden con server/src/domain/scenario/ScenarioAdapter.ts.

class Result:
	var data: ScenarioData
	var errors := PackedStringArray()
	var warnings := PackedStringArray()
	func ok() -> bool:
		return errors.is_empty() and data != null

const KNOWN_ROOT_KEYS := ["format_version", "scenario_id", "title", "description", "player_count", "roles",
	"evidence_spawns", "$schema", "phase_durations", "culprit_roles", "trial", "endings"]

static func parse(raw: Variant) -> Result:
	var res := Result.new()
	# Casos en formato libre de guion: se normalizan al vuelo (el archivo no se toca).
	if LegacyCaseNormalizer.is_legacy(raw):
		var n := LegacyCaseNormalizer.normalize(raw)
		res.warnings.append_array(n["warnings"])
		raw = n["scenario"]
	if not raw is Dictionary:
		res.errors.append("El escenario no es un objeto JSON")
		return res
	var d: Dictionary = raw

	for k in d.keys():
		if not k in KNOWN_ROOT_KEYS:
			res.warnings.append("Campo desconocido ignorado: %s" % k)
	if int(d.get("format_version", ScenarioData.FORMAT_VERSION)) > ScenarioData.FORMAT_VERSION:
		res.warnings.append("format_version más nueva que este cliente (%d)" % ScenarioData.FORMAT_VERSION)

	var data := ScenarioData.new()
	data.scenario_id = str(d.get("scenario_id", ""))
	data.title = str(d.get("title", ""))
	data.description = str(d.get("description", ""))
	var id_regex := RegEx.create_from_string("^[A-Za-z0-9_-]+$")
	if id_regex.search(data.scenario_id) == null:
		res.errors.append("scenario_id requerido (letras, números, _ o -)")
	if data.title.is_empty():
		res.errors.append("title requerido")

	var raw_roles = d.get("roles")
	var raw_spawns = d.get("evidence_spawns")
	if not raw_roles is Array or raw_roles.is_empty():
		res.errors.append("roles debe ser una lista no vacía")
		raw_roles = []
	if not raw_spawns is Array:
		res.errors.append("evidence_spawns debe ser una lista")
		raw_spawns = []

	for r in raw_roles:
		var role := _parse_role(r, res)
		if role:
			if data.get_role(role.id):
				res.errors.append("rol \"%s\": id duplicado" % role.id)
			data.roles.append(role)

	for e in raw_spawns:
		var spawn := _parse_spawn(e, data, res)
		if spawn:
			if data.get_spawn(spawn.id):
				res.errors.append("pista \"%s\": id duplicado" % spawn.id)
			data.evidence_spawns.append(spawn)

	var pc = d.get("player_count")
	if pc is Dictionary:
		data.player_count = {"min": int(pc.get("min", 0)), "max": int(pc.get("max", 0))}
	else:
		var mn := 0
		var mx := 0
		for r in data.roles:
			mn += r.count["min"]
			mx += r.count["max"]
		data.player_count = {"min": mn, "max": mx}

	if res.errors.is_empty():
		res.data = data
	return res

static func _parse_role(r: Variant, res: Result) -> ScenarioRoleData:
	if not r is Dictionary:
		res.errors.append("Un rol no es un objeto")
		return null
	var role := ScenarioRoleData.new()
	role.id = str(r.get("id", ""))
	role.display_name = str(r.get("name", ""))
	var where := "rol \"%s\"" % role.id
	if role.id.is_empty():
		res.errors.append("Un rol no tiene id")
	if role.display_name.is_empty():
		res.errors.append("%s: name requerido" % where)
	role.description = str(r.get("description", ""))
	role.team = str(r.get("team", ""))
	role.weight = int(r.get("weight", 0))
	role.knows_teammates = bool(r.get("knows_teammates", false))
	if r.get("count") is Dictionary:
		role.count = {"min": int(r["count"].get("min", 1)), "max": int(r["count"].get("max", 1))}
	if r.get("visibility") is Dictionary:
		role.visibility = r["visibility"]
	if r.get("modifiers") is Array:
		role.modifiers = r["modifiers"]

	var objectives = r.get("secret_objectives")
	if not objectives is Array:
		res.errors.append("%s: secret_objectives debe ser una lista" % where)
		return role
	for i in objectives.size():
		var o = objectives[i]
		var fallback_id := "obj_%d" % (i + 1)
		if o is String:
			role.secret_objectives.append({"id": fallback_id, "type": "narrative", "description": o})
		elif o is Dictionary and o.has("description"):
			var obj := {"id": str(o.get("id", fallback_id)), "type": str(o.get("type", "narrative")), "description": str(o["description"])}
			if o.get("params") is Dictionary:
				obj["params"] = o["params"]
			role.secret_objectives.append(obj)
		else:
			res.errors.append("%s: objetivo %d debe ser texto o {description, type?, params?}" % [where, i + 1])
	return role

static func _parse_spawn(e: Variant, data: ScenarioData, res: Result) -> EvidenceSpawnData:
	if not e is Dictionary:
		res.errors.append("Una pista no es un objeto")
		return null
	var s := EvidenceSpawnData.new()
	s.id = str(e.get("id", ""))
	s.display_name = str(e.get("name", ""))
	s.description = str(e.get("description", ""))
	var where := "pista \"%s\"" % s.id
	if s.id.is_empty():
		res.errors.append("Una pista no tiene id")
	if s.display_name.is_empty():
		res.errors.append("%s: name requerido" % where)

	s.type_name = str(e.get("type", ""))
	if not EvidenceSpawnData.TYPE_NAMES.has(s.type_name):
		res.errors.append("%s: type \"%s\" no es text | audio | photo | item" % [where, s.type_name])
	else:
		s.type = EvidenceSpawnData.TYPE_NAMES[s.type_name]

	var pos = _to_vector2(e.get("position"))
	if pos == null:
		res.errors.append("%s: position debe ser {x, y} o [x, y]" % where)
	else:
		s.position = pos

	s.radius = float(e.get("radius", 48.0))
	s.room = str(e.get("room", ""))
	s.pocketable = bool(e.get("pocketable", true))
	s.medium = str(e.get("medium", s.type_name))
	s.weight = int(e.get("weight", 1))
	for t in e.get("tags", []):
		s.tags.append(str(t))
	for r in e.get("benefits", []):
		s.benefits.append(str(r))
	for r in e.get("harms", []):
		s.harms.append(str(r))
	for ref in s.benefits + s.harms:
		if data.get_role(ref) == null:
			res.errors.append("%s: referencia a rol inexistente \"%s\"" % [where, ref])
	if e.get("content") is Dictionary:
		s.content = e["content"]
	_check_content(s, res)
	return s

## Avisos (no errores): el servidor no necesita los recursos multimedia.
static func _check_content(s: EvidenceSpawnData, res: Result) -> void:
	var key := ""
	match s.type:
		EvidenceSpawnData.Type.AUDIO: key = "audio"
		EvidenceSpawnData.Type.PHOTO: key = "image"
		_: return
	var path := str(s.content.get(key, ""))
	if path.is_empty() or not ResourceLoader.exists(path):
		res.warnings.append("pista \"%s\": content.%s no encontrado (%s); se usará un marcador" % [s.id, key, path])

static func _to_vector2(p: Variant) -> Variant:
	if p is Array and p.size() == 2 and (p[0] is float or p[0] is int) and (p[1] is float or p[1] is int):
		return Vector2(p[0], p[1])
	if p is Dictionary and p.has("x") and p.has("y"):
		return Vector2(float(p["x"]), float(p["y"]))
	return null
