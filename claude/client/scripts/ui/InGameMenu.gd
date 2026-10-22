class_name InGameMenu
extends CanvasLayer
## Menú en partida:
##  - Opciones de juego (Reanudar, Salir de la partida, Cerrar servidor, Salir del juego).
##  - Mochila con evidencias recolectadas hasta el momento e inspección directa.
##  - Estudio forense con barras de sospecha / culpables y temporizador en vivo.
##  - Mapa táctico con la distribución de oficinas (OCMAS / salas del Piso 14).

signal back_to_menu_requested
signal quit_game_requested
signal close_server_requested
signal inspect_evidence_requested(evidence: EvidenceData)

@export var inventory: InventoryManager
@export var evidence_modal: EvidenceInspectionModal
@export var players: PlayerSpawner

var _dimmer: ColorRect
var _card: PanelContainer
var _timer_label: Label
var _location_label: Label

var _tab_bar_container: HBoxContainer
var _tabs_container: MarginContainer
var _tab_views: Array[Control] = []
var _tab_buttons: Array[Button] = []
var _current_tab: int = 0

# Pestaña 0: Opciones
var _session_info_label: Label

# Pestaña 1: Mochila
var _backpack_count_label: Label
var _backpack_items_box: VBoxContainer

# Pestaña 2: Estudio de Culpables
var _suspects_box: VBoxContainer
var _call_meeting_btn: Button
var _selected_accused: String = "ROLE_CEO"

# Pestaña 3: Mapa
var _map_canvas: Control

func _ready() -> void:
	layer = 8
	hide()
	_build_ui()
	if inventory:
		inventory.changed.connect(_refresh_backpack)
	GameState.snapshot_applied.connect(func(_s): _refresh_session_info())

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var key: int = event.keycode
		var in_active_game := GameState.phase() in ["briefing", "investigation", "discussion", "voting"]

		# Tecla ESCAPE: Abrir/Cerrar menú principal de opciones
		if key == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			if visible:
				close()
			elif in_active_game:
				open(0)
			return

		# Tecla M: Abrir/Cerrar pestaña del MAPA (Piso 14 / OCMAS)
		elif key == KEY_M:
			get_viewport().set_input_as_handled()
			if visible and _current_tab == 3:
				close()
			elif in_active_game:
				open(3)
			return

		# Tecla I o B: Abrir/Cerrar pestaña de MOCHILA / INVENTARIO de evidencias
		elif key == KEY_I or key == KEY_B:
			get_viewport().set_input_as_handled()
			if visible and _current_tab == 1:
				close()
			elif in_active_game:
				open(1)
			return

		# Tecla TAB: Abrir/Cerrar pestaña de ESTUDIO DE CULPABLES
		elif key == KEY_TAB:
			get_viewport().set_input_as_handled()
			if visible and _current_tab == 2:
				close()
			elif in_active_game:
				open(2)
			return

	if event.is_action_pressed("ui_cancel"):
		# Botón Atrás en Android o controlador gamepad
		if visible:
			get_viewport().set_input_as_handled()
			close()
		elif GameState.phase() in ["briefing", "investigation", "discussion", "voting"]:
			get_viewport().set_input_as_handled()
			open()

func _process(_delta: float) -> void:
	if not visible:
		return
	_update_timer()
	_update_current_location()

func open(target_tab: int = -1) -> void:
	if target_tab >= 0 and target_tab < _tab_views.size():
		_switch_tab(target_tab)
	_refresh_all()
	show()

func close() -> void:
	hide()

func toggle() -> void:
	if visible:
		close()
	else:
		open()

# ─────────────────────────────────────────────────────────────
# CONSTRUCCIÓN DE LA INTERFAZ (UI NATIVA NEO-NOIR CORPORATE)
# ─────────────────────────────────────────────────────────────

func _build_ui() -> void:
	# 1. Fondo oscurecedor
	_dimmer = ColorRect.new()
	_dimmer.color = Color(0.04, 0.06, 0.10, 0.88)
	_dimmer.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_dimmer)

	# 2. Contenedor central (Card)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	_card = PanelContainer.new()
	_card.custom_minimum_size = Vector2(880, 580)
	var card_style := StyleBoxFlat.new()
	card_style.bg_color = Color(0.07, 0.10, 0.17, 0.96)
	card_style.border_color = Color(UiPalette.AMBER, 0.45)
	card_style.set_border_width_all(1)
	card_style.set_corner_radius_all(16)
	card_style.shadow_color = Color(0, 0, 0, 0.6)
	card_style.shadow_size = 12
	card_style.content_margin_left = 24
	card_style.content_margin_right = 24
	card_style.content_margin_top = 20
	card_style.content_margin_bottom = 20
	_card.add_theme_stylebox_override("panel", card_style)
	center.add_child(_card)

	var main_layout := VBoxContainer.new()
	main_layout.add_theme_constant_override("separation", 14)
	_card.add_child(main_layout)

	# ── Header Bar ──
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 16)
	main_layout.add_child(header)

	var title_box := VBoxContainer.new()
	title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title_box)

	var main_title := Label.new()
	main_title.text = "DOSSIER EJECUTIVO · PISO 14"
	main_title.add_theme_font_override("font", UiPalette.heading_font())
	main_title.add_theme_font_size_override("font_size", 20)
	main_title.add_theme_color_override("font_color", UiPalette.AMBER)
	title_box.add_child(main_title)

	_location_label = Label.new()
	_location_label.text = "📍 Ubicación: Consultando planos…"
	_location_label.add_theme_font_override("font", UiPalette.body_font())
	_location_label.add_theme_font_size_override("font_size", 13)
	_location_label.add_theme_color_override("font_color", UiPalette.TEXT_DIM)
	title_box.add_child(_location_label)

	# Temporizador en cabecera
	var timer_badge := PanelContainer.new()
	var badge_style := StyleBoxFlat.new()
	badge_style.bg_color = Color(0.04, 0.08, 0.14, 0.8)
	badge_style.border_color = Color(UiPalette.AMBER, 0.4)
	badge_style.set_border_width_all(1)
	badge_style.set_corner_radius_all(8)
	badge_style.content_margin_left = 12
	badge_style.content_margin_right = 12
	badge_style.content_margin_top = 6
	badge_style.content_margin_bottom = 6
	timer_badge.add_theme_stylebox_override("panel", badge_style)
	header.add_child(timer_badge)

	var timer_layout := HBoxContainer.new()
	timer_layout.add_theme_constant_override("separation", 6)
	timer_badge.add_child(timer_layout)

	var timer_icon := Label.new()
	timer_icon.text = "⏱️"
	timer_layout.add_child(timer_icon)

	_timer_label = Label.new()
	_timer_label.text = "--:--"
	_timer_label.add_theme_font_override("font", UiPalette.mono_font())
	_timer_label.add_theme_font_size_override("font_size", 16)
	_timer_label.add_theme_color_override("font_color", UiPalette.AMBER)
	timer_layout.add_child(_timer_label)

	# Botón Cerrar (X)
	var close_btn := Button.new()
	close_btn.text = " ✕ "
	close_btn.custom_minimum_size = Vector2(36, 36)
	close_btn.focus_mode = Control.FOCUS_NONE
	UiPalette.style_button(close_btn, UiPalette.TEXT_DIM)
	close_btn.pressed.connect(close)
	header.add_child(close_btn)

	# ── Barra de Pestañas ──
	_tab_bar_container = HBoxContainer.new()
	_tab_bar_container.add_theme_constant_override("separation", 10)
	main_layout.add_child(_tab_bar_container)

	var tab_names := [
		"⚙️ Opciones",
		"🎒 Mochila & Pruebas",
		"⚖️ Estudio de Culpables",
		"🗺️ Mapa Piso 14 (OCMAS)"
	]

	for i in tab_names.size():
		var btn := Button.new()
		btn.text = tab_names[i]
		btn.focus_mode = Control.FOCUS_NONE
		btn.custom_minimum_size = Vector2(160, 38)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.pressed.connect(_switch_tab.bind(i))
		_tab_bar_container.add_child(btn)
		_tab_buttons.append(btn)

	# Separador sutil
	var rule := ColorRect.new()
	rule.custom_minimum_size = Vector2(0, 1)
	rule.color = Color(1, 1, 1, 0.12)
	main_layout.add_child(rule)

	# ── Contenedor de Vistas de Pestaña ──
	_tabs_container = MarginContainer.new()
	_tabs_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_layout.add_child(_tabs_container)

	_tab_views.append(_build_tab_options())
	_tab_views.append(_build_tab_backpack())
	_tab_views.append(_build_tab_suspects())
	_tab_views.append(_build_tab_map())

	for v in _tab_views:
		_tabs_container.add_child(v)

	_switch_tab(0)

# ─────────────────────────────────────────────────────────────
# PESTAÑA 0: OPCIONES DE PARTIDA
# ─────────────────────────────────────────────────────────────

func _build_tab_options() -> Control:
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 16)
	scroll.add_child(box)

	var desc := Label.new()
	desc.text = "Opciones operativas y control de sesión de la partida actual."
	desc.add_theme_color_override("font_color", UiPalette.TEXT_DIM)
	box.add_child(desc)

	_session_info_label = Label.new()
	_session_info_label.text = "Cargando información de la sesión…"
	_session_info_label.add_theme_font_override("font", UiPalette.mono_font())
	_session_info_label.add_theme_font_size_override("font_size", 13)
	_session_info_label.add_theme_color_override("font_color", UiPalette.CYAN)
	box.add_child(_session_info_label)

	var btn_grid := VBoxContainer.new()
	btn_grid.add_theme_constant_override("separation", 12)
	btn_grid.custom_minimum_size = Vector2(360, 0)
	btn_grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(btn_grid)

	# 1. Reanudar
	var resume_btn := Button.new()
	resume_btn.text = "▶️  Reanudar Partida"
	resume_btn.custom_minimum_size = Vector2(340, 44)
	UiPalette.style_button(resume_btn, UiPalette.CYAN)
	resume_btn.pressed.connect(close)
	btn_grid.add_child(resume_btn)

	# 2. Salir de la partida
	var leave_btn := Button.new()
	leave_btn.text = "🚪  Salir de la Partida (Volver al Menú)"
	leave_btn.custom_minimum_size = Vector2(340, 44)
	UiPalette.style_button(leave_btn, UiPalette.AMBER)
	leave_btn.pressed.connect(func():
		close()
		back_to_menu_requested.emit()
	)
	btn_grid.add_child(leave_btn)

	# 3. Cerrar servidor / Desconectar sala
	var close_server_btn := Button.new()
	close_server_btn.text = "🛑  Cerrar Servidor / Desconectar Sala"
	close_server_btn.custom_minimum_size = Vector2(340, 44)
	UiPalette.style_button(close_server_btn, UiPalette.CRIMSON)
	close_server_btn.pressed.connect(func():
		close()
		close_server_requested.emit()
	)
	btn_grid.add_child(close_server_btn)

	# 4. Salir por completo del juego
	var quit_app_btn := Button.new()
	quit_app_btn.text = "✕  Salir por Completo del Juego"
	quit_app_btn.custom_minimum_size = Vector2(340, 44)
	UiPalette.style_button(quit_app_btn, Color(0.4, 0.4, 0.5))
	quit_app_btn.pressed.connect(func():
		quit_game_requested.emit()
		get_tree().quit()
	)
	btn_grid.add_child(quit_app_btn)

	return scroll

# ─────────────────────────────────────────────────────────────
# PESTAÑA 1: MOCHILA Y EVIDENCIAS
# ─────────────────────────────────────────────────────────────

func _build_tab_backpack() -> Control:
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 12)
	scroll.add_child(box)

	_backpack_count_label = Label.new()
	_backpack_count_label.text = "Mochila: 0 pruebas recolectadas"
	_backpack_count_label.add_theme_color_override("font_color", UiPalette.AMBER)
	_backpack_count_label.add_theme_font_override("font", UiPalette.heading_font())
	_backpack_count_label.add_theme_font_size_override("font_size", 16)
	box.add_child(_backpack_count_label)

	_backpack_items_box = VBoxContainer.new()
	_backpack_items_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_backpack_items_box.add_theme_constant_override("separation", 10)
	box.add_child(_backpack_items_box)

	return scroll

func _refresh_backpack() -> void:
	if not _backpack_items_box:
		return
	for c in _backpack_items_box.get_children():
		c.queue_free()

	var items: Array[EvidenceData] = inventory.items() if inventory else []
	_backpack_count_label.text = "Mochila táctica: %d evidencia(s) recolectada(s)" % items.size()

	if items.is_empty():
		var empty_card := PanelContainer.new()
		empty_card.add_theme_stylebox_override("panel", UiPalette.glass_panel(8, 16))
		var empty_lbl := Label.new()
		empty_lbl.text = "🎒 Tu mochila está vacía por el momento.\n\nExplora las terminales de servidores, laptops abiertas, archivadores de reciclaje y muebles de descanso.\nPulsa la tecla [E] cerca de cualquier evidencia para examinarla, descargar un dump forense o guardarla."
		empty_lbl.add_theme_color_override("font_color", UiPalette.TEXT_DIM)
		empty_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty_card.add_child(empty_lbl)
		_backpack_items_box.add_child(empty_card)
		return

	for item in items:
		var card := PanelContainer.new()
		var card_style := StyleBoxFlat.new()
		card_style.bg_color = Color(0.09, 0.13, 0.22, 0.9)
		card_style.border_color = Color(UiPalette.CYAN if item.is_copy else UiPalette.AMBER, 0.5)
		card_style.set_border_width_all(1)
		card_style.set_corner_radius_all(10)
		card_style.content_margin_left = 14
		card_style.content_margin_right = 14
		card_style.content_margin_top = 10
		card_style.content_margin_bottom = 10
		card.add_theme_stylebox_override("panel", card_style)

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)
		card.add_child(row)

		var icon_lbl := Label.new()
		if item.has_tag("audio") or (item.content is Dictionary and item.content.has("audio")):
			icon_lbl.text = "🎙️"
		elif item.has_tag("photo") or (item.content is Dictionary and item.content.has("image")):
			icon_lbl.text = "📷"
		elif item.has_tag("physical") or item.has_tag("item") or item.has_tag("key"):
			icon_lbl.text = "🔐"
		else:
			icon_lbl.text = "💾"
		icon_lbl.add_theme_font_size_override("font_size", 22)
		row.add_child(icon_lbl)

		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(info)

		var name_lbl := Label.new()
		name_lbl.text = item.display_name + (" [COPIA FORENSE]" if item.is_copy else " [ORIGINAL]")
		name_lbl.add_theme_font_override("font", UiPalette.bold_font())
		name_lbl.add_theme_color_override("font_color", Color.WHITE)
		info.add_child(name_lbl)

		var desc_lbl := Label.new()
		desc_lbl.text = item.description
		desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc_lbl.add_theme_font_size_override("font_size", 13)
		desc_lbl.add_theme_color_override("font_color", UiPalette.TEXT_DIM)
		info.add_child(desc_lbl)

		var inspect_btn := Button.new()
		inspect_btn.text = "🔍 Inspeccionar"
		inspect_btn.custom_minimum_size = Vector2(130, 36)
		UiPalette.style_button(inspect_btn, UiPalette.CYAN)
		inspect_btn.pressed.connect(func():
			close()
			if evidence_modal:
				evidence_modal.open_evidence(item)
			inspect_evidence_requested.emit(item)
		)
		row.add_child(inspect_btn)

		_backpack_items_box.add_child(card)

# ─────────────────────────────────────────────────────────────
# PESTAÑA 2: ESTUDIO FORENSE CON BARRAS DE CULPABILIDAD
# ─────────────────────────────────────────────────────────────

func _build_tab_suspects() -> Control:
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 14)
	scroll.add_child(box)

	var header_lbl := Label.new()
	header_lbl.text = "ESTUDIO DEDUCTIVO · NIVEL DE SOSPECHA Y PROBABILIDAD DE CULPABILIDAD"
	header_lbl.add_theme_font_override("font", UiPalette.heading_font())
	header_lbl.add_theme_color_override("font_color", UiPalette.AMBER)
	header_lbl.add_theme_font_size_override("font_size", 15)
	box.add_child(header_lbl)

	var intro := Label.new()
	intro.text = "Analiza los testimonios, móviles económicos y evidencias digitales para asignar tus sospechas antes de la Asamblea Extraordinaria."
	intro.add_theme_color_override("font_color", UiPalette.TEXT_DIM)
	intro.add_theme_font_size_override("font_size", 13)
	box.add_child(intro)

	# Botón de emergencia: abre la asamblea de EMERGENCIA (lo envía SocialHUD).
	var call_meeting_btn := Button.new()
	call_meeting_btn.name = "CallMeetingButton"
	call_meeting_btn.text = SocialHUD.MEETING_TEXT
	call_meeting_btn.custom_minimum_size = Vector2(0, 44)
	UiPalette.style_button(call_meeting_btn, UiPalette.CRIMSON)
	call_meeting_btn.pressed.connect(func() -> void:
		EventBus.emergency_meeting_requested.emit()
		close()
	)
	box.add_child(call_meeting_btn)
	_call_meeting_btn = call_meeting_btn

	_suspects_box = VBoxContainer.new()
	_suspects_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_suspects_box.add_theme_constant_override("separation", 12)
	box.add_child(_suspects_box)

	_build_suspect_cards()

	return scroll

func _build_suspect_cards() -> void:
	if not _suspects_box:
		return
	for c in _suspects_box.get_children():
		c.queue_free()

	var suspects := [
		{
			"id": "ROLE_CEO",
			"name": "El CEO (Fundador)",
			"role_desc": "Director Ejecutivo y responsable de finanzas corporativas.",
			"motive": "Deudas personales de 1.6M USD vencidas en BitCasino. Retiró fondos a través de Apex Growth LLC.",
			"evidence": "MAC address de Presidencia registrada en los logs SSH; facturas falsas firmadas sin autorización.",
			"base_suspicion": 82,
			"color": UiPalette.CRIMSON
		},
		{
			"id": "ROLE_CTO",
			"name": "El CTO (Director Técnico)",
			"role_desc": "Arquitecto de infraestructura y custodio del clúster de IA.",
			"motive": "Su llave SSH ejecutó el comando a las 02:00 AM, pero su pipeline estuvo en pausa.",
			"evidence": "Registro de torniquetes demuestra que su tarjeta física fue clonada con hardware Flipper Zero.",
			"base_suspicion": 24,
			"color": UiPalette.CYAN
		},
		{
			"id": "ROLE_LEAKER",
			"name": "El Filtrador / Lead Dev (Whistleblower)",
			"role_desc": "Desarrollador líder con acceso a canales confidenciales de Slack.",
			"motive": "Oportunismo financiero: posee grabadora oculta y capturas incriminatorias para extorsionar o filtrar.",
			"evidence": "Grabación de audio bajo la mesa de juntas; conversaciones de Slack sobre culpar la pipeline del CTO.",
			"base_suspicion": 54,
			"color": Color("#B48CFF")
		},
		{
			"id": "ROLE_INVESTOR",
			"name": "El Inversor Principal (Vanguard Capital)",
			"role_desc": "Auditor y socio gestor de la Ronda Serie B de $15M.",
			"motive": "Rescate estricto del capital: no firmará el cheque hasta recuperar las llaves criptográficas.",
			"evidence": "Auditoría bancaria externa con la marca de tiempo exacta del desvío.",
			"base_suspicion": 12,
			"color": UiPalette.AMBER
		}
	]

	for s in suspects:
		var panel := PanelContainer.new()
		var p_style := StyleBoxFlat.new()
		p_style.bg_color = Color(0.08, 0.12, 0.19, 0.9)
		p_style.border_color = Color(s["color"], 0.6 if _selected_accused == s["id"] else 0.25)
		p_style.set_border_width_all(2 if _selected_accused == s["id"] else 1)
		p_style.set_corner_radius_all(10)
		p_style.content_margin_left = 16
		p_style.content_margin_right = 16
		p_style.content_margin_top = 12
		p_style.content_margin_bottom = 12
		panel.add_theme_stylebox_override("panel", p_style)

		var layout := VBoxContainer.new()
		layout.add_theme_constant_override("separation", 6)
		panel.add_child(layout)

		var top_row := HBoxContainer.new()
		layout.add_child(top_row)

		var name_lbl := Label.new()
		name_lbl.text = s["name"]
		name_lbl.add_theme_font_override("font", UiPalette.heading_font())
		name_lbl.add_theme_font_size_override("font_size", 16)
		name_lbl.add_theme_color_override("font_color", s["color"])
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		top_row.add_child(name_lbl)

		if _selected_accused == s["id"]:
			var tag := Label.new()
			tag.text = "[ 🎯 SOSPECHOSO PRINCIPAL ]"
			tag.add_theme_font_override("font", UiPalette.bold_font())
			tag.add_theme_color_override("font_color", UiPalette.AMBER)
			tag.add_theme_font_size_override("font_size", 12)
			top_row.add_child(tag)

		var role_lbl := Label.new()
		role_lbl.text = s["role_desc"]
		role_lbl.add_theme_font_size_override("font_size", 12)
		role_lbl.add_theme_color_override("font_color", UiPalette.TEXT_DIM)
		layout.add_child(role_lbl)

		# Barra de sospecha
		var bar_row := HBoxContainer.new()
		bar_row.add_theme_constant_override("separation", 10)
		layout.add_child(bar_row)

		var bar_lbl := Label.new()
		bar_lbl.text = "Nivel de Sospecha: %d%%" % s["base_suspicion"]
		bar_lbl.custom_minimum_size = Vector2(160, 0)
		bar_lbl.add_theme_font_override("font", UiPalette.mono_font())
		bar_lbl.add_theme_font_size_override("font_size", 13)
		bar_lbl.add_theme_color_override("font_color", Color.WHITE)
		bar_row.add_child(bar_lbl)

		var bar := ProgressBar.new()
		bar.value = float(s["base_suspicion"])
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(0, 14)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var bar_bg := StyleBoxFlat.new()
		bar_bg.bg_color = Color(0.04, 0.06, 0.10, 0.8)
		bar_bg.set_corner_radius_all(7)
		var bar_fg := StyleBoxFlat.new()
		bar_fg.bg_color = s["color"]
		bar_fg.set_corner_radius_all(7)
		bar.add_theme_stylebox_override("background", bar_bg)
		bar.add_theme_stylebox_override("fill", bar_fg)
		bar_row.add_child(bar)

		# Detalles de evidencias
		var detail_box := VBoxContainer.new()
		detail_box.add_theme_constant_override("separation", 2)
		layout.add_child(detail_box)

		var motive_lbl := Label.new()
		motive_lbl.text = "• Móvil: " + s["motive"]
		motive_lbl.add_theme_font_size_override("font_size", 12)
		motive_lbl.add_theme_color_override("font_color", UiPalette.TEXT)
		motive_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		detail_box.add_child(motive_lbl)

		var ev_lbl := Label.new()
		ev_lbl.text = "• Pistas vinculadas: " + s["evidence"]
		ev_lbl.add_theme_font_size_override("font_size", 12)
		ev_lbl.add_theme_color_override("font_color", UiPalette.TEXT_DIM)
		ev_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		detail_box.add_child(ev_lbl)

		# Botón para fijar acusación
		var act_btn := Button.new()
		act_btn.text = "🎯 Marcar como Acusación Principal" if _selected_accused != s["id"] else "✓ Acusación Fijada para la Asamblea"
		act_btn.disabled = (_selected_accused == s["id"])
		act_btn.custom_minimum_size = Vector2(240, 32)
		act_btn.size_flags_horizontal = Control.SIZE_SHRINK_END
		UiPalette.style_button(act_btn, s["color"] if _selected_accused != s["id"] else UiPalette.AMBER)
		act_btn.pressed.connect(func():
			_selected_accused = s["id"]
			_build_suspect_cards()
		)
		layout.add_child(act_btn)

		_suspects_box.add_child(panel)

# ─────────────────────────────────────────────────────────────
# PESTAÑA 3: MAPA DE OFICINAS (OCMAS / DISTRIBUCIÓN PISO 14)
# ─────────────────────────────────────────────────────────────

func _build_tab_map() -> Control:
	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 8)

	var map_info := Label.new()
	map_info.text = "DISTRIBUCIÓN ARQUITECTÓNICA DE OFICINAS Y SALAS (OCMAS) · PISO 14"
	map_info.add_theme_font_override("font", UiPalette.heading_font())
	map_info.add_theme_color_override("font_color", UiPalette.AMBER)
	map_info.add_theme_font_size_override("font_size", 14)
	root.add_child(map_info)

	var map_panel := PanelContainer.new()
	map_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var map_style := StyleBoxFlat.new()
	map_style.bg_color = Color(0.04, 0.06, 0.10, 0.95)
	map_style.border_color = Color(UiPalette.CYAN, 0.35)
	map_style.set_border_width_all(1)
	map_style.set_corner_radius_all(12)
	map_panel.add_theme_stylebox_override("panel", map_style)
	root.add_child(map_panel)

	_map_canvas = Control.new()
	_map_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_map_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_map_canvas.draw.connect(_draw_office_map)
	map_panel.add_child(_map_canvas)

	var legend := HBoxContainer.new()
	legend.add_theme_constant_override("separation", 16)
	root.add_child(legend)

	var leg1 := Label.new()
	leg1.text = "📍 Tu Posición Actual"
	leg1.add_theme_font_size_override("font_size", 12)
	leg1.add_theme_color_override("font_color", UiPalette.CYAN)
	legend.add_child(leg1)

	var leg2 := Label.new()
	leg2.text = "⚠️ Zonas de Trampas / Sabotajes conocidos"
	leg2.add_theme_font_size_override("font_size", 12)
	leg2.add_theme_color_override("font_color", UiPalette.AMBER)
	legend.add_child(leg2)

	return root

func _draw_office_map() -> void:
	if not _map_canvas:
		return
	var canvas_sz := _map_canvas.size
	if canvas_sz.x < 100 or canvas_sz.y < 100:
		return

	# Bounds del OfficeLayout: Rect2(-640, -400, 3280, 1720)
	var bounds: Rect2 = OfficeLayout.BOUNDS
	var margin := 20.0
	var avail_w := canvas_sz.x - margin * 2.0
	var avail_h := canvas_sz.y - margin * 2.0
	var scale_factor := minf(avail_w / bounds.size.x, avail_h / bounds.size.y)

	var to_canvas := func(world_pt: Vector2) -> Vector2:
		var rel := world_pt - bounds.position
		return Vector2(margin, margin) + rel * scale_factor

	# 1. Dibujar cada sala
	for room in OfficeLayout.rooms():
		var r_rect: Rect2 = room["rect"]
		var c_pos: Vector2 = to_canvas.call(r_rect.position)
		var c_size: Vector2 = r_rect.size * scale_factor
		var room_rect := Rect2(c_pos, c_size)

		var room_col := Color(room.get("light", "#2563EB"))
		room_col.a = 0.22
		_map_canvas.draw_rect(room_rect, room_col, true)
		_map_canvas.draw_rect(room_rect, Color(room.get("light", "#60A5FA"), 0.5), false, 1.5)

		# Nombre de la sala
		if room.get("label", true) and r_rect.size.x > 300:
			var r_name: String = str(room.get("name", ""))
			var text_pos: Vector2 = c_pos + Vector2(6, 16)
			_map_canvas.draw_string(UiPalette.body_font(), text_pos, r_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color.WHITE)

	# 2. Dibujar muros
	for wall in OfficeLayout.walls():
		var a: Vector2 = to_canvas.call(wall["a"])
		var b: Vector2 = to_canvas.call(wall["b"])
		var wall_col := Color(1, 1, 1, 0.4)
		if wall.get("kind") == "glass":
			wall_col = Color(UiPalette.CYAN, 0.45)
		_map_canvas.draw_line(a, b, wall_col, 2.0)

	# 3. Dibujar ubicación del jugador local
	var me := players.get_player(GameState.local_player_id()) if players else null
	if me:
		var me_canvas: Vector2 = to_canvas.call(me.global_position)
		_map_canvas.draw_circle(me_canvas, 7.0, Color(UiPalette.CYAN, 0.4))
		_map_canvas.draw_circle(me_canvas, 4.5, UiPalette.CYAN)
		_map_canvas.draw_string(UiPalette.bold_font(), me_canvas + Vector2(10, 4), "📍 TÚ", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UiPalette.CYAN)

	# 4. Iconos de trampas conocidas en salas
	var traps_pos := [
		Vector2(460, 120),    # Servidores
		Vector2(1300, 780),   # Cafetería
		Vector2(1080, 60),    # CEO
		Vector2(-400, -150),  # CCTV
	]
	for tp in traps_pos:
		var cp: Vector2 = to_canvas.call(tp)
		_map_canvas.draw_circle(cp, 3.5, UiPalette.AMBER)

# ─────────────────────────────────────────────────────────────
# MÉTODOS DE ACTUALIZACIÓN Y NAVEGACIÓN
# ─────────────────────────────────────────────────────────────

func _switch_tab(index: int) -> void:
	_current_tab = index
	for i in _tab_views.size():
		_tab_views[i].visible = (i == index)
		if i == index:
			UiPalette.style_button(_tab_buttons[i], UiPalette.AMBER)
		else:
			UiPalette.style_button(_tab_buttons[i], Color(0.2, 0.3, 0.4, 0.6))

	if index == 1:
		_refresh_backpack()
	elif index == 2:
		_build_suspect_cards()
	elif index == 3 and _map_canvas:
		_map_canvas.queue_redraw()

func _refresh_all() -> void:
	_refresh_session_info()
	_refresh_backpack()
	_update_timer()
	_update_current_location()
	if _map_canvas:
		_map_canvas.queue_redraw()

func _refresh_session_info() -> void:
	SocialHUD.apply_meeting_button(_call_meeting_btn)
	if not _session_info_label:
		return
	var room_code := Network.room_code
	if room_code.is_empty():
		room_code = "PARTIDA_LOCAL"
	var me_id := GameState.local_player_id()
	var my_role := str(GameState.my_private_state().get("roleId", "Asignado en asamblea"))
	var phase_str := GameState.phase()
	_session_info_label.text = "Código de Sala: %s  |  Jugador ID: %s  |  Fase Actual: %s\nRol confidencial: %s" % [
		room_code, me_id, phase_str.to_upper(), my_role
	]

func _update_timer() -> void:
	if not _timer_label:
		return
	var ends = GameState.snapshot.get("phaseEndsAt")
	if ends == null:
		_timer_label.text = "--:--"
		return
	var left := maxi(0, int((float(ends) - Network.server_time_ms()) / 1000.0))
	_timer_label.text = "%02d:%02d" % [left / 60, left % 60]
	_timer_label.add_theme_color_override("font_color", UiPalette.CRIMSON if left <= 30 else UiPalette.AMBER)

func _update_current_location() -> void:
	if not _location_label:
		return
	var me := players.get_player(GameState.local_player_id()) if players else null
	if me:
		var room_info: Dictionary = OfficeLayout.room_at(me.global_position)
		var r_name: String = str(room_info.get("name", "Pasillos de NexusCore"))
		_location_label.text = "📍 Ubicación actual: " + r_name
	else:
		_location_label.text = "📍 Ubicación actual: Oficinas Centrales (Piso 14)"
