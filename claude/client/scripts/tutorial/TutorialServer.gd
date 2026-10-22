extends Node
## Servidor local de la práctica «Primer día en NexusCore»: una partida de mentira con 4 bots
## que habla el mismo protocolo que el servidor real (welcome, snapshot, event, ack,
## rejected), así la práctica usa la oficina, el HUD, el visor de pruebas, la asamblea y la
## mesa del juicio de verdad. Se engancha a Network.local_server: las intenciones del
## cliente llegan a handle_intent() y las respuestas salen por Network.deliver().
## Solo sabe lo justo para el guion de la práctica (lo dirige Tutorial.gd); no hay red.

signal collected(interactable_id: String)
signal backup_finished(ok: bool, reason: String)
signal reported
signal emergency_voted(target)
signal emergency_resolved(expelled: String)
signal presented
signal voted(option_id)
signal resolved

const ME := "me"
const ROOM := "PRACTICA"
const SCENARIO := "res://data/scenarios/nexuscore_fraude.json"
const DEBTS := "spawn_CLUE_CASINO_DEBTS"
const LAPTOP := "spawn_CLUE_UNLOCKED_LAPTOP"
const START := Vector2(1070, 470)
const REACH := 190.0
const BOT_SPEED := 170.0
const PUSH_INTERVAL := 0.1
## Bots: nombre, posición y rol (solo se ve en la pantalla final, como en una partida real).
const BOTS := [
	{"id": "beto", "name": "Beto", "pos": Vector2(860, 465), "role": "ROLE_CTO"},
	{"id": "carla", "name": "Carla", "pos": Vector2(1560, 470), "role": "ROLE_EMPLOYEE"},
	{"id": "dani", "name": "Dani", "pos": Vector2(1780, 440), "role": "ROLE_CEO"},
	{"id": "eva", "name": "Eva", "pos": Vector2(1330, 480), "role": "ROLE_LEAKER"},
]
const MY_ROLE := "ROLE_INVESTOR"

var players := {}            # id → {id, name, skinId, position: Vector2, alive, ghost, hidden, role}
var order: Array[String] = []
var phase := "lobby"
var phase_ends_at = null
var spots := {}              # interactable id → {position: Vector2, contents: [EvidenceView]}
var inventory: Array = []
var bodies: Array = []
var emergency = null
var trial := {"deck": [], "options": [], "voted": [], "myVote": null, "maxPresentedPerPlayer": 2, "tally": {}, "resolution": null}
var objectives := [
	{"id": "tut_pruebas", "description": "Guarda los avisos de cobro y fotografía la laptop del despacho", "completed": false},
	{"id": "tut_juicio", "description": "Expón una prueba y vota en el juicio final", "completed": false},
]
var channel = null           # {instanceId, startedAt, durationMs, origin, label}
var targets := {}            # bot id → Vector2 hacia donde camina
var version := 0
var emergency_votes := {}    # votante → objetivo
var installed := false

var _scenario: Dictionary = {}
var _out: Array = []
var _dirty := false
var _push_left := 0.0
var _timers: Array = []      # [{at: float, call: Callable}]
var _clock := 0.0
var _copy_seq := 0

func _init() -> void:
	name = "TutorialServer"

# ───── Arranque ─────

## Se engancha a Network y manda el welcome (fase briefing).
func start(my_name: String, my_skin: String) -> void:
	_load_scenario()
	var skins_taken := [my_skin]
	var pool := ["zorro", "gato", "oso", "conejo", "panda", "perro", "lobo", "mapache"]
	players[ME] = {"id": ME, "name": my_name, "skinId": my_skin, "position": START, "alive": true, "ghost": false, "hidden": false, "role": MY_ROLE}
	order = [ME]
	for b in BOTS:
		var skin := ""
		for s in pool:
			if not s in skins_taken:
				skin = s
				break
		skins_taken.append(skin)
		players[b["id"]] = {"id": b["id"], "name": b["name"], "skinId": skin, "position": b["pos"], "alive": true, "ghost": false, "hidden": false, "role": b["role"]}
		order.append(b["id"])
	spots[DEBTS] = {"position": _clue_pos("CLUE_CASINO_DEBTS"), "contents": [_view("CLUE_CASINO_DEBTS", "ev_debts", true, [])]}
	var laptop := _clue("CLUE_UNLOCKED_LAPTOP")
	var photo_label := "Tomar fotografía con el móvil"
	for a in laptop.get("actions", []):
		if a.get("kind") == "backup":
			photo_label = str(a.get("label", photo_label))
	spots[LAPTOP] = {"position": _clue_pos("CLUE_UNLOCKED_LAPTOP"), "contents": [_view("CLUE_UNLOCKED_LAPTOP", "ev_laptop", false, [{"kind": "backup", "label": photo_label, "seconds": 3}])]}
	for o in _scenario.get("trial", {}).get("options", []).slice(0, 3):
		trial["options"].append({"id": str(o.get("id")), "label": str(o.get("label")), "accusesRole": o.get("accuses_role")})
	phase = "briefing"
	installed = true
	Network.local_server = self
	version += 1
	_queue({"t": "welcome", "playerId": ME, "protocol": Protocol.VERSION, "roomCode": ROOM, "serverTime": now_ms(), "snapshot": snapshot()})

## Se desengancha de Network (al terminar o al salir de la escena).
func stop() -> void:
	if installed and Network.local_server == self:
		Network.local_server = null
	installed = false

func _exit_tree() -> void:
	stop()

func now_ms() -> float:
	return Network.local_time_ms()

# ───── Bucle ─────

func _process(delta: float) -> void:
	_clock += delta
	for t in _timers.duplicate():
		if _clock >= t["at"]:
			_timers.erase(t)
			t["call"].call()
	var moved := false
	for id in targets.keys():
		var p: Dictionary = players[id]
		var to: Vector2 = targets[id]
		var at: Vector2 = p["position"]
		var step := BOT_SPEED * delta
		if at.distance_to(to) <= step:
			p["position"] = to
			targets.erase(id)
		else:
			p["position"] = at + (to - at).normalized() * step
		moved = true
	if channel != null and now_ms() >= channel["startedAt"] + channel["durationMs"]:
		_finish_backup()
	_push_left -= delta
	if (moved or _dirty) and _push_left <= 0.0:
		_push_left = PUSH_INTERVAL
		push()
	_flush()

## Llama a f dentro de `seconds` (relojes de la práctica).
func after(seconds: float, f: Callable) -> void:
	_timers.append({"at": _clock + seconds, "call": f})

func _queue(msg: Dictionary) -> void:
	_out.append(msg)

## Entrega lo pendiente (en orden). Las respuestas nunca salen dentro de send_intent: quien
## envía guarda su seq antes de que llegue el ack o el rechazo, como con la red.
func _flush() -> void:
	if not installed:
		_out.clear()
		return
	var batch := _out
	_out = []
	for m in batch:
		Network.deliver(m)

func push() -> void:
	_dirty = false
	version += 1
	_queue({"t": "snapshot", "snapshot": snapshot()})

func event(e: Dictionary) -> void:
	_queue({"t": "event", "version": version, "event": e})

# ───── Estado (RoomSnapshot) ─────

func snapshot() -> Dictionary:
	var list := []
	for id in order:
		var p: Dictionary = players[id]
		var d := {"id": id, "name": p["name"], "position": Protocol.vec2_to(p["position"]), "connected": true, "ready": true,
			"alive": p["alive"], "inventoryCount": inventory.size() if id == ME else 0, "skinId": p["skinId"], "look": Account.equipped() if id == ME else {}}
		if p["ghost"]:
			d["ghost"] = true
			if id != ME:
				d["hidden"] = true
		if id == ME and channel != null:
			d["channel"] = {"kind": "backup", "label": channel["label"], "startedAt": channel["startedAt"], "durationMs": channel["durationMs"]}
		list.append(d)
	var inter := []
	for id in spots:
		inter.append({"id": id, "type": "evidence_spot", "position": Protocol.vec2_to(spots[id]["position"]), "radius": 48, "contents": spots[id]["contents"].duplicate(true)})
	return {
		"version": version, "phase": phase, "phaseEndsAt": phase_ends_at,
		"lobby": {"code": ROOM, "visibility": "private", "hostId": ME, "minPlayers": 4, "maxPlayers": 12, "startsAt": null},
		"players": list, "interactables": inter,
		"you": {"roleId": MY_ROLE, "team": "inocentes", "objectives": objectives.duplicate(true), "inventory": inventory.duplicate(true),
			"knownTeammates": [], "ghost": false, "powers": {}, "meetingUsed": true, "speedMultiplier": 1.0},
		"trial": trial.duplicate(true), "bodies": bodies.duplicate(true), "emergency": emergency.duplicate(true) if emergency is Dictionary else null,
	}

func my_position() -> Vector2:
	return players[ME]["position"]

func set_phase(p: String, seconds := 0.0) -> void:
	phase = p
	phase_ends_at = now_ms() + seconds * 1000.0 if seconds > 0.0 else null
	if p != "emergency":
		emergency = null
	event({"e": "phase_changed", "phase": p, "endsAt": phase_ends_at})
	push()

## Hace brillar una pista para guiar al jugador (como la marca de una misión fantasma).
func highlight(interactable_id: String, seconds := 600.0) -> void:
	var pos: Vector2 = spots[interactable_id]["position"] if spots.has(interactable_id) else Vector2.ZERO
	event({"e": "ghost_reveal", "interactableId": interactable_id, "position": Protocol.vec2_to(pos), "until": now_ms() + seconds * 1000.0})

## Marca un punto del mapa (como el ping de un fantasma).
func mark(position: Vector2, seconds := 30.0) -> void:
	event({"e": "ghost_ping", "by": "guia", "position": Protocol.vec2_to(position), "until": now_ms() + seconds * 1000.0})

func walk(bot: String, to: Vector2) -> void:
	targets[bot] = to

func bot_chat(bot: String, text: String) -> void:
	event({"e": "chat", "by": bot, "name": players[bot]["name"], "text": text, "at": int(now_ms())})

## Guion: Dani silencia a Eva en el pasillo y el jugador lo ve (testigo).
func scripted_silence(killer := "dani", victim := "eva") -> void:
	var v: Dictionary = players[victim]
	v["alive"] = false
	v["ghost"] = true
	bodies.append({"id": "body:%s" % victim, "playerId": victim, "position": Protocol.vec2_to(v["position"]), "reported": false, "kind": "dead"})
	event({"e": "witnessed", "killer": killer, "victim": victim, "at": int(now_ms())})
	push()

func body_position(victim := "eva") -> Vector2:
	for b in bodies:
		if b["playerId"] == victim:
			return Protocol.vec2_from(b["position"])
	return Vector2.ZERO

# ───── Intenciones ─────

func handle_intent(intent: Dictionary) -> void:
	var seq := int(intent.get("seq", 0))
	var reason := _apply(intent)
	if reason == "":
		_queue({"t": "ack", "seq": seq})
	else:
		_queue({"t": "rejected", "seq": seq, "reason": reason})

func _apply(i: Dictionary) -> String:
	match str(i.get("t", "")):
		Protocol.I_MOVE:
			if phase != "investigation" and phase != "briefing":
				return "wrong_phase"
			var to := Protocol.vec2_from(i.get("position", {}))
			players[ME]["position"] = to
			if channel != null and to.distance_to(channel["origin"]) > 10.0:
				_cancel_backup("moved")
			_dirty = true
			return ""
		Protocol.I_INTERACT:
			return _interact(str(i.get("interactableId", "")), str(i.get("evidenceInstanceId", "")))
		Protocol.I_CHANNEL_START:
			return _start_backup(str(i.get("evidenceInstanceId", "")), str(i.get("action", "")))
		Protocol.I_CHANNEL_CANCEL:
			if channel != null:
				_cancel_backup("cancelled")
			return ""
		Protocol.I_REPORT_BODY:
			return _report(str(i.get("bodyId", "")))
		Protocol.I_EMERGENCY_VOTE:
			return _emergency_vote(i.get("targetId"))
		Protocol.I_CHAT:
			var text := str(i.get("text", "")).strip_edges()
			if text.is_empty():
				return "empty_message"
			if not phase in ["emergency", "discussion", "voting"]:
				return "wrong_phase"
			event({"e": "chat", "by": ME, "name": players[ME]["name"], "text": text.left(200), "at": int(now_ms())})
			return ""
		Protocol.I_PRESENT:
			return _present(str(i.get("evidenceInstanceId", "")))
		Protocol.I_SKIP_TO_VOTING:
			if phase != "discussion":
				return "wrong_phase"
			set_phase("voting", 45.0)
			return ""
		Protocol.I_VOTE:
			return _vote(i.get("optionId"))
		Protocol.I_SILENCE, Protocol.I_ESCORT:
			return "no_power"
		Protocol.I_USE_ABILITY:
			return "no_ability"
		Protocol.I_CALL_MEETING:
			return "meeting_used"
		Protocol.I_GHOST_PING, Protocol.I_GHOST_TASK:
			return "not_ghost"
		Protocol.I_DROP, Protocol.I_DESTROY:
			return "wrong_phase"
		Protocol.I_LEAVE_ROOM, Protocol.I_READY, Protocol.I_CHOOSE_SKIN, Protocol.I_LEAVE_QUEUE:
			return ""
	return "tutorial"

func _interact(spot_id: String, instance_id: String) -> String:
	if phase != "investigation":
		return "wrong_phase"
	var spot: Dictionary = spots.get(spot_id, {})
	if spot.is_empty() or spot["contents"].is_empty():
		return "nothing_found"
	if my_position().distance_to(spot["position"]) > REACH:
		return "out_of_range"
	var view: Dictionary = spot["contents"][0]
	if instance_id != "" and instance_id != view["instanceId"]:
		return "nothing_found"
	if not view.get("pocketable", true):
		return "not_pocketable"
	spot["contents"].clear()
	inventory.append(view)
	event({"e": "evidence_collected", "by": ME, "interactableId": spot_id, "evidence": view})
	_check_objectives()
	push()
	collected.emit(spot_id)
	return ""

func _start_backup(instance_id: String, kind: String) -> String:
	if phase != "investigation":
		return "wrong_phase"
	if kind != "backup":
		return "action_not_allowed"
	if channel != null:
		return "already_channeling"
	for id in spots:
		for v in spots[id]["contents"]:
			if v["instanceId"] == instance_id:
				if my_position().distance_to(spots[id]["position"]) > REACH:
					return "out_of_range"
				var a: Dictionary = v.get("actions", [{}])[0]
				channel = {"instanceId": instance_id, "spot": id, "startedAt": now_ms(), "durationMs": int(a.get("seconds", 3)) * 1000,
					"origin": my_position(), "label": str(a.get("label", "Copiando…"))}
				event({"e": "channel_started", "by": ME, "channel": {"kind": "backup", "label": channel["label"], "startedAt": channel["startedAt"], "durationMs": channel["durationMs"]}})
				push()
				return ""
	return "nothing_found"

func _finish_backup() -> void:
	var c: Dictionary = channel
	channel = null
	var original: Dictionary = {}
	for v in spots.get(c["spot"], {}).get("contents", []):
		if v["instanceId"] == c["instanceId"]:
			original = v
	if original.is_empty():
		event({"e": "channel_finished", "by": ME, "ok": false, "reason": "nothing_found"})
		backup_finished.emit(false, "nothing_found")
		push()
		return
	_copy_seq += 1
	var copy := original.duplicate(true)
	copy["instanceId"] = "ev_copy_%d" % _copy_seq
	copy["isCopy"] = true
	copy["pocketable"] = true
	copy["actions"] = []
	inventory.append(copy)
	event({"e": "channel_finished", "by": ME, "ok": true})
	_check_objectives()
	push()
	backup_finished.emit(true, "")

func _cancel_backup(reason: String) -> void:
	channel = null
	event({"e": "channel_finished", "by": ME, "ok": false, "reason": reason})
	push()
	backup_finished.emit(false, reason)

func has_copy() -> bool:
	return inventory.any(func(v): return v.get("isCopy", false))

func _report(body_id: String) -> String:
	if phase != "investigation":
		return "wrong_phase"
	for b in bodies:
		if b["id"] == body_id and not b["reported"]:
			if my_position().distance_to(Protocol.vec2_from(b["position"])) > Protocol.REPORT_RANGE + 40.0:
				return "too_far"
			b["reported"] = true
			targets.clear()
			event({"e": "body_reported", "by": ME, "bodyId": body_id, "victim": b["playerId"]})
			emergency = {"calledBy": ME, "bodyId": body_id, "voted": [], "myVote": null, "endsAt": now_ms() + 75000.0, "remaining": 120000, "result": null}
			emergency_votes.clear()
			phase = "emergency"
			phase_ends_at = emergency["endsAt"]
			event({"e": "phase_changed", "phase": "emergency", "endsAt": phase_ends_at})
			push()
			reported.emit()
			return ""
	return "unknown_body"

func standing() -> Array:
	return order.filter(func(id): return players[id]["alive"] and not players[id]["ghost"])

func _emergency_vote(target) -> String:
	if phase != "emergency" or not emergency is Dictionary or emergency["result"] != null:
		return "wrong_phase"
	if target == null:
		emergency_votes.erase(ME)
	else:
		var t := str(target)
		if t != "skip" and not t in standing():
			return "unknown_target"
		emergency_votes[ME] = t
	emergency["myVote"] = emergency_votes.get(ME)
	emergency["voted"] = emergency_votes.keys()
	push()
	emergency_voted.emit(target)
	return ""

## Votos de los bots en la asamblea (Beto y Carla sospechan de Dani; Dani salta).
func bots_vote_emergency(votes := {"beto": "dani", "carla": "dani", "dani": "skip"}) -> void:
	for bot in votes:
		if bot in standing():
			emergency_votes[bot] = votes[bot]
	emergency["voted"] = emergency_votes.keys()
	push()

## Recuento: mayoría estricta de los votos emitidos (como el servidor real).
func resolve_emergency() -> String:
	if not emergency is Dictionary or emergency["result"] != null:
		return ""
	var tally := {}
	for v in emergency_votes.values():
		tally[v] = int(tally.get(v, 0)) + 1
	var top := ""
	var best := 0
	for k in tally:
		if tally[k] > best:
			best = tally[k]
			top = k
	var expelled := top if top != "skip" and best * 2 > emergency_votes.size() else ""
	emergency["result"] = {"expelled": expelled if expelled != "" else null, "tally": tally}
	event({"e": "emergency_result", "expelled": expelled if expelled != "" else null, "tally": tally})
	if expelled != "":
		players[expelled]["alive"] = false
		players[expelled]["ghost"] = true
	push()
	emergency_resolved.emit(expelled)
	return expelled

func end_investigation() -> void:
	set_phase("discussion", 120.0)

func _present(instance_id: String) -> String:
	if not phase in ["discussion", "voting"]:
		return "wrong_phase"
	var mine: Array = trial["deck"].filter(func(c): return c["presentedBy"] == ME)
	if mine.size() >= 2:
		return "present_limit"
	if trial["deck"].any(func(c): return c["instanceId"] == instance_id):
		return "already_presented"
	for v in inventory:
		if v["instanceId"] == instance_id:
			trial["deck"].append({"instanceId": instance_id, "presentedBy": ME, "at": int(now_ms()), "evidence": v.duplicate(true)})
			event({"e": "evidence_presented", "by": ME, "evidence": v})
			_check_objectives()
			push()
			presented.emit()
			return ""
	return "not_in_inventory"

## Los bots exponen sus pruebas (Beto las facturas, Carla la grabadora).
func bots_present() -> void:
	var cards := [["beto", "CLUE_FAKE_INVOICES"], ["carla", "CLUE_HIDDEN_RECORDER"]]
	for c in cards:
		if not c[0] in standing():
			continue
		var v := _view(c[1], "ev_bot_%s" % c[0], true, [])
		trial["deck"].append({"instanceId": v["instanceId"], "presentedBy": c[0], "at": int(now_ms()), "evidence": v})
		event({"e": "evidence_presented", "by": c[0], "evidence": v})
	push()

func _vote(option) -> String:
	if phase != "voting":
		return "wrong_phase"
	if option != null and not trial["options"].any(func(o): return o["id"] == str(option)):
		return "unknown_option"
	trial["myVote"] = option
	if option == null:
		trial["voted"].erase(ME)
	elif not ME in trial["voted"]:
		trial["voted"].append(ME)
		event({"e": "vote_cast", "by": ME})
	_check_objectives()
	push()
	voted.emit(option)
	return ""

## Los bots votan y se resuelve el juicio (pantalla de resultados de verdad).
func resolve_trial() -> void:
	var votes := {}
	if trial["myVote"] != null:
		votes[ME] = str(trial["myVote"])
	for bot in ["beto", "carla", "dani"]:
		if bot in standing():
			votes[bot] = "despedir_cto" if bot == "dani" else "despedir_ceo"
	var tally := {}
	for v in votes.values():
		tally[v] = int(tally.get(v, 0)) + 1
	var top := "despedir_ceo"
	for k in tally:
		if tally[k] > tally.get(top, 0):
			top = k
	var label := top
	for o in trial["options"]:
		if o["id"] == top:
			label = o["label"]
	var ceo_out := top == "despedir_ceo"
	var ending := {"id": "empleados", "title": "Justicia en NexusCore", "description": "Despedisteis al CEO: los avisos de cobro, las facturas y la grabadora contaban la misma historia."} if ceo_out \
		else {"id": "ceo_gana", "title": "El CEO se sale con la suya", "description": "El verdadero culpable sigue en su despacho. Las pruebas de la mesa lo señalaban."}
	var resolution_players := []
	var winners := []
	for id in order:
		var role := str(players[id]["role"])
		var team := _role_team(role)
		var won := (team != "culpables") == ceo_out
		if won:
			winners.append(id)
		resolution_players.append({"id": id, "name": players[id]["name"], "roleId": role, "roleName": _role_name(role), "team": team, "won": won,
			"objectives": objectives.duplicate(true) if id == ME else []})
	trial["tally"] = tally
	trial["resolution"] = {"verdict": {"optionId": top, "label": label, "tally": tally, "accused": ["dani"] if ceo_out else ["beto"]},
		"endings": [ending], "winners": winners, "players": resolution_players, "revealedEvidence": []}
	set_phase("results")
	event({"e": "game_over", "resolution": trial["resolution"]})
	push()
	resolved.emit()

func _check_objectives() -> void:
	objectives[0]["completed"] = inventory.any(func(v): return v["instanceId"] == "ev_debts") and has_copy()
	objectives[1]["completed"] = trial["deck"].any(func(c): return c["presentedBy"] == ME) and trial["myVote"] != null

# ───── Datos del caso ─────

func _load_scenario() -> void:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(SCENARIO)) if FileAccess.file_exists(SCENARIO) else null
	_scenario = parsed if parsed is Dictionary else {}

func _clue(id: String) -> Dictionary:
	for e in _scenario.get("evidence_spawns", []):
		if e.get("id") == id:
			return e
	return {}

func _clue_pos(id: String) -> Vector2:
	var p = _clue(id).get("position", {})
	if p is Array and p.size() >= 2:
		return Vector2(float(p[0]), float(p[1]))
	if p is Dictionary:
		return Vector2(float(p.get("x", 0)), float(p.get("y", 0)))
	return START

## EvidenceView completa de una pista del caso (la práctica no tiene candados).
func _view(clue_id: String, instance_id: String, pocketable: bool, actions: Array) -> Dictionary:
	var c := _clue(clue_id)
	return {"instanceId": instance_id, "visibility": "full", "definitionId": clue_id, "name": str(c.get("name", clue_id)),
		"description": str(c.get("description", "")), "tags": c.get("tags", []), "content": c.get("content", {}),
		"pocketable": pocketable, "medium": str(c.get("medium", "")), "actions": actions}

func _role(role_id: String) -> Dictionary:
	for r in _scenario.get("roles", []):
		if r.get("id") == role_id:
			return r
	return {}

func _role_name(role_id: String) -> String:
	return str(_role(role_id).get("name", role_id))

func _role_team(role_id: String) -> String:
	return str(_role(role_id).get("team", "inocentes"))
