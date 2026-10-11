class_name EvidenceFrames
extends RefCounted
## Elige el marco del visor según el aspecto de la pista (medium) y sus etiquetas.
## "Digital / Crítica" → terminal, "Digital / Visual" o "Testimonial" → celular,
## "Documental / Físico" → papel, lo demás → objeto. Las reglas se prueban en orden;
## para un marco nuevo basta con registrar(id, script, palabras).

static var _scripts := {
	"terminal": TerminalFrame,
	"phone": PhoneFrame,
	"paper": PaperFrame,
	"item": ItemFrame,
}

static var _rules: Array = [
	{"frame": "terminal", "words": ["critica", "terminal", "codigo", "logs", "servidor", "consola"]},
	{"frame": "phone", "words": ["visual", "testimonial", "photo", "foto", "audio", "movil", "celular", "chat", "captura"]},
	{"frame": "paper", "words": ["documental", "documento", "papel", "text", "carta", "contrato"]},
	{"frame": "terminal", "words": ["digital"]},
]

static func register(frame: String, script: Script, words: Array, first := true) -> void:
	_scripts[frame] = script
	var rule := {"frame": frame, "words": words}
	if first:
		_rules.push_front(rule)
	else:
		_rules.append(rule)

static func frame_for(e: EvidenceData) -> String:
	if e == null:
		return "item"
	var words := []
	for part in e.medium.split("/", false):
		words.append(part.strip_edges().to_lower())
	for t in e.tags:
		var s := str(t)
		words.append(s.get_slice(":", 1) if s.begins_with("tipo:") else s)
	for rule in _rules:
		for w in rule["words"]:
			if w in words:
				return rule["frame"]
	return "item"

static func create(frame: String) -> EvidenceFrame:
	var script: Script = _scripts.get(frame, ItemFrame)
	return script.new()
