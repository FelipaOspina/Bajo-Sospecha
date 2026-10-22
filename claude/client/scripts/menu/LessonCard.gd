extends RefCounted
## Tarjeta de una lección de la Ruta del Detective: nivel y título, ilustración, explicación
## corta, controles, consejo, el reto del nivel (con su progreso y su XP) y la recompensa por
## llegar. Las lecciones bloqueadas solo enseñan el título. Ninguna lección habla del rol
## concreto de nadie: son reglas generales.

const Path := preload("res://scripts/menu/DetectivePath.gd")
const LessonArt := preload("res://scripts/menu/LessonArt.gd")
const GlassBox := preload("res://scripts/ui/GlassBox.gd")

const AMBER := Color("#E5A93C")
const GOLD := Color("#FFD21F")
const GREEN := Color("#4ADE80")
const DIM := Color("#94A3B8")

## Tarjeta del nivel n para un jugador de nivel `level`. on_practice: botón de la práctica
## (solo en el nivel 1; vacío = sin botón).
static func build(n: int, level: int, profile: Dictionary, on_practice: Callable = Callable()) -> PanelContainer:
	var e := Path.entry(n)
	var lesson: Dictionary = e.get("lesson", {})
	var state := Path.state_of(n, level, profile)
	var locked := state == Path.LOCKED
	var card := PanelContainer.new()
	card.name = "LessonCard"
	card.add_theme_stylebox_override("panel", GlassBox.panel(16.0, 16.0))
	var box := MenuView.vbox(10)
	card.add_child(box)

	var head := MenuView.hbox(8)
	box.add_child(head)
	var lvl := MenuView.heading("NIVEL %d · %s" % [n, str(e.get("title", "")).to_upper()], 12, AMBER)
	lvl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(lvl)
	head.add_child(_state_chip(state))
	var title := MenuView.heading(str(lesson.get("title", "")), 22)
	title.name = "LessonTitle"
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(title)

	var art: Control = LessonArt.make(str(lesson.get("art", "badge")), Vector2(360, 150))
	art.name = "LessonArt"
	if locked:
		art.modulate = Color(0.45, 0.48, 0.55, 0.7)
	box.add_child(art)

	if locked:
		var lock_row := MenuView.hbox(10)
		lock_row.add_child(MenuIcon.make("lock", DIM, 20))
		var l := MenuView.caption("Lección bloqueada: llega al nivel %d para leerla y activar su reto." % n, 14, DIM)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lock_row.add_child(l)
		box.add_child(lock_row)
	else:
		var body := MenuView.vbox(6)
		body.name = "LessonBody"
		box.add_child(body)
		for line in lesson.get("body", []):
			var row := MenuView.hbox(8)
			var dot := Label.new()
			dot.text = "•"
			dot.add_theme_color_override("font_color", AMBER)
			dot.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
			row.add_child(dot)
			var t := MenuView.caption(str(line), 13, Color("#E2E8F0"))
			t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(t)
			body.add_child(row)
		var controls: Array = lesson.get("controls", [])
		if not controls.is_empty():
			var flow := HFlowContainer.new()
			flow.name = "LessonControls"
			flow.add_theme_constant_override("h_separation", 8)
			flow.add_theme_constant_override("v_separation", 6)
			for c in controls:
				flow.add_child(_control_chip(str(c[0]), str(c[1]) if c.size() > 1 else ""))
			box.add_child(flow)
		var tip := str(lesson.get("tip", ""))
		if tip != "":
			var tip_box := PanelContainer.new()
			tip_box.add_theme_stylebox_override("panel", UiPalette.flat(Color(AMBER, 0.10), Color(AMBER, 0.35), 1, 10, 8))
			var tr := MenuView.hbox(8)
			tip_box.add_child(tr)
			var star := MenuIcon.make("star", AMBER, 16)
			star.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
			tr.add_child(star)
			var tl := MenuView.caption(tip, 12, Color("#FFE7A8"))
			tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			tr.add_child(tl)
			box.add_child(tip_box)

	var ch: Dictionary = e.get("challenge", {})
	if not ch.is_empty():
		box.add_child(_challenge_box(n, ch, state, profile, on_practice))
	var reward: Dictionary = e.get("reward", {})
	if not reward.is_empty():
		var rr := MenuView.hbox(8)
		rr.name = "LevelReward"
		rr.add_child(MenuIcon.make("ticket", GOLD, 18))
		var got := n <= level
		var rl := MenuView.caption(("Recompensa del nivel (recibida): " if got else "Recompensa al llegar: ") + Path.reward_text(reward), 12, GREEN if got else Color("#FFE7A8"))
		rl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rr.add_child(rl)
		box.add_child(rr)
	return card

static func _state_chip(state: String) -> PanelContainer:
	var text: String = {Path.DONE: "COMPLETADO", Path.CURRENT: "TU NIVEL", Path.REACHED: "RETO PENDIENTE", Path.LOCKED: "BLOQUEADO"}[state]
	var c: Color = {Path.DONE: GREEN, Path.CURRENT: GOLD, Path.REACHED: Color("#60A5FA"), Path.LOCKED: DIM}[state]
	var p := PanelContainer.new()
	p.name = "StateChip"
	p.add_theme_stylebox_override("panel", UiPalette.flat(Color(c, 0.16), Color(c, 0.6), 1, 8, 4))
	var l := MenuView.heading(text, 10, c)
	p.add_child(l)
	return p

static func _control_chip(key: String, what: String) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UiPalette.flat(Color(1, 1, 1, 0.05), Color(1, 1, 1, 0.12), 1, 8, 6))
	var row := MenuView.hbox(6)
	p.add_child(row)
	var k := PanelContainer.new()
	k.add_theme_stylebox_override("panel", UiPalette.flat(Color("#1E293B"), Color(1, 1, 1, 0.35), 1, 5, 4))
	var kl := MenuView.heading(key, 11, Color.WHITE)
	k.add_child(kl)
	row.add_child(k)
	if what != "":
		var wl := MenuView.caption(what, 11, Color("#CBD5E1"))
		wl.autowrap_mode = TextServer.AUTOWRAP_OFF
		wl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(wl)
	return p

static func _challenge_box(n: int, ch: Dictionary, state: String, profile: Dictionary, on_practice: Callable) -> PanelContainer:
	var done := Path.challenge_done(profile, str(ch.get("id", "")))
	var locked := state == Path.LOCKED
	var accent := GREEN if done else (DIM if locked else Color("#60A5FA"))
	var p := PanelContainer.new()
	p.name = "ChallengeBox"
	p.add_theme_stylebox_override("panel", UiPalette.flat(Color(accent, 0.10), Color(accent, 0.5), 1, 12, 10))
	var col := MenuView.vbox(6)
	p.add_child(col)
	var top := MenuView.hbox(8)
	col.add_child(top)
	var icon := MenuIcon.make("check" if done else ("lock" if locked else "clipboard"), accent, 20)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(icon)
	var info := MenuView.vbox(2)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(info)
	info.add_child(MenuView.heading("RETO", 10, accent))
	var text := MenuView.caption(str(ch.get("text", "")), 14, Color.WHITE)
	text.name = "ChallengeText"
	info.add_child(text)
	var xp := int(ch.get("xp", 0))
	if str(ch.get("stat", "")) == "tutorial":
		xp = int(Path.tutorial_reward().get("xp", 0))
	var reward := MenuView.heading("+%d XP" % xp, 15, GOLD)
	reward.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(reward)
	var target := int(ch.get("target", 1))
	var status: String
	if done:
		status = "Cumplido. ¡Buen trabajo, detective!"
	elif locked:
		status = "Se activa al llegar al nivel %d." % n
	elif str(ch.get("stat", "")) == "tutorial":
		status = "Práctica local de unos minutos, sin otros jugadores."
	elif str(ch.get("scope", "")) == "match":
		status = "En curso: hazlo dentro de una misma partida."
	else:
		status = "En curso: llevas %d de %d." % [Path.challenge_progress(profile, ch), target]
	var sl := MenuView.caption(status, 12, accent if done else DIM)
	sl.name = "ChallengeStatus"
	col.add_child(sl)
	if target > 1 and not locked:
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.custom_minimum_size.y = 6
		bar.max_value = target
		bar.value = Path.challenge_progress(profile, ch)
		bar.add_theme_stylebox_override("background", UiPalette.flat(Color(1, 1, 1, 0.1), Color.TRANSPARENT, 0, 3, 0))
		bar.add_theme_stylebox_override("fill", UiPalette.flat(accent, Color.TRANSPARENT, 0, 3, 0))
		col.add_child(bar)
	if str(ch.get("stat", "")) == "tutorial" and on_practice.is_valid():
		var b := Button.new()
		b.name = "PracticeButton"
		b.text = "  Repetir la práctica  " if done else "  Jugar la práctica  "
		b.custom_minimum_size.y = 36
		MenuView.cta(b)
		b.pressed.connect(on_practice)
		col.add_child(b)
	return p
