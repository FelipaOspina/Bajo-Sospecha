class_name EvidenceInspectionModal
extends CanvasLayer
## Modal de inspección de pistas (tecla E sobre un objeto, o una prueba del inventario/mesa).
##
## Bisel y contenido intercambiables: el tipo de pista (medium "digital/critica",
## "documental/fisico"...) elige la vista con EvidenceFrames y esa vista se inyecta en
## el ContentSlot: SmartphoneView, TerminalView, PaperDocumentView o ItemView.
## DeviceBezelTexture (NinePatchRect detrás de la vista, en el ContentSlot) usa
## res://assets/ui/bezels/<bisel>.png (generados con tools/generate_bezels.py); si faltara
## la textura, cada vista dibuja su propio bisel con estilos.
##
## Footer: BackupEvidenceBtn (backup_action, cian) y DeleteEvidenceBtn (deletion_action,
## rojo) solo aparecen si TU rol puede hacer esa acción (lo decide el servidor).
## Al pulsarlos se pide la acción canalizada y el modal se cierra cuando el servidor
## la acepta: la FloatingProgressBar toma el relevo sobre el personaje.

signal closed
signal action_requested(evidence: EvidenceData, kind: String)

const STATUS_ICONS := {"phone": "5G ▮▮▮", "terminal": ">_", "paper": "§", "item": "◆"}

@export var evidence_system: EvidenceSystem
@export var inventory: InventoryManager

var source: InteractableEvidence   # objeto del mapa, o null si se abre una prueba suelta
var player_role := ""              # rol de quien inspecciona (para pistas leídas del JSON del caso)
var index := 0
var frame: EvidenceFrame

var _items: Array[EvidenceData] = []
var _awaiting := ""          # instance_id que se ha pedido guardar
var _awaiting_action := ""   # kind de la acción canalizada pedida

@onready var _dimmer: ColorRect = $BackgroundDimmer
@onready var _card: MarginContainer = %ModalCard
@onready var _bezel: NinePatchRect = %DeviceBezelTexture
@onready var _status_icon: Label = %StatusIcon
@onready var _title: Label = %TitleLabel
@onready var _copy_badge: Label = %CopyBadge
@onready var _close: Button = %CloseButton
@onready var _content_slot: MarginContainer = %ContentSlot
@onready var _lock: Label = %LockLabel
@onready var _status: Label = %StatusLabel
@onready var _backup_btn: Button = %BackupEvidenceBtn
@onready var _delete_btn: Button = %DeleteEvidenceBtn
@onready var _prev: Button = %PrevButton
@onready var _next: Button = %NextButton
@onready var _save: Button = %SaveButton

func _ready() -> void:
	hide()
	_style()
	_prev.pressed.connect(func() -> void: show_page(index - 1))
	_next.pressed.connect(func() -> void: show_page(index + 1))
	_save.pressed.connect(save_current)
	_close.pressed.connect(close)
	_backup_btn.pressed.connect(start_action.bind("backup"))
	_delete_btn.pressed.connect(start_action.bind("delete"))
	EventBus.evidence_inspect_requested.connect(open)
	EventBus.channel_started.connect(_on_channel_started)
	if evidence_system:
		evidence_system.action_failed.connect(_on_action_failed)
	if inventory:
		inventory.item_added.connect(_on_item_added)

func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()

# ───── API ─────

## Tecla E sobre un objeto del mapa (InteractableEvidence.interact → EventBus): inspecciona
## lo que contiene con el rol local. Se queda escuchando el objeto por si cambia.
func open(target: InteractableEvidence) -> void:
	setup_inspection(target.contents, str(GameState.my_private_state().get("roleId", "")))
	source = target
	source.contents_changed.connect(_on_source_changed)
	_refresh()

## Abre una prueba suelta (inventario o mesa del juicio), sin "Guardar".
func open_evidence(e: EvidenceData) -> void:
	setup_inspection(e, player_role)

## Prepara y abre el modal. clue_data puede ser:
##  - EvidenceData o un EvidenceView del servidor: sus acciones ya vienen filtradas para ti;
##  - una pista del JSON del caso (clues_and_evidence[], con interaction_requirements):
##    los botones salen de deletion_action / backup_action según authorized_roles y player_role;
##  - un Array de cualquiera de los anteriores (un objeto con varias piezas).
## El servidor vuelve a validar el permiso al pulsar.
func setup_inspection(clue_data: Variant, role_id: String = "") -> void:
	_detach_source()
	player_role = role_id
	var list: Array = clue_data if clue_data is Array else [clue_data]
	_items.clear()
	for c in list:
		var e := _to_evidence(c, role_id)
		if e:
			_items.append(e)
	_show_modal()

static func _to_evidence(c: Variant, role_id: String) -> EvidenceData:
	if c is EvidenceData:
		return c
	if c is Dictionary:
		if c.has("instanceId"):
			return EvidenceData.from_view(c)
		if c.has("interaction_requirements") or c.has("id"):
			return EvidenceData.from_case_clue(c, role_id)
	return null

func close() -> void:
	if not visible:
		return
	if frame:
		frame.stop()
	_detach_source()
	hide()
	EventBus.ui_modal_changed.emit(false)
	closed.emit()

func current() -> EvidenceData:
	if _items.is_empty():
		return null
	return _items[clampi(index, 0, _items.size() - 1)]

func show_page(i: int) -> void:
	index = clampi(i, 0, maxi(_items.size() - 1, 0))
	_refresh()

func frame_id() -> String:
	return frame.frame_id() if frame else ""

func save_current() -> void:
	var e := current()
	if e == null or source == null or not e.can_collect() or evidence_system == null:
		return
	_awaiting = e.instance_id
	_say("Guardando...")
	_save.disabled = true
	evidence_system.collect(source.interactable_id, e.instance_id)

## Botón del footer: "backup" (backup_action) o "delete" (deletion_action).
func start_action(kind: String) -> void:
	var e := current()
	if e == null or evidence_system == null or _awaiting_action != "":
		return
	var action := _action(e, kind)
	if action.is_empty():
		return
	_awaiting_action = kind
	_say("%s..." % action["label"])
	_set_actions_disabled(true)
	action_requested.emit(e, kind)
	evidence_system.start_channel(e.instance_id, kind)

## Botones de acción visibles (los que tu rol puede usar sobre la pista actual).
func action_buttons() -> Array[Button]:
	var out: Array[Button] = []
	for b in [_backup_btn, _delete_btn]:
		if b.visible:
			out.append(b)
	return out

# ───── Pintado ─────

func _show_modal() -> void:
	index = 0
	_awaiting = ""
	_awaiting_action = ""
	_say("")
	_refresh()
	show()
	_card.pivot_offset = _card.size / 2.0
	_card.scale = Vector2(0.94, 0.94)
	_card.modulate.a = 0.0
	var tw := create_tween().set_parallel().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_card, "scale", Vector2.ONE, 0.18)
	tw.tween_property(_card, "modulate:a", 1.0, 0.12)
	EventBus.ui_modal_changed.emit(true)

func _refresh() -> void:
	var e := current()
	var count := _items.size()
	_prev.visible = count > 1
	_next.visible = count > 1
	_prev.disabled = index <= 0
	_next.disabled = index >= count - 1
	_save.visible = source != null

	_use_frame(EvidenceFrames.frame_for(e))
	frame.show_evidence(e)
	_copy_badge.visible = e != null and e.is_copy

	if e == null:
		_title.text = source.prompt_text if source else ""
		frame.body.text = "No encuentras nada útil aquí."
		_lock.text = ""
		_lock.visible = false
		_save.disabled = true
		_set_action_button(_backup_btn, {})
		_set_action_button(_delete_btn, {})
		return

	_title.text = e.display_name if e.is_known else "Algo que no logras distinguir"
	_lock.text = e.lock_message()
	_lock.visible = _lock.text != ""
	_save.disabled = not e.can_collect() or _awaiting == e.instance_id
	_set_action_button(_backup_btn, _action(e, "backup"))
	_set_action_button(_delete_btn, _action(e, "delete"))
	_fit_card.call_deferred()

## Al cambiar de vista, un texto con autowrap mide muy alto en su primer frame (aún sin
## ancho) y los Control no encogen solos: se recoloca el centro para que vuelva a ajustarse.
func _fit_card() -> void:
	var center := _card.get_parent() as Control
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_card.reset_size()

## Cambia la vista del ContentSlot y el bisel según el tipo de pista.
func _use_frame(id: String) -> void:
	if frame == null or frame.frame_id() != id:
		if frame:
			frame.stop()
			_content_slot.remove_child(frame)
			frame.queue_free()
		frame = EvidenceFrames.create(id)
		frame.name = frame.view_name()
		_content_slot.add_child(frame)
	_status_icon.text = STATUS_ICONS.get(id, "◆")
	_content_slot.add_theme_constant_override("margin_left", frame.slot_side_margin())
	_content_slot.add_theme_constant_override("margin_right", frame.slot_side_margin())
	var path := frame.bezel_path()
	var has_texture := path != "" and ResourceLoader.exists(path)
	_bezel.visible = has_texture
	_bezel.texture = load(path) if has_texture else null
	if has_texture:
		var m := frame.bezel_patch()
		_bezel.patch_margin_left = m
		_bezel.patch_margin_top = m
		_bezel.patch_margin_right = m
		_bezel.patch_margin_bottom = m
		var mode := NinePatchRect.AXIS_STRETCH_MODE_TILE_FIT if frame.bezel_tiles() else NinePatchRect.AXIS_STRETCH_MODE_STRETCH
		_bezel.axis_stretch_horizontal = mode
		_bezel.axis_stretch_vertical = mode
	frame.set_texture_bezel(has_texture)

func _set_action_button(b: Button, action: Dictionary) -> void:
	b.visible = not action.is_empty()
	if b.visible:
		b.text = "%s  (%d s)" % [action["label"], int(action["seconds"])]
		b.disabled = _awaiting_action != ""

func _set_actions_disabled(v: bool) -> void:
	for b in action_buttons():
		b.disabled = v

static func _action(e: EvidenceData, kind: String) -> Dictionary:
	for a in e.actions:
		if a["kind"] == kind:
			return a
	return {}

# ───── Respuestas ─────

func _on_source_changed(contents: Array) -> void:
	if not visible:
		return
	_items.assign(contents)
	if _items.is_empty() and _awaiting == "":
		_say("Alguien se la ha llevado.")
	index = clampi(index, 0, maxi(_items.size() - 1, 0))
	_refresh()

func _on_item_added(e: EvidenceData) -> void:
	if visible and e.instance_id == _awaiting:
		_awaiting = ""
		_say("Guardada en tu inventario.")
		if _items.is_empty():
			close()
		else:
			_refresh()

func _on_channel_started(by: String, _channel: Dictionary) -> void:
	if visible and _awaiting_action != "" and by == GameState.local_player_id():
		_awaiting_action = ""
		close()  # la barra flotante toma el relevo

func _on_action_failed(reason: String) -> void:
	if not visible:
		return
	if _awaiting != "" or _awaiting_action != "":
		_awaiting = ""
		_awaiting_action = ""
		_say(reason)
		_refresh()

## Mensaje de estado bajo el contenido; oculto si está vacío para no dejar huecos.
func _say(text: String) -> void:
	_status.text = text
	_status.visible = text != ""

func _detach_source() -> void:
	if source and source.contents_changed.is_connected(_on_source_changed):
		source.contents_changed.disconnect(_on_source_changed)
	source = null

# ───── Estilo (paleta UiPalette) ─────

func _style() -> void:
	_dimmer.color = UiPalette.DIMMER
	_title.add_theme_font_override("font", UiPalette.heading_font())
	_title.add_theme_color_override("font_color", UiPalette.TEXT)
	_status_icon.add_theme_font_override("font", UiPalette.mono_font())
	_status_icon.add_theme_color_override("font_color", UiPalette.AMBER)
	_copy_badge.add_theme_color_override("font_color", UiPalette.CYAN)
	_lock.add_theme_color_override("font_color", UiPalette.AMBER)
	_status.add_theme_color_override("font_color", UiPalette.CYAN)
	(%ModalPanel as PanelContainer).add_theme_stylebox_override("panel", UiPalette.flat(UiPalette.NAVY, Color(UiPalette.AMBER, 0.27), 1, 10, 0))
	UiPalette.style_button(_backup_btn, UiPalette.CYAN)
	UiPalette.style_button(_delete_btn, UiPalette.CRIMSON)
	for b in [_prev, _next, _save, _close]:
		UiPalette.style_button(b, UiPalette.AMBER)
