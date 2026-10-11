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

const TABS := [
	{"id": "sala", "label": "Sala", "icon": "users"},
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
	GameState.snapshot_applied.connect(func(_s: Dictionary) -> void: _sync_visibility())
	EventBus.phase_changed.connect(func(_p: String, _e: int) -> void: _sync_visibility())
	toast.hide()
	show_tab("sala")
	_sync_header()
	_sync_visibility()

## Abre la conexión y pide el perfil. Sin servidor, el menú sigue usable y avisa.
func start() -> void:
	if _connecting:
		return
	_connecting = true
	ping_label.text = "Conectando…"
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
	level_label.text = "Nv. %d" % Account.level()
	xp_bar.max_value = maxi(1, int(Account.profile.get("xpForLevel", 1000)))
	xp_bar.value = int(Account.profile.get("xpIntoLevel", 0))
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
		return
	var ms := Network.latency_ms
	wifi_icon.level = 3 if ms < 90 else (2 if ms < 180 else 1)
	wifi_icon.color = Color("#4ADE80") if ms < 180 else UiPalette.AMBER
	ping_label.text = "%d ms" % ms if ms >= 0 else "En línea"
	ping_label.add_theme_color_override("font_color", Color("#BBF7D0"))

func _on_action_done(action: String, _seq: int) -> void:
	if SUCCESS.has(action):
		show_toast(SUCCESS[action])

func _on_rewards(r: Dictionary) -> void:
	var text := "Partida terminada: +%d XP · +%d MC" % [int(r.get("xp", 0)), int(r.get("coins", 0))]
	if int(r.get("passLevelsGained", 0)) > 0:
		text += " · ¡%d nivel(es) del pase!" % int(r["passLevelsGained"])
	show_toast(text)

# ───── Construcción ─────

func _build_views() -> void:
	var made := {
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
		l.add_theme_font_size_override("font_size", 15)
		row.add_child(l)
		b.add_child(row)
		b.pressed.connect(show_tab.bind(t["id"]))
		tabs_box.add_child(b)
		tab_buttons[t["id"]] = b
		_paint_tab(t["id"])

func _paint_tab(id: String) -> void:
	var b: Button = tab_buttons[id]
	var on := b.button_pressed
	var yellow := Color("#FFD21F")
	b.add_theme_stylebox_override("normal", UiPalette.flat(yellow if on else Color.TRANSPARENT, Color.TRANSPARENT, 0, 10, 6))
	b.add_theme_stylebox_override("hover", UiPalette.flat(yellow.lightened(0.1) if on else Color(1, 1, 1, 0.07), Color.TRANSPARENT, 0, 10, 6))
	b.add_theme_stylebox_override("pressed", UiPalette.flat(yellow, Color.TRANSPARENT, 0, 10, 6))
	b.add_theme_stylebox_override("hover_pressed", UiPalette.flat(yellow, Color.TRANSPARENT, 0, 10, 6))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var ink := Color("#1A1405") if on else Color("#E2E8F0")
	var row := b.get_child(0)
	(row.get_node("Icon") as MenuIcon).color = ink
	(row.get_node("Label") as Label).add_theme_color_override("font_color", ink)

func _style_header() -> void:
	var glass := UiPalette.flat(Color(UiPalette.NAVY, 0.88), Color(1, 1, 1, 0.10), 1, 14, 8)
	for p in [%ProfileBox, %CoinsPill, %CreditsPill, sidebar]:
		p.add_theme_stylebox_override("panel", glass)
	%PortraitFrame.add_theme_stylebox_override("panel", UiPalette.flat(Color("#1E2A4A"), UiPalette.AMBER, 2, 23, 0))
	content.add_theme_stylebox_override("panel", UiPalette.flat(Color(UiPalette.NAVY, 0.9), Color(1, 1, 1, 0.08), 1, 16, 16))
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
		b.add_theme_stylebox_override("normal", UiPalette.flat(Color(UiPalette.NAVY, 0.6), Color.TRANSPARENT, 0, 10, 0))
		b.add_theme_stylebox_override("hover", UiPalette.flat(Color(1, 1, 1, 0.1), Color.TRANSPARENT, 0, 10, 0))
		b.add_theme_stylebox_override("pressed", UiPalette.flat(Color(1, 1, 1, 0.16), Color.TRANSPARENT, 0, 10, 0))
		b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		b.add_child(LobbyView._centered_icon(pair[1], Color.WHITE, 24))
	connection_button.flat = true
	ping_label.add_theme_font_size_override("font_size", 12)
	toast_label.add_theme_font_override("font", UiPalette.bold_font())
