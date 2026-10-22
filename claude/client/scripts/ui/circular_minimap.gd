class_name CircularMinimap
extends Control
## Minimapa circular centrado en tu avatar. Muestra en tiempo real a los demás
## avatares que tienes a la vista (línea de vista, con el color de su animal) y los
## puntos de interés que tu cliente conoce: solo las pistas del snapshot en las que
## ves algo (el servidor ya filtra lo que cada jugador percibe). Tú eres la flecha
## blanca, apuntando hacia donde miras.
## Lo que queda fuera del radio se pega al borde (jugadores) o no se dibuja (pistas).
## Además: pings de fantasma (cian, se pegan al borde) y, si eres fantasma, tus misiones
## fantasma (rombos violeta). Los jugadores ocultos (fantasmas para los vivos) no salen.

@export var players: PlayerSpawner
@export var world_radius := 450.0   # px del mundo entre el centro y el borde
@export var border_color := Color(1, 1, 1, 0.22)

func _process(_delta: float) -> void:
	if is_visible_in_tree():
		queue_redraw()

func radius() -> float:
	return minf(size.x, size.y) / 2.0 - 2.0

## Posiciones en el minimapa (coordenadas locales del control), también para tests.
func markers() -> Dictionary:
	var center := size / 2.0
	var r := radius()
	var k := r / world_radius
	var me := players.get_player(GameState.local_player_id()) if players else null
	var origin := me.global_position if me else Vector2.ZERO
	var out := {"me": center, "heading": Vector2.DOWN, "players": [], "evidence": [], "pings": [], "tasks": []}
	if me is PlayerAvatar:
		out["heading"] = (me as PlayerAvatar).heading()
	for i in GameState.snapshot.get("interactables", []):
		if i.get("contents", []).is_empty():
			continue
		var p := (Protocol.vec2_from(i["position"]) - origin) * k
		if p.length() <= r - 5.0:
			out["evidence"].append(center + p)
	for ping in GameState.active_pings():
		var pp: Vector2 = (ping["position"] - origin) * k
		if pp.length() > r - 6.0:
			pp = pp.normalized() * (r - 6.0)
		out["pings"].append(center + pp)
	if GameState.is_ghost():
		for t in GameState.ghost_tasks():
			if t.get("done", false):
				continue
			var tp := (Protocol.vec2_from(t.get("position", {})) - origin) * k
			if tp.length() > r - 6.0:
				tp = tp.normalized() * (r - 6.0)
			out["tasks"].append(center + tp)
	if players:
		for avatar in players.get_children():
			if avatar == me or not avatar is Player:
				continue
			if not (avatar as Player).visible:
				continue   # oculto (fantasma visto por un vivo) o noqueado en el suelo
			if avatar is PlayerAvatar and (avatar as PlayerAvatar).sight < 0.5:
				continue   # fuera de tu línea de vista: tampoco sale en el minimapa
			var p: Vector2 = (avatar.global_position - origin) * k
			if p.length() > r - 6.0:
				p = p.normalized() * (r - 6.0)
			var skin := str(avatar.get("skin_id")) if avatar is PlayerAvatar else ""
			out["players"].append({"position": center + p, "color": Color(SkinCatalog.skin(skin).get("fur", "#E2E8F0")), "id": avatar.player_id})
	return out

func _draw() -> void:
	var center := size / 2.0
	var r := radius()
	var m := markers()

	# 1. Fondo oscuro de radar de cristal
	draw_circle(center, r, Color(0.06, 0.10, 0.18, 0.85))

	# 2. Silueta del plano de la oficina (sala de reuniones, pasillos y cubículos)
	var me := players.get_player(GameState.local_player_id()) if players else null
	var origin := me.global_position if me else Vector2.ZERO
	var k := r / world_radius

	# Salas del plano (OfficeLayout), el mismo que la oficina 3D y las colisiones.
	var office_rooms := []
	for room in OfficeLayout.rooms():
		var rr: Rect2 = room["rect"]
		office_rooms.append(Rect2(rr.position - origin, rr.size))

	for room in office_rooms:
		var mini_r := Rect2(center + room.position * k, room.size * k)
		draw_rect(mini_r, Color(0.35, 0.55, 0.8, 0.22))
		draw_rect(mini_r, Color(0.45, 0.75, 1.0, 0.35), false, 1.2)

	# 3. Retícula de radar
	draw_arc(center, r * 0.5, 0.0, TAU, 48, Color(1, 1, 1, 0.08), 1.0, true)
	draw_line(center - Vector2(r, 0), center + Vector2(r, 0), Color(1, 1, 1, 0.06), 1.0)
	draw_line(center - Vector2(0, r), center + Vector2(0, r), Color(1, 1, 1, 0.06), 1.0)

	# 4. Pistas descubiertas
	for p in m["evidence"]:
		draw_circle(p, 4.5, Color(UiPalette.AMBER, 0.35))
		draw_circle(p, 3.0, UiPalette.AMBER)

	# 5. Puntos de jugadores con sus colores de animal
	for p in m["players"]:
		draw_circle(p["position"], 5.5, Color(0, 0, 0, 0.7))
		draw_circle(p["position"], 4.0, p["color"])

	# 5b. Misiones fantasma y pings
	for p in m["tasks"]:
		draw_colored_polygon(PackedVector2Array([p + Vector2(0, -6), p + Vector2(5, 0), p + Vector2(0, 6), p + Vector2(-5, 0)]), Color("#C084FC"))
	var beat := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 120.0)
	for p in m["pings"]:
		draw_arc(p, 6.0 + 4.0 * beat, 0.0, TAU, 24, Color("#7DF9FF", 1.0 - 0.6 * beat), 2.0, true)
		draw_circle(p, 3.5, Color("#7DF9FF"))

	# 6. Flecha direccional blanca del jugador local
	var h: Vector2 = m["heading"]
	var side := h.orthogonal()
	var tip: Vector2 = m["me"] + h * 9.0
	draw_colored_polygon(PackedVector2Array([tip, m["me"] - h * 6.0 + side * 5.5, m["me"] - h * 2.5, m["me"] - h * 6.0 - side * 5.5]), Color.WHITE)

	# 7. Aro exterior plateado / cristal de alta definición
	draw_arc(center, r, 0.0, TAU, 72, Color(1, 1, 1, 0.4), 2.2, true)
	draw_arc(center, r - 3, 0.0, TAU, 72, Color(1, 1, 1, 0.12), 1.0, true)
