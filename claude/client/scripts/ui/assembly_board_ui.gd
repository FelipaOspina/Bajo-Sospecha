class_name AssemblyBoardUI
extends CanvasLayer
## Mesa de juntas (fase de juicio / asamblea). Dibuja lo que mantiene TrialAssemblyManager:
##   TopBar             temporizador de la asamblea y título de la fase
##   SeatingOrbit       un asiento por jugador alrededor de la mesa (tú abajo)
##   EvidenceDropZone   centro de la mesa: suelta aquí cartas de tu mano; muestra la
##                      última prueba expuesta en su marco (terminal, celular, papel)
##   BottomDrawer       tu mano de pruebas + panel de votación de expulsión
##
## Quién la muestra y la oculta: PhaseViewController (al cambiar la fase del servidor).
## Exponer: la UI emite evidence_presented(evidence_data, player_id) con la carta elegida
## (arrastre al centro o ExposeActionBtn); Main la conecta a TrialAssemblyManager.present,
## que la envía al servidor. Cuando el servidor la pone en la mesa, TrialAssemblyManager
## emite su propio evidence_presented y aquí se muestra en el centro.
##
## Los asientos muestran nombre, si ya votó y cuántas pruebas expuso. NO muestran
## roles ni a quién acusa cada voto: eso es secreto hasta la resolución, y entonces
## se marca con AccusationPinMarker a quien resultó acusado.

## El jugador local quiere exponer esta carta de su mano.
signal evidence_presented(evidence_data: EvidenceData, player_id: String)

const PHASE_TITLE := "ASAMBLEA EXTRAORDINARIA DEL DIRECTORIO"
const PHASE_SUBTITLES := {
	"discussion": "Debate: arrastra tus pruebas al centro de la mesa",
	"voting": "Votación de expulsión",
}
const ABSTAIN := "abstain"
const URGENT_SECONDS := 30
const SEAT_ARC_FROM := 150.0   # grados (0 = derecha, 90 = abajo)
const SEAT_ARC_TO := 390.0

@export var trial: TrialSystem
@export var assembly: TrialAssemblyManager
@export var evidence_modal: EvidenceInspectionModal

var center_frame: EvidenceFrame
var focused_instance := ""   # carta de la mesa elegida para verla en el centro

@onready var _timer_card: PanelContainer = %TimerCard
@onready var _timer_label: Label = %AssemblyTimerLabel
@onready var _phase_title: Label = %PhaseTitleLabel
@onready var _phase_subtitle: Label = %PhaseSubtitleLabel
@onready var _orbit: Control = %SeatingOrbitContainer
@onready var _drop_zone: EvidenceDropZone = %EvidenceDropZone
@onready var _table_layout: VBoxContainer = %TableLayout
@onready var _center_caption: Label = %CenterCaption
@onready var _slots_row: HBoxContainer = %EvidenceSlots
@onready var _expose_btn: Button = %ExposeActionBtn
@onready var _drawer_panel: PanelContainer = %DrawerPanel
@onready var _hand_title: Label = %HandTitle
@onready var _hand_box: HBoxContainer = %HandCardsHBox
@onready var _status: Label = %StatusLabel
@onready var _vote_selector: OptionButton = %TargetVoteSelector
@onready var _accuse_btn: Button = %AccuseButton
@onready var _skip_btn: Button = %SkipVoteButton
@onready var _tally_label: Label = %VoteTallyLabel

func _ready() -> void:
	if assembly == null:
		assembly = TrialAssemblyManager.new()
		assembly.name = "TrialAssemblyManager"
		add_child(assembly)
		assembly.bind(trial)
	elif trial == null:
		trial = assembly.trial
	_drop_zone.can_accept = assembly.can_drop
	_drop_zone.on_drop = func(data: Variant) -> void: request_present(str(data.get("instance_id", "")))
	_style()
	hide()
	_expose_btn.pressed.connect(func() -> void:
		if assembly.selected:
			request_present(assembly.selected.instance_id))
	_accuse_btn.pressed.connect(_on_accuse_pressed)
	_skip_btn.pressed.connect(func() -> void: assembly.accuse(ABSTAIN))
	_vote_selector.item_selected.connect(func(_i: int) -> void: _refresh_vote_buttons())
	_orbit.resized.connect(_layout_seats)
	trial.changed.connect(_refresh)
	assembly.selection_changed.connect(func(_e: EvidenceData) -> void: _refresh())
	assembly.action_failed.connect(func(reason: String) -> void: _status.text = reason)
	assembly.evidence_presented.connect(_on_placed)
	_refresh()

# ───── API ─────

## Despliega la mesa (la llama PhaseViewController al entrar en debate / votación).
func open_board() -> void:
	show()
	_refresh()

func close_board() -> void:
	hide()

## Pide exponer una carta de la mano: valida y emite evidence_presented.
func request_present(instance_id: String) -> bool:
	var why := assembly.why_not_present(instance_id)
	if why != "":
		_status.text = why
		return false
	var e := assembly.find_in_inventory(instance_id)
	assembly.clear_selection()
	evidence_presented.emit(e, GameState.local_player_id())
	return true

func _process(_d: float) -> void:
	if not visible:
		return
	var ends = GameState.snapshot.get("phaseEndsAt")
	if ends == null:
		_timer_label.text = "--:--"
		return
	var left := maxi(0, int((float(ends) - Network.server_time_ms()) / 1000.0))
	_timer_label.text = "%02d:%02d" % [left / 60, left % 60]
	_timer_label.add_theme_color_override("font_color", UiPalette.CRIMSON if left <= URGENT_SECONDS else UiPalette.AMBER)

# ───── Refresco ─────

func _refresh() -> void:
	if not visible:
		return
	_phase_subtitle.text = PHASE_SUBTITLES.get(trial.phase(), Protocol.PHASE_LABELS.get(trial.phase(), ""))
	_refresh_seats()
	_refresh_hand()
	_refresh_table()
	_refresh_votes()

func _on_placed(e: EvidenceData, player_id: String) -> void:
	focused_instance = e.instance_id
	_status.text = "%s coloca «%s» sobre la mesa." % [trial.player_name(player_id), e.display_name]
	_refresh_table()

## Un asiento por jugador. El orden es el del servidor, rotado para que tú quedes abajo.
func _refresh_seats() -> void:
	_clear(_orbit)
	var players := GameState.players()
	var me := GameState.local_player_id()
	var start := 0
	for i in players.size():
		if players[i]["id"] == me:
			start = i
	var accused: Array = trial.resolution.get("verdict", {}).get("accused", []) if not trial.resolution.is_empty() else []
	for k in players.size():
		var p: Dictionary = players[(start + k) % players.size()]
		_orbit.add_child(_seat(p, p["id"] in trial.voted, p["id"] in accused))
	_layout_seats()

func _seat(p: Dictionary, has_voted: bool, is_accused: bool) -> VBoxContainer:
	var seat := VBoxContainer.new()
	seat.name = "Seat_" + str(p["id"]).left(8)
	seat.alignment = BoxContainer.ALIGNMENT_CENTER
	seat.mouse_filter = Control.MOUSE_FILTER_IGNORE
	seat.custom_minimum_size = Vector2(110, 0)

	var avatar := PanelContainer.new()
	avatar.name = "AvatarCard"
	avatar.custom_minimum_size = Vector2(56, 56)
	avatar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var hue := float(hash(p["id"]) % 360) / 360.0
	var outline := UiPalette.CRIMSON if is_accused else (UiPalette.AMBER if has_voted else Color(UiPalette.AMBER, 0.2))
	avatar.add_theme_stylebox_override("panel", UiPalette.flat(Color.from_hsv(hue, 0.45, 0.55), outline, 3 if has_voted or is_accused else 1, 28, 0))
	var initial := Label.new()
	initial.text = str(p.get("name", "?")).left(1).to_upper()
	initial.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	initial.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	initial.add_theme_font_override("font", UiPalette.heading_font())
	initial.add_theme_font_size_override("font_size", 22)
	avatar.add_child(initial)
	seat.add_child(avatar)

	var tag := _label(str(p.get("name", "?")) + (" (tú)" if p["id"] == GameState.local_player_id() else ""))
	tag.name = "PlayerNameTag"
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	seat.add_child(tag)

	var presented := trial.deck.filter(func(c: Dictionary) -> bool: return c["presentedBy"] == p["id"]).size()
	var info := _label(("votó · " if has_voted else "") + ("%d prueba%s" % [presented, "" if presented == 1 else "s"]), true)
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info.add_theme_font_size_override("font_size", 11)
	seat.add_child(info)

	var pin := _label("📌 ACUSADO")
	pin.name = "AccusationPinMarker"
	pin.visible = is_accused
	pin.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pin.add_theme_color_override("font_color", UiPalette.CRIMSON)
	seat.add_child(pin)
	return seat

## Reparte los asientos en un arco alrededor de la mesa: de abajo a la izquierda (tú),
## por arriba, hasta abajo a la derecha. El hueco de abajo queda para tu mano y la votación.
func _layout_seats() -> void:
	var seats := _orbit.get_children()
	if seats.is_empty():
		return
	var area := _orbit.size
	var center := area / 2.0
	var radius := Vector2(area.x * 0.42, area.y * 0.42)
	var first := deg_to_rad(SEAT_ARC_FROM)
	var span := deg_to_rad(SEAT_ARC_TO - SEAT_ARC_FROM)
	for i in seats.size():
		var seat: Control = seats[i]
		var angle := first + (span * i / (seats.size() - 1) if seats.size() > 1 else span / 2.0)
		var at := center + Vector2(cos(angle) * radius.x, sin(angle) * radius.y)
		seat.reset_size()
		seat.position = at - seat.size / 2.0

func _refresh_hand() -> void:
	_clear(_hand_box)
	_hand_title.text = "TU MANO · %d/%d expuestas" % [trial.presented_by_me(), trial.max_presented]
	var mine := assembly.player_inventory()
	if mine.is_empty():
		_hand_box.add_child(_label("No tienes pruebas que exponer.", true))
	for e in mine:
		var card := EvidenceCard.new().setup(e, trial.can_present())
		card.custom_minimum_size = Vector2(170, 0)
		card.selected = assembly.selected != null and assembly.selected.instance_id == e.instance_id
		card.picked.connect(func(ev: EvidenceData) -> void: assembly.select(ev.instance_id))
		card.inspect.connect(_inspect)
		_hand_box.add_child(card)

func _refresh_table() -> void:
	var cards := assembly.table()
	var card := {}
	for c in cards:
		if c["instanceId"] == focused_instance:
			card = c
	if card.is_empty():
		card = assembly.center_card()
	if card.is_empty():
		if center_frame:
			center_frame.hide()
		_center_caption.text = "Arrastra aquí una prueba de tu mano para exponerla ante el directorio."
	else:
		var e: EvidenceData = card["evidence"]
		_use_center_frame(EvidenceFrames.frame_for(e))
		center_frame.show()
		center_frame.show_evidence(e)
		_center_caption.text = "%s — expuesta por %s" % [e.display_name, trial.player_name(card["presentedBy"])]

	_clear(_slots_row)
	for i in cards.size():
		var c: Dictionary = cards[i]
		var slot := EvidenceCard.new().setup(c["evidence"], false, "por %s" % trial.player_name(c["presentedBy"]))
		slot.name = "SlotEvidence_%d" % (i + 1)
		slot.custom_minimum_size = Vector2(150, 0)
		slot.compact = true
		slot.selected = not card.is_empty() and c["instanceId"] == card["instanceId"]
		slot.picked.connect(_focus)
		slot.inspect.connect(_inspect)
		_slots_row.add_child(slot)

	_fit_table.call_deferred()
	_expose_btn.disabled = assembly.selected == null or not trial.can_present()
	_expose_btn.text = "Colocar «%s» en la mesa" % assembly.selected.display_name if assembly.selected else "Colocar Prueba en la Mesa"

## Igual que en el modal: tras cambiar la prueba del centro, la mesa vuelve a su tamaño mínimo.
func _fit_table() -> void:
	var area := _drop_zone.get_parent() as Control
	area.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	area.offset_top = 70.0
	area.offset_bottom = -190.0
	_drop_zone.reset_size()

func _refresh_votes() -> void:
	var previous: Variant = _selected_option()
	_vote_selector.clear()
	var public := assembly.votes_public()
	var has_abstain := false
	for o in assembly.options():
		if o["id"] == ABSTAIN:
			has_abstain = true
			continue
		var text := ("● " if trial.my_vote == o["id"] else "") + str(o["label"])
		if public:
			text += "  ·  %d" % assembly.votes_for(o["id"])
		_vote_selector.add_item(text)
		_vote_selector.set_item_metadata(_vote_selector.item_count - 1, o["id"])
		_vote_selector.set_item_tooltip(_vote_selector.item_count - 1, str(o.get("description", "")))
	var want: Variant = trial.my_vote if trial.my_vote != null and trial.my_vote != ABSTAIN else previous
	for i in _vote_selector.item_count:
		if _vote_selector.get_item_metadata(i) == want:
			_vote_selector.select(i)
	_skip_btn.visible = has_abstain
	_skip_btn.text = ("● " if trial.my_vote == ABSTAIN else "") + "Abstenerse" + \
		("  ·  %d" % assembly.votes_for(ABSTAIN) if public and has_abstain else "")
	_vote_selector.disabled = not assembly.can_accuse()
	_skip_btn.disabled = not assembly.can_accuse()
	_refresh_vote_buttons()
	if not assembly.can_accuse():
		_tally_label.text = "La votación se abre al terminar el debate."
	else:
		_tally_label.text = "Han votado %d de %d" % [assembly.voted_count(), GameState.players().size()]
		if not public:
			_tally_label.text += " · votos secretos hasta el final"

func _refresh_vote_buttons() -> void:
	var target: Variant = _selected_option()
	_accuse_btn.disabled = not assembly.can_accuse() or target == null
	_accuse_btn.text = "Retirar mi voto" if target != null and target == trial.my_vote else "Confirmar Voto de Expulsión"

func _selected_option() -> Variant:
	var i := _vote_selector.selected
	return _vote_selector.get_item_metadata(i) if i >= 0 and i < _vote_selector.item_count else null

func _on_accuse_pressed() -> void:
	var target: Variant = _selected_option()
	if target != null:
		assembly.accuse(target)

func _focus(e: EvidenceData) -> void:
	focused_instance = e.instance_id
	_refresh_table()

func _inspect(e: EvidenceData) -> void:
	if evidence_modal:
		evidence_modal.open_evidence(e)

func _use_center_frame(id: String) -> void:
	if center_frame and center_frame.frame_id() == id:
		return
	if center_frame:
		_table_layout.remove_child(center_frame)
		center_frame.queue_free()
	center_frame = EvidenceFrames.create(id)
	center_frame.name = "CenterEvidence"
	center_frame.custom_minimum_size = Vector2(0, 100)
	center_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_table_layout.add_child(center_frame)
	_table_layout.move_child(center_frame, 0)

# ───── Estilo ─────

func _style() -> void:
	(%Background as ColorRect).color = UiPalette.NAVY
	_timer_card.add_theme_stylebox_override("panel", UiPalette.glass_panel(8, 10))
	_timer_label.add_theme_font_override("font", UiPalette.mono_font())
	_timer_label.add_theme_color_override("font_color", UiPalette.AMBER)
	_phase_title.text = PHASE_TITLE
	_phase_title.add_theme_font_override("font", UiPalette.heading_font())
	_phase_title.add_theme_color_override("font_color", UiPalette.TEXT)
	_phase_subtitle.add_theme_color_override("font_color", UiPalette.AMBER)
	_center_caption.add_theme_color_override("font_color", UiPalette.TEXT_DIM)
	_drawer_panel.add_theme_stylebox_override("panel", UiPalette.glass_panel(10, 12))
	_hand_title.add_theme_font_override("font", UiPalette.heading_font())
	_hand_title.add_theme_color_override("font_color", UiPalette.AMBER)
	_status.add_theme_color_override("font_color", UiPalette.AMBER)
	_tally_label.add_theme_color_override("font_color", UiPalette.TEXT_DIM)
	UiPalette.style_button(_expose_btn, UiPalette.AMBER)
	UiPalette.style_button(_accuse_btn, UiPalette.CRIMSON)
	UiPalette.style_button(_skip_btn, UiPalette.TEXT)

func _label(text: String, secondary := false) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_color_override("font_color", UiPalette.TEXT_DIM if secondary else UiPalette.TEXT)
	return l

static func _clear(n: Node) -> void:
	for c in n.get_children():
		n.remove_child(c)
		c.queue_free()
