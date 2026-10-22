extends Control
## Celebración tras una partida (o la práctica): subida de nivel con su nuevo título, la XP
## ganada, los retos de la Ruta del Detective cumplidos, las recompensas de nivel y la
## lección que se acaba de desbloquear. Es privada (solo la ve quien la gana) y nunca dice
## nada del rol con el que se jugó.
## MainMenu la crea con LevelUpPopup.show_for(parent, rewards).

signal lesson_requested(level: int)
signal closed

const Path := preload("res://scripts/menu/DetectivePath.gd")
const GlassBox := preload("res://scripts/ui/GlassBox.gd")
const GOLD := Color("#FFD21F")
const AMBER := Color("#E5A93C")
const GREEN := Color("#4ADE80")

var rewards: Dictionary = {}
var card: PanelContainer
var burst: Control
var lesson_button: Button
var continue_button: Button
var _t := 0.0
var _confetti: Array = []

static func show_for(parent: Node, r: Dictionary) -> Control:
	var p: Control = (load("res://scripts/menu/LevelUpPopup.gd") as GDScript).new()
	p.name = "LevelUpPopup"
	p.rewards = r
	parent.add_child(p)
	return p

func new_level() -> int:
	return int(rewards.get("level", Account.level()))

func levels_gained() -> int:
	return int(rewards.get("levelsGained", 0))

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.07, 0.72)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	burst = Control.new()
	burst.name = "Burst"
	burst.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	burst.mouse_filter = Control.MOUSE_FILTER_IGNORE
	burst.draw.connect(_draw_burst)
	add_child(burst)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	card = PanelContainer.new()
	card.name = "Card"
	card.custom_minimum_size.x = 500
	var style = GlassBox.panel(20.0, 22.0)
	style.with_glow(Color(1.0, 0.75, 0.1, 0.28), 18)
	card.add_theme_stylebox_override("panel", style)
	center.add_child(card)
	_build()
	for i in 70:
		_confetti.append({"x": randf(), "y": randf_range(-0.6, 0.0), "v": randf_range(0.10, 0.28), "r": randf() * TAU,
			"c": [GOLD, AMBER, Color("#60A5FA"), GREEN, Color("#F472B6")][i % 5], "s": randf_range(4, 8)})
	card.pivot_offset = card.size / 2.0
	card.scale = Vector2(0.6, 0.6)
	card.modulate.a = 0.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(card, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(card, "modulate:a", 1.0, 0.25)
	card.resized.connect(func() -> void: card.pivot_offset = card.size / 2.0)

func _build() -> void:
	var box := MenuView.vbox(10)
	card.add_child(box)
	var tutorial: bool = rewards.get("source") == "tutorial"
	var up := levels_gained() > 0
	var ribbon := "¡SUBES DE NIVEL!" if up else ("¡PRÁCTICA COMPLETADA!" if tutorial else "¡RETO CUMPLIDO!")
	var head := MenuView.heading(ribbon, 15, AMBER)
	head.name = "Ribbon"
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(head)
	var big := MenuView.heading("NIVEL %d" % new_level(), 54, GOLD)
	big.name = "BigLevel"
	big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(big)
	var e := Path.entry(new_level())
	var title := str(e.get("title", "Detective veterano")) if new_level() <= Path.max_level() else "Detective veterano"
	var sub := MenuView.heading(title, 20, Color.WHITE)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(sub)
	box.add_child(HSeparator.new())

	var rows := MenuView.vbox(6)
	rows.name = "Rows"
	box.add_child(rows)
	var match_xp := int(rewards.get("matchXp", rewards.get("xp", 0)))
	if not tutorial and match_xp > 0:
		rows.add_child(_row("clipboard", "XP de la partida", "+%d XP" % match_xp, Color.WHITE))
	for c in rewards.get("challenges", []):
		rows.add_child(_row("check", "Reto: " + str(c.get("text", "")), "+%d XP" % int(c.get("xp", 0)), GREEN))
	for lr in rewards.get("levelRewards", []):
		var reward := {}
		if lr.get("coins"):
			reward["coins"] = lr["coins"]
		if lr.get("cosmetic"):
			reward["cosmetic"] = lr["cosmetic"]
		rows.add_child(_row("ticket", "Recompensa del nivel %d" % int(lr.get("level", 0)), Path.reward_text(reward), GOLD))
	var coins := int(rewards.get("coins", 0))
	if coins > 0:
		rows.add_child(_row("coin", "Monedas Corporativas", "+%s MC" % Progression.format_amount(coins), Color("#FFE7A8")))
	if up and new_level() <= Path.max_level():
		var lesson: Dictionary = e.get("lesson", {})
		var unlocked := MenuView.caption("Nueva lección desbloqueada: «%s»" % str(lesson.get("title", "")), 14, Color("#BFDBFE"))
		unlocked.name = "Unlocked"
		unlocked.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(unlocked)

	var buttons := MenuView.hbox(10)
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(buttons)
	lesson_button = Button.new()
	lesson_button.name = "LessonButton"
	lesson_button.text = "  Ver la lección  " if up else "  Ver la Ruta  "
	lesson_button.custom_minimum_size = Vector2(170, 40)
	UiPalette.style_button(lesson_button, Color("#60A5FA"))
	lesson_button.pressed.connect(func() -> void:
		lesson_requested.emit(new_level())
		close())
	buttons.add_child(lesson_button)
	continue_button = Button.new()
	continue_button.name = "ContinueButton"
	continue_button.text = "  Continuar  "
	continue_button.custom_minimum_size = Vector2(150, 40)
	MenuView.cta(continue_button)
	continue_button.pressed.connect(close)
	buttons.add_child(continue_button)

func _row(icon: String, text: String, value: String, color: Color) -> HBoxContainer:
	var r := MenuView.hbox(10)
	var i := MenuIcon.make(icon, color, 18)
	i.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r.add_child(i)
	var l := MenuView.caption(text, 14, Color("#E2E8F0"))
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.add_child(l)
	var v := MenuView.heading(value, 15, color)
	v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r.add_child(v)
	return r

func close() -> void:
	if is_queued_for_deletion():
		return
	closed.emit()
	queue_free()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()

func _process(delta: float) -> void:
	_t += delta
	for c in _confetti:
		c["y"] += c["v"] * delta
		c["r"] += delta * 3.0
		if c["y"] > 1.05:
			c["y"] = -0.05
	burst.queue_redraw()

func _draw_burst() -> void:
	var c := burst.size / 2.0 + Vector2(0, -60)
	for i in 16:
		var a := _t * 0.25 + i * TAU / 16.0
		var w := 0.09
		var pts := PackedVector2Array([c, c + Vector2(cos(a - w), sin(a - w)) * 900.0, c + Vector2(cos(a + w), sin(a + w)) * 900.0])
		burst.draw_colored_polygon(pts, Color(1.0, 0.82, 0.25, 0.05))
	for k in _confetti:
		var p := Vector2(k["x"] * burst.size.x, k["y"] * burst.size.y)
		var s: float = k["s"]
		burst.draw_set_transform(p, k["r"], Vector2.ONE)
		burst.draw_rect(Rect2(-s / 2.0, -s / 4.0, s, s / 2.0), k["c"])
	burst.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
