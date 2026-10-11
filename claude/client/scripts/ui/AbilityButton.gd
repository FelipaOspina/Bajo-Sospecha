class_name AbilityButton
extends Control
## Botón de la habilidad activa de tu animal en el HUD (abajo a la derecha). Escucha
## las señales de AnimalAbilities (autoload Abilities):
##  - retrato redondo de tu animal con un barrido oscuro mientras se recarga y los
##    segundos que faltan; anillo ámbar mientras dura el efecto;
##  - nombre de la activa, tecla (Q) y, debajo, la pasiva;
##  - avisos cortos: por qué no se pudo usar, o "Beto usó Rugido" (solo las públicas).
## Se pulsa con el ratón o el dedo (móvil) o con la tecla Q.

const SIZE := 84.0
const WIDTH := 230.0
const NOTICE_SECONDS := 2.6

var abilities: Node            # Abilities (o un doble en las pruebas)
var button: Button
var portrait: SkinPreview
var overlay: Control
var name_label: Label
var key_label: Label
var passive_label: Label
var notice: Label

var _remaining := 0.0
var _total := 1.0
var _active_left := 0.0
var _active_total := 1.0
var _notice_left := 0.0

func _ready() -> void:
	if abilities == null:
		abilities = Abilities
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(WIDTH, SIZE + 46)
	_build()
	abilities.ability_changed.connect(_on_changed)
	abilities.cooldown_changed.connect(_on_cooldown)
	abilities.ability_activated.connect(_on_activated)
	abilities.ability_ended.connect(func(_id: String) -> void: _active_left = 0.0; overlay.queue_redraw())
	abilities.ability_failed.connect(func(_reason: String, message: String) -> void: show_notice(message, true))
	abilities.ability_seen.connect(_on_seen)
	abilities.scent_marked.connect(func(ids: Array, _d: float) -> void:
		show_notice("Olfato: %d escondite%s con pruebas cerca." % [ids.size(), "" if ids.size() == 1 else "s"] if not ids.is_empty() else "Olfato: nada cerca.", false))
	_on_changed(abilities.skin_id, AnimalAbilities.kit(abilities.skin_id))

func _build() -> void:
	button = Button.new()
	button.name = "UseButton"
	button.focus_mode = Control.FOCUS_NONE
	button.size = Vector2(SIZE, SIZE)
	button.position = Vector2(WIDTH - SIZE, 0)
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var bg := Color(0.05, 0.08, 0.14, 0.9) if state != "hover" else Color(0.09, 0.13, 0.22, 0.95)
		button.add_theme_stylebox_override(state, UiPalette.flat(bg, Color(0, 0, 0, 0), 0, int(SIZE / 2.0), 0))
	button.pressed.connect(func() -> void: abilities.use())
	add_child(button)
	portrait = SkinPreview.new()
	portrait.head_only = true
	portrait.position = Vector2(8, 8)
	portrait.size = Vector2(SIZE - 16, SIZE - 16)
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(portrait)
	overlay = _Overlay.new()
	overlay.host = self
	overlay.size = Vector2(SIZE, SIZE)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(overlay)

	var info := VBoxContainer.new()
	info.name = "Info"
	info.alignment = BoxContainer.ALIGNMENT_END
	info.add_theme_constant_override("separation", 0)
	info.position = Vector2(0, 0)
	info.size = Vector2(WIDTH - SIZE - 10, SIZE)
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(info)
	key_label = _label(12, UiPalette.AMBER, HORIZONTAL_ALIGNMENT_RIGHT)
	key_label.text = "[Q]"
	info.add_child(key_label)
	name_label = _label(16, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT)
	name_label.add_theme_font_override("font", UiPalette.heading_font())
	info.add_child(name_label)
	passive_label = _label(12, UiPalette.TEXT_DIM, HORIZONTAL_ALIGNMENT_RIGHT)
	info.add_child(passive_label)

	notice = _label(13, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT)
	notice.name = "Notice"
	notice.position = Vector2(0, SIZE + 8)
	notice.size = Vector2(WIDTH, 36)
	notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	notice.modulate.a = 0.0
	add_child(notice)

func _label(font_size: int, color: Color, align: HorizontalAlignment) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_constant_override("outline_size", 4)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	l.horizontal_alignment = align
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

## Segundos de recarga que muestra ahora.
func remaining() -> float:
	return _remaining

func show_notice(text: String, error := false) -> void:
	notice.text = text
	notice.add_theme_color_override("font_color", Color("#FCA5A5") if error else Color("#E2E8F0"))
	notice.modulate.a = 1.0
	_notice_left = NOTICE_SECONDS

func _on_changed(skin_id: String, kit: Dictionary) -> void:
	var active: Dictionary = kit.get("active", {})
	var passive: Dictionary = kit.get("passive", {})
	visible = not active.is_empty()
	if not visible:
		return
	portrait.skin_id = skin_id
	name_label.text = str(active.get("name", ""))
	passive_label.text = "Pasiva: %s" % passive.get("name", "")
	_total = maxf(0.1, float(active.get("cooldown", 1.0)))
	button.tooltip_text = "%s — %s\n%s\n\nPasiva · %s: %s" % [
		active.get("name", ""), active.get("description", ""), AnimalAbilities.timing_text(active),
		passive.get("name", ""), passive.get("description", "")]

func _on_cooldown(left: float, total: float) -> void:
	_remaining = left
	_total = maxf(0.1, total)
	overlay.queue_redraw()

func _on_activated(_id: String, duration: float) -> void:
	_active_left = duration
	_active_total = maxf(0.1, duration)
	overlay.queue_redraw()

func _on_seen(player_id: String, ability_id: String, affected_me: bool) -> void:
	var who := player_id
	for p in GameState.players():
		if p.get("id") == player_id:
			who = str(p.get("name", player_id))
	var ability_name := str(AnimalAbilities.find_active(ability_id).get("name", ability_id))
	show_notice("%s usó %s%s" % [who, ability_name, " y te alcanzó" if affected_me else ""], false)

func _process(delta: float) -> void:
	if _active_left > 0.0:
		_active_left = maxf(0.0, _active_left - delta)
		overlay.queue_redraw()
	if _notice_left > 0.0:
		_notice_left -= delta
		notice.modulate.a = clampf(_notice_left / 0.4, 0.0, 1.0)
	var usable := GameState.phase() == "investigation"
	portrait.modulate = Color.WHITE if usable and _remaining <= 0.0 else Color(0.55, 0.6, 0.7)

## Fondo redondo, barrido de recarga, segundos y anillo del efecto activo.
class _Overlay extends Control:
	var host: AbilityButton

	func _draw() -> void:
		var c := size / 2.0
		var r := minf(size.x, size.y) / 2.0 - 2.0
		draw_arc(c, r, 0, TAU, 48, Color(1, 1, 1, 0.25), 2.0, true)
		if host._remaining > 0.0:
			var k := clampf(host._remaining / host._total, 0.0, 1.0)
			var pts := PackedVector2Array([c])
			var steps := 40
			for i in steps + 1:
				var a := -PI / 2.0 + TAU * k * float(i) / float(steps)
				pts.append(c + Vector2(cos(a), sin(a)) * r)
			if pts.size() >= 3:
				draw_colored_polygon(pts, Color(0.02, 0.04, 0.08, 0.62))
			var font := get_theme_default_font()
			var text := str(ceili(host._remaining))
			var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x
			draw_string_outline(font, c + Vector2(-w / 2.0, 9), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, 5, Color(0, 0, 0, 0.8))
			draw_string(font, c + Vector2(-w / 2.0, 9), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color.WHITE)
		else:
			draw_arc(c, r, 0, TAU, 48, Color(UiPalette.AMBER, 0.85), 3.0, true)
		if host._active_left > 0.0:
			var k2 := clampf(host._active_left / host._active_total, 0.0, 1.0)
			draw_arc(c, r + 1.0, -PI / 2.0, -PI / 2.0 + TAU * k2, 48, Color("#22D3EE"), 4.0, true)
