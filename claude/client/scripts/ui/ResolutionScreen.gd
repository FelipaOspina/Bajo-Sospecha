class_name ResolutionScreen
extends Control
## Pantalla final: veredicto, recuento, finales cumplidos, roles revelados y
## objetivos secretos de cada jugador. Abajo, lo ganado (XP y monedas, cuando llega
## del servidor) y el botón para volver al menú.

## Main sale de la sala y vuelve al menú.
signal back_to_menu_requested

@export var trial: TrialSystem

var _box: VBoxContainer
var rewards_label: Label
var back_button: Button

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.04, 0.06, 0.95)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.offset_bottom = -96   # deja sitio a las recompensas y al botón
	add_child(scroll)
	_box = VBoxContainer.new()
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_box.add_theme_constant_override("separation", 8)
	scroll.add_child(_box)
	var footer := PanelContainer.new()
	footer.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 24)
	footer.grow_horizontal = Control.GROW_DIRECTION_BOTH
	footer.grow_vertical = Control.GROW_DIRECTION_BEGIN
	footer.add_theme_stylebox_override("panel", UiPalette.flat(Color(UiPalette.NAVY, 0.95), Color(UiPalette.AMBER, 0.6), 1, 12, 12))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	footer.add_child(row)
	rewards_label = Label.new()
	rewards_label.text = "Calculando recompensas…"
	rewards_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rewards_label.add_theme_color_override("font_color", Color("#FFE7A8"))
	row.add_child(rewards_label)
	back_button = Button.new()
	back_button.text = "Volver al menú"
	back_button.custom_minimum_size = Vector2(180, 40)
	UiPalette.style_button(back_button, UiPalette.AMBER)
	back_button.pressed.connect(func() -> void: back_to_menu_requested.emit())
	row.add_child(back_button)
	add_child(footer)
	hide()
	trial.resolved.connect(show_resolution)
	Account.rewards_granted.connect(show_rewards)

func show_resolution(r: Dictionary) -> void:
	for c in _box.get_children():
		c.queue_free()
	var me := GameState.local_player_id()

	var endings: Array = r.get("endings", [])
	_add(endings[0]["title"] if endings.size() == 1 else ("Varios finales" if endings.size() > 1 else "Nadie se sale con la suya"), 30)
	_add("Has ganado." if me in r.get("winners", []) else "Has perdido.", 22)
	for e in endings:
		_add("• %s: %s" % [e["title"], e.get("description", "")])

	var verdict: Dictionary = r.get("verdict", {})
	_add("Veredicto: %s" % verdict.get("label", "-"), 20)
	var labels := {}
	for o in trial.options:
		labels[o["id"]] = o["label"]
	for option_id in verdict.get("tally", {}):
		_add("   %s: %d votos" % [labels.get(option_id, option_id), verdict["tally"][option_id]])

	_add("Roles", 20)
	for p in r.get("players", []):
		_add("%s %s — %s" % ["★" if p["won"] else "·", p["name"], p["roleName"]])
		for o in p.get("objectives", []):
			_add("      %s %s" % ["✓" if o["completed"] else "–", o["description"]])
	show()

## XP y Monedas Corporativas de la partida (llegan del servidor tras el veredicto).
func show_rewards(r: Dictionary) -> void:
	var text := "+%d XP · +%d %s" % [int(r.get("xp", 0)), int(r.get("coins", 0)), Progression.currency_short("coins")]
	if int(r.get("levelsGained", 0)) > 0:
		text += " · ¡subes de nivel!"
	if int(r.get("passLevelsGained", 0)) > 0:
		text += " · Executive Pass +%d" % int(r["passLevelsGained"])
	rewards_label.text = text

func _add(text: String, size := 15) -> void:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", size)
	_box.add_child(l)
