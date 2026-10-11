class_name EvidenceSpawnData
extends RefCounted
## Una pista que el escenario coloca en el mapa.

enum Type { TEXT, AUDIO, PHOTO, ITEM }

const TYPE_NAMES := {"text": Type.TEXT, "audio": Type.AUDIO, "photo": Type.PHOTO, "item": Type.ITEM}

var id: String
var display_name: String
var description: String
var type: Type
var type_name: String
var position: Vector2
var radius := 48.0
var room := ""
var pocketable := true
var medium := ""                   # aspecto exterior ("digital/critica"...); elige el marco del visor
var weight := 1
var tags: Array[String] = []
var benefits: Array[String] = []   # ids de rol
var harms: Array[String] = []      # ids de rol
var content: Dictionary = {}       # text / audio / image según el tipo

## Id del objeto del mapa; el servidor usa exactamente el mismo.
func interactable_id() -> String:
	return "spawn_" + id

## Etiquetas finales (mismas que genera server/src/domain/scenario/ScenarioAdapter.ts).
func all_tags() -> Array[String]:
	var out: Array[String] = tags.duplicate()
	out.append(ScenarioData.tag_evidence(id))
	out.append(ScenarioData.tag_type(type_name))
	for r in benefits:
		out.append(ScenarioData.tag_benefits(r))
	for r in harms:
		out.append(ScenarioData.tag_harms(r))
	return out

func affects(role_id: String) -> int:
	## +1 si beneficia al rol, -1 si le perjudica, 0 si le es indiferente.
	if role_id in benefits:
		return 1
	if role_id in harms:
		return -1
	return 0
