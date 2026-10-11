extends SceneTree
## Genera el Theme general del proyecto a partir de UiPalette.build_theme().
## Uso (desde la raíz del repo):
##   godot --headless --path client --script res://tools/build_theme.gd
## Vuelve a ejecutarlo si cambias colores o fuentes en UiPalette.gd.

func _initialize() -> void:
	var theme := UiPalette.build_theme()
	DirAccess.make_dir_recursive_absolute(UiPalette.THEME_PATH.get_base_dir())
	var err := ResourceSaver.save(theme, UiPalette.THEME_PATH)
	print("Theme guardado en ", UiPalette.THEME_PATH) if err == OK else printerr("No se pudo guardar el theme: ", err)
	quit(0 if err == OK else 1)
