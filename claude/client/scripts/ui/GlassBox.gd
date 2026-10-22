@tool
extends StyleBox
## Estilo de panel "cristal oscuro" de la sala de espera (y del marco del menú):
## relleno en degradado vertical, borde en degradado (más claro arriba, como luz que
## cae), sombra suave debajo, halo de color opcional y "labio" inferior opcional para
## los botones con relieve. Todo dibujado con el RenderingServer (sin texturas).
## Se usa con preload (no tiene class_name): const GlassBox := preload("res://scripts/ui/GlassBox.gd").

var bg_top := Color(0.10, 0.13, 0.22, 0.90)
var bg_bottom := Color(0.04, 0.06, 0.11, 0.92)
var border_top := Color(1, 1, 1, 0.22)
var border_bottom := Color(1, 1, 1, 0.05)
var border_width := 1.0
var radius := 14.0
var shadow_color := Color(0, 0, 0, 0.42)
var shadow_size := 14
var shadow_offset := Vector2(0, 5)
## Halo exterior (acento): transparente = sin halo.
var glow_color := Color(0, 0, 0, 0)
var glow_size := 0
## Labio inferior (botones en relieve): alto en px y color.
var lip := 0.0
var lip_color := Color(0, 0, 0, 0.5)
## Desplazamiento del cuerpo hacia abajo (botón pulsado: se hunde sobre su labio).
var press_shift := 0.0
## Brillo interior en la mitad de arriba (0 = nada).
var sheen := 0.0

var _shadow_box: StyleBoxFlat
var _glow_box: StyleBoxFlat

static func make(top: Color, bottom: Color, rad := 14.0, pad := 12.0) -> StyleBox:
	var s = (load("res://scripts/ui/GlassBox.gd") as GDScript).new()
	s.bg_top = top
	s.bg_bottom = bottom
	s.radius = rad
	s.content_margin_left = pad
	s.content_margin_right = pad
	s.content_margin_top = pad
	s.content_margin_bottom = pad
	return s

## Panel estándar de la sala.
static func panel(rad := 16.0, pad := 12.0) -> StyleBox:
	return make(Color(0.075, 0.10, 0.18, 0.88), Color(0.03, 0.045, 0.085, 0.92), rad, pad)

## Tarjeta interior (más clara y sin sombra).
static func inset(rad := 10.0, pad := 8.0, alpha := 1.0) -> StyleBox:
	var s = make(Color(1, 1, 1, 0.06 * alpha), Color(1, 1, 1, 0.025 * alpha), rad, pad)
	s.border_top = Color(1, 1, 1, 0.14 * alpha)
	s.border_bottom = Color(1, 1, 1, 0.04 * alpha)
	s.shadow_size = 0
	return s

## Botón de acento (relleno en degradado del color dado).
static func accent(c: Color, rad := 10.0, pad := 8.0, strength := 1.0) -> StyleBox:
	var s = make(Color(c, 0.30 * strength), Color(c, 0.12 * strength), rad, pad)
	s.border_top = Color(c.lightened(0.35), 0.95 * strength)
	s.border_bottom = Color(c, 0.35 * strength)
	s.shadow_size = 8
	s.shadow_color = Color(0, 0, 0, 0.3)
	s.shadow_offset = Vector2(0, 3)
	return s

func with_glow(c: Color, size_px := 10) -> StyleBox:
	glow_color = c
	glow_size = size_px
	return self

func _draw(ci: RID, rect: Rect2) -> void:
	if glow_size > 0 and glow_color.a > 0.0:
		if _glow_box == null:
			_glow_box = StyleBoxFlat.new()
		_glow_box.bg_color = Color(glow_color, 0.0)
		_glow_box.draw_center = false
		_glow_box.set_corner_radius_all(int(radius))
		_glow_box.shadow_color = glow_color
		_glow_box.shadow_size = glow_size
		_glow_box.shadow_offset = Vector2.ZERO
		_glow_box.draw(ci, rect)
	if shadow_size > 0 and shadow_color.a > 0.0:
		if _shadow_box == null:
			_shadow_box = StyleBoxFlat.new()
		_shadow_box.bg_color = Color(0, 0, 0, 0)
		_shadow_box.draw_center = false
		_shadow_box.set_corner_radius_all(int(radius))
		_shadow_box.shadow_color = shadow_color
		_shadow_box.shadow_size = shadow_size
		_shadow_box.shadow_offset = shadow_offset
		_shadow_box.draw(ci, rect)
	var body := rect
	if lip > 0.0 or press_shift > 0.0:
		var lip_pts := rounded(rect, radius)
		RenderingServer.canvas_item_add_polygon(ci, lip_pts, _fill(lip_pts, lip_color, lip_color))
		RenderingServer.canvas_item_add_polyline(ci, _closed(lip_pts), _flat(lip_pts.size() + 1, lip_color), 1.0, true)
		body = Rect2(rect.position + Vector2(0, press_shift), Vector2(rect.size.x, rect.size.y - lip - press_shift))
	var pts := rounded(body, radius)
	RenderingServer.canvas_item_add_polygon(ci, pts, _fill(pts, bg_top, bg_bottom))
	if sheen > 0.0:
		var top := Rect2(body.position + Vector2(2, 2), Vector2(body.size.x - 4, body.size.y * 0.5))
		var sp := rounded(top, maxf(radius - 2.0, 0.0))
		RenderingServer.canvas_item_add_polygon(ci, sp, _fill(sp, Color(1, 1, 1, sheen), Color(1, 1, 1, 0.0), top))
	if border_width > 0.0 and (border_top.a > 0.0 or border_bottom.a > 0.0):
		var inset_r := body.grow(-border_width / 2.0)
		var bp := rounded(inset_r, maxf(radius - border_width / 2.0, 0.0))
		var cols := _fill(bp, border_top, border_bottom)
		cols.append(cols[0])
		RenderingServer.canvas_item_add_polyline(ci, _closed(bp), cols, border_width, true)
	else:
		# Borde de antialias del relleno.
		RenderingServer.canvas_item_add_polyline(ci, _closed(pts), _fill(_closed(pts), bg_top, bg_bottom), 1.0, true)

static func rounded(r: Rect2, rad: float, seg := 6) -> PackedVector2Array:
	rad = clampf(rad, 0.0, minf(r.size.x, r.size.y) / 2.0)
	var pts := PackedVector2Array()
	var centers := [r.position + Vector2(rad, rad), Vector2(r.end.x - rad, r.position.y + rad), r.end - Vector2(rad, rad), Vector2(r.position.x + rad, r.end.y - rad)]
	for i in 4:
		var a0 := PI + i * PI / 2.0
		for j in seg + 1:
			var a := a0 + (PI / 2.0) * j / seg
			pts.append(centers[i] + Vector2(cos(a), sin(a)) * rad)
	return pts

static func _closed(pts: PackedVector2Array) -> PackedVector2Array:
	var out := pts.duplicate()
	out.append(pts[0])
	return out

static func _flat(n: int, c: Color) -> PackedColorArray:
	var out := PackedColorArray()
	out.resize(n)
	out.fill(c)
	return out

static func _fill(pts: PackedVector2Array, top: Color, bottom: Color, bounds := Rect2()) -> PackedColorArray:
	var y0 := INF
	var y1 := -INF
	if bounds.size.y > 0.0:
		y0 = bounds.position.y
		y1 = bounds.end.y
	else:
		for p in pts:
			y0 = minf(y0, p.y)
			y1 = maxf(y1, p.y)
	var out := PackedColorArray()
	for p in pts:
		out.append(top.lerp(bottom, clampf((p.y - y0) / maxf(y1 - y0, 1.0), 0.0, 1.0)))
	return out
