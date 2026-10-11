class_name SettingsView
extends MenuView
## Configuración: tu nombre visible, el servidor y el id de tu perfil (mock, sin
## contraseña: el perfil se recupera con el id guardado en este equipo).

var name_input: LineEdit
var save_button: Button
var server_label: Label
var profile_label: Label
var quality_option: OptionButton
var pet_volume: HSlider

const QUALITY := [["auto", "Automática (rendimiento en móvil)"], ["off", "Máxima (animación completa)"], ["on", "Rendimiento (más FPS)"]]

func build() -> void:
	var layout := vbox(14)
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(layout)
	layout.add_child(heading("CONFIGURACIÓN", 28))
	var c := card()
	c.custom_minimum_size.x = 520
	c.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	layout.add_child(c)
	var box := vbox(10)
	c.add_child(box)
	box.add_child(heading("Nombre en la partida", 16))
	var row := hbox(8)
	box.add_child(row)
	name_input = LineEdit.new()
	name_input.max_length = Account.MAX_NAME
	name_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_input.custom_minimum_size.y = 36
	row.add_child(name_input)
	save_button = Button.new()
	save_button.text = "Guardar"
	cta(save_button)
	row.add_child(save_button)
	save_button.pressed.connect(save_name)
	name_input.text_submitted.connect(func(_t: String) -> void: save_name())
	box.add_child(caption("Lo ven los demás en la sala y sobre tu animal. Nunca se muestra tu rol.", 12))
	box.add_child(HSeparator.new())
	box.add_child(heading("Calidad de los avatares", 16))
	quality_option = OptionButton.new()
	quality_option.custom_minimum_size.y = 34
	for q in QUALITY:
		quality_option.add_item(q[1])
	quality_option.item_selected.connect(func(i: int) -> void:
		Account.set_avatar_quality(QUALITY[i][0])
		toast_requested.emit("Calidad de avatares: %s. Se aplica a los personajes nuevos." % QUALITY[i][1].to_lower()))
	box.add_child(quality_option)
	box.add_child(caption("En rendimiento cada animal se dibuja como una sola imagen: mismo aspecto, sin parpadeo ni orejas con muelle.", 12))
	box.add_child(HSeparator.new())
	box.add_child(heading("Sonidos de la mascota", 16))
	pet_volume = HSlider.new()
	pet_volume.name = "PetVolume"
	pet_volume.min_value = 0
	pet_volume.max_value = 100
	pet_volume.step = 5
	pet_volume.custom_minimum_size.y = 24
	pet_volume.value_changed.connect(func(v: float) -> void: Account.set_pet_volume(v / 100.0))
	box.add_child(pet_volume)
	box.add_child(caption("Ronroneos, ladridos y demás al tocar, acariciar o dar de comer a tu animal en la sala. A cero, en silencio.", 12))
	box.add_child(HSeparator.new())
	server_label = caption("", 13, Color.WHITE)
	box.add_child(server_label)
	profile_label = caption("", 12)
	box.add_child(profile_label)
	box.add_child(caption("Perfil de prueba guardado en el servidor (sin contraseña ni pagos reales).", 11))

func refresh() -> void:
	if not name_input.has_focus():
		name_input.text = Account.player_name
	for i in QUALITY.size():
		if QUALITY[i][0] == ChibiBaker.mode:
			quality_option.select(i)
	pet_volume.set_value_no_signal(PetSfx.volume * 100.0)
	server_label.text = "Servidor: %s · %s" % [Network.server_url, "conectado" if Account.online else "sin conexión"]
	profile_label.text = "Id de perfil: %s" % (Account.profile_id if Account.profile_id != "" else "se crea al conectar")

func save_name() -> void:
	var clean := name_input.text.strip_edges()
	if clean.is_empty():
		toast_requested.emit("Escribe un nombre.")
		return
	Account.set_player_name(clean)
	toast_requested.emit("Nombre guardado: %s." % Account.player_name)
