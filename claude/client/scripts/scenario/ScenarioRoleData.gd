class_name ScenarioRoleData
extends RefCounted
## Rol tal como lo define un escenario.

var id: String
var display_name: String
var description := ""
var team := ""
var count := {"min": 1, "max": 1}
var weight := 0
var knows_teammates := false
var secret_objectives: Array[Dictionary] = []  # {id, description, type, params}
var visibility: Dictionary = {}                # vacío = regla por defecto del escenario
var modifiers: Array = []

## Convierte al formato que entiende RoleManager / RoleDefinition.from_dict.
func to_role_dict() -> Dictionary:
	var vis := visibility
	if vis.is_empty():
		vis = {"default": "partial", "rules": [{"tags": [ScenarioData.tag_benefits(id)], "level": "full"}]}
	return {
		"id": id,
		"name": display_name,
		"team": team if team != "" else id,
		"description": description,
		"count": count,
		"weight": weight,
		"knowsTeammates": knows_teammates,
		"visibility": vis,
		"objectives": secret_objectives,
		"modifiers": modifiers,
	}
