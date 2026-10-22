class_name World3DView
extends CanvasLayer
## Vista 3D de la exploración, dibujada detrás del juego 2D (capa -1).
##
## El juego sigue siendo 2D por dentro (servidor, colisiones, interacción, nombres,
## barras de canalización, minimapa): esta vista solo lo dibuja en 3D. Una cámara
## ortográfica inclinada PITCH_DEG grados sigue a la Camera2D del jugador, y el suelo
## 2D se proyecta al 3D estirando la profundidad (to_3d), de forma que cada punto del
## suelo aparece en pantalla exactamente donde el 2D lo tiene. Por eso los nombres,
## los clics sobre las pistas y las colisiones siguen cuadrando sin tocar la lógica.
##
## Dentro: la oficina (Office3D), un personaje de peluche 3D por jugador
## (PlushAvatar3D, animado con el movimiento que ya interpola el 2D), la linterna del
## jugador local (más grande con la visión nocturna del búho) y un aro ámbar con luz
## sobre cada pista.
##
## Línea de vista (LineOfSight, en el mapa 2D): durante la exploración solo se ve lo que
## el jugador local tiene a la vista. Lo demás se oscurece y los otros jugadores que
## quedan fuera se ocultan con un fundido corto (cuerpo 3D, su luz, nombre y barras).
##
## Silenciar al testigo: los cuerpos de snapshot.bodies se dibujan tumbados (BodyProp3D:
## estrellitas y cuenta atrás si está noqueado, ojos en X si está fuera de juego) con la
## misma línea de vista que los personajes, igual que la bolsa de "objetos caídos". Si
## eres fantasma no hay línea de vista (lo ves todo) y ves tus misiones fantasma; los
## vivos ven los pings de su fantasma (6 s) y las pistas que una misión hace brillar (20 s).

## Personaje 3D cargado por ruta (no por class_name): funciona aunque la caché de clases
## de .godot sea vieja, p. ej. al abrir el juego con el .bat sin pasar por el editor.
const Plush3D := preload("res://scripts/world3d/HeroAvatar3D.gd")   # hero; sin su GLB cae a PlushAvatar3D / vinilo
const U := 100.0             # px del mundo 2D por metro
const PITCH_DEG := 50.0
const LOCAL_LIGHT_RANGE := 4.6
const SIGHT_FADE_S := 0.2    # fundido al entrar o salir de la línea de vista
const GLOW_ENERGY := 0.45
const BAG_COLOR := Color("#9DB4FF")       # bolsa de objetos caídos (no es una pista del caso)
const REVEAL_COLOR := Color("#E9D5FF")    # pista que hace brillar una misión fantasma
const PING_COLOR := Color("#7DF9FF")      # ping fantasma
const TASK_COLOR := Color("#C084FC")      # misión fantasma
const GHOST_LIGHT_MULT := 2.2             # el fantasma ve con más luz

@export var map: CanvasItem                 # Main/Map (se oculta en menú y asamblea)
@export var players: PlayerSpawner          # Map/Players
@export var evidence_root: Node2D           # Map/Evidence
@export var always_on := false              # vistas previas y herramientas: dibuja siempre
## Algo tapa toda la pantalla (el ascensor de carga al empezar): no se dibuja.
var covered := false

var viewport: SubViewport
var camera: Camera3D
var office: Office3D
var actors: Node3D
var mobile := false

var _rect: TextureRect
var _avatars := {}        # instance_id del PlayerAvatar → {node, skin, look, last}
var _markers := {}        # instance_id de la pista → {node, light, ring}
var _local_light: OmniLight3D
var _time := 0.0
var line_of_sight: LineOfSight
var _sight_on := false
var _bodies := {}         # id del cuerpo → BodyProp3D
var _beacons := {}        # clave → {root, mat, light, kind, until}

static func pitch() -> float:
	return deg_to_rad(PITCH_DEG)

## Punto del mundo 2D (px) → punto 3D (m) a la altura h.
static func to_3d(p: Vector2, h := 0.0) -> Vector3:
	return Vector3(p.x / U, h, p.y / (U * sin(pitch())))

## Alto en pantalla (px del mundo 2D, con zoom 1) de algo de h metros.
static func screen_height(h: float) -> float:
	return h * cos(pitch()) * U

func _ready() -> void:
	layer = -1
	add_to_group("world3d")
	mobile = OS.has_feature("mobile") or OS.has_feature("web")
	viewport = SubViewport.new()
	viewport.name = "Viewport3D"
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_2X if mobile else Viewport.MSAA_4X
	viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if not mobile else Viewport.SCREEN_SPACE_AA_DISABLED
	viewport.positional_shadow_atlas_size = 2048 if mobile else 4096
	add_child(viewport)
	_rect = TextureRect.new()
	_rect.name = "View"
	_rect.texture = viewport.get_texture()
	_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_rect)

	var env := WorldEnvironment.new()
	env.name = "WorldEnvironment"
	env.environment = _environment()
	viewport.add_child(env)
	var moon := DirectionalLight3D.new()
	moon.name = "Moon"
	moon.light_color = Color("#9DB3FF")
	moon.light_energy = 0.35
	moon.shadow_opacity = 0.55
	moon.rotation = Vector3(deg_to_rad(-48), deg_to_rad(160), 0)
	moon.shadow_enabled = true
	moon.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	moon.directional_shadow_max_distance = 40.0
	viewport.add_child(moon)
	# Relleno suave desde la cámara: que las caras de muros y muebles no queden negras.
	var fill := DirectionalLight3D.new()
	fill.name = "Fill"
	fill.light_color = Color("#FFE9D2")
	fill.light_energy = 0.35
	fill.rotation = Vector3(deg_to_rad(-35), deg_to_rad(-15), 0)
	fill.shadow_enabled = false
	fill.light_specular = 0.2
	viewport.add_child(fill)

	office = Office3D.new()
	office.name = "Office"
	viewport.add_child(office)
	var city := City3D.new()
	city.name = "City"
	viewport.add_child(city)
	actors = Node3D.new()
	actors.name = "Actors"
	viewport.add_child(actors)

	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.rotation = Vector3(-pitch(), 0, 0)
	camera.near = 0.5
	camera.far = 260.0
	camera.current = true
	viewport.add_child(camera)

	_local_light = OmniLight3D.new()
	_local_light.name = "Flashlight"
	_local_light.light_color = Color("#E6EEFF")
	_local_light.light_energy = 1.5
	_local_light.omni_range = LOCAL_LIGHT_RANGE
	_local_light.omni_attenuation = 1.4
	_local_light.shadow_enabled = not mobile
	_local_light.visible = false
	viewport.add_child(_local_light)

	line_of_sight = LineOfSight.new()
	if map:
		map.add_child.call_deferred(line_of_sight)

func _environment() -> Environment:
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("#04060B")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("#8C9AC0")
	e.ambient_light_energy = 0.75
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	e.tonemap_exposure = 0.95
	e.tonemap_white = 6.0
	if RenderingServer.get_rendering_device() == null:   # OpenGL (compatibilidad)
		e.tonemap_exposure = 0.55   # el renderizador de compatibilidad ilumina bastante más
	e.glow_enabled = true
	e.glow_intensity = 0.55
	e.glow_bloom = 0.0
	e.glow_hdr_threshold = 1.3
	e.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	if not mobile:
		e.ssao_enabled = true
		e.ssao_radius = 0.9
		e.ssao_intensity = 1.6
	# Niebla de altura: la calle, 14 pisos más abajo, se hunde en azul noche.
	e.fog_enabled = true
	e.fog_light_color = Color("#1E3460")
	e.fog_light_energy = 1.0
	e.fog_density = 0.0
	e.fog_height = -3.0
	e.fog_height_density = 0.00045
	e.adjustment_enabled = true
	e.adjustment_contrast = 1.06
	e.adjustment_saturation = 1.08
	return e

func _process(delta: float) -> void:
	_time += delta
	# Solo se dibuja durante la exploración (en el menú y la asamblea no se ve).
	var exploring := PhaseViewController.view_for(GameState.phase()) == PhaseViewController.VIEW_EXPLORATION
	var on := (exploring or always_on) and (map == null or map.is_visible_in_tree()) and not covered
	_rect.visible = on
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED
	if not on:
		_set_sight_on(false)
		return
	_sync_camera()
	_sync_avatars(delta)
	_sync_bodies(delta)
	_sync_evidence()
	_sync_beacons()

## La cámara 3D encuadra exactamente lo que encuadra la Camera2D.
func _sync_camera() -> void:
	var root := get_viewport()
	var visible_size := root.get_visible_rect().size
	_rect.position = Vector2.ZERO
	_rect.size = visible_size
	var px := Vector2i(get_window().size)
	if mobile:
		px = Vector2i(Vector2(px) * 0.75)
	if viewport.size != px and px.x > 0 and px.y > 0:
		viewport.size = px
	var xf := root.get_canvas_transform()
	var zoom := xf.x.length()
	var center := xf.affine_inverse() * (visible_size / 2.0)
	camera.size = visible_size.y / (zoom * U)
	var forward := -camera.global_transform.basis.z
	camera.position = to_3d(center) - forward * 40.0

func _sync_avatars(delta: float) -> void:
	if players == null:
		return
	var seen := {}
	var local_found := false
	var local := _local_avatar()
	if local:
		line_of_sight.set_viewer(local.global_position)
	# Los fantasmas no tienen línea de vista: lo ven todo.
	_set_sight_on(local != null and not GameState.is_ghost())
	var bodies := PackedVector2Array()
	for child in players.get_children():
		if not child is PlayerAvatar:
			continue
		var avatar: PlayerAvatar = child
		var id := avatar.get_instance_id()
		seen[id] = true
		var entry: Dictionary = _avatars.get(id, {})
		# Línea de vista: el local siempre se ve; los demás, solo si están a la vista.
		var in_sight := not _sight_on or avatar.is_local or line_of_sight.can_see(avatar.global_position)
		if entry.is_empty():
			avatar.set_sight(1.0 if in_sight else 0.0, true)   # al aparecer, sin fundido
		else:
			avatar.set_sight(move_toward(avatar.sight, 1.0 if in_sight else 0.0, delta / SIGHT_FADE_S))
		if _sight_on and in_sight:
			bodies.append(avatar.global_position)
		var look: Dictionary = avatar.chibi.look if avatar.chibi else {}
		if entry.is_empty() or entry["skin"] != avatar.skin_id or entry["look"] != look:
			if entry.has("node"):
				entry["node"].queue_free()
			var model: Plush3D = Plush3D.new()
			model.name = "Avatar_" + avatar.player_id
			actors.add_child(model)
			model.build(avatar.skin_id, look)
			model.face(0.0)
			if not entry.has("light") and not avatar.is_local:
				var glow := OmniLight3D.new()
				glow.light_color = Color("#C9D6FF")
				glow.light_energy = GLOW_ENERGY
				glow.omni_range = 1.9
				actors.add_child(glow)
				entry["light"] = glow
			entry["node"] = model
			entry["skin"] = avatar.skin_id
			entry["look"] = look.duplicate()
			entry["last"] = avatar.global_position
			_avatars[id] = entry
			avatar.use_3d_body(screen_height(Plush3D.HEIGHT) + 6.0)
		var node: Plush3D = entry["node"]
		var pos2: Vector2 = avatar.global_position
		var step: Vector2 = pos2 - entry["last"]
		entry["last"] = pos2
		node.position = to_3d(pos2)
		node.visible = avatar.is_visible_in_tree() and avatar.sight > 0.01
		node.set_alpha(avatar.modulate.a * avatar.sight)
		var speed := step.length() / maxf(delta, 0.0001)
		var dir := Vector3(step.x, 0.0, step.y / sin(pitch()))
		node.animate(delta, dir, speed / maxf(avatar.speed, 1.0))
		if entry.has("light"):
			entry["light"].position = to_3d(pos2, 1.3)
			entry["light"].visible = node.visible
			entry["light"].light_energy = GLOW_ENERGY * avatar.sight
		if avatar.is_local:
			local_found = true
			_local_light.position = to_3d(pos2, 1.5)
			_local_light.omni_range = LOCAL_LIGHT_RANGE * Abilities.flashlight_multiplier() * (GHOST_LIGHT_MULT if GameState.is_ghost() else 1.0)
	_local_light.visible = local_found
	if _sight_on:
		line_of_sight.set_bodies(bodies)
	for id in _avatars.keys():
		if not seen.has(id):
			var e: Dictionary = _avatars[id]
			e["node"].queue_free()
			if e.has("light"):
				e["light"].queue_free()
			_avatars.erase(id)


func _local_avatar() -> PlayerAvatar:
	for child in players.get_children():
		if child is PlayerAvatar and child.is_local:
			return child
	return null

## Enciende o apaga la línea de vista. Al apagarla todos vuelven a verse; al cambiar,
## sin fundido (el primer cuadro de la exploración ya oculta a quien no se ve).
func _set_sight_on(on: bool) -> void:
	if on == _sight_on:
		return
	_sight_on = on
	line_of_sight.active = on
	if players == null:
		return
	for child in players.get_children():
		if child is PlayerAvatar:
			var avatar: PlayerAvatar = child
			var in_sight := not on or avatar.is_local or line_of_sight.can_see(avatar.global_position)
			avatar.set_sight(1.0 if in_sight else 0.0, true)

## Cada pista: aro ámbar en el suelo que late y una luz cálida; más intensa si
## percibes algo en ella. El marcador 2D se oculta (ya se ve en 3D).
func _sync_evidence() -> void:
	if evidence_root == null:
		return
	var seen := {}
	var reveals := GameState.active_reveals()
	for child in evidence_root.get_children():
		if not child is InteractableEvidence:
			continue
		var ev: InteractableEvidence = child
		var id := ev.get_instance_id()
		seen[id] = true
		if not _markers.has(id):
			for c in ev.get_children():
				if c is CanvasItem and not c is CanvasLayer:
					c.visible = false
			_markers[id] = _make_marker(ev)
		var m: Dictionary = _markers[id]
		var strong := ev.has_perceivable_contents()
		var pulse := 0.5 + 0.5 * sin(_time * 3.0 + float(id % 7))
		# Pista que una misión fantasma hace brillar: aro grande, blanco violeta y fuerte.
		var revealed := reveals.has(ev.interactable_id)
		m["root"].position = to_3d(ev.global_position)
		var shown := ev.is_visible_in_tree()
		if ev is BodyContainers.BodyBag:
			# Los objetos caídos se ven como los cuerpos: solo si están a la vista.
			shown = shown and (not _sight_on or line_of_sight.can_see(ev.global_position)) and strong
		m["root"].visible = shown or revealed
		m["light"].light_energy = (1.3 if strong else 0.55) * (0.75 + 0.25 * pulse) * (3.0 if revealed else 1.0)
		m["ring"].scale = Vector3.ONE * (1.0 + 0.08 * pulse) * (1.8 + 0.3 * pulse if revealed else 1.0)
		m["mat"].emission = REVEAL_COLOR if revealed else m["base"]
		m["mat"].emission_energy_multiplier = (3.2 if strong else 1.4) * (0.7 + 0.3 * pulse) * (2.0 if revealed else 1.0)
	for id in _markers.keys():
		if not seen.has(id):
			_markers[id]["root"].queue_free()
			_markers.erase(id)

func _make_marker(ev: InteractableEvidence) -> Dictionary:
	var root := Node3D.new()
	root.name = "Clue_" + str(ev.name)
	actors.add_child(root)
	var bag := ev is BodyContainers.BodyBag
	var base := BAG_COLOR if bag else Color("#FFB547")
	var mat := StandardMaterial3D.new()
	mat.albedo_color = base.darkened(0.15)
	mat.emission_enabled = true
	mat.emission = base
	mat.emission_energy_multiplier = 2.0
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	var r := clampf(ev.radius / U, 0.25, 0.6)
	torus.inner_radius = r * 0.82
	torus.outer_radius = r
	torus.rings = 48
	ring.mesh = torus
	ring.material_override = mat
	ring.position.y = 0.02
	ring.scale = Vector3(1, 0.3, 1)
	root.add_child(ring)
	var gem := MeshInstance3D.new()
	var prism := PrismMesh.new()
	prism.size = Vector3(0.14, 0.2, 0.14)
	gem.mesh = prism
	gem.material_override = mat
	gem.position.y = 0.9
	gem.rotation.z = PI
	root.add_child(gem)
	var light := OmniLight3D.new()
	light.light_color = Color("#FFB547")
	light.omni_range = 1.6
	light.position.y = 0.5
	root.add_child(light)
	if bag:
		light.light_color = BAG_COLOR
	return {"root": root, "ring": ring, "light": light, "mat": mat, "gem": gem, "base": base}

## Cuerpos en el suelo (snapshot.bodies sin reportar), con la línea de vista.
func _sync_bodies(delta: float) -> void:
	var seen := {}
	var now := Network.server_time_ms()
	for b in GameState.bodies():
		if bool(b.get("reported", false)):
			continue
		var id := str(b.get("id", ""))
		seen[id] = true
		var owner_id := str(b.get("playerId", ""))
		var kind := str(b.get("kind", Protocol.BODY_DEAD))
		var prop: BodyProp3D = _bodies.get(id)
		if prop == null:
			var p := GameState.public_player(owner_id)
			var skin := str(p.get("skinId", ""))
			if skin == "":
				skin = SkinCatalog.fallback_for(owner_id)
			prop = BodyProp3D.new()
			prop.name = "Body_" + owner_id
			actors.add_child(prop)
			prop.build(id, owner_id, skin, p.get("look") if p.get("look") is Dictionary else {}, kind)
			_bodies[id] = prop
		prop.set_kind(kind)
		prop.until_ms = int(b["until"]) if b.get("until") != null else -1
		var pos := Protocol.vec2_from(b.get("position", {}))
		prop.position = to_3d(pos)
		var in_sight := not _sight_on or line_of_sight.can_see(pos)
		var a := move_toward(prop.get_meta("sight", 1.0 if in_sight else 0.0), 1.0 if in_sight else 0.0, delta / SIGHT_FADE_S)
		prop.set_meta("sight", a)
		prop.visible = a > 0.01
		prop.set_alpha(a)
		prop.tick(delta, now)
	for id in _bodies.keys():
		if not seen.has(id):
			_bodies[id].queue_free()
			_bodies.erase(id)

## Cuerpo 3D dibujado para un cuerpo de snapshot.bodies (o null). Para pruebas.
func body_prop(body_id: String) -> BodyProp3D:
	return _bodies.get(body_id)

## Pings de fantasma (columna de luz cian que late), misiones fantasma (rombo violeta,
## solo si eres fantasma) y balizas de pistas reveladas sin marcador.
func _sync_beacons() -> void:
	var want := {}
	for p in GameState.active_pings():
		want["ping:%s:%d" % [p["by"], int(p["until"])]] = {"kind": "ping", "pos": p["position"]}
	if GameState.is_ghost():
		for t in GameState.ghost_tasks():
			if not bool(t.get("done", false)):
				want["task:" + str(t.get("id", ""))] = {"kind": "task", "pos": Protocol.vec2_from(t.get("position", {}))}
	for key in want.keys():
		var w: Dictionary = want[key]
		if not _beacons.has(key):
			_beacons[key] = _make_beacon(w["kind"])
		var b: Dictionary = _beacons[key]
		var pulse := 0.5 + 0.5 * sin(_time * (6.0 if w["kind"] == "ping" else 2.5))
		b["root"].position = to_3d(w["pos"])
		b["ring"].scale = Vector3(1, 0.3, 1) * (0.8 + 0.5 * pulse)
		b["mat"].emission_energy_multiplier = 2.5 + 2.5 * pulse
		b["light"].light_energy = 1.2 + 1.2 * pulse
		b["gem"].rotation.y = _time * 2.0
	for key in _beacons.keys():
		if not want.has(key):
			_beacons[key]["root"].queue_free()
			_beacons.erase(key)

## Baliza: aro en el suelo, columna o rombo y luz.
func _make_beacon(kind: String) -> Dictionary:
	var col := PING_COLOR if kind == "ping" else TASK_COLOR
	var root := Node3D.new()
	root.name = "Beacon_" + kind
	actors.add_child(root)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.emission_enabled = true
	mat.emission = col
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color.a = 0.85
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.42
	torus.outer_radius = 0.5
	torus.rings = 48
	ring.mesh = torus
	ring.material_override = mat
	ring.position.y = 0.03
	root.add_child(ring)
	var gem := MeshInstance3D.new()
	if kind == "ping":
		var beam := CylinderMesh.new()
		beam.top_radius = 0.05
		beam.bottom_radius = 0.12
		beam.height = 2.4
		gem.mesh = beam
		gem.position.y = 1.2
	else:
		var prism := PrismMesh.new()
		prism.size = Vector3(0.22, 0.3, 0.22)
		gem.mesh = prism
		gem.position.y = 1.0
		gem.rotation.z = PI
	gem.material_override = mat
	root.add_child(gem)
	var light := OmniLight3D.new()
	light.light_color = col
	light.omni_range = 2.2
	light.position.y = 0.6
	root.add_child(light)
	return {"root": root, "ring": ring, "light": light, "mat": mat, "gem": gem, "kind": kind}

## Balizas vivas (pings y misiones): para pruebas.
func beacon_keys() -> Array:
	return _beacons.keys()
