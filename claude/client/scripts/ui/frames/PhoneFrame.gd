class_name PhoneFrame
extends EvidenceFrame
## Marco de celular: capturas, fotos, chats y audios ("Digital / Visual", "Testimonial").

func frame_id() -> String:
	return "phone"

func view_name() -> String:
	return "SmartphoneView"

func bezel_path() -> String:
	return "res://assets/ui/bezels/bezel_smartphone.png"

func bezel_patch() -> int:
	return 64

func slot_side_margin() -> int:
	return 120

func bezel_padding() -> Vector4i:
	return Vector4i(34, 30, 34, 26)

var _screen: PanelContainer
var _screen_style: StyleBox

func _on_texture_bezel(on: bool) -> void:
	# La pantalla ya está pintada en la textura: el panel interior se vuelve transparente.
	_screen.add_theme_stylebox_override("panel", StyleBoxEmpty.new() if on else _screen_style)

func _build_chrome() -> Container:
	add_theme_stylebox_override("panel", _box(UiPalette.NAVY, Color(UiPalette.AMBER, 0.4), 3, 28, 14))
	var outer := _vbox(self, 6)
	var status := HBoxContainer.new()
	outer.add_child(status)
	var clock := Label.new()
	clock.text = "9:41"
	clock.add_theme_font_size_override("font_size", 12)
	clock.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status.add_child(clock)
	var notch := ColorRect.new()
	notch.color = Color(0, 0, 0)
	notch.custom_minimum_size = Vector2(70, 12)
	status.add_child(notch)
	var icons := Label.new()
	icons.text = "5G ▮▮▮"
	icons.add_theme_font_size_override("font_size", 12)
	icons.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	icons.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	status.add_child(icons)
	var screen := PanelContainer.new()
	_screen = screen
	_screen_style = _box(Color("#111827"), Color.TRANSPARENT, 0, 14, 12)
	screen.add_theme_stylebox_override("panel", _screen_style)
	outer.add_child(screen)
	var home := ColorRect.new()
	home.color = Color(0.6, 0.6, 0.62)
	home.custom_minimum_size = Vector2(90, 4)
	home.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	outer.add_child(home)
	return _vbox(screen, 8)

func _style_body(b: RichTextLabel) -> void:
	b.add_theme_font_override("normal_font", UiPalette.body_font())
	b.add_theme_color_override("default_color", UiPalette.TEXT)

func _format(e: EvidenceData) -> String:
	var text := str(e.content.get("text", ""))
	var out := "[color=#E5A93C][font_size=12]%s[/font_size][/color]\n" % _esc(e.display_name)
	out += "[bgcolor=#1F2A40] %s [/bgcolor]" % _esc(e.description)
	if text != "":
		out += "\n\n[right][bgcolor=#0E4A57] %s [/bgcolor][/right]" % _esc(text)
	return out

func _unknown_text() -> String:
	return "[center]🔒\nPantalla bloqueada[/center]"
