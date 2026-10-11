extends Node2D

@onready var modal: EvidenceInspectionModal = $EvidenceInspectionModal
@onready var role_option: OptionButton = $UI/RoleSelectorPanel/MarginContainer/VBoxContainer/RoleOption
@onready var buttons_container: VBoxContainer = $UI/CluesPanel/MarginContainer/VBoxContainer/CluesButtonsVBox
@onready var log_label: Label = $UI/StatusPanel/MarginContainer/LogLabel

var case_data: Dictionary = {}
var current_role: String = "ROLE_CTO"

func _ready() -> void:
	_load_case_json()
	_setup_role_selector()
	_build_evidence_buttons()
	
	modal.evidence_backed_up.connect(_on_evidence_backed_up)
	modal.evidence_deleted.connect(_on_evidence_deleted)

func _load_case_json() -> void:
	var path := "res://caso_fraude_tech_startup.json"
	if not FileAccess.file_exists(path):
		log_label.text = "Error: no se encontró " + path
		return
		
	var file := FileAccess.open(path, FileAccess.READ)
	var text := file.get_as_text()
	var json = JSON.new()
	var error = json.parse(text)
	if error == OK:
		case_data = json.data
		log_label.text = "Caso cargado: " + case_data.get("title", "")
	else:
		log_label.text = "Error al parsear JSON: " + json.get_error_message()

func _setup_role_selector() -> void:
	role_option.clear()
	var roles = case_data.get("roles", [])
	for i in range(roles.size()):
		var r = roles[i]
		role_option.add_item(r.get("display_name", ""), i)
		role_option.set_item_metadata(i, r.get("role_id", ""))
		
	role_option.item_selected.connect(_on_role_selected)
	if roles.size() > 0:
		current_role = roles[0].get("role_id", "ROLE_CEO")

func _on_role_selected(index: int) -> void:
	current_role = role_option.get_item_metadata(index)
	log_label.text = "Rol activo cambiado a: " + role_option.get_item_text(index)

func _build_evidence_buttons() -> void:
	for child in buttons_container.get_children():
		child.queue_free()
		
	var clues = case_data.get("clues_and_evidence", [])
	for clue in clues:
		var btn = Button.new()
		btn.custom_minimum_size = Vector2(0, 38)
		btn.text = "🔍 Inspeccionar: " + clue.get("name", "") + " (" + clue.get("room", "") + ")"
		btn.pressed.connect(func(): _open_clue(clue))
		buttons_container.add_child(btn)

func _open_clue(clue: Dictionary) -> void:
	log_label.text = "Inspeccionando: " + clue.get("name", "")
	modal.open_inspection(clue, current_role)

func _on_evidence_backed_up(clue_id: String) -> void:
	log_label.text = "¡Evento capturado! Jugador (" + current_role + ") respaldó la evidencia: " + clue_id

func _on_evidence_deleted(clue_id: String) -> void:
	log_label.text = "¡Alerta de sabotaje! Jugador (" + current_role + ") destruyó la evidencia: " + clue_id
