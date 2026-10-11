class_name ComingSoonView
extends MenuView
## Pantalla vacía para lo que aún no existe (Gadgets, Correo, Amigos).

var title := "Próximamente"
var description := ""
var icon_name := "chip"

static func create(view_title: String, view_description: String, view_icon: String) -> ComingSoonView:
	var v := ComingSoonView.new()
	v.title = view_title
	v.description = view_description
	v.icon_name = view_icon
	return v

func build() -> void:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var box := vbox(10)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(box)
	var icon := MenuIcon.make(icon_name, Color(UiPalette.AMBER, 0.8), 72)
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(icon)
	var t := heading(title.to_upper(), 28)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(t)
	var chip := PanelContainer.new()
	chip.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	chip.add_theme_stylebox_override("panel", UiPalette.flat(Color(UiPalette.CYAN, 0.12), Color(UiPalette.CYAN, 0.6), 1, 10, 6))
	chip.add_child(heading("PRÓXIMAMENTE", 13, Color("#BFF6FF")))
	box.add_child(chip)
	var d := caption(description, 14)
	d.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	d.custom_minimum_size.x = 460
	box.add_child(d)
