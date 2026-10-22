extends RefCounted
## Ruta del Detective en el cliente: la curva de niveles del perfil y el estado de cada
## nivel (lección, reto, recompensa) para pintarlo. Lee detective_path y profile_level_curve
## de res://data/progression/progression.json (copia de shared/config/progression).
## El servidor es quien da la XP y marca los retos: aquí solo se replica la fórmula
## (ProfileService / DetectivePath.ts) y se lee profile.path.
## Sin class_name (se carga con preload) para no depender de la caché de clases del editor.

## Estados de un nivel en la ruta.
const DONE := "done"          # alcanzado y reto cumplido
const CURRENT := "current"    # tu nivel actual
const REACHED := "reached"    # alcanzado, con el reto aún pendiente
const LOCKED := "locked"      # todavía no llegas

static func config() -> Dictionary:
	var c = Progression.data().get("detective_path", {})
	return c if c is Dictionary else {}

static func path_name() -> String:
	return str(config().get("name", "Ruta del Detective"))

static func levels() -> Array:
	var l = config().get("levels", [])
	return l if l is Array else []

static func max_level() -> int:
	return levels().size()

## Entrada del nivel n (o {} si no existe).
static func entry(n: int) -> Dictionary:
	for l in levels():
		if int(l.get("level", 0)) == n:
			return l
	return {}

static func tutorial_reward() -> Dictionary:
	var r = config().get("tutorial_reward", {})
	return r if r is Dictionary else {}

## Consejos en partida hasta este nivel (incluido el anterior: nivel < hint_max_level).
static func hint_max_level() -> int:
	return int(config().get("hint_max_level", 5))

# ───── Curva de niveles (misma fórmula que el servidor) ─────

static func _curve() -> Dictionary:
	var c = Progression.data().get("profile_level_curve", {})
	return c if c is Dictionary else {}

## XP para pasar del nivel n al n+1.
static func xp_for_level(n: int) -> int:
	var c := _curve()
	if c.is_empty():
		return int(Progression.data().get("profile_xp_per_level", 1000))
	return mini(int(c.get("max_per_level", 3000)), int(c.get("base", 300)) + int(c.get("step", 150)) * maxi(0, n - 1))

## XP total para empezar el nivel n.
static func xp_to_reach(n: int) -> int:
	var total := 0
	for l in range(1, n):
		total += xp_for_level(l)
	return total

## {level, into, need} con esa XP total.
static func progress_for(xp: int) -> Dictionary:
	var level := 1
	var left := maxi(0, xp)
	while level < 999:
		var need := maxi(1, xp_for_level(level))
		if left < need:
			return {"level": level, "into": left, "need": need}
		left -= need
		level += 1
	return {"level": level, "into": 0, "need": 1}

# ───── Estado de la ruta con el perfil ─────

static func path_of(profile: Dictionary) -> Dictionary:
	var p = profile.get("path", {})
	return p if p is Dictionary else {}

static func challenge_done(profile: Dictionary, challenge_id: String) -> bool:
	return challenge_id in path_of(profile).get("done", [])

## Cuenta acumulada de un reto a medias (scope total).
static func challenge_progress(profile: Dictionary, challenge: Dictionary) -> int:
	var cid := str(challenge.get("id", ""))
	if challenge_done(profile, cid):
		return int(challenge.get("target", 1))
	var prog = path_of(profile).get("progress", {})
	return int(prog.get(cid, 0)) if prog is Dictionary else 0

static func tutorial_done(profile: Dictionary) -> bool:
	return bool(path_of(profile).get("tutorialDone", false))

## Estado del nivel n para un jugador de nivel `level`.
static func state_of(n: int, level: int, profile: Dictionary) -> String:
	if n > level:
		return LOCKED
	var ch: Dictionary = entry(n).get("challenge", {})
	var done := ch.is_empty() or challenge_done(profile, str(ch.get("id", "")))
	if n == level:
		return DONE if done and n == max_level() else CURRENT
	return DONE if done else REACHED

## Retos de niveles alcanzados que aún no se han cumplido (lo que puedes hacer ahora).
static func open_challenges(level: int, profile: Dictionary) -> Array:
	var out := []
	for l in levels():
		var ch: Dictionary = l.get("challenge", {})
		if int(l.get("level", 0)) <= level and not ch.is_empty() and not challenge_done(profile, str(ch.get("id", ""))):
			out.append(l)
	return out

## Texto de la recompensa de un nivel: "+100 MC", "Gorra negra", "Mochila militar + 500 MC".
static func reward_text(reward: Dictionary) -> String:
	var parts: Array[String] = []
	if reward.has("cosmetic"):
		parts.append(str(CosmeticCatalog.item(str(reward["cosmetic"])).get("name", str(reward["cosmetic"]).capitalize())))
	if int(reward.get("coins", 0)) > 0:
		parts.append("+%s %s" % [Progression.format_amount(int(reward["coins"])), Progression.currency_short("coins")])
	return " + ".join(parts)
