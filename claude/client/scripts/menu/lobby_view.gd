class_name LobbyView
extends Control
## Pestaña "Sala" del menú: la sala de espera en la oficina de noche.
##  - Tarjeta del caso arriba: miniatura, título, plazas (barra por segmentos), etiquetas
##    y estado; a la derecha, el código de sala (Copiar + Compartir). Sin sala, la misma
##    tarjeta ofrece Partida rápida, Crear sala privada y Unirse con código; en la cola,
##    un radar que busca con "Buscando partida x/12 · empieza en N s".
##  - En el centro, los animales de los jugadores en la grada (LobbyStage).
##  - A la derecha, las tarjetas de jugador en dos columnas (cabeza, nombre, corona del
##    anfitrión, LISTO, punto de conexión y huecos "Esperando…") y el tipo de caso.
##  - Abajo a la izquierda, el chat de la sala; abajo a la derecha, el dock con el estado
##    (anillo de cuenta atrás), Opciones y el botón grande (INICIAR / LISTO / JUGAR).
##  - Abajo en el centro, tu mascota (PetPanel): Hambre, Hidratación y los botones de
##    su comida y agua. Tu animal se puede tocar y acariciar en la sala (LobbyStage).
## JUGAR (el botón grande sin sala) y Partida rápida entran en la cola pública
## (Protocol.QUEUE_MATCH); Crear sala privada pide una sala con código
## (Protocol.CREATE_PRIVATE_ROOM) y, al llegar el "welcome", el menú pasa a la sala.
## Sin conexión, cada botón intenta conectar primero y, si no hay servidor, lo explica.
## En la sala el botón grande es INICIAR y marca "listo" (la partida empieza cuando
## todos lo están; las salas públicas además arrancan solas tras la cuenta atrás).
## Todas las acciones pasan por Account; los nombres nunca llevan el rol y las tarjetas
## no tienen colores por jugador (solo ámbar para ti y verde para LISTO, como todos).

signal toast_requested(text: String)
signal tab_requested(tab: String)

const GlassBox := preload("res://scripts/ui/GlassBox.gd")
const Fx := preload("res://scripts/menu/LobbyFx.gd")

const YELLOW := Color("#FFD21F")
const GREEN := Color("#4ADE80")
const INK := Color("#1A1405")
const DIM := Color("#94A3B8")
const MODE_IDLE := "idle"
const MODE_QUEUE := "queue"
const MODE_ROOM := "room"
const MAX_CHAT_LINES := 60
## Alto de cada tarjeta de jugador (caben 12 en dos columnas sin desbordar).
const CARD_H := 36
const OFFLINE_HELP := "No hay servidor en %s. Arráncalo (en la carpeta server: npm start) y vuelve a pulsar."
const REMOTE_HELP := "No se pudo conectar con %s. Revisa tu conexión a internet y vuelve a pulsar."
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
@onready var players_count: Label = %PlayersCount
@onready var player_list: GridContainer = %PlayerList
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
@onready var dock: PanelContainer = %Dock

var mode := MODE_IDLE
var options_menu: PopupMenu
var _list_signature := ""
var _known_players := {}   # id -> nombre, para avisar en el chat de quién entra y sale
var _room_code := ""
var _connecting := false
## Mascota (Alter Ego): estado guardado en el dispositivo, sus sonidos y su barra.
var pet := PetCare.new()
var pet_sfx: PetSfx
var pet_panel: PetPanel
var _pet_key := "-"
var _pet_clock := 0.0
## Piezas animadas (LobbyFx).
var slot_bar: Fx.SlotBar
var countdown: Fx.Ring
var radar: Fx.Radar
var status_dot: Fx.PulseDot
var _shine: Fx.Shine
var _cta_kind := ""
var _count_total := 0
var _entered := false

func _ready() -> void:
	_style()
	_build_fx()
	_build_case_list()
	options_menu = PopupMenu.new()
	options_menu.name = "OptionsMenu"
	add_child(options_menu)
	options_menu.id_pressed.connect(_on_option)

	start_button.pressed.connect(_on_start_pressed)
	options_button.pressed.connect(_open_options)
	quick_button.pressed.connect(play)
	create_button.pressed.connect(create_private_room)
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
	_build_pet()
	refresh()
	visibility_changed.connect(func() -> void:
		if is_visible_in_tree():
			play_entry())
	play_entry.call_deferred()

## Entrada de la pestaña: los paneles llegan desde su borde con un fundido.
func play_entry() -> void:
	if not is_inside_tree():
		return
	Fx.enter(room_card, Vector2(0, -22), 0.0)
	Fx.enter(%RightColumn, Vector2(28, 0), 0.06)
	Fx.enter(%ChatPanel, Vector2(-28, 0), 0.1)
	Fx.enter(dock, Vector2(0, 26), 0.12)
	if pet_panel:
		Fx.enter(pet_panel, Vector2(0, 26), 0.16)
	_entered = true

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
	var filled := players.size()
	match mode:
		MODE_ROOM:
			_room_code = str(lobby.get("code", Network.room_code))
			code_label.text = _room_code
			room_label.text = "Sala %s · %s" % [_room_code, "Pública" if public else "Privada"]
		MODE_QUEUE:
			room_label.text = "Partida pública"
			queue_label.text = _queue_detail()
			filled = maxi(1, Account.queue_waiting)
		_:
			room_label.text = "Sin sala · elige cómo jugar"
	count_label.text = "%d/%d" % [filled, max_players]
	slot_bar.total = clampi(max_players, 1, 16)
	slot_bar.filled = filled
	_set_chips([_case_type_name(), "Pública" if public else ("Privada" if mode == MODE_ROOM else "Modo libre")])
	_sync_status_chip()

	# Escenario central y lista de jugadores.
	var local_id := GameState.local_player_id() if mode == MODE_ROOM else "local"
	stage.set_players(players, str(lobby.get("hostId", "")) if mode == MODE_ROOM else "", max_players, local_id, mode != MODE_ROOM)
	_rebuild_player_list(players, str(lobby.get("hostId", "")), max_players, local_id)
	if mode == MODE_ROOM:
		_announce_changes(players)
	%ChatOnline.text = "%d en la sala" % players.size() if mode == MODE_ROOM else ""

	# Chat e INICIAR.
	chat_input.editable = mode == MODE_ROOM
	chat_send.disabled = mode != MODE_ROOM
	chat_input.placeholder_text = "Escribe un mensaje…" if mode == MODE_ROOM else "Entra en una sala para chatear"
	quick_button.disabled = _connecting
	create_button.disabled = _connecting
	join_button.disabled = _connecting or Account.normalize_code(code_input.text).length() != 6
	_sync_start_button()
	refresh_pet()

## "7/12 jugadores · empieza en 18 s" (la cola, sin repetir "Buscando partida").
func _queue_detail() -> String:
	return Account.queue_text().trim_prefix("Buscando partida ")

func _process(delta: float) -> void:
	if mode == MODE_ROOM and GameState.lobby().get("startsAt") != null:
		_sync_status_chip()
		_sync_start_button()
	elif mode == MODE_QUEUE and Account.queue_seconds_left() >= 0:
		queue_label.text = _queue_detail()
		_sync_status_chip()
		_sync_start_button()
	_pet_clock += delta
	if _pet_clock >= 1.0 and is_visible_in_tree():
		_pet_clock = 0.0
		refresh_pet()

# ───── Mascota ─────

func _build_pet() -> void:
	pet_panel = PetPanel.new()
	pet_panel.anchor_left = 0.0
	pet_panel.anchor_right = 1.0
	pet_panel.anchor_top = 1.0
	pet_panel.anchor_bottom = 1.0
	pet_panel.offset_left = 356.0    # entre el chat y Opciones/INICIAR
	pet_panel.offset_right = -392.0
	pet_panel.offset_top = -84.0
	pet_panel.offset_bottom = -16.0
	pet_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(pet_panel)
	move_child(pet_panel, stage.get_index() + 1)
	_style_pet()
	pet_panel.feed_pressed.connect(feed_pet)
	pet_panel.drink_pressed.connect(water_pet)
	pet_sfx = PetSfx.new()
	pet_sfx.name = "PetSfx"
	add_child(pet_sfx)
	stage.pet_touched.connect(func(gesture: String, skin: String) -> void: pet_sfx.play(PetSfx.key_for(skin, gesture)))

## Tu animal en la sala (el de tu asiento) o, sin sala, el elegido en tu perfil.
func pet_skin() -> String:
	var seat := stage.local_seat()
	return seat.skin_id if seat else Account.selected_skin()

func refresh_pet() -> void:
	if pet_panel == null:
		return
	if Account.profile_id != _pet_key:
		_pet_key = Account.profile_id
		pet.load_state(_pet_key)
	var skin := pet_skin()
	var l := pet.levels(skin)
	pet_panel.show_pet(skin, l["hunger"], l["hydration"])
	var need := pet.need(skin)
	stage.set_pet_need("water" if need == "hydration" else str(PetCare.food(skin).get("icon", "")) if need == "hunger" else "")

## Le da su comida (según la especie). Si ya está lleno, niega con la cabeza.
func feed_pet() -> void:
	var skin := pet_skin()
	var food := PetCare.food(skin)
	if pet.feed(skin)["ok"]:
		stage.pet_react("eat", "food:" + str(food.get("icon", "kibble")), true)
		pet_sfx.play("comer")
	else:
		stage.pet_react("refuse", "", true)
		pet_sfx.play("lleno")
		toast_requested.emit("Tu %s ya está lleno." % str(SkinCatalog.skin(skin).get("name", skin)).to_lower())
	refresh_pet()

func water_pet() -> void:
	var skin := pet_skin()
	if pet.drink(skin)["ok"]:
		stage.pet_react("drink", "food:water", true)
		pet_sfx.play("beber")
	else:
		stage.pet_react("refuse", "", true)
		pet_sfx.play("lleno")
		toast_requested.emit("Tu %s no tiene sed." % str(SkinCatalog.skin(skin).get("name", skin)).to_lower())
	refresh_pet()

# ───── Acciones ─────

## JUGAR / Partida rápida: entra en la cola pública (conecta antes si hace falta).
func play() -> void:
	if current_mode() != MODE_IDLE or not await ensure_online():
		return
	if current_mode() == MODE_IDLE:
		Account.quick_match()

## Crear sala privada: el servidor responde con el "welcome" de la sala nueva y el menú
## muestra la sala de espera con su código.
func create_private_room() -> void:
	if current_mode() != MODE_IDLE or not await ensure_online():
		return
	if current_mode() == MODE_IDLE:
		Account.create_room()

## Conecta con el servidor si aún no lo está. false (y un aviso) si no responde.
func ensure_online() -> bool:
	if Account.online:
		return true
	if _connecting:
		return false
	_connecting = true
	refresh()
	toast_requested.emit("Conectando con el servidor…" if Network.is_local_url(Network.server_url) else "Conectando con el servidor… Si estaba dormido puede tardar hasta un minuto.")
	var ok: bool = await Account.go_online()
	_connecting = false
	refresh()
	if not ok:
		toast_requested.emit((OFFLINE_HELP if Network.is_local_url(Network.server_url) else REMOTE_HELP) % Network.server_url)
	return ok

func _on_start_pressed() -> void:
	match current_mode():
		MODE_IDLE:
			play()
		MODE_QUEUE:
			Account.cancel_queue()
		MODE_ROOM:
			Account.set_ready(not my_ready())

func _join_with_code() -> void:
	var code := Account.normalize_code(code_input.text)
	if code.length() != 6:
		toast_requested.emit("El código de sala tiene 6 caracteres.")
		return
	if await ensure_online():
		Account.join_room(code)

func _on_code_typed(text: String) -> void:
	var clean := Account.normalize_code(text).left(6)
	if clean != text:
		var caret := code_input.caret_column
		code_input.text = clean
		code_input.caret_column = mini(caret, clean.length())
	join_button.disabled = _connecting or clean.length() != 6

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
	_add_chat_line("[color=#%s][b]%s[/b][/color]  %s" % [(Color("#FFC94A") if mine else Color("#7DD3FC")).to_html(false), _escape(author), _escape(text)])

func _add_chat_line(bbcode: String, system := false) -> void:
	var line := RichTextLabel.new()
	line.bbcode_enabled = true
	line.fit_content = true
	line.scroll_active = false
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_theme_font_size_override("normal_font_size", 13)
	line.add_theme_font_size_override("bold_font_size", 13)
	line.add_theme_font_size_override("italics_font_size", 12)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.text = "[color=#8B98B4][i]%s[/i][/color]" % bbcode if system else bbcode
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
	var key := str(texts)
	if chips.get_meta("key", "") == key:
		return
	chips.set_meta("key", key)
	for c in chips.get_children():
		chips.remove_child(c)
		c.queue_free()
	for i in texts.size():
		var tint := UiPalette.AMBER if i == 0 else UiPalette.CYAN
		var chip := PanelContainer.new()
		var st = GlassBox.make(Color(tint, 0.20), Color(tint, 0.08), 7.0, 0.0)
		st.border_top = Color(tint, 0.7)
		st.border_bottom = Color(tint, 0.25)
		st.shadow_size = 0
		st.content_margin_left = 7
		st.content_margin_right = 7
		st.content_margin_top = 1
		st.content_margin_bottom = 1
		chip.add_theme_stylebox_override("panel", st)
		var l := Label.new()
		l.text = str(texts[i]).to_upper()
		l.add_theme_font_size_override("font_size", 10)
		l.add_theme_font_override("font", UiPalette.bold_font())
		l.add_theme_color_override("font_color", tint.lightened(0.55))
		chip.add_child(l)
		chips.add_child(chip)

func status_text() -> String:
	match mode:
		MODE_QUEUE:
			var left := Account.queue_seconds_left()
			return "EMPIEZA EN %d s" % left if left >= 0 else "EN COLA"
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
	var text := status_text()
	var c := UiPalette.AMBER if seconds_to_start() >= 0 and mode == MODE_ROOM else (UiPalette.CYAN if mode == MODE_QUEUE else Color("#94A3B8"))
	if mode == MODE_ROOM and seconds_to_start() < 0 and text.begins_with("LISTOS"):
		c = GREEN
	if not Account.online and mode != MODE_ROOM:
		c = UiPalette.CRIMSON
	var key := text + c.to_html()
	if status_chip.get_meta("key", "") == key:
		return
	status_chip.set_meta("key", key)
	status_chip_label.text = text
	if status_chip.get_meta("color", Color.BLACK) != c:
		status_chip.set_meta("color", c)
		var st = GlassBox.make(Color(c, 0.22), Color(c, 0.10), 8.0, 0.0)
		st.border_top = Color(c, 0.8)
		st.border_bottom = Color(c, 0.3)
		st.shadow_size = 0
		st.content_margin_left = 6
		st.content_margin_right = 8
		st.content_margin_top = 2
		st.content_margin_bottom = 2
		status_chip.add_theme_stylebox_override("panel", st)
		status_chip_label.add_theme_color_override("font_color", c.lightened(0.45))
		status_dot.color = c.lightened(0.15)
	status_dot.pulse = mode != MODE_IDLE or Account.online

func _sync_start_button() -> void:
	var am_ready := my_ready()
	start_button.disabled = _connecting and mode != MODE_ROOM
	var players := GameState.players()
	match mode:
		MODE_IDLE:
			start_label.text = "JUGAR"
			start_icon.icon = "play"
			_set_cta("yellow")
			if _connecting:
				status_label.text = "Conectando con el servidor…"
			else:
				status_label.text = "Partida rápida · %d a %d jugadores" % [Account.queue_min_size, Account.match_size] if Account.online else "Sin conexión · pulsa JUGAR para reintentar"
			_set_countdown(-1, 0.0, _connecting)
		MODE_QUEUE:
			start_label.text = "CANCELAR"
			start_icon.icon = "search"
			_set_cta("red")
			status_label.text = Account.queue_text()
			var left := Account.queue_seconds_left()
			_set_countdown(left, 0.0, left < 0)
		MODE_ROOM:
			start_label.text = "LISTO" if am_ready else "INICIAR"
			start_icon.icon = "check" if am_ready else "play"
			_set_cta("green" if am_ready else "yellow")
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
			_set_countdown(s, float(ready_count) / maxf(players.size(), 1.0), false)

## Anillo del dock: cuenta atrás (s >= 0), o cuántos están listos, o girando (espera).
func _set_countdown(s: int, ratio: float, waiting: bool) -> void:
	countdown.visible = mode != MODE_IDLE or waiting
	countdown.spin = waiting
	if s >= 0:
		_count_total = maxi(_count_total, s)
		countdown.color = UiPalette.AMBER
		countdown.progress = float(s) / maxf(_count_total, 1.0)
		countdown.text = str(s)
	else:
		_count_total = 0
		countdown.color = GREEN if mode == MODE_ROOM else UiPalette.CYAN
		countdown.progress = ratio
		countdown.text = ""

## Estilo del botón grande: amarillo (JUGAR / INICIAR), verde (LISTO) o rojo (CANCELAR).
func _set_cta(kind: String) -> void:
	if kind == _cta_kind:
		return
	_cta_kind = kind
	var top := Color("#FFE66B")
	var bottom := Color("#F6B70C")
	var lip := Color("#B97C00")
	var ink := INK
	match kind:
		"green":
			top = Color("#86F5B0")
			bottom = Color("#22C566")
			lip = Color("#13703A")
			ink = Color("#052E16")
		"red":
			top = Color("#FF7A8A")
			bottom = Color("#E11D48")
			lip = Color("#8E1033")
			ink = Color.WHITE
	var states := {}
	for state in ["normal", "hover", "pressed", "disabled"]:
		var t := top
		var b := bottom
		if state == "hover":
			t = top.lightened(0.12)
			b = bottom.lightened(0.1)
		elif state == "pressed":
			t = top.darkened(0.06)
			b = bottom.darkened(0.08)
		var st = GlassBox.make(t, b, 16.0, 10.0)
		st.border_top = Color(1, 1, 1, 0.75)
		st.border_bottom = Color(lip, 0.0)
		st.border_width = 1.5
		st.lip = 6.0 if state != "pressed" else 2.0
		st.press_shift = 0.0 if state != "pressed" else 4.0
		st.lip_color = lip
		st.sheen = 0.16
		st.shadow_size = 16
		st.shadow_color = Color(0, 0, 0, 0.5)
		st.shadow_offset = Vector2(0, 6)
		st.glow_color = Color(bottom, 0.35 if state != "disabled" else 0.0)
		st.glow_size = 12 if state == "hover" else 8
		if state == "disabled":
			st.bg_top = Color(top, 0.35)
			st.bg_bottom = Color(bottom, 0.3)
			st.lip_color = Color(lip, 0.4)
		states[state] = st
	for state in states:
		start_button.add_theme_stylebox_override(state, states[state])
	start_label.add_theme_color_override("font_color", ink)
	start_icon.color = ink
	_shine.strength = 0.35 if kind != "red" else 0.22

func _rebuild_player_list(players: Array, host_id: String, max_players: int, local_id: String) -> void:
	var signature := JSON.stringify([players, host_id, max_players, local_id, mode])
	if signature == _list_signature:
		return
	_list_signature = signature
	players_title.text = "JUGADORES"
	players_count.text = "%d/%d" % [players.size(), max_players]
	for c in player_list.get_children():
		player_list.remove_child(c)
		c.queue_free()
	# Hasta 12 plazas en dos columnas: las ocupadas y los huecos libres.
	for p in players:
		player_list.add_child(_player_card(p, p["id"] == host_id, p["id"] == local_id))
	var free := clampi(max_players, 1, 12) - players.size()
	var ghost_text := "Esperando…" if mode == MODE_ROOM else ("Buscando…" if mode == MODE_QUEUE else "Plaza libre")
	for i in maxi(free, 0):
		player_list.add_child(_ghost_card(ghost_text))

func _card_style(local: bool, player_ready: bool) -> StyleBox:
	var st = GlassBox.inset(10.0, 5.0)
	st.content_margin_left = 5
	st.content_margin_right = 6
	if local:
		st.bg_top = Color(UiPalette.AMBER, 0.22)
		st.bg_bottom = Color(UiPalette.AMBER, 0.08)
		st.border_top = Color("#FFD27A", 0.9)
		st.border_bottom = Color(UiPalette.AMBER, 0.35)
	elif player_ready:
		st.bg_top = Color(GREEN, 0.12)
		st.bg_bottom = Color(GREEN, 0.04)
		st.border_top = Color(GREEN, 0.5)
		st.border_bottom = Color(GREEN, 0.12)
	return st

func _player_card(p: Dictionary, host: bool, local: bool) -> PanelContainer:
	var card := PanelContainer.new()
	card.name = "Player_" + str(p["id"]).left(8)
	card.custom_minimum_size = Vector2(0, CARD_H)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.mouse_filter = Control.MOUSE_FILTER_PASS
	var player_ready := bool(p.get("ready", false))
	var online := bool(p.get("connected", true)) or (local and mode != MODE_ROOM)
	card.add_theme_stylebox_override("panel", _card_style(local, player_ready))
	card.tooltip_text = str(p["name"]) + (" (tú)" if local else "") + (" · anfitrión" if host else "") + (" · listo" if player_ready else "")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(row)
	# Cabeza en un círculo, con la corona del anfitrión y el punto de conexión encima.
	var wrap := Control.new()
	wrap.custom_minimum_size = Vector2(26, 26)
	wrap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(wrap)
	var frame := Panel.new()
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	frame.add_theme_stylebox_override("panel", UiPalette.flat(Color("#25305A"), Color.TRANSPARENT, 0, 13, 0))
	wrap.add_child(frame)
	var head := SkinPreview.new()
	head.skin_id = p["skinId"]
	head.head_only = true
	head.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.add_child(head)
	var ring := Panel.new()
	ring.set_anchors_preset(Control.PRESET_FULL_RECT)
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ring_col := Color("#FFD27A") if local else (GREEN if player_ready else Color(1, 1, 1, 0.25))
	ring.add_theme_stylebox_override("panel", UiPalette.flat(Color.TRANSPARENT, ring_col, 2 if local or player_ready else 1, 13, 0))
	wrap.add_child(ring)
	var dot := Fx.PulseDot.new()
	dot.pulse = false
	dot.color = GREEN if online else Color("#64748B")
	dot.custom_minimum_size = Vector2(9, 9)
	dot.size = Vector2(9, 9)
	dot.position = Vector2(19, 18)
	var dot_bg := Panel.new()
	dot_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dot_bg.add_theme_stylebox_override("panel", UiPalette.flat(Color("#0B0F19"), Color.TRANSPARENT, 0, 6, 0))
	dot_bg.position = Vector2(18, 17)
	dot_bg.size = Vector2(11, 11)
	wrap.add_child(dot_bg)
	wrap.add_child(dot)
	# Nombre y estado.
	var texts := VBoxContainer.new()
	texts.add_theme_constant_override("separation", -2)
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	texts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(texts)
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 3)
	name_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	texts.add_child(name_row)
	var name_label := Label.new()
	name_label.text = str(p["name"])
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.add_theme_font_override("font", UiPalette.bold_font())
	name_label.add_theme_font_size_override("font_size", 12)
	name_label.add_theme_color_override("font_color", Color("#FFE7A8") if local else Color("#F1F5F9"))
	name_row.add_child(name_label)
	if host:
		var crown := MenuIcon.make("crown", Color("#FFC94A"), 13)
		crown.name = "Crown"
		crown.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		crown.tooltip_text = "Anfitrión"
		name_row.add_child(crown)
	var sub_row := HBoxContainer.new()
	sub_row.add_theme_constant_override("separation", 3)
	sub_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	texts.add_child(sub_row)
	var sub := Label.new()
	sub.clip_text = true
	sub.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	sub.add_theme_font_size_override("font_size", 10)
	sub.add_theme_font_override("font", UiPalette.bold_font())
	if not online:
		sub.text = "SIN CONEXIÓN"
		sub.add_theme_color_override("font_color", Color("#64748B"))
	elif player_ready:
		var check := MenuIcon.make("check", GREEN, 10)
		check.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		sub_row.add_child(check)
		sub.text = "LISTO"
		sub.add_theme_color_override("font_color", GREEN)
	elif host:
		sub.text = "ANFITRIÓN"
		sub.add_theme_color_override("font_color", Color("#FFC94A"))
	else:
		sub.text = "TÚ" if local else ("EN SALA" if mode == MODE_ROOM else "EN ESPERA")
		sub.add_theme_color_override("font_color", Color("#FFD27A") if local else DIM)
	sub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sub_row.add_child(sub)
	Fx.juice(card, 1.03, 0.98)
	return card

func _ghost_card(text: String) -> PanelContainer:
	var card := PanelContainer.new()
	card.name = "Free"
	card.custom_minimum_size = Vector2(0, CARD_H)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var st = GlassBox.inset(10.0, 5.0, 0.45)
	st.content_margin_left = 5
	card.add_theme_stylebox_override("panel", st)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(row)
	var ghost := Fx.Ghost.new()
	ghost.custom_minimum_size = Vector2(26, 26)
	ghost.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(ghost)
	var l := Label.new()
	l.text = text
	l.clip_text = true
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	l.add_theme_font_size_override("font_size", 11)
	l.add_theme_color_override("font_color", Color(1, 1, 1, 0.32))
	row.add_child(l)
	return card

func _build_case_list() -> void:
	var selected := str(CaseTypes.for_scenario(scenario_id).get("id", ""))
	for t in CaseTypes.all():
		var available := CaseTypes.is_available(t)
		var b := Button.new()
		b.name = "Case_" + str(t["id"])
		b.custom_minimum_size = Vector2(0, 28)
		b.toggle_mode = true
		b.button_pressed = t["id"] == selected
		b.disabled = not available
		b.focus_mode = Control.FOCUS_NONE
		b.tooltip_text = "Caso de %s" % t["name"] if available else "Próximamente: aún no hay casos de %s." % str(t["name"]).to_lower()
		_style_drawer(b)
		var row := HBoxContainer.new()
		row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 10)
		row.offset_left = 10
		row.offset_right = -8
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_theme_constant_override("separation", 6)
		var on: bool = t["id"] == selected
		var bullet := Fx.PulseDot.new()
		bullet.pulse = on
		bullet.color = UiPalette.AMBER if on else (Color(1, 1, 1, 0.5) if available else Color(1, 1, 1, 0.18))
		bullet.custom_minimum_size = Vector2(8, 8)
		row.add_child(bullet)
		var label := Label.new()
		label.text = str(t["name"]).to_upper()
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.add_theme_font_override("font", UiPalette.heading_font())
		label.add_theme_font_size_override("font_size", 12)
		label.add_theme_color_override("font_color", Color("#FFE7A8") if on else (Color("#E2E8F0") if available else Color(1, 1, 1, 0.3)))
		row.add_child(label)
		if not available:
			var soon := Label.new()
			soon.text = "PRONTO"
			soon.add_theme_font_size_override("font_size", 9)
			soon.add_theme_font_override("font", UiPalette.bold_font())
			soon.add_theme_color_override("font_color", Color(1, 1, 1, 0.3))
			row.add_child(soon)
		row.add_child(MenuIcon.make("check" if on else ("lock" if not available else "chevron"),
			UiPalette.AMBER if on else Color(1, 1, 1, 0.3), 13))
		for c in row.get_children():
			c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		b.add_child(row)
		# Solo hay un caso por tipo: el botón refleja el tipo de la sala, no cambia nada.
		b.toggled.connect(func(_on: bool) -> void: b.set_pressed_no_signal(t["id"] == selected))
		case_list.add_child(b)

func case_buttons() -> Array:
	return case_list.get_children()

func _style_drawer(b: Button) -> void:
	var normal = GlassBox.inset(8.0, 4.0)
	var hover = GlassBox.inset(8.0, 4.0, 1.8)
	var on = GlassBox.accent(UiPalette.AMBER, 8.0, 4.0, 0.9)
	on.shadow_size = 0
	on.with_glow(Color(UiPalette.AMBER, 0.25), 6)
	var off = GlassBox.inset(8.0, 4.0, 0.35)
	for s in [["normal", normal], ["hover", hover], ["pressed", on], ["hover_pressed", on], ["disabled", off], ["focus", StyleBoxEmpty.new()]]:
		b.add_theme_stylebox_override(s[0], s[1])

## Piezas animadas: barra de plazas, punto de estado, radar, anillo y brillo del botón.
func _build_fx() -> void:
	slot_bar = Fx.SlotBar.new()
	slot_bar.name = "SlotBar"
	slot_bar.custom_minimum_size = Vector2(70, 6)
	slot_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slot_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	%Meta.add_child(slot_bar)
	%Meta.move_child(slot_bar, count_label.get_index() + 1)
	status_dot = Fx.PulseDot.new()
	status_dot.name = "StatusDot"
	status_dot.custom_minimum_size = Vector2(9, 9)
	status_dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	%StatusChipRow.add_child(status_dot)
	%StatusChipRow.move_child(status_dot, 0)
	radar = Fx.Radar.new()
	radar.name = "Radar"
	radar.custom_minimum_size = Vector2(46, 46)
	radar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	%QueueTop.add_child(radar)
	%QueueTop.move_child(radar, 0)
	countdown = Fx.Ring.new()
	countdown.name = "CountdownRing"
	countdown.custom_minimum_size = Vector2(26, 26)
	countdown.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	%StatusRow.add_child(countdown)
	%StatusRow.move_child(countdown, 0)
	_shine = Fx.Shine.new()
	_shine.name = "Shine"
	_shine.radius = 16.0
	_shine.inset = Vector2(1, 1)
	start_button.add_child(_shine)
	start_button.move_child(_shine, 0)
	# El brillo no cubre el labio de abajo.
	_shine.offset_bottom = -6
	for b in [start_button, options_button, share_button, quick_button, create_button, join_button, cancel_queue_button, chat_send, copy_button]:
		Fx.juice(b)
	# "CONFIDENCIAL": sello sobre la miniatura del caso.
	var stamp := Label.new()
	stamp.name = "Stamp"
	stamp.text = "CONFIDENCIAL"
	stamp.add_theme_font_override("font", UiPalette.heading_font())
	stamp.add_theme_font_size_override("font_size", 9)
	stamp.add_theme_color_override("font_color", Color("#FF6B6B"))
	var stamp_style := UiPalette.flat(Color(0.35, 0.02, 0.05, 0.55), Color("#FF6B6B"), 1, 3, 2)
	stamp_style.content_margin_left = 4
	stamp_style.content_margin_right = 4
	stamp.add_theme_stylebox_override("normal", stamp_style)
	stamp.position = Vector2(30, 56)
	stamp.rotation = -0.18
	%CaseThumb.add_child(stamp)
	var divider: Control = %Divider
	divider.draw.connect(func() -> void:
		var h := divider.size.y
		divider.draw_polyline_colors(PackedVector2Array([Vector2(0.5, 4), Vector2(0.5, h * 0.5), Vector2(0.5, h - 4)]),
			PackedColorArray([Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.22), Color(1, 1, 1, 0.0)]), 1.0))

func _style() -> void:
	var panel = GlassBox.panel(16.0, 10.0)
	for p in [%PlayersPanel, %CasePanel, %ChatPanel]:
		p.add_theme_stylebox_override("panel", panel)
	var card = GlassBox.panel(18.0, 12.0)
	card.border_top = Color(UiPalette.AMBER, 0.55)
	card.border_bottom = Color(1, 1, 1, 0.05)
	card.with_glow(Color(UiPalette.AMBER, 0.08), 18)
	card.content_margin_top = 11
	card.content_margin_bottom = 11
	room_card.add_theme_stylebox_override("panel", card)
	var dock_style = GlassBox.panel(20.0, 8.0)
	dock_style.content_margin_left = 10
	dock_style.content_margin_right = 10
	dock.add_theme_stylebox_override("panel", dock_style)
	title_label.add_theme_font_override("font", UiPalette.heading_font())
	title_label.add_theme_font_size_override("font_size", 16)
	title_label.add_theme_color_override("font_color", Color("#F8FAFC"))
	title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title_label.max_lines_visible = 2
	title_label.add_theme_constant_override("line_spacing", -3)
	room_label.add_theme_color_override("font_color", DIM)
	room_label.add_theme_font_size_override("font_size", 12)
	count_label.add_theme_font_override("font", UiPalette.bold_font())
	count_label.add_theme_font_size_override("font_size", 13)
	# Código: monoespaciada grande con letras separadas, en una placa hundida.
	var mono := FontVariation.new()
	mono.base_font = UiPalette.mono_font()
	mono.spacing_glyph = 3
	mono.variation_embolden = 0.6
	code_label.add_theme_font_override("font", mono)
	code_label.add_theme_font_size_override("font_size", 25)
	code_label.add_theme_color_override("font_color", Color("#FFF4D6"))
	code_label.add_theme_color_override("font_shadow_color", Color(UiPalette.AMBER, 0.45))
	code_label.add_theme_constant_override("shadow_outline_size", 6)
	code_label.add_theme_constant_override("shadow_offset_x", 0)
	code_label.add_theme_constant_override("shadow_offset_y", 0)
	var plate = GlassBox.make(Color(0, 0, 0, 0.45), Color(0, 0, 0, 0.25), 10.0, 2.0)
	plate.border_top = Color(0, 0, 0, 0.5)
	plate.border_bottom = Color(UiPalette.AMBER, 0.45)
	plate.shadow_size = 0
	plate.content_margin_left = 8
	plate.content_margin_right = 4
	%CodePlate.add_theme_stylebox_override("panel", plate)
	for cap in [%CodeCaption, %CaseCaption]:
		cap.add_theme_font_override("font", UiPalette.bold_font())
		cap.add_theme_font_size_override("font_size", 10)
		cap.add_theme_color_override("font_color", DIM)
	%CodeCaption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_chip_label.add_theme_font_size_override("font_size", 10)
	status_chip_label.add_theme_font_override("font", UiPalette.bold_font())
	for t in [players_title, %ChatTitle, %QueueTitle]:
		t.add_theme_font_override("font", UiPalette.heading_font())
		t.add_theme_font_size_override("font_size", 13)
		t.add_theme_color_override("font_color", Color("#F1F5F9"))
	%QueueTitle.add_theme_color_override("font_color", Color("#BFF6FF"))
	players_count.add_theme_font_override("font", UiPalette.mono_font())
	players_count.add_theme_font_size_override("font_size", 12)
	players_count.add_theme_color_override("font_color", Color("#FFD27A"))
	%ChatOnline.add_theme_font_size_override("font_size", 11)
	%ChatOnline.add_theme_color_override("font_color", DIM)
	queue_label.add_theme_font_size_override("font_size", 12)
	queue_label.add_theme_color_override("font_color", Color("#E2E8F0"))
	_button_style(share_button, UiPalette.AMBER)
	_button_style(quick_button, UiPalette.CYAN, true)
	_button_style(create_button, Color("#A5B4FC"))
	_button_style(join_button, UiPalette.AMBER)
	_button_style(cancel_queue_button, UiPalette.CRIMSON)
	_flat_icon_button(copy_button)
	copy_button.add_child(_centered_icon("copy", Color("#FFD27A"), 16))
	_icon_label(share_button, "share", "Compartir", Color("#FFE7A8"))
	_icon_label(quick_button, "play", "Partida rápida", Color("#CFFAFE"))
	_icon_label(create_button, "lock", "Crear sala privada", Color("#E0E7FF"))
	_icon_label(cancel_queue_button, "door", "Cancelar búsqueda", Color("#FFE4E6"))
	join_button.add_theme_color_override("font_color", Color("#FFE7A8"))
	chat_send.add_child(_centered_icon("chat", INK, 17))
	var send_n = GlassBox.make(Color("#FFD567"), Color("#F0A92A"), 10.0, 6.0)
	send_n.border_top = Color(1, 1, 1, 0.6)
	send_n.border_bottom = Color(0, 0, 0, 0)
	send_n.shadow_size = 6
	var send_h = GlassBox.make(Color("#FFE38A"), Color("#F5B544"), 10.0, 6.0)
	send_h.shadow_size = 6
	var send_d = GlassBox.make(Color(UiPalette.AMBER, 0.25), Color(UiPalette.AMBER, 0.15), 10.0, 6.0)
	send_d.shadow_size = 0
	send_d.border_top = Color(1, 1, 1, 0.08)
	for s in [["normal", send_n], ["hover", send_h], ["pressed", send_n], ["disabled", send_d], ["focus", StyleBoxEmpty.new()]]:
		chat_send.add_theme_stylebox_override(s[0], s[1])
	for field in [chat_input, code_input]:
		var n = GlassBox.make(Color(0, 0, 0, 0.42), Color(0, 0, 0, 0.28), 10.0, 8.0)
		n.border_top = Color(0, 0, 0, 0.55)
		n.border_bottom = Color(1, 1, 1, 0.12)
		n.shadow_size = 0
		var f = GlassBox.make(Color(0, 0, 0, 0.5), Color(0, 0, 0, 0.35), 10.0, 8.0)
		f.border_top = Color(UiPalette.AMBER, 0.9)
		f.border_bottom = Color(UiPalette.AMBER, 0.5)
		f.shadow_size = 0
		f.with_glow(Color(UiPalette.AMBER, 0.25), 6)
		var ro = GlassBox.make(Color(0, 0, 0, 0.25), Color(0, 0, 0, 0.18), 10.0, 8.0)
		ro.border_top = Color(1, 1, 1, 0.04)
		ro.border_bottom = Color(1, 1, 1, 0.06)
		ro.shadow_size = 0
		field.add_theme_stylebox_override("normal", n)
		field.add_theme_stylebox_override("focus", f)
		field.add_theme_stylebox_override("read_only", ro)
		field.add_theme_font_size_override("font_size", 13)
		field.add_theme_color_override("font_placeholder_color", Color(1, 1, 1, 0.35))
	code_input.add_theme_font_override("font", UiPalette.mono_font())
	# Opciones: botón cuadrado de cristal.
	var opt_n = GlassBox.inset(14.0, 6.0, 1.4)
	var opt_h = GlassBox.inset(14.0, 6.0, 2.4)
	var opt_p = GlassBox.inset(14.0, 6.0, 3.0)
	opt_p.border_top = Color(UiPalette.AMBER, 0.9)
	for s in [["normal", opt_n], ["hover", opt_h], ["pressed", opt_p], ["focus", StyleBoxEmpty.new()]]:
		options_button.add_theme_stylebox_override(s[0], s[1])
	%OptionsLabel.add_theme_font_size_override("font_size", 11)
	%OptionsLabel.add_theme_font_override("font", UiPalette.bold_font())
	%OptionsLabel.add_theme_color_override("font_color", Color("#CBD5E1"))
	# Botón grande: degradado con relieve, brillo que barre y rebote (ver _set_cta).
	start_label.add_theme_font_override("font", UiPalette.heading_font())
	start_label.add_theme_font_size_override("font_size", 28)
	status_label.add_theme_font_size_override("font_size", 12)
	status_label.add_theme_font_override("font", UiPalette.bold_font())
	status_label.add_theme_color_override("font_color", Color("#E2E8F0"))

## Botón de acento de cristal (cian, ámbar, rojo...) con brillo al pasar.
func _button_style(b: Button, c: Color, strong := false) -> void:
	var n = GlassBox.accent(c, 10.0, 6.0, 1.3 if strong else 1.0)
	var h = GlassBox.accent(c, 10.0, 6.0, 1.8 if strong else 1.5)
	h.with_glow(Color(c, 0.3), 8)
	var p = GlassBox.accent(c, 10.0, 6.0, 2.2)
	var d = GlassBox.accent(c, 10.0, 6.0, 0.35)
	d.shadow_size = 0
	if strong:
		n.with_glow(Color(c, 0.18), 8)
	for s in [["normal", n], ["hover", h], ["pressed", p], ["disabled", d], ["focus", StyleBoxEmpty.new()]]:
		b.add_theme_stylebox_override(s[0], s[1])
	b.add_theme_color_override("font_color", UiPalette.TEXT)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_disabled_color", Color(UiPalette.TEXT, 0.4))
	b.add_theme_font_size_override("font_size", 13)

func _flat_icon_button(b: Button) -> void:
	var n := StyleBoxEmpty.new()
	var h = GlassBox.inset(8.0, 2.0, 2.0)
	for s in [["normal", n], ["hover", h], ["pressed", h], ["focus", StyleBoxEmpty.new()]]:
		b.add_theme_stylebox_override(s[0], s[1])

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
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_font_override("font", UiPalette.bold_font())
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

## La barra de la mascota con el mismo cristal que el resto de la sala.
func _style_pet() -> void:
	pet_panel.add_theme_stylebox_override("panel", GlassBox.panel(16.0, 8.0))
	for b in [pet_panel.feed_button, pet_panel.drink_button]:
		_button_style(b, UiPalette.AMBER)
		b.custom_minimum_size = Vector2(76, 50)
		Fx.juice(b)
