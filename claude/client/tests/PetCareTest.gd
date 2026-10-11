extends Node
## Mascota del lobby: comida por especie, hambre e hidratación que bajan con el tiempo,
## comer y beber, guardado por perfil, reacciones y sonidos de los 12 animales.

const SAVE := "user://pet_care_test.cfg"
var _failed := 0

func _ready() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	_species()
	_levels()
	_saving()
	_reactions()
	_sounds()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	await get_tree().process_frame   # que el servidor de audio suelte el sonido de prueba
	print("PetCareTest: ", "OK" if _failed == 0 else "%d FALLOS" % _failed)
	get_tree().quit(1 if _failed > 0 else 0)

func _species() -> void:
	var taps := {}
	for id in SkinCatalog.ids():
		var f := PetCare.food(id)
		_check(PetCare.species(id).has("food") and str(f.get("icon", "")) in PetIcons.ICONS, "%s come %s (icono %s)" % [id, f.get("name"), f.get("icon")])
		var tap := PetCare.tap_reaction(id)
		_check(tap in PetReactions.TAP_KINDS, "%s reacciona con %s" % [id, tap])
		taps[tap] = true
	_check(taps.size() == SkinCatalog.ids().size(), "cada animal tiene una reacción distinta (%d)" % taps.size())
	_check(PetCare.food("panda")["id"] == "bambu", "el panda come bambú")
	_check(PetCare.food("gato")["id"] == "pescado", "el gato come pescado")
	_check(PetCare.food("conejo")["id"] == "zanahoria", "el conejo come zanahoria")

func _levels() -> void:
	var pet := PetCare.new()
	pet.save_path = SAVE
	pet.load_state("prueba")
	var t0 := 1_000_000.0
	var start := float(PetCare.data()["start"])
	var l := pet.levels("panda", t0)
	_check(is_equal_approx(l["hunger"], start) and is_equal_approx(l["hydration"], start), "un animal nuevo empieza al %d %%" % start)
	var six := t0 + 6 * 3600.0
	l = pet.levels("panda", six)
	_check(absf(l["hunger"] - (start - 50.0)) < 0.01, "en 6 h el hambre baja la mitad de la barra (%.1f)" % l["hunger"])
	_check(absf(l["hydration"] - maxf(0.0, start - 75.0)) < 0.01, "y la hidratación, tres cuartos (%.1f)" % l["hydration"])
	_check(pet.need("panda", six) == "hydration", "con las dos bajas, primero pide agua")
	l = pet.levels("panda", six - 3600.0)
	_check(absf(l["hunger"] - (start - 50.0)) < 0.01, "si el reloj va hacia atrás no sube ni baja")
	var r := pet.drink("panda", six)
	_check(r["ok"] and absf(r["level"] - (maxf(0.0, start - 75.0) + 40.0)) < 0.01, "beber suma 40 (%.1f)" % r["level"])
	r = pet.feed("panda", six)
	_check(r["ok"] and absf(r["level"] - (start - 50.0 + 35.0)) < 0.01, "comer suma 35 (%.1f)" % r["level"])
	_check(pet.need("panda", six) == "", "ya no pide nada")
	pet.feed("panda", six)
	_check(is_equal_approx(pet.level("panda", "hunger", six), 100.0), "no pasa de 100")
	r = pet.feed("panda", six)
	_check(not r["ok"] and r["reason"] == "full", "lleno: no come más")
	l = pet.levels("panda", six + 30 * 3600.0)
	_check(l["hunger"] == 0.0 and l["hydration"] == 0.0, "con mucho tiempo sin cuidarlo, a 0 (nunca negativo)")
	_check(pet.need("panda", six + 30 * 3600.0) == "hydration", "a 0 las dos: primero el agua")
	_check(is_equal_approx(pet.level("gato", "hunger", six), start), "cada animal lleva sus propias barras")

func _saving() -> void:
	var a := PetCare.new()
	a.save_path = SAVE
	a.load_state("perfil_a")
	a.feed("perro", 5000.0)
	var b := PetCare.new()
	b.save_path = SAVE
	b.load_state("perfil_b")
	b.drink("perro", 5000.0)
	var a2 := PetCare.new()
	a2.save_path = SAVE
	a2.load_state("perfil_a")
	_check(is_equal_approx(a2.level("perro", "hunger", 5000.0), a.level("perro", "hunger", 5000.0)), "se guarda y se recupera por perfil")
	_check(is_equal_approx(a2.level("perro", "hydration", 5000.0), float(PetCare.data()["start"])), "guardar otro perfil no pisa este")
	a2.load_state("")
	_check(a2.profile_key == "local", "sin perfil se guarda como \"local\"")

func _reactions() -> void:
	for kind in PetReactions.DURATION:
		var d := PetReactions.duration(kind)
		var moved := 0.0
		var finite := true
		for i in 21:
			var s := PetReactions.sample(kind, d * i / 20.0)
			var off: Vector2 = s["offset"]
			var sc: Vector2 = s["scale"]
			finite = finite and off.is_finite() and sc.is_finite() and is_finite(float(s["rot"])) and sc.x > 0.3 and sc.y > 0.3
			var e: Dictionary = s["emote"]
			moved = maxf(moved, off.length() / 10.0 + absf(float(s["rot"])) + (sc - Vector2.ONE).length() * 4.0 + float(e.get("smile", 0.0)) + float(e.get("mouth", 0.0)) + (absf(e["head"].z) if e.has("head") else 0.0))
		var end := PetReactions.sample(kind, d)
		var still: bool = (end["offset"] as Vector2).length() < 0.5 and absf(float(end["rot"]) - roundf(float(end["rot"]) / TAU) * TAU) < 0.02 and ((end["scale"] as Vector2) - Vector2.ONE).length() < 0.03
		_check(finite and moved > 0.15 and still, "reacción %s: se mueve (%.2f) y acaba en reposo" % [kind, moved])

func _sounds() -> void:
	var missing := PetSfx.all_keys().filter(func(k): return not ResourceLoader.exists(PetSfx.path_for(k)))
	_check(missing.is_empty(), "están los %d sonidos (%s)" % [PetSfx.all_keys().size(), ", ".join(missing) if not missing.is_empty() else "ninguno falta"])
	_check(PetSfx.key_for("gato", "stroke") == "gato_caricia" and PetSfx.key_for("perro", "tap") == "perro_feliz", "nombres de los sonidos por gesto")
	var sfx := PetSfx.new()
	add_child(sfx)
	var old := PetSfx.volume
	PetSfx.volume = 0.8
	_check(sfx.play("gato_caricia") and sfx.last_played == "gato_caricia", "suena el ronroneo del gato")
	_check(not sfx.play("no_existe"), "un sonido que falta no rompe nada")
	PetSfx.volume = 0.0
	_check(not sfx.play("perro_feliz"), "a volumen 0, en silencio")
	PetSfx.volume = old
	for p in sfx.get_children():
		p.stop()
	sfx.free()

func _check(ok: bool, text: String) -> void:
	print("  ", "ok  " if ok else "FAIL", " ", text)
	if not ok:
		_failed += 1
