class_name LineOfSight
extends Node2D
## Línea de vista de la mascota local: solo se ve lo que tiene a la vista.
##
## Desde los pies del jugador local se calcula el polígono de visibilidad con todos
## los muros de OfficeLayout como opacos (todos los tipos tapan; los huecos de las
## puertas dejan pasar la vista) y sin límite de distancia: por un pasillo se ve hasta
## el fondo, y desde una sala solo la sala y el trozo de pasillo que asoma por la puerta.
##
## Cálculo: se parte de un rectángulo que envuelve el plano y se le recorta la sombra
## de cada muro (Geometry2D.clip_polygons, en C++), del más cercano al más lejano. La
## región visible desde un punto tiene forma de estrella respecto a él, así que siempre
## queda un único polígono sin agujeros. Se recalcula solo si el jugador se mueve más
## de MOVE_EPS px o cambia el plano.
##
## Dibujo: vive en el mapa 2D (encima de la vista 3D y debajo del HUD) y oscurece con
## azul marino todo lo que queda fuera. Como la vista 3D levanta muros y personajes
## sobre su punto del suelo, a lo visible se le suma la cara y el canto de los muros que
## lo cierran y el cuerpo de los personajes a la vista; el borde se difumina con unas
## capas desplazadas unos px. World3DView decide a quién se ve con can_see().

## Personaje 3D cargado por ruta (no por class_name): funciona aunque la caché de clases
## de .godot sea vieja, p. ej. al abrir el juego con el .bat sin pasar por el editor.
const Plush3D := preload("res://scripts/world3d/PlushAvatar3D.gd")
const MOVE_EPS := 2.0                   # px que hay que moverse para recalcular
const SIGHT_MARGIN := 6.0                # holgura (px) para ver a alguien al borde de la vista
const DIM := Color(0.02, 0.04, 0.10)     # azul marino de lo que no se ve
const DIM_ALPHA := 0.8                   # opacidad total fuera de la vista
const FEATHER_STEPS := 3                 # capas del borde suave
const FEATHER_PX := 6.0                  # separación entre capas
const BODY_HALF_WIDTH := 24.0            # medio ancho (px) del cuerpo 3D en pantalla
const WALLS_CHECK_S := 1.0               # cada cuánto se mira si cambió el plano
const INVERT_BORDER := 6000.0            # margen del oscurecido alrededor de lo visible

## true durante la exploración con jugador local: dibuja el oscurecido.
var active := false: set = set_active
## Polígono visible (suelo, px del mundo) desde `origin`.
var polygon := PackedVector2Array()
## Lo que no se oscurece: suelo visible + muros que lo cierran + cuerpos a la vista.
var lit := PackedVector2Array()
var origin := Vector2.INF

var _occluders: Array = []          # [{rect: Rect2, h: float}]
var _bounds := Rect2()
var _walls_hash := 0
var _walls_timer := 0.0
var _sight := PackedVector2Array()  # polygon con SIGHT_MARGIN de holgura
var _sight_box := Rect2()
var _lit_walls := PackedVector2Array()
var _bodies := PackedVector2Array()
var _layers: Array[Polygon2D] = []

func _init() -> void:
	name = "LineOfSight"
	z_index = 40          # sobre jugadores y pistas; debajo de las marcas de olfato (50)
	visible = false
	# Cada capa oscurece fuera de lo visible desplazado i·FEATHER_PX: juntas suman DIM_ALPHA
	# lejos del borde y menos cerca de él.
	var a := 1.0 - pow(1.0 - DIM_ALPHA, 1.0 / FEATHER_STEPS)
	for i in FEATHER_STEPS:
		var layer := Polygon2D.new()
		layer.name = "Dim%d" % i
		layer.color = Color(DIM, a)
		layer.invert_enabled = true
		layer.invert_border = INVERT_BORDER
		layer.antialiased = false
		add_child(layer)
		_layers.append(layer)
	refresh_walls()

func set_active(on: bool) -> void:
	active = on
	visible = on

func _process(delta: float) -> void:
	_walls_timer += delta
	if _walls_timer >= WALLS_CHECK_S:
		_walls_timer = 0.0
		if hash(OfficeLayout.walls()) != _walls_hash:
			refresh_walls()

## Relee los muros del plano y fuerza el recálculo.
func refresh_walls() -> void:
	var walls := OfficeLayout.walls()
	_walls_hash = hash(walls)
	_occluders = occluders_from(walls)
	_bounds = bounds_of(_occluders)
	origin = Vector2.INF

## Coloca el punto de vista (pies del jugador local). Recalcula si se movió > MOVE_EPS.
func set_viewer(p: Vector2) -> void:
	if origin != Vector2.INF and p.distance_to(origin) <= MOVE_EPS:
		return
	origin = p
	polygon = visible_polygon(p, _occluders, _bounds)
	_sight = _pick(Geometry2D.offset_polygon(polygon, SIGHT_MARGIN), p)
	_sight_box = _bbox(_sight)
	_lit_walls = _with_walls(polygon, _sight, _sight_box, _occluders, p)
	_bodies = PackedVector2Array()
	_rebuild_lit()

## ¿Se ve este punto del suelo desde el jugador local?
func can_see(p: Vector2) -> bool:
	if _sight.is_empty():
		return true
	return _sight_box.has_point(p) and Geometry2D.is_point_in_polygon(p, _sight)

## Pies de los personajes a la vista (el local incluido): su cuerpo 3D sobresale por
## encima de su punto del suelo y no debe quedar a oscuras. Recalcula si cambian.
func set_bodies(feet: PackedVector2Array) -> void:
	if feet.size() == _bodies.size():
		var same := true
		for i in feet.size():
			if feet[i].distance_to(_bodies[i]) > MOVE_EPS:
				same = false
				break
		if same:
			return
	_bodies = feet
	_rebuild_lit()

func _rebuild_lit() -> void:
	var shape := _lit_walls
	var body_h := World3DView.screen_height(Plush3D.HEIGHT) + 10.0
	for f in _bodies:
		var box := Rect2(f.x - BODY_HALF_WIDTH, f.y - body_h, BODY_HALF_WIDTH * 2.0, body_h + 8.0)
		shape = _pick(Geometry2D.merge_polygons(shape, _rect_poly(box)), origin, shape)
	lit = shape
	for i in _layers.size():
		var poly := shape
		if i > 0:
			poly = _pick(Geometry2D.offset_polygon(shape, FEATHER_PX * i, Geometry2D.JOIN_SQUARE), origin, shape)
		_layers[i].polygon = poly

# ── Geometría (estática: la usan las pruebas sin escena) ──

## Muros de OfficeLayout.walls() como rectángulos opacos (el mismo grosor que colisiona).
static func occluders_from(walls: Array) -> Array:
	var out := []
	for w in walls:
		var a: Vector2 = w["a"]
		var b: Vector2 = w["b"]
		out.append({"rect": Rect2(a, Vector2.ZERO).expand(b).grow(OfficeLayout.WALL / 2.0), "h": float(w.get("h", 1.0))})
	return out

## Rectángulo que envuelve todos los muros, con margen.
static func bounds_of(occluders: Array) -> Rect2:
	if occluders.is_empty():
		return OfficeLayout.BOUNDS.grow(100.0)
	var r: Rect2 = occluders[0]["rect"]
	for o in occluders:
		r = r.merge(o["rect"])
	return r.grow(100.0)

## Polígono visible desde `viewer`: el contorno menos la sombra de cada muro.
static func visible_polygon(viewer: Vector2, occluders: Array, bounds: Rect2) -> PackedVector2Array:
	var poly := _rect_poly(bounds)
	var far := bounds.size.length() + 100.0
	var order := occluders.duplicate()
	order.sort_custom(func(x: Dictionary, y: Dictionary) -> bool:
		return _rect_distance(x["rect"], viewer) < _rect_distance(y["rect"], viewer))
	var box := bounds
	for o in order:
		var r: Rect2 = o["rect"]
		if r.has_point(viewer) or not box.intersects(r):
			continue   # dentro del muro, o ya está entero en sombra: no tapa nada más
		poly = _pick(Geometry2D.clip_polygons(poly, _shadow(viewer, r, far)), viewer, poly)
		box = _bbox(poly)
	return poly

## ¿Se ve `to` desde `from`? Prueba directa contra los muros (para pruebas).
static func segment_clear(from: Vector2, to: Vector2, occluders: Array) -> bool:
	for o in occluders:
		var r: Rect2 = o["rect"]
		if r.has_point(from) or r.has_point(to):
			return false
		var c := _rect_poly(r)
		for i in 4:
			if Geometry2D.segment_intersects_segment(from, to, c[i], c[(i + 1) % 4]) != null:
				return false
	return true

## Suma a lo visible lo que la vista 3D levanta: cara y canto de los muros que lo cierran.
static func _with_walls(poly: PackedVector2Array, sight: PackedVector2Array, sight_box: Rect2, occluders: Array, viewer: Vector2) -> PackedVector2Array:
	var out := poly
	for o in occluders:
		var r: Rect2 = o["rect"]
		if not sight_box.intersects(r):
			continue
		var lift := World3DView.screen_height(float(o["h"]) + 0.15)   # + plantas y remates
		for piece in Geometry2D.intersect_polygons(sight, _rect_poly(r)):
			var pb := _bbox(piece)
			# Tramo del muro que asoma, con todo su grosor, levantado hasta su canto.
			var strip := Rect2(pb.position.x, r.position.y, pb.size.x, r.size.y) if r.size.x >= r.size.y \
					else Rect2(r.position.x, pb.position.y, r.size.x, pb.size.y)
			strip = Rect2(strip.position.x, strip.position.y - lift, strip.size.x, strip.size.y + lift).grow(1.0)
			out = _pick(Geometry2D.merge_polygons(out, _rect_poly(strip)), viewer, out)
	return out

## Sombra de un muro vista desde `viewer`: el muro y todo lo que queda detrás.
static func _shadow(viewer: Vector2, r: Rect2, far: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for c in _rect_poly(r):
		pts.append(c)
		pts.append(c + (c - viewer).normalized() * far)
	var hull := Geometry2D.convex_hull(pts)
	if hull.size() > 1 and hull[0] == hull[hull.size() - 1]:
		hull.remove_at(hull.size() - 1)
	return hull

## De lo que devuelve Clipper, el contorno que contiene al jugador (o el mayor). Los
## agujeros quedan dentro de su contorno, así que nunca ganan por tamaño.
static func _pick(parts: Array, viewer: Vector2, fallback := PackedVector2Array()) -> PackedVector2Array:
	if parts.size() == 1:
		return parts[0]
	var best := PackedVector2Array()
	var best_area := -1.0
	var best_has_viewer := false
	for p in parts:
		var has_viewer := Geometry2D.is_point_in_polygon(viewer, p)
		var area := _bbox(p).get_area()
		if (has_viewer and not best_has_viewer) or (has_viewer == best_has_viewer and area > best_area):
			best = p
			best_area = area
			best_has_viewer = has_viewer
	return best if not best.is_empty() else fallback

static func _rect_poly(r: Rect2) -> PackedVector2Array:
	return PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])

static func _bbox(poly: PackedVector2Array) -> Rect2:
	if poly.is_empty():
		return Rect2()
	var r := Rect2(poly[0], Vector2.ZERO)
	for p in poly:
		r = r.expand(p)
	return r

static func _rect_distance(r: Rect2, p: Vector2) -> float:
	var dx := maxf(maxf(r.position.x - p.x, 0.0), p.x - r.end.x)
	var dy := maxf(maxf(r.position.y - p.y, 0.0), p.y - r.end.y)
	return dx * dx + dy * dy
