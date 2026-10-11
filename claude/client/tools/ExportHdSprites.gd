extends Node
## Exporta los 12 animales en alta resolución: un PNG de color de 512x512 (de frente,
## quietos, con su ropa de serie y la oclusión de contacto bajo las zapatillas) y su mapa
## de normales de 512x512 (convención OpenGL/Godot: verde hacia arriba). Salen del mismo
## shader SDF del juego (res://shaders/chibi_sdf.gdshader con output_mode = 1 para las
## normales), así que el color y las normales encajan píxel a píxel.
##
## Para qué: tienda de apps, material de prensa, registro de la obra y como base para un
## arte final pintado o en 3D. En el juego el chibi se sigue dibujando en vivo (o
## horneado en móvil) porque así lleva la pose, los cosméticos y el color de tu rol.
##
## Uso (necesita GPU o un servidor X virtual; no funciona con --headless):
##   godot --path client res://tools/ExportHdSprites.tscn
## Variables de entorno opcionales: HD_OUT (carpeta de salida, por defecto
## res://assets/sprites/hd/) y HD_SIZE (lado en píxeles, por defecto 512).

const DEFAULT_OUT := "res://assets/sprites/hd/"

func _ready() -> void:
	var out := OS.get_environment("HD_OUT")
	if out == "":
		out = DEFAULT_OUT
	if not out.ends_with("/"):
		out += "/"
	var side := int(OS.get_environment("HD_SIZE")) if OS.get_environment("HD_SIZE") != "" else 512
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	var made := 0
	for id in SkinCatalog.ids():
		var color := await _render(id, side, 0)
		var normal := await _render(id, side, 1)
		if color == null or normal == null:
			printerr("No se pudo exportar ", id)
			continue
		color.save_png(out + id + ".png")
		normal.save_png(out + id + "_normal.png")
		made += 1
		print("exportado ", id, " (", side, "x", side, ")")
	print("Sprites HD: ", made, " de ", SkinCatalog.ids().size(), " en ", out)
	get_tree().quit(0 if made == SkinCatalog.ids().size() else 1)

## Dibuja un animal en un SubViewport transparente y devuelve la imagen sin premultiplicar
## (mode 0 = color, 1 = mapa de normales).
func _render(skin_id: String, side: int, mode: int) -> Image:
	var vp := SubViewport.new()
	vp.size = Vector2i(side, side)
	vp.transparent_bg = true
	vp.disable_3d = true
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(vp)
	var c := ProceduralChibiAvatar.new()
	c.skin_id = skin_id
	vp.add_child(c)
	c.set_facing("frente")
	c.pose(0.0, 0.0)
	c.shader_material.set_shader_parameter("output_mode", mode)
	# Cabe entero con un margen: de la punta (orejas, gorra) a los pies.
	var tall := -c.top_y() + 8.0
	var k := side * 0.9 / maxf(tall, ProceduralChibiAvatar.HALF_WIDTH * 1.6)
	c.scale = Vector2(k, k)
	c.position = Vector2(side / 2.0, side * 0.95 - 2.0 * k)
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	vp.queue_free()
	if img == null or img.is_empty():
		return null
	img.convert(Image.FORMAT_RGBA8)
	_unpremultiply(img, mode == 1)
	return img

## El SubViewport guarda el color multiplicado por el alfa; el PNG lo quiere sin multiplicar.
## En el mapa de normales, el fondo transparente lleva la normal "de cara" (128, 128, 255).
static func _unpremultiply(img: Image, normal_map: bool) -> void:
	for y in img.get_height():
		for x in img.get_width():
			var p := img.get_pixel(x, y)
			if p.a <= 0.0:
				img.set_pixel(x, y, Color(0.5, 0.5, 1.0, 0.0) if normal_map else Color(0, 0, 0, 0))
			elif p.a < 1.0:
				img.set_pixel(x, y, Color(clampf(p.r / p.a, 0.0, 1.0), clampf(p.g / p.a, 0.0, 1.0), clampf(p.b / p.a, 0.0, 1.0), p.a))
