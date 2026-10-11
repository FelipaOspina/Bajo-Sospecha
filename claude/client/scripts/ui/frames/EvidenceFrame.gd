class_name EvidenceFrame
extends PanelContainer
## Marco visual de una pista dentro del EvidenceInspectionModal (celular, terminal, papel...).
## Cada marco decide su "carcasa" y cómo formatear el texto; el contenido común
## (foto, texto, audio) lo pinta esta base. Para añadir un marco: heredar,
## sobrescribir _build_chrome()/_format()/_unknown_text() y registrarlo en EvidenceFrames.

var evidence: EvidenceData

var photo: TextureRect
var body: RichTextLabel
var audio_button: Button
var audio: AudioStreamPlayer
var _chrome_style: StyleBox

func _init() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var content := _build_chrome()
	_chrome_style = get_theme_stylebox("panel")
	photo = TextureRect.new()
	photo.custom_minimum_size = Vector2(0, 200)
	photo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	photo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	content.add_child(photo)
	body = RichTextLabel.new()
	body.bbcode_enabled = true
	body.fit_content = true
	body.scroll_active = false
	body.custom_minimum_size = Vector2(0, 90)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_body(body)
	content.add_child(body)
	audio = AudioStreamPlayer.new()
	add_child(audio)
	audio_button = Button.new()
	audio_button.text = "▶ Reproducir audio"
	audio_button.pressed.connect(_toggle_audio)
	content.add_child(audio_button)

func frame_id() -> String:
	return "item"

## Nombre del nodo dentro del ContentSlot del modal (SmartphoneView, TerminalView...).
func view_name() -> String:
	return "ItemView"

## Textura opcional del bisel (DeviceBezelTexture, un NinePatchRect detrás de la vista).
## Si existe, el marco deja de dibujar su propia carcasa; si no, se dibuja con estilos.
func bezel_path() -> String:
	return ""

## Margen 9-slice de la textura (esquinas que no se estiran), en píxeles.
func bezel_patch() -> int:
	return 32

## Separación entre el borde del bisel y el contenido.
func bezel_padding() -> Vector4i:   # izquierda, arriba, derecha, abajo
	return Vector4i(28, 28, 28, 28)

## Margen lateral en el modal: el celular se muestra en vertical, más estrecho.
func slot_side_margin() -> int:
	return 0

## true = el centro y los bordes se repiten en mosaico (texturas con grano o líneas).
func bezel_tiles() -> bool:
	return false

func set_texture_bezel(on: bool) -> void:
	if on:
		var empty := StyleBoxEmpty.new()
		var p := bezel_padding()
		empty.content_margin_left = p.x
		empty.content_margin_top = p.y
		empty.content_margin_right = p.z
		empty.content_margin_bottom = p.w
		add_theme_stylebox_override("panel", empty)
	else:
		add_theme_stylebox_override("panel", _chrome_style)
	_on_texture_bezel(on)

## Para que cada vista quite fondos propios que taparían la textura.
func _on_texture_bezel(_on: bool) -> void:
	pass

## Pinta la pista. Con vista parcial se ve la carcasa pero no el contenido.
func show_evidence(e: EvidenceData) -> void:
	evidence = e
	audio.stop()
	if e == null:
		body.text = _unknown_text()
		photo.hide()
		audio_button.hide()
		return
	body.text = _format(e) if e.is_known else _unknown_text()
	var image_path := str(e.content.get("image", ""))
	photo.visible = e.is_known and ResourceLoader.exists(image_path)
	if photo.visible:
		photo.texture = load(image_path)
	var audio_path := str(e.content.get("audio", ""))
	audio_button.visible = e.is_known and ResourceLoader.exists(audio_path)
	if audio_button.visible:
		audio.stream = load(audio_path)

func stop() -> void:
	audio.stop()

## Texto plano visible (para pruebas y accesibilidad).
func visible_text() -> String:
	return body.get_parsed_text()

# ───── Puntos de extensión ─────

## Construye la carcasa y devuelve el contenedor donde va el contenido.
func _build_chrome() -> Container:
	add_theme_stylebox_override("panel", UiPalette.glass_panel(8, 14))
	var v := _vbox(self, 8)
	return v

func _style_body(b: RichTextLabel) -> void:
	b.add_theme_font_override("normal_font", UiPalette.body_font())
	b.add_theme_color_override("default_color", UiPalette.TEXT)

func _format(e: EvidenceData) -> String:
	var text := str(e.content.get("text", ""))
	return _esc(e.description) + ("\n\n" + _esc(text) if text != "" else "")

func _unknown_text() -> String:
	return "Hay algo, pero no consigues saber qué es."

# ───── Utilidades para los marcos ─────

static func _box(bg: Color, border: Color, border_w := 0, radius := 4, pad := 12) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(border_w)
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(pad)
	return s

static func _vbox(parent: Node, sep: int) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(v)
	return v

static func _mono() -> Font:
	return UiPalette.mono_font()

static func _esc(s: String) -> String:
	return s.replace("[", "[lb]")

func _toggle_audio() -> void:
	if audio.playing:
		audio.stop()
	else:
		audio.play()
