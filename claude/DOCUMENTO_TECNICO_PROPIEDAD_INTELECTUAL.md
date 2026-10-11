# Documento técnico: memoria descriptiva de la obra

**Obra:** Juego de Roles (título de trabajo; nombre alternativo en estudio: "Bajo Sospecha")
**Tipo de obra:** programa de ordenador (software) y obra multimedia: videojuego multijugador de deducción social
**Titular y autor único:** JUAN FELIPE OSPINA CASTRILLÓN
**Versión descrita:** 0.1.0 (estado del desarrollo al 11 de octubre de 2026)
**Lenguajes:** GDScript y lenguaje de shaders de Godot (cliente); TypeScript (servidor y contrato compartido); JSON (datos de juego)

---

## 1. Descripción general

Juego de Roles es un videojuego multijugador en línea de deducción social ambientado en un "drama corporativo" de estética neo-noir. Entre 4 y 6 jugadores reciben en secreto un rol narrativo (por ejemplo, el CEO, el CTO, el Inversor o el Filtrador de una startup tecnológica acusada de fraude), con objetivos propios que pueden contradecir los de los demás. Durante una fase de investigación recorren una oficina de noche buscando pruebas, que pueden guardar, copiar o destruir según su rol. Después se reúnen en una asamblea del directorio, exponen las pruebas en una mesa pública, debaten y votan un desenlace. El resultado de la votación y las pruebas reveladas o destruidas deciden qué personajes ganan.

Cada caso (escenario) se describe en un archivo JSON propio, de modo que la misma base de software permite crear historias nuevas sin cambiar el código.

## 2. Arquitectura de software

### 2.1 Visión de conjunto

El sistema sigue una arquitectura cliente-servidor con **servidor autoritativo**:

```
┌───────────────────────────┐      WebSocket (JSON)       ┌────────────────────────────┐
│  Cliente Godot 4 (GDScript)│ ── intenciones (intents) ─▶ │  Servidor Node.js + TS      │
│  - Presentación y entrada  │ ◀─ snapshot / delta / event │  - Reglas y estado del juego│
│  - Predicción de movimiento│        ack / rejected        │  - Filtrado por jugador     │
└───────────────────────────┘                              └────────────────────────────┘
              ▲                                                         ▲
              └──────────────  shared/ (contrato común)  ───────────────┘
                     protocolo (protocol.ts) y configuración JSON
                     (roles, pruebas, escenarios, skins, habilidades,
                      cosméticos, progresión)
```

- **Cliente (Godot 4.3, GDScript):** dibuja el mundo y la interfaz, recoge la entrada del jugador y la traduce en *intenciones* (moverse, interactuar, exponer una prueba, votar). No decide ninguna regla.
- **Servidor (Node.js + TypeScript, librería `ws`):** recibe las intenciones, las valida contra las reglas del juego y mantiene el único estado verdadero de cada partida.
- **Contrato compartido (`shared/`):** define el protocolo de mensajes y la configuración de datos que leen los dos lados, para que cliente y servidor no se desincronicen.

### 2.2 Servidor (Node.js + TypeScript)

Organizado por capas, con inyección de dependencias por constructor y principios SOLID:

| Capa | Ubicación | Responsabilidad |
|---|---|---|
| Núcleo | `server/src/core/` | `EventBus` (eventos de dominio), `Result` (resultados sin excepciones), `Random` (azar con semilla, reproducible en pruebas). Sin dependencias de juego. |
| Dominio: roles | `server/src/domain/roles/` | `RoleManager` y sus piezas: carga (`RoleConfigSource`), validación (`RoleConfigValidator`), asignación secreta por sorteo ponderado (`RoleAssignmentStrategy`), visibilidad de pistas por rol (`ClueVisibilityPolicy`), registros extensibles de modificadores y objetivos. |
| Dominio: pruebas | `server/src/domain/evidence/` | `EvidenceSystem` (orquestación), `EvidenceCatalog`, `Inventory`, objetos interactuables (`EvidenceSpot`, `EvidenceContainer`), reglas (fase, alcance, capacidad), `EvidenceAccessPolicy` (permisos de ver y recoger) y `ChannelSystem` (acciones canalizadas con temporizador). |
| Dominio: escenarios | `server/src/domain/scenario/` | `ScenarioAdapter` convierte un caso JSON en roles, pruebas, opciones de voto y finales; `LegacyCaseNormalizer` admite casos escritos en formato libre. |
| Dominio: juicio | `server/src/domain/trial/` | `TrialSystem` (mesa pública y votos), `GameResolution` (evaluación de finales) y `ConditionRegistry` (condiciones combinables: veredicto, rol acusado, pruebas reveladas o destruidas, quién las tiene, y operadores `all`/`any`/`not`). |
| Dominio: skins y perfil | `server/src/domain/skins/`, `server/src/domain/profile/` | Catálogo de skins de animales; perfil del jugador, economía del juego y pase de temporada (ver 3.4). |
| Dominio: habilidades | `server/src/domain/abilities/` | `AbilityCatalog` (carga y valida) y `AbilitySystem` (usos, enfriamientos y efectos): habilidades tácticas por animal (ver 3.6). |
| Dominio: cosméticos | `server/src/domain/cosmetics/` | `CosmeticCatalog`: ropa, gorras, zapatillas y mochilas del avatar, lo único que se compra (ver 3.4). |
| Red | `server/src/net/` | `WsServer` (transporte WebSocket), `RoomDirectory` (enruta conexiones a salas), `Room` (ciclo de una partida), `RoomState`, `StateProjector` (vista filtrada por jugador) y `DeltaEncoder` (diferencias de estado). |
| Composición | `server/src/index.ts` | Crea e inyecta todas las piezas. |

**Sincronización de red.** El servidor funciona a 20 ticks por segundo. Usa dos canales lógicos sobre el mismo socket:

1. **Estado continuo:** un `snapshot` inicial y después `delta` (operaciones de diferencia), solo cuando algo cambia para ese jugador.
2. **Eventos discretos:** `event` inmediato cuando ocurre un hecho (recoger, destruir, exponer, votar, fin de partida).

Cada intención lleva un número de secuencia y recibe `ack` o `rejected`, lo que permite respuesta inmediata en el cliente y reconciliación.

**Información secreta por jugador.** En un juego de deducción, ocultar información es tan importante como sincronizarla. El servidor nunca difunde el estado completo: `StateProjector` construye una vista distinta para cada jugador (su rol y objetivos, su inventario, y las pruebas al nivel de detalle que su rol le permite). Las diferencias se calculan **después** de filtrar, de forma que ni los deltas pueden filtrar datos ocultos. Una prueba automatizada revisa todo el tráfico que recibe cada jugador en busca de secretos ajenos.

**Movimiento.** Predicción local en el cliente, posición autoritativa en el servidor, rechazo de saltos imposibles (margen de 1,5 veces la velocidad máxima) e interpolación de los jugadores remotos.

**Ciclo de una sala:** `lobby → briefing → investigation → discussion → voting → results`.

### 2.3 Cliente (Godot 4, GDScript)

| Parte | Ubicación | Responsabilidad |
|---|---|---|
| Autoloads | `client/autoload/` | `Network` (conexión WebSocket), `GameState` (aplica snapshots y deltas), `EventBus` (señales globales). |
| Protocolo | `client/scripts/net/Protocol.gd` | Espejo del contrato `shared/protocol`. |
| Roles y escenarios | `client/scripts/roles/`, `client/scripts/scenario/` | Lectura de los mismos JSON que el servidor: `ScenarioManager`, `ScenarioParser`, `LegacyCaseNormalizer`, `EvidenceSpawner` (coloca las pistas en el mapa). |
| Pruebas | `client/scripts/evidence/` | Jerarquía `Interactable → InteractableEvidence → EvidenceSpot / EvidenceContainer`, `InteractionDetector` (pista más cercana al alcance), `InventoryManager`. |
| Jugador | `client/scripts/player/`, `client/scenes/player/` | `Player` (movimiento con predicción), `PlayerAvatar` (personaje 2.4D), `PlayerSpawner`, `SkinCatalog`. |
| Mapa | `client/scripts/map/NightLighting.gd` | Iluminación nocturna de la oficina. |
| Juicio | `client/scripts/trial/`, `client/scripts/ui/trial/` | Estado del juicio en el cliente, cartas de prueba arrastrables y zona de exposición. |
| Habilidades | `client/scripts/AnimalAbilities.gd`, `client/scripts/ui/AbilityButton.gd`, `client/scripts/map/ScentMarkers.gd` | Diccionario de habilidades, enfriamientos, señales para el HUD y botón de habilidad (ver 3.6). |
| Menú y sala de espera | `client/scripts/menu/`, `client/scenes/menu/` | Menú principal, sala de espera, personajes, inventario, pase, tienda y configuración (ver 3.4). |
| Interfaz | `client/scenes/ui/`, `client/scripts/ui/` | Ver 3.3. |
| Shaders | `client/shaders/` | Ver 3.2. |
| Composición | `client/scenes/main/Main.tscn` | Une mapa, jugadores, interfaz y red. |

### 2.4 Contrato compartido y datos

- `shared/protocol/protocol.ts`: tipos de intenciones, mensajes del servidor, snapshot por jugador y eventos.
- `shared/config/roles/`, `evidence/`, `scenarios/`, `skins/`, `abilities/`, `cosmetics/`, `progression/`: datos de juego en JSON. El cliente recibe una copia con `tools/sync-config.sh`.

### 2.5 Calidad y pruebas

- Servidor: pruebas automatizadas con `node:test` (roles, pruebas, escenarios, juicio, skins, habilidades, progresión, salas y una partida completa).
- Cliente: escenas de prueba ejecutables sin ventana (`godot --headless`) para escenarios, modal de inspección, barras flotantes, juicio, iluminación nocturna, avatar, HUD y habilidades.
- El código fuente actual suma unas 15.700 líneas entre TypeScript, GDScript y shaders (pruebas incluidas), más los archivos de datos y escenas.

## 3. Módulos desarrollados

### 3.1 Generador procedural de personajes Chibi 2.4D

- **Archivos:** `client/scripts/ProceduralChibiAvatar.gd`, `client/scripts/player/PlayerAvatar.gd`, `client/scenes/player/PlayerAvatar.tscn`, `shared/config/skins/skins.json`.
- **Qué hace:** genera por código, sin imágenes, un personaje "chibi" de proporciones infantiles (cabeza grande, cuerpo pequeño) con traje de oficina, a partir de la descripción de una de las 12 skins de animales (león, lobo, tigre, zorro, gato, perro, oso, panda, conejo, mapache, búho y pingüino): color de pelaje, tipo de orejas, color del traje y acento.
- **2.4D:** el mundo es 2D, pero cada personaje tiene origen y colisión en los pies, sombra propia y orden por profundidad (Y-Sort), lo que da sensación de volumen y de que los personajes pasan por delante o por detrás de los objetos. Tiene vistas de frente, lado y espalda (de espaldas se ocultan los rasgos de la cara).
- **Animación procedural:** `animate_walk()` aplica un rebote de "juguete de cuerda": aplastar y estirar, pasos alternos, brazos que se balancean y orejas con muelle; quieto, el personaje respira.
- **Reglas de diseño:** la apariencia depende de la skin, que es pública, y nunca del rol, que es secreto. La corbata muestra el color del rol solo en el propio personaje del jugador, y la de todos al final de la partida.
- **Cosméticos:** ropa (traje o sudadera y su color), gorra, zapatillas y mochila se ponen sobre cualquier animal (`CosmeticCatalog.dress`). Nunca cambian la corbata.
- **Horneado para móviles** (`client/scripts/ChibiBaker.gd`): en móviles y web, cada combinación de animal y ropa se dibuja una vez en una hoja de sprites (25 poses) y luego se pinta como una sola textura. Así se pasa de unas 60 llamadas de dibujo por personaje a una. Se pierden el parpadeo, la respiración y el muelle de las orejas. Se puede elegir en Configuración → Calidad de los avatares.
- Cuando existan ilustraciones PNG de una skin, `PlayerAvatar` las usa en lugar del chibi procedural.

### 3.2 Shaders e iluminación

| Shader / recurso | Archivo | Efecto |
|---|---|---|
| Volumen de vinilo del chibi | `client/shaders/procedural_chibi_3d.gdshader` | Cada pieza plana del personaje recibe una normal esférica simulada, con luz difusa, brillo especular y luz de borde, para que parezca una figura de vinilo en 3D. Un solo material para todas las piezas. |
| Pantalla CRT | `client/shaders/crt_terminal_screen.gdshader` | Superpuesto a las terminales del visor de pruebas: curvatura de pantalla, líneas de escaneo animadas, aberración cromática y viñeta, calculadas en coordenadas locales del rectángulo. |
| Ambiente con glow | `client/assets/env/office_environment.tres` | Resplandor HDR (solo brilla lo que supera el umbral) y ajuste de brillo, contraste y saturación de la escena. |
| Iluminación nocturna | `client/scripts/map/NightLighting.gd` | Oscurece la oficina con un tono azul noche, dibuja el suelo y coloca luces: una linterna por jugador (más amplia para el jugador local) y una luz ámbar por pista, también para las que aparecen después. La interfaz queda fuera de la noche y conserva su color real. |

El shader CRT y el ambiente con glow proceden del prototipo previo del autor ("Bajo Sospecha") y se adaptaron e integraron en esta base.

### 3.3 Interfaz de usuario

Diseño "Corporate Drama" (neo-noir ejecutivo), con paleta y tipografías centralizadas en `UiPalette.gd` y un tema de Godot generado desde código (`client/assets/ui/corporate_theme.tres`).

- **Visor de inspección de pruebas** (`EvidenceInspectionModal`): elige automáticamente un "dispositivo" según el tipo de prueba: terminal con efecto CRT, teléfono, documento sobre carpeta con pinza u objeto. Usa biseles 9-slice generados por un script propio (`tools/generate_bezels.py`). Si el rol del jugador no tiene permiso, se ve el dispositivo bloqueado sin el contenido. Muestra los botones de copiar o borrar solo a los roles que pueden hacerlo.
- **Barras de progreso flotantes** (`FloatingProgressBar`): sobre el personaje durante una acción canalizada; roja para acciones hostiles (borrar) y cian para copias. Las ven todos los jugadores cercanos y se interrumpen si el personaje se mueve.
- **HUD de oficina** (`OfficeHUD`): panel de tareas con los objetivos secretos del jugador y minimapa circular centrado en él.
- **Mesa de juntas** (`AssemblyBoardUI`): asamblea con temporizador, asientos en arco alrededor de la mesa, zona central donde se arrastran las cartas de prueba, mano de cartas del jugador y panel de votación. Los asientos dicen quién ha votado, pero no qué ni su rol.
- **Pantalla de resolución** (`ResolutionScreen`): veredicto, recuento, finales cumplidos, roles revelados y estado de cada objetivo secreto.
- **Control de fases** (`PhaseViewController`): cambia entre exploración, asamblea y resultados según la fase que indica el servidor.

### 3.4 Sistema de salas, matchmaking y progresión

**Implementado:**

- **Salas por código.** Cada jugador entra con un código de sala; `RoomDirectory` crea la sala la primera vez y la cierra cuando se vacía. Cada sala tiene sus propios roles, pruebas y juicio, independientes de las demás.
- **Sala de espera y reparto secreto.** Cuando todos marcan "listo" y se alcanza el mínimo de jugadores, el servidor reparte los roles al azar según el escenario. En la espera cada jugador puede elegir una skin libre.
- **Desconexión en partida:** el jugador conserva su rol si vuelve y sus pruebas caen al suelo, en el punto libre más cercano.
- **Perfil, economía y pase de temporada (servidor):** `ProfileService` gestiona el perfil del jugador, la experiencia, dos monedas del juego (Monedas Corporativas y Créditos Nexus), la compra de cosméticos y el "Executive Pass" (Temporada 1 "Auditoría Nocturna", 50 niveles con recompensas gratuitas y premium). No hay pagos con dinero real: todo se paga con monedas ganadas jugando. La configuración está en `shared/config/progression/progression.json`.

- **Matchmaking y salas privadas:** cola pública (`queue_match` / `leave_queue`), creación de sala con código de 6 caracteres, abandono de sala y chat de sala.
- **Animales gratis y economía solo de cosméticos:** los 12 animales y sus habilidades son de todos. La tienda y el pase solo dan ropa, gorras, zapatillas, mochilas y monedas; los perfiles antiguos se migran solos.
- **Menú del cliente:** sala de espera nocturna (código, Compartir, tipo de caso y Opciones), Personajes (con la ficha de habilidades), Inventario (armario), Misiones, Executive Pass, Tienda y Configuración.

**En desarrollo:**

- Correo, Amigos y Gadgets (pantallas "Próximamente").
- Casos de Secuestro, Infidelidad, Robo e Investigación (se muestran como "Pronto" en la sala).
- Autenticación y reconexión con token.

### 3.5 Sistemas de juego principales

- **RoleManager:** roles configurables en JSON con equipo, número de plazas, peso en el sorteo, visibilidad (`hidden`, `partial`, `full`) por etiquetas, objetivos y modificadores (`extended_reach`, `inventory_capacity`, `forensic_eye`, `can_destroy_evidence`). El validador informa de todos los errores de configuración a la vez.
- **EvidenceSystem:** pruebas con permisos de ver y recoger por rol o por llave (otra prueba en el inventario), pruebas fijas que no se pueden llevar, y acciones canalizadas de borrar y sacar copia.
- **Escenarios:** un caso completo (roles, objetivos secretos, pistas, posiciones, opciones de voto y finales) en un único JSON, más un normalizador para casos escritos en formato libre.
- **Juicio y resolución:** mesa pública de pruebas, votación narrativa secreta y finales compuestos que permiten que ganen varios bandos.

### 3.6 SISTEMA DE HABILIDADES TÁCTICAS POR ANIMAL

Cada uno de los 12 animales tiene dos habilidades inspiradas en un rasgo real de la especie:

- una **pasiva**, siempre activa;
- una **activa**, que se usa con la tecla **Q** o con el botón redondo de la esquina inferior derecha. Tiene enfriamiento y solo funciona durante la fase de investigación.

Las habilidades dan a cada animal una forma distinta de jugar (moverse, esconderse, vigilar o actuar más rápido) sin que ninguno sea mejor que otro.

#### Principios de diseño

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

#### Los 12 animales

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

#### Funcionamiento técnico

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

## 4. Resumen de las mecánicas de juego

1. **Preparación.** Los jugadores se reúnen en una sala con un código. Cada uno elige un animal (skin), todos gratis y cada uno con su habilidad. Cuando todos están listos, el servidor reparte en secreto los roles del caso. Cada jugador solo conoce su propio rol y sus objetivos.
2. **Briefing.** Se presenta el caso; por ejemplo, "Fraude y Chantaje en la Startup Tecnológica" (NexusCore), con los roles CEO, CTO, Inversor y Filtrador.
3. **Investigación.** Los jugadores recorren la oficina a oscuras con su linterna. Al acercarse a una pista y pulsar E se abre el visor:
   - Cada animal tiene una habilidad activa (tecla Q) y una pasiva, como moverse más rápido, ocultar sus barras de acción o rugir para cortar las de otros (ver 3.6).
   - Según su rol, ven la prueba completa, solo que "hay algo" o nada.
   - Pueden guardarla en el inventario si su rol y sus llaves lo permiten.
   - Las pistas fijas (pantallas, servidores) no se llevan, pero algunos roles pueden **sacar una copia** (por ejemplo, un volcado forense) y otros pueden **borrarlas**. Ambas acciones tardan unos segundos, se interrumpen si el jugador se mueve y los jugadores cercanos ven la barra de progreso, lo que puede delatar a quien destruye pruebas.
4. **Debate (asamblea del directorio).** El mapa se pausa y todos se sientan a la mesa de juntas. Cada jugador puede exponer un número limitado de pruebas; una prueba expuesta la ven todos completa, aunque antes no tuvieran permiso para verla.
5. **Votación.** Se vota en secreto uno de los desenlaces narrativos del caso (por ejemplo, "Despedir y denunciar al CEO"), acusar a un personaje o no acusar a nadie. Un empate deja el caso sin veredicto.
6. **Resolución.** El servidor evalúa los finales del caso combinando el veredicto, el rol acusado y qué pruebas se revelaron, se destruyeron o quedaron en manos de quién. Varios personajes pueden ganar a la vez. Se revelan todos los roles y el estado de cada objetivo secreto.
7. **Progresión.** Al terminar, el jugador gana experiencia y monedas por jugar, ganar y cumplir objetivos, y sube de nivel en el pase de temporada, que da cosméticos y monedas.

## 5. Componentes de terceros

La obra se construye con las herramientas y recursos siguientes, que no son de autoría del titular y se usan conforme a sus licencias:

| Componente | Uso | Licencia |
|---|---|---|
| Godot Engine 4.3 | Motor del cliente | MIT |
| Node.js | Entorno de ejecución del servidor | MIT |
| TypeScript | Lenguaje y compilador del servidor (dependencia de desarrollo) | Apache 2.0 |
| `ws` | Librería WebSocket del servidor | MIT |
| `@types/node`, `@types/ws` | Tipos para TypeScript (dependencias de desarrollo) | MIT |
| Inter, Space Grotesk, JetBrains Mono (Google Fonts) | Tipografías de la interfaz, incluidas en `client/assets/fonts/` | SIL Open Font License 1.1 (textos en `client/assets/fonts/licenses/`) |
| Pillow y NumPy | Usadas solo por el script que genera los biseles (`tools/generate_bezels.py`); no se distribuyen con el juego | Licencia HPND (Pillow) y BSD (NumPy) |

Todo el código fuente del cliente y del servidor, los shaders, los datos de los escenarios, la narrativa de los casos y el diseño de la interfaz y las mecánicas son obra del titular. El shader CRT y el ambiente con glow vienen del prototipo anterior del propio autor ("Bajo Sospecha").

## 6. Relación de archivos principales

```
juego-de-roles/
├── shared/                 Contrato común: protocolo y configuración JSON
├── server/src/             Servidor autoritativo (core, domain, net)
├── server/test/            Pruebas automatizadas del servidor
├── client/autoload/        Red, estado y bus de eventos del cliente
├── client/scripts/         Lógica del cliente (roles, pruebas, escenarios, jugador, mapa, juicio, UI)
├── client/scenes/          Escenas de Godot (principal, jugador, interfaz)
├── client/shaders/         Shaders propios (chibi de vinilo, pantalla CRT)
├── client/assets/          Fuentes, biseles, tema, ambiente y sprites
├── client/tests/           Pruebas del cliente
├── scenarios/              Casos en formato libre
├── docs/                   Documentación técnica, capturas y vídeo de demostración
└── tools/                  Scripts de sincronización y generación de recursos
```

Material de apoyo incluido en `docs/`: capturas de la interfaz (`docs/ui/`), un vídeo de una partida de demostración (`docs/video/partida_demo.mp4`) y el esquema de red (`docs/networking.md`).

---

*Memoria descriptiva preparada a partir del código fuente del proyecto en su estado al 11 de octubre de 2026. Titular y autor único: JUAN FELIPE OSPINA CASTRILLÓN.*
