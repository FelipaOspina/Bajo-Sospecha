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
