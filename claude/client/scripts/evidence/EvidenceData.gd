class_name EvidenceData
extends RefCounted
## Vista de una pista tal como el servidor nos deja verla (EvidenceView).

var instance_id: String
var visibility: String           # "partial" | "full"
var definition_id := ""
var display_name := "???"
var description := ""
var tags: Array = []
var content: Dictionary = {}     # {text?, image?, audio?}
var pocketable := true
var medium := ""                 # aspecto exterior, visible también con vista parcial
var locked := ""                 # "" | "view" | "collect"
var required_items: Array = []   # nombres de las llaves que faltan
var actions: Array = []          # [{kind: "delete"|"backup", label, seconds}] que TU rol puede hacer
var is_copy := false             # copia (dump, foto) de una pista fija

var is_known: bool:
	get: return visibility == Protocol.VIS_FULL

static func from_view(v: Dictionary) -> EvidenceData:
	var e := EvidenceData.new()
	e.instance_id = v["instanceId"]
	e.visibility = v.get("visibility", Protocol.VIS_PARTIAL)
	e.locked = str(v.get("locked", "")) if v.get("locked") else ""
	e.required_items = v.get("requiredItems", [])
	e.actions = v.get("actions", [])
	e.is_copy = v.get("isCopy", false)
	e.medium = str(v.get("medium", ""))
	if e.is_known:
		e.definition_id = v.get("definitionId", "")
		e.display_name = v.get("name", "???")
		e.description = v.get("description", "")
		e.tags = v.get("tags", [])
		e.content = v.get("content", {}) if v.get("content") is Dictionary else {}
		e.pocketable = v.get("pocketable", true)
	return e

## Pista tal como viene en el JSON del caso (clues_and_evidence[]), vista por un rol.
## Las acciones se filtran con los authorized_roles de deletion_action / backup_action.
## Solo para uso local (editor, pruebas, modo sin servidor): en partida manda el servidor.
static func from_case_clue(c: Dictionary, role_id := "") -> EvidenceData:
	var mine := []
	for a in LegacyCaseNormalizer.clue_actions(c):
		if role_id in a["roles"]:
			mine.append({"kind": a["kind"], "label": a["label"], "seconds": a["seconds"]})
	var tags := LegacyCaseNormalizer.type_tags(str(c.get("type", "")))
	var req := LegacyCaseNormalizer._dict(c.get("interaction_requirements"))
	return from_view({
		"instanceId": str(c.get("id", "")), "visibility": Protocol.VIS_FULL, "definitionId": str(c.get("id", "")),
		"name": str(c.get("name", "???")), "description": str(c.get("description", "")),
		"tags": tags, "medium": "/".join(tags), "pocketable": req.get("can_be_pocketed", true), "actions": mine,
	})

func has_tag(tag: String) -> bool:
	return tag in tags

## Se puede pedir al servidor que la guarde (él vuelve a validarlo todo).
func can_collect() -> bool:
	return locked == "" and pocketable

## Texto para el visor cuando falta un permiso.
func lock_message() -> String:
	if locked == "":
		if pocketable:
			return ""
		return "No puedes llevártela; usa una acción para copiarla." if actions.any(func(a): return a["kind"] == "backup") \
			else "No puedes llevártela; solo examinarla aquí."
	var what := "ver los detalles" if locked == "view" else "llevártela"
	if required_items.is_empty():
		return "Tu rol no te permite %s." % what
	return "Necesitas %s para %s." % [", ".join(required_items), what]
