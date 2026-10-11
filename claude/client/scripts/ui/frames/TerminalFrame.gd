class_name TerminalFrame
extends EvidenceFrame
## Terminal de código: logs, servidores, datos "Digital / Crítica".

func frame_id() -> String:
	return "terminal"
const TEXT := "#00E5FF"     # UiPalette.CYAN
const DIM := "#E5A93C"      # UiPalette.AMBER: prompt
const CRT_SHADER := preload("res://shaders/crt_terminal_screen.gdshader")

var _title_bar: Label
## Capa con el shader CRT encima de la pantalla (curvatura, líneas de escaneo, viñeta).
var crt_overlay: ColorRect

func view_name() -> String:
	return "TerminalView"

func bezel_path() -> String:
	return "res://assets/ui/bezels/bezel_monitor.png"

func bezel_patch() -> int:
	return 40

func bezel_padding() -> Vector4i:
	return Vector4i(30, 30, 30, 34)

func bezel_tiles() -> bool:
	return true

func _build_chrome() -> Container:
	add_theme_stylebox_override("panel", _box(Color("#05080F"), Color(UiPalette.CYAN, 0.35), 2, 6, 0))
	var v := _vbox(self, 0)
	var bar := PanelContainer.new()
	bar.add_theme_stylebox_override("panel", _box(UiPalette.NAVY, Color.TRANSPARENT, 0, 0, 6))
	v.add_child(bar)
	var row := HBoxContainer.new()
	bar.add_child(row)
	for c in [Color(1, 0.37, 0.34), Color(1, 0.74, 0.2), Color(0.16, 0.8, 0.26)]:
		var dot := ColorRect.new()
		dot.color = c
		dot.custom_minimum_size = Vector2(10, 10)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(dot)
	_title_bar = Label.new()
	_title_bar.text = "  bash — ssh root@srv"
	_title_bar.add_theme_font_override("font", _mono())
	_title_bar.add_theme_font_size_override("font_size", 12)
	_title_bar.modulate = Color(1, 1, 1, 0.6)
	row.add_child(_title_bar)
	var glass := MarginContainer.new()   # cristal: contenido y capa CRT ocupan lo mismo
	v.add_child(glass)
	var screen := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		screen.add_theme_constant_override("margin_" + side, 12)
	glass.add_child(screen)
	var content := _vbox(screen, 8)
	crt_overlay = ColorRect.new()
	crt_overlay.name = "CRTOverlay"
	crt_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = CRT_SHADER
	crt_overlay.material = mat
	crt_overlay.resized.connect(func(): mat.set_shader_parameter("rect_size", crt_overlay.size))
	glass.add_child(crt_overlay)   # después del contenido: se dibuja encima
	return content

func _style_body(b: RichTextLabel) -> void:
	b.add_theme_font_override("normal_font", _mono())
	b.add_theme_font_size_override("normal_font_size", 13)
	b.add_theme_color_override("default_color", Color(TEXT))

func _format(e: EvidenceData) -> String:
	var file := (e.definition_id if e.definition_id != "" else "evidence").to_lower()
	var lines := ["[color=%s]root@srv:~$[/color] cat /var/log/%s.log" % [DIM, file], _esc(e.description)]
	var text := str(e.content.get("text", ""))
	if text != "":
		lines.append(_esc(text))
	lines.append("[color=%s]root@srv:~$[/color] █" % DIM)
	return "\n".join(lines)

func _unknown_text() -> String:
	return "[color=%s]user@srv:~$[/color] cat ???\ncat: Permiso denegado" % DIM
