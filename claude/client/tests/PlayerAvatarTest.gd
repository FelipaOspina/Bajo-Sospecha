extends Node2D
## Prueba sin servidor: godot --headless res://tests/PlayerAvatarTest.tscn

const TEST_SKINS := "user://skins_test/"

var _failures := 0

func _snap(p2_skin: String) -> Dictionary:
	return {"version": 1, "phase": "investigation", "interactables": [],
		"players": [{"id": "me", "name": "Ana", "skinId": "panda", "position": {"x": 100, "y": 100}},
			{"id": "p2", "name": "Beto", "skinId": p2_skin, "position": {"x": 300, "y": 100}, "connected": false}],
		"you": {"roleId": "ROLE_CEO", "inventory": [], "knownTeammates": [], "objectives": []}}

func _ready() -> void:
	Network.player_id = "me"
	var spawner := PlayerSpawner.new()
	spawner.y_sort_enabled = true
	add_child(spawner)
	GameState._replace(_snap("leon"))
	var me := spawner.get_player("me") as PlayerAvatar
	var other := spawner.get_player("p2") as PlayerAvatar

	# 1. Estructura de la escena.
	_check(me != null and me is CharacterBody2D, "el spawner crea PlayerAvatar (CharacterBody2D)")
	var feet: CollisionShape2D = me.get_node("FeetCollision")
	var feet_rect := feet.transform * feet.shape.get_rect()
	_check(absf(feet.position.y) < 1.0 and feet_rect.size.y < 20.0 and feet_rect.size.x > 20.0, "colisión baja y plana en los pies")
	_check(me.collision_layer == 2 and me.collision_mask == 1, "no choca con otros jugadores")
	_check(me.visuals.y_sort_enabled and me.body_sprite is AnimatedSprite2D and me.drop_shadow.get_parent() == me.visuals, "Visuals con Y-Sort, BodySprite animado y DropShadow")
	_check(me.drop_shadow.z_index < 0 and me.drop_shadow.light_mask == 0, "la sombra queda bajo el cuerpo y no la ilumina la linterna")

	# 2. Skins del servidor; sin PNG se ve el chibi procedural.
	_check(me.skin_id == "panda" and other.skin_id == "leon", "cada avatar lleva la skin que manda el servidor")
	_check(not me.using_sprites and me.chibi.visible and me.chibi.config.get("id") == "panda", "sin PNG, chibi procedural con los colores de la skin")
	_check(other.chibi.features()["has_mane"] and me.chibi.features()["patches"] == ProceduralChibiAvatar.PATCHES["panda"], "cada animal tiene sus rasgos (melena del león, manchas del panda)")
	var mat := me.chibi.material as ShaderMaterial
	_check(mat != null and mat.shader.resource_path.ends_with("chibi_sdf.gdshader") and me.chibi.get_child_count() == 0, "el chibi es un solo rectángulo con el shader SDF (sin piezas sueltas)")
	var panda_fur := Color("#F1F1EE")
	_check((me.chibi.shader_param("fur_color") as Vector4).is_equal_approx(Vector4(panda_fur.r, panda_fur.g, panda_fur.b, 1.0)), "los colores de la skin llegan al shader (pelaje del panda)")
	_check(me.chibi.bake and not ChibiBaker.enabled() and me.chibi.material == me.chibi.shader_material, "sin GPU (headless) no se hornea: shader en vivo")
	_check(ChibiBaker.region("lado", 3) == Rect2(Vector2(3, 1) * ChibiBaker.CELL * ChibiBaker.RESOLUTION, ChibiBaker.CELL * ChibiBaker.RESOLUTION) and ChibiBaker.region("frente", -1).position.y == 3 * ChibiBaker.CELL.y * ChibiBaker.RESOLUTION, "la hoja horneada: una fila por vista y la pose quieta aparte")
	GameState._replace(_snap("buho"))
	_check(other.skin_id == "buho" and other.chibi.features()["beak"] and not other.chibi.features()["has_mane"], "si el servidor cambia la skin, el avatar se actualiza")

	# 3. Color de rol solo en tu corbata.
	_check(me.accent_color() == UiPalette.CRIMSON, "tu corbata lleva el color de tu rol (CEO en carmesí)")
	_check(other.accent_color() == Color(SkinCatalog.skin("buho")["accent"]), "los demás llevan el acento de su skin (no revela su rol)")
	EventBus.game_over.emit({"players": [{"id": "p2", "roleId": "ROLE_CTO"}, {"id": "me", "roleId": "ROLE_CEO"}]})
	_check(other.accent_color() == UiPalette.CYAN, "al terminar la partida se revela el color de su rol")

	# 4. Con PNG: AnimatedSprite2D con una animación por vista.
	_write_png(TEST_SKINS + "gato/frente.png", 64, Color.ORANGE)
	_write_png(TEST_SKINS + "gato/lado.png", 128, Color.ORANGE)   # tira de 2 fotogramas
	other.skins_root = TEST_SKINS
	other.apply_skin("gato")
	var frames := other.body_sprite.sprite_frames
	_check(other.using_sprites and not other.chibi.visible, "con frente.png usa los PNG y oculta el chibi")
	_check(frames.has_animation("frente") and frames.get_frame_count("lado") == 2 and not frames.has_animation("espalda"), "una animación por vista; las tiras se trocean")
	_check(is_equal_approx(other.body_sprite.scale.y, 56.0 / 64.0) and other.body_sprite.offset.y == -32.0, "se escala a 56 px con los pies en el origen")
	for i in 6:
		other.position.x += 4.0
		await get_tree().process_frame
	_check(other.body_sprite.animation == "lado" and other.body_sprite.is_playing(), "caminando de lado reproduce lado.png")
	other.apply_skin("dragon")
	_check(not other.using_sprites and other.chibi.visible, "una skin sin archivos no da error: vuelve al chibi")

	# 5. Animación procedural del chibi.
	for i in 6:
		me.position.y -= 4.0
		await get_tree().process_frame
	_check(me.facing == "espalda" and me.chibi.shader_param("view") == ProceduralChibiAvatar.VIEWS["espalda"], "de espaldas no se le ve la cara ni la corbata (vista de espalda en el shader)")
	for i in 8:
		me.position.x -= 4.0
		await get_tree().process_frame
	_check(me.facing == "lado" and me.visuals.scale.x == -1.0, "caminando a la izquierda se pone de lado y se voltea")
	var ps := me.chibi.pose_state()
	var pose_feet: Array = ps["feet"]
	_check(ps["squash"] != 0.0 and (pose_feet[0] as Vector2).y != (pose_feet[1] as Vector2).y and is_equal_approx((me.chibi.shader_param("body_anim") as Vector4).y, ps["squash"]), "rebota (aplasta y estira) y alterna los pies, y el shader recibe la pose")

	# 6. Nombre en píldora, fuera del cuerpo y sin oscurecerse.
	_check(me.name_tag.text == "Ana" and me.name_tag.get_theme_constant("outline_size") > 0, "NameTagLabel con el nombre (nunca el rol) y contorno")
	var pill := me.name_pill.get_theme_stylebox("panel") as StyleBoxFlat
	_check(pill != null and pill.bg_color.a < 1.0 and pill.corner_radius_top_left >= 8, "fondo de píldora oscura translúcida")
	_check(me.overhead_layer.layer > 0 and me.overhead_layer.follow_viewport_enabled, "el nombre va en un CanvasLayer que sigue a la cámara (el CanvasModulate no lo toca)")
	_check(other.name_pill.modulate.a < 1.0, "el nombre de un jugador desconectado se atenúa")
	await get_tree().process_frame
	var tag_center := me.name_pill.position + Vector2(me.name_pill.size.x / 2.0, me.name_pill.size.y)
	_check(tag_center.distance_to(me.overhead_anchor.global_position) < 1.0 and me.overhead_anchor.global_position.y < me.global_position.y - 50, "la píldora sigue centrada encima de la cabeza")
	_check(me.name_pill.get_global_transform().get_scale() == Vector2.ONE and me.name_pill.get_global_transform().get_rotation() == 0.0, "el nombre no se voltea ni gira con el cuerpo")

	# 7. La barra de canalización va encima del nombre.
	var bar := me.attach_progress_bar("Purgando logs...", 5.0, 0.0, "delete")
	_check(bar.get_parent() == me.overhead_anchor and bar.global_position.y < me.name_pill.position.y + 1.0, "la barra se cuelga sobre el nombre")
	await get_tree().process_frame
	_check(not bar.finished and bar.layer.layer > me.overhead_layer.layer, "la barra se dibuja por encima del nombre")

	# 8. Al ocultar el mapa (asamblea) desaparecen nombre y barra.
	spawner.hide()
	_check(not me.overhead_layer.visible and not bar.layer.visible, "al ocultar el mapa se ocultan el nombre y la barra")
	spawner.show()
	_check(me.overhead_layer.visible and bar.layer.visible, "y vuelven al mostrarlo")

	print("PlayerAvatarTest: ", "OK" if _failures == 0 else "%d fallos" % _failures)
	get_tree().quit(1 if _failures > 0 else 0)

func _write_png(path: String, width: int, color: Color) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var img := Image.create(width, 64, false, Image.FORMAT_RGBA8)
	img.fill(color)
	img.save_png(path)

func _check(cond: bool, label: String) -> void:
	if cond:
		print("  ok   ", label)
	else:
		_failures += 1
		print("  FAIL ", label)
