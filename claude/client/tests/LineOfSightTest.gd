extends Node
## Prueba sin servidor: godot --headless res://tests/LineOfSightTest.tscn
## Línea de vista (LineOfSight): desde una sala cerrada no se ve la sala vecina tras el
## muro, pero sí el pasillo por la puerta; por el pasillo se ve hasta el fondo. Los
## puntos salen de OfficeLayout.rooms(), así que sirve aunque cambie el plano.

var _failures := 0
var _occ: Array
var _bounds: Rect2

func _ready() -> void:
	_occ = LineOfSight.occluders_from(OfficeLayout.walls())
	_bounds = LineOfSight.bounds_of(_occ)
	var rooms := OfficeLayout.rooms()
	var corridors := rooms.filter(func(r: Dictionary) -> bool: return _is_corridor(r))
	var closed := rooms.filter(func(r: Dictionary) -> bool: return not _is_corridor(r))
	_check(not corridors.is_empty(), "el plano tiene pasillo")

	# 1. Sala cerrada → sala vecina tras un muro: no se ve.
	var pair := _blocked_neighbours(closed)
	_check(not pair.is_empty(), "hay dos salas vecinas separadas por muro")
	if not pair.is_empty():
		_check(not _sees(pair[0], pair[1]), "desde una sala no se ve la vecina tras el muro")

	# 2. Sala → pasillo por la puerta: se ve.
	var door := _door_view(closed, corridors)
	_check(not door.is_empty(), "hay una sala con puerta al pasillo")
	if not door.is_empty():
		_check(_sees(door[0], door[1]), "desde la sala se ve el pasillo por la puerta")
		_check(not _sees(door[0], door[2]), "pero no el resto del pasillo, tapado por el muro")

	# 3. Por el pasillo se ve hasta el fondo.
	for c in corridors:
		var r: Rect2 = c["rect"]
		var horizontal := r.size.x >= r.size.y
		var a := Vector2(r.position.x + 40, r.get_center().y) if horizontal else Vector2(r.get_center().x, r.position.y + 40)
		var b := Vector2(r.end.x - 40, r.get_center().y) if horizontal else Vector2(r.get_center().x, r.end.y - 40)
		if LineOfSight.segment_clear(a, b, _occ):
			_check(_sees(a, b), "por %s se ve de punta a punta" % c["name"])

	# 4. El polígono coincide con la prueba directa contra los muros.
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var room_rect := OfficeLayout.BOUNDS
	var bad := 0
	var checked := 0
	for i in 12:
		var from := _free_point(rng, room_rect)
		var poly := LineOfSight.visible_polygon(from, _occ, _bounds)
		for j in 40:
			var to := _free_point(rng, room_rect)
			checked += 1
			if Geometry2D.is_point_in_polygon(to, poly) != LineOfSight.segment_clear(from, to, _occ):
				bad += 1
	_check(bad == 0, "polígono = prueba directa (%d/%d puntos)" % [checked - bad, checked])

	# 5. Rendimiento: el recálculo al moverse es barato.
	var t0 := Time.get_ticks_usec()
	var los := LineOfSight.new()
	for i in 20:
		los.set_viewer(door[0] + Vector2(i * 3.0, 0) if not door.is_empty() else Vector2(i * 3.0, 0))
	var ms := (Time.get_ticks_usec() - t0) / 20000.0
	print("  recálculo medio: %.2f ms" % ms)
	los.free()

	await _integration(door)
	print("LineOfSightTest: ", "OK" if _failures == 0 else "%d fallos" % _failures)
	get_tree().quit(1 if _failures > 0 else 0)

## En la partida, desde la sala junto a la puerta: el jugador del pasillo tapado por el
## muro se oculta (2D, 3D, luz y minimapa) y el que está frente a la puerta se ve.
func _integration(door: Array) -> void:
	if door.is_empty():
		return
	var main: Node = load("res://scenes/main/Main.tscn").instantiate()
	main.scenario_id = "caso_fraude_tech_startup"
	add_child(main)
	await get_tree().process_frame
	var view: World3DView = main.get_node("World3D")
	view.always_on = true
	var map: Node2D = main.get_node("Map")
	map.visible = true
	var players: Node = main.get_node("Map/Players")
	var me := _avatar(players, "yo", true, door[0])
	var hidden := _avatar(players, "vecino", false, door[2])
	var seen := _avatar(players, "pasillo", false, door[1])
	for i in 20:
		await get_tree().process_frame
	_check(view.line_of_sight.active and view.line_of_sight.is_inside_tree(), "la línea de vista está activa en el mapa")
	_check(hidden.sight == 0.0, "el que está tapado por el muro no se ve")
	_check(not view._avatars[hidden.get_instance_id()]["node"].visible, "su personaje 3D se oculta")
	_check(not view._avatars[hidden.get_instance_id()]["light"].visible, "y su luz")
	_check(not hidden.overhead_layer.visible, "y su nombre")
	_check(seen.sight == 1.0 and view._avatars[seen.get_instance_id()]["node"].visible, "el que está a la vista se ve")
	_check(me.sight == 1.0, "el jugador local siempre se ve")
	var hud := main.get_node("UI/OfficeHUD")
	var ids: Array = hud.minimap.markers()["players"].map(func(m: Dictionary) -> String: return m["id"])
	_check(not ids.has("vecino") and ids.has("pasillo"), "el minimapa solo enseña a quien ves")
	view.always_on = false
	map.visible = false
	await get_tree().process_frame
	_check(not view.line_of_sight.active and hidden.sight == 1.0, "fuera de la exploración se apaga")

func _avatar(players: Node, id: String, local: bool, at: Vector2) -> PlayerAvatar:
	var p: PlayerAvatar = load("res://scenes/player/PlayerAvatar.tscn").instantiate()
	p.player_id = id
	p.is_local = local
	players.add_child(p)
	p.teleport(at)
	return p

func _sees(from: Vector2, to: Vector2) -> bool:
	return Geometry2D.is_point_in_polygon(to, LineOfSight.visible_polygon(from, _occ, _bounds))

func _is_corridor(room: Dictionary) -> bool:
	var r: Rect2 = room["rect"]
	return str(room["name"]).to_upper().contains("PASILLO") or maxf(r.size.x / r.size.y, r.size.y / r.size.x) > 5.0

## Centros de dos salas que comparten lado y entre los que hay muro.
func _blocked_neighbours(rooms: Array) -> Array:
	for a in rooms:
		for b in rooms:
			if a == b or not _adjacent(a["rect"], b["rect"]):
				continue
			var pa: Vector2 = a["rect"].get_center()
			var pb: Vector2 = b["rect"].get_center()
			if not LineOfSight.segment_clear(pa, pb, _occ) and not _in_wall(pa) and not _in_wall(pb):
				return [pa, pb]
	return []

func _adjacent(a: Rect2, b: Rect2) -> bool:
	var share_x := is_equal_approx(a.end.x, b.position.x) or is_equal_approx(b.end.x, a.position.x)
	var share_y := is_equal_approx(a.end.y, b.position.y) or is_equal_approx(b.end.y, a.position.y)
	var overlap_y := minf(a.end.y, b.end.y) - maxf(a.position.y, b.position.y)
	var overlap_x := minf(a.end.x, b.end.x) - maxf(a.position.x, b.position.x)
	return (share_x and overlap_y > 40.0) or (share_y and overlap_x > 40.0)

## [dentro de la sala junto a la puerta, punto del pasillo al otro lado de la puerta,
##  punto del pasillo tapado por el muro].
func _door_view(rooms: Array, corridors: Array) -> Array:
	for c in corridors:
		var cr: Rect2 = c["rect"]
		for room in rooms:
			var r: Rect2 = room["rect"]
			if not _adjacent(r, cr):
				continue
			var horizontal_edge := is_equal_approx(r.end.y, cr.position.y) or is_equal_approx(cr.end.y, r.position.y)
			var edge := 0.0
			var from := 0.0
			var to := 0.0
			if horizontal_edge:
				edge = r.end.y if is_equal_approx(r.end.y, cr.position.y) else r.position.y
				from = maxf(r.position.x, cr.position.x) + OfficeLayout.WALL
				to = minf(r.end.x, cr.end.x) - OfficeLayout.WALL
			else:
				edge = r.end.x if is_equal_approx(r.end.x, cr.position.x) else r.position.x
				from = maxf(r.position.y, cr.position.y) + OfficeLayout.WALL
				to = minf(r.end.y, cr.end.y) - OfficeLayout.WALL
			# Primer hueco de puerta de al menos 40 px en el lado compartido.
			var start := INF
			var t := from
			while t <= to:
				var p := Vector2(t, edge) if horizontal_edge else Vector2(edge, t)
				if not _in_wall(p):
					start = minf(start, t)
				elif start != INF:
					if t - start >= 40.0:
						break
					start = INF
				t += 4.0
			if start == INF or t - start < 40.0:
				continue
			var mid := (start + t) / 2.0
			var inward := (r.get_center() - cr.get_center()).sign()
			var across := (cr.get_center() - r.get_center()).sign()
			var depth := OfficeLayout.WALL * 3.0
			var inside := Vector2(mid, edge + inward.y * depth) if horizontal_edge else Vector2(edge + inward.x * depth, mid)
			var span := (cr.size.y if horizontal_edge else cr.size.x) - OfficeLayout.WALL * 2.0
			var through := Vector2(mid, edge + across.y * span) if horizontal_edge else Vector2(edge + across.x * span, mid)
			# Pasillo adentro, lejos de la puerta y pegado al muro de la sala: tapado.
			var along := cr.end.x - 30.0 if mid < cr.get_center().x else cr.position.x + 30.0
			var along_y := cr.end.y - 30.0 if mid < cr.get_center().y else cr.position.y + 30.0
			var hidden := Vector2(along, edge + across.y * (OfficeLayout.WALL + 6.0)) if horizontal_edge else Vector2(edge + across.x * (OfficeLayout.WALL + 6.0), along_y)
			if LineOfSight.segment_clear(inside, through, _occ) and not LineOfSight.segment_clear(inside, hidden, _occ) and not _in_wall(hidden):
				return [inside, through, hidden]
	return []

func _in_wall(p: Vector2) -> bool:
	for o in _occ:
		if (o["rect"] as Rect2).grow(8.0).has_point(p):
			return true
	return false

## Punto al azar lejos de los muros (en el borde, polígono y prueba directa pueden
## discrepar por redondeo).
func _free_point(rng: RandomNumberGenerator, r: Rect2) -> Vector2:
	while true:
		var p := Vector2(rng.randf_range(r.position.x, r.end.x), rng.randf_range(r.position.y, r.end.y))
		if not _in_wall(p):
			return p
	return Vector2.ZERO

func _check(cond: bool, label: String) -> void:
	if cond:
		print("  ok   ", label)
	else:
		_failures += 1
		print("  FAIL ", label)
