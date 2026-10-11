class_name EvidenceContainer
extends InteractableEvidence
## Contenedor (armario, cajón, baúl). El visor permite pasar de una pieza a otra.

func get_prompt() -> String:
	if contents.is_empty():
		return "%s (vacío)" % prompt_text
	return "Registrar (%d)" % contents.size()
