extends VBoxContainer
## Lista de pruebas del jugador local con acciones según su rol.

@export var evidence_system_path: NodePath
@export var role_manager_path: NodePath

@onready var _evidence: EvidenceSystem = get_node(evidence_system_path)
@onready var _roles: RoleManager = get_node(role_manager_path)

func _ready() -> void:
	_evidence.inventory.changed.connect(_rebuild)  # InventoryManager
	_evidence.action_failed.connect(func(reason): print("[UI] ", reason))

func _rebuild() -> void:
	for c in get_children():
		c.queue_free()
	for e in _evidence.inventory.items():
		var row := HBoxContainer.new()
		var label := Label.new()
		label.text = e.display_name
		label.tooltip_text = e.description
		row.add_child(label)
		row.add_child(_button("Soltar", _evidence.drop.bind(e.instance_id)))
		row.add_child(_button("Mostrar", _evidence.present.bind(e.instance_id)))
		if _roles.can_destroy(e.tags):
			row.add_child(_button("Destruir", _evidence.destroy.bind(e.instance_id)))
		add_child(row)

func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	return b
