class_name MainMenu
extends CanvasLayer
## Menú principal del juego (hub), encima del mapa mientras no hay partida en curso:
##  - Cabecera: tu perfil (animal, nombre, nivel y XP), Monedas Corporativas y Créditos
##    Nexus, Amigos, Correo, Configuración y el estado de la conexión.
##  - Pestañas a la izquierda: Sala, Personajes, Inventario, Misiones, Pase de Batalla,
##    Tienda, Gadgets y Configuración.
##  - La Sala (LobbyView) ocupa toda la oficina; el resto se abre en un panel.
## Se oculta cuando empieza la partida (fase distinta de lobby) y vuelve al salir de ella.
## Amigos, Correo y Gadgets son pantallas "Próximamente".
## Debajo de las pestañas, JUGAR lleva a la sala y entra en la cola pública desde
## cualquier pestaña (LobbyView.play).
## Ruta del Detective: pestaña con los niveles que enseñan a jugar, la práctica local
## «Primer día en NexusCore» (se ofrece la primera vez que se abre el juego), la barra de XP
## de la cabecera animada al subir de nivel, la celebración tras la partida y los consejos
## de las primeras partidas (MatchHints, un nodo hermano de este menú).

const TABS := [
	{"id": "sala", "label": "Sala", "icon": "users"},
	{"id": "ruta", "label": "Ruta del Detective", "icon": "search"},
	{"id": "personajes", "label": "Personajes", "icon": "user"},
	{"id": "inventario", "label": "Inventario", "icon": "bag"},
	{"id": "misiones", "label": "Misiones", "icon": "clipboard"},
	{"id": "pase", "label": "Pase de Batalla", "icon": "ticket"},
	{"id": "tienda", "label": "Tienda", "icon": "cart"},
	{"id": "gadgets", "label": "Gadgets", "icon": "chip"},
	{"id": "configuracion", "label": "Configuración", "icon": "gear"},
]
const MENU_PHASES := ["", "lobby"]
const SUCCESS := {
	Protocol.I_BUY_SKIN: "¡Animal desbloqueado! Ya puedes elegirlo en Personajes.",
	Protocol.I_BUY_PREMIUM: "Executive Pass Premium activado.",
	Protocol.I_CLAIM_PASS_REWARD: "Recompensa reclamada.",
}
const TOAST_SECONDS := 3.2
const GlassBox := preload("res://scripts/ui/GlassBox.gd")
const Fx := preload("res://scripts/menu/LobbyFx.gd")
const DetectivePath := preload("res://scripts/menu/DetectivePath.gd")
const LevelUpPopup := preload("res://scripts/menu/LevelUpPopup.gd")
const LessonArt := preload("res://scripts/menu/LessonArt.gd")
const TUTORIAL_SCRIPT := "res://scripts/tutorial/Tutorial.gd"
const HINTS_SCRIPT := "res://scripts/ui/MatchHints.gd"

@onready var root: Control = $Root
@onready var backdrop: OfficeBackdrop = %Backdrop
@onready var lobby: LobbyView = %LobbyView
@onready var content_frame: Control = %ContentFrame
@onready var content: PanelContainer = %ContentPanel
@onready var sidebar: PanelContainer = %Sidebar
@onready var tabs_box: VBoxContainer = %Tabs
@onready var portrait: SkinPreview = %Portrait
@onready var profile_name: Label = %ProfileName
@onready var level_label: Label = %LevelLabel
@onready var xp_bar: ProgressBar = %ProfileXp
@onready var coins_label: Label = %CoinsLabel
@onready var credits_label: Label = %CreditsLabel
@onready var add_credits_button: Button = %AddCreditsButton
@onready var friends_button: Button = %FriendsButton
@onready var mail_button: Button = %MailButton
@onready var settings_button: Button = %SettingsButton
@onready var connection_button: Button = %ConnectionButton
@onready var wifi_icon: MenuIcon = %WifiIcon
@onready var ping_label: Label = %PingLabel
@onready var toast: PanelContainer = %Toast
@onready var toast_label: Label = %ToastLabel

var current_tab := ""
var views := {}           # id -> Control (sin "sala": esa es LobbyView)
var tab_buttons := {}     # id -> Button
var _toast_left := 0.0
var _ping_timer := 0.0
var _was_in_room := false
var _connecting := false
var play_button: Button
## Celebración de subida de nivel abierta (o null).
var level_popup: Control
## Aviso de primera vez («¿Practicamos?») abierto (o null).
var first_run_card: Control
var _xp_tween: Tween

func _ready() -> void:
	_style_header()
	_build_tabs()
	_build_views()
	lobby.toast_requested.connect(show_toast)
	lobby.tab_requested.connect(show_tab)
	friends_button.pressed.connect(show_tab.bind("amigos"))
	mail_button.pressed.connect(show_tab.bind("correo"))
	settings_button.pressed.connect(show_tab.bind("configuracion"))
	add_credits_button.pressed.connect(show_tab.bind("tienda"))
	connection_button.pressed.connect(func() -> void:
		if not Account.online:
			start())

	Account.profile_updated.connect(func(_p: Dictionary) -> void: _sync_header())
	Account.online_changed.connect(func(_o: bool) -> void: _sync_header())
	Account.action_failed.connect(func(_a: String, _r: String, message: String) -> void: show_toast(message, true))
	Account.action_done.connect(_on_action_done)
	Account.rewards_granted.connect(_on_rewards)
	Account.profile_updated.connect(func(_p: Dictionary) -> void: _maybe_celebrate())
	GameState.snapshot_applied.connect(func(_s: Dictionary) -> void: _sync_visibility())
	EventBus.phase_changed.connect(func(_p: String, _e: int) -> void: _sync_visibility())
	# Al entrar en una sala (crear, unirse o cola llena) se muestra la sala de espera.
	EventBus.connected_to_server.connect(func(_id: String) -> void: show_tab("sala"))
	toast.hide()
	show_tab("sala")
	_sync_header()
	_sync_visibility()
	_add_match_hints()
	Account.flush_tutorial_reward()
	_maybe_celebrate.call_deferred()
	_maybe_offer_tutorial.call_deferred()

## Abre la conexión y pide el perfil. Sin servidor, el menú sigue usable y avisa.
func start() -> void:
	if _connecting:
		return
	_connecting = true
	ping_label.text = "Conectando…"
	_fit_connection()
	if not Network.is_local_url(Network.server_url):
		show_toast("Conectando con el servidor… Si estaba dormido puede tardar hasta un minuto.")
	var ok: bool = await Account.go_online()
	_connecting = false
	if not ok:
		show_toast("No se pudo conectar con el servidor (%s)." % Network.server_url, true)
	_sync_header()

## Caso que carga este cliente (título en la tarjeta de la sala y tipo en el selector).
func set_case(title: String, scenario_id: String) -> void:
	lobby.case_title = title
	lobby.scenario_id = scenario_id
	for c in lobby.case_list.get_children():
		c.queue_free()
	lobby._build_case_list()
	lobby.refresh()

func show_tab(id: String) -> void:
	current_tab = id
	var in_lobby := id == "sala"
	lobby.visible = in_lobby
	content_frame.visible = not in_lobby
	backdrop.dim = 0.0 if in_lobby else 0.6
	for v in views:
		views[v].visible = v == id
	for t in tab_buttons:
		tab_buttons[t].set_pressed_no_signal(t == id)
		_paint_tab(t)

func view(id: String) -> Control:
	return lobby if id == "sala" else views.get(id)

func show_toast(text: String, error := false) -> void:
	toast_label.text = text
	var c := UiPalette.CRIMSON if error else UiPalette.AMBER
	toast.add_theme_stylebox_override("panel", UiPalette.flat(Color(UiPalette.NAVY, 0.95), c, 1, 10, 12))
	toast.show()
	_toast_left = TOAST_SECONDS

func is_menu_visible() -> bool:
	return visible

func _process(delta: float) -> void:
	if _toast_left > 0.0:
		_toast_left -= delta
		if _toast_left <= 0.0:
			toast.hide()
	_ping_timer -= delta
	if _ping_timer <= 0.0:
		_ping_timer = 0.5
		_sync_connection()

# ───── Visibilidad ─────

func _sync_visibility() -> void:
	var show_menu := GameState.phase() in MENU_PHASES
	visible = show_menu
	root.process_mode = Node.PROCESS_MODE_INHERIT if show_menu else Node.PROCESS_MODE_DISABLED
	var in_room := GameState.in_room()
	if in_room and not _was_in_room:
		show_tab("sala")   # al entrar en una sala, a la sala de espera
	_was_in_room = in_room

# ───── Cabecera ─────

func _sync_header() -> void:
	profile_name.text = Account.player_name
	_sync_xp(Account.level(), int(Account.profile.get("xpIntoLevel", 0)), int(Account.profile.get("xpForLevel", DetectivePath.xp_for_level(Account.level()))))
	portrait.skin_id = Account.selected_skin()
	portrait.look = Account.equipped()
	coins_label.text = Progression.format_amount(Account.coins()) if Account.has_profile() else "—"
	credits_label.text = Progression.format_amount(Account.credits()) if Account.has_profile() else "—"
	_sync_connection()

func _sync_connection() -> void:
	if _connecting:
		return
	if not Account.online:
		wifi_icon.level = 0
		wifi_icon.color = UiPalette.CRIMSON
		ping_label.text = "Sin conexión · Reintentar"
		ping_label.add_theme_color_override("font_color", Color("#FCA5A5"))
		_fit_connection()
		return
	var ms := Network.latency_ms
	wifi_icon.level = 3 if ms < 90 else (2 if ms < 180 else 1)
	wifi_icon.color = Color("#4ADE80") if ms < 180 else UiPalette.AMBER
	ping_label.text = "%d ms" % ms if ms >= 0 else "En línea"
	ping_label.add_theme_color_override("font_color", Color("#BBF7D0"))
	_fit_connection()

## El botón de conexión mide lo que su texto (nada se sale por la derecha).
func _fit_connection() -> void:
	var w := ping_label.get_minimum_size().x + 20.0 + 6.0 + 22.0
	if absf(connection_button.custom_minimum_size.x - w) > 0.5:
		connection_button.custom_minimum_size.x = w

func _on_action_done(action: String, _seq: int) -> void:
	if SUCCESS.has(action):
		show_toast(SUCCESS[action])

func _on_rewards(r: Dictionary) -> void:
	if r.get("source") != "tutorial":
		var text := "Partida terminada: +%d XP · +%d MC" % [int(r.get("xp", 0)), int(r.get("coins", 0))]
		if int(r.get("passLevelsGained", 0)) > 0:
			text += " · ¡%d nivel(es) del pase!" % int(r["passLevelsGained"])
		show_toast(text)
	_maybe_celebrate()

# ───── Ruta del Detective ─────

## Celebración pendiente (subida de nivel, retos, práctica) si el menú está a la vista.
func _maybe_celebrate() -> void:
	if not visible or level_popup != null or Account.pending_celebration.is_empty():
		return
	show_level_up(Account.take_celebration())

func show_level_up(r: Dictionary) -> Control:
	if level_popup != null:
		level_popup.queue_free()
	level_popup = LevelUpPopup.show_for(root, r)
	level_popup.lesson_requested.connect(func(level_n: int) -> void:
		show_tab("ruta")
		var v = views.get("ruta")
		if v and level_n <= DetectivePath.max_level():
			v.select_level(level_n))
	level_popup.closed.connect(func() -> void: level_popup = null)
	return level_popup

## Práctica local «Primer día en NexusCore»: sale de la sala o la cola y arranca la
## partida guiada con bots en la oficina real (scripts/tutorial/Tutorial.gd).
func start_tutorial() -> Node:
	if Network.local_server != null:
		return null
	if first_run_card:
		first_run_card.queue_free()
		first_run_card = null
	if Account.in_queue():
		Account.cancel_queue()
	if GameState.in_room():
		Account.leave_room()
	Account.set_tutorial_seen()
	var t: Node = (load(TUTORIAL_SCRIPT) as GDScript).new()
	t.name = "Tutorial"
	(get_parent() if get_parent() else self).add_child(t)
	t.begin()
	return t

## La primera vez que se abre el juego: ofrece la práctica (se puede jugar luego desde la Ruta).
func _maybe_offer_tutorial() -> void:
	if Account.tutorial_seen or Account.from_env() or OS.get_environment("ROOM") != "" \
			or DisplayServer.get_name() == "headless" or GameState.in_room() or not visible:
		return
	offer_tutorial()

func offer_tutorial() -> Control:
	var shade := ColorRect.new()
	shade.name = "FirstRunCard"
	shade.color = Color(0.02, 0.03, 0.07, 0.7)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(shade)
	first_run_card = shade
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.add_child(center)
	var card := PanelContainer.new()
	card.custom_minimum_size.x = 480
	card.add_theme_stylebox_override("panel", GlassBox.panel(20.0, 22.0))
	center.add_child(card)
	var box := MenuView.vbox(12)
	card.add_child(box)
	box.add_child(MenuView.heading("¡Bienvenido a NexusCore!", 26))
	var reward := DetectivePath.tutorial_reward()
	box.add_child(MenuView.caption("¿Primera vez? Juega «Primer día en NexusCore»: unos minutos de práctica guiada en la oficina, con bots y sin presión. Aprenderás a explorar, recoger y copiar pruebas, reportar, votar en una asamblea y en el juicio.", 14, Color("#E2E8F0")))
	box.add_child(MenuView.caption("Recompensa: +%d XP y +%d MC (una vez). Puedes repetirla cuando quieras desde la Ruta del Detective." % [int(reward.get("xp", 0)), int(reward.get("coins", 0))], 13, Color("#FFE7A8")))
	box.add_child(LessonArt.make("office", Vector2(436, 150)))
	var row := MenuView.hbox(10)
	row.alignment = BoxContainer.ALIGNMENT_END
	box.add_child(row)
	var later := Button.new()
	later.name = "LaterButton"
	later.text = "  Ahora no  "
	later.custom_minimum_size.y = 40
	UiPalette.style_button(later, Color("#94A3B8"))
	later.pressed.connect(func() -> void:
		Account.set_tutorial_seen()
		show_toast("Puedes practicar cuando quieras desde la Ruta del Detective.")
		shade.queue_free()
		first_run_card = null)
	row.add_child(later)
	var go := Button.new()
	go.name = "StartTutorialButton"
	go.text = "  Empezar la práctica  "
	go.custom_minimum_size.y = 40
	MenuView.cta(go)
	go.pressed.connect(start_tutorial)
	row.add_child(go)
	return shade

## Consejos de las primeras partidas: un nodo hermano (vive aunque el menú se oculte).
func _add_match_hints() -> void:
	var parent := get_parent()
	if parent == null or parent.has_node("MatchHints"):
		return
	var hints: Node = (load(HINTS_SCRIPT) as GDScript).new()
	hints.name = "MatchHints"
	parent.add_child.call_deferred(hints)

## Barra de XP de la cabecera: si subiste (de XP o de nivel) desde la última vez que se
## pintó, se llena con animación; al cruzar de nivel, destello y vuelta a empezar.
func _sync_xp(level_n: int, into: int, need: int) -> void:
	var from_level := Account.shown_level
	var from_into := Account.shown_xp_into
	Account.shown_level = level_n
	Account.shown_xp_into = into
	var grew := Account.has_profile() and from_level > 0 and (level_n > from_level or (level_n == from_level and into > from_into))
	if _xp_tween:
		_xp_tween.kill()
	if not grew or not is_inside_tree():
		level_label.text = "Nv. %d" % level_n
		xp_bar.max_value = maxi(1, need)
		xp_bar.value = into
		return
	_xp_tween = create_tween()
	if level_n > from_level:
		level_label.text = "Nv. %d" % from_level
		xp_bar.max_value = maxi(1, DetectivePath.xp_for_level(from_level))
		xp_bar.value = from_into
		_xp_tween.tween_property(xp_bar, "value", xp_bar.max_value, 0.7).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		_xp_tween.tween_callback(func() -> void:
			level_label.text = "Nv. %d" % level_n
			level_label.pivot_offset = level_label.size / 2.0
			xp_bar.max_value = maxi(1, need)
			xp_bar.value = 0)
		_xp_tween.tween_property(level_label, "scale", Vector2(1.5, 1.5), 0.15)
		_xp_tween.parallel().tween_property(level_label, "modulate", Color(2.0, 1.7, 0.6), 0.15)
		_xp_tween.tween_property(level_label, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK)
		_xp_tween.parallel().tween_property(level_label, "modulate", Color.WHITE, 0.4)
	else:
		level_label.text = "Nv. %d" % level_n
		xp_bar.max_value = maxi(1, need)
	_xp_tween.tween_property(xp_bar, "value", into, 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

# ───── Construcción ─────

func _build_views() -> void:
	var made := {
		"ruta": (load("res://scripts/menu/detective_path_view.gd") as GDScript).new(),
		"personajes": CharactersView.new(),
		"inventario": InventoryView.new(),
		"misiones": MissionsView.new(),
		"pase": load("res://scenes/menu/BattlePassView.tscn").instantiate(),
		"tienda": load("res://scenes/menu/ShopView.tscn").instantiate(),
		"gadgets": ComingSoonView.create("Gadgets", "Aquí equiparás objetos de oficina para tu animal: maletines, auriculares, gafas de investigador… Solo estéticos.", "chip"),
		"configuracion": SettingsView.new(),
		"amigos": ComingSoonView.create("Amigos", "Tu lista de amigos para invitarlos a tu sala. Mientras tanto, comparte el código de sala desde la tarjeta del caso.", "users"),
		"correo": ComingSoonView.create("Correo", "Avisos de la temporada y recompensas por correo.", "mail"),
	}
	for id in made:
		var v: Control = made[id]
		v.name = id.capitalize().replace(" ", "") + "View"
		v.visible = false
		content.add_child(v)
		views[id] = v
		v.toast_requested.connect(show_toast)
		v.tab_requested.connect(show_tab)
		if v.has_signal("tutorial_requested"):
			v.tutorial_requested.connect(start_tutorial)

func _build_tabs() -> void:
	var group := ButtonGroup.new()
	for t in TABS:
		var b := Button.new()
		b.name = "Tab_" + t["id"]
		b.toggle_mode = true
		b.button_group = group
		b.custom_minimum_size = Vector2(0, 40)
		b.focus_mode = Control.FOCUS_NONE
		var row := HBoxContainer.new()
		row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 12)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_theme_constant_override("separation", 10)
		var icon := MenuIcon.make(t["icon"], Color.WHITE, 20)
		icon.name = "Icon"
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(icon)
		var l := Label.new()
		l.name = "Label"
		l.text = t["label"]
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		l.add_theme_font_override("font", UiPalette.bold_font())
		l.add_theme_font_size_override("font_size", 15 if str(t["label"]).length() <= 15 else 14)
		row.add_child(l)
		b.add_child(row)
		b.pressed.connect(show_tab.bind(t["id"]))
		tabs_box.add_child(b)
		tab_buttons[t["id"]] = b
		_paint_tab(t["id"])
	var gap := Control.new()
	gap.custom_minimum_size.y = 6
	tabs_box.add_child(gap)
	play_button = Button.new()
	play_button.name = "PlayButton"
	play_button.custom_minimum_size = Vector2(0, 44)
	play_button.focus_mode = Control.FOCUS_NONE
	MenuView.cta(play_button)
	LobbyView._icon_label(play_button, "play", "JUGAR", Color("#1A1405"))
	var label: Label = play_button.get_node("Content").get_child(1)
	label.add_theme_font_override("font", UiPalette.heading_font())
	label.add_theme_font_size_override("font_size", 17)
	play_button.pressed.connect(_on_play_pressed)
	tabs_box.add_child(play_button)

## JUGAR desde cualquier pestaña: a la sala y, si no estás en ninguna, a la cola pública.
func _on_play_pressed() -> void:
	show_tab("sala")
	lobby.play()

func _paint_tab(id: String) -> void:
	var b: Button = tab_buttons[id]
	var on := b.button_pressed
	var active = GlassBox.make(Color("#FFE36A"), Color("#F5B70F"), 10.0, 6.0)
	active.border_top = Color(1, 1, 1, 0.7)
	active.border_bottom = Color("#C98A00")
	active.shadow_size = 8
	active.shadow_color = Color(0, 0, 0, 0.35)
	active.with_glow(Color(1.0, 0.75, 0.1, 0.18), 8)
	var idle := UiPalette.flat(Color.TRANSPARENT, Color.TRANSPARENT, 0, 10, 6)
	b.add_theme_stylebox_override("normal", active if on else idle)
	b.add_theme_stylebox_override("hover", active if on else UiPalette.flat(Color(1, 1, 1, 0.07), Color(1, 1, 1, 0.06), 1, 10, 6))
	b.add_theme_stylebox_override("pressed", active)
	b.add_theme_stylebox_override("hover_pressed", active)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var ink := Color("#1A1405") if on else Color("#E2E8F0")
	var row := b.get_child(0)
	(row.get_node("Icon") as MenuIcon).color = ink
	(row.get_node("Label") as Label).add_theme_color_override("font_color", ink)

func _style_header() -> void:
	for p in [%ProfileBox, %CoinsPill, %CreditsPill, sidebar]:
		var glass = GlassBox.panel(16.0 if p == sidebar else 14.0, 8.0)
		p.add_theme_stylebox_override("panel", glass)
	%PortraitFrame.add_theme_stylebox_override("panel", UiPalette.flat(Color("#1E2A4A"), UiPalette.AMBER, 2, 23, 0))
	var content_style = GlassBox.panel(18.0, 16.0)
	content.add_theme_stylebox_override("panel", content_style)
	profile_name.add_theme_font_override("font", UiPalette.heading_font())
	profile_name.add_theme_font_size_override("font_size", 17)
	level_label.add_theme_font_size_override("font_size", 12)
	level_label.add_theme_color_override("font_color", Color("#FFE7A8"))
	xp_bar.add_theme_stylebox_override("fill", UiPalette.flat(UiPalette.AMBER, Color.TRANSPARENT, 0, 3, 0))
	for l in [coins_label, credits_label]:
		l.add_theme_font_override("font", UiPalette.bold_font())
		l.add_theme_font_size_override("font_size", 16)
	add_credits_button.add_theme_stylebox_override("normal", UiPalette.flat(Color("#1E3A5F"), Color(1, 1, 1, 0.2), 1, 6, 0))
	add_credits_button.add_theme_stylebox_override("hover", UiPalette.flat(Color("#25507F"), Color(1, 1, 1, 0.4), 1, 6, 0))
	add_credits_button.add_child(LobbyView._centered_icon("plus", Color.WHITE, 14))
	for pair in [[friends_button, "users"], [mail_button, "mail"], [settings_button, "gear"]]:
		var b: Button = pair[0]
		_glass_button(b)
		b.add_child(LobbyView._centered_icon(pair[1], Color.WHITE, 22))
		Fx.juice(b, 1.06, 0.94)
	_glass_button(connection_button)
	connection_button.flat = false
	ping_label.add_theme_font_size_override("font_size", 12)
	ping_label.add_theme_font_override("font", UiPalette.bold_font())
	toast_label.add_theme_font_override("font", UiPalette.bold_font())

func _glass_button(b: Button) -> void:
	var n = GlassBox.panel(12.0, 0.0)
	n.shadow_size = 8
	var h = GlassBox.panel(12.0, 0.0)
	h.bg_top = Color(0.16, 0.2, 0.33, 0.92)
	h.border_top = Color(1, 1, 1, 0.35)
	h.shadow_size = 8
	var p = GlassBox.panel(12.0, 0.0)
	p.border_top = Color(UiPalette.AMBER, 0.9)
	p.shadow_size = 4
	for s in [["normal", n], ["hover", h], ["pressed", p], ["focus", StyleBoxEmpty.new()]]:
		b.add_theme_stylebox_override(s[0], s[1])
