class_name ItemFrame
extends EvidenceFrame
## Objeto físico genérico (pendrive, llave...). Es el marco por defecto.

func frame_id() -> String:
	return "item"

func view_name() -> String:
	return "ItemView"
