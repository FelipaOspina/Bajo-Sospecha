class_name PaperFrame
extends EvidenceFrame
## Hoja de papel: contratos, cartas, documentos ("Documental / Físico").

func frame_id() -> String:
	return "paper"

func view_name() -> String:
	return "PaperDocumentView"

func bezel_path() -> String:
	return "res://assets/ui/bezels/bezel_paper_clipboard.png"

func bezel_patch() -> int:
	return 44

func bezel_padding() -> Vector4i:
	return Vector4i(44, 36, 44, 40)

func bezel_tiles() -> bool:
	return true

func _build_chrome() -> Container:
	var s := _box(Color(0.96, 0.93, 0.84), Color(0.75, 0.7, 0.58), 1, 2, 22)
	s.shadow_color = Color(0, 0, 0, 0.45)
	s.shadow_size = 6
	s.shadow_offset = Vector2(3, 4)
	add_theme_stylebox_override("panel", s)
	var v := _vbox(self, 8)
	var margin_line := ColorRect.new()
	margin_line.color = Color(0.85, 0.35, 0.35, 0.6)
	margin_line.custom_minimum_size = Vector2(0, 1)
	v.add_child(margin_line)
	return v

func _style_body(b: RichTextLabel) -> void:
	var serif := SystemFont.new()
	serif.font_names = PackedStringArray(["DejaVu Serif", "Georgia", "Times New Roman", "serif"])
	b.add_theme_font_override("normal_font", serif)
	b.add_theme_color_override("default_color", Color(0.18, 0.15, 0.12))

func _format(e: EvidenceData) -> String:
	var text := str(e.content.get("text", ""))
	var out := "[center][b]%s[/b][/center]\n\n%s" % [_esc(e.display_name.to_upper()), _esc(e.description)]
	if text != "":
		out += "\n\n[i]%s[/i]" % _esc(text)
	return out

func _unknown_text() -> String:
	return "[i]La letra es ilegible desde aquí.[/i]"
