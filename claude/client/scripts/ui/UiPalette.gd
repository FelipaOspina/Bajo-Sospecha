class_name UiPalette
extends RefCounted
## Guía de estilo "Corporate Drama" (Neo-Noir ejecutivo): colores, tipografías y
## estilos compartidos por toda la UI. Tipografías incluidas en el proyecto:
## Space Grotesk (títulos), Inter (texto) y JetBrains Mono (terminal y logs).

const NAVY := Color("#0B0F19")           # fondo de paneles, modales y barras
const GLASS := Color("#161F30D8")        # tarjetas, asientos (85 % de opacidad)
const AMBER := Color("#E5A93C")          # acentos, selección, temporizador
const CYAN := Color("#00E5FF")           # terminal, logs, respaldos
const CRIMSON := Color("#FF334B")        # borrar, votos de expulsión
const TEXT := Color("#E2E8F0")           # texto principal
const TEXT_DIM := Color("#E2E8F099")
const DIMMER := Color("#0B0F19B2")       # fondo del modal

## Color de acento de cada rol para el cuerpo del avatar. Solo se usa con el rol propio
## o en la pantalla final: pintar a los demás con su color revelaría roles secretos.
const ROLE_COLORS := {
	"ROLE_CEO": CRIMSON,
	"ROLE_CTO": CYAN,
	"ROLE_INVESTOR": AMBER,
	"ROLE_LEAKER": Color("#B48CFF"),     # violeta
	"ROLE_EMPLOYEE": Color("#4ADE80"),   # verde
}
const NEUTRAL_SUIT := Color("#8A94A8")   # rol sin color asignado

static func role_color(role_id: String) -> Color:
	return ROLE_COLORS.get(role_id, NEUTRAL_SUIT)

## Traje neutro y distinto para cada jugador; no dice nada de su rol.
static func neutral_color(player_id: String) -> Color:
	return Color.from_hsv(float(hash(player_id) % 360) / 360.0, 0.22, 0.62)

## Color de una acción canalizada: rojo si es hostil (borrar), cian si es pacífica (respaldo).
static func action_color(kind: String) -> Color:
	return CRIMSON if kind == "delete" else CYAN

static func is_hostile(kind: String) -> bool:
	return kind == "delete"

## Fuentes del proyecto (OFL, en res://assets/fonts/, licencias en assets/fonts/licenses/).
## Son fuentes variables: el peso se elige con FontVariation. Si faltara un archivo,
## se cae a la fuente del sistema con el mismo nombre.
const FONT_HEADING := "res://assets/fonts/SpaceGrotesk-Variable.ttf"
const FONT_BODY := "res://assets/fonts/Inter-Variable.ttf"
const FONT_MONO := "res://assets/fonts/JetBrainsMono-Variable.ttf"
## Theme general del proyecto (project.godot → gui/theme/custom). Se genera con
## godot --headless --path client --script res://tools/build_theme.gd
const THEME_PATH := "res://assets/ui/corporate_theme.tres"

static var _cache := {}

static func heading_font() -> Font:
	return _font(FONT_HEADING, 600, ["Space Grotesk", "DejaVu Sans", "sans-serif"])

static func body_font() -> Font:
	return _font(FONT_BODY, 400, ["Inter", "DejaVu Sans", "sans-serif"])

static func bold_font() -> Font:
	return _font(FONT_BODY, 700, ["Inter", "DejaVu Sans", "sans-serif"])

static func mono_font() -> Font:
	return _font(FONT_MONO, 400, ["JetBrains Mono", "DejaVu Sans Mono", "monospace"])

## Theme general: fuente Inter, colores de la paleta y estilos de botones, paneles,
## barras y campos. Lo usa tools/build_theme.gd para escribir THEME_PATH.
static func build_theme() -> Theme:
	var t := Theme.new()
	t.default_font = body_font()
	t.default_font_size = 15
	for type in ["Label", "Button", "OptionButton", "LineEdit", "CheckBox", "PopupMenu", "TooltipLabel"]:
		t.set_color("font_color", type, TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_disabled_color", "Button", Color(TEXT, 0.4))
	t.set_color("default_color", "RichTextLabel", TEXT)
	t.set_font("normal_font", "RichTextLabel", body_font())
	t.set_font("bold_font", "RichTextLabel", bold_font())
	t.set_font("mono_font", "RichTextLabel", mono_font())
	for type in ["Button", "OptionButton"]:
		t.set_stylebox("normal", type, flat(Color(AMBER, 0.12), Color(AMBER, 0.6), 1, 6, 8))
		t.set_stylebox("hover", type, flat(Color(AMBER, 0.24), AMBER, 1, 6, 8))
		t.set_stylebox("pressed", type, flat(Color(AMBER, 0.38), AMBER, 1, 6, 8))
		t.set_stylebox("disabled", type, flat(Color(AMBER, 0.05), Color(AMBER, 0.25), 1, 6, 8))
		t.set_stylebox("focus", type, flat(Color.TRANSPARENT, AMBER, 1, 6, 8))
	t.set_stylebox("panel", "PanelContainer", glass_panel())
	t.set_stylebox("panel", "Panel", glass_panel())
	t.set_color("font_outline_color", "Label", Color(0, 0, 0, 0.85))
	t.set_stylebox("panel", "PopupMenu", flat(NAVY, Color(AMBER, 0.4), 1, 6, 6))
	t.set_stylebox("panel", "TooltipPanel", flat(NAVY, Color(AMBER, 0.4), 1, 4, 6))
	t.set_stylebox("background", "ProgressBar", flat(Color(NAVY, 0.8), Color(0, 0, 0, 0.6), 1, 3, 0))
	t.set_stylebox("fill", "ProgressBar", flat(AMBER, Color.TRANSPARENT, 0, 3, 0))
	return t

## Panel de cristal: radio 8 px, borde dorado tenue y fondo pizarra.
static func glass_panel(radius := 8, pad := 12) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = GLASS
	s.border_color = Color(AMBER, 0.27)
	s.set_border_width_all(1)
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(pad)
	return s

static func flat(bg: Color, border := Color.TRANSPARENT, border_w := 0, radius := 6, pad := 8) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(border_w)
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(pad)
	return s

## Botón con el color de acento indicado (borrar en rojo, respaldar en cian...).
static func style_button(b: Button, accent: Color) -> void:
	b.add_theme_stylebox_override("normal", flat(Color(accent, 0.16), Color(accent, 0.8), 1, 6, 8))
	b.add_theme_stylebox_override("hover", flat(Color(accent, 0.3), accent, 1, 6, 8))
	b.add_theme_stylebox_override("pressed", flat(Color(accent, 0.45), accent, 1, 6, 8))
	b.add_theme_stylebox_override("disabled", flat(Color(accent, 0.06), Color(accent, 0.3), 1, 6, 8))
	b.add_theme_color_override("font_color", TEXT)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_disabled_color", Color(TEXT, 0.4))

static func _font(path: String, weight: int, fallback_names: Array) -> Font:
	var key := "%s@%d" % [path, weight]
	if _cache.has(key):
		return _cache[key]
	var font: Font
	if ResourceLoader.exists(path):
		var v := FontVariation.new()
		v.base_font = load(path)
		v.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): weight}
		font = v
	else:
		var sys := SystemFont.new()
		sys.font_names = PackedStringArray(fallback_names)
		sys.font_weight = weight
		font = sys
	_cache[key] = font
	return font
