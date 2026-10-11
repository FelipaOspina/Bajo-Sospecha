class_name EvidenceCard
extends PanelContainer
## Carta de prueba arrastrable (inventario) o de solo lectura (mesa pública).
## Clic = seleccionar, doble clic = ver en el EvidenceInspectionModal, arrastrar = exponer.

signal picked(evidence: EvidenceData)
signal inspect(evidence: EvidenceData)

var evidence: EvidenceData
var draggable := false
## Una sola línea con puntos suspensivos (huecos de la mesa).
var compact := false:
	set(v):
		compact = v
		if _title_label:
			_title_label.autowrap_mode = TextServer.AUTOWRAP_OFF if v else TextServer.AUTOWRAP_WORD_SMART
			_title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS if v else TextServer.OVERRUN_NO_TRIMMING
			_title_label.clip_text = v
var selected := false:
	set(v):
		selected = v
		_restyle()

var _subtitle: Label
var _title_label: Label

func setup(e: EvidenceData, can_drag: bool, subtitle := "") -> EvidenceCard:
	evidence = e
	draggable = can_drag
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_DRAG if can_drag else Control.CURSOR_POINTING_HAND
	tooltip_text = e.description
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(v)
	var title := Label.new()
	title.text = e.display_name
	_title_label = title
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.add_theme_font_override("font", UiPalette.heading_font())
	title.add_theme_color_override("font_color", UiPalette.TEXT)
	v.add_child(title)
	_subtitle = Label.new()
	_subtitle.text = subtitle if subtitle != "" else _kind_text(e)
	_subtitle.add_theme_color_override("font_color", UiPalette.TEXT_DIM)
	_subtitle.add_theme_font_size_override("font_size", 12)
	_subtitle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_subtitle)
	_restyle()
	return self

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if event.double_click:
			inspect.emit(evidence)
		else:
			picked.emit(evidence)

func _get_drag_data(_at: Vector2) -> Variant:
	if not draggable:
		return null
	var preview := Label.new()
	preview.text = evidence.display_name
	var holder := PanelContainer.new()
	holder.add_theme_stylebox_override("panel", UiPalette.glass_panel(8, 8))
	holder.add_child(preview)
	holder.modulate = Color(1, 1, 1, 0.85)
	set_drag_preview(holder)
	return TrialAssemblyManager.drag_data(evidence)

func _restyle() -> void:
	var s := UiPalette.glass_panel(8, 8)
	if selected:
		s.border_color = UiPalette.AMBER
		s.set_border_width_all(2)
	add_theme_stylebox_override("panel", s)

static func _kind_text(e: EvidenceData) -> String:
	match EvidenceFrames.frame_for(e):
		"terminal": return "Registro digital" + (" (copia)" if e.is_copy else "")
		"phone": return "Captura / móvil" + (" (copia)" if e.is_copy else "")
		"paper": return "Documento"
		_: return "Objeto"
