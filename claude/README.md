# Juego de Roles: base de código

Juego multijugador de deducción social con roles narrativos y recolección de pruebas.

- **Cliente:** Godot 4 (GDScript).
- **Servidor autoritativo:** Node.js + TypeScript, WebSocket.
- **Contrato compartido:** `shared/` (protocolo y configuración JSON de roles y pruebas).

## Estructura

```
juego-de-roles/
├── shared/                         # Fuente única de verdad entre cliente y servidor
│   ├── protocol/protocol.ts        # Intenciones, mensajes, snapshots, eventos
│   └── config/
│       ├── roles/mansion_clasica.json      # Roles, visibilidad, objetivos, modificadores
│       ├── evidence/mansion_clasica.json   # Catálogo de pruebas y objetos del mapa
│       └── scenarios/nexuscore_fraude.json # Caso completo (roles + pistas) en un solo archivo
├── server/
│   ├── src/
│   │   ├── core/                   # EventBus, Result, Random (sin dependencias de juego)
│   │   ├── domain/
│   │   │   ├── roles/              # RoleManager y sus piezas
│   │   │   │   ├── RoleManager.ts
│   │   │   │   ├── RoleConfigSource.ts      # IRoleConfigSource: fichero / memoria
│   │   │   │   ├── RoleConfigValidator.ts
│   │   │   │   ├── assignment/              # IRoleAssignmentStrategy (sorteo ponderado)
│   │   │   │   ├── modifiers/               # IModifierHandler + registro
│   │   │   │   ├── objectives/              # IObjectiveHandler + registro
│   │   │   │   └── visibility/              # IVisibilityPolicy
│   │   │   ├── scenario/           # ScenarioAdapter + LegacyCaseNormalizer (casos en formato libre)
│   │   │   ├── trial/              # TrialSystem (mesa pública, votos), GameResolution, condiciones de final
│   │   │   └── evidence/           # EvidenceSystem y sus piezas
│   │   │       ├── EvidenceSystem.ts
│   │   │       ├── EvidenceCatalog.ts
│   │   │       ├── Inventory.ts             # IInventory, IInventoryStore
│   │   │       ├── interactables/           # IInteractable, IEvidenceSource, IEvidenceDropTarget
│   │   │       └── rules/                   # IEvidenceRule: alcance, fase, capacidad...
│   │   ├── net/                    # Room, RoomDirectory (salas por código), StateProjector, DeltaEncoder, WsServer
│   │   └── index.ts                # Composition root
│   └── test/                       # node:test (27 tests)
├── client/                         # Proyecto Godot 4
│   ├── autoload/                   # EventBus, Network, GameState
│   ├── scripts/
│   │   ├── roles/                  # RoleManager, RoleDefinition, RoleConfigSource, ModifierRegistry
│   │   ├── evidence/               # EvidenceSystem, Interactable → InteractableEvidence → EvidenceSpot /
│   │   │                           # EvidenceContainer, InteractionDetector, InventoryManager, EvidenceData
│   │   ├── scenario/               # ScenarioManager, ScenarioData, ScenarioParser, LegacyCaseNormalizer, EvidenceSpawner...
│   │   ├── trial/TrialSystem.gd    # Estado del juicio en el cliente
│   │   ├── net/Protocol.gd         # Espejo de shared/protocol
│   │   ├── player/                 # Player (movimiento con predicción), PlayerSpawner
│   │   └── ui/                     # evidence_inspection_modal, floating_progress_bar, assembly_board_ui,
│   │       │                       # UiPalette, ChannelPresenter, PhaseViewController, TrialAssemblyManager, ResolutionScreen
│   │       ├── frames/             # EvidenceFrames + vistas: TerminalFrame, PhoneFrame, PaperFrame, ItemFrame
│   │       └── trial/              # EvidenceCard (arrastrable), EvidenceDropZone (centro de la mesa)
│   ├── scenes/main/Main.tscn       # Composition root del cliente
│   ├── scenes/ui/                  # EvidenceInspectionModal, FloatingProgressBar, AssemblyBoardUI, ResolutionScreen
│   ├── scripts/pet/                # Mascota del lobby: PetCare, PetReactions, PetIcons, PetPanel, PetSfx
│   ├── shaders/                    # chibi_sdf (chibi de vinilo), baked_sheet (hoja horneada), crt_terminal_screen
│   ├── assets/audio/pets/          # 27 sonidos de la mascota (tools/gen_pet_sfx.py) + LICENCIA.md
│   ├── assets/sprites/hd/          # 12 animales a 512×512 con mapa de normales (tools/ExportHdSprites.tscn)
│   ├── tests/                      # godot --headless res://tests/<ScenarioTest|EvidenceInspectionModalTest|FloatingProgressBarTest|TrialTest|NightLightingTest|PlayerAvatarTest|OfficeHUDTest|AbilitiesTest|StorePricesTest|ServerUrlTest|PetCareTest|PetLobbyTest>.tscn
│   └── data/                       # Copia de shared/config (tools/sync-config.sh)
├── docs/networking.md              # Esquema de sincronización
└── tools/sync-config.sh
```

## Cómo se aplica SOLID

| Principio | Dónde |
|---|---|
| **S** Responsabilidad única | Cargar (`RoleConfigSource`), validar (`RoleConfigValidator`), asignar (`WeightedRoleAssignment`) y consultar (`RoleManager`) son clases distintas. En pruebas: catálogo, inventario, objetos, reglas y orquestación (`EvidenceSystem`) separados. `StateProjector` es el único que decide qué ve cada jugador. |
| **O** Abierto/cerrado | Nuevos modificadores, objetivos, reglas de pruebas y tipos de objeto se **registran**; no se edita `RoleManager` ni `EvidenceSystem`. |
| **L** Sustitución de Liskov | `EvidenceSpot` y `EvidenceContainer` cumplen `IEvidenceSource`/`IEvidenceDropTarget` y son intercambiables para el sistema. En Godot, `EvidenceSpot`/`EvidenceContainer` extienden `Interactable`. |
| **I** Segregación de interfaces | `EvidenceSystem` solo ve `IRoleQuery` (4 métodos), no el `RoleManager` completo; y `IWorldQuery` en vez de la sala. Un objeto puede ser fuente, destino o ambos. |
| **D** Inversión de dependencias | Todo se inyecta por constructor (`RoleManagerDeps`, `EvidenceSystemDeps`). El dominio publica en `IEventSink`; la red se suscribe. `Room` habla con `IClientTransport`, no con WebSocket. |

## Configurar roles (JSON)

```jsonc
{
  "id": "detective",
  "team": "investigadores",
  "count": { "min": 1, "max": 1 },   // plazas garantizadas / tope
  "weight": 0,                       // probabilidad al rellenar plazas libres (0 = solo por mínimo)
  "knowsTeammates": false,
  "visibility": {
    "default": "partial",            // hidden | partial | full
    "rules": [{ "tags": ["fisica"], "level": "full" }]   // si chocan reglas, gana la más restrictiva
  },
  "objectives": [{ "id": "reunir", "type": "collect_evidence", "params": { "tags": ["fisica"], "count": 3 } }],
  "modifiers":  [{ "id": "extended_reach", "params": { "multiplier": 1.5 } }]
}
```

- **Visibilidad:** `hidden` = ni sabes que existe; `partial` = ves que hay "algo" pero no qué es; `full` = nombre, descripción y etiquetas. Lo que llevas encima siempre es `full`.
- **Modificadores incluidos:** `extended_reach`, `inventory_capacity`, `forensic_eye` (eleva a `full` ciertas etiquetas), `can_destroy_evidence`.
- **Objetivos incluidos:** `collect_evidence`, `keep_evidence_hidden`, `accuse_culprit`.
- El validador rechaza ids duplicados, niveles desconocidos, modificadores/objetivos sin handler y combinaciones de `count` que no cuadran con `minPlayers`/`maxPlayers`, y lista **todos** los problemas a la vez.

## Escenarios (casos)

Un escenario reúne en un JSON todo lo de un caso. Lo leen **los dos lados**: el `ScenarioManager` de Godot (para la UI y para colocar las pistas) y el servidor con `SCENARIO=<id>` (para la lógica real).

```jsonc
{
  "format_version": 1,
  "scenario_id": "nexuscore_fraude",
  "title": "Fraude y Chantaje en la Startup Tecnológica",
  "player_count": { "min": 4, "max": 6 },          // opcional: si falta, suma de count
  "roles": [{
    "id": "ROLE_CTO", "name": "El CTO", "description": "...",
    "team": "inocentes",                           // opcional (por defecto, su propio id)
    "count": { "min": 1, "max": 1 }, "weight": 0,   // opcional
    "secret_objectives": [
      "Texto libre: objetivo narrativo, se muestra pero no se evalúa solo",
      { "id": "pendrive", "description": "...", "type": "collect_evidence",
        "params": { "tags": ["pista:CLUE_ENCRYPTED_PENDRIVE"], "count": 1 } }
    ]
    // opcionales: visibility, modifiers (mismo formato que los sets de roles)
  }],
  "evidence_spawns": [{
    "id": "CLUE_SERVER_LOGS", "name": "...", "description": "...",
    "type": "text",                                // text | audio | photo | item
    "position": { "x": 200, "y": 150 },            // o [200, 150]
    "benefits": ["ROLE_CTO"], "harms": ["ROLE_CEO"],
    "medium": "digital/critica",                   // opcional: aspecto exterior; elige el marco del visor
    "pocketable": false,                           // opcional: no se puede llevar (pantallas, servidores)
    "content": { "text": "..." },                  // audio: {"audio": "res://..."}, photo: {"image": "res://..."}
    "actions": [                                   // opcional: acciones canalizadas por rol
      { "kind": "delete", "label": "Purgar partición /var/log/audit.log", "roles": ["ROLE_CEO"], "seconds": 10 },
      { "kind": "backup", "label": "Descargar dump forense", "roles": ["ROLE_CTO", "ROLE_LEAKER"], "seconds": 6 } ]
  }]
}
```

Qué hace el sistema con cada campo:
- Cada pista recibe etiquetas automáticas `pista:<id>`, `tipo:<type>`, `beneficia:<rol>` y `perjudica:<rol>`. Con ellas, objetivos y modificadores pueden referirse a pistas y roles concretos (por ejemplo, el CEO puede destruir lo que tenga `perjudica:ROLE_CEO`).
- Un rol sin `visibility` ve todo en parcial, salvo las pistas que le benefician, que ve completas.
- Cada pista se instancia como un `Interactable` con id `spawn_<id>`, el mismo en cliente y servidor, en su `position`.
- El parser lista todos los errores a la vez (ids duplicados, tipos desconocidos, posiciones mal escritas, roles inexistentes en `benefits`/`harms`). Los campos extra se ignoran con un aviso.
- `EvidenceSpawner` crea un marcador por tipo; con `register_scene(tipo, escena)` se usa una escena propia.

`nexuscore_fraude.json` es el caso de `scenarios/caso_fraude_tech_startup.json` pasado a este formato. Las posiciones son provisionales (una por sala) porque el original no tenía coordenadas, y se añadió un rol de relleno "Empleado" para 5–6 jugadores.

## Inspección de pistas y permisos especiales

Flujo en el cliente: el jugador se acerca (`InteractionDetector` enfoca el `InteractableEvidence` más cercano a su alcance), pulsa **E**, se abre `EvidenceInspectionModal` (ver *Interfaz*) y, si puede, pulsa **Guardar** o una de las acciones de su rol. Eso envía `interact` con la pieza concreta; el servidor valida y, al confirmarlo, `InventoryManager` emite `item_added` y el visor se cierra. Mientras el visor está abierto el jugador no se mueve.

Permisos, en la pista (`requires` en escenarios, `access` en `shared/config/evidence`):

```jsonc
"requires": {
  "view":    { "roles": ["ROLE_CEO", "ROLE_CTO"] },     // solo estos roles ven los detalles
  "collect": { "items": ["llave_estudio"] }              // para llevártela necesitas esta pista en el inventario
}
```

- Se cumple un requisito si tienes **uno** de los `roles` **y todos** los `items`. Recoger exige también el permiso de ver.
- Lo aplica el servidor: sin permiso de ver, la pista llega en parcial y sin detalles (no se pueden sacar del tráfico de red). El visor muestra el candado y el nombre de la llave que falta; nunca dice qué rol hace falta.
- Ejemplos: los logs de NexusCore solo los leen CEO, CTO y Filtrador; la carta de la mansión necesita la llave del estudio.

## Salas y reparto secreto de roles

- Cada jugador se une con un código de sala (`roomCode`; vacío = sala pública). `RoomDirectory` crea la sala la primera vez y la cierra cuando se queda vacía. Cada sala tiene su propio RoleManager, pruebas y juicio.
- Cuando todos pulsan "listo" y hay `minPlayers`, el servidor reparte los roles al azar según el escenario (`count` y `weight`).
- Cada jugador recibe **solo** su rol, sus objetivos secretos y su inventario (`you`). De los demás solo ve nombre, posición y cuántas pruebas llevan; los compañeros que se conocen (`knows_teammates`) sí ven el rol del otro. Los roles se revelan a todos en la resolución. Hay un test que revisa **todo** el tráfico que recibe cada jugador buscando secretos ajenos.
- Movimiento: predicción local + posición autoritativa a 20 Hz. Recoger o destruir una pista la quita del objeto para todos en el siguiente tick.

## Juicio y resolución

Fases: investigación → **debate** (`discussion`) → **votación** (`voting`) → resolución.

- **Mesa pública (`PublicEvidenceDeck`)**: en el debate y la votación cada jugador puede exponer hasta `max_presented_per_player` pruebas. Una prueba expuesta la ven todos completa, aunque no tuvieran permiso para verla.
- **Pistas fijas** (`pocketable: false`, como pantallas o servidores): no se llevan, pero los roles con `backup` sacan una **copia** (dump, foto, captura) que va al inventario y sí se puede exponer. Quien tenga `delete` la borra en el sitio. Las dos cosas son acciones canalizadas (ver abajo).
- **Votación narrativa**: se vota una de las `trial.options` del escenario (`"Despedir y denunciar al CEO"`, `"Encubrir la infidelidad"`...). Una opción puede acusar a un rol (`accuses_role`). Opcionalmente "Acusar a <jugador>" y "No acusar a nadie". El voto es secreto hasta la resolución; si votan todos, se resuelve sin esperar. Empate = sin veredicto.
- **GameResolution**: evalúa todos los `endings`; cada final cumplido suma sus ganadores (pueden ganar varios bandos). Condiciones disponibles: `verdict`, `accused_role`, `revealed_all/any/count`, `destroyed_all/any`, `held_by_role`, `all`, `any`, `not`. Sin `endings` pero con `culprit_roles`, se usa el final "¿se acusó al culpable?". La pantalla final muestra veredicto, recuento, finales, roles y el estado de cada objetivo secreto.

```jsonc
"trial": { "max_presented_per_player": 2, "options": [
  { "id": "despedir_ceo", "label": "Despedir y denunciar al CEO", "accuses_role": "ROLE_CEO" } ] },
"endings": [{
  "id": "cto_gana", "title": "El CTO limpia su nombre",
  "when": { "all": [ { "verdict": "despedir_ceo" }, { "revealed_all": ["CLUE_SERVER_LOGS", "CLUE_UNLOCKED_LAPTOP"] } ] },
  "winners": { "roles": ["ROLE_CTO"] } }]
```

## Acciones canalizadas (borrar / sacar copia)

- `channel_start {evidenceInstanceId, action}`: el servidor comprueba rol, alcance y que no estés haciendo otra cosa, y arranca un temporizador. Si te mueves más de 6 px, te desconectas o la pista desaparece, se interrumpe (`channel_finished ok=false` con el motivo).
- Al terminar: `delete` destruye la pista para todos; `backup` crea una copia (`isCopy`) en tu inventario, aunque el original sea fijo. La copia guarda el contenido del original, así que sigue valiendo si después lo borran.
- La barra la ven todos los jugadores a menos de 500 px (`players[].channel` en el estado), con la hora de inicio del servidor para que quien llega tarde la vea a la mitad.

## Interfaz (UI)

Escenas en `client/scenes/ui/`, scripts en `client/scripts/ui/`. Sigue la guía "Corporate Drama" (Neo-Noir ejecutivo): los colores, tipografías y el panel de cristal están en `UiPalette.gd` (`#0B0F19` fondo, `#161F30` paneles, `#E5A93C` ámbar, `#00E5FF` cian, `#FF334B` rojo, `#E2E8F0` texto). Las fuentes van incluidas en `client/assets/fonts/` (Space Grotesk para títulos, Inter para texto, JetBrains Mono para terminal y logs; licencia SIL OFL 1.1 en `assets/fonts/licenses/`). Son fuentes variables: `UiPalette` elige el peso con `FontVariation`. El Theme general del proyecto (`client/assets/ui/corporate_theme.tres`, puesto en `project.godot` → `gui/theme/custom`) se genera desde `UiPalette.build_theme()` con `godot --headless --path client --script res://tools/build_theme.gd`; vuelve a ejecutarlo si cambias colores o fuentes. Los biseles del modal (`client/assets/ui/bezels/bezel_smartphone.png`, `bezel_monitor.png`, `bezel_paper_clipboard.png`, PNG con fondo transparente) se generan con `python3 tools/generate_bezels.py` (Pillow + numpy) y se usan como 9-slice en `DeviceBezelTexture` (`NinePatchRect`); los márgenes de cada uno están en su vista (`bezel_patch()`, `bezel_padding()`). Si falta un PNG, la vista dibuja su bisel con estilos. La pantalla de `TerminalView` lleva encima `CRTOverlay`, un `ColorRect` con `client/shaders/crt_terminal_screen.gdshader` (curvatura, líneas de escaneo, aberración, viñeta; parámetros en el inspector del material). El ambiente `client/assets/env/office_environment.tres` (glow HDR y ajuste de color) está en el `WorldEnvironment` de `Main.tscn`, con `rendering/viewport/hdr_2d=true`: solo brillan los colores por encima de 1.0 (p. ej. `self_modulate` > 1), y el glow solo se ve con el renderizador Forward+ o Mobile, no con Compatibility. Ambos vienen del prototipo "Bajo Sospecha" hecho con Antigravity.

El Theme cubre botones, paneles (`Panel` y `PanelContainer` con el cristal oscuro), etiquetas (texto claro y color de contorno negro), barras de progreso, menús y tooltips; todo nodo de UI sin estilo propio lo hereda. El arte final va en `client/assets/`: `fonts/`, `ui/bezels/` y `sprites/` (personajes, objetos y mapa; las convenciones están en `assets/sprites/README.md`).

**Ambiente nocturno.** `Map/NightLighting` (`client/scripts/map/NightLighting.gd`) añade un `CanvasModulate` azul oscuro (`#2A3350`) y un suelo de moqueta, y pone una `PointLight2D` a cada jugador (linterna más amplia para el jugador local) y a cada pista (luz ámbar), también a los que aparecen después. Solo oscurece el mundo: el modal, la mesa de juntas y las barras flotantes están en sus propios CanvasLayers y se ven con su color real. Para ajustar la noche, cambia `night_color` y las escalas de luz en el inspector. Capturas: `docs/ui/mapa_nocturno.png` y `docs/ui/mapa_nocturno_modal.png`.

**Avatar del jugador.** Cada jugador es un `PlayerAvatar` (`client/scenes/player/PlayerAvatar.tscn`, preparado para 2.4D). Es un CharacterBody2D con el origen y la colisión en los pies. Debajo tiene `Visuals` con Y-Sort, que contiene `DropShadow` y `BodySprite` (AnimatedSprite2D). El mapa ordena por Y a jugadores y pistas. El nombre va en una píldora oscura translúcida (`NameTag`) y la barra de canalización encima; los dos están en CanvasLayers propios, así que no giran con el cuerpo ni los oscurece la noche. Mira `docs/ui/hud_oficina.png`.

**Skins de animales.** El catálogo está en `shared/config/skins/skins.json`, con 12 animales: león, lobo, tigre, zorro, gato, perro, oso, panda, conejo, mapache, búho y pingüino.
- El servidor reparte una skin libre a cada jugador al entrar. En el lobby se puede cambiar con el intent `choose_skin` (`{"skinId": "panda"}`); se rechaza si otro la lleva.
- La skin es pública y no depende del rol. `assign_by_role: true` haría que cada rol lleve su animal de `role_skins` (CEO león, CTO lobo, Inversor tigre, Filtrador zorro), pero eso delata el rol a todos, por eso viene en `false`.
- Los PNG van en `client/assets/sprites/skins/<animal>/{frente,lado,espalda,caminando}.png`; el formato está en `client/assets/sprites/README.md`.
- Mientras falte `frente.png`, el avatar dibuja el chibi procedural: `client/scripts/ProceduralChibiAvatar.gd` con el shader `client/shaders/chibi_sdf.gdshader`.
  - El shader pinta el animal entero en un solo rectángulo con campos de distancia: silueta orgánica continua, volumen inflado de vinilo, oclusión de contacto, luz de estudio satinada y antialias a cualquier escala.
  - `animate_walk(delta, velocidad)` aplica el rebote de juguete de cuerda (aplasta y estira, pasos alternos, brazos y orejas con muelle).
  - `emote` añade gestos: ojos de gusto, boca abierta, cabeza, brazos y cola.
  - Los colores van en sRGB y se pasan a lineal si el viewport usa HDR 2D (Forward+), así se ve igual en PC y en móvil.
  - Mira `docs/ui/chibi_vinilo_antes_despues.png` y `docs/ui/chibi_catalogo.png`.
- **Sprites HD:** `godot --path client res://tools/ExportHdSprites.tscn` (con GPU o un servidor X virtual) exporta los 12 animales a 512×512 con su mapa de normales en `client/assets/sprites/hd/`. Son para la tienda de apps, la prensa y como base de arte final; el juego sigue usando el chibi en vivo.
- La corbata del chibi lleva el color de tu rol solo en tu personaje; al final de la partida, todas.
- Los 12 animales son gratis para todos (`starter_skins` en `progression.json`). Cada uno trae su habilidad (ver *Habilidades por animal*).
- **Cosméticos** (`shared/config/cosmetics/cosmetics.json`): ropa (traje o sudadera), gorra, zapatillas y mochila. Es lo único que se compra en la Tienda o se gana en el Executive Pass. Se equipan con `equip_cosmetic` y viajan en `look` dentro del estado público del jugador. Nunca tocan la corbata.
- **Horneado** (`client/scripts/ChibiBaker.gd`): en móviles y web cada chibi se dibuja una vez en una hoja de 25 poses y se pinta como una textura.
  - La hoja sale a 1,75× con mipmaps, en un SubViewport con mundo propio (`own_world_3d`) para no aplicar dos veces el glow del ambiente.
  - Leer una textura es mucho más barato para la GPU que el shader en vivo.
  - Se cambia en Configuración → Calidad de los avatares, o con `CHIBI_BAKE=1/0`. Tu propio animal en la sala va siempre en vivo, para poder poner caras.

**HUD de oficina.** `client/scenes/ui/OfficeHUD.tscn` (en `Main/UI`) se ve solo en la exploración.
- Arriba a la izquierda, el panel **Tareas** muestra tus objetivos secretos con un punto de estado: ámbar el activo, blanco los pendientes, gris los hechos. Solo los ves tú.
- Arriba a la derecha, el **minimapa circular** (`CircularMinimap`) se centra en ti (flecha blanca). Muestra a los demás con el color de su animal y las pistas en las que ves algo.

- **`FloatingProgressBar.tscn`** (`floating_progress_bar.gd`): `Node2D` → `CanvasLayer` (`follow_viewport_enabled`) → `BarAnchor` → `ActionLabel` + `ChannelingBar`. Sigue a la cámara (posición y zoom) sin heredar la escala ni el volteo del personaje. Roja (`#ff334b`) en acciones hostiles (borrar, triturar) y cian (`#00e5ff`) en respaldos. `FloatingProgressBar.attach(personaje, texto, segundos, ya_transcurrido, "delete"|"backup")`. Emite `completed` o `interrupted(motivo)`; con `watch_movement` se interrumpe si el personaje se mueve. En partida la gestiona `ChannelPresenter`: una barra por cada canalización que manda el servidor (las ven todos los cercanos); la del jugador local cancela al moverse y el resultado lo confirma el servidor (`server_finished`).
- **`EvidenceInspectionModal.tscn`** (`evidence_inspection_modal.gd`): `BackgroundDimmer` → `ModalCard` (`DeviceBezelTexture` + panel) → `ModalHeader` / `ContentSlot` / `ActionFooter`. El tipo de pista (`medium` y etiquetas, reglas en `EvidenceFrames`) elige la vista que se inyecta en `ContentSlot`: `TerminalView` (Digital / Crítica), `SmartphoneView` (Digital / Visual, Testimonial), `PaperDocumentView` (Documental / Físico) o `ItemView`. Si existe `res://assets/ui/bezels/bezel_monitor.png` (o `bezel_smartphone.png`, `bezel_paper_clipboard.png`) se usa como bisel; si no, la vista lo dibuja con estilos. Con vista parcial se ve el dispositivo pero no el contenido ("Permiso denegado", "Pantalla bloqueada"). En el footer, `BackupEvidenceBtn` (cian) y `DeleteEvidenceBtn` (rojo) solo aparecen si **tu rol** tiene esa `backup_action` / `deletion_action`; al pulsar, el modal se cierra cuando el servidor acepta y la barra flotante toma el relevo. Para una vista nueva: heredar de `EvidenceFrame` y `EvidenceFrames.register("id", Script, ["palabras"])`.
- **`AssemblyBoardUI.tscn`** (`assembly_board_ui.gd`, mesa de juntas): `TopBar` con `AssemblyTimerLabel` (ámbar, rojo en los últimos 30 s) y "ASAMBLEA EXTRAORDINARIA DEL DIRECTORIO"; `SeatingOrbitContainer` con un asiento por jugador en arco alrededor de la mesa (tú abajo a la izquierda); `EvidenceDropZone` en el centro, donde se sueltan las cartas y se ve la última prueba en su vista, con las demás en huecos `SlotEvidence_N` y `ExposeActionBtn`; `BottomDrawer` con tu mano (`HandCardsHBox`, clic = seleccionar, doble clic = abrir en el modal, arrastrar = exponer) y `VotingActionPanel` (`TargetVoteSelector`, `AccuseButton` "Confirmar Voto de Expulsión", `SkipVoteButton` "Abstenerse", recuento si el escenario tiene `public_tally`). Los asientos dicen quién ya votó y cuántas pruebas expuso, **no** su rol ni a quién votó; el `AccusationPinMarker` aparece al resolver, sobre quien resultó acusado.
- **`TrialAssemblyManager`** (lógica de la mesa, sin dibujo): `select`, `present_selected`, `can_drop`/`drop`, señal `evidence_presented(evidence_data, player_id)`, `accuse(option_id)` (pulsar tu opción otra vez retira el voto), `accuse_role(role_id)`, `votes_by_option()` y `votes_by_role()`. Valida fase, cupo y propiedad antes de enviar; el servidor vuelve a validar.

### Cómo se conecta con el juego

- **E sobre una pista**: `InteractableEvidence.interact()` → `EventBus.evidence_inspect_requested` → `EvidenceInspectionModal.open()` → `setup_inspection(contenido, rol_local)`. `setup_inspection(clue_data, player_role)` también acepta una pista tal cual viene en el JSON del caso (`clues_and_evidence[]`): los botones salen de `deletion_action` / `backup_action` según `authorized_roles`. En partida, las acciones ya llegan filtradas por el servidor, que vuelve a validar al pulsar.
- **Barra y movimiento**: al aceptar la acción, `ChannelPresenter` instancia la `FloatingProgressBar` sobre el personaje con su `channeling_time_seconds`. Si el jugador pulsa una tecla de movimiento (`Player.MOVE_ACTIONS`) antes de terminar, se llama a `cancel_channeling()` y se envía `channel_cancel` al servidor; además el servidor corta la acción si la posición cambia más de 6 px.
- **Cambio de fase**: `PhaseViewController` escucha la fase del servidor. En debate y votación oculta y pausa el mapa (nadie se mueve), cierra el modal y abre `AssemblyBoardUI`; en investigación vuelve a la exploración; en resultados cierra la mesa.
- **Exponer**: la mesa emite `evidence_presented(evidence_data, player_id)` al soltar una carta o pulsar "Colocar Prueba en la Mesa"; `Main.gd` la conecta a `TrialAssemblyManager.present`, que la envía al servidor. Cuando el servidor la pone en la mesa, `TrialAssemblyManager.evidence_presented` hace que todos la vean en el centro.

## Habilidades por animal

Cada animal tiene una pasiva y una activa (tecla Q o botón abajo a la derecha, solo en la investigación). Están en `shared/config/abilities/abilities.json`, con una copia en `client/data/abilities/`. La tabla completa y las reglas de diseño están en `ROADMAP_EXPANSION.md`.

- **Servidor:** `server/src/domain/abilities/` (`AbilityCatalog` valida el JSON y `AbilitySystem` aplica usos, enfriamientos y efectos). `Room` atiende `use_ability`, y `StateProjector` decide quién ve cada barra de acción.
- **Cliente:** `client/scripts/AnimalAbilities.gd` (autoload `Abilities`) tiene el diccionario y emite las señales del HUD. `AbilityButton` es el botón con la recarga y `ScentMarkers` dibuja los escondites del olfato.
- **Roles:** ninguna habilidad revela roles. El animal se elige antes del reparto y las activas secretas solo las sabe quien las usa.
- **Pruebas:** `server/test/abilities.test.ts` y `client/tests/AbilitiesTest.tscn`.

## Menú: botones, sala y precios

- **Botones:**
  - **JUGAR** y **Partida rápida** envían `queue_match`.
  - **Crear sala privada** envía `create_room` (`Protocol.CREATE_PRIVATE_ROOM`).
  - **Unirse** envía `join_room`.
  - En la sala, **INICIAR** marca "listo".
  - Sin conexión, cada botón conecta primero y, si no puede, lo explica.
- **Sala** (`LobbyStage.gd`): el sofá es bajo y está al fondo, sin tapar el ventanal, el tablero ni el lema. Asientos, pufs y mesa van ordenados por Y.
- **Precios** (`client/data/store/store_prices.json`, `StorePrices.gd`):
  - Precio base en USD y precio local en COP para la región `es_CO`. Por ejemplo, 4,99 USD se muestra como $19.900 COP.
  - Solo se muestran: el botón dice "Próximamente".
  - Para cobrar en Android hará falta integrar Google Play Billing, con los precios dados de alta en Play Console. Lo mismo para la App Store en iOS.

## Mascota del lobby (Alter Ego)

Tu animal es también tu mascota en la sala de espera.

- **Barras:**
  - **Hambre** e **Hidratación** bajan con el tiempo, también con el juego cerrado: 12 h y 8 h de llena a vacía.
  - Se rellenan con los botones de su comida (según la especie: bambú para el panda, pescado para el gato, zanahoria para el conejo...) y de agua. Todo es gratis y no afecta a la partida.
  - Con menos del 30 %, la barra parpadea y la mascota piensa en lo que le falta.
- **Gestos:** un toque o clic sobre tu animal hace su reacción propia (el panda da una voltereta, el búho gira la cabeza...). Arrastrar por encima es una caricia: cierra los ojos de gusto y salen corazones.
- **Sonidos:** 27 WAV en `client/assets/audio/pets/`.
  - Los sintetiza `python3 client/tools/gen_pet_sfx.py` (solo Python 3, sin librerías). Son obra propia, sin grabaciones de terceros; ver `LICENCIA.md` en esa carpeta.
  - Para usar grabaciones reales, deja un WAV con el mismo nombre (con licencia que lo permita, por ejemplo CC0) y apunta su origen.
  - El volumen se ajusta en Configuración.
- **Archivos y pruebas:**
  - Código: `client/scripts/pet/`. Datos: `client/data/pets/pets.json`.
  - Se guarda por perfil en `user://pet.cfg`, en el dispositivo.
  - Pruebas: `client/tests/PetCareTest.tscn` y `PetLobbyTest.tscn`.

## Casos en formato libre

`scenarios/caso_fraude_tech_startup.json` se carga tal cual, en el servidor (`SCENARIO=../scenarios/caso_fraude_tech_startup.json`) y en Godot (`scenario_id = "caso_fraude_tech_startup"`). Al cargarlo se normaliza:

| Original | Se convierte en |
|---|---|
| `case_id` | `scenario_id` (`case_002_tech_fraud`) |
| `individual_objectives` | objetivos secretos narrativos |
| `alignment` ("Culpable / Encubridor") | equipo (`culpable`); los culpables alimentan el final por defecto |
| `clues_and_evidence[].room` | posición: una celda por sala de `setting.rooms` (provisional) |
| `type` ("Digital / Visual") | `photo` / `item` / `audio` / `text` + etiquetas (`digital`, `visual`) |
| `can_be_pocketed`, `evidence_weight` | `pocketable`, `weight` |
| `type` (de nuevo) | `medium` (`digital/critica`): el marco del visor |
| `backup_action` | `benefits` + acción `backup` (nombre y `channeling_time_seconds`) |
| `deletion_action` | `harms` + acción `delete` (nombre y `channeling_time_seconds`) |
| personajes | una opción de voto "Acusar a <personaje>" por rol, con recuento público |
| reglas de la confrontación ("hasta 2 evidencias"), duraciones | `max_presented_per_player`, duración de fases |

Lo que es texto narrativo (`victory_resolution`, habilidades, minijuegos, sabotajes) se ignora con un aviso en consola. `player_count.max` se ajusta al número de roles. `shared/config/scenarios/nexuscore_fraude.json` es la versión ajustada a mano del mismo caso, con finales que siguen `victory_resolution`.

## Ejecutar

```bash
# Servidor
cd server
npm install
npm test          # compila y pasa los tests
npm start         # ws://localhost:7777  (PORT, ROLE_SET o SCENARIO por variable de entorno)
SCENARIO=nexuscore_fraude npm start
SCENARIO=../scenarios/caso_fraude_tech_startup.json npm start   # caso en formato libre

# Cliente
./tools/sync-config.sh
# Abrir client/ con Godot 4.3+ y ejecutar. En Main: scenario_id, player_name y room_code.
# Hacen falta minPlayers clientes con el mismo código de sala para empezar.
# Por defecto el cliente va al servidor de producción (wss://bajo-sospecha.onrender.com).
# Para probar con el servidor local:
godot --path client -- --local                       # o --server=ws://localhost:7777
SERVER_URL=local godot --path client                 # lo mismo con variable de entorno

# Pruebas del cliente (sin ventana)
godot --headless --path client res://tests/PetLobbyTest.tscn
```

**Servidor en Render.**
- **Configuración del servicio:**
  - El directorio raíz es la raíz del repositorio, porque el servidor usa `../shared`.
  - Build: `cd server && npm install && npm run build`. Start: `cd server && npm start`.
- **Puerto y salud:**
  - El servidor escucha en `PORT` (Render lo pone solo).
  - Responde 200 en `/health`: ponlo como *Health Check Path*.
  - El TLS (`wss://`) lo pone Render.
- **Plan gratuito:**
  - El servidor se duerme sin uso y la primera conexión tarda hasta un minuto. El cliente espera 75 s y avisa.
  - El disco no es persistente: los perfiles de `server/data/profiles.json` se pierden al reiniciar.
- **Variables opcionales:** `SCENARIO` y `ROLE_SET`.
- **Android:** la exportación necesita el permiso INTERNET.

## Pendiente / siguientes pasos

- Escena de mapa con `Interactable`s colocados y escena de jugador.
- Mecánicas del caso aún sin modelar: habilidades de rol, minijuegos, sabotajes, negociación/soborno.
- Autenticación y reconexión con token.
- Intent `resync` ante huecos de versión.
- Arte: los marcos y barras están hechos con estilos de Godot, sin texturas.
- Mascota: guardar las barras en el servidor (hoy van en el dispositivo) y, si se quiere, cambiar los sonidos sintetizados por grabaciones con licencia CC0.
- Pagos reales: integrar Google Play Billing (y App Store) antes de activar la compra de Créditos Nexus.
