class_name CaseThumb
extends Control
## Miniatura del caso en la tarjeta de la sala: la ciudad de noche desde el piso 14.

var _buildings: Array = []

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rng := RandomNumberGenerator.new()
	rng.seed = 4587
	var x := 0.0
	while x < 1.0:
		var w := rng.randf_range(0.05, 0.11)
		var lit: Array = []
		for i in 14:
			if rng.randf() < 0.35:
				lit.append(Vector2(rng.randf(), rng.randf()))
		_buildings.append({"x": x, "w": w, "h": rng.randf_range(0.3, 0.85), "lit": lit})
		x += w + rng.randf_range(0.0, 0.02)
	resized.connect(queue_redraw)

func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	draw_polygon(PackedVector2Array([r.position, Vector2(r.end.x, 0), r.end, Vector2(0, r.end.y)]),
		PackedColorArray([Color("#1A1240"), Color("#1A1240"), Color("#C0607A"), Color("#C0607A")]))
	for b in _buildings:
		var br := Rect2(b["x"] * size.x, size.y * (1.0 - b["h"]), b["w"] * size.x, size.y * b["h"])
		draw_rect(br, Color("#0B0F1D"))
		for p in b["lit"]:
			draw_rect(Rect2(br.position + Vector2(p.x * (br.size.x - 3), p.y * (br.size.y - 4)), Vector2(2, 3)), Color("#FFD38A", 0.9))
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color.TRANSPARENT
	sb.border_color = Color(1, 1, 1, 0.18)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(8)
	draw_style_box(sb, r)
