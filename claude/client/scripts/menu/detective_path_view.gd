extends MenuView
## Pestaña «Ruta del Detective»: los niveles 1–15 del perfil como un camino. Cada nivel
## enseña una mecánica (tarjeta de lección) y tiene un reto que da XP extra la primera vez
## que se cumple en una partida real (lo cuenta el servidor). El nivel actual brilla, los
## alcanzados se encienden y los futuros salen con candado. Arriba: tu nivel, la XP del
## nivel y la práctica «Primer día en NexusCore».
## Sin class_name: MainMenu la carga con load().

## La práctica se pide desde aquí; la arranca MainMenu.
signal tutorial_requested

const Path := preload("res://scripts/menu/DetectivePath.gd")
const LessonCard := preload("res://scripts/menu/LessonCard.gd")
const GlassBox := preload("res://scripts/ui/GlassBox.gd")

const PER_ROW := 5
const NODE_R := 26.0

var level_label: Label
var title_label: Label
var xp_bar: ProgressBar
var xp_label: Label
var practice_button: Button
var next_label: Label
var map: Control
var card_holder: VBoxContainer
var card_scroll: ScrollContainer
var node_buttons := {}       # nivel → Button
var selected := 0
## El jugador ha elegido un nivel a mano (si no, se sigue su nivel actual).
var _picked := false
var _last_level := 0
var _time := 0.0

func build() -> void:
	var layout := vbox(12)
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(layout)

	var head := hbox(14)
	layout.add_child(head)
	var titles := vbox(2)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(titles)
	titles.add_child(heading(Path.path_name().to_upper(), 28))
	next_label = caption("", 13)
	next_label.name = "NextLabel"
	titles.add_child(next_label)

	var lvl_box := PanelContainer.new()
	lvl_box.add_theme_stylebox_override("panel", GlassBox.inset(12.0, 10.0))
	lvl_box.custom_minimum_size.x = 260
	head.add_child(lvl_box)
	var lv := vbox(4)
	lvl_box.add_child(lv)
	var row := hbox(8)
	lv.add_child(row)
	level_label = heading("Nv. 1", 20, Color("#FFE7A8"))
	level_label.name = "PathLevel"
	row.add_child(level_label)
	title_label = caption("", 13, Color.WHITE)
	title_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title_label)
	xp_bar = ProgressBar.new()
	xp_bar.name = "PathXp"
	xp_bar.show_percentage = false
	xp_bar.custom_minimum_size.y = 8
	xp_bar.add_theme_stylebox_override("background", UiPalette.flat(Color(1, 1, 1, 0.1), Color.TRANSPARENT, 0, 4, 0))
	xp_bar.add_theme_stylebox_override("fill", UiPalette.flat(UiPalette.AMBER, Color.TRANSPARENT, 0, 4, 0))
	lv.add_child(xp_bar)
	xp_label = caption("", 11)
	lv.add_child(xp_label)

	practice_button = Button.new()
	practice_button.name = "PracticeHeaderButton"
	practice_button.custom_minimum_size = Vector2(0, 52)
	practice_button.focus_mode = Control.FOCUS_NONE
	cta(practice_button)
	practice_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	practice_button.pressed.connect(func() -> void: tutorial_requested.emit())
	LobbyView._icon_label(practice_button, "play", "Primer día en NexusCore", Color("#1A1405"))
	head.add_child(practice_button)

	var body := hbox(14)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(body)
	var map_frame := PanelContainer.new()
	map_frame.name = "PathFrame"
	map_frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	map_frame.add_theme_stylebox_override("panel", UiPalette.flat(Color(0.03, 0.05, 0.10, 0.72), Color(1, 1, 1, 0.07), 1, 14, 0))
	body.add_child(map_frame)
	map = Control.new()
	map.name = "PathMap"
	map.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map.size_flags_vertical = Control.SIZE_EXPAND_FILL
	map.custom_minimum_size = Vector2(440, 300)
	map.clip_contents = true
	map.draw.connect(_draw_map)
	map.resized.connect(_layout_nodes)
	map_frame.add_child(map)
	for l in Path.levels():
		var n := int(l.get("level", 0))
		var b := Button.new()
		b.name = "Node_%d" % n
		b.flat = true
		b.focus_mode = Control.FOCUS_NONE
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		b.tooltip_text = "Nivel %d · %s" % [n, str(l.get("title", ""))]
		for s in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
			b.add_theme_stylebox_override(s, StyleBoxEmpty.new())
		b.custom_minimum_size = Vector2(NODE_R * 2 + 16, NODE_R * 2 + 16)
		b.size = b.custom_minimum_size
		b.pressed.connect(select_level.bind(n))
		map.add_child(b)
		node_buttons[n] = b

	card_scroll = ScrollContainer.new()
	card_scroll.name = "CardScroll"
	card_scroll.custom_minimum_size.x = 420
	card_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	card_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(card_scroll)
	card_holder = vbox(0)
	card_holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card_scroll.add_child(card_holder)

func _process(delta: float) -> void:
	_time += delta
	if is_visible_in_tree():
		map.queue_redraw()

func player_level() -> int:
	return Account.level()

func refresh() -> void:
	var level := player_level()
	var p := Account.profile
	var e := Path.entry(mini(level, Path.max_level()))
	level_label.text = "Nv. %d" % level
	title_label.text = str(e.get("title", "Detective")) if level <= Path.max_level() else "Detective veterano"
	xp_bar.max_value = maxi(1, int(p.get("xpForLevel", Path.xp_for_level(level))))
	xp_bar.value = int(p.get("xpIntoLevel", 0))
	xp_label.text = "%s / %s XP para el nivel %d" % [Progression.format_amount(int(xp_bar.value)), Progression.format_amount(int(xp_bar.max_value)), level + 1]
	var done := Account.tutorial_done() if Account.has_profile() else Account.tutorial_seen
	_set_practice_text("Repetir práctica" if done else "Primer día en NexusCore")
	var open := Path.open_challenges(level, p)
	if not Account.has_profile():
		next_label.text = "Conéctate para guardar tu progreso. Cada nivel enseña una mecánica; su reto da XP extra."
	elif level > Path.max_level() and open.is_empty():
		next_label.text = "Ruta completada. Tu XP sigue sumando niveles."
	elif open.is_empty():
		next_label.text = "Sube al nivel %d para desbloquear la siguiente lección y su reto." % (level + 1)
	else:
		next_label.text = "Retos activos: %d. Próximo: %s." % [open.size(), str(open[0].get("challenge", {}).get("text", ""))]
	if not _picked or level != _last_level or selected > Path.max_level():
		selected = clampi(level, 1, Path.max_level())
		_picked = false
	_last_level = level
	_show_card(selected)
	_layout_nodes()
	map.queue_redraw()

func _set_practice_text(text: String) -> void:
	var content := practice_button.get_node_or_null("Content")
	if content and content.get_child_count() > 1:
		(content.get_child(1) as Label).text = text
		practice_button.custom_minimum_size.x = content.get_combined_minimum_size().x + 28

## Muestra la lección del nivel n en la tarjeta de la derecha.
func select_level(n: int) -> void:
	selected = n
	_picked = true
	_show_card(n)
	map.queue_redraw()

func _show_card(n: int) -> void:
	for c in card_holder.get_children():
		c.queue_free()
	var level := player_level()
	var card := LessonCard.build(n, level, Account.profile, func() -> void: tutorial_requested.emit())
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card_holder.add_child(card)
	if n <= level:
		Account.mark_lesson_seen(n)

func lesson_card() -> Control:
	for c in card_holder.get_children():
		if not c.is_queued_for_deletion():
			return c
	return null

# ───── Camino ─────

## Centros de los nodos: filas de PER_ROW en zigzag (como una serpiente de tablero).
func node_center(n: int) -> Vector2:
	var count := maxi(1, Path.max_level())
	var rows := ceili(float(count) / PER_ROW)
	var i := n - 1
	var r := i / PER_ROW
	var c := i % PER_ROW
	if r % 2 == 1:
		c = PER_ROW - 1 - c
	var pad := Vector2(64, 52)
	var area := map.size - pad * 2
	var x := pad.x + (area.x * c / float(PER_ROW - 1) if PER_ROW > 1 else area.x / 2)
	var y := pad.y + (area.y * r / float(maxi(1, rows - 1)) if rows > 1 else area.y / 2)
	return Vector2(x, y)

func _layout_nodes() -> void:
	for n in node_buttons:
		var b: Button = node_buttons[n]
		b.position = node_center(n) - b.size / 2.0

func _draw_map() -> void:
	var level := player_level()
	var p := Account.profile
	var font := UiPalette.bold_font()
	var count := Path.max_level()
	# Tramos: dorados hasta tu nivel, apagados después.
	for n in range(1, count):
		var a := node_center(n)
		var b := node_center(n + 1)
		var lit := n + 1 <= level
		if lit:
			map.draw_line(a, b, Color(UiPalette.AMBER, 0.25), 12.0, true)
			map.draw_line(a, b, UiPalette.AMBER, 4.0, true)
		else:
			map.draw_dashed_line(a, b, Color(1, 1, 1, 0.18), 3.0, 9.0, true)
	for n in range(1, count + 1):
		var c := node_center(n)
		var state := Path.state_of(n, level, p)
		var e := Path.entry(n)
		var fill: Color
		var ring := Color(1, 1, 1, 0.25)
		match state:
			Path.DONE:
				fill = Color("#B7791F")
				ring = UiPalette.AMBER
			Path.CURRENT:
				fill = Color("#F5B70F")
				ring = Color("#FFE36A")
				var pulse := 0.5 + 0.5 * sin(_time * 3.2)
				for k in 3:
					map.draw_circle(c, NODE_R + 6 + k * 6 + pulse * 5, Color(1.0, 0.8, 0.2, 0.10 - k * 0.025))
			Path.REACHED:
				fill = Color("#1D4ED8")
				ring = Color("#60A5FA")
			_:
				fill = Color("#1E293B")
		if n == selected:
			map.draw_arc(c, NODE_R + 5, 0, TAU, 48, Color.WHITE, 2.0, true)
		map.draw_circle(c, NODE_R, fill)
		map.draw_arc(c, NODE_R, 0, TAU, 48, ring, 2.5, true)
		var label := str(n)
		var ink := Color("#1A1405") if state in [Path.CURRENT, Path.DONE] else Color.WHITE
		if state == Path.LOCKED:
			_draw_lock(c, Color("#64748B"))
		else:
			var size := 20
			var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
			map.draw_string(font, c + Vector2(-w / 2.0, 7), label, HORIZONTAL_ALIGNMENT_LEFT, -1, size, ink)
		if state == Path.DONE:
			_draw_check(c + Vector2(NODE_R * 0.72, -NODE_R * 0.72))
		elif state in [Path.REACHED, Path.CURRENT] and not Account.is_lesson_seen(n):
			_draw_new(c + Vector2(0, -NODE_R - 10))
		var title := str(e.get("title", ""))
		var tsize := 11
		var tw := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, tsize).x
		var tcol := Color("#FFE7A8") if state != Path.LOCKED else Color("#64748B")
		map.draw_string(font, c + Vector2(-tw / 2.0, NODE_R + 18), title, HORIZONTAL_ALIGNMENT_LEFT, -1, tsize, tcol)

func _draw_lock(c: Vector2, col: Color) -> void:
	map.draw_rect(Rect2(c + Vector2(-8, -2), Vector2(16, 12)), col)
	map.draw_arc(c + Vector2(0, -3), 5.5, PI, TAU, 12, col, 2.5, true)

func _draw_check(c: Vector2) -> void:
	map.draw_circle(c, 9, Color("#16A34A"))
	map.draw_polyline(PackedVector2Array([c + Vector2(-4, 0), c + Vector2(-1, 3.5), c + Vector2(4.5, -3.5)]), Color.WHITE, 2.2, true)

func _draw_new(c: Vector2) -> void:
	var font := UiPalette.bold_font()
	var w := font.get_string_size("NUEVA", HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x + 10
	map.draw_rect(Rect2(c - Vector2(w / 2.0, 8), Vector2(w, 14)), Color("#DC2626"))
	map.draw_string(font, c + Vector2(-w / 2.0 + 5, 3), "NUEVA", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color.WHITE)
