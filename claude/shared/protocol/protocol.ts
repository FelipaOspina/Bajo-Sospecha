/**
 * Contrato de red compartido entre servidor (TypeScript) y cliente (Godot).
 * El cliente GDScript replica estas constantes en client/scripts/net/Protocol.gd.
 *
 * Reglas:
 *  - El cliente solo envía INTENCIONES (ClientIntent). Nunca estado.
 *  - El servidor es la única fuente de verdad y responde con snapshots,
 *    deltas versionados y eventos ya filtrados por jugador.
 */

export const PROTOCOL_VERSION = 1;

export type PlayerId = string;
export type Vec2 = { x: number; y: number };
export type VisibilityLevel = 'hidden' | 'partial' | 'full';
/** emergency: asamblea de emergencia tras reportar un cuerpo (pausa la investigación). */
export type RoomPhase = 'lobby' | 'briefing' | 'investigation' | 'emergency' | 'discussion' | 'voting' | 'results';

// ───────────── Cliente → Servidor ─────────────

interface IntentBase { seq: number } // número de secuencia para acks / reconciliación

export type ClientIntent =
  /** roomCode: sala a la que unirse (se crea si no existe). Sin código, la sala por defecto. */
  | (IntentBase & { t: 'join'; name: string; protocol: number; roomCode?: string })
  | (IntentBase & { t: 'ready'; ready: boolean })
  // ── Menú, salas y matchmaking (antes de entrar o entre partidas) ──
  /** Identifica el perfil (id guardado en el cliente; sin él o si no existe se crea uno). Responde 'profile'. */
  | (IntentBase & { t: 'hello'; name: string; protocol: number; profileId?: string })
  /** Sala privada nueva con código de 6 caracteres; entra en ella (llega 'welcome'). */
  | (IntentBase & { t: 'create_room'; name?: string; protocol?: number })
  /** Entrar en una sala privada por su código. Rechazos: room_not_found, room_full, game_started. */
  | (IntentBase & { t: 'join_room'; roomCode: string; name?: string; protocol?: number })
  /** Cola pública: con MATCH_MAX en cola arranca ya; con MATCH_MIN empieza una cuenta atrás de
   *  MATCH_WAIT_MS y al vencer arranca con los que haya. Llega 'queued'. */
  | (IntentBase & { t: 'queue_match'; name?: string; protocol?: number })
  | (IntentBase & { t: 'leave_queue' })
  /** Salir de la sala actual (vuelta al menú) sin cerrar la conexión. */
  | (IntentBase & { t: 'leave_room' })
  /** Chat de la sala: lobby, debate (discussion/voting) y asamblea de emergencia. Llega a todos como
   *  evento 'chat'. Rechazos: wrong_phase, empty_message, not_alive (fantasmas fuera del lobby). */
  | (IntentBase & { t: 'chat'; text: string })
  // ── Perfil, Executive Pass y tienda (monedas del juego; sin pagos reales) ──
  | (IntentBase & { t: 'claim_pass_reward'; level: number; track: 'free' | 'premium' })
  /** Antiguo: los animales ya son gratis para todos (responde already_owned). */
  | (IntentBase & { t: 'buy_skin'; skinId: string })
  /** Comprar un cosmético (ropa, gorra, zapatillas, mochila) con monedas del juego.
   *  Rechazos: unknown_cosmetic, already_owned, not_for_sale, not_enough_coins/credits. */
  | (IntentBase & { t: 'buy_cosmetic'; cosmeticId: string })
  /** Ponerse un cosmético propio en su hueco (null = quitárselo). Rechazos: bad_slot,
   *  unknown_cosmetic, wrong_slot, cosmetic_locked. En el lobby los demás lo ven al momento. */
  | (IntentBase & { t: 'equip_cosmetic'; slot: 'outfit' | 'hat' | 'shoes' | 'bag'; cosmeticId: string | null })
  | (IntentBase & { t: 'buy_premium_pass' })
  /** Tutorial local «Primer día en NexusCore» terminado: su recompensa (XP y monedas de
   *  detective_path.tutorial_reward), una sola vez por perfil. Responde 'rewards' (source
   *  'tutorial') y 'profile'. Rechazos: no_profile, already_claimed. */
  | (IntentBase & { t: 'claim_tutorial_reward' })
  /** Skin preferida del perfil (la que se intenta llevar al entrar en una sala). */
  | (IntentBase & { t: 'select_skin'; skinId: string })
  /** Elegir skin de animal en el lobby (rechazada si otro jugador ya la lleva). */
  | (IntentBase & { t: 'choose_skin'; skinId: string })
  | (IntentBase & { t: 'move'; position: Vec2 })
  /** Recoger. Con evidenceInstanceId se elige qué pieza de un contenedor; sin él, la primera visible. */
  | (IntentBase & { t: 'interact'; interactableId: string; evidenceInstanceId?: string })
  /** Empezar una acción canalizada (borrar, sacar copia). Moverse la interrumpe. */
  | (IntentBase & { t: 'channel_start'; evidenceInstanceId: string; action: 'delete' | 'backup' })
  | (IntentBase & { t: 'channel_cancel' })
  | (IntentBase & { t: 'drop_evidence'; evidenceInstanceId: string })
  | (IntentBase & { t: 'destroy_evidence'; evidenceInstanceId: string })
  /** Rechazo 'knocked_before' si te noquearon en la partida. */
  | (IntentBase & { t: 'present_evidence'; evidenceInstanceId: string })
  /** Botón de emergencia (solo en la investigación): abre la asamblea de emergencia (fase 'emergency',
   *  calledBy = quien la convoca, bodyId null). Una vez por jugador y partida; cuenta para el máximo
   *  de emergencias. Rechazos: wrong_phase, not_alive, knocked, meeting_used, no_meetings_left. */
  | (IntentBase & { t: 'call_meeting' })
  /** Juicio final: pasar de la fase de debate a la fase de votación. Rechazos: wrong_phase, not_alive. */
  | (IntentBase & { t: 'skip_to_voting' })
  /** Usar la habilidad activa de tu animal (solo en la investigación). Rechazos: wrong_phase,
   *  not_alive, no_ability, on_cooldown. Llega el evento 'ability_used'. */
  | (IntentBase & { t: 'use_ability' })
  /** Silenciar a un jugador cercano (solo roles con power "silence"). La 1.ª vez queda noqueado 30 s;
   *  la 2.ª, fantasma. Rechazos: wrong_phase, not_alive, knocked, no_power, too_early, on_cooldown,
   *  target_not_alive (también si ya está noqueado), too_far (>90 px), no_motive (sin móvil:
   *  ver you.motiveTargets), target_protected (escolta: la consume y pone el cooldown). */
  | (IntentBase & { t: 'silence'; targetId: PlayerId })
  /** Reportar un cuerpo a ≤160 px: abre la emergencia (máx. 3 por partida; después solo lo retira).
   *  Rechazos: wrong_phase, not_alive, knocked, too_far, unknown_body. */
  | (IntentBase & { t: 'report_body'; bodyId: string })
  /** Jefe de Seguridad: protege 45 s a un jugador vivo a ≤160 px; cooldown 90 s.
   *  Rechazos: wrong_phase, not_alive, knocked, no_power, on_cooldown, too_far, target_not_alive. */
  | (IntentBase & { t: 'escort'; targetId: PlayerId })
  /** Voto de la emergencia: a un jugador vivo, 'skip' o null (retirar). Solo vivos.
   *  Rechazos: wrong_phase, not_alive, unknown_target. */
  | (IntentBase & { t: 'emergency_vote'; targetId: PlayerId | 'skip' | null })
  /** Solo fantasmas, cada 20 s: marca una posición 6 s para los vivos de su equipo.
   *  Rechazos: not_ghost, on_cooldown, bad_position. */
  | (IntentBase & { t: 'ghost_ping'; position: Vec2 })
  /** Solo fantasmas: misión de 6 s a ≤80 px (moverse la cancela). Al completarla aparece una prueba.
   *  Rechazos: not_ghost, wrong_phase, unknown_task, too_far, already_channeling. */
  | (IntentBase & { t: 'ghost_task'; taskId: string })
  /** Voto a una decisión narrativa del juicio (null = retirar el voto). */
  | (IntentBase & { t: 'vote'; optionId: string | null });

// ───────────── Servidor → Cliente ─────────────

/** Vista de una prueba tal como la ve UN jugador concreto. */
export interface EvidenceView {
  instanceId: string;
  visibility: Exclude<VisibilityLevel, 'hidden'>;
  /** Solo presentes si visibility === 'full'. */
  definitionId?: string;
  name?: string;
  description?: string;
  tags?: string[];
  /** Material para el visor: { text?, image?, audio? }. Solo con 'full'. */
  content?: Record<string, unknown>;
  pocketable?: boolean;
  /** Aspecto exterior ("digital/critica", "documental/fisico", "photo"...). También con 'partial':
   *  se ve que es una pantalla o un papel aunque no se sepa qué dice. */
  medium?: string;
  /** Permiso que le falta al receptor: 'view' = no puede ver detalles, 'collect' = no puede recogerla. */
  locked?: 'view' | 'collect';
  /** Si lo que falta es un objeto (llave), sus nombres. Nunca se revela qué ROL hace falta. */
  requiredItems?: string[];
  /** Acciones canalizadas que EL RECEPTOR puede hacer sobre ella (según su rol). */
  actions?: { kind: 'delete' | 'backup'; label: string; seconds: number }[];
  /** Es una copia (dump, foto) de una pista fija. */
  isCopy?: boolean;
}

/** Acción canalizada en curso, visible para el propio jugador y los cercanos. */
export interface ChannelView {
  /** ghost_task: misión de fantasma (solo la ven los fantasmas). */
  kind: 'delete' | 'backup' | 'ghost_task';
  label: string;
  /** Hora del servidor (ms). El cliente la convierte con el serverTime del welcome. */
  startedAt: number;
  durationMs: number;
}

export interface PublicPlayerState {
  id: PlayerId;
  name: string;
  position: Vec2;
  connected: boolean;
  ready: boolean;
  alive: boolean;
  inventoryCount: number;
  /** Solo si el receptor es este jugador o está cerca. */
  channel?: ChannelView;
  /** Solo se envía si el receptor puede conocer ese rol (él mismo o compañero visible). */
  roleId?: string;
  /** Skin de animal (cosmética y pública; no depende del rol salvo que se active assign_by_role). */
  skinId?: string;
  /** Cosméticos puestos por hueco (outfit, hat, shoes, bag → id de shared/config/cosmetics). */
  look?: Partial<Record<'outfit' | 'hat' | 'shoes' | 'bag', string>>;
  /** Fuera de la partida (silenciado dos veces o expulsado en una emergencia). */
  ghost?: boolean;
  /** Para receptores VIVOS los fantasmas van ocultos (sin posición actualizada): no se dibujan. */
  hidden?: boolean;
  /** Noqueado (1.er silencio): en el suelo hasta knockedUntil (hora del servidor). */
  knocked?: boolean;
  knockedUntil?: number;
}

/** Poderes de rol del receptor (horas del servidor en ms). */
export interface PowersState {
  /** readyAt ya incluye los primeros 60 s de la investigación y el cooldown de 60 s. */
  silence?: { readyAt: number };
  escort?: { readyAt: number; protecting: PlayerId | null; until: number | null };
}

/** A quién tiene MOTIVO para silenciar el receptor (solo se puede silenciar con móvil).
 *  evidence: lleva una prueba que te incrimina; witness: te vio (a ti o a tu cómplice);
 *  backup: sacó copia de una prueba que te incrimina; story: su rol (p. ej. te chantajea). */
export interface MotiveTarget {
  playerId: PlayerId;
  reason: 'evidence' | 'witness' | 'backup' | 'story';
  /** evidence/backup: nombre de la prueba. */
  evidence?: string;
}

/** Misión de fantasma: ir al punto y canalizar 6 s. */
export interface GhostTaskView {
  id: string;
  label: string;
  position: Vec2;
  done: boolean;
}

/** Cuerpo en el suelo. knocked: noqueado (desaparece al levantarse); dead: fantasma. */
export interface BodyView {
  id: string;
  playerId: PlayerId;
  position: Vec2;
  reported: boolean;
  kind: 'knocked' | 'dead';
  /** Solo knocked: hora del servidor a la que se levanta. */
  until?: number;
}

/** Asamblea de emergencia en curso (fase 'emergency'). */
export interface EmergencyState {
  calledBy: PlayerId;
  bodyId: string | null;
  /** Quién ha votado ya (no a quién). */
  voted: PlayerId[];
  myVote: PlayerId | 'skip' | null;
  endsAt: number;
  /** Ms de investigación que quedaban al abrirla (se restauran al volver). */
  remaining: number;
  /** Tras el recuento (se muestra unos segundos antes de volver a la investigación). */
  result: { expelled: PlayerId | null; tally: Record<string, number> } | null;
}

/** Habilidad activa del animal del receptor (shared/config/abilities). Horas del servidor en ms. */
export interface AbilityState {
  id: string;
  /** Cuándo se puede volver a usar (0 = ya). */
  readyAt: number;
  /** Hasta cuándo dura su efecto; null si no hay ninguno en curso. */
  activeUntil: number | null;
  cooldownMs: number;
}

export interface PrivatePlayerState {
  roleId: string;
  team: string;
  objectives: { id: string; description: string; completed: boolean }[];
  inventory: EvidenceView[];
  knownTeammates: PlayerId[];
  /** Habilidad activa de tu animal (sin ella si la skin no tiene). */
  ability?: AbilityState;
  /** Multiplicador de tu velocidad ahora (pasiva + acelerones); el servidor valida con él. */
  speedMultiplier?: number;
  /** Poderes del rol (silence, escort). */
  powers?: PowersState;
  /** Eres un fantasma (te mueves libre, no interactúas ni votas). */
  ghost: boolean;
  /** Fantasmas: cuándo puedes volver a usar ghost_ping. */
  ghostPingReadyAt?: number;
  /** Solo roles con silence: jugadores con motivo (se recalcula en cada proyección). */
  motiveTargets?: MotiveTarget[];
  /** Ya te noquearon una vez: no puedes presentar pruebas en el juicio. */
  wasKnocked?: boolean;
  /** Ya usaste tu botón de emergencia (call_meeting) en esta partida. */
  meetingUsed?: boolean;
  /** Fantasmas: misiones (máx. 6 en total). */
  ghostTasks?: GhostTaskView[];
}

export interface InteractableView {
  id: string;
  type: string;
  position: Vec2;
  radius: number;
  /** Lo que el receptor percibe del contenido (vacío si no ve nada). */
  contents: EvidenceView[];
  /** Contenedor "body": de quién son los objetos caídos y su rótulo ("Objetos caídos de X"). */
  ownerId?: PlayerId;
  label?: string;
}

/** Datos de la sala para la vista de lobby. */
export interface LobbyState {
  code: string;
  /** private: por código; public: creada por el matchmaking (arranca sola). */
  visibility: 'private' | 'public';
  /** Anfitrión (corona): el primero que sigue en la sala. */
  hostId: PlayerId | null;
  minPlayers: number;
  maxPlayers: number;
  /** Hora del servidor (ms) a la que arranca sola; null sin cuenta atrás. */
  startsAt: number | null;
}

export interface RoomSnapshot {
  version: number;
  phase: RoomPhase;
  lobby: LobbyState;
  phaseEndsAt: number | null;
  players: PublicPlayerState[];
  interactables: InteractableView[];
  you: PrivatePlayerState | null;
  trial: TrialState;
  /** Cuerpos en el suelo (noqueados y fantasmas sin reportar/reportados). */
  bodies: BodyView[];
  /** Asamblea de emergencia; null fuera de la fase 'emergency'. */
  emergency: EmergencyState | null;
}

// ───────────── Juicio ─────────────

/** Prueba expuesta en la mesa pública: todos la ven completa. */
export interface DeckCard {
  instanceId: string;
  presentedBy: PlayerId;
  at: number;
  evidence: EvidenceView;
}

/** Decisión narrativa votable ("Acusar a la Esposa", "Encubrir la infidelidad"...). */
export interface VerdictOption {
  id: string;
  label: string;
  description?: string;
  /** Si la opción acusa a un personaje, su rol (para agrupar los votos por rol). */
  accusesRole?: string;
}

export interface Resolution {
  verdict: { optionId: string | null; label: string; tally: Record<string, number>; accused: PlayerId[] };
  endings: { id: string; title: string; description: string }[];
  winners: PlayerId[];
  players: {
    id: PlayerId;
    name: string;
    roleId: string;
    roleName: string;
    team: string;
    won: boolean;
    objectives: { id: string; description: string; completed: boolean }[];
  }[];
  revealedEvidence: string[];
}

export interface TrialState {
  deck: DeckCard[];
  options: VerdictOption[];
  /** Quién ha votado ya (no a qué: el voto es secreto hasta la resolución). */
  voted: PlayerId[];
  myVote: string | null;
  maxPresentedPerPlayer: number;
  /** Votos por opción en vivo; solo si el escenario tiene trial.public_tally. */
  tally?: Record<string, number>;
  resolution: Resolution | null;
}

/** Operación de parche JSON simplificada sobre RoomSnapshot. */
export type PatchOp =
  | { op: 'set'; path: (string | number)[]; value: unknown }
  | { op: 'remove'; path: (string | number)[] };

export type GameEvent =
  | { e: 'player_joined'; playerId: PlayerId; name: string }
  | { e: 'player_left'; playerId: PlayerId }
  | { e: 'phase_changed'; phase: RoomPhase; endsAt: number | null }
  | { e: 'evidence_collected'; by: PlayerId; interactableId: string; evidence?: EvidenceView }
  | { e: 'evidence_dropped'; by: PlayerId; interactableId: string }
  | { e: 'evidence_destroyed'; by: PlayerId }
  | { e: 'evidence_presented'; by: PlayerId; evidence: EvidenceView }
  | { e: 'vote_cast'; by: PlayerId }
  | { e: 'channel_started'; by: PlayerId; channel: ChannelView }
  | { e: 'channel_finished'; by: PlayerId; ok: boolean; reason?: string }
  | { e: 'game_over'; resolution: Resolution }
  | { e: 'chat'; by: PlayerId; name: string; text: string; at: number }
  /** Alguien usó la activa de su animal. Las secretas (sigilo, engaño...) solo le llegan a él;
   *  marks (olfato) solo a quien la usó; affected: a quién alcanzó (rugido, aullido). */
  | { e: 'ability_used'; by: PlayerId; abilityId: string; endsAt: number | null; marks?: string[]; affected?: PlayerId[] }
  /** Solo al asesino (completo) y a la víctima (SIN killer). knocked: noqueo con until; si no, fantasma. */
  | { e: 'silenced'; killer?: PlayerId; victim: PlayerId; at: number; knocked: boolean; until?: number }
  /** Solo a los vivos con línea de vista del asesino (≤900 px, sin muros por medio). */
  | { e: 'witnessed'; killer: PlayerId; victim: PlayerId; at: number }
  | { e: 'body_reported'; by: PlayerId; bodyId: string; victim: PlayerId }
  /** Alguien pulsó el botón de emergencia (call_meeting); a continuación llega phase_changed → emergency. */
  | { e: 'meeting_called'; by: PlayerId }
  | { e: 'emergency_result'; expelled: PlayerId | null; tally: Record<string, number> }
  /** Al asesino, al Jefe de Seguridad y al protegido. */
  | { e: 'escort_blocked'; target: PlayerId }
  /** A los vivos del equipo del fantasma; la marca dura hasta until. */
  | { e: 'ghost_ping'; by: PlayerId; position: Vec2; until: number }
  /** Misión fantasma completada: una pista brilla para los vivos hasta until. */
  | { e: 'ghost_reveal'; interactableId: string; position: Vec2; until: number };

export type ServerMessage =
  | { t: 'welcome'; playerId: PlayerId; protocol: number; roomCode: string; serverTime: number; snapshot: RoomSnapshot }
  | { t: 'snapshot'; snapshot: RoomSnapshot }
  | { t: 'delta'; from: number; to: number; ops: PatchOp[] }
  | { t: 'event'; version: number; event: GameEvent }
  | { t: 'ack'; seq: number }
  | { t: 'rejected'; seq: number; reason: string }
  /** Perfil (nivel, XP, monedas, pase, skins). Tras 'hello' y tras cada cambio. */
  | { t: 'profile'; profile: unknown }
  /** Posición en la cola pública (position 0 = fuera de la cola). matchSize = máximo (MATCH_MAX),
   *  minSize = mínimo (MATCH_MIN), startsAt = hora del servidor a la que arranca (null sin cuenta atrás). */
  | { t: 'queued'; position: number; waiting: number; matchSize: number; minSize: number; startsAt: number | null }
  /** Recompensas de la partida que acaba de terminar (o del tutorial). Privado: solo a su jugador. */
  | { t: 'rewards'; rewards: RewardsView };

/** Reto de la Ruta del Detective cumplido. */
export interface ChallengeRewardView { id: string; text: string; level: number; xp: number; coins: number }

export interface RewardsView {
  /** XP total (partida + retos). */
  xp: number;
  coins: number;
  won: boolean;
  levelsGained: number;
  passLevelsGained: number;
  /** 'match' (fin de partida) o 'tutorial'. */
  source?: 'match' | 'tutorial';
  matchXp?: number;
  levelBefore?: number;
  level?: number;
  challenges?: ChallengeRewardView[];
  /** Recompensas por llegar a niveles de la Ruta (solo monedas y cosméticos). */
  levelRewards?: { level: number; coins?: number; cosmetic?: string }[];
}
