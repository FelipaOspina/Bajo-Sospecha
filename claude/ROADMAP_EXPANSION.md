# Hoja de ruta de la expansión

Este documento recoge los sistemas que amplían el juego base: qué hay ya construido, cómo funciona y qué viene después. La descripción completa de la obra está en `DOCUMENTO_TECNICO_PROPIEDAD_INTELECTUAL.md`.

**Estado al 11 de octubre de 2026.**

## SISTEMA DE HABILIDADES TÁCTICAS POR ANIMAL

**Estado:** implementado en el servidor y en el cliente, con pruebas automáticas.

Cada uno de los 12 animales tiene dos habilidades inspiradas en un rasgo real de la especie:

- una **pasiva**, siempre activa;
- una **activa**, que se usa con la tecla **Q** o con el botón redondo de la esquina inferior derecha. Tiene enfriamiento y solo funciona durante la fase de investigación.

Las habilidades dan a cada animal una forma distinta de jugar (moverse, esconderse, vigilar o actuar más rápido) sin que ninguno sea mejor que otro.

### Principios de diseño

1. **Sin pago para ganar.** Los 12 animales y sus habilidades son gratis para todos desde la primera partida. La tienda y el Executive Pass solo ofrecen cosméticos (ropa, gorras, zapatillas y mochilas), que no cambian nada del juego. Los perfiles creados antes de este cambio se migran solos y reciben los 12 animales.
2. **Ninguna habilidad revela roles.** El animal se elige en la sala de espera, antes del reparto secreto de roles, así que el animal (y su habilidad) no dice nada del rol de quien lo lleva. Las habilidades actúan solo sobre el movimiento, las barras de acción (borrar o copiar pruebas), el inventario y los escondites con pruebas que el jugador ya podría ver; ninguna muestra el rol, los objetivos ni el inventario de otro jugador. Las activas marcadas como *secretas* solo las conoce quien las usa. Las públicas se anuncian como "Beto usó Rugido", sin más datos.
3. **Ventajas simétricas.** Cada ventaja sirve igual a quien quiere destruir pruebas que a quien quiere protegerlas. Por ejemplo, el sigilo del zorro también puede usarlo un inocente para sacar una copia sin que lo vean, y la vigilancia del conejo sirve a cualquiera.
4. **Validación en el servidor.** El servidor lee el mismo archivo de datos y es el único que decide. Comprueba la fase, que el jugador siga en juego y el enfriamiento, y aplica cada efecto:
   - la velocidad máxima permitida al validar el movimiento;
   - la duración de las acciones de borrar y copiar;
   - quién ve cada barra de acción y el disfraz de la barra;
   - la capacidad del inventario y el alcance para recoger.

   El cliente solo pide usar la habilidad y muestra el resultado; un cliente modificado no puede darse ventajas.
5. **Topes de seguridad.** Si el archivo de datos trae un multiplicador fuera de rango, el servidor no arranca. Los rangos son: velocidad de 0,5 a 2,5; alcance de 0,5 a 2; duración de acciones de 0,3 a 2; vigilancia de 0,3 a 3; sigilo de 0 a 2. Además, el inventario extra y el alcance solo pueden ser pasivos.

### Los 12 animales

| Animal | Pasiva (siempre activa) | Activa (tecla Q o botón) | Enfriamiento · duración | Rasgo real en que se basa |
|---|---|---|---|---|
| Búho | **Visión nocturna**: Tu linterna alumbra un 35 % más lejos. | **Vuelo silencioso** *(secreta)*: 6 s: nadie ve tus barras de acción y vas un 15 % más rápido. | 45 s · 6 s | Los búhos ven con cien veces menos luz que nosotros. Sus plumas con flecos amortiguan el ruido del vuelo. |
| Zorro | **Astucia**: Tus barras de acción solo se ven desde un 30 % más cerca. | **Engaño** *(secreta)*: 12 s: los demás ven tus acciones como «Revisando papeles…». | 50 s · 12 s | El zorro caza a escondidas y sin hacer ruido. Famoso por despistar a sus perseguidores. |
| Lobo | **Resistencia**: Te mueves un 6 % más rápido. | **Aullido de manada**: 5 s: tú y quien esté a menos de 200 px vais un 20 % más rápido. | 50 s · 5 s | Los lobos recorren decenas de kilómetros al día. El aullido reúne a la manada. |
| Gato | **Curiosidad**: Alcanzas los objetos desde un 15 % más lejos. | **Ojos de gato** *(secreta)*: 8 s: ves las barras de acción de los demás al doble de distancia. | 40 s · 8 s | Un gato lo toca todo con la pata. Sus pupilas se abren para captar cualquier movimiento. |
| Perro | **Trote**: Te mueves un 5 % más rápido. | **Olfato** *(secreta)*: Marca 6 s los escondites a menos de 320 px con pruebas que puedes ver. | 40 s · 6 s | Trotar es su paso natural: rápido y sin cansarse. Su olfato es decenas de miles de veces más fino que el nuestro. |
| Oso | **Fuerza**: Un hueco más en el inventario. | **Embestida**: 2,5 s: vas un 50 % más rápido. | 35 s · 2,5 s | Un oso levanta el triple de su peso. Pese a su tamaño, corre a más de 50 km/h. |
| Panda | **Calma**: Tus acciones aguantan pequeños movimientos y el rugido no las corta. | **Concentración**: 10 s: borras y copias un 35 % más rápido. | 55 s · 10 s | Pasa el día comiendo bambú sin que nada lo altere. Puede pasar horas concentrado en una sola caña. |
| León | **Vista de cazador**: Ves las barras de acción de los demás un 20 % más lejos. | **Rugido**: Corta las acciones (borrar, copiar) de quien esté a menos de 220 px. | 60 s · instantánea | Vigila la sabana desde lejos. Su rugido se oye a 8 km. |
| Tigre | **Camuflaje rayado**: Tus barras de acción solo se ven desde un 20 % más cerca. | **Emboscada**: 2,5 s: vas un 60 % más rápido. | 30 s · 2,5 s | Sus rayas lo esconden entre la maleza. Caza acercándose en silencio y atacando de golpe. |
| Conejo | **Orejas largas**: Ves las barras de acción de los demás un 40 % más lejos. | **Salto**: 1,2 s: vas un 90 % más rápido. | 18 s · 1,2 s | Sus orejas giran para oír a un depredador a lo lejos. Arranca a toda velocidad de un salto. |
| Mapache | **Manos hábiles**: Borras y copias un 15 % más rápido. | **Antifaz** *(secreta)*: 8 s: nadie ve tus barras de acción. | 50 s · 8 s | Sus dedos abren cierres y tapas como manos humanas. El ladronzuelo nocturno del barrio. |
| Pingüino | **Colonia**: Si hay alguien a tu lado (120 px) al empezar, tu acción va un 20 % más rápida. | **Tobogán**: 2 s: te deslizas un 70 % más rápido. | 25 s · 2 s | Los pingüinos se apiñan y se turnan para resistir el frío. Se tumban sobre la barriga y se deslizan por el hielo. |

Cómo leer la tabla:

- **Barras de acción:** cuando alguien borra o copia una prueba, quienes están cerca ven una barra de progreso sobre su cabeza (hasta 500 px por defecto). La vigilancia multiplica esa distancia para quien mira y el sigilo la reduce para quien actúa.
- **Habilidades secretas:** solo las conoce quien las usa. Son Vuelo silencioso, Engaño, Ojos de gato, Olfato y Antifaz.

### Funcionamiento técnico

- **Datos:** `shared/config/abilities/abilities.json`, con una copia para el cliente en `client/data/abilities/`. Cambiar números o textos no requiere tocar código.
- **Servidor:**
  - `server/src/domain/abilities/AbilityCatalog.ts` carga y valida el archivo de datos.
  - `AbilitySystem.ts` gestiona los usos y los enfriamientos, suma los efectos activos y resuelve el rugido, el olfato y el aullido de área. Aplica un margen de 600 ms en la velocidad para absorber la latencia.
  - Integración con el resto del servidor:
    - `Room` atiende la intención `use_ability` y aplica velocidad, inventario y alcance.
    - `ChannelSystem` ajusta la duración de las acciones y la tolerancia de movimiento.
    - `StateProjector` calcula la distancia a la que se ve cada barra (500 px × vigilancia de quien mira × sigilo de quien actúa) y el disfraz del zorro.
  - Los enfriamientos se reinician al empezar cada fase de investigación.
- **Protocolo** (`shared/protocol/protocol.ts`):
  - la intención `use_ability`;
  - el evento `ability_used {by, abilityId, endsAt, marks?, affected?}`, que llega solo a quien la usa si es secreta;
  - el estado privado `you.ability {id, readyAt, activeUntil, cooldownMs}` y `you.speedMultiplier`.
- **Cliente:**
  - `client/scripts/AnimalAbilities.gd` (autoload `Abilities`) contiene:
    - el diccionario de pasivas y activas de los 12 animales;
    - la lógica de enfriamiento;
    - las señales para el HUD: `ability_changed`, `cooldown_changed`, `ability_ready`, `ability_activated`, `ability_ended`, `ability_failed`, `scent_marked` y `ability_seen`.
  - Piezas que usan esas señales:
    - `AbilityButton.gd`: botón con el retrato del animal, barrido oscuro y segundos de recarga, y anillo cian mientras dura el efecto.
    - `ScentMarkers.gd`: anillos ámbar del olfato del perro.
    - `Player.gd`: predicción de la velocidad.
    - `NightLighting.gd`: linterna más amplia del búho.
    - `ChannelPresenter.gd`: tolerancia de movimiento del panda.
  - La pestaña Personajes muestra la pasiva, la activa, sus tiempos y el rasgo real de cada animal.
- **Pruebas:**
  - 7 pruebas automáticas del servidor en `server/test/abilities.test.ts`: catálogo y validación, enfriamiento, acelerones, rugido frente a la calma del panda, sigilo, disfraz, orejas, olfato secreto, aullido de área y pasivas.
  - 24 comprobaciones del cliente en `client/tests/AbilitiesTest`.
- **Capturas:**
  - `docs/ui/hud_habilidad.png`: botón de habilidad en partida.
  - `docs/ui/menu_personajes.png`: ficha de habilidades.
  - `docs/ui/menu_tienda.png`: tienda solo de cosméticos.

### Próximos pasos

- Ajustar enfriamientos y porcentajes con datos de partidas reales: basta con editar el archivo de datos.
- Dibujar iconos propios para cada habilidad. Por ahora, el botón muestra el retrato del animal.

## Otras líneas de la expansión

| Línea | Estado |
|---|---|
| Lobby nocturno con código, Compartir, tipo de caso y Opciones | Implementado |
| Economía solo de cosméticos (tienda, Executive Pass, armario) | Implementado |
| Avatares chibi refinados y horneado de sprites para móvil | Implementado |
| Chibi "vinyl toy" con shader de campos de distancia, luz de estudio y sprites HD de 512×512 con mapa de normales | Implementado |
| Botones de juego conectados (cola, sala privada, unirse, INICIAR) y sofá del lobby reubicado | Implementado |
| Precios de Créditos Nexus en USD y COP según la región | Solo se muestran; falta integrar Google Play Billing (y App Store) para cobrar |
| Mascota del lobby (Alter Ego): hambre, hidratación, comida por especie, caricias, reacciones y sonidos | Implementado; las barras se guardan en el dispositivo (pendiente: guardarlas en el servidor) |
| Sonidos realistas de animales | Hay 27 sonidos sintetizados propios; pendiente cambiarlos por grabaciones con licencia CC0 si se quiere más realismo |
| Servidor en producción (Render, `wss://`) con comprobación de salud | Cliente y servidor listos; el despliegue lo gestiona el autor |
| Casos de Secuestro, Infidelidad, Robo e Investigación | Pendiente: aparecen como "Pronto" hasta que exista su caso |
| Correo, Amigos y Gadgets | Pendiente: pantallas "Próximamente" |
| Ilustraciones PNG por skin | Admitido por el código; faltan las ilustraciones |
| Autenticación y reconexión con token | Pendiente |
