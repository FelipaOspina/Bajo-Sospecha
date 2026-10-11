class_name ScenarioData
extends RefCounted
## Datos de un caso ya validados. Se construye con ScenarioParser.parse().
## Sabe traducirse a los formatos que consumen RoleManager y el servidor, de
## modo que esos sistemas no necesitan conocer el formato de escenario.

const FORMAT_VERSION := 1

var format_version := FORMAT_VERSION
var scenario_id: String
var title: String
var description := ""
var player_count := {"min": 0, "max": 0}
var roles: Array[ScenarioRoleData] = []
var evidence_spawns: Array[EvidenceSpawnData] = []

static func tag_evidence(id: String) -> String: return "pista:" + id
static func tag_type(t: String) -> String: return "tipo:" + t
static func tag_benefits(role_id: String) -> String: return "beneficia:" + role_id
static func tag_harms(role_id: String) -> String: return "perjudica:" + role_id

func get_role(role_id: String) -> ScenarioRoleData:
	for r in roles:
		if r.id == role_id:
			return r
	return null

func get_spawn(evidence_id: String) -> EvidenceSpawnData:
	for e in evidence_spawns:
		if e.id == evidence_id:
			return e
	return null

## Pistas que benefician (+1) o perjudican (-1) a un rol.
func spawns_affecting(role_id: String, direction: int) -> Array[EvidenceSpawnData]:
	var out: Array[EvidenceSpawnData] = []
	for e in evidence_spawns:
		if e.affects(role_id) == direction:
			out.append(e)
	return out

## Set de roles con el formato de shared/config/roles/*.json.
func to_role_set() -> Dictionary:
	return {
		"id": scenario_id,
		"name": title,
		"version": format_version,
		"minPlayers": player_count["min"],
		"maxPlayers": player_count["max"],
		"roles": roles.map(func(r: ScenarioRoleData): return r.to_role_dict()),
	}
