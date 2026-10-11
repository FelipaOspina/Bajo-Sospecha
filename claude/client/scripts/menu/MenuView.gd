class_name MenuView
extends Control
## Base de las pestañas del menú (Personajes, Inventario, Pase, Tienda...): se repinta
## cuando llega un perfil nuevo y ofrece piezas de estilo comunes (títulos, tarjetas,
## precios). Las acciones van por Account; los avisos los muestra MainMenu.

signal toast_requested(text: String)
signal tab_requested(tab: String)

const GREEN := Color("#4ADE80")
const YELLOW := Color("#FFD21F")
const DIM := Color("#94A3B8")

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	build()
	Account.profile_updated.connect(_refresh_if_visible.unbind(1))
	visibility_changed.connect(_refresh_if_visible)
	refresh()

func _refresh_if_visible() -> void:
	if is_visible_in_tree():
		refresh()

## Crea los nodos fijos (una vez).
func build() -> void:
	pass

## Vuelve a pintar con el perfil actual.
func refresh() -> void:
	pass

# ───── Piezas de estilo ─────

static func heading(text: String, font_size := 26, color := Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", UiPalette.heading_font())
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	return l

static func caption(text: String, font_size := 13, color := DIM) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l

static func card(bg := Color(0.09, 0.12, 0.19, 0.92), border := Color(1, 1, 1, 0.08), pad := 12) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UiPalette.flat(bg, border, 1, 12, pad))
	return p

static func vbox(separation := 8) -> VBoxContainer:
	var b := VBoxContainer.new()
	b.add_theme_constant_override("separation", separation)
	return b

static func hbox(separation := 8) -> HBoxContainer:
	var b := HBoxContainer.new()
	b.add_theme_constant_override("separation", separation)
	return b

## "● 1.240 MC" con el icono de la moneda.
static func amount_row(currency: String, amount: int, font_size := 15, suffix := false) -> HBoxContainer:
	var row := hbox(5)
	row.add_child(MenuIcon.make("coin" if currency == "coins" else "diamond", Color.WHITE, font_size + 3))
	var l := Label.new()
	l.text = Progression.format_amount(amount) + (" " + Progression.currency_short(currency) if suffix else "")
	l.add_theme_font_override("font", UiPalette.bold_font())
	l.add_theme_font_size_override("font_size", font_size)
	row.add_child(l)
	for c in row.get_children():
		c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return row

## Botón amarillo de llamada a la acción (comprar, reclamar).
static func cta(b: Button, color := YELLOW) -> Button:
	var normal := UiPalette.flat(color, color.darkened(0.25), 0, 10, 8)
	normal.border_width_bottom = 3
	var hover := normal.duplicate()
	hover.bg_color = color.lightened(0.15)
	var pressed := normal.duplicate()
	pressed.bg_color = color.darkened(0.08)
	pressed.border_width_bottom = 1
	var disabled := UiPalette.flat(Color(color, 0.18), Color(color, 0.3), 1, 10, 8)
	for s in [["normal", normal], ["hover", hover], ["pressed", pressed], ["disabled", disabled]]:
		b.add_theme_stylebox_override(s[0], s[1])
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_color_override("font_color", Color("#1A1405"))
	b.add_theme_color_override("font_hover_color", Color("#1A1405"))
	b.add_theme_color_override("font_pressed_color", Color("#1A1405"))
	b.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.4))
	b.add_theme_font_override("font", UiPalette.bold_font())
	return b

static func skin_name(skin_id: String) -> String:
	return str(SkinCatalog.skin(skin_id).get("name", skin_id.capitalize()))
