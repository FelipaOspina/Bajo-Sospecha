class_name Office3D
extends Node3D
## Oficina de NexusCore en 3D, construida con primitivas a partir de OfficeLayout
## (el mismo plano que usan las colisiones 2D). Noche de auditoría: fachada de
## cristal con la ciudad de fondo, luces cálidas en el despacho, el azul frío de los
## servidores, pantallas encendidas y una máquina expendedora que brilla en la
## cafetería. Muros bajos tipo maqueta para que la cámara vea dentro de cada sala.
## Ala este: despacho legal, RRHH, el cuarto eléctrico en penumbra ámbar con luces de
## emergencia que parpadean, el gimnasio y la terraza abierta (deck, guirnaldas de
## bombillas y barandilla de cristal con la ciudad debajo).
##
## Coordenadas: el mundo 2D (px) se proyecta al suelo 3D con World3DView.to_3d, de modo
## que la cámara ortográfica inclinada ve cada punto del suelo exactamente donde el
## juego 2D lo tiene (nombres, barras, clics y colisiones siguen funcionando igual).

const C_WALL := Color("#B7C0CE")
const C_WALL_CAP := Color("#E9EDF3")
const C_METAL := Color("#9AA5B4")
const C_DARK := Color("#1B2230")
const C_WOOD := Color("#8A5A3B")
const C_WOOD_LIGHT := Color("#C08A5B")
const C_FABRIC := Color("#334155")
const C_SCREEN := Color(0.35, 0.75, 1.4)
const C_LEAF := Color("#2F7D4A")

var mobile := false
var _mats := {}
var _rng := RandomNumberGenerator.new()
var _blink: Array = []      # luces de emergencia: {light, mat, phase}
var _time := 0.0

func _ready() -> void:
	mobile = OS.has_feature("mobile") or OS.has_feature("web")
	_rng.seed = 1414
	build()

func _process(delta: float) -> void:
	if _blink.is_empty():
		return
	_time += delta
	for b in _blink:
		# Destello lento, como una baliza de emergencia.
		var k := pow(0.5 + 0.5 * sin(_time * 2.6 + float(b["phase"])), 3.0)
		(b["light"] as OmniLight3D).light_energy = 0.25 + 1.6 * k
		(b["mat"] as StandardMaterial3D).emission_energy_multiplier = 0.6 + 3.0 * k

func build() -> void:
	for c in get_children():
		c.queue_free()
	_blink.clear()
	for room in OfficeLayout.rooms():
		_floor(room)
	for w in OfficeLayout.walls():
		_wall(w)
	for p in OfficeLayout.props():
		_prop(p)
	_signage()
	_room_lights()

static func p3(p: Vector2, h := 0.0) -> Vector3:
	return World3DView.to_3d(p, h)

## Caja con la huella de un rect 2D, de alto h (m), apoyada a la altura y0.
func _rbox(r: Rect2, y0: float, h: float, mat: Material, shrink := 0.0) -> MeshInstance3D:
	var rr := r.grow(-shrink)
	var a := p3(rr.position)
	var b := p3(rr.end)
	return _box3((a + b) / 2.0 + Vector3(0, y0 + h / 2.0, 0), Vector3(b.x - a.x, h, b.z - a.z), mat)

func _box3(center: Vector3, size: Vector3, mat: Material, parent: Node3D = self) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = size
	mi.mesh = m
	mi.material_override = mat
	mi.position = center
	parent.add_child(mi)
	return mi

func _cyl(center: Vector3, r_top: float, r_bottom: float, h: float, mat: Material, segs := 24) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := CylinderMesh.new()
	m.top_radius = r_top
	m.bottom_radius = r_bottom
	m.height = h
	m.radial_segments = segs
	mi.mesh = m
	mi.material_override = mat
	mi.position = center
	add_child(mi)
	return mi

func _ball(center: Vector3, r: float, mat: Material, scl := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	m.radial_segments = 20
	m.rings = 10
	mi.mesh = m
	mi.material_override = mat
	mi.position = center
	mi.scale = scl
	add_child(mi)
	return mi

## Unidades: un rect 2D → (centro 3D, ancho x, fondo z).
func _span(r: Rect2) -> Array:
	var a := p3(r.position)
	var b := p3(r.end)
	return [(a + b) / 2.0, b.x - a.x, b.z - a.z]

# ── suelos ──────────────────────────────────────────────────────────────────

func _floor(room: Dictionary) -> void:
	var r: Rect2 = room["rect"]
	var mi := _rbox(r, -0.05, 0.05, _floor_mat(str(room["floor"])))
	mi.name = "Floor_" + str(room["name"]).replace(" ", "_")

func _floor_mat(kind: String) -> StandardMaterial3D:
	var key := "floor_" + kind
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	match kind:
		"marble":
			m.albedo_texture = _tex_tiles(Color("#C9CCD2"), Color("#9EA3AB"), 2, 0.05, true)
			m.roughness = 0.12
			m.uv1_scale = Vector3.ONE * 0.5
		"raised":
			m.albedo_texture = _tex_tiles(Color("#5A6474"), Color("#2A313C"), 2, 0.04, false, true)
			m.roughness = 0.5
			m.metallic = 0.3
			m.uv1_scale = Vector3.ONE * 0.85
		"wood":
			m.albedo_texture = _tex_planks(Color("#9C6A43"))
			m.roughness = 0.35
			m.uv1_scale = Vector3.ONE * 0.6
		"wood_dark":
			m.albedo_texture = _tex_planks(Color("#5E3B27"))
			m.roughness = 0.35
			m.uv1_scale = Vector3.ONE * 0.6
		"carpet":
			m.albedo_texture = _tex_tiles(Color("#6B778C"), Color("#5C687D"), 2, 0.09)
			m.roughness = 0.95
			m.uv1_scale = Vector3.ONE * 0.8
		"concrete":
			m.albedo_texture = _tex_tiles(Color("#7C838E"), Color("#6B727C"), 1, 0.06)
			m.roughness = 0.25
			m.uv1_scale = Vector3.ONE * 0.35
		"rubber":
			m.albedo_texture = _tex_tiles(Color("#3B4452"), Color("#323A46"), 4, 0.05)
			m.roughness = 0.8
			m.uv1_scale = Vector3.ONE * 0.8
		"epoxy":
			m.albedo_texture = _tex_tiles(Color("#C9CFDA"), Color("#B9C0CC"), 1, 0.03)
			m.roughness = 0.08
			m.metallic_specular = 0.8
			m.uv1_scale = Vector3.ONE * 0.4
		"carpet_warm":
			m.albedo_texture = _tex_tiles(Color("#7A6A5C"), Color("#6C5D50"), 2, 0.09)
			m.roughness = 0.95
			m.uv1_scale = Vector3.ONE * 0.8
		"deck":
			# Tarima exterior de teca: tablas anchas con junta abierta.
			m.albedo_texture = _tex_planks(Color("#8F6844"), 22)
			m.roughness = 0.6
			m.uv1_scale = Vector3.ONE * 0.45
		"terrazzo":
			m.albedo_texture = _tex_terrazzo(Color("#D8CCB8"))
			m.roughness = 0.3
			m.uv1_scale = Vector3.ONE * 0.6
		_:
			m.albedo_texture = _tex_tiles(Color("#8C9590"), Color("#747D78"), 2, 0.05)
			m.roughness = 0.55
			m.uv1_scale = Vector3.ONE * 0.8
	_mats[key] = m
	return m

# ── muros ───────────────────────────────────────────────────────────────────

func _wall(w: Dictionary) -> void:
	var a: Vector2 = w["a"]
	var b: Vector2 = w["b"]
	var h: float = w["h"]
	if w.has("kinds"):
		for part in w["kinds"]:
			var pa := a
			var pb := b
			if is_equal_approx(a.y, b.y):
				pa = Vector2(part[0], a.y)
				pb = Vector2(part[1], a.y)
			else:
				pa = Vector2(a.x, part[0])
				pb = Vector2(a.x, part[1])
			_wall_piece(pa, pb, str(part[2]), h)
	else:
		_wall_piece(a, b, str(w["kind"]), h)

func _wall_piece(a: Vector2, b: Vector2, kind: String, h: float) -> void:
	var r := Rect2(a, Vector2.ZERO).expand(b).grow(OfficeLayout.WALL / 2.0)
	var horizontal := r.size.x > r.size.y
	match kind:
		"back":
			_facade(r)
		"side":
			_rbox(r, 0.0, h, _mat("side", Color("#2A3242"), 0.6))
			_rbox(r.grow(2), h, 0.04, _mat("cap", C_WALL_CAP, 0.4))
		"front":
			_rbox(r, 0.0, h, _mat("wall", C_WALL, 0.7))
			_rbox(r.grow(1), h, 0.03, _mat("cap", C_WALL_CAP, 0.4))
		"glass":
			_rbox(r, 0.0, 0.1, _mat("alu", C_METAL, 0.3, 0.8))
			_rbox(r.grow(-4), 0.1, h - 0.1, _glass())
			_rbox(r.grow(-2), h - 0.03, 0.05, _mat("alu", C_METAL, 0.3, 0.8))
			var length := r.size.x if horizontal else r.size.y
			var n := int(length / 120.0)
			for i in range(1, n + 1):
				var t := float(i) / float(n + 1)
				var c := r.position + Vector2(r.size.x * t, r.size.y / 2.0) if horizontal else r.position + Vector2(r.size.x / 2.0, r.size.y * t)
				var mr := Rect2(c - Vector2(3, 8), Vector2(6, 16)) if horizontal else Rect2(c - Vector2(8, 3), Vector2(16, 6))
				_rbox(mr, 0.1, h - 0.1, _mat("alu", C_METAL, 0.3, 0.8))
		"railing":
			# Barandilla de cristal de la terraza: zócalo, vidrio, postes y pasamanos.
			_rbox(r, 0.0, 0.08, _mat("alu", C_METAL, 0.3, 0.8))
			_rbox(r.grow(-6), 0.08, h - 0.12, _glass())
			_rbox(r.grow(-3), h - 0.04, 0.06, _mat("rail", Color("#C9D2DE"), 0.25, 0.9))
			var length3 := r.size.x if horizontal else r.size.y
			var posts := maxi(1, int(length3 / 95.0))
			for i in posts + 1:
				var t3 := float(i) / float(posts)
				var c3 := r.position + Vector2(r.size.x * t3, r.size.y / 2.0) if horizontal else r.position + Vector2(r.size.x / 2.0, r.size.y * t3)
				_rbox(Rect2(c3 - Vector2(4, 4), Vector2(8, 8)), 0.0, h, _mat("rail", Color("#C9D2DE"), 0.25, 0.9))
			# Tira de LED bajo el pasamanos: ilumina el borde de noche.
			var lr := Rect2(r.position.x, r.position.y + r.size.y / 2.0 - 1, r.size.x, 2) if horizontal else Rect2(r.position.x + r.size.x / 2.0 - 1, r.position.y, 2, r.size.y)
			_rbox(lr, h - 0.07, 0.02, _emit("rail_led", Color(1.8, 1.4, 0.8)))
		"planter":
			_rbox(r, 0.0, 0.45, _mat("wood_l", C_WOOD_LIGHT, 0.5))
			_rbox(r.grow(-3), 0.45, 0.02, _mat("soil", Color("#2B1D14"), 1.0))
			var length2 := r.size.x if horizontal else r.size.y
			var count := maxi(1, int(length2 / 26.0))
			for i in count:
				var t2 := (float(i) + 0.5) / float(count)
				var c2 := r.position + Vector2(r.size.x * t2, r.size.y / 2.0) if horizontal else r.position + Vector2(r.size.x / 2.0, r.size.y * t2)
				_ball(p3(c2, 0.55 + _rng.randf() * 0.06), 0.13 + _rng.randf() * 0.05, _leaf())
		_:   # solid
			_rbox(r, 0.0, h, _mat("wall", C_WALL, 0.7))
			_rbox(r.grow(1.5), h, 0.035, _mat("cap", C_WALL_CAP, 0.4))
			_rbox(r.grow(1), 0.0, 0.08, _mat("skirt", Color("#3B4558"), 0.5))

## Fachada norte: pilares, ventanales con la ciudad de noche y, en la recepción, la
## pared del logo.
func _facade(r: Rect2) -> void:
	var h := 3.0
	_rbox(r, 0.0, h, _mat("facade", Color("#1A2130"), 0.6))
	# Ventanales sobre el despacho, el open space y el laboratorio; la recepción lleva
	# la pared del logo, la sala de servidores rejillas y la de seguridad va ciega.
	for seg in [[760.0, 1400.0], [1400.0, 2120.0], [2120.0, 2640.0], [2640.0, 3160.0], [3160.0, 3600.0]]:
		var x0: float = seg[0]
		var x1: float = seg[1]
		var panes := int((x1 - x0) / 110.0)
		for i in panes:
			var px0 := x0 + (x1 - x0) * float(i) / panes + 6.0
			var px1 := x0 + (x1 - x0) * float(i + 1) / panes - 6.0
			var pr := Rect2(px0, r.end.y - 2.0, px1 - px0, 3.0)
			var win := _rbox(pr, 0.55, 2.2, _skyline_mat())
			win.name = "Window"
	for i in 7:
		var vr := Rect2(190.0 + i * 78.0, r.end.y - 2.0, 50, 3)
		_rbox(vr, 2.2, 0.35, _mat("vent", Color("#2E3748"), 0.5, 0.6))
	# Cuarto eléctrico: ciego, con rejillas de ventilación y un aviso de alta tensión.
	for i in 4:
		var vr2 := Rect2(3650.0 + i * 70.0, r.end.y - 2.0, 50, 3)
		_rbox(vr2, 2.35, 0.3, _mat("vent", Color("#2E3748"), 0.5, 0.6))
	var hv := Label3D.new()
	hv.text = "ALTA TENSIÓN"
	hv.font_size = 36
	hv.pixel_size = 0.003
	hv.modulate = Color(2.0, 1.5, 0.2)
	hv.shaded = false
	hv.position = p3(Vector2(3780, r.end.y + 4.0), 2.15)
	add_child(hv)
	# Pared del logo en el vestíbulo: madera cálida + letras luminosas.
	_rbox(Rect2(-150, r.end.y - 2.0, 300, 4.0), 0.0, h - 0.2, _mat("wood_wall", Color("#6B4630"), 0.45))
	var logo := Label3D.new()
	logo.text = "NEXUSCORE AI"
	logo.font_size = 72
	logo.pixel_size = 0.0036
	logo.outline_size = 0
	logo.modulate = Color(0.55, 1.9, 2.4)
	logo.shaded = false
	logo.position = p3(Vector2(0, r.end.y + 4.0), 1.95)
	add_child(logo)
	var sub := Label3D.new()
	sub.text = "PISO 14 · OFICINAS CENTRALES"
	sub.font_size = 32
	sub.pixel_size = 0.0032
	sub.modulate = Color(0.85, 0.9, 1.0, 0.8)
	sub.shaded = false
	sub.position = p3(Vector2(0, r.end.y + 4.0), 1.6)
	add_child(sub)
	# Pilares.
	for x in [-640.0, -160.0, 160.0, 760.0, 1400.0, 2120.0, 2640.0, 3160.0, 3600.0, 4040.0]:
		_rbox(Rect2(x - 14, r.position.y, 28, r.size.y + 14), 0.0, h + 0.05, _mat("pillar", Color("#2B3446"), 0.5))
	_rbox(r.grow(3), h, 0.06, _mat("cap", C_WALL_CAP, 0.4))

# ── mobiliario ─────────────────────────────────────────────────────────────

func _prop(p: Dictionary) -> void:
	var r: Rect2 = p["rect"]
	var face := str(p.get("face", "s"))
	match str(p["type"]):
		"rug":
			_rbox(r, 0.0, 0.015, _mat("rug_" + str(p["color"]), Color(str(p["color"])), 1.0))
			_rbox(r.grow(-10), 0.015, 0.004, _mat("rug_in_" + str(p["color"]), Color(str(p["color"])).lightened(0.12), 1.0))
		"reception":
			_rbox(r, 0.0, 0.95, _mat("recep", Color("#E8E3DA"), 0.25))
			_rbox(r.grow(4), 0.95, 0.05, _mat("wood_l", C_WOOD_LIGHT, 0.4))
			var strip := Rect2(r.position.x, r.end.y - 4, r.size.x, 4)
			_rbox(strip, 0.08, 0.04, _emit("strip_cyan", Color(0.3, 1.6, 2.2)))
			_monitor(Vector2(r.get_center().x - 40, r.get_center().y), "n")
			_monitor(Vector2(r.get_center().x + 40, r.get_center().y), "n")
		"plant_big":
			_plant(r.get_center(), 0.55)
		"sofa":
			_sofa(r, face, Color(str(p.get("color", "#3F4C66"))))
		"armchair":
			_sofa(r, face, Color("#7C3A2D"))
		"coffee_table":
			_rbox(r, 0.36, 0.04, _mat("glass_top", Color(0.7, 0.85, 1.0), 0.05, 0.2))
			_rbox(r.grow(-8), 0.0, 0.36, _mat("dark", C_DARK, 0.4, 0.4))
			_ball(p3(r.get_center(), 0.44), 0.06, _mat("vase", Color("#E5E7EB"), 0.2))
		"kiosk":
			_rbox(r.grow(-12), 0.0, 1.0, _mat("dark", C_DARK, 0.4, 0.4))
			_rbox(Rect2(r.position.x, r.position.y + 8, r.size.x, 10), 0.95, 0.45, _emit("kiosk", Color(0.4, 0.9, 1.6)))
		"rack":
			_rbox(r, 0.0, 2.05, _mat("rack", Color("#151A22"), 0.35, 0.6))
			var front := Rect2(r.position.x + 5, r.end.y - 3, r.size.x - 10, 3)
			for i in 9:
				var col := Color(0.2, 1.6, 2.4) if (i + int(r.position.x)) % 3 != 0 else Color(2.4, 0.4, 0.3)
				_rbox(Rect2(front.position.x, front.position.y, front.size.x * (0.35 + 0.6 * _rng.randf()), 2), 0.18 + i * 0.2, 0.02, _emit("led%d" % (i % 3), col))
		"ups":
			_rbox(r, 0.0, 0.9, _mat("ups", Color("#2A303B"), 0.4, 0.5))
			_rbox(Rect2(r.position.x + 10, r.end.y - 2, 16, 2), 0.7, 0.05, _emit("ups_ok", Color(0.3, 2.0, 0.6)))
		"cooling":
			_rbox(r, 0.0, 1.7, _mat("cool", Color("#C8CED8"), 0.4, 0.4))
			for i in 5:
				_rbox(Rect2(r.position.x - 1, r.position.y + 15 + i * 20, 3, 12), 0.5, 0.9, _mat("vent", Color("#2E3748"), 0.5, 0.6))
		"sysadmin_desk":
			_desk(r, face, C_DARK)
			_monitor(r.get_center() + Vector2(-22, -8), face)
			_monitor(r.get_center() + Vector2(22, -8), face)
			_chair(r.get_center() + Vector2(0, 46), face)
		"bookshelf":
			_rbox(r, 0.0, 2.1, _mat("wood_d", Color("#4A2F20"), 0.5))
			for row in 4:
				for i in 10:
					var bw := 6.0 + _rng.randf() * 8.0
					var bx := r.position.x + 10 + i * (r.size.x - 20) / 10.0
					var col2: Color = [Color("#7F1D1D"), Color("#1E3A8A"), Color("#14532D"), Color("#A16207"), Color("#E5E7EB")][_rng.randi() % 5]
					_rbox(Rect2(bx, r.end.y - 6, bw, 5), 0.25 + row * 0.48, 0.28 + _rng.randf() * 0.1, _mat("book%d" % (_rng.randi() % 99), col2, 0.6))
		"exec_desk":
			_desk(r, face, Color("#5B3826"), 0.78)
			_monitor(r.get_center() + Vector2(-50, -12), face, 1.25)
			_lamp(r.get_center() + Vector2(80, -15))
			_box3(p3(r.get_center() + Vector2(0, 25), 0.8), Vector3(0.36, 0.02, 0.26), _mat("laptop", Color("#CBD5E1"), 0.25, 0.7))
		"exec_chair":
			_chair(r.get_center(), face, Color("#111827"), 1.15)
		"safe":
			_rbox(r, 0.0, 0.85, _mat("safe", Color("#5B6475"), 0.3, 0.85))
			_cyl(p3(r.get_center() + Vector2(0, r.size.y / 2.0), 0.45), 0.07, 0.07, 0.03, _mat("dial", Color("#D1D5DB"), 0.2, 0.9)).rotation.x = PI / 2.0
		"desk_pod":
			_desk_pod(r)
		"whiteboard":
			_rbox(r, 0.0, 1.0, _mat("alu", C_METAL, 0.3, 0.8))
			_rbox(r.grow(-2), 0.6, 0.9, _mat("board", Color("#F8FAFC"), 0.15))
		"printer":
			_rbox(r, 0.0, 0.95, _mat("printer", Color("#E2E8F0"), 0.35))
			_rbox(r.grow(-6), 0.95, 0.12, _mat("dark", C_DARK, 0.4, 0.4))
			_rbox(Rect2(r.position.x + 6, r.end.y - 2, 12, 2), 0.8, 0.04, _emit("ups_ok", Color(0.3, 2.0, 0.6)))
		"meeting_table":
			_rbox(r.grow(-20), 0.73, 0.05, _mat("wood_d", Color("#3D2617"), 0.3))
			_rbox(r.grow(-50), 0.0, 0.73, _mat("dark", C_DARK, 0.4, 0.4))
			for i in 4:
				var x := r.position.x + 40 + i * (r.size.x - 80) / 3.0
				_chair(Vector2(x, r.position.y + 8), "s")
				_chair(Vector2(x, r.end.y - 8), "n")
		"tv_wall":
			_rbox(r, 0.25, 1.15, _mat("dark", C_DARK, 0.4, 0.4))
			_rbox(Rect2(r.end.x - 2, r.position.y + 6, 2, r.size.y - 12), 0.3, 1.05, _emit("tv", Color(0.25, 0.6, 1.3)))
		"counter":
			_rbox(r, 0.0, 0.92, _mat("counter", Color("#E7E1D6"), 0.3))
			_rbox(r.grow(2), 0.92, 0.05, _mat("stone", Color("#8F98A4"), 0.15))
			_rbox(Rect2(r.position.x + 6, r.position.y + 30, 28, 36), 0.97, 0.38, _mat("dark", C_DARK, 0.4, 0.4))   # cafetera
			_rbox(Rect2(r.position.x + 6, r.position.y + 30, 2, 36), 1.15, 0.06, _emit("coffee", Color(2.0, 0.9, 0.3)))
			_cyl(p3(Vector2(r.get_center().x, r.position.y + 110), 1.0), 0.04, 0.035, 0.1, _mat("mug", Color("#F8FAFC"), 0.3))
		"fridge":
			_rbox(r, 0.0, 1.85, _mat("fridge", Color("#CBD5E1"), 0.25, 0.6))
		"vending":
			_rbox(r, 0.0, 1.9, _mat("vend", Color("#7F1D1D"), 0.35))
			_rbox(Rect2(r.position.x + 6, r.end.y - 2, r.size.x - 20, 2), 0.5, 1.25, _emit("vend_glow", Color(1.8, 1.5, 1.0)))
		"cafe_table":
			var c := r.get_center()
			_cyl(p3(c, 0.74), r.size.x / 200.0 * 0.85, r.size.x / 200.0 * 0.85, 0.04, _mat("table_w", Color("#F1F5F9"), 0.25), 32)
			_cyl(p3(c, 0.37), 0.03, 0.03, 0.72, _mat("alu", C_METAL, 0.3, 0.8))
			for k in 3:
				var ang := TAU * k / 3.0 + 0.4
				var sc := c + Vector2(cos(ang), sin(ang)) * r.size.x * 0.62
				_cyl(p3(sc, 0.45), 0.12, 0.12, 0.05, _mat("stool", Color("#E5A93C"), 0.4), 20)
				_cyl(p3(sc, 0.22), 0.02, 0.02, 0.44, _mat("alu", C_METAL, 0.3, 0.8))
		"cabinets":
			_rbox(r, 0.0, 1.3, _mat("cab", Color("#6B7280"), 0.4, 0.5))
			var n := int(maxf(r.size.x, r.size.y) / 45.0)
			for i in n:
				for row in 3:
					var dr := Rect2(r.end.x - 2, r.position.y + 6 + i * 45, 2, 36) if face == "o" else Rect2(r.position.x, r.position.y + 6 + i * 45, 2, 36)
					if face == "e":
						dr = Rect2(r.end.x - 1, r.position.y + 6 + i * 45, 2, 36)
					_rbox(dr, 0.12 + row * 0.4, 0.3, _mat("cab_d", Color("#9CA3AF"), 0.35, 0.6))
		"boxes":
			for i in 6:
				var bx2 := Rect2(r.position.x + (i % 3) * 46, r.position.y + (i / 3) * 4, 42, 44)
				_rbox(bx2, (i / 3) * 0.32, 0.32, _mat("cardboard", Color("#B08455"), 0.9))
		"bins":
			var cols := [Color("#2563EB"), Color("#16A34A"), Color("#CA8A04")]
			for i in 3:
				var br := Rect2(r.position.x + i * (r.size.x / 3.0) + 4, r.position.y, r.size.x / 3.0 - 8, r.size.y)
				_rbox(br, 0.0, 0.7, _mat("bin%d" % i, cols[i], 0.45))
		"cctv_wall":
			# Muro de pantallas de vigilancia: 2 filas de monitores con imagen fría.
			_rbox(r, 0.0, 2.0, _mat("dark", C_DARK, 0.4, 0.4))
			var cols3 := int(r.size.x / 70.0)
			for row in 2:
				for i in cols3:
					var sr := Rect2(r.position.x + 6 + i * (r.size.x - 12) / cols3, r.end.y - 2, (r.size.x - 12) / cols3 - 6, 2)
					var tint := Color(0.35, 0.9, 1.4) if (i + row) % 3 else Color(0.9, 1.3, 0.8)
					_rbox(sr, 0.8 + row * 0.55, 0.45, _emit("cctv%d" % ((i + row) % 3), tint))
		"elevator":
			_rbox(r, 0.0, 2.2, _mat("alu", C_METAL, 0.3, 0.8))
			var seam := Rect2(r.end.x - 1, r.get_center().y - 1, 2, 2)
			_rbox(seam, 0.0, 2.1, _mat("dark", C_DARK, 0.4, 0.4))
			_rbox(Rect2(r.end.x - 1, r.get_center().y - 12, 2, 24), 2.3, 0.12, _emit("lift", Color(2.0, 1.2, 0.3)))
		"holo_table":
			_rbox(r.grow(-10), 0.0, 0.8, _mat("dark", C_DARK, 0.4, 0.4))
			_rbox(r, 0.8, 0.05, _mat("glass_top", Color(0.7, 0.85, 1.0), 0.05, 0.2))
			_rbox(r.grow(-16), 0.86, 0.01, _emit("holo", Color(0.6, 0.5, 2.2)))
			_ball(p3(r.get_center(), 1.25), 0.22, _emit("holo_core", Color(0.8, 0.6, 2.4)))
		"lab_bench":
			_desk(r, face, Color("#E5E7EB"))
			_monitor(r.get_center() + Vector2(-50, 0), face)
			_rbox(Rect2(r.get_center().x + 20, r.get_center().y - 12, 40, 24), 0.74, 0.3, _mat("gpu", Color("#111827"), 0.3, 0.7))
			_rbox(Rect2(r.get_center().x + 22, r.end.y - 2 if face == "s" else r.position.y + 6, 36, 2), 0.85, 0.05, _emit("gpu_led", Color(0.4, 2.2, 0.8)))
		"shredder":
			_rbox(r, 0.0, 0.7, _mat("dark", C_DARK, 0.4, 0.4))
			_rbox(Rect2(r.position.x + 6, r.end.y - 2, 8, 2), 0.6, 0.04, _emit("red_led", Color(2.4, 0.3, 0.2)))
		_:
			_prop_east(p, r, face)

## Mobiliario del ala este (legal, RRHH, cuarto eléctrico, gimnasio y terraza).
func _prop_east(p: Dictionary, r: Rect2, face: String) -> void:
	match str(p["type"]):
		"extinguisher":
			var c := r.get_center()
			_cyl(p3(c, 0.28), 0.09, 0.09, 0.5, _mat("ext_red", Color("#C0262D"), 0.35), 16)
			_cyl(p3(c, 0.57), 0.04, 0.05, 0.08, _mat("dark", C_DARK, 0.4, 0.4), 12)
			_box3(p3(c + Vector2(-8, 0), 0.5), Vector3(0.05, 0.18, 0.03), _mat("dark", C_DARK, 0.4, 0.4))
		"law_shelf":
			# Estantería de códigos y jurisprudencia: lomos uniformes con bandas doradas,
			# en series por colección. Fondo, laterales y baldas; los libros asoman al frente.
			var wood := _mat("wood_d", Color("#4A2F20"), 0.5)
			_rbox(Rect2(r.position.x, r.position.y, r.size.x, 8), 0.0, 2.1, wood)
			for x in [r.position.x, r.end.x - 8]:
				_rbox(Rect2(x, r.position.y, 8, r.size.y), 0.0, 2.1, wood)
			_rbox(r, 2.06, 0.05, wood)
			var gold := _mat("gold", Color("#C9A24A"), 0.3, 0.9)
			var tones := [Color("#7A1F1F"), Color("#1F4A33"), Color("#22325E"), Color("#5A3A1E")]
			for row in 4:
				var y0 := 0.12 + row * 0.48
				_rbox(Rect2(r.position.x + 8, r.position.y + 8, r.size.x - 16, r.size.y - 8), y0 - 0.03, 0.03, wood)
				var series: Color = tones[_rng.randi() % tones.size()]
				var x := r.position.x + 12.0
				while x < r.end.x - 20.0:
					if _rng.randf() < 0.07:
						series = tones[_rng.randi() % tones.size()]
						x += 7.0
						continue
					var bh := 0.32 + _rng.randf() * 0.05
					_rbox(Rect2(x, r.position.y + 10, 7.5, r.size.y - 12), y0, bh, _mat("law%s" % series.to_html(), series, 0.55))
					_rbox(Rect2(x, r.end.y - 2.5, 7.5, 0.8), y0 + bh * 0.72, 0.03, gold)
					_rbox(Rect2(x, r.end.y - 2.5, 7.5, 0.8), y0 + bh * 0.2, 0.02, gold)
					x += 8.5
			# Luz de lectura cálida sobre la estantería.
			_rbox(Rect2(r.position.x + 20, r.end.y - 3, r.size.x - 40, 3), 2.02, 0.03, _emit("shelf_led", Color(2.2, 1.6, 0.9)))
		"meeting_small":
			_rbox(r.grow(-22), 0.72, 0.05, _mat("wood_l", C_WOOD_LIGHT, 0.4))
			_rbox(r.grow(-56), 0.0, 0.72, _mat("dark", C_DARK, 0.4, 0.4))
			for x in [r.position.x + 52, r.end.x - 52]:
				_chair(Vector2(x, r.position.y + 6), "s", Color("#5B2333"))
				_chair(Vector2(x, r.end.y - 6), "n", Color("#5B2333"))
			# Carpetas de expedientes y una jarra de agua.
			_box3(p3(r.get_center() + Vector2(-26, -6), 0.79), Vector3(0.3, 0.05, 0.22), _mat("folder", Color("#D6C8A6"), 0.8))
			_box3(p3(r.get_center() + Vector2(-24, -4), 0.83), Vector3(0.28, 0.03, 0.2), _mat("folder_r", Color("#8C2F2F"), 0.8))
			_cyl(p3(r.get_center() + Vector2(30, 6), 0.86), 0.05, 0.05, 0.18, _mat("glass_top", Color(0.7, 0.85, 1.0), 0.05, 0.2), 16)
		"scales":
			# Peana con la balanza de la justicia.
			var c2 := r.get_center()
			_rbox(r.grow(-6), 0.0, 0.9, _mat("marble_p", Color("#D9D6CF"), 0.2))
			var brass := _mat("brass", Color("#B08D57"), 0.3, 0.9)
			_cyl(p3(c2, 1.12), 0.015, 0.015, 0.45, brass, 10)
			_box3(p3(c2, 1.34), Vector3(0.4, 0.02, 0.02), brass)
			for dx in [-0.19, 0.19]:
				_box3(p3(c2, 1.24) + Vector3(dx, 0, 0), Vector3(0.006, 0.2, 0.006), brass)
				_cyl(p3(c2, 1.14) + Vector3(dx, 0, 0), 0.08, 0.05, 0.03, brass, 16)
		"notice_board":
			# Tablón de corcho con avisos y fotos de plantilla.
			_rbox(Rect2(r.position.x + 10, r.position.y, 6, r.size.y), 0.0, 0.9, _mat("alu", C_METAL, 0.3, 0.8))
			_rbox(Rect2(r.end.x - 16, r.position.y, 6, r.size.y), 0.0, 0.9, _mat("alu", C_METAL, 0.3, 0.8))
			_rbox(r, 0.9, 0.85, _mat("frame", Color("#5A4632"), 0.5))
			_rbox(Rect2(r.position.x + 4, r.end.y - 2, r.size.x - 8, 2), 0.94, 0.77, _mat("cork", Color("#B98B5E"), 0.95))
			var notes := [Color("#F8FAFC"), Color("#FDE68A"), Color("#BFDBFE"), Color("#FBCFE8"), Color("#BBF7D0")]
			for i in 9:
				var nx := r.position.x + 10 + _rng.randf() * (r.size.x - 34)
				var col: Color = notes[_rng.randi() % notes.size()]
				_rbox(Rect2(nx, r.end.y, 16 + _rng.randf() * 8, 1.5), 1.0 + _rng.randf() * 0.5, 0.14 + _rng.randf() * 0.08, _mat("note%s" % col.to_html(), col, 0.9))
		"office_desk":
			_desk(r, face, Color("#D9CBB4"))
			_monitor(r.get_center() + Vector2(-22, -6 if face == "n" else 6), face)
			_box3(p3(r.get_center() + Vector2(34, 0), 0.76), Vector3(0.22, 0.04, 0.3), _mat("paper", Color("#F1F5F9"), 0.9))
			_cyl(p3(r.get_center() + Vector2(48, -14), 0.79), 0.035, 0.03, 0.09, _mat("mug", Color("#F8FAFC"), 0.3))
			_chair(r.get_center() + Vector2(0, 46 if face == "n" else -46), face)
		"waiting_chairs":
			# Bancada de espera de cuatro asientos sobre una viga.
			var vertical := r.size.y > r.size.x
			var n := 4
			var fab := _mat("wait", Color("#2F6F73"), 0.8)
			if vertical:
				_rbox(Rect2(r.position.x + 14, r.position.y + 6, 10, r.size.y - 12), 0.28, 0.05, _mat("alu", C_METAL, 0.3, 0.8))
			else:
				_rbox(Rect2(r.position.x + 6, r.position.y + 14, r.size.x - 12, 10), 0.28, 0.05, _mat("alu", C_METAL, 0.3, 0.8))
			for i in n:
				var seat := Rect2(r.position.x + 2, r.position.y + 4 + i * (r.size.y - 8) / n, r.size.x - 4, (r.size.y - 8) / n - 6) if vertical \
					else Rect2(r.position.x + 4 + i * (r.size.x - 8) / n, r.position.y + 2, (r.size.x - 8) / n - 6, r.size.y - 4)
				_rbox(seat, 0.4, 0.07, fab)
				var back := Rect2(seat.position.x, seat.position.y, 7, seat.size.y)
				match face:
					"o": back = Rect2(seat.end.x - 7, seat.position.y, 7, seat.size.y)
					"s": back = Rect2(seat.position.x, seat.position.y, seat.size.x, 7)
					"n": back = Rect2(seat.position.x, seat.end.y - 7, seat.size.x, 7)
				_rbox(back, 0.47, 0.4, fab)
			for t in [0.12, 0.88]:
				var lc := r.position + r.size * (Vector2(0.5, t) if vertical else Vector2(t, 0.5))
				_rbox(Rect2(lc - Vector2(3, 3), Vector2(6, 6)), 0.0, 0.3, _mat("alu", C_METAL, 0.3, 0.8))
		"water_cooler":
			var c3 := r.get_center()
			_rbox(r.grow(-2), 0.0, 0.95, _mat("cooler", Color("#E8ECF1"), 0.3))
			_rbox(Rect2(r.position.x + 8, r.end.y - 3, r.size.x - 16, 3), 0.62, 0.12, _mat("dark", C_DARK, 0.4, 0.4))
			var water := StandardMaterial3D.new()
			water.albedo_color = Color(0.45, 0.7, 1.0, 0.55)
			water.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			water.roughness = 0.05
			_cyl(p3(c3, 1.15), 0.12, 0.13, 0.4, water, 18)
		"elec_panel":
			# Fila de cuadros eléctricos: puertas grises, aviso amarillo y pilotos.
			var vertical2 := r.size.y > r.size.x
			var n2 := int((r.size.y if vertical2 else r.size.x) / 60.0)
			_rbox(r, 0.0, 1.95, _mat("panel", Color("#7A818C"), 0.45, 0.4))
			for i in n2:
				var a0 := (r.position.y if vertical2 else r.position.x) + i * 60.0
				var door := Rect2()
				match face:
					"e": door = Rect2(r.end.x - 1, a0 + 4, 2, 52)
					"o": door = Rect2(r.position.x - 1, a0 + 4, 2, 52)
					"n": door = Rect2(a0 + 4, r.position.y - 1, 52, 2)
					_: door = Rect2(a0 + 4, r.end.y - 1, 52, 2)
				_rbox(door, 0.1, 1.75, _mat("panel_d", Color("#9AA1AC"), 0.4, 0.5))
				var mid := door.get_center()
				var sticker := Rect2(mid - Vector2(7, 1.5), Vector2(14, 3)) if not vertical2 else Rect2(mid - Vector2(1.5, 7), Vector2(3, 14))
				_rbox(sticker, 1.45, 0.14, _mat("hv_sign", Color("#F2C230"), 0.6))
				var led := Rect2(mid - Vector2(10, 2), Vector2(4, 4))
				_rbox(led, 1.72, 0.04, _emit("led%d" % (i % 3), Color(0.2, 1.6, 2.4) if i % 3 else Color(2.4, 0.4, 0.3)))
				_rbox(Rect2(mid + Vector2(4, -2), Vector2(4, 4)), 1.72, 0.04, _emit("ups_ok", Color(0.3, 2.0, 0.6)))
		"ups_big":
			# SAI de sala: armario doble con pantalla de estado ámbar y rejillas.
			_rbox(r, 0.0, 1.95, _mat("ups", Color("#2A303B"), 0.4, 0.5))
			_rbox(r.grow(2), 1.95, 0.04, _mat("dark", C_DARK, 0.4, 0.4))
			var fx := r.position.x - 1 if face == "o" else r.end.x - 1
			for i in 2:
				var y0 := r.position.y + 10 + i * (r.size.y / 2.0)
				_rbox(Rect2(fx, y0, 2, r.size.y / 2.0 - 20), 0.1, 1.7, _mat("ups_d", Color("#363E4B"), 0.4, 0.5))
				_rbox(Rect2(fx - 0.5, y0 + 30, 3, 60), 1.35, 0.25, _emit("ups_screen", Color(2.0, 1.2, 0.3)))
				for k in 5:
					_rbox(Rect2(fx - 0.5, y0 + 20 + k * 18, 3, 10), 0.3, 0.6, _mat("vent", Color("#1B2230"), 0.5, 0.6))
			# Testigos en la cara que da a la sala (se ven desde la cámara).
			_rbox(Rect2(r.position.x + 12, r.end.y - 1, r.size.x - 24, 2), 1.3, 0.22, _emit("ups_screen", Color(2.0, 1.2, 0.3)))
			_rbox(Rect2(r.position.x + 12, r.end.y - 1, 10, 2), 1.62, 0.05, _emit("ups_ok", Color(0.3, 2.0, 0.6)))
		"cables":
			# Mazos de cable por el suelo y cinta de peligro delante de los cuadros.
			var black := _mat("cable", Color("#121418"), 0.6)
			for i in 5:
				var x0 := r.position.x + 30 + i * 22.0
				_rbox(Rect2(x0, r.position.y + 6, 6, r.size.y * (0.5 + 0.1 * i)), 0.0, 0.035, black)
				_rbox(Rect2(x0, r.position.y + 6 + r.size.y * (0.5 + 0.1 * i) - 6, r.end.x - x0 - 10, 6), 0.0, 0.035, black)
			_rbox(Rect2(r.position.x, r.position.y + 2, r.size.x, 6), 0.0, 0.01, _mat("hazard", Color("#E5B92B"), 0.7))
			for i in int(r.size.x / 24.0):
				_rbox(Rect2(r.position.x + i * 24.0, r.position.y + 2, 10, 6), 0.0, 0.012, _mat("dark", C_DARK, 0.4, 0.4))
		"cable_reel":
			var c4 := r.get_center()
			var reel := _cyl(p3(c4, 0.32), 0.32, 0.32, 0.06, _mat("wood_l", C_WOOD_LIGHT, 0.5), 20)
			reel.rotation.x = PI / 2.0
			reel.position.z -= 0.18
			var reel2 := _cyl(p3(c4, 0.32), 0.32, 0.32, 0.06, _mat("wood_l", C_WOOD_LIGHT, 0.5), 20)
			reel2.rotation.x = PI / 2.0
			reel2.position.z += 0.18
			var core := _cyl(p3(c4, 0.32), 0.24, 0.24, 0.32, _mat("cable_o", Color("#D9622B"), 0.6), 20)
			core.rotation.x = PI / 2.0
		"emergency_light":
			# Baliza roja de emergencia (parpadea en _process).
			var h0 := float(p.get("h", 1.8))
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color(0.5, 0.05, 0.04)
			mat.emission_enabled = true
			mat.emission = Color(1.0, 0.12, 0.08)
			_rbox(r, h0, 0.1, _mat("dark", C_DARK, 0.4, 0.4))
			_rbox(r.grow(-2), h0 + 0.1, 0.08, mat)
			var o := OmniLight3D.new()
			o.position = p3(r.get_center(), h0 + 0.25)
			o.light_color = Color("#FF3B2A")
			o.omni_range = 3.4
			o.omni_attenuation = 1.3
			o.light_cull_mask = 1
			add_child(o)
			_blink.append({"light": o, "mat": mat, "phase": float(_blink.size()) * 2.1})
		"treadmill":
			# Cinta de correr mirando al norte: base, banda, barandillas y consola.
			_rbox(r, 0.0, 0.16, _mat("tm_base", Color("#2B313C"), 0.4, 0.5))
			_rbox(Rect2(r.position.x + 10, r.position.y + 26, r.size.x - 20, r.size.y - 34), 0.16, 0.02, _mat("belt", Color("#111317"), 0.9))
			var steel := _mat("alu", C_METAL, 0.3, 0.8)
			for x in [r.position.x + 4, r.end.x - 10]:
				_rbox(Rect2(x, r.position.y + 6, 6, 8), 0.16, 1.05, steel)
				_rbox(Rect2(x, r.position.y + 6, 6, 50), 0.95, 0.04, steel)
			_rbox(Rect2(r.position.x + 6, r.position.y + 2, r.size.x - 12, 16), 1.15, 0.2, _mat("dark", C_DARK, 0.4, 0.4))
			_rbox(Rect2(r.position.x + 14, r.position.y + 16, r.size.x - 28, 2), 1.19, 0.12, _emit("tm_screen", Color(0.3, 1.4, 2.0)))
		"weight_bench":
			# Banco de press con soporte y barra cargada (el soporte en la cabecera norte).
			_rbox(Rect2(r.position.x + 10, r.position.y + 30, r.size.x - 20, r.size.y - 36), 0.38, 0.1, _mat("pad", Color("#7F1D1D"), 0.7))
			_rbox(Rect2(r.position.x + 20, r.position.y + 36, r.size.x - 40, r.size.y - 48), 0.0, 0.38, _mat("dark", C_DARK, 0.4, 0.4))
			var steel2 := _mat("alu", C_METAL, 0.3, 0.8)
			for x in [r.position.x, r.end.x - 6]:
				_rbox(Rect2(x, r.position.y + 6, 6, 6), 0.0, 1.15, steel2)
			var bar := _cyl(p3(Vector2(r.get_center().x, r.position.y + 9), 1.1), 0.015, 0.015, 1.5, steel2, 8)
			bar.rotation.z = PI / 2.0
			for dx in [-0.6, 0.6]:
				var plate := _cyl(p3(Vector2(r.get_center().x, r.position.y + 9), 1.1) + Vector3(dx, 0, 0), 0.2, 0.2, 0.05, _mat("plate", Color("#1F2328"), 0.6, 0.3), 18)
				plate.rotation.z = PI / 2.0
		"dumbbells":
			# Estante de mancuernas en dos alturas, contra la pared.
			var steel3 := _mat("alu", C_METAL, 0.3, 0.8)
			_rbox(r, 0.0, 0.06, steel3)
			_rbox(Rect2(r.position.x, r.position.y, 8, r.size.y), 0.0, 0.75, steel3)
			_rbox(Rect2(r.position.x, r.position.y, r.size.x, 6), 0.0, 0.75, steel3)
			_rbox(Rect2(r.position.x, r.end.y - 6, r.size.x, 6), 0.0, 0.75, steel3)
			for tier in 2:
				var y_t := 0.32 + tier * 0.36
				_rbox(Rect2(r.position.x + 4, r.position.y + 4, r.size.x - 8, r.size.y - 8), y_t, 0.03, _mat("dark", C_DARK, 0.4, 0.4))
				var count2 := int((r.size.y - 16) / 26.0)
				var dcol := Color("#2A2F37") if tier == 0 else Color("#3F7FBF")
				for i in count2:
					var cy := r.position.y + 16 + i * 26.0
					var size := 0.04 + 0.006 * i
					var dc := p3(Vector2(r.get_center().x + 2, cy), y_t + 0.03 + size)
					var handle := _cyl(dc, 0.012, 0.012, 0.22, steel3, 6)
					handle.rotation.z = PI / 2.0
					for dx in [-0.1, 0.1]:
						var head := _cyl(dc + Vector3(dx, 0, 0), size, size, 0.05, _mat("db%d" % tier, dcol, 0.5, 0.3), 12)
						head.rotation.z = PI / 2.0
		"lockers":
			# Taquillas numeradas (de "first" en adelante), puertas al lado "face".
			var vertical3 := r.size.y > r.size.x
			var n3 := int((r.size.y if vertical3 else r.size.x) / 40.0)
			_rbox(r, 0.0, 1.9, _mat("locker", Color("#4C6A8C"), 0.4, 0.5))
			_rbox(r.grow(1), 1.9, 0.04, _mat("dark", C_DARK, 0.4, 0.4))
			var first := int(p.get("first", 1))
			for i in n3:
				var a1 := (r.position.y if vertical3 else r.position.x) + i * 40.0
				var door2 := Rect2(a1 + 3, r.end.y - 1, 34, 2)
				var rot := 0.0
				match face:
					"n":
						door2 = Rect2(a1 + 3, r.position.y - 1, 34, 2)
						rot = PI
					"e":
						door2 = Rect2(r.end.x - 1, a1 + 3, 2, 34)
						rot = PI / 2.0
					"o":
						door2 = Rect2(r.position.x - 1, a1 + 3, 2, 34)
						rot = -PI / 2.0
				_rbox(door2, 0.06, 1.78, _mat("locker_d", Color("#5E7FA3"), 0.35, 0.5))
				var dc := door2.get_center()
				for k in 4:
					var slot := Rect2(dc + Vector2(-8, -1.5), Vector2(16, 3)) if not vertical3 else Rect2(dc + Vector2(-1.5, -8), Vector2(3, 16))
					_rbox(slot, 1.45 + k * 0.06, 0.02, _mat("dark", C_DARK, 0.4, 0.4))
				var num := Label3D.new()
				num.text = str(first + i)
				num.font_size = 32
				num.pixel_size = 0.0035
				num.modulate = Color(0.95, 0.97, 1.0)
				num.outline_size = 4
				num.shaded = false
				var out := (dc - r.get_center()).normalized() * 2.5
				num.position = p3(dc + out, 1.3)
				num.rotation.y = rot
				add_child(num)
		"bench":
			# Banco de vestuario: listones de madera sobre dos patas.
			_rbox(r, 0.42, 0.05, _mat("wood_l", C_WOOD_LIGHT, 0.5))
			for x in [r.position.x + 10, r.end.x - 18]:
				_rbox(Rect2(x, r.position.y + 4, 8, r.size.y - 8), 0.0, 0.42, _mat("alu", C_METAL, 0.3, 0.8))
		"planter_big":
			# Jardinera grande de fibrocemento con un arbusto (o un olivo).
			var c5 := r.get_center()
			_rbox(r, 0.0, 0.62, _mat("fibro", Color("#59606B"), 0.85))
			_rbox(r.grow(-5), 0.62, 0.02, _mat("soil", Color("#2B1D14"), 1.0))
			if r.size.x >= 64:
				_cyl(p3(c5, 1.0), 0.04, 0.06, 0.8, _mat("trunk", Color("#5A4030"), 0.9), 8)
				for i in 7:
					var ang := TAU * i / 7.0
					_ball(p3(c5, 1.45 + _rng.randf() * 0.25) + Vector3(cos(ang) * 0.22, 0, sin(ang) * 0.22), 0.2 + _rng.randf() * 0.06, _mat("olive%d" % (i % 2), Color("#6E8B5A").darkened(0.15 * (i % 2)), 0.8))
			else:
				for i in 5:
					var ang2 := TAU * i / 5.0
					_ball(p3(c5, 0.85 + _rng.randf() * 0.15) + Vector3(cos(ang2) * 0.12, 0, sin(ang2) * 0.12), 0.17 + _rng.randf() * 0.05, _leaf())
		"patio_table":
			# Mesa de exterior con sombrilla y cuatro sillas.
			var c6 := r.get_center()
			_cyl(p3(c6, 0.72), 0.42, 0.42, 0.04, _mat("teak", Color("#9A6A45"), 0.6), 28)
			_cyl(p3(c6, 0.36), 0.04, 0.04, 0.72, _mat("dark", C_DARK, 0.4, 0.4), 8)
			_cyl(p3(c6, 1.25), 0.02, 0.02, 2.5, _mat("alu", C_METAL, 0.3, 0.8), 8)
			_cyl(p3(c6, 2.35), 0.0, 0.95, 0.32, _mat("canvas", Color("#E9E2D0"), 0.9), 8)
			_chair(c6 + Vector2(0, -58), "s", Color("#9A6A45"))
			_chair(c6 + Vector2(0, 58), "n", Color("#9A6A45"))
		"lounger":
			# Tumbona de teca con colchoneta a rayas, respaldo en la cabecera.
			var teak := _mat("teak", Color("#9A6A45"), 0.6)
			_rbox(r, 0.18, 0.06, teak)
			for y in [r.position.y + 6, r.end.y - 12]:
				_rbox(Rect2(r.position.x + 2, y, r.size.x - 4, 6), 0.0, 0.18, teak)
			_rbox(r.grow(-4), 0.24, 0.05, _mat("cushion_w", Color("#F1EDE4"), 0.9))
			for i in 3:
				_rbox(Rect2(r.position.x + 4, r.position.y + 20 + i * 36, r.size.x - 8, 10), 0.29, 0.005, _mat("stripe", Color("#2F7F86"), 0.9))
			var head_y := r.position.y + 4 if face == "s" else r.end.y - 34
			var back := _rbox(Rect2(r.position.x + 4, head_y, r.size.x - 8, 30), 0.3, 0.06, _mat("cushion_w", Color("#F1EDE4"), 0.9))
			back.rotation.x = 0.7 if face == "s" else -0.7
			back.position.y += 0.18
		"telescope":
			# Telescopio sobre trípode, apuntando a la ciudad.
			var c7 := r.get_center()
			var steel4 := _mat("alu", C_METAL, 0.3, 0.8)
			for k in 3:
				var ang3 := TAU * k / 3.0
				var leg := _cyl(p3(c7, 0.6) + Vector3(cos(ang3) * 0.14, 0, sin(ang3) * 0.14), 0.012, 0.012, 1.22, steel4, 6)
				leg.rotation = Vector3(sin(ang3) * 0.22, 0, -cos(ang3) * 0.22)
			var tube := _cyl(p3(c7, 1.28), 0.07, 0.05, 0.75, _mat("scope", Color("#E5E7EB"), 0.3, 0.4), 16)
			tube.rotation = Vector3(0.5, 0, -1.1)
		"festoon":
			_festoon(r)

## Guirnalda de bombillas cálidas sobre la terraza: cuatro mástiles (en las
## jardineras de las esquinas) y cables combados entre ellos, con pocas luces reales.
func _festoon(r: Rect2) -> void:
	var top := 2.45
	var corners := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
	var steel := _mat("pole", Color("#2B3446"), 0.5, 0.6)
	var mid_w: Vector2 = (corners[0] + corners[3]) / 2.0
	var mid_e: Vector2 = (corners[1] + corners[2]) / 2.0
	for c in corners + [mid_w, mid_e]:
		_cyl(p3(c, top / 2.0), 0.03, 0.035, top, steel, 8)
	var bulb := _emit("bulb", Color(2.4, 1.7, 0.8))
	var wire := _mat("dark", C_DARK, 0.4, 0.4)
	# Perímetro y un tramo central de oeste a este, con un mástil en cada extremo.
	var spans := [[corners[0], corners[1]], [corners[3], corners[2]], [corners[0], mid_w], [mid_w, corners[3]], [corners[1], mid_e], [mid_e, corners[2]], [mid_w, mid_e]]
	for sp in spans:
		var a: Vector2 = sp[0]
		var b: Vector2 = sp[1]
		var n := int(a.distance_to(b) / 40.0)
		var prev := p3(a, top)
		for i in range(1, n + 1):
			var t := float(i) / float(n)
			var cur := p3(a.lerp(b, t), top - 0.45 * 4.0 * t * (1.0 - t))
			var seg := _box3((prev + cur) / 2.0, Vector3(0.012, 0.012, prev.distance_to(cur)), wire)
			seg.basis = Basis.looking_at(cur - prev, Vector3.UP)
			if i < n:
				_ball(cur - Vector3(0, 0.05, 0), 0.045, bulb)
			prev = cur
	# Luces reales: pocas y cálidas, a media altura de los cables.
	for c in [r.get_center(), r.position.lerp(Vector2(r.end.x, r.position.y), 0.5) + Vector2(0, 120), r.position.lerp(Vector2(r.position.x, r.end.y), 0.5) + Vector2(140, 120), Vector2(r.end.x, r.get_center().y) + Vector2(-160, 180)]:
		var o := OmniLight3D.new()
		o.position = p3(c, 2.0)
		o.light_color = Color("#FFC27A")
		o.light_energy = 1.1
		o.omni_range = 4.2
		o.omni_attenuation = 1.3
		o.light_cull_mask = 1
		add_child(o)

func _desk(r: Rect2, face: String, top_col: Color, h := 0.74) -> void:
	_rbox(r, h - 0.04, 0.04, _mat("top" + top_col.to_html(), top_col, 0.35))
	var back := Rect2(r.position.x + 4, r.position.y + 2, r.size.x - 8, 6) if face == "s" else Rect2(r.position.x + 4, r.end.y - 8, r.size.x - 8, 6)
	_rbox(back, 0.1, h - 0.14, _mat("dark", C_DARK, 0.4, 0.4))
	for x in [r.position.x + 4, r.end.x - 10]:
		_rbox(Rect2(x, r.position.y + 4, 6, r.size.y - 8), 0.0, h - 0.04, _mat("dark", C_DARK, 0.4, 0.4))

func _monitor(c: Vector2, face: String, scale := 1.0) -> void:
	var w := 0.5 * scale
	var pos := p3(c)
	_box3(pos + Vector3(0, 0.82, 0), Vector3(0.06, 0.16, 0.06), _mat("dark", C_DARK, 0.4, 0.4))
	_box3(pos + Vector3(0, 1.02, 0), Vector3(w, 0.3 * scale, 0.03), _mat("bezel", Color("#0B0F17"), 0.3, 0.3))
	var dz := 0.018 if face == "s" else -0.018
	_box3(pos + Vector3(0, 1.02, dz), Vector3(w - 0.04, 0.3 * scale - 0.04, 0.01), _emit("screen", C_SCREEN))

func _lamp(c: Vector2) -> void:
	var pos := p3(c)
	_cyl(pos + Vector3(0, 0.8, 0), 0.06, 0.06, 0.02, _mat("brass", Color("#B08D57"), 0.3, 0.9))
	_cyl(pos + Vector3(0, 0.98, 0), 0.01, 0.01, 0.34, _mat("brass", Color("#B08D57"), 0.3, 0.9))
	_cyl(pos + Vector3(0, 1.18, 0), 0.07, 0.12, 0.13, _emit("lampshade", Color(2.2, 1.6, 0.9)))
	var light := OmniLight3D.new()
	light.position = pos + Vector3(0, 1.1, 0.1)
	light.light_color = Color("#FFC98A")
	light.light_energy = 1.6
	light.omni_range = 3.2
	light.shadow_enabled = not mobile
	add_child(light)

func _chair(c: Vector2, face: String, col := C_FABRIC, scale := 1.0) -> void:
	var pos := p3(c)
	_cyl(pos + Vector3(0, 0.03, 0), 0.24 * scale, 0.24 * scale, 0.03, _mat("dark", C_DARK, 0.4, 0.4), 5)
	_cyl(pos + Vector3(0, 0.24, 0), 0.025, 0.025, 0.4, _mat("alu", C_METAL, 0.3, 0.8))
	_box3(pos + Vector3(0, 0.46, 0), Vector3(0.44, 0.08, 0.42) * scale, _mat("fab" + col.to_html(), col, 0.8))
	var back_dz := -0.2 if face == "s" else 0.2
	var back := _box3(pos + Vector3(0, 0.78 * scale, back_dz * scale), Vector3(0.42 * scale, 0.55 * scale, 0.07), _mat("fab" + col.to_html(), col, 0.8))
	back.rotation.x = 0.12 if face == "s" else -0.12

func _sofa(r: Rect2, face: String, col: Color) -> void:
	var mat := _mat("sofa" + col.to_html(), col, 0.85)
	_rbox(r, 0.08, 0.32, mat)
	var back_r := Rect2(r.position.x, r.position.y, 16, r.size.y) if face == "e" else Rect2(r.end.x - 16, r.position.y, 16, r.size.y)
	if face == "s":
		back_r = Rect2(r.position.x, r.position.y, r.size.x, 14)
	elif face == "n":
		back_r = Rect2(r.position.x, r.end.y - 14, r.size.x, 14)
	_rbox(back_r, 0.08, 0.75, mat)
	_rbox(r.grow(-6), 0.4, 0.1, _mat("cushion" + col.to_html(), col.lightened(0.12), 0.9))
	_rbox(r, 0.0, 0.08, _mat("dark", C_DARK, 0.4, 0.4))

func _desk_pod(r: Rect2) -> void:
	# Dos filas de puestos enfrentados con mampara central, pantallas y sillas.
	var mid := r.get_center().y
	_rbox(Rect2(r.position.x, r.position.y + 22, r.size.x, r.size.y - 44), 0.7, 0.04, _mat("top_white", Color("#EEF2F6"), 0.3))
	_rbox(Rect2(r.position.x + 4, mid - 2, r.size.x - 8, 4), 0.74, 0.32, _mat("screen_div", Color("#7C8DA6"), 0.8))
	for x in [r.position.x + 6, r.end.x - 12]:
		_rbox(Rect2(x, r.position.y + 24, 6, r.size.y - 48), 0.0, 0.7, _mat("alu", C_METAL, 0.3, 0.8))
	for i in 2:
		var x2 := r.position.x + r.size.x * (0.27 + 0.46 * i)
		_monitor(Vector2(x2, mid - 12), "n")
		_monitor(Vector2(x2, mid + 12), "s")
		_chair(Vector2(x2, r.position.y + 8), "s")
		_chair(Vector2(x2, r.end.y - 8), "n")

func _plant(c: Vector2, h: float) -> void:
	var pos := p3(c)
	_cyl(pos + Vector3(0, h * 0.35, 0), 0.17, 0.13, h * 0.7, _mat("pot", Color("#E7E1D6"), 0.35), 20)
	for i in 6:
		var ang := TAU * i / 6.0
		_ball(pos + Vector3(cos(ang) * 0.12, h * 0.95 + _rng.randf() * 0.25, sin(ang) * 0.12), 0.16 + _rng.randf() * 0.06, _leaf())
	_ball(pos + Vector3(0, h * 1.3, 0), 0.18, _leaf())

# ── letreros y luces ─────────────────────────────────────────────────────────

func _signage() -> void:
	for room in OfficeLayout.rooms():
		if not room.get("label", true):
			continue
		var r: Rect2 = room["rect"]
		var label := Label3D.new()
		label.text = str(room["name"])
		label.font_size = 64
		label.pixel_size = 0.0045
		label.modulate = Color(1, 1, 1, 0.16)
		label.outline_size = 0
		label.shaded = false
		label.rotation.x = -PI / 2.0
		label.position = p3(Vector2(r.get_center().x, r.end.y - 84), 0.012)
		label.double_sided = false
		add_child(label)
	# Salida de emergencia sobre la recepción.
	var exit := Label3D.new()
	exit.text = "SALIDA"
	exit.font_size = 48
	exit.pixel_size = 0.004
	exit.modulate = Color(0.4, 2.2, 0.8)
	exit.shaded = false
	exit.position = p3(Vector2(-620, 640), 2.35)
	exit.rotation.y = PI / 2.0
	add_child(exit)

## Luces de techo por sala: una rejilla de focos según su tamaño, del color de la sala.
## Sombras solo en el primer foco de las salas marcadas (y nunca en móvil).
func _room_lights() -> void:
	for room in OfficeLayout.rooms():
		var r: Rect2 = room["rect"]
		var nx := maxi(1, int(round(r.size.x / 420.0)))
		var ny := maxi(1, int(round(r.size.y / 420.0)))
		var shadows: bool = room.get("shadows", false)
		if room.get("outdoor", false):
			# Exterior de noche: sin focos de techo; un relleno frío de luna y ciudad
			# (las guirnaldas ponen el tono cálido).
			var moon := OmniLight3D.new()
			moon.position = p3(r.get_center(), 4.5)
			moon.light_color = Color(str(room.get("light", "#9DB3FF")))
			moon.light_energy = 0.7
			moon.omni_range = 7.5
			moon.omni_attenuation = 0.8
			moon.light_cull_mask = 1
			add_child(moon)
			continue
		for iy in ny:
			for ix in nx:
				var c := r.position + Vector2(r.size.x * (ix + 0.5) / nx, r.size.y * (iy + 0.5) / ny)
				var o := OmniLight3D.new()
				o.position = p3(c, 2.3)
				o.light_color = Color(str(room.get("light", "#FFFFFF")))
				o.light_energy = float(room.get("energy", 1.25))
				o.omni_range = clampf(maxf(r.size.x / nx, r.size.y / ny) / 100.0 * 0.95, 3.0, 6.5)
				o.omni_attenuation = 1.2
				o.shadow_enabled = shadows and ix == 0 and iy == 0 and not mobile
				o.light_cull_mask = 1   # no ilumina la ciudad (capa 2): solo la oficina
				add_child(o)

# ── materiales y texturas ───────────────────────────────────────────────────

func _mat(key: String, col: Color, rough := 0.5, metal := 0.0) -> StandardMaterial3D:
	var k := key + col.to_html() + str(rough) + str(metal)
	if not _mats.has(k):
		var m := StandardMaterial3D.new()
		m.albedo_color = col
		m.roughness = rough
		m.metallic = metal
		_mats[k] = m
	return _mats[k]

func _emit(key: String, col: Color) -> StandardMaterial3D:
	var k := "emit_" + key + str(col)
	if not _mats.has(k):
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(col.r, col.g, col.b).clamp() * 0.4
		m.emission_enabled = true
		m.emission = Color(minf(col.r, 1.0), minf(col.g, 1.0), minf(col.b, 1.0))
		m.emission_energy_multiplier = maxf(maxf(col.r, col.g), col.b) * 0.9
		_mats[k] = m
	return _mats[k]

func _glass() -> StandardMaterial3D:
	if not _mats.has("glass"):
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.62, 0.8, 0.95, 0.18)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.roughness = 0.05
		m.metallic = 0.2
		m.metallic_specular = 0.9
		_mats["glass"] = m
	return _mats["glass"]

func _leaf() -> StandardMaterial3D:
	var i := _rng.randi() % 3
	return _mat("leaf%d" % i, C_LEAF.lightened(0.08 * i), 0.7)

func _skyline_mat() -> Material:
	if not _mats.has("sky"):
		var m := ShaderMaterial.new()
		m.shader = preload("res://shaders/skyline_window.gdshader")
		_mats["sky"] = m
	return _mats["sky"]

func _tex_tiles(base: Color, joint: Color, tiles: int, noise: float, veins := false, perforated := false) -> ImageTexture:
	var n := 128
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	var cell := n / tiles
	var tone := []
	for i in tiles * tiles:
		tone.append(_rng.randf_range(-noise, noise))
	for y in n:
		for x in n:
			var t: float = tone[(y / cell) * tiles + (x / cell)]
			var c := base.lightened(t) if t > 0 else base.darkened(-t)
			c = c.darkened(_rng.randf() * noise * 0.6)
			if veins:
				var v := sin(x * 0.09 + sin(y * 0.05) * 3.0 + y * 0.03)
				if v > 0.92:
					c = c.darkened(0.12)
			if perforated and (x % 8 == 4) and (y % 8 == 4):
				c = joint
			if x % cell == 0 or y % cell == 0:
				c = joint
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)

func _tex_planks(base: Color, plank_h := 16) -> ImageTexture:
	var n := 128
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	var tones := []
	var offsets := []
	for i in n / plank_h + 1:
		tones.append(_rng.randf_range(-0.08, 0.08))
		offsets.append(_rng.randi() % n)
	for y in n:
		var row := y / plank_h
		for x in n:
			var t: float = tones[row]
			var c := base.lightened(t) if t > 0 else base.darkened(-t)
			c = c.darkened(0.06 * (0.5 + 0.5 * sin(x * 0.35 + y * 1.7 + row * 4.0)))
			if y % plank_h == 0 or (x + offsets[row]) % n == 0:
				c = base.darkened(0.4)
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)

func _tex_terrazzo(base: Color) -> ImageTexture:
	var n := 128
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	img.fill(base)
	var chips := [Color("#B45309"), Color("#475569"), Color("#E5E7EB"), Color("#9A3412"), Color("#64748B")]
	for i in 420:
		var col: Color = chips[_rng.randi() % chips.size()]
		var x := _rng.randi() % n
		var y := _rng.randi() % n
		var s := 1 + _rng.randi() % 2
		img.fill_rect(Rect2i(x, y, s, s), col)
	return ImageTexture.create_from_image(img)
