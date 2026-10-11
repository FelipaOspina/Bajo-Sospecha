import type { PlayerId, RoomPhase, Vec2 } from '../../../../shared/protocol/protocol.js';

export type { PlayerId, RoomPhase, Vec2 };

/** Plantilla de una prueba (dato de diseño, inmutable). */
export interface EvidenceDefinition {
  id: string;
  name: string;
  description: string;
  tags: string[];
  /** Huecos de inventario que ocupa. */
  weight: number;
  /** false = solo se examina en el sitio (una pantalla, un servidor). Por defecto true. */
  pocketable?: boolean;
  /** Aspecto exterior (pantalla, papel...), público incluso con visibilidad parcial. */
  medium?: string;
  /** Material para el visor del cliente (texto, ruta de imagen o audio). */
  content?: Record<string, unknown>;
  /** Permisos especiales. Sin access = cualquiera que la perciba puede verla y recogerla. */
  access?: EvidenceAccess;
  /** Acciones con tiempo de canalización (borrar, sacar copia) y quién puede hacerlas. */
  actions?: EvidenceActionConfig[];
}

export type EvidenceActionKind = 'delete' | 'backup';

export interface EvidenceActionConfig {
  kind: EvidenceActionKind;
  /** Texto de la acción, p. ej. "Purgar partición /var/log/audit.log". */
  label: string;
  /** Roles autorizados. */
  roles: string[];
  /** Tiempo de canalización; moverse lo interrumpe. */
  seconds: number;
}

/** Requisito: hay que cumplir TODO lo que se indique (rol entre `roles` Y tener cada ítem de `items`). */
export interface AccessRequirement {
  /** Ids de rol permitidos (basta con tener uno de ellos). */
  roles?: string[];
  /** Ids de definición de prueba que hay que llevar en el inventario (llaves, tarjetas...). */
  items?: string[];
}

export interface EvidenceAccess {
  view?: AccessRequirement;
  collect?: AccessRequirement;
}

/** Dónde está una prueba concreta ahora mismo. */
export type EvidenceLocation =
  | { kind: 'world'; interactableId: string }
  | { kind: 'inventory'; playerId: PlayerId }
  | { kind: 'destroyed'; by: PlayerId };

/** Copia concreta de una prueba dentro de una partida. */
export interface EvidenceInstance {
  instanceId: string;
  definitionId: string;
  location: EvidenceLocation;
  /** Rastro de quién la ha tenido: útil para deducción y para la repetición. */
  history: { playerId: PlayerId; action: 'collected' | 'dropped' | 'destroyed' | 'presented' | 'copied'; at: number }[];
  /** Si es una copia (dump, foto), la instancia original. */
  copyOf?: string;
}

export interface InteractableConfig {
  id: string;
  type: string;
  position: Vec2;
  radius: number;
  [extra: string]: unknown;
}

export interface EvidenceMapConfig {
  mapId: string;
  evidence: EvidenceDefinition[];
  interactables: InteractableConfig[];
}

/** Eventos de dominio que publica EvidenceSystem. */
export interface EvidenceEvents {
  'evidence.collected': { playerId: PlayerId; interactableId: string; instanceId: string };
  'evidence.dropped': { playerId: PlayerId; interactableId: string; instanceId: string };
  'evidence.destroyed': { playerId: PlayerId; instanceId: string };
  'evidence.presented': { playerId: PlayerId; instanceId: string };
  'evidence.copied': { playerId: PlayerId; instanceId: string; originalId: string };
}

/** Lo que EvidenceSystem necesita saber del estado de la sala, y nada más. */
export interface IWorldQuery {
  positionOf(playerId: PlayerId): Vec2 | undefined;
  isAlive(playerId: PlayerId): boolean;
  currentPhase(): RoomPhase;
  now(): number;
}
