class_name InteractionDetector
extends Area2D
## Se cuelga del jugador local. Detecta interactuables cercanos y decide cuál
## está "enfocado" (el más cercano dentro del alcance predicho por el rol).
## Responsabilidad única: percepción espacial. No envía nada por red.

signal focus_changed(interactable: Interactable)

var role_manager: RoleManager
var focused: Interactable

var _nearby: Array[Interactable] = []

func _ready() -> void:
	area_entered.connect(_on_area_entered)
	area_exited.connect(_on_area_exited)

func _on_area_entered(area: Area2D) -> void:
	if area is Interactable:
		_nearby.append(area)

func _on_area_exited(area: Area2D) -> void:
	if area is Interactable:
		_nearby.erase(area)

func _physics_process(_delta: float) -> void:
	var reach: float = role_manager.local_stats["interact_range"] if role_manager else 64.0
	var best: Interactable = null
	var best_d := INF
	for i in _nearby:
		var d := global_position.distance_to(i.global_position)
		if d <= reach + i.radius and d < best_d:
			best = i
			best_d = d
	if best != focused:
		if focused:
			EventBus.interactable_unfocused.emit(focused)
		focused = best
		if focused:
			EventBus.interactable_focused.emit(focused)
		focus_changed.emit(focused)
