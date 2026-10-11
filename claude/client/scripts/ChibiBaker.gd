class_name ChibiBaker
extends RefCounted
## "Hornea" un chibi procedural en una hoja de sprites para dibujarlo como una sola
## textura. El chibi en vivo es un rectángulo con un shader SDF bastante pesado por píxel
## (silueta, volumen, luz y cara se calculan en cada píxel); horneado es leer una textura.
## Pensado para móviles y web: con 8-10 jugadores en pantalla ahorra casi todo el coste
## de GPU de los avatares.
##
## Cómo: monta en un SubViewport transparente las 25 poses de la skin (frente quieto,
## 8 pasos de frente, 8 de lado y 8 de espaldas), lo dibuja una vez y guarda la imagen
## con mipmaps (al alejarse no se pixela ni parpadea). Lo hace ProceduralChibiAvatar
## solo cuando tiene bake = true y enabled() lo permite; mientras se hornea (un frame)
## se sigue viendo el chibi en vivo.
##
## Se pierde el parpadeo, la respiración y el muelle de las orejas; el paso, el rebote,
## los brazos y la cola siguen ahí. Cada combinación skin + color de acento se hornea
## una vez (tu corbata con el color de tu rol es otra hoja, solo en tu cliente), y
## también cada combinación de cosméticos puestos.

## "auto": horneado en móviles y web; "on": siempre; "off": nunca (chibi en vivo).
## La variable de entorno CHIBI_BAKE=1/0 lo fuerza (para probar en el escritorio).
static var mode := "auto"

const WALK_FRAMES := 8
## Celda en unidades del chibi (escala 1) y dónde caen los pies dentro de ella.
const CELL := Vector2(104, 136)
const FEET := Vector2(52, 128)
## Píxeles por unidad. El chibi del mapa va a 0.75 y las vistas previas horneadas hasta
## 1.5; en un móvil la ventana se estira ~1.5-2x, así que 1.75 queda nítido (cada hoja
## mide 1456x952 px, unos 7.4 MB con mipmaps).
const RESOLUTION := 1.75
const ROWS := {"caminando": 0, "lado": 1, "espalda": 2, "frente": 3}
const MAX_CACHED := 12
const SHEET_SHADER := "res://shaders/baked_sheet.gdshader"

static var _cache := {}      # clave -> ImageTexture
static var _order: Array[String] = []
static var _pending := {}    # clave -> true mientras se hornea
static var _premult: ShaderMaterial

static func enabled() -> bool:
	if DisplayServer.get_name() == "headless":
		return false   # sin GPU no hay nada que hornear (pruebas, servidor)
	var env := OS.get_environment("CHIBI_BAKE")
	if env != "":
		return env == "1"
	match mode:
		"on":
			return true
		"off":
			return false
	return OS.has_feature("mobile") or OS.has_feature("web")

static func key(skin_id: String, accent: Color, look := {}) -> String:
	return "%s|%s|%s" % [skin_id, accent.to_html(false), CosmeticCatalog.look_key(look)]

static func cached(skin_id: String, accent: Color, look := {}) -> Texture2D:
	return _cache.get(key(skin_id, accent, look))

## Rectángulo de la hoja (en píxeles) para una vista y un paso (frame < 0 = quieto).
static func region(view: String, frame: int) -> Rect2:
	var row: int = ROWS["frente"] if view == "frente" and frame < 0 else ROWS.get(view if view != "frente" else "caminando", 0)
	var col := 0 if frame < 0 else frame % WALK_FRAMES
	var px := CELL * RESOLUTION
	return Rect2(Vector2(col, row) * px, px)

## Dónde dibujar la celda en las coordenadas del chibi (pies en el origen).
static func local_rect() -> Rect2:
	return Rect2(-FEET, CELL)

## El SubViewport transparente guarda el color ya multiplicado por el alfa: el chibi
## horneado se dibuja con este material (res://shaders/baked_sheet.gdshader) para que los
## bordes no salgan oscuros. Probado en Forward+ con HDR 2D y en Compatibility: la hoja
## se ve igual que el chibi en vivo.
static func premultiplied() -> ShaderMaterial:
	if _premult == null:
		_premult = ShaderMaterial.new()
		_premult.shader = load(SHEET_SHADER)
	return _premult

## Pide la hoja y llama a done(clave, textura) cuando esté (si quien la pidió sigue vivo).
static func request(host: Node, skin_id: String, accent: Color, done: Callable, look := {}) -> void:
	var tex := await sheet(host, skin_id, accent, look)
	if done.is_valid():
		done.call(key(skin_id, accent, look), tex)

## Devuelve la hoja de la skin con ese acento; la hornea si hace falta (espera un frame).
static func sheet(host: Node, skin_id: String, accent: Color, look := {}) -> Texture2D:
	var k := key(skin_id, accent, look)
	if not host.is_inside_tree():
		return _cache.get(k)
	var tree := host.get_tree()
	while _pending.has(k):
		await tree.process_frame
	if _cache.has(k):
		return _cache[k]
	_pending[k] = true
	await tree.process_frame   # fuera de _ready: la raíz puede estar montando sus hijos
	var vp := SubViewport.new()
	vp.size = Vector2i((Vector2(WALK_FRAMES, ROWS.size()) * CELL * RESOLUTION).ceil())
	vp.transparent_bg = true
	vp.disable_3d = true
	# Mundo propio: si compartiera el de la escena, el WorldEnvironment de la oficina (brillo,
	# contraste, saturación y glow) se aplicaría al hornear y otra vez al dibujar la hoja.
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	tree.root.add_child(vp)
	for view in ROWS:
		var frames := 1 if view == "frente" else WALK_FRAMES
		for f in frames:
			var c := ProceduralChibiAvatar.new()
			c.skin_id = skin_id
			c.look = look
			var r := region(view, -1 if view == "frente" else f)
			c.position = r.position + FEET * RESOLUTION
			c.scale = Vector2.ONE * RESOLUTION
			vp.add_child(c)
			c.set_accent(accent)
			c.set_facing("frente" if view == "caminando" else view)
			c.pose(TAU * f / WALK_FRAMES, 0.0 if view == "frente" else 1.0)
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	vp.queue_free()
	_pending.erase(k)
	if img == null or img.is_empty():
		return null
	img.generate_mipmaps()   # alfa premultiplicado: los mipmaps promedian bien los bordes
	var tex := ImageTexture.create_from_image(img)
	_cache[k] = tex
	_order.append(k)
	while _order.size() > MAX_CACHED:
		_cache.erase(_order.pop_front())
	return tex
