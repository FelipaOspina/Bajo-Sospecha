class_name Interactable
extends Area2D
## Base genérica de cualquier objeto del mapa con el que se puede interactuar
## (pistas, puertas, terminales...). Solo sabe su id, su radio y qué texto
## mostrar; qué pasa al interactuar lo decide cada subclase con interact().
## La escena del mapa usa el mismo `interactable_id` que el servidor.

@export var interactable_id: String
@export var radius := 48.0
@export var prompt_text := "Examinar"

func _ready() -> void:
	add_to_group("interactables")
	if not has_node("CollisionShape2D"):
		var shape := CircleShape2D.new()
		shape.radius = radius
		var col := CollisionShape2D.new()
		col.name = "CollisionShape2D"
		col.shape = shape
		add_child(col)

## Texto del indicador "[E] ..." cuando el jugador lo tiene enfocado.
func get_prompt() -> String:
	return prompt_text

## Lo llama EvidenceSystem cuando el jugador pulsa la tecla de interacción.
func interact() -> void:
	pass
