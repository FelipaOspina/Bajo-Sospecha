class_name TrialAssemblyManager
extends Node
## Lógica de la mesa de asamblea / juicio (sin dibujar nada; la pinta AssemblyBoardUI).
##  - El jugador elige (clic o arrastre) una prueba de su inventario y la expone:
##    se pide al servidor y, cuando la pone en la mesa pública, se emite
##    evidence_presented(evidence_data, player_id) para mostrarla en el centro.
##  - Votación: accuse(option_id) es el botón "Acusar"; votes_by_option() y
##    votes_by_role() cuentan los votos recibidos por cada opción / rol acusado.
## El servidor sigue siendo la autoridad: aquí solo se validan cosas para dar
## feedback inmediato (fase, cupo, que la prueba sea tuya y no esté ya en la mesa).

signal evidence_presented(evidence_data: EvidenceData, player_id: String)
signal selection_changed(evidence_data: EvidenceData)
signal votes_changed(by_option: Dictionary)
signal accused(option_id: String)
signal action_failed(reason: String)

const DRAG_TYPE := "trial_evidence"

@export var trial: TrialSystem

var selected: EvidenceData

var _on_table := {}        # instanceId -> true (lo ya anunciado)
var _last_votes := {}
var _bound := false

func _ready() -> void:
	if trial:
		bind(trial)

func bind(t: TrialSystem) -> void:
	if _bound:
		return
	_bound = true
	trial = t
	trial.changed.connect(_on_trial_changed)
	trial.action_failed.connect(func(reason): action_failed.emit(reason))
	_on_trial_changed()

# ───── Inventario y selección ─────

## Pruebas del jugador que aún puede exponer (inventario, copias incluidas, menos la mesa).
func player_inventory() -> Array[EvidenceData]:
	return trial.presentable()

func find_in_inventory(instance_id: String) -> EvidenceData:
	for e in player_inventory():
		if e.instance_id == instance_id:
			return e
	return null

func select(instance_id: String) -> void:
	selected = find_in_inventory(instance_id)
	selection_changed.emit(selected)

func clear_selection() -> void:
	selected = null
	selection_changed.emit(null)

## Datos de arrastre de una prueba del inventario (para Control._get_drag_data).
static func drag_data(e: EvidenceData) -> Dictionary:
	return {"type": DRAG_TYPE, "instance_id": e.instance_id}

## ¿Se puede soltar esto en la mesa? (para Control._can_drop_data)
func can_drop(data) -> bool:
	return data is Dictionary and data.get("type") == DRAG_TYPE and can_present(str(data.get("instance_id", "")))

func drop(data) -> void:
	if data is Dictionary and data.get("type") == DRAG_TYPE:
		present(str(data["instance_id"]))

# ───── Exponer ─────

func can_present(instance_id: String) -> bool:
	return why_not_present(instance_id) == ""

func why_not_present(instance_id: String) -> String:
	if not trial.is_active():
		return TrialSystem.REASON_TEXT["wrong_phase"]
	if _on_table.has(instance_id):
		return TrialSystem.REASON_TEXT["already_presented"]
	if find_in_inventory(instance_id) == null:
		return TrialSystem.REASON_TEXT["not_in_inventory"]
	if not trial.can_present():
		return TrialSystem.REASON_TEXT["present_limit"]
	return ""

func present(instance_id: String) -> bool:
	var why := why_not_present(instance_id)
	if why != "":
		action_failed.emit(why)
		return false
	trial.present(instance_id)
	return true

func present_selected() -> bool:
	if selected == null:
		action_failed.emit("Elige primero una prueba de tu inventario.")
		return false
	var ok := present(selected.instance_id)
	if ok:
		clear_selection()
	return ok

## Mesa pública, en orden de exposición: [{instanceId, presentedBy, at, evidence: EvidenceData}].
func table() -> Array:
	return trial.deck

## La última prueba expuesta: la que se muestra en el centro de la mesa.
func center_card() -> Dictionary:
	return trial.deck[-1] if not trial.deck.is_empty() else {}

# ───── Votación ─────

func options() -> Array:
	return trial.options

func can_accuse() -> bool:
	return trial.can_vote()

## Botón "Acusar" de una opción. Pulsar la que ya votaste retira el voto.
func accuse(option_id) -> void:
	if not can_accuse():
		action_failed.emit(TrialSystem.REASON_TEXT["wrong_phase"])
		return
	var id = null if option_id == trial.my_vote else option_id
	trial.vote(id)
	if id != null:
		accused.emit(str(id))

## Acusa al rol indicado si hay una opción que lo acusa (accuses_role del escenario).
func accuse_role(role_id: String) -> bool:
	var o := option_for_role(role_id)
	if o.is_empty():
		return false
	accuse(o["id"])
	return true

func option_for_role(role_id: String) -> Dictionary:
	for o in trial.options:
		if o.get("accusesRole") == role_id:
			return o
	return {}

## Votos recibidos por opción. En vivo solo si el escenario los hace públicos
## (public_tally); si no, se conocen al resolver. {} = aún secretos.
func votes_by_option() -> Dictionary:
	if not trial.resolution.is_empty():
		return trial.resolution.get("verdict", {}).get("tally", {})
	return trial.tally

func votes_public() -> bool:
	return not trial.tally.is_empty() or not trial.resolution.is_empty()

## Votos recibidos por cada rol acusado (opciones con accusesRole).
func votes_by_role() -> Dictionary:
	var by_option := votes_by_option()
	var out := {}
	for o in trial.options:
		var role = o.get("accusesRole")
		if role:
			out[role] = int(out.get(role, 0)) + int(by_option.get(o["id"], 0))
	return out

func votes_for(option_id: String) -> int:
	return int(votes_by_option().get(option_id, 0))

func voted_count() -> int:
	return trial.voted.size()

# ───── Sincronización ─────

func _on_trial_changed() -> void:
	var still := {}
	for card in trial.deck:
		var id: String = card["instanceId"]
		still[id] = true
		if not _on_table.has(id):
			_on_table[id] = true
			evidence_presented.emit(card["evidence"], str(card["presentedBy"]))
	_on_table = still
	if selected and find_in_inventory(selected.instance_id) == null:
		clear_selection()
	var votes := votes_by_option()
	if votes != _last_votes:
		_last_votes = votes.duplicate()
		votes_changed.emit(votes)
