class_name PlushAvatar3D
extends Node3D
## Personaje 3D de peluche chibi (≈2,2 cabezas) de cada jugador: mapa, sala, menú,
## retratos y cuerpos. Modelos GLB por especie en assets/characters/<id>.glb (hoy
## generados en Blender con tools/_plush_build.py; se pueden cambiar por modelos de IA
## con el mismo esqueleto sin tocar este script). Si falta el GLB o no se puede leer,
## dibuja el muñeco de vinilo de antes (VinylAvatar3D) con la misma API.
##
## El GLB trae un esqueleto (Hips > Spine > Chest > Neck / ArmX > ElbowX > HandX;
## Hips > LegX > KneeX > FootX; Hips > Tail1..3) y mallas con piel (Body, Bag, Cap), así
## que rodillas, codos, sudadera y cola se doblan; aquí se posan los huesos a mano
## (paso, reposo, reacciones), sin clips de animación. Los colores no van horneados: cada vértice lleva máscaras
## (pelo claro / marca oscura / rosa) + oclusión, y aquí se pintan con los colores de la
## skin y de los cosméticos (shaders/plush_fur.gdshader, shaders/plush_eye.gdshader).
##
## Misma API pública que VinylAvatar3D: build, animate, face, set_alpha, react,
## is_reacting, happy_amount, rig_transform, set_knocked_face, HEIGHT, BODY_Y.
## Nunca muestra el rol: solo usa colores de la skin y de los cosméticos públicos.

const SIZE := 0.88              # escala del GLB en el juego (≈ el alto del muñeco de vinilo)
const HEIGHT := 1.34            # alto aproximado con orejas (m), para colocar el nombre encima
const BODY_Y := 0.40            # centro del cuerpo (reacciones, cuerpos tumbados)
const HEAD_Y := 0.84            # centro de la cabeza (retratos, encuadres de la cara)
const MOUTH_Y := 0.71           # boca (dar de comer a la mascota en la sala)
const HEAD_R := 0.44            # medio ancho de la cabeza (la parte más ancha)
const LEG := 0.191              # cadera -> tobillo
const ARM_IN := 0.16            # los brazos (modelados abiertos) se acercan al cuerpo
const GLB_DIR := "res://assets/characters/"

const FUR_SHADER := preload("res://shaders/plush_fur.gdshader")
const EYE_SHADER := preload("res://shaders/plush_eye.gdshader")

## Colores propios de cada especie (marcas, cejas, nariz) — nunca dependen del rol.
const SPECIES := {
	"zorro": {"mark": "#5E2C14", "brow": "#3A1C10", "nose": "#1E1414"},
	"gato": {"mark": "#5B6573", "brow": "#4B5563", "nose": "#E88A9E"},
	"pinguino": {"mark": "#1E293B", "brow": "#0F172A", "nose": "#F59E0B", "lid": "light"},
	"panda": {"mark": "#1A1A1E", "brow": "#18181B", "nose": "#18181B", "lid": "mark"},
	"leon": {"mark": "mane", "brow": "#7A3E12", "nose": "#8E4C3E"},
	"conejo": {"mark": "#D6CFD6", "brow": "#D4A5B5", "nose": "#F58FB0"},
	"oso": {"mark": "#3B1D0A", "brow": "#2E1607", "nose": "#1A1210"},
	"perro": {"mark": "#7A5232", "brow": "#5B3A1E", "nose": "#1A1210"},
	"lobo": {"mark": "#3F4552", "brow": "#374151", "nose": "#141418"},
	"tigre": {"mark": "#2A1A12", "brow": "#2A1A12", "nose": "#C0626A"},
	"mapache": {"mark": "#2A2F3A", "brow": "#2A2F3A", "nose": "#141418", "lid": "mark"},
	"buho": {"mark": "#4A3020", "brow": "#3F2A1A", "nose": "#F59E0B", "lid": "light"},
}

var skin_id := ""
var skin: Dictionary = {}

var _rig: Node3D
var _pivot: Node3D
var _model: Node3D
var _skel: Skeleton3D
var _bone := {}                 # nombre -> índice de hueso
var _rest := {}                 # índice -> reposo
var _eye_mat: ShaderMaterial
var _phase := 0.0
var _amp := 0.0
var _time := 0.0
var _yaw := 0.0
var _alpha := 1.0
var _react_kind := ""
var _react_t := 0.0
var _react_len := 1.0
var _happy := 0.0
var _ko := ""
var _blink_t := 0.0
var _blink_next := 2.0
var _glance := Vector2.ZERO
var _glance_target := Vector2.ZERO
var _glance_next := 1.5
var _rng := RandomNumberGenerator.new()
## Sin GLB: el muñeco de vinilo de siempre, al que se pasan todas las llamadas.
var _fallback: VinylAvatar3D

static var _scene_cache := {}
static var _mat_cache := {}
static var _alpha_shaders := {}

## Arma el modelo. look: cosméticos públicos (ropa, gorra, zapatillas, mochila).
func build(id: String, look: Dictionary = {}) -> void:
	for c in get_children():
		c.queue_free()
	_skel = null
	_fallback = null
	_model = null
	_bone.clear()
	_rest.clear()
	_react_kind = ""
	_happy = 0.0
	_ko = ""
	_alpha = 1.0
	skin_id = id
	skin = CosmeticCatalog.dress(SkinCatalog.skin(id), look)
	_rng.seed = hash(id) ^ get_instance_id()
	_blink_next = _rng.randf_range(0.8, 3.0)
	var sb: Array = skin.get("scale_body", [1.0, 1.0])
	var wide := float(sb[0]) if sb.size() > 0 else 1.0
	var tall := float(sb[1]) if sb.size() > 1 else 1.0

	_rig = Node3D.new()
	_rig.name = "Rig"
	add_child(_rig)
	_pivot = Node3D.new()
	_pivot.name = "Pivot"
	_pivot.scale = Vector3(lerpf(1.0, wide, 0.35), lerpf(1.0, tall, 0.5), lerpf(1.0, wide, 0.25)) * SIZE
	_rig.add_child(_pivot)
	var ps := _scene(id)
	if ps == null:
		_use_fallback(id, look)
		return
	_model = ps.instantiate()
	_pivot.add_child(_model)
	var sks := _model.find_children("*", "Skeleton3D", true, false)
	if sks.is_empty():
		push_warning("PlushAvatar3D: '%s' no tiene esqueleto" % id)
		_use_fallback(id, look)
		return
	_skel = sks[0]
	for i in _skel.get_bone_count():
		_bone[_skel.get_bone_name(i)] = i
		_rest[i] = _skel.get_bone_rest(i)
	var bag := _model.find_child("Bag", true, false) as Node3D
	if bag:
		bag.visible = skin.has("bag") and look.has("bag")
	var cap := _model.find_child("Cap", true, false) as Node3D
	if cap:
		cap.visible = str(skin.get("hat", "")) == "cap"
	_paint()
	pose(0.0, 0.0, 0.0)
	_apply_eyes()
	_apply_alpha()

func _use_fallback(id: String, look: Dictionary) -> void:
	for c in get_children():
		c.queue_free()
	_rig = null
	_pivot = null
	_model = null
	_skel = null
	_fallback = VinylAvatar3D.new()
	_fallback.name = "Vinyl"
	add_child(_fallback)
	_fallback.build(id, look)

## true si este personaje se dibuja con el GLB de peluche (false = vinilo de reserva).
func has_plush_model() -> bool:
	return _skel != null

## Modelo de la especie. Primero el GLB importado por el editor (.godot/imported: LOD,
## compresión); si el proyecto se abre sin haberlo importado nunca (p. ej. con el .bat,
## sin pasar por el editor) se lee el .glb crudo con GLTFDocument en tiempo de ejecución.
## null si no hay archivo o no se puede leer.
static func _scene(id: String) -> PackedScene:
	if _scene_cache.has(id):
		return _scene_cache[id]
	var path := GLB_DIR + id + ".glb"
	var ps: PackedScene = null
	if _is_imported(path):
		ps = load(path) as PackedScene
	if ps == null and FileAccess.file_exists(path):
		var bytes := FileAccess.get_file_as_bytes(path)
		var doc := GLTFDocument.new()
		var st := GLTFState.new()
		if not bytes.is_empty() and doc.append_from_buffer(bytes, path.get_base_dir(), st) == OK:
			var root := doc.generate_scene(st)
			if root:
				ps = PackedScene.new()
				_own(root, root)
				ps.pack(root)
				root.free()
	_scene_cache[id] = ps
	return ps

## El .glb tiene su versión importada lista (si no, load() solo daría errores).
static func _is_imported(path: String) -> bool:
	if not FileAccess.file_exists(path + ".import"):
		return ResourceLoader.exists(path)     # exportado: solo queda el recurso remapeado
	var cfg := ConfigFile.new()
	if cfg.load(path + ".import") != OK:
		return false
	var dest := str(cfg.get_value("remap", "path", ""))
	return dest != "" and FileAccess.file_exists(dest)

static func _own(n: Node, root: Node) -> void:
	for c in n.get_children():
		c.owner = root
		_own(c, root)

## Opacidad (desconexión, camuflaje): 1 = sólido.
func set_alpha(a: float) -> void:
	if _fallback:
		_fallback.set_alpha(a)
		return
	if is_equal_approx(a, _alpha):
		return
	_alpha = a
	_apply_alpha()

## velocity_dir: dirección de movimiento en el mundo 3D (y = 0). speed_ratio: 0..1.5.
func animate(delta: float, velocity_dir: Vector3, speed_ratio: float) -> void:
	if _fallback:
		_fallback.animate(delta, velocity_dir, speed_ratio)
		return
	if _skel == null:
		return
	_time += delta
	var moving := speed_ratio > 0.08
	_amp = move_toward(_amp, 1.0 if moving else 0.0, delta * 7.0)
	if moving:
		_phase += delta * TAU * (1.3 + 0.7 * clampf(speed_ratio, 0.0, 1.5))
		var target := atan2(velocity_dir.x, velocity_dir.z)
		_yaw = lerp_angle(_yaw, target, clampf(delta * 12.0, 0.0, 1.0))
		rotation.y = _yaw
	pose(_phase, _amp, _time)
	_tick_face(delta)
	_tick_reaction(delta)

## Pose de un hueso relativa a su reposo (los huesos del GLB reposan sin giro).
func _rot(b: String, euler: Vector3, off := Vector3.ZERO) -> void:
	var i: int = _bone.get(b, -1)
	if i < 0:
		return
	var r: Transform3D = _rest[i]
	_skel.set_bone_pose_rotation(i, (r.basis * Basis.from_euler(euler)).get_rotation_quaternion())
	_skel.set_bone_pose_position(i, r.origin + off)

## Suma un giro a la pose actual de un hueso (reacciones).
func _add_rot(b: String, euler: Vector3) -> void:
	var i: int = _bone.get(b, -1)
	if i < 0:
		return
	_skel.set_bone_pose_rotation(i, _skel.get_bone_pose_rotation(i) * Quaternion.from_euler(euler))

## Pose procedural: paso saltarín de muñeco (fase, amplitud 0..1) mezclado con el reposo.
## Muslo + rodilla + pie, hombro + codo + mano, cadera / columna / pecho (la sudadera se
## dobla), cuello y cola en tres huesos (la ola baja por la cola).
func pose(phase: float, amp: float, t: float) -> void:
	if _skel == null:
		return
	var idle := 1.0 - amp
	var reach := 0.0
	var br := sin(t * 1.8)
	for i in 2:
		var nm := "R" if i == 0 else "L"
		var p := phase + (0.0 if i == 0 else PI)
		var sw := sin(p)
		var a := -0.75 * sw * amp
		var swing := maxf(0.0, cos(p - 0.25))          # pierna en el aire, yendo hacia delante
		var lift := 0.045 * swing * amp
		var knee := (0.85 * swing * swing + 0.08) * amp
		_rot("Leg" + nm, Vector3(a - knee * 0.35, 0.0, 0.0), Vector3(0, lift, 0.06 * sw * amp))
		_rot("Knee" + nm, Vector3(knee, 0.0, 0.0))
		var heel := 0.3 * maxf(0.0, cos(p - 0.15)) * amp - 0.15 * maxf(0.0, -cos(p + 0.6)) * amp
		_rot("Foot" + nm, Vector3(-(a - knee * 0.35 + knee) * 0.85 + heel, 0.0, 0.0))
		reach = maxf(reach, LEG * cos(a) - lift)
		var s := -1.0 if i == 0 else 1.0
		var asw := 0.85 * sw * amp
		_rot("Arm" + nm, Vector3(asw + 0.04 * br * idle, 0.0, s * (-ARM_IN - 0.04 * amp + 0.03 * br * idle)))
		_rot("Elbow" + nm, Vector3(-(0.14 * idle + (0.2 + 0.5 * maxf(0.0, -sw)) * amp), 0.0, s * 0.06))
		_rot("Hand" + nm, Vector3(-0.1 * amp * maxf(0.0, -sw), 0.0, 0.0))
	var bob := absf(cos(phase)) * 0.035 * amp + br * 0.004 * idle
	_pivot.position = Vector3(0.0, (reach - LEG) * _pivot.scale.y + bob, 0.0)
	_rot("Hips", Vector3(0.0, 0.12 * sin(phase) * amp, 0.05 * sin(phase) * amp))
	_rot("Spine", Vector3(0.035 * amp - 0.01 * br * idle, -0.05 * sin(phase) * amp, -0.02 * sin(phase) * amp))
	_rot("Chest", Vector3(0.03 * amp - 0.008 * br * idle, -0.06 * sin(phase) * amp, -0.02 * sin(phase) * amp))
	var ci: int = _bone.get("Chest", -1)
	if ci >= 0:
		_skel.set_bone_pose_scale(ci, Vector3(1.0 + 0.012 * br * idle, 1.0 - 0.01 * br * idle, 1.0 + 0.012 * br * idle))
	_rot("Neck", Vector3(-0.06 * amp + 0.03 * sin(t * 0.8) * idle + 0.05 * (absf(cos(phase)) - 0.5) * amp,
		-0.05 * sin(phase) * amp + 0.16 * sin(t * 0.37) * idle, -0.05 * sin(phase) * amp + 0.05 * sin(t * 0.29) * idle))
	for k in 3:
		var lag := float(k) * 0.9
		_rot("Tail%d" % (k + 1), Vector3(0.03 * sin(t * 2.0 - lag) + 0.03 * absf(cos(phase)) * amp,
			sin(t * 2.6 + phase - lag) * (0.07 + 0.08 * amp) * (1.0 + 0.3 * k), 0.0))

func face(yaw: float) -> void:
	if _fallback:
		_fallback.face(yaw)
		return
	_yaw = yaw
	rotation.y = yaw

# ── cara: parpadeo, miradas ─────────────────────────────────────────────────

func _tick_face(delta: float) -> void:
	_blink_next -= delta
	if _blink_next <= 0.0:
		_blink_t = 0.16
		_blink_next = _rng.randf_range(2.2, 5.0)
	_blink_t = maxf(0.0, _blink_t - delta)
	_glance_next -= delta
	if _glance_next <= 0.0:
		_glance_next = _rng.randf_range(1.2, 3.5)
		_glance_target = Vector2(_rng.randf_range(-0.1, 0.1), _rng.randf_range(-0.05, 0.05)) if _rng.randf() < 0.6 else Vector2.ZERO
	_glance = _glance.lerp(_glance_target, clampf(delta * 14.0, 0.0, 1.0))
	_apply_eyes()

func _apply_eyes() -> void:
	if _eye_mat == null:
		return
	var blink := sin(clampf(_blink_t / 0.16, 0.0, 1.0) * PI)
	var lid := maxf(blink, _happy)
	var arch := 1.0
	var x := 0.0
	if _ko == "knocked":
		lid = 1.0
		arch = -0.6
	elif _ko == "dead":
		lid = 0.0
		x = 1.0
	_eye_mat.set_shader_parameter("lid", lid)
	_eye_mat.set_shader_parameter("arch", arch)
	_eye_mat.set_shader_parameter("xeyes", x)
	_eye_mat.set_shader_parameter("look", _glance)

# ── reacciones (mascota) ────────────────────────────────────────────────────

# ── reacciones (mascota) ────────────────────────────────────────────────────

## Movimientos de reacción: duración por defecto (s). Se reproducen dentro de animate().
const REACTIONS := {
	"hop": 0.5, "double_hop": 1.6, "spin": 1.5, "flip": 1.6, "wiggle": 1.4, "squish": 1.2,
	"nod": 1.5, "shake": 0.9, "sway": 2.0, "flap": 1.6, "stretch": 1.8, "pounce": 1.3,
	"tilt": 1.5, "rub": 1.6, "look": 1.8, "pop": 0.45,
}

## Empieza una reacción (ver REACTIONS); duration <= 0 usa la de serie. Corta la anterior.
func react(kind: String, duration := 0.0) -> void:
	if _fallback:
		_fallback.react(kind, duration)
		return
	if not REACTIONS.has(kind):
		return
	_react_kind = kind
	_react_t = 0.0
	_react_len = duration if duration > 0.0 else float(REACTIONS[kind])

func is_reacting() -> bool:
	if _fallback:
		return _fallback.is_reacting()
	return _react_kind != ""

## 0..1: cuánto entorna los ojos de gusto ahora mismo.
func happy_amount() -> float:
	if _fallback:
		return _fallback.happy_amount()
	return _happy

## Transformación de la reacción en curso (identidad en reposo).
func rig_transform() -> Transform3D:
	if _fallback:
		return _fallback.rig_transform()
	return _rig.transform if _rig else Transform3D.IDENTITY

func _tick_reaction(delta: float) -> void:
	if _rig == null:
		return
	if _react_kind == "":
		if _happy > 0.0 or _rig.transform != Transform3D.IDENTITY:
			_happy = 0.0
			_rig.transform = Transform3D.IDENTITY
			_apply_eyes()
		return
	_react_t += delta
	if _react_t >= _react_len:
		_react_kind = ""
		_tick_reaction(0.0)
		return
	var t := _react_t
	var u := clampf(t / _react_len, 0.0, 1.0)
	var f := _fade(u)
	var off := Vector3.ZERO
	var rot := Vector3.ZERO
	var scl := Vector3.ONE
	var center := BODY_Y
	var happy := 0.0
	var arms := Vector3.ZERO   # x: hacia delante (ambos), y: abrir, z: alternar
	var head := Vector3.ZERO
	match _react_kind:
		"hop":
			var j := _bump(u, 0.0, 1.0)
			off.y = 0.22 * j
			scl = Vector3(1.0 - 0.03 * j, 1.0 + 0.05 * j, 1.0 - 0.03 * j)
			arms.y = 0.5 * j
		"pop":
			var k := _ease(u)
			var s := 0.3 + 0.7 * k + sin(u * PI) * 0.18
			scl = Vector3(s, s, s)
			center = 0.0
		"double_hop":
			var h := maxf(_bump(u, 0.05, 0.42), _bump(u, 0.5, 0.87) * 0.7)
			off.y = 0.26 * h
			rot.z = sin(t * 18.0) * 0.06 * f
			scl = Vector3(1.0 - 0.03 * h, 1.0 + 0.05 * h, 1.0 - 0.03 * h)
			arms.y = 1.6 * h
			happy = f
		"spin":
			var j2 := _bump(u, 0.08, 0.7)
			off.y = 0.42 * j2
			rot.y = TAU * _ease(clampf((u - 0.08) / 0.62, 0.0, 1.0))
			var land := _bump(u, 0.7, 0.95)
			scl = Vector3(1.0 + 0.06 * land, 1.0 - 0.08 * land, 1.0 + 0.06 * land)
			arms.y = 1.4 * j2
			happy = maxf(j2, land)
		"flip":
			if u < 0.12:
				var c := _ease(u / 0.12)
				scl = Vector3(1.0 + 0.04 * c, 1.0 - 0.07 * c, 1.0 + 0.04 * c)
			elif u < 0.72:
				var k2 := _ease((u - 0.12) / 0.6)
				rot.x = -k2 * TAU
				off.y = 0.5 * sin(k2 * PI)
				arms.x = 1.2 * sin(k2 * PI)
				happy = 1.0
			else:
				var k3 := (u - 0.72) / 0.28
				rot.z = sin(k3 * TAU * 1.5) * 0.1 * (1.0 - k3)
				happy = 1.0 - k3
		"wiggle":
			head.z = sin(t * 26.0) * 0.3 * (1.0 - u) * f
			head.y = sin(t * 13.0) * 0.25 * (1.0 - u) * f
			rot.z = sin(t * 26.0) * 0.05 * (1.0 - u) * f
			happy = _window(u, 0.55, 1.0)
		"squish":
			var w := sin(t * 9.0) * 0.02
			scl = Vector3(1.0 + 0.04 * f + w * f, 1.0 - 0.05 * f - w * f, 1.0 + 0.04 * f + w * f)
			rot.z = sin(t * 4.0) * 0.06 * f
			head.z = sin(t * 4.0) * 0.15 * f
			arms.x = 0.9 * f
			center = 0.0
			happy = f
		"nod":
			var beat := absf(sin(u * PI * 4.0)) if u > 0.12 and u < 0.82 else 0.0
			head.x = (0.2 + 0.25 * beat) * f
			rot.x = 0.06 * beat * f
			center = 0.0
			happy = _window(u, 0.8, 1.0)
		"shake":
			head.y = sin(u * TAU * 2.0) * 0.55 * (1.0 - u)
			rot.y = sin(u * TAU * 2.0) * 0.12 * (1.0 - u)
		"sway":
			rot.z = sin(u * TAU * 2.0) * 0.1 * f
			center = 0.0
			arms.y = 1.9 * f
			happy = f
		"flap":
			rot.z = sin(t * 9.0) * 0.05 * f
			center = 0.0
			arms.y = (1.0 + 0.6 * sin(t * 20.0)) * f
			happy = _window(u, 0.25, 0.85)
		"stretch":
			var up := _window(u, 0.15, 0.9)
			scl = Vector3(1.0 - 0.02 * up, 1.0 + 0.05 * up, 1.0 - 0.02 * up)
			head.x = -0.45 * up
			rot.x = -0.1 * up
			center = 0.0
			arms.y = 2.6 * up
			happy = up
		"pounce":
			if u < 0.27:
				var k4 := _ease(u / 0.27)
				scl = Vector3(1.0 + 0.05 * k4, 1.0 - 0.1 * k4, 1.0 + 0.05 * k4)
				center = 0.0
			elif u < 0.75:
				var k5 := (u - 0.27) / 0.48
				off = Vector3(0.0, 0.5 * sin(k5 * PI), 0.25 * sin(k5 * PI))
				rot.x = 0.25 * sin(k5 * PI)
				arms.x = 1.6 * sin(k5 * PI)
				happy = 1.0
			else:
				var k6 := (u - 0.75) / 0.25
				var land2 := sin(k6 * PI) * (1.0 - k6)
				scl = Vector3(1.0 + 0.06 * land2, 1.0 - 0.09 * land2, 1.0 + 0.06 * land2)
				center = 0.0
				happy = 1.0 - k6
		"tilt":
			head.z = 0.35 * f
			rot.z = 0.05 * f
			off.y = 0.06 * _bump(u, 0.05, 0.3)
			happy = _window(u, 0.6, 1.0)
		"rub":
			arms.x = 1.0 * f
			arms.z = sin(t * 22.0) * 0.25 * f
			center = 0.0
			happy = f
		"look":
			head.y = sin(u * TAU) * 0.9 * f
			var fluff := _window(u, 0.7, 1.0)
			scl = Vector3(1.0 + 0.04 * fluff, 1.0 + 0.01 * fluff, 1.0 + 0.04 * fluff)
			happy = fluff
	var basis := Basis.from_euler(rot) * Basis.from_scale(scl)
	var c3 := Vector3(0.0, center, 0.0)
	_rig.transform = Transform3D(basis, off + c3 - basis * c3)
	_happy = happy
	_apply_eyes()
	_add_rot("Neck", head)
	if arms != Vector3.ZERO:
		for i in 2:
			var s := -1.0 if i == 0 else 1.0
			_add_rot("Arm" + ("R" if i == 0 else "L"), Vector3(-arms.x + arms.z * s, 0.0, s * arms.y * 0.8))

## Cuerpo en el suelo (silenciado): ojos cerrados (noqueado) o ojos en X de dibujo
## animado (fuera de juego). Nada gore: solo la cara de "K.O." de los cartoons.
func set_knocked_face(kind: String) -> void:
	_ko = kind if kind in ["knocked", "dead"] else ""
	if _fallback:
		_fallback.set_knocked_face(kind)
		return
	_apply_eyes()

## Cara de "K.O." puesta ahora: "knocked", "dead" o "".
func knocked_face() -> String:
	return _ko

static func _fade(u: float) -> float:
	return smoothstep(0.0, 0.15, u) * (1.0 - smoothstep(0.85, 1.0, u))

static func _window(u: float, a: float, b: float) -> float:
	var edge := minf(0.08, (b - a) / 3.0)
	return smoothstep(a, a + edge, u) * (1.0 - smoothstep(b - edge, b, u))

static func _bump(u: float, a: float, b: float) -> float:
	if u <= a or u >= b:
		return 0.0
	return sin((u - a) / (b - a) * PI)

static func _ease(x: float) -> float:
	return x * x * (3.0 - 2.0 * x)


# ── colores y materiales ────────────────────────────────────────────────────

func _c(key: String, fallback: String) -> Color:
	return Color(str(skin.get(key, fallback)))

func _sp() -> Dictionary:
	return SPECIES.get(skin_id, SPECIES["perro"])

func _mark_color() -> Color:
	var m := str(_sp().get("mark", "#241A16"))
	if m == "mane":
		return _c("mane", "#8A4515")
	if skin.has("ear_color"):
		return Color(str(skin["ear_color"]))
	return Color(m)

func _lid_color() -> Color:
	match str(_sp().get("lid", "fur")):
		"light":
			return _c("fur_light", "#FFFFFF")
		"mark":
			return _mark_color()
	return _c("fur", "#999999")

## Zapatilla: si la skin trae zapatillas casi blancas, la lona toma el color de la ropa
## (suela, puntera y cordones siguen blancos), como las de la referencia.
func _shoe_color() -> Color:
	var c := _c("shoes", "#F1F5F9")
	if c.get_luminance() > 0.8 and str(skin.get("style", "hoodie")) != "suit":
		return _c("outfit", "#2563EB")
	return c

func _m(p: Dictionary, shader: Shader = FUR_SHADER) -> ShaderMaterial:
	var key := var_to_str(p) + str(shader.get_instance_id())
	if not _mat_cache.has(key):
		var m := ShaderMaterial.new()
		m.shader = shader
		for k in p:
			m.set_shader_parameter(k, p[k])
		_mat_cache[key] = m
	return _mat_cache[key]

func _fur_m(col: Color, tex: Texture2D = null) -> ShaderMaterial:
	var light := _soft(_c("fur_light", "#FFFFFF").lerp(_c("fur", "#999999"), 0.1))
	return _m({"base_color": _soft(col), "light_color": light, "mark_color": _mark_color(),
		"pink_color": Color("#FF9AAE"), "roughness_v": 0.95, "specular_v": 0.15, "sheen": 0.35, "fuzz": 0.25,
		"fuzz_freq": 320.0, "grain": 0.03, "rim_v": 0.12, "mask_tex": tex, "use_tex": 1.0 if tex else 0.0})

func _cloth_m(col: Color, fuzz := 0.3) -> ShaderMaterial:
	return _m({"base_color": col, "light_color": col, "mark_color": col, "pink_amt": 0.0, "roughness_v": 0.92,
		"specular_v": 0.12, "sheen": 0.28, "fuzz": fuzz, "fuzz_freq": 420.0, "grain": 0.04, "grain_freq": 150.0, "rim_v": 0.15})

func _gloss_m(col: Color) -> ShaderMaterial:
	return _m({"base_color": col, "light_color": col, "mark_color": col, "pink_amt": 0.0, "roughness_v": 0.22,
		"specular_v": 0.6, "sheen": 0.0, "fuzz": 0.0, "grain": 0.0, "rim_v": 0.0, "ao_amt": 0.6})

func _rubber_m(col: Color) -> ShaderMaterial:
	return _m({"base_color": col, "light_color": col, "mark_color": col, "pink_amt": 0.0, "roughness_v": 0.6,
		"specular_v": 0.3, "sheen": 0.1, "fuzz": 0.05, "fuzz_freq": 500.0, "grain": 0.02, "rim_v": 0.05})

## Los blancos puros se queman con las luces: se bajan un poco.
static func _soft(c: Color) -> Color:
	var l := c.get_luminance()
	return c if l < 0.7 else c.darkened(clampf((l - 0.7) * 0.75, 0.0, 0.25))

func _material_for(name: String, src: Material = null) -> Material:
	var suit := str(skin.get("style", "hoodie")) == "suit"
	var outfit := _c("outfit", "#1E293B")
	match name:
		"fur":
			return _fur_m(_c("fur", "#9CA3AF"))
		"furtex":
			var tex: Texture2D = src.albedo_texture if src is BaseMaterial3D else null
			return _fur_m(_c("fur", "#9CA3AF"), tex)
		"mane":
			return _m({"base_color": _c("mane", "#8A4515"), "light_color": _c("mane", "#8A4515"), "mark_color": _c("mane", "#8A4515"),
				"pink_amt": 0.0, "roughness_v": 0.95, "sheen": 0.6, "fuzz": 0.6, "fuzz_freq": 200.0, "grain": 0.1, "rim_v": 0.3})
		"outfit":
			return _cloth_m(outfit, 0.2 if suit else 0.3)
		"rib":
			return _cloth_m(outfit.darkened(0.18), 0.2)
		"white", "shirt":
			return _cloth_m(Color("#F3F2EE"), 0.15)
		"tie":
			return _cloth_m(_c("accent", "#DC2626"), 0.1)
		"shoe":
			return _gloss_m(_c("shoes", "#1E293B")) if suit else _cloth_m(_shoe_color(), 0.25)
		"sole":
			return _rubber_m(Color("#26262B")) if suit else _rubber_m(Color("#F4F3EF"))
		"brow":
			return _fur_m(Color(str(_sp().get("brow", "#2A1A12"))))
		"nose":
			return _gloss_m(Color(str(_sp().get("nose", "#1A1212"))))
		"beak":
			return _m({"base_color": Color("#F59E0B"), "light_color": Color("#F59E0B"), "mark_color": Color("#F59E0B"), "pink_amt": 0.0,
				"roughness_v": 0.55, "specular_v": 0.35, "sheen": 0.2, "fuzz": 0.05, "grain": 0.03, "rim_v": 0.1})
		"mouth":
			return _m({"base_color": Color("#5A1824"), "light_color": Color("#5A1824"), "mark_color": Color("#5A1824"), "pink_amt": 0.0,
				"roughness_v": 0.6, "sheen": 0.0, "fuzz": 0.0, "grain": 0.0, "rim_v": 0.0, "ao_amt": 0.3})
		"tongue":
			return _m({"base_color": Color("#F27C8E"), "light_color": Color("#F27C8E"), "mark_color": Color("#F27C8E"), "pink_amt": 0.0,
				"roughness_v": 0.5, "sheen": 0.0, "fuzz": 0.0, "grain": 0.0, "rim_v": 0.0, "ao_amt": 0.3})
		"bag":
			return _cloth_m(_c("bag", "#1E293B"), 0.2)
		"cap":
			return _cloth_m(_c("hat_color", "#2563EB"), 0.2)
		"dark":
			return _gloss_m(Color("#1F2937"))
		"eye":
			return _eye_mat
	return _cloth_m(Color("#FF00FF"))

func _paint() -> void:
	_eye_mat = ShaderMaterial.new()
	_eye_mat.shader = EYE_SHADER
	_eye_mat.set_shader_parameter("iris_color", _c("eye", "#5B3A1E").lerp(Color("#3A1E0E"), 0.55))
	_eye_mat.set_shader_parameter("lid_color", _soft(_lid_color()))
	_eye_mat.set_shader_parameter("line_color", Color(str(_sp().get("brow", "#2A1A12"))).darkened(0.2))
	for mi: MeshInstance3D in _model.find_children("*", "MeshInstance3D", true, false):
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		# LOD automático de Godot, pero menos agresivo: los ojos y la boca son superficies
		# pequeñas de la misma malla y se deformaban en miniatura
		mi.lod_bias = 4.0
		for i in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(i)
			var n := src.resource_name if src else "fur"
			mi.set_surface_override_material(i, _material_for(n, src))

static func _alpha_shader(src: Shader) -> Shader:
	if not _alpha_shaders.has(src):
		var sh := Shader.new()
		sh.code = src.code.replace("depth_draw_opaque", "depth_draw_always").replace("//ALPHA", "ALPHA = alpha_v;")
		_alpha_shaders[src] = sh
	return _alpha_shaders[src]

## Con transparencia se duplican los materiales para no afectar a los demás jugadores.
func _apply_alpha() -> void:
	if _model == null:
		return
	var translucent := _alpha < 0.99
	for mi: MeshInstance3D in _model.find_children("*", "MeshInstance3D", true, false):
		var n: int = mi.mesh.get_surface_count()
		if not mi.has_meta("base_mats"):
			var base: Array = []
			for i in n:
				base.append(mi.get_surface_override_material(i))
			mi.set_meta("base_mats", base)
		var mats: Array = mi.get_meta("base_mats")
		for i in n:
			var src: ShaderMaterial = mats[i]
			if translucent:
				var m: ShaderMaterial = mi.get_meta("alpha_%d" % i) if mi.has_meta("alpha_%d" % i) else null
				if m == null:
					m = src.duplicate() if src != _eye_mat else src
					m.shader = _alpha_shader(src.shader)
					mi.set_meta("alpha_%d" % i, m)
				m.set_shader_parameter("alpha_v", _alpha)
				mi.set_surface_override_material(i, m)
			else:
				if src == _eye_mat:
					_eye_mat.shader = EYE_SHADER
				mi.set_surface_override_material(i, src)
