class_name HeroAvatar3D
extends PlushAvatar3D
## Personaje 3D de calidad "hero" de cada jugador (mapa, sala, menú, retratos, cuerpos):
## mallas de subdivisión hechas en Blender (tools/_hero_build.py + _hero_common.py +
## _hero_species.py), ropa con malla propia y grosor, texturas horneadas (albedo con alfa
## = teñible, normal, ORM) y ojos con párpados de verdad.
##
## Cada GLB (assets/characters_hq/<id>_hq.glb) trae un esqueleto humanoide (Hips > Spine >
## Chest > Neck > Head > HairTuft, Shoulder > UpperArm > LowerArm > Hand, UpperLeg >
## LowerLeg > Foot > Toes, Tail1..3) y cinco mallas que se encienden según el look:
##   Body (animal, con shape keys de la cara), Suit (traje), Hoodie (sudadera, jogger y
##   zapatillas altas), Bag (mochila) y Cap (gorra).
## La ropa, la corbata, los zapatos, la mochila y la gorra se tiñen con los colores de la
## skin y de los cosméticos públicos. Nunca muestra el rol.
##
## Es un PlushAvatar3D (misma API pública y mismas medidas: HEIGHT, BODY_Y, HEAD_Y,
## MOUTH_Y, HEAD_R): si una especie no tiene modelo "hero" o no se puede leer, se dibuja el
## peluche de antes (y este, si tampoco, el muñeco de vinilo).

const HERO_SIZE := 0.9           # escala del GLB (cabeza a la altura de HEAD_Y del peluche)
const HERO_DIR := "res://assets/characters_hq/"
const HERO_IDS := ["zorro", "gato", "pinguino", "panda", "leon", "conejo", "oso", "perro", "lobo", "tigre", "mapache", "buho"]

const PLUSH := preload("res://shaders/hero_plush.gdshader")
const EYE := preload("res://shaders/hero_eye.gdshader")

## Parámetros de cada material del GLB (hero_<nombre>).
const MAT := {
	"fur": {"wrap": 0.40, "sheen": 0.9, "spec_amount": 0.25, "subsurface": 0.15, "sheen_tint": Color(0.75, 0.85, 1.0),
		"rim_amount": 0.10, "rim_color": Color(0.50, 0.60, 1.0)},
	"suit": {"wrap": 0.35, "sheen": 0.75, "spec_amount": 0.22, "sheen_tint": Color(0.7, 0.8, 1.0),
		"rim_amount": 0.09, "rim_color": Color(0.50, 0.60, 1.0)},
	"outfit": {"wrap": 0.40, "sheen": 0.85, "spec_amount": 0.12, "sheen_tint": Color(0.85, 0.9, 1.0),
		"rim_amount": 0.09, "rim_color": Color(0.50, 0.60, 1.0)},
	"rib": {"wrap": 0.40, "sheen": 0.6, "spec_amount": 0.10, "rim_amount": 0.06},
	"pants": {"wrap": 0.35, "sheen": 0.6, "spec_amount": 0.12, "rim_amount": 0.08, "rim_color": Color(0.50, 0.60, 1.0)},
	"shirt": {"wrap": 0.4, "sheen": 0.35, "spec_amount": 0.25},
	"tie": {"wrap": 0.3, "sheen": 0.8, "spec_amount": 0.55, "sheen_tint": Color(1.0, 0.8, 0.8)},
	"shoe": {"wrap": 0.10, "sheen": 0.2, "spec_amount": 0.9},
	"sole": {"wrap": 0.1, "sheen": 0.0, "spec_amount": 0.3},
	"solew": {"wrap": 0.3, "sheen": 0.0, "spec_amount": 0.35},
	"string": {"wrap": 0.4, "sheen": 0.3, "spec_amount": 0.2},
	"metal": {"wrap": 0.05, "sheen": 0.0, "spec_amount": 1.4},
	"beak": {"wrap": 0.4, "sheen": 0.0, "spec_amount": 0.6, "subsurface": 0.5, "subsurface_tint": Color(1.0, 0.45, 0.1)},
	"nose": {"wrap": 0.2, "sheen": 0.0, "spec_amount": 1.0},
	"button": {"wrap": 0.05, "sheen": 0.0, "spec_amount": 0.9},
	"mouth": {"wrap": 0.5, "sheen": 0.0, "spec_amount": 0.3},
	"bag": {"wrap": 0.35, "sheen": 0.5, "spec_amount": 0.2, "rim_amount": 0.06},
	"cap": {"wrap": 0.35, "sheen": 0.5, "spec_amount": 0.2, "rim_amount": 0.06},
}
## Zapato de vestir de serie (con traje): piel oscura; un cosmético de zapatos lo tiñe.
const LEATHER := Color("#23262E")
## Cara de reposo por especie (shape keys): el zorro sonríe con la boca abierta.
const REST_FACE := {"zorro": {"open": 0.70, "smile": 0.70}}

var _hq := false                 # true = dibujado con el modelo "hero"
var _h_meshes := {}              # "Body"/"Suit"/"Hoodie"/"Bag"/"Cap" -> MeshInstance3D
var _h_body: MeshInstance3D
var _h_rest_q := {}
var _h_rest_p := {}
var _h_gbasis := {}
var _h_shape := {}
var _h_mats: Array[ShaderMaterial] = []
var _h_eye_mats: Array[ShaderMaterial] = []
var _h_blink := 0.0
var _h_tuft := 0.0
var _h_tuft_v := 0.0
var _h_expr := {}

static var _h_scenes := {}
static var _h_textures := {}
static var _h_alpha := {}

## Ruta del GLB "hero" de una especie ("" si no hay).
static func hero_path(id: String) -> String:
	if not id in HERO_IDS:
		return ""
	var p: String = HERO_DIR + id + "_hq.glb"
	return p if (FileAccess.file_exists(p) or ResourceLoader.exists(p)) else ""

## Arma el modelo. look: cosméticos públicos (ropa, gorra, zapatillas, mochila).
func build(id: String, look: Dictionary = {}) -> void:
	_hq = false
	var ps := _h_scene(id)
	if ps == null:
		super.build(id, look)
		return
	for c in get_children():
		c.queue_free()
	_skel = null
	_fallback = null
	_model = null
	_bone.clear()
	_h_meshes.clear()
	_h_body = null
	_h_rest_q.clear()
	_h_rest_p.clear()
	_h_gbasis.clear()
	_h_shape.clear()
	_h_mats.clear()
	_h_eye_mats.clear()
	_h_expr = {}
	_react_kind = ""
	_happy = 0.0
	_ko = ""
	_alpha = 1.0
	skin_id = id
	skin = CosmeticCatalog.dress(SkinCatalog.skin(id), look)
	_rng.seed = hash(id) ^ get_instance_id()
	_blink_next = _rng.randf_range(0.8, 3.0)
	_blink_t = 0.0
	var sb: Array = skin.get("scale_body", [1.0, 1.0])
	var wide := float(sb[0]) if sb.size() > 0 else 1.0
	var tall := float(sb[1]) if sb.size() > 1 else 1.0
	_rig = Node3D.new()
	_rig.name = "Rig"
	add_child(_rig)
	_pivot = Node3D.new()
	_pivot.name = "Pivot"
	_pivot.scale = Vector3(lerpf(1.0, wide, 0.35), lerpf(1.0, tall, 0.5), lerpf(1.0, wide, 0.25)) * HERO_SIZE
	_rig.add_child(_pivot)
	_model = ps.instantiate()
	_pivot.add_child(_model)
	var sks := _model.find_children("*", "Skeleton3D", true, false)
	if sks.is_empty():
		push_warning("HeroAvatar3D: '%s' no tiene esqueleto" % id)
		for c in get_children():
			c.queue_free()
		super.build(id, look)
		return
	_hq = true
	_skel = sks[0]
	for i in _skel.get_bone_count():
		_bone[_skel.get_bone_name(i)] = i
		var r := _skel.get_bone_rest(i)
		_h_rest_q[i] = r.basis.get_rotation_quaternion()
		_h_rest_p[i] = r.origin
		_h_gbasis[i] = _skel.get_bone_global_rest(i).basis.orthonormalized()
	for mi: MeshInstance3D in _model.find_children("*", "MeshInstance3D", true, false):
		var key := str(mi.name)
		for k in ["Body", "Suit", "Hoodie", "Bag", "Cap"]:
			if key.begins_with(k):
				_h_meshes[k] = mi
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_h_body = _h_meshes.get("Body")
	if _h_body:
		for k in _h_body.mesh.get_blend_shape_count():
			_h_shape[str(_h_body.mesh.get_blend_shape_name(k))] = k
	var suit := str(skin.get("style", "hoodie")) == "suit"
	_h_show("Suit", suit)
	_h_show("Hoodie", not suit)
	_h_show("Bag", skin.has("bag") and look.has("bag"))
	_h_show("Cap", str(skin.get("hat", "")) == "cap")
	_h_paint(id, look)
	pose_walk(0.0, 0.0)
	_h_apply_face()

func _h_show(k: String, on: bool) -> void:
	if _h_meshes.has(k):
		(_h_meshes[k] as MeshInstance3D).visible = on

## true si este personaje se dibuja con un GLB (hero o peluche); false = vinilo de reserva.
func has_plush_model() -> bool:
	return _hq or super.has_plush_model()

## true si se dibuja con el modelo "hero".
func has_hero_model() -> bool:
	return _hq

## Escena de la especie: la importada por el editor; si el proyecto se abre sin haberla
## importado nunca, el .glb crudo con GLTFDocument (como el peluche).
static func _h_scene(id: String) -> PackedScene:
	if _h_scenes.has(id):
		return _h_scenes[id]
	var path := hero_path(id)
	var ps: PackedScene = null
	if path != "":
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
	_h_scenes[id] = ps
	return ps

## Textura horneada (WebP aparte, 1024; fuentes 2048 en characters_hq/src): la importada
## (VRAM) o, sin importar, leída del disco.
static func _h_tex(id: String, kind: String) -> Texture2D:
	var path := HERO_DIR + "%s_hq_%s.webp" % [id, kind]
	if _h_textures.has(path):
		return _h_textures[path]
	var tex: Texture2D = null
	if _is_imported(path):
		tex = load(path) as Texture2D
	if tex == null and FileAccess.file_exists(path):
		var img := Image.load_from_file(path)
		if img:
			img.generate_mipmaps()
			tex = ImageTexture.create_from_image(img)
	_h_textures[path] = tex
	return tex

# ── materiales ──────────────────────────────────────────────────────────────────────

## Tela: el color de los datos, con un mínimo de luminosidad (de noche el marino y el
## carbón se leen como silueta y no como un agujero negro).
static func _h_cloth(c: Color) -> Color:
	return Color.from_hsv(c.h, c.s * 0.97, maxf(c.v, 0.40))

func _h_tint_for(nm: String) -> Variant:
	var base_skin := SkinCatalog.skin(skin_id)
	var outfit := _h_cloth(_c("outfit", "#1E293B"))
	match nm:
		"suit", "outfit", "rib":
			return outfit
		"tie":
			return _c("accent", "#DC2626")
		"shoe":
			if str(skin.get("style", "hoodie")) == "suit":
				var cosmetic: bool = str(skin.get("shoes", "")) != str(base_skin.get("shoes", ""))
				return _c("shoes", "#23262E") if cosmetic else LEATHER
			return _h_cloth(_shoe_color())
		"bag":
			return _h_cloth(_c("bag", "#1E293B"))
		"cap":
			return _h_cloth(_c("hat_color", "#2563EB"))
	return null

func _h_paint(id: String, _look: Dictionary) -> void:
	var alb := _h_tex(id, "albedo")
	var nrm := _h_tex(id, "normal")
	var orm := _h_tex(id, "orm")
	var eye := _h_tex(id, "eye")
	for mi: MeshInstance3D in _h_meshes.values():
		for s in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(s)
			var nm := src.resource_name.trim_prefix("hero_") if src else "fur"
			var m := ShaderMaterial.new()
			if nm == "eye":
				m.shader = EYE
				m.set_shader_parameter("eye_tex", eye)
				_h_eye_mats.append(m)
			else:
				m.shader = PLUSH
				m.set_shader_parameter("albedo_tex", alb)
				m.set_shader_parameter("normal_tex", nrm)
				m.set_shader_parameter("orm_tex", orm)
				var p: Dictionary = MAT.get(nm, MAT["fur"])
				for k in p:
					m.set_shader_parameter(k, p[k])
				var tint: Variant = _h_tint_for(nm)
				if tint != null:
					m.set_shader_parameter("tint_color", tint)
					m.set_shader_parameter("tint_on", 1.0)
			m.resource_name = nm
			_h_mats.append(m)
			mi.set_surface_override_material(s, m)

## Opacidad (desconexión, camuflaje): 1 = sólido.
func set_alpha(a: float) -> void:
	if not _hq:
		super.set_alpha(a)
		return
	if is_equal_approx(a, _alpha):
		return
	var was_solid := _alpha >= 0.999
	_alpha = a
	var solid := a >= 0.999
	for m in _h_mats:
		if solid != was_solid:
			m.shader = _h_variant(m.shader, not solid)
		m.set_shader_parameter("alpha", a)
	for mi: MeshInstance3D in _h_meshes.values():
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if a > 0.5 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

static func _h_variant(sh: Shader, transparent: bool) -> Shader:
	for base in [PLUSH, EYE]:
		if sh == base and not transparent:
			return sh
		if sh == base and transparent:
			if not _h_alpha.has(base):
				var t := Shader.new()
				t.code = base.code.replace("render_mode ", "render_mode blend_mix, depth_prepass_alpha, ").replace("//ALPHA", "ALPHA = alpha;")
				_h_alpha[base] = t
			return _h_alpha[base]
	if not transparent:
		for base in _h_alpha:
			if _h_alpha[base] == sh:
				return base
	return sh

# ── animación ───────────────────────────────────────────────────────────────────────

## velocity_dir: dirección de movimiento en el mundo 3D (y = 0). speed_ratio: 0..1.5.
func animate(delta: float, velocity_dir: Vector3, speed_ratio: float) -> void:
	if not _hq:
		super.animate(delta, velocity_dir, speed_ratio)
		return
	if _skel == null:
		return
	_time += delta
	var moving := speed_ratio > 0.08
	_amp = move_toward(_amp, 1.0 if moving else 0.0, delta * 6.0)
	if moving:
		_phase += delta * TAU * (1.5 + 0.9 * clampf(speed_ratio, 0.0, 1.5))
		var target := atan2(velocity_dir.x, velocity_dir.z)
		_yaw = lerp_angle(_yaw, target, clampf(delta * 12.0, 0.0, 1.0))
		rotation.y = _yaw
	_h_tick_face(delta)
	pose_walk(_phase, _amp)
	_h_tick_reaction(delta)
	_h_apply_face()

## Pose procedural (fase, amplitud 0..1, tiempo): la del peluche, con el paso del hero.
func pose(phase: float, amp: float, t: float) -> void:
	if not _hq:
		super.pose(phase, amp, t)
		return
	_time = t
	pose_walk(phase, amp)

## Mira hacia una dirección sin caminar (al aparecer o en el menú).
func face(yaw: float) -> void:
	if not _hq:
		super.face(yaw)
		return
	_yaw = yaw
	rotation.y = yaw

## Gira el hueso alrededor de un eje del modelo (en su postura de reposo).
func _h_q(b: int, axis: Vector3, ang: float) -> Quaternion:
	if ang == 0.0 or b < 0:
		return Quaternion.IDENTITY
	var local: Vector3 = (_h_gbasis[b].inverse() * axis).normalized()
	return Quaternion(local, ang)

func _h_b(bname: String) -> int:
	return _bone.get(bname, -1)

func _h_pose(bname: String, rot: Quaternion, offset := Vector3.ZERO, scl := Vector3.ONE) -> void:
	var b: int = _bone.get(bname, -1)
	if b < 0:
		return
	_skel.set_bone_pose_rotation(b, _h_rest_q[b] * rot)
	_skel.set_bone_pose_position(b, _h_rest_p[b] + offset)
	_skel.set_bone_pose_scale(b, scl)

## Postura de paso (fase en radianes, amp 0 = reposo, 1 = andando). Pública para capturas.
func pose_walk(ph: float, amp: float, extra := {}) -> void:
	if _skel == null or not _hq:
		return
	var s := sin(ph)
	var c := cos(ph)
	var idle := 1.0 - amp
	var br := sin(_time * 2.1)
	var X := Vector3.RIGHT
	var Y := Vector3.UP
	var Z := Vector3.BACK
	var bob := (1.0 - absf(s)) * 0.024 * amp - 0.014 * amp
	var sway := s * 0.075 * amp
	var hips_b := _h_b("Hips")
	_h_pose("Hips", _h_q(hips_b, Z, sway * 0.6) * _h_q(hips_b, Y, s * 0.16 * amp) * _h_q(hips_b, X, 0.05 * amp),
		Vector3(0.0, bob + br * 0.002 * idle, 0.0))
	var sp := _h_b("Spine")
	_h_pose("Spine", _h_q(sp, Y, -s * 0.10 * amp) * _h_q(sp, Z, -sway * 0.4) * _h_q(sp, X, 0.03 * amp))
	var ch := _h_b("Chest")
	_h_pose("Chest", _h_q(ch, Y, -s * 0.06 * amp) * _h_q(ch, X, -0.02 * br * idle), Vector3.ZERO,
		Vector3(1.0 + 0.010 * br * idle, 1.0 + 0.006 * br * idle, 1.0 + 0.012 * br * idle))
	_h_pose("Neck", _h_q(_h_b("Neck"), X, -0.03 * amp))
	var head_b := _h_b("Head")
	var hx := 0.02 * sin(_time * 0.7) * idle - absf(c) * 0.03 * amp + float(extra.get("head_x", 0.0))
	var hy := 0.06 * sin(_time * 0.45) * idle + s * 0.05 * amp + float(extra.get("head_y", 0.0))
	var hz := -sway * 0.5 + 0.03 * sin(_time * 0.6) * idle + float(extra.get("head_z", 0.0))
	_h_pose("Head", _h_q(head_b, Y, hy) * _h_q(head_b, X, hx) * _h_q(head_b, Z, hz))
	var tb := _h_b("HairTuft")
	_h_pose("HairTuft", _h_q(tb, X, _h_tuft) * _h_q(tb, Z, sway * 0.6))
	# cola: ola que baja por los tres huesos (más viva al andar)
	for k in 3:
		var lag := float(k) * 0.9
		var nm := "Tail%d" % (k + 1)
		var tbk := _h_b(nm)
		if tbk >= 0:
			var wag := sin(_time * 2.6 + ph - lag) * (0.10 + 0.10 * amp) * (1.0 + 0.3 * k)
			var lift := 0.04 * sin(_time * 1.7 - lag) + 0.05 * absf(c) * amp
			_h_pose(nm, _h_q(tbk, Y, wag) * _h_q(tbk, X, lift))
	for side in ["L", "R"]:
		var sg := 1.0 if side == "L" else -1.0
		var ls := s * sg
		var lc := c * sg
		var thigh := -0.62 * ls * amp
		var swing := maxf(0.0, lc)
		var knee := (0.06 + 1.05 * swing * (1.0 - 0.4 * maxf(0.0, ls)) + 0.10 * maxf(0.0, -ls)) * amp
		var want := (-0.32 * maxf(0.0, ls) * (1.0 - swing) + 0.55 * maxf(0.0, -ls) * maxf(0.0, -lc) - 0.12 * swing) * amp
		var foot := want - thigh - knee
		_h_pose("UpperLeg_" + side, _h_q(_h_b("UpperLeg_" + side), X, thigh) * _h_q(_h_b("UpperLeg_" + side), Z, -sway * 0.6))
		_h_pose("LowerLeg_" + side, _h_q(_h_b("LowerLeg_" + side), X, knee))
		_h_pose("Foot_" + side, _h_q(_h_b("Foot_" + side), X, foot) * _h_q(_h_b("Foot_" + side), Z, sway * 0.5))
		_h_pose("Toes_" + side, _h_q(_h_b("Toes_" + side), X, -0.45 * maxf(0.0, -ls) * maxf(0.0, -lc) * amp))
		var arm := 0.62 * ls * amp
		var out := (0.02 + 0.025 * br * idle + 0.06 * amp) * sg + float(extra.get("arms_out", 0.0)) * sg
		var fwd := float(extra.get("arms_fwd", 0.0))
		_h_pose("Shoulder_" + side, _h_q(_h_b("Shoulder_" + side), Z, 0.02 * sg * br * idle))
		_h_pose("UpperArm_" + side, _h_q(_h_b("UpperArm_" + side), X, arm - fwd) * _h_q(_h_b("UpperArm_" + side), Z, out))
		_h_pose("LowerArm_" + side, _h_q(_h_b("LowerArm_" + side), X, -0.18 - 0.35 * maxf(0.0, -ls) * amp - float(extra.get("elbow", 0.0))))
		_h_pose("Hand_" + side, _h_q(_h_b("Hand_" + side), X, -0.1 * amp) * _h_q(_h_b("Hand_" + side), Z, 0.08 * sg))

func _h_tick_face(delta: float) -> void:
	_blink_t += delta
	if _blink_t > _blink_next:
		_blink_t = 0.0
		_blink_next = _rng.randf_range(1.8, 4.5)
	var bt := _blink_t / 0.14
	_h_blink = sin(clampf(bt, 0.0, 1.0) * PI) if bt < 1.0 else 0.0
	_glance_next -= delta
	if _glance_next <= 0.0:
		_glance_next = _rng.randf_range(1.0, 3.2)
		_glance_target = Vector2(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-0.6, 0.5)) * (0.6 if _amp < 0.5 else 0.2)
		if _rng.randf() < 0.35:
			_glance_target = Vector2.ZERO
	_glance = _glance.lerp(_glance_target, clampf(delta * 10.0, 0.0, 1.0))
	var target := -0.10 * _amp * absf(cos(_phase)) + 0.04 * sin(_time * 1.3) * (1.0 - _amp)
	_h_tuft_v += ((target - _h_tuft) * 90.0 - _h_tuft_v * 9.0) * delta
	_h_tuft += _h_tuft_v * delta

func _h_apply_face() -> void:
	if _h_body == null:
		return
	var w := {"blink_L": 0.0, "blink_R": 0.0, "happy": 0.0, "surprised": 0.0, "open": 0.0, "smile": 0.0,
		"brow_up": 0.0, "brow_sad": 0.0, "brow_angry": 0.0}
	var h := clampf(_happy, 0.0, 1.0)
	w["happy"] = h
	var rest: Dictionary = REST_FACE.get(skin_id, {})
	for k in rest:
		w[k] = float(rest[k]) * (1.0 - h) * (1.0 if _ko == "" else 0.0)
	var blink := _h_blink * (1.0 - h)
	if _ko == "knocked":
		blink = 1.0
		w["brow_sad"] = 0.8
	elif _ko == "dead":
		blink = 0.0
		w["brow_sad"] = 0.6
	w["blink_L"] = blink
	w["blink_R"] = blink
	for k in _h_expr:
		w[k] = _h_expr[k]
	for k in w:
		if _h_shape.has(k):
			_h_body.set_blend_shape_value(_h_shape[k], w[k])
	for m in _h_eye_mats:
		m.set_shader_parameter("look", _glance if _ko == "" else Vector2.ZERO)
		m.set_shader_parameter("ko", 1.0 if _ko == "dead" else 0.0)

## Expresión fija para capturas/retratos: {"happy": 1.0} / {"blink_L": 1, "blink_R": 1} /
## {"surprised": 1, "open": 0.6}. Vacía = expresión viva (parpadeo, miradas).
func set_expression(e: Dictionary) -> void:
	if not _hq:
		return
	_h_expr = e.duplicate()
	if e.has("look"):
		_glance = e["look"]
		_glance_target = e["look"]
		_h_expr.erase("look")
	_blink_next = 1e9 if not e.is_empty() else _rng.randf_range(0.8, 3.0)
	_h_blink = 0.0
	_h_apply_face()

# ── reacciones (mascota) ────────────────────────────────────────────────────────────

## Empieza una reacción (ver REACTIONS); duration <= 0 usa la de serie. Corta la anterior.
func react(kind: String, duration := 0.0) -> void:
	if not _hq:
		super.react(kind, duration)
		return
	if not REACTIONS.has(kind):
		return
	_react_kind = kind
	_react_t = 0.0
	_react_len = duration if duration > 0.0 else float(REACTIONS[kind])

func is_reacting() -> bool:
	if not _hq:
		return super.is_reacting()
	return _react_kind != ""

## 0..1: cuánto entorna los ojos de gusto ahora mismo.
func happy_amount() -> float:
	if not _hq:
		return super.happy_amount()
	return _happy

## Transformación de la reacción en curso (identidad en reposo).
func rig_transform() -> Transform3D:
	if not _hq:
		return super.rig_transform()
	return _rig.transform if _rig else Transform3D.IDENTITY

func _h_tick_reaction(delta: float) -> void:
	if _rig == null:
		return
	if _react_kind == "":
		if _happy > 0.0 or _rig.transform != Transform3D.IDENTITY:
			_happy = 0.0
			_rig.transform = Transform3D.IDENTITY
		return
	_react_t += delta
	if _react_t >= _react_len:
		_react_kind = ""
		_h_tick_reaction(0.0)
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
			scl = Vector3(1.0 - 0.05 * j, 1.0 + 0.07 * j, 1.0 - 0.05 * j)
			arms.y = 0.5 * j
		"pop":
			var k := _ease(u)
			var spp := 0.3 + 0.7 * k + sin(u * PI) * 0.18
			scl = Vector3(spp, spp, spp)
			center = 0.0
		"double_hop":
			var h := maxf(_bump(u, 0.05, 0.42), _bump(u, 0.5, 0.87) * 0.7)
			off.y = 0.26 * h
			rot.z = sin(t * 18.0) * 0.08 * f
			scl = Vector3(1.0 - 0.04 * h, 1.0 + 0.06 * h, 1.0 - 0.04 * h)
			arms.y = 1.0 * h
			happy = f
		"spin":
			var j2 := _bump(u, 0.08, 0.7)
			off.y = 0.42 * j2
			rot.y = TAU * _ease(clampf((u - 0.08) / 0.62, 0.0, 1.0))
			var land := _bump(u, 0.7, 0.95)
			scl = Vector3(1.0 + 0.1 * land, 1.0 - 0.12 * land, 1.0 + 0.1 * land)
			arms.y = 1.2 * j2
			happy = maxf(j2, land)
		"flip":
			if u < 0.12:
				var cc := _ease(u / 0.12)
				scl = Vector3(1.0 + 0.06 * cc, 1.0 - 0.1 * cc, 1.0 + 0.06 * cc)
			elif u < 0.72:
				var k2 := _ease((u - 0.12) / 0.6)
				rot.x = -k2 * TAU
				off.y = 0.4 * sin(k2 * PI)
				arms.y = 0.8
				happy = 1.0
			else:
				var k3 := (u - 0.72) / 0.28
				rot.z = sin(k3 * TAU * 1.5) * 0.14 * (1.0 - k3)
				happy = 1.0 - k3
		"wiggle":
			head.z = sin(t * 26.0) * 0.25 * (1.0 - u) * f
			rot.z = sin(t * 26.0) * 0.08 * (1.0 - u) * f
			rot.y = sin(t * 13.0) * 0.12 * (1.0 - u) * f
			happy = _window(u, 0.55, 1.0)
		"squish":
			var w := sin(t * 9.0) * 0.025
			scl = Vector3(1.0 + 0.07 * f + w * f, 1.0 - 0.07 * f - w * f, 1.0 + 0.07 * f + w * f)
			rot.z = sin(t * 4.0) * 0.07 * f
			center = 0.0
			happy = f
		"nod":
			var beat := absf(sin(u * PI * 4.0)) if u > 0.12 and u < 0.82 else 0.0
			head.x = (0.15 + 0.25 * beat) * f
			rot.x = (0.05 + 0.06 * beat) * f
			center = 0.0
			happy = _window(u, 0.8, 1.0)
		"shake":
			head.y = sin(u * TAU * 2.0) * 0.55 * (1.0 - u)
			rot.y = sin(u * TAU * 2.0) * 0.15 * (1.0 - u)
		"sway":
			rot.z = sin(u * TAU * 2.0) * 0.16 * f
			center = 0.0
			arms.y = 1.3 * f
			happy = f
		"flap":
			rot.z = sin(t * 9.0) * 0.08 * f
			center = 0.0
			arms.y = (0.9 + 0.6 * sin(t * 20.0)) * f
			happy = _window(u, 0.25, 0.85)
		"stretch":
			var up := _window(u, 0.15, 0.9)
			scl = Vector3(1.0 - 0.04 * up, 1.0 + 0.1 * up, 1.0 - 0.04 * up)
			head.x = -0.35 * up
			center = 0.0
			arms.y = 0.6 * up
			arms.x = 0.8 * up
			happy = up
		"pounce":
			if u < 0.27:
				var k4 := _ease(u / 0.27)
				scl = Vector3(1.0 + 0.1 * k4, 1.0 - 0.15 * k4, 1.0 + 0.1 * k4)
				center = 0.0
			elif u < 0.75:
				var k5 := (u - 0.27) / 0.48
				off = Vector3(0.0, 0.5 * sin(k5 * PI), 0.25 * sin(k5 * PI))
				rot.x = 0.3 * sin(k5 * PI)
				scl = Vector3(0.95, 1.08, 0.95)
				arms.x = 1.2 * sin(k5 * PI)
				happy = 1.0
			else:
				var k6 := (u - 0.75) / 0.25
				var land2 := sin(k6 * PI) * (1.0 - k6)
				scl = Vector3(1.0 + 0.12 * land2, 1.0 - 0.14 * land2, 1.0 + 0.12 * land2)
				center = 0.0
				happy = 1.0 - k6
		"tilt":
			head.z = 0.30 * f
			rot.z = 0.06 * f
			off.y = 0.06 * _bump(u, 0.05, 0.3)
			happy = _window(u, 0.6, 1.0)
		"rub":
			arms.x = 1.0 * f
			arms.z = sin(t * 22.0) * 0.3 * f
			scl = Vector3(1.0, 1.0 - 0.025 * absf(sin(t * 11.0)) * f, 1.0)
			center = 0.0
			happy = f
		"look":
			head.y = sin(u * TAU) * 0.9 * f
			rot.y = sin(u * TAU) * 0.2 * f
			var fluff := _window(u, 0.7, 1.0)
			scl = Vector3(1.0 + 0.06 * fluff, 1.0 + 0.02 * fluff, 1.0 + 0.06 * fluff)
			happy = fluff
	var basis := Basis.from_euler(rot) * Basis.from_scale(scl)
	var c3 := Vector3(0.0, center, 0.0)
	_rig.transform = Transform3D(basis, off + c3 - basis * c3)
	_happy = happy
	if arms != Vector3.ZERO or head != Vector3.ZERO:
		_h_add_arms_head(arms, head)

func _h_add_arms_head(arms: Vector3, head: Vector3) -> void:
	for side in ["L", "R"]:
		var sg := 1.0 if side == "L" else -1.0
		var b := _h_b("UpperArm_" + side)
		if b < 0:
			continue
		var cur := _skel.get_bone_pose_rotation(b)
		var alt := arms.z * sg
		_skel.set_bone_pose_rotation(b, cur * _h_q(b, Vector3.RIGHT, -arms.x + alt) * _h_q(b, Vector3.BACK, arms.y * sg))
	var hb := _h_b("Head")
	if hb >= 0:
		var hq := _skel.get_bone_pose_rotation(hb)
		_skel.set_bone_pose_rotation(hb, hq * _h_q(hb, Vector3.UP, head.y) * _h_q(hb, Vector3.RIGHT, head.x) * _h_q(hb, Vector3.BACK, head.z))

## Cuerpo en el suelo (silenciado): ojos cerrados (noqueado) o ojos en X de dibujo
## animado (fuera de juego). Nada gore: solo la cara de "K.O." de los cartoons.
func set_knocked_face(kind: String) -> void:
	if not _hq:
		super.set_knocked_face(kind)
		return
	_ko = kind if kind in ["knocked", "dead"] else ""
	_h_apply_face()
