# Sprites

Arte final de personajes, objetos y mapa. Convención sugerida:

- `skins/<animal>/` — skins de los personajes (ver abajo).
- `props/` — objetos del mapa (servidor, laptop, basurero, cafetera...).
- `map/` — suelos, paredes y decorado de las salas.

Mientras no haya arte, el juego dibuja marcadores con `Polygon2D` (ver `EvidenceSpawner`).

## Skins de animales

Una carpeta por skin del catálogo (`client/data/skins/skins.json`, copia de
`shared/config/skins/skins.json`): leon, lobo, tigre, zorro, gato, perro, oso, panda,
conejo, mapache, buho y pinguino. Cada una admite cuatro vistas:

| Archivo          | Cuándo se usa                                   |
|------------------|-------------------------------------------------|
| `frente.png`     | quieto o caminando hacia abajo (obligatoria)    |
| `lado.png`       | caminando a izquierda o derecha (se voltea sola) |
| `espalda.png`    | caminando hacia arriba                          |
| `caminando.png`  | caminando hacia abajo (si falta, usa `frente`)  |

- Fondo transparente, el personaje de pie con los pies en el borde inferior.
- Una imagen = un fotograma. Para animar, pon los fotogramas en una tira horizontal
  de cuadros del mismo tamaño (ancho = alto × número de fotogramas); se reproduce a 8 fps.
- El avatar escala la imagen a unos 56 px de alto en el mapa.
- Si falta `frente.png`, el avatar dibuja el chibi procedural
  (`scripts/ProceduralChibiAvatar.gd` + `shaders/chibi_sdf.gdshader`)
  con los colores de la skin. No hace falta tocar código al añadir los PNG.

## Sprites HD (`hd/`)

Los 12 animales de frente a 512×512 (`<animal>.png`) y su mapa de normales
(`<animal>_normal.png`, convención OpenGL/Godot: verde hacia arriba). Los exporta
`tools/ExportHdSprites.tscn` desde el mismo shader del juego, así que encajan píxel a
píxel. El juego no los usa: son para la tienda de apps, prensa, el registro de la obra y
como referencia para un arte final. Para regenerarlos (hace falta GPU o un servidor X
virtual): `godot --path client res://tools/ExportHdSprites.tscn`.
