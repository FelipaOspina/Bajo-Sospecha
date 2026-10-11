import type { PlayerId, VisibilityLevel } from '../../../../shared/protocol/protocol.js';

export type { PlayerId, VisibilityLevel };

export const VISIBILITY_ORDER: Record<VisibilityLevel, number> = { hidden: 0, partial: 1, full: 2 };

export interface VisibilityRule {
  /** La regla aplica si la prueba tiene AL MENOS una de estas etiquetas. */
  tags: string[];
  level: VisibilityLevel;
}

export interface ObjectiveDefinition {
  id: string;
  type: string;
  description: string;
  params?: Record<string, unknown>;
}

export interface ModifierDefinition {
  id: string;
  params?: Record<string, unknown>;
}

export interface RoleDefinition {
  id: string;
  name: string;
  team: string;
  description: string;
  count: { min: number; max: number };
  /** Peso para rellenar plazas libres tras cubrir los mínimos. 0 = solo por mínimo. */
  weight?: number;
  knowsTeammates?: boolean;
  visibility: { default: VisibilityLevel; rules: VisibilityRule[] };
  objectives: ObjectiveDefinition[];
  modifiers: ModifierDefinition[];
}

export interface RoleSetConfig {
  id: string;
  name: string;
  version: number;
  minPlayers: number;
  maxPlayers: number;
  roles: RoleDefinition[];
}

/** Estadísticas efectivas de un jugador tras aplicar los modificadores de su rol. */
export interface PlayerStats {
  interactRange: number;
  inventoryCapacity: number;
  /** Etiquetas cuya visibilidad se eleva a 'full' (p. ej. ojo forense). */
  visibilityUpgrades: Set<string>;
  /** Etiquetas de pruebas que el jugador puede destruir. */
  destroyableTags: Set<string>;
}

export const DEFAULT_STATS = (): PlayerStats => ({
  interactRange: 64,
  inventoryCapacity: 5,
  visibilityUpgrades: new Set(),
  destroyableTags: new Set(),
});

/**
 * Consulta de solo lectura sobre roles. Es lo único que otros sistemas
 * (EvidenceSystem, StateSync) conocen del RoleManager: Segregación de Interfaces.
 */
export interface IRoleQuery {
  getRoleOf(playerId: PlayerId): RoleDefinition | undefined;
  getStats(playerId: PlayerId): PlayerStats;
  visibilityFor(playerId: PlayerId, evidenceTags: readonly string[]): VisibilityLevel;
  knownTeammates(playerId: PlayerId): PlayerId[];
}
