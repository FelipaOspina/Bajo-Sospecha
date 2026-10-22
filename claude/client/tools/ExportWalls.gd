extends Node
## Exporta los muros del plano (OfficeLayout.walls() y BOUNDS) a JSON para el servidor,
## que los usa para la línea de vista del evento "witnessed" (silenciar a un testigo).
## Todos los tramos tapan la vista, igual que en LineOfSight.gd; los huecos entre
## tramos son las puertas.
##
## Formato: {"version":1,"bounds":[x,y,w,h],"walls":[[ax,ay,bx,by],…]} en píxeles del
## mundo 2D.
##
## Uso (sin GPU vale): godot --headless --path client res://tools/ExportWalls.tscn
## Escribe res://data/maps/office_walls.json y la copia del servidor en
## <raíz>/shared/config/maps/office_walls.json (o en WALLS_SHARED si se indica).
## Hay que volver a ejecutarlo cada vez que cambie OfficeLayout.

const CLIENT_OUT := "res://data/maps/office_walls.json"
## Rutas de la carpeta compartida relativas a la del cliente (repo y copia de trabajo).
const SHARED_CANDIDATES := ["../shared/config", "../dev/shared/config"]

func _ready() -> void:
	var text := to_json()
	var ok := _write(ProjectSettings.globalize_path(CLIENT_OUT), text)
	var shared := OS.get_environment("WALLS_SHARED")
	if shared == "":
		var root := ProjectSettings.globalize_path("res://")
		for c in SHARED_CANDIDATES:
			if DirAccess.dir_exists_absolute(root.path_join(c)):
				shared = root.path_join(c).path_join("maps/office_walls.json").simplify_path()
				break
	if shared != "":
		ok = _write(shared, text) and ok
	else:
		push_warning("ExportWalls: no encuentro shared/config; solo se escribe la copia del cliente")
	print("ExportWalls: %d muros" % OfficeLayout.walls().size())
	get_tree().quit(0 if ok else 1)

## JSON con un muro por línea (fácil de revisar en un diff).
static func to_json() -> String:
	var b := OfficeLayout.BOUNDS
	var lines := PackedStringArray()
	for w in OfficeLayout.walls():
		var a: Vector2 = w["a"]
		var e: Vector2 = w["b"]
		lines.append("    [%s, %s, %s, %s]" % [_n(a.x), _n(a.y), _n(e.x), _n(e.y)])
	return "{\n  \"version\": 1,\n  \"bounds\": [%s, %s, %s, %s],\n  \"walls\": [\n%s\n  ]\n}\n" % [
		_n(b.position.x), _n(b.position.y), _n(b.size.x), _n(b.size.y), ",\n".join(lines)]

static func _n(v: float) -> String:
	return str(int(v)) if is_equal_approx(v, roundf(v)) else str(v)

func _write(path: String, text: String) -> bool:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("ExportWalls: no puedo escribir %s" % path)
		return false
	f.store_string(text)
	f.close()
	print("ExportWalls: escrito ", path)
	return true
