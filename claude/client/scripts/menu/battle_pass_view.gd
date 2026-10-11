class_name BattlePassView
extends MenuView
## Executive Pass (temporada 1): nivel y barra de XP, pista de recompensas de los
## niveles 1–50 en dos filas (Gratis y Premium) y la colección de cosméticos de la
## temporada, cada uno puesto sobre tu animal. El pase solo da cosméticos y monedas:
## los 12 animales y sus habilidades son gratis para todos. El Premium se compra con
## Monedas Corporativas (moneda del juego; no hay pagos reales). Reclamar y comprar los
## valida el servidor.

const COLUMN_WIDTH := 96

@onready var title_label: Label = %PassTitle
@onready var season_label: Label = %SeasonLabel
@onready var level_label: Label = %LevelLabel
@onready var xp_label: Label = %XpLabel
@onready var xp_bar: ProgressBar = %XpBar
@onready var claim_all_button: Button = %ClaimAllButton
@onready var premium_button: Button = %PremiumButton
@onready var premium_chip: PanelContainer = %PremiumChip
@onready var track_scroll: ScrollContainer = %TrackScroll
@onready var track: HBoxContainer = %Track
@onready var collection: HBoxContainer = %Collection

var _columns := {}   # nivel -> {"free": Control, "premium": Control}
var _previews := {}  # cosmetic_id -> {preview, check, source} de la colección
var _reward_previews: Array[SkinPreview] = []   # casillas de la pista con un cosmético
var _signature := ""

func build() -> void:
	title_label.add_theme_font_override("font", UiPalette.heading_font())
	title_label.add_theme_font_size_override("font_size", 30)
	title_label.add_theme_color_override("font_color", UiPalette.AMBER)
	season_label.add_theme_color_override("font_color", DIM)
	level_label.add_theme_font_override("font", UiPalette.heading_font())
	level_label.add_theme_font_size_override("font_size", 22)
	xp_label.add_theme_font_size_override("font_size", 12)
	xp_label.add_theme_color_override("font_color", DIM)
	xp_bar.add_theme_stylebox_override("fill", UiPalette.flat(UiPalette.AMBER, Color.TRANSPARENT, 0, 4, 0))
	cta(premium_button)
	UiPalette.style_button(claim_all_button, GREEN)
	premium_chip.add_theme_stylebox_override("panel", UiPalette.flat(Color(UiPalette.AMBER, 0.18), UiPalette.AMBER, 1, 10, 6))
	%CollectionTitle.add_theme_font_override("font", UiPalette.heading_font())
	%CollectionTitle.add_theme_font_size_override("font_size", 16)
	%TrackPanel.add_theme_stylebox_override("panel", UiPalette.flat(Color(UiPalette.NAVY, 0.6), Color(1, 1, 1, 0.06), 1, 12, 10))
	premium_button.pressed.connect(func() -> void: Account.buy_premium())
	claim_all_button.pressed.connect(func() -> void: Account.claim_all())
	var bp := Progression.pass_config()
	title_label.text = str(bp.get("name", "Executive Pass")).to_upper()
	season_label.text = str(bp.get("season", ""))
	premium_button.text = "Desbloquear Premium · %s" % Progression.price_text(Progression.premium_price())
	for level in range(1, Progression.max_pass_level() + 1):
		track.add_child(_column(level))
	for id in season_cosmetics():
		collection.add_child(_collection_card(id))

## Cosméticos que da el pase, por nivel.
static func season_cosmetics() -> Array:
	var rewards: Array = Progression.pass_config().get("cosmetic_rewards", []).duplicate()
	rewards.sort_custom(func(a, b): return int(a["level"]) < int(b["level"]))
	return rewards.map(func(r): return str(r["cosmetic"]))

func refresh() -> void:
	var pv := Account.pass_view()
	var level := int(pv.get("level", 1))
	var signature := JSON.stringify([pv, Account.owned_cosmetics(), Account.equipped(), Account.selected_skin(), Account.coins()])
	if signature == _signature:
		return
	_signature = signature
	level_label.text = "NIVEL %d / %d" % [level, Progression.max_pass_level()]
	var into := int(pv.get("xpIntoLevel", 0))
	var need := int(pv.get("xpForLevel", Progression.pass_config().get("xp_per_level", 400)))
	xp_bar.max_value = need
	xp_bar.value = into
	xp_label.text = "%d / %d XP para el nivel %d" % [into, need, mini(level + 1, Progression.max_pass_level())] if level < Progression.max_pass_level() else "Nivel máximo"
	var premium := Account.is_premium()
	premium_button.visible = not premium
	premium_button.disabled = not Account.can_afford(Progression.premium_price())
	premium_chip.visible = premium
	var pending := 0
	for track_id in ["free", "premium"]:
		pending += pv.get("claimable", {}).get(track_id, []).size()
	claim_all_button.visible = pending > 0
	claim_all_button.text = "Reclamar todo (%d)" % pending
	for l in _columns:
		for track_id in ["free", "premium"]:
			_paint_reward(_columns[l][track_id], l, track_id, level, premium)
		_columns[l]["number"].add_theme_color_override("font_color", UiPalette.AMBER if l == level else (Color.WHITE if l < level else DIM))
	var skin := Account.selected_skin()
	for preview in _reward_previews:
		preview.skin_id = skin
		preview.look = ShopView.try_on(str(preview.get_meta("cosmetic")))
	for id in _previews:
		var owned := Account.owns_cosmetic(id)
		_previews[id]["preview"].skin_id = skin
		_previews[id]["preview"].look = ShopView.try_on(id)
		_previews[id]["check"].visible = owned
		_previews[id]["source"].text = "En tu armario" if owned else Progression.source_text(id)

## Estado de una casilla: "claimed", "claimable", "locked" (nivel no alcanzado) o "premium_locked".
static func reward_state(level: int, track_id: String, pass_level: int, premium: bool, claimed: bool) -> String:
	if claimed:
		return "claimed"
	if level > pass_level:
		return "locked"
	if track_id == "premium" and not premium:
		return "premium_locked"
	return "claimable"

func reward_cell(level: int, track_id: String) -> Control:
	return _columns[level][track_id]

## Desplaza la pista para que se vea el nivel actual.
func scroll_to_level(level: int) -> void:
	track_scroll.scroll_horizontal = maxi(0, (level - 3) * (COLUMN_WIDTH + 8))

func _column(level: int) -> VBoxContainer:
	var col := vbox(6)
	col.name = "Level%d" % level
	col.custom_minimum_size.x = COLUMN_WIDTH
	var number := Label.new()
	number.text = str(level)
	number.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	number.add_theme_font_override("font", UiPalette.heading_font())
	number.add_theme_font_size_override("font_size", 16)
	col.add_child(number)
	var cells := {"number": number}
	for track_id in ["free", "premium"]:
		var cell := _reward_cell(level, track_id)
		col.add_child(cell)
		cells[track_id] = cell
	_columns[level] = cells
	return col

func _reward_cell(level: int, track_id: String) -> PanelContainer:
	var cell := PanelContainer.new()
	cell.name = "Free" if track_id == "free" else "Premium"
	cell.custom_minimum_size = Vector2(COLUMN_WIDTH, 126)
	var box := vbox(2)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	cell.add_child(box)
	var reward := Progression.reward_at(level, track_id)
	var visual := CenterContainer.new()
	visual.custom_minimum_size = Vector2(0, 62)
	box.add_child(visual)
	if reward["kind"] == "cosmetic":
		var preview := SkinPreview.new()
		preview.skin_id = Account.selected_skin()
		preview.look = ShopView.try_on(reward["cosmetic"])
		preview.set_meta("cosmetic", reward["cosmetic"])
		preview.custom_minimum_size = Vector2(80, 62)
		visual.add_child(preview)
		_reward_previews.append(preview)
	elif reward["kind"] == "skin":
		var preview := SkinPreview.new()
		preview.skin_id = reward["skin"]
		preview.custom_minimum_size = Vector2(80, 62)
		visual.add_child(preview)
	else:
		visual.add_child(MenuIcon.make("coin" if reward["kind"] == "coins" else "diamond", Color.WHITE, 34))
	var label := Label.new()
	label.name = "RewardLabel"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 12)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	match reward["kind"]:
		"cosmetic":
			label.text = str(CosmeticCatalog.item(reward["cosmetic"]).get("name", reward["cosmetic"]))
			label.add_theme_font_size_override("font_size", 11)
		"skin":
			label.text = skin_name(reward["skin"])
		_:
			label.text = "+%s %s" % [Progression.format_amount(reward["amount"]), Progression.currency_short(reward["kind"])]
	box.add_child(label)
	var button := Button.new()
	button.name = "ClaimButton"
	button.text = "Reclamar"
	button.custom_minimum_size.y = 26
	button.add_theme_font_size_override("font_size", 12)
	cta(button, GREEN)
	button.pressed.connect(func() -> void: Account.claim_reward(level, track_id))
	box.add_child(button)
	var status := HBoxContainer.new()
	status.name = "Status"
	status.alignment = BoxContainer.ALIGNMENT_CENTER
	status.custom_minimum_size.y = 26
	var status_icon := MenuIcon.make("lock", DIM, 14)
	status_icon.name = "StatusIcon"
	status.add_child(status_icon)
	var status_label := Label.new()
	status_label.name = "StatusLabel"
	status_label.add_theme_font_size_override("font_size", 11)
	status_label.add_theme_color_override("font_color", DIM)
	status.add_child(status_label)
	box.add_child(status)
	return cell

func _paint_reward(cell: PanelContainer, level: int, track_id: String, pass_level: int, premium: bool) -> void:
	var state := reward_state(level, track_id, pass_level, premium, Account.is_claimed(level, track_id))
	cell.set_meta("state", state)
	var accent := UiPalette.AMBER if track_id == "premium" else UiPalette.CYAN
	var bg := Color(accent, 0.10) if state != "locked" else Color(1, 1, 1, 0.03)
	var border := Color(accent, 0.35)
	if state == "claimable":
		border = GREEN
	elif state == "claimed":
		bg = Color(1, 1, 1, 0.04)
		border = Color(1, 1, 1, 0.08)
	cell.add_theme_stylebox_override("panel", UiPalette.flat(bg, border, 2 if state == "claimable" else 1, 10, 6))
	cell.modulate = Color(1, 1, 1, 0.55) if state in ["locked", "claimed"] else Color.WHITE
	var button: Button = cell.find_child("ClaimButton", true, false)
	button.visible = state == "claimable"
	var status: HBoxContainer = cell.find_child("Status", true, false)
	status.visible = state != "claimable"
	var status_icon: MenuIcon = status.get_node("StatusIcon")
	var status_label: Label = status.get_node("StatusLabel")
	match state:
		"claimed":
			status_icon.icon = "check"
			status_icon.color = GREEN
			status_label.text = "Reclamado"
		"premium_locked":
			status_icon.icon = "lock"
			status_icon.color = UiPalette.AMBER
			status_label.text = "Premium"
		_:
			status_icon.icon = "lock"
			status_icon.color = DIM
			status_label.text = "Nivel %d" % level

func _collection_card(id: String) -> VBoxContainer:
	var box := vbox(2)
	box.name = "Cosmetic_" + id
	box.custom_minimum_size.x = 92
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(92, 86)
	var preview := SkinPreview.new()
	preview.skin_id = Account.selected_skin()
	preview.look = ShopView.try_on(id)
	preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	holder.add_child(preview)
	var check := MenuIcon.make("check", GREEN, 18)
	check.position = Vector2(72, 0)
	holder.add_child(check)
	box.add_child(holder)
	var name_label := Label.new()
	name_label.text = str(CosmeticCatalog.item(id).get("name", id))
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.add_theme_color_override("font_color", CosmeticCatalog.rarity_color(id).lightened(0.3) if CosmeticCatalog.item(id).has("rarity") else Color.WHITE)
	name_label.add_theme_font_override("font", UiPalette.bold_font())
	name_label.add_theme_font_size_override("font_size", 12)
	box.add_child(name_label)
	var source := Label.new()
	source.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	source.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	source.add_theme_font_size_override("font_size", 10)
	source.add_theme_color_override("font_color", DIM)
	box.add_child(source)
	# Al pasar el ratón, tu animal camina en el sitio con el cosmético puesto.
	holder.mouse_entered.connect(func() -> void: preview.walking = true)
	holder.mouse_exited.connect(func() -> void: preview.walking = false)
	_previews[id] = {"preview": preview, "check": check, "source": source}
	return box

func collection_preview(id: String) -> SkinPreview:
	return _previews[id]["preview"]
