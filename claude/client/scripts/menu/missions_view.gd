class_name MissionsView
extends MenuView
## Misiones: lo que da XP y monedas en cada partida (reglas reales del servidor).
## Arriba, un acceso a la Ruta del Detective con los retos que tienes activos.
## Las misiones diarias y semanales llegarán más adelante.

var path_card: PanelContainer
var path_text: Label

func build() -> void:
	var layout := vbox(14)
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(layout)
	layout.add_child(heading("MISIONES", 28))
	layout.add_child(caption("Cada partida suma experiencia de perfil y del Executive Pass, y Monedas Corporativas.", 13))
	path_card = card(Color(0.16, 0.13, 0.05, 0.92), Color(UiPalette.AMBER, 0.5))
	path_card.name = "PathCard"
	var prow := hbox(12)
	path_card.add_child(prow)
	var picon := MenuIcon.make("search", UiPalette.AMBER, 28)
	picon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	prow.add_child(picon)
	var pcol := vbox(2)
	pcol.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	prow.add_child(pcol)
	pcol.add_child(heading("Ruta del Detective", 17))
	path_text = caption("", 13, Color("#FFE7A8"))
	pcol.add_child(path_text)
	var go := Button.new()
	go.text = "  Ver la Ruta  "
	go.custom_minimum_size.y = 36
	go.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cta(go)
	go.pressed.connect(func() -> void: tab_requested.emit("ruta"))
	prow.add_child(go)
	layout.add_child(path_card)
	var r := Progression.match_rewards()
	var list := vbox(10)
	layout.add_child(list)
	list.add_child(_mission("Juega una partida completa", "+%d XP · +%d MC" % [r.get("xp_played", 0), r.get("coins_played", 0)], "clipboard"))
	list.add_child(_mission("Gana la partida con tu equipo", "+%d XP · +%d MC" % [r.get("xp_win", 0), r.get("coins_win", 0)], "star"))
	list.add_child(_mission("Cumple cada objetivo secreto de tu rol", "+%d XP por objetivo" % r.get("xp_per_objective", 0), "search"))
	var soon := card(Color(0.09, 0.12, 0.19, 0.6), Color(1, 1, 1, 0.06))
	var sbox := hbox(10)
	soon.add_child(sbox)
	sbox.add_child(MenuIcon.make("lock", DIM, 22))
	sbox.add_child(caption("Misiones diarias y semanales: próximamente.", 14))
	layout.add_child(soon)

func refresh() -> void:
	var open: Array = preload("res://scripts/menu/DetectivePath.gd").open_challenges(Account.level(), Account.profile)
	var xp := 0
	for l in open:
		xp += int(l.get("challenge", {}).get("xp", 0))
	path_text.text = ("Retos activos: %d (+%d XP). Próximo: %s" % [open.size(), xp, str(open[0].get("challenge", {}).get("text", ""))]) if not open.is_empty() \
		else "Cada nivel enseña una mecánica y su reto da XP extra la primera vez."

func _mission(title: String, reward: String, icon_name: String) -> PanelContainer:
	var c := card()
	var row := hbox(12)
	c.add_child(row)
	var icon := MenuIcon.make(icon_name, UiPalette.AMBER, 28)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(icon)
	var t := heading(title, 17)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(t)
	var r := heading(reward, 15, Color("#FFE7A8"))
	row.add_child(r)
	return c
