class_name InventoryView
extends MenuView
## Inventario: saldo de Monedas Corporativas y Créditos Nexus (y cómo se ganan), estado
## del Executive Pass, estadísticas y tu armario: lo que llevas puesto sobre tu animal y
## los cosméticos que tienes, por hueco (ropa, gorra, zapatillas, mochila), para ponértelos
## o quitártelos. Los cosméticos no cambian nada del juego ni dicen nada de tu rol.

var coins_box: HBoxContainer
var credits_box: HBoxContainer
var pass_label: Label
var stats_label: Label
var outfit_preview: SkinPreview
var worn_label: Label
var wardrobe: VBoxContainer
var _signature := ""

func build() -> void:
	var layout := vbox(12)
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(layout)
	layout.add_child(heading("INVENTARIO", 28))

	var top := hbox(12)
	layout.add_child(top)
	var rewards := Progression.match_rewards()
	coins_box = _wallet(top, "coins", "Se ganan al jugar (+%d por partida, +%d si ganas) y en el pase." % [rewards.get("coins_played", 0), rewards.get("coins_win", 0)])
	credits_box = _wallet(top, "credits", "Moneda rara: llega con niveles del Executive Pass.")
	var pass_card := card()
	pass_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var pbox := vbox(4)
	pass_card.add_child(pbox)
	pbox.add_child(heading("Executive Pass", 16, UiPalette.AMBER))
	pass_label = caption("", 13, Color.WHITE)
	pbox.add_child(pass_label)
	stats_label = caption("", 12)
	pbox.add_child(stats_label)
	top.add_child(pass_card)

	var closet := hbox(12)
	closet.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(closet)
	var mirror := card(Color(0.06, 0.08, 0.13, 0.9), Color(UiPalette.AMBER, 0.3), 12)
	mirror.custom_minimum_size.x = 250
	closet.add_child(mirror)
	var mbox := vbox(6)
	mirror.add_child(mbox)
	mbox.add_child(heading("TU ARMARIO", 14, DIM))
	outfit_preview = SkinPreview.new()
	outfit_preview.name = "OutfitPreview"
	outfit_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outfit_preview.custom_minimum_size = Vector2(0, 150)
	mbox.add_child(outfit_preview)
	worn_label = caption("", 12, Color.WHITE)
	mbox.add_child(worn_label)
	var more := Button.new()
	more.text = "Más en la Tienda"
	UiPalette.style_button(more, UiPalette.AMBER)
	more.pressed.connect(func() -> void: tab_requested.emit("tienda"))
	mbox.add_child(more)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	closet.add_child(scroll)
	wardrobe = vbox(8)
	wardrobe.name = "Wardrobe"
	wardrobe.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(wardrobe)

func _wallet(parent: Container, currency: String, text: String) -> HBoxContainer:
	var c := card()
	c.custom_minimum_size.x = 250
	var box := vbox(4)
	c.add_child(box)
	box.add_child(heading(Progression.currency_name(currency), 15, DIM))
	var amount := hbox(0)
	amount.name = "Amount"
	box.add_child(amount)
	box.add_child(caption(text, 11))
	parent.add_child(c)
	return amount

func refresh() -> void:
	var signature := JSON.stringify([Account.profile])
	if signature == _signature:
		return
	_signature = signature
	for box in [coins_box, credits_box]:
		for child in box.get_children():
			child.queue_free()
	coins_box.add_child(amount_row("coins", Account.coins(), 26, true))
	credits_box.add_child(amount_row("credits", Account.credits(), 26, true))
	var pv := Account.pass_view()
	pass_label.text = "Nivel %d de %d · %s" % [int(pv.get("level", 1)), Progression.max_pass_level(), "Premium activo" if Account.is_premium() else "Pista gratuita"]
	var stats: Dictionary = Account.profile.get("stats", {})
	stats_label.text = "Nivel de perfil %d · %d partidas · %d victorias" % [Account.level(), int(stats.get("played", 0)), int(stats.get("won", 0))]
	var equipped := Account.equipped()
	outfit_preview.skin_id = Account.selected_skin()
	outfit_preview.look = equipped
	var worn: Array[String] = []
	for slot in CosmeticCatalog.SLOTS:
		if equipped.get(slot):
			worn.append(str(CosmeticCatalog.item(str(equipped[slot])).get("name", equipped[slot])))
	worn_label.text = "%s con %s." % [skin_name(Account.selected_skin()), ", ".join(worn)] if not worn.is_empty() else "%s con su ropa de serie." % skin_name(Account.selected_skin())
	for child in wardrobe.get_children():
		child.queue_free()
	for slot in CosmeticCatalog.SLOTS:
		wardrobe.add_child(heading(CosmeticCatalog.slot_name(slot), 16))
		var row := HFlowContainer.new()
		row.name = "Slot_" + slot
		row.add_theme_constant_override("h_separation", 8)
		row.add_theme_constant_override("v_separation", 8)
		wardrobe.add_child(row)
		row.add_child(_wear_button(slot, "", "De serie", Color("#475569"), not equipped.get(slot)))
		for it in CosmeticCatalog.by_slot(slot):
			if Account.owns_cosmetic(str(it["id"])):
				row.add_child(_wear_button(slot, str(it["id"]), str(it["name"]), Color(it["color"]), equipped.get(slot) == it["id"]))

## Botón de una prenda: muestra su color y su nombre; al pulsarlo te la pones (o te
## quitas la de ese hueco, con "De serie").
func _wear_button(slot: String, id: String, label: String, color: Color, worn: bool) -> Button:
	var b := Button.new()
	b.name = "Wear_" + (id if id != "" else slot + "_default")
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 36)
	b.toggle_mode = true
	b.button_pressed = worn
	b.text = label
	b.add_theme_font_size_override("font_size", 13)
	var border := UiPalette.AMBER if worn else (CosmeticCatalog.rarity_color(id) if id != "" and CosmeticCatalog.item(id).has("rarity") else Color(1, 1, 1, 0.12))
	for state in ["normal", "hover", "pressed", "hover_pressed"]:
		var bg := Color(0.13, 0.17, 0.27, 0.96) if state.begins_with("hover") else Color(0.09, 0.12, 0.19, 0.94)
		var sb := UiPalette.flat(bg, border, 2 if worn else 1, 10, 8)
		sb.content_margin_left = 34
		sb.content_margin_right = 12
		b.add_theme_stylebox_override(state, sb)
	var swatch := Panel.new()
	swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	swatch.add_theme_stylebox_override("panel", UiPalette.flat(color, Color(1, 1, 1, 0.5), 1, 8, 0))
	swatch.position = Vector2(10, 10)
	swatch.size = Vector2(16, 16)
	b.add_child(swatch)
	b.tooltip_text = "Llevas puesto: %s" % label if worn else "Ponerte: %s" % label
	b.pressed.connect(func() -> void:
		if not worn:
			Account.equip_cosmetic(slot, id)
		else:
			b.set_pressed_no_signal(true))
	return b
