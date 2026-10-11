class_name EvidenceSpot
extends InteractableEvidence
## Punto con como mucho una pista. Brilla si percibes algo en él.

@export var highlight_color := Color(1.0, 0.85, 0.3)

func get_prompt() -> String:
	if contents.is_empty():
		return prompt_text
	var e := contents[0]
	return "%s: %s" % [prompt_text, e.display_name if e.is_known else "algo extraño"]

func _on_contents_changed() -> void:
	modulate = highlight_color if has_perceivable_contents() else Color.WHITE
