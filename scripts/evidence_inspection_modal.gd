extends CanvasLayer
class_name EvidenceInspectionModal

signal evidence_backed_up(clue_id: String)
signal evidence_deleted(clue_id: String)
signal modal_closed

@onready var modal_card: PanelContainer = $BackgroundDimmer/CenterContainer/ModalCard
@onready var title_label: Label = $BackgroundDimmer/CenterContainer/ModalCard/MarginContainer/VBoxContainer/HeaderBar/TitleLabel
@onready var type_tag_label: Label = $BackgroundDimmer/CenterContainer/ModalCard/MarginContainer/VBoxContainer/HeaderBar/TypeTagLabel
@onready var room_label: Label = $BackgroundDimmer/CenterContainer/ModalCard/MarginContainer/VBoxContainer/HeaderBar/RoomLabel

# Contenedores de contenido dinámico
@onready var terminal_view: PanelContainer = $BackgroundDimmer/CenterContainer/ModalCard/MarginContainer/VBoxContainer/ContentArea/TerminalView
@onready var terminal_text: RichTextLabel = $BackgroundDimmer/CenterContainer/ModalCard/MarginContainer/VBoxContainer/ContentArea/TerminalView/MarginContainer/TerminalText
@onready var crt_overlay: ColorRect = $BackgroundDimmer/CenterContainer/ModalCard/MarginContainer/VBoxContainer/ContentArea/TerminalView/CRTOverlay

@onready var document_view: PanelContainer = $BackgroundDimmer/CenterContainer/ModalCard/MarginContainer/VBoxContainer/ContentArea/DocumentView
@onready var document_text: RichTextLabel = $BackgroundDimmer/CenterContainer/ModalCard/MarginContainer/VBoxContainer/ContentArea/DocumentView/MarginContainer/DocumentText

@onready var generic_item_view: PanelContainer = $BackgroundDimmer/CenterContainer/ModalCard/MarginContainer/VBoxContainer/ContentArea/GenericItemView
@onready var generic_item_desc: Label = $BackgroundDimmer/CenterContainer/ModalCard/MarginContainer/VBoxContainer/ContentArea/GenericItemView/MarginContainer/VBox/ItemDescription

# Acciones y canalización
@onready var action_progress_bar: ProgressBar = $BackgroundDimmer/CenterContainer/ModalCard/MarginContainer/VBoxContainer/ActionFooter/ProgressBar
@onready var status_label: Label = $BackgroundDimmer/CenterContainer/ModalCard/MarginContainer/VBoxContainer/ActionFooter/StatusLabel
@onready var btn_backup: Button = $BackgroundDimmer/CenterContainer/ModalCard/MarginContainer/VBoxContainer/ActionFooter/HBoxContainer/BtnBackup
@onready var btn_delete: Button = $BackgroundDimmer/CenterContainer/ModalCard/MarginContainer/VBoxContainer/ActionFooter/HBoxContainer/BtnDelete
@onready var btn_close: Button = $BackgroundDimmer/CenterContainer/ModalCard/MarginContainer/VBoxContainer/HeaderBar/BtnClose

var current_clue: Dictionary = {}
var current_player_role: String = "ROLE_CTO"

var is_channeling: bool = false
var channeling_time: float = 0.0
var channeling_target_time: float = 0.0
var channeling_action_type: String = "" # "backup" o "delete"

func _ready() -> void:
	btn_close.pressed.connect(_on_close_pressed)
	btn_backup.pressed.connect(_on_backup_pressed)
	btn_delete.pressed.connect(_on_delete_pressed)
	action_progress_bar.hide()
	status_label.text = "Seleccione una acción para interactuar."

func _process(delta: float) -> void:
	if not is_channeling:
		return
	
	channeling_time += delta
	action_progress_bar.value = (channeling_time / channeling_target_time) * 100.0
	
	if channeling_time >= channeling_target_time:
		_finish_channeling()

func open_inspection(clue_data: Dictionary, player_role: String = "ROLE_CTO") -> void:
	current_clue = clue_data
	current_player_role = player_role
	is_channeling = false
	action_progress_bar.hide()
	
	title_label.text = clue_data.get("name", "Evidencia Desconocida")
	type_tag_label.text = "[ " + clue_data.get("type", "General") + " ]"
	room_label.text = "Ubicación: " + clue_data.get("room", "Oficina")
	
	# Ocultar vistas
	terminal_view.hide()
	document_view.hide()
	generic_item_view.hide()
	
	var clue_type: String = clue_data.get("type", "")
	var clue_id: String = clue_data.get("id", "")
	
	if "Digital" in clue_type or clue_id in ["CLUE_SERVER_LOGS", "CLUE_UNLOCKED_LAPTOP", "CLUE_SLACK_MESSAGE"]:
		terminal_view.show()
		_setup_terminal_view(clue_data)
	elif "Documental" in clue_type or clue_id == "CLUE_TORN_CONTRACT":
		document_view.show()
		_setup_document_view(clue_data)
	else:
		generic_item_view.show()
		_setup_generic_item_view(clue_data)
		
	_configure_action_buttons(clue_data)
	show()

func _setup_terminal_view(clue: Dictionary) -> void:
	var bbcode := "[color=#00e5ff][b]>>> SISTEMA NEXUSCORE v4.1 - CONEXIÓN ESTABLECIDA[/b][/color]\n\n"
	bbcode += "[color=#e2e8f0]" + clue.get("description", "") + "[/color]\n\n"
	
	var reqs = clue.get("interaction_requirements", {})
	if reqs.has("skill_check"):
		bbcode += "[color=#e5a93c]Skill Check Requerido: " + reqs["skill_check"] + "[/color]\n"
		
	terminal_text.text = bbcode

func _setup_document_view(clue: Dictionary) -> void:
	var bbcode := "[color=#8b4513][b]=== DOCUMENTO RECUPERADO DE PAPEL ===[/b][/color]\n\n"
	bbcode += "[color=#2c1810]" + clue.get("description", "") + "[/color]\n\n"
	bbcode += "[color=#b22222][i]* Fragmentos rasgados pero legibles al unirse *[/i][/color]"
	document_text.text = bbcode

func _setup_generic_item_view(clue: Dictionary) -> void:
	generic_item_desc.text = clue.get("description", "Objeto físico recolectable.")

func _configure_action_buttons(clue: Dictionary) -> void:
	var reqs: Dictionary = clue.get("interaction_requirements", {})
	
	# Botón Respaldar / Extraer
	var backup_action = reqs.get("backup_action")
	if backup_action != null and typeof(backup_action) == TYPE_DICTIONARY:
		var auth_roles = backup_action.get("authorized_roles", [])
		btn_backup.visible = current_player_role in auth_roles or auth_roles.is_empty()
		btn_backup.text = "💾 " + backup_action.get("action_name", "Respaldar Evidencia")
		btn_backup.disabled = false
	else:
		btn_backup.visible = reqs.get("can_be_pocketed", false)
		btn_backup.text = "🎒 Guardar en Inventario"
		btn_backup.disabled = false

	# Botón Purgar / Destruir
	var deletion_action = reqs.get("deletion_action")
	if deletion_action != null and typeof(deletion_action) == TYPE_DICTIONARY:
		var auth_roles = deletion_action.get("authorized_roles", [])
		btn_delete.visible = current_player_role in auth_roles
		btn_delete.text = "🔥 " + deletion_action.get("action_name", "Destruir Evidencia")
		btn_delete.disabled = false
	else:
		btn_delete.visible = false

func _on_backup_pressed() -> void:
	var reqs = current_clue.get("interaction_requirements", {})
	var backup = reqs.get("backup_action", {})
	var wait_time: float = 3.0
	if typeof(backup) == TYPE_DICTIONARY and backup.has("channeling_time_seconds"):
		wait_time = float(backup["channeling_time_seconds"])
	
	_start_channeling("backup", "Descargando evidencia a dispositivo seguro...", wait_time)

func _on_delete_pressed() -> void:
	var reqs = current_clue.get("interaction_requirements", {})
	var deletion = reqs.get("deletion_action", {})
	var wait_time: float = 4.0
	if typeof(deletion) == TYPE_DICTIONARY and deletion.has("channeling_time_seconds"):
		wait_time = float(deletion["channeling_time_seconds"])
		
	_start_channeling("delete", "Destruyendo evidencia de forma permanente...", wait_time)

func _start_channeling(action_type: String, message: String, duration: float) -> void:
	is_channeling = true
	channeling_action_type = action_type
	channeling_target_time = duration
	channeling_time = 0.0
	
	btn_backup.disabled = true
	btn_delete.disabled = true
	action_progress_bar.value = 0.0
	action_progress_bar.show()
	status_label.text = message

func _finish_channeling() -> void:
	is_channeling = false
	action_progress_bar.hide()
	btn_backup.disabled = false
	btn_delete.disabled = false
	
	var clue_id: String = current_clue.get("id", "")
	if channeling_action_type == "backup":
		status_label.text = "✅ Evidencia respaldada con éxito en tu inventario."
		evidence_backed_up.emit(clue_id)
	elif channeling_action_type == "delete":
		status_label.text = "🚨 Evidencia purgada/destruida permanentemente."
		evidence_deleted.emit(clue_id)

func _on_close_pressed() -> void:
	is_channeling = false
	hide()
	modal_closed.emit()
