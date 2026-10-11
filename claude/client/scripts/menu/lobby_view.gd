class_name LobbyView
extends Control
## Pestaña "Sala" del menú: la sala de espera en la oficina de noche.
##  - Tarjeta del caso arriba: título, sala (código + Copiar + Compartir), plazas y estado.
##    Sin sala, la misma tarjeta ofrece Partida rápida, Crear sala privada y Unirse con código.
##  - En el centro, los animales de los jugadores alrededor de la mesa (LobbyStage).
##  - A la derecha, la lista de jugadores (corona del anfitrión, punto verde) y el tipo de caso.
##  - Abajo a la izquierda, el chat de la sala; abajo a la derecha, Opciones e INICIAR.
## INICIAR sin sala entra en la cola pública; en la sala marca "listo" (la partida empieza
## cuando todos lo están; las salas públicas además arrancan solas tras la cuenta atrás).
## Todas las acciones pasan por Account; los nombres nunca llevan el rol.

signal toast_requested(text: String)
signal tab_requested(tab: String)

const YELLOW := Color("#FFD21F")
const GREEN := Color("#4ADE80")
const MODE_IDLE := "idle"
const MODE_QUEUE := "queue"
const MODE_ROOM := "room"
const MAX_CHAT_LINES := 60
enum Option { COPY_CODE, SHARE, CHANGE_ANIMAL, SETTINGS, LEAVE }

## Título y escenario del caso que carga el cliente (Main los rellena).
@export var case_title := "Fraude y Chantaje en la Startup Tecnológica"
@export var scenario_id := "nexuscore_fraude"

@onready var stage: LobbyStage = %Stage
@onready var room_card: PanelContainer = %RoomCard
@onready var title_label: Label = %CaseTitle
@onready var room_label: Label = %RoomLabel
@onready var count_label: Label = %CountLabel
@onready var chips: HBoxContainer = %Chips
@onready var status_chip: PanelContainer = %StatusChip
@onready var status_chip_label: Label = %StatusChipLabel
@onready var code_box: VBoxContainer = %CodeBox
@onready var code_label: Label = %CodeLabel
@onready var copy_button: Button = %CopyButton
@onready var share_button: Button = %ShareButton
@onready var play_box: VBoxContainer = %PlayBox
@onready var quick_button: Button = %QuickMatchButton
@onready var create_button: Button = %CreateRoomButton
@onready var code_input: LineEdit = %CodeInput
@onready var join_button: Button = %JoinButton
@onready var queue_box: VBoxContainer = %QueueBox
@onready var queue_label: Label = %QueueLabel
@onready var cancel_queue_button: Button = %CancelQueueButton
@onready var players_title: Label = %PlayersTitle
@onready var player_list: VBoxContainer = %PlayerList
@onready var case_list: VBoxContainer = %CaseList
@onready var chat_scroll: ScrollContainer = %ChatScroll
@onready var chat_lines: VBoxContainer = %ChatLines
@onready var chat_input: LineEdit = %ChatInput
@onready var chat_send: Button = %ChatSend
@onready var options_button: Button = %OptionsButton
@onready var start_button: Button = %StartButton
@onready var start_label: Label = %StartLabel
@onready var start_icon: MenuIcon = %StartIcon
@onready var status_label: Label = %StatusLabel

var mode := MODE_IDLE
var options_menu: PopupMenu
var _list_signature := ""
var _known_players := {}   # id -> nombre, para avisar en el chat de quién entra y sale
var _room_code := ""

func _ready() -> void:
	_style()
	_build_case_list()
	options_menu = PopupMenu.new()
	options_menu.name = "OptionsMenu"
	add_child(options_menu)
	options_menu.id_pressed.connect(_on_option)

	start_button.pressed.connect(_on_start_pressed)
	options_button.pressed.connect(_open_options)
	quick_button.pressed.connect(func() -> void: Account.quick_match())
	create_button.pressed.connect(func() -> void: Account.create_room())
	join_button.pressed.connect(_join_with_code)
	code_input.text_submitted.connect(func(_t: String) -> void: _join_with_code())
	code_input.text_changed.connect(_on_code_typed)
	cancel_queue_button.pressed.connect(func() -> void: Account.cancel_queue())
	copy_button.pressed.connect(copy_code)
	share_button.pressed.connect(share_invite)
	chat_send.pressed.connect(func() -> void: send_chat(chat_input.text))
	chat_input.text_submitted.connect(send_chat)

	GameState.snapshot_applied.connect(func(_s: Dictionary) -> void: refresh())
	Account.profile_updated.connect(func(_p: Dictionary) -> void: refresh())
	Account.queue_changed.connect(func(_p: int, _w: int, _m: int) -> void: refresh())
	Account.online_changed.connect(func(_o: bool) -> void: refresh())
	EventBus.chat_received.connect(_on_chat)
	refresh()

func current_mode() -> String:
	if GameState.in_room():
		return MODE_ROOM
	if Account.in_queue():
		return MODE_QUEUE
	return MODE_IDLE

## Jugadores de la sala en orden de llegada: [{id, name, skinId, look, ready, connected}].
func room_players() -> Array:
	return GameState.players().map(func(p): return {
		"id": str(p.get("id", "")), "name": str(p.get("name", "?")),
		"skinId": str(p.get("skinId", SkinCatalog.fallback_for(str(p.get("id", ""))))),
		"look": p.get("look") if p.get("look") is Dictionary else {},
		"ready": bool(p.get("ready", false)), "connected": bool(p.get("connected", true))})

func my_ready() -> bool:
	for p in GameState.players():
		if p.get("id") == GameState.local_player_id():
			return bool(p.get("ready", false))
	return false

## Segundos que faltan para que la sala pública arranque sola (-1 sin cuenta atrás).
func seconds_to_start() -> int:
	var starts_at = GameState.lobby().get("startsAt")
	if starts_at == null:
		return -1
	return maxi(0, ceili((float(starts_at) - Network.server_time_ms()) / 1000.0))

func refresh() -> void:
	var previous := mode
	mode = current_mode()
	if mode != MODE_ROOM and previous == MODE_ROOM:
		_clear_chat()
	var lobby := GameState.lobby()
	var players: Array = room_players() if mode == MODE_ROOM else [_me_entry()]
	var max_players := int(lobby.get("maxPlayers", Account.match_size)) if mode == MODE_ROOM else Account.match_size

	# Tarjeta del caso.
	title_label.text = case_title.to_upper()
	code_box.visible = mode == MODE_ROOM
	play_box.visible = mode == MODE_IDLE
	queue_box.visible = mode == MODE_QUEUE
	var public := str(lobby.get("visibility", "")) == "public"
	match mode:
		MODE_ROOM:
			_room_code = str(lobby.get("code", Network.room_code))
			code_label.text = _room_code
			room_label.text = "Sala %s (%s)" % [_room_code, "Pública" if public else "Privada"]
		MODE_QUEUE:
			room_label.text = "Partida pública · buscando jugadores"
			queue_label.text = "En cola: %d/%d jugadores" % [Account.queue_waiting, Account.match_size]
		_:
			room_label.text = "Sin sala · elige cómo jugar"
	count_label.text = "%d/%d" % [players.size(), max_players]
	_set_chips([_case_type_name(), "Pública" if public else ("Privada" if mode == MODE_ROOM else "Modo libre")])
	_sync_status_chip()

	# Escenario central y lista de jugadores.
	var local_id := GameState.local_player_id() if mode == MODE_ROOM else "local"
	stage.set_players(players, str(lobby.get("hostId", "")) if mode == MODE_ROOM else "", max_players, local_id, mode != MODE_ROOM)
	_rebuild_player_list(players, str(lobby.get("hostId", "")), max_players, local_id)
	if mode == MODE_ROOM:
		_announce_changes(players)

	# Chat e INICIAR.
	chat_input.editable = mode == MODE_ROOM
	chat_send.disabled = mode != MODE_ROOM
	chat_input.placeholder_text = "Escribe un mensaje…" if mode == MODE_ROOM else "Entra en una sala para chatear"
	quick_button.disabled = not Account.online
	create_button.disabled = not Account.online
	join_button.disabled = not Account.online or Account.normalize_code(code_input.text).length() != 6
	_sync_start_button()

func _process(_delta: float) -> void:
	if mode == MODE_ROOM and GameState.lobby().get("startsAt") != null:
		_sync_status_chip()
		_sync_start_button()

# ───── Acciones ─────

func _on_start_pressed() -> void:
	match current_mode():
		MODE_IDLE:
			Account.quick_match()
		MODE_QUEUE:
			Account.cancel_queue()
		MODE_ROOM:
			Account.set_ready(not my_ready())

func _join_with_code() -> void:
	var code := Account.normalize_code(code_input.text)
	if code.length() != 6:
		toast_requested.emit("El código de sala tiene 6 caracteres.")
		return
	Account.join_room(code)

func _on_code_typed(text: String) -> void:
	var clean := Account.normalize_code(text).left(6)
	if clean != text:
		var caret := code_input.caret_column
		code_input.text = clean
		code_input.caret_column = mini(caret, clean.length())
	join_button.disabled = not Account.online or clean.length() != 6

func copy_code() -> void:
	if _room_code.is_empty():
		return
	DisplayServer.clipboard_set(_room_code)
	toast_requested.emit("Código %s copiado." % _room_code)

func invite_text() -> String:
	return "¡Únete a mi sala en Juego de Roles! Caso: %s. Código de sala: %s" % [case_title, _room_code]

func share_invite() -> void:
	if _room_code.is_empty():
		return
	DisplayServer.clipboard_set(invite_text())
	toast_requested.emit("Invitación copiada: pégala en tu chat o red social.")

func send_chat(text: String) -> void:
	if Account.send_chat(text) >= 0:
		chat_input.clear()

func _open_options() -> void:
	options_menu.clear()
	var in_room := current_mode() == MODE_ROOM
	options_menu.add_item("Copiar código de sala", Option.COPY_CODE)
	options_menu.set_item_disabled(options_menu.get_item_index(Option.COPY_CODE), not in_room)
	options_menu.add_item("Compartir invitación", Option.SHARE)
	options_menu.set_item_disabled(options_menu.get_item_index(Option.SHARE), not in_room)
	options_menu.add_item("Cambiar de animal", Option.CHANGE_ANIMAL)
	options_menu.add_item("Configuración", Option.SETTINGS)
	options_menu.add_separator()
	options_menu.add_item("Salir de la cola" if current_mode() == MODE_QUEUE else "Salir de la sala", Option.LEAVE)
	options_menu.set_item_disabled(options_menu.get_item_index(Option.LEAVE), current_mode() == MODE_IDLE)
	var r := options_button.get_global_rect()
	options_menu.reset_size()
	options_menu.position = Vector2i(r.position + Vector2(0, -options_menu.size.y - 6))
	options_menu.popup()

func _on_option(id: int) -> void:
	match id:
		Option.COPY_CODE:
			copy_code()
		Option.SHARE:
			share_invite()
		Option.CHANGE_ANIMAL:
			tab_requested.emit("personajes")
		Option.SETTINGS:
			tab_requested.emit("configuracion")
		Option.LEAVE:
			if current_mode() == MODE_QUEUE:
				Account.cancel_queue()
			else:
				Account.leave_room()

# ───── Chat ─────

func _on_chat(by: String, author: String, text: String, _at: int) -> void:
	var mine := by == GameState.local_player_id()
	_add_chat_line("[color=#%s]%s:[/color] %s" % [(UiPalette.AMBER if mine else Color("#7DD3FC")).to_html(false), _escape(author), _escape(text)])

func _add_chat_line(bbcode: String, system := false) -> void:
	var line := RichTextLabel.new()
	line.bbcode_enabled = true
	line.fit_content = true
	line.scroll_active = false
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_theme_font_size_override("normal_font_size", 13)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tag := "[color=#E5A93C][Sala][/color] "
	line.text = tag + ("[color=#94A3B8][i]%s[/i][/color]" % bbcode if system else bbcode)
	chat_lines.add_child(line)
	while chat_lines.get_child_count() > MAX_CHAT_LINES:
		var old := chat_lines.get_child(0)
		chat_lines.remove_child(old)
		old.queue_free()
	_scroll_chat_to_end.call_deferred()

func chat_texts() -> Array:
	return chat_lines.get_children().map(func(l): return (l as RichTextLabel).get_parsed_text())

func _scroll_chat_to_end() -> void:
	await get_tree().process_frame
	chat_scroll.scroll_vertical = int(chat_scroll.get_v_scroll_bar().max_value)

func _clear_chat() -> void:
	for c in chat_lines.get_children():
		c.queue_free()
	_known_players.clear()

func _announce_changes(players: Array) -> void:
	var now := {}
	for p in players:
		now[p["id"]] = p["name"]
	if _known_players.is_empty():
		_add_chat_line("Has entrado en la sala %s." % _escape(_room_code), true)
	else:
		for id in now:
			if not _known_players.has(id):
				_add_chat_line("%s se ha unido." % _escape(now[id]), true)
		for id in _known_players:
			if not now.has(id):
				_add_chat_line("%s ha salido." % _escape(_known_players[id]), true)
	_known_players = now

static func _escape(text: String) -> String:
	return text.replace("[", "[lb]")

# ───── Pintado ─────

func _me_entry() -> Dictionary:
	return {"id": "local", "name": Account.player_name, "skinId": Account.selected_skin(), "look": Account.equipped(), "ready": false, "connected": Account.online}

func _case_type_name() -> String:
	return str(CaseTypes.for_scenario(scenario_id).get("name", "Caso"))

func _set_chips(texts: Array) -> void:
	for c in chips.get_children():
		c.queue_free()
	for t in texts:
		var chip := PanelContainer.new()
		chip.add_theme_stylebox_override("panel", UiPalette.flat(Color(UiPalette.CYAN, 0.10), Color(UiPalette.CYAN, 0.45), 1, 8, 3))
		var l := Label.new()
		l.text = t
		l.add_theme_font_size_override("font_size", 11)
		l.add_theme_color_override("font_color", Color("#BFF6FF"))
		chip.add_child(l)
		chips.add_child(chip)

func status_text() -> String:
	match mode:
		MODE_QUEUE:
			return "EN COLA"
		MODE_ROOM:
			var s := seconds_to_start()
			if s >= 0:
				return "EMPIEZA EN %d s" % s
			var players := GameState.players()
			if players.size() < int(GameState.lobby().get("minPlayers", 1)):
				return "ESPERANDO JUGADORES"
			return "LISTOS %d/%d" % [players.filter(func(p): return p.get("ready", false)).size(), players.size()]
	return "SIN SALA" if Account.online else "SIN CONEXIÓN"

func _sync_status_chip() -> void:
	status_chip_label.text = status_text()
	var c := UiPalette.AMBER if seconds_to_start() >= 0 and mode == MODE_ROOM else (UiPalette.CYAN if mode == MODE_QUEUE else Color("#94A3B8"))
	if not Account.online:
		c = UiPalette.CRIMSON
	status_chip.add_theme_stylebox_override("panel", UiPalette.flat(Color(c, 0.14), Color(c, 0.7), 1, 8, 3))
	status_chip_label.add_theme_color_override("font_color", c.lightened(0.3))

func _sync_start_button() -> void:
	var am_ready := my_ready()
	start_button.disabled = not Account.online and mode != MODE_ROOM
	match mode:
		MODE_IDLE:
			start_label.text = "INICIAR"
			start_icon.icon = "play"
			status_label.text = "Partida rápida · %d jugadores" % Account.match_size if Account.online else "Sin conexión con el servidor"
		MODE_QUEUE:
			start_label.text = "CANCELAR"
			start_icon.icon = "search"
			status_label.text = "Buscando partida… %d/%d" % [Account.queue_waiting, Account.match_size]
		MODE_ROOM:
			start_label.text = "LISTO" if am_ready else "INICIAR"
			start_icon.icon = "check" if am_ready else "play"
			var players := GameState.players()
			var ready_count := players.filter(func(p): return p.get("ready", false)).size()
			var min_players := int(GameState.lobby().get("minPlayers", 1))
			var s := seconds_to_start()
			if s >= 0:
				status_label.text = "La partida empieza en %d s" % s
			elif players.size() < min_players:
				status_label.text = "Faltan %d jugadores para empezar" % (min_players - players.size())
			elif am_ready:
				status_label.text = "Listos %d/%d · pulsa para cancelar" % [ready_count, players.size()]
			else:
				status_label.text = "Pulsa INICIAR cuando estés listo (%d/%d)" % [ready_count, players.size()]

func _rebuild_player_list(players: Array, host_id: String, max_players: int, local_id: String) -> void:
	var signature := JSON.stringify([players, host_id, max_players, local_id, mode])
	if signature == _list_signature:
		return
	_list_signature = signature
	players_title.text = "Jugadores (%d/%d)" % [players.size(), max_players]
	for c in player_list.get_children():
		player_list.remove_child(c)
		c.queue_free()
	for p in players:
		player_list.add_child(_player_row(p, p["id"] == host_id, p["id"] == local_id))
	for i in range(players.size(), max_players):
		player_list.add_child(_empty_row())

func _player_row(p: Dictionary, host: bool, local: bool) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.custom_minimum_size.y = 28
	var crown := MenuIcon.make("crown", UiPalette.AMBER, 16) if host else Control.new()
	crown.custom_minimum_size = Vector2(16, 16)
	crown.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(crown)
	var head := SkinPreview.new()
	head.skin_id = p["skinId"]
	head.head_only = true
	head.custom_minimum_size = Vector2(24, 24)
	head.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(head)
	var name_label := Label.new()
	name_label.text = p["name"] + (" (tú)" if local else "")
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.clip_text = true
	name_label.add_theme_font_size_override("font_size", 14)
	if local:
		name_label.add_theme_color_override("font_color", Color("#FFE7A8"))
	row.add_child(name_label)
	if p.get("ready", false):
		var ready_label := Label.new()
		ready_label.text = "LISTO"
		ready_label.add_theme_font_size_override("font_size", 10)
		ready_label.add_theme_font_override("font", UiPalette.bold_font())
		ready_label.add_theme_color_override("font_color", GREEN)
		row.add_child(ready_label)
	row.add_child(_dot(GREEN if p.get("connected", true) else Color("#64748B")))
	return row

func _empty_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = 28
	row.add_theme_constant_override("separation", 6)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(46, 0)
	row.add_child(spacer)
	var l := Label.new()
	l.text = "Plaza libre"
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", Color(1, 1, 1, 0.35))
	row.add_child(l)
	row.add_child(_dot(Color(1, 1, 1, 0.15)))
	return row

func _dot(c: Color) -> Panel:
	var dot := Panel.new()
	dot.custom_minimum_size = Vector2(9, 9)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dot.add_theme_stylebox_override("panel", UiPalette.flat(c, Color.TRANSPARENT, 0, 5, 0))
	return dot

func _build_case_list() -> void:
	var selected := str(CaseTypes.for_scenario(scenario_id).get("id", ""))
	for t in CaseTypes.all():
		var available := CaseTypes.is_available(t)
		var b := Button.new()
		b.name = "Case_" + str(t["id"])
		b.custom_minimum_size = Vector2(0, 36)
		b.toggle_mode = true
		b.button_pressed = t["id"] == selected
		b.disabled = not available
		b.focus_mode = Control.FOCUS_NONE
		b.tooltip_text = "Caso de %s" % t["name"] if available else "Próximamente: aún no hay casos de %s." % str(t["name"]).to_lower()
		_style_drawer(b)
		var row := HBoxContainer.new()
		row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 10)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var label := Label.new()
		label.text = str(t["name"]).to_upper()
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.add_theme_font_override("font", UiPalette.heading_font())
		label.add_theme_font_size_override("font_size", 14)
		label.add_theme_color_override("font_color", Color("#F1E7D6") if available else Color(1, 1, 1, 0.35))
		row.add_child(label)
		if not available:
			var soon := Label.new()
			soon.text = "PRONTO"
			soon.add_theme_font_size_override("font_size", 10)
			soon.add_theme_color_override("font_color", Color(1, 1, 1, 0.35))
			row.add_child(soon)
		row.add_child(MenuIcon.make("check" if t["id"] == selected else ("lock" if not available else "chevron"),
			UiPalette.AMBER if t["id"] == selected else Color(1, 1, 1, 0.4), 16))
		for c in row.get_children():
			c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		b.add_child(row)
		# Solo hay un caso por tipo: el botón refleja el tipo de la sala, no cambia nada.
		b.toggled.connect(func(_on: bool) -> void: b.set_pressed_no_signal(t["id"] == selected))
		case_list.add_child(b)

func case_buttons() -> Array:
	return case_list.get_children()

func _style_drawer(b: Button) -> void:
	b.add_theme_stylebox_override("normal", UiPalette.flat(Color("#26211E", 0.95), Color("#4A4036"), 1, 6, 6))
	b.add_theme_stylebox_override("hover", UiPalette.flat(Color("#332B25", 0.95), Color("#6B5A48"), 1, 6, 6))
	b.add_theme_stylebox_override("pressed", UiPalette.flat(Color("#3A2F22", 0.95), UiPalette.AMBER, 2, 6, 6))
	b.add_theme_stylebox_override("hover_pressed", UiPalette.flat(Color("#3A2F22", 0.95), UiPalette.AMBER, 2, 6, 6))
	b.add_theme_stylebox_override("disabled", UiPalette.flat(Color("#171412", 0.9), Color("#2E2925"), 1, 6, 6))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

func _style() -> void:
	var panel := UiPalette.flat(Color(UiPalette.NAVY, 0.88), Color(1, 1, 1, 0.10), 1, 14, 12)
	for p in [room_card, %PlayersPanel, %ChatPanel]:
		p.add_theme_stylebox_override("panel", panel)
	title_label.add_theme_font_override("font", UiPalette.heading_font())
	title_label.add_theme_font_size_override("font_size", 16)
	title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title_label.max_lines_visible = 2
	room_label.add_theme_color_override("font_color", Color("#CBD5E1"))
	room_label.add_theme_font_size_override("font_size", 13)
	code_label.add_theme_font_override("font", UiPalette.mono_font())
	code_label.add_theme_font_size_override("font_size", 26)
	code_label.add_theme_color_override("font_color", Color.WHITE)
	%CodeCaption.add_theme_color_override("font_color", Color("#94A3B8"))
	%CodeCaption.add_theme_font_size_override("font_size", 12)
	status_chip_label.add_theme_font_size_override("font_size", 11)
	status_chip_label.add_theme_font_override("font", UiPalette.bold_font())
	players_title.add_theme_font_override("font", UiPalette.heading_font())
	players_title.add_theme_font_size_override("font_size", 16)
	%CaseCaption.add_theme_font_override("font", UiPalette.heading_font())
	%CaseCaption.add_theme_font_size_override("font_size", 13)
	%CaseCaption.add_theme_color_override("font_color", Color("#94A3B8"))
	%ChatTitle.add_theme_font_override("font", UiPalette.heading_font())
	%ChatTitle.add_theme_font_size_override("font_size", 14)
	UiPalette.style_button(share_button, UiPalette.AMBER)
	UiPalette.style_button(quick_button, UiPalette.CYAN)
	UiPalette.style_button(cancel_queue_button, UiPalette.CRIMSON)
	copy_button.flat = true
	copy_button.add_child(_centered_icon("copy", Color("#CBD5E1"), 18))
	_icon_label(share_button, "share", "Compartir", Color("#FFE7A8"))
	_icon_label(quick_button, "play", "Partida rápida", Color("#BFF6FF"))
	_icon_label(create_button, "lock", "Crear sala privada", Color("#E2E8F0"))
	chat_send.add_child(_centered_icon("chat", Color("#0B0F19"), 18))
	chat_send.add_theme_stylebox_override("normal", UiPalette.flat(UiPalette.AMBER, Color.TRANSPARENT, 0, 8, 6))
	chat_send.add_theme_stylebox_override("hover", UiPalette.flat(UiPalette.AMBER.lightened(0.15), Color.TRANSPARENT, 0, 8, 6))
	chat_send.add_theme_stylebox_override("pressed", UiPalette.flat(UiPalette.AMBER.darkened(0.15), Color.TRANSPARENT, 0, 8, 6))
	chat_send.add_theme_stylebox_override("disabled", UiPalette.flat(Color(UiPalette.AMBER, 0.25), Color.TRANSPARENT, 0, 8, 6))
	for field in [chat_input, code_input]:
		field.add_theme_stylebox_override("normal", UiPalette.flat(Color(0, 0, 0, 0.35), Color(1, 1, 1, 0.12), 1, 8, 8))
		field.add_theme_stylebox_override("focus", UiPalette.flat(Color(0, 0, 0, 0.45), UiPalette.AMBER, 1, 8, 8))
		field.add_theme_stylebox_override("read_only", UiPalette.flat(Color(0, 0, 0, 0.2), Color(1, 1, 1, 0.06), 1, 8, 8))
	code_input.add_theme_font_override("font", UiPalette.mono_font())
	# Opciones: botón cuadrado de cristal.
	options_button.add_theme_stylebox_override("normal", UiPalette.flat(Color(UiPalette.NAVY, 0.9), Color(1, 1, 1, 0.16), 1, 14, 8))
	options_button.add_theme_stylebox_override("hover", UiPalette.flat(Color("#1B2338", 0.95), Color(1, 1, 1, 0.3), 1, 14, 8))
	options_button.add_theme_stylebox_override("pressed", UiPalette.flat(Color("#232D47", 0.95), UiPalette.AMBER, 1, 14, 8))
	%OptionsLabel.add_theme_font_size_override("font_size", 12)
	# INICIAR: amarillo intenso con relieve.
	var normal := UiPalette.flat(YELLOW, Color("#C99A00"), 0, 16, 10)
	normal.border_width_bottom = 6
	var hover := normal.duplicate()
	hover.bg_color = Color("#FFE04D")
	var pressed := normal.duplicate()
	pressed.bg_color = Color("#F2C200")
	pressed.border_width_bottom = 2
	var disabled := normal.duplicate()
	disabled.bg_color = Color("#6B6440")
	disabled.border_color = Color("#4A4530")
	for s in [["normal", normal], ["hover", hover], ["pressed", pressed], ["disabled", disabled], ["focus", StyleBoxEmpty.new()]]:
		start_button.add_theme_stylebox_override(s[0], s[1])
	start_label.add_theme_font_override("font", UiPalette.heading_font())
	start_label.add_theme_font_size_override("font_size", 30)
	start_label.add_theme_color_override("font_color", Color("#1A1405"))
	start_icon.color = Color("#1A1405")
	status_label.add_theme_font_size_override("font_size", 13)
	status_label.add_theme_color_override("font_color", Color("#E2E8F0"))
	status_label.add_theme_constant_override("outline_size", 4)
	status_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))

## Contenido de botón con icono + texto (el texto propio del botón queda vacío).
static func _icon_label(b: Button, icon_name: String, text: String, c: Color) -> void:
	b.text = ""
	var row := HBoxContainer.new()
	row.name = "Content"
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 8)
	row.add_child(MenuIcon.make(icon_name, c, 16))
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", c)
	row.add_child(l)
	for child in row.get_children():
		child.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.add_child(row)
	b.custom_minimum_size.x = maxf(b.custom_minimum_size.x, l.get_minimum_size().x + 52)

static func _centered_icon(icon_name: String, c: Color, px: float) -> CenterContainer:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(MenuIcon.make(icon_name, c, px))
	return center
