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
	return r
