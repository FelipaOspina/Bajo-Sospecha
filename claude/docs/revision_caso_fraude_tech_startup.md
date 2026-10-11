# Revisión: caso_fraude_tech_startup.json

Copia sin cambios en `juego-de-roles/scenarios/caso_fraude_tech_startup.json` (mismo sha256 que el original).

## Resumen del caso
**NexusCore AI, piso 14.** Noche de auditoría antes de una Serie B de 15M; alguien drenó 1,8M a una billetera fría. 4–6 jugadores, dificultad Hard, 3 rondas (exploración 180 s + juicio 120 s).

### Roles y objetivos
| Rol | Bando | Objetivos | Gana si |
|---|---|---|---|
| CEO | Culpable | Purgar los logs del servidor; destruir el contrato fantasma; que el Inversor culpe al CTO | Logs purgados **o** CTO condenado por mayoría |
| CTO | Inocente | Sacar copia forense de los logs; probar que la IP salió del despacho del CEO; no ser votado | Presenta ≥2 evidencias digitales contra el CEO |
| Inversor | Juez | Identificar al ladrón; recuperar el pendrive; no acusar al inocente | Vota al CEO **y** retiene el Pendrive o el Contrato |
| Filtrador (Lead Dev) | Mercenario | Conseguir pendrive o capturas; negociar con Inversor o chantajear al CEO; salir impune | Llega al final con ≥2 evidencias críticas y pacta con el ganador, **o** filtra y gana solo |

Habilidades: CEO expulsa de una sala 45 s (cd 90 s); CTO minijuegos x2 de rápido; Inversor convoca juicio de emergencia (1 uso); Filtrador soborno/amenaza (cd 120 s).

### Pistas
| id | Sala | Tipo | Peso | Se guarda | La puede borrar | Respaldo |
|---|---|---|---|---|---|---|
| CLUE_SERVER_LOGS | Sala de Servidores | Digital / Crítica | 3 | no | CEO (10 s) | CTO, Filtrador (6 s) |
| CLUE_UNLOCKED_LAPTOP | Despacho del CEO | Digital / Visual | 2 | no | CEO (4 s) | CTO, Inversor, Filtrador (3 s) |
| CLUE_TORN_CONTRACT | Archivo y Basura | Documental / Físico | 2 | sí | CEO (5 s) | ninguno |
| CLUE_SLACK_MESSAGE | Open Space | Digital / Testimonial | 1 | no | CEO (3 s) | Filtrador, CTO, Inversor (2 s) |
| CLUE_ENCRYPTED_PENDRIVE | Cafetería | Físico / Criptográfico | 3 | sí | nadie | ninguno |

Además: 2 sabotajes (alarma DDoS en servidores, caída de Wi-Fi en cafetería).

## Campos que no encajan con el formato pedido
Formato esperado: `scenario_id`, `title`, `roles[].secret_objectives`, `evidence_spawns[]` con `id, name, description, type, posición, rol beneficiado/perjudicado`.

| Esperado | En el archivo | Arreglo sugerido |
|---|---|---|
| `scenario_id` | `case_id` (`CASE-002-TECH-FRAUD`) | Renombrar |
| `title` | `title` | OK |
| `roles[].secret_objectives` | `roles[].individual_objectives` | Renombrar. Los roles usan `role_id` (no `id`) |
| `evidence_spawns` | `clues_and_evidence` | Renombrar |
| `id`, `name`, `description` | presentes | OK |
| `type` | texto libre compuesto (`"Digital / Crítica"`) | Pasar a un enum (`digital`, `documental`, `fisico`…) y llevar "Crítica" a otro campo |
| posición | solo `room` como nombre de sala, sin coordenadas | Añadir `position {x,y}` o un `spawn_point` y usar ids de sala en vez de nombres |
| rol beneficiado / perjudicado | **no existe**; solo implícito en `deletion_action.authorized_roles` y `backup_action.authorized_roles` | Añadir p. ej. `harms_role: ROLE_CEO` y `benefits_roles: [...]`. Todas las pistas perjudican al CEO |

### Otras inconsistencias
- `player_count.max` es 6 pero solo hay 4 roles: con 5–6 jugadores faltan roles (o un rol genérico).
- La condición de victoria del CEO difiere entre `roles` ("logs purgados **o** CTO condenado") y `victory_resolution` ("CTO despedido **o** logs **y** contrato destruidos").
- `victory_resolution` del CTO exige el dump de logs **y** la foto de la laptop; su `win_condition` pide "≥2 evidencias digitales" cualesquiera.
- El sabotaje `SABOTAGE_COFFEE_SPILL` se llama "Corte de Red Local (Wi-Fi Caído)": id y nombre no coinciden.
- Las reglas hablan de "los conspiradores" en plural, pero solo el CEO es culpable.
- `$schema` apunta al meta-esquema genérico de JSON Schema, no a un esquema del juego.
- Campos extra que el formato no contempla (no son errores, pero el ScenarioManager tendría que ignorarlos o soportarlos): `setting`, `hidden_ability`, `starting_knowledge`, `win_condition`, `interaction_requirements`, `evidence_weight`, `sabotage_events`, `turn_and_phase_flow`.
