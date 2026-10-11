import type { PlayerId, RoomPhase, Vec2 } from '../../../shared/protocol/protocol.js';

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
  /** Se incrementa con cada cambio relevante; los deltas van de versión en versión. */
  version = 0;

  bump() { return ++this.version; }
}
