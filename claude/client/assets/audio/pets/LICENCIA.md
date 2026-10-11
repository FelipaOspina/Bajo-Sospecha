# Sonidos de la mascota del lobby: origen y licencia

## Origen

- **Cómo se hicieron:** los 27 archivos `.wav` de esta carpeta los genera el script del proyecto `client/tools/gen_pet_sfx.py`.
  - La síntesis es de fuente y filtro: osciladores con armónicos y ruido, pasados por filtros de formantes y envolventes.
  - Cada sonido sale de una función con nombre, por ejemplo `gato_caricia` (ronroneo) o `perro_feliz` (dos ladridos).
- **Sin material de terceros:** no se usaron grabaciones, muestras, bancos de sonido ni sonidos generados por inteligencia artificial.
- **Reproducibles:** las semillas del ruido son fijas. Ejecutar `python3 client/tools/gen_pet_sfx.py` vuelve a crear exactamente los mismos archivos.
- **Autoría y licencia:**
  - Son obra original del proyecto, igual que el código que los genera.
  - Autor y titular: JUAN FELIPE OSPINA CASTRILLÓN.
  - Tienen la misma licencia que el resto del juego.

## Archivos

| Archivo | Cuándo suena | Qué imita |
|---|---|---|
| `<animal>_feliz.wav` | al tocar a tu animal | su sonido de alegría |
| `<animal>_caricia.wav` | al acariciarlo | un sonido de gusto más bajito |
| `comer.wav` | al darle su comida | mordiscos crujientes |
| `beber.wav` | al darle agua | lengüetazos |
| `lleno.wav` | si ya está lleno o no tiene sed | un "mm-mm" de "no, gracias" |

Sonido de cada animal (`_feliz` / `_caricia`):

| Animal | Al tocarlo | Al acariciarlo |
|---|---|---|
| León | gruñido-rugido suave | retumbo grave |
| Lobo | aullido suave | gemido cariñoso |
| Tigre | tres resoplidos (el saludo amistoso de los tigres) | resoplido largo con retumbo |
| Zorro | tres "yips" agudos | castañeteo contento ("gekker") |
| Gato | maullido "mi-a-u" | ronroneo |
| Perro | dos ladridos alegres | jadeo con un gemidito |
| Oso | dos resoplidos graves | zumbido "mmm" |
| Panda | balido (los pandas gigantes balan) | chillidos de cachorro |
| Conejo | golpe de pata y dos "honks" | "ronroneo" de dientes |
| Mapache | trino-castañeteo | ronroneo agudo |
| Búho | "hu-huuu" | trino grave |
| Pingüino | rebuzno de cortejo, en miniatura | piídos suaves |

## Límites

- **No son grabaciones de animales reales:** son aproximaciones sintéticas con un toque de dibujo animado. Se reconocen, pero no suenan como un animal grabado.
- **Cómo cambiarlos por grabaciones reales:**
  - Deja en esta carpeta un `.wav` con el mismo nombre, y el juego lo usa sin tocar código.
  - Usa solo audio con licencia que lo permita, por ejemplo CC0 (dominio público), y apunta en esta tabla la fuente, el autor y la licencia de cada archivo.
  - Así el registro de la obra sigue en orden.
