class_name CharactersView
extends MenuView
## Personajes: elige tu animal. A la izquierda, el elegido en grande (camina y gira, con
## tu ropa puesta) y sus habilidades: la pasiva y la activa, con el rasgo real del animal
## en que se basan. A la derecha, los 12 animales, todos gratis y todos elegibles. Si
## estás en una sala de espera, el cambio se ve allí al momento.

var big_preview: SkinPreview
var grid: GridContainer
var name_label: Label
var passive_name: Label
var passive_text: Label
var active_name: Label
var active_timing: Label
var active_text: Label
var trait_text: Label
var _tiles := {}   # skin_id -> {button, preview, hint}
var _view_index := 0
var _signature := ""

const VIEWS := ["frente", "lado", "espalda"]

func build() -> void:
	var layout := hbox(18)
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(layout)

	var left := card(Color(0.06, 0.08, 0.13, 0.9), Color(UiPalette.AMBER, 0.3), 14)
	left.custom_minimum_size.x = 340
	layout.add_child(left)
	var lbox := vbox(6)
	left.add_child(lbox)
	lbox.add_child(heading("TU ANIMAL", 14, DIM))
	name_label = heading("", 26, UiPalette.AMBER)
	lbox.add_child(name_label)
	big_preview = SkinPreview.new()
	big_preview.custom_minimum_size = Vector2(0, 170)
	big_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	big_preview.walking = true
	lbox.add_child(big_preview)
	var turn := hbox(8)
	turn.alignment = BoxContainer.ALIGNMENT_CENTER
	var rotate := Button.new()
	rotate.text = "Girar"
	UiPalette.style_button(rotate, UiPalette.CYAN)
	rotate.pressed.connect(func() -> void:
		_view_index = (_view_index + 1) % VIEWS.size()
		big_preview.facing = VIEWS[_view_index])
	turn.add_child(rotate)
	var walk := Button.new()
	walk.text = "Caminar / quieto"
	UiPalette.style_button(walk, UiPalette.CYAN)
	walk.pressed.connect(func() -> void: big_preview.walking = not big_preview.walking)
	turn.add_child(walk)
	lbox.add_child(turn)
	lbox.add_child(_abilities_panel())

	var right := vbox(10)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	layout.add_child(right)
	right.add_child(heading("PERSONAJES", 28))
	right.add_child(caption("Los 12 animales y sus habilidades son gratis para todos. Cada uno juega distinto, pero ninguno es mejor que otro ni dice nada de tu rol: el animal se elige antes del reparto.", 13))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(scroll)
	grid = GridContainer.new()
	grid.columns = 4
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	scroll.add_child(grid)
	for id in SkinCatalog.ids():
		grid.add_child(_tile(id))

## Activa y pasiva del animal elegido, con el rasgo real en que se basan.
func _abilities_panel() -> PanelContainer:
	var panel := card(Color(0.09, 0.12, 0.19, 0.92), Color(1, 1, 1, 0.08), 10)
	panel.name = "Abilities"
	var box := vbox(2)
	panel.add_child(box)
	box.add_child(caption("ACTIVA · tecla Q o botón en pantalla", 10, UiPalette.CYAN))
	var head := hbox(6)
	active_name = heading("", 16, Color.WHITE)
	active_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(active_name)
	active_timing = caption("", 11, UiPalette.AMBER)
	active_timing.autowrap_mode = TextServer.AUTOWRAP_OFF
	head.add_child(active_timing)
	box.add_child(head)
	active_text = caption("", 12, Color("#CBD5E1"))
	box.add_child(active_text)
	box.add_child(caption("PASIVA · siempre activa", 10, UiPalette.CYAN))
	passive_name = heading("", 15, Color.WHITE)
	box.add_child(passive_name)
	passive_text = caption("", 12, Color("#CBD5E1"))
	box.add_child(passive_text)
	trait_text = caption("", 11, DIM)
	box.add_child(trait_text)
	return panel

func refresh() -> void:
	var selected := Account.selected_skin()
	var signature := JSON.stringify([selected, Account.equipped()])
	if signature == _signature:
		return
	_signature = signature
	big_preview.skin_id = selected
	big_preview.look = Account.equipped()
	name_label.text = skin_name(selected).to_upper()
	var active := AnimalAbilities.active_of(selected)
	var passive := AnimalAbilities.passive_of(selected)
	active_name.text = str(active.get("name", "—"))
	active_timing.text = AnimalAbilities.timing_text(active) if not active.is_empty() else ""
	active_text.text = str(active.get("description", ""))
	passive_name.text = str(passive.get("name", "—"))
	passive_text.text = str(passive.get("description", ""))
	var fact := str(active.get("trait", passive.get("trait", "")))
	trait_text.text = "En la naturaleza: %s" % fact if fact != "" else ""
	for id in _tiles:
		var t: Dictionary = _tiles[id]
		t["hint"].text = "Elegido" if id == selected else str(AnimalAbilities.active_of(id).get("name", "Elegir"))
		t["hint"].add_theme_color_override("font_color", UiPalette.AMBER if id == selected else DIM)
		var border := UiPalette.AMBER if id == selected else Color(1, 1, 1, 0.1)
		for state in ["normal", "hover", "pressed", "disabled"]:
			var bg := Color(0.09, 0.12, 0.19, 0.94) if state != "hover" else Color(0.13, 0.17, 0.27, 0.96)
			t["button"].add_theme_stylebox_override(state, UiPalette.flat(bg, border, 2 if id == selected else 1, 12, 8))

func tile_for(id: String) -> Dictionary:
	return _tiles.get(id, {})

## Elige el animal (todos son tuyos).
func pick(id: String) -> void:
	Account.select_skin(id)

func _tile(id: String) -> Button:
	var b := Button.new()
	b.name = "Tile_" + id
	b.custom_minimum_size = Vector2(150, 168)
	b.focus_mode = Control.FOCUS_NONE
	var active := AnimalAbilities.active_of(id)
	var passive := AnimalAbilities.passive_of(id)
	b.tooltip_text = "%s\nActiva · %s: %s\nPasiva · %s: %s" % [skin_name(id), active.get("name", ""), active.get("description", ""), passive.get("name", ""), passive.get("description", "")]
	var box := vbox(2)
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 8)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(box)
	var stage := Control.new()
	stage.custom_minimum_size = Vector2(0, 104)
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var preview := SkinPreview.new()
	preview.skin_id = id
	preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stage.add_child(preview)
	box.add_child(stage)
	var title := heading(skin_name(id), 15)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(title)
	var hint := caption("", 11)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(hint)
	b.pressed.connect(pick.bind(id))
	b.mouse_entered.connect(func() -> void: preview.walking = true)
	b.mouse_exited.connect(func() -> void: preview.walking = false)
	_tiles[id] = {"button": b, "preview": preview, "hint": hint}
	return b
