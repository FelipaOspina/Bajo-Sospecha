class_name ChannelPresenter
extends Node
## Pinta una FloatingProgressBar sobre cada personaje que esté canalizando una
## acción, según el estado del servidor (que solo nos la manda si estamos cerca).
## La barra del jugador local vigila además el movimiento para cancelar al momento.

@export var players: PlayerSpawner
@export var evidence_system: EvidenceSystem

var _bars := {}  # player_id -> {bar, startedAt}

func _ready() -> void:
	GameState.snapshot_applied.connect(_sync)
	EventBus.channel_finished.connect(_on_finished)

## Pulsar una tecla de movimiento durante tu canalización la cancela al momento
## (sin esperar a que el personaje llegue a moverse) y avisa al servidor.
func _unhandled_input(event: InputEvent) -> void:
	var bar := local_bar()
	if bar == null or bar.finished or local_move_tolerance() > 0.0:
		return   # con Calma (panda) se puede mover un poco: lo vigila la barra por distancia
	for action in Player.MOVE_ACTIONS:
		if event.is_action_pressed(action):
			bar.cancel_channeling("moved")   # → interrupted → _on_local_interrupted → servidor
			return

## Píxeles que tu animal puede moverse sin cortar su acción (pasiva Calma del panda).
func local_move_tolerance() -> float:
	return float(AnimalAbilities.passive_effect(Abilities.skin_id, "moveTolerance", 0.0))

func local_bar() -> FloatingProgressBar:
	return bar_for(GameState.local_player_id())

func bar_for(player_id: String) -> FloatingProgressBar:
	var entry = _bars.get(player_id)
	return entry["bar"] if entry and is_instance_valid(entry["bar"]) else null

func _sync(s: Dictionary) -> void:
	var active := {}
	for p in s.get("players", []):
		var c = p.get("channel")
		if not c is Dictionary:
			continue
		active[p["id"]] = true
		var entry = _bars.get(p["id"])
		if entry and is_instance_valid(entry["bar"]) and entry["startedAt"] == c["startedAt"]:
			continue
		var node := players.get_player(p["id"]) if players else null
		if node == null:
			continue
		var elapsed := maxf(0.0, (Network.server_time_ms() - float(c["startedAt"])) / 1000.0)
		var bar := node.attach_progress_bar(c["label"], float(c["durationMs"]) / 1000.0, elapsed, str(c.get("kind", "backup")))
		bar.auto_complete = false
		bar.watch_movement = node.is_local
		if node.is_local:
			bar.move_tolerance = maxf(bar.move_tolerance, local_move_tolerance() - 2.0)
			bar.interrupted.connect(_on_local_interrupted)
		_bars[p["id"]] = {"bar": bar, "startedAt": c["startedAt"]}
	# Canalizaciones que ya no vemos (se alejó, o el servidor la cerró sin evento para nosotros).
	for id in _bars.keys():
		if not active.has(id):
			var bar := bar_for(id)
			if bar and not bar.finished:
				bar.queue_free()
			_bars.erase(id)

func _on_finished(by: String, ok: bool, reason: String) -> void:
	var bar := bar_for(by)
	if bar:
		bar.server_finished(ok, reason)
	_bars.erase(by)

func _on_local_interrupted(reason: String) -> void:
	if reason == "moved" and evidence_system:
		evidence_system.cancel_channel()
