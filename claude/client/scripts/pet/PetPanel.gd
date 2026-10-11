class_name PetPanel
extends PanelContainer
## Barra de la mascota en el lobby: el nombre del animal, sus barras de Hambre e
## Hidratación (llenas = bien) y los botones para darle su comida y agua. La comida
## depende de la especie (ver PetCare). Todo es gratis.

signal feed_pressed
signal drink_pressed

const HUNGER_COLOR := Color("#F59E0B")
const WATER_COLOR := Color("#38BDF8")
const LOW_COLOR := Color("#FF5C5C")

var title: Label
var hint: Label
var hunger_bar: Bar
var hydration_bar: Bar
var hunger_value: Label
var hydration_value: Label
var feed_button: Button
var drink_button: Button
var feed_icon: PetIcons.Rect
var feed_label: Label
var skin_id := ""

func _init() -> void:
	name = "PetPanel"
	add_theme_stylebox_override("panel", UiPalette.flat(Color(UiPalette.NAVY, 0.86), Color(1, 1, 1, 0.12), 1, 14, 8))
	var row := MenuView.hbox(12)
	add_child(row)
	var who := MenuView.vbox(0)
	who.custom_minimum_size.x = 100
	who.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(who)
	title = MenuView.heading("Tu mascota", 15, Color("#FFE7A8"))
	title.name = "PetName"
	who.add_child(title)
	hint = MenuView.caption("Tócala o acaríciala", 11)
	hint.autowrap_mode = TextServer.AUTOWRAP_OFF
	who.add_child(hint)
	var bars := MenuView.vbox(5)
	bars.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bars.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(bars)
	hunger_bar = Bar.new(HUNGER_COLOR)
	hunger_bar.name = "HungerBar"
	hunger_value = _bar_row(bars, "Hambre", hunger_bar)
	hydration_bar = Bar.new(WATER_COLOR)
	hydration_bar.name = "HydrationBar"
	hydration_value = _bar_row(bars, "Hidratación", hydration_bar)
	feed_button = _care_button("FeedButton", "kibble", "Comida")
	feed_icon = feed_button.get_node("Box/Icon")
	feed_label = feed_button.get_node("Box/Label")
	feed_button.pressed.connect(func() -> void: feed_pressed.emit())
	row.add_child(feed_button)
	drink_button = _care_button("DrinkButton", "water", "Agua")
	drink_button.pressed.connect(func() -> void: drink_pressed.emit())
	row.add_child(drink_button)

## Pone el animal (cambia la comida del botón) y los niveles (0..100).
func show_pet(skin: String, hunger: float, hydration: float) -> void:
	if skin != skin_id:
		skin_id = skin
		var f := PetCare.food(skin)
		title.text = str(SkinCatalog.skin(skin).get("name", skin))
		feed_icon.icon = str(f.get("icon", "kibble"))
		feed_label.text = str(f.get("name", "Comida"))
		feed_button.tooltip_text = "Darle %s. %s" % [str(f.get("name", "comida")).to_lower(), str(PetCare.species(skin).get("fact", ""))]
		drink_button.tooltip_text = "Darle %s." % str(PetCare.water().get("name", "agua")).to_lower()
		tooltip_text = "Tu animal también es tu mascota: dale de comer, de beber y mímalo. Es gratis y no cambia nada en la partida."
	_set_bar(hunger_bar, hunger_value, hunger)
	_set_bar(hydration_bar, hydration_value, hydration)

func _set_bar(bar: Bar, label: Label, v: float) -> void:
	bar.value = v / PetCare.max_level()
	bar.low = v < float(PetCare.data().get("low_at", 30))
	label.text = "%d %%" % roundi(v)

func _bar_row(parent: Container, text: String, bar: Bar) -> Label:
	var r := MenuView.hbox(8)
	parent.add_child(r)
	var l := MenuView.caption(text, 12, UiPalette.TEXT)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.custom_minimum_size.x = 76
	r.add_child(l)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r.add_child(bar)
	var v := MenuView.caption("0 %", 12, UiPalette.TEXT)
	v.autowrap_mode = TextServer.AUTOWRAP_OFF
	v.custom_minimum_size.x = 38
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	r.add_child(v)
	return v

func _care_button(node_name: String, icon: String, text: String) -> Button:
	var b := Button.new()
	b.name = node_name
	b.custom_minimum_size = Vector2(80, 52)
	UiPalette.style_button(b, UiPalette.AMBER)
	var box := MenuView.vbox(0)
	box.name = "Box"
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(box)
	var ic := PetIcons.Rect.new(icon, 26)
	ic.name = "Icon"
	ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(ic)
	var l := MenuView.caption(text, 11, UiPalette.TEXT)
	l.name = "Label"
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(l)
	return b

## Barra redondeada con brillo; parpadea suave en rojo cuando está baja.
class Bar extends Control:
	var color: Color
	var value := 1.0:
		set(v):
			value = clampf(v, 0.0, 1.0)
			queue_redraw()
	var low := false:
		set(v):
			low = v
			set_process(v)
			queue_redraw()
	var _t := 0.0

	func _init(c: Color) -> void:
		color = c
		custom_minimum_size = Vector2(56, 12)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_process(false)

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_style_box(UiPalette.flat(Color(1, 1, 1, 0.08), Color(1, 1, 1, 0.10), 1, int(size.y / 2.0), 0), r)
		if value <= 0.0:
			return
		var c := color
		if low:
			c = PetPanel.LOW_COLOR.lerp(color, 0.25 + 0.25 * sin(_t * 5.0))
		var fill := Rect2(Vector2.ONE, Vector2(maxf(size.y - 2.0, (size.x - 2.0) * value), size.y - 2.0))
		draw_style_box(UiPalette.flat(c, Color.TRANSPARENT, 0, int(fill.size.y / 2.0), 0), fill)
		draw_line(fill.position + Vector2(fill.size.y / 2.0, 2.5), Vector2(fill.end.x - fill.size.y / 2.0, fill.position.y + 2.5), Color(1, 1, 1, 0.35), 1.5, true)
