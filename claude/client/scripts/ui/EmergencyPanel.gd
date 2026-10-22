class_name EmergencyPanel
extends CanvasLayer
## Asamblea de emergencia (fase "emergency", la abre reportar un cuerpo). Pantalla
## completa sobre el mapa en pausa, con la estética de alarma de la oficina:
##  - quién la convocó y de quién era el cuerpo; cuenta atrás (snapshot.emergency.endsAt);
##  - una tarjeta por jugador en pie (retrato de su animal y nombre; NUNCA el rol), con
##    la marca de si ya ha votado y, en la tuya, tu voto. Clic = votar a esa persona,
##    otra vez = retirar el voto; "Saltar voto" = no expulsar a nadie;
##  - lo que has visto (registro de testigo), que es tu argumento;
##  - el chat de la asamblea (columna derecha, bajo lo que has visto): escriben los vivos;
##    los fantasmas lo leen pero no escriben (el servidor responde not_alive);
##  - el resultado: "X fue expulsado" o "Nadie fue expulsado" con el recuento.
## Los fantasmas la ven pero no votan. El servidor decide (mayoría estricta).
## Hasta 12 jugadores: 4 columnas hasta 8, 6 columnas con más.

const URGENT_SECONDS := 10
const CARD_SIZE := Vector2(150, 150)
const CARD_SIZE_SMALL := Vector2(128, 128)
const CHAT_MAX_LINES := 40

var network: Node              # Network o un doble en las pruebas

var root: Control
var title: Label
var subtitle: Label
var timer_label: Label
var grid: GridContainer
var skip_button: Button
var status_label: Label
var result_label: Label
var witness_box: VBoxContainer
var witness_panel: PanelContainer
var chat_panel: PanelContainer
var chat_lines: VBoxContainer
var chat_scroll: ScrollContainer
var chat_input: LineEdit
var chat_send: Button

var _signature := ""
var _cards := {}               # player_id -> Button

func _ready() -> void:
	layer = 8
	if network == null:
		network = Network
	_build()
	visible = false
	GameState.snapshot_applied.connect(func(_s: Dictionary) -> void: refresh())
	EventBus.chat_received.connect(_on_chat_received)

func open_panel() -> void:
	visible = true
	EventBus.ui_modal_changed.emit(true)
	_signature = ""
	clear_chat()
	refresh()

func close_panel() -> void:
	if visible:
		EventBus.ui_modal_changed.emit(false)
	visible = false

func _build() -> void:
	root = Control.new()
	root.name = "Root"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.04, 0.09, 0.97)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	# Franjas de alarma arriba y abajo.
	for top in [true, false]:
		var stripe := ColorRect.new()
		stripe.color = Color(UiPalette.CRIMSON, 0.85)
		stripe.anchor_right = 1.0
		stripe.anchor_top = 0.0 if top else 1.0
		stripe.anchor_bottom = 0.0 if top else 1.0
		stripe.offset_top = 0.0 if top else -6.0
		stripe.offset_bottom = 6.0 if top else 0.0
		root.add_child(stripe)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 40)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_bottom", 22)
	root.add_child(margin)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	margin.add_child(col)

	var head := HBoxContainer.new()
	col.add_child(head)
	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.add_theme_constant_override("separation", 0)
	head.add_child(titles)
	title = _label("ASAMBLEA DE EMERGENCIA", 34, UiPalette.CRIMSON, UiPalette.heading_font())
	title.name = "Title"
	titles.add_child(title)
	subtitle = _label("", 17, UiPalette.TEXT)
	subtitle.name = "Subtitle"
	titles.add_child(subtitle)
	timer_label = _label("--:--", 40, UiPalette.AMBER, UiPalette.mono_font())
	timer_label.name = "Timer"
	head.add_child(timer_label)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 18)
	col.add_child(body)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(center)
	grid = GridContainer.new()
	grid.name = "Grid"
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	center.add_child(grid)

	# Columna derecha: lo que has visto y, debajo, el chat de la asamblea.
	var side := VBoxContainer.new()
	side.name = "Side"
	side.custom_minimum_size.x = 280
	side.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_theme_constant_override("separation", 10)
	body.add_child(side)
	witness_panel = PanelContainer.new()
	witness_panel.add_theme_stylebox_override("panel", UiPalette.flat(Color(0.10, 0.04, 0.07, 0.85), Color(UiPalette.CRIMSON, 0.5), 1, 12, 12))
	witness_panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	side.add_child(witness_panel)
	witness_box = VBoxContainer.new()
	witness_box.name = "Witness"
	witness_panel.add_child(witness_box)
	_build_chat(side)

	result_label = _label("", 30, Color.WHITE, UiPalette.heading_font())
	result_label.name = "Result"
	result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_label.add_theme_constant_override("outline_size", 8)
	col.add_child(result_label)

	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 16)
	col.add_child(foot)
	status_label = _label("", 15, UiPalette.TEXT_DIM)
	status_label.name = "Status"
	status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(status_label)
	skip_button = Button.new()
	skip_button.name = "SkipButton"
	skip_button.text = "Saltar voto"
	skip_button.custom_minimum_size = Vector2(200, 46)
	skip_button.focus_mode = Control.FOCUS_NONE
	UiPalette.style_button(skip_button, UiPalette.AMBER)
	skip_button.pressed.connect(func() -> void: vote(Protocol.EMERGENCY_SKIP))
	foot.add_child(skip_button)

func _build_chat(parent: Control) -> void:
	chat_panel = PanelContainer.new()
	chat_panel.name = "Chat"
	chat_panel.add_theme_stylebox_override("panel", UiPalette.flat(Color(0.05, 0.07, 0.13, 0.9), Color(1, 1, 1, 0.18), 1, 12, 10))
	chat_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	chat_panel.custom_minimum_size.y = 150
	parent.add_child(chat_panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	chat_panel.add_child(col)
	col.add_child(_label("CHAT DE LA ASAMBLEA", 14, UiPalette.AMBER, UiPalette.heading_font()))
	chat_scroll = ScrollContainer.new()
	chat_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	chat_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(chat_scroll)
	chat_lines = VBoxContainer.new()
	chat_lines.name = "Lines"
	chat_lines.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chat_lines.add_theme_constant_override("separation", 3)
	chat_scroll.add_child(chat_lines)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	col.add_child(row)
	chat_input = LineEdit.new()
	chat_input.name = "ChatInput"
	chat_input.placeholder_text = "Defiende tu voto…"
	chat_input.max_length = 200
	chat_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chat_input.text_submitted.connect(send_chat)
	row.add_child(chat_input)
	chat_send = Button.new()
	chat_send.name = "ChatSend"
	chat_send.text = "Enviar"
	chat_send.focus_mode = Control.FOCUS_NONE
	UiPalette.style_button(chat_send, UiPalette.AMBER)
	chat_send.pressed.connect(func() -> void: send_chat(chat_input.text))
	row.add_child(chat_send)

func _label(t: String, font_size: int, color: Color, font: Font = null) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	if font:
		l.add_theme_font_override("font", font)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

# ───────────── Estado ─────────────

func emergency() -> Dictionary:
	return GameState.emergency()

## Jugadores en pie que se pueden votar (vivos, no fantasmas ni ocultos).
func candidates() -> Array:
	return GameState.players().filter(func(p): return p.get("alive", true) != false and not p.get("ghost", false) and not p.get("hidden", false))

func can_vote() -> bool:
	var e := emergency()
	return GameState.phase() == "emergency" and not e.is_empty() and not e.get("result") is Dictionary \
		and not GameState.is_ghost() and GameState.public_player(GameState.local_player_id()).get("alive", true) != false

func my_vote() -> String:
	var v = emergency().get("myVote")
	return "" if v == null else str(v)

static func result_text(expelled: String) -> String:
	return "%s fue expulsado" % GameState.player_name(expelled) if expelled != "" else "Nadie fue expulsado"

## Vota a un jugador o "skip"; repetir el mismo voto lo retira.
func vote(target: String) -> void:
	if not can_vote():
		return
	var payload := {"targetId": null if target == my_vote() else target}
	network.send_intent(Protocol.I_EMERGENCY_VOTE, payload)

## Los vivos escriben en la asamblea; los fantasmas solo leen.
func can_chat() -> bool:
	return GameState.phase() == "emergency" and not GameState.is_ghost()

func send_chat(text: String) -> void:
	var clean := text.strip_edges()
	if clean.is_empty() or not can_chat():
		return
	if network.send_intent(Protocol.I_CHAT, {"text": clean}) >= 0:
		chat_input.clear()

func clear_chat() -> void:
	for c in chat_lines.get_children():
		chat_lines.remove_child(c)
		c.queue_free()

func chat_texts() -> Array:
	return chat_lines.get_children().filter(func(c): return not c.is_queued_for_deletion()).map(func(c): return (c as RichTextLabel).get_parsed_text())

func _on_chat_received(by: String, author: String, text: String, _at: int) -> void:
	if GameState.phase() != "emergency":
		return
	var line := RichTextLabel.new()
	line.bbcode_enabled = true
	line.fit_content = true
	line.scroll_active = false
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_theme_font_size_override("normal_font_size", 13)
	var color: Color = UiPalette.AMBER if by == GameState.local_player_id() else Color("#7DD3FC")
	line.text = "[color=#%s]%s:[/color] %s" % [color.to_html(false), author.replace("[", "[lb]"), text.replace("[", "[lb]")]
	chat_lines.add_child(line)
	while chat_lines.get_child_count() > CHAT_MAX_LINES:
		var old := chat_lines.get_child(0)
		chat_lines.remove_child(old)
		old.queue_free()
	_scroll_chat_to_end.call_deferred()

func _scroll_chat_to_end() -> void:
	if chat_scroll and is_inside_tree():
		await get_tree().process_frame
		chat_scroll.scroll_vertical = int(chat_scroll.get_v_scroll_bar().max_value)

func card(player_id: String) -> Button:
	return _cards.get(player_id)

# ───────────── Refresco ─────────────

func refresh() -> void:
	if not visible:
		return
	var e := emergency()
	var called_by := str(e.get("calledBy", "")) if e.get("calledBy") != null else ""
	var body_id := str(e.get("bodyId", "")) if e.get("bodyId") != null else ""
	var victim := ""
	for b in GameState.bodies():
		if str(b.get("id", "")) == body_id:
			victim = str(b.get("playerId", ""))
	if victim == "" and body_id.begins_with("body:"):
		victim = body_id.trim_prefix("body:").get_slice("#", 0)
	if called_by != "" and victim != "":
		subtitle.text = "%s ha encontrado a %s. ¿Quién ha sido?" % [GameState.player_name(called_by), GameState.player_name(victim)]
	elif called_by != "":
		subtitle.text = "%s ha pulsado el botón de emergencia. ¿Quién ha sido?" % GameState.player_name(called_by)
	else:
		subtitle.text = "Votad a quién expulsar o saltad el voto."
	var result = e.get("result")
	var voted: Array = e.get("voted", []) if e.get("voted") is Array else []
	var tally: Dictionary = result.get("tally", {}) if result is Dictionary and result.get("tally") is Dictionary else {}
	var expelled := ""
	if result is Dictionary and result.get("expelled") != null:
		expelled = str(result["expelled"])
	var list := candidates()
	# Expulsado: ya no está "vivo", pero su tarjeta se queda para ver el resultado.
	if expelled != "" and list.filter(func(p): return p.get("id") == expelled).is_empty():
		list.append(GameState.public_player(expelled))
	var signature := JSON.stringify([list.map(func(p): return [p.get("id"), p.get("name"), p.get("skinId")]), voted, my_vote(), result, can_vote(), GameState.witness_log.size()])
	if signature == _signature:
		return
	_signature = signature
	grid.columns = 4 if list.size() <= 8 else 6
	var size := CARD_SIZE if list.size() <= 8 else CARD_SIZE_SMALL
	for c in grid.get_children():
		grid.remove_child(c)
		c.queue_free()
	_cards.clear()
	for p in list:
		var id := str(p.get("id", ""))
		var b := _card(p, size, id in voted, my_vote() == id, id == expelled, int(tally.get(id, 0)) if result is Dictionary else -1)
		grid.add_child(b)
		_cards[id] = b
	var vote_ok := can_vote()
	skip_button.disabled = not vote_ok
	skip_button.text = ("● " if my_vote() == Protocol.EMERGENCY_SKIP else "") + "Saltar voto" + \
		("  ·  %d" % int(tally.get(Protocol.EMERGENCY_SKIP, 0)) if result is Dictionary else "")
	if result is Dictionary:
		result_label.text = result_text(expelled)
		result_label.add_theme_color_override("font_color", UiPalette.CRIMSON if expelled != "" else UiPalette.AMBER)
		status_label.text = "Su rol no se revela. La investigación continúa."
	else:
		result_label.text = ""
		if GameState.is_ghost():
			status_label.text = "Los fantasmas no votan. Han votado %d de %d." % [voted.size(), candidates().size()]
		else:
			status_label.text = "Han votado %d de %d · hace falta mayoría para expulsar" % [voted.size(), candidates().size()]
	_refresh_witness()
	var chat_ok := can_chat()
	chat_input.editable = chat_ok
	chat_send.disabled = not chat_ok
	chat_input.placeholder_text = "Defiende tu voto…" if chat_ok else "Los fantasmas no pueden hablar"

func _card(p: Dictionary, size: Vector2, has_voted: bool, mine: bool, expelled: bool, votes: int) -> Button:
	var id := str(p.get("id", ""))
	var b := Button.new()
	b.name = "Card_" + id
	b.custom_minimum_size = size
	b.focus_mode = Control.FOCUS_NONE
	var accent := UiPalette.CRIMSON if expelled else (UiPalette.AMBER if mine else Color(1, 1, 1, 0.25))
	b.add_theme_stylebox_override("normal", UiPalette.flat(Color(0.08, 0.11, 0.19, 0.95), accent, 3 if mine or expelled else 1, 14, 6))
	b.add_theme_stylebox_override("hover", UiPalette.flat(Color(0.12, 0.16, 0.27, 0.98), UiPalette.AMBER, 2, 14, 6))
	b.add_theme_stylebox_override("pressed", UiPalette.flat(Color(UiPalette.AMBER, 0.3), UiPalette.AMBER, 2, 14, 6))
	b.add_theme_stylebox_override("disabled", UiPalette.flat(Color(0.08, 0.11, 0.19, 0.9), accent, 3 if mine or expelled else 1, 14, 6))
	b.disabled = not can_vote() or expelled
	b.pressed.connect(func() -> void: vote(id))
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 2)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(box)
	var head := SkinPreview.new()
	head.head_only = true
	var skin := str(p.get("skinId", ""))
	head.skin_id = skin if skin != "" else SkinCatalog.fallback_for(id)
	head.custom_minimum_size = Vector2(size.y * 0.5, size.y * 0.5)
	head.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.locked = expelled
	box.add_child(head)
	var name_label := _label(str(p.get("name", "?")) + (" (tú)" if id == GameState.local_player_id() else ""), 15, Color.WHITE, UiPalette.bold_font())
	name_label.name = "Name"
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	box.add_child(name_label)
	var tag := ""
	var tag_color := Color("#4ADE80")
	if expelled:
		tag = "EXPULSADO"
		tag_color = UiPalette.CRIMSON
	elif votes >= 0:
		tag = "%d voto%s" % [votes, "" if votes == 1 else "s"]
		tag_color = UiPalette.AMBER
	elif mine:
		tag = "TU VOTO"
		tag_color = UiPalette.AMBER
	elif has_voted:
		tag = "✓ HA VOTADO"
	var tag_label := _label(tag, 11, tag_color, UiPalette.bold_font())
	tag_label.name = "Tag"
	tag_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(tag_label)
	b.set_meta("voted", has_voted)
	return b

func _refresh_witness() -> void:
	for c in witness_box.get_children():
		witness_box.remove_child(c)
		c.queue_free()
	witness_box.add_child(_label("LO QUE HAS VISTO", 14, Color("#FCA5A5"), UiPalette.heading_font()))
	if GameState.witness_log.is_empty():
		var none := _label("No has visto a nadie silenciar a nadie.", 13, UiPalette.TEXT_DIM)
		none.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		none.custom_minimum_size.x = 220
		witness_box.add_child(none)
	for w in GameState.witness_log:
		var l := _label(SocialHUD.witness_line(w), 14, Color("#FECACA"))
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = 220
		witness_box.add_child(l)

func _process(_d: float) -> void:
	if not visible:
		return
	var ends = emergency().get("endsAt")
	if ends == null or emergency().get("result") is Dictionary:
		timer_label.text = "--:--" if ends == null else "00:00"
		return
	var left := maxi(0, int((float(ends) - Network.server_time_ms()) / 1000.0))
	timer_label.text = "%02d:%02d" % [left / 60, left % 60]
	timer_label.add_theme_color_override("font_color", UiPalette.CRIMSON if left <= URGENT_SECONDS else UiPalette.AMBER)
