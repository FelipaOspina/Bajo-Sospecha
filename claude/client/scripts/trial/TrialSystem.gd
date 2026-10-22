class_name TrialSystem
extends Node
## Fase de confrontación en el cliente. Refleja el estado del juicio que manda el
## servidor (mesa pública, opciones, quién ha votado, resolución) y traduce las
## acciones del jugador en intenciones. No decide nada: el servidor valida.

signal changed
signal resolved(resolution: Dictionary)
signal action_failed(reason: String)

const REASON_TEXT := {
	"present_limit": "Ya has expuesto todas las pruebas que puedes.",
	"already_presented": "Esa prueba ya está en la mesa.",
	"wrong_phase": "Ahora no se puede hacer eso.",
	"not_in_inventory": "No tienes esa prueba.",
	"unknown_option": "Esa opción ya no existe.",
	"not_alive": "Ya no puedes votar.",
	"knocked_before": "Te noquearon durante la investigación: no puedes presentar pruebas en el juicio.",
	"ghost": "Los fantasmas no votan.",
}

var network: Node
var deck: Array = []          # [{instanceId, presentedBy, at, evidence: EvidenceData}]
var options: Array = []       # [{id, label, description?}]
var voted: Array = []         # ids de jugador
var my_vote = null
var tally: Dictionary = {}    # votos por opción, si el escenario los hace públicos
var max_presented := 2
var resolution: Dictionary = {}

var _pending := {}
var _last_signature := ""

func _ready() -> void:
	if network == null:
		network = Network
	GameState.snapshot_applied.connect(_sync)
	EventBus.intent_rejected.connect(_on_rejected)

func phase() -> String:
	return GameState.snapshot.get("phase", "")

func is_active() -> bool:
	return phase() in ["discussion", "voting"]

func can_vote() -> bool:
	return phase() == "voting" and not GameState.is_ghost()

## Te noquearon alguna vez: en el juicio puedes votar, pero no presentar pruebas.
func was_knocked() -> bool:
	return GameState.was_knocked()

func presented_by_me() -> int:
	return deck.filter(func(c): return c["presentedBy"] == GameState.local_player_id()).size()

func can_present() -> bool:
	return is_active() and presented_by_me() < max_presented and not was_knocked() and not GameState.is_ghost()

## Lo que puedo exponer: mi inventario (incluidas copias de pistas fijas), sin lo que ya está en la mesa.
func presentable() -> Array[EvidenceData]:
	var on_table := deck.map(func(c): return c["instanceId"])
	var you := GameState.my_private_state()
	var out: Array[EvidenceData] = []
	for v in you.get("inventory", []):
		if not v["instanceId"] in on_table:
			out.append(EvidenceData.from_view(v))
	return out

func present(instance_id: String) -> void:
	_pending[network.send_intent(Protocol.I_PRESENT, {"evidenceInstanceId": instance_id})] = true

func call_meeting() -> void:
	network.send_intent(Protocol.I_CALL_MEETING, {})

func skip_to_voting() -> void:
	network.send_intent(Protocol.I_SKIP_TO_VOTING, {})

func vote(option_id) -> void:
	_pending[network.send_intent(Protocol.I_VOTE, {"optionId": option_id})] = true

func player_name(id: String) -> String:
	for p in GameState.players():
		if p["id"] == id:
			return p["name"]
	return "?"

func _sync(s: Dictionary) -> void:
	var t: Dictionary = s.get("trial", {})
	var signature := JSON.stringify([t, s.get("phase"), GameState.my_private_state().get("inventory", []), GameState.is_ghost()])
	if signature == _last_signature:
		return
	_last_signature = signature
	deck = t.get("deck", []).map(func(c):
		var card: Dictionary = c.duplicate()
		card["evidence"] = EvidenceData.from_view(c["evidence"])
		return card)
	options = t.get("options", [])
	voted = t.get("voted", [])
	my_vote = t.get("myVote")
	tally = t.get("tally") if t.get("tally") is Dictionary else {}
	max_presented = int(t.get("maxPresentedPerPlayer", 2))
	var had := not resolution.is_empty()
	resolution = t.get("resolution") if t.get("resolution") is Dictionary else {}
	changed.emit()
	if not had and not resolution.is_empty():
		resolved.emit(resolution)

func _on_rejected(seq: int, reason: String) -> void:
	if _pending.erase(seq):
		action_failed.emit(REASON_TEXT.get(reason, reason))
