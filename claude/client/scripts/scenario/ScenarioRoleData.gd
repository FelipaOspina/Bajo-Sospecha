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
var min_players := 0                           # 0 = sin mínimo
var powers: Array[String] = []                 # "silence" (silenciar), "escort" (escoltar)
var motive_targets: Array[String] = []         # roles a los que siempre tiene motivo para silenciar

## Convierte al formato que entiende RoleManager / RoleDefinition.from_dict.
func to_role_dict() -> Dictionary:
	var vis := visibility
	if vis.is_empty():
		vis = {"default": "partial", "rules": [{"tags": [ScenarioData.tag_benefits(id)], "level": "full"}]}
	var out := {
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
	if min_players > 0:
		out["minPlayers"] = min_players
	if not powers.is_empty():
		out["powers"] = powers
	if not motive_targets.is_empty():
		out["motiveTargets"] = motive_targets
	return out
