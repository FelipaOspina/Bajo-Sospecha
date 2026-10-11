class_name SkinCatalog
extends RefCounted
## Catálogo de skins de animales (res://data/skins/skins.json, copia de
## shared/config/skins/skins.json) y carga dinámica de sus PNG desde
## res://assets/sprites/skins/<id>/{frente,lado,espalda,caminando}.png.
##
## La skin la asigna el servidor por jugador (PublicPlayerState.skinId); es pública
## y no depende del rol. Si el servidor no manda ninguna, fallback_for() elige una
## estable a partir del id del jugador.

const DATA_PATH := "res://data/skins/skins.json"
const SKINS_ROOT := "res://assets/sprites/skins/"
const VIEWS := ["frente", "lado", "espalda", "caminando"]
const FPS := 8.0
const DEFAULT_SKIN := {"id": "zorro", "name": "Zorro", "ear_type": "tall_pointed", "fur": "#D9622B",
	"fur_light": "#F8E8DA", "outfit": "#262838", "accent": "#9A9AB3", "scale_body": [0.9, 0.95]}

static var _data: Dictionary

static func data() -> Dictionary:
	if _data.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH)) if FileAccess.file_exists(DATA_PATH) else null
		_data = parsed if parsed is Dictionary else {"skins": [DEFAULT_SKIN]}
	return _data

static func ids() -> Array:
	return data().get("skins", []).map(func(s): return s["id"])

static func has(id: String) -> bool:
	return ids().has(id)

## Datos de la skin; si no existe, la primera del catálogo (o el zorro de reserva).
static func skin(id: String) -> Dictionary:
	var skins: Array = data().get("skins", [])
	for s in skins:
		if s["id"] == id:
			return s
	return skins[0] if not skins.is_empty() else DEFAULT_SKIN

static func fallback_for(player_id: String) -> String:
	var all := ids()
	return all[hash(player_id) % all.size()] if not all.is_empty() else DEFAULT_SKIN["id"]

## Textura de una vista, o null si no existe. Usa el PNG importado por Godot y, si
## aún no se importó (o la ruta es user://), lo lee directamente del disco.
static func view_texture(skin_id: String, view: String, root := SKINS_ROOT) -> Texture2D:
	var path := root.path_join(skin_id).path_join(view + ".png")
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	if FileAccess.file_exists(path):
		var img := Image.load_from_file(path)
		if img and not img.is_empty():
			return ImageTexture.create_from_image(img)
	return null

## SpriteFrames con una animación por vista encontrada, o null si falta frente.png.
## Una tira horizontal de cuadros (ancho = alto × n) se trocea en n fotogramas.
static func build_frames(skin_id: String, root := SKINS_ROOT) -> SpriteFrames:
	if view_texture(skin_id, "frente", root) == null:
		return null
	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	for view in VIEWS:
		var tex := view_texture(skin_id, view, root)
		if tex == null:
			continue
		frames.add_animation(view)
		frames.set_animation_speed(view, FPS)
		frames.set_animation_loop(view, true)
		var h := tex.get_height()
		var n := tex.get_width() / h if h > 0 and tex.get_width() >= h * 2 and tex.get_width() % h == 0 else 1
		if n == 1:
			frames.add_frame(view, tex)
			continue
		for i in n:
			var atlas := AtlasTexture.new()
			atlas.atlas = tex
			atlas.region = Rect2(i * h, 0, h, h)
			frames.add_frame(view, atlas)
	return frames
