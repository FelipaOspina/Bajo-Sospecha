class_name EvidenceDropZone
extends PanelContainer
## Centro de la mesa de juntas: acepta cartas de prueba arrastradas desde la mano
## del jugador y se ilumina en ámbar mientras se arrastra algo que se puede exponer.

var can_accept: Callable   # (data) -> bool
var on_drop: Callable      # (data) -> void
var _hover := false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	_restyle()

func _can_drop_data(_at: Vector2, data: Variant) -> bool:
	var ok: bool = can_accept.is_valid() and can_accept.call(data)
	if ok != _hover:
		_hover = ok
		_restyle()
	return ok

func _drop_data(_at: Vector2, data: Variant) -> void:
	_hover = false
	_restyle()
	if on_drop.is_valid():
		on_drop.call(data)

func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END or what == NOTIFICATION_MOUSE_EXIT:
		if _hover:
			_hover = false
			_restyle()

func _restyle() -> void:
	# La mesa: madera oscura lacada, con borde ámbar al pasar una carta por encima.
	var s := UiPalette.flat(Color("#1A2236") if _hover else Color("#121A2B"),
		UiPalette.AMBER if _hover else Color(UiPalette.AMBER, 0.25), 2, 48, 24)
	s.shadow_color = Color(0, 0, 0, 0.5)
	s.shadow_size = 18
	add_theme_stylebox_override("panel", s)
