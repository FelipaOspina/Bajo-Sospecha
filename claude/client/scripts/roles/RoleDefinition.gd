class_name RoleDefinition
extends RefCounted
## Definición inmutable de un rol, construida desde el JSON compartido.

const VISIBILITY_ORDER := {"hidden": 0, "partial": 1, "full": 2}

var id: String
var display_name: String
var team: String
var description: String
var knows_teammates: bool
var default_visibility: String
var visibility_rules: Array[Dictionary] = []  # [{tags: [..], level: ".."}]
var objectives: Array[Dictionary] = []        # [{id, type, description, params}]
var modifiers: Array[Dictionary] = []         # [{id, params}]
var min_players := 0                          # solo entra en el reparto desde N jugadores (0 = siempre)
var powers: Array[String] = []                # "silence", "escort"
var motive_targets: Array[String] = []        # roles a los que siempre tiene motivo para silenciar

static func from_dict(d: Dictionary) -> RoleDefinition:
	var r := RoleDefinition.new()
	r.id = d["id"]
	r.display_name = d.get("name", d["id"])
	r.team = d["team"]
	r.description = d.get("description", "")
	r.knows_teammates = d.get("knowsTeammates", false)
	var vis: Dictionary = d.get("visibility", {})
	r.default_visibility = vis.get("default", "partial")
	for rule in vis.get("rules", []):
		r.visibility_rules.append(rule)
	for o in d.get("objectives", []):
		r.objectives.append(o)
	for m in d.get("modifiers", []):
		r.modifiers.append(m)
	r.min_players = int(d.get("minPlayers", 0))
	for p in d.get("powers", []):
		r.powers.append(str(p))
	for t in d.get("motiveTargets", []):
		r.motive_targets.append(str(t))
	return r
