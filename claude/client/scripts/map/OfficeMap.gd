class_name OfficeMap
extends Node2D
## Colisiones 2D de la oficina (muros y muebles) a partir de OfficeLayout. No dibuja nada:
## lo que se ve es la oficina 3D (Office3D, dentro de World3DView), construida con el
## mismo plano, así que lo que se ve y lo que choca coinciden.

func _ready() -> void:
	var body := StaticBody2D.new()
	body.name = "OfficeColliders"
	body.collision_layer = 1
	body.collision_mask = 0
	for r in OfficeLayout.colliders():
		var shape := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = r.size
		shape.shape = rect
		shape.position = r.get_center()
		body.add_child(shape)
	add_child(body)
