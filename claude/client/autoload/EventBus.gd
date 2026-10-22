extends Node
## Bus de señales global del cliente. Desacopla red, dominio y UI:
## la UI nunca llama a Network directamente; escucha aquí.

signal connected_to_server(player_id: String)
signal disconnected_from_server(reason: String)

signal phase_changed(phase: String, ends_at_ms: int)
signal role_revealed(role_id: String)

signal evidence_collected(by: String, interactable_id: String, evidence: Dictionary)
signal evidence_dropped(by: String, interactable_id: String)
signal evidence_destroyed(by: String)
signal evidence_presented(by: String, evidence: Dictionary)
signal inventory_changed(items: Array)

signal evidence_inspect_requested(interactable: Node)
## Un modal (visor de pistas, votación...) toma o suelta el control del teclado.
signal ui_modal_changed(open: bool)

signal interactable_focused(interactable: Node)
signal interactable_unfocused(interactable: Node)

signal channel_started(by: String, channel: Dictionary)
signal channel_finished(by: String, ok: bool, reason: String)

signal intent_rejected(seq: int, reason: String)
signal game_over(resolution: Dictionary)

## Mensaje del chat de la sala (lobby).
signal chat_received(by: String, author: String, text: String, at_ms: int)
## Alguien usó la activa de su animal (las secretas solo te llegan si eres tú).
signal ability_used(by: String, ability_id: String, ends_at_ms: int, marks: Array, affected: Array)

# ── Silenciar al testigo ──
## Te silenciaron (victim = tú; killer vacío: no sabes quién) o silenciaste a alguien
## (killer = tú). knocked: noqueo de 30 s (until, hora del servidor); si no, fantasma.
signal silenced(killer: String, victim: String, knocked: bool, until_ms: int)
## Viste a killer silenciar a victim (solo a los vivos con línea de vista).
signal witnessed(killer: String, victim: String, at_ms: int)
signal body_reported(by: String, body_id: String, victim: String)
## Alguien pulsó el botón de emergencia (call_meeting).
signal meeting_called(by: String)
## La UI (HUD o menú en partida) pide pulsar el botón de emergencia; lo envía SocialHUD.
signal emergency_meeting_requested
signal emergency_result(expelled: String, tally: Dictionary)
## La escolta frenó un ataque contra target (al asesino, al Jefe de Seguridad y al protegido).
signal escort_blocked(target: String)
## Un fantasma de tu equipo marca una posición (hasta until_ms, hora del servidor).
signal ghost_ping(by: String, position: Vector2, until_ms: int)
## Una misión fantasma hace brillar una pista para los vivos.
signal ghost_reveal(interactable_id: String, position: Vector2, until_ms: int)
