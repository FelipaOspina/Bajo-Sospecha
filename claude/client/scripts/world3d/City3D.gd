class_name City3D
extends Node3D
## El exterior del piso 14: la torre de NexusCore baja hasta la calle y alrededor se
## ve la ciudad de noche desde arriba (calles con farolas y coches, azoteas de las
## torres vecinas con antenas que parpadean y un helipuerto). Todo queda por debajo
## del suelo de la oficina, así que nunca tapa a los jugadores; la niebla de altura
## (World3DView) lo hunde en azul para que se note la caída.
##
## Hecho con cajas y texturas generadas: ningún modelo externo.

const GROUND_Y := -42.0
const BLOCK := 34.0          # manzana + calle (m)
const ROAD := 9.0            # ancho de la calle (m)
const CARS := 36
const FACADE := preload("res://shaders/city_facade.gdshader")

var mobile := false
var _rng := RandomNumberGenerator.new()
var _mats := {}
var _cars: Array = []        # {node, axis, lane, speed, pos}
var _beacons: Array[StandardMaterial3D] = []
var _time := 0.0
var _origin := Vector2.ZERO  # centro de la rejilla de calles (x, z)

func _ready() -> void:
	mobile = OS.has_feature("mobile") or OS.has_feature("web")
	_rng.seed = 2614
	build()

func build() -> void:
	for c in get_children():
		c.queue_free()
	_cars.clear()
	_beacons.clear()
	var b := OfficeLayout.BOUNDS
	var p0 := World3DView.to_3d(b.position)
	var p1 := World3DView.to_3d(b.end)
	var foot := Rect2(p0.x, p0.z, p1.x - p0.x, p1.z - p0.z)   # huella de la torre (x, z) en m
	_origin = foot.get_center()
	_tower(foot)
	_ground()
	_neighbours(foot.grow(7.0))
	_traffic()

func _process(delta: float) -> void:
	_time += delta
	var half := BLOCK * 4.0
	for car in _cars:
		car["pos"] += car["speed"] * delta
		if car["pos"] > half:
			car["pos"] -= half * 2.0
		elif car["pos"] < -half:
			car["pos"] += half * 2.0
		var n: Node3D = car["node"]
		if car["axis"] == 0:
			n.position = Vector3(_origin.x + car["pos"], GROUND_Y + 0.35, car["lane"])
		else:
			n.position = Vector3(car["lane"], GROUND_Y + 0.35, _origin.y + car["pos"])
	var blink := 0.5 + 0.5 * sin(_time * 3.2)
	for m in _beacons:
		m.emission_energy_multiplier = 0.4 + 4.0 * blink * blink

# ── torre propia ─────────────────────────────────────────────────────────────

func _tower(foot: Rect2) -> void:
	# Fachada de la torre: de la calle hasta justo bajo el suelo de la oficina.
	var h := -GROUND_Y - 0.06
	_box(Vector3(foot.get_center().x, GROUND_Y + h / 2.0, foot.get_center().y), Vector3(foot.size.x, h, foot.size.y), _mat("tower", Color("#151B27"), 0.4, 0.3))
	_windows(Vector3(foot.get_center().x, GROUND_Y, foot.end.y + 0.02), foot.size.x, h - 0.3, "own", 0.55)
	# Cornisa (borde de la terraza) alrededor del piso.
	_box(Vector3(foot.get_center().x, -0.12, foot.get_center().y), Vector3(foot.size.x + 1.2, 0.2, foot.size.y + 1.2), _mat("ledge", Color("#3A4356"), 0.5, 0.3))
	# Franjas de forjado cada 3,5 m: dan escala a la caída.
	var y := -3.5
	while y > GROUND_Y + 1.0:
		_box(Vector3(foot.get_center().x, y, foot.end.y + 0.03), Vector3(foot.size.x + 0.1, 0.25, 0.08), _mat("slab", Color("#202838"), 0.6))
		y -= 3.5

# ── calle ────────────────────────────────────────────────────────────────────

func _ground() -> void:
	var size := BLOCK * 10.0
	var mi := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(size, size)
	mi.mesh = plane
	var m := ShaderMaterial.new()
	m.shader = preload("res://shaders/city_ground.gdshader")
	m.set_shader_parameter("block", BLOCK)
	m.set_shader_parameter("road", ROAD)
	m.set_shader_parameter("origin", _origin)
	mi.material_override = m
	mi.layers = 2
	mi.position = Vector3(_origin.x, GROUND_Y, _origin.y)
	add_child(mi)

## Coches: luces blancas en un sentido, rojas en el otro, por el centro de las calles.
func _traffic() -> void:
	var count := CARS / 2 if mobile else CARS
	for i in count:
		var axis := i % 2
		var road := (_rng.randi() % 8) - 4
		var dir := 1.0 if _rng.randf() < 0.5 else -1.0
		var lane := (road + 0.5) * BLOCK - ROAD / 2.0 + (ROAD * 0.3 if dir > 0 else ROAD * 0.7)
		lane += _origin.y if axis == 0 else _origin.x
		var car := Node3D.new()
		add_child(car)
		var body := _box(Vector3.ZERO, Vector3(1.9, 0.6, 0.9) if axis == 0 else Vector3(0.9, 0.6, 1.9), _mat("car%d" % (i % 4), [Color("#1F2937"), Color("#7F1D1D"), Color("#E5E7EB"), Color("#1E3A8A")][i % 4], 0.3, 0.5), car)
		body.position.y = 0.0
		var front := Vector3(dir * 1.0, 0.05, 0.0) if axis == 0 else Vector3(0.0, 0.05, dir * 1.0)
		var back := -front
		_box(front, Vector3(0.12, 0.18, 0.7) if axis == 0 else Vector3(0.7, 0.18, 0.12), _glow("head", Color(2.6, 2.4, 1.9)), car)
		_box(back, Vector3(0.12, 0.18, 0.7) if axis == 0 else Vector3(0.7, 0.18, 0.12), _glow("tail", Color(2.4, 0.2, 0.15)), car)
		_cars.append({"node": car, "axis": axis, "lane": lane, "speed": dir * _rng.randf_range(6.0, 11.0), "pos": _rng.randf_range(-BLOCK * 4.0, BLOCK * 4.0)})

# ── torres vecinas ───────────────────────────────────────────────────────────

func _neighbours(keep_out: Rect2) -> void:
	var roof := _mat("roof", Color("#2A3140"), 0.7)
	var helipad_done := false
	for gx in range(-4, 5):
		for gz in range(-4, 5):
			# Cada manzana: 1 a 4 torres que no tocan la nuestra.
			var cell := Rect2(_origin.x + gx * BLOCK - BLOCK / 2.0 + ROAD / 2.0, _origin.y + gz * BLOCK - BLOCK / 2.0 + ROAD / 2.0, BLOCK - ROAD, BLOCK - ROAD)
			var parts := 1 + _rng.randi() % 3
			for k in parts:
				var w := cell.size.x / parts - 1.5
				var r := Rect2(cell.position.x + k * (cell.size.x / parts) + 0.75, cell.position.y + _rng.randf_range(0.5, 4.0), w, cell.size.y - _rng.randf_range(1.0, 8.0))
				if r.intersects(keep_out):
					continue
				# Las más cercanas, más bajas: nunca llegan a nuestro piso.
				var dist := (r.get_center() - _origin).length()
				var top := GROUND_Y + _rng.randf_range(8.0, 22.0) + clampf(dist * 0.12, 0.0, 16.0)
				top = minf(top, -4.0)
				var hgt := top - GROUND_Y
				_box(Vector3(r.get_center().x, GROUND_Y + hgt / 2.0, r.get_center().y), Vector3(r.size.x, hgt, r.size.y), _mat("tower", Color("#151B27"), 0.4, 0.3))
				_windows(Vector3(r.get_center().x, GROUND_Y, r.end.y + 0.02), r.size.x, hgt, "n%d" % (_rng.randi() % 3), 0.7)
				_box(Vector3(r.get_center().x, top + 0.15, r.get_center().y), Vector3(r.size.x + 0.4, 0.3, r.size.y + 0.4), roof)
				_rooftop(r, top + 0.3, not helipad_done and r.size.x > 12.0 and r.size.y > 12.0 and dist < 70.0)
				if not helipad_done and r.size.x > 12.0 and r.size.y > 12.0 and dist < 70.0:
					helipad_done = true

func _rooftop(r: Rect2, y: float, helipad: bool) -> void:
	var c := r.get_center()
	if helipad:
		var pad := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = minf(r.size.x, r.size.y) * 0.38
		cyl.bottom_radius = cyl.top_radius
		cyl.height = 0.1
		pad.mesh = cyl
		pad.material_override = _mat("pad", Color("#3F4A5C"), 0.6)
		pad.position = Vector3(c.x, y + 0.05, c.y)
		add_child(pad)
		var hl := Label3D.new()
		hl.text = "H"
		hl.font_size = 220
		hl.pixel_size = 0.02
		hl.modulate = Color(1.6, 1.4, 0.5)
		hl.shaded = false
		hl.rotation.x = -PI / 2.0
		hl.position = Vector3(c.x, y + 0.12, c.y)
		add_child(hl)
		for i in 8:
			var ang := TAU * i / 8.0
			_box(Vector3(c.x + cos(ang) * cyl.top_radius, y + 0.15, c.y + sin(ang) * cyl.top_radius), Vector3(0.3, 0.2, 0.3), _glow("pad_led", Color(0.3, 2.4, 0.8)))
		return
	# Máquinas de aire, depósito de agua y, a veces, una antena con luz roja.
	for i in 1 + _rng.randi() % 3:
		var sz := Vector3(_rng.randf_range(1.2, 3.0), _rng.randf_range(0.6, 1.4), _rng.randf_range(1.2, 3.0))
		var off := Vector2(_rng.randf_range(-0.3, 0.3) * r.size.x, _rng.randf_range(-0.3, 0.3) * r.size.y)
		_box(Vector3(c.x + off.x, y + sz.y / 2.0, c.y + off.y), sz, _mat("ac", Color("#5B6475"), 0.5, 0.5))
	if _rng.randf() < 0.45:
		var ah := _rng.randf_range(3.0, 6.0)
		_box(Vector3(c.x, y + ah / 2.0, c.y), Vector3(0.15, ah, 0.15), _mat("mast", Color("#9AA5B4"), 0.4, 0.7))
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.4, 0.05, 0.05)
		m.emission_enabled = true
		m.emission = Color(1.0, 0.1, 0.08)
		_beacons.append(m)
		var bulb := MeshInstance3D.new()
		var s := SphereMesh.new()
		s.radius = 0.28
		s.height = 0.56
		bulb.mesh = s
		bulb.material_override = m
		bulb.position = Vector3(c.x, y + ah + 0.2, c.y)
		add_child(bulb)

# ── utilidades ───────────────────────────────────────────────────────────────

func _box(center: Vector3, size: Vector3, mat: Material, parent: Node3D = self) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = center
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.layers = 2   # las luces de la oficina no la iluminan
	parent.add_child(mi)
	return mi

func _mat(key: String, col: Color, rough := 0.5, metal := 0.0) -> StandardMaterial3D:
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = col
		m.roughness = rough
		m.metallic = metal
		_mats[key] = m
	return _mats[key]

func _glow(key: String, col: Color) -> StandardMaterial3D:
	if not _mats.has("g_" + key):
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(col.r, col.g, col.b).clamp() * 0.5
		m.emission_enabled = true
		m.emission = Color(minf(col.r, 1.0), minf(col.g, 1.0), minf(col.b, 1.0))
		m.emission_energy_multiplier = maxf(maxf(col.r, col.g), col.b)
		_mats["g_" + key] = m
	return _mats["g_" + key]

## Fachada de oficinas de noche en la cara que mira a la cámara (+Z): ventanas
## encendidas al azar (shader procedural). Las otras caras no se ven nunca.
func _windows(base: Vector3, w: float, h: float, _key: String, lit: float) -> void:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(w, h)
	mi.mesh = q
	var m := ShaderMaterial.new()
	m.shader = FACADE
	m.set_shader_parameter("lit", lit * _rng.randf_range(0.6, 1.0))
	m.set_shader_parameter("seed", _rng.randf() * 100.0)
	mi.material_override = m
	mi.position = base + Vector3(0, h / 2.0, 0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.layers = 2
	add_child(mi)
