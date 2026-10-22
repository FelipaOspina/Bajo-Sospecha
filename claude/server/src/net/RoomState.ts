import type { BodyView, GhostTaskView, PlayerId, RoomPhase, Vec2 } from '../../../shared/protocol/protocol.js';

export interface PlayerRecord {
  id: PlayerId;
  name: string;
  position: Vec2;
  connected: boolean;
  ready: boolean;
  alive: boolean;
  lastSeq: number;
  lastMoveAt: number;
  skinId?: string;
  /** Skins que puede llevar (las desbloqueadas de su perfil); sin perfil, todas. */
  ownedSkins?: string[];
  /** Cosméticos puestos (ids de shared/config/cosmetics); públicos y sin efecto en el juego. */
  look?: Record<string, string>;
  // ───── Silenciar, noqueo y fantasmas ─────
  /** Fuera de la partida (2.º silencio o expulsado). alive pasa a false. */
  ghost: boolean;
  /** Noqueado hasta esta hora (1.er silencio); null si está en pie. */
  knockedUntil: number | null;
  /** Ya le noquearon: no puede presentar pruebas. */
  wasKnocked: boolean;
  /** Veces que le han silenciado (1 = noqueo, 2 = fantasma). */
  timesSilenced: number;
  /** Cooldown de silence (sin contar los primeros 60 s de la investigación). */
  silenceReadyAt: number;
  escort: { readyAt: number; protecting: PlayerId | null; until: number | null };
  ghostPingReadyAt: number;
  /** Ya usó su botón de emergencia (call_meeting) en esta partida. */
  meetingUsed: boolean;
  ghostTasks: GhostTaskView[];
  /** Misión fantasma en curso. */
  ghostChannel: { taskId: string; label: string; startedAt: number; durationMs: number; origin: Vec2 } | null;
  /** Dónde le vieron por última vez los vivos (los fantasmas se proyectan quietos ahí). */
  lastSeenPosition: Vec2;
  /** Asesinos (y sus compañeros) de los que fue testigo: motivo para silenciarle. */
  witnessed: Set<PlayerId>;
}

/** Cuerpo en el suelo (estado crudo). */
export type BodyRecord = BodyView;

/** Asamblea de emergencia (estado crudo; StateProjector la filtra por receptor). */
export interface EmergencyRecord {
  calledBy: PlayerId;
  bodyId: string | null;
  votes: Map<PlayerId, PlayerId | 'skip'>;
  endsAt: number;
  remaining: number;
  result: { expelled: PlayerId | null; tally: Record<string, number> } | null;
}

/** Estado inicial de los campos de silencio/fantasma de un jugador nuevo. */
export function freshSocialFields(position: Vec2): Pick<PlayerRecord,
  'ghost' | 'knockedUntil' | 'wasKnocked' | 'timesSilenced' | 'silenceReadyAt' | 'escort' | 'ghostPingReadyAt'
  | 'meetingUsed' | 'ghostTasks' | 'ghostChannel' | 'lastSeenPosition' | 'witnessed'> {
  return {
    ghost: false, knockedUntil: null, wasKnocked: false, timesSilenced: 0, silenceReadyAt: 0,
    escort: { readyAt: 0, protecting: null, until: null }, ghostPingReadyAt: 0, meetingUsed: false, ghostTasks: [], ghostChannel: null,
    lastSeenPosition: { ...position }, witnessed: new Set(),
  };
}

export type RoomVisibility = 'private' | 'public';

/**
 * Estado autoritativo "crudo" de la sala (sin filtrar). Nunca se envía tal cual:
 * StateProjector produce una vista por jugador.
 */
export class RoomState {
  readonly players = new Map<PlayerId, PlayerRecord>();
  phase: RoomPhase = 'lobby';
  phaseEndsAt: number | null = null;
  /** Código de la sala (6 caracteres en las nuevas). */
  code = '';
  visibility: RoomVisibility = 'private';
  /** Cuenta atrás del lobby (salas públicas): hora a la que arranca sola. */
  startsAt: number | null = null;
  /** Cuerpos en el suelo. */
  bodies: BodyRecord[] = [];
  /** Asamblea en curso (fase 'emergency'). */
  emergency: EmergencyRecord | null = null;
  /** Emergencias abiertas en la partida. */
  emergenciesHeld = 0;
  /** Cuándo empezó la investigación (para el "aún no" de los primeros 60 s). */
  investigationStartedAt: number | null = null;
  /** Se incrementa con cada cambio relevante; los deltas van de versión en versión. */
  version = 0;

  bump() { return ++this.version; }
}
