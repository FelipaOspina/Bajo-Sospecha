class_name CircularMinimap
extends Control
## Minimapa circular centrado en tu avatar. Muestra en tiempo real a los demás
## avatares (con el color de su animal) y los puntos de interés que tu cliente
## conoce: solo las pistas del snapshot en las que ves algo (el servidor ya filtra
## lo que cada jugador percibe). Tú eres la flecha blanca, apuntando hacia donde miras.
## Lo que queda fuera del radio se pega al borde (jugadores) o no se dibuja (pistas).

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
	var out := {"me": center, "heading": Vector2.DOWN, "players": [], "evidence": []}
	if me is PlayerAvatar:
		out["heading"] = (me as PlayerAvatar).heading()
	for i in GameState.snapshot.get("interactables", []):
		if i.get("contents", []).is_empty():
			continue
		var p := (Protocol.vec2_from(i["position"]) - origin) * k
		if p.length() <= r - 5.0:
			out["evidence"].append(center + p)
	if players:
		for avatar in players.get_children():
			if avatar == me or not avatar is Player:
				continue
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
	draw_circle(center, r, Color(UiPalette.NAVY, 0.78))
	draw_arc(center, r * 0.5, 0.0, TAU, 48, Color(1, 1, 1, 0.06), 1.0, true)
	draw_line(center - Vector2(r, 0), center + Vector2(r, 0), Color(1, 1, 1, 0.05), 1.0)
	draw_line(center - Vector2(0, r), center + Vector2(0, r), Color(1, 1, 1, 0.05), 1.0)
	for p in m["evidence"]:
		draw_circle(p, 4.0, Color(UiPalette.AMBER, 0.35))
		draw_circle(p, 2.5, UiPalette.AMBER)
	for p in m["players"]:
		draw_circle(p["position"], 5.0, Color(0, 0, 0, 0.6))
		draw_circle(p["position"], 3.8, p["color"])
	var h: Vector2 = m["heading"]
	var side := h.orthogonal()
	var tip: Vector2 = m["me"] + h * 8.0
	draw_colored_polygon(PackedVector2Array([tip, m["me"] - h * 5.0 + side * 5.0, m["me"] - h * 2.0, m["me"] - h * 5.0 - side * 5.0]), Color.WHITE)
	draw_arc(center, r, 0.0, TAU, 72, border_color, 2.0, true)
