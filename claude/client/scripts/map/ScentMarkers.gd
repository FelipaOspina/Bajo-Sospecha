class_name ScentMarkers
extends Node2D
## Olfato (activa del perro): anillos ámbar que laten sobre los escondites cercanos con
## pruebas que tú puedes ver, mientras dura. Solo los ve quien usó la habilidad (el
## servidor solo le manda a él las marcas). Vive en el mapa, con las coordenadas del mundo.

const COLOR := Color(1.6, 1.1, 0.35, 0.9)   # >1: brilla con el glow aunque sea de noche

var _marks: Array = []   # [{position, radius}]
var _left := 0.0
var _time := 0.0

func _ready() -> void:
	z_index = 50
	Abilities.scent_marked.connect(mark)

func mark(ids: Array, duration_s: float) -> void:
	_marks.clear()
	for id in ids:
		var view := GameState.interactable_view(str(id))
		if view.is_empty():
			continue
		_marks.append({"position": Protocol.vec2_from(view["position"]), "radius": float(view.get("radius", 40.0))})
	_left = duration_s
	queue_redraw()

func marked_count() -> int:
	return _marks.size() if _left > 0.0 else 0

func _process(delta: float) -> void:
	if _left <= 0.0:
		return
	_left -= delta
	_time += delta
	if _left <= 0.0:
		_marks.clear()
	queue_redraw()

func _draw() -> void:
	var fade := clampf(_left / 0.6, 0.0, 1.0)
	for m in _marks:
		var pulse := 0.5 + 0.5 * sin(_time * 6.0)
		var r: float = m["radius"] + 6.0 + pulse * 8.0
		draw_arc(m["position"], r, 0, TAU, 40, Color(COLOR, COLOR.a * fade), 3.0, true)
		draw_arc(m["position"], r + 10.0, 0, TAU, 40, Color(COLOR, 0.35 * fade * (1.0 - pulse)), 2.0, true)
