extends Node
## Práctica «Primer día en NexusCore» (nivel 1 de la Ruta del Detective): una partida guiada,
## local y sin servidor, en la oficina real y con la interfaz real. TutorialServer hace de
## servidor (4 bots con guion) y este nodo lleva los pasos y el panel de ayuda:
##   moverse → examinar una prueba → guardarla → fotografiar la laptop (copia) →
##   ver un silenciamiento (testigo) → reportar el cuerpo → votar en la asamblea →
##   exponer una prueba en el juicio → votar el veredicto → fin (+XP).
## Al terminar pide su XP al servidor (Account.complete_tutorial: una vez por perfil; sin
## conexión queda pendiente para la próxima). La lanza MainMenu.start_tutorial().

signal step_changed(id: String)
signal finished(completed: bool)

const TutorialServer := preload("res://scripts/tutorial/TutorialServer.gd")
const GlassBox := preload("res://scripts/ui/GlassBox.gd")
const Path := preload("res://scripts/menu/DetectivePath.gd")

## Despacho del CEO (dentro, pasada la puerta del pasillo).
const OFFICE := Rect2(760, -400, 640, 740)
const DOOR := Vector2(1070, 330)
const STEPS := ["intro", "move", "inspect", "collect", "backup", "witness", "report", "vote", "verdict_wait", "present", "verdict", "done"]
## Pasos que cuentan en la barra de progreso (los de transición no).
const COUNTED := ["move", "inspect", "collect", "backup", "witness", "report", "vote", "present", "verdict"]

const TEXTS := {
	"intro": ["Primer día en NexusCore",
		"Esta noche hay auditoría en el piso 14 y alguien robó 1,8 millones. En esta práctica eres el Inversor (un rol de práctica) y los demás son bots. Tu rol es secreto: en una partida real nunca lo digas.",
		[["Briefing", "Tu rol y objetivos"], ["Bots", "Beto, Carla, Dani y Eva"]], "Empezar"],
	"move": ["Muévete",
		"Usa WASD, las flechas o el joystick. Entra en el despacho del CEO por la puerta del pasillo: sigue la marca. Solo ves lo que tu animal tiene a la vista.",
		[["WASD", "Moverte"], ["Joystick", "En el móvil"]], ""],
	"inspect": ["Examina la prueba",
		"Los objetos que brillan esconden pruebas. Acércate a los papeles junto a la caja fuerte y pulsa E (o haz clic) para examinarlos.",
		[["E / clic", "Examinar"]], ""],
	"collect": ["Guárdala",
		"Son avisos de cobro: una prueba de bolsillo. Pulsa «Guardar» para llevártela. Ojo: llevar una prueba contra un culpable te convierte en su objetivo.",
		[["Guardar", "Al inventario"]], ""],
	"backup": ["Haz una copia",
		"La laptop no se puede llevar, pero tu rol puede fotografiarla. Examínala y pulsa la acción de copia. Quédate quieto hasta que se llene la barra: moverte la interrumpe.",
		[["E", "Examinar"], ["Copiar", "Quieto 3 s"]], ""],
	"witness": ["¡Mira el pasillo!",
		"Dani acaba de silenciar a Eva y lo has visto: eres testigo. Solo los culpables pueden silenciar, y solo a quien les amenaza (lleva una prueba contra ellos, los vio o la historia les da un motivo). La 1.ª vez se queda noqueado 30 s; la 2.ª, fantasma.",
		[["Testigo", "Tu testimonio"], ["Noqueo", "30 s"], ["Fantasma", "2.ª vez"]], "Entendido"],
	"report": ["Reporta el cuerpo",
		"Acércate a Eva y pulsa REPORTAR [R]. Se abre una asamblea de emergencia y la investigación se pausa.",
		[["R", "Reportar"]], ""],
	"vote": ["Asamblea de emergencia",
		"Lee el chat y vota: a un jugador o «Saltar». Hace falta mayoría estricta para expulsar, y el rol del expulsado no se revela.",
		[["Votar", "Un jugador"], ["Saltar", "Nadie"], ["Chat", "Explica tu voto"]], ""],
	"verdict_wait": ["Resultado de la asamblea", "", [], "Ir al juicio"],
	"present": ["Juicio final: expón una prueba",
		"La investigación ha terminado. Arrastra una prueba de tu mano a la mesa (máximo 2 por jugador). Todos la verán completa.",
		[["Arrastrar", "A la mesa"], ["Máx. 2", "Las mejores"]], ""],
	"verdict": ["Vota el veredicto",
		"Mira lo que hay en la mesa: avisos de cobro, la foto de la laptop, facturas, una grabadora… ¿A quién señalan? Elige la decisión final y vota.",
		[["Votar", "Decisión final"], ["Secreto", "Hasta el final"]], ""],
	"done": ["¡Primer día completado!", "", [], "Volver al menú"],
}

var server: Node
var step := ""
var overlay: CanvasLayer
var panel: PanelContainer
var step_label: Label
var title_label: Label
var text_label: Label
var keys_box: HFlowContainer
var note_label: Label
var next_button: Button
var skip_button: Button
var dots: HBoxContainer
var completed := false
var _expelled := ""
var _watch_inspect := true

func _init() -> void:
	name = "Tutorial"

## Arranca la práctica (MainMenu la añade a Main y llama a begin()).
func begin() -> void:
	server = TutorialServer.new()
	add_child(server)
	_build_overlay()
	server.collected.connect(func(id: String) -> void:
		if step in ["inspect", "collect"] and id == TutorialServer.DEBTS:
			_go("backup"))
	server.backup_finished.connect(_on_backup)
	server.reported.connect(func() -> void:
		if step in ["witness", "report"]:
			_go("vote"))
	server.emergency_voted.connect(_on_emergency_vote)
	server.presented.connect(func() -> void:
		if step == "present":
			_go("verdict"))
	server.voted.connect(func(option) -> void:
		if step == "verdict" and option != null:
			server.after(1.2, func() -> void: server.resolve_trial()))
	server.resolved.connect(func() -> void: _go("done"))
	EventBus.evidence_inspect_requested.connect(_on_inspect)
	server.start(Account.player_name, Account.selected_skin())
	_go("intro")

func _exit_tree() -> void:
	if server:
		server.stop()

func _process(_delta: float) -> void:
	if step == "move" and OFFICE.has_point(server.my_position()) and server.my_position().y < 330.0:
		_go("inspect")

# ───── Pasos ─────

func _go(id: String) -> void:
	if step == id or step == "done":
		return
	step = id
	_show_step(id)
	match id:
		"intro":
			pass
		"move":
			server.set_phase("investigation", 600.0)
			server.mark(DOOR, 60.0)
		"inspect":
			server.highlight(TutorialServer.DEBTS)
		"collect":
			pass
		"backup":
			server.highlight(TutorialServer.LAPTOP)
		"witness":
			_play_silence()
		"report":
			server.mark(server.body_position(), 120.0)
		"vote":
			server.after(1.5, func() -> void: server.bot_chat("beto", "He visto a Dani salir corriendo del pasillo justo ahora."))
			server.after(3.5, func() -> void: server.bot_chat("dani", "¡Yo estaba en la cafetería! Beto se lo inventa."))
			server.after(5.0, func() -> void: server.bot_chat("carla", "Dani, la cafetería está en la otra punta…"))
		"verdict_wait":
			pass
		"present":
			server.end_investigation()
		"verdict":
			server.after(1.5, func() -> void: server.bots_present())
			server.after(3.0, func() -> void:
				if server.phase == "discussion":
					server.set_phase("voting", 60.0))
		"done":
			completed = true
			Account.complete_tutorial()
	step_changed.emit(id)

func _on_inspect(interactable: Node) -> void:
	if not _watch_inspect or interactable == null:
		return
	var iid := str(interactable.get("interactable_id"))
	if step in ["move", "inspect"] and iid == TutorialServer.DEBTS:
		_go("collect")

func _on_backup(ok: bool, reason: String) -> void:
	if step != "backup":
		return
	if ok:
		_go("witness")
	elif reason == "moved":
		_note("Te has movido y la foto se ha cortado. Vuelve a intentarlo sin moverte.")

func _on_emergency_vote(target) -> void:
	if step != "vote" or target == null:
		return
	server.after(0.8, func() -> void:
		server.bots_vote_emergency()
		server.after(1.0, func() -> void:
			_expelled = server.resolve_emergency()
			_go("verdict_wait")))

## Guion del silenciamiento: Dani camina hasta Eva, la silencia delante de ti y se va.
func _play_silence() -> void:
	next_button.disabled = true
	_note("Algo pasa en el pasillo…")
	var eva: Vector2 = server.players["eva"]["position"]
	server.walk("dani", eva + Vector2(46, -8))
	server.after(3.4, func() -> void:
		server.scripted_silence()
		server.walk("dani", Vector2(2300, 450))
		next_button.disabled = false
		_note(""))

func next_pressed() -> void:
	match step:
		"intro":
			_go("move")
		"witness":
			if not next_button.disabled:
				_go("report")
		"verdict_wait":
			_go("present")
		"done":
			finish()

## Fin (o salir antes): vuelve al menú como al acabar una partida.
func finish() -> void:
	if not completed:
		Account.set_tutorial_seen()
	finished.emit(completed)
	server.stop()
	# Fuera de la «sala» de práctica antes de volver: así no se manda leave_room al servidor real.
	Network.forget_room()
	GameState.reset()
	var main := get_tree().current_scene if is_inside_tree() else null
	if main and main.has_method("back_to_menu"):
		main.back_to_menu()
	else:
		queue_free()

# ───── Panel de ayuda ─────

func _show_step(id: String) -> void:
	var t: Array = TEXTS[id]
	title_label.text = t[0]
	var body: String = t[1]
	if id == "verdict_wait":
		var who := str(server.players.get(_expelled, {}).get("name", "")) if _expelled != "" else ""
		body = ("%s ha sido expulsado: ahora es un fantasma. Su rol no se revela hasta el final." % who) if who != "" \
			else "Nadie ha tenido mayoría, así que no se expulsa a nadie. Sin pruebas, saltar también es una buena decisión."
		body += " Al acabar la investigación llega el juicio final."
	elif id == "done":
		var r := Path.tutorial_reward()
		var claimed := Account.has_profile() and Account.tutorial_done()
		body = "Ya sabes explorar, guardar y copiar pruebas, reconocer un silenciamiento, reportar, votar en una asamblea y en el juicio. "
		if claimed:
			body += "La recompensa de la práctica ya la tenías: ¡repasar también cuenta!"
		elif Account.online:
			body += "+%d XP y +%d MC para tu perfil (nivel 1 de la Ruta del Detective)." % [int(r.get("xp", 0)), int(r.get("coins", 0))]
		else:
			body += "+%d XP y +%d MC se sumarán a tu perfil la próxima vez que te conectes." % [int(r.get("xp", 0)), int(r.get("coins", 0))]
	text_label.text = body
	for c in keys_box.get_children():
		c.queue_free()
	for k in t[2]:
		keys_box.add_child(_chip(k[0], k[1]))
	next_button.text = "  %s  " % t[3]
	next_button.visible = t[3] != ""
	next_button.disabled = false
	skip_button.visible = id != "done"
	_note("")
	var idx := COUNTED.find(id)
	step_label.text = "PRIMER DÍA EN NEXUSCORE" + (" · PASO %d DE %d" % [idx + 1, COUNTED.size()] if idx >= 0 else "")
	for i in dots.get_child_count():
		var done := idx >= 0 and i < idx or id == "done" or (idx < 0 and i < _last_counted(id))
		(dots.get_child(i) as ColorRect).color = UiPalette.AMBER if done else (Color("#FFE36A") if i == idx else Color(1, 1, 1, 0.18))
	_place_panel(id)
	panel.modulate.a = 0.0
	create_tween().tween_property(panel, "modulate:a", 1.0, 0.25)

func _last_counted(id: String) -> int:
	var i := STEPS.find(id)
	var n := 0
	for s in STEPS.slice(0, i):
		if s in COUNTED:
			n += 1
	return n

## En la exploración, arriba a la izquierda; en la asamblea y el juicio, abajo (no tapa
## la mesa ni la lista de votos); al final, en el centro.
func _place_panel(id: String) -> void:
	var vp := Vector2(1280, 720)
	if is_inside_tree():
		vp = get_viewport().get_visible_rect().size
	panel.size = Vector2(400, 0)
	panel.reset_size()
	var h := panel.get_combined_minimum_size().y
	match id:
		"present", "verdict":
			panel.position = Vector2(16, 96)   # la mano de pruebas está abajo
		"vote", "verdict_wait":
			panel.position = Vector2(minf(430.0, vp.x - 416.0), vp.y - h - 16)   # bajo las tarjetas de voto
		"done", "intro":
			panel.position = Vector2((vp.x - 400) / 2.0, (vp.y - h) / 2.0)
		_:
			panel.position = Vector2(16, 128)

func _note(text: String) -> void:
	note_label.text = text
	note_label.visible = text != ""
	_place_panel.call_deferred(step)

func _chip(key: String, what: String) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UiPalette.flat(Color(1, 1, 1, 0.06), Color(1, 1, 1, 0.14), 1, 8, 5))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	p.add_child(row)
	var k := Label.new()
	k.text = key
	k.add_theme_font_override("font", UiPalette.bold_font())
	k.add_theme_font_size_override("font_size", 12)
	k.add_theme_color_override("font_color", Color("#FFE7A8"))
	row.add_child(k)
	var w := Label.new()
	w.text = what
	w.add_theme_font_size_override("font_size", 12)
	w.add_theme_color_override("font_color", Color("#CBD5E1"))
	row.add_child(w)
	return p

func _build_overlay() -> void:
	overlay = CanvasLayer.new()
	overlay.name = "TutorialOverlay"
	overlay.layer = 60
	add_child(overlay)
	panel = PanelContainer.new()
	panel.name = "CoachPanel"
	var style = GlassBox.panel(16.0, 16.0)
	style.border_top = Color(UiPalette.AMBER, 0.85)
	style.with_glow(Color(1.0, 0.75, 0.1, 0.18), 10)
	panel.add_theme_stylebox_override("panel", style)
	panel.custom_minimum_size = Vector2(400, 0)
	overlay.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	step_label = Label.new()
	step_label.name = "StepLabel"
	step_label.add_theme_font_override("font", UiPalette.bold_font())
	step_label.add_theme_font_size_override("font_size", 10)
	step_label.add_theme_color_override("font_color", UiPalette.AMBER)
	box.add_child(step_label)
	dots = HBoxContainer.new()
	dots.add_theme_constant_override("separation", 4)
	for i in COUNTED.size():
		var d := ColorRect.new()
		d.custom_minimum_size = Vector2(36, 4)
		dots.add_child(d)
	box.add_child(dots)
	title_label = Label.new()
	title_label.name = "StepTitle"
	title_label.add_theme_font_override("font", UiPalette.heading_font())
	title_label.add_theme_font_size_override("font_size", 21)
	box.add_child(title_label)
	text_label = Label.new()
	text_label.name = "StepText"
	text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_label.custom_minimum_size.x = 368
	text_label.add_theme_font_size_override("font_size", 14)
	text_label.add_theme_color_override("font_color", Color("#E2E8F0"))
	box.add_child(text_label)
	keys_box = HFlowContainer.new()
	keys_box.add_theme_constant_override("h_separation", 6)
	keys_box.add_theme_constant_override("v_separation", 6)
	box.add_child(keys_box)
	note_label = Label.new()
	note_label.name = "StepNote"
	note_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note_label.add_theme_font_size_override("font_size", 13)
	note_label.add_theme_color_override("font_color", Color("#FCA5A5"))
	note_label.hide()
	box.add_child(note_label)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)
	skip_button = Button.new()
	skip_button.name = "SkipButton"
	skip_button.text = "Salir de la práctica"
	skip_button.flat = true
	skip_button.focus_mode = Control.FOCUS_NONE
	skip_button.add_theme_color_override("font_color", Color("#94A3B8"))
	skip_button.add_theme_font_size_override("font_size", 12)
	skip_button.pressed.connect(finish)
	row.add_child(skip_button)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	next_button = Button.new()
	next_button.name = "NextButton"
	next_button.custom_minimum_size = Vector2(0, 38)
	next_button.focus_mode = Control.FOCUS_NONE
	MenuView.cta(next_button)
	next_button.pressed.connect(next_pressed)
	row.add_child(next_button)
