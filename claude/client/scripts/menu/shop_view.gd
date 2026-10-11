class_name ShopView
extends MenuView
## Tienda corporativa: cosméticos del avatar (ropa, gorras, zapatillas y mochilas) y el
## Executive Pass Premium. Los 12 animales y sus habilidades son gratis para todos: aquí
## no se venden. Todo se paga con monedas del juego (Monedas Corporativas o Créditos
## Nexus) que se ganan jugando. Los cosméticos no cambian nada del juego ni dicen nada
## de tu rol.
## Arriba, los paquetes de Créditos Nexus con su precio en dinero real (USD, o la moneda
## de tu región, p. ej. COP en es_CO; ver StorePrices). Solo se muestran: los pagos aún no
## están integrados y el botón está desactivado.

@onready var shelves: VBoxContainer = %Shelves
@onready var premium_buy: Button = %PremiumBuy
@onready var premium_state: Label = %PremiumState

var _cards := {}   # cosmetic_id -> {card, preview, price, buy, wear}
var _signature := ""

func build() -> void:
	%ShopTitle.add_theme_font_override("font", UiPalette.heading_font())
	%ShopTitle.add_theme_font_size_override("font_size", 30)
	%ShopTitle.add_theme_color_override("font_color", UiPalette.AMBER)
	%ShopNote.add_theme_color_override("font_color", DIM)
	%PremiumCard.add_theme_stylebox_override("panel", UiPalette.flat(Color("#2A2110", 0.95), UiPalette.AMBER, 2, 14, 14))
	%PremiumName.add_theme_font_override("font", UiPalette.heading_font())
	%PremiumName.add_theme_font_size_override("font_size", 22)
	%PremiumName.add_theme_color_override("font_color", Color("#FFE7A8"))
	%PremiumText.add_theme_color_override("font_color", Color("#E2D3B0"))
	premium_state.add_theme_color_override("font_color", GREEN)
	cta(premium_buy)
	premium_buy.text = "Comprar · %s" % Progression.price_text(Progression.premium_price())
	premium_buy.pressed.connect(func() -> void: Account.buy_premium())
	%GoToPass.pressed.connect(func() -> void: tab_requested.emit("pase"))
	UiPalette.style_button(%GoToPass, UiPalette.AMBER)
	var crown := MenuIcon.make("crown", UiPalette.AMBER, 54)
	crown.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	%PremiumBox.add_child(crown)
	%PremiumBox.move_child(crown, 0)
	_build_packs()
	for slot in CosmeticCatalog.SLOTS:
		var ids := shop_order(slot)
		if ids.is_empty():
			continue
		shelves.add_child(heading(CosmeticCatalog.slot_name(slot).to_upper(), 18, Color("#FFE7A8")))
		var grid := GridContainer.new()
		grid.name = "Grid_" + slot
		grid.columns = 4
		grid.add_theme_constant_override("h_separation", 10)
		grid.add_theme_constant_override("v_separation", 10)
		grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		shelves.add_child(grid)
		for id in ids:
			grid.add_child(_cosmetic_card(id))

## Cosméticos de un hueco que se venden en la tienda: Monedas Corporativas de menor a
## mayor y luego Créditos Nexus. Los de inicio y los que solo da el pase no salen aquí.
static func shop_order(slot: String) -> Array:
	var ids: Array = CosmeticCatalog.by_slot(slot).map(func(i): return str(i["id"])).filter(func(id): return not Progression.shop_price(id).is_empty())
	ids.sort_custom(func(a, b): return _weight(a) < _weight(b))
	return ids

static func _weight(id: String) -> int:
	var p := Progression.shop_price(id)
	return int(p.get("coins", 0)) + int(p.get("credits", 0)) * 100

func refresh() -> void:
	var signature := JSON.stringify([Account.owned_cosmetics(), Account.equipped(), Account.selected_skin(), Account.coins(), Account.credits(), Account.is_premium(), Account.has_profile()])
	if signature == _signature:
		return
	_signature = signature
	var premium := Account.is_premium()
	premium_buy.visible = not premium
	premium_buy.disabled = not Account.can_afford(Progression.premium_price())
	premium_state.visible = premium
	var skin := Account.selected_skin()
	for id in _cards:
		var c: Dictionary = _cards[id]
		var it := CosmeticCatalog.item(id)
		var owned := Account.owns_cosmetic(id)
		var worn := Account.is_equipped(id)
		var price := Progression.shop_price(id)
		c["preview"].skin_id = skin
		c["preview"].look = try_on(id)
		c["buy"].visible = not owned
		c["buy"].disabled = not Account.can_afford(price)
		c["wear"].visible = owned
		c["wear"].text = "Quitar" if worn else "Ponérmelo"
		c["price"].text = "En tu armario" if owned else Progression.price_text(price)
		var border := UiPalette.AMBER if worn else CosmeticCatalog.rarity_color(id) if it.has("rarity") else Color(1, 1, 1, 0.1)
		c["card"].add_theme_stylebox_override("panel", UiPalette.flat(Color(0.09, 0.12, 0.19, 0.94), border, 2 if worn or it.has("rarity") else 1, 12, 10))

## Lo que llevas puesto con este cosmético encima (para probártelo en la tarjeta).
static func try_on(cosmetic_id: String) -> Dictionary:
	var look := Account.equipped().duplicate()
	var it := CosmeticCatalog.item(cosmetic_id)
	if not it.is_empty():
		look[it["slot"]] = cosmetic_id
	return look

## Paquetes de Créditos Nexus con el precio en la moneda de tu región.
func _build_packs() -> void:
	if StorePrices.packs().is_empty():
		return
	shelves.add_child(heading("CRÉDITOS NEXUS", 18, Color("#BFF6FF")))
	var note := caption("Precios en %s según la región de tu dispositivo. Los pagos aún no están disponibles: por ahora los Créditos Nexus se ganan en el Executive Pass." % StorePrices.currency_for(), 12)
	note.name = "PacksNote"
	shelves.add_child(note)
	var grid := GridContainer.new()
	grid.name = "Grid_packs"
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shelves.add_child(grid)
	for pack in StorePrices.packs():
		grid.add_child(_pack_card(pack))

func _pack_card(pack: Dictionary) -> PanelContainer:
	var panel := card(Color(0.07, 0.13, 0.2, 0.94), Color("#22D3EE", 0.35))
	panel.name = "Pack_" + str(pack.get("id", ""))
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var box := vbox(4)
	panel.add_child(box)
	var icon := MenuIcon.make("diamond", Color.WHITE, 34)
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(icon)
	var amount := heading("%s CN" % Progression.format_amount(int(pack.get("credits", 0))), 18)
	amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(amount)
	var bonus := int(pack.get("bonus", 0))
	var extra := caption("+%s de regalo" % Progression.format_amount(bonus) if bonus > 0 else " ", 11, GREEN)
	extra.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(extra)
	var price := Label.new()
	price.name = "Price"
	price.text = StorePrices.price_text(pack)
	price.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	price.add_theme_font_override("font", UiPalette.bold_font())
	price.add_theme_font_size_override("font_size", 16)
	price.add_theme_color_override("font_color", Color("#FFE7A8"))
	box.add_child(price)
	var buy := Button.new()
	buy.name = "Buy"
	buy.text = "Próximamente"
	buy.disabled = true
	buy.tooltip_text = "Los pagos con dinero real aún no están integrados."
	buy.custom_minimum_size.y = 32
	cta(buy)
	box.add_child(buy)
	return panel

func card_for(id: String) -> Dictionary:
	return _cards.get(id, {})

func _cosmetic_card(id: String) -> PanelContainer:
	var it := CosmeticCatalog.item(id)
	var panel := card()
	panel.name = "Card_" + id
	panel.custom_minimum_size = Vector2(160, 0)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var box := vbox(4)
	panel.add_child(box)
	var stage := Control.new()
	stage.custom_minimum_size = Vector2(0, 112)
	var preview := SkinPreview.new()
	preview.skin_id = Account.selected_skin()
	preview.look = try_on(id)
	preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stage.add_child(preview)
	stage.mouse_entered.connect(func() -> void: preview.walking = true)
	stage.mouse_exited.connect(func() -> void: preview.walking = false)
	box.add_child(stage)
	var name_label := heading(str(it.get("name", id)), 15)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(name_label)
	var rarity := str({"rare": "Raro", "epic": "Épico"}.get(str(it.get("rarity", "")), ""))
	var unlock := Progression.pass_unlock(id)
	var hints: Array[String] = []
	if rarity != "":
		hints.append(rarity)
	if not unlock.is_empty():
		hints.append("También en el pase (nv. %d)" % unlock["level"])
	var hint := caption(" · ".join(hints) if not hints.is_empty() else " ", 11, CosmeticCatalog.rarity_color(id) if rarity != "" else DIM)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(hint)
	var price := Label.new()
	price.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	price.add_theme_font_override("font", UiPalette.bold_font())
	price.add_theme_color_override("font_color", Color("#FFE7A8"))
	box.add_child(price)
	var buy := Button.new()
	buy.name = "Buy"
	buy.text = "Comprar"
	buy.custom_minimum_size.y = 32
	cta(buy)
	buy.pressed.connect(func() -> void: Account.buy_cosmetic(id))
	box.add_child(buy)
	var wear := Button.new()
	wear.name = "Wear"
	wear.text = "Ponérmelo"
	wear.custom_minimum_size.y = 32
	UiPalette.style_button(wear, UiPalette.CYAN)
	wear.pressed.connect(func() -> void: Account.equip_cosmetic(str(it["slot"]), "" if Account.is_equipped(id) else id))
	box.add_child(wear)
	_cards[id] = {"card": panel, "preview": preview, "price": price, "buy": buy, "wear": wear}
	return panel
